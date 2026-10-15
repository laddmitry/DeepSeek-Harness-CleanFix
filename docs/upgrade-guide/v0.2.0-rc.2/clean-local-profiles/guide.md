---
kind: upgrade-guide
description: The cleaned distribution uses a direct local model endpoint and rejects incomplete Windows worker deployments at startup.
---

# Clean local profiles

English | [中文](guide.zh.md)

## Change

The default model endpoint changes from the laboratory gateway at port 8000 to Ollama at `http://127.0.0.1:11434/v1`, with model `qwen3:0.6b`. The CLI allows outbound TCP only to the configured literal loopback or private IPv4 endpoint. Existing remote URLs, DNS names and proxies fail. Windows worker, sandbox and model-provider failures now reject startup. The `sdk` and `acp` profiles and ordered user overlays are available; DeepSeek exporters and arbitrary execution remain denied.

## Migration

1. Set `DSH_LOCAL_MODEL_BASE_URL` and `DSH_LOCAL_MODEL_NAME` to the API and model you operate. Set `LOCAL_MODEL_API_KEY` when that server requires authentication; otherwise the launcher supplies a synthetic local key.
2. Set `DSH_LOCAL_MODEL_CONTEXT_WINDOW` and `DSH_LOCAL_MODEL_MAX_TOKENS` to the model's configured capacities. Configure Ollama's actual context window separately to match.
3. Provision the authenticated Windows worker using the installation kit. Point `DSH_WORKER_CREDENTIAL_FILE` at its controller-private credential file. Protect source, tools and credentials from worker writes.
4. Restart the CLI after changing the model endpoint. Run `dsh --profile headless` with a synthetic write/read task, then validate `dsh --profile sdk` with your JSON-RPC client. Collect session logs and `DSH_NETWORK_LOG`; a text reply alone does not validate tool execution or subprocess network isolation.

The TypeScript and Python SDK defaults now select the local adapter. SDK initialization never mounts a DeepSeek adapter implicitly; use the modified SDK source and explicitly point it at the cleaned CLI rather than installing the upstream published runtime. Qwen3 defaults to `reasoning_effort: none`; override `DSH_LOCAL_MODEL_REASONING` only when your server supports the selected value. Instruction and skill discovery respect provider boundaries. Permission presets use the shared file policy without requiring shell execution; Auto and full access stay forbidden.
