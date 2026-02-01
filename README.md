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
