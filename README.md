# OpenCode

Run opencode in sandboxed bubblewrap via nix.

## Usage

In your repository root run:

```sh
nix run github:nix-dba/opencode --refresh --accept-flake-config
```

or via backup respository:

```sh
nix run git+https://codeberg.org/nix-dba/opencode --refresh --accept-flake-config
```

## Features

This respository provides my development opencode setup. We package all version pinned so we can roll back in case of broken opencode release by specify the git hash in the `nix run` command. The nix flake bundels the following additional features:

- [tuicr](https://github.com/agavra/tuicr): A code review TUI with vim keybindings directly integrated into opencode via command `/tuicr`. In `tuicr` use the key `y` to automatically load the annotation to opencode.
- `zellij` to manage the terminal workspace with floting popups for integrated tui applications.
- Sandboxed bubblewrap environment. Reduce the rist of exposing secrets and protect your private data from LLM access.
- [GitNexus](https://github.com/abhigyanpatwari/GitNexus): A client-side knowledge graph creator that runs entirely local. Via integrated `gitnexus` skills the agent has access to every dependency, call chain, cluster, and execution flow so AI agents never miss code.

## Config

Example config for `~/.config/opencode/opencode.json` when using the llama-cpp endpoint direct.

```
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
            "input": [
              "text"
            ],
            "output": [
              "text"
            ]
          },
          "limit": {
            "context": 240000,
            "output": 65536
          }
        },
        "Gemma4-31B-Q3-KV8": {
          "name": "Gemma4-31B-Q3-KV8",
          "modalities": {
            "input": [
              "text"
            ],
            "output": [
              "text"
            ]
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

when integrated into `omni-route`:

```
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

### LLaMa.cpp

Example config for a NVIDIA RTX 3090:

```
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
ctx-checkpoints = 16 # llama-cpp workaround for high ram usage
split-mode = none # use main gpu only

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
no-mmproj = 1
split-mode = none # use main gpu only

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
split-mode = none # use main gpu only
spec-type = draft-mtp
spec-draft-n-max = 3
draft-p-min = 0.0
reasoning-format = deepseek
```

llama-cpp server is started with folowing arg in my k8s server:

```
app:
  image:
    repository:  ghcr.io/ggml-org/llama.cpp
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

#### Relay

Using nginx to relay our tailscale llama.cpp http endpoint to the local network by creating `/etc/nginx/nginx.conf` with the following content:

```
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
