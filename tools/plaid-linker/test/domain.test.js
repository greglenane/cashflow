import assert from "node:assert/strict";
import test from "node:test";

import {
  buildItemSecret,
  LinkerError,
  validateAccounts,
  validateLinkedInstitution,
} from "../src/domain.js";

const wellsAccounts = [
  {
    account_id: "checking-id",
    type: "depository",
    subtype: "checking",
    mask: "1111",
    name: "Checking",
  },
  {
    account_id: "credit-id",
    type: "credit",
    subtype: "credit card",
    mask: "2222",
    name: "Credit Card",
  },
];

test("accepts Wells Fargo only when checking and credit accounts exist", () => {
  assert.doesNotThrow(() => validateAccounts("wells-fargo", wellsAccounts));
  assert.throws(
    () => validateAccounts("wells-fargo", wellsAccounts.slice(1)),
    (error) =>
      error instanceof LinkerError &&
      error.code === "REQUIRED_ACCOUNTS_MISSING",
  );
});

test("accepts Amex credit accounts", () => {
  assert.doesNotThrow(() => validateAccounts("amex", wellsAccounts.slice(1)));
});

test("rejects an institution mismatch", () => {
  assert.throws(
    () => validateLinkedInstitution("amex", "Wells Fargo"),
    (error) =>
      error instanceof LinkerError && error.code === "INSTITUTION_MISMATCH",
  );
});

test("builds the private secret payload without balances", () => {
  const value = JSON.parse(
    buildItemSecret({
      institutionKey: "wells-fargo",
      institutionId: "ins_1",
      institutionName: "Wells Fargo",
      accessToken: "access-production-test",
      itemId: "item-test",
      accounts: wellsAccounts,
      linkedAt: "2026-07-03T12:00:00.000Z",
    }),
  );

  assert.equal(value.access_token, "access-production-test");
  assert.equal(value.accounts.length, 2);
  assert.deepEqual(Object.keys(value.accounts[0]).sort(), [
    "account_id",
    "mask",
    "name",
    "subtype",
    "type",
  ]);
});

