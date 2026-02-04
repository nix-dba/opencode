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

        for entry in ".nix-portable" ".cache"; do
          grep -q "^$entry$" .gitignore 2>/dev/null || echo "$entry" >> .gitignore
        done

        mkdir -p "$HOME/.config/opencode"
        mkdir -p "$HOME/.locale/share/opencode"
        mkdir -p "$HOME/.local/state/opencode"
        mkdir -p "$HOME/.cache/opencode"
        
        CONTAINER="ghcr.io/nix-dba/opencode:dev"

        podman pull $CONTAINER
        exec podman run \
          --userns="keep-id:uid=$(id -u),gid=$(id -g)" \
          --user="$(id -u):$(id -g)" \
          --rm=true \
          -ti \
          --tmpfs /tmp \
          -e WAYLAND_DISPLAY=$WAYLAND_DISPLAY \
          -e XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR \
          -v $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY:$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY \
          -v "$PWD:/workspace" \
          -v "$HOME/.config/opencode:/home/developer/.config/opencode:Z" \
          -v "$HOME/.cache/opencode:/home/developer/.cache/opencode:Z" \
          -v "$HOME/.local/share/opencode:/home/developer/.local/share/opencode:Z" \
          -v "$HOME/.local/state/opencode:/home/developer/.local/state/opencode:Z" \
          --workdir /workspace \
          -e NODE_TLS_REJECT_UNAUTHORIZED=0 \
          $CONTAINER "$@"
      '';
    };
  in {
    apps.${system}.default = {
      type = "app";
      program = "${opencodeApp}/bin/opencode";
    };
  };
}
