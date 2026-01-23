// azure openai module
// creating an azure openai 

//parameters

@description('Env name')
param environmentType string

@description('Key Vault name to store secrets')
param keyVaultName string

@description('Azure region')
param location string = resourceGroup().location

@description('GPT-4 deployment capacity (tokens per min)')
@minValue(1)
@maxValue(120)
param capacity int = 10

@description('GPT 4 model version')
@allowed([
  'gpt-4'
  'gpt-4-32k'
  'gpt-4o'
])
param modelName string = 'gpt-4'

//variables

var openaiAccountName = 'adv-openai-${environmentType}-${uniqueString(resourceGroup().id)}'
var deploymentName = 'gpt-4-deployment'

// Model version mappings
var modelVersions = {
  'gpt-4': '0613'
  'gpt-4-32k': '0613'
  'gpt-4o': '2024-05-13'
}


//resources

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource openaiAccount 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: openaiAccountName
  location: location
  kind: 'OpenAI'
  sku: {
    name: 'S0'  // Standard tier (only option for OpenAI)
  }
  properties: {
    customSubDomainName: openaiAccountName
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

// GPT-4 Model Deployment
resource gpt4Deployment 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = {
  parent: openaiAccount
  name: deploymentName
  sku: {
    name: 'Standard'
    capacity: capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersions[modelName]
    }
    raiPolicyName: 'Microsoft.Default'  // Content filtering policy
  }
}

resource keyVaultSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'openai-api-key'
  parent: keyVault
  properties: {
    value: openaiAccount.listKeys().key1
  }
}

// Store OpenAI endpoint in Key Vault (for container to read at runtime)
resource openaiEndpointSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'openai-endpoint'
  parent: keyVault
  properties: {
    value: openaiAccount.properties.endpoint
  }
}

// Store OpenAI deployment name in Key Vault (for container to read at runtime)
resource openaiDeploymentSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'openai-deployment-name'
  parent: keyVault
  properties: {
    value: gpt4Deployment.name
  }
}

// ----------------------------------------------------------------------------
// Outputs
// ----------------------------------------------------------------------------

@description('Azure OpenAI endpoint URL')
output endpoint string = openaiAccount.properties.endpoint

@description('Azure OpenAI account name')
output accountName string = openaiAccount.name

@description('GPT-4 deployment name (use this in your code)')
output deploymentName string = gpt4Deployment.name


