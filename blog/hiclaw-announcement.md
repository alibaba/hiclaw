# HiClaw：OpenClaw 超进化，更安全更易用，5 分钟打造出一人公司

> 发布日期：2026 年 2 月 27 日

---

## 你是否也曾这样？

作为 OpenClaw 的深度用户，我深刻体会到它的强大——一个 Agent 就能帮你写代码、查邮件、操作 GitHub。但当你开始做更复杂的项目时，问题就来了：

**安全问题让人睡不着**：每个 Agent 都要配置自己的 API Key，GitHub PAT、LLM Key 散落各处。2026 年 1 月的 CVE-2026-25253 漏洞让我意识到，这种 "self-hackable" 架构在便利的同时也带来了风险。

**一个 Agent 承担太多角色**：让它做前端，又做后端，还要写文档。`skills/` 目录越来越乱，`MEMORY.md` 里混杂各种记忆，每次加载都要塞一大堆无关上下文。

**想指挥多个 Agent 协作，但没有好工具**：手动配置、手动分配任务、手动同步进度……你想专注于业务决策，而不是当 AI 的"保姆"。

**移动端体验一言难尽**：想在手机上指挥 Agent 干活，却发现飞书、钉钉的机器人接入流程要几天甚至几周。

如果你有同感，那 **HiClaw** 就是为而生的。

---

## HiClaw 是什么？

**HiClaw = OpenClaw 超进化**

核心创新是引入 **Manager Agent** 角色——你的 "AI 管家"。它不直接干活，而是帮你管理一批 Worker Agent。

```
┌─────────────────────────────────────────────────────┐
│                   你的本地环境                       │
│  ┌───────────────────────────────────────────────┐ │
│  │           Manager Agent (AI 管家)             │ │
│  │                    ↓ 管理                     │ │
│  │    Worker Alice    Worker Bob    Worker ...   │ │
│  │    (前端开发)       (后端开发)                  │ │
│  └───────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
         ↑
    你（真人管理员）
    只需做决策，不用当保姆
```

---

## 技术架构：OpenClaw 的"器官移植"

OpenClaw 的设计就像一个完整的生物体：有**大脑**（LLM）、**中枢神经系统**（pi-mono）、**眼睛和嘴**（各种 Channel）。但原生设计中，大脑和感知器官都是"外接"的——你需要自己去配置 LLM Provider、去对接各种消息渠道。

HiClaw 做了一次"器官移植"手术，把这些外接组件变成**内置器官**：

```
┌────────────────────────────────────────────────────────────────────┐
│                         HiClaw All-in-One                          │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │                     OpenClaw (pi-mono)                       │ │
│  │                      中枢神经系统                             │ │
│  └──────────────────────────────────────────────────────────────┘ │
│           ↑                              ↑                        │
│  ┌────────────────┐              ┌────────────────┐               │
│  │  Higress AI    │              │   Tuwunel      │               │
│  │  Gateway       │              │   Matrix       │               │
│  │  (大脑接入)     │              │   Server       │               │
│  │                │              │   (感知器官)    │               │
│  │  灵活切换       │              │                │               │
│  │  LLM供应商      │              │  Element Web   │               │
│  │  和模型         │              │  Element/Xbox    │               │
│  └────────────────┘              │  (自带客户端)   │               │
│                                  └────────────────┘               │
└────────────────────────────────────────────────────────────────────┘
```

### LLM 接入：Higress AI Gateway

**大脑不再外接，而是通过 AI Gateway 灵活管理**：

- **一个入口，多种模型**：在 Higress 控制台即可切换阿里云通义、OpenAI、Claude 等不同供应商
- **凭证集中管理**：API Key 只需要配置一次，所有 Agent 共享
- **按需授权**：每个 Worker 只获得调用权限，永远接触不到真实的 API Key

### 通信接入：内置 Matrix Server

**感知器官也变成内置的**：

- **Tuwunel Matrix Server**：开箱即用的消息服务器，无需任何配置
- **自带 Element Web 客户端**：浏览器打开就能对话
- **移动端友好**：支持 Element、FluffyChat 等全平台客户端
- **零对接成本**：不需要申请飞书/钉钉机器人，不需要等待审批

> 💡 换个比喻：OpenClaw 原生就像一台组装电脑，你需要自己买显卡（LLM）、显示器（Channel）然后装驱动。HiClaw 则是一台开箱即用的笔记本，所有外设都集成好了，开机就能干活。

---

## Multi-Agent 系统：你的 AI 管家贾维斯

在组件封装的基础上，HiClaw 还实现了一套**开箱即用的 Multi-Agent 系统**——Manager Agent 管理 Worker Agent，就像钢铁侠的管家 **贾维斯** 一样。

### 按需启用，两种模式

这套系统是**按需启用**的，你可以灵活选择：

**模式一：直接对话 Manager**
- 简单任务直接告诉 Manager，它自己处理
- 适合快速问答、简单操作

**模式二：Manager 分派 Worker**
- 复杂任务由 Manager 拆解，分配给专业 Worker
- 每个 Worker 有独立的 Skills 和 Memory
- 技能和记忆**完全隔离**，不会互相污染

### 协作架构：Supervisor + Swarm 的融合

从 Manager-Worker 的角度看，这是一个 **Supervisor 架构**：Manager 作为中心节点协调所有 Worker。但因为基于 Matrix 群聊房间协作，它同时也具备了 **Swarm（蜂群）架构** 的特点。

**共享上下文，无需重复沟通**：每个 Agent 都能看到群聊房间里的完整上下文。Alice 说"我在做登录页面"，Bob 自动知道前端在做什么，API 设计时可以配合。

**防惊群设计**：Agent 只有被 @ 的时候才会触发 LLM 调用，不会因为无关消息被唤醒，成本可控。

**中间产物不污染上下文**：文件交换、代码片段等大量协作通过底层的 **MinIO 共享文件系统** 完成，不会发到群聊里导致上下文膨胀。

### 安全设计：Manager 能管理，但不能泄密

原生 OpenClaw 架构下，每个 Agent 都需要持有真实的 API Key，一旦被攻击或意外输出，凭证就可能泄露。

HiClaw 的解决方案是 **Worker 永远不持有真实凭证**：

```
┌──────────────┐      ┌──────────────────┐      ┌─────────────┐
│   Worker     │─────►│  Higress AI      │─────►│  LLM API    │
│   (只持有    │      │  Gateway         │      │  GitHub API │
│   Consumer   │      │  (凭证集中管理)   │      │  ...        │
│   Token)     │      │                  │      │             │
└──────────────┘      └──────────────────┘      └─────────────┘
```

- Worker 只持有一个 Consumer Token（类似于"工牌"）
- 真实的 API Key、GitHub PAT 等凭证存储在 AI Gateway
- **即使 Worker 被攻击，攻击者也拿不到真实凭证**

Manager 的安全设计同样严格：它知道 Worker 要做什么任务，但不知道 API Key、GitHub PAT。Manager 的职责是"管理和协调"，不直接执行文件读写、代码编写。

| 维度 | OpenClaw 原生 | HiClaw |
|------|--------------|--------|
| 凭证持有 | 每个 Agent 自己持有 | Worker 只持有 Consumer Token |
| 泄漏途径 | Agent 可直接输出凭证 | Manager 无法访问真实凭证 |
| 攻击面 | 每个 Agent 都是入口 | 只有 Manager 需要防护 |

### Human in the Loop：全程透明，随时干预

和 OpenClaw 原生的 Sub Agent 系统相比，HiClaw 的 Multi-Agent 系统不仅更易用，而且**更透明**：

```
┌─────────────────────────────────────────────────────────────┐
│                  Matrix 项目群聊房间                        │
│                                                             │
│  你: 实现一个登录页面                                        │
│                                                             │
│  Manager: 收到，我来分派...                                  │
│           → @alice 前端页面                                  │
│           → @bob 后端 API                                    │
│                                                             │
│  Alice: 正在实现登录组件...                                  │
│  Bob: API 接口已定义好...                                    │
│                                                             │
│  你: @bob 等下，密码规则改成至少8位                          │  ← 随时干预
│                                                             │
│  Bob: 好的，已修改...                                        │
│  Alice: 收到，前端校验也更新了                               │
│                                                             │
│  Manager: 任务完成，请 Review                                │
└─────────────────────────────────────────────────────────────┘
```

**核心优势**：
- **全程可见**：所有 Agent 的协作过程都在 Matrix 群聊里
- **随时介入**：发现问题可以直接 @某个 Agent 修正
- **自然交互**：就像在微信群里和一群同事协作

### Manager 的核心能力

| 能力 | 说明 |
|------|------|
| **Worker 生命周期管理** | "帮我创建一个前端 Worker" → 自动完成配置、技能分配 |
| **自动分派任务** | 你说目标，Manager 拆解并分配给合适的 Worker |
| **Heartbeat 自动监工** | 定期检查 Worker 状态，发现卡住自动提醒你 |
| **项目群自动拉起** | 为项目创建 Matrix Room，邀请相关人员 |

### 移动端体验

HiClaw 内置 Matrix 服务器，支持多种客户端：

- **一键安装后直接用**：无需配置飞书/钉钉机器人
- **手机上随时指挥**：下载 Matrix 客户端（Element、FluffyChat 等）
- **消息实时推送**：不会折叠到"服务号"
- **所有对话可见**：你、Manager、Worker 在同一个 Room，全程透明

> 💡 **移动端**：支持 Element、FluffyChat 等主流 Matrix 客户端，iOS/Android/Web 全平台覆盖。

---

## 5 分钟快速开始

### 第一步：安装

**macOS / Linux：**

```bash
bash <(curl -sSL https://higress.ai/hiclaw/install.sh)
```

**Windows（PowerShell 7+）：**

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://higress.ai/hiclaw/install.ps1'))
```

> ⚠️ Windows 用户需要先安装 **PowerShell 7+** 和 **Docker Desktop**。

安装脚本特点：
- **跨平台**：Mac / Linux 用 bash，Windows 用 PowerShell，体验一致
- **智能检测**：根据时区自动选择最近的镜像仓库
- **Docker 封装**：所有组件跑在容器里，屏蔽操作系统差异
- **最少配置**：只需要一个 LLM API Key，其他都是可选的

安装完成后，你会看到：

```
=== HiClaw Manager Started! ===

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ★ Open the following URL in your browser to start:                           ★
                                                                                
    http://127.0.0.1:18088/#/login
                                                                                
  Login with:                                                                   
    Username: admin
    Password: [自动生成的密码]
                                                                                
  After login, start chatting with the Manager!                                 
    Tell it: "Create a Worker named alice for frontend dev"                     
    The Manager will handle everything automatically.                           
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

> 💡 **无需配置 hosts**：`*-local.hiclaw.io` 会自动解析到 `127.0.0.1`，开箱即用！

### 第二步：登录开始对话

1. 打开浏览器访问安装时显示的 URL（如 `http://127.0.0.1:18088`）
2. 输入安装时显示的用户名和密码登录
3. 你会看到一个 "Manager" 的对话

### 第三步：创建你的第一个 Worker

```
你: 帮我创建一个 Worker，名字叫 alice，负责前端开发

Manager: 好的，正在创建...
         Worker alice 已创建，Room: !xxx:matrix-local.hiclaw.io
         你可以在 "Worker: Alice" Room 里直接给 alice 分配任务
```

### 第四步：分配任务

```
你: @alice 请帮我实现一个简单的登录页面，使用 React

Alice: 好的，我正在处理...
       [几分钟后] 完成了！代码已提交到 GitHub，PR 链接: https://github.com/xxx/pull/1
```

### 第五步：在手机上查看进度

1. 下载 Matrix 客户端（Element、FluffyChat 等，支持 iOS/Android/全平台）
2. 登录时选择"其他服务器"，填入你的 Matrix 服务器地址
3. 随时查看 Worker 的进度，随时干预

---

## 一人公司实战：一个人，一支队伍

假设你想做一个 SaaS 产品——从 idea 到上线到增长，传统上你需要产品、设计、开发、测试、运营……但现在你可以这样：

```
你: 帮我创建 4 个 Worker：
    - alex: 产品经理，负责需求分析、竞品调研
    - sam: 全栈开发，前后端都能搞
    - taylor: 内容运营，负责社媒、SEO、增长
    - jordan: 数据分析，负责埋点、报表、洞察

Manager: 好的，已创建 4 个 Worker，各自有独立的技能和记忆。

你: 我们要做一款 AI 写作助手，下周要发 MVP。alex 先出 PRD。

[2 小时后]

alex: PRD 已完成，核心功能：AI 续写、多模型切换、历史记录。
      文档地址：/shared/prd-v1.md
      请 @sam 评估技术可行性

你: 看了 PRD，方向 OK。@sam 你看下

sam: 评估完成。技术栈：Next.js + Vercel + Supabase。
      预计 3 天可完成 MVP。开始动手？

你: 开搞

[3 天后]

Manager: MVP 开发完成
         - sam: 所有功能已实现，已部署到 vercel
         - alex: 产品验收通过
         地址：https://xxx.vercel.app

你: 很好。@taylor 准备上线推广

taylor: 已准备好发布素材：
        - Product Hunt 发布页文案
        - Twitter/X 宣发推文（3 条）
        - 独立开发者社区推广贴
        建议：明天早上 9 点（美西时间）在 PH 上线

[上线当天]

taylor: PH 当日排名第 3！
        - 423 upvotes
        - 87 条评论
        - 首日注册用户：1,247

jordan: 已配置埋点和看板
        - 用户留存（次日）：34%
        - 核心功能使用率：AI 续写 78%，多模型切换 23%
        建议：优先优化多模型切换的引导流程

你: @alex 看下多模型切换的使用数据

alex: 分析完成。问题：用户不知道不同模型的区别。
      建议：增加模型选择引导页 + 使用场景提示。
      PRD 更新：/shared/prd-v2.md

你: 批准。@sam 下个迭代加上

[就这样，你一个人带着 4 个 AI 员工，跑完了产品从 0 到 1 的完整流程]
```

**这不是科幻——是 HiClaw 能让你做到的事。**

---

## 开源地址

- **GitHub**: https://github.com/higress-group/hiclaw
- **文档**: https://github.com/higress-group/hiclaw/tree/main/docs
- **社区**: 加入我们的 Discord / 钉钉群 / 微信群

---

## 写在最后

HiClaw 是对 OpenClaw 的一次"超进化"——不是推翻，而是增强。

我们保留了 OpenClaw 的核心理念（自然语言对话、Skills 生态、MCP 工具），同时解决了安全和易用性上的痛点。

如果你是：
- **独立开发者**：一个人想干一个团队的活
- **OpenClaw 深度用户**：想要更安全、更易用的体验
- **一人公司创始人**：需要 AI 员工帮你分担工作

HiClaw 就是为你准备的。

**现在就开始：**

```bash
bash <(curl -sSL https://higress.ai/hiclaw/install.sh)
```

---

*HiClaw 是开源项目，基于 Apache 2.0 协议。如果你觉得有用，欢迎 Star ⭐ 和贡献代码！*
