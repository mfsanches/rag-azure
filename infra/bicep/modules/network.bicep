@description('Azure region.')
param location string

@description('Name suffix shared by all resources.')
param suffix string

param tags object

@description('Address space of the virtual network.')
param addressPrefix string = '10.20.0.0/16'

// Private DNS zones for every service reached through a private endpoint.
var dnsZoneNames = {
  openai: 'privatelink.openai.azure.com'
  search: 'privatelink.search.windows.net'
  blob: 'privatelink.blob.${environment().suffixes.storage}'
  vault: 'privatelink.vaultcore.azure.net'
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: 'vnet-${suffix}'
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [addressPrefix] }
    subnets: [
      {
        // Container Apps environment (workload profiles need a delegated /27 or larger).
        name: 'snet-apps'
        properties: {
          addressPrefix: cidrSubnet(addressPrefix, 23, 0)
          delegations: [
            {
              name: 'containerapps'
              properties: { serviceName: 'Microsoft.App/environments' }
            }
          ]
        }
      }
      {
        name: 'snet-private-endpoints'
        properties: {
          addressPrefix: cidrSubnet(addressPrefix, 24, 2)
          privateEndpointNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

resource zones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for zone in items(dnsZoneNames): {
  name: zone.value
  location: 'global'
  tags: tags
}]

resource zoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zone, i) in items(dnsZoneNames): {
  parent: zones[i]
  name: 'link-${vnet.name}'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}]

output vnetId string = vnet.id
output appsSubnetId string = vnet.properties.subnets[0].id
output privateEndpointSubnetId string = vnet.properties.subnets[1].id
// items() sorts keys alphabetically: blob, openai, search, vault.
output dnsZoneIds object = {
  blob: zones[0].id
  openai: zones[1].id
  search: zones[2].id
  vault: zones[3].id
}
