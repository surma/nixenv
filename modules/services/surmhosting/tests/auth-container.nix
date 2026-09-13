{
  pkgs,
  lib ? pkgs.lib,
  ...
}:
let
  statePath = "/var/lib/surmhosting-auth-fixture-state";
  credentialPath = "/var/lib/surmhosting-auth-fixture-credentials";
  setupUnit = "surmhosting-auth-fixture-setup.service";
  oauthUnit = "surmhosting-auth-fixture-oauth.service";
  mockPort = 18080;
  mockScript = pkgs.writeText "surmhosting-auth-fixture-oauth.py" ''
    import base64
    import json
    import threading
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    from urllib.parse import parse_qs, urlencode, urlsplit, urlunsplit

    state = {
        "authorize": 0,
        "token": 0,
        "user": 0,
        "lookup": 0,
        "codes": {},
    }
    lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format, *args):
            return

        def send_json(self, status, value):
            body = json.dumps(value).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            parsed = urlsplit(self.path)
            query = parse_qs(parsed.query)

            if parsed.path == "/authorize":
                if query.get("client_id", [""])[0] != "synthetic-client-id":
                    self.send_json(400, {"error": "bad client id"})
                    return
                redirect_uri = query.get("redirect_uri", [""])[0]
                redirect = urlsplit(redirect_uri)
                if redirect.scheme != "https" or redirect.netloc != "auth.surmhosting.test":
                    self.send_json(400, {"error": "bad redirect"})
                    return
                with lock:
                    state["authorize"] += 1
                    code = "fixture-code-%d" % state["authorize"]
                    state["codes"][code] = "fixture-token"
                callback_query = {
                    "code": [code],
                    "state": [query.get("state", [""])[0]],
                }
                location = urlunsplit(
                    (
                        redirect.scheme,
                        redirect.netloc,
                        redirect.path,
                        urlencode(callback_query, doseq=True),
                        "",
                    )
                )
                self.send_response(302)
                self.send_header("Location", location)
                self.end_headers()
                return

            if parsed.path == "/user":
                if self.headers.get("Authorization") != "Bearer fixture-token":
                    self.send_json(401, {"error": "bad token"})
                    return
                with lock:
                    state["user"] += 1
                self.send_json(
                    200,
                    {
                        "id": 1000,
                        "login": "fixture-user",
                        "email": "fixture@example.test",
                    },
                )
                return

            if parsed.path == "/users/fixture-user":
                with lock:
                    state["lookup"] += 1
                    lookup = state["lookup"]
                if lookup > 1:
                    self.send_json(503, {"error": "the persisted seed marker must skip this lookup"})
                    return
                self.send_json(
                    200,
                    {
                        "id": 1000,
                        "login": "fixture-user",
                        "email": "fixture@example.test",
                    },
                )
                return

            if parsed.path == "/stats":
                with lock:
                    value = {
                        key: count
                        for key, count in state.items()
                        if key != "codes"
                    }
                self.send_json(200, value)
                return

            self.send_json(404, {"error": "not found"})

        def do_POST(self):
            if urlsplit(self.path).path != "/token":
                self.send_json(404, {"error": "not found"})
                return

            length = int(self.headers.get("Content-Length", "0"))
            form = parse_qs(self.rfile.read(length).decode())
            client_id = ""
            client_secret = ""
            authorization = self.headers.get("Authorization", "")
            if authorization.startswith("Basic "):
                decoded = base64.b64decode(authorization.removeprefix("Basic ")).decode()
                client_id, _, client_secret = decoded.partition(":")
            else:
                client_id = form.get("client_id", [""])[0]
                client_secret = form.get("client_secret", [""])[0]

            if client_id != "synthetic-client-id" or client_secret != "synthetic-client-secret":
                self.send_json(401, {"error": "bad client credentials"})
                return

            code = form.get("code", [""])[0]
            with lock:
                token = state["codes"].pop(code, None)
                if token is not None:
                    state["token"] += 1
            if token is None:
                self.send_json(400, {"error": "bad code"})
                return
            self.send_json(200, {"access_token": token, "token_type": "bearer"})

    ThreadingHTTPServer.allow_reuse_address = True
    server = ThreadingHTTPServer(("0.0.0.0", 18080), Handler)
    server.serve_forever()
  '';

  setupScript = pkgs.writeShellScript "surmhosting-auth-fixture-setup" ''
    set -eu

    state=${lib.escapeShellArg statePath}
    credentials=${lib.escapeShellArg credentialPath}

    # The fixture owns these paths. Surmhosting must not create them first.
    test ! -e "$state"
    test ! -e "$credentials"
    install -d -m 0700 "$state" "$credentials" /run/surmhosting-auth-fixture
    printf '%s\n' synthetic-client-id > "$credentials/github-client-id"
    printf '%s\n' synthetic-client-secret > "$credentials/github-client-secret"
    printf '%s\n' synthetic-cookie-secret-0123456789abcdef > "$credentials/cookie-secret"
    chmod 0600 "$credentials"/*
    printf '%s\n' fixture-created-state-and-credentials > /run/surmhosting-auth-fixture/setup-complete
  '';

  flowScript = pkgs.writeText "surmhosting-auth-fixture-flow.py" ''
    import http.client
    import json
    import re
    from html import unescape
    from http.cookies import SimpleCookie
    from urllib.parse import urlsplit

    AUTH_IP = "127.0.0.1"
    MOCK_IP = "10.202.0.1"
    AUTH_HOST = "auth.surmhosting.test"
    APP_HOST = "fixture.apps.surmhosting.test"

    class Browser:
        def __init__(self):
            self.cookies = {}

        def request(self, address, port, path, headers=None):
            request_headers = dict(headers or {})
            if self.cookies:
                request_headers["Cookie"] = "; ".join(
                    "%s=%s" % pair for pair in sorted(self.cookies.items())
                )
            connection = http.client.HTTPConnection(address, port, timeout=10)
            connection.request("GET", path, headers=request_headers)
            response = connection.getresponse()
            body = response.read()
            for value in response.headers.get_all("Set-Cookie", []):
                cookie = SimpleCookie()
                cookie.load(value)
                for name, morsel in cookie.items():
                    if morsel["max-age"] == "0" or morsel.value == "":
                        self.cookies.pop(name, None)
                    else:
                        self.cookies[name] = morsel.value
            return response.status, dict(response.getheaders()), body

    browser = Browser()

    status, headers, body = browser.request(
        AUTH_IP,
        8080,
        "/health",
        {"Host": AUTH_HOST},
    )
    assert status == 200, (status, body)
    assert body == b"OK", body

    forwarded = {
        "X-Forwarded-Proto": "https",
        "X-Forwarded-Host": APP_HOST,
        "X-Forwarded-Uri": "/",
    }
    status, headers, body = browser.request(
        AUTH_IP,
        8080,
        "/auth?app=fixture",
        forwarded,
    )
    assert status == 302, (status, body)
    login = urlsplit(headers["Location"])
    assert login.scheme == "https", login
    assert login.netloc == AUTH_HOST, login

    login_path = login.path + ("?" + login.query if login.query else "")
    status, headers, body = browser.request(
        AUTH_IP,
        8080,
        login_path,
        {"Host": AUTH_HOST},
    )
    assert status == 200, (status, body)
    match = re.search(rb'<a href="(/login/github\?[^\"]+)"', body)
    assert match, body
    oauth_path = unescape(match.group(1).decode())

    status, headers, body = browser.request(
        AUTH_IP,
        8080,
        oauth_path,
        {"Host": AUTH_HOST},
    )
    assert status == 302, (status, body)
    provider = urlsplit(headers["Location"])
    assert provider.scheme == "http", provider
    assert provider.hostname == MOCK_IP, provider
    assert provider.port == 18080, provider

    provider_path = provider.path + ("?" + provider.query if provider.query else "")
    status, headers, body = browser.request(MOCK_IP, 18080, provider_path)
    assert status == 302, (status, body)
    callback = urlsplit(headers["Location"])
    assert callback.scheme == "https", callback
    assert callback.netloc == AUTH_HOST, callback

    callback_path = callback.path + ("?" + callback.query if callback.query else "")
    status, headers, body = browser.request(
        AUTH_IP,
        8080,
        callback_path,
        {"Host": AUTH_HOST},
    )
    assert status == 302, (status, body)
    assert headers["Location"] == "https://%s/" % APP_HOST, headers

    status, headers, body = browser.request(
        AUTH_IP,
        8080,
        "/auth?app=fixture",
        forwarded,
    )
    assert status == 200, (status, body)
    assert headers["X-Auth-Request-User"] == "fixture-user", headers
    assert headers["X-Auth-Request-Email"] == "fixture@example.test", headers

    status, headers, body = browser.request(MOCK_IP, 18080, "/stats")
    assert status == 200, (status, body)
    stats = json.loads(body)
    assert stats == {
        "authorize": 1,
        "token": 1,
        "user": 1,
        "lookup": 1,
    }, stats
  '';
in
pkgs.testers.nixosTest {
  name = "surmhosting-auth-container";

  nodes.machine =
    { config, pkgs, lib, ... }:
    {
      imports = [ ../nix/modules/surmhosting.nix ];

      system.stateVersion = "25.05";
      networking.hostName = "surmhosting-auth-fixture";
      boot.enableContainers = true;
      virtualisation.memorySize = 2048;
      virtualisation.cores = 2;
      environment.systemPackages = [ pkgs.curl pkgs.python3 ];
      environment.etc."surmhosting-auth-flow.py".source = flowScript;

      networking.firewall = {
        trustedInterfaces = [ "ve-+" ];
        extraInputRules = ''
          ip saddr 10.202.0.0/16 tcp dport 18080 accept comment "isolated OAuth fixture"
        '';
      };
      networking.nat.enable = lib.mkForce false;

      services.surmhosting = {
        enable = true;
        hostname = "surmhosting.test";
        externalInterface = "eth0";
        appsNamespace = "apps.surmhosting.test";
        tls.enable = true;
        auth = {
          enable = true;
          domain = "auth.surmhosting.test";
          cookieDomain = ".surmhosting.test";
          stateHostPath = statePath;
          github.clientIdFile = "${credentialPath}/github-client-id";
          github.clientSecretFile = "${credentialPath}/github-client-secret";
          cookieSecretFile = "${credentialPath}/cookie-secret";
          unitDependencies = {
            requires = [ "${setupUnit}" ];
            after = [ "${setupUnit}" ];
          };
        };
        services.fixture = {
          host = "127.0.0.1";
          expose.apps.fixture = {
            access.mode = "allowlist";
            access.seedUsers = [ "fixture-user" ];
            internal.access = "trusted-network";
            public.aliases = [ "fixture.surmhosting.test" ];
            ports = [
              {
                port = 8081;
                hostname = "fixture";
              }
            ];
          };
        };
      };

      containers.surm-auth.config =
        { ... }:
        {
          environment.etc."surmhosting-auth-flow.py".source = flowScript;
          environment.systemPackages = [ pkgs.curl pkgs.python3 ];
          services.surm-auth.github = {
            authUrl = "http://10.202.0.1:${toString mockPort}/authorize";
            tokenUrl = "http://10.202.0.1:${toString mockPort}/token";
            userUrl = "http://10.202.0.1:${toString mockPort}/user";
            usersApiUrl = "http://10.202.0.1:${toString mockPort}/users";
          };
        };

      systemd.services.surmhosting-auth-fixture-oauth = {
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.python3}/bin/python ${mockScript}";
          Restart = "always";
          RestartSec = 1;
        };
      };

      systemd.services.surmhosting-auth-fixture-setup = {
        wantedBy = [ "multi-user.target" ];
        requires = [ oauthUnit ];
        after = [ oauthUnit ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = setupScript;
        };
      };
    };

  testScript = ''
    start_all()

    machine.wait_for_unit("surmhosting-auth-fixture-oauth.service")
    machine.wait_for_unit("surmhosting-auth-fixture-setup.service")
    machine.wait_for_unit("traefik.service")
    machine.wait_for_unit("container@surm-auth.service")
    machine.wait_for_open_port(80)
    machine.wait_for_open_port(443)

    machine.succeed("test -f /run/surmhosting-auth-fixture/setup-complete")
    machine.succeed("curl --fail --silent http://10.202.0.1:${toString mockPort}/stats")
    status, output = machine.execute(
        "nixos-container run surm-auth -- curl --fail --silent --max-time 2 "
        "http://10.202.0.1:${toString mockPort}/stats"
    )
    print("container-to-mock status:", status)
    print(output)
    machine.succeed("nixos-container run surm-auth -- curl --fail --silent http://127.0.0.1:8080/health")
    machine.succeed("nixos-container run surm-auth -- python3 /etc/surmhosting-auth-flow.py")

    # The state directory contains the committed seed marker and policy.
    machine.succeed(
        "test -n \\\"$(find ${statePath} -type f -name policy.json -print -quit)\\\""
    )

    # The fixture setup unit owns the host directory. The auth module did not
    # create it before the setup unit ran, and the policy survives recreation.
    machine.succeed("systemctl restart container@surm-auth.service")
    machine.wait_for_unit("container@surm-auth.service")
    machine.wait_until_succeeds("nixos-container run surm-auth -- curl --fail --silent http://127.0.0.1:8080/health")
    machine.succeed(
        "python3 -c 'import json,urllib.request; s=json.load(urllib.request.urlopen(\"http://10.202.0.1:${toString mockPort}/stats\")); assert s[\"lookup\"] == 1, s'"
    )

    # The generated config contains credential paths, but never secret values.
    machine.succeed(
        "nixos-container run surm-auth -- sh -c "
        "'config=$(find /nix/store -maxdepth 1 -name \"*surm-auth-config.yaml\" -print -quit); "
        "test -n \"$config\"; "
        "grep -F \"/run/credentials/surm-auth.service/github-client-id\" \"$config\"; "
        "grep -F \"/run/credentials/surm-auth.service/github-client-secret\" \"$config\"; "
        "grep -F \"/run/credentials/surm-auth.service/cookie-secret\" \"$config\"; "
        "! grep -F \"synthetic-client-id\" \"$config\"; "
        "! grep -F \"synthetic-client-secret\" \"$config\"; "
        "! grep -F \"synthetic-cookie-secret\" \"$config\"'"
    )
  '';
}
