{ pkgs, surmhosting }:
# NixOS VM test: create a box from a prebuilt system, exec, files, ephemeral
# root, reconfigure in place, TTL expiry -> reaped, delete, boot wipe.
# The boxes use prebuilt systems ({"system": <store path>}) because the VM
# has no network to build a NixOS config; live checks cover {nixos}/{flake}.
let
  # NAT contributions must merge with Surmhosting. Forced host overrides win.
  evalNat =
    modules:
    (import "${pkgs.path}/nixos/lib/eval-config.nix" {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        ./default.nix
        {
          system.stateVersion = "26.05";
          services.throwaway-containers.enable = true;
        }
      ]
      ++ modules;
    }).config.networking.nat.internalIPs;
  surmhostingModules = [
    surmhosting.nixosModules.default
    {
      services.surmhosting = {
        enable = true;
        hostname = "nat-check";
        externalInterface = "eth0";
        containeruser.uid = null;
      };
    }
  ];
  mergedNat = evalNat surmhostingModules;

  mkBox =
    version:
    (import "${pkgs.path}/nixos/lib/eval-config.nix" {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        (
          { lib, ... }:
          {
            boot.isNspawnContainer = true;
            networking.useDHCP = false;
            networking.useHostResolvConf = false;
            system.stateVersion = lib.trivial.release;
            environment.etc."box-version".text = version;
            documentation.enable = false;
          }
        )
      ];
    }).config.system.build.toplevel;
  box1 = mkBox "1";
  box2 = mkBox "2";
in
assert pkgs.lib.assertMsg (
  builtins.sort builtins.lessThan mergedNat == [
    "10.201.0.0/16"
    "10.202.0.0/16"
    "10.233.0.0/16"
  ]
) "Throwaway containers must preserve Surmhosting NAT ranges";
assert pkgs.lib.assertMsg (
  evalNat [ ] == [ "10.233.0.0/16" ]
) "Standalone throwaway containers must retain their NAT range";
assert pkgs.lib.assertMsg (
  evalNat (
    surmhostingModules ++ [ { networking.nat.internalIPs = pkgs.lib.mkForce [ "10.250.0.0/16" ]; } ]
  ) == [ "10.250.0.0/16" ]
) "Forced host NAT ranges must replace all contributions";
pkgs.testers.runNixOSTest {
  name = "throwaway-containers";

  nodes.machine = {
    imports = [ ./default.nix ];
    services.throwaway-containers.enable = true;
    virtualisation.memorySize = 2048;
    virtualisation.additionalPaths = [
      box1
      box2
    ];
    environment.systemPackages = [ pkgs.curl ];
  };

  testScript = ''
    import json, shlex, time

    def api(method, path, body=None, raw=False):
        cmd = f"curl -sS --fail-with-body -X {method} http://127.0.0.1:8093{path}"
        if body is not None:
            data = body if isinstance(body, str) else json.dumps(body)
            cmd += " --data-binary " + shlex.quote(data)
        out = machine.succeed(cmd)
        return out if raw else json.loads(out)

    def wait_state(cid, want):
        for _ in range(300):
            c = api("GET", f"/containers/{cid}")
            if c["state"] == want:
                return c
            if c["state"] == "failed":
                print(api("GET", f"/containers/{cid}/log", raw=True))
                raise Exception(f"{cid} failed: {c['error']}")
            time.sleep(1)
        print(api("GET", f"/containers/{cid}/log", raw=True))
        raise Exception(f"{cid} never got {want}")

    def conf(cid):
        return f"/etc/nixos-containers/{cid}.conf"

    machine.wait_for_unit("throwaway-containers.service")
    machine.wait_for_open_port(8093)
    machine.succeed("systemctl list-timers | grep throwaway-containers-reap")

    with subtest("create from a prebuilt system, exec"):
        c = api("POST", "/containers", {"config": {"system": "${box1}"}, "ttl_secs": 900, "owner": "vm-test"})
        cid = c["id"]
        assert c["state"] == "creating", c
        c = wait_state(cid, "running")
        assert c["address"].startswith("10.233."), c
        r = api("POST", f"/containers/{cid}/exec", {"cmd": "uname -a; cat /etc/box-version"})
        assert r["exit"] == 0 and "Linux" in r["stdout"] and r["stdout"].endswith("1"), r
        r = api("POST", f"/containers/{cid}/exec", {"cmd": ["sh", "-c", "read x; echo got $x; exit 3"], "stdin": "hi\n"})
        assert r["exit"] == 3 and r["stdout"] == "got hi\n", r
        r = api("POST", f"/containers/{cid}/exec", {"cmd": "sleep 30", "timeout_secs": 2})
        assert r["timed_out"], r
        machine.succeed(f"ping -c1 -W5 {c['address']}")

    with subtest("no autostart, no ports, ephemeral root"):
        machine.fail(f"grep -E '^(AUTO_START=1|HOST_PORT=.+|HOST_BRIDGE=.+)' {conf(cid)}")
        machine.succeed(f"grep -x 'EXTRA_NSPAWN_FLAGS=\"--ephemeral\"' {conf(cid)}")
        assert api("PUT", f"/containers/{cid}/files/root/sub/hello.txt", "hi there") == {"ok": True}
        assert api("GET", f"/containers/{cid}/files/root/sub/hello.txt", raw=True) == "hi there"
        d = api("GET", f"/containers/{cid}/files/root/sub")
        assert d["entries"] == [{"name": "hello.txt", "type": "file"}], d
        machine.fail(f"curl -sf http://127.0.0.1:8093/containers/{cid}/files/nope")
        # Written inside the box, but not into its persistent root dir.
        machine.fail(f"test -e /var/lib/nixos-containers/{cid}/root/sub/hello.txt")

    with subtest("reconfigure in place"):
        c = api("PUT", f"/containers/{cid}/config", {"config": {"system": "${box2}"}})
        assert c["state"] == "updating", c
        c = wait_state(cid, "running")
        assert c["error"] is None and c["config"] == {"system": "${box2}"}, c
        r = api("POST", f"/containers/{cid}/exec", {"cmd": "cat /etc/box-version; cat /root/sub/hello.txt"})
        assert r["stdout"] == "2hi there", r

    with subtest("TTL expiry: the reaper destroys it"):
        c = api("POST", f"/containers/{cid}/extend", {"ttl_secs": 5})
        machine.wait_until_succeeds(f"! test -e {conf(cid)}", timeout=150)
        machine.wait_until_fails(f"curl -sf http://127.0.0.1:8093/containers/{cid}", timeout=30)
        machine.fail(f"ls -d /var/lib/nixos-containers/{cid} /var/lib/throwaway-containers/{cid}")

    with subtest("delete and bad requests"):
        c = api("POST", "/containers", {"config": {"system": "${box1}"}})
        wait_state(c["id"], "running")
        assert api("DELETE", f"/containers/{c['id']}") == {"ok": True}
        machine.fail(f"test -e {conf(c['id'])}")
        assert api("DELETE", f"/containers/{c['id']}") == {"ok": True}
        machine.fail("curl -sf -X POST http://127.0.0.1:8093/containers --data-binary '{}'")
        machine.fail("curl -sf -X POST http://127.0.0.1:8093/containers --data-binary '{\"config\":{\"system\":\"/tmp\"}}'")

    with subtest("boot wipes every box"):
        c = api("POST", "/containers", {"config": {"system": "${box1}"}, "ttl_secs": 3600})
        wait_state(c["id"], "running")
        machine.shutdown()
        machine.start()
        machine.wait_for_unit("throwaway-containers.service")
        machine.wait_for_open_port(8093)
        machine.fail(f"test -e {conf(c['id'])}")
        assert api("GET", "/containers") == {"containers": []}
  '';
}
