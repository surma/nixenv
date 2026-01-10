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
  --openrouter-models: string    # JSON array of OpenRouter model IDs (optional)
  --client-key-file: path        # Path to client API key file (optional, for authentication)
  --database-host: string        # PostgreSQL host
  --database-port: int           # PostgreSQL port
  --database-name: string        # PostgreSQL database name
  --database-user: string        # PostgreSQL user
  --database-password-file: path # Path to PostgreSQL password file
  --master-key-file: path        # Path to master key file
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

  # OpenRouter provider (static model list)
  if $openrouter_key_file != null and ($openrouter_key_file | path exists) {
    let key = open $openrouter_key_file | str trim
    if ($key | str length) > 0 {
      let models_list = if $openrouter_models != null { $openrouter_models | from json } else { [] }
      if ($models_list | is-not-empty) {
        print $"Configuring ($models_list | length) OpenRouter models"
        $providers = $providers | insert openrouter {
          prefix: "openrouter/"
          models: ($models_list | each {|id| {id: $id}})
          key: $key
          extra: {
            api_base: "https://openrouter.ai/api/v1"
          }
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

  # Read database password if configured
  mut database_url = null
  if $database_password_file != null and ($database_password_file | path exists) {
    let db_password = open $database_password_file | str trim
    if ($db_password | str length) > 0 {
      print $"Database configuration enabled for ($database_host):($database_port)/($database_name)"
      $database_url = $"postgresql://($database_user):($db_password)@($database_host):($database_port)/($database_name)?sslmode=disable"
    } else {
      print "Warning: Database password file is empty"
    }
  }

  # Read master key if configured
  mut master_key = null
  if $master_key_file != null and ($master_key_file | path exists) {
    $master_key = open $master_key_file | str trim
    if ($master_key | str length) > 0 {
      print "Master key configured for virtual key management"
    } else {
      print "Warning: Master key file is empty"
    }
  }

  # Read client key if configured (for backward compatibility)
  mut client_key = null
  if $client_key_file != null and ($client_key_file | path exists) {
    $client_key = open $client_key_file | str trim
    if ($client_key | str length) > 0 {
      print "Client authentication enabled (legacy mode)"
    } else {
      print "Warning: Client key file is empty"
    }
  }

  # Add general_settings if database, master key, or client key is configured
  if $database_url != null or $master_key != null or $client_key != null {
    mut general_settings = {}
    
    if $database_url != null {
      $general_settings = $general_settings | insert database_url $database_url
    }
    
    if $master_key != null {
      $general_settings = $general_settings | insert master_key $master_key
    } else if $client_key != null {
      # Use client key as master key if no dedicated master key is set (backward compatibility)
      $general_settings = $general_settings | insert master_key $client_key
    }
    
    $litellm_config = $litellm_config | insert general_settings $general_settings
  }

  print $"Writing config with ($model_list | length) models to ($config)"
  $litellm_config | to yaml | better_save $config

  # Execute litellm
  print $"Starting LiteLLM on port ($port)..."
  exec $litellm --config $config --port ($port | into string)
}
