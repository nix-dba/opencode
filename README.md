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
        "GLM-4.7-Flash": {
          "name": "GLM-4.7-Flash",
          "limit": {
            "context": 65536,
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
models-max = 1
models-autoload = 0
sleep-idle-seconds = 180
warmup = 0
fit = 1
mmap = 1
main-gpu = 0
fit-target = 512

[GLM-4.7-Flash]
hf-repo = unsloth/GLM-4.7-Flash-GGUF
hf-file = GLM-4.7-Flash-UD-Q4_K_XL.gguf
model = /models/GLM-4.7-Flash-UD-Q4_K_XL.gguf
temp = 1.0
min-p = 0.01
top-p = 0.95
flash-attn = 1
ctx-size = 65536
jinja = 1
ubatch-size = 256
repeat-penalty = 1.0
batch-size = 1024
split-mode = none

[gpt-oss-20b]
hf-repo = unsloth/gpt-oss-20b-GGUF
hf-file = gpt-oss-20b-F16.gguf
model = /models/gpt-oss-20b-F16.gguf
ctx-size = 65536
temp = 1.0
min-p = 0.0
top-p = 1.0
top-k = 0.0
split-mode = none

[gpt-oss-120b]
hf-repo = unsloth/gpt-oss-120b-GGUF
hf-file = gpt-oss-120b-F16.gguf
model = /models/gpt-oss-120b-F16.gguf
ctx-size = 65536
temp = 1.0
min-p = 0.0
top-p = 1.0
top-k = 0.0
override-tensor = .ffn_(up)_exps.=CPU
split-mode = layer

[Qwen3-Coder-30B-A3B-Instruct]
hf-repo = unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF
hf-file = Qwen3-Coder-30B-A3B-Instruct-UD-Q4_K_XL.gguf
model = /models/Qwen3-Coder-30B-A3B-Instruct-UD-Q4_K_XL.gguf
jinja = 1
ctx-size = 65536
temp = 0.7
min-p = 0.0
top-p = 0.80
top-k = 20
repeat-penalty = 1.05
split-mode = none

[Qwen3-VL-8B-Instruct]
hf-repo = unsloth/Qwen3-VL-8B-Instruct-GGUF
hf-file = Qwen3-VL-8B-Instruct-UD-Q4_K_XL.gguf
model = /models/Qwen3-VL-8B-Instruct-UD-Q4_K_XL.gguf
mmproj-url = https://huggingface.co/unsloth/Qwen3-VL-8B-Instruct-GGUF/resolve/main/mmproj-F16.gguf
mmproj = /models/mmproj-F16.gguf
jinja = 1
ctx-size = 8192
temp = 1.0
min-p = 0.0
top-p = 0.95
top-k = 20
flash-attn = 1
presence-penalty = 0.0
split-mode = none

[Devstral-Small-2]
hf-repo = unsloth/Devstral-Small-2-24B-Instruct-2512-GGUF
hf-file = Devstral-Small-2-24B-Instruct-2512-UD-Q4_K_XL.gguf
model = /models/Devstral-Small-2-24B-Instruct-2512-UD-Q4_K_XL.gguf
mmproj-url = https://huggingface.co/unsloth/Devstral-Small-2-24B-Instruct-2512-GGUF/resolve/main/mmproj-F16.gguf
mmproj = /models/Devstral-Small-2-24B-Instruct-2512-mmproj-F16.gguf
jinja = 1
ctx-size = 65536
temp = 0.15
min-p = 0.01
split-mode = layer
main-gpu = 0
tensor-split = 4,1

[Qwen3-Coder-Next]
hf-repo = unsloth/Qwen3-Coder-Next-GGUF
hf-file = Qwen3-Coder-Next-UD-Q4_K_XL.gguf
model = /models/Qwen3-Coder-Next-UD-Q4_K_XL.gguf
jinja = 1
ctx-size = 65536
temp = 1.0
top-p = 0.95
min-p = 0.01
top-k = 40
main-gpu = 0
split-mode = layer
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
