# CLAUDE.md

Guidance for AI coding assistants (and humans) working in this repository.

## What this is

A public, portfolio-quality **reference architecture for secure RAG on Azure**. It is read by
potential clients and engineers, so clarity and correctness matter more than feature count.
The same architecture exists in **Bicep** and **Terraform**, plus a small Python API.

## Layout

- `infra/bicep/` – `main.bicep` orchestrates modules in `modules/`; parameters in `main.bicepparam`.
- `infra/terraform/` – the same resources with the `azurerm` provider (~> 4.x); example values in `terraform.tfvars.example`.
- `app/` – FastAPI service (`main.py`), ingestion job (`ingest.py`), pure logic (`core.py`), settings (`config.py`).
- `tests/` – unit tests for `core.py`; no Azure account needed.
- `docs/decisions.md` – architecture decisions and trade-offs.
- `samples/documents/` – example documents in the folder layout ingestion expects.

## Rules

1. **Keep Bicep and Terraform in parity.** Any resource, setting or role change goes into both,
   with the same names and behavior. Mention any intentional difference in `docs/decisions.md`.
2. **Security invariants. Never weaken these:**
   - No API keys or shared keys: `disableLocalAuth` / `local_auth_enabled = false` on Azure OpenAI and
     AI Search, shared key access off on Storage, registry admin user off. Use managed identity.
   - Data services (OpenAI, Search, Storage, Key Vault) stay private, reached through private endpoints.
     Storage may allow specific IPs only through `allowedIpAddresses` / `allowed_ip_addresses`.
   - The API identity is read-only on the index; only the ingestion identity can write.
   - The tenant used in the search filter comes only from the validated identity
     (`X-MS-CLIENT-PRINCIPAL`), never from the request body or model output, and is validated
     before it enters the filter.
   - Ingestion skips anything outside `public/` and `tenants/<id>/` (fail closed).
3. **Least privilege.** New role assignments get the narrowest built-in role and scope that works.
4. **Pure logic goes in `core.py` with tests.** SDK calls stay in `main.py` / `ingest.py`.
5. **No real data.** Samples, names and numbers are fictional. Never commit secrets, `.tfvars`,
   state files or client information.
6. **Model names and versions change often.** They live only in `main.bicepparam` and
   `terraform.tfvars.example`; don't hard-code them elsewhere.
7. **Document decisions.** A change in architecture or a trade-off gets a short entry in
   `docs/decisions.md`; user-facing changes update `README.md`.

## Checks to run before committing

```bash
# Python
pip install -r app/requirements.txt pytest
pytest -q

# Bicep
az bicep build --file infra/bicep/main.bicep --stdout > /dev/null
az bicep build-params --file infra/bicep/main.bicepparam --stdout > /dev/null
az bicep lint --file infra/bicep/main.bicep

# Terraform
cd infra/terraform
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

CI (`.github/workflows/validate.yml`) runs the same checks on every push and pull request.

## Style

- Bicep: one module per concern, `@description` on parameters, explicit API versions.
- Terraform: one file per concern (`network.tf`, `ai.tf`, `apps.tf`, `rbac.tf`, ...), `for_each` over maps, `terraform fmt`.
- Python 3.12, type hints, small functions; keep dependencies minimal.
- Comments explain *why*, not *what*.
