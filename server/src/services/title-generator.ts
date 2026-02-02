import { getClaudePath, getClaudeEnv } from './claude-config';
import { logInfo, logError, logDebug } from './logger';

const TITLE_TIMEOUT_MS = 15_000; // 15 seconds max for title generation

interface TitleResult {
  title: string | null;
  error?: string;
}

/**
 * Generate a conversation title based on message history.
 * Uses a quick Claude call with minimal context.
 */
export async function generateTitle(
  currentTitle: string | null,
  recentMessages: Array<{ role: string; content: string }>
): Promise<TitleResult> {
  if (recentMessages.length === 0) {
    return { title: null, error: 'No messages to generate title from' };
  }

  // Build context from recent messages (last 4 max to keep it quick)
  const context = recentMessages
    .slice(-4)
    .map((m) => `${m.role}: ${m.content.slice(0, 200)}`)
    .join('\n');

  const prompt = currentTitle
    ? `Current title: "${currentTitle}"

Recent conversation:
${context}

If the topic has significantly shifted, provide a new short title (3-6 words) that captures the current topic. If the topic is the same, respond with just: KEEP

Respond with ONLY the new title or KEEP, nothing else.`
    : `Conversation:
${context}

Provide a short title (3-6 words) that captures what this conversation is about. Respond with ONLY the title, nothing else.`;

  logInfo('title-generator', `Generating title, current: ${currentTitle}`);

  try {
    const proc = Bun.spawn([getClaudePath(), '-p', prompt, '--output-format', 'text'], {
      cwd: process.env.HOME || '/',
      stdout: 'pipe',
      stderr: 'pipe',
      env: getClaudeEnv(),
    });

    // Set up timeout
    const timeoutId = setTimeout(() => {
      proc.kill();
    }, TITLE_TIMEOUT_MS);

    const output = await new Response(proc.stdout).text();
    clearTimeout(timeoutId);

    const exitCode = await proc.exited;
    if (exitCode !== 0) {
      const stderr = await new Response(proc.stderr).text();
      logError('title-generator', `Process exited with code ${exitCode}: ${stderr}`);
      return { title: null, error: 'Title generation failed' };
    }

    const result = output.trim();

    if (result === 'KEEP' || result === '') {
      logInfo('title-generator', 'Keeping existing title');
      return { title: null }; // null means keep existing
    }

    // Clean up the title (remove quotes if present, limit length)
    let title = result.replace(/^["']|["']$/g, '').trim();
    if (title.length > 60) {
      title = title.slice(0, 57) + '...';
    }

    logInfo('title-generator', `Generated title: ${title}`);
    return { title };
  } catch (error) {
    logError('title-generator', `Title generation error: ${error}`);
    return { title: null, error: String(error) };
  }
}
