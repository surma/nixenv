{
  lib,
  deno,
  writeTextFile,
  python3,
  symlinkJoin,
  writeShellScriptBin,
}:
let
  # NOTE: I tried to install jupyter via `python3.withPackages` previously,
  # however that led jupyter *prepending* stuff to $PATH, which means it would
  # only find the `pip` in the nix store (i.e read-only), rather than the one
  # from the venv. So you couldn’t install packages from within the notebook.
  python = python3;

  denoKernelSpec = {
    argv = [
      "${deno}/bin/deno"
      "jupyter"
      "--kernel"
      "--conn"
      "{connection_file}"
    ];
    display_name = "Deno";
    language = "typescript";
  };
  denoKernelSpecFile = writeTextFile {
    name = "deno-kernel";
    destination = "/kernels/deno/kernel.json";
    text = builtins.toJSON denoKernelSpec;
  };

  kernels = symlinkJoin {
    name = "kernels";
    paths = [ denoKernelSpecFile ];
  };
in
writeShellScriptBin "jupyter-start" ''
  ${python}/bin/python -m venv venv
  source venv/bin/activate
  pip install jupyter
  export JUPYTER_PATH="${kernels}:$JUPYTER_PATH"
  jupyter lab --no-browser
''
