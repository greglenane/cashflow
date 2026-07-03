import {
  GetSecretValueCommand,
  SecretsManagerClient,
} from "@aws-sdk/client-secrets-manager";

import { API_SECRET_ID, ITEMS, REGION } from "./config.js";
import { SyncError } from "./sync-error.js";

export function createSecretsReader({
  client = new SecretsManagerClient({ region: REGION, maxAttempts: 3 }),
} = {}) {
  return {
    async load() {
      const [apiSecret, ...itemSecrets] = await Promise.all([
        getJsonSecret(client, API_SECRET_ID),
        ...ITEMS.map(({ secretId }) => getJsonSecret(client, secretId)),
      ]);

      if (
        !apiSecret.PLAID_CLIENT_ID ||
        !apiSecret.PLAID_SECRET ||
        apiSecret.PLAID_ENV !== "production"
      ) {
        throw new SyncError("PLAID_API_SECRET_INCOMPLETE");
      }

      const items = ITEMS.map((item, index) => {
        const value = itemSecrets[index];
        if (
          value.institution !== item.institution ||
          !value.access_token ||
          !value.item_id
        ) {
          throw new SyncError("PLAID_ITEM_SECRET_INCOMPLETE", {
            institution: item.institution,
          });
        }

        return {
          institution: item.institution,
          accessToken: value.access_token,
        };
      });

      return {
        api: {
          clientId: apiSecret.PLAID_CLIENT_ID,
          secret: apiSecret.PLAID_SECRET,
        },
        items,
      };
    },
  };
}

async function getJsonSecret(client, secretId) {
  const response = await client.send(
    new GetSecretValueCommand({ SecretId: secretId }),
  );
  if (!response.SecretString) {
    throw new SyncError("SECRET_VALUE_EMPTY", { secretId });
  }

  try {
    return JSON.parse(response.SecretString);
  } catch {
    throw new SyncError("SECRET_VALUE_INVALID", { secretId });
  }
}

