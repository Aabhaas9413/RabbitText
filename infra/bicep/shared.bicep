// ─────────────────────────────────────────────────────────────────────────────
// shared.bicep — Resources shared by every environment
// Deployed by the pipeline's Build stage into the shared resource group
// (default: alpha-rg-shared) BEFORE images are pushed.
// ─────────────────────────────────────────────────────────────────────────────

targetScope = 'resourceGroup'

@description('Azure region for shared resources.')
param location string = resourceGroup().location

@description('Project name prefix for resource naming.')
param projectName string = 'alpha'

@description('ACR SKU.')
@allowed(['Basic', 'Standard', 'Premium'])
param acrSku string = 'Basic'

// ACR names must be globally unique. uniqueString() makes the name stable for
// this subscription + resource group, so re-deployments are idempotent.
var acrName = take('${projectName}acr${uniqueString(resourceGroup().id)}', 50)

module acr 'modules/containerRegistry.bicep' = {
  name: 'sharedAcr'
  params: {
    acrName:  acrName
    location: location
    sku:      acrSku
    tags: {
      project:   projectName
      scope:     'shared'
      managedBy: 'bicep'
    }
  }
}

output acrName        string = acr.outputs.acrName
output acrLoginServer string = acr.outputs.loginServer
