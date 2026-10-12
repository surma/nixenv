{ inputs }:
let
  palette = builtins.fromJSON (
    builtins.readFile "${inputs.sx}/assets/palette/palette.json"
  );
in
builtins.mapAttrs
  (_: reference:
    let
      parts = builtins.match "^(.*)-([^-]+)$" reference;
      ramp = builtins.elemAt parts 0;
      step = builtins.elemAt parts 1;
    in
    palette.ramps.${ramp}.${step}.srgb
  )
  palette.tokens
