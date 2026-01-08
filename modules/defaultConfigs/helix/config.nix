{
  enable = true;
  defaultEditor = true;
  settings = {
    # theme="everforest_dark"
    theme = "gruvbox";
    editor = {
      true-color = true;
      rulers = [
        80
        100
        120
      ];
      color-modes = true;
      auto-pairs = true;
      cursorline = true;
      soft-wrap = {
        enable = true;
      };
      indent-guides = {
        render = true;
      };
      lsp = {
        display-inlay-hints = true;
      };
      file-picker = {
        hidden = false;
      };
    };
    keys = {
      normal = {
        "C-q" = ":buffer-close";
        space = {
          f = "file_picker_in_current_buffer_directory";
          F = "file_picker";
          C-f = "file_picker_in_current_directory";
          "[" = ":set-option lsp.display-inlay-hints false";
          "]" = ":set-option lsp.display-inlay-hints true";
          "{" = ":theme gruvbox_light_hard";
          "}" = ":theme gruvbox";
          "(" = ":set soft-wrap.enable false";
          ")" = ":set soft-wrap.enable true";
        };
      };
    };
  };

  languages = {
    language-server.rust-analyzer.config = {
      files = {
        excludeDirs = [ "node_modules" ];
      };
      procMacro.enabled = true;
      inlayHints = {
        maxLength = 25;
        discriminantHints.enable = true;
        closureReturnTypeHints.enable = true;
        closureCaptureHints.enable = true;
      };
    };

    language-server.vscode-css-language-server.command = "css-languageserver";
    language-server.wasm-lsp.command = "wasm-lsp";

    language = [
      {
        name = "wat";
        scope = "source.wat";
        injection-regex = "^wat$";
        file-types = [ "wat" ];
        comment-token = ";;";
        indent = {
          tab-width = 2;
          unit = "\t";
        };
        roots = [ ];
        grammar = "wat";
        language-servers = [ "wasm-lsp" ];
        formatter = {
          command = "silly-wat-linker";
          args = [
            "format"
            "-"
          ];
        };
      }
      {
        name = "markdown";
        text-width = 80;
      }
    ];

    grammar = [
      {
        name = "wat";
        source = {
          git = "https://github.com/wasm-lsp/tree-sitter-wasm";
          rev = "d9cb9aa9437172403203c242f08b8d4d95e0e61d";
          subpath = "wat";
        };
      }
    ];
  };
}
