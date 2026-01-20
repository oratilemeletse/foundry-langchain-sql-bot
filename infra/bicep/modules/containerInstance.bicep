// ============================================================================
// Azure Container Instance Module
// Creates a serverless container to run the FastAPI chatbot application
// ============================================================================

// ----------------------------------------------------------------------------
// Parameters


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

@description('ACR admin password')
@secure()
param acrPassword string

@description('Azure SQL connection string')
@secure()
param sqlConnectionString string

@description('Azure OpenAI endpoint URL')
param openaiEndpoint string

@description('Azure OpenAI API key')
@secure()
param openaiApiKey string

@description('Azure OpenAI deployment name')
param openaiDeploymentName string

// ----------------------------------------------------------------------------
// Variables
// ----------------------------------------------------------------------------

var containerGroupName = 'adventureworks-chatbot-${environmentType}'
var containerName = 'chatbot-api'
var dnsLabel = 'adventureworks-chatbot-${environmentType}'

//resources

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: containerGroupName
  location: location
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
          
          // Environment variables (secrets passed securely)
          environmentVariables: [
            {
              name: 'AZURE_SQL_CONNECTION_STRING'
              secureValue: sqlConnectionString    // Secure: won't show in logs
            }
            {
              name: 'AZURE_OPENAI_ENDPOINT'
              value: openaiEndpoint               // Not secret: just a URL
            }
            {
              name: 'AZURE_OPENAI_API_KEY'
              secureValue: openaiApiKey           // Secure: won't show in logs
            }
            {
              name: 'AZURE_OPENAI_DEPLOYMENT'
              value: openaiDeploymentName         // Not secret: just a name
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

// Outputs
// ----------------------------------------------------------------------------

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
