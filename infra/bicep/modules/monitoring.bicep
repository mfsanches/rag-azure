@description('Azure region.')
param location string

@description('Name suffix shared by all resources.')
param suffix string

param tags object

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${suffix}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${suffix}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logs.id
    DisableLocalAuth: false
  }
}

output logAnalyticsId string = logs.id
output logAnalyticsCustomerId string = logs.properties.customerId
@secure()
output logAnalyticsSharedKey string = logs.listKeys().primarySharedKey
output appInsightsConnectionString string = appInsights.properties.ConnectionString
