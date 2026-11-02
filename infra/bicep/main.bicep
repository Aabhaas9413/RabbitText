// ─────────────────────────────────────────────────────────────────────────────
// main.bicep — Alpha Platform, per-environment infrastructure
// Deploys into the environment resource group (alpha-rg-dev / alpha-rg-prod):
//   VNet → Log Analytics → Container Apps Environment → RabbitMQ, Sender, Receiver
// Images are pulled from the SHARED registry deployed by shared.bicep.
// ─────────────────────────────────────────────────────────────────────────────

targetScope = 'resourceGroup'

@description('Environment name. Used in resource naming and sizing.')
@allowed(['dev', 'prod'])
param environmentName string

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Project name prefix for resource naming.')
param projectName string = 'alpha'

@description('Container image tag to deploy (the pipeline passes the build id).')
param imageTag string

@description('Name of the shared Azure Container Registry (output of shared.bicep).')
param acrName string

@description('Resource group that contains the shared Azure Container Registry.')
param acrResourceGroup string

@description('RabbitMQ user created on first start of the broker.')
param rabbitmqUsername string = 'alpha'

@description('RabbitMQ password. Supplied by the pipeline from a secret variable — never commit it.')
@secure()
@minLength(12)
param rabbitmqPassword string

// ─── Per-environment settings (tuned for minimal Azure cost) ─────────────────
var envConfig = {
  dev: {
    senderMinReplicas:  1
    senderMaxReplicas:  2
    swaggerEnabled:     'true'
    logRetentionInDays: 30  // 30 days is free in Log Analytics
    vnetAddressPrefix:  '10.20.0.0/16'
    acaSubnetPrefix:    '10.20.0.0/23'
  }
  prod: {
    senderMinReplicas:  1
    senderMaxReplicas:  5
    swaggerEnabled:     'false'
    logRetentionInDays: 30  // Keep at 30 days to stay in the free retention tier
    vnetAddressPrefix:  '10.30.0.0/16'
    acaSubnetPrefix:    '10.30.0.0/23'
  }
}
var cfg = envConfig[environmentName]

var tags = {
  environment: environmentName
  project:     projectName
  managedBy:   'bicep'
}

// ─── Modules ──────────────────────────────────────────────────────────────────
module network 'modules/network.bicep' = {
  name: 'network-${environmentName}'
  params: {
    vnetName:        '${projectName}-vnet-${environmentName}'
    location:        location
    addressPrefix:   cfg.vnetAddressPrefix
    acaSubnetPrefix: cfg.acaSubnetPrefix
    tags:            tags
  }
}

module containerApps 'modules/containerApps.bicep' = {
  name: 'containerApps-${environmentName}'
  params: {
    location:           location
    environmentName:    environmentName
    projectName:        projectName
    tags:               tags
    infraSubnetId:      network.outputs.acaSubnetId
    acrName:            acrName
    acrResourceGroup:   acrResourceGroup
    imageTag:           imageTag
    rabbitmqUsername:   rabbitmqUsername
    rabbitmqPassword:   rabbitmqPassword
    senderMinReplicas:  cfg.senderMinReplicas
    senderMaxReplicas:  cfg.senderMaxReplicas
    swaggerEnabled:     cfg.swaggerEnabled
    logRetentionInDays: cfg.logRetentionInDays
  }
}

// ─── Outputs (consumed by the pipeline smoke tests) ──────────────────────────
output senderFqdn   string = containerApps.outputs.senderFqdn
output receiverFqdn string = containerApps.outputs.receiverFqdn
