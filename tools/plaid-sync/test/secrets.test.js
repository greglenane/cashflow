import assert from "node:assert/strict";
import test from "node:test";

import { createSecretsReader } from "../src/secrets.js";

test("loads credentials while exposing only sanitized account metadata", async () => {
  const responses = [
    {
      PLAID_CLIENT_ID: "client-id",
      PLAID_SECRET: "api-secret",
      PLAID_ENV: "production",
    },
    {
      institution: "wells-fargo",
      access_token: "wf-token",
      item_id: "wf-item",
      accounts: [
        {
          account_id: "wf-checking",
          type: "depository",
          subtype: "checking",
          mask: "1111",
          name: "Synthetic Checking",
          unexpected_secret: "must-not-pass-through",
        },
      ],
    },
    {
      institution: "amex",
      access_token: "amex-token",
      item_id: "amex-item",
      accounts: [
        {
          account_id: "amex-credit",
          type: "credit",
          subtype: "credit card",
          mask: "3333",
          name: "Synthetic Card",
        },
      ],
    },
  ];
  let call = 0;
  const client = {
    send: async () => ({ SecretString: JSON.stringify(responses[call++]) }),
  };

  const result = await createSecretsReader({ client }).load();

  assert.equal(result.items.length, 2);
  assert.deepEqual(result.items[0].accounts, [
    {
      account_id: "wf-checking",
      type: "depository",
      subtype: "checking",
      mask: "1111",
      name: "Synthetic Checking",
    },
  ]);
  assert.equal(
    JSON.stringify(result.items).includes("unexpected_secret"),
    false,
  );
  assert.equal(JSON.stringify(result.items).includes("item_id"), false);
});
