import assert from "node:assert/strict";
import test from "node:test";

import { runSync } from "../src/run-sync.js";
import { rawBatchKey, stateKey } from "../src/s3-store.js";

test("writes raw data before advancing cursor state", async () => {
  const operations = [];
  const logs = [];
  const fetchedAt = new Date("2026-07-03T10:00:00.000Z");

  const result = await runSync({
    credentials: {
      api: { clientId: "client", secret: "secret" },
      items: [
        {
          institution: "amex",
          accessToken: "access-token",
        },
      ],
    },
    store: {
      loadState: async () => ({
        state: { institution: "amex", cursor: "cursor-old" },
        etag: '"etag-old"',
      }),
      writeRawBatch: async (key, batch) => {
        operations.push(["raw", key, batch.counts]);
      },
      writeState: async (institution, state, etag) => {
        operations.push(["state", institution, state.cursor, etag]);
      },
    },
    createClient: () => ({ client: true }),
    fetchUpdates: async ({ cursor }) => {
      assert.equal(cursor, "cursor-old");
      return {
        added: [{ transaction_id: "new" }],
        modified: [],
        removed: [],
        nextCursor: "cursor-new",
        pageCount: 1,
        updateStatus: "HISTORICAL_UPDATE_COMPLETE",
      };
    },
    now: () => fetchedAt,
    batchId: () => "batch-test",
    log: (message) => logs.push(message),
  });

  const expectedKey = rawBatchKey("amex", fetchedAt, "batch-test");
  assert.equal(stateKey("amex"), "state/plaid/amex.json");
  assert.deepEqual(operations, [
    ["raw", expectedKey, { added: 1, modified: 0, removed: 0 }],
    ["state", "amex", "cursor-new", '"etag-old"'],
  ]);
  assert.equal(result[0].key, expectedKey);
  assert.equal(logs.length, 1);
  assert.equal(logs[0].includes("access-token"), false);
});

