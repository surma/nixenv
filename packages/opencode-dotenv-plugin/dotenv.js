import { readFileSync } from "node:fs"
import { join } from "node:path"

/**
 * Parse a .env file into key-value pairs.
 * Supports:
 *   - KEY=VALUE
 *   - KEY="quoted value"
 *   - KEY='single quoted value'
 *   - # comments
 *   - Empty lines
 * Does not support multi-line values or variable interpolation.
 */
function parseDotenv(content) {
  const result = {}
  for (const raw of content.split("\n")) {
    const line = raw.trim()
    if (!line || line.startsWith("#")) continue
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
  return {
    "shell.env": async (input, output) => {
      const cwd = input.cwd
      if (!cwd) return

      // Load .env then .env.local — later values override earlier ones.
      const base = loadEnvFile(join(cwd, ".env"))
      const local = loadEnvFile(join(cwd, ".env.local"))
      const merged = { ...base, ...local }

      for (const [key, value] of Object.entries(merged)) {
        // Don't override variables already set in the environment.
        if (output.env[key] === undefined) {
          output.env[key] = value
        }
      }
    },
  }
}
