# Azure SA Workshop Complete Guide
## Building a Claude + Azure CLI Integrated Lab Environment and 8-Module Hands-On Practice

**Audience:** LTM Korea Azure Solution Architect Position Candidate  
**Date:** 2026-06-13  
**Total Time:** 30 minutes setup + 7–8 hours of hands-on practice  
**Level:** 300-level (Practicing Architect)

---

## Table of Contents

1. [Environment Setup: Azure CLI Installation (Method A)](#-environment-setup-method-a--azure-cli-installation-recommended)
2. [Environment Setup: Azure MCP Server Installation (Method B)](#-environment-setup-method-b--azure-mcp-server-claude-direct-control)
3. [Azure Login and Variable Setup](#-azure-login-and-common-variable-setup)
4. [Pre-work: Management Group Creation & Korea Region Restriction Policy](#-pre-work-management-group-creation--korea-region-restriction-policy)
5. [Module 1: Governance & Landing Zone](#module-1-azure-governance--landing-zone-60-minutes)
6. [Module 2: Network Architecture (Hub-Spoke)](#module-2-network-architecture---hub-and-spoke-60-minutes)
7. [Module 3: Security & Identity](#module-3-security--identity-60-minutes)
8. [Module 4: Resiliency & HA](#module-4-cloud-resiliency--high-availability-50-minutes)
9. [Module 5: Monitor & Telemetry](#module-5-azure-monitor--telemetry-50-minutes)
10. [Module 6: FinOps & Cost Governance](#module-6-finops--cost-governance-40-minutes)
11. [Module 7: Automation & Bicep IaC](#module-7-azure-automation--iac-with-bicep-50-minutes)
12. [Module 8: Security Artifacts (Post E2E)](#module-8-security-artifacts--compliance-assessment--vulnerability-review-post-e2e)
13. [Lab Environment Clean-up](#-lab-environment-clean-up)
14. [Design Key Q&A](#-design-key-questions--model-answers)

---

## 🛠 Environment Setup: Method A — Azure CLI Installation (Recommended)

> **When to use?** When you want to run `az` commands directly from the terminal. This is the most stable option and suitable for all module exercises.

### Step 1: Install Azure CLI

**PowerShell (run as administrator):**
```powershell
# Install via winget (Windows 10/11)
winget install Microsoft.AzureCLI

# Or download the MSI directly
# https://aka.ms/installazurecliwindows
```

> ⚠️ After installation, **close the terminal completely and reopen it** for the PATH to take effect.

### Step 2: Verify Installation

```powershell
az --version
# Example output:
# azure-cli  2.61.0
# core        2.61.0
# telemetry   1.1.0
```

### Step 3: Install Bicep CLI (for Module 7)

```powershell
az bicep install
az bicep version
# Example output: Bicep CLI version 0.28.1
```

---

## 🤖 Environment Setup: Method B — Azure MCP Server (Claude Direct Control)

> **When to use?** When you want to manage Azure with natural language in Claude Code, such as "Create an Azure resource for me." Can be used **alongside** Azure CLI.

### Step 1: Install Node.js

```powershell
# Install via winget
winget install OpenJS.NodeJS

# Verify installation (in a new terminal)
node --version   # v20.x.x or higher recommended
npx --version    # 10.x.x or higher
```

### Step 2: Create an Azure Service Principal

Use the Azure Portal or Azure CLI to issue credentials for the MCP Server.

```bash
# Run after logging in with Azure CLI
az login

# Create Service Principal (Contributor role)
az ad sp create-for-rbac \
  --name "claude-mcp-sp" \
  --role Contributor \
  --scopes "/subscriptions/$(az account show --query id -o tsv)" \
  --output json
```

Example output:
```json
{
  "appId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",   ← AZURE_CLIENT_ID
  "displayName": "claude-mcp-sp",
  "password": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",    ← AZURE_CLIENT_SECRET
  "tenant": "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"   ← AZURE_TENANT_ID
}
```

> 🔐 **Security note:** The `password` value is only shown at this point. Be sure to store it somewhere safe.

### Step 3: Edit Claude settings.json

File path: `C:\Users\<username>\.claude\settings.json`

```json
{
  "theme": "dark",
  "mcpServers": {
    "azure": {
      "command": "npx",
      "args": ["-y", "@azure/mcp-server"],
      "env": {
        "AZURE_SUBSCRIPTION_ID": "enter-your-subscription-id-here",
        "AZURE_TENANT_ID": "enter-your-tenant-id-here",
        "AZURE_CLIENT_ID": "enter-your-app-id-here",
        "AZURE_CLIENT_SECRET": "enter-your-password-here"
      }
    }
  }
}
```

> 📝 **How to find the values:**
> - **Subscription ID**: `az account show --query id -o tsv`
> - **Tenant ID**: `az account show --query tenantId -o tsv`
> - **Client ID / Secret**: `appId` / `password` from Step 2 above

### Step 4: Restart Claude Code

Fully quit and restart Claude Code for the settings to take effect.

### How to Verify MCP Connection

Try the following conversation in Claude Code:
```
Show me a list of all resource groups in the current Azure subscription
```

If Azure responds, the MCP Server is working correctly.

---

## 🔑 Azure Login and Common Variable Setup

> These variables are reused across all module exercises. Be sure to run them at the start of each CLI session.

### Azure Login

```bash
# Log in via browser popup
az login

# Verify current account
az account show --output table

# If you have multiple subscriptions, switch to the lab subscription
az account list --output table
az account set --subscription "<subscription name or ID>"
```

### Common Variable Setup (Bash / Azure Cloud Shell)

```bash
# === Common Variables (reused across all exercises) ===
export LOCATION="koreacentral"
export PREFIX="ltmsa"
export RG_GOV="${PREFIX}-governance-rg"
export RG_NET="${PREFIX}-network-rg"
export RG_SEC="${PREFIX}-security-rg"
export RG_OPS="${PREFIX}-ops-rg"

# Verify settings
echo "Location: $LOCATION"
echo "Governance RG: $RG_GOV"
echo "Network RG: $RG_NET"
echo "Security RG: $RG_SEC"
echo "Ops RG: $RG_OPS"
```

### Common Variable Setup (PowerShell)

```powershell
# === Common Variables (for PowerShell) ===
$LOCATION = "koreacentral"
$PREFIX = "ltmsa"
$RG_GOV = "${PREFIX}-governance-rg"
$RG_NET = "${PREFIX}-network-rg"
$RG_SEC = "${PREFIX}-security-rg"
$RG_OPS = "${PREFIX}-ops-rg"

# Verify settings
Write-Host "Location: $LOCATION"
Write-Host "Governance RG: $RG_GOV"
```

---

## 🏗 Pre-work: Landing Zone Foundation — Management Group & Korea Region Restriction Policy

> **What is a Landing Zone?** As defined by the Microsoft CAF (Cloud Adoption Framework), it is the foundational environment that allows enterprises to use Azure safely and consistently.  
> This pre-work builds the **Platform Layer** of the Landing Zone — the governance foundation that operates above all subscriptions.
>
> ```
> Overall Landing Zone Structure (scope covered by this workshop)
> ─────────────────────────────────────────────
> [Pre-work]  Platform Layer: MG hierarchy + Korea policy (subscription level and above)
> [Module 1]  Governance Layer: Policy + RBAC + Resource Lock (subscription/RG level)
> [Module 2]  Network Layer: Hub-Spoke + NSG 3-tier (network isolation)
> [Module 3]  Identity Layer: Managed Identity + Key Vault (Zero Trust)
> ─────────────────────────────────────────────
> ```
>
> Starting Module 1 without this pre-work results in nothing more than a simple RBAC exercise.  
> With an MG hierarchy in place, policies are **automatically inherited by all child subscriptions** — this is the core of an enterprise Landing Zone.

### Tenant Structure After Lab Setup (Expected Result)

```
[Tenant Root Group: 1555f067-...]
  ├── [MG-Company] — "Company Management Group" (existing)
  │     └── Azure subscription 1
  └── [LTM-Corp] — "LTM Corporation" ✅ for lab use
        ├── LTM subscription_id 1  (lab subscription)
        └── [Policy] Allow Korea regions only  ← Only Korea Central/South allowed
```

---

### Step 1: Verify Management Group Creation Permissions

Creating a MG requires **Tenant-level permissions**. Use the command below to verify access in advance.

```bash
# Query the list of MGs in the current tenant (verify read permissions)
az account management-group list --output table

# If you have permissions, output will look like this:
# DisplayName               Name        TenantId
# ------------------------  ----------  -----------
# Tenant Root Group         xxxxxxxx-…  xxxxxxxx-…
```

If you lack permissions, an `AuthorizationFailed` error will occur.  
→ In this case, go to Azure Portal → Entra ID → Properties → set "Access management for Azure resources" to **Yes**.

---

### Step 2: Create Management Group and Move Subscription

```bash
# Create the LTM-Corp Management Group
az account management-group create \
  --name "LTM-Corp" \
  --display-name "LTM Corporation"

# Move the lab subscription under the LTM-Corp MG
az account management-group subscription add \
  --name "LTM-Corp" \
  --subscription "$(az account show --query id -o tsv)"

# Verify the structure
az account management-group show \
  --name "LTM-Corp" \
  --expand --recurse
```

---

### Step 3: Assign Korea Region Restriction Policy

> Once this policy is applied, resource creation in any region other than koreacentral and koreasouth will be blocked **across all subscriptions under the LTM-Corp MG**.

**Find the policy definition ID:**
```bash
az policy definition list \
  --query "[?contains(displayName, 'Allowed locations')].{Name:name, DisplayName:displayName}" \
  --output table

# Output:
# Name                                  DisplayName
# e56962a6-4747-49cd-b67b-bf8b01975c4c  Allowed locations
# e765b5de-1225-4ba3-bd56-1ac6695af988  Allowed locations for resource groups
```

**Assign the policy (using az rest — to work around an Azure CLI bug when assigning at MG scope):**

> ⚠️ `az policy assignment create` has a known bug that causes a "MissingSubscription" error when assigning at MG scope.  
> Calling the REST API directly with `az rest` works correctly.

```bash
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

**Verify the assignment:**
```bash
# The atScope() filter is required — omitting it causes a FilterNotFound error
az rest \
  --method GET \
  --uri "https://management.azure.com/providers/Microsoft.Management/managementGroups/LTM-Corp/providers/Microsoft.Authorization/policyAssignments?api-version=2023-04-01&\$filter=atScope()" \
  --query "value[].{Name:name, DisplayName:properties.displayName, Enforcement:properties.enforcementMode}" \
  --output table

# Example output:
# Name              DisplayName                  Enforcement
# ----------------  ---------------------------  -----------
# allow-korea-only  Allow Korea regions only     Default
```

**Test the policy effect (verify that RG creation in japaneast is blocked):**
```bash
# This command should be denied by the policy
az group create \
  --name "test-policy-block-rg" \
  --location "japaneast"

# Expected error:
# (RequestDisallowedByPolicy) Resource 'test-policy-block-rg' was disallowed by policy.
# Policy: 'Allow Korea regions only'
```

> 💡 **Architectural point:** Why MG-level policies take precedence over subscription-level policies  
> → "Policies are inherited from parent scopes down to child scopes. They are applied in the order MG → Subscription → Resource Group, and a Deny policy at a higher scope cannot be overridden at a lower scope. This prevents subscription owners from bypassing enterprise-wide compliance."

---

### Lab Completion Checklist

| Item | Command | Expected Result |
|------|------|-----------|
| Verify MG exists | `az account management-group list` | LTM-Corp is shown |
| Verify subscription link | `az account management-group show --name LTM-Corp --expand` | Subscription ID is shown |
| Verify policy assignment | `az rest --method GET --uri ".../policyAssignments?api-version=2023-04-01"` | allow-korea-only is shown |

---

## Module 1: Azure Governance & Landing Zone (60 minutes)

### Learning Objectives
- Understand and design Management Group hierarchy
- Enforce compliance with Azure Policy
- Apply least-privilege principle with RBAC
- Protect critical assets with Resource Locks

### Key Concepts

> **Where this module fits:** The pre-work established the MG hierarchy and Korea region policy.  
> Module 1 adds a **Governance Layer at the subscription/RG level** on top of that.
> 
> ```
> Cumulative Landing Zone Structure (after Pre-work → Module 1)
> ───────────────────────────────────────────────────
> [Pre-work done] MG: LTM-Corp + Allow Korea Only policy
>       ↓ (added in this module)
> [Module 1 done] Per-RG RBAC + Owner tag Policy (Audit) + Resource Lock
> ───────────────────────────────────────────────────
> After Modules 2 and 3 → Full Landing Zone foundation complete
> ```

> A **Landing Zone** is the foundational environment that allows enterprises to use Azure safely and consistently.  
> Microsoft CAF (Cloud Adoption Framework) recommended order: **Governance → Network → Identity**

```
Enterprise Landing Zone Full Hierarchy (for reference)
[Tenant Root Group]
  └── [LTM-Corp]                    ← Enterprise MG (created in pre-work)
        ├── [LTM-Platform]          ← Platform team (network, security)
        │     ├── Connectivity Sub  ← Hub VNet subscription (Module 2)
        │     └── Identity Sub      ← Entra ID subscription (Module 3)
        └── [LTM-Workloads]         ← Business applications
              ├── Dev Sub           ← Development subscription (this lab subscription)
              └── Prod Sub          ← Production subscription (separate)
```

---

### Exercise 1.1: Verify Management Group and Subscription Hierarchy

**Verify via CLI:**
```bash
# List Management Groups in the current tenant
az account management-group list --output table

# View the structure under a specific MG
az account management-group show \
  --name "Tenant Root Group" \
  --expand --recurse
```

**Portal verification steps:**
1. Azure Portal → Type `Management groups` in the search bar
2. Click [Tenant Root Group] → View current hierarchy
3. Identify which group the subscription belongs to

> 💡 **Architectural point:** Why Management Groups are needed  
> → "They are used to apply the same policies to multiple subscriptions at once, and to aggregate cost reports by business unit."

---

### Exercise 1.2: Create Governance Resource Group and Tag Policy

```bash
# Create governance resource group
az group create \
  --name $RG_GOV \
  --location $LOCATION \
  --tags Environment=Lab Project=LTM-SA-Workshop Owner=inhwan.jung@outlook.kr

# Verify creation
az group show --name $RG_GOV --output table
```

---

### Exercise 1.3: Azure Policy — Assign Tag Enforcement Policy

> Azure Policy checks rules (Audit) or rejects (Deny) resource creation.

**Step 1: Look up the built-in policy definition ID**
```bash
az policy definition list \
  --query "[?contains(displayName, 'Require a tag')].{Name:name, DisplayName:displayName}" \
  --output table
```

**Step 2: Assign the policy (Audit mode)**
```bash
# Store the policy definition ID
POLICY_DEF_ID=$(az policy definition list \
  --query "[?displayName=='Require a tag on resources'].name" \
  --output tsv | head -1)

# Assign policy at resource group scope
az policy assignment create \
  --name "require-owner-tag" \
  --display-name "Require Owner tag on all resources" \
  --policy $POLICY_DEF_ID \
  --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RG_GOV" \
  --params '{"tagName": {"value": "Owner"}}' \
  --enforcement-mode DoNotEnforce
```

**Step 3: Verify compliance in the Portal**
1. Azure Portal → Search `Policy`
2. Click [Compliance]
3. Check the compliance status of the policy just assigned

---

### Exercise 1.4: RBAC — Role-Based Access Control

```bash
# List role assignments at current subscription scope
az role assignment list \
  --scope "/subscriptions/$(az account show --query id -o tsv)" \
  --output table

# Check role assignments at resource group level
az role assignment list \
  --resource-group $RG_GOV \
  --output table

# Check the Reader role definition
az role definition list \
  --query "[?roleName=='Reader'].{Name:roleName, Description:description}" \
  --output table

# Check detailed permissions of the Contributor role
az role definition list \
  --name "Contributor" \
  --output json | python -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d[0]['permissions'], indent=2))"
```

---

### Exercise 1.5: Resource Lock — Prevent Deletion of Critical Resources

> CanNotDelete: prevents deletion only | ReadOnly: allows read only (prevents both modification and deletion)

```bash
# Apply a delete lock to the resource group
az lock create \
  --name "DoNotDelete-GOV-RG" \
  --resource-group $RG_GOV \
  --lock-type CanNotDelete \
  --notes "Production governance resources - do not delete"

# Verify the lock
az lock list --resource-group $RG_GOV --output table

# Remove the lock (when finishing the exercise or moving to the next module)
az lock delete \
  --name "DoNotDelete-GOV-RG" \
  --resource-group $RG_GOV
```

> 💡 **Architectural point:** Difference between Resource Lock and Azure Policy  
> → "Policy enforces rules at the time new resources are created, while Lock prevents modification or deletion of existing resources. Using both together achieves complete governance."

---

## Module 2: Network Architecture — Hub-and-Spoke (60 minutes)

### Learning Objectives
- Design and implement Hub-Spoke VNet architecture
- Configure VNet Peering (bidirectional)
- Design Network Security Group (NSG) rules
- Secure VM access with Azure Bastion

### Key Concepts

**Hub-Spoke topology** — the standard pattern for enterprise Azure networking

```
[On-Premises] ←→ [VPN/ExpressRoute] ←→ [Hub VNet 10.0.0.0/16]
                                              │
                                    ┌─────────┴─────────┐
                                    ↓                   ↓
                        [Spoke1 VNet 10.1.0.0/16]  [Spoke2 VNet 10.2.0.0/16]
                         (App Team A dedicated)     (App Team B dedicated)
```

| Component | Role |
|-----------|------|
| Hub VNet | Centralized Firewall, Bastion, DNS, VPN Gateway |
| Spoke VNet | Isolated network per application/team |
| VNet Peering | Low-latency connection between Hub and Spoke (dedicated line) |

---

### Exercise 2.1: Create Resource Group and Hub VNet

> **Workshop Hub-Spoke configuration**: Implements a 2-VNet structure with Hub (Bastion+Jumpbox) + Spoke (App VMs+LB).

```bash
# Environment variables
export RG="ltmsa-security-rg"
export LOCATION="koreacentral"
export HUB_VNET="ltmsa-hub-vnet"
export SPOKE_VNET="ltmsa-spoke-vnet"

# Create Resource Group
az group create \
  --name $RG \
  --location $LOCATION \
  --tags Environment=Lab Project=LTM-SA-Workshop Owner=inhwan.jung@outlook.kr

# Hub VNet (10.0.0.0/16) + AzureBastionSubnet
# AzureBastionSubnet: fixed name, minimum /26, no NSG allowed (Azure requirement)
az network vnet create \
  --name $HUB_VNET \
  --resource-group $RG \
  --location $LOCATION \
  --address-prefix 10.0.0.0/16 \
  --subnet-name AzureBastionSubnet \
  --subnet-prefix 10.0.0.0/26

# Hub mgmt-snet (Jumpbox VM — accessible only via Bastion)
az network vnet subnet create \
  --name mgmt-snet \
  --resource-group $RG \
  --vnet-name $HUB_VNET \
  --address-prefix 10.0.1.0/24
```

---

### Exercise 2.2: Create Spoke VNet (Workload tier)

```bash
# Spoke VNet (10.1.0.0/16) — App VMs + LB placement
az network vnet create \
  --name $SPOKE_VNET \
  --resource-group $RG \
  --location $LOCATION \
  --address-prefix 10.1.0.0/16

# Spoke web-snet (App VMs + LB backend)
az network vnet subnet create \
  --name web-snet \
  --resource-group $RG \
  --vnet-name $SPOKE_VNET \
  --address-prefix 10.1.1.0/24
```

---

### Exercise 2.3: Configure VNet Peering (Hub ↔ Spoke bidirectional)

> ⚠️ Peering must be configured **bidirectionally**. One-way peering blocks traffic.  
> Once peering is complete, Bastion (Hub) can SSH into Spoke App VMs.

```bash
HUB_ID=$(az network vnet show --resource-group $RG --name $HUB_VNET --query id -o tsv)
SPOKE_ID=$(az network vnet show --resource-group $RG --name $SPOKE_VNET --query id -o tsv)

# Hub → Spoke: allows Bastion/Jumpbox to reach Spoke workloads
az network vnet peering create \
  --name hub-to-spoke \
  --resource-group $RG \
  --vnet-name $HUB_VNET \
  --remote-vnet "$SPOKE_ID" \
  --allow-vnet-access \
  --allow-forwarded-traffic

# Spoke → Hub: allows return traffic from Spoke to Hub services
az network vnet peering create \
  --name spoke-to-hub \
  --resource-group $RG \
  --vnet-name $SPOKE_VNET \
  --remote-vnet "$HUB_ID" \
  --allow-vnet-access \
  --allow-forwarded-traffic

# Verify peering state (check for Connected)
az network vnet peering list \
  --resource-group $RG \
  --vnet-name $HUB_VNET \
  --query "[].{Name:name, State:peeringState}" \
  --output table
```

---

### Exercise 2.4: NSG — Hub-Spoke Security Rule Design

> **Hub-Spoke NSG principles**:
> - **Hub mgmt-nsg**: Allow Jumpbox SSH only from Bastion / Allow Jumpbox→Spoke outbound
> - **Spoke web-nsg**: Allow SSH only from Hub Bastion subnet and Hub mgmt-snet (no internet SSH)
> - SSH source is Hub VNet IP range — source IP is preserved even when traffic traverses Peering

**Hub mgmt-snet NSG (Jumpbox):**
```bash
az network nsg create --name ltmsa-mgmt-nsg --resource-group $RG

# Jumpbox SSH: allow only from Hub Bastion
az network nsg rule create \
  --name allow-bastion-to-jumpbox \
  --nsg-name ltmsa-mgmt-nsg --resource-group $RG \
  --priority 100 --protocol Tcp --direction Inbound --access Allow \
  --source-address-prefixes 10.0.0.0/26 \
  --destination-port-ranges 22

# Jumpbox → Spoke web-snet outbound (explicit audit trail)
az network nsg rule create \
  --name allow-jumpbox-to-spoke \
  --nsg-name ltmsa-mgmt-nsg --resource-group $RG \
  --priority 200 --protocol Tcp --direction Outbound --access Allow \
  --source-address-prefixes 10.0.1.0/24 \
  --destination-address-prefixes 10.1.1.0/24 \
  --destination-port-ranges 22

# Attach NSG to mgmt-snet
az network vnet subnet update \
  --name mgmt-snet --vnet-name $HUB_VNET --resource-group $RG \
  --network-security-group ltmsa-mgmt-nsg
```

**Spoke web-snet NSG (App VMs):**
```bash
az network nsg create --name ltmsa-web-nsg --resource-group $RG

# SSH: allow only from Hub AzureBastionSubnet (reaches via Peering, source IP preserved)
az network nsg rule create \
  --name allow-bastion-ssh \
  --nsg-name ltmsa-web-nsg --resource-group $RG \
  --priority 100 --protocol Tcp --direction Inbound --access Allow \
  --source-address-prefixes 10.0.0.0/26 \
  --destination-port-ranges 22

# SSH: allow only from Hub Jumpbox (mgmt-snet)
az network nsg rule create \
  --name allow-jumpbox-ssh \
  --nsg-name ltmsa-web-nsg --resource-group $RG \
  --priority 110 --protocol Tcp --direction Inbound --access Allow \
  --source-address-prefixes 10.0.1.0/24 \
  --destination-port-ranges 22

# HTTP/80: LB frontend (internet)
az network nsg rule create \
  --name allow-http \
  --nsg-name ltmsa-web-nsg --resource-group $RG \
  --priority 200 --protocol Tcp --direction Inbound --access Allow \
  --destination-port-ranges 80

# App port 3000: LB health probe + direct access
az network nsg rule create \
  --name allow-app-3000 \
  --nsg-name ltmsa-web-nsg --resource-group $RG \
  --priority 210 --protocol Tcp --direction Inbound --access Allow \
  --destination-port-ranges 3000

# LB health probe
az network nsg rule create \
  --name allow-lb-probe \
  --nsg-name ltmsa-web-nsg --resource-group $RG \
  --priority 300 --protocol Tcp --direction Inbound --access Allow \
  --source-address-prefixes AzureLoadBalancer \
  --destination-port-ranges "*"

# Attach NSG to web-snet
az network vnet subnet update \
  --name web-snet --vnet-name $SPOKE_VNET --resource-group $RG \
  --network-security-group ltmsa-web-nsg

# Verify NSG rules
az network nsg rule list --nsg-name ltmsa-web-nsg --resource-group $RG --output table
```

> 💡 **Design point**: The NSG source address is the actual IP the packet originates from. When Bastion connects to a Spoke VM via Peering, the source is Hub's `10.0.0.0/26`. Therefore the `allow-bastion-ssh` rule on Spoke web-nsg must use `10.0.0.0/26` as source.
>
> Troubleshoot: Portal → select VM → Networking → "Effective security rules" tab → view active rule list

---

## Module 3: Security & Identity (60 minutes)

### Learning Objectives
- Manage Microsoft Entra ID users and groups
- Centrally manage secrets with Azure Key Vault
- Enable and analyze Microsoft Defender for Cloud
- Implement passwordless authentication with Managed Identity

### Key Concept: Zero Trust Security Model

```
"Never trust, always verify"

Layer 1: Identity  → Entra ID + MFA + Conditional Access
Layer 2: Network   → NSG + Azure Firewall + DDoS Protection
Layer 3: Compute   → Defender for Servers + Just-in-Time VM Access
Layer 4: Data      → Key Vault + encryption at rest/in transit
Layer 5: Monitoring → Defender for Cloud + Sentinel (SIEM)
```

> **Shared Responsibility Model**  
> Microsoft secures physical infrastructure, networking, and the hypervisor.  
> **Customers are directly responsible for data, access permissions, OS configuration, and applications.**  
> Defender for Cloud automatically evaluates configuration in the customer responsibility domain and provides Secure Score and recommendations.

---

### Exercise 3.1: Microsoft Entra ID — User and Group Management

```bash
# Check current tenant information
az account show --query tenantId

# List Entra ID users (using Graph API)
az ad user list \
  --output table \
  --query "[].{UPN:userPrincipalName, DisplayName:displayName}"

# Create a group for the lab
az ad group create \
  --display-name "Azure-SA-Team" \
  --mail-nickname "azure-sa-team" \
  --description "Azure Solution Architect Team"

# Add the currently logged-in user to the group
MY_USER_ID=$(az ad signed-in-user show --query id --output tsv)
GROUP_ID=$(az ad group list \
  --filter "displayName eq 'Azure-SA-Team'" \
  --query "[].id" --output tsv)

az ad group member add \
  --group $GROUP_ID \
  --member-id $MY_USER_ID

# Verify group members
az ad group member list --group $GROUP_ID --output table
```

---

### Exercise 3.2: Azure Key Vault — Centralized Secret Management

> Key Vault principle: **Never hard-code passwords in code!**  
> Centrally manage all connection strings, API keys, and certificates in Key Vault.

```bash
# Create security resource group
az group create \
  --name $RG_SEC \
  --location $LOCATION \
  --tags Environment=Lab Project=LTM-SA-Workshop

# Generate Key Vault name (must be globally unique)
KV_NAME="${PREFIX}-kv-$(date +%s | tail -c 6)"
echo "Key Vault name: $KV_NAME"

# Create Key Vault
az keyvault create \
  --name $KV_NAME \
  --resource-group $RG_SEC \
  --location $LOCATION \
  --sku standard \
  --enable-rbac-authorization true \
  --enable-soft-delete true \
  --soft-delete-retention-days 7 \
  --enable-purge-protection false    # For lab only - true is recommended for production

# Grant yourself the Key Vault Secret Officer role
KV_ID=$(az keyvault show --name $KV_NAME --resource-group $RG_SEC --query id --output tsv)
MY_USER_ID=$(az ad signed-in-user show --query id --output tsv)

az role assignment create \
  --assignee $MY_USER_ID \
  --role "Key Vault Secrets Officer" \
  --scope $KV_ID

# Store a secret (example: DB connection string)
az keyvault secret set \
  --vault-name $KV_NAME \
  --name "db-connection-string" \
  --value "Server=sql-ltmsa.database.windows.net;Database=appdb;User=appuser;Password=P@ssw0rd123!"

# Read the secret value
az keyvault secret show \
  --vault-name $KV_NAME \
  --name "db-connection-string" \
  --query "value" --output tsv

# Check version history (secret change log)
az keyvault secret list-versions \
  --vault-name $KV_NAME \
  --name "db-connection-string" \
  --output table
```

---

### Exercise 3.3: Microsoft Defender for Cloud — Activation and Secure Score Analysis

> Defender for Cloud = **CSPM** + **CWPP**  
> - **CSPM** (Cloud Security Posture Management): Detects and scores security vulnerabilities and compliance violations in resource configuration  
> - **CWPP** (Cloud Workload Protection Platform): Detects and blocks runtime threats in VMs, containers, databases, etc. in real time

#### Step 1: Enable Defender Standard Tier

```bash
# Enable VM protection plan (Standard = all paid Defender features)
az security pricing create \
  --name "VirtualMachines" \
  --tier "Standard"

# Verify overall Defender activation status
az security pricing list --output table
```

> ⚠️ **Cost note**: Standard Tier is billed per VM. Revert to Free Tier after completing the lab.  
> (See Defender recovery step in Lab Clean-up section)

#### Step 2: Configure Auto-Provisioning (automatic agent installation)

```bash
# Check current auto-provisioning status
az security auto-provisioning-setting list --output table

# Enable AMA auto-installation via Defender for Servers
# API key name is "MicrosoftMonitoringAgent" (legacy naming retained in the REST API)
az security auto-provisioning-setting update \
  --name "MicrosoftMonitoringAgent" \
  --auto-provision "On"
```

> Enabling auto-provisioning causes AMA/MMA agents to be automatically installed on subsequently created VMs, expanding the Defender detection scope.

#### Step 3: Analyze Secure Score and Recommendations

**Portal check:**
1. Azure Portal → `Microsoft Defender for Cloud`
2. **Overview** → **Secure Score** — check current score (target: 75+)
3. **Recommendations** → compare unresolved items by severity
4. **Security alerts** → check for suspicious activity

**CLI check:**
```bash
# Query Secure Score
az security secure-score show \
  --name "ascScore" \
  --output table

# Filter Unhealthy items — top priority actions
az security assessment list \
  --query "[?status.code=='Unhealthy'].{name:displayName, severity:metadata.severity, status:status.code}" \
  --output table
```

---

### Exercise 3.4: Managed Identity — Passwordless Authentication

> Managed Identity = An "Azure employee badge" automatically issued to a VM  
> Allows access to Azure services (Key Vault, Storage, etc.) without any passwords in code

```bash
# Create a VM with System-assigned Managed Identity
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

echo "Creating VM... (approximately 3 minutes)"

# Grant the VM Managed Identity read access to Key Vault
VM_PRINCIPAL_ID=$(az vm show \
  --name "${PREFIX}-demo-vm" \
  --resource-group $RG_SEC \
  --query "identity.principalId" --output tsv)

az role assignment create \
  --assignee $VM_PRINCIPAL_ID \
  --role "Key Vault Secrets User" \
  --scope $KV_ID

echo "✅ This VM can now read Key Vault secrets without any credentials."
```

---

### Exercise 3.5: NSG Security Hardening — SSH Port Access Restriction

> One of the most common Defender for Cloud recommendations: **"Do not open SSH (port 22) to the entire internet"**  
> Remove the internet-wide SSH allow rule from the existing NSG and restrict access to a specific IP.

```bash
# Get NSG name in the lab resource group
NSG_NAME=$(az network nsg list \
  --resource-group $RG_SEC \
  --query "[0].name" -o tsv)
echo "NSG: $NSG_NAME"

# Delete the existing internet-wide SSH allow rule
az network nsg rule delete \
  --resource-group $RG_SEC \
  --nsg-name $NSG_NAME \
  --name "default-allow-ssh"

# Add a rule allowing SSH only from your public IP
# Find your public IP: curl ifconfig.me
MY_IP=$(curl -s ifconfig.me)
echo "My IP: $MY_IP"

az network nsg rule create \
  --resource-group $RG_SEC \
  --nsg-name $NSG_NAME \
  --name "Allow-SSH-MyIP" \
  --protocol Tcp \
  --direction Inbound \
  --priority 1000 \
  --source-address-prefixes "$MY_IP" \
  --source-port-ranges "*" \
  --destination-address-prefixes "*" \
  --destination-port-ranges 22 \
  --access Allow

# Verify applied NSG rules
az network nsg rule list \
  --resource-group $RG_SEC \
  --nsg-name $NSG_NAME \
  --output table
```

> **Architecture point:** Blocking SSH entirely and using Azure Bastion aligns more closely with Zero Trust principles.  
> JIT (Just-in-Time) VM Access is available with Defender for Servers Standard — it temporarily opens specific ports only during the required time window.

---

### Exercise 3.6: Security Alert Monitoring

> Defender for Cloud generates an **Alert** when it detects suspicious activity.  
> Use the CLI to query the current subscription's alert list and filter by severity.

```bash
# Query all security alerts in the subscription
az security alert list --output table

# Filter alerts scoped to the resource group
az security alert list \
  --resource-group $RG_SEC \
  --output table

# Show only High-severity alerts
az security alert list \
  --query "[?properties.severity=='High'].{title:properties.alertDisplayName, severity:properties.severity, time:properties.startTimeUtc}" \
  --output table
```

> **Portal check:** Azure Portal → Defender for Cloud → Security alerts  
> Click an alert → view affected resources, MITRE ATT&CK tactics, and remediation steps

---

### Exercise 3.7: External Attack Surface Management (EASM) and CASB Concepts

> **Defender EASM (External Attack Surface Management)**  
> Continuously discovers and scans assets exposed to the internet (public IPs, domains, subdomains, SSL certificates, etc.) from an attacker's perspective. Prevents "assets the organization is unaware of" from becoming attack entry points.

```bash
# Check public IPs assigned to VM (externally exposed assets)
az vm list-ip-addresses \
  --resource-group $RG_SEC \
  --name "${PREFIX}-demo-vm" \
  --output table

# Detailed public IP resource query
az network public-ip list \
  --resource-group $RG_SEC \
  --query "[].{name:name, IP:ipAddress, SKU:sku.name, allocation:publicIPAllocationMethod}" \
  --output table
```

> **Portal check (EASM):** Azure Portal → Defender for Cloud → Workload protections → EASM  
> Note: Asset discovery may take several hours to days to reflect the actual environment.

---

> **Defender for Cloud Apps (CASB — Cloud Access Security Broker)**  
> Provides visibility into SaaS app usage within the organization and detects sensitive data sharing and anomalous behavior.  
> Key features:
> - **Cloud Discovery**: Detect Shadow IT (unauthorized SaaS) in use within the organization
> - **App governance**: Allow/block policies, risk score-based app control
> - **Information protection policies**: Rules for detecting external sharing of sensitive data
> - **Session policies**: Block downloads via Conditional Access App Control
>
> Portal: `https://security.microsoft.com` → Cloud Apps menu (no CLI support — portal navigation exercise)

---

## Module 4: Cloud Resiliency & High Availability (50 minutes)

### Learning Objectives
- Implement high-availability architecture with Availability Zones
- Configure Standard Load Balancer
- Set up recovery policies with Azure Backup
- RTO/RPO concepts and tier-based design

### Key Concepts: RTO vs RPO

| Term | Definition | Example Target |
|------|------|-----------|
| **RTO** (Recovery Time Objective) | Maximum allowable time to recover | "Recover within 4 hours" |
| **RPO** (Recovery Point Objective) | Maximum allowable data loss window | "Up to 1 hour of data loss" |
| **Availability Zone** | Independent datacenters within the same region | Zone 1, 2, 3 each independent |
| **Region Pair** | Paired region for natural disaster preparedness | Korea Central ↔ Korea South |

**Tier-based HA design guidelines:**

| Tier | RTO | RPO | Solution |
|------|-----|-----|--------|
| Tier 1 (Mission Critical) | < 1 hour | < 15 minutes | Zone-redundant + ASR + RA-GRS |
| Tier 2 (Business Critical) | < 4 hours | < 1 hour | Availability Set + Azure Backup |
| Tier 3 (Standard) | < 24 hours | < 24 hours | Azure Backup once daily |

---

### Exercise 4.1: Deploy Zone-Redundant VMs

```bash
# Create ops resource group
az group create \
  --name $RG_OPS \
  --location $LOCATION \
  --tags Environment=Lab Project=LTM-SA-Workshop

# Deploy VM in Zone 1
# ⚠️ Standard_B1s has insufficient capacity in Korea Central → use Standard_D2s_v3
az vm create \
  --name "${PREFIX}-vm-zone1" \
  --resource-group $RG_OPS \
  --location $LOCATION \
  --image Ubuntu2204 \
  --size Standard_D2s_v3 \
  --zone 1 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --no-wait

# Deploy VM in Zone 2
az vm create \
  --name "${PREFIX}-vm-zone2" \
  --resource-group $RG_OPS \
  --location $LOCATION \
  --image Ubuntu2204 \
  --size Standard_D2s_v3 \
  --zone 2 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --no-wait

echo "Deploying VMs to Zone 1 and Zone 2... (approximately 3 minutes)"
```

---

### Exercise 4.2: Configure Standard Load Balancer

> Zone-redundant Standard LB = Service continues even during a single Zone failure

```bash
# Create Zone-redundant Public IP
az network public-ip create \
  --name "${PREFIX}-lb-pip" \
  --resource-group $RG_OPS \
  --location $LOCATION \
  --sku Standard \
  --zone 1 2 3 \
  --allocation-method Static

# Create Standard Load Balancer
az network lb create \
  --name "${PREFIX}-std-lb" \
  --resource-group $RG_OPS \
  --location $LOCATION \
  --sku Standard \
  --frontend-ip-name "frontend-ip" \
  --public-ip-address "${PREFIX}-lb-pip" \
  --backend-pool-name "backend-pool"

# Add health probe (HTTP check on port 80, 15-second interval, remove after 2 failures)
az network lb probe create \
  --name "http-probe" \
  --lb-name "${PREFIX}-std-lb" \
  --resource-group $RG_OPS \
  --protocol Http \
  --port 80 \
  --path "/" \
  --interval 15 \
  --threshold 2

# Add LB rule (distribute port 80)
az network lb rule create \
  --name "http-rule" \
  --lb-name "${PREFIX}-std-lb" \
  --resource-group $RG_OPS \
  --frontend-ip-name "frontend-ip" \
  --backend-pool-name "backend-pool" \
  --probe-name "http-probe" \
  --protocol Tcp \
  --frontend-port 80 \
  --backend-port 80 \
  --idle-timeout 15 \
  --enable-tcp-reset true

echo "✅ Load Balancer configuration complete"
```

---

### Exercise 4.3: Azure Backup — Configure Recovery Services Vault

> Azure Backup = Agentless backup for VMs, SQL DBs, Files, and more

**Perform in the Portal:**
1. Azure Portal → `Recovery Services vaults` → [+ Create]
2. Basic information:
   - Resource group: `ltmsa-ops-rg`
   - Vault name: `ltmsa-rsv`
   - Region: Korea Central
3. [Review + create] → Go to RSV after deployment completes
4. Click [Backup] → Workload: Azure, Target: Virtual machine
5. Backup policy: `DefaultPolicy` (daily at 2 AM, retain 30 days)
6. Add VM: Select `ltmsa-vm-zone1` → [Enable backup]

**Verify via CLI:**
```bash
# List RSVs
az backup vault list \
  --resource-group $RG_OPS \
  --output table

# List backup policies
az backup policy list \
  --vault-name "ltmsa-rsv" \
  --resource-group $RG_OPS \
  --output table
```

> 💡 **Architectural point:** Difference between Backup and Disaster Recovery (ASR)  
> → "Backup addresses accidental deletion or data corruption (RPO: hours to days). Azure Site Recovery is a DR solution for full regional outages, targeting RPO/RTO of minutes."

---

## Module 5: Azure Monitor & Telemetry (50 minutes)

### Learning Objectives
- Configure Log Analytics Workspace
- Collect logs with Diagnostic Settings
- Practice 5 KQL (Kusto Query Language) queries
- Configure threshold-based alerts with Alert Rules

### Key Concept: Azure Monitor Data Flow

```
[Azure Resource] → [Diagnostic Settings] → [Log Analytics Workspace]
                                                    │
                                          ┌─────────┴──────────┐
                                          ↓                    ↓
                                     [KQL Queries]       [Alert Rules]
                                          │                    │
                                     [Dashboards]      [Action Group]
                                                               │
                                                 [Email / Teams / PagerDuty]
```

#### AMA Internal Pipeline Detail

```
VM (Linux)
  ├─ telegraf ──influx socket──► mdsd ──HTTPS──► ODS endpoint        → Perf / Heartbeat table
  │   └─ collects CPU/Disk metrics   └─ Syslog socket ◄── rsyslog    → Syslog table
  │
  └─ amacoreagent ──port 13005──► mdsd (Perf aggregation assist)
       └─ receives DCR config from MCS → generates telegraf conf

MCS (Azure Monitor Config Service)
  └─ deploys DCR config ──gig token──► ODS (72b62554-...ods.opinsights.azure.com)
```

> **Key processes**: `mdsd` (main collection engine), `amacoreagent` (DCR config management), `telegraf` (OS metric collection)  
> `Heartbeat`·`Perf` are sent directly mdsd → ODS / `Syslog` goes rsyslog → mdsd → ODS

#### AMA vs MMA (Legacy) Comparison

| Item | MMA (Legacy) | AMA (Current) |
|------|-------------|---------------|
| Authentication | Workspace ID + Key (security risk) | Managed Identity (Zero Trust) |
| Collection config | Fixed at agent install | Defined independently via DCR — changeable at any time |
| Multi-destination | Single Workspace | Perf → monitoring LAW / Syslog → Sentinel LAW (separate routing) |
| Linux support | Python-dependent | Built-in (no Python required) |
| Lifecycle | **End of support August 2024** | Current standard (v1.42+) |

#### Table Plans (key to cost optimization)

| Plan | KQL capabilities | Cost | Use case |
|------|-----------------|------|----------|
| **Analytics** | All KQL (join, union, ML) | High | Heartbeat, Perf, Syslog — operational analysis |
| **Basic** | Simple filter/aggregate only (no join) | Low (~1/4) | High-volume raw log long-term retention |

> Retention: **Interactive** (default 30 days, instant query) + **Archival** (up to 7 years, low-cost long-term)

---

### Exercise 5.1: Create Log Analytics Workspace

```bash
# Create Log Analytics Workspace
az monitor log-analytics workspace create \
  --workspace-name "${PREFIX}-law" \
  --resource-group $RG_OPS \
  --location $LOCATION \
  --sku PerGB2018 \
  --retention-time 30 \
  --tags Environment=Lab Project=LTM-SA-Workshop

# Get Workspace GUID (customerId — used in KQL portal and agent config) and Key
LAW_WORKSPACE_GUID=$(az monitor log-analytics workspace show \
  --workspace-name "${PREFIX}-law" \
  --resource-group $RG_OPS \
  --query customerId --output tsv)

# Get Workspace ARM Resource ID (used in DCR, diagnostic-settings, alert rules)
LAW_RESOURCE_ID=$(az monitor log-analytics workspace show \
  --workspace-name "${PREFIX}-law" \
  --resource-group $RG_OPS \
  --query id --output tsv)

LAW_KEY=$(az monitor log-analytics workspace get-shared-keys \
  --workspace-name "${PREFIX}-law" \
  --resource-group $RG_OPS \
  --query primarySharedKey --output tsv)

echo "Workspace GUID:        $LAW_WORKSPACE_GUID"
echo "Workspace Resource ID: $LAW_RESOURCE_ID"
echo "Primary Key:           $LAW_KEY"
```

---

### Exercise 5.2: Log Collection Setup — AMA Agent + DCR + Activity Log

> **Why this matters for log search:**
> - `az monitor diagnostic-settings --metrics AllMetrics` only fills the `AzureMetrics` table (platform metrics)
> - `Heartbeat`, `Perf`, `Syslog` tables require the **Azure Monitor Agent (AMA)** extension + **Data Collection Rule (DCR)**
> - `SecurityEvent` is **Windows-only** — Ubuntu VMs use `Syslog` instead
> - `AzureActivity` requires a **subscription-level** diagnostic setting, not VM-level

**Log collection table reference:**

| Table | Source | Setup Required |
|-------|--------|----------------|
| `AzureMetrics` | Platform metrics (CPU, disk, network) | `diagnostic-settings --metrics AllMetrics` (already done) |
| `Heartbeat` | VM connectivity status | AMA agent extension |
| `Perf` | Guest OS performance counters | AMA + DCR (performanceCounters) |
| `Syslog` | Linux OS logs, SSH, auth failures | AMA + DCR (syslog) |
| `SecurityEvent` | Windows login events | Windows VMs only — N/A for Ubuntu |
| `AzureActivity` | Resource create/delete/change events | Subscription-level diagnostic setting |

---

#### Step 1: Enable Managed Identity on VMs (AMA prerequisite)

```powershell
$PREFIX = "ltmsa"; $RG_SEC = "$PREFIX-security-rg"; $RG_OPS = "$PREFIX-ops-rg"; $LOCATION = "koreacentral"

# AMA requires system-assigned managed identity
az vm identity assign --resource-group $RG_SEC --name "$PREFIX-demo-vm"
az vm identity assign --resource-group $RG_SEC --name "$PREFIX-demo-vm-2"

# Verify
az vm identity show --resource-group $RG_SEC --name "$PREFIX-demo-vm" `
  --query "{type:type, principalId:principalId}" --output table
```

---

#### Step 2: Create Data Collection Rule (DCR)

```powershell
$LAW_ID = az monitor log-analytics workspace show `
  --workspace-name "$PREFIX-law" --resource-group $RG_OPS --query id -o tsv

$SUB_ID = az account show --query id -o tsv

# Build DCR spec (ARM REST body) — PowerShell here-string expands $LAW_ID and $PREFIX
$DCR_BODY = @"
{
  "location": "$LOCATION",
  "properties": {
    "dataSources": {
      "syslog": [{
        "name": "syslog-ds",
        "streams": ["Microsoft-Syslog"],
        "facilityNames": ["auth", "cron", "daemon", "syslog", "user"],
        "logLevels": ["Warning", "Error", "Critical", "Alert", "Emergency"]
      }],
      "performanceCounters": [{
        "name": "perf-ds",
        "streams": ["Microsoft-Perf"],
        "samplingFrequencyInSeconds": 60,
        "counterSpecifiers": [
          "\\\\Processor Information(_Total)\\\\% Processor Time",
          "\\\\Memory\\\\Available Bytes",
          "\\\\Logical Disk(/)\\\\% Free Space",
          "\\\\Network Interface(*)\\\\Bytes Total/sec"
        ]
      }]
    },
    "destinations": {
      "logAnalytics": [{"workspaceResourceId": "$LAW_ID", "name": "$PREFIX-law"}]
    },
    "dataFlows": [{
      "streams": ["Microsoft-Syslog", "Microsoft-Perf"],
      "destinations": ["$PREFIX-law"]
    }]
  }
}
"@

az rest --method PUT `
  --uri "https://management.azure.com/subscriptions/$SUB_ID/resourceGroups/$RG_OPS/providers/Microsoft.Insights/dataCollectionRules/$PREFIX-dcr?api-version=2022-06-01" `
  --body $DCR_BODY

echo "✅ DCR created"
```

> ⚠️ **Linux AMA counter name notes**  
> | Incorrect name (Windows style) | Correct Linux name | Difference |
> |-------------------------------|-------------------|------------|
> | `\\Memory\\Available MBytes` | `\\Memory\\Available Bytes` | Linux AMA (telegraf) uses bytes |
> | `\\Processor(_Total)\\% Processor Time` | `\\Processor Information(_Total)\\% Processor Time` | Object name changed in AMA v1.42+ |
> | `\\LogicalDisk(_Total)\\...` | `\\Logical Disk(/)\\...` | Must specify slash (/) path explicitly |
>
> Entering an incorrect name does not produce an error — the counter is silently excluded from `metricCounters.json`.  
> Verify: SSH into VM then run `cat /etc/opt/microsoft/azuremonitoragent/config-cache/configchunks/*.json | python3 -m json.tool | grep -i counterspeci`

---

#### Step 3: Associate DCR with VMs

```powershell
$DCR_ID = az rest --method GET `
  --uri "https://management.azure.com/subscriptions/$SUB_ID/resourceGroups/$RG_OPS/providers/Microsoft.Insights/dataCollectionRules/$PREFIX-dcr?api-version=2022-06-01" `
  --query id -o tsv

$VM1_ID = az vm show --resource-group $RG_SEC --name "$PREFIX-demo-vm"   --query id -o tsv
$VM2_ID = az vm show --resource-group $RG_SEC --name "$PREFIX-demo-vm-2" --query id -o tsv

az monitor data-collection rule association create `
  --resource $VM1_ID --name "$PREFIX-dcra-vm1" --rule-id $DCR_ID

az monitor data-collection rule association create `
  --resource $VM2_ID --name "$PREFIX-dcra-vm2" --rule-id $DCR_ID

echo "✅ DCR associated with both VMs"
```

---

#### Step 4: Install AMA Extension on VMs

```powershell
foreach ($VM in @("$PREFIX-demo-vm", "$PREFIX-demo-vm-2")) {
  Write-Host "Installing AMA on $VM ..."
  az vm extension set `
    --resource-group $RG_SEC `
    --vm-name $VM `
    --name AzureMonitorLinuxAgent `
    --publisher Microsoft.Azure.Monitor `
    --enable-auto-upgrade true
  Write-Host "✅ $VM done"
}
```

> ⏳ After AMA installation, wait **5–10 minutes** before querying — logs need time to flow.

---

#### Step 5: Route Activity Log to Log Analytics (Subscription Level)

```powershell
# Subscription-level Activity Log uses a dedicated command (not --resource-group or --resource)
# Use az monitor diagnostic-settings subscription create (different from az monitor diagnostic-settings create)
az monitor diagnostic-settings subscription create `
  --name "activity-log-to-law" `
  --location $LOCATION `
  --workspace $LAW_ID `
  --logs '[
    {"category":"Administrative","enabled":true},
    {"category":"Security","enabled":true},
    {"category":"Alert","enabled":true},
    {"category":"Policy","enabled":true}
  ]'

# Verify
az monitor diagnostic-settings subscription list --query "[].{Name:name,Workspace:workspaceId}" -o table

echo "✅ Activity log now routed to Log Analytics"
```

> ⚠️ **CLI note**: `az monitor diagnostic-settings create --resource "/subscriptions/$SUB_ID"` is not supported at subscription level → use `az monitor diagnostic-settings subscription create`  
> Portal alternative: Azure Portal → Monitor → Activity Log → Export Activity Logs → +Add diagnostic setting

---

#### Step 6: Verify Log Collection Status

```powershell
# AMA extension state
az vm extension list --resource-group $RG_SEC --vm-name "$PREFIX-demo-vm" `
  --query "[?name=='AzureMonitorLinuxAgent'].{Name:name,State:provisioningState,Version:typeHandlerVersion}" `
  --output table

# DCR associations
az monitor data-collection rule association list `
  --resource (az vm show --resource-group $RG_SEC --name "$PREFIX-demo-vm" --query id -o tsv) `
  --query "[].{Name:name, DCR:dataCollectionRuleId}" --output table

# Activity Log diagnostic settings
az monitor diagnostic-settings list --resource "/subscriptions/$SUB_ID" `
  --query "[].{Name:name, Workspace:workspaceId}" --output table
```

**Portal check:** Log Analytics → `ltmsa-law` → Logs → run this table existence query:
```kusto
// Check which tables have data (run after 10 min)
union withsource=TableName Heartbeat, Perf, Syslog, AzureActivity, AzureMetrics
| where TimeGenerated > ago(1h)
| summarize RowCount = count() by TableName
| order by TableName asc
```

---

#### Step 7: AMA Pipeline Deep Verification (Troubleshooting)

If Heartbeat is visible but Perf data is missing, diagnose with the steps below:

```bash
# 1. Verify all 3 AMA processes are running
ps aux | grep -E "(mdsd|amacoreagent|telegraf)"
# Expected: at least one process each for mdsd, amacoreagent, and telegraf

# 2. Check telegraf ↔ mdsd socket connection
ss -xp | grep default_influx.socket
# Expected: 2 ESTAB entries (one telegraf side + one mdsd side)

# 3. List counters loaded from the DCR
cat /etc/opt/microsoft/azuremonitoragent/config-cache/configchunks/*.json \
  | python3 -m json.tool 2>/dev/null | grep -A2 "counterSpecifiers"
# Expected: all 4 configured counters must appear — if missing, check DCR name

# 4. Check mdsd ODS connection status
cat /var/opt/microsoft/azuremonitoragent/log/mdsd.hr.json \
  | python3 -m json.tool | grep -E "(AMCS|ODS|AzureMonitor)"
# Expected: "AMCS": true, "ODS": true

# 5. Inspect actual Perf data transmission logs
tail -50 /var/opt/microsoft/azuremonitoragent/log/mdsd.info \
  | grep -i "perf\|telegraf\|influx"
```

**Resolution by symptom:**

| Symptom | Cause | Resolution |
|---------|-------|------------|
| `mdsd` missing, others normal | mdsd crash | `systemctl restart azuremonitoragent` |
| telegraf `broken pipe` error | Socket reconnection failed after mdsd restart | `pkill telegraf && pkill amacoreagent` → amacoreagent auto-restarts and recreates telegraf |
| configchunks files are empty | AzExtension ↔ mdsd timing race condition | **VM reboot** — resolves once boot order normalizes |
| Some Perf counters missing | Incorrect counter name | Recreate DCR (see Step 2 warning) |
| Data delayed ~5–15 min | Log Analytics ingestion pipeline latency | Normal — wait at least 15 min after install before running KQL |

---

### Exercise 5.3: KQL Query Practice (5 Key Queries)

> Portal access: Azure Portal → Log Analytics workspaces → `ltmsa-law` → Logs

> **Linux vs Windows table differences:**  
> | Windows | Linux (Ubuntu) | Note |
> |---------|----------------|------|
> | `SecurityEvent` (EventID 4625) | `Syslog` (Facility: auth) | Login failure detection |
> | `Perf` CounterName: `Available MBytes` | `Perf` CounterName: `Available Bytes` | AMA reports bytes, not MB |

---

**Query 1: VM Heartbeat — Check Connectivity Status**
```kusto
// Check if VMs are alive (heartbeat within the last 1 hour)
Heartbeat
| where TimeGenerated > ago(1h)
| summarize LastHeartbeat=max(TimeGenerated) by Computer
| order by LastHeartbeat desc
```
> If no results: AMA extension is not installed or DCR is not associated → re-run Exercise 5.2.

---

**Query 2: CPU Utilization Trend — Performance Analysis**
```kusto
// VM CPU utilization - last 1 hour, 5-minute intervals
Perf
| where TimeGenerated > ago(1h)
| where ObjectName == "Processor Information" and CounterName == "% Processor Time"
| where InstanceName == "_Total"
| summarize AvgCPU = avg(CounterValue) by bin(TimeGenerated, 5m), Computer
| render timechart
```

---

**Query 3: Memory Utilization — Capacity Planning**
```kusto
// Available memory (AMA reports Available Bytes, not MBytes)
Perf
| where TimeGenerated > ago(30m)
| where ObjectName == "Memory" and CounterName == "Available Bytes"
| summarize AvgBytes = avg(CounterValue) by Computer
| extend AvgMemGB = round(AvgBytes / 1073741824, 2)
| project Computer, AvgMemGB
| order by AvgMemGB asc
```
> ⚠️ AMA on Linux reports `Available Bytes` (not `Available MBytes` as in legacy MMA). Divide by 1,073,741,824 for GB.

---

**Query 4: Linux Security Events — SSH/Auth Failure Detection**
```kusto
// Linux auth failures via Syslog (replaces SecurityEvent which is Windows-only)
Syslog
| where TimeGenerated > ago(24h)
| where Facility in ("auth", "authpriv")
| where SyslogMessage has "Failed password"
    or SyslogMessage has "authentication failure"
    or SyslogMessage has "Invalid user"
| summarize FailureCount = count() by HostName, SyslogMessage
| where FailureCount > 3
| order by FailureCount desc
```
> `SecurityEvent` is Windows-only. Ubuntu VMs write auth events to the `Syslog` table.

---

**Query 5: Activity Log — Track Resource Changes**
```kusto
// Resource creation/deletion events in the last 24 hours
AzureActivity
| where TimeGenerated > ago(24h)
| where OperationNameValue has "write" or OperationNameValue has "delete"
| where ActivityStatusValue == "Success"
| project TimeGenerated, Caller, OperationNameValue, ResourceGroup, Resource
| order by TimeGenerated desc
| take 50
```
> If no results: run Exercise 5.2 Step 5 (subscription-level diagnostic setting).

---

**Bonus: VM metrics already available from diagnostic-settings (AllMetrics)**
```kusto
// AzureMetrics — populated immediately by diagnostic-settings, no AMA needed
AzureMetrics
| where TimeGenerated > ago(1h)
| where MetricName == "Percentage CPU"
| summarize AvgCPU = avg(Average) by bin(TimeGenerated, 5m), Resource
| render timechart
```

---

### Exercise 5.3b: Percentile Queries — Outlier Detection

> **Why percentiles instead of averages?**  
> Average masks outliers. A VM that runs at 20% CPU for 55 minutes and 100% for 5 minutes shows an average of ~27% — but P95 reveals the spike.  
> **Rule of thumb:** use P95 as alert threshold, compare P50 vs P95 gap to spot unstable workloads.

---

**Query 6: CPU Percentile Distribution (P50 / P90 / P95 / P99)**
```kusto
// CPU percentile profile per VM — last 24 hours
Perf
| where TimeGenerated > ago(24h)
| where ObjectName == "Processor Information" and CounterName == "% Processor Time"
| where InstanceName == "_Total"
| summarize
    P50 = percentile(CounterValue, 50),
    P90 = percentile(CounterValue, 90),
    P95 = percentile(CounterValue, 95),
    P99 = percentile(CounterValue, 99),
    MaxCPU = max(CounterValue),
    AvgCPU = avg(CounterValue)
  by Computer
| extend Skew = round(P95 - P50, 1)    // large gap = spiky workload
| order by P95 desc
```
> `Skew = P95 - P50`: Large gap between P95 and median indicates frequent CPU spikes.

---

**Query 7: CPU Time-Series — P50 vs P95 Overlay**
```kusto
// Compare median vs 95th percentile over time — spot when spikes start
Perf
| where TimeGenerated > ago(6h)
| where ObjectName == "Processor Information" and CounterName == "% Processor Time"
| where InstanceName == "_Total"
| summarize
    P50 = percentile(CounterValue, 50),
    P95 = percentile(CounterValue, 95)
  by bin(TimeGenerated, 5m), Computer
| render timechart
```

---

**Query 8: IQR-Based Outlier Detection (Statistical)**
```kusto
// IQR method: flag data points more than 1.5×IQR beyond Q1/Q3
// Classic box-plot outlier definition — no assumption about normal distribution
let baseline = 
    Perf
    | where TimeGenerated > ago(24h)
    | where ObjectName == "Processor Information" and CounterName == "% Processor Time"
    | where InstanceName == "_Total"
    | summarize
        Q1 = percentile(CounterValue, 25),
        Q3 = percentile(CounterValue, 75)
      by Computer;
Perf
| where TimeGenerated > ago(24h)
| where ObjectName == "Processor Information" and CounterName == "% Processor Time"
| where InstanceName == "_Total"
| join kind=inner baseline on Computer
| extend IQR = Q3 - Q1
| extend LowerFence = Q1 - 1.5 * IQR
| extend UpperFence = Q3 + 1.5 * IQR
| where CounterValue > UpperFence or CounterValue < LowerFence
| project TimeGenerated, Computer, CounterValue, UpperFence, LowerFence
| order by CounterValue desc
```
> IQR = Q3 − Q1. Values exceeding `UpperFence = Q3 + 1.5×IQR` are outliers. No normal distribution assumption required — valid for skewed distributions.

---

**Query 9: Memory Percentile + Pressure Index**
```kusto
// Memory availability percentiles (AMA: Available Bytes)
Perf
| where TimeGenerated > ago(24h)
| where ObjectName == "Memory" and CounterName == "Available Bytes"
| summarize
    P5_AvailGB  = round(percentile(CounterValue, 5)  / 1073741824, 2),  // worst case
    P50_AvailGB = round(percentile(CounterValue, 50) / 1073741824, 2),  // typical
    P95_AvailGB = round(percentile(CounterValue, 95) / 1073741824, 2),  // best case
    MinAvailGB  = round(min(CounterValue) / 1073741824, 2)
  by Computer
| extend PressureSignal = iff(P5_AvailGB < 0.5, "⚠ HIGH", iff(P5_AvailGB < 1.0, "WARN", "OK"))
| order by P5_AvailGB asc
```
> P5 (5th percentile) represents the worst-case available memory. Below 0.5 GB indicates OOM risk.

---

**Query 10: AzureMetrics CPU Percentile (no AMA required)**
```kusto
// AzureMetrics is available immediately from diagnostic-settings — no agent needed
// Use this if AMA is not yet installed
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

> 💡 **Architectural point:** Alert threshold design  
> → "Use P95-based thresholds instead of simple averages. Averages dilute momentary spikes, and a large P5/P95 gap signals an unstable workload. The IQR method requires no normal distribution assumption, making it applicable to skewed workloads."

---

### Exercise 5.3c: App Performance & LB Health Queries

Queries in this section are split into **Group A** (AMA-based, no additional setup), **Group B** (requires LB Diagnostic Settings), and **Group C** (app inference from VM metrics).

#### LB Diagnostic Settings Setup (Group B Prerequisite)

```powershell
$LB_ID = az network lb show `
  --name "ltmsa-lb" --resource-group ltmsa-security-rg `
  --query id -o tsv
az monitor diagnostic-settings create `
  --name "lb-to-law" --resource $LB_ID --workspace $LAW_ID `
  --metrics '[{"category":"AllMetrics","enabled":true}]'
```

| LB Metric | Description | Value Range |
|-----------|-------------|-------------|
| `VipAvailability` | LB frontend availability | 0 (degraded) / 100 (healthy) |
| `DipAvailability` | Backend VM health probe result | 0 (fail) / 100 (success) |
| `ByteCount` | Bytes processed (throughput indicator) | Cumulative |
| `PacketCount` | Packets processed | Cumulative |
| `SNATConnectionCount` | SNAT connection count (port exhaustion detection) | Cumulative |

---

#### Group A: VM Health Correlation

```kusto
// Query 11. Multi-VM Availability Dashboard — Heartbeat-based status at a glance
// No Heartbeat for 5+ minutes → classified as "OFFLINE"
let threshold = 5m;
Heartbeat
| where TimeGenerated > ago(1h)
| summarize LastBeat = max(TimeGenerated) by Computer, ResourceGroup
| extend Status = iff(LastBeat < ago(threshold), "OFFLINE", "ONLINE")
| extend MinutesSinceLastBeat = datetime_diff("minute", now(), LastBeat)
| project Computer, ResourceGroup, Status, LastBeat, MinutesSinceLastBeat
| order by Status asc, MinutesSinceLastBeat desc
```

> **`datetime_diff` function**: Returns the difference between two datetimes in a specified unit — `"minute"`, `"second"`, `"hour"`, etc.

```kusto
// Query 12. CPU Spike + Heartbeat Cross-Analysis — App overload vs VM down
// CPU high, Heartbeat normal → App overload (VM is alive)
// CPU high, no Heartbeat → Suspected VM down
let cpu_spikes =
    Perf
    | where TimeGenerated > ago(1h)
    | where ObjectName == "Processor Information" and CounterName == "% Processor Time"
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
    VMStatus == "NO_HEARTBEAT",              "VM DOWN — check Azure portal",
    SpikeCount > 0 and VMStatus == "ALIVE",  "APP OVERLOAD — VM healthy but CPU high",
    "Normal")
| project TimeGenerated, Computer, MaxCPU, SpikeCount, VMStatus, Diagnosis
| order by TimeGenerated desc
```

> **`case()` function**: Multi-branch conditional. `iff()` handles binary branches; `case()` handles multiple branches.

```kusto
// Query 13. Network Throughput Trend — LB backend VM traffic flow
// Bytes Total/sec spike = traffic surge; sudden drop = VM removed from LB or isolated
Perf
| where TimeGenerated > ago(1h)
| where ObjectName == "Network Interface" and CounterName == "Bytes Total/sec"
| summarize
    AvgBps = avg(CounterValue),
    MaxBps = max(CounterValue),
    P95Bps = percentile(CounterValue, 95)
  by bin(TimeGenerated, 5m), Computer, InstanceName
| extend AvgMbps = round(AvgBps * 8 / 1000000, 2)
| extend MaxMbps = round(MaxBps * 8 / 1000000, 2)
| project TimeGenerated, Computer, InstanceName, AvgMbps, MaxMbps
| render timechart
```

```kusto
// Query 14. VM Restart / Suspension Detection — based on Heartbeat gaps
// Heartbeat gap > 10 min then resumed = suspected VM restart or suspension
Heartbeat
| where TimeGenerated > ago(24h)
| order by Computer asc, TimeGenerated asc
| serialize
| extend PrevBeat = prev(TimeGenerated, 1)
| extend GapMinutes = datetime_diff("minute", TimeGenerated, PrevBeat)
| where GapMinutes > 10
| project TimeGenerated, Computer, GapMinutes,
          RestartAt    = TimeGenerated,
          LastSeenBefore = PrevBeat
| order by GapMinutes desc
```

> **`serialize` + `prev()`**: Guarantees time-series order, then references the previous row's value. Essential for computing inter-event gaps.

---

#### Group B: LB Health (requires LB Diagnostic Settings)

```kusto
// Query 15. LB Frontend Availability (VipAvailability)
// Standard LB only. 0=degraded, 100=healthy (binary value)
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
```

```kusto
// Query 16. LB Backend Health Probe (DipAvailability) — per-VM status
// 100=VM responding to probe normally, 0=probe failure (app down or VM down)
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
```

```kusto
// Query 17. DipAvailability Degradation Windows — identify incident time ranges
// Shows start/end of probe failure and duration as a time window
AzureMetrics
| where TimeGenerated > ago(24h)
| where ResourceProvider == "MICROSOFT.NETWORK/LOADBALANCERS"
| where MetricName == "DipAvailability"
| where Average < 100
| summarize
    DegradedStart = min(TimeGenerated),
    DegradedEnd   = max(TimeGenerated),
    MinAvail      = min(Average),
    EventCount    = count()
  by Resource
| extend DurationMin = datetime_diff("minute", DegradedEnd, DegradedStart)
| project Resource, DegradedStart, DegradedEnd, DurationMin, MinAvail, EventCount
| order by DegradedStart desc
```

```kusto
// Query 18. LB Throughput + DipAvailability Correlation — health degradation under traffic surge
// DipAvailability drop during ByteCount spike = app unable to handle traffic → probe failure
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
```

---

#### Group C: App Layer Inference (indirect measurement via VM metrics)

```kusto
// Query 19. Per-VM App Load Profile — CPU + network composite classification
// CPU high + network high → handling traffic (normal load)
// CPU high, network low → internal compute bottleneck (loop / query intensive)
// Both low → idle
let cpu =
    Perf
    | where TimeGenerated > ago(1h)
    | where ObjectName == "Processor Information" and CounterName == "% Processor Time"
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
| project TimeGenerated, Computer,
          AvgCPU     = round(AvgCPU, 1),
          AvgNetMbps = round(AvgNetBps * 8 / 1000000, 2),
          LoadProfile
| order by TimeGenerated desc
```

```kusto
// Query 20. Pre/Post-Deploy Performance Comparison — before/after CPU around deploy time
// Change deploy_time to the actual deployment timestamp before running
let deploy_time = datetime(2026-06-13 09:30:00);
let before =
    Perf
    | where TimeGenerated between ((deploy_time - 30m) .. deploy_time)
    | where ObjectName == "Processor Information" and CounterName == "% Processor Time"
    | where InstanceName == "_Total"
    | summarize AvgCPU_Before = avg(CounterValue) by Computer;
let after =
    Perf
    | where TimeGenerated between (deploy_time .. (deploy_time + 30m))
    | where ObjectName == "Processor Information" and CounterName == "% Processor Time"
    | where InstanceName == "_Total"
    | summarize AvgCPU_After = avg(CounterValue) by Computer;
before
| join kind=inner after on Computer
| extend Delta = round(AvgCPU_After - AvgCPU_Before, 1)
| extend Impact = case(
    Delta > 10,  "CPU INCREASE — possible regression",
    Delta < -10, "CPU DECREASE — possible improvement",
    "STABLE")
| project Computer,
          AvgCPU_Before = round(AvgCPU_Before, 1),
          AvgCPU_After  = round(AvgCPU_After, 1),
          Delta, Impact
```

> 💡 **Architectural point:** LB health monitoring — 3-tier approach  
> → "Diagnose LB issues across 3 tiers: ① **VipAvailability** (is the LB frontend reachable?) → ② **DipAvailability** (are backend VMs responding to health probes?) → ③ **VM Heartbeat + CPU** (is the VM itself alive and is the app running?). If VipAvailability is healthy but DipAvailability is 0, the app is down; if there is also no Heartbeat, the VM itself is down."

---

### Exercise 5.4: Create Alert Rule — CPU Threshold Notification

```bash
# Create Action Group (email notification)
az monitor action-group create \
  --name "${PREFIX}-ops-ag" \
  --resource-group $RG_OPS \
  --short-name "OpsTeam" \
  --action email "InHwan" "inhwan.jung@outlook.kr"

# Create Alert Rule for VM CPU > 80% warning
VM_ID=$(az vm show \
  --name "${PREFIX}-demo-vm" \
  --resource-group $RG_SEC \
  --query id --output tsv)

AG_ID=$(az monitor action-group show \
  --name "${PREFIX}-ops-ag" \
  --resource-group $RG_OPS \
  --query id --output tsv)

az monitor metrics alert create \
  --name "High-CPU-Alert" \
  --resource-group $RG_OPS \
  --scopes $VM_ID \
  --condition "avg Percentage CPU > 80" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --severity 2 \
  --description "VM CPU usage exceeded 80% threshold" \
  --action $AG_ID

# List Alert Rules
az monitor metrics alert list \
  --resource-group $RG_OPS \
  --output table
```

> 💡 **Architectural point:** How to reduce alert noise  
> → "Set thresholds based on P95 percentile instead of simple averages. Also aggregate alerts over a 5-minute window to reduce false positives from momentary spikes."

---

### Exercise 5.5: Log Analytics Cost Optimization

> **Key point**: Log Analytics billing is based on ingested data volume (GB). Filtering before ingestion can cut costs by 25% or more.

#### Cost Analysis KQL

```kusto
// Ingestion volume by table — identify which table drives the most cost
Usage
| where TimeGenerated > ago(7d)
| where IsBillable == true
| summarize
    TotalGB     = round(sum(Quantity) / 1024, 3),
    AvgDailyGB  = round(sum(Quantity) / 1024 / 7, 3)
  by DataType
| order by TotalGB desc
```

```kusto
// Per-event size check (_BilledSize: bytes billed for this row)
Heartbeat
| where TimeGenerated > ago(1h)
| where _IsBillable == true
| summarize
    RowCount    = count(),
    TotalKB     = round(sum(_BilledSize) / 1024, 1),
    AvgBytesRow = round(avg(_BilledSize), 0)
  by Computer
| order by TotalKB desc
```

```kusto
// When Syslog ingestion is high — breakdown by Facility
Syslog
| where TimeGenerated > ago(24h)
| where _IsBillable == true
| summarize
    RowCount = count(),
    TotalKB  = round(sum(_BilledSize) / 1024, 1)
  by Facility
| order by TotalKB desc
```

#### DCR transformKql — Pre-Ingestion Filtering (Advanced)

Remove unnecessary columns at the ingestion stage to reduce per-event size:

```json
"dataFlows": [{
  "streams": ["Microsoft-Syslog"],
  "destinations": ["ltmsa-law"],
  "transformKql": "source | project-away TenantId, _ResourceId, MG, ManagementGroupName"
}]
```

> Use `project-away` to drop columns not needed for analysis → up to 25% reduction in event size

#### Daily Cap Configuration (Prevent Bill Shock)

```powershell
# Set Log Analytics daily ingestion limit (unit: GB/day)
az monitor log-analytics workspace update `
  --workspace-name "$PREFIX-law" `
  --resource-group $RG_OPS `
  --quota 1  # 1 GB/day — suitable for workshop lab environment (production: calculate from actual traffic)

# Verify current settings
az monitor log-analytics workspace show `
  --workspace-name "$PREFIX-law" `
  --resource-group $RG_OPS `
  --query "{DailyCapGB:workspaceCapping.dailyQuotaGb, RetentionDays:retentionInDays}" -o json
```

> ⚠️ When the Daily Cap is exceeded, ingestion stops for the rest of that day. Recommended: configure an alert.  
> Portal → LAW → Usage and estimated costs → Daily cap → Set daily volume cap and alert

#### Cost Optimization Decision Points

| Situation | Recommended Action |
|-----------|-------------------|
| Syslog `debug`/`info` levels account for 60%+ of volume | Adjust `logLevels` in DCR to collect `Warning` and above only |
| Table not queried for 30+ days | Switch table plan to Basic (limited KQL features but ~1/4 the cost) |
| A column always contains the same value | Add `project-away` for that column in DCR `transformKql` |
| Retention needed only for compliance, not analysis | Set Archival retention period (up to 7 years, low cost) |

---

### Module 5 Key Summary (Workshop Q&A Points)

| Question | Key Answer |
|----------|-----------|
| What is the difference between AMA and MMA? | MMA uses Workspace Key auth (security risk, deprecated Aug 2024) → AMA uses Managed Identity + DCR (Zero Trust, multi-destination capable) |
| What is DCR Multi-homing? | From a single VM, send Perf to the operational LAW and Syslog (for Sentinel) to a separate LAW — only possible with AMA |
| How does Log Analytics billing work? | Billed per GB ingested. Set an upper bound with Daily Cap. Further optimize with table plan (Analytics vs Basic) and retention period (Interactive vs Archival) |
| Troubleshooting order when Perf data is missing? | ① Check DCR counter names (Linux: Available Bytes, Processor Information) → ② Check telegraf socket connection → ③ Check configchunks file contents → ④ VM reboot (AzExtension timing issue) |

---

## Module 6: FinOps & Cost Governance (40 minutes)

### Learning Objectives
- Analyze spending patterns with Cost Analysis
- Leverage Azure Advisor cost-saving recommendations
- Compare Reserved Instances vs Savings Plans
- Tag-based cost allocation (Chargeback / Showback)

### Key Concept: FinOps 3-Phase Cycle

```
Inform (Visibility) → Optimize (Optimization) → Operate (Governance)
     ↑___________________________________|

Inform:   Understand current spending with Cost Analysis
Optimize: Apply Advisor recommendations, adopt RI/Savings Plans
Operate:  Set budget alerts, establish Chargeback framework
```

---

### Exercise 6.1: Cost Analysis — Analyze Spending Patterns

**Perform in the Portal:**
1. Azure Portal → Search `Cost Management + Billing`
2. Click **Cost Analysis**
3. Check each of the following views:
   - **By service**: Identify the highest-cost services
   - **By resource group**: Cost share per project
   - **By tag**: Analyze costs per team using Owner/Project tags
4. **Time series view**: Check growth patterns compared to previous month

**Verify via CLI:**
```bash
# Query usage for the last 30 days (Bash / Cloud Shell)
az consumption usage list \
  --start-date $(date -d "30 days ago" +%Y-%m-%d 2>/dev/null || date -v-30d +%Y-%m-%d) \
  --end-date $(date +%Y-%m-%d) \
  --output table \
  --query "[].{Service:consumedService, Cost:pretaxCost, Currency:currency}" | head -30
```
```powershell
# PowerShell equivalent
$startDate = (Get-Date).AddDays(-30).ToString('yyyy-MM-dd')
$endDate   = (Get-Date).ToString('yyyy-MM-dd')
az consumption usage list `
  --start-date $startDate --end-date $endDate `
  --output table `
  --query "[].{Service:consumedService, Cost:pretaxCost, Currency:currency}"
```

---

### Exercise 6.2: Azure Advisor — Cost-Saving Recommendations

```bash
# Check Advisor cost recommendations
az advisor recommendation list \
  --category Cost \
  --output table \
  --query "[].{Impact:impact, Problem:shortDescription.problem, Solution:shortDescription.solution}"
```

**Key items to check in the Portal:**
1. Azure Portal → Search `Advisor` → **Cost** tab
2. Key recommendation types:
   - **Shut down idle VMs**: VMs with CPU < 5% for 7 days
   - **VM Right-sizing**: Reduce size of resource-wasteful VMs
   - **Purchase Reserved Instances**: Continuously running VMs → save up to 72% with RI
   - **Delete unused Public IPs**: IPs not attached to any VM

---

### Exercise 6.3: RI vs Savings Plans Comparison

| Category | Reserved Instances | Savings Plans |
|------|-------------------|---------------|
| **Commitment period** | 1 year / 3 years | 1 year / 3 years |
| **Flexibility** | Fixed VM size/region | All compute (VM, AKS, Functions) |
| **Max discount** | Up to 72% (3 years, upfront) | Up to 65% |
| **Best for** | Predictable, fixed workloads | Mixed service usage |
| **Recommended scenario** | SQL DB, fixed VM fleet | Container + serverless mix |

```bash
# Check current RI status
az reservations reservation list --output table 2>/dev/null \
  || echo "No reserved instances currently"

# Check RI purchase recommendations from Advisor
az advisor recommendation list \
  --category Cost \
  --query "[?contains(shortDescription.problem, 'Reserved')]" \
  --output table
```

---

### Exercise 6.4: Tag-Based Cost Allocation

```bash
# Identify resources without tags (items that cannot be cost-allocated)
az resource list \
  --query "[?tags == null || tags == {}].{Name:name, Type:type, RG:resourceGroup}" \
  --output table | head -20

# Apply FinOps tags in bulk at resource group level (CostCenter-based Chargeback)
az group update --name ltmsa-governance-rg \
  --tags Environment=dev Project=LTM-SA-Workshop Owner=inhwan.jung@outlook.kr CostCenter=IT-OPS
az group update --name ltmsa-network-rg \
  --tags Environment=dev Project=LTM-SA-Workshop Owner=inhwan.jung@outlook.kr CostCenter=NETWORKING
az group update --name ltmsa-security-rg \
  --tags Environment=dev Project=LTM-SA-Workshop Owner=inhwan.jung@outlook.kr CostCenter=SECURITY
az group update --name ltmsa-ops-rg \
  --tags Environment=dev Project=LTM-SA-Workshop Owner=inhwan.jung@outlook.kr CostCenter=OPERATIONS
```

### Exercise 6.5: Set Budget Alerts

> ⚠️ `az consumption budget create` returns a 400 error on Free Trial/MSDN subscriptions.  
> Use `az rest` to call the Cost Management API directly.

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
        "Actual_75":  { "enabled": true, "operator": "GreaterThan", "threshold": 75,
                        "contactEmails": ["inhwan.jung@outlook.kr"], "thresholdType": "Actual" },
        "Actual_90":  { "enabled": true, "operator": "GreaterThan", "threshold": 90,
                        "contactEmails": ["inhwan.jung@outlook.kr"], "thresholdType": "Actual" },
        "Actual_100": { "enabled": true, "operator": "GreaterThan", "threshold": 100,
                        "contactEmails": ["inhwan.jung@outlook.kr"], "thresholdType": "Actual" }
      }
    }
  }'

# Verify budget
az rest `
  --method GET `
  --uri "https://management.azure.com/subscriptions/${SUB_ID}/providers/Microsoft.Consumption/budgets?api-version=2023-05-01" `
  --query "value[].{Name:name, Amount:properties.amount, CurrentSpend:properties.currentSpend.amount}" `
  --output table
```

> 💡 **Architectural point:** Chargeback vs Showback  
> → "Showback means 'showing' cost information to each team, while Chargeback means actually 'billing' it from the team's budget. Organizations with low FinOps maturity typically start with Showback to raise cost awareness, then transition to Chargeback."

---

## Module 7: Azure Automation & IaC with Bicep (50 minutes)

### Learning Objectives
- Codify 3-tier architecture with Bicep (IaC)
- Preview changes before deployment with What-if
- Automate repetitive tasks with Azure Automation Account
- Detect Infrastructure Drift

### Key Concept: Benefits of IaC

| Property | Description |
|------|------|
| **Idempotency** | Running the same code multiple times produces the same result |
| **Version Control** | Track change history with Git |
| **Drift Detection** | Compare code state vs actual infrastructure |
| **Audit Trail** | Record who changed what and when |

---

### Exercise 7.1: Codify 3-tier Architecture with Bicep

**Create file: `main.bicep`**

> Save the content below to `D:\inhwa\Documents\LTM\bicep\main.bicep`.

```bicep
// main.bicep — LTM SA Workshop 3-tier architecture
targetScope = 'resourceGroup'

@description('Deployment environment (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Deployment region')
param location string = resourceGroup().location

@description('Resource prefix')
param prefix string = 'ltmsa'

// Common tag definitions
var commonTags = {
  Environment: environment
  Project: 'LTM-SA-Workshop'
  ManagedBy: 'Bicep'
  Owner: 'inhwan.jung@outlook.kr'
}

// Create VNet
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

// Key Vault — name is limited to 3-24 alphanumeric chars + hyphens → use only 8 chars with take()
// enablePurgeProtection: cannot be set to false (once set to true, cannot be changed back)
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
  }
}

// Output values (referenced by other modules/pipelines)
output vnetId string = vnet.id
output vnetName string = vnet.name
output lawId string = law.id
output keyVaultName string = keyVault.name
```

**Deploy Bicep:**
```bash
# Verify Bicep CLI
az bicep version

# Run What-if (preview changes before actual deployment)
az deployment group what-if \
  --resource-group $RG_OPS \
  --template-file main.bicep \
  --parameters environment=dev prefix=ltmsa

# Run actual deployment
az deployment group create \
  --name "ltmsa-infra-$(date +%Y%m%d%H%M)" \
  --resource-group $RG_OPS \
  --template-file main.bicep \
  --parameters environment=dev prefix=ltmsa

# Check deployment status
az deployment group list \
  --resource-group $RG_OPS \
  --output table

# Check output values (vnetId, lawId, keyVaultName, etc.)
az deployment group show \
  --name "$(az deployment group list --resource-group $RG_OPS --query '[0].name' -o tsv)" \
  --resource-group $RG_OPS \
  --query "properties.outputs" \
  --output json
```

---

### Exercise 7.2: Azure Automation — VM Auto-Shutdown Runbook

> ⚠️ `az automation account create` requires a separate extension installation (fails in non-interactive environments).  
> Use `az rest` to create it directly. `Microsoft.Automation` provider registration is required first.

```bash
# Check and register provider
az provider register --namespace Microsoft.Automation --wait
az provider show --namespace Microsoft.Automation --query registrationState -o tsv
# Output: Registered
```

```powershell
# Run in PowerShell
$SUB_ID = az account show --query id -o tsv
$RG = "ltmsa-ops-rg"
$AA_NAME = "ltmsa-automation"

# 1. Create Automation Account
az rest `
  --method PUT `
  --uri "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.Automation/automationAccounts/${AA_NAME}?api-version=2023-11-01" `
  --body "{
    `"location`": `"koreacentral`",
    `"properties`": { `"sku`": { `"name`": `"Basic`" } },
    `"identity`": { `"type`": `"SystemAssigned`" },
    `"tags`": { `"Environment`": `"dev`", `"Project`": `"LTM-SA-Workshop`" }
  }" `
  --query "{Name:name, State:properties.state, PrincipalId:identity.principalId}"

# 2. Grant the Automation Account MI the Virtual Machine Contributor role
$AA_PRINCIPAL = az rest `
  --method GET `
  --uri "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.Automation/automationAccounts/${AA_NAME}?api-version=2023-11-01" `
  --query "identity.principalId" -o tsv

$GUID = [System.Guid]::NewGuid().ToString()
$body = @{
  properties = @{
    roleDefinitionId = "/subscriptions/${SUB_ID}/providers/Microsoft.Authorization/roleDefinitions/9980e02c-c2be-4d73-94e8-173b1dc7cf3c"
    principalId      = $AA_PRINCIPAL
    principalType    = "ServicePrincipal"
  }
} | ConvertTo-Json
$body | Out-File -FilePath "C:\Temp\aa-rbac.json" -Encoding utf8

az rest `
  --method PUT `
  --uri "https://management.azure.com/subscriptions/${SUB_ID}/providers/Microsoft.Authorization/roleAssignments/${GUID}?api-version=2022-04-01" `
  --body "@C:\Temp\aa-rbac.json"
```

**Create and publish Runbook (az rest):**

```powershell
# 3. Create Runbook
az rest `
  --method PUT `
  --uri "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.Automation/automationAccounts/${AA_NAME}/runbooks/Stop-VMsAfterHours?api-version=2023-11-01" `
  --body '{"location":"koreacentral","properties":{"runbookType":"PowerShell","description":"Auto-shutdown VMs tagged Environment=dev"}}'

# 4. Upload Runbook script (draft content)
$SCRIPT = @'
param([string]$TagName="Environment",[string]$TagValue="dev")
Connect-AzAccount -Identity
$vms = Get-AzVM -Status | Where-Object { $_.Tags[$TagName] -eq $TagValue -and $_.PowerState -eq "VM running" }
Write-Output "Target VM count: $($vms.Count)"
foreach ($vm in $vms) {
    Write-Output "Stopping: $($vm.Name)"
    Stop-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Force -NoWait
}
Write-Output "Complete: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
'@
$SCRIPT | Out-File -FilePath "C:\Temp\runbook.ps1" -Encoding utf8

az rest `
  --method PUT `
  --uri "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.Automation/automationAccounts/${AA_NAME}/runbooks/Stop-VMsAfterHours/draft/content?api-version=2023-11-01" `
  --headers "Content-Type=text/powershell" `
  --body "@C:\Temp\runbook.ps1"

# 5. Publish Runbook
az rest `
  --method POST `
  --uri "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.Automation/automationAccounts/${AA_NAME}/runbooks/Stop-VMsAfterHours/publish?api-version=2023-11-01"

# 6. Create Schedule (daily at 7 PM KST = UTC 10:00)
az rest `
  --method PUT `
  --uri "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.Automation/automationAccounts/${AA_NAME}/schedules/DailyStop-7PM-KST?api-version=2023-11-01" `
  --body '{"properties":{"startTime":"2026-06-14T10:00:00+00:00","expiryTime":"2027-06-14T10:00:00+00:00","frequency":"Day","interval":1,"timeZone":"Asia/Seoul"}}'

# 7. Link Schedule to Runbook
$JOB_GUID = [System.Guid]::NewGuid().ToString()
az rest `
  --method PUT `
  --uri "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.Automation/automationAccounts/${AA_NAME}/jobSchedules/${JOB_GUID}?api-version=2023-11-01" `
  --body '{"properties":{"runbook":{"name":"Stop-VMsAfterHours"},"schedule":{"name":"DailyStop-7PM-KST"},"parameters":{"TagName":"Environment","TagValue":"dev"}}}'
```

**Verify exercise results:**
```bash
# Check Runbook status
az rest --method GET \
  --uri "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/ltmsa-ops-rg/providers/Microsoft.Automation/automationAccounts/ltmsa-automation/runbooks?api-version=2023-11-01" \
  --query "value[].{Name:name, State:properties.state}" --output table

# Check Schedule
az rest --method GET \
  --uri "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/ltmsa-ops-rg/providers/Microsoft.Automation/automationAccounts/ltmsa-automation/schedules?api-version=2023-11-01" \
  --query "value[].{Name:name, Frequency:properties.frequency, NextRun:properties.nextRun}" --output table
```

---

### Exercise 7.3: Detect Infrastructure Drift

```bash
# Export the current resource group state as an ARM Template
az group export \
  --name $RG_OPS \
  --output json > rg-ops-current-state.json

echo "Current infrastructure state saved to rg-ops-current-state.json"
echo "Comparing this file with the Bicep code will reveal any drift"

# Check for drift with What-if
az deployment group what-if \
  --resource-group $RG_OPS \
  --template-file main.bicep \
  --parameters environment=dev prefix=ltmsa
```

> 💡 **Architectural point:** IaC drift management strategy  
> → "Run Azure Policy Audit mode and what-if periodically in GitHub Actions to detect differences (Drift) between the code and actual infrastructure. When drift is found, roll back the infrastructure to the code state, or update the code if the change was intentional."

---

### Exercise 7.4: GitHub Actions CI/CD → LB HA Deployment (VM-1 + VM-2)

> **Scenario**: On every push to master, GitHub Actions deploys the Node.js app to two VMs behind a Standard Load Balancer.  
> All VM commands go through **Azure Management API (az vm run-command)** — no SSH, no inbound ports opened (Zero Trust).
>
> **Repository**: `jungfrau70/github-actions-azure`  
> **Workflow file**: `.github/workflows/deploy-vm.yml`

#### Step 1: Create a Service Principal for GitHub Actions

> **Important — SP scope selection**
> The E2E test (`e2e-test.yml`) deletes and recreates the RG, so a **subscription-level** scope is required.  
> For `deploy-vm.yml` only, a `resourceGroups/ltmsa-security-rg` scope (least privilege) is also acceptable.

> **Windows Git Bash warning**: `/subscriptions/...` paths are converted to Windows file paths  
> → `MSYS_NO_PATHCONV=1` prefix is required. Not needed in PowerShell.

```bash
SUB_ID=$(az account show --query id -o tsv)

# Full workflow including E2E — subscription-level scope
# Windows Git Bash: MSYS_NO_PATHCONV=1 required
MSYS_NO_PATHCONV=1 az ad sp create-for-rbac \
  --name "github-actions-ltmsa" \
  --role Contributor \
  --scopes "/subscriptions/${SUB_ID}" \
  --sdk-auth \
  --output json
# Note: --sdk-auth deprecated but still functional (outputs legacy JSON format required by azure/login@v2)
# Copy the entire output JSON → store as AZURE_CREDENTIALS secret
```

| Use Case | `--scopes` | Reason |
|----------|-----------|--------|
| E2E test (RG delete → recreate) | `/subscriptions/${SUB_ID}` | Create permission needed when RG does not yet exist |
| deploy-vm.yml (existing RG retained) | `/subscriptions/${SUB_ID}/resourceGroups/ltmsa-security-rg` | Least privilege principle |

#### Step 2: Configure GitHub Repository Secrets

Configure via GitHub CLI (recommended):

```bash
# AZURE_CREDENTIALS: pipe SP creation output directly
MSYS_NO_PATHCONV=1 az ad sp create-for-rbac \
  --name "github-actions-ltmsa" \
  --role Contributor \
  --scopes "/subscriptions/$(az account show --query id -o tsv)" \
  --sdk-auth --output json > /tmp/sp.json

gh secret set AZURE_CREDENTIALS \
  --repo jungfrau70/github-actions-azure \
  --body "$(cat /tmp/sp.json)"

gh secret set ADMIN_PASSWORD \
  --repo jungfrau70/github-actions-azure
# (enter VM admin password at prompt)

rm /tmp/sp.json
```

Or via GitHub web UI: Repository → Settings → Secrets and variables → Actions

| Secret Name | Value |
|-------------|-------|
| `AZURE_CREDENTIALS` | Full JSON from Step 1 (`az ad sp create-for-rbac --sdk-auth`) |
| `ADMIN_PASSWORD` | VM-2 admin password for lb-vm2.bicep deployment |

#### Step 3: Workflow Structure (4-job pipeline)

```
[git push master]
        ↓
[Job 1: CI — Test & Lint]
  ① npm install + npm run test:unit
  ② node --check src/app.js    ← syntax-only, no listen() hang
        ↓ CI passes
[Job 2: deploy-infra — Bicep: LB + VM-2]         (skippable: skip_infra=true)
  ③ Get VM-1 subnet ID
  ④ az deployment group what-if → bicep/lb-vm2.bicep
  ⑤ az deployment group create → creates ltmsa-lb (port 80→3000) + ltmsa-demo-vm-2
  ⑥ Add VM-1 NIC to LB backend pool (dynamic ip-config name lookup)
        ↓
[Job 3: deploy-app — App deploy (parallel matrix)]
  Runs on: ltmsa-demo-vm AND ltmsa-demo-vm-2 (simultaneously)
  ⑦ Check VM state (auto-start if stopped)
  ⑧ az vm run-command invoke → inside each VM:
       • Install Node.js 18 if missing
       • base64-decode app.js + package.json to /opt/ltm-workshop
       • npm install --production
       • pm2 restart/start ltm-workshop
       • curl http://localhost:3000/health (retry 6×)
        ↓ Both VMs healthy
[Job 4: verify-lb — Load Balancer Health Check]
  ⑨ Wait for LB health probe (port 80, path /health → port 3000)
  ⑩ curl http://<LB_PUBLIC_IP>/health + /api/modules
```

#### Step 4: Manually Trigger the Workflow

```bash
# Manual trigger with skip_infra=true (LB already exists)
gh workflow run "Deploy to Azure VM (LB HA)" \
  --repo jungfrau70/github-actions-azure \
  --field environment=dev \
  --field skip_infra=true

# Check run status
gh run list --repo jungfrau70/github-actions-azure --limit 5
```

Or from the GitHub web UI: Actions tab → "Deploy to Azure VM (LB HA)" → [Run workflow]

#### Step 5: Verify the Deployment

```bash
# Get the LB Public IP (single endpoint for both VMs)
LB_IP=$(az network public-ip show \
  --resource-group ltmsa-security-rg \
  --name ltmsa-lb-pip \
  --query ipAddress --output tsv)

# Verify via Load Balancer (port 80 → 3000)
curl http://${LB_IP}/health
curl http://${LB_IP}/api/modules

# Verify each VM directly (optional)
VM1_IP=$(az vm show --resource-group ltmsa-security-rg --name ltmsa-demo-vm \
  --show-details --query publicIps --output tsv)
curl http://${VM1_IP}:3000/health
```

| Item | Value |
|------|-------|
| LB URL | `http://<ltmsa-lb-pip>` (port 80) |
| VM-1 direct | `http://<ltmsa-demo-vm publicIp>:3000` |
| VM-2 | private only (no public IP — via LB only) |
| App path | `/opt/ltm-workshop` |
| Process manager | pm2 (`pm2 list`) |

> 💡 **Architectural point:** Security design for GitHub Actions + Azure integration  
> → "Instead of storing SSH keys and opening inbound SSH ports, commands are executed through the Azure management plane via `az vm run-command`. No need to open port 22 in the NSG — this is the Zero Trust principle applied to CI/CD."

> 💡 **Architectural point:** CI/CD pipeline stage design  
> → "Separating into 4 jobs (CI → infra → app → verify) means a test failure in CI blocks all downstream jobs automatically. The `skip_infra=true` flag lets you redeploy only the app when the LB already exists, cutting deployment time significantly."

> 💡 **Architectural point:** az CLI vs Bicep — hybrid IaC strategy  
> → "Network/security topology (VNet, NSG, Bastion, Jumpbox) is provisioned via az CLI: one-time, environment-scoped resources that are explicit and easy to audit line-by-line. The LB+VM-2 bundle uses Bicep: a reusable module with idempotency, what-if preview, and typed outputs. This mirrors real-world team ownership — the platform team controls topology via CLI, the app team owns the Bicep module. Choosing the right tool per layer avoids over-engineering one-off resources while still gaining IaC benefits for repeatable patterns."

---

### Exercise 7.5: Zero Trust Admin Access — Bastion + Jumpbox + Break-glass

> **Scenario**: VMs must be reachable by administrators, but corporate security policy prohibits opening SSH to the internet. Three layered access patterns are implemented: Azure Bastion (Zero Trust), Jumpbox VM (enterprise management subnet), and Break-glass via Management Plane.

#### Architecture Overview

```
10.0.0.0/16  (ltmsa-vnet)
  ├── AzureBastionSubnet: 10.0.0.0/26   ← Azure-required name, /26 min, NO NSG
  ├── web-snet:           10.0.1.0/24   ← App VMs (ltmsa-web-nsg)
  └── mgmt-snet:          10.0.2.0/24   ← Jumpbox VM (ltmsa-mgmt-nsg, no public IP)

Admin access paths:
  [Scenario 1] Browser → Azure Portal → Bastion → App VM (TLS, no SSH port needed)
  [Scenario 2] Bastion → Jumpbox (mgmt-snet) → SSH → App VM (web-snet)
  [Scenario 3] az vm run-command → Azure Management API → VM Agent (bypasses NSG entirely)
```

#### Step 1: Update NSGs (Remove Internet SSH)

```bash
RG=ltmsa-security-rg

# web-snet NSG: remove internet-facing SSH, allow only from Bastion subnet + Jumpbox
az network nsg rule delete \
  --resource-group $RG --nsg-name ltmsa-web-nsg --name allow-ssh

az network nsg rule create \
  --resource-group $RG --nsg-name ltmsa-web-nsg \
  --name allow-bastion-ssh --priority 100 --protocol Tcp \
  --source-address-prefixes 10.0.0.0/26 \
  --destination-port-ranges 22 --access Allow

az network nsg rule create \
  --resource-group $RG --nsg-name ltmsa-web-nsg \
  --name allow-jumpbox-ssh --priority 110 --protocol Tcp \
  --source-address-prefixes 10.0.2.0/24 \
  --destination-port-ranges 22 --access Allow

# mgmt-snet NSG: Jumpbox accessible from Bastion only
az network nsg create --resource-group $RG --name ltmsa-mgmt-nsg

az network nsg rule create \
  --resource-group $RG --nsg-name ltmsa-mgmt-nsg \
  --name allow-bastion-to-jumpbox --priority 100 --protocol Tcp \
  --source-address-prefixes 10.0.0.0/26 \
  --destination-port-ranges 22 --access Allow

az network nsg rule create \
  --resource-group $RG --nsg-name ltmsa-mgmt-nsg \
  --name allow-jumpbox-to-web --priority 200 --protocol Tcp \
  --direction Outbound \
  --source-address-prefixes 10.0.2.0/24 \
  --destination-address-prefixes 10.0.1.0/24 \
  --destination-port-ranges 22 --access Allow
```

#### Step 2: Add Subnets (AzureBastionSubnet + mgmt-snet)

```bash
# AzureBastionSubnet: MUST NOT have NSG attached (Azure hard requirement)
az network vnet subnet create \
  --resource-group $RG --vnet-name ltmsa-vnet \
  --name AzureBastionSubnet \
  --address-prefix 10.0.0.0/26
  # Do NOT add --network-security-group

# mgmt-snet: Jumpbox subnet
az network vnet subnet create \
  --resource-group $RG --vnet-name ltmsa-vnet \
  --name mgmt-snet \
  --address-prefix 10.0.2.0/24 \
  --network-security-group ltmsa-mgmt-nsg
```

#### Step 3: Deploy Azure Bastion (Scenario 1 — Zero Trust SSH)

```bash
# Standard Static PIP (zone-redundant)
az network public-ip create \
  --resource-group $RG --name ltmsa-bastion-pip \
  --sku Standard --allocation-method Static --zone 1 2 3

# Basic SKU Bastion — provisioning takes 5-10 min
az network bastion create \
  --resource-group $RG --name ltmsa-bastion \
  --public-ip-address ltmsa-bastion-pip \
  --vnet-name ltmsa-vnet --sku Basic

# Verify
az network bastion show --resource-group $RG --name ltmsa-bastion \
  --query "{state:provisioningState, ip:ipConfigurations[0].publicIPAddress.id}" --output json
```

Admin access: **Azure Portal → Search "Bastion" → ltmsa-bastion → Connect → Select target VM**

| Bastion SKU | Features |
|-------------|----------|
| Basic | SSH/RDP via browser only |
| Standard | + Native client, IP-based connection, tunneling |

#### Step 4: Deploy Jumpbox VM (Scenario 2 — Management Subnet)

```bash
# No public IP, no NSG override — mgmt-snet NSG (ltmsa-mgmt-nsg) applies
az vm create \
  --resource-group $RG \
  --name ltmsa-jumpbox \
  --location koreacentral \
  --image Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest \
  --size Standard_B2s \
  --admin-username azureuser \
  --admin-password "YourSecurePassword!" \
  --vnet-name ltmsa-vnet \
  --subnet mgmt-snet \
  --nsg "" \
  --public-ip-address ""    # Critical: no public IP

# Verify: publicIps must be empty
az vm show --resource-group $RG --name ltmsa-jumpbox \
  --show-details --query "{name:name, private:privateIps, public:publicIps}" --output json

# Access: Bastion → ltmsa-jumpbox → then SSH to app VMs
VM1_PRIVATE=$(az vm show --resource-group $RG --name ltmsa-demo-vm \
  --show-details --query privateIps --output tsv)
# Inside Jumpbox: ssh azureuser@${VM1_PRIVATE}
```

#### Step 5: Break-glass via Management Plane (Scenario 3)

```bash
# Emergency access — bypasses NSG, no network path required
# Commands delivered via VM Agent (waagent) — Management Plane, not data plane
az vm run-command invoke \
  --resource-group $RG \
  --name ltmsa-demo-vm \
  --command-id RunShellScript \
  --scripts "
    echo 'Host:' \$(hostname)
    pm2 list --no-color 2>/dev/null
    ss -tlnp | grep :3000
    uptime
  " \
  --query "value[0].message" --output tsv

# Works even when:
#   - NSG blocks all inbound traffic
#   - No SSH keys configured
#   - Bastion/Jumpbox not provisioned yet
```

#### E2E Test — Full Pipeline (Automated)

```bash
# Trigger the complete automation test (destroys and rebuilds everything)
# Workflow: .github/workflows/e2e-test.yml
# Jobs: preflight → cleanup → setup-network → setup-jumpbox ∥ setup-vm1 → setup-lb → deploy-app → verify

gh workflow run "E2E Test — Full Fresh Deploy" \
  --repo jungfrau70/github-actions-azure \
  --field confirm_destroy=DESTROY \
  --field environment=dev

# Monitor
gh run list --repo jungfrau70/github-actions-azure --limit 3
```

| Access Scenario | Requires Port 22 Open | Audit Trail | Use Case |
|----------------|----------------------|-------------|----------|
| Azure Bastion | No (TLS tunnel) | Azure Monitor logs | Daily admin |
| Jumpbox + Bastion | Internal only | Jumpbox audit + Bastion logs | Scripting, batch |
| Break-glass (run-command) | No | Azure Activity Log | Emergency, CI/CD |

> 💡 **Architectural point:** Zero Trust admin access  
> → "We removed internet-facing SSH entirely. Azure Bastion replaces the traditional SSH bastion host as a PaaS service — no VM to patch, MFA inherited from Azure AD, Conditional Access policies apply automatically. The Jumpbox adds a second trust boundary for lateral movement control. Break-glass via `az vm run-command` uses the Azure Management Plane — the cloud-native equivalent of console access on-prem, working even when all network paths are blocked."

> 💡 **Architectural point:** Defense-in-depth for admin access  
> → "The three scenarios are layered by trust level: Bastion for everyday operations, Jumpbox for privileged batch work, run-command only for emergencies. This satisfies both operational efficiency and compliance — no standing access, JIT possible via PIM, all paths logged."

---

## To-be Architecture Recommendations

> The workshop builds the **As-is** foundation. The table below maps each gap to its recommended evolution path.

| Gap (As-is) | To-be Recommendation | Key Service |
|-------------|----------------------|-------------|
| az CLI resources have no state (VNet, NSG, Bastion, Jumpbox, VM-1) | Full Bicep modules — `network.bicep`, `jumpbox.bicep`, `vm.bicep` + environment parameter files | Bicep Deployment Stacks |
| VMs without Availability Zone assignment | VM-1 → Zone 1, VM-2 → Zone 2, LB already zone-redundant | Standard LB (zone-redundant) |
| No backup policy | Azure Backup vault + daily VM snapshot policy | Recovery Services Vault |
| Single region (koreacentral), RTO ~45 min | Active-Passive DR to koreasouth via Azure Site Recovery + Traffic Manager failover | ASR + Traffic Manager |
| No drift detection | Scheduled `az deployment group what-if` scan + GitHub Issue on diff | GitHub Actions (cron) |
| Manual teardown | `az stack group delete` — removes all stack-managed resources atomically | Bicep Deployment Stacks |
| Mutable VM (Node.js installed at deploy time via apt) | Golden Image — Packer builds runtime-baked image → Azure Compute Gallery; deploy-app only injects app code | Packer + Azure Compute Gallery |

### Evolution Roadmap

```
As-is (Workshop)                To-be Step 1                 To-be Step 2
────────────────────            ─────────────────────        ──────────────────────────
az CLI + lb-vm2.bicep      →   Full Bicep modules       →   Bicep Deployment Stacks
Single region (KR Central) →   AZ placement (Zone 1,2)  →   Multi-region + ASR + TM
No backup                  →   Azure Backup (daily)      →   ASR continuous replication
Manual deploy only         →   PR what-if gate           →   Drift detection (scheduled)
Mutable VM (apt@deploy)    →   Golden Image (Packer)     →   Azure Compute Gallery + VMSS
```

> 💡 **Architectural point — Immutable Infrastructure:**  
> → "The workshop installs Node.js at deployment time via apt, which creates non-deterministic behavior — dpkg locks, mirror availability, and patch timing affect whether the deployment succeeds and how long it takes. In production, we pre-bake the runtime into a Golden Image using Packer and store versioned images in Azure Compute Gallery. The deploy pipeline then only injects application code — no package managers. This reduces per-VM RTO from ~12 minutes to ~2 minutes and eliminates an entire class of deployment failures. The key principle: deploy infrastructure, not package managers."

> 💡 **Architectural point — IaC maturity progression:**  
> → "We intentionally kept the workshop at As-is level to focus on core concepts. In production, the next step is consolidating all az CLI provisioning into Bicep modules with Deployment Stacks — this gives us `what-if` drift detection, atomic teardown, and consistent state across environments. For DR, Azure Site Recovery with Traffic Manager priority routing achieves ~15 min RTO to the paired koreasouth region, compared to ~45 min from a full E2E rebuild."

> See **Scenario.md → To-be Architecture Recommendations** for full implementation detail including Packer HCL, CLI examples, Bicep module structure, and Traffic Manager configuration.

---

## Module 8: Security Artifacts — Compliance Assessment & Vulnerability Review (Post E2E)

> **When to run**: After E2E Test + Log Analytics (Module 5) — while infrastructure is live  
> **Duration**: 60–90 minutes  
> **Goal**: Quantify the security posture of all deployed infrastructure and produce 3 security artifact documents

### Learning Objectives

- Understand the CSPM + CWP architecture of Microsoft Defender for Cloud (MDC)
- Measure Secure Score quantitatively and prioritize Unhealthy Recommendations
- Audit NSG, public IPs, RBAC, and Key Vault to produce a vulnerability report
- Validate compliance against CIS Azure Benchmark Controls via CLI
- Design a SOAR workflow: Brute Force detection → automatic NSG block
- Identify external attack surface and Shadow IT using EASM

### Key Concept: MDC Architecture and Cloud Security Mindset

#### Perimeter Security → Zero Trust

```
[On-premises mindset]             [Cloud Zero Trust]
  Firewall → trust inside         Explicitly verify every access
  Inside perimeter = safe         Assume Breach at all times
  Static rules                    Least privilege + dynamic policy
```

#### Shared Responsibility Model

| Domain | Microsoft Responsibility | Customer Responsibility |
|--------|--------------------------|------------------------|
| Physical infrastructure & data centers | ✅ Microsoft | — |
| Hypervisor & network hardware | ✅ Microsoft | — |
| OS (IaaS VM) | — | ✅ Customer (patch & configure) |
| App, code & data | — | ✅ Customer |
| IAM & access control | — | ✅ Customer |
| Network configuration (NSG, firewall) | — | ✅ Customer |

> MDC automatically evaluates misconfigurations and vulnerabilities in the **customer responsibility** domains.

#### MDC = CSPM + CWPP + SOAR + DevSecOps

```
Microsoft Defender for Cloud
  ├── CSPM (Cloud Security Posture Management)
  │     ├─ Foundational CSPM (FREE): Secure Score, basic recommendations, Azure Security Benchmark
  │     └─ Defender CSPM (PAID): attack path analysis, cloud security explorer,
  │                               EASM integration, agentless scanning
  │         Compliance baselines: CIS / PCI DSS / NIST / ISO 27001
  │
  ├── CWPP (Cloud Workload Protection Platform)
  │     ├─ Defender for Servers Plan 1: MDE integration, 500 MB/day free log ingestion
  │     ├─ Defender for Servers Plan 2: + JIT VM Access, adaptive controls, vulnerability assessment
  │     ├─ Defender for Containers: AKS/ARC runtime protection
  │     └─ Defender for Databases: anomalous query detection (SQL, Cosmos DB)
  │
  ├── SOAR (Security Orchestration, Automation & Response)
  │     └─ Logic Apps integration: MDC alert → automatic NSG block + email notification
  │
  └── DevSecOps
        └─ Code pipeline insights: IaC scanning (Bicep/ARM), GitHub/ADO integration
```

> 💡 **Interview point**: Secure Score is available in the **free Foundational CSPM tier** — no paid plan required for the score itself. The paid Defender CSPM plan adds advanced features like attack path analysis and EASM discovery.

#### Why After E2E, Not Module 3?

| Check Item | At Module 3 | After E2E |
|------------|-------------|-----------|
| Secure Score | No resources to scan | VM, NSG, LB all scanned ✅ |
| NSG rule audit | NSG not yet created | Actual deployed rules inspected ✅ |
| Public IP exposure | No VMs | VM-1, LB, Bastion IPs verified ✅ |
| RBAC audit | SP & MI not yet assigned | Full role assignment audit ✅ |
| Policy compliance rate | No resources | Actual resource tags & region checked ✅ |

#### Artifact Structure (3 Types)

```
Security Artifacts
  ├── 8.1 Security Posture Assessment  — Secure Score + Unhealthy Recommendations
  ├── 8.2 Vulnerability Report         — NSG / Public IP / Key Vault / MI / RBAC audit
  └── 8.3 Compliance Assessment        — Azure Policy + CIS Benchmark + Lock + Tag
```

---

### Exercise 8.1: CSPM — Secure Score Analysis and Improvement Plan

#### Step 1: Enable Defender for Servers

```powershell
$PREFIX = "ltmsa"; $RG_SEC = "$PREFIX-security-rg"; $RG_OPS = "$PREFIX-ops-rg"; $SUB_ID = az account show --query id -o tsv

# Enable Defender for Servers Plan 2 (includes VM vulnerability scanning)
az security pricing create --name "VirtualMachines" --tier "Standard"

# Verify all Defender plans
az security pricing list `
  --query "[].{Plan:name, Tier:pricingTier}" --output table
```

> ⚠️ Standard tier incurs charges. After lab, revert with `--tier "Free"` (see Lab Clean-up)

#### Step 2: Collect Secure Score

```powershell
# Secure Score for the entire subscription
az security secure-score show --name "ascScore" `
  --query "{Score:score.current, MaxScore:score.max, Percentage:score.percentage}" -o json

# Score breakdown by control (identify which areas are weak)
az security secure-score-control list `
  --query "[].{Control:displayName, Score:score.current, Max:score.max, Unhealthy:unhealthyResourceCount}" `
  --output table | Sort-Object -Property Unhealthy -Descending
```

#### Step 3: Prioritize Unhealthy Recommendations

```powershell
# List unresolved recommendations with High severity
az security assessment list `
  --query "[?status.code=='Unhealthy'].{Title:displayName, Severity:metadata.severity, ResourceType:resourceDetails.resourceType}" `
  --output table

# Detailed analysis via Log Analytics (KQL)
```
```kusto
// MDC Recommendations — unresolved items by severity
SecurityRecommendation
| where TimeGenerated > ago(24h)
| where RecommendationState == "Unhealthy"
| summarize Count = count() by RecommendationSeverity, RecommendationName
| order by case(RecommendationSeverity, "High", 1, "Medium", 2, "Low", 3, 4), Count desc
```

**Secure Score Target:**

| Score Range | Rating | Meaning |
|-------------|--------|---------|
| 90 and above | Excellent | Industry-leading level |
| 75–89 | Good | Workshop target — major vulnerabilities remediated |
| 60–74 | Fair | Multiple items requiring immediate action |
| Below 60 | Poor | Basic security configuration inadequate |

> 💡 **Secure Score is available in the free Foundational CSPM tier** — no paid Defender plan is required to see the score. Enabling Defender for Servers Plan 2 adds workload-specific recommendations that can push the score higher.

---

### Exercise 8.2: CWPP — Vulnerability Report

#### Step 1: Detect Risky NSG Rules

```powershell
# Rules that allow SSH (22) or RDP (3389) from the entire internet (*)
az network nsg rule list --resource-group $RG_SEC --nsg-name "$PREFIX-web-nsg" `
  --query "[?access=='Allow' && direction=='Inbound' && (sourceAddressPrefix=='*' || sourceAddressPrefix=='Internet') && (destinationPortRange=='22' || destinationPortRange=='3389')].{Rule:name, SrcIP:sourceAddressPrefix, Port:destinationPortRange}" `
  --output table

# Expected result for this workshop: empty (NSG is designed to block internet SSH)
# Confirm SSH is only allowed via Bastion → Jumpbox → VM path
az network nsg rule list --resource-group $RG_SEC --nsg-name "$PREFIX-web-nsg" `
  --output table
```

#### Step 2: Public IP Exposure Inventory

```powershell
# All public IPs in the subscription + associated resources
az network public-ip list `
  --query "[].{Name:name, IP:ipAddress, AssociatedTo:ipConfiguration.id, SKU:sku.name}" `
  --output table

# Expected: VM-1 PIP (direct), LB PIP (load-balanced), Bastion PIP (TLS gateway)
# Risk: a PIP attached directly to a VM NIC bypasses Bastion — exposure risk
```

#### Step 3: Key Vault Access Audit

```powershell
# Verify Key Vault network access policy (public access blocked?)
az keyvault show --name (az keyvault list --resource-group $RG_SEC --query "[0].name" -o tsv) `
  --query "{NetworkAcls:properties.networkAcls.defaultAction, PublicAccess:properties.publicNetworkAccess, PurgeProtection:properties.enablePurgeProtection}" -o json

# Verify Key Vault diagnostic logs → Log Analytics connection
az monitor diagnostic-settings list `
  --resource (az keyvault list --resource-group $RG_SEC --query "[0].id" -o tsv) `
  --query "[].{Name:name, Workspace:workspaceId}" -o table
```
```kusto
// Key Vault access failure log (detect unauthorized access attempts)
AzureDiagnostics
| where ResourceType == "VAULTS"
| where ResultType == "Unauthorized" or ResultType == "Forbidden"
| summarize FailCount = count() by CallerIPAddress, OperationName, bin(TimeGenerated, 1h)
| order by FailCount desc
```

#### Step 4: RBAC Audit — Least Privilege Principle

```powershell
# List of subscription-level Owner role holders (minimize — max 2 Owners)
az role assignment list --role "Owner" --scope "/subscriptions/$SUB_ID" `
  --query "[].{Principal:principalName, Type:principalType, AssignedAt:createdOn}" --output table

# Check Service Principal permissions (excessive privilege?)
az role assignment list --all `
  --query "[?principalType=='ServicePrincipal'].{SP:principalName, Role:roleDefinitionName, Scope:scope}" `
  --output table

# Role assignment summary by resource group
az role assignment list --all `
  --query "[].{Role:roleDefinitionName, Type:principalType, Scope:scope}" `
  --output table | Group-Object Role | Sort-Object Count -Descending
```

#### Step 5: JIT (Just-in-Time) VM Access Status

```powershell
# JIT policy activation status (requires Defender for Servers Plan 2)
az security jit-policy list --resource-group $RG_SEC `
  --query "[].{VM:name, State:properties.provisioningState, Ports:properties.jitNetworkAccessPolicies[0].ports[*].number}" `
  --output table

# Enable JIT if not already active
# NOTE: PowerShell JSON escaping in --virtual-machines is fragile.
# Portal path is more reliable: MDC → Workload protections → Just-in-time VM access → Enable
az security jit-policy create `
  --resource-group $RG_SEC `
  --name "default" `
  --virtual-machines "[{\"id\":\"$(az vm show --resource-group $RG_SEC --name $PREFIX-demo-vm --query id -o tsv)\",\"ports\":[{\"number\":22,\"protocol\":\"*\",\"allowedSourceAddressPrefix\":\"*\",\"maxRequestAccessDuration\":\"PT3H\"}]}]"
```

> **JIT VM Access design principle**: "NSG blocks port 22 by default → JIT request opens it temporarily for 3 hours → auto-closed when time expires"  
> Workshop point: "Rather than leaving SSH open to the internet, JIT grants temporary access for the minimum IP range, only when needed."

---

### Exercise 8.3: CIS Azure Benchmark Compliance Assessment

```powershell
# Policy compliance status — total non-compliant item count
az policy state list --resource-group $RG_SEC `
  --filter "complianceState eq 'NonCompliant'" `
  --query "length(@)" -o tsv

# Non-compliant item detail list (top 20)
az policy state list --resource-group $RG_SEC `
  --filter "complianceState eq 'NonCompliant'" `
  --query "[0:20].{Policy:policyDefinitionName, Resource:resourceId, ComplianceState:complianceState}" `
  --output table

# Tag coverage check (resources missing Owner or Environment tag)
az resource list --resource-group $RG_SEC `
  --query "[?tags.Owner==null || tags.Environment==null].{Name:name, Type:type, Tags:tags}" `
  --output table

# Resource Lock status (verify lock set in Module 1 is still in place)
az lock list --resource-group $RG_SEC `
  --query "[].{Name:name, Level:level, Notes:notes}" --output table
```

**CIS Azure Benchmark v2.0 Key Controls Checklist:**

| CIS Control | Check Item | CLI Verification Command | Expected Value |
|-------------|-----------|--------------------------|----------------|
| 1.1 | MFA enabled | Entra ID Portal check | MFA required for all accounts |
| 2.1 | MDC Standard enabled | `az security pricing list` | VirtualMachines: Standard |
| 3.1 | Storage HTTPS-only | `az storage account list` → `enableHttpsTrafficOnly` | true |
| 4.1 | SQL audit log enabled | N/A (SQL not in use) | N/A |
| 5.1 | Diagnostic logs enabled | `az monitor diagnostic-settings list` | LAW connection confirmed |
| 6.1 | NSG Flow Log enabled | `az network watcher flow-log list` | Enabled (recommended) |
| 7.1 | VM OS disk encryption | `az vm encryption show` | Encrypted |
| 8.1 | Key Vault audit log | `az monitor diagnostic-settings list --resource <KV_ID>` | Enabled |
| 9.1 | App Service HTTPS-only | N/A (VM-based) | N/A |

---

### Exercise 8.4: SOAR — Security Automation (Brute Force Response)

> **Scenario**: When an SSH Brute Force attack is detected → automatically block the attacker IP in the NSG

#### Detection Query (Log Analytics)

```kusto
// SSH Brute Force detection — 10+ failures from the same IP within 1 minute
Syslog
| where TimeGenerated > ago(1h)
| where Facility == "auth"
| where SyslogMessage has "Failed password" or SyslogMessage has "Invalid user"
| extend AttackerIP = extract(@"from\s+(\d+\.\d+\.\d+\.\d+)", 1, SyslogMessage)
| where isnotempty(AttackerIP)
| summarize FailCount = count() by AttackerIP, bin(TimeGenerated, 1m)
| where FailCount >= 10
| order by FailCount desc
```

#### MDC Alert-Based Automated Response Design (SOAR 5-Step Flow)

```
① Attack Target VM with a Brute Force tool such as Hydra
    ↓
② Log Analytics Agent on Target VM collects logs into Log Analytics Workspace
    ↓
③ Defender for Cloud generates a Brute Force Attack Alert
    ↓
④ Defender for Cloud → triggers Azure Logic App
    ├─ Initialize attackerIPs   (extract attacker IP from Alert body)
    ├─ Initialize NSG rule priority
    ├─ Initialize resource ID
    ├─ Parse alert body
    └─ Auto-create Inbound Deny rule in NSG (using Managed Identity permissions)
    ↓
⑤ Logic App sends email to administrator (Outlook connector)
```

> **Why use Logic Apps (SOAR without code)**  
> - Define workflows visually without writing code  
> - Deploy as an Azure Resource Manager template → reusable across environments  
> - Chain MDC Alert trigger → variable init → NSG rule creation → email alert as sequential blocks

#### Logic App Workflow Configuration (Step by Step)

```
[Trigger] When a Microsoft Defender for Cloud Alert is created or triggered
    ↓
[Initialize variable] Initialize attackerIPs
    └─ Extract attacker IP from alert body (JSON parse)
    ↓
[Initialize variable] Initialize NSG rule priority
    └─ Set a priority number that does not conflict with existing rules (e.g., 100)
    ↓
[Initialize variable] Initialize resource ID
    └─ Set the Resource ID of the NSG to block
    ↓
[Action] Parse alert body
    └─ Parse attackerIP, targetVM, alertTime from alert JSON
    ↓
[HTTP action] Create Inbound Deny rule in NSG
    └─ ARM API: PUT /networkSecurityGroups/{name}/securityRules/{ruleName}
       Modifies the NSG using Logic App Managed Identity permissions
    ↓
[Connector] Outlook → Send email
    └─ To: admin email / Body: attacker IP, block rule name, incident time
```

**Create Logic App in Portal:**
```
Azure Portal → Logic Apps → + Create → Consumption plan
  → Logic App Designer → search "When an MDC Alert is created or triggered"
  → Add the steps above as blocks in order
  → Grant Network Contributor role to Logic App's Managed Identity
```

```powershell
# Create Brute Force detection Alert Rule (Log Analytics → Syslog-based)
$LAW_ID = az monitor log-analytics workspace show `
  --workspace-name "$PREFIX-law" --resource-group $RG_OPS --query id -o tsv

$AG_ID = az monitor action-group show `
  --name "$PREFIX-ops-ag" --resource-group $RG_OPS --query id -o tsv

az monitor scheduled-query create `
  --name "SSH-BruteForce-Alert" `
  --resource-group $RG_OPS `
  --scopes $LAW_ID `
  --condition "count 'Syslog | where Facility==\"auth\" | where SyslogMessage has \"Failed password\" | summarize c=count() | where c > 10' greater than 0" `
  --condition-query "Syslog | where TimeGenerated > ago(5m) | where Facility == 'auth' | where SyslogMessage has 'Failed password' | summarize FailCount = count()" `
  --evaluation-frequency "PT5M" `
  --window-size "PT5M" `
  --severity 2 `
  --action $AG_ID `
  --description "SSH Brute Force: 10+ auth failures within 5 minutes"
```

> **Workshop point**: "Rather than stopping at a simple alert, we chain through Logic Apps all the way to an automatic block. Following the SOAR (Security Orchestration, Automation & Response) philosophy: automate repetitive threat responses, and let security staff focus on Threat Hunting for unknown threats."

---

### Exercise 8.5: Defender EASM — External Attack Surface Management

> **Purpose**: Identify organization assets exposed to the internet from an attacker's perspective (including Shadow IT)

#### Threat Types EASM Discovers

| Threat Type | Example | Severity |
|-------------|---------|----------|
| Near-expiring SSL/TLS certificate | `*.company.com` certificate expiring in 30 days | High |
| Abandoned subdomain | `old-api.company.com` → service nobody knows about | High |
| Unnecessarily open port | Port 3389 (RDP) exposed to the internet | Critical |
| OWASP vulnerability | SQL Injection, XSS-vulnerable endpoints | High |
| Shadow IT | Azure resources created privately by employees | Medium |

#### Portal Exercise Procedure

```
Azure Portal → Microsoft Defender for Cloud
  → Workload protections → External Attack Surface Management
  → + Create → Enter Seed (e.g., inhwan.jung@outlook.kr or company domain)
  → Review discovered asset list after a few hours
```

```powershell
# Create EASM resource (CLI)
az rest --method PUT `
  --uri "https://management.azure.com/subscriptions/$SUB_ID/resourceGroups/$RG_OPS/providers/Microsoft.Easm/workspaces/$PREFIX-easm?api-version=2023-04-01-preview" `
  --body '{"location":"koreacentral","properties":{}}'

# Query discovered asset list
az rest --method GET `
  --uri "https://management.azure.com/subscriptions/$SUB_ID/resourceGroups/$RG_OPS/providers/Microsoft.Easm/workspaces/$PREFIX-easm/assets?api-version=2023-04-01-preview"

# NOTE: The asset list will be EMPTY during the workshop session.
# EASM requires 6–48 hours of domain crawling after the seed domain is submitted.
# Verify workspace creation in the portal now; rerun this query the next day.
```

---

### Exercise 8.6: Generate Security Artifacts

#### 8.1 Security Posture Assessment

```powershell
# Collect in one shot
$score = az security secure-score show --name "ascScore" -o json | ConvertFrom-Json
$unhealthy = az security assessment list `
  --query "[?status.code=='Unhealthy'] | length(@)" -o tsv

Write-Host "=== Security Posture Assessment ==="
Write-Host "Assessment date: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
Write-Host "Secure Score: $($score.score.current)/$($score.score.max) ($([math]::Round($score.score.percentage,1))%)"
Write-Host "Unresolved recommendations: $unhealthy"
Write-Host "Target score: 75 or above"
```

#### 8.2 Vulnerability Report

```powershell
Write-Host "=== Vulnerability Report ==="

# Risky NSG rules
$dangerRules = az network nsg rule list --resource-group $RG_SEC --nsg-name "$PREFIX-web-nsg" `
  --query "[?access=='Allow' && direction=='Inbound' && sourceAddressPrefix=='*' && (destinationPortRange=='22' || destinationPortRange=='3389')] | length(@)" -o tsv
Write-Host "Internet SSH/RDP open rules: $dangerRules (expected: 0)"

# Public IP count
$pipCount = az network public-ip list --query "length(@)" -o tsv
Write-Host "Public IP count: $pipCount (VM PIP 1 + LB PIP 1 + Bastion PIP 1 = 3 is normal)"

# RBAC Owner count
$ownerCount = az role assignment list --role "Owner" --scope "/subscriptions/$SUB_ID" --query "length(@)" -o tsv
Write-Host "Owner role holders: $ownerCount (recommended: 2 or fewer)"
```

#### 8.3 Compliance Assessment

```powershell
Write-Host "=== Compliance Assessment ==="

# Policy non-compliance rate
$total = az policy state list --query "length(@)" -o tsv
$nonCompliant = az policy state list --filter "complianceState eq 'NonCompliant'" --query "length(@)" -o tsv
$compRate = [math]::Round((($total - $nonCompliant) / $total) * 100, 1)
Write-Host "Policy compliance rate: $compRate% ($nonCompliant/$total non-compliant)"

# Resource Lock
$locks = az lock list --resource-group $RG_SEC --query "length(@)" -o tsv
Write-Host "Resource Lock count: $locks (1 or more = protected)"

# Tag coverage
$noTag = az resource list --resource-group $RG_SEC `
  --query "[?tags.Owner==null] | length(@)" -o tsv
Write-Host "Resources missing Owner tag: $noTag"
```

---

### Module 8 Key Summary (Workshop Q&A Points)

| Question | Key Answer |
|----------|-----------|
| Difference between MDC CSPM and CWP? | CSPM = scores misconfigurations and provides recommendations (prevention) / CWP = runtime threat detection and vulnerability scanning (detection & response) |
| How to achieve a Secure Score of 75? | ① Block internet SSH in NSG ② Enable JIT VM Access ③ Enable Defender plans ④ Enable Key Vault audit log |
| Customer responsibility in the Shared Responsibility Model? | IaaS: OS, app, data, IAM, and network configuration are all the customer's responsibility. The misunderstanding that "the cloud handles everything" is the biggest security risk |
| Benefits of SOAR automation? | Automates repetitive threat responses (Brute Force → NSG block) → reduces MTTD (time to detect) + MTTR (time to respond), freeing security staff for Threat Hunting |
| Why is EASM necessary? | Shadow IT, abandoned subdomains, and expired certificates that organizations are unaware of are real breach vectors. Finding them first from an attacker's perspective enables proactive remediation |
| Three principles of Zero Trust? | ① Explicit verification (always authenticate and authorize) ② Least privilege (Just Enough Access) ③ Assume Breach (assume compromise has already occurred — detect and isolate) |

---

## 🧹 Lab Environment Clean-up

> ⚠️ **Important:** Be sure to run this after completing the lab to avoid unnecessary costs!

```bash
# [Step 0] Revert Defender Standard → Free tier (prevent charges — must run first)
az security pricing create \
  --name "VirtualMachines" \
  --tier "Free"

# Verify Defender revert
az security pricing list \
  --query "[?name=='VirtualMachines'].{name:name, tier:pricingTier}" \
  --output table

# Delete all lab resource groups (run in parallel)
for rg in $RG_GOV $RG_NET $RG_SEC $RG_OPS; do
  echo "Requesting deletion: $rg"
  az group delete --name $rg --yes --no-wait
done

echo "Deletion requested. Full deletion takes 5–10 minutes."

# Check deletion progress
az group list \
  --query "[?contains(name, 'ltmsa')].{Name:name, State:properties.provisioningState}" \
  --output table

# Check Key Vault Soft Delete residuals and permanently delete if needed
az keyvault list-deleted --output table
# If needed: az keyvault purge --name <KV_NAME> --location koreacentral

# Delete Service Principals
az ad sp delete --id $(az ad sp list --display-name "claude-mcp-sp" --query "[].id" -o tsv) 2>/dev/null
az ad sp delete --id $(az ad sp list --display-name "github-actions-ltmsa" --query "[].id" -o tsv) 2>/dev/null

# Remove subscription from MG and delete MG
az account management-group subscription remove --name "LTM-Corp" --subscription "$SUB_ID"
az account management-group delete --name "LTM-Corp"
```

---

## 💬 Design Key Questions & Model Answers

### Q1. "Please describe your experience designing Azure 300-level architectures."

**STAR-format answer:**
- **Situation**: In an enterprise multi-team environment, network isolation and centralized security management were required
- **Task**: Design Hub-Spoke architecture and build a Landing Zone
- **Action**: Designed in the order Management Group → Policy → Hub VNet (Firewall, Bastion) → Spoke VNet (per app). Configured dual defense lines with NSG and Azure Firewall
- **Result**: Maintained each team's autonomy while consistently applying common security policies

### Q2. "Do you have experience practicing FinOps?"

**Key points:**
1. **Tag strategy**: 4 required tags: Environment/Project/Owner/CostCenter
2. **Budget alerts**: Notify responsible parties when reaching 75%, 90%, 100%
3. **Regular Advisor review**: Monthly right-sizing and unused resource cleanup
4. **RI adoption**: Stable prod workloads use 1-year RI for ~40% savings

### Q3. "How do you respond to outages during cloud operations?"

**SRE-style answer:**
1. **Detection**: Azure Monitor Alert → PagerDuty/Teams notification
2. **Initial response**: Check recent change history in Activity Log (KQL)
3. **Diagnosis**: Analyze correlation between error rate/CPU/memory in Log Analytics
4. **Recovery**: Restore from Backup or redeploy with Bicep
5. **Post-incident review (PIR)**: Root cause analysis → Strengthen Policy/Alert to prevent recurrence

### Q4. "Please explain how you harden Azure security."

**Defense in Depth:**
```
Layer 1: Identity  → Entra ID + MFA + Conditional Access
Layer 2: Network   → NSG + Azure Firewall + DDoS Protection
Layer 3: Compute   → Defender for Servers + Just-in-Time VM Access
Layer 4: Data      → Key Vault + encryption at rest/in transit
Layer 5: Monitoring → Defender for Cloud + Sentinel (SIEM)
```

### Q5. "How do you design for high availability and disaster recovery?"

| Tier | RTO | RPO | Solution |
|------|-----|-----|--------|
| Tier 1 (Mission Critical) | < 1 hour | < 15 minutes | Zone-redundant + ASR + RA-GRS |
| Tier 2 (Business Critical) | < 4 hours | < 1 hour | Availability Set + Azure Backup |
| Tier 3 (Standard) | < 24 hours | < 24 hours | Azure Backup once daily |

---

## 📚 Recommended Additional Learning Path

| Certification | Related Modules | Priority |
|------|-----------|----------|
| AZ-305 (Azure Solutions Architect Expert) | All of Modules 1–4 | Highest |
| AZ-700 (Network Engineer Associate) | Module 2 deep-dive | High |
| SC-100 (Cybersecurity Architect) | Module 3 deep-dive | High |
| FinOps Certified Practitioner (FOCP) | Module 6 deep-dive | High |

---

## Appendix: GitHub Repository Reference (Private AKS Workshop)

> Repository: https://github.com/jungfrau70/private-aks-workshop

The network foundation (Hub-Spoke, Bastion, VNet Peering) from this workshop connects directly to **Step 3: Network Infrastructure** in the above repository.  
If you need AKS deep-dive practice, refer to that repository and proceed in the following order:

```
This workshop Module 2 (Hub-Spoke Network)
    ↓
Private AKS Workshop Step 3 (Hub VNet + ACR + KeyVault)
    ↓
Private AKS Workshop Step 4-5 (Bastion + Private AKS Cluster)
    ↓
Private AKS Workshop Step 6-8 (App Deployment + AGIC)
```

---

## 🔧 Troubleshooting — Issues Encountered During Lab

> These are errors encountered while actually performing this workshop, along with solutions.  
> The same errors may occur depending on Azure CLI version, subscription type, and region environment.

| Error | Cause | Solution |
|------|------|------|
| `az policy assignment create` → MissingSubscription | Known CLI bug for MG/subscription scope assignment | Call REST API directly with `az rest --method PUT` |
| `az role assignment create` → MissingSubscription | Same as above | Use `az rest --method PUT` + generate GUID with PowerShell |
| `az consumption budget create` → 400 Invalid | CLI uses older API version | Call directly with `az rest` using `2023-05-01` API version |
| `az automation account create` → EOF / extension installation failure | Non-interactive environment restriction | Create with `az rest --method PUT` |
| Policy assignment ID typo | `e56962a6-…4c` (ends in c) | Verify with `az policy definition list --query "[?contains(displayName,'Allowed locations')]"` |
| MG policy list query → FilterNotFound | Missing atScope() filter | Add `&\$filter=atScope()` to URI |
| `--remote-vnet` full resource ID → InvalidArgumentValue | VNet Peering API limitation | Use only the VNet name string |
| Standard_B1s → SkuNotAvailable | Insufficient capacity in Korea Central | Use `Standard_D2s_v3` |
| `--enable-soft-delete true` not recognized | Default changed in CLI 2.87+ | Remove the option (soft delete is now applied by default) |
| `--enable-purge-protection false` → BadRequest | Cannot set to false after setting to true | Remove the option; document in Bicep as a comment |
| AzureMonitorLinuxAgent → GCS parameters error | AMA requires DCR | Use `az monitor diagnostic-settings create` |
| `diagnostic-settings create` → retentionPolicy error | Metrics API changed | Remove `retentionPolicy` from metrics JSON |
| Bash `$VAR` assignment → `C:/Program Files/Git/...` injected into path | Windows Git Bash environment variable bug | Assign variables in PowerShell |
| `az monitor metrics alert create` → scope error | Microsoft.Insights registration in progress | Retry after provider registration is complete |
| Key Vault name exceeds 24 chars → VaultNameNotValid | `uniqueString()` is 13 chars + prefix | Use `take(uniqueString(...), 8)` for only 8 characters |
| `az ad sp create-for-rbac --scopes` → path injection | Git path prepended to `/subscriptions/` in Windows Git Bash | Prefix command with `MSYS_NO_PATHCONV=1` |

---

*Date: 2026-06-13 | Prepared for LTM Korea Azure SA Interview*  
*Reference: LTM\workshop.md, LTM\Azure_SA_Interview_Workshop.md, https://github.com/jungfrau70/private-aks-workshop*
