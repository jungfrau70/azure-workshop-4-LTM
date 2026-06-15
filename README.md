# Azure Solution Architect Workshop for LTM Korea

> An **8-module hands-on workshop** for building an enterprise Azure Landing Zone from scratch.  
> Modules progress from Governance -> Network -> Security -> HA -> Observability -> FinOps -> IaC/CI-CD -> Security Artifacts, implementing the design decisions that come up in real SA workshops.

---

## Workshop Architecture

```
+----------------------------------------------------------+
|          LTM Korea -- Azure Landing Zone                 |
+----------------------------------------------------------+
| [Pre-work]  Management Group + Korea Region Policy       |
| [Module 1]  Governance    -- RBAC / Policy / Lock        |
| [Module 2]  Network       -- Hub-Spoke / NSG / Bastion   |
| [Module 3]  Security      -- Managed Identity / Key Vault|
| [Module 4]  Resiliency    -- AZ / Standard LB / Backup   |
| [Module 5]  Observability -- Log Analytics / KQL / Alerts|
| [Module 6]  FinOps        -- Tags / Budget / Advisor     |
| [Module 7]  IaC & CI/CD   -- Bicep / GitHub Actions      |
| [Module 8]  Security Artifacts -- Secure Score / CIS     |
+----------------------------------------------------------+
```

**Target resource group**: `ltmsa-security-rg` (Korea Central)

---

## Module Summary

| # | Module | Key Technologies | Learning Objective |
|---|--------|------------------|--------------------|
| Pre | Management Group | Azure Policy (Deny) | Governance control above subscription boundary |
| 1 | Governance | RBAC / Policy / Lock | Least privilege + resource protection |
| 2 | Network | Hub-Spoke / NSG / Peering | 3-tier network isolation design |
| 3 | Security | Managed Identity / Key Vault | Zero Trust app with no secrets in code |
| 4 | Resiliency | AZ / Standard LB / Backup | RTO/RPO requirements design |
| 5 | Observability | Log Analytics / KQL / Alert | Proactive failure detection automation |
| 6 | FinOps | Tag / Budget Alert / Advisor | Cost visibility + Chargeback/Showback |
| 7 | IaC & CI/CD | Bicep / GitHub Actions | Drift prevention + zero-downtime deployment |
| 8 | Security Artifacts | Defender for Cloud / CIS | Quantified security posture report |

---

## Repository Structure

```
azure-workshop-4-LTM/
+-- Workshop_Complete_Guide.md   # Step-by-step lab guide (main document)
+-- Scenario.md                  # Module scenarios, design rationale, architecture points
+-- COMMANDS.md                  # Quick-reference az CLI commands per module
+-- E2E_Test.md                  # E2E test procedure + security artifact templates
+-- LogAnalytics.md              # Log Analytics / AMA reference notes
+-- MDC.md                       # Microsoft Defender for Cloud reference notes
+-- bicep/
|   +-- lb-vm2.bicep             # Standard LB + VM-2 (zone-redundant, Module 7)
+-- github-actions-azure/        # GitHub Actions repo (separate git)
    +-- .github/workflows/
    |   +-- e2e-test.yml         # 4-job CI/CD pipeline
    +-- bicep/
    |   +-- lb-vm2.bicep         # LB+VM-2 Bicep (used by e2e-test.yml)
    +-- src/
        +-- app.js               # Node.js workshop app (health / /api/modules)
```

---

## Quick Start

### Prerequisites

- Azure subscription (Owner role)
- Azure CLI 2.50+, Bicep CLI
- GitHub account with Actions enabled
- Node.js 18+ (for local testing)

### Environment Variables

```bash
export RG="ltmsa-security-rg"
export LOCATION="koreacentral"
export PREFIX="ltmsa"
export ADMIN_USERNAME="azureuser"
export APP_PORT=3000
```

### Lab Sequence

1. **[Workshop_Complete_Guide.md](Workshop_Complete_Guide.md)** -- Follow the module-by-module lab exercises
2. **[Scenario.md](Scenario.md)** -- Understand the design rationale behind each module
3. **[COMMANDS.md](COMMANDS.md)** -- Quick-copy az CLI commands per module
4. **[E2E_Test.md](E2E_Test.md)** -- Full E2E validation + generate security artifacts

---

## Module 7 -- GitHub Actions CI/CD Pipeline

E2E testing runs via GitHub Actions in the `github-actions-azure` repository.

```
[git push] -> CI(test/lint) -> deploy-infra(Bicep LB+VM-2) -> deploy-app(VM-1 / VM-2) -> verify-lb
```

### GitHub Secrets Required

| Secret | Description |
|--------|-------------|
| `AZURE_CREDENTIALS` | Full output of `az ad sp create-for-rbac --sdk-auth` |
| `ADMIN_PASSWORD` | VM-2 admin password |

### Manual Workflow Trigger

```bash
gh workflow run e2e-test.yml \
  --repo <your-org>/github-actions-azure \
  -f confirm_destroy=DESTROY \
  -f environment=dev
```

### Pipeline Architecture (4 Jobs)

```
[git push master]
      -> [Job 1: CI]           -> npm test + node --check (syntax only)
      -> [Job 2: deploy-infra] -> Bicep what-if -> create (LB + VM-2 zone-redundant)
                                  Add VM-1 NIC to LB backend pool
[Job 3: deploy-app]            -> Parallel matrix: VM-1 / VM-2
                                  az vm run-command (no SSH -- Azure Management Plane)
                                  pm2 restart + health check (retry 6x)
      -> [Job 4: verify-lb]    -> curl http://<LB_IP>/health / /api/modules
```

> **Key design**: `az vm run-command` replaces SSH -- commands are delivered via the Azure Management Plane.
> No inbound port 22 required; NSG blocks internet SSH entirely (Zero Trust).

---

## Module 8 -- Security Artifacts (Post-E2E)

Once all infrastructure is deployed and E2E passes, Defender for Cloud has real resources to scan and generates meaningful security scores.

```bash
# Secure Score
az security secure-score show --name "ascScore" \
  --query "{current:score.current, max:score.max, percentage:score.percentage}" -o json

# Detect risky NSG rules (internet -> SSH allow-all)
az network nsg rule list --resource-group $RG --nsg-name ltmsa-web-nsg \
  --query "[?access=='Allow' && direction=='Inbound' && sourceAddressPrefix=='*' && destinationPortRange=='22'].name" -o tsv

# CIS Benchmark -- non-compliant policy states
az policy state list --resource-group $RG \
  --filter "complianceState eq 'NonCompliant'" \
  --query "length(@)" -o tsv
```

Three artifact types generated:
- **Security Posture Assessment** -- Secure Score, unhealthy recommendations, top-5 action items
- **Vulnerability Assessment** -- NSG risk rules, public IP exposure, Key Vault config, RBAC audit
- **Compliance Assessment** -- Policy compliance rate, CIS Azure Benchmark v2.0 controls, tag coverage

Full commands and report templates: **[E2E_Test.md -- Section 8](E2E_Test.md)**

---

## Core Design Principles

| Principle | Implementation |
|-----------|----------------|
| **Zero Trust** | Managed Identity eliminates secrets in code; NSG blocks internet SSH |
| **Defense in Depth** | Bastion -> Jumpbox -> Break-glass three-layer admin access |
| **Least Privilege** | RBAC Reader/Contributor role separation; SP scope minimization |
| **Idempotency** | Bicep IaC -- same code produces same result on repeated runs |
| **Shared Responsibility** | Microsoft: platform / Customer: data / access / OS / apps |

---

## Admin Access Patterns (Exercise 7.5)

| Pattern | Path | When to Use |
|---------|------|-------------|
| **Azure Bastion** | Browser -> Portal -> Bastion -> VM (TLS, no public SSH) | Daily operations |
| **Jumpbox** | Bastion -> ltmsa-jumpbox (mgmt-snet) -> App VM | Enterprise audit trail required |
| **Break-glass** | `az vm run-command` via Azure Management Plane | Emergency / automation |

---

## To-be Architecture Recommendations

The workshop builds a single-region foundation. Recommended evolution path toward production:

1. **Full IaC Coverage** -- Convert az CLI-provisioned resources to Bicep modules + Deployment Stacks
2. **Availability Zone Placement** -- Explicit VM-1 (Zone 1) / VM-2 (Zone 2) assignment for genuine HA
3. **Multi-region DR** -- ASR + Azure Traffic Manager (koreacentral -> koreasouth failover)
4. **GitOps Drift Detection** -- Daily `what-if` scan + GitHub Issue on drift detected
5. **Golden Image (Immutable Infrastructure)** -- Packer -> Azure Compute Gallery -> VM with runtime pre-baked; eliminate apt at deploy time; RTO from ~12 min -> ~2 min

Details: **[Scenario.md -- To-be Architecture Recommendations](Scenario.md)**

---

*LTM Korea Azure SA Workshop | Korea Central | 2026*
