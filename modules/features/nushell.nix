{ lib, systemManager, ... }:
{
  # Nushell is home-manager only
  config = lib.mkIf (systemManager == "home-manager") {
    programs.nushell = {
      extraConfig = ''
        def ngs [...args] {
          git status --porcelain ...$args | from ssv -n -m 1 | rename status path | update path { [(git rev-parse --show-toplevel) $in] | path join }
        }

        def --wrapped ngb [...args] {
          git for-each-ref refs/heads | from tsv -n | rename meta ref |  update ref { $in | str substring 11.. } | get ref | sort | str join "\n" | fzf ...$args
        }

        def ngco [] {
          ngb | if ($in|str length) > 0 {git checkout $in} else {print "Aborted."};
        }

        def ngstack [] {
          gt log --stack | lines | chunk-by  {|l| ($l | str starts-with "◯") or ($l | str starts-with "◉") } | enumerate | where { $in.index mod 2 == 0 } | flatten | each { $in.item | parse --regex `[^\s]+\s*([^(\s]+)` | get capture0.0 }
        }


      '';
    };
  };
}
