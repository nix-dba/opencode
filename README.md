# OpenCode

Run opencode in sandboxed container via nix.

## Usage

In your repository root run:

```sh
nix run github:nix-dba/opencode
```

to update the flake use:

```sh
nix run github:nix-dba/opencode --refresh
```

## Config

Example config for `~/.config/opencode/opencode.json`

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

### LLaMa.cpp

Example config for my NVIDIA RTX 3090:

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

[Qwen3.5-27B-Q3-KV8]
hf-repo = unsloth/Qwen3.5-27B-GGUF
hf-file = Qwen3.5-27B-UD-Q3_K_XL.gguf
jinja = 1
ctx-size = 240000
temp = 0.7
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
