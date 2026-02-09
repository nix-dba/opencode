FROM docker.io/library/node:24-slim

ARG USER_ID=1000
ARG GROUP_ID=1000

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    curl jq tar git ca-certificates sudo xz-utils binutils wget vim poppler-utils wl-clipboard python3 python3-venv python3-virtualenv procps build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp
RUN LATEST_TYPS_TAG=$(wget -qO- https://api.github.com/repos/typst/typst/releases/latest | \
                 jq -r .tag_name) && \
    wget https://github.com/typst/typst/releases/download/${LATEST_TYPS_TAG}/typst-x86_64-unknown-linux-musl.tar.xz && \
    tar -xf typst-x86_64-unknown-linux-musl.tar.xz && \
    mv typst-x86_64-unknown-linux-musl/typst /usr/local/bin/typst && \
    chmod +x /usr/local/bin/typst && \
    rm typst-x86_64-unknown-linux-musl.tar.xz && \
    rm -rf /tmp/*

RUN wget https://github.com/zellij-org/zellij/releases/latest/download/zellij-x86_64-unknown-linux-musl.tar.gz \
    && tar -xvf zellij-x86_64-unknown-linux-musl.tar.gz \
    && chmod +x zellij \
    && mv zellij /usr/local/bin/

RUN npm install -g @ai-sdk/openai-compatible
RUN npm install -g opencode-ai@latest

# Delete the existing 'node' user to prevent ID collisions
RUN userdel -r node 2>/dev/null || true

# Handle Group: If GID exists (e.g. 20), rename it; otherwise create it
RUN if getent group "${GROUP_ID}"; then \
      groupmod -n developer $(getent group "${GROUP_ID}" | cut -d: -f1); \
    else \
      groupadd -g "${GROUP_ID}" developer; \
    fi

# create user
RUN useradd -l -u "${USER_ID}" -g "${GROUP_ID}" -m -s /bin/bash developer && \
    echo "developer ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN curl -L https://github.com/DavHau/nix-portable/releases/latest/download/nix-portable-$(uname -m) > /usr/bin/nix-portable
RUN chmod +x /usr/bin/nix-portable

USER developer

RUN mkdir -p /home/developer/.cache/zellij/$(zellij --version | cut -d ' ' -f 2) \
    && mkdir -p /home/developer/.config/zellij \
    && touch /home/developer/.cache/zellij/$(zellij --version | cut -d ' ' -f 2)/seen_release_notes

RUN cat > /home/developer/.config/zellij/config.kdl << 'EOF'
show_startup_tips false
show_release_notes false
default_shell "bash"
copy_command "wl-copy"
default_mode "locked"
EOF

RUN cat > /home/developer/.config/zellij/layout.kdl << 'EOF'
layout {
    pane {
        command "/bin/bash"
        args "-c" "opencode"
    }
    pane size=1 borderless=true {
        plugin location="zellij:status-bar"
    }
}
EOF

RUN mkdir -p /home/developer/.config/opencode \
    && mkdir -p /home/developer/.cache/opencode \
    && mkdir -p /home/developer/.locale/share/opencode \
    && mkdir -p /home/developer/.locale/state/opencode

ENV NP_GIT=/usr/bin/git
ENV NP_LOCATION=/workspace

ENV XDG_CONFIG_HOME="/home/developer/.config"
ENV XDG_DATA_HOME="/home/developer/.local/share"
ENV XDG_STATE_HOME="/home/developer/.local/state"
ENV XDG_CACHE_HOME="/home/developer/.cache"

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

RUN opencode upgrade
RUN chmod -R 777 /home/developer

ENV PATH="/home/developer/.cargo/bin/:$PATH:/home/developer/.local/bin"

# fix permission issue when mounting wayland cliboard share
ENV ZELLIJ_SOCKET_DIR=/tmp/zellij

WORKDIR /workspace

#CMD ["bash"]
CMD ["zellij", "--layout", "/home/developer/.config/zellij/layout.kdl"]
