<div align="center">

<img src="docs/images/icon.png" width="88" alt="AICleverYet 波形图标">

# AICleverYet

**今天的 AI，聪明点了吗？**

一个安静待在 Mac 菜单栏里的 GPT IQ 对比工具。<br>
点开，看看同一个模型的哪个推理档位更值得用。

![macOS](https://img.shields.io/badge/macOS-13%2B-111827?logo=apple&logoColor=white) ![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white) [![License: MIT](https://img.shields.io/badge/License-MIT-10B981)](LICENSE) ![Dependencies](https://img.shields.io/badge/第三方依赖-0-10B981)

[界面预览](#preview) · [安装运行](#quick-start) · [省心省流量](#network) · [开发说明](#development)

</div>

## 🧠 为什么做这个？

选好了模型，还得选 `LOW`、`HIGH`、`MAX` 还是 `ULTRA`。

**推理强度拉满，评测分数就一定最高吗？** 与其凭名字猜，不如把同一个模型的各档位摊开来看：IQ、耗时、成本，一行一个。

AICleverYet 的 App 名称是 **GPT IQ**。它读取 [Codex Radar](https://codexradar.com) 的公开评测数据，帮你快速比较档位，再把你关心的分数固定到菜单栏。

> 👑 皇冠给当前数据里的最高分，不给名字听起来最厉害的档位。

<a name="preview"></a>

## 👀 看一眼就懂

<table>
  <tr>
    <th>☀️ 浅色</th>
    <th>🌙 深色</th>
  </tr>
  <tr>
    <td><img src="docs/images/preview-light.png" width="360" alt="浅色面板：同一 GPT 模型的六种推理强度、IQ、耗时与成本对比"></td>
    <td><img src="docs/images/preview-dark.png" width="360" alt="深色面板：最高 IQ 皇冠标记、所选档位和历史趋势"></td>
  </tr>
</table>

*图片由实际 SwiftUI 界面渲染，使用 2026-09-30 的测试样本；不是实时排行榜。*

| 你想知道的 | 打开后能看到的 |
| --- | --- |
| 同一个模型，哪个档位分数高？ | 所有可用推理强度同时列出，最高 IQ 用绿色皇冠标记 |
| 更高分要花多少时间和钱？ | 同行展示平均耗时与评测成本 |
| 我常用的档位最近怎么样？ | 点击该行，查看 24h／7d 变化和近七天曲线 |
| 不想一直开着窗口？ | 所选档位的上次 IQ 留在菜单栏，悬停可看模型与获取时间 |
| 网络暂时不通？ | 保留上次成功结果，显示错误状态与时间 |

<a name="quick-start"></a>

## 🚀 三步跑起来

目前提供**源码构建**，无需 API Key，也不用登录 Codex Radar。无需完整 Xcode。

### 1. 准备环境

需要 **macOS 13+** 和 **Swift 5.9+**。在终端检查：

```sh
swift --version
```

如果尚未安装 Apple Command Line Tools：

```sh
xcode-select --install
```

安装完成后再次检查 Swift 版本。若版本过旧，请更新 Command Line Tools。

### 2. 下载并构建

```sh
git clone https://github.com/lcp2021211/AICleverYet.git
cd AICleverYet
./scripts/build.sh
```

构建完成后，应用位于 `dist/GPT IQ.app`。

### 3. 打开菜单栏 App

```sh
open "dist/GPT IQ.app"
```

菜单栏会出现波形图标和 `IQ`。**第一次点击时才获取数据。** 你也可以把生成的 App 拖进“应用程序”目录。

> 找不到 Dock 图标？这是正常的，它住在菜单栏里。🏠

构建产物对应当前 Mac 的处理器架构；Apple Silicon 已做本机验证，Intel 尚未实机验证。脚本执行本机 ad-hoc 签名，未提供 Developer ID 签名或 Apple 公证的安装包。

## 🎛️ 怎么用

1. **选模型**：顶部下拉菜单切换 GPT，下面一次展示该模型的所有有效档位。
2. **看皇冠**：最高 IQ 高亮显示；同一行对比耗时和成本。
3. **点一行**：将这个档位固定到菜单栏，并切换下方历史趋势。选择会自动保存。

| 操作 | 方式 |
| --- | --- |
| 获取最新数据 | 右上角刷新按钮，或面板内 `⌘R` |
| 收起面板 | 点击外部、再点菜单栏图标，或按 `Esc` |
| 退出 App | 右下角电源按钮，或面板内 `⌘Q` |

首次使用默认选择数据源列出的第一个 GPT 模型及其最高 IQ 档位。皇冠会随数据更新；你手动固定的档位不会因为排名变化而自动跳走。

<a name="network"></a>

## 🍃 你不点它，它就不联网

SwiftUI + AppKit + 系统 Charts。没有浏览器内核，没有第三方运行时，没有后台轮询。

| 场景 | 行为 |
| --- | --- |
| 启动 App / 待在后台 / 从睡眠唤醒 | 不请求数据 |
| 打开面板 | 先显示缓存，仅请求过期的数据 |
| 短时间内反复打开 | 当前数据缓存 **60 秒**，历史数据缓存 **15 分钟** |
| 切换模型或推理档位 | 本地切换，不追加网络请求 |
| 面板一直开着 | 不定时刷新；需要时手动点刷新 |
| 关闭面板 | 取消未完成请求，不接受迟到响应 |
| 主动刷新 | 请求当前与历史数据，带 3 秒防连点保护 |

仅访问两个公开 JSON 接口，最多并发两项请求，不自动重试。历史接口包含较多数据，因此使用更长缓存周期。详细限制见 [数据与网络说明](docs/data-and-network.md)。

App 不收集账号、提示词或聊天内容，也不含分析埋点。它请求公开评测数据，并在本地保存缓存和选项；点击数据源链接会在浏览器中打开 Codex Radar。

## 📏 关于这个「IQ」

**IQ 是 Codex Radar 的评测分数，不是人类智商，也不保证某个档位在你的每个任务上都最好。**

- 当前 IQ 按 **模型 + 推理强度** 匹配；皇冠只比较当前模型的可用档位。
- 历史使用对应的 `模型@推理强度` 序列，不混入模型汇总或 `latest:` 序列。
- `24h / 7d` 显示 **IQ 分数差**，不是涨跌百分比；`≈` 表示使用邻近时间样本，数据不足时直接标明。
- 成本是 **USD / 评测**，当前数据源采用中位数；耗时是 **分钟 / 评测**，不是聊天定价或单次回答延迟。
- “获取于”与“该档位评测更新”分别显示，刚下载的数据不一定是刚完成的评测。

精确计算方式、缓存路径、接口地址见 [数据与网络说明](docs/data-and-network.md)。本项目与 OpenAI、Codex Radar 均无官方隶属关系。

<a name="development"></a>

## 🛠️ 开发与测试

```sh
# 离线检查：使用仓库内的固定样本
swift run --disable-sandbox RadarChecks

# 可选：追加真实公开 API 检查，需要网络
GPT_IQ_LIVE_TEST=1 swift run --disable-sandbox RadarChecks

# 构建可运行的 App
./scripts/build.sh
```

测试程序不依赖 XCTest 或完整 Xcode。覆盖 JSON 解码、空值处理、档位匹配、最高分选择、历史时间窗口、启动零请求、独立缓存周期、关闭取消、立即重开、离线恢复与主动刷新。

生成浅色／深色原生界面预览：

```sh
"dist/GPT IQ.app/Contents/MacOS/GPTIQ" \
  --render-preview Tests/RadarCoreTests/Fixtures dist
```

图片输出到 `dist/preview-light.png` 和 `dist/preview-dark.png`。此模式使用测试样本，不联网。

```text
AICleverYet/
├── Sources/
│   ├── GPTIQ/          # 菜单栏、对比表、趋势与预览
│   └── RadarCore/      # API、数据模型、缓存与请求生命周期
├── Tests/              # 独立测试程序与固定 API 样本
├── Resources/          # macOS 应用信息
├── scripts/            # 构建、生成图标与本机签名
└── docs/               # 界面图片与数据说明
```

## 🤝 一起让它更好用

欢迎 [报告问题](https://github.com/lcp2021211/AICleverYet/issues) 或提交 PR。想法可以很小：更清楚的一列、更顺手的交互、一个被遗漏的边界情况。

提交前请看看 [贡献说明](CONTRIBUTING.md)。有一条朴素的原则：**保持轻量，把网络请求留给用户主动打开面板的时候。**

## 📄 许可与致谢

项目代码使用 [MIT License](LICENSE)。感谢 [Codex Radar](https://codexradar.com) 提供公开评测数据。测试样本与截图的数据来源说明见 [第三方说明](THIRD_PARTY_NOTICES.md)。

<div align="center">

**少猜一个档位，多看一眼数据。** 👑

</div>
