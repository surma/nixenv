# WireGuard VPN Infrastructure Plan

## Overview

This document outlines the complete architecture and implementation plan for a WireGuard-based VPN across all machines in this nixenv repository. The VPN will provide secure, encrypted connectivity between all machines (NixOS, Darwin, and home-manager standalone) with centralized management through Nix configuration.

## Architecture Goals

### Primary Objectives

1. **Universal Coverage**: All machines get WireGuard configured automatically
2. **Secrets Management**: All private keys managed through existing age-encrypted secrets infrastructure
3. **Central Gateway**: Pylon acts as the VPN entrypoint/hub for hub-and-spoke topology
4. **DNS Resolution**: Pylon runs DNS server resolving hostnames to VPN internal IPs
5. **Static IP Assignment**: Each machine gets a permanent IP from 10.137.0.0/16 subnet
6. **Automatic IP Allocation**: IPs implicitly distributed by order in secrets file (with manual override capability)
7. **Cross-Platform**: Support NixOS, nix-darwin, and home-manager
8. **Mobile Support**: Generate configs for non-Nix devices (phones, tablets)
9. **Declarative**: Entire VPN configuration in Nix, no manual intervention

### Network Topology

```
Internet
    |
    v
┌─────────────────┐
│  Pylon (Gateway)│  - Public IP: pylon.surma.link
│  10.137.0.X     │  - WireGuard port: 51820
│  DNS Server     │  - DNS domain: vpn.surma.link
└────────┬────────┘
         │
    Hub-and-Spoke
         │
    ┌────┴─────┬──────────┬──────────┬─────────┐
    │          │          │          │         │
┌───v────┐ ┌──v─────┐ ┌──v─────┐ ┌──v─────┐ ┌v────────┐
│ Nexus  │ │ Archon │ │Dragoon │ │Surmrock│ │  Phone  │
│10.137.X│ │10.137.X│ │10.137.X│ │10.137.X│ │10.137.X │
└────────┘ └────────┘ └────────┘ └────────┘ └─────────┘
```

**Topology Type**: Hub-and-Spoke
- All VPN traffic routes through pylon
- Simpler configuration, easier debugging
- Works well with NAT and dynamic IPs
- Pylon acts as single point of ingress/egress

**Traffic Routing**: VPN Subnet Only
- Only 10.137.0.0/16 traffic uses the VPN tunnel
- Internet traffic stays on regular connections
- AllowedIPs = 10.137.0.0/16 (not 0.0.0.0/0)

## IP Address Assignment Strategy

### Source of Truth

The **canonical source** for machine ordering is `secrets/config.nix`, specifically the `keys` attribute set. This ensures:

- **Stability**: New machines are always added at the end of the keys list
- **No reordering**: Existing machines never change IPs when new ones are added
- **Single source of truth**: Same file that manages encryption keys also determines IP order
- **Manual override**: Any machine can override its auto-assigned IP if needed

### IP Assignment Algorithm

```nix
# Read secrets/config.nix
let
  secretsConfig = import ./secrets/config.nix;
  
  # Extract machines in order (preserves attribute order as defined in file)
  allMachines = builtins.attrNames secretsConfig.keys;
  # Result: ["surma", "surmbook", "dragoon", "shopisurm", "surmrock", ...]
  
  # Assign IPs sequentially
  # Index starts at 1, so first machine gets 10.137.0.1
  assignedIPs = lib.imap1 (idx: name: {
    inherit name;
    ip = "10.137.0.${toString idx}";
  }) allMachines;
in
  # Generate final registry with override support
  machineRegistry = lib.mapAttrs (name: machineConfig:
    if machineConfig ? ip && machineConfig.ip != null
    then machineConfig.ip  # Use manual override
    else (findIpForMachine name assignedIPs)  # Use auto-assigned
  ) cfg.machines;
```

### IP Ranges

- **10.137.0.1 - 10.137.254.254**: Auto-assigned to machines in secrets/config.nix order
- **10.137.255.0 - 10.137.255.254**: Reserved for manual devices (phones, tablets, etc.)
- **10.137.0.1**: Typically pylon (first in secrets keys), but not required
- **10.137.255.255**: Broadcast address (reserved)

### Example IP Assignments

Based on current `secrets/config.nix` order:

```
surma          -> 10.137.0.1
surmbook       -> 10.137.0.2
dragoon        -> 10.137.0.3
shopisurm      -> 10.137.0.4
surmrock       -> 10.137.0.5
surmedge       -> 10.137.0.6
pylon          -> 10.137.0.7
surmframework  -> 10.137.0.8
archon         -> 10.137.0.9
surmturntable  -> 10.137.0.10
nexus          -> 10.137.0.11
```

**Note**: Adding a new machine "zephyr" to secrets/config.nix would give it 10.137.0.12, and all existing IPs remain unchanged.

## DNS Configuration

### DNS Server (Pylon Only)

Pylon runs a **dnsmasq** instance that:

1. Listens on the WireGuard interface (wg0) only
2. Resolves `*.vpn.surma.link` to internal VPN IPs
3. Forwards other queries to upstream DNS (1.1.1.1, 8.8.8.8)
4. Provides split-horizon DNS (internal view vs external view)

### DNS Records

All machines get DNS entries in the format: `<hostname>.vpn.surma.link`

```
pylon.vpn.surma.link      -> 10.137.0.7
nexus.vpn.surma.link      -> 10.137.0.11
archon.vpn.surma.link     -> 10.137.0.9
dragoon.vpn.surma.link    -> 10.137.0.3
surmrock.vpn.surma.link   -> 10.137.0.5
# ... etc for all machines
```

### Using Public Domain

**Q: Is it a problem to use an actual public domain like vpn.surma.link?**

**A**: No, it's actually recommended! Here's why:

#### Advantages:
1. **Real TLS certificates**: Can get Let's Encrypt certs for internal services
2. **No .local conflicts**: Avoids mDNS/.local domain issues
3. **Split-horizon DNS**: Different answers for internal vs external queries
4. **Professional**: Looks cleaner than .internal/.local TLDs

#### How It Works:

**Internal DNS (on VPN)**:
- Query from VPN client: `nexus.vpn.surma.link` → `10.137.0.11` (internal IP)
- Resolved by pylon's dnsmasq server

**External DNS (public)**:
- Query from internet: `vpn.surma.link` → No record (or pylon's public IP if desired)
- Subdomain `*.vpn.surma.link` doesn't need public DNS records
- Only VPN clients can resolve these names

#### Implementation:
```nix
# On pylon
services.dnsmasq = {
  enable = true;
  settings = {
    interface = "wg0";           # Only listen on VPN interface
    bind-interfaces = true;      # Don't leak to public internet
    
    # Internal DNS records
    address = [
      "/pylon.vpn.surma.link/10.137.0.7"
      "/nexus.vpn.surma.link/10.137.0.11"
      # ... generated for all machines
    ];
    
    # Upstream for non-VPN queries
    server = ["1.1.1.1" "8.8.8.8"];
  };
};
```

### Client DNS Configuration

All VPN clients configure pylon as their DNS server (for VPN subnet only):

```nix
# In WireGuard client config
[Interface]
DNS = 10.137.0.7  # Pylon's VPN IP

# This sets DNS server ONLY for queries related to VPN
# Regular internet DNS stays unchanged
```

## WireGuard Cryptography & Secrets

### Public Key Cryptography (No Shared Secrets!)

WireGuard uses **Curve25519** for key exchange - each machine has:

1. **Private Key** (secret): Stays on the machine, never transmitted
2. **Public Key** (public): Shared with all peers, identifies the machine

**No PKI, No Certificates, No Shared Secrets Required!**

This is simpler than traditional VPNs (OpenVPN, IPSec) because:
- No certificate authority needed
- No certificate expiration/renewal
- No pre-shared keys to rotate
- Each machine authenticates using its public key

### Key Generation Process

Each machine needs a WireGuard key pair generated once during initial setup:

```bash
# Generate private key
wg genkey > privatekey

# Derive public key from private key
wg pubkey < privatekey > publickey
```

**Security Model**:
- Private key: Encrypted with age, stored in `assets/wireguard/<machine>-privatekey.age`
- Public key: Stored in plaintext in `modules/services/wireguard-vpn/public-keys.nix`

### Secrets File Structure

Each machine's private key is added to `secrets/config.nix`:

```nix
{
  keys = {
    # Existing keys...
    pylon = "ssh-ed25519 AAAAC3...";
    nexus = "ssh-ed25519 AAAAC3...";
    # etc.
  };
  
  secrets = {
    # Existing secrets...
    
    # WireGuard private keys (one per machine)
    wireguard-pylon-privatekey = {
      contents = ../assets/wireguard/pylon-privatekey.age;
      keys = ["surma", "pylon"];  # Only pylon (and surma for recovery) can decrypt
    };
    
    wireguard-nexus-privatekey = {
      contents = ../assets/wireguard/nexus-privatekey.age;
      keys = ["surma", "nexus"];
    };
    
    wireguard-archon-privatekey = {
      contents = ../assets/wireguard/archon-privatekey.age;
      keys = ["surma", "archon"];
    };
    
    # ... one for each machine
  };
}
```

### Public Keys Registry

Public keys are stored in version control (they're public!):

```nix
# modules/services/wireguard-vpn/public-keys.nix
{
  pylon = "base64encodedpublickey1234567890abcdef...";
  nexus = "base64encodedpublickey0987654321fedcba...";
  archon = "base64encodedpublickey1111222233334444...";
  dragoon = "base64encodedpublickeymacOSversion...";
  # ... etc for all machines
}
```

### Secret Deployment

Using the existing secrets infrastructure, each machine decrypts its private key:

```nix
# In machines/pylon/default.nix
secrets.items.wireguard-privatekey = {
  target = "/var/lib/wireguard/privatekey";
  mode = "0600";  # Readable only by root
};

# The secrets activation script (already exists) will:
# 1. Decrypt assets/wireguard/pylon-privatekey.age using /home/surma/.ssh/id_machine
# 2. Write decrypted key to /var/lib/wireguard/privatekey
# 3. Set permissions to 0600
```

## Module Structure

### File Organization

```
modules/services/wireguard-vpn/
├── default.nix              # Main module with options and orchestration
├── registry.nix             # Machine registry and IP assignment logic
├── dns.nix                  # DNS server configuration (dnsmasq)
├── public-keys.nix          # Public keys for all machines (version controlled)
└── backends/
    ├── nixos.nix            # NixOS-specific implementation
    ├── darwin.nix           # nix-darwin implementation
    └── home-manager.nix     # home-manager standalone implementation

assets/wireguard/            # Age-encrypted private keys
├── pylon-privatekey.age
├── nexus-privatekey.age
├── archon-privatekey.age
├── dragoon-privatekey.age
└── ... (one per machine)

packages/wireguard-vpn/
└── default.nix              # CLI tool for key generation and config export
```

### Module Options Design

The main module (`modules/services/wireguard-vpn/default.nix`) provides these options:

```nix
{ config, lib, pkgs, ... }:

{
  options.services.wireguard-vpn = {
    enable = lib.mkEnableOption "WireGuard VPN mesh network";
    
    thisHost = lib.mkOption {
      type = lib.types.str;
      description = ''
        Hostname of this machine. Must match a key in secrets/config.nix.
        Used to look up IP address, public key, and configure peer connections.
      '';
      example = "pylon";
    };
    
    port = lib.mkOption {
      type = lib.types.port;
      default = 51820;
      description = ''
        UDP port for WireGuard to listen on.
        Easily configurable per-machine if needed.
      '';
    };
    
    interface = lib.mkOption {
      type = lib.types.str;
      default = "wg0";
      description = "Name of the WireGuard network interface";
    };
    
    subnet = lib.mkOption {
      type = lib.types.str;
      default = "10.137.0.0/16";
      description = "VPN subnet in CIDR notation";
    };
    
    gateway = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "pylon";
        description = "Hostname of the gateway machine (hub in hub-and-spoke)";
      };
      
      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "pylon.surma.link:51820";
        description = ''
          Public endpoint of the gateway machine.
          Format: "hostname:port" or "ip:port"
          Used by clients to connect to the VPN hub.
        '';
      };
    };
    
    dns = {
      enable = lib.mkEnableOption "DNS server for VPN" // {
        description = ''
          Run a DNS server for the VPN network.
          Should only be enabled on the gateway machine (pylon).
        '';
      };
      
      domain = lib.mkOption {
        type = lib.types.str;
        default = "vpn.surma.link";
        description = "DNS domain for VPN hostnames";
      };
      
      upstreamServers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["1.1.1.1" "8.8.8.8"];
        description = "Upstream DNS servers for non-VPN queries";
      };
    };
    
    machines = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          ip = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              Override the auto-assigned IP address.
              If null, IP is auto-assigned based on position in secrets/config.nix.
            '';
            example = "10.137.0.1";
          };
          
          publicKey = lib.mkOption {
            type = lib.types.str;
            description = "WireGuard public key for this machine";
            example = "base64encodedpublickey1234567890...";
          };
          
          endpoint = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              Public endpoint for this machine (if it's reachable from internet).
              Only needed for machines that act as gateways/servers.
              Format: "hostname:port" or "ip:port"
            '';
            example = "pylon.surma.link:51820";
          };
          
          persistentKeepalive = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null;
            description = ''
              Send keepalive packets every N seconds.
              Useful for machines behind NAT to keep connection alive.
              Set to 25 for mobile devices or NAT traversal.
            '';
            example = 25;
          };
        };
      });
      description = ''
        Registry of all machines in the VPN.
        Automatically populated from public-keys.nix and secrets/config.nix.
        Can be extended or overridden per-machine.
      '';
    };
    
    privateKeyFile = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/wireguard/privatekey";
      description = ''
        Path to the WireGuard private key file.
        Should be set by secrets.items.wireguard-privatekey.target
      '';
    };
    
    extraAllowedIPs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        Additional IP ranges to route through VPN.
        By default, only the VPN subnet (10.137.0.0/16) is routed.
        Add "0.0.0.0/0" to route all traffic through VPN.
      '';
      example = ["192.168.1.0/24"];
    };
  };
  
  # Implementation goes here (config = { ... })
}
```

### Registry Module (`registry.nix`)

This module handles the core logic of IP assignment and machine discovery:

```nix
{ lib, ... }:

let
  # Import secrets to get canonical machine order
  secretsConfig = import ../../../secrets/config.nix;
  
  # Import public keys registry
  publicKeys = import ./public-keys.nix;
  
  # Extract machine names in order from secrets file
  machineNames = builtins.attrNames secretsConfig.keys;
  
  # Auto-assign IPs based on position in secrets file
  # Index starts at 1, so first machine gets .1, second gets .2, etc.
  autoAssignedIPs = lib.imap1 (idx: name: {
    inherit name;
    ip = "10.137.0.${toString idx}";
  }) machineNames;
  
  # Convert list to attrset for easy lookup
  ipByMachine = builtins.listToAttrs (map (m: {
    name = m.name;
    value = m.ip;
  }) autoAssignedIPs);
  
  # Build machine registry with public keys and auto-assigned IPs
  buildMachineRegistry = overrides:
    lib.mapAttrs (name: publicKey:
      let
        autoIP = ipByMachine.${name} or null;
        override = overrides.${name} or {};
      in
      {
        publicKey = publicKey;
        ip = override.ip or autoIP;
        endpoint = override.endpoint or null;
        persistentKeepalive = override.persistentKeepalive or null;
      }
    ) publicKeys;
    
in
{
  # Export the registry builder
  inherit buildMachineRegistry ipByMachine machineNames;
  
  # Helper function to get this machine's IP
  getThisIP = thisHost: overrides:
    let
      override = overrides.${thisHost} or {};
    in
    override.ip or ipByMachine.${thisHost};
    
  # Helper to generate peer configurations
  generatePeers = thisHost: machineRegistry: gatewayHost:
    let
      # Filter out this machine from peers
      allPeers = lib.filterAttrs (name: _: name != thisHost) machineRegistry;
      
      # Generate WireGuard peer config for each machine
      makePeer = name: machine: {
        publicKey = machine.publicKey;
        allowedIPs = [ "${machine.ip}/32" ];
        endpoint = lib.mkIf (machine.endpoint != null) machine.endpoint;
        persistentKeepalive = lib.mkIf (machine.persistentKeepalive != null) machine.persistentKeepalive;
      };
    in
    lib.mapAttrsToList makePeer allPeers;
}
```

### DNS Module (`dns.nix`)

Handles DNS server configuration for pylon:

```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.services.wireguard-vpn;
  
  # Generate dnsmasq address entries for all machines
  generateDnsRecords = machines: domain:
    lib.mapAttrsToList (name: machine:
      "/${name}.${domain}/${machine.ip}"
    ) machines;
    
in
{
  config = lib.mkIf (cfg.enable && cfg.dns.enable) {
    # Install dnsmasq
    services.dnsmasq = {
      enable = true;
      
      settings = {
        # Listen only on WireGuard interface
        interface = cfg.interface;
        bind-interfaces = true;
        
        # Don't read /etc/hosts
        no-hosts = true;
        
        # Don't read /etc/resolv.conf
        no-resolv = true;
        
        # DNS records for all VPN machines
        address = generateDnsRecords cfg.machines cfg.dns.domain;
        
        # Upstream DNS servers for non-VPN queries
        server = cfg.dns.upstreamServers;
        
        # Cache size
        cache-size = 1000;
        
        # Enable logging (optional, for debugging)
        # log-queries = true;
        # log-facility = "/var/log/dnsmasq.log";
      };
    };
    
    # Firewall: Allow DNS on WireGuard interface
    networking.firewall.interfaces.${cfg.interface}.allowedTCPPorts = [ 53 ];
    networking.firewall.interfaces.${cfg.interface}.allowedUDPPorts = [ 53 ];
  };
}
```

### Platform-Specific Backends

#### NixOS Backend (`backends/nixos.nix`)

```nix
{ config, lib, pkgs, systemManager, ... }:

let
  cfg = config.services.wireguard-vpn;
  registry = import ../registry.nix { inherit lib; };
  
  # Get this machine's IP
  thisIP = registry.getThisIP cfg.thisHost cfg.machines;
  
  # Build full machine registry
  machineRegistry = registry.buildMachineRegistry cfg.machines;
  
  # Is this machine the gateway?
  isGateway = cfg.thisHost == cfg.gateway.host;
  
  # Generate peer configurations
  peers = registry.generatePeers cfg.thisHost machineRegistry cfg.gateway.host;
  
in
{
  config = lib.mkIf (cfg.enable && systemManager == "nixos") {
    # Configure WireGuard interface using NixOS native options
    networking.wireguard.interfaces.${cfg.interface} = {
      # Interface IP address with /16 subnet
      ips = [ "${thisIP}/16" ];
      
      # Listen port
      listenPort = cfg.port;
      
      # Private key file (decrypted by secrets system)
      privateKeyFile = cfg.privateKeyFile;
      
      # Peer configurations
      peers = peers;
      
      # MTU optimization (optional)
      # mtu = 1420;
    };
    
    # Firewall configuration
    networking.firewall = {
      # Allow WireGuard port (UDP) if this is the gateway
      allowedUDPPorts = lib.mkIf isGateway [ cfg.port ];
      
      # Allow forwarding if gateway
      extraCommands = lib.mkIf isGateway ''
        # Enable IP forwarding for VPN subnet
        iptables -A FORWARD -i ${cfg.interface} -j ACCEPT
        iptables -A FORWARD -o ${cfg.interface} -j ACCEPT
      '';
    };
    
    # Enable IP forwarding if gateway
    boot.kernel.sysctl = lib.mkIf isGateway {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };
    
    # Set DNS to point to gateway for VPN queries
    networking.resolvconf.extraConfig = lib.mkIf (!isGateway) ''
      # Use VPN gateway for *.vpn.surma.link queries
      name_servers="${machineRegistry.${cfg.gateway.host}.ip}"
    '';
  };
}
```

#### Darwin Backend (`backends/darwin.nix`)

macOS doesn't have native WireGuard kernel module in NixOS sense, so we use wireguard-tools:

```nix
{ config, lib, pkgs, systemManager, ... }:

let
  cfg = config.services.wireguard-vpn;
  registry = import ../registry.nix { inherit lib; };
  
  thisIP = registry.getThisIP cfg.thisHost cfg.machines;
  machineRegistry = registry.buildMachineRegistry cfg.machines;
  peers = registry.generatePeers cfg.thisHost machineRegistry cfg.gateway.host;
  isGateway = cfg.thisHost == cfg.gateway.host;
  
  # Generate WireGuard config file
  wgConfig = pkgs.writeText "wg0.conf" ''
    [Interface]
    PrivateKey = $(cat ${cfg.privateKeyFile})
    Address = ${thisIP}/16
    ListenPort = ${toString cfg.port}
    ${lib.optionalString (!isGateway) "DNS = ${machineRegistry.${cfg.gateway.host}.ip}"}
    
    ${lib.concatMapStringsSep "\n\n" (peer: ''
      [Peer]
      PublicKey = ${peer.publicKey}
      AllowedIPs = ${lib.concatStringsSep ", " peer.allowedIPs}
      ${lib.optionalString (peer ? endpoint && peer.endpoint != null) "Endpoint = ${peer.endpoint}"}
      ${lib.optionalString (peer ? persistentKeepalive && peer.persistentKeepalive != null) "PersistentKeepalive = ${toString peer.persistentKeepalive}"}
    '') peers}
  '';
  
  # Script to bring up WireGuard
  wgUp = pkgs.writeShellScript "wg-up" ''
    set -e
    
    # Load config (expands PrivateKey from file)
    ${pkgs.wireguard-tools}/bin/wg-quick up ${wgConfig}
  '';
  
  # Script to bring down WireGuard
  wgDown = pkgs.writeShellScript "wg-down" ''
    ${pkgs.wireguard-tools}/bin/wg-quick down ${cfg.interface} || true
  '';
  
in
{
  config = lib.mkIf (cfg.enable && systemManager == "nix-darwin") {
    # Install wireguard-tools
    environment.systemPackages = [ pkgs.wireguard-tools ];
    
    # Create launchd service
    launchd.daemons.wireguard-wg0 = {
      serviceConfig = {
        Label = "org.wireguard.wg0";
        ProgramArguments = [ "${wgUp}" ];
        RunAtLoad = true;
        KeepAlive = {
          NetworkState = true;
        };
        StandardOutPath = "/var/log/wireguard-wg0.log";
        StandardErrorPath = "/var/log/wireguard-wg0-error.log";
      };
    };
    
    # Firewall (if using pf on macOS)
    # Note: macOS firewall configuration is more complex
    # May need manual configuration or different approach
    
    # TODO: Investigate nix-darwin firewall options
    # or provide instructions for manual pf.conf setup
  };
}
```

**Note**: Darwin support is more complex due to:
- No native WireGuard kernel module (uses userspace wireguard-go)
- Different firewall system (pf instead of nftables/iptables)
- May require some manual setup or additional nix-darwin modules

#### Home-Manager Backend (`backends/home-manager.nix`)

For standalone home-manager (non-NixOS Linux systems):

```nix
{ config, lib, pkgs, systemManager, ... }:

let
  cfg = config.services.wireguard-vpn;
  registry = import ../registry.nix { inherit lib; };
  
  thisIP = registry.getThisIP cfg.thisHost cfg.machines;
  machineRegistry = registry.buildMachineRegistry cfg.machines;
  peers = registry.generatePeers cfg.thisHost machineRegistry cfg.gateway.host;
  isGateway = cfg.thisHost == cfg.gateway.host;
  
  # Generate WireGuard config file
  wgConfig = pkgs.writeText "wg0.conf" ''
    [Interface]
    PrivateKey = $(cat ${cfg.privateKeyFile})
    Address = ${thisIP}/16
    ListenPort = ${toString cfg.port}
    ${lib.optionalString (!isGateway) "DNS = ${machineRegistry.${cfg.gateway.host}.ip}"}
    
    ${lib.concatMapStringsSep "\n\n" (peer: ''
      [Peer]
      PublicKey = ${peer.publicKey}
      AllowedIPs = ${lib.concatStringsSep ", " peer.allowedIPs}
      ${lib.optionalString (peer ? endpoint && peer.endpoint != null) "Endpoint = ${peer.endpoint}"}
      ${lib.optionalString (peer ? persistentKeepalive && peer.persistentKeepalive != null) "PersistentKeepalive = ${toString peer.persistentKeepalive}"}
    '') peers}
  '';
  
in
{
  config = lib.mkIf (cfg.enable && systemManager == "home-manager") {
    # Install wireguard-tools
    home.packages = [ pkgs.wireguard-tools ];
    
    # Create systemd user service
    systemd.user.services.wireguard-wg0 = {
      Unit = {
        Description = "WireGuard VPN Tunnel - wg0";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.wireguard-tools}/bin/wg-quick up ${wgConfig}";
        ExecStop = "${pkgs.wireguard-tools}/bin/wg-quick down ${cfg.interface}";
      };
      
      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}
```

**Note**: Home-manager backend requires:
- `wireguard-tools` package installed
- User must have sudo permissions to configure network interfaces
- May need to add user to sudoers for `wg-quick` without password
- Alternative: Provide instructions to set up system-wide WireGuard service

## Per-Machine Configuration

### Gateway Machine (Pylon)

```nix
# machines/pylon/default.nix
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    # ... existing imports
  ];
  
  # Enable WireGuard VPN
  services.wireguard-vpn = {
    enable = true;
    thisHost = "pylon";
    
    # Gateway-specific configuration
    gateway.endpoint = "pylon.surma.link:51820";  # Public endpoint
    
    # Enable DNS server
    dns.enable = true;
    dns.domain = "vpn.surma.link";
    
    # Optional: Override auto-assigned IP to ensure pylon is always .1
    machines.pylon.ip = "10.137.0.1";
  };
  
  # Decrypt WireGuard private key
  secrets.items.wireguard-privatekey = {
    target = "/var/lib/wireguard/privatekey";
    mode = "0600";
  };
  
  # Firewall: Allow WireGuard port from internet
  networking.firewall.allowedUDPPorts = [ 51820 ];
  
  # Optional: Enable connection tracking for better performance
  networking.firewall.connectionTrackingModules = [ "nf_conntrack_pptp" ];
  
  # ... rest of pylon config
}
```

### Client Machine (Nexus - NixOS)

```nix
# machines/nexus/default.nix
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  imports = [
    # ... existing imports
  ];
  
  # Enable WireGuard VPN
  services.wireguard-vpn = {
    enable = true;
    thisHost = "nexus";
    
    # Optional: Enable persistent keepalive if behind NAT
    machines.nexus.persistentKeepalive = 25;
  };
  
  # Decrypt WireGuard private key
  secrets.items.wireguard-privatekey = {
    target = "/var/lib/wireguard/privatekey";
    mode = "0600";
  };
  
  # ... rest of nexus config
}
```

### Client Machine (Dragoon - Darwin)

```nix
# machines/dragoon/default.nix
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  imports = [
    # ... existing imports
  ];
  
  # Enable WireGuard VPN
  services.wireguard-vpn = {
    enable = true;
    thisHost = "dragoon";
    
    # macOS laptops often on the move, use keepalive
    machines.dragoon.persistentKeepalive = 25;
  };
  
  # Decrypt WireGuard private key
  secrets.items.wireguard-privatekey = {
    target = "/var/lib/wireguard/privatekey";
    mode = "0600";
  };
  
  # ... rest of dragoon config
}
```

### Client Machine (Surmturntable - Home-Manager)

```nix
# machines/surmturntable/home.nix
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  imports = [
    # ... existing imports
  ];
  
  # Enable WireGuard VPN
  services.wireguard-vpn = {
    enable = true;
    thisHost = "surmturntable";
    
    machines.surmturntable.persistentKeepalive = 25;
  };
  
  # Decrypt WireGuard private key
  secrets.items.wireguard-privatekey = {
    target = "/var/lib/wireguard/privatekey";
    mode = "0600";
  };
  
  # ... rest of home.nix config
}
```

**Note**: For home-manager, user needs sudo access for `wg-quick`. Alternative approach:
- Set up system-wide WireGuard service (outside home-manager)
- Or configure sudoers to allow `wg-quick` without password for specific user

## Mobile Device Support

For non-Nix devices (phones, tablets, IoT devices), we need a way to generate WireGuard configurations manually.

### CLI Tool for Config Generation

Create a Nix package that provides a CLI tool:

```nix
# packages/wireguard-vpn/default.nix
{ pkgs, lib, ... }:

pkgs.writeShellApplication {
  name = "wireguard-vpn-admin";
  
  runtimeInputs = with pkgs; [
    wireguard-tools
    qrencode
    age
  ];
  
  text = ''
    # Admin tool for WireGuard VPN management
    
    case "''${1:-help}" in
      generate-keys)
        # Generate keys for all machines in secrets/config.nix
        echo "Generating WireGuard keys for all machines..."
        # Implementation here
        ;;
        
      add-device)
        # Add a mobile device to the VPN
        DEVICE_NAME="''${2:-}"
        if [ -z "$DEVICE_NAME" ]; then
          echo "Usage: wireguard-vpn-admin add-device <device-name>"
          exit 1
        fi
        
        echo "Generating configuration for device: $DEVICE_NAME"
        # Implementation here
        ;;
        
      show-config)
        # Show config for a specific machine
        MACHINE="''${2:-}"
        if [ -z "$MACHINE" ]; then
          echo "Usage: wireguard-vpn-admin show-config <machine-name>"
          exit 1
        fi
        
        echo "Configuration for $MACHINE:"
        # Implementation here
        ;;
        
      list-machines)
        # List all machines and their IPs
        echo "VPN Machines:"
        # Implementation here
        ;;
        
      *)
        echo "WireGuard VPN Admin Tool"
        echo ""
        echo "Commands:"
        echo "  generate-keys           Generate keys for all machines"
        echo "  add-device <name>       Add a mobile/manual device"
        echo "  show-config <machine>   Show config for a machine"
        echo "  list-machines           List all machines and IPs"
        ;;
    esac
  '';
}
```

### Adding a Mobile Device

Workflow for adding a phone:

```bash
# Generate config for a device named "iphone-surma"
nix run .#wireguard-vpn-admin -- add-device iphone-surma

# Output:
# Generated configuration for device: iphone-surma
# IP Address: 10.137.255.1
# 
# Scan this QR code with WireGuard mobile app:
# [QR code displayed in terminal]
#
# Or manually configure with this config:
# Config saved to: ./wireguard-configs/iphone-surma.conf
```

### Mobile Device Config Format

```ini
[Interface]
PrivateKey = <generated-private-key>
Address = 10.137.255.1/16
DNS = 10.137.0.1

[Peer]
PublicKey = <pylon-public-key>
Endpoint = pylon.surma.link:51820
AllowedIPs = 10.137.0.0/16
PersistentKeepalive = 25
```

### Mobile Device Registry

Store mobile device public keys separately:

```nix
# modules/services/wireguard-vpn/mobile-devices.nix
{
  iphone-surma = {
    publicKey = "base64publickey...";
    ip = "10.137.255.1";
  };
  
  android-phone = {
    publicKey = "base64publickey...";
    ip = "10.137.255.2";
  };
  
  # etc.
}
```

Import this in the main module so gateway (pylon) includes these devices as peers.

## Initial Setup Procedure

### 1. Generate Keys for All Machines

```bash
# Run the key generation tool
nix run .#wireguard-vpn-admin -- generate-keys

# This will:
# 1. Read machine list from secrets/config.nix
# 2. For each machine:
#    a. Generate WireGuard private key
#    b. Derive public key
#    c. Encrypt private key with age for that machine
#    d. Save encrypted key to assets/wireguard/<machine>-privatekey.age
#    e. Output public key
# 3. Generate public-keys.nix with all public keys
```

Example output:
```
Generating keys for machines...

surma:
  Private key encrypted to: assets/wireguard/surma-privatekey.age
  Public key: aBcDeFgHiJkLmNoPqRsTuVwXyZ1234567890=

surmbook:
  Private key encrypted to: assets/wireguard/surmbook-privatekey.age
  Public key: 1234567890aBcDeFgHiJkLmNoPqRsTuVwXyZ=

[... for all machines ...]

Public keys written to: modules/services/wireguard-vpn/public-keys.nix
```

### 2. Update secrets/config.nix

Add WireGuard secret entries:

```nix
secrets = {
  # ... existing secrets ...
  
  # WireGuard private keys
  wireguard-surma-privatekey = {
    contents = ../assets/wireguard/surma-privatekey.age;
    keys = ["surma"];
  };
  wireguard-surmbook-privatekey = {
    contents = ../assets/wireguard/surmbook-privatekey.age;
    keys = ["surma", "surmbook"];
  };
  # ... etc for all machines
};
```

### 3. Commit Public Keys

```bash
git add modules/services/wireguard-vpn/public-keys.nix
git commit -m "Add WireGuard public keys for all machines"
```

### 4. Encrypt and Commit Private Keys

```bash
# Encrypt private keys for each machine using their SSH key
# (The generate-keys tool should do this automatically)

git add assets/wireguard/*.age
git commit -m "Add encrypted WireGuard private keys"
```

### 5. Update Machine Configurations

Add to each machine's `default.nix`:

```nix
services.wireguard-vpn.enable = true;
services.wireguard-vpn.thisHost = "<machine-name>";

secrets.items.wireguard-privatekey = {
  target = "/var/lib/wireguard/privatekey";
  mode = "0600";
};
```

### 6. Configure Gateway (Pylon)

```nix
# machines/pylon/default.nix
services.wireguard-vpn = {
  enable = true;
  thisHost = "pylon";
  gateway.endpoint = "pylon.surma.link:51820";
  dns.enable = true;
};

networking.firewall.allowedUDPPorts = [ 51820 ];
```

### 7. Deploy to Gateway First

```bash
# Deploy pylon configuration
nixos-rebuild switch --flake .#pylon --target-host pylon

# Verify WireGuard is running
ssh pylon "sudo wg show"
```

### 8. Deploy to Client Machines

```bash
# Deploy to each client machine
nixos-rebuild switch --flake .#nexus --target-host nexus
nixos-rebuild switch --flake .#archon --target-host archon

# For Darwin
darwin-rebuild switch --flake .#dragoon

# For home-manager
home-manager switch --flake .#surmturntable
```

### 9. Verify Connectivity

On each machine:

```bash
# Check WireGuard interface is up
ip addr show wg0  # or: ifconfig wg0 on macOS

# Ping gateway through VPN
ping 10.137.0.1

# Ping another machine through VPN
ping 10.137.0.11  # nexus

# Test DNS resolution
dig nexus.vpn.surma.link
ping nexus.vpn.surma.link
```

### 10. Add Mobile Devices (Optional)

```bash
# Generate config for phone
nix run .#wireguard-vpn-admin -- add-device iphone-surma

# Scan QR code with WireGuard app
# Or copy config file to device
```

## Troubleshooting Guide

### Common Issues

#### 1. WireGuard Interface Not Coming Up

**Check**:
```bash
# View WireGuard status
sudo wg show

# Check if interface exists
ip addr show wg0

# Check systemd service (NixOS)
systemctl status wireguard-wg0

# Check logs
journalctl -u wireguard-wg0 -f
```

**Common causes**:
- Private key file not readable (permissions issue)
- Port already in use
- Firewall blocking UDP port

#### 2. Can't Reach Gateway

**Check**:
```bash
# Verify gateway endpoint is reachable
ping pylon.surma.link

# Check if UDP port is open (from client)
nc -u -v pylon.surma.link 51820

# On gateway, check firewall
sudo nft list ruleset | grep 51820
```

**Common causes**:
- Gateway firewall not allowing UDP 51820
- DNS resolution failing for gateway endpoint
- Gateway endpoint wrong (IP changed, domain not updated)

#### 3. Can Reach Gateway But Not Other Peers

**Symptoms**: Can ping 10.137.0.1 but not 10.137.0.11

**Check**:
```bash
# On gateway, verify IP forwarding
sysctl net.ipv4.ip_forward  # Should be 1

# Check iptables rules
sudo iptables -L FORWARD -v

# Verify all peers are configured
sudo wg show
```

**Common causes**:
- IP forwarding not enabled on gateway
- Firewall blocking forwarding
- Peer not actually connected

#### 4. DNS Not Resolving

**Symptoms**: `ping 10.137.0.11` works but `ping nexus.vpn.surma.link` fails

**Check**:
```bash
# Check DNS server is running (on pylon)
systemctl status dnsmasq

# Test DNS directly
dig @10.137.0.1 nexus.vpn.surma.link

# Check DNS configuration on client
cat /etc/resolv.conf
resolvectl status  # systemd-resolved
```

**Common causes**:
- dnsmasq not running on gateway
- Client not configured to use gateway as DNS
- DNS domain mismatch

#### 5. Connection Drops After Some Time

**Symptoms**: VPN works initially but stops after a while, especially on mobile/NAT

**Solution**: Add `PersistentKeepalive = 25` to peer configuration

```nix
services.wireguard-vpn.machines.<machine>.persistentKeepalive = 25;
```

#### 6. macOS/Darwin Issues

**Common issues**:
- Permissions: `wg-quick` needs root access
- Firewall: macOS firewall may block connections
- Route conflicts: Multiple VPN clients can conflict

**Solutions**:
- Ensure wireguard-tools is installed
- May need to manually configure pf firewall
- Check for conflicts with other VPNs (Tailscale, etc.)

### Debug Commands

```bash
# View full WireGuard status
sudo wg show all

# View handshake times (should be recent)
sudo wg show wg0 latest-handshakes

# View transfer statistics
sudo wg show wg0 transfer

# Monitor real-time traffic
watch -n 1 'sudo wg show wg0 transfer'

# Test connectivity to specific peer
ping -I wg0 10.137.0.11

# Trace route through VPN
traceroute -i wg0 10.137.0.11

# Packet capture on WireGuard interface
sudo tcpdump -i wg0 -n
```

## Security Considerations

### Key Management

1. **Private Keys**:
   - Never commit unencrypted private keys
   - Always encrypt with age using machine's SSH key
   - Store in `assets/wireguard/` with `.age` extension
   - Permissions: 0600 (readable only by root)

2. **Public Keys**:
   - Safe to commit to version control
   - Stored in `modules/services/wireguard-vpn/public-keys.nix`
   - Used for peer authentication

3. **Key Rotation**:
   - No automatic rotation (WireGuard keys don't expire)
   - To rotate: Generate new key, update public-keys.nix, redeploy all machines
   - Consider rotating yearly or after compromise

### Network Security

1. **Firewall Rules**:
   - Gateway: Only UDP 51820 exposed to internet
   - Clients: No inbound ports needed (outbound only)
   - VPN subnet: Full access between peers (trust model)

2. **Allowed IPs**:
   - Default: Only 10.137.0.0/16 (VPN subnet)
   - Avoid `0.0.0.0/0` unless you want full tunneling
   - Mobile devices: Consider full tunneling for privacy

3. **DNS Security**:
   - DNS server only listens on WireGuard interface
   - Not exposed to internet
   - DNSSEC validation on upstream queries (optional)

### Access Control

1. **Peer Authorization**:
   - Only machines with public keys in config can connect
   - Remove peer from public-keys.nix to revoke access
   - Redeploy gateway to enforce revocation

2. **Machine Trust**:
   - All VPN peers are trusted (hub-and-spoke model)
   - No segmentation within VPN subnet
   - Consider network segmentation if needed (future enhancement)

3. **Mobile Devices**:
   - Separate IP range (10.137.255.0/24)
   - Easy to identify and manage separately
   - Can be blocked/allowed at firewall level

## Performance Optimization

### MTU Tuning

WireGuard adds overhead, reducing effective MTU:

```nix
networking.wireguard.interfaces.wg0 = {
  # ... other options ...
  mtu = 1420;  # Optimal for most networks
};
```

**Calculation**: Standard MTU (1500) - WireGuard overhead (80) = 1420

### Persistent Keepalive

Trade-off between battery life and connection stability:

- **Don't use** (null): For servers with static IPs
- **25 seconds**: For laptops/mobile devices behind NAT
- **60+ seconds**: For battery-sensitive devices with stable networks

```nix
machines.<machine>.persistentKeepalive = 25;  # or null
```

### Connection Tracking

Enable connection tracking modules for better performance:

```nix
# On gateway (pylon)
networking.firewall.connectionTrackingModules = [ "nf_conntrack" ];
```

### Compression

WireGuard doesn't support compression (by design - security risk). If needed:
- Use application-layer compression (gzip, brotli)
- Or run VPN over compressed transport (not recommended)

## Future Enhancements

### Potential Improvements

1. **Automatic Key Rotation**:
   - Generate new keys periodically
   - Graceful rollover without downtime
   - Automated through CI/CD

2. **Network Segmentation**:
   - Multiple VPN subnets for different trust levels
   - Firewall rules between segments
   - Example: servers vs clients vs mobile

3. **Monitoring & Metrics**:
   - Prometheus exporter for WireGuard stats
   - Grafana dashboards
   - Alert on connection failures

4. **Multi-Gateway Setup**:
   - Multiple gateways for redundancy
   - Automatic failover
   - Geographic distribution

5. **IPv6 Support**:
   - Dual-stack VPN (IPv4 + IPv6)
   - Native IPv6 over WireGuard
   - ULA addresses for internal use

6. **Dynamic Peer Discovery**:
   - Machines discover each other automatically
   - Mesh networking option
   - Direct peer-to-peer when possible

7. **Web Dashboard**:
   - View VPN status via web UI
   - Add/remove mobile devices
   - Monitor connection health

8. **Integration with Existing Services**:
   - Traefik routing via VPN
   - Container networking over VPN
   - Home Assistant over VPN

## References & Documentation

### WireGuard Resources

- Official website: https://www.wireguard.com/
- Protocol whitepaper: https://www.wireguard.com/papers/wireguard.pdf
- Quick start: https://www.wireguard.com/quickstart/

### NixOS Documentation

- WireGuard on NixOS: https://nixos.wiki/wiki/WireGuard
- networking.wireguard options: https://search.nixos.org/options?query=wireguard
- Secrets management: https://nixos.wiki/wiki/Comparison_of_secret_managing_schemes

### Tools Used

- **WireGuard**: VPN protocol and implementation
- **wireguard-tools**: `wg` and `wg-quick` utilities
- **age**: Encryption for private keys
- **dnsmasq**: DNS server for VPN
- **nftables/iptables**: Firewall configuration

### Similar Projects

- Tailscale: Commercial WireGuard-based mesh VPN
- Headscale: Open-source Tailscale control server
- Netbird: Self-hosted WireGuard mesh network
- Nebula: Overlay network from Slack

## Conclusion

This plan provides a complete, declarative WireGuard VPN solution that:

✅ Integrates with existing nixenv infrastructure  
✅ Uses proven secrets management (age encryption)  
✅ Supports all platform types (NixOS, Darwin, home-manager)  
✅ Provides automatic IP assignment with manual override  
✅ Includes DNS resolution for friendly hostnames  
✅ Supports mobile devices  
✅ Scales from small to large deployments  
✅ Maintains security best practices  

The implementation is designed to be:
- **Declarative**: Everything in Nix configuration
- **Reproducible**: Deterministic builds and deployments
- **Maintainable**: Clear module structure, good documentation
- **Secure**: Private keys encrypted, minimal attack surface
- **Extensible**: Easy to add new machines or features

Next steps:
1. Review and approve this plan
2. Implement the core modules
3. Generate initial keys
4. Deploy to gateway (pylon)
5. Roll out to client machines
6. Add mobile devices as needed
