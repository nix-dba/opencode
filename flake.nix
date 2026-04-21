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
      runtimeInputs = [ pkgs.podman pkgs.git ];
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
        mkdir -p "$HOME/.opencode"
        mkdir -p "$HOME/.local/share/opencode"
        mkdir -p "$HOME/.local/state/opencode"
        mkdir -p "$HOME/.cache/opencode"
        mkdir -p "$HOME/.cache/opencode/containers"
        
        CONTAINER="ghcr.io/nix-dba/opencode:dev"

        podman pull $CONTAINER

        if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
          read -r -p "$PWD is not a git repo. Initialize repository now? (y/N): " answer
          case "$answer" in
            [Yy]* )
              git init
              git add --all .
              echo "Initialized empty git repository"
              ;;
            * )
              echo "Skipped git init"
              ;;
          esac
        fi

        if [ -v WAYLAND_DISPLAY ]; then
          echo "We pass WAYLAND_DISPLAY to container to share clipboard with host"
          exec podman run \
            --userns="keep-id:uid=$(id -u),gid=$(id -g)" \
            --user="$(id -u):$(id -g)" \
            --rm=true \
            -ti \
            --tmpfs /tmp \
            --device=/dev/fuse \
            --security-opt label=disable \
            --cap-add=SYS_ADMIN \
            -e WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
            -v "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY:/home/developer/.xdg-runtime/$WAYLAND_DISPLAY:z" \
            -v "$PWD:/workspace" \
            -v "$HOME/.opencode:/home/developer/.opencode:Z" \
            -v "$HOME/.config/opencode:/home/developer/.config/opencode:Z" \
            -v "$HOME/.cache/opencode:/home/developer/.cache/opencode:Z" \
            -v "$HOME/.local/share/opencode:/home/developer/.local/share/opencode:Z" \
            -v "$HOME/.local/state/opencode:/home/developer/.local/state/opencode:Z" \
            -v "$HOME/.cache/opencode/containers:/home/developer/.local/share/containers" \
            -v "/etc/ssl/certs:/etc/ssl/certs:ro" \
            --workdir /workspace \
            -e NODE_TLS_REJECT_UNAUTHORIZED=0 \
            $CONTAINER "$@"
        else
          exec podman run \
            --userns="keep-id:uid=$(id -u),gid=$(id -g)" \
            --user="$(id -u):$(id -g)" \
            --rm=true \
            -ti \
            --tmpfs /tmp \
            --device=/dev/fuse \
            --security-opt label=disable \
            --cap-add=SYS_ADMIN \
            -v "$PWD:/workspace" \
            -v "$HOME/.opencode:/home/developer/.opencode:Z" \
            -v "$HOME/.config/opencode:/home/developer/.config/opencode:Z" \
            -v "$HOME/.cache/opencode:/home/developer/.cache/opencode:Z" \
            -v "$HOME/.local/share/opencode:/home/developer/.local/share/opencode:Z" \
            -v "$HOME/.local/state/opencode:/home/developer/.local/state/opencode:Z" \
            -v "$HOME/.local/share/containers:/home/developer/.local/share/containers" \
            -v "/etc/ssl/certs:/etc/ssl/certs:ro" \
            --workdir /workspace \
            -e NODE_TLS_REJECT_UNAUTHORIZED=0 \
            $CONTAINER "$@"
        fi
      '';
    };
  in {
    apps.${system}.default = {
      type = "app";
      program = "${opencodeApp}/bin/opencode";
    };
  };
}
