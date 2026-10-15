---
description: "离线套件的 `ctx.fs` 后端：供部署方将文件观察与变更限制在固定工作区内。"
kind: "package-reference"
---

# @deepseek-ai/dsh-fs-sandbox

[English](README.md) | 中文

## 概述

`dsh-fs-sandbox` 将读取、元数据、目录列举、监听、写入与编辑限制在 `ctx.sandboxPolicy.workspaceRoot` 配置的部署工作区内。`read-only` 额外拒绝所有变更；`workspace-write` 同时要求部署目录包含关系与逐调用可写策略成立。禁止 `danger-full-access`。离线套件使用本后端替代 `fs-local`；被拒绝的文件操作返回 `FS_SANDBOX_DENIED`。

## 目录

- [使用本包](#use-this-package)
- [理解实现](#understand-the-implementation)
- [进一步探索](#further-exploration)
- [模型体验](#model-experience)
- [已知限制与延期工作](#known-limitations-and-deferred-work)
- [开发备注](#dev-note)

-----

<a id="use-this-package"></a>
## 使用本包

需要将文件观察与变更限制在单一部署工作区时，挂载本后端替代 `fs-local`。会话 cwd、平台临时目录和获批写入授权不能扩大部署工作区。调用会话的策略可以缩小可写集合或选择只读访问。

### 最小组合

先加载共享策略服务，再加载此后端，最后加载工具；编辑前读取策略插件仍为可选。

```yaml
- name: '@deepseek-ai/dsh-sandbox-policy'
- name: '@deepseek-ai/dsh-fs-sandbox'
  config:
    cwd: /absolute/path/to/workspace
- name: '@deepseek-ai/dsh-tool-fs'
```

后端的配置与本地后端完全相同（`cwd` 解析默认值与 `diffBasisMaxBytes` 覆写上限）；[配置目录](../../../docs/config-catalog.zh.md#deepseek-aidsh-fs-sandbox)是完整配置的真源。

### 围栏行为

提供方在解析目标时及每次操作前重新规范化路径，并检查目标位于部署根目录内。调用方直接提供 `FsTarget` 也不能绕过检查。变更还受逐调用模式约束：只读拒绝写入与编辑；workspace-write 将 `writableRoots` 与部署工作区取交集。部署根目录外的临时路径仍被拒绝。完整访问的部署配置和写入模式覆盖均被拒绝。

### 可观察的成功与失败

部署工作区内的读取、列出、元数据与监听保留本地后端行为。目录外访问在委托操作前失败。获批的 workspace-write 覆盖可以在默认只读模式下允许目录内写入，但不能启用完整访问或扩大部署根目录。

-----

<a id="understand-the-implementation"></a>
## 理解实现

<details>
<summary>实现细节——点击展开</summary>

本节解释沙箱后端背后的设计决策，并指出实现它们的代码位置；可观察行为已在[使用本包](#use-this-package)中完整说明。

### 设计理念

围栏是在可信代码中检查模型控制路径的策略，而非内核边界。操作属于 seam 自身（open、rename），只有目标路径不可信，因此「规范化后检查包含关系」就是该接口的完整答案。不可信代码的内核级隔离仍由 `ctx.shell` 负责。

### 源码地图

| 文件 | 职责 |
|---|---|
| [`src/index.ts`](src/index.ts) | `SandboxedFileSystem`：所有文件操作的部署根检查、变更模式检查与 `sandboxMode` 事实 |
| [`src/containment.ts`](src/containment.ts) | 祖先包含检查，带词法快速路径与基于身份的兜底 |

### 变更如何被围栏

每次变更先拒绝完整访问，检查调用方目标位于部署根内，并拒绝只读写入。Workspace-write 随后重新解析显示路径，要求其位于逐调用可写根内。两项包含检查必须同时成立；委托变更使用新的目标。

### 威胁模型

解析到系统调用之间残留的 TOCTOU 通过写入前立即重新规范化来缩小，并为该威胁模型所接受；内核严密边界需要 `openat2` 一类原语，其可移植性成本在此不值。拒绝是结构化 `FsError`，而不是 stderr 推断——进程内围栏准确知道自己拒绝了什么。

</details>

-----

<a id="further-exploration"></a>
## 进一步探索

当包级约定不够用时阅读以下页面。它们从本后端逐步进入共享策略归属及其背后的隔离决策。

- [文件系统子系统](../../../docs/subsystems/filesystem.zh.md)——穷尽式提供方约定、策略事件与错误分类体系。
- [dsh-fs](../fs/README.zh.md)——本后端实现的 `ctx.fs` 约定。
- [fs-local](../fs-local/README.zh.md)——本后端扩展的本地后端。
- [sandbox-policy](../../sandbox/sandbox-policy/README.zh.md)——本后端所需的共享逐会话策略解析器。
- [进程沙箱子系统](../../../docs/subsystems/sandbox.zh.md)——模式、逐调用策略与故障关闭错误。
- [跨能力族 fs 沙箱决策](../../../.agents/notes/implemented/feature/2026-07-14-cross-family-fs-sandbox.zh.md)——共享模式围栏及其升级编排。

-----

<a id="model-experience"></a>
## 模型体验

### 文件系统策略与拒绝

#### 模型看到的内容

策略归属方贡献与具体能力无关的 `sandbox:policy` 上下文。作为间接影响，`dsh-tool-fs` 会把本后端的 `FS_SANDBOX_DENIED` 拒绝渲染为 `[sandbox: file access denied under <mode> mode]` 标记和同轮次升级提示。

#### Token 影响

该后端挂载期间，当前策略条款会增加一条简短的运行时上下文消息；拒绝则会把有界标记与升级提示追加到对话历史。

#### KV Cache 影响

常驻策略发生变化时，会在保留的历史之后追加一份由归属方渲染、取代先前状态的运行时上下文快照；操作结果保持仅追加。

## 已知限制与延期工作

<a id="known-limitations-and-deferred-work"></a>


这些限制说明沙箱后端何时不合适，或何时需要特别的运维注意。它们是当前包约束，不是通用沙箱对比或任务积压。

- **策略围栏，而非内核边界**：该检查是可信代码处理模型控制的路径，因此解析到系统调用之间残留的 TOCTOU 会被原位重新规范化缩小，但不会消除；对抗性宿主进程不在范围内。不可信代码的内核级隔离仍属于 `ctx.shell`。
- **文件访问比进程临时目录授权更窄**：即使 `writableRoots` 允许部署根外的临时区域，部署根检查仍然生效。
- **要求 `ctx.sandboxPolicy`**：工具使用它解析每个会话策略，后端用它处理无 agent（智能体）调用的回退；未组合该服务时，后端不会实施约束。

<a id="dev-note"></a>
### 开发备注

<details>
<summary>维护者的工作上下文——点击展开</summary>

无。

</details>

**运行时不变式：** 不发布伴生入口。这个无状态适配器把策略与文件系统关系委托给各自所属的 seam。
