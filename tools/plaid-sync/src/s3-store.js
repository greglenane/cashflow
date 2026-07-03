import {
  GetObjectCommand,
  NoSuchKey,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";

import { BUCKET, REGION } from "./config.js";
import { SyncError } from "./sync-error.js";

export function createS3Store({
  client = new S3Client({ region: REGION, maxAttempts: 3 }),
  bucket = BUCKET,
} = {}) {
  return {
    async loadState(institution) {
      const key = stateKey(institution);
      try {
        const response = await client.send(
          new GetObjectCommand({ Bucket: bucket, Key: key }),
        );
        const body = await response.Body.transformToString();
        const state = JSON.parse(body);
        if (state.institution !== institution || !state.cursor) {
          throw new SyncError("SYNC_STATE_INVALID", { institution });
        }
        return { state, etag: response.ETag };
      } catch (error) {
        if (
          error instanceof NoSuchKey ||
          error?.name === "NoSuchKey" ||
          error?.$metadata?.httpStatusCode === 404
        ) {
          return { state: null, etag: null };
        }
        if (error instanceof SyntaxError) {
          throw new SyncError("SYNC_STATE_INVALID", { institution });
        }
        throw error;
      }
    },

    async writeRawBatch(key, batch) {
      await client.send(
        new PutObjectCommand({
          Bucket: bucket,
          Key: key,
          Body: JSON.stringify(batch),
          ContentType: "application/json",
          ServerSideEncryption: "AES256",
        }),
      );
    },

    async writeState(institution, state, previousEtag) {
      const input = {
        Bucket: bucket,
        Key: stateKey(institution),
        Body: JSON.stringify(state),
        ContentType: "application/json",
        ServerSideEncryption: "AES256",
      };

      if (previousEtag) {
        input.IfMatch = previousEtag;
      } else {
        input.IfNoneMatch = "*";
      }

      await client.send(new PutObjectCommand(input));
    },
  };
}

export function stateKey(institution) {
  return `state/plaid/${institution}.json`;
}

export function rawBatchKey(institution, fetchedAt, batchId) {
  const date = new Date(fetchedAt);
  const year = String(date.getUTCFullYear());
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");
  const timestamp = date.toISOString().replaceAll(":", "-");
  return [
    "raw/plaid",
    `year=${year}`,
    `month=${month}`,
    `day=${day}`,
    `institution=${institution}`,
    `${timestamp}-${batchId}.json`,
  ].join("/");
}

