import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import { publishRun } from "../src/publisher.js";

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

const testRoot = path.resolve(
  import.meta.dirname,
  "../../../.local/test-tmp",
);

for (const relativeKey of [
  "accounts/accounts.parquet",
  "quality/account_status.parquet",
  "quality/account_reconciliation.parquet",
  "quality/data_status.parquet",
]) {
  test(`uploads ${relativeKey} before immutable and latest manifests`, async () => {
    await mkdir(testRoot, { recursive: true });
    const directory = await mkdtemp(path.join(testRoot, "curated-publish-"));
    const filePath = path.join(directory, relativeKey);
    const fileBody = Buffer.from("synthetic-parquet");
    await mkdir(path.dirname(filePath), { recursive: true });
    await writeFile(filePath, fileBody);

    const manifest = {
      schema_version: 1,
      run_id: "0123456789abcdef01234567",
      source_data_cutoff: "2026-07-05",
      total_transactions: 7,
      files: [
        {
          key: relativeKey,
          content_type: "application/vnd.apache.parquet",
          row_count: 3,
          size_bytes: fileBody.length,
          sha256: sha256(fileBody),
        },
      ],
    };
    const manifestPath = path.join(directory, "manifest.json");
    await writeFile(manifestPath, JSON.stringify(manifest));

    const requests = [];
    const client = {
      send: async (command) => {
        const input = command.input;
        let body;
        if (Buffer.isBuffer(input.Body)) {
          body = input.Body;
        } else {
          const chunks = [];
          for await (const chunk of input.Body) {
            chunks.push(chunk);
          }
          body = Buffer.concat(chunks);
        }
        requests.push({ ...input, Body: body });
        return {};
      },
    };

    const result = await publishRun({ client, manifestPath });

    assert.deepEqual(
      requests.map((request) => request.Key),
      [
        `curated/${relativeKey}`,
        "curated/manifests/runs/0123456789abcdef01234567.json",
        "curated/manifests/latest.json",
      ],
    );
    assert.equal(
      requests.every(
        (request) => request.ServerSideEncryption === "AES256",
      ),
      true,
    );
    assert.equal(requests[0].Body.equals(fileBody), true);
    assert.equal(result.transactions, 7);
  });
}

test("rejects manifest paths outside the curated layout", async () => {
  await mkdir(testRoot, { recursive: true });
  const directory = await mkdtemp(path.join(testRoot, "curated-publish-"));
  const manifestPath = path.join(directory, "manifest.json");
  await writeFile(
    manifestPath,
    JSON.stringify({
      schema_version: 1,
      run_id: "0123456789abcdef01234567",
      files: [
        {
          key: "../private.txt",
          content_type: "application/vnd.apache.parquet",
          row_count: 1,
          size_bytes: 1,
          sha256: "0".repeat(64),
        },
      ],
    }),
  );

  await assert.rejects(
    publishRun({
      client: { send: async () => ({}) },
      manifestPath,
    }),
    /CURATED_MANIFEST_KEY_INVALID/,
  );
});
