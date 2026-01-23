// ============================================================================
// ACR Access Module
// Grants Managed Identity permission to PULL images from Azure Container Registry
// 
// Analogy: Adding someone's "face" to ACR's trusted guest list
//          so they can download Docker images without a password
// ============================================================================

// ----------------------------------------------------------------------------
// Parameters
// ----------------------------------------------------------------------------

@description('Azure Container Registry name')
param acrName string

@description('Principal ID (the "face" ID) of the Managed Identity to grant access')
param principalId string

// ----------------------------------------------------------------------------
// Variables - Azure Built-in Role IDs (public Microsoft constants)
// ----------------------------------------------------------------------------

// AcrPull role - can pull images but NOT push/delete
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

// ----------------------------------------------------------------------------
// Reference Existing ACR
// ----------------------------------------------------------------------------

// We don't create a new ACR - we reference the existing one
resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: acrName
}

// ----------------------------------------------------------------------------
// Role Assignment: AcrPull (Read-Only for Images)
// ----------------------------------------------------------------------------

// Grant "AcrPull" role to the Managed Identity
// This role can:
//   ✅ Pull (download) images
//   ✅ List repositories and tags
//   ❌ Cannot push (upload) images
//   ❌ Cannot delete images
//   ❌ Cannot manage ACR settings

resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  // Unique name for this role assignment
  // guid() ensures same inputs = same output (idempotent)
  name: guid(acr.id, principalId, acrPullRoleId)
  
  // This permission applies ONLY to this ACR
  scope: acr
  
  properties: {
    // WHO gets the permission (the container's "face")
    principalId: principalId
    
    // WHAT permission they get (AcrPull = download images only)
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      acrPullRoleId
    )
    
    // TYPE of identity (ServicePrincipal = app/managed identity, not a human)
    principalType: 'ServicePrincipal'
  }
}
