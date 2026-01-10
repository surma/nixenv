{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
with lib;
let
  pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.system};
  torrentingPort = 60123;
  giteaPort = 2222;
in
{
  imports = [
    ./hardware.nix
    inputs.nixos-hardware.nixosModules.hardkernel-odroid-h4
    inputs.home-manager.nixosModules.home-manager
    ../../profiles/nixos/base.nix
    ../../modules/services/surmhosting

    ../../modules/secrets

    ../../apps/hate

    ../../modules/home-manager/unfree-apps
  ];

  config = mkMerge [
    {
      nix.settings.require-sigs = false;
      secrets.identity = "/home/surma/.ssh/id_machine";

      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      boot.kernelPackages = pkgs.linuxPackages_latest;

      networking.hostName = "nexus";
      networking.networkmanager.enable = true;
      networking.nftables.enable = true;
      networking.firewall.enable = true;

      environment.systemPackages = with pkgs; [
        smartmontools
        e2fsprogs
      ];

      users.users.surma.linger = true;
      users.groups.podman.members = [ "surma" ];

      users.users.root.openssh.authorizedKeys.keys = with config.secrets.keys; [
        surma
        dragoon
        archon
      ];

      virtualisation.oci-containers.backend = "podman";

      services.tailscale.enable = true;

      services.surmhosting.enable = true;
      services.surmhosting.hostname = "nexus";
      services.surmhosting.containeruser.uid = config.users.users.surma.uid;
      services.surmhosting.externalInterface = "enp2s0";
      services.surmhosting.dashboard.enable = true;
      services.surmhosting.docker.enable = true;

      services.openssh.enable = true;

      system.stateVersion = "25.05";
    }

    {

      secrets.items.nexus-syncthing.target = "/var/lib/syncthing/key.pem";
      services.syncthing.enable = true;
      services.syncthing.user = "surma";
      services.syncthing.dataDir = "/dump/state/syncthing/data";
      services.syncthing.configDir = "/dump/state/syncthing/config";
      services.syncthing.databaseDir = "/dump/state/syncthing/db";
      services.syncthing.cert = ./syncthing/cert.pem |> builtins.toString;
      services.syncthing.key = config.secrets.items.nexus-syncthing.target;
      services.syncthing.settings.folders."audiobooks".path = "/dump/audiobooks";
      services.syncthing.settings.folders."audiobooks".devices = [
        "dragoon"
        "arbiter"
      ];
      services.syncthing.settings.folders."scratch".path = "/dump/scratch";
      services.syncthing.settings.folders."scratch".devices = [ "dragoon" ];
      services.syncthing.settings.folders."ebooks".path = "/dump/ebooks";
      services.syncthing.settings.folders."ebooks".devices = [
        "dragoon"
        "arbiter"
      ];
      services.syncthing.settings.devices.dragoon.id =
        "TAYU7SA-CCAFI4R-ZLB6FNM-OCPMW5W-6KEYYPI-ANW52FK-DUHVT7Z-L2GYBAB";
      services.syncthing.settings.devices.arbiter.id =
        "7HXMC4G-66H3UDT-BRJ6ATT-3HOXUVN-XIMDBOT-JSFEOO3-HRR3NVF-P4GFUQN";
      services.syncthing.guiAddress = "0.0.0.0:4538";
      services.surmhosting.exposedApps.syncthing.target.port = 4538;

    }
    {
      services.mosquitto.enable = true;
      services.mosquitto.listeners = [
        {
          users.ha.hashedPassword = "$7$101$7KOip01uJDP71vA0$y9vhvHE/pxka3/eQiP+Fs4EVjaXCJ4gwChMtFxiCH/jTDricu5MW3BjMx3XTyo2vXAVgUd/QHKuwoejw8h1OuQ==";
          acl = [
            "topic readwrite #"
          ];
        }
      ];
      services.mosquitto.dataDir = "/dump/state/mosquitto";
      services.mosquitto.persistence = false;
    }
    {

      networking.firewall.allowedTCPPorts = [ giteaPort ];
      services.surmhosting.exposedApps.gitea.target.container = {
        config = {
          system.stateVersion = "25.05";

          services.gitea.enable = true;
          services.gitea.stateDir = "/dump/state/gitea";
          services.gitea.user = "containeruser";
          services.gitea.settings.server.HTTP_PORT = 8080;
          services.gitea.settings.server.SSH_PORT = giteaPort;
          services.gitea.settings.server.START_SSH_SERVER = true;
          # services.openssh.enable = true;
        };

        forwardPorts = [
          {
            containerPort = giteaPort;
            hostPort = giteaPort;
            protocol = "tcp";
          }
        ];

        bindMounts = {
          state = {
            mountPoint = "/dump/state/gitea";
            hostPath = "/dump/state/gitea";
            isReadOnly = false;
          };
        };
      };
    }
    {
      services.surmhosting.exposedApps.lidarr.target.container = {
        config = {
          system.stateVersion = "25.05";

          services.lidarr.enable = true;
          services.lidarr.package = pkgs-unstable.lidarr;
          services.lidarr.user = "containeruser";
          services.lidarr.dataDir = "/dump/state/lidarr";
          services.lidarr.settings.server.port = 8080;
          services.lidarr.settings.auth.method = "External";
        };

        bindMounts = {
          state = {
            mountPoint = "/dump/state/lidarr";
            hostPath = "/dump/state/lidarr";
            isReadOnly = false;
          };
          music = {
            mountPoint = "/dump/music";
            hostPath = "/dump/music";
            isReadOnly = false;
          };
          torrent = {
            mountPoint = "/dump/state/qbittorrent";
            hostPath = "/dump/state/qbittorrent";
            isReadOnly = false;
          };
        };
      };
    }
    {

      services.surmhosting.exposedApps.radarr.target.container = {
        config = {
          system.stateVersion = "25.05";

          services.radarr.enable = true;
          services.radarr.package = pkgs-unstable.radarr;
          services.radarr.user = "containeruser";
          services.radarr.dataDir = "/dump/state/radarr";
          services.radarr.settings.server.port = 8080;
          services.radarr.settings.auth.method = "External";
        };

        bindMounts = {
          state = {
            mountPoint = "/dump/state/radarr";
            hostPath = "/dump/state/radarr";
            isReadOnly = false;
          };
          movies = {
            mountPoint = "/dump/Movies";
            hostPath = "/dump/Movies";
            isReadOnly = false;
          };
          torrent = {
            mountPoint = "/dump/state/qbittorrent";
            hostPath = "/dump/state/qbittorrent";
            isReadOnly = false;
          };
        };
      };
    }
    {
      services.surmhosting.exposedApps.sonarr.target.container = {
        config = {
          system.stateVersion = "25.05";

          services.sonarr.enable = true;
          services.sonarr.package = pkgs-unstable.sonarr;
          services.sonarr.user = "containeruser";
          services.sonarr.dataDir = "/dump/state/sonarr";
          services.sonarr.settings.server.port = 8080;
          services.sonarr.settings.auth.method = "External";
        };
        bindMounts = {
          state = {
            mountPoint = "/dump/state/sonarr";
            hostPath = "/dump/state/sonarr";
            isReadOnly = false;
          };
          series = {
            mountPoint = "/dump/TV";
            hostPath = "/dump/TV";
            isReadOnly = false;
          };
          torrent = {
            mountPoint = "/dump/state/qbittorrent";
            hostPath = "/dump/state/qbittorrent";
            isReadOnly = false;
          };
        };
      };
    }
    {
      services.surmhosting.exposedApps.prowlarr.target.container = {
        config = {
          system.stateVersion = "25.05";

          services.prowlarr.enable = true;
          services.prowlarr.package = pkgs-unstable.prowlarr;
          services.prowlarr.settings.server.port = 8080;
          services.prowlarr.settings.auth.method = "External";
        };

        bindMounts.state = {
          mountPoint = "/var/lib/private/prowlarr";
          hostPath = "/dump/state/prowlarr";
          isReadOnly = false;
        };
      };
    }
    {
      services.surmhosting.exposedApps.rss.target.port = 80;
      services.surmhosting.exposedApps.rss.target.container = {
        config = {
          system.stateVersion = "25.05";

          services.freshrss.enable = true;
          services.freshrss.dataDir = "/dump/state/freshrss";
          # services.freshrss.user = "containeruser";
          services.freshrss.authType = "none";
          services.freshrss.baseUrl = "http://rss.nexus.hosts.10.0.0.2.nip.io";
        };

        bindMounts.state = {
          mountPoint = "/dump/state/freshrss";
          hostPath = "/dump/state/freshrss";
          isReadOnly = false;
        };
      };
    }
    {
      networking.firewall.allowedTCPPorts = [ torrentingPort ];
      networking.firewall.allowedUDPPorts = [ torrentingPort ];
      services.surmhosting.exposedApps.torrent.target.container = {
        config = {
          system.stateVersion = "25.05";

          services.qbittorrent.enable = true;
          # services.qbittorrent.package = pkgs-unstable.qbittorrent;
          services.qbittorrent.user = "containeruser";
          services.qbittorrent.webuiPort = 8080;
          services.qbittorrent.torrentingPort = torrentingPort;
          services.qbittorrent.profileDir = "/dump/state/qbittorrent";
          services.qbittorrent.serverConfig = {
            Preferences.WebUI = {
              AuthSubnetWhitelistEnabled = true;
              AuthSubnetWhitelist = "0.0.0.0/0";
            };
          };
        };

        forwardPorts = [
          {
            containerPort = torrentingPort;
            hostPort = torrentingPort;
            protocol = "tcp";
          }
          {
            containerPort = torrentingPort;
            hostPort = torrentingPort;
            protocol = "udp";
          }
        ];
        bindMounts.state = {
          mountPoint = "/dump/state/qbittorrent";
          hostPath = "/dump/state/qbittorrent";
          isReadOnly = false;
        };
      };
    }
    {

      services.surmhosting.exposedApps.music.target.container = {
        config = {
          system.stateVersion = "25.05";

          services.navidrome.enable = true;
          services.navidrome.package = pkgs-unstable.navidrome;
          services.navidrome.user = "containeruser";
          services.navidrome.settings = {
            MusicFolder = "/dump/music";
            DataFolder = "/dump/state/navidrome";
            DefaultDownloadableShare = true;
            Address = "0.0.0.0";
            Port = 8080;
          };
        };

        bindMounts = {
          music = {
            mountPoint = "/dump/music";
            hostPath = "/dump/music";
            isReadOnly = true;
          };
          state = {
            mountPoint = "/dump/state/navidrome";
            hostPath = "/dump/state/navidrome";
            isReadOnly = false;
          };
        };
      };
    }
    {
      secrets.items.nexus-copyparty.command = ''
        cat > /var/lib/copyparty/surma.passwd
        chmod 0644 /var/lib/copyparty/surma.passwd
      '';
      services.surmhosting.exposedApps.copyparty.target.container = {
        config = (
          { ... }:
          {
            imports = [
              inputs.copyparty.nixosModules.default
            ];
            config = {
              system.stateVersion = "25.05";
              services.copyparty.enable = true;
              services.copyparty.user = "containeruser";
              services.copyparty.package = inputs.copyparty.packages.${pkgs.stdenv.system}.copyparty;
              services.copyparty = {
                accounts = {
                  surma.passwordFile = "/var/lib/credentials/copyparty/surma.passwd";
                };
                settings.p = [ 8080 ];
                volumes."/all" = {
                  path = "/dump";
                  access.A = [ "surma" ];
                };
                volumes."/tv" = {
                  path = "/dump/TV";
                  access.r = "*";
                };
                volumes."/movies" = {
                  path = "/dump/Tovies";
                  access.r = "*";
                };
                volumes."/music" = {
                  path = "/dump/music";
                  access.r = "*";
                };
              };
            };
          }
        );

        bindMounts.dump = {
          mountPoint = "/dump";
          hostPath = "/dump";
          isReadOnly = false;
        };
        bindMounts.creds = {
          mountPoint = "/var/lib/credentials/copyparty";
          hostPath = "/var/lib/copyparty";
          isReadOnly = true;
        };
      };
    }
    {
      virtualisation.oci-containers.containers.jellyfin = {
        serviceName = "jellyfin-container";
        image = "jellyfin/jellyfin";
        podman.sdnotify = "healthy";
        volumes = [
          "/dump/state/jellyfin/config:/config"
          "/dump/state/jellyfin/cache:/cache"
          "/dump/TV:/media/TV"
          "/dump/Movies:/media/Movies"
          "/dump/audiobooks:/media/audiobooks"
          "/dump/lol:/media/lol"
        ];
        labels = {
          "traefik.enable" = "true";
          "traefik.http.services.jellyfin.loadbalancer.server.port" = "8096";
          "traefik.http.routers.jellyfin.rule" =
            "HostRegexp(`^jellyfin\\.surmcluster`) || HostRegexp(`^jellyfin\\.nexus\\.hosts`)";
        };
      };
    }
    {

      virtualisation.oci-containers.containers.jaeger = {
        serviceName = "jaeger-container";
        image = "cr.jaegertracing.io/jaegertracing/jaeger:2.11.0";
        ports = [
          "4318:4318"
        ];
        labels = {
          "traefik.enable" = "true";
          "traefik.http.services.jaeger.loadbalancer.server.port" = "16686";
          "traefik.http.routers.jaeger.rule" =
            "HostRegexp(`^jaeger\\.surmcluster`) || HostRegexp(`^jaeger\\.nexus\\.hosts`)";
        };
      };
    }
    {
      services.traefik.staticConfigOptions.tracing = {
        serviceName = "traefik-nexus";
        sampleRate = 1.0;
        otlp = {
          http = {
            endpoint = "http://localhost:4318/v1/traces";
          };
        };
      };
    }

    {
      # services.hate.enable = true;
    }

    {
      services.vsftpd.enable = true;
      services.vsftpd.localUsers = true;
      services.vsftpd.writeEnable = true;
    }

    {
      # PostgreSQL database server
      secrets.items.postgres-admin-password.target = "/var/lib/postgres-credentials/password";

      networking.firewall.allowedTCPPorts = [ 5432 ];

      services.surmhosting.exposedApps.postgres.target.container = {
        config = {
          system.stateVersion = "25.05";

          services.postgresql = {
            enable = true;
            package = pkgs.postgresql_17;
            port = 5432;
            enableTCPIP = true;

            # Allow connections from Tailscale network
            authentication = pkgs.lib.mkOverride 10 ''
              # TYPE  DATABASE        USER            ADDRESS                 METHOD
              local   all             all                                     trust
              host    all             all             127.0.0.1/32            scram-sha-256
              host    all             all             ::1/128                 scram-sha-256
              host    all             all             100.64.0.0/10           scram-sha-256
            '';

            # Create admin user on first run
            initialScript = pkgs.writeText "postgres-init.sql" ''
              -- Create admin user (password will be set via ALTER USER)
              DO $$
              BEGIN
                IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'surma') THEN
                  CREATE ROLE surma WITH LOGIN SUPERUSER CREATEDB CREATEROLE;
                END IF;
              END
              $$;
            '';
          };

          # Set admin password from file after PostgreSQL starts
          systemd.services.postgresql.postStart = ''
            PASSWORD=$(cat /var/lib/credentials/password)
            $PSQL -tAc "ALTER USER surma WITH PASSWORD '$PASSWORD';"
          '';
        };

        forwardPorts = [
          {
            containerPort = 5432;
            hostPort = 5432;
            protocol = "tcp";
          }
        ];

        bindMounts = {
          state = {
            mountPoint = "/var/lib/postgresql";
            hostPath = "/dump/state/postgres";
            isReadOnly = false;
          };
          credentials = {
            mountPoint = "/var/lib/credentials";
            hostPath = "/var/lib/postgres-credentials";
            isReadOnly = true;
          };
        };
      };
    }

    {
      # pgweb - PostgreSQL web interface
      services.surmhosting.exposedApps.pgweb.target.container = {
        config = {
          system.stateVersion = "25.05";

          # Simple systemd service to run pgweb
          systemd.services.pgweb = {
            description = "pgweb - PostgreSQL Web Interface";
            wantedBy = [ "multi-user.target" ];
            after = [ "network.target" ];

            serviceConfig = {
              Type = "simple";
              ExecStart = "${pkgs.pgweb}/bin/pgweb --bind=0.0.0.0 --listen=8080 --host=100.83.198.90 --port=5432 --user=surma --db=postgres --sessions";
              Restart = "always";
              RestartSec = "10s";
            };

            environment = {
              PGWEB_DATABASE_URL = "postgres://surma@100.83.198.90:5432/postgres?sslmode=disable";
            };
          };
        };
      };
    }

    {
      home-manager.users.surma =
        {
          config,
          ...
        }:
        {
          imports = [
            ../../scripts
            ../../modules/home-manager/opencode

            ../../profiles/home-manager/base.nix
            ../../profiles/home-manager/dev.nix
            ../../profiles/home-manager/nixdev.nix
            ../../profiles/home-manager/linux.nix
            ../../profiles/home-manager/workstation.nix

            ../../modules/home-manager/unfree-apps
          ];

          config = {
            allowedUnfreeApps = [
              "claude-code"
            ];

            secrets.items.llm-proxy-client-key.target = "${config.home.homeDirectory}/.local/state/llm-proxy-client-key";

            home.stateVersion = "25.05";

            home.sessionVariables.FLAKE_CONFIG_URI = "path:${config.home.homeDirectory}/src/github.com/surma/nixenv#nexus";
            customScripts.llm-proxy.enable = true;

            programs.opencode.enable = true;
            defaultConfigs.opencode.enable = true;
          };
        };
    }
  ];
}
