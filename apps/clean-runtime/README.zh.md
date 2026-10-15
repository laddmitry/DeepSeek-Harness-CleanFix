---
kind: package-reference
description: 通过统一依赖清单部署完整的已清理 Web、headless、SDK 和 ACP 运行时。
---

# 清理版运行时闭包

[English](README.md) | 中文

此私有依赖清单用于清理版安装套件。它包含 Python 运行时闭包、Web 界面及前端资源、TypeScript SDK 客户端和所需的工作区 peer。Python wheel 较小的运行时清单保持独立。

构建仓库后执行部署：

```sh
pnpm --filter dsh-clean-runtime-closure deploy --prod --offline --ignore-scripts <destination>
```

CLI 入口为 `node_modules/@deepseek-ai/dsh/lib/bin.js`。传输部署时保留内部包链接；验证文件哈希后再重建链接。使用安装套件单独安装和测试经过身份验证的 Windows worker。

使用 `node --import tsx/esm scripts/verify-runtime-closure.ts --manifest apps/clean-runtime/package.json` 检查闭包。依赖检查成功不代表模型、worker、浏览器或网络隔离行为正确；必须从部署目录运行各个已提供的 profile。
