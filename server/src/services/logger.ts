import { appendFileSync, writeFileSync } from 'node:fs';
import { config } from '../config';

function formatLog(level: string, context: string, message: string, data?: unknown): string {
  const timestamp = new Date().toISOString();
  const dataStr = data !== undefined ? `\n${JSON.stringify(data, null, 2)}` : '';
  return `[${timestamp}] [${level}] [${context}] ${message}${dataStr}\n`;
}

/**
 * Write log synchronously to avoid fire-and-forget async issues.
 * Logging should never crash the app, so we catch and ignore errors.
 */
function writeLog(line: string): void {
  try {
    appendFileSync(config.logPath, line);
  } catch {
    try {
      // If directory doesn't exist or other error, try to create file
      writeFileSync(config.logPath, line);
    } catch {
      // If all else fails, silently continue - don't crash for logging
      // The console.log/error already captured the output
    }
  }
}

export function logError(context: string, error: unknown): void {
  const message = error instanceof Error ? error.message : String(error);
  const stack = error instanceof Error ? error.stack : undefined;
  const line = formatLog('ERROR', context, message, stack);

  console.error(line.trim());
  writeLog(line);
}

export function logDebug(context: string, message: string, data?: unknown): void {
  const line = formatLog('DEBUG', context, message, data);

  if (process.env.DEBUG) {
    console.log(line.trim());
  }
  writeLog(line);
}

export function logInfo(context: string, message: string, data?: unknown): void {
  const line = formatLog('INFO', context, message, data);
  console.log(line.trim());
  writeLog(line);
}
