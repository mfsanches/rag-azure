// Container Apps environment inside the virtual network, the RAG API and the ingestion job.

@description('Azure region.')
param location string

@description('Name suffix shared by all resources.')
param suffix string

param tags object

param appsSubnetId string
param logAnalyticsCustomerId string
@secure()
param logAnalyticsSharedKey string

@description('Container image for both the API and the ingestion job.')
param containerImage string

@description('Registry login server, or empty when the image is public.')
param registryLoginServer string = ''

param apiIdentityId string
param apiIdentityClientId string
param ingestIdentityId string
param ingestIdentityClientId string

@description('Environment variables shared by the API and the job (name/value pairs).')
param sharedEnv array

var registries = empty(registryLoginServer) ? [] : [
  {
    server: registryLoginServer
    identity: apiIdentityId
  }
]

var jobRegistries = empty(registryLoginServer) ? [] : [
  {
    server: registryLoginServer
    identity: ingestIdentityId
  }
]

resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${suffix}'
  location: location
  tags: tags
  properties: {
    vnetConfiguration: {
      infrastructureSubnetId: appsSubnetId
      internal: false
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: logAnalyticsSharedKey
      }
    }
  }
}

resource api 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-api-${suffix}'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${apiIdentityId}': {} }
  }
  properties: {
    environmentId: env.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      registries: registries
      ingress: {
        external: true
        targetPort: 8000
        transport: 'auto'
        allowInsecure: false
      }
    }
    template: {
      containers: [
        {
          name: 'api'
          image: containerImage
          resources: { cpu: json('0.5'), memory: '1Gi' }
          env: concat(sharedEnv, [{ name: 'AZURE_CLIENT_ID', value: apiIdentityClientId }])
          probes: [
            {
              type: 'Liveness'
              httpGet: { path: '/healthz', port: 8000 }
              initialDelaySeconds: 10
              periodSeconds: 30
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 5
        rules: [
          {
            name: 'http'
            http: { metadata: { concurrentRequests: '20' } }
          }
        ]
      }
    }
  }
}

resource ingestJob 'Microsoft.App/jobs@2024-03-01' = {
  name: 'caj-ingest-${suffix}'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${ingestIdentityId}': {} }
  }
  properties: {
    environmentId: env.id
    workloadProfileName: 'Consumption'
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 3600
      replicaRetryLimit: 1
      manualTriggerConfig: {
        parallelism: 1
        replicaCompletionCount: 1
      }
      registries: jobRegistries
    }
    template: {
      containers: [
        {
          name: 'ingest'
          image: containerImage
          command: ['python', 'ingest.py']
          resources: { cpu: json('0.5'), memory: '1Gi' }
          env: concat(sharedEnv, [{ name: 'AZURE_CLIENT_ID', value: ingestIdentityClientId }])
        }
      ]
    }
  }
}

output apiFqdn string = api.properties.configuration.ingress.fqdn
output apiName string = api.name
output ingestJobName string = ingestJob.name
