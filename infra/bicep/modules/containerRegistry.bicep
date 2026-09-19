// ─────────────────────────────────────────────────────────────────────────────
// containerRegistry.bicep — Azure Container Registry
// ─────────────────────────────────────────────────────────────────────────────

param acrName     string
param location    string
param environment string

@description('SKU tier: Basic for dev, Standard/Premium for production.')
param sku string = environment == 'prod' ? 'Standard' : 'Basic'

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name:     acrName
  location: location
  sku: {
    name: sku
  }
  properties: {
    adminUserEnabled:        true   // Required for Container Apps pull; disable for prod with managed identity
    publicNetworkAccess:     'Enabled'
    zoneRedundancy:          environment == 'prod' ? 'Enabled' : 'Disabled'
  }
  tags: {
    environment: environment
    project:     'mango'
    managedBy:   'bicep'
  }
}

output loginServer string = acr.properties.loginServer
output acrName     string = acr.name
