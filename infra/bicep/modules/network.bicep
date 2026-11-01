// ─────────────────────────────────────────────────────────────────────────────
// network.bicep — VNet + subnet for the Container Apps Environment
// A custom VNet is REQUIRED because RabbitMQ is exposed with TCP ingress (AMQP),
// and Container Apps only supports TCP ingress in VNet-integrated environments.
// ─────────────────────────────────────────────────────────────────────────────

param vnetName string
param location string
param tags     object = {}

@description('VNet address space.')
param addressPrefix string = '10.20.0.0/16'

@description('Container Apps infrastructure subnet. Workload-profile environments need at least /27.')
param acaSubnetPrefix string = '10.20.0.0/23'

var acaSubnetName = 'snet-container-apps'

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name:     vnetName
  location: location
  tags:     tags
  properties: {
    addressSpace: {
      addressPrefixes: [addressPrefix]
    }
    subnets: [
      {
        name: acaSubnetName
        properties: {
          addressPrefix: acaSubnetPrefix
          delegations: [
            {
              name: 'container-apps-delegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
    ]
  }
}

resource acaSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: vnet
  name:   acaSubnetName
}

output acaSubnetId string = acaSubnet.id
