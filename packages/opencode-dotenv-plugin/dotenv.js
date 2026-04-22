import { readFileSync } from "node:fs"
import { join } from "node:path"
import { homedir } from "node:os"

/**
 * Parse a shell-like env file into key-value pairs.
 * Supports:
 *   - KEY=VALUE
 *   - export KEY=VALUE  (export prefix is stripped)
 *   - KEY="quoted value"
 *   - KEY='single quoted value'
 *   - # comments
 *   - Empty lines
 * Does not support multi-line values or variable interpolation.
 */
function parseDotenv(content) {
  const result = {}
  for (const raw of content.split("\n")) {
    let line = raw.trim()
    if (!line || line.startsWith("#")) continue
    // Support shell-style "export KEY=VALUE" lines (e.g. hm-session-vars.sh).
    if (line.startsWith("export ")) line = line.slice(7)
    const eq = line.indexOf("=")
    if (eq === -1) continue
    const key = line.slice(0, eq).trim()
    let value = line.slice(eq + 1).trim()
    // Strip matching quotes
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1)
    }
    result[key] = value
  }
  return result
}

function loadEnvFile(path) {
  try {
    return parseDotenv(readFileSync(path, "utf-8"))
  } catch {
    return {}
  }
}

export const DotenvPlugin = async () => {
  // Load Home Manager session variables once at plugin init.
  // These provide exports like GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE that
  // would normally be sourced by a login shell but aren't available to
  // processes started outside one (e.g. OpenCode's shell tool).
  const hmSessionVars = loadEnvFile(
    join(homedir(), ".nix-profile/etc/profile.d/hm-session-vars.sh"),
  )

  return {
    "shell.env": async (input, output) => {
      // Layer CWD .env files first — they take priority over HM defaults.
      const cwd = input.cwd
      if (cwd) {
        const base = loadEnvFile(join(cwd, ".env"))
        const local = loadEnvFile(join(cwd, ".env.local"))
        const merged = { ...base, ...local }

        for (const [key, value] of Object.entries(merged)) {
          // Don't override variables already set in the process environment.
          if (output.env[key] === undefined) {
            output.env[key] = value
          }
        }
      }

      // Then fill in Home Manager session variables for anything still unset.
      for (const [key, value] of Object.entries(hmSessionVars)) {
        if (output.env[key] === undefined) {
          output.env[key] = value
        }
      }
    },
  }
}
