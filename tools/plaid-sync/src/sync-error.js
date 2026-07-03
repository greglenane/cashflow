export class SyncError extends Error {
  constructor(code, context = {}) {
    super(code);
    this.name = "SyncError";
    this.code = code;
    this.context = context;
  }
}

