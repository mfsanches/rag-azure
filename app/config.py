"""Settings read from environment variables (set by the infrastructure templates)."""

from __future__ import annotations

import os
from dataclasses import dataclass


def _required(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"missing required environment variable {name}")
    return value


@dataclass(frozen=True)
class Settings:
    openai_endpoint: str
    openai_api_version: str
    chat_small_deployment: str
    chat_large_deployment: str
    embedding_deployment: str
    embedding_dimensions: int
    search_endpoint: str
    search_index: str
    storage_account_url: str
    documents_container: str
    tenant_claim_type: str
    allow_dev_auth: bool
    dev_tenant_id: str | None

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            openai_endpoint=_required("AZURE_OPENAI_ENDPOINT"),
            openai_api_version=os.environ.get("AZURE_OPENAI_API_VERSION", "2024-10-21"),
            chat_small_deployment=_required("CHAT_SMALL_DEPLOYMENT"),
            chat_large_deployment=_required("CHAT_LARGE_DEPLOYMENT"),
            embedding_deployment=_required("EMBEDDING_DEPLOYMENT"),
            embedding_dimensions=int(os.environ.get("EMBEDDING_DIMENSIONS", "1536")),
            search_endpoint=_required("AZURE_SEARCH_ENDPOINT"),
            search_index=os.environ.get("SEARCH_INDEX_NAME", "docs"),
            storage_account_url=os.environ.get("STORAGE_ACCOUNT_URL", ""),
            documents_container=os.environ.get("DOCUMENTS_CONTAINER", "documents"),
            tenant_claim_type=os.environ.get("TENANT_CLAIM_TYPE", "tenant_id"),
            # Local development only: lets you call the API without built-in auth.
            allow_dev_auth=os.environ.get("ALLOW_DEV_AUTH", "false").lower() == "true",
            dev_tenant_id=os.environ.get("DEV_TENANT_ID"),
        )
