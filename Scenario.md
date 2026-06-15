# Azure SA Workshop : Module-by-Module Scenario Descriptions

> Summarizes **why each module is needed**, **how it actually works**, and **how to explain the design decisions**.

---

## Full Landing Zone Picture (Overall Workshop Architecture)

The 7 modules in this workshop are not independent exercises -- they are a step-by-step process of **building a single enterprise Landing Zone**.

```
+------------------------------------------------------+

> **Architectural Point**: "A Landing Zone is not a single setting ->it is a layered structure. Each layer can be deployed independently, but the upper layers (Governance, Network) form the security foundation for the layers below."

---

## Pre-work: Management Group + Korea Region Restriction Policy

### Scenario
LTM Korea is a global enterprise. Under Korean data sovereignty regulations (Personal Information Protection Act, financial regulations), **all Azure resources must be deployed only in domestic regions (Korea Central / Korea South)**. This completely blocks developers from accidentally deploying to overseas regions.

### How It Works
```
[Developer] -- az group create --location japaneast
                    ->[Azure Policy: Allow Korea regions only]
    Scope: LTM-Corp Management Group (applied to all child subscriptions)
    Effect: Deny ->request rejected immediately
                    ->[Error] RequestDisallowedByPolicy: 'japaneast' is not in allowed list
```

### Core Structure
```
[Tenant Root Group]
  +-- [LTM-Corp MG]  -- Policy assignment location (subscription level or above)
        +-- LTM subscription_id 1
              +-- (automatically applied to all resource groups)
```

### Architectural Point
> "When a policy is assigned at the Management Group level, it is automatically inherited by all subscriptions below it. Subscription owners cannot override the policy, ensuring enterprise-wide compliance."

---

## Module 1: Governance & Landing Zone

### Scenario
A new project team has started using Azure. The CIO issued a mandate: "All resources must have an Owner tag so that cost billing can be tracked," and critical governance infrastructure must not be accidentally deleted.

### The Role of Three Governance Tools

| Tool | Role | When Applied |
|------|------|--------------|
| **Azure Policy** | Checks/enforces rules when new resources are created | Before creation (Deny) or after (Audit) |
| **RBAC** | Controls who can do what | Validated on every API call |
| **Resource Lock** | Prevents modification/deletion of existing resources | Blocks delete/modify requests |

### How It Works
```
[Resource creation request]
       -- [RBAC validation] ->Denied if no permission
       ->[Policy validation] ->Audit logged if no Owner tag (DoNotEnforce)
       ->[Resource creation complete]
       ->[Resource Lock] ->Subsequent delete attempt ->CanNotDelete error
```

### Architectural Point
> "Policy controls future resource creation, while Lock protects resources that already exist. The two tools serve different roles, so using them together achieves complete governance."

---

## Module 2: Network Architecture -- Hub-Spoke

### Scenario
LTM Korea requires Team A (app team) and Team B (data team) to have their own Azure environments, while shared infrastructure like firewalls, DNS, and VPN Gateways is managed centrally. Direct access to DB servers from the internet must also be completely blocked.

### Hub-Spoke Structure Roles

```
[Internet]
    -- HTTPS (443) only / LB public IP
[Hub VNet -- ltmsa-hub-vnet 10.0.0.0/16]  ->Shared services tier
    +-- AzureBastionSubnet (10.0.0.0/26)  ->Secure VM access (Azure-required name, /26 min, NO NSG)
    +-- mgmt-snet          (10.0.1.0/24)  ->Jumpbox VM (ltmsa-mgmt-nsg, no public IP)
           ->VNet Peering (hub-to-spoke + spoke-to-hub, bidirectional)
[Spoke VNet -- ltmsa-spoke-vnet 10.1.0.0/16]  ->Workload tier
    +-- web-snet (10.1.1.0/24)  ->App VM-1, VM-2, LB backend (ltmsa-web-nsg)
```

> **To-be (Production expansion)**: The workshop implements a Hub+Spoke1 2-VNet configuration. In an enterprise environment, add AzureFirewallSubnet + Azure Firewall to the Hub and expand Spokes per team/application.

### NSG Defense Line Design Principles
- **Web tier**: Internet -- HTTPS/HTTP allowed. SSH only via Bastion
- **App tier**: Inbound allowed only from web subnet (10.1.1.0/24)
- **DB tier**: SQL (1433) allowed only from app subnet (10.1.2.0/24). All else blocked (Deny All)

### Architectural Point
> "In Hub-Spoke, the Hub is the central point for shared security services. Spokes are isolated networks per team/app, connected only to the Hub via VNet Peering. Direct communication between Spokes is routed through the Hub's firewall, controlling East-West traffic as well."

---

## Module 3: Security & Identity

### Scenario
For application code to connect to a DB, it needs a connection string (including a password). Previously this was hardcoded in the code or managed as an environment variable -- a major cause of security incidents such as Git leaks and log exposure.

**Solution: Managed Identity + Key Vault Integration**

### How It Works (3 Steps)

```
[Step 1] Enable Managed Identity when creating a VM
    az vm create --assign-identity [system]
    -- Azure automatically registers a service principal for this VM in Entra ID
    ->An automatically renewed token is issued to the VM

[Step 2] Grant a role on Key Vault
    VM's Managed Identity ->"Key Vault Secrets User" role
    ->Registers permission: "This VM can read secrets from this Key Vault"

[Step 3] When app code runs inside the VM
    Code ->IMDS (169.254.169.254) token request
         ->Entra ID validates the VM and issues a token
         ->Token is used to call the Key Vault API
         ->Secret (DB connection string) is returned
```

### Code Comparison

```python
# -- Old approach ->password exposed in code
conn_str = "Server=sql.azure.com;Password=P@ssw0rd123!"

# ->Managed Identity approach ->no password in code
from azure.identity import ManagedIdentityCredential
from azure.keyvault.secrets import SecretClient

credential = ManagedIdentityCredential()
client = SecretClient("https://ltmsa-kv.vault.azure.net/", credential)
conn_str = client.get_secret("db-connection-string").value
```

### Connection to Zero Trust
```
Layer 1: Identity  -- Entra ID verifies the VM's identity
Layer 4: Data      ->Key Vault stores secrets encrypted
                     No credentials in code means no exfiltration path
```

### Architectural Point
> "Managed Identity is like an Azure-issued employee badge that the VM receives automatically. Developers don't need to embed credentials in code or manage rotation -- the Azure platform renews the token automatically. Because no password exists in the code to begin with, this aligns with Zero Trust principles."

---

## Module 4: Cloud Resiliency & HA

### Scenario
If a core LTM Korea service goes down due to a datacenter failure, significant losses occur. The business requirement is "recovery within 4 hours (RTO), maximum 1 hour of data loss tolerated (RPO)."

### Eliminating Single Points of Failure with Availability Zones

```
[Zone 1 -- Datacenter A]    [Zone 2 -- Datacenter B]
    ltmsa-vm-zone1              ltmsa-vm-zone2
          |                           |     [Zone-Redundant Standard Load Balancer]
              |     Zone 1 failure ->automatic traffic failover to Zone 2 (within seconds)
```

### RTO/RPO Design by Tier

| Tier | RTO | RPO | Solution | Cost |
|------|-----|-----|----------|------|
| Mission Critical | < 1 hour | < 15 min | Zone-redundant + ASR + RA-GRS | High |
| Business Critical | < 4 hours | < 1 hour | Availability Set + Backup | Medium |
| Standard | < 24 hours | < 24 hours | Daily backup | Low |

### Backup vs Disaster Recovery (ASR) Differences

| | Azure Backup | Azure Site Recovery |
|--|--------------|---------------------|
| **Scenario** | Accidental deletion, data corruption | Full region/datacenter failure |
| **RPO** | Hours to days | Minutes |
| **RTO** | Hours | Minutes to 1 hour |
| **Recovery unit** | File/VM level | Entire application |

### Architectural Point
> "High Availability (HA) and Disaster Recovery (DR) are different concepts. HA eliminates single points of failure to minimize service interruption, while DR failovers to another region when the entire region fails. Different strategies are applied per tier based on cost and RTO/RPO requirements."

---

## Module 5: Azure Monitor & Telemetry

### Scenario
When a running service's CPU spikes, the team doesn't notice until an outage occurs. A system is needed to detect anomalies in advance and automatically send alerts.

### Azure Monitor Data Flow

```
[Azure resources] -- metrics/logs auto-generated
      ->Diagnostic Settings
[Log Analytics Workspace]
      ->KQL query
      +-- [Dashboard] ->real-time visualization
      +-- [Alert Rules] ->triggered when threshold exceeded
                |           [Action Group]
                |      [Email / Teams / PagerDuty]
```

### Top 5 Essential KQL Queries

| Query | Purpose |
|-------|---------|
| `Heartbeat` | Check VM connectivity status |
| `Perf (CPU)` | Analyze CPU usage trends |
| `Perf (Memory)` | Memory capacity planning |
| `Syslog` (auth/authpriv) | Login failures -- Brute Force detection (Linux; `SecurityEvent` is Windows-only) |
| `AzureActivity` | Resource change audit trail |

### Alert Design Principles
- Use **P95 percentile**-based thresholds instead of simple averages -- prevents false alerts from momentary spikes
- **5-minute window** aggregation ->alerts only on sustained anomalies
- Distinguish Alert Severity 1 (Critical) / 2 (Warning) / 3 (Info)

### Architectural Point
> "Incident diagnosis process: Alert fires -- check recent changes in Activity Log ->correlate CPU/memory/error rate with KQL ->identify root cause ->remediate. Decisions are data-driven, not based on intuition."

---

## Module 6: FinOps & Cost Governance

### Scenario
The end-of-month Azure bill came in 30% over budget. It's impossible to tell which team, which service, or why it went over. Without tags, cost allocation is impossible, and no one cleaned up idle VMs.

### FinOps 3-Stage Cycle

```
[Inform -- Visibility]
  Use Cost Analysis to understand spend by service/team/tag
  "You can't reduce what you can't see"
        ->[Optimize -- Optimization]
  Right-sizing and idle resource cleanup via Advisor
  Commit discounts via RI/Savings Plans
        ->[Operate -- Governance]
  Set budget alerts (75% / 90% / 100%)
  Block untagged resources via tag policies
  Monthly Advisor review routine
        ->__________________________|
```

### Chargeback vs Showback

| | Showback | Chargeback |
|--|----------|------------|
| **Definition** | Show each team their cost information | Bill actual charges against team budget |
| **Effect** | Raises cost awareness | Strengthens incentive to reduce spend |
| **Best fit** | Early FinOps adoption | FinOps maturity stage |

### Tag Strategy (4 Essential Tags)

| Tag Key | Example Value | Purpose |
|---------|---------------|---------|
| `Environment` | prod / dev / lab | Environment classification |
| `Project` | LTM-SA-Workshop | Per-project cost aggregation |
| `Owner` | inhwan.jung@outlook.kr | Owner tracking |
| `CostCenter` | CC-1234 | Billing to accounting department |

### Architectural Point
> "FinOps is not a technology problem -- it's a culture and process problem. The key is making the cycle of tag strategy ->Cost Analysis ->Advisor review ->budget alerts a regular team routine."

---

## Module 7: Automation & IaC with Bicep

### Scenario
Manually clicking to create infrastructure each time has caused small differences between dev, staging, and production environments (Drift). One day a bug that only appeared in production couldn't be reproduced, and there was no way to track who changed what and when.

### Problems Solved by IaC (Bicep)

| Problem | Bicep Solution |
|---------|----------------|
| Environment inconsistency (Drift) | Deploy all environments from the same code |
| No change history | Git commits record who changed what and when |
| Deployment mistakes | `what-if` previews changes before actual deployment |
| Not reproducible | Code is the infrastructure state -- reproducible any time |

### What-if Deployment Flow

```
[Code change] -- git commit
      ->[az deployment group what-if]
      ->Preview list of resources that will change
      +-- + Resources to be created
      +-- ~ Resources to be modified
      +-- - Resources to be deleted
      ->After review
[az deployment group create]  ->Actual deployment
```

### Drift Detection Strategy

```
[Actual infrastructure state] -- az group export ->[ARM JSON]
[Bicep code state]             ->what-if compare  ->[Drift detected]
      ->When difference found
  Intentional change? ->Update Bicep code
  Accidental change?  ->Roll back infrastructure to code state
```

### Automation Runbook Usage (Cost Savings)

```
[Automation Account + Managed Identity]
      -- Daily at 7 PM KST (Schedule)
[Stop-VMsAfterHours Runbook]
      ->Query VMs with Environment=Lab tag
[Auto-shutdown all lab VMs]
      ->Eliminate unnecessary VM costs after business hours
[Estimated savings: 14 overnight hours × VM cost]
```

### Architectural Point
> "The core value of IaC is Idempotency. Running the same code 10 times always produces the same result. This guarantees consistency across environments and allows Git to serve as the Single Source of Truth for infrastructure."

---

## Exercise 7.4: GitHub Actions CI/CD -- LB HA Deployment (VM-1 + VM-2)

### Scenario
The development team pushes code to GitHub and wants it automatically deployed to two VMs behind a Standard Load Balancer -- with zero downtime. Manual deployment was error-prone, untracked, and blocked on nights/weekends.

**Solution: GitHub Actions 4-job pipeline + Azure Service Principal + Bicep IaC**

### How It Works (4-Job Pipeline)

```
[git push master]
        -- [Job 1: CI -- Test & Lint]
  ->npm install + npm run test:unit
  ->node --check src/app.js (syntax only ->no listen() hang)
        ->CI passes
[Job 2: deploy-infra -- Bicep: LB + VM-2]
  ->az deployment group what-if ->bicep/lb-vm2.bicep (preview)
  ->az deployment group create  ->ltmsa-lb (80/3000) + ltmsa-demo-vm-2
  ->Add VM-1 NIC to LB backend pool (dynamic ip-config name lookup)
        ->[Job 3: deploy-app ->Parallel matrix: VM-1 -- VM-2]
  ->Check VM running state (auto-start if stopped)
  ->az vm run-command invoke (no SSH ->Azure management plane):
       ->Install Node.js 18 if missing
       ->Deploy app.js + package.json to /opt/ltm-workshop
       ->npm install --production
       ->pm2 restart/start ltm-workshop
       ->curl http://localhost:3000/health (retry 6×)
        ->Both VMs healthy
[Job 4: verify-lb -- LB Health Check]
  ->curl http://<ltmsa-lb-pip>/health (port 80 ->3000)
  ->curl http://<ltmsa-lb-pip>/api/modules
```

### Why Execute Commands on VM Without SSH

```
Traditional approach:
[GitHub Actions]
    -- Requires open SSH (port 22)
    ->SSH key stored in GitHub Secrets
    ->NSG on VM allows 0.0.0.0/0:22 (security risk!)

Azure approach (az vm run-command):
[GitHub Actions]
    ->Azure Management API (HTTPS 443)
    ->Service Principal permission validation (Azure RBAC)
    ->Azure delivers script via VM agent (waagent)
    ->SSH port 22 never opened in NSG (Zero Trust!)
```

### Required Configuration Summary

| Item | Value |
|------|-------|
| GitHub Secret: `AZURE_CREDENTIALS` | Full SP JSON (`az ad sp create-for-rbac --sdk-auth`) |
| GitHub Secret: `ADMIN_PASSWORD` | VM-2 admin password (for lb-vm2.bicep) |
| VM-1 (existing) | `ltmsa-demo-vm` (ltmsa-security-rg) |
| VM-2 (Bicep) | `ltmsa-demo-vm-2` (ltmsa-security-rg) |
| Load Balancer | `ltmsa-lb` -- port 80 ->3000 |
| App path | `/opt/ltm-workshop` |
| Health check URL | `http://localhost:3000/health` (on-VM) / `http://<LB_IP>/health` (external) |
| SP permission scope | Subscription-level Contributor (E2E deletes/recreates RG) |

### IaC Strategy -- az CLI vs Bicep

```
az CLI  ->Network / security topology (VNet, NSG, Bastion, Jumpbox, VM-1)
           ->One-time, environment-scoped resources
           ->Ops team owns: explicit, auditable, easy to troubleshoot line-by-line

Bicep   ->Application-tier reusable module (lb-vm2.bicep: LB + VM-2)
           ->Repeatable pattern ->same template reused across regions/environments
           ->Provides: idempotency, what-if preview, typed parameters, output contracts
```

> Real-world analogy: "Network topology is managed by the platform team via CLI/Portal.
> Application-tier modules are owned by the app team as versioned Bicep templates."

### Architectural Point
> "When deploying to Azure VMs from GitHub Actions, `az vm run-command` replaces SSH. Commands go through the Azure management plane -- no inbound ports opened, no keys stored. The pipeline uses a hybrid IaC strategy: network/security topology is provisioned via az CLI (explicit, auditable), while the LB+VM application-tier module uses Bicep (idempotent, reusable, what-if capable). This mirrors real-world team ownership boundaries ->platform team controls topology, app team owns the Bicep module. The Service Principal uses subscription-level scope for E2E automation (RG delete/recreate requires subscription Contributor); production deployments targeting a stable RG can narrow to RG-level scope."

---

## Exercise 7.5: Zero Trust Admin Access -- Bastion + Jumpbox + Break-glass

### Scenario
The deployed VMs must be accessible to administrators, but opening SSH to the internet is prohibited by the corporate security policy (CVE risk, brute force, compliance audit failure). Three access patterns are implemented in a layered strategy -- from everyday operations to emergency break-glass.

### Three-Scenario Architecture

```
?붴븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븮
|              Admin Access ->Defense-in-Depth                    ->?졻븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븺
* Scenario 1: Azure Bastion (Zero Trust SSH/RDP)                  ->|    Browser ->Azure Portal ->Bastion (AzureBastionSubnet)        ->|                           ->VM via TLS tunnel (no public SSH)    ->?졻븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븺
* Scenario 2: Jumpbox Pattern (Enterprise Mgmt Subnet)            ->|    Bastion ->ltmsa-jumpbox (mgmt-snet, no public IP)            ->|           ->SSH ->App VMs (web-snet, port 22 from mgmt-snet)    ->?졻븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븺
* Scenario 3: Break-glass (Management Plane Bypass)               ->|    az vm run-command ->Azure API ->VM Agent                     ->|    (network restrictions irrelevant ->Management Plane only)     ->?싢븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븧?먥븴
```

### VNet Subnet Design

```
Hub VNet: ltmsa-hub-vnet (10.0.0.0/16)
  +-- AzureBastionSubnet: 10.0.0.0/26   -- Azure-required name, /26 min, NO NSG
  +-- mgmt-snet:          10.0.1.0/24   ->Jumpbox VM (ltmsa-mgmt-nsg, no public IP)
           ->VNet Peering (hub-to-spoke + spoke-to-hub)
Spoke VNet: ltmsa-spoke-vnet (10.1.0.0/16)
  +-- web-snet:           10.1.1.0/24   ->App VM-1, VM-2 (ltmsa-web-nsg)
```

### NSG Rule Changes vs. Traditional Setup

| NSG | Location | Direction | Rule Name | Source | Effect |
|-----|----------|-----------|-----------|--------|--------|
| ltmsa-web-nsg | Spoke web-snet | Inbound | allow-bastion-ssh | 10.0.0.0/26 (Hub Bastion) via Peering | Allow port 22 |
| ltmsa-web-nsg | Spoke web-snet | Inbound | allow-jumpbox-ssh | 10.0.1.0/24 (Hub mgmt-snet) via Peering | Allow port 22 |
| ltmsa-mgmt-nsg | Hub mgmt-snet | Inbound | allow-bastion-to-jumpbox | 10.0.0.0/26 (Hub Bastion) | Allow port 22 |
| ltmsa-mgmt-nsg | Hub mgmt-snet | **Outbound** | allow-jumpbox-to-spoke | 10.0.1.0/24 -- 10.1.1.0/24 (Spoke) | Allow port 22 |
| Any NSG | ->| Inbound | *(no rule)* | Internet | **Blocked** (no 0.0.0.0/0:22 rule) |

> **Hub-Spoke Peering and NSG**: When Bastion SSH's into a Spoke VM, the source IP is the Hub AzureBastionSubnet (10.0.0.0/26). Even after traversing the Peering, the source IP remains the Hub subnet IP, so the `allow-bastion-ssh` rule source on the Spoke web-nsg must be set to `10.0.0.0/26`. The mgmt-nsg outbound rule can also communicate via Azure's default `AllowVnetOutBound` (which includes peered VNets), but it is added explicitly so that compliance tools can inspect the intent.

### Scenario 1 -- Azure Bastion (Zero Trust, Hub VNet)

```bash
# Hub VNet: AzureBastionSubnet (NO NSG ->Azure hard requirement)
az network vnet create --name ltmsa-hub-vnet --address-prefix 10.0.0.0/16 \
  --subnet-name AzureBastionSubnet --subnet-prefix 10.0.0.0/26

# Standard SKU Public IP (zone-redundant) + Bastion in Hub
az network public-ip create --name ltmsa-bastion-pip --sku Standard --zone 1 2 3
az network bastion create --name ltmsa-bastion --sku Basic \
  --public-ip-address ltmsa-bastion-pip --vnet-name ltmsa-hub-vnet

# Bastion reaches Spoke VMs through VNet Peering ->no public SSH needed on Spoke
```

- Browser ->Azure Portal ->Bastion (Hub) ->[VNet Peering] ->App VM (Spoke): TLS encrypted
- Spoke web-nsg `allow-bastion-ssh` source = `10.0.0.0/26` (Hub Bastion subnet IP)

### Scenario 2 -- Jumpbox Pattern (Hub mgmt-snet ->Spoke via Peering)

```bash
# Jumpbox VM in Hub mgmt-snet: no public IP
az vm create --name ltmsa-jumpbox --size Standard_D2s_v3 \
  --vnet-name ltmsa-hub-vnet --subnet mgmt-snet \
  --public-ip-address "" --nsg ""

# From Jumpbox: SSH to Spoke App VM via VNet Peering
# ssh azureuser@<spoke-vm-private-ip>   (10.1.1.x)
```

- Access path: Bastion (Hub) ->Jumpbox (Hub mgmt-snet) ->[Peering] ->App VM (Spoke web-snet)
- Jumpbox is a single management entry point crossing the Hub-Spoke boundary ->centralizes audit logs
- Standard_D2s_v3: B2s/DS2v2 not available in Korea Central; D2s_v3 used instead

### Scenario 3 -- Break-glass (Management Plane)

```bash
# Emergency access ->bypasses NSG, Bastion, network entirely
az vm run-command invoke \
  --resource-group ltmsa-security-rg \
  --name ltmsa-demo-vm \
  --command-id RunShellScript \
  --scripts "pm2 list; ss -tlnp | grep :3000"
```

- Delivered via Azure VM Agent (waagent) ->Management Plane, not data plane
- No network path required ->works even if NSG blocks all inbound traffic
- Use case: emergency diagnostics, post-incident forensics, runbook automation

### Why This Architecture (Design Rationale)

```
Question: "How do you manage VMs in Azure without opening SSH to the internet?"

Answer structure (4 layers):
  1. Remove internet-facing SSH (NSG rule delete)
  2. Azure Bastion ->browser-based, no client software, MFA/Conditional Access inherited
  3. Jumpbox ->single-entry choke point, audit trail, PIM for just-in-time access
  4. Break-glass ->az vm run-command for emergency / automation (no network dependency)

Key differentiator vs on-prem:
  "Azure Bastion replaces the traditional bastion host ->it's a PaaS service, no VM to patch,
   natively integrated with AAD/Conditional Access. The Jumpbox adds a second trust boundary
   for lateral movement control. Break-glass via run-command is unique to cloud
   (Management Plane) ->on-prem has no equivalent."
```

### Required Configuration Summary

| Item | Value |
|------|-------|
| Hub VNet | `ltmsa-hub-vnet` (10.0.0.0/16) -- Bastion + Jumpbox |
| Spoke VNet | `ltmsa-spoke-vnet` (10.1.0.0/16) ->App VMs + LB |
| VNet Peering | hub-to-spoke + spoke-to-hub (bidirectional, allow-vnet-access) |
| AzureBastionSubnet | `10.0.0.0/26` in Hub (exact name required, no NSG) |
| Bastion SKU | Basic (SSH/RDP; Standard adds tunneling/IP connect) |
| Jumpbox location | Hub mgmt-snet (10.0.1.0/24) |
| Jumpbox size | `Standard_D2s_v3` (B2s/DS2v2 not available in Korea Central) |
| Jumpbox public IP | None (Bastion-only access) |
| NSG: Spoke web-snet source | `10.0.0.0/26` (Hub Bastion) + `10.0.1.0/24` (Hub mgmt) via Peering |
| Break-glass permission | `Microsoft.Compute/virtualMachines/runCommands/action` |

### Architectural Point
> "We removed internet-facing SSH entirely and replaced it with three layered access patterns. Azure Bastion gives browser-based Zero Trust access via the portal, with MFA automatically inherited from Azure AD. The Jumpbox in a dedicated mgmt subnet acts as a second trust boundary -- any lateral movement from management to application requires passing through it. For emergency situations, `az vm run-command` delivers scripts via the Azure Management Plane, completely bypassing network controls ->this is the cloud equivalent of console access on-prem. All three patterns are codified in the E2E automation workflow."

---

## Module 8 (Post-E2E): Security Artifacts -- Compliance Assessment & Vulnerability Check

### Scenario

The E2E test has passed. The app is being served through the LB, and Bastion, Jumpbox, and Break-glass are all working. Now the security officer asks: **"How secure is this infrastructure?"** There is a significant difference between simply saying "We configured NSG rules" and submitting a **quantified security posture report**.

### Why This Must Be Done After Deployment

```
Module 3 (before deployment)         Module 8 (after deployment)
??????????????????????????????        ??????????????????????????????????????
Concept explanation + activation      Inspect against actually deployed infra
NSG concept explanation               Extract real NSG rule list + detect risky rules
Defender activation                   Real Secure Score + list of unhealthy items
Key Vault configuration               Real KV soft-delete / purge-protection state
```

> Defender for Cloud must scan **existing resources** before recommendations are generated.  
> NSG auditing requires **actually deployed rules** to determine risk.  
> RBAC auditing produces meaningful results only **after SPs, MIs, and users have been role-assigned**.

### Three Artifact Structure

```
[Artifact 1] Security Posture Assessment
  +-- Secure Score status (current / max / percentage)
  +-- High / Medium / Low unhealthy item counts
  +-- Top 5 immediate action items

[Artifact 2] Vulnerability Assessment
  +-- NSG risky rule detection (internet -- SSH/RDP fully open)
  +-- Public IP exposure status (intentional vs unintentional)
  +-- Key Vault configuration (soft delete, purge protection, RBAC)
  +-- Managed Identity coverage (AMA authentication assurance)
  +-- RBAC over-privilege (Owner/Contributor subscription-level usage)

[Artifact 3] Compliance Assessment
  +-- Azure Policy compliance rate (subscription / RG level)
  +-- CIS Azure Benchmark v2.0 ->7 key controls
  +-- Resource Lock status
  +-- Tag compliance rate (Environment / Project / Owner ->3 required tags)
```

### How It Works

```
[E2E Test Passed]
      -- [az security secure-score show]              ->Actual score scanned by Defender
[az security assessment list]                ->Unhealthy recommendation list
[az network nsg rule list + filter]          ->Detect 0.0.0.0/0:22 allow rules
[az vm list --query identity.type]           ->Identify VMs without Managed Identity
[az policy state list --filter NonCompliant] ->Policy-violating resources
[az resource list + tag missing check]       ->Calculate tag compliance rate
      ->[Write security artifact report]             ->Inspection results + action plan table
      ->[Clean-up]                                   ->Final checkpoint before teardown
```

### Architectural Point
> "Security must be validated at two stages: design time (Module 3) and operations time (Module 8).  
> At design time, apply principles. At operations time, measure actual configuration.  
> **Quantitative metrics** such as Secure Score and CIS Benchmark compliance rate are required to determine improvement direction and priority."

### Detailed Command Reference
- CLI commands: `COMMANDS.md` -- Module 8 section
- Result report templates: `E2E_Test.md` ->Section 8

---

## To-be Architecture Recommendations

> Current workshop builds an **As-is** foundation (single-region, hybrid IaC, no DR).
> The following recommendations describe the **To-be** evolution path toward production-grade architecture.

---

### Recommendation 1 -- IaC Full Coverage (Configuration Management)

**Problem with As-is:**
```
VNet, NSG, Bastion, Jumpbox, VM-1  -> az CLI (imperative, stateless)
LB + VM-2                          -> Bicep  (declarative, stateful per deployment)
```
CLI-provisioned resources have no state file. Drift goes undetected. Re-running the same CLI commands may produce different results (idempotency not guaranteed).

**To-be:**
```
+------------------------------------------------------+

Key gains:
- `az deployment group what-if` across **all** resources (drift detection)
- **Bicep Deployment Stacks** ->tracks which resources belong to a deployment, enables `az stack group delete` for clean teardown
- Parameter files per environment ->no hardcoded values in workflow
- GitHub Actions: add `what-if` gate before `create` in every PR

```bicep
// modules/vm.bicep ->reusable single VM module
param vmName string
param subnetId string
param publicIp bool = false
// VM-1: publicIp=true  VM-2: publicIp=false (via lb-vm2.bicep)
// Jumpbox: publicIp=false, different subnet
```

---

### Recommendation 2 — Availability Zones (HA Enhancement)

**Problem with As-is:**
VM-1 and VM-2 are created without `--zone` assignment — both may land on the same physical fault domain — LB HA provides no real protection against zone failure.

**To-be:**
```
Zone 1                    Zone 2
+-------------------+     +-------------------+
| ltmsa-demo-vm     |     | ltmsa-demo-vm-2   |
| (VM-1, AZ 1)      |     | (VM-2, AZ 2)      |
+-------------------+     +-------------------+
          \                /
           Zone-redundant
               Standard LB (AZ 1,2,3)
```

Changes required:
```bash
# VM-1: add --zone 1
az vm create ... --zone 1

# lb-vm2.bicep: add availabilityZone
resource vm2 ... = {
  zones: ['2']
  ...
}

# LB PIP: already zone-redundant (zone 1, 2, 3)
```

---

### Recommendation 3 — Disaster Recovery (DR)

**Problem with As-is:**
Single region (koreacentral). No failover path. RTO = provisioning time (~45 min from E2E). RPO = data since last backup (currently no backup configured).

**To-be: Active-Passive Multi-Region**
```
koreacentral (Primary)          koreasouth (Secondary — paired region)
+---------------------------+     +---------------------------------------+
| ltmsa-security-rg         |─ASR→| ltmsa-security-rg-dr                  |
|   VM-1 (AZ 1)             |────→|   VM-1-replica (ASR managed)          |
|   VM-2 (AZ 2)             |────→|   VM-2-replica (ASR managed)          |
|   Standard LB             |     |   Standard LB (standby)               |
+---------------------------+     +---------------------------------------+
                Azure Traffic Manager
                  (Priority routing: primary -> secondary)
                  or Azure Front Door (global HTTP/S)
```

Implementation steps:
```bash
# 1. Recovery Services Vault (koreacentral)
az backup vault create --name ltmsa-rsv \
  --resource-group ltmsa-security-rg --location koreacentral

# 2. Enable Azure Backup for VMs
az backup protection enable-for-vm \
  --vault-name ltmsa-rsv \
  --resource-group ltmsa-security-rg \
  --vm ltmsa-demo-vm \
  --policy-name DefaultPolicy

# 3. Azure Site Recovery: replicate VMs to koreasouth
#    (configured via Portal or az recoveryservices — requires ASR vault in secondary region)

# 4. Azure Traffic Manager (DNS-based failover)
az network traffic-manager profile create \
  --name ltmsa-tm --resource-group ltmsa-security-rg \
  --routing-method Priority --dns-config-relative-name ltmsa-workshop \
  --unique-dns-name ltmsa-workshop --ttl 30 \
  --monitor-protocol HTTP --monitor-port 80 --monitor-path /health

# Primary endpoint (priority 1)
az network traffic-manager endpoint create \
  --name primary --profile-name ltmsa-tm \
  --resource-group ltmsa-security-rg \
  --type azureEndpoints --priority 1 \
  --target-resource-id <koreacentral-LB-PIP-id>

# Secondary endpoint (priority 2 -- failover)
az network traffic-manager endpoint create \
  --name secondary --profile-name ltmsa-tm \
  --resource-group ltmsa-security-rg \
  --type azureEndpoints --priority 2 \
  --target-resource-id <koreasouth-LB-PIP-id>
```

| DR Metric | As-is | To-be |
|-----------|-------|-------|
| RTO | ~45 min (full E2E rebuild) | ~15 min (ASR failover) |
| RPO | No backup = data loss risk | ~1 hour (backup policy) / ~seconds (ASR sync) |
| Failover trigger | Manual (workflow_dispatch) | Automatic (Traffic Manager health probe) |
| Scope | Single region | koreacentral + koreasouth (Azure paired regions) |

---

### Recommendation 4 -- GitOps & Drift Detection (IaC State Automation)

**Problem with As-is:**
No automated detection when actual Azure state diverges from the declared IaC state (e.g., someone manually changes an NSG rule in the portal).

**To-be:**
```
+------------------------------------------------------+

```yaml
# .github/workflows/drift-detect.yml (example)
on:
  schedule:
    - cron: '0 1 * * *'   # daily 10:00 KST

jobs:
  drift-check:
    steps:
      - name: Bicep what-if
        run: |
          RESULT=$(az deployment group what-if \
            --resource-group ltmsa-security-rg \
            --template-file bicep/network.bicep \
            --parameters environments/prod.bicepparam \
            --result-format FullResourcePayloads)
          if echo "$RESULT" | grep -q '"changeType": "Modify"'; then
            echo "DRIFT DETECTED"
            # gh issue create ...
            exit 1
          fi
```

---

### Recommendation 5 -- Golden Image & Immutable Infrastructure

**Problem with As-is:**
```
Create VM (bare OS) ->apt install Node.js at deploy time ->deploy app
```
OS state is non-deterministic ->deployment time and success depend on dpkg lock from unattended-upgrades, network speed, and apt mirror availability. In a DR scenario, RTO is hostage to "how fast apt finishes."

**Root cause ->Mutable Infrastructure anti-pattern:**
- Even with the same IaC code, post-boot OS state differs over time
- OS state in production and DR environments may diverge ->not reproducible
- `az vm run-command` is for Break-glass/diagnostics ->not a package installation mechanism

**To-be: Immutable Infrastructure with Golden Image**
```
+------------------------------------------------------+

**Implementation Example (Packer HCL):**
```hcl
# packer/ltm-workshop-app.pkr.hcl
source "azure-arm" "ubuntu" {
  image_publisher = "Canonical"
  image_offer     = "0001-com-ubuntu-server-jammy"
  image_sku       = "22_04-lts-gen2"
  location        = "koreacentral"
  vm_size         = "Standard_D2s_v3"
  managed_image_resource_group_name = "ltmsa-security-rg"
  managed_image_name                = "ltm-workshop-app-image"
}

build {
  sources = ["source.azure-arm.ubuntu"]

  provisioner "shell" {
    inline = [
      # OS hardening
      "sudo systemctl disable unattended-upgrades --now",
      "sudo apt-get remove -y unattended-upgrades",
      # Runtime
      "curl -fsSL https://deb.nodesource.com/setup_18.x | sudo bash -",
      "sudo apt-get install -y nodejs",
      "sudo npm install -g pm2",
      # Register pm2 with systemd
      "sudo env PATH=$PATH:/usr/bin pm2 startup systemd -u root --hp /root",
      "sudo systemctl enable pm2-root",
      # App directory
      "sudo mkdir -p /opt/ltm-workshop",
      "sudo chown azureuser:azureuser /opt/ltm-workshop"
    ]
  }

  post-processor "shell-local" {
    command = "az sig image-version create --resource-group ltmsa-security-rg --gallery-name ltmsa-gallery --gallery-image-definition ltm-workshop-app --gallery-image-version 1.0.0 --managed-image ltm-workshop-app-image --target-regions koreacentral"
  }
}
```

**Simplified deploy-app after Golden Image:**
```bash
# No package installation ->only inject app.js + restart
az vm run-command invoke \
  --resource-group ltmsa-security-rg \
  --name ltmsa-demo-vm \
  --command-id RunShellScript \
  --scripts "
    echo '$APP_B64' | base64 -d > /opt/ltm-workshop/app.js
    cd /opt/ltm-workshop && npm install --production --silent
    pm2 restart ltm-workshop --update-env || \
      PORT=3000 pm2 start /opt/ltm-workshop/app.js --name ltm-workshop
  "
# Execution time: ~30 sec (previously ~10 min ->95% reduction)
```

**DR perspective improvements:**

| DR Metric | As-is (Mutable) | To-be (Immutable) |
|-----------|-----------------|-------------------|
| Time to serve app after VM deployment | ~10 min (apt non-deterministic) | ~30 sec (runtime baked into image) |
| RTO (VM failure ->new VM online) | ~12 min (1 min VM + 10 min apt + 1 min app) | ~2 min (1 min VM + 30 sec app inject) |
| DR environment reproducibility | Non-deterministic (apt state differs) | Same image ->100% identical |
| Risk of deployment failure due to apt lock | Present | None |
| Image version management | None | Azure Compute Gallery (SemVer) |

> **Core principle**: "Deploy infrastructure, not package managers."  
> There is no scenario in a DR situation where `apt install` can be allowed to fail. Runtime goes in the image; only code is injected at deploy time.

---

### Evolution Roadmap Summary

```
As-is (Workshop)           To-be Step 1            To-be Step 2
??????????????????         ????????????????         ??????????????????????
az CLI + lb-vm2.bicep   -> Full Bicep modules    -> Bicep Deployment Stacks
Single region           -> AZ placement (1,2)    -> Multi-region (ASR + TM)
No backup               -> Azure Backup daily    -> ASR continuous replication
Manual deploy only      -> PR what-if gate       -> Drift detection (scheduled)
No state tracking       -> Parameter files/env   -> GitOps drift auto-remediation
Mutable VM (apt@deploy) -> Golden Image (Packer) -> Azure Compute Gallery + VMSS
```

---

*Date: 2026-06-13 | LTM Korea Azure SA Workshop*

