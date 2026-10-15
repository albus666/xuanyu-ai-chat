# 客户端结构与维护约定

## 实际主链路

`main.dart` → 启动状态及路由 → 功能页面 → `core/network/api_client.dart` → Django API。

`app/pages/system/login/controller.dart` 保存 Token 并设置网络层；`features/message/ai_master_chat_page.dart` 负责 AI 对话请求及 SSE 解析。

## 渐进整理建议

- `app/` 与 `features/` 都包含现用代码，不批量移动或删除前者。
- 新业务优先放对应 `features/<业务>/`。迁移旧页面时同时更新导入、路由和测试。
- `core/` 放跨业务基础能力，单业务逻辑留在业务目录；`shared/` 放复用 UI。
- 维护脚本、发布素材和构建配置统一放 `tools/`，按用途分到 `assets/`、`release/`、`build-console/` 和 `audit_probes/`；维护文档放 `docs/`。

这些是后续维护建议，不代表业务页面已完成迁移。本次不修改包名、路由、平台配置或业务目录。

## 清理边界

资源可能通过字符串拼接、pubspec 或原生配置加载，不能只凭缺少 import 删除。锁文件、迁移资料、签名配置和用户备份不属于可自动清理的垃圾。

依赖版本以 pubspec 和锁文件为准，功能以实际调用链为准。文档不能替代回归验证。
