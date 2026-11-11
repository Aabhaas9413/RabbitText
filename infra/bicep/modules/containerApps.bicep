// ─────────────────────────────────────────────────────────────────────────────
// containerApps.bicep — Log Analytics + Container Apps Environment + Apps
// Deploys: Log Analytics, VNet-integrated Container Apps Environment,
//          Broker (RabbitMQ OR Kafka based on messagingProvider feature flag),
//          Notification Sender, Notification Receiver
// ─────────────────────────────────────────────────────────────────────────────

param location         string
param environmentName  string
param projectName      string
param tags             object
param infraSubnetId    string
param acrName          string
param acrResourceGroup string
param imageTag         string
@allowed(['RabbitMQ', 'Kafka'])
param messagingProvider string
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
var kafkaAppName    = '${projectName}-kafka-${environmentName}'
var workloadProfile = 'Consumption'
var useKafka        = toLower(messagingProvider) == 'kafka'

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
    // Cap daily ingestion at 0.1 GB (≈3 GB/month max) so usage stays inside
    // Azure's 5 GB/month free allowance and can never cause a surprise bill.
    workspaceCapping: {
      dailyQuotaGb: json('0.1')
    }
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
  // Feature flag injected into both microservices ("RabbitMQ" or "Kafka")
  { name: 'Messaging__Provider',                value: messagingProvider }
  // RabbitMQ settings (used when Messaging__Provider == "RabbitMQ")
  { name: 'RabbitMQ__Host',                     value: rabbitAppName }
  { name: 'RabbitMQ__Username',                 value: rabbitmqUsername }
  { name: 'RabbitMQ__Password',                 secretRef: 'rabbitmq-password' }
  // Kafka settings (used when Messaging__Provider == "Kafka")
  { name: 'Kafka__BootstrapServers',            value: '${kafkaAppName}:9092' }
  { name: 'Kafka__Topic',                       value: 'notification-created' }
]

var httpProbes = [
  {
    type:    'Liveness'
    httpGet: { path: '/health/live', port: 8080, scheme: 'HTTP' }
    initialDelaySeconds: 5
    periodSeconds:       30
    failureThreshold:    3
  }
  {
    type:    'Readiness'
    httpGet: { path: '/health/live', port: 8080, scheme: 'HTTP' }
    initialDelaySeconds: 3
    periodSeconds:       10
    failureThreshold:    3
  }
]

// ─── Option A: RabbitMQ Container App (deployed only when messagingProvider == 'RabbitMQ') ──
resource rabbitApp 'Microsoft.App/containerApps@2024-03-01' = if (!useKafka) {
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
          image: 'docker.io/library/rabbitmq:3.13-alpine'
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
              periodSeconds: 30
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

// ─── Option B: Kafka (KRaft single-node) Container App (deployed only when messagingProvider == 'Kafka') ──
resource kafkaApp 'Microsoft.App/containerApps@2024-03-01' = if (useKafka) {
  name:     kafkaAppName
  location: location
  tags:     tags
  properties: {
    managedEnvironmentId: caEnv.id
    workloadProfileName:  workloadProfile
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external:    false
        transport:   'tcp'
        targetPort:  9092
        exposedPort: 9092
      }
    }
    template: {
      containers: [
        {
          name:  'kafka'
          image: 'docker.io/apache/kafka:3.8.1'
          resources: {
            cpu:    json('0.5')
            memory: '1Gi'
          }
          env: [
            { name: 'KAFKA_NODE_ID',                                  value: '1' }
            { name: 'KAFKA_PROCESS_ROLES',                            value: 'broker,controller' }
            { name: 'KAFKA_LISTENERS',                                value: 'PLAINTEXT://:9092,CONTROLLER://:9093' }
            { name: 'KAFKA_ADVERTISED_LISTENERS',                     value: 'PLAINTEXT://${kafkaAppName}:9092' }
            { name: 'KAFKA_CONTROLLER_LISTENER_NAMES',                value: 'CONTROLLER' }
            { name: 'KAFKA_LISTENER_SECURITY_PROTOCOL_MAP',           value: 'CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT' }
            { name: 'KAFKA_CONTROLLER_QUORUM_VOTERS',                 value: '1@localhost:9093' }
            { name: 'KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR',         value: '1' }
            { name: 'KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR', value: '1' }
            { name: 'KAFKA_TRANSACTION_STATE_LOG_MIN_ISR',            value: '1' }
            { name: 'KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS',         value: '0' }
            { name: 'KAFKA_NUM_PARTITIONS',                           value: '1' }
            { name: 'KAFKA_AUTO_CREATE_TOPICS_ENABLE',                value: 'true' }
            { name: 'KAFKA_HEAP_OPTS',                                value: '-Xms256m -Xmx256m' }
            { name: 'CLUSTER_ID',                                     value: 'MkU3OEVBNTcwNTJENDM2Qk' }
          ]
          probes: [
            {
              type:             'Startup'
              tcpSocket:        { port: 9092 }
              periodSeconds:    5
              failureThreshold: 30
            }
            {
              type:          'Liveness'
              tcpSocket:     { port: 9092 }
              periodSeconds: 30
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
  dependsOn: [
    rabbitApp
    kafkaApp
  ]
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
          image: '${acr.properties.loginServer}/alpha/notification-sender:${imageTag}'
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
  dependsOn: [
    rabbitApp
    kafkaApp
  ]
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
          image: '${acr.properties.loginServer}/alpha/notification-receiver:${imageTag}'
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
output senderFqdn    string = senderApp.properties.configuration.ingress.fqdn
output receiverFqdn  string = receiverApp.properties.configuration.ingress.fqdn
output brokerAppName string = useKafka ? kafkaAppName : rabbitAppName
