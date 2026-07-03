import {
  Configuration,
  PlaidApi,
  PlaidEnvironments,
} from "plaid";

import { SyncError } from "./sync-error.js";

const MAX_PAGES = 1_000;
const MAX_MUTATION_RETRIES = 3;

export function createPlaidClient({ clientId, secret }) {
  return new PlaidApi(
    new Configuration({
      basePath: PlaidEnvironments.production,
      baseOptions: {
        headers: {
          "PLAID-CLIENT-ID": clientId,
          "PLAID-SECRET": secret,
        },
      },
    }),
  );
}

export async function fetchTransactionUpdates({
  client,
  accessToken,
  cursor = null,
}) {
  const fetchPage = (pageCursor) =>
    client.transactionsSync({
      access_token: accessToken,
      cursor: pageCursor ?? undefined,
      count: 500,
      options: {
        include_original_description: true,
      },
    });

  return fetchWithMutationRetry({ fetchPage, cursor });
}

export async function fetchWithMutationRetry({ fetchPage, cursor = null }) {
  for (let attempt = 1; attempt <= MAX_MUTATION_RETRIES; attempt += 1) {
    try {
      return await fetchAllPages({ fetchPage, cursor });
    } catch (error) {
      if (
        plaidErrorCode(error) !==
          "TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION" ||
        attempt === MAX_MUTATION_RETRIES
      ) {
        throw error;
      }
    }
  }

  throw new SyncError("SYNC_RETRY_EXHAUSTED");
}

async function fetchAllPages({ fetchPage, cursor }) {
  const added = [];
  const modified = [];
  const removed = [];
  let nextCursor = cursor;
  let hasMore = true;
  let pageCount = 0;
  let updateStatus = null;

  while (hasMore) {
    pageCount += 1;
    if (pageCount > MAX_PAGES) {
      throw new SyncError("SYNC_PAGE_LIMIT_EXCEEDED");
    }

    const response = await fetchPage(nextCursor);
    const data = response.data ?? response;
    added.push(...(data.added ?? []));
    modified.push(...(data.modified ?? []));
    removed.push(...(data.removed ?? []));
    nextCursor = data.next_cursor;
    hasMore = Boolean(data.has_more);
    updateStatus = data.transactions_update_status ?? updateStatus;

    if (!nextCursor) {
      throw new SyncError("SYNC_CURSOR_MISSING");
    }
  }

  return {
    added,
    modified,
    removed,
    nextCursor,
    pageCount,
    updateStatus,
  };
}

function plaidErrorCode(error) {
  return error?.response?.data?.error_code ?? error?.error_code;
}

