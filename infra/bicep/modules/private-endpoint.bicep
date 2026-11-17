@description('Azure region.')
param location string

@description('Private endpoint name.')
param name string

param tags object

@description('Subnet that hosts the private endpoint.')
param subnetId string

@description('Resource the endpoint connects to.')
param targetResourceId string

@description('Sub-resource, for example account, searchService, blob or vault.')
param groupId string

@description('Private DNS zone that resolves the service name to the private IP.')
param dnsZoneId string

resource endpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: { id: subnetId }
    privateLinkServiceConnections: [
      {
        name: name
        properties: {
          privateLinkServiceId: targetResourceId
          groupIds: [groupId]
        }
      }
    ]
  }
}

resource dnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  parent: endpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'zone'
        properties: { privateDnsZoneId: dnsZoneId }
      }
    ]
  }
}
