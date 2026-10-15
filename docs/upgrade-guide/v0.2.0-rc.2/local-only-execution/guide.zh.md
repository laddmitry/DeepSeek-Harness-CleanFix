---
kind: upgrade-guide
description: "LOCAL_ONLY 从面向模型的工具中移除任意 shell、持久终端和 PTC 执行。"
---

# LOCAL_ONLY 移除任意执行

[English](guide.md) | 中文

## 变更

清理后的安装不再向代理提供 PowerShell、Bash、持久终端、PTC 或工作流代码执行。预设预检在导入前拒绝这些提供者和工具，兼容性豁免无法恢复它们。Windows 写入受限令牌仍允许不受限制的读取，因此禁用执行不提供操作系统读取隔离。文件系统工具和进程内委派仍可用。

## 迁移

1. 使用工作区的 `read`、`write`、`edit`、`glob` 和 `grep` 操作替换依赖 shell 命令的任务。仍然必要的 shell 命令需要独立的可信操作员进程。
2. 保留经过审查的 `web` 或 `headless` 安装 bundle。用户、home 补丁和 CLI overlay 无法恢复任意执行。
3. 确认实际代理工具注册表不包含 shell、terminal、`run_code` 和 workflow 工具。在已安装运行时验证工作区文件操作及允许的本地模型路由；旧版本结果不覆盖修改后的字节。
