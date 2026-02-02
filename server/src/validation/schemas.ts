import { z } from 'zod';

// Maximum lengths for various fields
const MAX_MESSAGE_LENGTH = 100_000; // 100KB max message
const MAX_TOOL_NAME_LENGTH = 100;
const MAX_TOOLS_COUNT = 50;

// Auth request validation
export const authRequestSchema = z.object({
  identityToken: z.string().min(1, 'Identity token is required'),
  deviceToken: z.string().optional(),
  deviceId: z.string().optional(),
});

export type AuthRequest = z.infer<typeof authRequestSchema>;

// Chat message request validation
export const chatMessageSchema = z.object({
  message: z
    .string()
    .min(1, 'Message is required')
    .max(MAX_MESSAGE_LENGTH, `Message too long (max ${MAX_MESSAGE_LENGTH} characters)`),
});

export type ChatMessageRequest = z.infer<typeof chatMessageSchema>;

// Chat stream request validation (with optional allowed tools)
export const chatStreamSchema = z.object({
  message: z
    .string()
    .min(1, 'Message is required')
    .max(MAX_MESSAGE_LENGTH, `Message too long (max ${MAX_MESSAGE_LENGTH} characters)`),
  allowedTools: z
    .array(z.string().max(MAX_TOOL_NAME_LENGTH))
    .max(MAX_TOOLS_COUNT)
    .optional(),
});

export type ChatStreamRequest = z.infer<typeof chatStreamSchema>;

// Permission event request validation
export const permissionEventSchema = z.object({
  role: z.enum(['user', 'assistant', 'system']).default('system'),
  content: z.string().min(1, 'Content is required'),
});

export type PermissionEventRequest = z.infer<typeof permissionEventSchema>;

// Pagination query parameters
export const paginationSchema = z.object({
  limit: z
    .string()
    .optional()
    .transform((val) => (val ? parseInt(val, 10) : undefined))
    .pipe(z.number().int().min(1).max(100).optional()),
  cursor: z.string().optional(),
});

export type PaginationParams = z.infer<typeof paginationSchema>;

/**
 * Parse and validate request body with Zod schema
 * Returns the validated data or throws an error with details
 */
export async function parseBody<T>(
  request: Request,
  schema: z.ZodSchema<T>
): Promise<T> {
  const body = await request.json();
  const result = schema.safeParse(body);

  if (!result.success) {
    // Zod 4 uses .message directly on the error
    throw new ValidationError(result.error.message);
  }

  return result.data;
}

/**
 * Parse and validate query parameters with Zod schema
 */
export function parseQuery<T>(
  url: URL,
  schema: z.ZodSchema<T>
): T {
  const params = Object.fromEntries(url.searchParams.entries());
  const result = schema.safeParse(params);

  if (!result.success) {
    throw new ValidationError(result.error.message);
  }

  return result.data;
}

/**
 * Custom validation error that can be caught and handled
 */
export class ValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ValidationError';
  }
}
