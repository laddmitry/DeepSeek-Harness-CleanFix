---
kind: package-reference
description: Deploy the complete cleaned Web, headless, SDK and ACP runtime from one dependency manifest.
---

# Clean runtime closure

English | [中文](README.zh.md)

This private dependency manifest supplies the cleaned installation kit. It includes the Python runtime closure, the Web surface and frontend assets, the TypeScript SDK client, and their required workspace peers. The Python wheel's smaller runtime manifest remains separate.

Deploy after building the repository:

```sh
pnpm --filter dsh-clean-runtime-closure deploy --prod --offline --ignore-scripts <destination>
```

The CLI entry is `node_modules/@deepseek-ai/dsh/lib/bin.js`. Preserve contained package links when transferring the deployment; verify file hashes before reconstructing them. Install and test the authenticated Windows worker separately using the kit.

Check closure with `node --import tsx/esm scripts/verify-runtime-closure.ts --manifest apps/clean-runtime/package.json`. A successful dependency check does not prove model, worker, browser, or network isolation behavior; exercise each shipped profile from the deployed directory.
