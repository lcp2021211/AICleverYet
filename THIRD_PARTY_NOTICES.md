# 第三方数据说明

本项目使用 [Codex Radar](https://codexradar.com) 的公开 JSON API：

- https://api.codexradar.com/api/v1/intelligence-efficiency
- https://api.codexradar.com/api/v1/iq-history

`Tests/RadarCoreTests/Fixtures/efficiency.json` 是 2026-09-30 采集的公开响应；`history.json` 是同日响应中选取的部分序列，用于可重复的离线测试。README 的面板图片使用这些固定样本渲染，不代表实时排名。

本仓库的 MIT 许可证适用于项目代码和原创文档，不代表对第三方评测数据、服务名称或商标授予额外权利。第三方内容的相关权利归其权利人所有。

本项目与 OpenAI、Codex Radar 均无官方隶属关系。数据源的可用性、字段和统计方式可能变化。

## 雷达 Bench 样本（2026-10-11）

`bench-binding.json` 和 `bench-summary.json` 分别来自 Codex Radar 的公开模型配置与 Astra MAX 轻量评分摘要。`bench-preview.json` 与 `bench-preview-history.json` 是同日 Astra 各档位真实摘要的字段投影，用于界面预览，非实时排行。网络单元测试会生成变体以检查空值、身份错误与失败分支。旧 IQ 样本仅用于历史格式回归，不在正常运行中展示。当前接口详见 [数据说明](docs/data-and-network.md)。
