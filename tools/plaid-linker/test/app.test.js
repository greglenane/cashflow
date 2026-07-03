import assert from "node:assert/strict";
import test from "node:test";

import { createApp } from "../src/app.js";

async function startTestServer(plaidService) {
  const app = createApp({
    plaidService,
    now: () => 1_000,
    sessionId: () => "session-test",
  });
  const server = app.listen(0, "127.0.0.1");
  await new Promise((resolve) => server.once("listening", resolve));
  const address = server.address();

  return {
    baseUrl: `http://127.0.0.1:${address.port}`,
    close: () => new Promise((resolve) => server.close(resolve)),
  };
}

test("creates a session and stores a linked item without returning tokens", async () => {
  const calls = [];
  const server = await startTestServer({
    async createLinkToken(institution) {
      calls.push(["create", institution]);
      return { linkToken: "link-test", institutionName: "American Express" };
    },
    async exchangeAndStore(institution, publicToken) {
      calls.push(["exchange", institution, publicToken]);
      return {
        institutionName: "American Express",
        accounts: [{ type: "credit", subtype: "credit card", mask: "1234" }],
      };
    },
  });

  try {
    const linkResponse = await fetch(`${server.baseUrl}/api/link-token`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Origin: "http://127.0.0.1:8787",
      },
      body: JSON.stringify({ institution: "amex" }),
    });
    const link = await linkResponse.json();

    const exchangeResponse = await fetch(`${server.baseUrl}/api/exchange`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Origin: "http://127.0.0.1:8787",
      },
      body: JSON.stringify({
        institution: "amex",
        public_token: "public-test",
        session_id: link.session_id,
      }),
    });
    const result = await exchangeResponse.json();

    assert.equal(exchangeResponse.status, 200);
    assert.equal(result.stored, true);
    assert.equal("access_token" in result, false);
    assert.deepEqual(calls, [
      ["create", "amex"],
      ["exchange", "amex", "public-test"],
    ]);
  } finally {
    await server.close();
  }
});

test("rejects cross-origin API requests", async () => {
  const server = await startTestServer({
    createLinkToken: async () => {
      throw new Error("should not run");
    },
  });

  try {
    const response = await fetch(`${server.baseUrl}/api/link-token`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Origin: "https://malicious.example",
      },
      body: JSON.stringify({ institution: "amex" }),
    });

    assert.equal(response.status, 403);
  } finally {
    await server.close();
  }
});

