// ─────────────────────────────────────────────────────────────────────────────
// containerApps.bicep — Log Analytics + Container Apps Environment + Apps
// Deploys: Log Analytics, VNet-integrated Container Apps Environment,
//          RabbitMQ (internal TCP), Notification Sender, Notification Receiver
// ─────────────────────────────────────────────────────────────────────────────

param location         string
param environmentName  string
param projectName      string
param tags             object
param infraSubnetId    string
param acrName          string
param acrResourceGroup string
param imageTag         string
param rabbitmqUsername string
@secure()
param rabbitmqPassword string
param senderMinReplicas  int
param senderMaxReplicas  int
param swaggerEnabled     string
param logRetentionInDays int

var envName         = '${projectName}-env-${environmentName}'
var senderAppName   = '${projectName}-sender-${environmentName}'
var receiverAppName = '${projectName}-receiver-${environmentName}'
var rabbitAppName   = '${projectName}-rabbitmq-${environmentName}'
var workloadProfile = 'Consumption'

// ─── Shared ACR (lives in another resource group) ─────────────────────────────
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name:  acrName
  scope: resourceGroup(acrResourceGroup)
}

// ─── Log Analytics Workspace ──────────────────────────────────────────────────
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name:     '${projectName}-logs-${environmentName}'
  location: location
  tags:     tags
  properties: {
    sku:             { name: 'PerGB2018' }
    retentionInDays: logRetentionInDays
  }
}

// ─── Container Apps Environment (VNet-integrated, workload profiles) ──────────
resource caEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name:     envName
  location: location
  tags:     tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey:  logAnalytics.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: {
      infrastructureSubnetId: infraSubnetId
      internal:               false   // Sender/Receiver keep public HTTPS endpoints
    }
    workloadProfiles: [
      {
        name:                workloadProfile
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

// ─── Common app settings ──────────────────────────────────────────────────────
var registryConfig = [
  {
    server:            acr.properties.loginServer
    username:          acr.listCredentials().username
    passwordSecretRef: 'acr-password'
  }
]

var appSecrets = [
  { name: 'acr-password',      value: acr.listCredentials().passwords[0].value }
  { name: 'rabbitmq-password', value: rabbitmqPassword }
]

var commonEnv = [
  { name: 'ASPNETCORE_ENVIRONMENT',             value: 'Production' }
  { name: 'ASPNETCORE_HTTP_PORTS',              value: '8080' }
  // Container Apps terminates TLS; trust X-Forwarded-* so HTTPS redirection works.
  { name: 'ASPNETCORE_FORWARDEDHEADERS_ENABLED', value: 'true' }
  { name: 'Swagger__Enabled',                   value: swaggerEnabled }
  { name: 'RabbitMQ__Host',                     value: rabbitApp.properties.configuration.ingress.fqdn }
  { name: 'RabbitMQ__Username',                 value: rabbitmqUsername }
  { name: 'RabbitMQ__Password',                 secretRef: 'rabbitmq-password' }
]

var httpProbes = [
  {
    type:    'Liveness'
    httpGet: { path: '/health/live', port: 8080, scheme: 'HTTP' }
    initialDelaySeconds: 10
    periodSeconds:       15
    failureThreshold:    3
  }
  {
    type:    'Readiness'
    httpGet: { path: '/health/ready', port: 8080, scheme: 'HTTP' }
    initialDelaySeconds: 10
    periodSeconds:       10
    failureThreshold:    6
  }
]

// ─── RabbitMQ Container App (internal TCP only) ───────────────────────────────
// NOTE: storage is ephemeral — queued messages are lost if the replica restarts.
// For durable messaging, mount Azure Files or move to Azure Service Bus.
resource rabbitApp 'Microsoft.App/containerApps@2024-03-01' = {
  name:     rabbitAppName
  location: location
  tags:     tags
  properties: {
    managedEnvironmentId: caEnv.id
    workloadProfileName:  workloadProfile
    configuration: {
      activeRevisionsMode: 'Single'
      secrets: [
        { name: 'rabbitmq-password', value: rabbitmqPassword }
      ]
      ingress: {
        external:    false
        transport:   'tcp'
        targetPort:  5672
        exposedPort: 5672
      }
    }
    template: {
      containers: [
        {
          name:  'rabbitmq'
          image: 'docker.io/library/rabbitmq:3.13-management'
          resources: {
            cpu:    json('0.5')
            memory: '1Gi'
          }
          env: [
            { name: 'RABBITMQ_DEFAULT_USER', value: rabbitmqUsername }
            { name: 'RABBITMQ_DEFAULT_PASS', secretRef: 'rabbitmq-password' }
          ]
          probes: [
            {
              type:             'Startup'
              tcpSocket:        { port: 5672 }
              periodSeconds:    5
              failureThreshold: 30
            }
            {
              type:          'Liveness'
              tcpSocket:     { port: 5672 }
              periodSeconds: 20
            }
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

// ─── Notification Sender (Command side) ───────────────────────────────────────
resource senderApp 'Microsoft.App/containerApps@2024-03-01' = {
  name:     senderAppName
  location: location
  tags:     tags
  properties: {
    managedEnvironmentId: caEnv.id
    workloadProfileName:  workloadProfile
    configuration: {
      activeRevisionsMode: 'Single'
      registries: registryConfig
      secrets:    appSecrets
      ingress: {
        external:   true
        targetPort: 8080
        transport:  'auto'
        allowInsecure: false
      }
    }
    template: {
      containers: [
        {
          name:  'notification-sender'
          image: '${acr.properties.loginServer}/mango/notification-sender:${imageTag}'
          resources: {
            cpu:    json('0.25')
            memory: '0.5Gi'
          }
          env:    commonEnv
          probes: httpProbes
        }
      ]
      scale: {
        minReplicas: senderMinReplicas
        maxReplicas: senderMaxReplicas
        rules: [
          {
            name: 'http-scaling'
            http: { metadata: { concurrentRequests: '50' } }
          }
        ]
      }
    }
  }
}

// ─── Notification Receiver (Query side) ───────────────────────────────────────
// Pinned to ONE replica: it stores data in a local SQLite file, so extra
// replicas would each have their own database and split the message stream.
resource receiverApp 'Microsoft.App/containerApps@2024-03-01' = {
  name:     receiverAppName
  location: location
  tags:     tags
  properties: {
    managedEnvironmentId: caEnv.id
    workloadProfileName:  workloadProfile
    configuration: {
      activeRevisionsMode: 'Single'
      registries: registryConfig
      secrets:    appSecrets
      ingress: {
        external:   true
        targetPort: 8080
        transport:  'auto'
        allowInsecure: false
      }
    }
    template: {
      containers: [
        {
          name:  'notification-receiver'
          image: '${acr.properties.loginServer}/mango/notification-receiver:${imageTag}'
          resources: {
            cpu:    json('0.25')
            memory: '0.5Gi'
          }
          env: concat(commonEnv, [
            { name: 'ConnectionStrings__DefaultConnection', value: 'Data Source=/app/data/notifications.db' }
          ])
          probes: httpProbes
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

// ─── Outputs ──────────────────────────────────────────────────────────────────
output senderFqdn   string = senderApp.properties.configuration.ingress.fqdn
output receiverFqdn string = receiverApp.properties.configuration.ingress.fqdn
output rabbitFqdn   string = rabbitApp.properties.configuration.ingress.fqdn
