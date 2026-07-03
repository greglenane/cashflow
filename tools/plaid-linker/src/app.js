import express from "express";
import { randomUUID } from "node:crypto";
import { fileURLToPath } from "node:url";
import path from "node:path";

import {
  getInstitutionConfig,
  LinkerError,
  supportedInstitutions,
} from "./domain.js";

const SESSION_TTL_MS = 15 * 60 * 1000;
const EXPECTED_ORIGIN = "http://127.0.0.1:8787";
const publicDirectory = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../public",
);

export function createApp({
  plaidService,
  now = () => Date.now(),
  sessionId = () => randomUUID(),
} = {}) {
  if (!plaidService) {
    throw new Error("plaidService is required");
  }

  const app = express();
  const sessions = new Map();

  app.disable("x-powered-by");
  app.use((request, response, next) => {
    response.setHeader("Cache-Control", "no-store");
    response.setHeader("Referrer-Policy", "no-referrer");
    response.setHeader("X-Content-Type-Options", "nosniff");
    response.setHeader("Content-Security-Policy", "frame-ancestors 'none'");

    const origin = request.get("origin");
    if (request.path.startsWith("/api/") && origin && origin !== EXPECTED_ORIGIN) {
      return response.status(403).json({ error: "ORIGIN_NOT_ALLOWED" });
    }
    next();
  });
  app.use(express.json({ limit: "16kb", type: "application/json" }));

  app.post("/api/link-token", async (request, response, next) => {
    try {
      const institution = request.body?.institution;
      getInstitutionConfig(institution);
      removeExpiredSessions(sessions, now());

      const result = await plaidService.createLinkToken(institution);
      const id = sessionId();
      sessions.set(id, {
        institution,
        expiresAt: now() + SESSION_TTL_MS,
        processing: false,
      });

      response.json({
        link_token: result.linkToken,
        session_id: id,
        institution_name: result.institutionName,
      });
    } catch (error) {
      next(error);
    }
  });

  app.post("/api/exchange", async (request, response, next) => {
    const { institution, public_token: publicToken, session_id: id } =
      request.body ?? {};
    const session = sessions.get(id);

    try {
      if (
        !supportedInstitutions().includes(institution) ||
        typeof publicToken !== "string" ||
        !publicToken ||
        !session ||
        session.institution !== institution ||
        session.expiresAt <= now() ||
        session.processing
      ) {
        throw new LinkerError("INVALID_LINK_SESSION");
      }

      session.processing = true;
      const result = await plaidService.exchangeAndStore(
        institution,
        publicToken,
      );
      sessions.delete(id);
      response.json({
        stored: true,
        institution_name: result.institutionName,
        accounts: result.accounts,
      });
    } catch (error) {
      if (session) {
        session.processing = false;
      }
      next(error);
    }
  });

  app.use(express.static(publicDirectory, { etag: false, maxAge: 0 }));

  app.use((error, request, response, next) => {
    if (response.headersSent) {
      return next(error);
    }

    const code = publicErrorCode(error);
    const requestId =
      error?.response?.data?.request_id ?? error?.$metadata?.requestId;
    console.error(
      `[plaid-linker] ${code}${requestId ? ` request_id=${requestId}` : ""}`,
    );
    response.status(code === "INTERNAL_ERROR" ? 500 : 400).json({ error: code });
  });

  return app;
}

function removeExpiredSessions(sessions, timestamp) {
  for (const [id, session] of sessions.entries()) {
    if (session.expiresAt <= timestamp) {
      sessions.delete(id);
    }
  }
}

function publicErrorCode(error) {
  if (error instanceof LinkerError) {
    return error.code;
  }
  if (error?.response?.data?.error_code) {
    return `PLAID_${error.response.data.error_code}`;
  }
  if (error?.name?.startsWith("AccessDenied")) {
    return "AWS_ACCESS_DENIED";
  }
  return "INTERNAL_ERROR";
}

