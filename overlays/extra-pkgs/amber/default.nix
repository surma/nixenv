{
  inputs,
  system,
}:
let
  amber-lang = inputs.amber-upstream.packages.${system}.default;
in
amber-lang
