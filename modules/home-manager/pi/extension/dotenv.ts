import { readFileSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

/**
 * Parse a shell-like env file into key-value pairs.
 * Supports KEY=VALUE, export KEY=VALUE, quoted values, and comments.
 */
function parseDotenv(content: string): Record<string, string> {
  const result: Record<string, string> = {};
  for (const raw of content.split("\n")) {
    let line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    if (line.startsWith("export ")) line = line.slice(7);
    const eq = line.indexOf("=");
    if (eq === -1) continue;
    const key = line.slice(0, eq).trim();
    let value = line.slice(eq + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    result[key] = value;
  }
  return result;
}

function loadEnvFile(path: string): Record<string, string> {
  try {
    return parseDotenv(readFileSync(path, "utf-8"));
  } catch {
    return {};
  }
}

/**
 * Dotenv extension for pi. Loads .env and .env.local from cwd plus
 * Home Manager session variables, setting them on process.env so that
 * bash tool invocations and brain CLI calls inherit them.
 */
export default function dotenvExtension(pi: ExtensionAPI) {
  // Load Home Manager session variables once at extension init.
  const hmSessionVars = loadEnvFile(
    join(homedir(), ".nix-profile/etc/profile.d/hm-session-vars.sh"),
  );

  // Apply env vars from cwd .env files and HM session vars.
  // CWD .env takes priority, then .env.local, then HM vars.
  // Never overrides variables already set in process.env.
  function applyEnv() {
    const cwd = process.cwd();
    const base = loadEnvFile(join(cwd, ".env"));
    const local = loadEnvFile(join(cwd, ".env.local"));
    const merged = { ...hmSessionVars, ...base, ...local };

    for (const [key, value] of Object.entries(merged)) {
      if (process.env[key] === undefined) {
        process.env[key] = value;
      }
    }
  }

  // Apply on session start so env vars are available immediately.
  pi.on("session_start", async () => {
    applyEnv();
  });

  // Also apply at extension load time for the initial session.
  applyEnv();
}
