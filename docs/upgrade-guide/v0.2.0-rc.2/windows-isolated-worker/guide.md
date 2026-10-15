---
kind: upgrade-guide
description: "Offline Windows profiles require a separate worker identity and private credentials, and reject unrestricted commands and user terminals."
---

# Offline Windows commands require a separate worker identity

English | [中文](guide.zh.md)

## Change

The offline Windows build replaces same-account command execution with an authenticated worker account. The controller and worker must have different SIDs. Shell, search and PTC launches use the restricted worker token and managed Job; direct controller-user subprocesses, user terminals and `session.openWorkspacePath` desktop execution are rejected. `danger-full-access` is rejected, including explicit grants and restored session overrides. Filesystem tools are limited to the deployment workspace.

This affects the offline `web` and `headless` profiles. The new configuration and native launch paths require isolated Windows 11 VM validation; this guide does not certify runtime behavior or deployment readiness.

## Migration

1. Provision separate standard local accounts, DSHAudit for the controller and DSHAgent for commands. Give only DSHAudit `SeAssignPrimaryTokenPrivilege` and `SeIncreaseQuotaPrivilege`, retain the previous user-rights policy, and start a new controller logon. Neither account may belong to Administrators.
2. Protect `C:/DSH/data/worker-credentials.json` for the controller, SYSTEM and Administrators. Its fields are `username`, `domain`, `password` and `expectedSid`; the expected SID must identify DSHAgent. Keep credentials and controller logs outside the workspace. Do not place credentials in model-visible environment variables or command arguments.
3. In the installation-owned base bundle, set `subprocess.config.windowsWorkerRunner` to the immutable built Windows ACL runner entry. Set both `subprocess.config.windowsWorkerCredentialFile` and `sandbox.config.workerCredentialFile` to the private credential file; caller-supplied credential paths and Node startup environment overrides are rejected. Preserve these fields when replacing a complete row configuration. This build accepts only the reviewed `web`/`headless` bundles and rejects user/home patch layers and CLI overlays.
4. Give the worker ReadAndExecute on source and tools, Modify only on workspace and private-temp roots, and no access to controller data or logs. The controller must own sandbox provisioning roots and have FullControl there. Do not add WRITE_DAC or WRITE_OWNER to worker capability grants. Administrator policy evidence must remain administrator-only.
5. Rebuild and validate the final installation in a clean Windows 11 VM. Confirm worker and grandchild SIDs, shell/search/PTC output and control pipes, workspace writes, protected-token read/write denial, outside-write denial, read-only mode, Job cleanup and network restrictions. A failed authentication, SID/session check or native launch must stop execution; do not restore unrestricted execution or the removed terminal rows to obtain a passing smoke.
