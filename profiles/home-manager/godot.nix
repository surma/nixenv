{
  pkgs,
  ...
}:
{
  config = {
    home.packages = with pkgs; [
      omnisharp-roslyn
      dotnet-sdk
      csharpier
    ];
  };
}
