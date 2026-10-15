---
kind: upgrade-guide
description: 清理后的发行版使用直接本地模型端点，并在 Windows 工作进程部署不完整时拒绝启动。
---

# 本地清理配置

[English](guide.md) | 中文

## 变更

默认端点从端口 8000 的实验网关改为 `http://127.0.0.1:11434/v1`，模型为 `qwen3:0.6b`。CLI 出站 TCP 只能访问已配置的字面量回环地址或私有 IPv4 地址。远程 URL、DNS 名称和代理不可用。Windows 工作进程、沙箱或模型提供者失败会阻止启动。`sdk`、`acp` 和用户叠加配置现已支持；DeepSeek 数据导出及任意执行仍被拒绝。

## 迁移

1. 将 `DSH_LOCAL_MODEL_BASE_URL` 和 `DSH_LOCAL_MODEL_NAME` 设置为自己运行的 API 和模型。服务器需要认证时设置 `LOCAL_MODEL_API_KEY`；否则启动器提供合成本地密钥。
2. 设置 `DSH_LOCAL_MODEL_CONTEXT_WINDOW` 和 `DSH_LOCAL_MODEL_MAX_TOKENS`。另行配置 Ollama 的实际上下文窗口，使其与声明一致。
3. 使用安装工具包配置 Windows 工作进程，将 `DSH_WORKER_CREDENTIAL_FILE` 指向控制器私有的凭据文件，禁止工作进程修改源码、工具和凭据。
4. 更改端点后重启 CLI。用合成写入和读取任务验证 `dsh --profile headless`，再用 JSON-RPC 客户端验证 `dsh --profile sdk`。保存会话日志和 `DSH_NETWORK_LOG`；纯文本回答无法验证工具执行或子进程网络隔离。

TypeScript 和 Python SDK 默认使用本地适配器。SDK 初始化不会隐式挂载 DeepSeek 适配器；请使用修改后的 SDK 源码，并明确指定清理后的 CLI，而不是安装上游已发布的运行时。Qwen3 默认发送 `reasoning_effort: none`；仅在服务器支持所选值时覆盖 `DSH_LOCAL_MODEL_REASONING`。指令和技能发现遵守提供方边界。权限预设使用共享文件策略，不依赖 shell 执行；仍禁止 Auto 和完全访问。
