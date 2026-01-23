@description('Key Vault name')
param keyVaultName string

@description('Principal ID (the "face" ID) of the Managed Identity to grant access')
param principalId string


resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource secretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  // Unique name for this role assignment
  // guid() ensures same inputs = same output (idempotent)
  name: guid(keyVault.id, principalId, '4633458b-17de-408a-b874-0445c86b69e6')
  
  // This permission applies ONLY to this Key Vault
  scope: keyVault
  
  properties: {
    // WHO gets the permission (the container's "face")
    principalId: principalId
    
    // WHAT permission they get
    // 4633458b-17de-408a-b874-0445c86b69e6 = "Key Vault Secrets User" (read-only)
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '4633458b-17de-408a-b874-0445c86b69e6'
    )
    
    // TYPE of identity (ServicePrincipal = app/managed identity, not a human)
    principalType: 'ServicePrincipal'
  }
}
