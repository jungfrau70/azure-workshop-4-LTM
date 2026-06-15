# Azure SA Workshop : Command Reference

---

## Common Variable Setup (Run before starting any module)

```bash
LOCATION="koreacentral"
PREFIX="ltmsa"
RG_GOV="${PREFIX}-governance-rg"
RG_NET="${PREFIX}-network-rg"
RG_SEC="${PREFIX}-security-rg"
RG_OPS="${PREFIX}-ops-rg"
SUB_ID=$(az account show --query id -o tsv)
```

---

## Pre-work: Management Group + Korea Region Restriction Policy

### Create

```bash
# Create MG
az account management-group create \
  --name "LTM-Corp" \
  --display-name "LTM Corporation"

# Move subscription to LTM-Corp MG
az account management-group subscription add \
  --name "LTM-Corp" \
  --subscription "$SUB_ID"

# Assign Korea region restriction policy (az rest method ??workaround for CLI bug)
az rest \
  --method PUT \
  --uri "https://management.azure.com/providers/Microsoft.Management/managementGroups/LTM-Corp/providers/Microsoft.Authorization/policyAssignments/allow-korea-only?api-version=2023-04-01" \
  --body '{
    "properties": {
      "displayName": "Allow Korea regions only",
      "policyDefinitionId": "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c",
      "parameters": {
        "listOfAllowedLocations": {
          "value": ["koreacentral", "koreasouth"]
        }
      },
      "enforcementMode": "Default"
    }
  }'
```

### Verify

```bash
# MG structure
az account management-group show \
  --name "LTM-Corp" --expand --recurse \
  --query "{MG:displayName, Subscription:children[0].displayName}" \
  --output table

# MG policy list
az rest \
  --method GET \
  --uri "https://management.azure.com/providers/Microsoft.Management/managementGroups/LTM-Corp/providers/Microsoft.Authorization/policyAssignments?api-version=2023-04-01&\$filter=atScope()" \
  --query "value[].{Name:name, DisplayName:properties.displayName, Mode:properties.enforcementMode}" \
  --output table
```

---

## Module 1: Governance & Landing Zone

### Create

```bash
# 1. Create governance resource group
az group create \
  --name $RG_GOV \
  --location $LOCATION \
  --tags Environment=Lab Project=LTM-SA-Workshop Owner=inhwan.jung@outlook.kr

# 2. Assign Owner tag required policy (DoNotEnforce = Audit mode)
#    Note: az policy assignment create produces MissingSubscription error after MG migration
#          Using az rest as workaround
az rest \
  --method PUT \
  --uri "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${RG_GOV}/providers/Microsoft.Authorization/policyAssignments/require-owner-tag?api-version=2023-04-01" \
  --body '{
    "properties": {
      "displayName": "Require Owner tag on all resources",
      "policyDefinitionId": "/providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99",
      "parameters": { "tagName": { "value": "Owner" } },
      "enforcementMode": "DoNotEnforce"
    }
  }'

# 3. Resource Lock (prevent deletion)
az lock create \
  --name "DoNotDelete-GOV-RG" \
  --resource-group $RG_GOV \
  --lock-type CanNotDelete \
  --notes "Production governance resources - do not delete"
```

### Verify

```bash
# [1] Governance RG
az group show --name $RG_GOV \
  --query "{Name:name, Location:location, State:properties.provisioningState}" \
  --output table

# [2] RG policy assignments
az policy assignment list \
  --resource-group $RG_GOV \
  --query "[].{Name:name, DisplayName:displayName, Mode:enforcementMode}" \
  --output table

# [3] Resource Lock
az lock list \
  --resource-group $RG_GOV \
  --query "[].{Name:name, Type:level, Notes:notes}" \
  --output table

# [4] Verify everything at once
echo "=== MG Structure ===" && \
az account management-group show --name "LTM-Corp" --expand --recurse \
  --query "{MG:displayName, Subscription:children[0].displayName}" --output table && \
echo "=== MG Policy ===" && \
az rest --method GET \
  --uri "https://management.azure.com/providers/Microsoft.Management/managementGroups/LTM-Corp/providers/Microsoft.Authorization/policyAssignments?api-version=2023-04-01&\$filter=atScope()" \
  --query "value[].{Name:name, DisplayName:properties.displayName, Mode:properties.enforcementMode}" --output table && \
echo "=== Governance RG ===" && \
az group show --name $RG_GOV \
  --query "{Name:name, Location:location, State:properties.provisioningState}" --output table && \
echo "=== RG Policy ===" && \
az policy assignment list --resource-group $RG_GOV \
  --query "[].{Name:name, DisplayName:displayName, Mode:enforcementMode}" --output table && \
echo "=== Resource Lock ===" && \
az lock list --resource-group $RG_GOV \
  --query "[].{Name:name, Type:level, Notes:notes}" --output table
```

---

## Module 2: Network Architecture (Hub-Spoke)

```
Hub VNet (ltmsa-hub-vnet, 10.0.0.0/16)     Spoke VNet (ltmsa-spoke-vnet, 10.1.0.0/16)
  ?쒋?? AzureBastionSubnet (10.0.0.0/26)   ??  ?붴?? web-snet (10.1.1.0/24)
  ?붴?? mgmt-snet (10.0.1.0/24)
```

### Create

```bash
# Environment variables
RG="ltmsa-security-rg"
LOCATION="koreacentral"
HUB_VNET="ltmsa-hub-vnet"
SPOKE_VNET="ltmsa-spoke-vnet"

# 1. Hub VNet + AzureBastionSubnet + mgmt-snet
az network vnet create \
  --name $HUB_VNET --resource-group $RG \
  --address-prefix 10.0.0.0/16 \
  --subnet-name AzureBastionSubnet --subnet-prefix 10.0.0.0/26

# mgmt-snet NSG (Jumpbox: Bastion-only SSH inbound)
az network nsg create --resource-group $RG --name ltmsa-mgmt-nsg

az network nsg rule create --resource-group $RG --nsg-name ltmsa-mgmt-nsg \
  --name allow-bastion-to-jumpbox --priority 100 --protocol Tcp \
  --source-address-prefixes 10.0.0.0/26 --destination-port-ranges 22 --access Allow

az network nsg rule create --resource-group $RG --nsg-name ltmsa-mgmt-nsg \
  --name allow-jumpbox-to-spoke --priority 200 --protocol Tcp \
  --direction Outbound \
  --source-address-prefixes 10.0.1.0/24 --destination-address-prefixes 10.1.1.0/24 \
  --destination-port-ranges 22 --access Allow

az network vnet subnet create \
  --resource-group $RG --vnet-name $HUB_VNET \
  --name mgmt-snet --address-prefix 10.0.1.0/24 \
  --network-security-group ltmsa-mgmt-nsg

# 2. Spoke VNet + web-snet
az network vnet create \
  --name $SPOKE_VNET --resource-group $RG \
  --address-prefix 10.1.0.0/16

# web-snet NSG (SSH via Hub Bastion/Jumpbox through Peering)
az network nsg create --resource-group $RG --name ltmsa-web-nsg

az network nsg rule create --resource-group $RG --nsg-name ltmsa-web-nsg \
  --name allow-bastion-ssh --priority 100 --protocol Tcp \
  --source-address-prefixes 10.0.0.0/26 --destination-port-ranges 22 --access Allow

az network nsg rule create --resource-group $RG --nsg-name ltmsa-web-nsg \
  --name allow-jumpbox-ssh --priority 110 --protocol Tcp \
  --source-address-prefixes 10.0.1.0/24 --destination-port-ranges 22 --access Allow

az network nsg rule create --resource-group $RG --nsg-name ltmsa-web-nsg \
  --name allow-http --priority 200 --protocol Tcp \
  --destination-port-ranges 80 --access Allow

az network vnet subnet create \
  --resource-group $RG --vnet-name $SPOKE_VNET \
  --name web-snet --address-prefix 10.1.1.0/24 \
  --network-security-group ltmsa-web-nsg

# 3. VNet Peering (bidirectional)
HUB_ID=$(az network vnet show --resource-group $RG --name $HUB_VNET --query id -o tsv)
SPOKE_ID=$(az network vnet show --resource-group $RG --name $SPOKE_VNET --query id -o tsv)

az network vnet peering create \
  --name hub-to-spoke --resource-group $RG \
  --vnet-name $HUB_VNET --remote-vnet "$SPOKE_ID" \
  --allow-vnet-access --allow-forwarded-traffic

az network vnet peering create \
  --name spoke-to-hub --resource-group $RG \
  --vnet-name $SPOKE_VNET --remote-vnet "$HUB_ID" \
  --allow-vnet-access --allow-forwarded-traffic

# 4. Azure Bastion in Hub AzureBastionSubnet
az network public-ip create --resource-group $RG \
  --name ltmsa-bastion-pip --sku Standard --zone 1 2 3

az network bastion create --resource-group $RG \
  --name ltmsa-bastion --sku Basic \
  --public-ip-address ltmsa-bastion-pip \
  --vnet-name $HUB_VNET
```

### Verify

```bash
# [1] Hub-Spoke VNet list
az network vnet list --resource-group $RG \
  --query "[].{Name:name, Prefix:addressSpace.addressPrefixes[0], Subnets:length(subnets)}" \
  --output table

# [2] Peering status (verify Connected)
az network vnet peering list --resource-group $RG \
  --vnet-name ltmsa-hub-vnet \
  --query "[].{Name:name, State:peeringState, RemoteVnet:remoteVirtualNetwork.id}" \
  --output table

# [3] Spoke web-snet NSG rules
az network nsg rule list --resource-group $RG \
  --nsg-name ltmsa-web-nsg --output table

# [4] Full summary
echo "=== VNets ===" && \
az network vnet list --resource-group $RG \
  --query "[].{Name:name, Prefix:addressSpace.addressPrefixes[0]}" --output table && \
echo "=== Peering ===" && \
az network vnet peering list --resource-group $RG \
  --vnet-name ltmsa-hub-vnet \
  --query "[].{Name:name, State:peeringState}" --output table && \
echo "=== NSGs ===" && \
az network nsg list --resource-group $RG \
  --query "[].{Name:name, Rules:length(securityRules)}" --output table
```

---

## Module 3: Security & Identity

### Create

```bash
# 1. Create security RG
az group create \
  --name $RG_SEC --location $LOCATION \
  --tags Environment=Lab Project=LTM-SA-Workshop

# 2. Create Entra ID group and add current user
az ad group create \
  --display-name "Azure-SA-Team" \
  --mail-nickname "azure-sa-team" \
  --description "Azure Solution Architect Team"

MY_USER_ID=$(az ad signed-in-user show --query id -o tsv)
GROUP_ID=$(az ad group list --filter "displayName eq 'Azure-SA-Team'" --query "[].id" -o tsv)
az ad group member add --group $GROUP_ID --member-id $MY_USER_ID

# 3. Register Microsoft.KeyVault resource provider (once only)
az provider register --namespace Microsoft.KeyVault --wait

# 4. Create Key Vault
#    Note: --enable-soft-delete / --soft-delete-retention-days not recognized in CLI 2.87
#          --enable-purge-protection false causes error on already-enabled subscriptions ??remove option
SUFFIX=$(date +%s | tail -c 5)
KV_NAME="${PREFIX}-kv-${SUFFIX}"
az keyvault create \
  --name $KV_NAME \
  --resource-group $RG_SEC \
  --location $LOCATION \
  --sku standard \
  --enable-rbac-authorization true \
  --retention-days 7

# 5. Grant Key Vault Secrets Officer role to yourself (az rest method)
KV_ID="/subscriptions/${SUB_ID}/resourceGroups/${RG_SEC}/providers/Microsoft.KeyVault/vaults/${KV_NAME}"
ROLE_GUID=$(powershell -Command "[System.Guid]::NewGuid().ToString()")
cat > /tmp/kv_role.json <<EOF
{
  "properties": {
    "roleDefinitionId": "/subscriptions/${SUB_ID}/providers/Microsoft.Authorization/roleDefinitions/b86a8fe4-44ce-4948-aee5-eccb2c155cd7",
    "principalId": "$(az ad signed-in-user show --query id -o tsv)"
  }
}
EOF
az rest --method PUT \
  --uri "https://management.azure.com${KV_ID}/providers/Microsoft.Authorization/roleAssignments/${ROLE_GUID}?api-version=2022-04-01" \
  --body "@/tmp/kv_role.json"

# 6. Store secret
KV_NAME=$(az keyvault list --resource-group $RG_SEC --query "[0].name" -o tsv)
az keyvault secret set \
  --vault-name $KV_NAME \
  --name "db-connection-string" \
  --value "Server=sql-ltmsa.database.windows.net;Database=appdb;User=appuser;Password=P@ssw0rd123!"

# 7. Create Managed Identity VM
#    Note: Standard_B1s has insufficient capacity in Korea Central ??use Standard_D2s_v3
az vm create \
  --name "${PREFIX}-demo-vm" \
  --resource-group $RG_SEC \
  --location $LOCATION \
  --image Ubuntu2204 \
  --size Standard_D2s_v3 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --assign-identity "[system]" \
  --no-wait

# 8. Grant Key Vault Secrets User role to VM Managed Identity
VM_PRINCIPAL_ID=$(az vm show \
  --name "${PREFIX}-demo-vm" --resource-group $RG_SEC \
  --query "identity.principalId" -o tsv)
ROLE_GUID2=$(powershell -Command "[System.Guid]::NewGuid().ToString()")
cat > /tmp/kv_vm_role.json <<EOF
{
  "properties": {
    "roleDefinitionId": "/subscriptions/${SUB_ID}/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6",
    "principalId": "${VM_PRINCIPAL_ID}"
  }
}
EOF
az rest --method PUT \
  --uri "https://management.azure.com${KV_ID}/providers/Microsoft.Authorization/roleAssignments/${ROLE_GUID2}?api-version=2022-04-01" \
  --body "@/tmp/kv_vm_role.json"
```

### Verify

```bash
KV_NAME=$(az keyvault list --resource-group $RG_SEC --query "[0].name" -o tsv)

# [1] Security RG
az group show --name $RG_SEC \
  --query "{Name:name, Location:location, State:properties.provisioningState}" --output table

# [2] Entra ID group
az ad group list --filter "displayName eq 'Azure-SA-Team'" \
  --query "[].{Name:displayName, Description:description}" --output table

# [3] Key Vault
az keyvault show --name $KV_NAME --resource-group $RG_SEC \
  --query "{Name:name, RbacEnabled:properties.enableRbacAuthorization, SoftDelete:properties.enableSoftDelete}" \
  --output table

# [4] Key Vault secrets
az keyvault secret list --vault-name $KV_NAME \
  --query "[].{Name:name, Enabled:attributes.enabled}" --output table

# [5] VM + Managed Identity
az vm show --name "${PREFIX}-demo-vm" --resource-group $RG_SEC \
  --query "{Name:name, Size:hardwareProfile.vmSize, Identity:identity.type, PrincipalId:identity.principalId}" \
  --output table

# [6] Verify everything at once
echo "=== Security RG ===" && \
az group show --name $RG_SEC \
  --query "{Name:name, Location:location, State:properties.provisioningState}" --output table && \
echo "=== Entra ID Group ===" && \
az ad group list --filter "displayName eq 'Azure-SA-Team'" \
  --query "[].{Name:displayName, Description:description}" --output table && \
echo "=== Key Vault ===" && \
az keyvault show --name $KV_NAME --resource-group $RG_SEC \
  --query "{Name:name, RbacEnabled:properties.enableRbacAuthorization}" --output table && \
echo "=== Secrets ===" && \
az keyvault secret list --vault-name $KV_NAME \
  --query "[].{Name:name, Enabled:attributes.enabled}" --output table && \
echo "=== VM + Managed Identity ===" && \
az vm show --name "${PREFIX}-demo-vm" --resource-group $RG_SEC \
  --query "{Name:name, Size:hardwareProfile.vmSize, Identity:identity.type}" --output table
```

---

## Module 4: Resiliency & HA

### Create

```bash
# 1. Create operations RG
az group create \
  --name $RG_OPS --location $LOCATION \
  --tags Environment=Lab Project=LTM-SA-Workshop

# 2. Deploy VMs simultaneously in Zone 1/2
#    Note: Standard_B1s ??insufficient capacity in Korea Central ??use Standard_D2s_v3
az vm create \
  --name "${PREFIX}-vm-zone1" --resource-group $RG_OPS \
  --location $LOCATION --image Ubuntu2204 --size Standard_D2s_v3 \
  --zone 1 --admin-username azureuser --generate-ssh-keys --no-wait

az vm create \
  --name "${PREFIX}-vm-zone2" --resource-group $RG_OPS \
  --location $LOCATION --image Ubuntu2204 --size Standard_D2s_v3 \
  --zone 2 --admin-username azureuser --generate-ssh-keys --no-wait

# 3. Create zone-redundant Public IP
az network public-ip create \
  --name "${PREFIX}-lb-pip" --resource-group $RG_OPS \
  --location $LOCATION --sku Standard \
  --zone 1 2 3 --allocation-method Static

# 4. Create Standard Load Balancer
az network lb create \
  --name "${PREFIX}-std-lb" --resource-group $RG_OPS \
  --location $LOCATION --sku Standard \
  --frontend-ip-name "frontend-ip" \
  --public-ip-address "${PREFIX}-lb-pip" \
  --backend-pool-name "backend-pool"

# 5. Add health probe (HTTP 80, 15-second interval)
az network lb probe create \
  --name "http-probe" --lb-name "${PREFIX}-std-lb" --resource-group $RG_OPS \
  --protocol Http --port 80 --path "/" --interval 15 --threshold 2

# 6. Add LB rule (distribute port 80)
az network lb rule create \
  --name "http-rule" --lb-name "${PREFIX}-std-lb" --resource-group $RG_OPS \
  --frontend-ip-name "frontend-ip" --backend-pool-name "backend-pool" \
  --probe-name "http-probe" --protocol Tcp \
  --frontend-port 80 --backend-port 80 \
  --idle-timeout 15 --enable-tcp-reset true
```

### Verify

```bash
# [1] Zone VM status
az vm list --resource-group $RG_OPS \
  --query "[].{Name:name, Zone:zones[0], Size:hardwareProfile.vmSize, State:provisioningState}" \
  --output table

# [2] Public IP
az network public-ip show --name "${PREFIX}-lb-pip" --resource-group $RG_OPS \
  --query "{Name:name, IP:ipAddress, Sku:sku.name}" --output table

# [3] LB probe + rules
az network lb probe list --lb-name "${PREFIX}-std-lb" --resource-group $RG_OPS \
  --query "[].{Name:name, Protocol:protocol, Port:port}" --output table && \
az network lb rule list --lb-name "${PREFIX}-std-lb" --resource-group $RG_OPS \
  --query "[].{Name:name, FrontendPort:frontendPort, BackendPort:backendPort}" --output table

# [4] Verify everything at once
echo "=== Zone VMs ===" && \
az vm list --resource-group $RG_OPS \
  --query "[].{Name:name, Zone:zones[0], State:provisioningState}" --output table && \
echo "=== Public IP ===" && \
az network public-ip show --name "${PREFIX}-lb-pip" --resource-group $RG_OPS \
  --query "{Name:name, IP:ipAddress, Sku:sku.name}" --output table && \
echo "=== Load Balancer ===" && \
az network lb show --name "${PREFIX}-std-lb" --resource-group $RG_OPS \
  --query "{Name:name, Sku:sku.name}" --output table && \
echo "=== Probes ===" && \
az network lb probe list --lb-name "${PREFIX}-std-lb" --resource-group $RG_OPS \
  --query "[].{Name:name, Protocol:protocol, Port:port}" --output table && \
echo "=== LB Rules ===" && \
az network lb rule list --lb-name "${PREFIX}-std-lb" --resource-group $RG_OPS \
  --query "[].{Name:name, FrontendPort:frontendPort, BackendPort:backendPort}" --output table
```

---

## Module 5: Monitor & Telemetry

> **Table ??Setup mapping (Ubuntu VMs):**
> | Table | Requires |
> |-------|---------|
> | `AzureMetrics` | `diagnostic-settings --metrics AllMetrics` |
> | `Heartbeat`, `Perf`, `Syslog` | AMA extension + DCR |
> | `AzureActivity` | Subscription-level diagnostic setting |
> | `SecurityEvent` | Windows VMs only ??use `Syslog` on Linux |

### Create

```bash
# 1. Register resource providers (once only)
az provider register --namespace Microsoft.Insights --wait
az provider register --namespace Microsoft.AlertsManagement --wait
az provider register --namespace Microsoft.OperationalInsights --wait
az provider register --namespace Microsoft.Monitor --wait

# 2. Create Log Analytics Workspace
az monitor log-analytics workspace create \
  --workspace-name "${PREFIX}-law" \
  --resource-group $RG_OPS --location $LOCATION \
  --sku PerGB2018 --retention-time 30 \
  --tags Environment=Lab Project=LTM-SA-Workshop
```

```powershell
# All remaining steps in PowerShell (prevents Windows path injection)
$PREFIX = "ltmsa"; $RG_OPS = "$PREFIX-ops-rg"; $RG_SEC = "$PREFIX-security-rg"; $LOCATION = "koreacentral"
$LAW_ID  = az monitor log-analytics workspace show --workspace-name "$PREFIX-law" --resource-group $RG_OPS --query id -o tsv
$SUB_ID  = az account show --query id -o tsv

# 3. VM platform metrics ??Log Analytics (fills AzureMetrics table immediately)
$VM_ID = az vm show --name "$PREFIX-demo-vm" --resource-group $RG_SEC --query id -o tsv
az monitor diagnostic-settings create `
  --name "vm-to-law" --resource $VM_ID --workspace $LAW_ID `
  --metrics '[{"category":"AllMetrics","enabled":true}]'

# 4. Enable Managed Identity on VMs (AMA prerequisite)
az vm identity assign --resource-group $RG_SEC --name "$PREFIX-demo-vm"
az vm identity assign --resource-group $RG_SEC --name "$PREFIX-demo-vm-2"

# 5. Create DCR ??Syslog + Performance counters ??Heartbeat, Perf, Syslog tables
$DCR_BODY = @"
{
  "location": "$LOCATION",
  "properties": {
    "dataSources": {
      "syslog": [{"name":"syslog-ds","streams":["Microsoft-Syslog"],"facilityNames":["auth","cron","daemon","syslog","user"],"logLevels":["Warning","Error","Critical","Alert","Emergency"]}],
      "performanceCounters": [{"name":"perf-ds","streams":["Microsoft-Perf"],"samplingFrequencyInSeconds":60,"counterSpecifiers":["\\\\Processor Information(_Total)\\\\% Processor Time","\\\\Memory\\\\Available Bytes","\\\\Logical Disk(/)\\\\% Free Space","\\\\Network Interface(*)\\\\Bytes Total/sec"]}]
    },
    "destinations": {"logAnalytics": [{"workspaceResourceId": "$LAW_ID", "name": "$PREFIX-law"}]},
    "dataFlows": [{"streams": ["Microsoft-Syslog","Microsoft-Perf"], "destinations": ["$PREFIX-law"]}]
  }
}
"@
az rest --method PUT `
  --uri "https://management.azure.com/subscriptions/$SUB_ID/resourceGroups/$RG_OPS/providers/Microsoft.Insights/dataCollectionRules/$PREFIX-dcr?api-version=2022-06-01" `
  --body $DCR_BODY

# 6. Associate DCR with both VMs
$DCR_ID = az rest --method GET `
  --uri "https://management.azure.com/subscriptions/$SUB_ID/resourceGroups/$RG_OPS/providers/Microsoft.Insights/dataCollectionRules/$PREFIX-dcr?api-version=2022-06-01" `
  --query id -o tsv
$VM1_ID = az vm show --resource-group $RG_SEC --name "$PREFIX-demo-vm"   --query id -o tsv
$VM2_ID = az vm show --resource-group $RG_SEC --name "$PREFIX-demo-vm-2" --query id -o tsv
az monitor data-collection rule association create --resource $VM1_ID --name "$PREFIX-dcra-vm1" --rule-id $DCR_ID
az monitor data-collection rule association create --resource $VM2_ID --name "$PREFIX-dcra-vm2" --rule-id $DCR_ID

# 7. Install AMA extension on both VMs
foreach ($VM in @("$PREFIX-demo-vm", "$PREFIX-demo-vm-2")) {
  az vm extension set --resource-group $RG_SEC --vm-name $VM `
    --name AzureMonitorLinuxAgent --publisher Microsoft.Azure.Monitor --enable-auto-upgrade true
}

# 8. Subscription-level Activity Log ??Log Analytics (fills AzureActivity table)
az monitor diagnostic-settings create `
  --name "activity-log-to-law" --resource "/subscriptions/$SUB_ID" --workspace $LAW_ID `
  --logs '[{"category":"Administrative","enabled":true},{"category":"Security","enabled":true},{"category":"Alert","enabled":true},{"category":"Policy","enabled":true}]'

# 9. Action Group + Alert Rule
az monitor action-group create `
  --name "$PREFIX-ops-ag" --resource-group $RG_OPS --short-name "OpsTeam" `
  --action email "InHwan" "inhwan.jung@outlook.kr"

$AG_ID = az monitor action-group show --name "$PREFIX-ops-ag" --resource-group $RG_OPS --query id -o tsv
az monitor metrics alert create `
  --name "High-CPU-Alert" --resource-group $RG_OPS --scopes $VM_ID `
  --condition "avg Percentage CPU > 80" --window-size 5m --evaluation-frequency 1m `
  --severity 2 --description "VM CPU usage exceeded 80% threshold" --action $AG_ID
```

### KQL Queries (Portal: Log Analytics ??Logs)

> Wait 5??0 min after AMA install before running Heartbeat/Perf/Syslog queries.

```kusto
// 0. Diagnose ??which tables have data?
union withsource=TableName Heartbeat, Perf, Syslog, AzureActivity, AzureMetrics
| where TimeGenerated > ago(1h)
| summarize RowCount = count() by TableName
| order by TableName asc

// 1. VM heartbeat (requires AMA)
Heartbeat
| where TimeGenerated > ago(1h)
| summarize LastHeartbeat=max(TimeGenerated) by Computer
| order by LastHeartbeat desc

// 2. CPU usage trend (requires AMA + DCR)
Perf
| where TimeGenerated > ago(1h)
| where ObjectName == "Processor" and CounterName == "% Processor Time"
| where InstanceName == "_Total"
| summarize AvgCPU = avg(CounterValue) by bin(TimeGenerated, 5m), Computer
| render timechart

// 3. Memory ??AMA reports Available Bytes (not MBytes), divide by 1073741824 for GB
Perf
| where TimeGenerated > ago(30m)
| where ObjectName == "Memory" and CounterName == "Available Bytes"
| summarize AvgBytes = avg(CounterValue) by Computer
| extend AvgMemGB = round(AvgBytes / 1073741824, 2)
| project Computer, AvgMemGB

// 4. Linux auth failures via Syslog (SecurityEvent = Windows only)
Syslog
| where TimeGenerated > ago(24h)
| where Facility in ("auth", "authpriv")
| where SyslogMessage has "Failed password"
    or SyslogMessage has "authentication failure"
    or SyslogMessage has "Invalid user"
| summarize FailureCount = count() by HostName, SyslogMessage
| where FailureCount > 3
| order by FailureCount desc

// 5. Resource change audit trail (requires subscription-level diagnostic setting)
AzureActivity
| where TimeGenerated > ago(24h)
| where OperationNameValue has "write" or OperationNameValue has "delete"
| where ActivityStatusValue == "Success"
| project TimeGenerated, Caller, OperationNameValue, ResourceGroup, Resource
| order by TimeGenerated desc
| take 50

// Bonus: VM CPU via AzureMetrics (available immediately, no AMA needed)
AzureMetrics
| where TimeGenerated > ago(1h)
| where MetricName == "Percentage CPU"
| summarize AvgCPU = avg(Average) by bin(TimeGenerated, 5m), Resource
| render timechart
```

### Percentile & Outlier Queries

```kusto
// 6. CPU percentile distribution ??P50/P90/P95/P99 + skew index
Perf
| where TimeGenerated > ago(24h)
| where ObjectName == "Processor" and CounterName == "% Processor Time"
| where InstanceName == "_Total"
| summarize
    P50 = percentile(CounterValue, 50),
    P90 = percentile(CounterValue, 90),
    P95 = percentile(CounterValue, 95),
    P99 = percentile(CounterValue, 99),
    MaxCPU = max(CounterValue),
    AvgCPU = avg(CounterValue)
  by Computer
| extend Skew = round(P95 - P50, 1)
| order by P95 desc

// 7. CPU time-series P50 vs P95 ??spot when spikes start
Perf
| where TimeGenerated > ago(6h)
| where ObjectName == "Processor" and CounterName == "% Processor Time"
| where InstanceName == "_Total"
| summarize
    P50 = percentile(CounterValue, 50),
    P95 = percentile(CounterValue, 95)
  by bin(TimeGenerated, 5m), Computer
| render timechart

// 8. IQR outlier detection ??box-plot method, no normal distribution assumption
let baseline =
    Perf
    | where TimeGenerated > ago(24h)
    | where ObjectName == "Processor" and CounterName == "% Processor Time"
    | where InstanceName == "_Total"
    | summarize Q1 = percentile(CounterValue, 25), Q3 = percentile(CounterValue, 75) by Computer;
Perf
| where TimeGenerated > ago(24h)
| where ObjectName == "Processor" and CounterName == "% Processor Time"
| where InstanceName == "_Total"
| join kind=inner baseline on Computer
| extend IQR = Q3 - Q1
| extend UpperFence = Q3 + 1.5 * IQR, LowerFence = Q1 - 1.5 * IQR
| where CounterValue > UpperFence or CounterValue < LowerFence
| project TimeGenerated, Computer, CounterValue, UpperFence, LowerFence
| order by CounterValue desc

// 9. Memory percentile + pressure index (AMA: Available Bytes)
Perf
| where TimeGenerated > ago(24h)
| where ObjectName == "Memory" and CounterName == "Available Bytes"
| summarize
    P5_AvailGB  = round(percentile(CounterValue, 5)  / 1073741824, 2),
    P50_AvailGB = round(percentile(CounterValue, 50) / 1073741824, 2),
    P95_AvailGB = round(percentile(CounterValue, 95) / 1073741824, 2),
    MinAvailGB  = round(min(CounterValue) / 1073741824, 2)
  by Computer
| extend PressureSignal = iff(P5_AvailGB < 0.5, "HIGH", iff(P5_AvailGB < 1.0, "WARN", "OK"))
| order by P5_AvailGB asc

// 10. AzureMetrics CPU percentile (no AMA ??available immediately)
AzureMetrics
| where TimeGenerated > ago(24h)
| where MetricName == "Percentage CPU"
| summarize
    P50 = percentile(Maximum, 50),
    P95 = percentile(Maximum, 95),
    P99 = percentile(Maximum, 99),
    AvgCPU = avg(Average)
  by Resource
| extend Skew = round(P95 - P50, 1)
| order by P95 desc
```

### KQL Queries ??App Performance & LB Health

> **Prerequisite**: LB Diagnostic Settings ??Log Analytics connection required (Group B)
> ```powershell
> $LB_ID = az network lb show --name "ltmsa-lb" --resource-group ltmsa-security-rg --query id -o tsv
> az monitor diagnostic-settings create `
>   --name "lb-to-law" --resource $LB_ID --workspace $LAW_ID `
>   --metrics '[{"category":"AllMetrics","enabled":true}]'
> ```

```kusto
// ?? Group A: VM Health Correlation (AMA-based, no additional setup required) ??

// 11. Multi-VM availability dashboard ??VM status at a glance based on Heartbeat
// No Heartbeat for 5+ minutes ??"OFFLINE" determination
let threshold = 5m;
Heartbeat
| where TimeGenerated > ago(1h)
| summarize LastBeat = max(TimeGenerated) by Computer, ResourceGroup
| extend Status = iff(LastBeat < ago(threshold), "OFFLINE", "ONLINE")
| extend MinutesSinceLastBeat = datetime_diff("minute", now(), LastBeat)
| project Computer, ResourceGroup, Status, LastBeat, MinutesSinceLastBeat
| order by Status asc, MinutesSinceLastBeat desc

// 12. CPU spike + Heartbeat cross-analysis ??distinguish app overload vs VM down
// CPU spike (>80%) and missing Heartbeat simultaneously ??VM down
// CPU high only, Heartbeat normal ??app overload (VM is alive)
let cpu_spikes =
    Perf
    | where TimeGenerated > ago(1h)
    | where ObjectName == "Processor" and CounterName == "% Processor Time"
    | where InstanceName == "_Total" and CounterValue > 80
    | summarize SpikeCount = count(), MaxCPU = max(CounterValue)
      by bin(TimeGenerated, 5m), Computer;
let heartbeats =
    Heartbeat
    | where TimeGenerated > ago(1h)
    | summarize BeatCount = count() by bin(TimeGenerated, 5m), Computer;
cpu_spikes
| join kind=leftouter heartbeats on TimeGenerated, Computer
| extend VMStatus = iff(isempty(BeatCount) or BeatCount == 0, "NO_HEARTBEAT", "ALIVE")
| extend Diagnosis = case(
    VMStatus == "NO_HEARTBEAT", "VM DOWN ??check Azure portal",
    SpikeCount > 0 and VMStatus == "ALIVE", "APP OVERLOAD ??VM healthy but CPU high",
    "Normal")
| project TimeGenerated, Computer, MaxCPU, SpikeCount, VMStatus, Diagnosis
| order by TimeGenerated desc

// 13. Network throughput trend ??LB backend VM traffic flow
// Bytes Total/sec surge = traffic spike, drop = VM isolated or removed from LB
Perf
| where TimeGenerated > ago(1h)
| where ObjectName == "Network Interface" and CounterName == "Bytes Total/sec"
| summarize
    AvgBps  = avg(CounterValue),
    MaxBps  = max(CounterValue),
    P95Bps  = percentile(CounterValue, 95)
  by bin(TimeGenerated, 5m), Computer, InstanceName
| extend AvgMbps = round(AvgBps * 8 / 1000000, 2)
| extend MaxMbps = round(MaxBps * 8 / 1000000, 2)
| project TimeGenerated, Computer, InstanceName, AvgMbps, MaxMbps
| render timechart

// 14. VM restart/shutdown event detection ??Heartbeat gap-based
// Heartbeat suddenly drops then resumes ??possible VM restart
Heartbeat
| where TimeGenerated > ago(24h)
| order by Computer asc, TimeGenerated asc
| serialize
| extend PrevBeat = prev(TimeGenerated, 1)
| extend GapMinutes = datetime_diff("minute", TimeGenerated, PrevBeat)
| where GapMinutes > 10  // 10+ min gap = suspected restart or suspension
| project TimeGenerated, Computer, GapMinutes,
          RestartAt = TimeGenerated,
          LastSeenBefore = PrevBeat
| order by GapMinutes desc

// ?? Group B: LB Health (requires LB Diagnostic Settings ??Log Analytics) ??

// 15. LB Frontend availability (VipAvailability) ??0=degraded, 100=healthy
// Standard LB only. Binary value: 0 or 100 (no intermediate values)
AzureMetrics
| where TimeGenerated > ago(1h)
| where ResourceProvider == "MICROSOFT.NETWORK/LOADBALANCERS"
| where MetricName == "VipAvailability"
| summarize
    AvgAvail = avg(Average),
    MinAvail = min(Minimum)
  by bin(TimeGenerated, 1m), Resource
| extend Status = iff(MinAvail < 100, "DEGRADED", "OK")
| project TimeGenerated, Resource, AvgAvail, MinAvail, Status
| order by TimeGenerated desc

// 16. LB backend health (DipAvailability) ??health probe result per VM
// 100=VM responding, 0=VM not responding to probe (app down or VM down)
AzureMetrics
| where TimeGenerated > ago(1h)
| where ResourceProvider == "MICROSOFT.NETWORK/LOADBALANCERS"
| where MetricName == "DipAvailability"
| summarize
    AvgAvail = avg(Average),
    MinAvail = min(Minimum)
  by bin(TimeGenerated, 1m), Resource
| extend BackendStatus = iff(MinAvail < 100, "PROBE_FAIL", "HEALTHY")
| project TimeGenerated, Resource, AvgAvail, MinAvail, BackendStatus
| order by TimeGenerated desc

// 17. LB DipAvailability degradation window ??extract below-threshold intervals
// Captures probe failure start time and duration per interval
AzureMetrics
| where TimeGenerated > ago(24h)
| where ResourceProvider == "MICROSOFT.NETWORK/LOADBALANCERS"
| where MetricName == "DipAvailability"
| where Average < 100  // below-healthy threshold only
| summarize
    DegradedStart = min(TimeGenerated),
    DegradedEnd   = max(TimeGenerated),
    MinAvail      = min(Average),
    EventCount    = count()
  by Resource
| extend DurationMin = datetime_diff("minute", DegradedEnd, DegradedStart)
| project Resource, DegradedStart, DegradedEnd, DurationMin, MinAvail, EventCount
| order by DegradedStart desc

// 18. LB throughput + DipAvailability correlation ??does health drop under traffic surge?
// If DipAvailability drops during high-throughput intervals ??app overload causing probe failure
let throughput =
    AzureMetrics
    | where TimeGenerated > ago(1h)
    | where ResourceProvider == "MICROSOFT.NETWORK/LOADBALANCERS"
    | where MetricName == "ByteCount"
    | summarize TotalBytes = sum(Total) by bin(TimeGenerated, 1m), Resource;
let health =
    AzureMetrics
    | where TimeGenerated > ago(1h)
    | where ResourceProvider == "MICROSOFT.NETWORK/LOADBALANCERS"
    | where MetricName == "DipAvailability"
    | summarize AvgAvail = avg(Average) by bin(TimeGenerated, 1m), Resource;
throughput
| join kind=inner health on TimeGenerated, Resource
| extend TotalMB = round(todouble(TotalBytes) / 1048576, 2)
| project TimeGenerated, Resource, TotalMB, AvgAvail
| render timechart

// ?? Group C: App layer inference (indirect measurement via VM metrics) ??????

// 19. Per-VM app load index (CPU + Network composite)
// High CPU + high network throughput ??"processing traffic" (normal load)
// High CPU + low network ??"internal bottleneck" (loop/compute-bound)
let cpu =
    Perf
    | where TimeGenerated > ago(1h)
    | where ObjectName == "Processor" and CounterName == "% Processor Time"
    | where InstanceName == "_Total"
    | summarize AvgCPU = avg(CounterValue) by bin(TimeGenerated, 5m), Computer;
let net =
    Perf
    | where TimeGenerated > ago(1h)
    | where ObjectName == "Network Interface" and CounterName == "Bytes Total/sec"
    | summarize AvgNetBps = avg(CounterValue) by bin(TimeGenerated, 5m), Computer;
cpu
| join kind=inner net on TimeGenerated, Computer
| extend LoadProfile = case(
    AvgCPU > 70 and AvgNetBps > 100000, "HIGH TRAFFIC LOAD",
    AvgCPU > 70 and AvgNetBps < 10000,  "INTERNAL BOTTLENECK",
    AvgCPU < 20 and AvgNetBps < 1000,   "IDLE",
    "NORMAL")
| project TimeGenerated, Computer, AvgCPU=round(AvgCPU,1), AvgNetMbps=round(AvgNetBps*8/1000000,2), LoadProfile
| order by TimeGenerated desc

// 20. Pre/post-deploy performance comparison ??before/after the deploy timestamp
// 30 min before vs 30 min after deployment: CPU comparison
let deploy_time = datetime(2026-06-13 09:30:00);  // replace with actual deploy time
let before =
    Perf
    | where TimeGenerated between ((deploy_time - 30m) .. deploy_time)
    | where ObjectName == "Processor" and CounterName == "% Processor Time"
    | where InstanceName == "_Total"
    | summarize AvgCPU_Before = avg(CounterValue) by Computer;
let after =
    Perf
    | where TimeGenerated between (deploy_time .. (deploy_time + 30m))
    | where ObjectName == "Processor" and CounterName == "% Processor Time"
    | where InstanceName == "_Total"
    | summarize AvgCPU_After = avg(CounterValue) by Computer;
before
| join kind=inner after on Computer
| extend Delta = round(AvgCPU_After - AvgCPU_Before, 1)
| extend Impact = case(
    Delta > 10,  "CPU INCREASE ??possible regression",
    Delta < -10, "CPU DECREASE ??possible improvement",
    "STABLE")
| project Computer, AvgCPU_Before=round(AvgCPU_Before,1), AvgCPU_After=round(AvgCPU_After,1), Delta, Impact
```

### Verify

```powershell
$PREFIX = "ltmsa"; $RG_OPS = "$PREFIX-ops-rg"; $RG_SEC = "$PREFIX-security-rg"
$SUB_ID = az account show --query id -o tsv

# [1] Log Analytics Workspace
az monitor log-analytics workspace show `
  --workspace-name "$PREFIX-law" --resource-group $RG_OPS `
  --query "{Name:name, Sku:sku.name, RetentionDays:retentionInDays}" --output table

# [2] AMA extension state on VM-1
az vm extension list --resource-group $RG_SEC --vm-name "$PREFIX-demo-vm" `
  --query "[?name=='AzureMonitorLinuxAgent'].{Name:name,State:provisioningState,Version:typeHandlerVersion}" `
  --output table

# [3] DCR associations
$VM1_ID = az vm show --resource-group $RG_SEC --name "$PREFIX-demo-vm" --query id -o tsv
az monitor data-collection rule association list --resource $VM1_ID `
  --query "[].{Name:name}" --output table

# [4] Subscription Activity Log diagnostic settings
az monitor diagnostic-settings list --resource "/subscriptions/$SUB_ID" `
  --query "[].{Name:name}" --output table

# [5] Alert Rule
az monitor metrics alert list --resource-group $RG_OPS `
  --query "[].{Name:name, Severity:severity, Enabled:enabled}" --output table
```

---

## Module 6: FinOps & Cost Governance

### 6.1 Query Azure Advisor Cost Recommendations

```bash
# Query Advisor recommendations (Cost category)
az advisor recommendation list \
  --subscription $SUB_ID \
  --category Cost \
  --output table

# No results expected if subscription/resources are new (this is normal)
```

### 6.2 Tag Compliance Analysis (Chargeback-based)

```bash
# Query all resource tag status
az resource list \
  --subscription $SUB_ID \
  --query "[].{Name:name, RG:resourceGroup, Environment:tags.Environment, Project:tags.Project}" \
  --output table

# Count untagged resources
TOTAL=$(az resource list --subscription $SUB_ID --query "length(@)" --output tsv)
TAGGED=$(az resource list --subscription $SUB_ID --query "[?tags.Environment!=null] | length(@)" --output tsv)
echo "Total: $TOTAL, Tagged: $TAGGED, Untagged: $((TOTAL - TAGGED))"
```

### 6.3 Bulk FinOps Tag Application (Resource Group Level)

```bash
# Governance RG
az group update \
  --name ltmsa-governance-rg \
  --tags Environment=dev Project=LTM-SA-Workshop Owner=inhwan.jung@outlook.kr CostCenter=IT-OPS

# Network RG
az group update \
  --name ltmsa-network-rg \
  --tags Environment=dev Project=LTM-SA-Workshop Owner=inhwan.jung@outlook.kr CostCenter=NETWORKING

# Security RG
az group update \
  --name ltmsa-security-rg \
  --tags Environment=dev Project=LTM-SA-Workshop Owner=inhwan.jung@outlook.kr CostCenter=SECURITY

# Operations RG
az group update \
  --name ltmsa-ops-rg \
  --tags Environment=dev Project=LTM-SA-Workshop Owner=inhwan.jung@outlook.kr CostCenter=OPERATIONS

# Verify tag application
az group list \
  --query "[?starts_with(name, 'ltmsa')].{Name:name, CostCenter:tags.CostCenter, Env:tags.Environment}" \
  --output table
```

### 6.4 Budget Alert Configuration (az rest ??CLI bug workaround)

> The `az consumption budget create` command returns a 400 error on Free Trial/MSDN subscriptions.  
> Call the Cost Management API directly via `az rest`.

```powershell
# Run in PowerShell
$SUB_ID = az account show --query id -o tsv

az rest `
  --method PUT `
  --uri "https://management.azure.com/subscriptions/${SUB_ID}/providers/Microsoft.Consumption/budgets/ltmsa-monthly-budget?api-version=2023-05-01" `
  --body '{
    "properties": {
      "category": "Cost",
      "amount": 100,
      "timeGrain": "Monthly",
      "timePeriod": {
        "startDate": "2026-06-01T00:00:00Z",
        "endDate": "2027-06-01T00:00:00Z"
      },
      "notifications": {
        "Actual_75": {
          "enabled": true,
          "operator": "GreaterThan",
          "threshold": 75,
          "contactEmails": ["inhwan.jung@outlook.kr"],
          "thresholdType": "Actual"
        },
        "Actual_90": {
          "enabled": true,
          "operator": "GreaterThan",
          "threshold": 90,
          "contactEmails": ["inhwan.jung@outlook.kr"],
          "thresholdType": "Actual"
        },
        "Actual_100": {
          "enabled": true,
          "operator": "GreaterThan",
          "threshold": 100,
          "contactEmails": ["inhwan.jung@outlook.kr"],
          "thresholdType": "Actual"
        }
      }
    }
  }'
```

### 6.5 Verification Commands

```bash
# Verify budget list
az rest \
  --method GET \
  --uri "https://management.azure.com/subscriptions/${SUB_ID}/providers/Microsoft.Consumption/budgets?api-version=2023-05-01" \
  --query "value[].{Name:name, Amount:properties.amount, CurrentSpend:properties.currentSpend.amount, TimeGrain:properties.timeGrain}" \
  --output table

# Query Advisor RI recommendations (az rest)
az rest \
  --method GET \
  --uri "https://management.azure.com/subscriptions/${SUB_ID}/providers/Microsoft.Advisor/recommendations?api-version=2023-01-01&\$filter=Category eq 'Cost'" \
  --query "value[].{Title:properties.shortDescription.solution, Impact:properties.impact}" \
  --output table
```

---

## Module 7: Automation & Bicep IaC

### 7.1 Bicep What-If Deployment

```bash
# Check Bicep CLI version
az bicep version

# Run What-if ??preview changes before actual deployment
az deployment group what-if \
  --resource-group ltmsa-governance-rg \
  --template-file "D:/inhwa/Documents/LTM/bicep/main.bicep" \
  --parameters environment=dev

# Interpreting results:
#   + Create  : Resources that will be newly created
#   ~ Modify  : Resources that will be changed
#   - Delete  : Resources that will be deleted
#   x Ignore  : No changes
```

### 7.2 Bicep Actual Deployment

```bash
# Include timestamp in deployment name (for easy tracking)
DEPLOY_NAME="ltmsa-infra-$(date +%Y%m%d%H%M)"

az deployment group create \
  --name "$DEPLOY_NAME" \
  --resource-group ltmsa-governance-rg \
  --template-file "D:/inhwa/Documents/LTM/bicep/main.bicep" \
  --parameters environment=dev \
  --output table

# View deployment list
az deployment group list \
  --resource-group ltmsa-governance-rg \
  --query "[].{Name:name, State:properties.provisioningState, Timestamp:properties.timestamp}" \
  --output table

# View output values (vnetId, lawId, keyVaultName, etc.)
az deployment group show \
  --name "$DEPLOY_NAME" \
  --resource-group ltmsa-governance-rg \
  --query "properties.outputs" \
  --output json
```

### 7.3 Infrastructure Drift Detection

```bash
# Export current infrastructure state as ARM Template
az group export \
  --name ltmsa-ops-rg \
  --output json > rg-ops-current-state.json

# Use What-if to find differences between code vs actual infrastructure (drift detection)
az deployment group what-if \
  --resource-group ltmsa-governance-rg \
  --template-file "D:/inhwa/Documents/LTM/bicep/main.bicep" \
  --parameters environment=dev

# If results contain '~ Modify' or '- Delete' entries, drift has occurred
```

### 7.4 Create Automation Account (Portal-based Runbook)

> The `az automation` command requires a separate extension.  
> Use the `az rest` method below to create it without an extension.

```powershell
# Run in PowerShell
$SUB_ID = az account show --query id -o tsv
$RG = "ltmsa-ops-rg"
$LOCATION = "koreacentral"
$AA_NAME = "ltmsa-automation"

# Create Automation Account (az rest)
az rest `
  --method PUT `
  --uri "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.Automation/automationAccounts/${AA_NAME}?api-version=2023-11-01" `
  --body "{
    `"location`": `"${LOCATION}`",
    `"properties`": {
      `"sku`": { `"name`": `"Basic`" }
    },
    `"tags`": {
      `"Environment`": `"dev`",
      `"Project`": `"LTM-SA-Workshop`"
    }
  }"

# Verify creation
az rest `
  --method GET `
  --uri "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.Automation/automationAccounts/${AA_NAME}?api-version=2023-11-01" `
  --query "{Name:name, State:properties.state, Location:location}"
```

**Create Runbook in Azure Portal:**
1. Automation Account ??[Runbooks] ??[+ Create a runbook]
2. Name: `Stop-VMsAfterHours`, Type: PowerShell 5.1
3. Enter the script below, then [Save] ??[Publish]

```powershell
# Stop-VMsAfterHours.ps1 (Automation Runbook)
param(
    [string]$TagName = "Environment",
    [string]$TagValue = "dev"
)

Connect-AzAccount -Identity

$vms = Get-AzVM -Status | Where-Object {
    $_.Tags[$TagName] -eq $TagValue -and
    $_.PowerState -eq "VM running"
}

Write-Output "Target VM count: $($vms.Count)"

foreach ($vm in $vms) {
    Write-Output "Stopping: $($vm.Name)"
    Stop-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Force -NoWait
}

Write-Output "Done"
```

4. [Schedule] ??Register daily at 7:00 PM KST (UTC+9 ??UTC 10:00)

### 7.5 GitHub Actions CI/CD ??Azure VM Deployment (Lab 7.4)

> **Repo**: `jungfrau70/github-actions-azure` (GitHub)  
> **Workflow**: `.github/workflows/deploy-vm.yml`  
> **Deployment targets**: `ltmsa-demo-vm` + `ltmsa-demo-vm-2` (behind Standard LB)

#### Step 1: Create Service Principal for GitHub Actions

> **Windows Git Bash note**: `/subscriptions/...` paths are rewritten to `C:/Program Files/Git/subscriptions/...`
> ??Prefix `MSYS_NO_PATHCONV=1` is required. Not needed in PowerShell.

```bash
SUB_ID=$(az account show --query id -o tsv)

# Scope: subscription level (E2E deletes and recreates RG ??RG scope is insufficient)
# Windows Git Bash: MSYS_NO_PATHCONV=1 required
MSYS_NO_PATHCONV=1 az ad sp create-for-rbac \
  --name "github-actions-ltmsa" \
  --role Contributor \
  --scopes "/subscriptions/${SUB_ID}" \
  --sdk-auth \
  --output json
# Note: --sdk-auth is deprecated but still functional (outputs legacy JSON format)
# Copy the full output JSON ??store in AZURE_CREDENTIALS secret
```

> **SP scope selection guide**
> | Use case | Scope | Reason |
> |----------|-------|--------|
> | E2E test (RG delete ??recreate) | Subscription level | Must create RG from scratch |
> | deploy-vm.yml (existing RG retained) | RG level | Least-privilege principle |

#### Step 2: Configure GitHub Secrets

```bash
# Set secrets via GitHub CLI (recommended)
gh secret set AZURE_CREDENTIALS \
  --repo jungfrau70/github-actions-azure \
  --body "$(MSYS_NO_PATHCONV=1 az ad sp create-for-rbac \
    --name github-actions-ltmsa \
    --role Contributor \
    --scopes /subscriptions/$(az account show --query id -o tsv) \
    --sdk-auth --output json)"

gh secret set ADMIN_PASSWORD \
  --repo jungfrau70/github-actions-azure
# (enter password at prompt)
```

Or via GitHub web UI:
```
GitHub Repo ??Settings ??Secrets and variables ??Actions ??New repository secret

  AZURE_CREDENTIALS  : full JSON output of az ad sp create-for-rbac --sdk-auth
  ADMIN_PASSWORD     : VM admin password (e.g. bright2n@1234)
```

#### Step 3: Deploy LB + VM-2 via Bicep (7.5.1)

```bash
# Get existing VM-1 subnet ID
SUBNET_ID=$(az vm show -g ltmsa-security-rg -n ltmsa-demo-vm \
  --query "networkProfile.networkInterfaces[0].id" -o tsv \
  | xargs -I{} az network nic show --ids {} \
  --query "ipConfigurations[0].subnet.id" -o tsv)

# Deploy lb-vm2.bicep: creates Standard LB + VM-2
az deployment group create \
  --resource-group ltmsa-security-rg \
  --template-file "D:/inhwa/Documents/LTM/bicep/lb-vm2.bicep" \
  --parameters adminPassword="bright2n@1234" subnetId="$SUBNET_ID"

# Get LB public IP
az network public-ip show \
  --resource-group ltmsa-security-rg \
  --name ltmsa-lb-pip \
  --query ipAddress --output tsv

# Add VM-1 NIC to LB backend pool
NIC_NAME=$(az vm show -g ltmsa-security-rg -n ltmsa-demo-vm \
  --query "networkProfile.networkInterfaces[0].id" -o tsv | xargs basename)
IP_CONFIG=$(az network nic show -g ltmsa-security-rg -n "$NIC_NAME" \
  --query "ipConfigurations[0].name" -o tsv)
POOL_ID=$(az network lb show -g ltmsa-security-rg -n ltmsa-lb \
  --query "backendAddressPools[0].id" -o tsv)

az network nic ip-config address-pool add \
  --resource-group ltmsa-security-rg \
  --nic-name "$NIC_NAME" --ip-config-name "$IP_CONFIG" --address-pool "$POOL_ID"
```

#### Step 4: Verify LB and Deployment

```bash
LB_IP=$(az network public-ip show -g ltmsa-security-rg -n ltmsa-lb-pip \
  --query ipAddress -o tsv)

# LB health check (port 80 ??3000)
curl http://${LB_IP}/health

# Backend pool members
az network lb address-pool show \
  -g ltmsa-security-rg -n ltmsa-lb --address-pool lb-backend \
  --query "loadBalancerBackendAddresses[].name" --output table
```

### 7.6 Zero Trust Admin Access ??Bastion + Jumpbox + Break-glass (Hub-Spoke)

> Three-tier admin access based on Hub-Spoke architecture ??no internet-facing SSH

```
Hub VNet (10.0.0.0/16)               Spoke VNet (10.1.0.0/16)
  ?쒋?? AzureBastionSubnet (10.0.0.0/26)      ?붴?? web-snet (10.1.1.0/24)
  ?붴?? mgmt-snet (10.0.1.0/24)
           ??VNet Peering
Bastion (Hub) ??[Peering]????App VM (Spoke)
Bastion (Hub) ????Jumpbox (Hub) ??[Peering]????App VM (Spoke)
```

#### Step 1: NSG Rules (Hub-Spoke based ??already created in Module 2)

```bash
# Spoke web-snet NSG ??source is Hub subnet (reaches via Peering)
az network nsg rule list --resource-group $RG_SEC \
  --nsg-name ltmsa-web-nsg --output table
# Verify:
#   allow-bastion-ssh  : source 10.0.0.0/26 (Hub Bastion) ??port 22
#   allow-jumpbox-ssh  : source 10.0.1.0/24 (Hub mgmt)   ??port 22

# Hub mgmt-snet NSG
az network nsg rule list --resource-group $RG_SEC \
  --nsg-name ltmsa-mgmt-nsg --output table
# Verify:
#   allow-bastion-to-jumpbox  : source 10.0.0.0/26 ??port 22
#   allow-jumpbox-to-spoke    : Outbound, dest 10.1.1.0/24 ??port 22
```

#### Step 2: Deploy Azure Bastion in Hub (Scenario 1 ??Zero Trust)

```bash
# Standard Static PIP (zone-redundant)
az network public-ip create \
  --resource-group $RG_SEC \
  --name ltmsa-bastion-pip \
  --sku Standard --allocation-method Static \
  --zone 1 2 3

# Basic SKU Bastion in Hub AzureBastionSubnet (~5-10 min)
# Bastion reaches Spoke VMs through VNet Peering
az network bastion create \
  --resource-group $RG_SEC \
  --name ltmsa-bastion \
  --public-ip-address ltmsa-bastion-pip \
  --vnet-name ltmsa-hub-vnet \
  --sku Basic

# Check provisioning state
az network bastion show \
  --resource-group $RG_SEC \
  --name ltmsa-bastion \
  --query "provisioningState" --output tsv
# Expected: Succeeded

# Admin access: Azure Portal ??Bastion ??ltmsa-bastion ??Connect (select Spoke VM)
```

#### Step 3: Deploy Jumpbox VM in Hub mgmt-snet (Scenario 2 ??Jumpbox Pattern)

```bash
# Jumpbox placed in Hub mgmt-snet ??accessible only via Bastion (no public IP)
# Jumpbox ??Spoke App VM: SSH over VNet Peering (10.0.1.0/24 ??10.1.1.0/24)
az vm create \
  --resource-group $RG_SEC \
  --name ltmsa-jumpbox \
  --location koreacentral \
  --image Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest \
  --size Standard_D2s_v3 \
  --admin-username azureuser \
  --admin-password "YourSecurePassword!" \
  --authentication-type password \
  --vnet-name ltmsa-hub-vnet \
  --subnet mgmt-snet \
  --nsg "" \
  --public-ip-address ""

# Verify: no public IP, confirm placement in Hub mgmt-snet
az vm show \
  --resource-group $RG_SEC \
  --name ltmsa-jumpbox \
  --show-details --query "{name:name, privateIps:privateIps, publicIps:publicIps}"
# Expected: publicIps = "", privateIps = 10.0.1.x (Hub mgmt-snet)

# Access path (Hub-Spoke):
# Portal ??Bastion (Hub) ??Connect to ltmsa-jumpbox
# In Jumpbox: ssh azureuser@<spoke-vm-private-ip>   (10.1.1.x)
```

#### Step 4: Break-glass via Management Plane (Scenario 3)

```bash
# Emergency access ??bypasses NSG/network entirely (VM Agent delivery)
az vm run-command invoke \
  --resource-group $RG_SEC \
  --name ltmsa-demo-vm \
  --command-id RunShellScript \
  --scripts "
    echo 'Host:' \$(hostname)
    pm2 list --no-color
    ss -tlnp | grep :3000
    df -h / | tail -1
  " \
  --query "value[0].message" --output tsv

# Required RBAC permission:
#   Microsoft.Compute/virtualMachines/runCommands/action
#   Contributor on the resource group is sufficient
```

#### Access Pattern Comparison

| Scenario | Protocol | Port 22 Required | Use Case |
|----------|----------|-----------------|----------|
| Azure Bastion | HTTPS/TLS | No | Daily admin operations |
| Jumpbox | SSH (internal) | Internal only | Batch operations, scripting |
| Break-glass | HTTPS (Mgmt Plane) | No | Emergency, CI/CD automation |

### 7.7 E2E Automation Test (Full Fresh Deploy)

> Workflow: `.github/workflows/e2e-test.yml`  
> Trigger: **Manual only** (workflow_dispatch) ??type "DESTROY" in confirm field  
> Flow: Delete RG ??Network+NSG+Bastion ??VM-1+Jumpbox ??LB+VM-2 ??App deploy ??LB+Bastion verify

```
GitHub Repo ??Actions ??"E2E Test ??Full Fresh Deploy" ??Run workflow
  confirm_destroy: DESTROY
  environment:     dev
```

Workflow steps (Hub-Spoke configuration):
1. Delete `ltmsa-security-rg` (remove lock, wait for completion)
2. Recreate RG + Hub VNet (AzureBastionSubnet+mgmt-snet) + Spoke VNet (web-snet) + VNet Peering
3. Deploy Azure Bastion in Hub (async, --no-wait)
4. Jumpbox VM in Hub mgmt-snet + VM-1 in Spoke web-snet ??parallel execution
5. Deploy lb-vm2.bicep (LB + VM-2, Spoke web-snet)
6. Add VM-1 NIC to LB backend pool
7. Deploy app to VM-1/VM-2 simultaneously (matrix, az vm run-command)
8. Verify: LB health + Bastion provisioning + Break-glass demo

---

## Module 8: Security Artifacts (Run after E2E passes ??while infrastructure is live)

> Full procedure: `E2E_Test.md` Section 8  
> **Execution order**: E2E Test Passed ??Section 7 Log Analytics ??**Run this** ??Clean-up

```bash
# Common variables
RG="ltmsa-security-rg"
SUB_ID=$(az account show --query id -o tsv)
```

### 8.1 Security Posture Assessment (Secure Score + Unhealthy Recommendations)

```bash
# Secure Score
az security secure-score show --name "ascScore" \
  --query "{score:score.current, max:score.max, percentage:score.percentage}" -o json

# High-severity unhealthy items
az security assessment list \
  --query "[?status.code=='Unhealthy' && metadata.severity=='High'].{name:displayName, category:metadata.categories[0]}" \
  -o table

# Aggregate by severity
az security assessment list \
  --query "{High:[?status.code=='Unhealthy' && metadata.severity=='High'] | length(@), Medium:[?status.code=='Unhealthy' && metadata.severity=='Medium'] | length(@)}" \
  -o json
```

### 8.2 Vulnerability Assessment

```bash
# Detect risky NSG rules (internet ??SSH/RDP allow-all)
for nsg in ltmsa-web-nsg ltmsa-mgmt-nsg; do
  echo "=== $nsg ==="
  az network nsg rule list --resource-group $RG --nsg-name $nsg \
    --query "[?access=='Allow' && direction=='Inbound' && (sourceAddressPrefix=='*' || sourceAddressPrefix=='0.0.0.0/0') && (destinationPortRange=='22' || destinationPortRange=='3389' || destinationPortRange=='*')].{name:name, source:sourceAddressPrefix, port:destinationPortRange}" \
    -o table
done

# Public IP exposure
az network public-ip list --resource-group $RG \
  --query "[].{name:name, IP:ipAddress, attachment:ipConfiguration.id}" -o table

# VM Managed Identity status
az vm list --resource-group $RG \
  --query "[].{VM:name, IdentityType:identity.type}" -o table

# RBAC subscription-level Owner/Contributor list
az role assignment list --scope "/subscriptions/$SUB_ID" \
  --query "[?roleDefinitionName=='Owner' || roleDefinitionName=='Contributor'].{principal:principalName, role:roleDefinitionName, type:principalType}" \
  -o table
```

### 8.3 Compliance Assessment

```bash
# Policy compliance status (ltmsa-security-rg)
az policy state list --resource-group $RG \
  --query "[?complianceState=='NonCompliant'].{policy:policyDefinitionName, resource:resourceId}" \
  -o table

# CIS 6.2: Verify no SSH internet exposure
az network nsg list --resource-group $RG \
  --query "[].securityRules[?destinationPortRange=='22' && access=='Allow' && (sourceAddressPrefix=='*' || sourceAddressPrefix=='0.0.0.0/0')].name" \
  -o tsv && echo "No results = CIS 6.2 compliant"

# Resource Lock status
az lock list --resource-group $RG -o table

# Tag compliance (required tags: Environment, Project, Owner)
az resource list --resource-group $RG \
  --query "[?tags.Environment==null || tags.Project==null || tags.Owner==null].{name:name, type:type}" \
  -o table
echo "No results = all tags compliant"
```

---

## Clean-up (After completing labs)

```bash
# Delete all lab RGs
for rg in $RG_GOV $RG_NET $RG_SEC $RG_OPS; do
  az group delete --name $rg --yes --no-wait
done

# Remove subscription from MG
az account management-group subscription remove \
  --name "LTM-Corp" --subscription "$SUB_ID"

# Delete MG
az account management-group delete --name "LTM-Corp"
```

