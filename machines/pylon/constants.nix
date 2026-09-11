{
  # Tailscale IPv4s of the backend hosts (verify with `tailscale status`
  # before deployment; auth-rework section 8.1).
  nexusTsV4 = "100.83.198.90";
  citadelTsV4 = "100.70.63.93";
  # Pylon's own public IPv4 (Hetzner, enp1s0). Used for hairpin NAT
  # reflection so hosts behind Pylon can reach the public edge address.
  pylonPublicV4 = "49.12.5.28";
}
