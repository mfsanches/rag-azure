"""Pure functions shared by the API and the ingestion job.

Kept free of Azure SDK calls so they can be unit-tested without a cloud account.
"""

from __future__ import annotations

import base64
import json
import re

PUBLIC_TENANT = "public"
_TENANT_ID = re.compile(r"^[A-Za-z0-9_-]{1,64}$")

# Words that usually signal a multi-step question worth the larger model.
_COMPLEX_HINTS = (
    "compare",
    "difference between",
    "why",
    "explain",
    "analy",
    "step by step",
    "summarize",
    "summarise",
    "trade-off",
    "tradeoff",
    "pros and cons",
)


def validate_tenant_id(tenant_id: str) -> str:
    """Reject anything that is not a plain identifier, so it is safe inside an OData filter."""
    if not tenant_id or not _TENANT_ID.match(tenant_id):
        raise ValueError("invalid tenant id")
    return tenant_id


def build_tenant_filter(tenant_id: str) -> str:
    """Search filter that limits retrieval to the caller's tenant plus shared public content.

    The tenant id must come from the authenticated identity, never from the request body
    or from anything the model produced.
    """
    tenant_id = validate_tenant_id(tenant_id)
    return f"tenantId eq '{tenant_id}' or tenantId eq '{PUBLIC_TENANT}'"


def tenant_from_blob_path(path: str) -> str | None:
    """Map a blob path to the tenant that owns it.

    public/<anything>              -> "public"
    tenants/<tenantId>/<anything>  -> "<tenantId>"
    anything else                  -> None (skipped by ingestion, fail closed)
    """
    parts = path.strip("/").split("/")
    if len(parts) >= 2 and parts[0] == PUBLIC_TENANT:
        return PUBLIC_TENANT
    if len(parts) >= 3 and parts[0] == "tenants":
        try:
            return validate_tenant_id(parts[1])
        except ValueError:
            return None
    return None


def tenant_from_principal_header(header_value: str | None, claim_type: str) -> str | None:
    """Read the tenant claim from the X-MS-CLIENT-PRINCIPAL header set by Container Apps built-in auth.

    Container Apps strips this header from incoming requests and sets it only after it has
    validated the caller's token, so the app can trust it when built-in auth is enabled.
    """
    if not header_value:
        return None
    try:
        principal = json.loads(base64.b64decode(header_value))
    except (ValueError, json.JSONDecodeError):
        return None
    for claim in principal.get("claims", []):
        if claim.get("typ") == claim_type and claim.get("val"):
            return claim["val"]
    return None


def choose_model(question: str, small_deployment: str, large_deployment: str) -> str:
    """Route simple lookups to the small model and multi-step questions to the large one.

    A deliberately simple heuristic; replace it with a classifier once you have evaluation data.
    """
    q = question.lower()
    if len(question) > 400 or q.count("?") > 1 or any(hint in q for hint in _COMPLEX_HINTS):
        return large_deployment
    return small_deployment


def chunk_text(text: str, max_chars: int = 2400, overlap: int = 300) -> list[str]:
    """Split text into overlapping chunks of roughly 500-600 tokens, preferring paragraph breaks."""
    if overlap >= max_chars:
        raise ValueError("overlap must be smaller than max_chars")
    text = text.strip()
    if not text:
        return []
    chunks: list[str] = []
    start = 0
    while start < len(text):
        end = min(start + max_chars, len(text))
        if end < len(text):
            # Break at the last paragraph or sentence end inside the window, if there is one.
            window = text[start:end]
            cut = max(window.rfind("\n\n"), window.rfind(". "))
            if cut > max_chars // 2:
                end = start + cut + 1
        chunks.append(text[start:end].strip())
        if end >= len(text):
            break
        start = end - overlap
    return [c for c in chunks if c]


def doc_key(path: str, chunk_index: int) -> str:
    """Stable, Search-safe document key (letters, digits, '-', '_' and '=' only)."""
    raw = f"{path}#{chunk_index}".encode()
    return base64.urlsafe_b64encode(raw).decode()
