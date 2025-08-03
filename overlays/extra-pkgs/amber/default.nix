{
  amber-upstream,
  lib,
  system,
}:
let
  amber-lang = amber-upstream.packages.${system}.default;
in
amber-lang
