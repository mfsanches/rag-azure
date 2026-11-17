import base64
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "app"))

from core import (  # noqa: E402
    build_tenant_filter,
    choose_model,
    chunk_text,
    doc_key,
    tenant_from_blob_path,
    tenant_from_principal_header,
)


def _principal(claims):
    return base64.b64encode(json.dumps({"claims": claims}).encode()).decode()


class TestTenantIsolation:
    def test_filter_includes_tenant_and_public(self):
        assert build_tenant_filter("acme") == "tenantId eq 'acme' or tenantId eq 'public'"

    @pytest.mark.parametrize("bad", ["", "acme' or tenantId ne '", "a b", "x" * 65, "../etc"])
    def test_filter_rejects_injection_and_bad_ids(self, bad):
        with pytest.raises(ValueError):
            build_tenant_filter(bad)

    @pytest.mark.parametrize(
        "path,expected",
        [
            ("public/policies/claims.md", "public"),
            ("tenants/acme/invoices/2026-01.txt", "acme"),
            ("tenants/acme", None),  # no file under the tenant folder
            ("tenants/bad id/file.txt", None),
            ("random/file.txt", None),
            ("file.txt", None),
        ],
    )
    def test_blob_path_ownership_fails_closed(self, path, expected):
        assert tenant_from_blob_path(path) == expected

    def test_principal_header_reads_tenant_claim(self):
        header = _principal([{"typ": "name", "val": "Ana"}, {"typ": "tenant_id", "val": "acme"}])
        assert tenant_from_principal_header(header, "tenant_id") == "acme"

    @pytest.mark.parametrize("header", [None, "", "not-base64!!", _principal([{"typ": "name", "val": "Ana"}])])
    def test_principal_header_missing_or_invalid(self, header):
        assert tenant_from_principal_header(header, "tenant_id") is None


class TestRouting:
    def test_simple_lookup_uses_small_model(self):
        assert choose_model("What is the claims deadline?", "small", "large") == "small"

    @pytest.mark.parametrize(
        "q",
        ["Compare the standard and express plans", "Why was my shipment delayed?", "What is X? And what is Y?", "a" * 401],
    )
    def test_complex_questions_use_large_model(self, q):
        assert choose_model(q, "small", "large") == "large"


class TestChunking:
    def test_empty_text(self):
        assert chunk_text("   ") == []

    def test_short_text_is_one_chunk(self):
        assert chunk_text("hello world") == ["hello world"]

    def test_long_text_overlaps_and_covers_everything(self):
        text = ". ".join(f"Sentence number {i} about logistics" for i in range(400))
        chunks = chunk_text(text, max_chars=1000, overlap=150)
        assert len(chunks) > 1
        assert all(len(c) <= 1000 for c in chunks)
        assert chunks[0][:20] == text[:20]
        assert text.rstrip().endswith(chunks[-1][-20:])

    def test_overlap_must_be_smaller(self):
        with pytest.raises(ValueError):
            chunk_text("abc", max_chars=100, overlap=100)


def test_doc_key_is_stable_and_search_safe():
    key = doc_key("tenants/acme/a b.txt", 3)
    assert key == doc_key("tenants/acme/a b.txt", 3)
    assert set(key) <= set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_=")
