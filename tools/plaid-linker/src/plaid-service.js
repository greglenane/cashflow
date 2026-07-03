import {
  Configuration,
  CountryCode,
  PlaidApi,
  PlaidEnvironments,
  Products,
} from "plaid";

import {
  buildItemSecret,
  getInstitutionConfig,
  publicAccountSummary,
  validateAccounts,
  validateLinkedInstitution,
} from "./domain.js";

export function createPlaidService({ secretsStore, now = () => new Date() }) {
  let clientPromise;

  async function getClient() {
    clientPromise ??= secretsStore.getPlaidCredentials().then(
      ({ clientId, secret }) =>
        new PlaidApi(
          new Configuration({
            basePath: PlaidEnvironments.production,
            baseOptions: {
              headers: {
                "PLAID-CLIENT-ID": clientId,
                "PLAID-SECRET": secret,
              },
            },
          }),
        ),
    );
    return clientPromise;
  }

  return {
    async createLinkToken(institutionKey) {
      const config = getInstitutionConfig(institutionKey);
      const client = await getClient();
      const response = await client.linkTokenCreate({
        user: {
          client_user_id: `cashflow-dashboard-${institutionKey}`,
        },
        client_name: "Cashflow Dashboard",
        products: [Products.Transactions],
        country_codes: [CountryCode.Us],
        language: "en",
        transactions: {
          days_requested: 730,
        },
      });

      return {
        linkToken: response.data.link_token,
        institutionName: config.displayName,
      };
    },

    async exchangeAndStore(institutionKey, publicToken) {
      const client = await getClient();
      const exchange = await client.itemPublicTokenExchange({
        public_token: publicToken,
      });
      const accessToken = exchange.data.access_token;
      const itemId = exchange.data.item_id;

      const [itemResponse, accountsResponse] = await Promise.all([
        client.itemGet({ access_token: accessToken }),
        client.accountsGet({ access_token: accessToken }),
      ]);

      const institutionId = itemResponse.data.item.institution_id;
      const institutionResponse = await client.institutionsGetById({
        institution_id: institutionId,
        country_codes: [CountryCode.Us],
      });
      const institutionName = institutionResponse.data.institution.name;
      const accounts = accountsResponse.data.accounts;

      validateLinkedInstitution(institutionKey, institutionName);
      validateAccounts(institutionKey, accounts);

      const secretString = buildItemSecret({
        institutionKey,
        institutionId,
        institutionName,
        accessToken,
        itemId,
        accounts,
        linkedAt: now().toISOString(),
      });

      await secretsStore.putItemCredentials(institutionKey, secretString);

      return {
        institutionName,
        accounts: publicAccountSummary(accounts),
      };
    },
  };
}

