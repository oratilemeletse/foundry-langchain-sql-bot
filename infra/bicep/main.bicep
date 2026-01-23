// ============================================================================
// Main Bicep Orchestration File
// Deploys all infrastructure for AdventureWorks SQL Agent Chatbot
//
// SECURITY: Uses Managed Identity - secrets stored in Key Vault, not in outputs
// ============================================================================

targetScope = 'resourceGroup'

// ============================================================================
// Parameters
// ============================================================================

@description('Environment type')
@allowed(['dev', 'staging', 'prod'])
param environmentType string = 'dev'

@description('Azure region')
param location string = resourceGroup().location

@description('Your Azure AD Object ID (run: az ad signed-in-user show --query id -o tsv)')
param adminObjectId string

@description('SQL Server admin username')
param sqlAdminUsername string

@description('SQL Server admin password')
@secure()
param sqlAdminPassword string

@description('Your local IP address for SQL firewall')
param localDevIpAddress string

@description('Container image to deploy')
param containerImage string = 'adventureworksacr${environmentType}${uniqueString(resourceGroup().id)}.azurecr.io/chatbot-api:latest'

module keyVault 'modules/keyVault.bicep' = {
  name: 'keyVault-deployment'
  params: {
    environmentType: environmentType
    location: location
    adminObjectId: adminObjectId
  }
}

// ----------------------------------------------------------------------------
// Module 2: Azure OpenAI (stores API key in Key Vault)
// ----------------------------------------------------------------------------

module openai 'modules/openAI.bicep' = {
  name: 'openai-deployment'
  params: {
    environmentType: environmentType
    location: location
    keyVaultName: keyVault.outputs.keyVaultName
  }
  // NOTE: dependsOn not needed - Bicep auto-infers from keyVault.outputs reference
}

// ----------------------------------------------------------------------------
// Module 3: SQL Database
// UPDATED: Now stores credentials in Key Vault
// ----------------------------------------------------------------------------

module sqlDatabase 'modules/sqlDatabase.bicep' = {
  name: 'sql-deployment'
  params: {
    environmentType: environmentType
    location: location
    sqlAdminUsername: sqlAdminUsername
    sqlAdminPassword: sqlAdminPassword
    localDevIpAddress: localDevIpAddress
    // ========================================================================
    // NEW: Pass Key Vault name so SQL module can store credentials there
    // WHY: The SQL password needs to be in Key Vault so the container can
    //      read it at runtime using Managed Identity.
    // ========================================================================
    keyVaultName: keyVault.outputs.keyVaultName
  }
  // NOTE: dependsOn not needed - Bicep auto-infers from keyVault.outputs reference
}

module containerRegistry 'modules/containerRegistry.bicep' = {
  name: 'acr-deployment'
  params: {
    environmentType: environmentType
    location: location
    keyVaultName: keyVault.outputs.keyVaultName
  }
  // NOTE: dependsOn not needed - Bicep auto-infers from keyVault.outputs reference
}

// ============================================================================
// Reference Key Vault to get secrets securely
// WHY: We use getSecret() to pass the ACR password to the container.
//      This is MUCH more secure than outputting the password because:
//      - getSecret() retrieves the value at deployment time
//      - The value is passed directly to the container module
//      - It NEVER appears in deployment logs or outputs!
// ============================================================================
resource keyVaultRef 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVault.outputs.keyVaultName
}

// ----------------------------------------------------------------------------
// Module 5: Container Instance (runs the chatbot - needs everything else)
// UPDATED: Uses Managed Identity and Key Vault for secrets
// ----------------------------------------------------------------------------

module containerInstance 'modules/containerInstance.bicep' = {
  name: 'aci-deployment'
  params: {
    environmentType: environmentType
    location: location
    containerImage: containerImage
    acrLoginServer: containerRegistry.outputs.loginServer
    acrUsername: containerRegistry.outputs.adminUsername
    
    // ========================================================================
    // UPDATED: ACR password now comes from Key Vault using getSecret()
    // 
    // OLD WAY (insecure):
    //   acrPassword: containerRegistry.outputs.adminPassword
    //   Problem: Password visible in deployment logs!
    //
    // NEW WAY (secure):
    //   acrPassword: keyVaultRef.getSecret('acr-admin-password')
    //   - Password is fetched from Key Vault at deployment time
    //   - Never appears in logs or outputs
    // ========================================================================
    acrPassword: keyVaultRef.getSecret('acr-admin-password')
    
    // ========================================================================
    // UPDATED: Pass Key Vault URI instead of secrets
    // 
    // OLD WAY (insecure):
    //   sqlConnectionString: 'Server=...Password=${sqlAdminPassword}...'
    //   openaiApiKey: openai.outputs.apiKey
    //   Problem: Secrets visible in deployment logs!
    //
    // NEW WAY (secure):
    //   keyVaultUri: keyVault.outputs.keyVaultUri
    //   - Container uses Managed Identity to read secrets at runtime
    //   - Secrets never pass through Bicep
    // ========================================================================
    keyVaultUri: keyVault.outputs.keyVaultUri
    
    // ========================================================================
    // NON-SECRET CONFIG: These are safe to pass (no passwords/keys)
    // ========================================================================
    openaiEndpoint: openai.outputs.endpoint
    openaiDeploymentName: openai.outputs.deploymentName
    sqlServerFqdn: sqlDatabase.outputs.sqlServerFqdn
    sqlDatabaseName: sqlDatabase.outputs.sqlDatabaseName
    
    // ========================================================================
    // OLD PARAMETERS (REMOVED):
    // These are no longer needed because secrets come from Key Vault
    // ========================================================================
    // OLD: sqlConnectionString: 'Server=tcp:${sqlDatabase.outputs.sqlServerFqdn}...'
    // OLD: openaiApiKey: openai.outputs.apiKey
  }
  // NOTE: dependsOn not needed - Bicep auto-infers from all the .outputs references above
}

// ============================================================================
// NEW MODULE: Grant Container access to Key Vault
// WHY: The container has a Managed Identity (its "face"), but Key Vault
//      doesn't automatically trust it. This module adds the container's
//      identity to Key Vault's trusted list so it can read secrets.
// 
// Flow:
//   1. Container is created with Managed Identity → outputs principalId
//   2. This module grants that principalId "Key Vault Secrets User" role
//   3. At runtime, container can read secrets from Key Vault
// ============================================================================
module keyVaultAccess 'modules/keyVaultAccess.bicep' = {
  name: 'keyVaultAccess-deployment'
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    principalId: containerInstance.outputs.principalId
  }
  // NOTE: dependsOn not needed - Bicep auto-infers from output references
}

// ----------------------------------------------------------------------------
// Outputs
// ----------------------------------------------------------------------------

@description('Key Vault name')
output keyVaultName string = keyVault.outputs.keyVaultName

@description('Key Vault URI')
output keyVaultUri string = keyVault.outputs.keyVaultUri

@description('OpenAI endpoint')
output openaiEndpoint string = openai.outputs.endpoint

@description('OpenAI deployment name')
output openaiDeploymentName string = openai.outputs.deploymentName

@description('SQL Server FQDN')
output sqlServerFqdn string = sqlDatabase.outputs.sqlServerFqdn

@description('SQL Database name')
output sqlDatabaseName string = sqlDatabase.outputs.sqlDatabaseName

@description('Container Registry login server')
output acrLoginServer string = containerRegistry.outputs.loginServer

@description('Chatbot API URL')
output chatbotUrl string = containerInstance.outputs.applicationUrl

// ============================================================================
// SECURITY NOTE: What's NOT in outputs (and why)
// 
// These are intentionally NOT output because they're secrets:
//   - openaiApiKey (stored in Key Vault as 'openai-api-key')
//   - sqlAdminPassword (stored in Key Vault as 'sql-admin-password')
//   - acrAdminPassword (stored in Key Vault as 'acr-admin-password')
//
// The container reads these from Key Vault at runtime using Managed Identity.
// This means: NO SECRETS IN DEPLOYMENT LOGS! 🎉
// ============================================================================
