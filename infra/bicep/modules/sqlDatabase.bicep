// ============================================================================
// Azure SQL Database Module
// Creates SQL Server + Database and stores credentials in Key Vault
// ============================================================================


// ----------------------------------------------------------------------------
// Parameters
// ----------------------------------------------------------------------------

@description('The type of environment, this project will only be dev but cam be extended to prod/staging later')
param environmentType string

@description('Resoiurce group location')
param location string

@description('sqlAdminUsername')
param sqlAdminUsername string

@description('sqlAdminPassword')
@secure()
param sqlAdminPassword string

@description('sql db SKU name')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])

param skuName string = 'Basic'

@description('Your local development IP address')
param localDevIpAddress string = '20.164.37.16'

// ============================================================================
// NEW PARAMETER: Key Vault name
// WHY: We need to store SQL credentials in Key Vault so the container can
//      read them at runtime using Managed Identity. This avoids passing
//      passwords through Bicep outputs (which would be visible in logs).
// ============================================================================
@description('Key Vault name to store SQL credentials')
param keyVaultName string

// azure  sql db vars


var sqlServerName = 'adventureworks-sql-server-${environmentType}'
var sqlDBName = 'adventureworks-sql-db-${environmentType}'

var skuConfig = {
  Basic: {
    name: 'Basic'
    tier: 'Basic'
    capacity : 5
  }
  Standard: {
    name : 'Standard'
    tier : 'Standard'
    capicity : 10
  }

  Premium : {
    name : 'Premium'
    tier : 'Premium'
    capacity : 125
  }
}


// azure sql db resources

resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {

  name : sqlServerName
  location: location
  properties: {
    administratorLogin: sqlAdminUsername
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
    minimalTlsVersion: '1.2'

  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  parent : sqlServer
  name : sqlDBName
  location: location
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648
    readScale: 'Disabled'
    zoneRedundant: false
  }
  sku: {
    name: skuConfig[skuName].name
    tier: skuConfig[skuName].tier
    capacity: skuConfig[skuName].capacity
  }
}

resource allowAzureServices 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = {

  parent : sqlServer
  name : 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
}
}

resource allowLocalDevelopment 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = {
  parent: sqlServer
  name: 'AllowLocalDevelopment'
  properties: {
    startIpAddress: localDevIpAddress
    endIpAddress: localDevIpAddress
  }
}

// ============================================================================
// NEW SECTION: Store credentials in Key Vault
// WHY: Instead of passing passwords through Bicep outputs (insecure!),
//      we store them in Key Vault. The container will use its Managed Identity
//      to read these secrets at runtime. This means:
//      - No passwords in deployment logs
//      - No passwords in Bicep outputs
//      - Container reads secrets only when it needs them
// ============================================================================

// Reference the existing Key Vault (created by keyVault.bicep)
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Store SQL admin password in Key Vault
resource sqlPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'sql-admin-password'
  properties: {
    value: sqlAdminPassword
  }
}

// Store SQL admin username in Key Vault (for convenience)
resource sqlUsernameSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'sql-admin-username'
  properties: {
    value: sqlAdminUsername
  }
}

// ============================================================================
// Outputs
// ============================================================================

// azure sql db outputs

@description('SQL Server fully qualified domain name')
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName

@description('SQL Database name')
output sqlDatabaseName string = sqlDatabase.name

@description('SQL Server name')
output sqlServerName string = sqlServer.name

// ============================================================================
// OLD OUTPUT (COMMENTED OUT):
// WHY REMOVED: This connection string contained a placeholder for the password.
//              In the old approach, main.bicep would build the full connection
//              string with the actual password - which would appear in deployment
//              logs. Now the container builds this string at runtime by reading
//              credentials from Key Vault.
// ============================================================================
// @description('Connection string (without password - add at runtime)')
// output connectionString string = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Initial Catalog=${sqlDBName};Persist Security Info=False;User ID=${sqlAdminUsername};Password={your_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
