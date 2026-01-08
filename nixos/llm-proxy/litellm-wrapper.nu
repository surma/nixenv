#!/usr/bin/env nu

# LiteLLM wrapper script that reads API keys from files and generates config dynamically

def better_save [
  file: string
] {
  mkdir ($file | path parse | get parent)
  $in | save -f $file
}

def main [
  --shopify-key-file: path       # Path to Shopify API key file
  --openrouter-key-file: path    # Path to OpenRouter API key file (optional)
  --client-key-file: path        # Path to client API key file (optional, for authentication)
  --config: path = "/var/lib/llm-proxy/config.yml"  # Output config path
  --port: int = 4000             # LiteLLM port
  --litellm: path                # Path to litellm binary
] {
  mut providers = {}

  # Shopify provider
  if $shopify_key_file != null and ($shopify_key_file | path exists) {
    let key = open $shopify_key_file | str trim
    if ($key | str length) > 0 {
      print "Fetching models from Shopify proxy..."
      let response = http get --full --headers ["Authorization" $"Bearer ($key)"] https://proxy.shopify.ai/v1/models
      let models = $response | get body.data | where id =~ '^(openai|anthropic|google):'
      print $"Found ($models | length) Shopify models"
      $providers = $providers | insert shopify {
        prefix: "openai/"
        models: $models
        key: $key
        extra: {
          api_base: "https://proxy.shopify.ai/v1/"
        }
      }
    } else {
      print "Warning: Shopify key file is empty"
    }
  }

  # OpenRouter provider
  if $openrouter_key_file != null and ($openrouter_key_file | path exists) {
    let key = open $openrouter_key_file | str trim
    if ($key | str length) > 0 {
      print "Fetching models from OpenRouter..."
      let response = http get --full --headers ["Authorization" $"Bearer ($key)"] https://openrouter.ai/api/v1/models
      let models = $response | get body.data
      print $"Found ($models | length) OpenRouter models"
      $providers = $providers | insert openrouter {
        prefix: "openai/"
        models: $models
        key: $key
        extra: {
          api_base: "https://openrouter.ai/api/v1"
        }
      }
    } else {
      print "Warning: OpenRouter key file is empty"
    }
  }

  if ($providers | is-empty) {
    print "No providers configured yet (key files missing or empty), starting with empty model list"
  }

  # Generate LiteLLM config
  let model_list = $providers
    | transpose "name" "config"
    | each {|c|
      $c.config.models
        | each {|m|
          {
            model_name: $"($c.name):($m.id)"
            litellm_params: {
              model: $"($c.config.prefix)($m.id)"
              api_key: $c.config.key
              ...$c.config.extra
            }
          }
        }
    }
    | flatten

  mut litellm_config = {
    model_list: $model_list
  }

  # Add client authentication if configured
  if $client_key_file != null and ($client_key_file | path exists) {
    let client_key = open $client_key_file | str trim
    if ($client_key | str length) > 0 {
      print "Client authentication enabled"
      $litellm_config = $litellm_config | insert general_settings { master_key: $client_key }
    } else {
      print "Warning: Client key file is empty, authentication disabled"
    }
  }

  print $"Writing config with ($model_list | length) models to ($config)"
  $litellm_config | to yaml | better_save $config

  # Execute litellm
  print $"Starting LiteLLM on port ($port)..."
  exec $litellm --config $config --port ($port | into string)
}
