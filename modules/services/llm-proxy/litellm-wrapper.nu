#!/usr/bin/env nu

# LiteLLM wrapper script that reads API keys from files and generates config dynamically

def better_save [
  file: string
] {
  mkdir ($file | path parse | get parent)
  $in | save -f $file
}

def extract_model_info [
  model: record
  provider: string
] {
  try {
    if $provider == "shopify" {
      # Shopify has nested structure: config.targets[0].targets[0].model_info
      # Try to extract model_info from the first target's first target
      let model_info = try {
        $model | get config | get targets | first | get targets | first | get -o model_info
      } catch {
        null
      }
      
      if $model_info != null {
        let context = $model_info | get -o context_window
        let max_out = $model_info | get -o max_output_tokens
        
        if $context != null and $max_out != null {
          return {
            max_input_tokens: $context        # Total context window
            max_output_tokens: $max_out       # Max completion tokens
            max_tokens: $context              # Legacy field
          }
        }
      }
    } else if $provider == "openrouter" {
      # OpenRouter uses context_length and top_provider.max_completion_tokens
      let context = $model | get -o context_length
      
      if $context != null {
        let max_out = if ($model | get -o top_provider) != null {
          ($model | get top_provider | get -o max_completion_tokens)
        } else {
          null
        }
        
        # If max_completion_tokens is null, use context_length as fallback
        let output_tokens = if $max_out != null { $max_out } else { $context }
        
        return {
          max_input_tokens: $context        # Total context window
          max_output_tokens: $output_tokens # Max completion tokens
          max_tokens: $context              # Legacy field
        }
      }
    }
    
    # If we get here, metadata is missing
    print $"Warning: Missing metadata for ($provider) model: ($model.id)"
    return null
  } catch {
    print $"Warning: Error extracting metadata for ($provider) model: ($model.id)"
    return null
  }
}

def main [
  --shopify-key-file: path       # Path to Shopify API key file
  --openrouter-key-file: path    # Path to OpenRouter API key file (optional)
  --openrouter-models: string    # JSON array of OpenRouter model IDs (optional)
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
      let models_list = if $openrouter_models != null { $openrouter_models | from json } else { [] }
      if ($models_list | is-not-empty) {
        print "Fetching models from OpenRouter API..."
        try {
          let response = http get --full --headers ["Authorization" $"Bearer ($key)"] https://openrouter.ai/api/v1/models
          let all_models = $response | get body.data
          
          # Filter to only models in the static list
          let models = $all_models | where id in $models_list
          
          # Warn about models in static list not found in API
          let found_ids = $models | get id
          let missing = $models_list | where $it not-in $found_ids
          if ($missing | is-not-empty) {
            print $"Warning: OpenRouter models not found in API: ($missing | str join ', ')"
          }
          
          print $"Found ($models | length) OpenRouter models"
          $providers = $providers | insert openrouter {
            prefix: "openrouter/"
            models: $models
            key: $key
            extra: {
              api_base: "https://openrouter.ai/api/v1"
            }
          }
        } catch {
          print "Error: Failed to fetch OpenRouter models, skipping OpenRouter provider"
        }
      } else {
        print "OpenRouter enabled but no models configured, skipping"
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
          let metadata = extract_model_info $m $c.name
          
          mut entry = {
            model_name: $"($c.name):($m.id)"
            litellm_params: {
              model: $"($c.config.prefix)($m.id)"
              api_key: $c.config.key
              ...$c.config.extra
            }
          }
          
          if $metadata != null {
            $entry = $entry | insert model_info $metadata
          }
          
          $entry
        }
    }
    | flatten

  # Count models with/without metadata
  let models_with_metadata = $model_list | where ($it | get -o model_info) != null | length
  let models_without_metadata = $model_list | where ($it | get -o model_info) == null | length

  print $"Models with metadata: ($models_with_metadata)"
  print $"Models without metadata: ($models_without_metadata)"

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
