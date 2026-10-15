---
kind: upgrade-guide
description: "离线 Windows 配置要求独立的工作进程身份和私有凭据，并拒绝不受限制的命令及用户终端。"
---

# 离线 Windows 命令要求独立的工作进程身份

[English](guide.md) | 中文

## 变更

离线 Windows 构建使用经过身份验证的工作进程账户代替同账户命令执行。控制器与工作进程必须具有不同 SID。Shell、搜索和 PTC 启动使用受限工作进程令牌及托管 Job；直接以控制器用户运行的子进程、用户终端和 `session.openWorkspacePath` 桌面执行被拒绝。`danger-full-access` 被拒绝，包括显式授权和恢复的会话覆盖。文件系统工具仅能访问部署工作目录。

这影响离线 `web` 和 `headless` 配置。新的配置和原生启动路径需要在隔离的 Windows 11 VM 中验证；本指南不证明运行时行为或部署就绪状态。

## 迁移

1. 创建两个独立的标准本地账户：DSHAudit 用于控制器，DSHAgent 用于命令。仅向 DSHAudit 授予 `SeAssignPrimaryTokenPrivilege` 和 `SeIncreaseQuotaPrivilege`，保留原用户权限策略，并重新登录控制器。两个账户都不得属于 Administrators。
2. 将 `C:/DSH/data/worker-credentials.json` 的访问权限限制为控制器、SYSTEM 和 Administrators。其字段为 `username`、`domain`、`password` 和 `expectedSid`；预期 SID 必须标识 DSHAgent。凭据和控制器日志必须位于工作目录之外。不要将凭据放入模型可见的环境变量或命令参数。
3. 在安装所属的 base bundle 中，将 `subprocess.config.windowsWorkerRunner` 设置为不可修改的已构建 Windows ACL runner 入口。将 `subprocess.config.windowsWorkerCredentialFile` 和 `sandbox.config.workerCredentialFile` 都设置为私有凭据文件；调用方提供的凭据路径和 Node 启动环境覆盖被拒绝。替换完整行配置时保留这些字段。此构建仅接受经过审查的 `web`/`headless` bundles，拒绝用户和主目录补丁层及 CLI 覆盖。
4. 向工作进程授予源代码和工具的 ReadAndExecute 权限，仅在工作目录和私有临时目录根上授予 Modify 权限，并禁止访问控制器数据及日志。控制器必须拥有沙箱配置根目录，并在这些目录中具有 FullControl 权限。不要向工作进程能力授权添加 WRITE_DAC 或 WRITE_OWNER。管理员策略证据必须仅供管理员访问。
5. 在干净的 Windows 11 VM 中重新构建并验证最终安装。确认工作进程和后代进程的 SID、shell/search/PTC 输出及控制管道、工作目录写入、受保护令牌读取和写入拒绝、目录外写入拒绝、只读模式、Job 清理及网络限制。身份验证、SID/session 检查或原生启动失败时必须停止执行；不要为了让 smoke 通过而恢复不受限制的执行或被移除的终端行。
