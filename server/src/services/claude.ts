import { logError, logDebug } from './logger';
import {
  getWorkDir,
  getClaudePath,
  getClaudeEnv,
  buildBaseArgs,
  createSubprocessTimeout,
  CLAUDE_TIMEOUT_MS,
} from './claude-config';

export interface ClaudeResponse {
  text: string;
  sessionId: string;
}

export async function runClaude(
  message: string,
  claudeSessionId: string | null
): Promise<ClaudeResponse> {
  const workDir = getWorkDir();
  const args = buildBaseArgs({ message, claudeSessionId });

  logDebug('claude', 'Starting request', { claudeSessionId, message: message.slice(0, 100) });

  const proc = Bun.spawn([getClaudePath(), ...args], {
    cwd: workDir,
    stdout: 'pipe',
    stderr: 'pipe',
    env: getClaudeEnv(),
  });

  // Set up timeout
  let timedOut = false;
  const clearTimeout = createSubprocessTimeout(proc, CLAUDE_TIMEOUT_MS, () => {
    timedOut = true;
    logError('claude', new Error(`Request timed out after ${CLAUDE_TIMEOUT_MS}ms`));
  });

  const reader = proc.stdout.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let responseText = '';
  let sessionId = '';

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });

      // Process complete JSON lines
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';

      for (const line of lines) {
        if (!line.trim()) continue;

        try {
          const event = JSON.parse(line);

          // Capture session ID from system init event
          if (event.type === 'system' && event.session_id) {
            sessionId = event.session_id;
          }

          // Capture response text from assistant event
          if (event.type === 'assistant' && event.message?.content) {
            for (const block of event.message.content) {
              if (block.type === 'text') {
                responseText += block.text;
              }
            }
            // Also grab session_id from assistant event if present
            if (event.session_id) {
              sessionId = event.session_id;
            }
          }
        } catch {
          // Not valid JSON, might be partial - continue
        }
      }
    }

    // Clear timeout before waiting for exit
    clearTimeout();

    await proc.exited;

    if (timedOut) {
      throw new Error('Claude CLI request timed out');
    }

    if (proc.exitCode !== 0) {
      const stderrReader = proc.stderr.getReader();
      try {
        const { value } = await stderrReader.read();
        const stderr = value ? decoder.decode(value) : '';
        logError('claude', new Error(`CLI exited with code ${proc.exitCode}: ${stderr}`));
      } finally {
        stderrReader.releaseLock();
      }
      throw new Error(`Claude CLI exited with code ${proc.exitCode}`);
    }

    logDebug('claude', 'Request completed', { sessionId, responseLength: responseText.length });

    return { text: responseText, sessionId };
  } catch (error) {
    // Kill process if still running
    try {
      proc.kill();
    } catch {
      // Process may already be dead
    }
    throw error;
  } finally {
    clearTimeout();
    reader.releaseLock();
  }
}
