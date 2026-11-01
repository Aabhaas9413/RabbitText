// ─────────────────────────────────────────────────────────────────────────────
// containerRegistry.bicep — Azure Container Registry (shared by dev + prod)
// ─────────────────────────────────────────────────────────────────────────────

@description('Globally unique registry name (5-50 alphanumeric characters).')
@minLength(5)
@maxLength(50)
param acrName string

param location string

@description('Basic is enough for a two-environment setup; use Premium for geo-replication / private endpoints.')
@allowed(['Basic', 'Standard', 'Premium'])
param sku string = 'Basic'

param tags object = {}

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name:     acrName
  location: location
  sku: {
    name: sku
  }
  properties: {
    // Admin user is used by Container Apps to pull images. Hardening option:
    // switch to a user-assigned managed identity with AcrPull (requires the
    // pipeline identity to be allowed to create role assignments).
    adminUserEnabled:    true
    publicNetworkAccess: 'Enabled'
  }
  tags: tags
}

output loginServer string = acr.properties.loginServer
output acrName     string = acr.name
