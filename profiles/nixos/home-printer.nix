# The Brother DCP-1610W at home. The printer announces its hostname through
# mDNS, so this profile works only on the home LAN. Nothing in it depends on
# the client machine.
#
# The printer is a host-based printer. Its mDNS record has an empty pdl, so
# driverless printing does not work and cups-browsed has nothing to add. The
# brlaser driver supplies the PPD.
{ pkgs, ... }:
{
  services.printing = {
    enable = true;
    drivers = [ pkgs.brlaser ];
    browsed.enable = false;
  };

  # CUPS backends resolve the printer hostname through NSS, so .local names
  # need nss-mdns, and nss-mdns sends its queries to avahi-daemon. The
  # hostname comes from the printer MAC and stays stable when the IP changes.
  services.avahi.enable = true;
  services.avahi.nssmdns4 = true;

  hardware.printers = {
    ensureDefaultPrinter = "Brother_DCP-1610W";
    ensurePrinters = [
      {
        name = "Brother_DCP-1610W";
        location = "Home";
        deviceUri = "socket://BRN68140165592C.local:9100";
        model = "drv:///brlaser.drv/br1610.ppd";
        ppdOptions.PageSize = "A4";
      }
    ];
  };
}
