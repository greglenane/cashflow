import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { readFile, stat } from "node:fs/promises";
import path from "node:path";

import { PutObjectCommand } from "@aws-sdk/client-s3";

const ALLOWED_KEY_PATTERN =
  /^(accounts\/accounts\.parquet|transactions\/year=\d{4}\/transactions\.parquet|metrics\/(monthly_(cashflow|spending_by_category)|cashflow_periods|mtd_comparison)\.parquet|analytics\/(recurring|outlier)_purchases\.parquet)$/;

async function sha256File(filePath) {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(filePath)) {
    hash.update(chunk);
  }
  return hash.digest("hex");
}

function resolveDataFile(runDirectory, key) {
  if (!ALLOWED_KEY_PATTERN.test(key)) {
    throw new Error("CURATED_MANIFEST_KEY_INVALID");
  }

  const resolvedRunDirectory = path.resolve(runDirectory);
  const resolvedFile = path.resolve(resolvedRunDirectory, ...key.split("/"));
  if (!resolvedFile.startsWith(`${resolvedRunDirectory}${path.sep}`)) {
    throw new Error("CURATED_MANIFEST_PATH_INVALID");
  }
  return resolvedFile;
}

async function putBuffer({ client, bucket, key, body, contentType }) {
  const digest = createHash("sha256").update(body).digest();
  await client.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      Body: body,
      ContentLength: body.length,
      ContentType: contentType,
      ServerSideEncryption: "AES256",
      ChecksumSHA256: digest.toString("base64"),
    }),
  );
}

export async function publishRun({
  client,
  manifestPath,
  bucket = "cashflow-dashboard",
  prefix = "curated",
}) {
  const resolvedManifestPath = path.resolve(manifestPath);
  const runDirectory = path.dirname(resolvedManifestPath);
  const manifestBody = await readFile(resolvedManifestPath);
  const manifest = JSON.parse(manifestBody.toString("utf-8"));

  if (
    manifest.schema_version !== 1 ||
    !/^[a-f0-9]{24}$/.test(manifest.run_id) ||
    !Array.isArray(manifest.files) ||
    manifest.files.length === 0
  ) {
    throw new Error("CURATED_MANIFEST_INVALID");
  }

  for (const file of manifest.files) {
    const filePath = resolveDataFile(runDirectory, file.key);
    const fileStat = await stat(filePath);
    const digest = await sha256File(filePath);
    if (
      fileStat.size !== file.size_bytes ||
      digest !== file.sha256 ||
      file.content_type !== "application/vnd.apache.parquet"
    ) {
      throw new Error("CURATED_FILE_INTEGRITY_FAILED");
    }

    await client.send(
      new PutObjectCommand({
        Bucket: bucket,
        Key: `${prefix}/${file.key}`,
        Body: createReadStream(filePath),
        ContentLength: fileStat.size,
        ContentType: file.content_type,
        ServerSideEncryption: "AES256",
        ChecksumSHA256: Buffer.from(digest, "hex").toString("base64"),
      }),
    );
  }

  await putBuffer({
    client,
    bucket,
    key: `${prefix}/manifests/runs/${manifest.run_id}.json`,
    body: manifestBody,
    contentType: "application/json",
  });
  await putBuffer({
    client,
    bucket,
    key: `${prefix}/manifests/latest.json`,
    body: manifestBody,
    contentType: "application/json",
  });

  return {
    runId: manifest.run_id,
    files: manifest.files.length,
    transactions: manifest.total_transactions,
    cutoff: manifest.source_data_cutoff,
  };
}
