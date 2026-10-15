---
kind: upgrade-guide
description: "LOCAL_ONLY removes arbitrary shell, persistent terminal, and PTC execution from model-facing tools."
---

# LOCAL_ONLY removes arbitrary execution

English | [中文](guide.zh.md)

## Change

The cleaned installation no longer exposes PowerShell, Bash, persistent terminals, PTC, or workflow code execution to agents. Preset preflight refuses these providers and consumers before import; compatibility grants cannot restore them. Windows write-restricted tokens retain unrestricted reads, so disabling execution does not create OS read isolation. Filesystem tools and in-process delegation remain available.

## Migration

1. Replace tasks that depend on shell commands with workspace `read`, `write`, `edit`, `glob`, and `grep` operations. Shell commands that remain necessary require a separate trusted operator process.
2. Keep the reviewed `web` or `headless` installation bundles. User/home patches and CLI overlays cannot restore arbitrary execution.
3. Confirm the actual agent tool registry omits shell, terminal, `run_code`, and workflow tools. Verify workspace file operations and the permitted local model route in the installed runtime; prior-version results do not cover changed bytes.
