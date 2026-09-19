// ─────────────────────────────────────────────────────────────────────────────
// main.bicep — Mango Platform Azure Infrastructure
// Deploys: Azure Container Registry + Azure Container Apps Environment
// Target scope: Resource Group
// ─────────────────────────────────────────────────────────────────────────────

targetScope = 'resourceGroup'

@description('Short environment name. Used in resource naming.')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Project name prefix for resource naming.')
param projectName string = 'mango'

@description('Container image tag to deploy (e.g. build run number).')
param imageTag string = 'latest'

// ─── Variables ────────────────────────────────────────────────────────────────
var acrName         = '${projectName}acr${environment}'
var envName         = '${projectName}-env-${environment}'
var senderAppName   = '${projectName}-sender-${environment}'
var receiverAppName = '${projectName}-receiver-${environment}'
var rabbitAppName   = '${projectName}-rabbitmq-${environment}'

// ─── Modules ──────────────────────────────────────────────────────────────────
module acr 'modules/containerRegistry.bicep' = {
  name: 'deployACR'
  params: {
    acrName:     acrName
    location:    location
    environment: environment
  }
}

module containerApps 'modules/containerApps.bicep' = {
  name: 'deployContainerApps'
  params: {
    location:       location
    environment:    environment
    envName:        envName
    acrLoginServer: acr.outputs.loginServer
    acrName:        acrName
    projectName:    projectName
    imageTag:       imageTag
    senderAppName:   senderAppName
    receiverAppName: receiverAppName
    rabbitAppName:   rabbitAppName
  }
  dependsOn: [acr]
}

// ─── Outputs ──────────────────────────────────────────────────────────────────
output acrLoginServer    string = acr.outputs.loginServer
output senderFqdn        string = containerApps.outputs.senderFqdn
output receiverFqdn      string = containerApps.outputs.receiverFqdn
