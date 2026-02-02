const isProduction = process.env.NODE_ENV === 'production';

// Validate required environment variables
function requireEnv(name: string, defaultValue?: string): string {
  const value = process.env[name] || defaultValue;
  if (!value) {
    if (isProduction) {
      throw new Error(`Missing required environment variable: ${name}`);
    }
    console.warn(`WARNING: ${name} not set. This would fail in production.`);
    return '';
  }
  return value;
}

// Validate port is a valid number
function parsePort(value: string | undefined): number {
  const port = Number(value) || 3000;
  if (port < 1 || port > 65535) {
    throw new Error(`Invalid PORT: ${value}. Must be between 1 and 65535.`);
  }
  return port;
}

export const config = {
  port: parsePort(process.env.PORT),
  isProduction,

  // Security - required in production
  jwtSecret: requireEnv('JWT_SECRET', isProduction ? undefined : 'dev-secret-change-in-production'),
  apiKey: requireEnv('API_KEY', isProduction ? undefined : ''),

  // Allowlists
  approvedEmails: (process.env.APPROVED_EMAILS || '').split(',').map(e => e.trim().toLowerCase()).filter(Boolean),
  approvedAppleIds: (process.env.APPROVED_APPLE_IDS || '').split(',').map(id => id.trim()).filter(Boolean),

  // Apple configuration
  appleTeamId: process.env.APPLE_TEAM_ID || '',
  appleBundleId: process.env.APPLE_BUNDLE_ID || 'com.ovrlrd.app',
  apnsKeyId: process.env.APNS_KEY_ID || '',
  apnsKeyPath: process.env.APNS_KEY_PATH || './apns-key.p8',

  // Paths
  dbPath: process.env.DB_PATH || './ovrlrd.db',
  claudePath: process.env.CLAUDE_PATH || 'claude',
  logPath: process.env.LOG_PATH || './debug.log',

  // Claude CLI settings
  claudeWorkDir: process.env.CLAUDE_WORK_DIR || process.env.HOME || '/',
  claudeAdditionalDirs: (process.env.CLAUDE_ADDITIONAL_DIRS || '').split(':').filter(Boolean),

  // CORS - configure allowed origins
  corsOrigins: (process.env.CORS_ORIGINS || '').split(',').map(o => o.trim()).filter(Boolean),
} as const;
