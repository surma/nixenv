{ lib, buildGoModule }:
buildGoModule {
  pname = "jazzy-poisonous-plant-parlour";
  version = "0.1.0";

  src = ./.;
  vendorHash = null;

  meta = with lib; {
    description = "Novelty page based on the office and garden door sensors";
    license = licenses.mit;
    mainProgram = "jazzy-poisonous-plant-parlour";
  };
}
