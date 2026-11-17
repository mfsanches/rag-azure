# Architecture decisions

Short records of the main choices in this reference, and what was traded away.

## 1. Tenant isolation with a filtered shared index

**Decision:** one search index for all tenants, with a `tenantId` field on every chunk and a filter applied on every query.

**Why:** cheapest and simplest to operate for many small tenants. One index, one ingestion job, one set of deployments.

**How it stays safe:**
- The tenant comes only from the validated identity (Container Apps built-in auth sets `X-MS-CLIENT-PRINCIPAL` after validating the token). Never from the request body, and never from model output.
- Tenant IDs are validated against a strict pattern before going into the filter, which prevents filter injection.
- Ingestion assigns ownership from the folder path and skips anything outside the known layout.
- Unit tests cover injection attempts, missing claims and misplaced files.

**Trade-off:** a bug in the filter would expose data across tenants. For regulated or very large tenants, use **one index per tenant** (or one search service per tenant) instead, at higher cost.

## 2. Managed identity everywhere, keys disabled

**Decision:** `disableLocalAuth` on Azure OpenAI and AI Search, `allowSharedKeyAccess: false` on Storage, admin user off on the registry.

**Why:** no secrets to leak, rotate or store. Access is visible and revocable in role assignments.

**Trade-off:** some tools and older SDKs only support keys. Local development needs `az login` and the right roles.

## 3. Two identities: API reads, ingestion writes

**Decision:** separate user-assigned identities. The API has *Search Index Data Reader*; the ingestion job has *Search Index Data Contributor* and *Search Service Contributor*.

**Why:** a compromised API cannot modify or poison the index.

## 4. Private endpoints for all data services

**Decision:** Azure OpenAI, AI Search, Storage and Key Vault have public network access disabled and are reached through private endpoints with private DNS zones. The Container Apps environment is injected into the virtual network.

**Why:** removes the data services from the internet entirely.

**Trade-offs:** about the cost of four private endpoints per month, more DNS to manage, and local development needs network access. Storage can optionally allow specific IPs, so documents can be uploaded without a VPN.

## 5. Ingestion as a Container Apps job inside the network

**Decision:** ingestion runs as a manually triggered Container Apps job using the same image as the API.

**Why:** it can reach the private services without opening them up, it scales to zero, and it can later be triggered on a schedule or by a storage event.

## 6. Model routing: small by default, large when needed

**Decision:** a simple heuristic sends multi-step or long questions to the large model and everything else to the small one.

**Why:** in typical support workloads most questions are simple lookups, and small models cost a fraction of large ones per token.

**Trade-off:** a heuristic will misroute some questions. Replace it with a classifier once you have evaluation data, and measure quality per route.

## 7. Small context: ~600-token chunks, top 3 results, hybrid search + semantic ranking

**Decision:** chunks of about 2,400 characters with overlap, hybrid keyword + vector retrieval, semantic re-ranking, and only the top 3 chunks sent to the model.

**Why:** retrieval quality comes from better ranking, not from stuffing more context. Smaller prompts are cheaper and faster.

## 8. Bicep and Terraform side by side

**Decision:** the same architecture in both tools.

**Why:** teams standardize on one or the other. Keeping both shows the mapping between them and lets the reference drop into either kind of team.
