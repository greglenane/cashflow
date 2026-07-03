import { createSecretsReader } from "./secrets.js";
import { createS3Store } from "./s3-store.js";
import {
  createPlaidClient,
  fetchTransactionUpdates,
} from "./plaid-sync.js";
import { runSync } from "./run-sync.js";

try {
  await runSync({
    secretsReader: createSecretsReader(),
    store: createS3Store(),
    createClient: createPlaidClient,
    fetchUpdates: fetchTransactionUpdates,
  });
} catch (error) {
  const code =
    error?.code ??
    error?.response?.data?.error_code ??
    error?.name ??
    "UNKNOWN_ERROR";
  const requestId =
    error?.response?.data?.request_id ?? error?.$metadata?.requestId;
  console.error(
    `[plaid-sync] failed code=${code}${requestId ? ` request_id=${requestId}` : ""}`,
  );
  process.exitCode = 1;
}

