// Secure RAG reference architecture on Azure.
// Deploy into an existing resource group:
//   az deployment group create -g <rg> -f main.bicep -p main.bicepparam

targetScope = 'resourceGroup'

@description('Azure region. Pick one where your chosen models are available.')
param location string = resourceGroup().location

@minLength(2)
@maxLength(8)
@description('Short prefix for resource names (letters and digits).')
param namePrefix string = 'rag'

@description('Small chat model: answers simple lookups. Object with name, model, version, skuName, capacity.')
param chatSmall object

@description('Large chat model: answers complex, multi-step questions.')
param chatLarge object

@description('Embedding model.')
param embedding object

@description('Vector size produced by the embedding model.')
param embeddingDimensions int = 1536

@allowed(['basic', 'standard', 'standard2'])
param searchSku string = 'basic'

@description('Container image for the API and ingestion job. The default is a placeholder until you push your own.')
param containerImage string = 'mcr.microsoft.com/k8se/quickstart:latest'

@description('Use the registry created by this template for the image (set true after pushing to it).')
param useCreatedRegistry bool = false

@description('Public IPs allowed to upload documents to storage, e.g. your office IP. Empty = fully private.')
param allowedIpAddresses array = []

@description('Object ID of the user or pipeline that uploads documents. Empty = no assignment.')
param deployerPrincipalId string = ''

param tags object = {
  workload: 'secure-rag'
  managedBy: 'bicep'
}

var suffix = toLower('${namePrefix}-${take(uniqueString(resourceGroup().id), 6)}')
var searchIndexName = 'docs'
var documentsContainer = 'documents'

// ---------- Identities: one per workload, so each gets only the access it needs ----------

resource apiIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-api-${suffix}'
  location: location
  tags: tags
}

resource ingestIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-ingest-${suffix}'
  location: location
  tags: tags
}

// ---------- Foundation ----------

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: { location: location, suffix: suffix, tags: tags }
}

module network 'modules/network.bicep' = {
  name: 'network'
  params: { location: location, suffix: suffix, tags: tags }
}

module data 'modules/data.bicep' = {
  name: 'data'
  params: {
    location: location
    suffix: suffix
    tags: tags
    allowedIpAddresses: allowedIpAddresses
    documentsContainer: documentsContainer
  }
}

module ai 'modules/ai.bicep' = {
  name: 'ai'
  params: {
    location: location
    suffix: suffix
    tags: tags
    searchSku: searchSku
    modelDeployments: [chatSmall, chatLarge, embedding]
  }
}

// ---------- Private endpoints: data services are reachable only from inside the network ----------

// The loop runs over a fixed list; targets come from module outputs inside the loop body.
var privateEndpointTargets = {
  oai: { target: ai.outputs.openaiId, groupId: 'account', zone: network.outputs.dnsZoneIds.openai }
  srch: { target: ai.outputs.searchId, groupId: 'searchService', zone: network.outputs.dnsZoneIds.search }
  blob: { target: data.outputs.storageId, groupId: 'blob', zone: network.outputs.dnsZoneIds.blob }
  kv: { target: data.outputs.vaultId, groupId: 'vault', zone: network.outputs.dnsZoneIds.vault }
}

module endpoints 'modules/private-endpoint.bicep' = [for key in ['oai', 'srch', 'blob', 'kv']: {
  name: 'pe-${key}-${suffix}'
  params: {
    location: location
    tags: tags
    name: 'pe-${key}-${suffix}'
    subnetId: network.outputs.privateEndpointSubnetId
    targetResourceId: privateEndpointTargets[key].target
    groupId: privateEndpointTargets[key].groupId
    dnsZoneId: privateEndpointTargets[key].zone
  }
}]

// ---------- Access ----------

module roles 'modules/roles.bicep' = {
  name: 'roles'
  params: {
    openaiName: last(split(ai.outputs.openaiId, '/'))
    searchName: last(split(ai.outputs.searchId, '/'))
    storageName: data.outputs.storageName
    registryName: data.outputs.registryName
    apiPrincipalId: apiIdentity.properties.principalId
    ingestPrincipalId: ingestIdentity.properties.principalId
    deployerPrincipalId: deployerPrincipalId
  }
}

// ---------- Compute ----------

module apps 'modules/apps.bicep' = {
  name: 'apps'
  dependsOn: [roles, endpoints]
  params: {
    location: location
    suffix: suffix
    tags: tags
    appsSubnetId: network.outputs.appsSubnetId
    logAnalyticsCustomerId: monitoring.outputs.logAnalyticsCustomerId
    logAnalyticsSharedKey: monitoring.outputs.logAnalyticsSharedKey
    containerImage: containerImage
    registryLoginServer: useCreatedRegistry ? data.outputs.registryLoginServer : ''
    apiIdentityId: apiIdentity.id
    apiIdentityClientId: apiIdentity.properties.clientId
    ingestIdentityId: ingestIdentity.id
    ingestIdentityClientId: ingestIdentity.properties.clientId
    sharedEnv: [
      { name: 'AZURE_OPENAI_ENDPOINT', value: ai.outputs.openaiEndpoint }
      { name: 'CHAT_SMALL_DEPLOYMENT', value: chatSmall.name }
      { name: 'CHAT_LARGE_DEPLOYMENT', value: chatLarge.name }
      { name: 'EMBEDDING_DEPLOYMENT', value: embedding.name }
      { name: 'EMBEDDING_DIMENSIONS', value: string(embeddingDimensions) }
      { name: 'AZURE_SEARCH_ENDPOINT', value: ai.outputs.searchEndpoint }
      { name: 'SEARCH_INDEX_NAME', value: searchIndexName }
      { name: 'STORAGE_ACCOUNT_URL', value: data.outputs.storageBlobEndpoint }
      { name: 'DOCUMENTS_CONTAINER', value: documentsContainer }
      { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: monitoring.outputs.appInsightsConnectionString }
    ]
  }
}

output apiUrl string = 'https://${apps.outputs.apiFqdn}'
output apiAppName string = apps.outputs.apiName
output ingestJobName string = apps.outputs.ingestJobName
output storageAccountName string = data.outputs.storageName
output registryLoginServer string = data.outputs.registryLoginServer
output openaiEndpoint string = ai.outputs.openaiEndpoint
output searchEndpoint string = ai.outputs.searchEndpoint
