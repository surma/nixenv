#!/usr/bin/env nu

def log [message: string] {
  print --stderr $message
}

def fetch_key_from_host [
  host: string
  ssh_bin: string
  ssh_user: string
  ssh_identity_file: string
  known_hosts_file: string
  remote_command: string
] {
  log $"Trying shopisurm via ($host)"

  let ssh_result = (
    do { ^$ssh_bin -o BatchMode=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$known_hosts_file -i $ssh_identity_file $"($ssh_user)@($host)" $remote_command } | complete
  )

  if $ssh_result.exit_code != 0 {
    let stderr = ($ssh_result.stderr | str trim)
    log $"SSH failed for ($host): ($stderr)"
    return null
  }

  let key = ($ssh_result.stdout | str trim)
  if $key == "" {
    log $"Received empty key from ($host)"
    return null
  }

  {
    host: $host
    key: $key
  }
}

def main [] {
  let ssh_bin = ($env.KEY_POLLER_SSH_BIN? | default "ssh")
  let curl_bin = ($env.KEY_POLLER_CURL_BIN? | default "curl")
  let jwt_bin = ($env.KEY_POLLER_JWT_BIN? | default "jwt")
  let ssh_user = ($env.KEY_POLLER_SSH_USER? | default "surma")
  let ssh_identity_file = ($env.KEY_POLLER_SSH_IDENTITY_FILE? | default "/home/surma/.ssh/id_machine")
  let known_hosts_file = ($env.KEY_POLLER_KNOWN_HOSTS_FILE? | default "/var/lib/key-poller/known_hosts")
  let receiver_url = ($env.KEY_POLLER_RECEIVER_URL? | default "https://key.llm.surma.technology")
  let secret_file = ($env.KEY_POLLER_SECRET_FILE? | default "/var/lib/key-poller/receiver-secret")
  let remote_nu_bin = ($env.KEY_POLLER_REMOTE_NU_BIN? | default "/etc/profiles/per-user/surma/bin/nu")
  let remote_gcloud_bin = ($env.KEY_POLLER_REMOTE_GCLOUD_BIN? | default "/etc/profiles/per-user/surma/bin/gcloud")
  let ssh_hosts = ($env.KEY_POLLER_SSH_HOSTS_JSON? | default '["10.0.0.20","100.79.232.5"]' | from json)

  mkdir ($known_hosts_file | path dirname)

  let remote_script = ([
    "let token = ("
    $"  ^($remote_gcloud_bin) auth print-identity-token --format json"
    "  | from json"
    "  | get id_token"
    ")"
    ""
    'http post --headers [Authorization $"Bearer ($token)"] https://openai-proxy.shopify.io/hmac/personal'
    "| get key"
  ] | str join "\n")
  let remote_command = $"($remote_nu_bin) -c '($remote_script)'"

  mut fetched = null
  for host in $ssh_hosts {
    let attempt = (fetch_key_from_host $host $ssh_bin $ssh_user $ssh_identity_file $known_hosts_file $remote_command)
    if $attempt != null {
      $fetched = $attempt
      break
    }
  }

  if $fetched == null {
    error make { msg: "Failed to fetch Shopify key from all configured hosts" }
  }

  let fetched = $fetched
  log $"Fetched Shopify key from ($fetched.host)"

  let jwt_result = (
    do {
      ^$jwt_bin encode -S $"@($secret_file)" -e "+5 minutes" '{}'
    } | complete
  )
  if $jwt_result.exit_code != 0 {
    let stderr = ($jwt_result.stderr | str trim)
    error make { msg: $"Failed to generate JWT: ($stderr)" }
  }

  let jwt = ($jwt_result.stdout | str trim)
  if $jwt == "" {
    error make { msg: "Generated empty JWT" }
  }

  let post_result = (
    do { ^$curl_bin -fsS -X POST -H $"Authorization: Bearer ($jwt)" --data-binary $fetched.key $"($receiver_url)/update" } | complete
  )
  if $post_result.exit_code != 0 {
    let stderr = ($post_result.stderr | str trim)
    error make { msg: $"Failed to post key to receiver: ($stderr)" }
  }

  log $"Forwarded Shopify key to ($receiver_url)/update"
}
