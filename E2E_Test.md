# E2E Test Procedure

> Workflow: `.github/workflows/e2e-test.yml`  
> Repository: `jungfrau70/github-actions-azure`  
> Purpose: Delete the entire infrastructure and rebuild from scratch to automatically verify that LB + Zero Trust admin access + Break-glass patterns work correctly

---

## 1. Prerequisites

### 1.1 GitHub Secrets Verification

| Secret | Content | Notes |
|--------|---------|-------|
| `AZURE_CREDENTIALS` | Full JSON output of `az ad sp create-for-rbac --sdk-auth` | Subscription-level Contributor required |
| `ADMIN_PASSWORD` | VM admin password | Shared by VM-1, VM-2, Jumpbox |

> **SP scope note**: E2E deletes and recreates the RG, so **subscription-level** Contributor is required. An RG-scoped SP will fail when the RG does not yet exist.

```bash
# Create SP (Windows Git Bash: MSYS_NO_PATHCONV=1 required)
MSYS_NO_PATHCONV=1 az ad sp create-for-rbac \
  --name "github-actions-ltmsa" \
  --role Contributor \
  --scopes "/subscriptions/$(az account show --query id -o tsv)" \
  --sdk-auth --output json > /tmp/sp.json

gh secret set AZURE_CREDENTIALS \
  --repo jungfrau70/github-actions-azure \
  --body "$(cat /tmp/sp.json)"

gh secret set ADMIN_PASSWORD --repo jungfrau70/github-actions-azure
rm /tmp/sp.json
```

### 1.2 KoreaCentral VM Size Availability

| VM Size | Purpose | Status |
|---------|---------|--------|
| `Standard_D2s_v3` | VM-1, VM-2, Jumpbox | ✓ Available |
| `Standard_DS2_v2` | - | ✗ SkuNotAvailable |
| `Standard_B2s` | - | ✗ SkuNotAvailable (Capacity Restrictions) |

---

## 2. E2E Pipeline Structure

```
[Preflight]
    ↓ (validate confirm_destroy = "DESTROY")
[Step 1] Delete ltmsa-security-rg
    ↓ (wait for full RG deletion — up to 30 min, including Bastion)
[Step 2] VNet + NSG + Bastion
    ↓ (Bastion starts async with --no-wait)
    ├── [Step 3a] Jumpbox VM (mgmt-snet, no public IP) ───┐
    └── [Step 3b] VM-1 (web-snet, public IP present)      │
                     ↓                                     │
         [Step 4] Bicep: LB + VM-2 + VM-1 → backend pool  │
                     ↓                                     │
              [Step 5] App deploy (VM-1 ∥ VM-2)           │
                     ↓  ←──────────────────────────────────┘
         [Step 6] Verify: LB + Bastion + Jumpbox + Break-glass
```

**IaC Strategy (Hybrid)**

| Tool | Target Resources | Reason |
|------|-----------------|--------|
| az CLI | RG, VNet, NSG, Bastion, Jumpbox, VM-1 | Topology/security boundary — explicit, auditable |
| Bicep (`lb-vm2.bicep`) | Standard LB + VM-2 | Reusable module — idempotent, what-if, output contract |

---

## 3. Execution Procedure

### 3.1 GitHub Web UI

```
GitHub Repo → Actions → "E2E Test — Full Fresh Deploy" → Run workflow
  confirm_destroy: DESTROY      ← must be uppercase
  environment:     dev
```

### 3.2 GitHub CLI

```bash
gh workflow run e2e-test.yml \
  --repo jungfrau70/github-actions-azure \
  --ref master \
  -f confirm_destroy=DESTROY \
  -f environment=dev
```

### 3.3 Progress Monitoring

```bash
# Get latest run ID
gh run list --repo jungfrau70/github-actions-azure --limit 3

# Real-time monitoring
gh run watch <RUN_ID> --repo jungfrau70/github-actions-azure

# View specific job log
gh run view --job=<JOB_ID> --log --repo jungfrau70/github-actions-azure
```

---

## 4. Step-by-Step Details

### Preflight — Safety Gate (~2 sec)

- Validates that `confirm_destroy` input is exactly `"DESTROY"`
- Any other value causes immediate failure → prevents accidental RG deletion

---

### Step 1 — Delete ltmsa-security-rg (up to 30 min)

**Key actions:**
1. List Resource Locks → delete any that exist (a lock causes `az group delete` to fail silently)
2. Run `az group delete --yes --no-wait`
3. Poll 60 × 30 sec (30 min) — wait until RG existence returns `false`

**Timing:**
- RG does not exist: ~8 sec (skip)
- RG exists with Bastion: **15–25 min** (Bastion deletion is the dominant factor)

> **Note**: Do not trigger a new E2E run while a previous one is still in progress. If another run issues run-command while the RG is being deleted, an `OperationPreempted` error occurs.

---

### Step 2 — Hub-Spoke VNet + NSG + Peering + Bastion (~1 min 50 sec)

**Hub-Spoke architecture** — two separate VNets connected via VNet Peering:

**Hub VNet** (`ltmsa-hub-vnet`, 10.0.0.0/16) — shared services:

| Resource | Name | Address / Config |
|----------|------|-----------------|
| AzureBastionSubnet | (fixed name, Azure requirement) | 10.0.0.0/26 — **no NSG allowed** |
| mgmt-snet | Jumpbox VM | 10.0.1.0/24 |
| mgmt-NSG | `ltmsa-mgmt-nsg` | Bastion→Jumpbox SSH Inbound(100), Jumpbox→web-snet SSH **Outbound**(200) |
| Bastion Public IP | `ltmsa-bastion-pip` | Standard Static, Zone 1-2-3 |
| Azure Bastion | `ltmsa-bastion` | Standard SKU, **--no-wait** (async — verified in Step 6) |

**Spoke VNet** (`ltmsa-spoke-vnet`, 10.1.0.0/16) — workload tier:

| Resource | Name | Address / Config |
|----------|------|-----------------|
| web-snet | App VMs (VM-1, VM-2) | 10.1.1.0/24 |
| web-NSG | `ltmsa-web-nsg` | Bastion SSH(100), Jumpbox SSH(110), App 3000(200), HTTP 80(210), LB probe(300) |

**VNet Peering**: Hub ↔ Spoke bidirectional (allows Bastion/Jumpbox in Hub to reach App VMs in Spoke)

> **NSG direction note**: `allow-jumpbox-to-web` is an **Outbound** rule on mgmt-NSG. Setting it as Inbound would block SSH from Jumpbox to web-snet.

---

### Step 3a — Jumpbox VM (Hub mgmt-snet) (~1 min 21 sec, parallel with Step 3b)

**Resources created:**

| Item | Value |
|------|-------|
| VM name | `ltmsa-jumpbox` |
| Size | `Standard_D2s_v3` |
| Subnet | mgmt-snet in **Hub VNet** (10.0.1.0/24) |
| Public IP | **None** (accessible only via Bastion) |
| NSG | mgmt-NSG (applied at subnet level) |
| Auth | password (`ADMIN_PASSWORD`) |
| cloud-init | Pre-installs Node.js 18 + pm2 at boot |

**Success criteria**: Step 6 verifies private IP only — no public IP assigned.

---

### Step 3b — VM-1 (Spoke web-snet) (~1 min 24 sec, parallel with Step 3a)

| Item | Value |
|------|-------|
| VM name | `ltmsa-demo-vm` |
| Size | `Standard_D2s_v3` |
| Subnet | web-snet in **Spoke VNet** (10.1.1.0/24) |
| Public IP | Standard SKU (direct access for diagnostics) |
| NSG | web-NSG (applied at subnet level) |
| cloud-init | Pre-installs Node.js 18 + pm2 at boot |

---

### Step 4 — Bicep: LB + VM-2 (~1 min)

**`bicep/lb-vm2.bicep` deploys:**

| Resource | Name | Description |
|----------|------|-------------|
| Public IP | `ltmsa-lb-pip` | LB frontend IP |
| Standard LB | `ltmsa-lb` | Frontend 80 → Backend 3000, TCP probe |
| NIC (VM-2) | `ltmsa-demo-vm-2-nic` | web-snet, connected to LB backend pool |
| VM-2 | `ltmsa-demo-vm-2` | Standard_D2s_v3, web-snet |

**Post-Bicep step**: Add VM-1 NIC to LB backend pool (VM-1 was created via az CLI and is not automatically registered with the LB).

---

### Step 5 — App Deploy to VM-1 & VM-2 (~1 min 50 sec, parallel)

Deploys Node.js app to each VM via `az vm run-command invoke` (no SSH port required — uses Azure Management Plane):

```
Execution sequence inside VM:
1. cloud-init status --wait   (Node.js 18 + pm2 already installed by cloud-init at boot)
2. Create /opt/ltm-workshop/ directory
3. Extract app.js + package.json (base64 → files)
4. npm install --production
5. pm2 kill                   (stop any existing daemon cleanly)
6. pm2 start app.js --name ltm-workshop
7. pm2 save --force           (persist process list to dump file)
8. systemctl enable --now pm2-root  (hand ownership to systemd — Restart=on-failure)
9. Health check: curl http://localhost:3000/health (6× × 5 sec = up to 30 sec)
```

**Timing**: ~2 min — Node.js and pm2 are pre-installed by cloud-init at VM creation, so no package installation happens here.

> **pm2 → systemd handover**: After `pm2 save`, `systemctl enable --now pm2-root` starts the systemd unit that owns the pm2 daemon. If pm2 crashes, systemd restarts it automatically (`Restart=on-failure`). Previously, Step 6 intermittently failed because a manually-started pm2 process died between steps.

---

### Step 6 — Verify: LB + Bastion + Break-glass

**Verification items:**

| Scenario | Check | Success Criteria |
|----------|-------|-----------------|
| Scenario 1 | LB health check | `http://<LB_IP>/health` 200 OK |
| Scenario 1 | API response | `/api/modules`, `/api/status` return JSON |
| Scenario 2 | Bastion state | provisioningState = `Succeeded` (wait up to 15 min) |
| Scenario 2 | Jumpbox public IP | public IP = **none** |
| Scenario 3 | Break-glass | `az vm run-command` executes successfully on VM-1 |

**Final output:**
```
==================================================
  E2E TEST PASSED
==================================================
  [Serving]
  LB URL  : http://<LB_IP>       (port 80 → 3000)
  VM-1    : http://<VM1_IP>:3000 (direct)
  VM-2    : (private IP, via LB)

  [Admin Access — Zero Trust]
  Bastion : Azure Portal → ltmsa-bastion
  Jumpbox : <private_IP> (mgmt-snet, no public IP)
  Path    : Bastion → Jumpbox → SSH → App VMs

  [Break-glass]
  az vm run-command → Management Plane (no SSH port required)
==================================================
```

---

## 5. Expected Duration

| Step | Actual Duration | Notes |
|------|----------------|-------|
| Preflight | ~2 sec | |
| Step 1 Delete | 8 sec (no RG) / **~15 min** (with Bastion) | Bastion deletion is the bottleneck |
| Step 2 Network | ~1 min 50 sec | Hub-Spoke + NSG + Peering + Bastion (async) |
| Step 3a Jumpbox | ~1 min 21 sec | Parallel with Step 3b |
| Step 3b VM-1 | ~1 min 24 sec | Parallel with Step 3a |
| Step 4 LB+VM-2 | ~1 min 41 sec | Bicep what-if + deploy + NIC registration |
| Step 5 App Deploy | **~1 min 50 sec** | Node.js pre-installed via cloud-init — no apt |
| Step 6 Verify | ~5 min 56 sec | LB probe wait + Bastion state check |
| **Total (fresh, no Bastion)** | **~15 min** | |
| **Total (re-run, Bastion exists)** | **~29 min** | Bastion deletion dominates Step 1 |

> Timings measured from actual run `27514206932` (2026-06-15).

---

## 6. Troubleshooting

| Error | Step | Cause | Resolution |
|-------|------|-------|------------|
| `SkuNotAvailable` | Step 3a | B2s/DS2v2 capacity exhausted in KoreaCentral | Use `Standard_D2s_v3` |
| `still exists after 30 min` | Step 1 | Bastion deletion delayed | Manual delete via portal or Azure support, then retry |
| `OperationPreempted` | Step 5 | Two E2E runs overlapping simultaneously | Wait for or cancel previous run, then retry |
| `No subscriptions found` | All steps | AZURE_CREDENTIALS SP expired or RG-scoped | Recreate SP at subscription level and update secret |
| `Required input 'confirm_destroy' not provided` | Preflight | Missing `-f confirm_destroy` in gh CLI call | Add `-f confirm_destroy=DESTROY` |
| `RuntimeError: content already consumed` | Step 3a | Azure CLI Python bug during error reporting | Check inner error for actual cause (e.g. SkuNotAvailable) |
| Health check failed | Step 5 | Timeout during Node.js installation | Re-run (Node.js already installed — passes quickly) |

---

## 7. After E2E Test — Log Analysis

> Adds log collection + KQL analysis environment to the running infrastructure after E2E passes.  
> **Independent of the E2E workflow** — can be executed any time while infrastructure is live.

---

### 7.1 Architecture

```
VM-1 (ltmsa-demo-vm)   ─┐
                         ├─ [AMA latest] ─→ [DCR ltmsa-dcr] ─→ [ltmsa-law]
VM-2 (ltmsa-demo-vm-2) ─┘
                              Syslog + Perf (60s)    Log Analytics Workspace
```

| Component | Resource name | Description |
|-----------|--------------|-------------|
| Log Analytics Workspace | `ltmsa-law` | Central log store, PerGB2018, 30-day retention |
| Data Collection Rule | `ltmsa-dcr` | Syslog (Warning+) + Perf Counter (60 sec) |
| Azure Monitor Agent | `AzureMonitorLinuxAgent` (auto-latest) | Extension installed on VM-1, VM-2 |
| DCR Association | `dcra-vm1`, `dcra-vm2` | VM ↔ DCR binding |

**Collection tables:**

| KQL table | Data source | First data arrival |
|-----------|------------|-------------------|
| `Heartbeat` | AMA | ~5 min after install |
| `Perf` | DCR performanceCounters | ~10 min after install |
| `Syslog` | DCR syslog | On event occurrence |
| `AzureMetrics` | LB Diagnostic Settings | Requires separate setup (see below) |

---

#### 7.1.1 AMA Internal Data Flow — Perf Collection Path

Since AMA v1.29, Perf collection on Linux VMs uses a **telegraf → mdsd** two-stage pipeline.  
Understanding this structure lets you quickly pinpoint where data gets blocked when issues occur.

```
[DCR] performanceCounters config (Windows-format counter names)
  ↓  amacoreagent auto-generates telegraf.d/*.conf (only on DCR change)
[telegraf] collects inputs.cpu / inputs.mem / inputs.diskio
  ↓  processors.rename
[measurement: Azure.VM.Linux.GuestMetrics]  ← name auto-generated by AMA
  ↓  outputs.socket_writer → passes namepass filter
[mdsd influx socket]  /run/azuremonitoragent/default_influx.socket
  ↓  mdsd built-in routing (LINUX_PERF_BLOB stream)
[ODS uploader]  HTTPS → ods.opinsights.azure.com
  ↓
[LA Perf table]
```

**AMA key processes:**

| Process | Role |
|---------|------|
| `mdsd` | Collects/uploads Heartbeat, Syslog, Perf. Sends to LA via ODS (HTTPS) |
| `telegraf` | Collects CPU/memory/disk metrics → delivers to mdsd influx socket |
| `agentlauncher` + `fluent-bit` | Syslog collection (rsyslog → fluent socket) |
| `amacoreagent` | Downloads DCR config and manages telegraf.d files |
| `MetricsExtension` | Handles Azure Monitor Metrics pipeline separately (unrelated to LA Perf) |

> **DCR counter format — Windows format is used even on Linux VMs**  
> Windows-format names like `\Processor(_Total)\% Processor Time` are the DCR API standard.  
> Even on Linux VMs, the same format is required. AMA internally maps to Linux metrics.  
> This design allows a single DCR to deploy across mixed Linux/Windows environments.

> **⚠️ telegraf.d files — never edit manually**  
> `.conf` files in `telegraf.d/` are **automatically managed by amacoreagent**.  
> Manual edits will break Perf data, and re-applying the DCR via `az rest` will not regenerate  
> files that already exist (regeneration only occurs when the DCR **changes**).  
> Reinstalling AMA is the most reliable fix when problems occur.

> **⚠️ telegraf.d backup — required immediately after AMA installation**  
> Once amacoreagent generates the telegraf.d files for the first time, back them up immediately.  
> If a manual edit becomes unavoidable, you can compare against the originals.

---

### 7.2 Setup Commands

#### Step 1: Create Log Analytics Workspace

```bash
az monitor log-analytics workspace create \
  --resource-group ltmsa-security-rg \
  --workspace-name ltmsa-law \
  --location koreacentral \
  --sku PerGB2018 --retention-time 30 \
  --tags Environment=dev Project=LTM-SA-Workshop

# Verify Workspace ID (used in DCR configuration)
az monitor log-analytics workspace show \
  --resource-group ltmsa-security-rg --workspace-name ltmsa-law \
  --query "{customerId:customerId,id:id}" -o json
```

#### Step 2: Assign Managed Identity + Install Azure Monitor Agent (VM-1, VM-2)

> **Required**: AMA authenticates to the workspace using the VM's System-Assigned Managed Identity.  
> Installing AMA without a Managed Identity will succeed but data will not be transmitted.  
> Always follow the order: assign MI → then install AMA.

```bash
# 2a. Assign System-Assigned Managed Identity
for vm in ltmsa-demo-vm ltmsa-demo-vm-2; do
  az vm identity assign \
    --resource-group ltmsa-security-rg \
    --name $vm \
    --query "{vm:name, principalId:systemAssignedIdentity}" -o json
done

# 2b. Install AMA (no pinned version — latest auto-install recommended)
for vm in ltmsa-demo-vm ltmsa-demo-vm-2; do
  az vm extension set \
    --resource-group ltmsa-security-rg \
    --vm-name $vm \
    --name AzureMonitorLinuxAgent \
    --publisher Microsoft.Azure.Monitor \
    --enable-auto-upgrade true --no-wait \
  && echo "$vm: AMA install dispatched"
done

# 2c. Verify installation complete (after 1–3 min — should show Succeeded)
for vm in ltmsa-demo-vm ltmsa-demo-vm-2; do
  az vm extension show \
    --resource-group ltmsa-security-rg --vm-name $vm \
    --name AzureMonitorLinuxAgent \
    --query "{vm:name,state:provisioningState,version:typeHandlerVersion}" -o json
done
```

> **Version pinning note**: Using `--version 1.xx` disables automatic patch updates.  
> If you must pin a version, check the [latest release](https://learn.microsoft.com/azure/azure-monitor/agents/azure-monitor-agent-extension-versions) first.

#### Step 3: Create DCR + Associate VMs (recommended: `az rest` method)

```bash
SUB_ID=$(az account show --query id -o tsv)
LAW_ID=$(az monitor log-analytics workspace show \
  --resource-group ltmsa-security-rg --workspace-name ltmsa-law \
  --query id -o tsv)

# Create DCR (via JSON file)
# Note: counter format uses Windows format (same for Linux VMs)
# Note: in bash heredoc, JSON backslashes are \\\\ (4) → file has \\ (2) → JSON string value \ (1)
cat > /tmp/ltmsa-dcr.json << EOF
{
  "location": "koreacentral",
  "properties": {
    "destinations": {
      "logAnalytics": [{"name": "law-dest", "workspaceResourceId": "$LAW_ID"}]
    },
    "dataFlows": [
      {"streams": ["Microsoft-Syslog","Microsoft-Perf"], "destinations": ["law-dest"]}
    ],
    "dataSources": {
      "syslog": [{
        "name": "syslog-all", "streams": ["Microsoft-Syslog"],
        "facilityNames": ["kern","user","auth","syslog","daemon"],
        "logLevels": ["Warning","Error","Critical","Alert","Emergency"]
      }],
      "performanceCounters": [{
        "name": "perf-basic", "streams": ["Microsoft-Perf"],
        "samplingFrequencyInSeconds": 60,
        "counterSpecifiers": [
          "\\\\Processor(_Total)\\\\% Processor Time",
          "\\\\Memory\\\\Available MBytes",
          "\\\\LogicalDisk(_Total)\\\\Disk Read Bytes/sec",
          "\\\\Network Interface(*)\\\\Bytes Total/sec"
        ]
      }]
    }
  }
}
EOF

az rest --method PUT \
  --url "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/ltmsa-security-rg/providers/Microsoft.Insights/dataCollectionRules/ltmsa-dcr?api-version=2022-06-01" \
  --body @/tmp/ltmsa-dcr.json

# Associate DCR ↔ VMs
DCR_ID="/subscriptions/${SUB_ID}/resourceGroups/ltmsa-security-rg/providers/Microsoft.Insights/dataCollectionRules/ltmsa-dcr"
for vm in ltmsa-demo-vm ltmsa-demo-vm-2; do
  VM_ID=$(az vm show --resource-group ltmsa-security-rg --name $vm --query id -o tsv)
  # Determine association name from VM name (explicit branch instead of sed)
  if [[ "$vm" == *"-2" ]]; then ASSOC="dcra-vm2"; else ASSOC="dcra-vm1"; fi
  az rest --method PUT \
    --url "https://management.azure.com${VM_ID}/providers/Microsoft.Insights/dataCollectionRuleAssociations/${ASSOC}?api-version=2022-06-01" \
    --body "{\"properties\":{\"dataCollectionRuleId\":\"${DCR_ID}\"}}"
  echo "$vm → $ASSOC association complete"
done
```

> **Do not use `az monitor data-collection rule association create`**:  
> This command has a CLI bug that produces a `MissingSubscription` error.  
> `az rest --method PUT` is stable and works without CLI extensions.

#### Step 3-b: Back up telegraf.d source files (wait 5 min after DCR association)

> It takes ~5 min for amacoreagent to read the DCR and generate telegraf.d files.  
> Backing up immediately after generation gives you a reference for AMA diagnostics and recovery.

```bash
# Confirm telegraf.d files have been generated (5 min after Step 3 completes)
az vm run-command invoke \
  --resource-group ltmsa-security-rg --name ltmsa-demo-vm \
  --command-id RunShellScript \
  --scripts "ls /var/lib/waagent/Microsoft.Azure.Monitor.AzureMonitorLinuxAgent-*/config/telegraf_configs/telegraf.d/"

# Backup — run on VM-1 and VM-2 separately
for vm in ltmsa-demo-vm ltmsa-demo-vm-2; do
  az vm run-command invoke \
    --resource-group ltmsa-security-rg --name $vm \
    --command-id RunShellScript \
    --scripts "cp -r /var/lib/waagent/Microsoft.Azure.Monitor.AzureMonitorLinuxAgent-*/config/telegraf_configs/telegraf.d/ /tmp/telegraf.d.orig-backup/ && echo 'backup done'"
done
```

> **⚠️ Run this step 5 minutes after Step 3 completes.**  
> If telegraf.d files are not visible, the DCR Association was not applied correctly.  
> Verify association state with `az rest --method GET` or re-run Step 3.

---

#### Step 4: Verify Data Arrival (10–15 min after installation)

```bash
# Verify Heartbeat arrival (after 5 min)
az monitor log-analytics query \
  --workspace $(az monitor log-analytics workspace show \
    --resource-group ltmsa-security-rg --workspace-name ltmsa-law \
    --query customerId -o tsv) \
  --analytics-query "Heartbeat | where TimeGenerated > ago(30m) | summarize count() by Computer" \
  -o table

# Verify Perf arrival (after 10–15 min)
az monitor log-analytics query \
  --workspace $(az monitor log-analytics workspace show \
    --resource-group ltmsa-security-rg --workspace-name ltmsa-law \
    --query customerId -o tsv) \
  --analytics-query "Perf | where TimeGenerated > ago(30m) | summarize count() by Computer, CounterName" \
  -o table
```

#### (Optional) LB Diagnostic Settings → AzureMetrics table

```bash
LB_ID=$(az network lb show --name ltmsa-lb --resource-group ltmsa-security-rg --query id -o tsv)
LAW_ID=$(az monitor log-analytics workspace show \
  --resource-group ltmsa-security-rg --workspace-name ltmsa-law \
  --query id -o tsv)
az monitor diagnostic-settings create \
  --name "lb-to-law" --resource "$LB_ID" --workspace "$LAW_ID" \
  --metrics '[{"category":"AllMetrics","enabled":true}]'
```

> LB is an Azure PaaS service with no OS. LB metrics are collected via Azure Resource Diagnostics (not AMA)  
> into the `AzureMetrics` table. Without this setting, Group E KQL queries return empty results.

---

### 7.3 KQL Query Practice

> **Portal**: Log Analytics workspace `ltmsa-law` → **Logs**  
> **CLI**: `az monitor log-analytics query --workspace <customerId> --analytics-query "..."`  
> **Wait times**: Heartbeat arrives ~5 min after AMA install; Perf arrives ~10–15 min after.

---

#### Group A: Basic Availability (AMA required)

```kusto
// A-0. Verify data arrival by table — run this first
union withsource=TableName Heartbeat, Perf, Syslog
| where TimeGenerated > ago(1h)
| summarize RowCount=count() by TableName
| order by TableName asc

// A-1. VM Heartbeat — agent connectivity status
Heartbeat
| where TimeGenerated > ago(1h)
| summarize LastHeartbeat=max(TimeGenerated) by Computer
| order by LastHeartbeat desc

// A-2. Multi-VM availability dashboard — 5 min gap = OFFLINE
let threshold = 5m;
Heartbeat
| where TimeGenerated > ago(1h)
| summarize LastBeat=max(TimeGenerated) by Computer, ResourceGroup
| extend Status=iff(LastBeat < ago(threshold), "OFFLINE", "ONLINE")
| extend MinutesSinceLastBeat=datetime_diff("minute", now(), LastBeat)
| project Computer, Status, LastBeat, MinutesSinceLastBeat
| order by Status asc, MinutesSinceLastBeat desc
```

---

#### Group B: Performance Metrics (AMA + DCR required)

```kusto
// B-1. CPU utilization trend (5 min aggregation)
Perf
| where TimeGenerated > ago(1h)
| where ObjectName == "Processor" and CounterName == "% Processor Time"
| where InstanceName == "_Total"
| summarize AvgCPU=avg(CounterValue) by bin(TimeGenerated, 5m), Computer
| render timechart

// B-2. CPU percentile distribution (P50/P95/P99)
Perf
| where TimeGenerated > ago(24h)
| where ObjectName == "Processor" and CounterName == "% Processor Time"
| where InstanceName == "_Total"
| summarize
    P50=percentile(CounterValue, 50),
    P95=percentile(CounterValue, 95),
    P99=percentile(CounterValue, 99),
    MaxCPU=max(CounterValue)
  by Computer
| extend Skew=round(P95 - P50, 1)
| order by P95 desc

// B-3. Available memory (AMA reports Available MBytes)
Perf
| where TimeGenerated > ago(30m)
| where ObjectName == "Memory" and CounterName == "Available MBytes"
| summarize AvgMemMB=avg(CounterValue) by Computer
| extend AvgMemGB=round(AvgMemMB / 1024, 2)
| project Computer, AvgMemGB

// B-4. Network throughput trend
Perf
| where TimeGenerated > ago(1h)
| where ObjectName == "Network Interface" and CounterName == "Bytes Total/sec"
| summarize AvgBps=avg(CounterValue) by bin(TimeGenerated, 5m), Computer
| extend AvgMbps=round(AvgBps * 8 / 1000000, 2)
| project TimeGenerated, Computer, AvgMbps
| render timechart
```

---

#### Group C: Security / Anomaly Detection

```kusto
// C-1. Linux authentication failures (Syslog)
Syslog
| where TimeGenerated > ago(24h)
| where Facility in ("auth", "authpriv")
| where SyslogMessage has "Failed password"
    or SyslogMessage has "authentication failure"
    or SyslogMessage has "Invalid user"
| summarize FailureCount=count() by HostName, SyslogMessage
| where FailureCount > 3
| order by FailureCount desc

// C-2. VM restart/shutdown event detection — Heartbeat gap-based
Heartbeat
| where TimeGenerated > ago(24h)
| order by Computer asc, TimeGenerated asc
| serialize
| extend PrevBeat=prev(TimeGenerated, 1)
| extend GapMinutes=datetime_diff("minute", TimeGenerated, PrevBeat)
| where GapMinutes > 10
| project TimeGenerated, Computer, GapMinutes, LastSeenBefore=PrevBeat
| order by GapMinutes desc
```

---

#### Group D: CPU + Heartbeat Cross-Analysis (Advanced)

```kusto
// D-1. App overload vs VM down — differentiation
// High CPU + Heartbeat normal → app overload (VM alive)
// No Heartbeat → VM down
let cpu_spikes =
    Perf
    | where TimeGenerated > ago(1h)
    | where ObjectName == "Processor" and CounterName == "% Processor Time"
    | where InstanceName == "_Total" and CounterValue > 80
    | summarize SpikeCount=count(), MaxCPU=max(CounterValue)
      by bin(TimeGenerated, 5m), Computer;
let heartbeats =
    Heartbeat
    | where TimeGenerated > ago(1h)
    | summarize BeatCount=count() by bin(TimeGenerated, 5m), Computer;
cpu_spikes
| join kind=leftouter heartbeats on TimeGenerated, Computer
| extend VMStatus=iff(isempty(BeatCount) or BeatCount == 0, "NO_HEARTBEAT", "ALIVE")
| extend Diagnosis=case(
    VMStatus == "NO_HEARTBEAT",              "VM DOWN — check Azure portal",
    SpikeCount > 0 and VMStatus == "ALIVE",  "APP OVERLOAD — VM healthy, CPU high",
    "Normal")
| project TimeGenerated, Computer, MaxCPU, SpikeCount, VMStatus, Diagnosis
| order by TimeGenerated desc

// D-2. Pre/post-deploy CPU comparison (update deploy time as needed)
let deploy_time = datetime(2026-06-13 12:05:00);  // replace with actual Step 5 completion time
let before =
    Perf
    | where TimeGenerated between ((deploy_time - 30m) .. deploy_time)
    | where ObjectName == "Processor" and CounterName == "% Processor Time"
    | where InstanceName == "_Total"
    | summarize AvgCPU_Before=avg(CounterValue) by Computer;
let after =
    Perf
    | where TimeGenerated between (deploy_time .. (deploy_time + 30m))
    | where ObjectName == "Processor" and CounterName == "% Processor Time"
    | where InstanceName == "_Total"
    | summarize AvgCPU_After=avg(CounterValue) by Computer;
before
| join kind=inner after on Computer
| extend Delta=round(AvgCPU_After - AvgCPU_Before, 1)
| extend Impact=case(
    Delta > 10,  "CPU INCREASE — possible regression",
    Delta < -10, "CPU DECREASE — possible improvement",
    "STABLE")
| project Computer, AvgCPU_Before=round(AvgCPU_Before,1), AvgCPU_After=round(AvgCPU_After,1), Delta, Impact
```

---

#### Group E: LB Health (LB Diagnostic Settings required)

```kusto
// E-1. LB Frontend availability — 0=degraded, 100=healthy
// Note: use ResourceProvider column (not ResourceType — causes SemanticError)
AzureMetrics
| where TimeGenerated > ago(1h)
| where ResourceProvider == "MICROSOFT.NETWORK/LOADBALANCERS"
| where MetricName == "VipAvailability"
| summarize AvgAvail=avg(Average), MinAvail=min(Minimum)
  by bin(TimeGenerated, 1m), Resource
| extend Status=iff(MinAvail < 100, "DEGRADED", "OK")
| project TimeGenerated, Resource, AvgAvail, MinAvail, Status
| order by TimeGenerated desc

// E-2. LB backend health probe result per VM
AzureMetrics
| where TimeGenerated > ago(1h)
| where ResourceProvider == "MICROSOFT.NETWORK/LOADBALANCERS"
| where MetricName == "DipAvailability"
| summarize AvgAvail=avg(Average), MinAvail=min(Minimum)
  by bin(TimeGenerated, 1m), Resource
| extend BackendStatus=iff(MinAvail < 100, "PROBE_FAIL", "HEALTHY")
| project TimeGenerated, Resource, MinAvail, BackendStatus
| order by TimeGenerated desc

// E-3. Extract health degradation windows (with duration)
AzureMetrics
| where TimeGenerated > ago(24h)
| where ResourceProvider == "MICROSOFT.NETWORK/LOADBALANCERS"
| where MetricName == "DipAvailability" and Average < 100
| summarize
    DegradedStart=min(TimeGenerated),
    DegradedEnd=max(TimeGenerated),
    MinAvail=min(Average),
    EventCount=count()
  by Resource
| extend DurationMin=datetime_diff("minute", DegradedEnd, DegradedStart)
| project Resource, DegradedStart, DegradedEnd, DurationMin, MinAvail, EventCount
| order by DegradedStart desc
```

---

### 7.4 AMA Diagnostics Guide

Step-by-step in-VM checks when Perf data is not arriving in LA.  
All commands can be run without SSH via `az vm run-command invoke`.

#### Diagnostic 1: Check AMA process status

```bash
az vm run-command invoke \
  --resource-group ltmsa-security-rg --name ltmsa-demo-vm \
  --command-id RunShellScript \
  --scripts "systemctl status azuremonitoragent --no-pager; echo ---; ps aux | grep -E 'mdsd|telegraf|amacoreagent|fluent' | grep -v grep"
```

Expected: `active (running)`, all of mdsd/telegraf/amacoreagent processes present

#### Diagnostic 2: Check telegraf.d configuration files

```bash
az vm run-command invoke \
  --resource-group ltmsa-security-rg --name ltmsa-demo-vm \
  --command-id RunShellScript \
  --scripts "ls -la /var/lib/waagent/Microsoft.Azure.Monitor.AzureMonitorLinuxAgent-*/config/telegraf_configs/telegraf.d/; echo ---; grep -h 'dest = ' /var/lib/waagent/Microsoft.Azure.Monitor.AzureMonitorLinuxAgent-*/config/telegraf_configs/telegraf.d/*.conf"
```

Expected:
- 3 files present: `processor-dcr-*.conf`, `filesystem-dcr-*.conf`, `memory-dcr-*.conf`
- First `dest =` value in each file must be `"Azure.VM.Linux.GuestMetrics"`

> **If telegraf.d files are empty or missing**: Reinstalling AMA is the most reliable fix.  
> Re-applying the DCR (`az rest --method PUT`) will not regenerate files that already exist.  
> Manually deleting files will not cause amacoreagent to auto-regenerate them.

#### Diagnostic 3: Check telegraf log for errors

```bash
az vm run-command invoke \
  --resource-group ltmsa-security-rg --name ltmsa-demo-vm \
  --command-id RunShellScript \
  --scripts "tail -50 /var/log/azure/Microsoft.Azure.Monitor.AzureMonitorLinuxAgent/telegraf.log | grep -E 'Error|error|broken pipe|connect'"
```

- `broken pipe` errors: socket disconnected due to mdsd restart; telegraf auto-reconnects.  
  If persists > 5 min, restart AMA and wait 10 min.
- **No errors + no Perf**: telegraf is connected to the socket but not sending data.  
  Verify telegraf.d files are correct (Diagnostic 2). If unresolved, reinstall AMA.

#### Diagnostic 4: Verify Perf transmission via mdsd QoS log

```bash
az vm run-command invoke \
  --resource-group ltmsa-security-rg --name ltmsa-demo-vm \
  --command-id RunShellScript \
  --scripts "grep 'LINUX_PERF_BLOB' /var/opt/microsoft/azuremonitoragent/log/mdsd.qos | tail -5"
```

Expected: `MaODSRequest,...LINUX_PERF_BLOB,15,15,...` — TotalCount=15, SuccessCount=15  
If absent or SuccessCount=0, mdsd is not receiving Perf data from the influx socket → re-check Diagnostic 2.

#### AMA Restart Procedure (when Perf is interrupted)

A full AMA restart also restarts telegraf.  
If telegraf tries to connect before the mdsd socket is ready, a brief broken pipe occurs,  
but **automatic recovery happens within 5–10 minutes.** Restarting immediately again complicates the situation.

```bash
az vm run-command invoke \
  --resource-group ltmsa-security-rg --name ltmsa-demo-vm \
  --command-id RunShellScript \
  --scripts "systemctl restart azuremonitoragent; sleep 30; systemctl status azuremonitoragent --no-pager | head -5"
```

Wait 10 min after restart → re-run Diagnostic 4 (mdsd QoS) to confirm LINUX_PERF_BLOB entries.

> **If Perf is still not working — reinstall AMA**  
> Fastest fix when telegraf.d has been manually edited or the cause is unknown.
> ```bash
> # Remove and reinstall AMA (Managed Identity is retained)
> az vm extension delete --resource-group ltmsa-security-rg --vm-name ltmsa-demo-vm \
>   --name AzureMonitorLinuxAgent --yes
> az vm extension set --resource-group ltmsa-security-rg --vm-name ltmsa-demo-vm \
>   --name AzureMonitorLinuxAgent --publisher Microsoft.Azure.Monitor \
>   --enable-auto-upgrade true
> # → amacoreagent re-downloads DCR config and correctly regenerates telegraf.d
> ```

---

### 7.5 Troubleshooting

| Symptom | Cause | Resolution |
|---------|-------|------------|
| `Heartbeat` table empty | AMA just installed — still connecting | Wait 5–10 min and retry |
| `Heartbeat` absent 15+ min | **Managed Identity not assigned** — AMA cannot authenticate to workspace | `az vm identity assign` then reinstall AMA (see Step 2) |
| `Perf` table empty (right after install) | DCR association not complete or AMA still installing | Verify `az vm extension show` shows Succeeded, then wait 10 min |
| `Perf` interrupted after AMA restart | mdsd socket regeneration causes telegraf broken pipe | Self-recovers. Wait 5–10 min. If persists, check Diagnostics 3→4 |
| `broken pipe` repeated in telegraf log | telegraf cannot reconnect to mdsd socket | `systemctl restart azuremonitoragent` then wait 10 min |
| `LINUX_PERF_BLOB` absent in mdsd QoS | telegraf.d files missing or empty, or AMA recently restarted | Check telegraf.d files via Diagnostic 2. If missing, reinstall AMA |
| No telegraf errors + no Perf | telegraf connected to socket but not sending (telegraf.d issue) | Check telegraf.d file content → reinstall AMA |
| Perf stops after manual telegraf.d edit | Manual edit diverges from AMA's expected config | Reinstall AMA to reset telegraf.d (DCR re-apply alone does not regenerate) |
| telegraf.d files empty | amacoreagent does not regenerate (AMA restarted without DCR change) | Reinstall AMA |
| `Syslog` empty | No Warning+ events have occurred | Normal — generate a test event with `logger -p kern.warning "test"` |
| `AzureMetrics` LB results empty | LB Diagnostic Settings not configured | Run `(Optional) LB Diagnostic Settings` step in 7.2 |
| DCR association `MissingSubscription` | CLI bug in `az monitor data-collection rule association create` | Use `az rest --method PUT` method (see Step 3) |
| `SemanticError: ResourceType` (Group E) | `ResourceType` used in KQL — column does not exist in AzureMetrics | Use `ResourceProvider == "MICROSOFT.NETWORK/LOADBALANCERS"` |

---

## 8. Security Artifacts (Run after E2E passes — while infrastructure is live)

> **When to run**: After E2E Test Passed + Section 7 Log Analytics collection confirmed  
> **Purpose**: Assess the security posture of the deployed infrastructure and identify action items.  
> **Prerequisite**: All resources in `ltmsa-security-rg` (VM-1, VM-2, Jumpbox, Bastion, LB, NSG) are running normally

```bash
# Common variables
RG="ltmsa-security-rg"
LOCATION="koreacentral"
SUB_ID=$(az account show --query id -o tsv)
```

---

### 8.1 Security Posture Assessment

> Quantifies current security posture based on Defender for Cloud Secure Score and recommendations.

#### Data Collection Commands

```bash
# ① Secure Score
az security secure-score show \
  --name "ascScore" \
  --query "{score:score.current, max:score.max, percentage:score.percentage}" \
  -o json

# ② Secure Score by control
az security secure-score-controls list \
  --query "[].{control:displayName, score:score.current, max:score.max, unhealthyCount:unhealthyResourceCount}" \
  -o table | sort -k4 -rn | head -15

# ③ Unhealthy recommendations — by severity
az security assessment list \
  --query "[?status.code=='Unhealthy'].{
    name:displayName,
    severity:metadata.severity,
    category:metadata.categories[0],
    targetResource:resourceDetails.id
  }" \
  -o table

# ④ Aggregate by severity
az security assessment list \
  --query "[?status.code=='Unhealthy'] | {
    High: [?metadata.severity=='High'] | length(@),
    Medium: [?metadata.severity=='Medium'] | length(@),
    Low: [?metadata.severity=='Low'] | length(@)
  }" \
  -o json
```

#### Security Posture Assessment Results (fill in after running)

| Item | Value | Target | Status |
|------|-------|--------|--------|
| Secure Score (current) | ___ / 100 | 75+ | ⬜ |
| Secure Score (max) | ___ / 100 | — | — |
| High unhealthy count | ___ | 0 | ⬜ |
| Medium unhealthy count | ___ | 5 or fewer | ⬜ |
| Low unhealthy count | ___ | — | ⬜ |

#### Top 5 Priority Actions (High Severity)

| Rank | Recommendation | Target Resource | Action |
|------|---------------|----------------|--------|
| 1 | | | |
| 2 | | | |
| 3 | | | |
| 4 | | | |
| 5 | | | |

---

### 8.2 Vulnerability Assessment

> Audits NSG rules, public IP exposure, Key Vault configuration, Managed Identity, and excessive RBAC permissions.

#### 8.2-1 NSG Rule Audit — Detect Internet-wide Allow Rules

```bash
# Detect inbound Allow rules open to 0.0.0.0/0
echo "=== web-nsg rules ==="
az network nsg rule list \
  --resource-group $RG --nsg-name ltmsa-web-nsg \
  --query "[?access=='Allow' && direction=='Inbound'].{
    name:name, priority:priority,
    source:sourceAddressPrefix, port:destinationPortRange
  }" -o table

echo "=== mgmt-nsg rules ==="
az network nsg rule list \
  --resource-group $RG --nsg-name ltmsa-mgmt-nsg \
  --query "[?access=='Allow' && direction=='Inbound'].{
    name:name, priority:priority,
    source:sourceAddressPrefix, port:destinationPortRange
  }" -o table

# Risky rules: source = * or 0.0.0.0/0 + port 22/3389 allowed
az network nsg rule list \
  --resource-group $RG --nsg-name ltmsa-web-nsg \
  --query "[?access=='Allow' && direction=='Inbound' && (sourceAddressPrefix=='*' || sourceAddressPrefix=='0.0.0.0/0') && (destinationPortRange=='22' || destinationPortRange=='3389' || destinationPortRange=='*')]" \
  -o table
echo "Empty result above = Zero Trust compliant"
```

#### NSG Audit Results

| NSG Name | Risky Rule Count | Internet→SSH/RDP Exposure | Status |
|----------|-----------------|--------------------------|--------|
| ltmsa-web-nsg | ___ | ☐ None / ☐ Present | ⬜ |
| ltmsa-mgmt-nsg | ___ | ☐ None / ☐ Present | ⬜ |

> **Expected**: `allow-bastion-ssh` (src: 10.0.0.0/26) + `allow-jumpbox-ssh` (src: 10.0.2.0/24) — no internet SSH ✅

#### 8.2-2 Public IP Exposure

```bash
# All public IPs in the resource group
az network public-ip list \
  --resource-group $RG \
  --query "[].{
    name:name, IP:ipAddress,
    SKU:sku.name,
    attachment:ipConfiguration.id
  }" -o table

# Public IP per VM
for vm in ltmsa-demo-vm ltmsa-demo-vm-2 ltmsa-jumpbox; do
  PUB=$(az vm show --resource-group $RG --name $vm \
    --show-details --query publicIps -o tsv 2>/dev/null || echo "none")
  echo "$vm: publicIP=$PUB"
done
```

#### Public IP Exposure Results

| Resource | Public IP | Purpose | Allowed |
|----------|----------|---------|---------|
| ltmsa-demo-vm (VM-1) | ___.___.___.___ | Diagnostic access (dev) | ⬜ By design |
| ltmsa-demo-vm-2 (VM-2) | none | LB-only access | ✅ |
| ltmsa-jumpbox | none | Bastion-only | ✅ |
| ltmsa-bastion-pip | ___.___.___.___ | Bastion (required) | ✅ |
| ltmsa-lb-pip | ___.___.___.___ | LB Frontend (required) | ✅ |

> **Recommendation**: VM-1 public IP is for diagnostic access during labs. Remove it in production and route all access via Bastion.

#### 8.2-3 Key Vault Configuration Audit

```bash
# Get KV name
KV_NAME=$(az keyvault list --resource-group $RG --query "[0].name" -o tsv 2>/dev/null)
if [ -z "$KV_NAME" ]; then
  echo "No Key Vault found in $RG — check Module 3 lab RG"
else
  echo "Key Vault: $KV_NAME"
  az keyvault show --name $KV_NAME \
    --query "{
      name:name,
      softDelete:properties.enableSoftDelete,
      softDeleteRetentionDays:properties.softDeleteRetentionInDays,
      purgeProtection:properties.enablePurgeProtection,
      rbacAuth:properties.enableRbacAuthorization,
      publicNetworkAccess:properties.publicNetworkAccess
    }" -o json
fi
```

#### Key Vault Configuration Results

| Item | Current Setting | Recommended | Status |
|------|----------------|-------------|--------|
| Soft Delete | ___ | `true` | ⬜ |
| Soft Delete retention | ___ days | 90 days (production) | ⬜ |
| Purge Protection | ___ | `true` (production) | ⬜ |
| RBAC Authorization | ___ | `true` | ⬜ |
| Public Network Access | ___ | `Disabled` (production) | ⬜ |

> **Lab environment exceptions**: Purge Protection = false and 7-day retention are acceptable for lab cleanup convenience.

#### 8.2-4 Managed Identity Status

```bash
# Check Managed Identity assignment per VM
az vm list --resource-group $RG \
  --query "[].{VM:name, ManagedIdentity:identity.type, PrincipalId:identity.principalId}" \
  -o table
```

#### MI Status Results

| VM Name | MI Type | principalId | Status |
|---------|---------|------------|--------|
| ltmsa-demo-vm | ___ | ___ | ⬜ |
| ltmsa-demo-vm-2 | ___ | ___ | ⬜ |
| ltmsa-jumpbox | ___ | ___ | ⬜ |

> **Expected**: VMs with AMA installed must have `SystemAssigned` MI. Without MI, AMA cannot transmit data.

#### 8.2-5 RBAC Excessive Permission Audit

```bash
# Subscription-level Owner list (verify least privilege)
echo "=== Subscription Owners ==="
az role assignment list \
  --scope "/subscriptions/$SUB_ID" \
  --query "[?roleDefinitionName=='Owner'].{principal:principalName, type:principalType, role:roleDefinitionName}" \
  -o table

# Subscription-level Contributor list
echo "=== Subscription Contributors ==="
az role assignment list \
  --scope "/subscriptions/$SUB_ID" \
  --query "[?roleDefinitionName=='Contributor'].{principal:principalName, type:principalType, role:roleDefinitionName}" \
  -o table

# All role assignments in lab RG
az role assignment list \
  --resource-group $RG \
  --query "[].{principal:principalName, type:principalType, role:roleDefinitionName}" \
  -o table
```

#### RBAC Audit Results

| Scope | Role | Principal | Type | Assessment |
|-------|------|-----------|------|------------|
| Subscription | Owner | ___ | User | ⬜ Minimize |
| Subscription | Contributor | github-actions-ltmsa | ServicePrincipal | ✅ Required for E2E (reduce to RG scope in production) |
| RG | Key Vault Secrets Officer | ___ | User | ✅ |
| RG | Key Vault Secrets User | ltmsa-demo-vm MI | ServicePrincipal | ✅ |

> **Recommendation**: Subscription-level Contributor for github-actions-ltmsa SP is required for E2E (RG delete/recreate).  
> For stable production pipelines, reduce scope to `resourceGroups/ltmsa-security-rg`.

---

### 8.3 Compliance Assessment

> Evaluates Azure Policy compliance rate, key CIS Azure Benchmark Controls, and Resource Lock / Tag compliance.

#### 8.3-1 Azure Policy Compliance Status

```bash
# Aggregate subscription-wide policy compliance
az policy state summarize \
  --query "results.{total:resourceDetails.count, compliant:resourceDetails.compliantCount, nonCompliant:resourceDetails.noncompliantCount}" \
  -o json

# NonCompliant resource list
az policy state list \
  --filter "complianceState eq 'NonCompliant'" \
  --query "[].{policy:policyDefinitionName, resource:resourceId, type:resourceType}" \
  -o table | head -20

# Policy state within ltmsa-security-rg scope
az policy state list \
  --resource-group $RG \
  --query "[?complianceState=='NonCompliant'].{
    policyName:policyDefinitionName,
    resource:resourceId,
    state:complianceState
  }" -o table
```

#### Policy Compliance Results

| Scope | Total Resources | Compliant | Non-Compliant | Rate |
|-------|----------------|-----------|---------------|------|
| Subscription | ___ | ___ | ___ | ___% |
| ltmsa-security-rg | ___ | ___ | ___ | ___% |

#### Key Non-Compliant Items

| Policy Name | Target Resource | Action |
|-------------|----------------|--------|
| | | |

#### 8.3-2 CIS Azure Benchmark v2.0 Key Controls Check

```bash
# Check CIS Benchmark compliance in Defender for Cloud
# (based on Regulatory Compliance dashboard)
az security regulatory-compliance-standards list \
  --query "[?id contains 'CIS'].{standard:displayName, complianceRate:percentageCompliance, passed:passedControls, failed:failedControls}" \
  -o table 2>/dev/null || echo "CIS Benchmark not assigned — check in portal"

# Manual CLI checks (key CIS Controls)
echo "--- CIS 1.1: Guest user accounts ---"
az ad user list --query "[?userType=='Guest'].{UPN:userPrincipalName}" -o table

echo "--- CIS 4.1: MFA enforcement (Conditional Access) ---"
az ad policy list 2>/dev/null | grep -i "mfa\|multi-factor" || echo "Check Conditional Access policies in portal"

echo "--- CIS 5.1: Activity Log diagnostic settings ---"
az monitor diagnostic-settings list \
  --resource "/subscriptions/$SUB_ID" \
  --query "[].{name:name, storage:storageAccountId, LAW:workspaceId}" -o table 2>/dev/null

echo "--- CIS 6.1: RDP internet exposure ---"
az network nsg list --resource-group $RG \
  --query "[].securityRules[?destinationPortRange=='3389' && access=='Allow' && (sourceAddressPrefix=='*' || sourceAddressPrefix=='0.0.0.0/0')].{NSG:name, rule:name}" \
  -o table

echo "--- CIS 6.2: SSH internet exposure ---"
az network nsg list --resource-group $RG \
  --query "[].securityRules[?destinationPortRange=='22' && access=='Allow' && (sourceAddressPrefix=='*' || sourceAddressPrefix=='0.0.0.0/0')].{NSG:name, rule:name}" \
  -o table
echo "Empty result = CIS 6.2 compliant"

echo "--- CIS 7.1: VM disk encryption ---"
az vm list --resource-group $RG \
  --query "[].{VM:name, OSDisk:storageProfile.osDisk.managedDisk.storageAccountType}" \
  -o table

echo "--- CIS 8.1: Key Vault Soft Delete ---"
az keyvault list --resource-group $RG \
  --query "[].{KV:name, SoftDelete:properties.enableSoftDelete, PurgeProtection:properties.enablePurgeProtection}" \
  -o table
```

#### CIS Azure Benchmark Key Controls Results

| CIS Control | Description | Result | Status |
|------------|-------------|--------|--------|
| 1.1 | Minimize guest users | ___ | ⬜ |
| 4.1 | MFA enforcement (Conditional Access) | ☐ Applied / ☐ Not applied | ⬜ |
| 5.1 | Activity Log → Storage/LAW integration | ☐ Configured / ☐ Not configured | ⬜ |
| 6.1 | No RDP internet exposure | ☐ None / ☐ Present | ⬜ |
| 6.2 | No SSH internet exposure | ☐ None / ☐ Present | ⬜ |
| 7.1 | VM disk — StandardSSD or better | ___ | ⬜ |
| 8.1 | Key Vault Soft Delete enabled | ☐ Enabled / ☐ Disabled | ⬜ |

#### 8.3-3 Resource Lock Status

```bash
# All locks in subscription
az lock list --query "[].{name:name, type:level, scope:id, notes:notes}" -o table

# Locks within ltmsa-security-rg
az lock list --resource-group $RG \
  --query "[].{name:name, type:level}" -o table
```

#### Resource Lock Results

| Scope | Lock Name | Type | Assessment |
|-------|----------|------|------------|
| Subscription | ___ | ___ | ⬜ |
| ltmsa-security-rg | ___ | ___ | ⬜ |

> **Recommendation**: Apply `CanNotDelete` lock on critical infrastructure RGs.  
> Locks must be removed before E2E runs — the workflow removes them automatically (see `cleanup` job).

#### 8.3-4 Tag Compliance Check

```bash
# Required tags: Environment, Project, Owner, CostCenter
REQUIRED_TAGS='["Environment","Project","Owner"]'

# Tag status of resources in ltmsa-security-rg
az resource list --resource-group $RG \
  --query "[].{name:name, type:type, tags:tags}" -o json | \
  python3 -c "
import sys, json
resources = json.load(sys.stdin)
missing = []
for r in resources:
    tags = r.get('tags') or {}
    missing_tags = [t for t in ['Environment','Project','Owner'] if t not in tags]
    if missing_tags:
        missing.append({'resource': r['name'], 'type': r['type'].split('/')[-1], 'missingTags': ', '.join(missing_tags)})
if missing:
    print(f'Resources with missing tags: {len(missing)}')
    for m in missing: print(f'  - {m[\"resource\"]} ({m[\"type\"]}): {m[\"missingTags\"]}')
else:
    print('All resources comply with required tags')
"

# Check RG tags
az group show --name $RG --query "tags" -o json
```

#### Tag Compliance Results

| Scope | Total Resources | Missing Tags | Compliance Rate |
|-------|----------------|-------------|----------------|
| ltmsa-security-rg | ___ | ___ | ___% |

| Missing Tag Item | Target Resource | Action |
|-----------------|----------------|--------|
| ___ | ___ | `az resource tag --tags ...` |

---

### 8.4 Security Artifact Summary and Action Plan

> Complete the summary table below after finishing checks 8.1–8.3 to produce the final security report.

#### Overall Assessment Summary

| Assessment Area | Items | Pass | Fail | Priority |
|----------------|-------|------|------|----------|
| Security Posture (Secure Score) | — | ___pts | — | — |
| NSG Rule Audit | 2 NSGs | ___ | ___ | High |
| Public IP Exposure | 5 resources | ___ | ___ | Medium |
| Key Vault Config | 5 items | ___ | ___ | High |
| Managed Identity | 3 VMs | ___ | ___ | High |
| RBAC Permission Audit | ___ | ___ | ___ | Medium |
| Policy Compliance | ___ resources | ___ | ___ | Medium |
| CIS Benchmark | 7 Controls | ___ | ___ | High |
| Resource Lock | ___ | ___ | ___ | Low |
| Tag Compliance | ___ resources | ___ | ___ | Low |

#### Immediate Actions Required (High — must resolve before production)

| # | Item | Current State | Action Command | Owner |
|---|------|--------------|---------------|-------|
| 1 | VM-1 public IP → Bastion-only | Public IP present | `az network public-ip delete` + remove NSG rule | Infra team |
| 2 | SP subscription Contributor → RG-scoped | Subscription level | `az role assignment create --scope /RG/...` then remove subscription permission | Security team |
| 3 | Enable KV Purge Protection | false | `az keyvault update --enable-purge-protection true` | Security team |
| 4 | Verify Managed Identity on VMs without AMA | ___ | `az vm identity assign` + reinstall AMA | Ops team |

#### Near-term Improvements (Medium — next sprint)

| # | Item | Rationale | Expected Benefit |
|---|------|-----------|-----------------|
| 1 | Permanently enable Defender Standard Tier | CWPP runtime threat detection | Early detection of undetected attacks |
| 2 | Activity Log → Log Analytics integration | CIS 5.1 requirement | Full audit trail |
| 3 | Restrict KV access to Private Endpoint | Network isolation | Remove public-internet KV API exposure |
| 4 | Assign Availability Zones to all VMs | Eliminate single points of failure | Zone-failure resilience |

---

## 9. Manual Cleanup (After E2E + Security Assessment)

```bash
# Delete RG (15–25 min including Bastion)
az group delete --name ltmsa-security-rg --yes --no-wait

# Verify deletion
az group exists --name ltmsa-security-rg
```

---

## 10. Environment Variables Summary

| Variable | Value | Description |
|----------|-------|-------------|
| `AZURE_RG` | `ltmsa-security-rg` | Target Resource Group |
| `AZURE_LOCATION` | `koreacentral` | Deployment region |
| `HUB_VNET_NAME` | `ltmsa-hub-vnet` | Hub Virtual Network (10.0.0.0/16) |
| `SPOKE_VNET_NAME` | `ltmsa-spoke-vnet` | Spoke Virtual Network (10.1.0.0/16) |
| `BASTION_NAME` | `ltmsa-bastion` | Azure Bastion (Hub VNet) |
| `BASTION_PREFIX` | `10.0.0.0/26` | AzureBastionSubnet in Hub VNet (minimum /26) |
| `MGMT_SUBNET` | `mgmt-snet` | Jumpbox subnet (Hub VNet) |
| `MGMT_PREFIX` | `10.0.1.0/24` | Hub VNet mgmt-snet |
| `WEB_SUBNET` | `web-snet` | App VM subnet (Spoke VNet) |
| `WEB_PREFIX` | `10.1.1.0/24` | Spoke VNet web-snet |
| `VM_SIZE` | `Standard_D2s_v3` | VM-1, VM-2 size |
| `JUMPBOX_SIZE` | `Standard_D2s_v3` | Jumpbox size |
| `VM_IMAGE_URN` | `Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest` | Ubuntu 22.04 LTS |
| `APP_DIR` | `/opt/ltm-workshop` | App deployment path |
| `APP_PORT` | `3000` | Node.js app port |

---

*LTM Korea Azure SA Workshop*  
*Workflow: `.github/workflows/e2e-test.yml` | Date: 2026-06-13*
