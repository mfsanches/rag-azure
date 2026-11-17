// Storage for source documents, Key Vault for future application secrets, and a container registry.

@description('Azure region.')
param location string

@minLength(5)
@description('Name suffix shared by all resources.')
param suffix string

param tags object

@description('Public IP addresses allowed to upload documents to storage. Empty = private only.')
param allowedIpAddresses array = []

@description('Blob container that holds source documents.')
param documentsContainer string = 'documents'

var storageOpenToIps = !empty(allowedIpAddresses)

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  #disable-next-line BCP334 // suffix is always at least 5 characters
  name: 'st${replace(suffix, '-', '')}'
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false // Entra ID only
    defaultToOAuthAuthentication: true
    publicNetworkAccess: storageOpenToIps ? 'Enabled' : 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: [for ip in allowedIpAddresses: { value: ip, action: 'Allow' }]
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {
    deleteRetentionPolicy: { enabled: true, days: 7 }
  }
}

resource documents 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: documentsContainer
  properties: { publicAccess: 'None' }
}

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-${suffix}'
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: true
    publicNetworkAccess: 'Disabled'
    networkAcls: { defaultAction: 'Deny', bypass: 'AzureServices' }
  }
}

// Basic SKU keeps the reference cheap; use Premium for private endpoints on the registry.
resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  #disable-next-line BCP334 // suffix is always at least 5 characters
  name: 'cr${replace(suffix, '-', '')}'
  location: location
  tags: tags
  sku: { name: 'Basic' }
  properties: {
    adminUserEnabled: false
  }
}

output storageId string = storage.id
output storageName string = storage.name
output storageBlobEndpoint string = storage.properties.primaryEndpoints.blob
output vaultId string = vault.id
output vaultName string = vault.name
output registryId string = registry.id
output registryName string = registry.name
output registryLoginServer string = registry.properties.loginServer
