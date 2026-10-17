{ buildGoModule }:
buildGoModule {
  pname = "throwaway-containers";
  version = "0.1.0";
  src = ./src;
  # Go standard library only.
  vendorHash = null;
  meta.mainProgram = "throwaway-containers";
}
