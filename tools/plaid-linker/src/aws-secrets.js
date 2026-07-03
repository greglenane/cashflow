import {
  GetSecretValueCommand,
  PutSecretValueCommand,
  SecretsManagerClient,
} from "@aws-sdk/client-secrets-manager";
import { randomUUID } from "node:crypto";

import { getInstitutionConfig, LinkerError } from "./domain.js";

const API_SECRET_ID = "cashflow/plaid/production";

export function createSecretsStore({
  region = "us-east-1",
  client = new SecretsManagerClient({ region, maxAttempts: 3 }),
} = {}) {
  let apiCredentialsPromise;

  return {
    async getPlaidCredentials() {
      apiCredentialsPromise ??= loadPlaidCredentials(client);
      return apiCredentialsPromise;
    },

    async putItemCredentials(institutionKey, secretString) {
      const { secretId } = getInstitutionConfig(institutionKey);
      await client.send(
        new PutSecretValueCommand({
          SecretId: secretId,
          SecretString: secretString,
          ClientRequestToken: randomUUID(),
        }),
      );
    },
  };
}

async function loadPlaidCredentials(client) {
  const response = await client.send(
    new GetSecretValueCommand({ SecretId: API_SECRET_ID }),
  );

  if (!response.SecretString) {
    throw new LinkerError("PLAID_CREDENTIAL_SECRET_EMPTY");
  }

  let value;
  try {
    value = JSON.parse(response.SecretString);
  } catch {
    throw new LinkerError("PLAID_CREDENTIAL_SECRET_INVALID");
  }

  const clientId = value.PLAID_CLIENT_ID;
  const secret = value.PLAID_SECRET;
  const environment = value.PLAID_ENV;

  if (!clientId || !secret || environment !== "production") {
    throw new LinkerError("PLAID_CREDENTIAL_SECRET_INCOMPLETE");
  }

  return { clientId, secret };
}

