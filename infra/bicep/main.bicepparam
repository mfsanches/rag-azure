using 'main.bicep'

param namePrefix = 'rag'

// Model names and versions change often. Before deploying, check what your region offers:
//   az cognitiveservices model list -l <region> -o table
// and update these values. Capacity is in thousands of tokens per minute.
param chatSmall = {
  name: 'chat-small'
  model: 'gpt-4o-mini'
  version: '2024-07-18'
  skuName: 'GlobalStandard'
  capacity: 50
}

param chatLarge = {
  name: 'chat-large'
  model: 'gpt-4o'
  version: '2024-11-20'
  skuName: 'GlobalStandard'
  capacity: 20
}

param embedding = {
  name: 'embedding'
  model: 'text-embedding-3-small'
  version: '1'
  skuName: 'Standard'
  capacity: 50
}

param embeddingDimensions = 1536

param searchSku = 'basic'

// Your public IP, so you can upload documents. Leave empty to keep storage fully private.
param allowedIpAddresses = []

// Your Entra object ID (az ad signed-in-user show --query id -o tsv), to upload documents.
param deployerPrincipalId = ''
