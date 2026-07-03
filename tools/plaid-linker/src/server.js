import { createApp } from "./app.js";
import { createSecretsStore } from "./aws-secrets.js";
import { createPlaidService } from "./plaid-service.js";

const host = "127.0.0.1";
const port = 8787;
const region = "us-east-1";

const secretsStore = createSecretsStore({ region });
const plaidService = createPlaidService({ secretsStore });
const app = createApp({ plaidService });

const server = app.listen(port, host, () => {
  console.log(`Plaid linker listening at http://${host}:${port}`);
});

function shutdown() {
  server.close(() => process.exit(0));
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

