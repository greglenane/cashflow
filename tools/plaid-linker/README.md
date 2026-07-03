# Local Plaid Linker

This localhost-only utility links Wells Fargo and American Express to the
cashflow project and stores Plaid Item credentials directly in AWS Secrets
Manager.

It reads:

- `cashflow/plaid/production`

It replaces:

- `cashflow/plaid/items/wells-fargo`
- `cashflow/plaid/items/amex`

It never returns access tokens to the browser.

## Prerequisites

- Node.js 20 or newer
- AWS CLI v2
- A current `cashflow-mcp` login session
- The `cashflow-linker` role profile configured in `~/.aws/config`

## Install

From the repository root in Git Bash:

```bash
cd tools/plaid-linker
npm install
```

## Run

Export temporary assumed-role credentials into this terminal only:

```bash
eval "$(
  aws configure export-credentials \
    --profile cashflow-linker \
    --format env
)"
export AWS_REGION=us-east-1
```

Start the linker:

```bash
npm start
```

Open <http://127.0.0.1:8787>, connect Wells Fargo, verify both expected masked
accounts, then connect American Express.

Stop the process with `Ctrl+C`. Close the terminal afterward to discard the
temporary environment credentials.

## Test

Tests use only synthetic values and do not call Plaid or AWS:

```bash
npm test
```

