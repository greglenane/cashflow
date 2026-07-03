import assert from "node:assert/strict";
import test from "node:test";

import { rawBatchKey, stateKey } from "../src/s3-store.js";

test("uses partitioned immutable raw keys", () => {
  assert.equal(
    rawBatchKey(
      "wells-fargo",
      "2026-07-03T05:00:00.000Z",
      "batch-id",
    ),
    "raw/plaid/year=2026/month=07/day=03/institution=wells-fargo/2026-07-03T05-00-00.000Z-batch-id.json",
  );
});

test("uses one cursor state object per institution", () => {
  assert.equal(
    stateKey("wells-fargo"),
    "state/plaid/wells-fargo.json",
  );
  assert.equal(stateKey("amex"), "state/plaid/amex.json");
});

