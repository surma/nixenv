{
  lib,
  stdenv,
  go,
  inputs,
  surm-auth,
}:

# Runs the packaged surm-auth binary through a full mocked-OAuth
# end-to-end flow. The Go test lives in apps/surm-auth/e2e_test.go
# behind the `surm_auth_e2e` build tag and fails instead of skipping
# when SURM_AUTH_BIN is absent. The binary under test is the wrapped
# package, so the test also exercises the packaged templates.
stdenv.mkDerivation {
  name = "surm-auth-e2e-check";

  src = inputs.self + "/apps/surm-auth";

  nativeBuildInputs = [ go ];

  dontConfigure = true;

  buildPhase = ''
    # The module tree comes from the package's own goModules
    # derivation, so the test build needs no network.
    cp -r ${surm-auth.goModules} vendor/
    chmod -R u+w vendor/

    export HOME=$TMPDIR
    export GOCACHE=$TMPDIR/gocache
    export GOFLAGS=-mod=vendor
    export GOPROXY=off
    export GOTOOLCHAIN=local
    export CGO_ENABLED=1

    # The wrapped package binary carries the packaged templates.
    export SURM_AUTH_BIN=${lib.getExe surm-auth}

    go test -tags surm_auth_e2e -race -count=1 -v ./...
  '';

  installPhase = ''
    touch $out
  '';

  meta = {
    description = "End-to-end OAuth flow test for the packaged surm-auth binary";
  };
}
