import path from "node:path";
import { fileURLToPath } from "node:url";

import { S3Client } from "@aws-sdk/client-s3";

import { publishRun } from "./publisher.js";

const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const defaultManifest = path.resolve(
  currentDirectory,
  "../../../.local/curated/current/manifest.json",
);
const manifestPath = process.argv[2] ?? defaultManifest;
const region = process.env.AWS_REGION ?? "us-east-1";
const client = new S3Client({ region, maxAttempts: 3 });

const result = await publishRun({ client, manifestPath });
console.log(
  "[curated-publish]"
  + ` run_id=${result.runId}`
  + ` files=${result.files}`
  + ` transactions=${result.transactions}`
  + ` cutoff=${result.cutoff}`,
);
