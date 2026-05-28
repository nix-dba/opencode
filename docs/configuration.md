# Configuration

## opencode.jsonc

File: `default/opencode.jsonc`

General opencode configuration:
- **autoupdate**: `true` -- auto-update opencode
- **plugin**: `opencode-omniroute-auth@v1.1.4` -- authentication plugin for omniroute
- **mcp.gitnexus**: Local MCP server running `gitnexus mcp`
- **permission.external_directory**: Allows access to `**/.opencode/**` and `**/.gitnexus/**`
- **instructions**: Loads three prompt files: `general.md`, `gitnexus.md`, `karpathy.md`

## Zellij Layout

File: `default/layout.kdl`

A minimal Zellij layout with two panes:
1. Main pane running `opencode` via bash
2. Borderless status bar pane (1 line)

## tuicr Config

File: `default/tuicr/config.toml`

Code review TUI settings:
- `diff_view = "side-by-side"`
- `appearance = "dark"`
- `mouse = true`
- `leader = ","`
- `review_watch_interval_ms = 1000`

## Nix Flake

File: `flake.nix`

Flake outputs:
- `devShells.default` -- shell with all dependencies (bash, bubblewrap, bun, opencode, gitnexus, tuicr, zellij, git, wl-clipboard, uv)
- `apps.default` -- runs `sandbox` script
- `formatter.default` -- `nixfmt` wrapper (formats all `*.nix` files or specified paths)

Flake inputs:
- `nixpkgs` (nixpkgs-unstable)
- `llm-agents.nix` (provides opencode, gitnexus, tuicr packages)

Extra substituter: `https://cache.numtide.com`

## Provider Configuration

Example `~/.config/opencode/opencode.json` for a llama.cpp endpoint:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "llama.cpp": {
      "name": "llama-server",
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "https://llama-cpp.k8s.lan/v1"
      },
      "models": {
        "Qwen3.5-27B-Q3-KV8": {
          "name": "Qwen3.5-27B-Q3-KV8",
          "modalities": {
            "input": ["text"],
            "output": ["text"]
          },
          "limit": {
            "context": 240000,
            "output": 65536
          }
        },
        "Gemma4-31B-Q3-KV8": {
          "name": "Gemma4-31B-Q3-KV8",
          "modalities": {
            "input": ["text"],
            "output": ["text"]
          },
          "limit": {
            "context": 150000,
            "output": 65536
          }
        }
      }
    }
  }
}
```

When integrated with omni-route:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "omniroute": {
      "options": {
        "baseURL": "https://omni-route.k8s.lan/v1",
        "apiMode": "chat",
        "refreshOnList": true,
        "modelCacheTtl": 300000,
        "modelMetadata": {
          "gpu/Qwen3.6-35B-A3B-Q4-KV8": {
            "contextWindow": 262144
          },
          "gpu/Qwen3.6-27B-Q4-KV8-MTP": {
            "contextWindow": 170000
          }
        }
      }
    }
  },
  "plugin": ["opencode-omniroute-auth"]
}
```

### LLaMa.cpp Server Config

Example `config.ini` for a NVIDIA RTX 3090:

```ini
[*]
models-autoload = 0
sleep-idle-seconds = 600
warmup = 0
fit = 1
mmap = 0
fit-target = 400
cache-ram = 16384
parallel = 1
ctx-checkpoints = 128
cache-prompt = 1

[Gemma4-31B-Q3-KV8]
hf-repo = unsloth/gemma-4-31B-it-GGUF
hf-file = gemma-4-31B-it-UD-Q3_K_XL.gguf
jinja = 1
ctx-size = 150000
temp = 1.0
top-p = 0.95
top-k = 64
main-gpu = 0
cache-type-k = q8_0
cache-type-v = q8_0
no-mmproj = 1
flash-attn = 1
split-mode = none

[Qwen3.6-35B-A3B-Q4-KV8]
hf-repo = unsloth/Qwen3.6-35B-A3B-GGUF
hf-file = Qwen3.6-35B-A3B-UD-Q4_K_S.gguf
jinja = 1
ctx-size = 262144
temp = 0.7
min-p = 0.0
top-p = 0.95
top-k = 20
presence-penalty = 1.5
repeat-penalty = 1.0
main-gpu = 0
cache-type-k = q8_0
cache-type-v = q8_0
split-mode = none

[Qwen3.6-27B-Q4-KV8-MTP]
hf-repo = unsloth/Qwen3.6-27B-MTP-GGUF
hf-file = Qwen3.6-27B-IQ4_NL.gguf
jinja = 1
ctx-size = 170000
temp = 0.6
min-p = 0.0
top-p = 0.95
top-k = 20
presence-penalty = 0.0
repeat-penalty = 1.0
main-gpu = 0
cache-type-k = q8_0
cache-type-v = q8_0
no-mmproj = 1
split-mode = none
spec-type = draft-mtp
spec-draft-n-max = 3
draft-p-min = 0.0
reasoning-format = deepseek
```

### llama-cpp Server (Kubernetes)

```yaml
app:
  image:
    repository: ghcr.io/ggml-org/llama.cpp
    tag: "server-cuda"
  env:
    NVIDIA_VISIBLE_DEVICES: all
    NVIDIA_DRIVER_CAPABILITIES: all
    LLAMA_CACHE: "/models"
  args:
    - --port
    - "8080"
    - --host
    - 0.0.0.0
    - --models-preset
    - /models/config.ini
```

### Nginx Relay

```nginx
http {
  server {
    listen 8080;
    server_name _;

    location / {
      proxy_pass https://llama-cpp.$TAILNET_ID.ts.net;
      proxy_set_header Host llama-cpp.$TAILNET_ID.ts.net;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto http;
      proxy_ssl_server_name on;
    }
  }
}
```
