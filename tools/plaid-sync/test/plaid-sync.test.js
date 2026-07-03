import assert from "node:assert/strict";
import test from "node:test";

import { fetchWithMutationRetry } from "../src/plaid-sync.js";

test("collects every transaction sync page", async () => {
  const cursors = [];
  const pages = [
    {
      added: [{ transaction_id: "a" }],
      modified: [],
      removed: [],
      next_cursor: "cursor-1",
      has_more: true,
      transactions_update_status: "HISTORICAL_UPDATE_COMPLETE",
    },
    {
      added: [{ transaction_id: "b" }],
      modified: [{ transaction_id: "m" }],
      removed: [{ transaction_id: "r" }],
      next_cursor: "cursor-2",
      has_more: false,
      transactions_update_status: "HISTORICAL_UPDATE_COMPLETE",
    },
  ];

  const result = await fetchWithMutationRetry({
    cursor: "cursor-0",
    fetchPage: async (cursor) => {
      cursors.push(cursor);
      return { data: pages.shift() };
    },
  });

  assert.deepEqual(cursors, ["cursor-0", "cursor-1"]);
  assert.deepEqual(
    result.added.map((transaction) => transaction.transaction_id),
    ["a", "b"],
  );
  assert.equal(result.modified.length, 1);
  assert.equal(result.removed.length, 1);
  assert.equal(result.nextCursor, "cursor-2");
});

test("restarts pagination from the original cursor after a mutation", async () => {
  const cursors = [];
  let calls = 0;

  const result = await fetchWithMutationRetry({
    cursor: "cursor-original",
    fetchPage: async (cursor) => {
      calls += 1;
      cursors.push(cursor);
      if (calls === 2) {
        const error = new Error("mutation");
        error.response = {
          data: {
            error_code: "TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION",
          },
        };
        throw error;
      }
      return {
        data:
          calls === 1
            ? {
                added: [{ transaction_id: "discarded" }],
                next_cursor: "cursor-intermediate",
                has_more: true,
              }
            : {
                added: [{ transaction_id: "kept" }],
                next_cursor: "cursor-final",
                has_more: false,
              },
      };
    },
  });

  assert.deepEqual(cursors, [
    "cursor-original",
    "cursor-intermediate",
    "cursor-original",
  ]);
  assert.deepEqual(result.added, [{ transaction_id: "kept" }]);
});

