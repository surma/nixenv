{
  config.programs.nushell = {
    extraConfig = ''
      def ngs [...args] {
        git status --porcelain ...$args | from ssv -n -m 1 | rename status path | update path { [(git rev-parse --show-toplevel) $in] | path join }
      }

      def ngb [] {
        git for-each-ref refs/heads | from tsv -n | rename meta ref |  update ref { $in | str substring 11.. } | get ref | sort | str join "\n" | fzf
      }

      def ngco [] {
        ngb | if ($in|str length) > 0 {git checkout $in} else {print "Aborted."};
      }

      def --wrapped ocq [...rest] {
        opencode run --dangerously-skip-permissions ...$rest
      }

      def --wrapped oc [...rest] {
        opencode --dangerously-skip-permissions ...$rest
      }
    '';
  };
}
