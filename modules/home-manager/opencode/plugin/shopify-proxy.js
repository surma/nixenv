const DEFAULT_PROXY_BASE = "https://vendors.llm.surma.technology";
const GOOGLE_ROUTE =
  "/googlevertexai-global/v1beta1/projects/shopify-ml-production/locations/global/publishers/google";

function trimSlash(value) {
  return value.replace(/\/$/, "");
}

function resolveProxyBase() {
  const envUrl = process.env.OPENCODE_PROXY_BASE_URL ?? process.env.OPENAI_BASE_URL;

  if (envUrl?.startsWith("http")) {
    return trimSlash(envUrl).replace(/\/v1$/, "");
  }

  return DEFAULT_PROXY_BASE;
}

// Matches the format emitted by world's @shopify-internal/opencode-proxy-plugin
// so the proxy attributes traffic as opencode usage:
//   ["opencode", <sessionId>, "rtk:<enabled|disabled>"]
// nixenv has no rtk integration, so the third segment is always "rtk:disabled".
function buildUsageTag(sessionId) {
  return JSON.stringify(["opencode", sessionId, "rtk:disabled"]);
}

function getProviders(proxyBase) {
  return {
    anthropic: `${proxyBase}/apis/anthropic/v1`,
    openai: `${proxyBase}/v1`,
    google: `${proxyBase}${GOOGLE_ROUTE}`,
    groq: `${proxyBase}/groq/openai/v1`,
    xai: `${proxyBase}/xai/v1`,
    cohere: `${proxyBase}/cohere/v2`,
    perplexity: `${proxyBase}/perplexity`,
  };
}

export default async function shopifyProxyPlugin() {
  const sessionId = crypto.randomUUID();

  return {
    async config(config) {
      const token = process.env.OPENCODE_API_KEY?.trim();

      if (!token) {
        throw new Error("OpenCode proxy API key is not configured.");
      }

      const usageTag = buildUsageTag(sessionId);
      const providers = getProviders(resolveProxyBase());

      config.provider ??= {};

      for (const [name, baseURL] of Object.entries(providers)) {
        const existingConfig = config.provider[name] ?? {};
        const existingOptions = existingConfig.options ?? {};

        config.provider[name] = {
          ...existingConfig,
          options: {
            ...existingOptions,
            baseURL,
            apiKey: token,
            headers: {
              ...existingOptions.headers,
              "Shopify-Usage-Tag": usageTag,
              "X-Shopify-Session-Affinity-Header": "opencode-session-id",
              "opencode-session-id": sessionId,
              ...(name === "google" ? { Authorization: `Bearer ${token}` } : {}),
            },
          },
        };
      }

      const existingProviders = config.enabled_providers ?? [];
      config.enabled_providers = [...new Set([...existingProviders, ...Object.keys(providers)])];
    },
  };
}
