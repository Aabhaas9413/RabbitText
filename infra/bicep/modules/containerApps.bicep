// ─────────────────────────────────────────────────────────────────────────────
// containerApps.bicep — Azure Container Apps Environment + Apps
// Deploys: Log Analytics, Container Apps Environment, RabbitMQ, Sender, Receiver
// ─────────────────────────────────────────────────────────────────────────────

param location       string
param environment    string
param envName        string
param acrLoginServer string
param acrName        string
param projectName    string
param imageTag       string
param senderAppName  string
param receiverAppName string
param rabbitAppName  string

// ─── Log Analytics Workspace ──────────────────────────────────────────────────
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name:     '${projectName}-logs-${environment}'
  location: location
  properties: {
    sku:            { name: 'PerGB2018' }
    retentionInDays: 30
  }
  tags: {
    environment: environment
    project:     projectName
  }
}

// ─── Container Apps Environment ───────────────────────────────────────────────
resource caEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name:     envName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey:  logAnalytics.listKeys().primarySharedKey
      }
    }
  }
  tags: {
    environment: environment
    project:     projectName
  }
}

// ─── ACR credentials (referenced by all apps) ─────────────────────────────────
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

// ─── RabbitMQ Container App ───────────────────────────────────────────────────
resource rabbitApp 'Microsoft.App/containerApps@2023-05-01' = {
  name:     rabbitAppName
  location: location
  properties: {
    managedEnvironmentId: caEnv.id
    configuration: {
      ingress: {
        external:   false
        targetPort: 5672
        transport:  'tcp'
      }
    }
    template: {
      containers: [
        {
          name:  'rabbitmq'
          image: 'rabbitmq:3.13-management'
          resources: {
            cpu:    json('0.5')
            memory: '1Gi'
          }
          env: [
            { name: 'RABBITMQ_DEFAULT_USER', value: 'guest' }
            { name: 'RABBITMQ_DEFAULT_PASS', value: 'guest' }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

// ─── Notification Sender Container App ────────────────────────────────────────
resource senderApp 'Microsoft.App/containerApps@2023-05-01' = {
  name:     senderAppName
  location: location
  properties: {
    managedEnvironmentId: caEnv.id
    configuration: {
      registries: [
        {
          server:            acrLoginServer
          username:          acr.listCredentials().username
          passwordSecretRef: 'acr-password'
        }
      ]
      secrets: [
        {
          name:  'acr-password'
          value: acr.listCredentials().passwords[0].value
        }
      ]
      ingress: {
        external:   true
        targetPort: 8080
        transport:  'http'
      }
    }
    template: {
      containers: [
        {
          name:  'notification-sender'
          image: '${acrLoginServer}/mango/notification-sender:${imageTag}'
          resources: {
            cpu:    json('0.25')
            memory: '0.5Gi'
          }
          env: [
            { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
            { name: 'RabbitMQ__Host',         value: rabbitApp.properties.configuration.ingress.fqdn }
            { name: 'RabbitMQ__Username',     value: 'guest' }
            { name: 'RabbitMQ__Password',     value: 'guest' }
          ]
          probes: [
            {
              type: 'Readiness'
              httpGet: { path: '/health', port: 8080, scheme: 'HTTP' }
              initialDelaySeconds: 10
              periodSeconds:       10
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 5
        rules: [
          {
            name: 'http-scaling'
            http: { metadata: { concurrentRequests: '50' } }
          }
        ]
      }
    }
  }
  dependsOn: [rabbitApp]
}

// ─── Notification Receiver Container App ──────────────────────────────────────
resource receiverApp 'Microsoft.App/containerApps@2023-05-01' = {
  name:     receiverAppName
  location: location
  properties: {
    managedEnvironmentId: caEnv.id
    configuration: {
      registries: [
        {
          server:            acrLoginServer
          username:          acr.listCredentials().username
          passwordSecretRef: 'acr-password'
        }
      ]
      secrets: [
        {
          name:  'acr-password'
          value: acr.listCredentials().passwords[0].value
        }
      ]
      ingress: {
        external:   true
        targetPort: 8080
        transport:  'http'
      }
    }
    template: {
      containers: [
        {
          name:  'notification-receiver'
          image: '${acrLoginServer}/mango/notification-receiver:${imageTag}'
          resources: {
            cpu:    json('0.25')
            memory: '0.5Gi'
          }
          env: [
            { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
            { name: 'RabbitMQ__Host',         value: rabbitApp.properties.configuration.ingress.fqdn }
            { name: 'RabbitMQ__Username',     value: 'guest' }
            { name: 'RabbitMQ__Password',     value: 'guest' }
          ]
          probes: [
            {
              type: 'Readiness'
              httpGet: { path: '/health', port: 8080, scheme: 'HTTP' }
              initialDelaySeconds: 10
              periodSeconds:       10
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
  dependsOn: [rabbitApp]
}

// ─── Outputs ──────────────────────────────────────────────────────────────────
output senderFqdn   string = senderApp.properties.configuration.ingress.fqdn
output receiverFqdn string = receiverApp.properties.configuration.ingress.fqdn
