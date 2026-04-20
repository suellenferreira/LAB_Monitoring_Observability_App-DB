# Contributing

Thank you for your interest in contributing to this project!

## Getting Started

1. **Fork** the repository
2. **Clone** your fork locally
3. Create a **feature branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```
4. Make your changes and test them
5. Push and open a **Pull Request** against `main`

## Branch Naming

| Prefix | Purpose |
|--------|---------|
| `feature/` | New functionality or modules |
| `fix/` | Bug fixes |
| `docs/` | Documentation changes |
| `refactor/` | Code restructuring without behavior changes |

## Before Submitting a PR

- [ ] Run `az bicep build --file main.bicep` — must pass with no errors
- [ ] Review linter warnings against `bicepconfig.json` rules
- [ ] Ensure no secrets, passwords, or personal identity values are committed
- [ ] Update `deploy-config.cfg` or `main.bicepparam` if you added new parameters
- [ ] Update `README.md` if user-facing behavior changed
- [ ] Test with What-If (`az deployment group what-if`) or a full deployment if possible

## Local Validation (no Azure credentials needed)

```bash
# Install/update Bicep CLI
az bicep install
az bicep upgrade

# Build — checks syntax and compiles to ARM JSON
az bicep build --file main.bicep

# Lint — applies rules from bicepconfig.json
az bicep lint --file main.bicep
```

## Full Validation (requires Azure credentials)

```bash
az login
az account set --subscription <YOUR_SUBSCRIPTION_ID>

# Validate without deploying
az deployment group validate \
  --resource-group <YOUR_RG> \
  --template-file main.bicep \
  --parameters main.bicepparam

# What-If — shows what would change
az deployment group what-if \
  --resource-group <YOUR_RG> \
  --template-file main.bicep \
  --parameters main.bicepparam
```

## Recommended Branch Protection (for maintainers)

If you fork this repo, we recommend enabling these branch protection rules on `main`:

- **Require pull request** before merging (no direct pushes)
- **Require status checks** — the `Validate Bicep` job must pass
- **Require at least 1 reviewer**
- **Do not allow bypassing** the above rules

## Code Style

- Bicep: follow the [Bicep best practices](https://learn.microsoft.com/azure/azure-resource-manager/bicep/best-practices) guide
- .NET: standard C# conventions
- Commit messages: imperative mood, concise summary line (e.g., "Add alert rule for SQL latency")

## Questions?

Open a [GitHub Issue](https://github.com/suellenferreira/LAB_Monitoring_Observability_App-DB/issues) with the "question" label.
