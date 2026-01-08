{
  lib,
  buildGoModule,
}:

buildGoModule {
  pname = "llm-key-receiver";
  version = "0.1.0";

  src = ./.;

  vendorHash = "sha256-deZ8L5aju1JraGTnjIW3vR1zm5Jc15F6D+goi1pVLpU=";

  meta = with lib; {
    description = "HTTP server that receives LLM API keys via JWT-authenticated requests";
    license = licenses.mit;
    mainProgram = "llm-key-receiver";
  };
}
