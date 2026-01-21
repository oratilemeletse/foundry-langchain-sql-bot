// azuer container registry module params
// // Creates a private Docker image registry for the chatbot application



// Parameters
@description('The type of environment, this project will only be dev but cam be extended to prod/staging later')
param environmentType string

@description('Azure region')
param location string = resourceGroup().location


@description('ACR SKU name')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param sku string = 'Basic'

@description('Key Vault name to store secrets')
param keyVaultName string


// ----------------------------------------------------------------------------
// Variables
// ----------------------------------------------------------------------------

// ACR names must be globally unique, lowercase, alphanumeric only (no hyphens)
var acrName = 'adventureworksacr${environmentType}${uniqueString(resourceGroup().id)}'


//resources
// Reference existing Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: sku
  }
  properties: {
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
    zoneRedundancy: 'Disabled'
    policies: {
      retentionPolicy:{
        status: 'disabled'
      }
      trustPolicy: {
        status: 'disabled'
      }
    }
  }
}

// Store ACR password securely in Key Vault
resource acrPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'acr-admin-password'
  properties: {
    value: containerRegistry.listCredentials().passwords[0].value
  }
}
// ----------------------------------------------------------------------------
// Outputs
// ----------------------------------------------------------------------------

@description('Container Registry login server (e.g., adventureworksacrdev.azurecr.io)')
output loginServer string = containerRegistry.properties.loginServer

@description('Container Registry name')
output name string = containerRegistry.name

@description('Container Registry resource ID')
output id string = containerRegistry.id

@description('Admin username (same as registry name)')
output adminUsername string = containerRegistry.name

