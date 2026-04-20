# Security Policy

## Scope

This repository is an **educational/demo** project for Azure monitoring and observability. It is **not production-hardened** and should not be used as-is for production workloads.

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly:

1. **Do NOT open a public issue.**
2. Use [GitHub's private vulnerability reporting](https://github.com/suellenferreira/LAB_Monitoring_Observability_App-DB/security/advisories/new) to submit a report.
3. Include a description of the vulnerability, steps to reproduce, and potential impact.

You should receive a response within 7 days.

## Known Security Considerations

This demo environment intentionally uses simplified configurations for learning purposes. See the **Security Considerations** section in the [README](README.md) for details, including:

- NSG rules default to `*` (open) — restrict via `ALLOWED_SOURCE_ADDRESS` in `deploy-config.cfg`
- SQL VM uses a public IP — consider Private Endpoints / Bastion for production
- `TrustServerCertificate=True` is used for demo convenience — disable in production
- Azure SQL has `publicNetworkAccess: Enabled` — use Private Endpoints in production

## Secrets Handling

- All sensitive values (passwords, client secrets, object IDs) are passed via **GitHub Secrets** or environment variables
- No secrets are hardcoded in source code
- The `deploy-config.cfg` file contains only non-secret configuration (SKUs, regions, retention)
- Pipeline logs mask subscription IDs, tenant IDs, and SP credentials
