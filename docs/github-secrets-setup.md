# GitHub Actions secrets & variables setup

The `sre-loop` workflow needs a few values to reach Azure/AKS and Slack. Following
repo policy (`.claude/rules/no-secrets.md`), they split cleanly:

- **Variables** (`gh variable set`) - *identifiers*. Client/tenant/subscription
  IDs, resource group, cluster name. Not credentials; nothing to protect.
- **Secrets** (`gh secret set`) - *credentials*. The Slack webhook (embeds a
  token) and, only if you skip OIDC, the Azure service-principal JSON.

Prefer **OIDC** for Azure (below): GitHub exchanges a short-lived token with
Entra ID, so **no Azure secret is ever stored**. All commands use your own
values throughout; run them from a clone of this repo (so `gh` targets it) or
add `--repo travismoran/claude-ai-kubernetes-sre-loop`.

---

## Option A - Azure via OIDC (recommended, no Azure secret)

One-time federated-credential setup:

```bash
SUBSCRIPTION_ID="<your subscription id>"
GITHUB_REPO="travismoran/claude-ai-kubernetes-sre-loop"

# 1. App registration + service principal
APP_ID=$(az ad app create --display-name "gh-sre-loop" --query appId -o tsv)
az ad sp create --id "$APP_ID" --query id -o tsv

# 2. Federated credentials: PRs, pushes to main, and repository_dispatch runs
for sub in \
  "repo:${GITHUB_REPO}:ref:refs/heads/main" \
  "repo:${GITHUB_REPO}:pull_request"; do
  az ad app federated-credential create --id "$APP_ID" --parameters "{
    \"name\": \"gh-$(echo "$sub" | tr ':/' '--')\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"${sub}\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"
done

# 3. RBAC. 'review' mode needs only read; 'auto' mode needs write to restart/
#    scale/delete pods. Scope as tightly as your use allows.
az role assignment create --assignee "$APP_ID" \
  --role "Azure Kubernetes Service Cluster User Role" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"
# For auto-remediation, also grant in-cluster RBAC (edit on target namespaces)
# via a Kubernetes RoleBinding - see manifests/ and docs/SAFETY.md.
```

Then set the **repository variables** (identifiers - deliberately not secrets):

```bash
gh variable set AZURE_CLIENT_ID       --body "$APP_ID"
gh variable set AZURE_TENANT_ID       --body "$(az account show --query tenantId -o tsv)"
gh variable set AZURE_SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID"
gh variable set AKS_RESOURCE_GROUP    --body "<your aks resource group>"
gh variable set AKS_CLUSTER_NAME      --body "<your aks cluster name>"
```

The workflow's Azure-login step is gated on `vars.AZURE_CLIENT_ID != ''`, so
when these are set it uses OIDC automatically.

---

## Option B - Azure via service-principal secret (no OIDC)

If you cannot use OIDC, store the SP JSON as a secret instead. Leave
`AZURE_CLIENT_ID` **unset** so the workflow falls back to this path.

```bash
# Create an SP with a client secret and capture the azure/login JSON shape.
az ad sp create-for-rbac \
  --name "gh-sre-loop" \
  --role "Azure Kubernetes Service Cluster User Role" \
  --scopes "/subscriptions/<your subscription id>" \
  --sdk-auth > azure-creds.json      # contains a client secret - do NOT commit

gh secret set AZURE_CREDENTIALS < azure-creds.json
rm -f azure-creds.json               # delete immediately after upload

# Identifiers still go in variables:
gh variable set AKS_RESOURCE_GROUP --body "<your aks resource group>"
gh variable set AKS_CLUSTER_NAME   --body "<your aks cluster name>"
```

---

## Required for both options - Slack + in-cluster dispatch

```bash
# Slack Incoming Webhook (embeds a token -> secret). The loop posts health
# reports and escalations here (Skill 4 / orchestrator).
gh secret set SLACK_WEBHOOK_URL --body "https://hooks.slack.com/services/T.../B.../XXXX"

# GitHub PAT used by the IN-CLUSTER lifecycle hooks (Skill 7) to fire
# repository_dispatch back at this workflow. Fine-grained, scoped to this repo:
#   Contents: read/write   +   metadata: read   (dispatch permission)
# Stored as a repo secret here for reference; the manifests mount it as a
# Kubernetes Secret (sre-loop-dispatch), never inline. See manifests/.
gh secret set GH_DISPATCH_PAT --body "github_pat_..."

# Create the matching in-cluster Secret the manifests reference:
kubectl -n <namespace> create secret generic sre-loop-dispatch \
  --from-literal=github_pat="github_pat_..."
```

---

## Summary

| Name | Kind | Purpose | Needed when |
|------|------|---------|-------------|
| `AZURE_CLIENT_ID` | variable | OIDC app (client) id | Option A |
| `AZURE_TENANT_ID` | variable | Entra tenant id | Option A |
| `AZURE_SUBSCRIPTION_ID` | variable | Target subscription | Option A |
| `AZURE_CREDENTIALS` | **secret** | SP JSON w/ client secret | Option B only |
| `AKS_RESOURCE_GROUP` | variable | AKS resource group | always |
| `AKS_CLUSTER_NAME` | variable | AKS cluster name | always |
| `SLACK_WEBHOOK_URL` | **secret** | Alert channel | always |
| `GH_DISPATCH_PAT` | **secret** | In-cluster dispatch trigger | if using Skill 7 hooks |

Verify what's set:

```bash
gh variable list
gh secret list
```

The credential-free `ci` workflow (gitleaks + lint + schema validation) needs
none of the above, so it stays green on forks that configure nothing.
