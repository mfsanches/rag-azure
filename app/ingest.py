"""Ingestion job: blob storage -> chunks -> embeddings -> Azure AI Search.

Runs as a Container Apps job inside the virtual network, with its own managed identity
(write access to the index), separate from the API identity (read-only).

Blob layout decides ownership:
    public/...                shared content, visible to every tenant
    tenants/<tenantId>/...    visible to that tenant only
Anything else is skipped.

Handles .txt and .md files. For PDFs and Office files, add Azure AI Document Intelligence.
"""

from __future__ import annotations

import logging

from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.indexes.models import (
    HnswAlgorithmConfiguration,
    SearchableField,
    SearchField,
    SearchFieldDataType,
    SearchIndex,
    SemanticConfiguration,
    SemanticField,
    SemanticPrioritizedFields,
    SemanticSearch,
    SimpleField,
    VectorSearch,
    VectorSearchProfile,
)
from azure.storage.blob import ContainerClient
from openai import AzureOpenAI

from config import Settings
from core import chunk_text, doc_key, tenant_from_blob_path

log = logging.getLogger("ingest")
logging.basicConfig(level=logging.INFO)

SUPPORTED = (".txt", ".md")
EMBED_BATCH = 16


def build_index(name: str, dimensions: int) -> SearchIndex:
    return SearchIndex(
        name=name,
        fields=[
            SimpleField(name="id", type=SearchFieldDataType.String, key=True),
            SimpleField(name="tenantId", type=SearchFieldDataType.String, filterable=True),
            SimpleField(name="source", type=SearchFieldDataType.String, filterable=True),
            SimpleField(name="chunk", type=SearchFieldDataType.Int32),
            SearchableField(name="content", type=SearchFieldDataType.String),
            SearchField(
                name="contentVector",
                type=SearchFieldDataType.Collection(SearchFieldDataType.Single),
                searchable=True,
                vector_search_dimensions=dimensions,
                vector_search_profile_name="default",
            ),
        ],
        vector_search=VectorSearch(
            algorithms=[HnswAlgorithmConfiguration(name="hnsw")],
            profiles=[VectorSearchProfile(name="default", algorithm_configuration_name="hnsw")],
        ),
        semantic_search=SemanticSearch(
            configurations=[
                SemanticConfiguration(
                    name="default",
                    prioritized_fields=SemanticPrioritizedFields(content_fields=[SemanticField(field_name="content")]),
                )
            ]
        ),
    )


def main() -> None:
    s = Settings.from_env()
    cred = DefaultAzureCredential()
    aoai = AzureOpenAI(
        azure_endpoint=s.openai_endpoint,
        azure_ad_token_provider=get_bearer_token_provider(cred, "https://cognitiveservices.azure.com/.default"),
        api_version=s.openai_api_version,
    )
    SearchIndexClient(s.search_endpoint, cred).create_or_update_index(build_index(s.search_index, s.embedding_dimensions))
    search = SearchClient(s.search_endpoint, s.search_index, cred)
    container = ContainerClient(account_url=s.storage_account_url, container_name=s.documents_container, credential=cred)

    total = skipped = 0
    for blob in container.list_blobs():
        tenant = tenant_from_blob_path(blob.name)
        if tenant is None or not blob.name.lower().endswith(SUPPORTED):
            skipped += 1
            log.info("skip %s", blob.name)
            continue
        text = container.download_blob(blob.name).readall().decode("utf-8", errors="replace")
        chunks = chunk_text(text)
        docs = []
        for start in range(0, len(chunks), EMBED_BATCH):
            batch = chunks[start : start + EMBED_BATCH]
            vectors = aoai.embeddings.create(
                model=s.embedding_deployment, input=batch, dimensions=s.embedding_dimensions
            ).data
            for offset, (chunk, vec) in enumerate(zip(batch, vectors)):
                i = start + offset
                docs.append(
                    {
                        "id": doc_key(blob.name, i),
                        "tenantId": tenant,
                        "source": blob.name,
                        "chunk": i,
                        "content": chunk,
                        "contentVector": vec.embedding,
                    }
                )
        if docs:
            search.merge_or_upload_documents(docs)
        total += len(docs)
        log.info("indexed %s: %d chunks (tenant=%s)", blob.name, len(docs), tenant)

    log.info("done: %d chunks indexed, %d blobs skipped", total, skipped)


if __name__ == "__main__":
    main()
