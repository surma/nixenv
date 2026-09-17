{ lib, buildGoModule }:
buildGoModule {
  pname = "adguardhome-reconciler";
  version = "0.1.0";

  src = ./.;
  vendorHash = null;

  meta = with lib; {
    description = "Converges AdGuardHome static DHCP leases to the IP registry";
    license = licenses.mit;
    mainProgram = "adguardhome-reconciler";
  };
}
