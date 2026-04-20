{
  lib,
  python3Packages,
  fetchFromGitHub,
  ffmpeg,
  inputs,
  ...
}:
let
  version = "0.5.1";
in
python3Packages.buildPythonApplication {
  pname = "parakeet-mlx";
  inherit version;
  pyproject = true;

  src = fetchFromGitHub {
    owner = "senstella";
    repo = "parakeet-mlx";
    rev = "ba03a1b6e8df4edadc83aca312a32600831dd481";
    hash = "sha256-udiDBB8vp27ID1JRhT8rNj1S8agJslb2OVo5tkhnRLw=";
  };

  build-system = with python3Packages; [
    setuptools
    wheel
  ];

  dependencies = with python3Packages; [
    dacite
    huggingface-hub
    librosa
    mlx
    numpy
    typer
  ];

  # ffmpeg needed at runtime for audio processing
  makeWrapperArgs = [
    "--prefix PATH : ${lib.makeBinPath [ ffmpeg ]}"
  ];

  # Tests require model downloads and GPU
  doCheck = false;

  meta = {
    description = "NVIDIA Parakeet ASR for Apple Silicon via MLX";
    homepage = "https://github.com/senstella/parakeet-mlx";
    license = lib.licenses.asl20;
    platforms = lib.platforms.darwin;
    mainProgram = "parakeet-mlx";
  };
}
