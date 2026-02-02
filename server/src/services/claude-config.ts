import { config } from '../config';

// Default timeout for Claude subprocess (2 minutes)
export const CLAUDE_TIMEOUT_MS = 2 * 60 * 1000;

/**
 * Get the working directory for Claude CLI
 */
export function getWorkDir(): string {
  return config.claudeWorkDir;
}

/**
 * Get additional directories Claude should have access to.
 * Configure via CLAUDE_ADDITIONAL_DIRS in .env (colon-separated paths).
 */
export function getAdditionalDirs(): string[] {
  return config.claudeAdditionalDirs;
}

/**
 * Get the Claude CLI path
 */
export function getClaudePath(): string {
  return config.claudePath || process.env.CLAUDE_PATH || 'claude';
}

/**
 * Get environment variables for Claude subprocess
 * Extends PATH to include common binary locations on macOS
 */
export function getClaudeEnv(): NodeJS.ProcessEnv {
  const additionalPaths: string[] = [];

  // macOS-specific paths
  if (process.platform === 'darwin') {
    additionalPaths.push('/opt/homebrew/bin', '/usr/local/bin');
  }

  // Linux common paths (if not already in PATH)
  if (process.platform === 'linux') {
    additionalPaths.push('/usr/local/bin', '/usr/bin');
  }

  const extendedPath = additionalPaths.length > 0
    ? `${process.env.PATH}:${additionalPaths.join(':')}`
    : process.env.PATH;

  return {
    ...process.env,
    PATH: extendedPath,
  };
}

/**
 * Build common Claude CLI arguments
 */
export function buildBaseArgs(options: {
  message?: string;
  claudeSessionId?: string | null;
  allowedTools?: string[];
  useStdin?: boolean;
}): string[] {
  const args: string[] = [];

  // Message via -p flag or stdin
  if (options.message && !options.useStdin) {
    args.push('-p', options.message);
  } else if (options.useStdin) {
    args.push('-p'); // -p without argument reads from stdin
  }

  args.push('--output-format', 'stream-json');
  args.push('--verbose');

  // Add allowed tools if any
  if (options.allowedTools && options.allowedTools.length > 0) {
    args.push('--allowedTools', options.allowedTools.join(' '));
  }

  // Add additional directories
  for (const dir of getAdditionalDirs()) {
    args.push('--add-dir', dir);
  }

  // Resume session if provided
  if (options.claudeSessionId) {
    args.push('--resume', options.claudeSessionId);
  }

  return args;
}

/**
 * Create a timeout that kills a subprocess
 * Returns a cleanup function to clear the timeout
 */
export function createSubprocessTimeout(
  proc: { kill: () => void },
  timeoutMs: number,
  onTimeout: () => void
): () => void {
  const timeoutId = setTimeout(() => {
    onTimeout();
    proc.kill();
  }, timeoutMs);

  return () => clearTimeout(timeoutId);
}
