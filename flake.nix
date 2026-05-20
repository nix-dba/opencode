{
  description = "OpenCode";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    llm-agents.url = "github:numtide/llm-agents.nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      llm-agents,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
      };

      sandbox = pkgs.writeShellApplication {
        name = "sandbox";
        runtimeInputs = [
          pkgs.bash
          pkgs.bubblewrap
          pkgs.bun
          llm-agents.packages.${system}.opencode
          llm-agents.packages.${system}.skills-installer
          llm-agents.packages.${system}.gitnexus
          pkgs.git
          pkgs.wl-clipboard
        ];
        text = ''
          export SKILL_DIR="${./default/skill}"
          export COMMANDS_DIR="${./default/command}"
          export PROMPTS_DIR="${./default/prompts}"
          export OPENCODE_JSONC="${./default/opencode.jsonc}"
        '' + builtins.readFile ./sandbox.sh;
      };
    in
    {
      apps.${system}.default = {
        type = "app";
        program = "${sandbox}/bin/sandbox";
      };
      formatter.${system} = pkgs.writeShellApplication {
        name = "nixfmt-wrapper";
        runtimeInputs = [
          pkgs.findutils
          pkgs.nixfmt
        ];
        text = ''
          if [ $# -eq 0 ]; then
            find . -name '*.nix' -exec nixfmt {} +
          else
            nixfmt "$@"
          fi
        '';
      };
    };
}
