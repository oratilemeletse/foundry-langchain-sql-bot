// ============================================================================
// Azure Container Instance Module
// Creates a serverless container to run the FastAPI chatbot application
// 
// UPDATED FOR MANAGED IDENTITY:
// - Container now has a Managed Identity (its "face")
// - Container reads secrets from Key Vault at RUNTIME (not deployment time)
// - No more secrets passed through Bicep parameters (except ACR password via Key Vault)
// ============================================================================

// ----------------------------------------------------------------------------
// Parameters
// ----------------------------------------------------------------------------

@description('Env name')
param environmentType string

@description('Azure region')
param location string = resourceGroup().location

@description('Container image to deploy (e.g., adventureworksacrdev.azurecr.io/chatbot-api:latest)')
param containerImage string

@description('CPU cores for the container')
@minValue(1)
@maxValue(4)
param cpu int = 1

@description('Memory in GB for the container')
@minValue(1)
@maxValue(16)
param memoryInGb int = 2

@description('Port the application listens on')
param port int = 8000

// Azure Container Registry credentials (from container-registry.bicep outputs)
@description('ACR login server (e.g., adventureworksacrdev.azurecr.io)')
param acrLoginServer string

@description('ACR admin username')
param acrUsername string

// ============================================================================
// ACR Password - Still needed but now passed securely via Key Vault reference
// WHY: ACI doesn't support System-Assigned Managed Identity for ACR pull.
//      So we still need the password, BUT it now comes from Key Vault using
//      getSecret() in main.bicep - never visible in deployment logs!
// ============================================================================
@description('ACR admin password')
@secure()
param acrPassword string

// ============================================================================
// OLD PARAMETERS (COMMENTED OUT):
// WHY REMOVED: These secrets were passed through Bicep, which means they
//              appeared in deployment logs. Now the container reads them
//              from Key Vault at runtime using its Managed Identity.
// ============================================================================

// OLD: @description('Azure SQL connection string')
// OLD: @secure()
// OLD: param sqlConnectionString string
// 
// OLD: @description('Azure OpenAI API key')
// OLD: @secure()
// OLD: param openaiApiKey string

// ============================================================================
// NEW PARAMETERS: Non-secret configuration
// WHY: The container needs to know WHERE to connect (server names, endpoints)
//      but not the SECRETS (passwords, API keys). Secrets come from Key Vault.
// ============================================================================

@description('Azure OpenAI endpoint URL')
param openaiEndpoint string

@description('Azure OpenAI deployment name')
param openaiDeploymentName string

@description('SQL Server FQDN (e.g., adventureworks-sql-server-dev.database.windows.net)')
param sqlServerFqdn string

@description('SQL Database name')
param sqlDatabaseName string

// ============================================================================
// NEW PARAMETER: Key Vault URI
// WHY: The container needs to know where Key Vault is so it can read secrets
//      at runtime using its Managed Identity.
// ============================================================================
@description('Key Vault URI for reading secrets at runtime')
param keyVaultUri string

// ----------------------------------------------------------------------------
// Variables
// ----------------------------------------------------------------------------

var containerGroupName = 'adventureworks-chatbot-${environmentType}'
var containerName = 'chatbot-api'
var dnsLabel = 'adv-chatbot-${environmentType}-${uniqueString(resourceGroup().id)}'

// ============================================================================
// Container Group Resource
// ============================================================================

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: containerGroupName
  location: location
  
  // ==========================================================================
  // NEW: Managed Identity
  // WHY: This gives the container its own "face" (identity) that Azure trusts.
  //      With this identity, the container can:
  //      1. Authenticate to Key Vault to read secrets
  //      2. No passwords needed for Key Vault access!
  // 
  // How it works:
  //      - Azure creates a unique identity for this container
  //      - We output the principalId (the identity's "face")
  //      - keyVaultAccess.bicep grants this identity permission to read secrets
  //      - At runtime, the container shows its "face" to Key Vault
  // ==========================================================================
  identity: {
    type: 'SystemAssigned'
  }
  
  properties: {
    
    // --- Container Configuration ---
    containers: [
      {
        name: containerName
        properties: {
          
          // Image from Azure Container Registry
          image: containerImage
          
          // Resource allocation
          resources: {
            requests: {
              cpu: cpu
              memoryInGB: memoryInGb
            }
            // Limits same as requests (no bursting)
            limits: {
              cpu: cpu
              memoryInGB: memoryInGb
            }
          }
          // Port configuration
          ports: [
            {
              port: port
              protocol: 'TCP'
            }
          ]
          
          // ================================================================
          // Environment Variables - UPDATED FOR MANAGED IDENTITY
          // ================================================================
          environmentVariables: [
            // ============================================================
            // OLD WAY (COMMENTED OUT):
            // These passed secrets directly as environment variables.
            // Problem: Secrets were passed through Bicep = visible in logs!
            // ============================================================
            // OLD: {
            // OLD:   name: 'AZURE_SQL_CONNECTION_STRING'
            // OLD:   secureValue: sqlConnectionString
            // OLD: }
            // OLD: {
            // OLD:   name: 'AZURE_OPENAI_API_KEY'
            // OLD:   secureValue: openaiApiKey
            // OLD: }
            
            // ============================================================
            // NEW WAY: Pass KEY_VAULT_URI instead of secrets
            // The Python app will use Managed Identity to read secrets
            // from Key Vault at runtime.
            // ============================================================
            {
              name: 'KEY_VAULT_URI'
              value: keyVaultUri  // App reads secrets from here at runtime
            }
            
            // ============================================================
            // NON-SECRET CONFIG: These are safe to pass directly
            // (no passwords or API keys - just names and URLs)
            // ============================================================
            {
              name: 'AZURE_OPENAI_ENDPOINT'
              value: openaiEndpoint
            }
            {
              name: 'AZURE_OPENAI_DEPLOYMENT'
              value: openaiDeploymentName
            }
            {
              name: 'SQL_SERVER'
              value: sqlServerFqdn  // Just the server name, not password
            }
            {
              name: 'SQL_DATABASE'
              value: sqlDatabaseName
            }
            {
              name: 'ENVIRONMENT'
              value: environmentType
            }
            {
              name: 'PORT'
              value: string(port)
            }
          ]
          
          // Health probe: checks if container is healthy
          livenessProbe: {
            httpGet: {
              path: '/health'
              port: port
              scheme: 'HTTP'
            }
            initialDelaySeconds: 30     // Wait 30s before first check
            periodSeconds: 10           // Check every 10s
            failureThreshold: 3         // Restart after 3 failures
            successThreshold: 1         // 1 success = healthy
            timeoutSeconds: 5           // Timeout per check
          }
          // Readiness probe: checks if container is ready to receive traffic
          readinessProbe: {
            httpGet: {
              path: '/health'
              port: port
              scheme: 'HTTP'
            }
            initialDelaySeconds: 10     // Wait 10s before first check
            periodSeconds: 5            // Check every 5s
            failureThreshold: 3         // Mark unhealthy after 3 failures
            successThreshold: 1         // 1 success = ready
            timeoutSeconds: 3           // Timeout per check
          }
        }
      }
    ]
    
    // --- Operating System ---
    osType: 'Linux'
    
    // --- Restart Policy ---
    // Always: restart on exit (production)
    // OnFailure: restart only on non-zero exit code
    // Never: don't restart (for batch jobs)
    restartPolicy: 'Always'
      // --- Networking ---
    ipAddress: {
      type: 'Public'                    // Assigns public IP
      ports: [
        {
          port: port
          protocol: 'TCP'
        }
      ]
      dnsNameLabel: dnsLabel            // Creates: adventureworks-chatbot-dev.eastus.azurecontainer.io
    }
    
    // --- Image Registry Credentials ---
    imageRegistryCredentials: [
      {
        server: acrLoginServer
        username: acrUsername
        password: acrPassword
      }
    ]
  }
  tags: {
    environment: environmentType
    project: 'adventureworks-chatbot'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Container group name')
output containerGroupName string = containerGroup.name

@description('Public IP address')
output ipAddress string = containerGroup.properties.ipAddress.ip

@description('Fully qualified domain name')
output fqdn string = containerGroup.properties.ipAddress.fqdn

@description('Application URL')
output applicationUrl string = 'http://${containerGroup.properties.ipAddress.fqdn}:${port}'

@description('Health check URL')
output healthCheckUrl string = 'http://${containerGroup.properties.ipAddress.fqdn}:${port}/health'

// ============================================================================
// NEW OUTPUT: Principal ID (the container's "face")
// WHY: We need to output this so main.bicep can pass it to keyVaultAccess.bicep
//      which grants this identity permission to read secrets from Key Vault.
// 
// Flow:
//   1. Container is created with Managed Identity
//   2. This output gives us the identity's ID
//   3. keyVaultAccess.bicep uses this ID to grant Key Vault access
//   4. At runtime, container uses this identity to read secrets
// ============================================================================
@description('Principal ID of the Managed Identity (needed to grant Key Vault access)')
output principalId string = containerGroup.identity.principalId
