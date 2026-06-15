// lb-vm2.bicep — Standard Load Balancer + VM-2 (high-availability application tier)
// Usage:
//   az deployment group create \
//     --resource-group ltmsa-security-rg \
//     --template-file lb-vm2.bicep \
//     --parameters adminPassword="<password>" subnetId="<web-snet-id>"
targetScope = 'resourceGroup'

@description('Deployment location')
param location string = 'koreacentral'

@description('Resource prefix')
param prefix string = 'ltmsa'

@description('VM admin username')
param adminUsername string = 'azureuser'

@description('VM admin password')
@secure()
param adminPassword string

@description('Existing web subnet ID to attach VM-2 NIC')
param subnetId string

@description('VM size — Standard_D2s_v3 available in Korea Central')
param vmSize string = 'Standard_D2s_v3'

var appPort = 3000
var lbFrontendPort = 80
var vm2Name = '${prefix}-demo-vm-2'

var commonTags = {
  Project: 'LTM-SA-Workshop'
  Module: 'Module7-HA'
  ManagedBy: 'Bicep'
  Owner: 'inhwan.jung@outlook.kr'
}

// ── Load Balancer Public IP ──────────────────────────────────────────
resource lbPip 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: '${prefix}-lb-pip'
  location: location
  tags: commonTags
  sku: { name: 'Standard' }
  zones: ['1', '2', '3']   // Zone-redundant: survives single-zone failure (matches Bastion PIP config)
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: '${prefix}-workshop-lb'
    }
  }
}

// ── Standard Load Balancer ───────────────────────────────────────────
resource lb 'Microsoft.Network/loadBalancers@2023-04-01' = {
  name: '${prefix}-lb'
  location: location
  tags: commonTags
  sku: { name: 'Standard' }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'lb-frontend'
        properties: {
          publicIPAddress: { id: lbPip.id }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'lb-backend'
      }
    ]
    probes: [
      {
        name: 'http-health'
        properties: {
          protocol: 'Http'
          port: appPort
          requestPath: '/health'
          intervalInSeconds: 15
          numberOfProbes: 2
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'app-rule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', '${prefix}-lb', 'lb-frontend')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', '${prefix}-lb', 'lb-backend')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', '${prefix}-lb', 'http-health')
          }
          protocol: 'Tcp'
          frontendPort: lbFrontendPort
          backendPort: appPort
          idleTimeoutInMinutes: 4
          enableFloatingIP: false
          // disableOutboundSnat defaults to false — do NOT use outboundRules when VMs have instance-level public IPs
        }
      }
    ]
  }
}

// ── VM-2 NIC (attached to LB backend pool) ──────────────────────────
resource nic2 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: '${vm2Name}-nic'
  location: location
  tags: commonTags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: subnetId }
          privateIPAllocationMethod: 'Dynamic'
          loadBalancerBackendAddressPools: [
            {
              id: '${lb.id}/backendAddressPools/lb-backend'
            }
          ]
        }
      }
    ]
  }
}

// ── VM-2 ─────────────────────────────────────────────────────────────
resource vm2 'Microsoft.Compute/virtualMachines@2023-07-01' = {
  name: vm2Name
  location: location
  tags: commonTags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vm2Name
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'StandardSSD_LRS' }
        deleteOption: 'Delete'
      }
    }
    networkProfile: {
      networkInterfaces: [
        { id: nic2.id, properties: { deleteOption: 'Delete' } }
      ]
    }
  }
}

// ── Outputs ──────────────────────────────────────────────────────────
output lbPublicIp string = lbPip.properties.ipAddress
output lbFqdn string = lbPip.properties.dnsSettings.fqdn
output lbName string = lb.name
output backendPoolId string = '${lb.id}/backendAddressPools/lb-backend'
output vm2Name string = vm2.name
output vm2PrivateIp string = nic2.properties.ipConfigurations[0].properties.privateIPAddress
