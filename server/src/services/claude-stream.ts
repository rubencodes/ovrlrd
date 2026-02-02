import type { Subprocess } from 'bun';
import { logInfo, logError, logDebug } from './logger';
import {
  getWorkDir,
  getClaudePath,
  getClaudeEnv,
  buildBaseArgs,
  createSubprocessTimeout,
  CLAUDE_TIMEOUT_MS,
} from './claude-config';

// Types for stream-json output
interface StreamMessage {
  type: 'system' | 'assistant' | 'user' | 'result';
  subtype?: string;
  message?: {
    role?: string;
    content: Array<{ type: string; text?: string; name?: string; input?: unknown }> | string;
  };
  result?: string;
  session_id?: string;
  is_error?: boolean;
  permission_denials?: PermissionDenial[];
}

export interface PermissionDenial {
  tool_name: string;
  tool_use_id: string;
  tool_input: Record<string, unknown>;
}

interface StreamSession {
  process: Subprocess;
  sessionId: string | null;
  conversationId: string;
  currentSegment: string;
  lastToolName: string | null;
  clearTimeout: () => void;
  onChunk: (text: string) => void;
  onSegmentEnd: (content: string) => void;
  onToolStart: (toolName: string) => void;
  onToolEnd: (toolName: string) => void;
  onComplete: (result: string, sessionId: string | null, permissionDenials?: PermissionDenial[]) => void;
  onError: (error: string) => void;
}

export interface StreamOptions {
  allowedTools?: string[];
}

const activeSessions = new Map<string, StreamSession>();

/**
 * Run Claude with stream-json output format
 */
export async function runClaudeStreaming(
  message: string,
  conversationId: string,
  claudeSessionId: string | null,
  callbacks: {
    onChunk: (text: string) => void;
    onSegmentEnd: (content: string) => void;
    onToolStart: (toolName: string) => void;
    onToolEnd: (toolName: string) => void;
    onComplete: (result: string, sessionId: string | null, permissionDenials?: PermissionDenial[]) => void;
    onError: (error: string) => void;
  },
  options?: StreamOptions
): Promise<void> {
  const workDir = getWorkDir();
  const args = buildBaseArgs({
    claudeSessionId,
    allowedTools: options?.allowedTools,
    useStdin: true,
  });

  logInfo('claude-stream', `Starting streaming session for ${conversationId}`);
  logDebug('claude-stream', `Working dir: ${workDir}`);
  logDebug('claude-stream', `Args: ${JSON.stringify(args)}`);

  // Kill any existing session for this conversation to prevent orphaned processes
  const existingSession = activeSessions.get(conversationId);
  if (existingSession) {
    logInfo('claude-stream', `Killing existing session for ${conversationId}`);
    existingSession.clearTimeout();
    try {
      existingSession.process.kill();
    } catch {
      // Process may already be dead
    }
    activeSessions.delete(conversationId);
  }

  const proc = Bun.spawn([getClaudePath(), ...args], {
    cwd: workDir,
    stdin: 'pipe',
    stdout: 'pipe',
    stderr: 'pipe',
    env: getClaudeEnv(),
  });

  // Set up timeout
  let timedOut = false;
  const clearTimeout = createSubprocessTimeout(proc, CLAUDE_TIMEOUT_MS, () => {
    timedOut = true;
    logError('claude-stream', new Error(`Request timed out after ${CLAUDE_TIMEOUT_MS}ms`));
    callbacks.onError('Request timed out');
  });

  const session: StreamSession = {
    process: proc,
    sessionId: claudeSessionId,
    conversationId,
    currentSegment: '',
    lastToolName: null,
    clearTimeout,
    ...callbacks,
  };

  activeSessions.set(conversationId, session);

  // Write message to stdin with error handling
  try {
    proc.stdin.write(message);
    proc.stdin.end();
  } catch (error) {
    logError('claude-stream', `Failed to write to stdin: ${error}`);
    clearTimeout();
    activeSessions.delete(conversationId);
    callbacks.onError(`Failed to send message: ${error}`);
    try {
      proc.kill();
    } catch {
      // Ignore
    }
    return;
  }

  // Read stdout line by line
  const reader = proc.stdout.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });

      // Process complete lines
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';

      for (const line of lines) {
        if (!line.trim()) continue;

        try {
          const parsed = JSON.parse(line) as StreamMessage;
          handleStreamMessage(session, parsed);
        } catch {
          logDebug('claude-stream', `Non-JSON line: ${line.slice(0, 100)}`);
        }
      }
    }

    // Process any remaining buffer
    if (buffer.trim()) {
      try {
        const parsed = JSON.parse(buffer) as StreamMessage;
        handleStreamMessage(session, parsed);
      } catch {
        // Ignore incomplete JSON
      }
    }
  } catch (error) {
    logError('claude-stream', `Read error: ${error}`);
    if (!timedOut) {
      callbacks.onError(`Stream read error: ${error}`);
    }
  } finally {
    // Always clean up resources
    clearTimeout();
    reader.releaseLock();
    activeSessions.delete(conversationId);
  }

  // Check exit code and read stderr
  const exitCode = await proc.exited;

  if (timedOut) {
    return; // Error already reported
  }

  if (exitCode !== 0) {
    const stderrReader = proc.stderr.getReader();
    try {
      const { value } = await stderrReader.read();
      const stderr = value ? decoder.decode(value) : '';
      logError('claude-stream', `Process exited with code ${exitCode}: ${stderr}`);
    } finally {
      stderrReader.releaseLock();
    }
  }
}

function handleStreamMessage(session: StreamSession, msg: StreamMessage): void {
  logDebug('claude-stream', `Message type: ${msg.type}/${msg.subtype || ''}`);

  switch (msg.type) {
    case 'system':
      if (msg.subtype === 'init' && msg.session_id) {
        session.sessionId = msg.session_id;
        logInfo('claude-stream', `Session ID: ${msg.session_id}`);
      }
      break;

    case 'assistant':
      if (msg.message?.content && Array.isArray(msg.message.content)) {
        for (const block of msg.message.content) {
          if (block.type === 'text' && block.text) {
            // If we were waiting on a tool, signal it ended before new text
            if (session.lastToolName) {
              logDebug('claude-stream', `Tool end: ${session.lastToolName}`);
              session.onToolEnd(session.lastToolName);
              session.lastToolName = null;
            }

            logDebug('claude-stream', `Response text: ${block.text.slice(0, 200)}`);
            session.currentSegment += block.text;
            session.onChunk(block.text);
          } else if (block.type === 'tool_use' && block.name) {
            // Finalize current segment before tool use
            if (session.currentSegment.trim()) {
              logDebug('claude-stream', `Segment end (${session.currentSegment.length} chars)`);
              session.onSegmentEnd(session.currentSegment);
              session.currentSegment = '';
            }

            logDebug('claude-stream', `Tool start: ${block.name}`);
            session.onToolStart(block.name);
            session.lastToolName = block.name;
          }
        }
      }
      break;

    case 'result':
      // If a tool was pending, signal it ended
      if (session.lastToolName) {
        logDebug('claude-stream', `Tool end (on result): ${session.lastToolName}`);
        session.onToolEnd(session.lastToolName);
        session.lastToolName = null;
      }

      if (msg.is_error) {
        session.onError(msg.result || 'Unknown error');
      } else {
        const permissionDenials = msg.permission_denials && msg.permission_denials.length > 0
          ? msg.permission_denials
          : undefined;

        if (permissionDenials) {
          logInfo('claude-stream', `Permission denials: ${JSON.stringify(permissionDenials)}`);
        }

        session.onComplete(msg.result || '', session.sessionId, permissionDenials);
      }
      break;

    case 'user':
      // Check for slash command output
      if (msg.message?.content && typeof msg.message.content === 'string') {
        const content = msg.message.content;
        const match = content.match(/<local-command-stdout>([\s\S]*?)<\/local-command-stdout>/);
        if (match && match[1]) {
          const commandOutput = match[1].trim();
          logDebug('claude-stream', `Slash command output: ${commandOutput.slice(0, 200)}`);
          session.currentSegment += commandOutput;
          session.onChunk(commandOutput);
        }
      }
      break;
  }
}

/**
 * Cancel an active streaming session
 */
export function cancelStream(conversationId: string): boolean {
  const session = activeSessions.get(conversationId);
  if (session) {
    logInfo('claude-stream', `Cancelling session for ${conversationId}`);
    session.clearTimeout();
    try {
      session.process.kill();
    } catch {
      // Process may already be dead
    }
    activeSessions.delete(conversationId);
    return true;
  }
  return false;
}

/**
 * Get count of active sessions (for monitoring)
 */
export function getActiveSessionCount(): number {
  return activeSessions.size;
}
