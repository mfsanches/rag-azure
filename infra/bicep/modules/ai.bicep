// Azure OpenAI (chat + embeddings) and Azure AI Search. Both private, both Entra ID only.

@description('Azure region. Check model availability for the region you pick.')
param location string

@description('Name suffix shared by all resources.')
param suffix string

param tags object

@description('Model deployments: name, model, version, skuName, capacity (thousands of tokens per minute).')
param modelDeployments array

@allowed(['basic', 'standard', 'standard2'])
@description('AI Search tier. Basic is the lowest tier with private endpoints and semantic ranking.')
param searchSku string = 'basic'

resource openai 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: 'oai-${suffix}'
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: { name: 'S0' }
  properties: {
    customSubDomainName: 'oai-${suffix}'
    publicNetworkAccess: 'Disabled'
    disableLocalAuth: true // no API keys
    networkAcls: { defaultAction: 'Deny' }
  }
}

// Deploy one model at a time: the service rejects parallel deployment changes.
@batchSize(1)
resource deployments 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = [for d in modelDeployments: {
  parent: openai
  name: d.name
  sku: {
    name: d.skuName
    capacity: d.capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: d.model
      version: d.version
    }
  }
}]

resource search 'Microsoft.Search/searchServices@2023-11-01' = {
  name: 'srch-${suffix}'
  location: location
  tags: tags
  sku: { name: searchSku }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    publicNetworkAccess: 'disabled'
    disableLocalAuth: true // no admin or query keys
    semanticSearch: 'free'
  }
}

output openaiId string = openai.id
output openaiEndpoint string = openai.properties.endpoint
output searchId string = search.id
output searchEndpoint string = 'https://${search.name}.search.windows.net'
