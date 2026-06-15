// main.bicep — LTM SA Workshop 3-tier 아키텍처
// 사용법: az deployment group create --resource-group <RG> --template-file main.bicep --parameters environment=dev
targetScope = 'resourceGroup'

@description('배포 환경 (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('배포 지역')
param location string = resourceGroup().location

@description('리소스 접두사')
param prefix string = 'ltmsa'

var commonTags = {
  Environment: environment
  Project: 'LTM-SA-Workshop'
  ManagedBy: 'Bicep'
  Owner: 'inhwan.jung@outlook.kr'
}

// VNet with 3-tier subnets
resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: '${prefix}-${environment}-vnet'
  location: location
  tags: commonTags
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/16']
    }
    subnets: [
      {
        name: 'web-snet'
        properties: { addressPrefix: '10.0.1.0/24' }
      }
      {
        name: 'app-snet'
        properties: { addressPrefix: '10.0.2.0/24' }
      }
      {
        name: 'db-snet'
        properties: { addressPrefix: '10.0.3.0/24' }
      }
    ]
  }
}

// Log Analytics Workspace
resource law 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${prefix}-${environment}-law'
  location: location
  tags: commonTags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Key Vault (RBAC-based authorization)
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: '${prefix}-kv-${take(uniqueString(resourceGroup().id), 8)}'
  location: location
  tags: commonTags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    // enablePurgeProtection: false — 한 번 true로 설정된 KV는 false로 변경 불가
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output lawId string = law.id
output lawName string = law.name
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
