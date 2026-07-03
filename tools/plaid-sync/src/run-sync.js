import { randomUUID } from "node:crypto";

import { rawBatchKey } from "./s3-store.js";

export async function runSync({
  credentials,
  secretsReader,
  store,
  createClient,
  fetchUpdates,
  now = () => new Date(),
  batchId = () => randomUUID(),
  log = console.log,
}) {
  const { api, items } = credentials ?? (await secretsReader.load());
  const client = createClient(api);
  const results = [];

  for (const item of items) {
    const { state, etag } = await store.loadState(item.institution);
    const fetchedAt = now().toISOString();
    const id = batchId();
    const updates = await fetchUpdates({
      client,
      accessToken: item.accessToken,
      cursor: state?.cursor ?? null,
    });
    const key = rawBatchKey(item.institution, fetchedAt, id);
    const counts = {
      added: updates.added.length,
      modified: updates.modified.length,
      removed: updates.removed.length,
    };

    const batch = {
      schema_version: 1,
      batch_id: id,
      institution: item.institution,
      fetched_at: fetchedAt,
      transactions_update_status: updates.updateStatus,
      page_count: updates.pageCount,
      counts,
      added: updates.added,
      modified: updates.modified,
      removed: updates.removed,
    };

    await store.writeRawBatch(key, batch);
    await store.writeState(
      item.institution,
      {
        schema_version: 1,
        institution: item.institution,
        cursor: updates.nextCursor,
        last_successful_sync: fetchedAt,
        last_batch_key: key,
        last_counts: counts,
        transactions_update_status: updates.updateStatus,
      },
      etag,
    );

    log(
      `[plaid-sync] institution=${item.institution} added=${counts.added} modified=${counts.modified} removed=${counts.removed}`,
    );
    results.push({ institution: item.institution, key, counts });
  }

  return results;
}

