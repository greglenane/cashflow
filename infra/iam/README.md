# Cashflow IAM roles

These files define the local transformation role. The role can read Plaid raw
batches and write curated datasets, but it cannot read Plaid secrets, state
cursors, or unrelated S3 prefixes.

## Create `CashflowTransform`

Use an AWS administrative IAM identity in the AWS Console. Do not use the root
user.

1. Open **IAM → Roles → Create role → Custom trust policy**.
2. Paste `cashflow-transform-trust.json`.
3. Name the role `CashflowTransform`.
4. Set the maximum session duration to one hour.
5. Add an inline permissions policy named
   `CashflowTransformS3Access` using
   `cashflow-transform-permissions.json`.
6. Tag the role with `Project=cashflow-dashboard` and
   `ManagedBy=manual-reviewed`.

## Allow local, but not MCP, role assumption

Attach `cashflow-transform-assume.json` as an additional inline policy on the
`cashflow-mcp` IAM user. Do not replace its existing metadata, linker, or sync
policies.

The explicit deny prevents the AWS MCP service from assuming the data-bearing
role. Local CLI use remains available after `aws login`.

## Configure the local profile

Add this block to `~/.aws/config`:

```ini
[profile cashflow-transform]
role_arn = arn:aws:iam::377045608575:role/CashflowTransform
source_profile = cashflow-mcp
role_session_name = cashflow-transform-local
region = us-east-1
```

Then verify from Git Bash:

```bash
aws sts get-caller-identity \
  --profile cashflow-transform \
  --region us-east-1 \
  --query Arn \
  --output text
```

The result must contain:

```text
assumed-role/CashflowTransform/cashflow-transform-local
```

Do not expose the `cashflow-transform` profile to the AWS MCP configuration.

## Policy scope

- Bucket listing is limited to `raw/plaid/` and `curated/`.
- Object reads are limited to `raw/plaid/*`.
- Object writes are limited to `curated/*` and must request SSE-S3 encryption.
- There is no object delete permission.
- There is no Secrets Manager permission.
