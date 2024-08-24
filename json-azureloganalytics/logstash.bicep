@description('Selects the resource group location with the default value.')
param location string = resourceGroup().location
@description('Generates a unique name with the default value.')
param storageAccountName string = 'logstash${substring(uniqueString(resourceGroup().id),0,5)}'
@description('The name of the Azure Files share.')
param storageAccountShareName string = 'logstash-config'
@description('Generates a unique name with the default value.')
param logAnalyticsAccountName string = 'logstash-${substring(uniqueString(resourceGroup().id),0,5)}'
@description('Generates a unique name with the default value.')
param dataCollectionEndpointName string = 'logstash-${substring(uniqueString(resourceGroup().id),0,5)}'
@description('Generates a unique name with the default value.')
param dataCollectionRuleName string = 'logstash-${substring(uniqueString(resourceGroup().id),0,5)}'
@description('Generates a unique name with the default value.')
param containerAppEnvironmentName string = 'logstash-${substring(uniqueString(resourceGroup().id),0,5)}'
@description('Generates a unique name with the default value.')
param containerAppName string = 'logstash-${substring(uniqueString(resourceGroup().id),0,5)}'
@description('The name of the container.')
param containerName string = 'logstash'
@description('The vCPU allocation that meets the consumption workload profile requirements.')
param containerCpu string = '1'
@description('The Memory allocation that meets the consumption workload profile requirements.')
param containerMemory string = '2'
@description('The URI for the container image, see docker.elastic.co/r/logstash for latest images.')
param containerImage string = 'docker.elastic.co/logstash/logstash-oss:8.14.3'
@description('The port the Logstash pipeline will listen on, and the target port for ingress traffic to the Container App.')
param logstashInputPort string = '1066'
@description('The user ID for Logstash pipeline basic authentication.')
param logstashInputUser string = 'logstash'
@description('The password for Logstash pipeline basic authentication.')
@secure()
param logstashInputPass string
@description('The client ID of the application given access to the DCR.')
param applicationClientId string
@description('The secret value of the application.')
@secure()
param applicationSecretValue string

var tableName = 'Logstash_CL'


resource sa 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    isHnsEnabled: true
  }

  resource saService 'fileServices' = {
    name: 'default'

    resource saShare 'shares' = {
      name: storageAccountShareName
      properties: {
        accessTier: 'TransactionOptimized'
      }
    }
  }
}

resource dce 'Microsoft.Insights/dataCollectionEndpoints@2023-03-11' = {
  name: dataCollectionEndpointName
  location: location
  kind: 'string'
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

resource la 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsAccountName 
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }

  resource laTable 'tables@2022-10-01' = {
    name: tableName
    properties: {
      schema: {
        name: tableName
        columns: [
          {
            name: 'TimeGenerated'
            type: 'dateTime'
          }
          {
            name: 'RawData'
            type: 'string'
          }
        ]
      }
    }
  }
}

resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  location: location
  name: dataCollectionRuleName
  properties: {
    dataCollectionEndpointId: dce.id
    destinations: {
      logAnalytics: [
        {
          name: 'la-workspace-destination'
          workspaceResourceId: la.id
        }
      ]
    }
    dataFlows: [
      {
        outputStream: 'Custom-${la::laTable.name}'
        streams: [
          'Custom-${la::laTable.name}'
        ]
        destinations: [
          'la-workspace-destination'
        ]
        transformKql: 'source | extend TimeGenerated = now()'
      }
    ]
  }
}

resource caEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppEnvironmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: la.properties.customerId
        sharedKey: la.listKeys().primarySharedKey
      }
    }
  }

  resource caEnvironmentStorage 'storages' = {
    name: sa::saService::saShare.name
    properties: {
      azureFile: {
        accountName: storageAccountName
        shareName: storageAccountShareName
        accountKey: sa.listKeys().keys[0].value
        accessMode: 'ReadWrite'
      }
    }
  }
}

resource ca 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppName
  location: location
  properties: {
    environmentId: caEnvironment.id
    template: {
      containers: [
        {
          name: containerName
          image: containerImage 
          command: [
            '/bin/bash'
            '-c'
            'logstash-plugin install logstash-filter-json_encode microsoft-sentinel-log-analytics-logstash-output-plugin && logstash'
          ]
          resources: {
            cpu: json(containerCpu)
            memory: '${containerMemory}Gi'
          }
          volumeMounts: [
            {
              volumeName: storageAccountShareName
              mountPath: '/usr/share/logstash/config/'
            }
          ]
          env:[
            {
              name: 'INPUT_PORT'
              value: logstashInputPort
            }
            {
              name: 'INPUT_USER'
              value: logstashInputUser
            }
            {
              name: 'INPUT_PASS'
              secretRef: 'input-pass'
            }
            {
              name: 'OUTPUT_TENANT_ID'
              value: subscription().tenantId
            }
            {
              name: 'OUTPUT_APP_ID'
              value: applicationClientId
            }
            {
              name: 'OUTPUT_APP_SECRET'
              secretRef: 'output-app-secret'
            }
            {
              name: 'OUTPUT_DCE'
              value: dce.properties.logsIngestion.endpoint
            }
            {
              name: 'OUTPUT_DCR_ID'
              value: dcr.properties.immutableId
            }
            {
              name: 'OUTPUT_DCR_STREAM'
              value: 'Custom-${la::laTable.name}'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 1
      }
      volumes: [
        {
          name: caEnvironment::caEnvironmentStorage.name
          storageName: storageAccountShareName
          storageType: 'AzureFile'
        }
      ]
    }
    configuration: {
      ingress: {
        external: true
        targetPort: int(logstashInputPort)
      }
      secrets: [
        {
          name: 'input-pass'
          value: logstashInputPass
        }
        {
          name: 'output-app-secret'
          value: applicationSecretValue
        }
      ]
    }
  }
}
