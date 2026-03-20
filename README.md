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
        "baseURL": "https://llama-cpp.gpu.lan/v1"
      },
      "models": {
        "Qwen3.5-27B-Q3-KV8": {
          "name": "Qwen3.5-27B-Q3-KV8",
          "modalities": {
            "input": [
              "text",
              "image"
            ],
            "output": [
              "text"
            ]
          },
          "limit": {
            "context": 190000,
            "output": 65536
          }
        }
      }
    }
  }
}
```

### LLaMa.cpp

Example config for my NVIDIA RTX 3090 + NVIDIA P40 setup:

```
[*]
models-autoload = 0
sleep-idle-seconds = 600
warmup = 0
fit = 1
mmap = 0
fit-target = 512

[GLM-4.7-Flash]
hf-repo = unsloth/GLM-4.7-Flash-GGUF
hf-file = GLM-4.7-Flash-UD-Q4_K_XL.gguf
model = /models/GLM-4.7-Flash-UD-Q4_K_XL.gguf
temp = 1.0
min-p = 0.01
top-p = 0.95
flash-attn = 1
ctx-size = 72000
jinja = 1
ubatch-size = 256
repeat-penalty = 1.0
batch-size = 1024
split-mode = none
main-gpu = 0

[Qwen3.5-27B-Q3-KV8]
hf-repo = unsloth/Qwen3.5-27B-GGUF
hf-file = Qwen3.5-27B-UD-Q3_K_XL.gguf
model = /models/Qwen3.5-27B-UD-Q3_K_XL.gguf
mmproj-url = https://huggingface.co/unsloth/Qwen3.5-27B-GGUF/resolve/main/mmproj-F16.gguf
mmproj = /models/Qwen3.5-27B-mmproj-F16.gguf
jinja = 1
ctx-size = 190000
temp = 0.7
min-p = 0.0
top-p = 0.95
top-k = 20
presence-penalty = 0.0
repeat-penalty = 1.0
main-gpu = 0
split-mode = none
cache-type-k = q8_0
cache-type-v = q8_0
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
