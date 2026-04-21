{
  description = "OpenCode";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    llm-agents.url = "github:numtide/llm-agents.nix";
  };

  outputs = { self, nixpkgs, llm-agents }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
    };

    sandbox = pkgs.writeShellApplication {
      name = "sandbox";
      runtimeInputs = [ pkgs.bash pkgs.bubblewrap pkgs.bun llm-agents.packages.${system}.opencode llm-agents.packages.${system}.skills-installer pkgs.git pkgs.wl-clipboard ];
      text = builtins.readFile ./sandbox.sh;
    };
  in {
    apps.${system}.default = {
      type = "app";
      program = "${sandbox}/bin/sandbox";
    };
  };
}
