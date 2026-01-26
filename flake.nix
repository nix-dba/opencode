{
  description = "OpenCode";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
    };
    
    opencodeApp = pkgs.writeShellApplication {
      name = "opencode";
      runtimeInputs = [ pkgs.podman ];
      text = ''
        if ! test -f "$HOME/.config/containers/policy.json"; then
          mkdir -p "$HOME/.config/containers"
          install -m 644 ${pkgs.skopeo.src}/default-policy.json \
            "$HOME/.config/containers/policy.json"
        fi

        for entry in ".bun" ".cache" ".config" ".local"; do
          grep -q "^$entry$" .gitignore 2>/dev/null || echo "$entry" >> .gitignore
        done

        if [ ! -d "$HOME/.config/opencode" ]; then
          mkdir -p "$HOME/.config/opencode"
        fi

        podman pull ghcr.io/anomalyco/opencode:latest
        exec podman run --userns=keep-id --rm=true -ti --tmpfs /tmp \
          -v "$PWD:/data" -v "$HOME/.config/opencode:/config" --workdir /data \
          -e OPENCODE_CONFIG_DIR=/config \
          ghcr.io/anomalyco/opencode:latest "$@"
      '';
    };
  in {
    apps.${system}.default = {
      type = "app";
      program = "${opencodeApp}/bin/opencode";
    };
  };
}
