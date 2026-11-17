// Least-privilege role assignments. The API can only read; the ingestion job can write the index.

param openaiName string
param searchName string
param storageName string
param registryName string

param apiPrincipalId string
param ingestPrincipalId string

@description('Optional: the person or pipeline that uploads documents. Empty = skip.')
param deployerPrincipalId string = ''

// Built-in role definition IDs.
var roles = {
  openaiUser: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd' // Cognitive Services OpenAI User
  searchIndexReader: '1407120a-92aa-4202-b7e9-c0e197c71c8f' // Search Index Data Reader
  searchIndexContributor: '8ebe5a00-799e-43f5-93ac-243d3dce84a7' // Search Index Data Contributor
  searchServiceContributor: '7ca78c08-252a-4471-8644-bb5ff32d4ba0' // Search Service Contributor (create the index)
  blobReader: '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1' // Storage Blob Data Reader
  blobContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
  acrPull: '7f951dda-4ed3-4680-a7ca-43fe172d538d' // AcrPull
}

resource openai 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: openaiName
}

resource search 'Microsoft.Search/searchServices@2023-11-01' existing = {
  name: searchName
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageName
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: registryName
}

var openaiAssignments = [
  { principalId: apiPrincipalId, role: roles.openaiUser }
  { principalId: ingestPrincipalId, role: roles.openaiUser }
]

var searchAssignments = [
  { principalId: apiPrincipalId, role: roles.searchIndexReader }
  { principalId: ingestPrincipalId, role: roles.searchIndexContributor }
  { principalId: ingestPrincipalId, role: roles.searchServiceContributor }
]

var storageAssignments = concat(
  [{ principalId: ingestPrincipalId, role: roles.blobReader }],
  empty(deployerPrincipalId) ? [] : [{ principalId: deployerPrincipalId, role: roles.blobContributor }]
)

var registryAssignments = [
  { principalId: apiPrincipalId, role: roles.acrPull }
  { principalId: ingestPrincipalId, role: roles.acrPull }
]

resource openaiRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for a in openaiAssignments: {
  scope: openai
  name: guid(openai.id, a.principalId, a.role)
  properties: {
    principalId: a.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', a.role)
    principalType: 'ServicePrincipal'
  }
}]

resource searchRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for a in searchAssignments: {
  scope: search
  name: guid(search.id, a.principalId, a.role)
  properties: {
    principalId: a.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', a.role)
    principalType: 'ServicePrincipal'
  }
}]

resource storageRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for a in storageAssignments: {
  scope: storage
  name: guid(storage.id, a.principalId, a.role)
  properties: {
    principalId: a.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', a.role)
  }
}]

resource registryRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for a in registryAssignments: {
  scope: registry
  name: guid(registry.id, a.principalId, a.role)
  properties: {
    principalId: a.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', a.role)
    principalType: 'ServicePrincipal'
  }
}]
