{
  description = "My Sandboxed OpenCode";

  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [ "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    llm-agents.url = "github:numtide/llm-agents.nix";
    opencode-omniroute-auth-src = {
      url = "github:Alph4d0g/opencode-omniroute-auth/release/v1.2.3";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      llm-agents,
      opencode-omniroute-auth-src,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
      };

      lightShellInputs = with pkgs; [
        bash
        bubblewrap
        bun
        llm-agents.packages.${system}.opencode
        llm-agents.packages.${system}.tuicr
        zellij
        git
        wl-clipboard
        uv
        python3
        python3Packages.pyyaml
      ];

      fullShellInputs = lightShellInputs ++ [
        llm-agents.packages.${system}.gitnexus
      ];

      omnirouteAuthPlugin =
        let
          # Source with vendored package-lock.json (required by fetchNpmDeps)
          opencode-omniroute-auth-src-with-lock = pkgs.runCommand "opencode-omniroute-auth-with-lock" { } ''
            cp -r ${opencode-omniroute-auth-src} $out
            chmod -R +w $out
            cp ${./opencode-omniroute-auth-package-lock.json} $out/package-lock.json
          '';
        in
        pkgs.buildNpmPackage {
          name = "opencode-omniroute-auth";
          src = opencode-omniroute-auth-src-with-lock;
          npmDeps = pkgs.fetchNpmDeps {
            src = opencode-omniroute-auth-src-with-lock;
            hash = "sha256-YKhVxYV+Yz05xCmDocVtXhWsK7Olc+rsKRQ45kcacSM=";
          };
          npmFlags = [ "--legacy-peer-deps" ];
          buildPhase = ''
            npm run build
          '';
          installPhase = ''
            mkdir -p $out
            cp -r dist package.json $out/
          '';
        };

      makeSandbox =
        {
          name,
          packages,
          defaultFeatures,
        }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = packages;
          text = ''
            export SKILL_DIR="${./default/skill}"
            export COMMANDS_DIR="${./default/command}"
            export PROMPTS_DIR="${./default/prompts}"
            export OPENCODE_JSONC="${./default/opencode.jsonc}"
            export LAYOUT_KDL="${./default/layout.kdl}"
            export TUICR_CONFIG="${./default/tuicr/config.toml}"
            export MERGE_SCRIPT="${./merge-jsonc.js}"
            export GITNEXUS_DIR="${./gitnexus}"
            export MEMORY_DIR="${./memory}"
            export DEFAULT_FEATURES="${defaultFeatures}"
            export OMNIROUTE_AUTH_PLUGIN="${omnirouteAuthPlugin}"
          ''
          + builtins.readFile ./sandbox.sh;
        };

      sandbox-light = makeSandbox {
        name = "sandbox";
        packages = lightShellInputs;
        defaultFeatures = "";
      };

      sandbox-full = makeSandbox {
        name = "sandbox";
        packages = fullShellInputs;
        defaultFeatures = "gitnexus";
      };
    in
    {
      devShells.${system} = {
        default = pkgs.mkShell {
          buildInputs = lightShellInputs;
        };
        full = pkgs.mkShell {
          buildInputs = fullShellInputs;
        };
      };
      apps.${system} = {
        default = {
          type = "app";
          program = "${sandbox-light}/bin/sandbox";
        };
        full = {
          type = "app";
          program = "${sandbox-full}/bin/sandbox";
        };
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
