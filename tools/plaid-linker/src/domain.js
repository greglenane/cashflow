const INSTITUTIONS = Object.freeze({
  "wells-fargo": {
    displayName: "Wells Fargo",
    secretId: "cashflow/plaid/items/wells-fargo",
    namePattern: /wells\s*fargo/i,
    requiredAccounts: [
      { type: "depository", subtype: "checking" },
      { type: "credit" },
    ],
  },
  amex: {
    displayName: "American Express",
    secretId: "cashflow/plaid/items/amex",
    namePattern: /american\s*express|amex/i,
    requiredAccounts: [{ type: "credit" }],
  },
});

export function supportedInstitutions() {
  return Object.keys(INSTITUTIONS);
}

export function getInstitutionConfig(key) {
  const config = INSTITUTIONS[key];
  if (!config) {
    throw new LinkerError("UNSUPPORTED_INSTITUTION");
  }
  return config;
}

export function validateLinkedInstitution(key, institutionName) {
  const config = getInstitutionConfig(key);
  if (
    typeof institutionName !== "string" ||
    !config.namePattern.test(institutionName)
  ) {
    throw new LinkerError("INSTITUTION_MISMATCH");
  }
}

export function validateAccounts(key, accounts) {
  const config = getInstitutionConfig(key);
  if (!Array.isArray(accounts)) {
    throw new LinkerError("ACCOUNTS_UNAVAILABLE");
  }

  const missing = config.requiredAccounts.filter(
    (required) =>
      !accounts.some(
        (account) =>
          account.type === required.type &&
          (!required.subtype || account.subtype === required.subtype),
      ),
  );

  if (missing.length > 0) {
    throw new LinkerError("REQUIRED_ACCOUNTS_MISSING");
  }
}

export function buildItemSecret({
  institutionKey,
  institutionId,
  institutionName,
  accessToken,
  itemId,
  accounts,
  linkedAt,
}) {
  getInstitutionConfig(institutionKey);

  if (!accessToken || !itemId) {
    throw new LinkerError("TOKEN_EXCHANGE_INCOMPLETE");
  }

  return JSON.stringify({
    version: 1,
    institution: institutionKey,
    institution_id: institutionId,
    institution_name: institutionName,
    access_token: accessToken,
    item_id: itemId,
    accounts: accounts.map((account) => ({
      account_id: account.account_id,
      type: account.type,
      subtype: account.subtype,
      mask: account.mask ?? null,
      name: account.name ?? null,
    })),
    linked_at: linkedAt,
  });
}

export function publicAccountSummary(accounts) {
  return accounts.map((account) => ({
    type: account.type,
    subtype: account.subtype,
    mask: account.mask ?? null,
    name: account.name ?? null,
  }));
}

export class LinkerError extends Error {
  constructor(code) {
    super(code);
    this.name = "LinkerError";
    this.code = code;
  }
}

