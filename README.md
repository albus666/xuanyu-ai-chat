# 玄遇移动客户端

这是独立的 AI 聊天入口版：从「消息」右上角「AI 聊天」进入 AI 广场。基于原仓库提交 `b0fb093` 创建，详见 [本版本说明](docs/ai-chat-edition.md)。后端继续独立运行，本仓库不包含服务端。

Flutter 客户端，包含排盘、AI 对话、社区、消息、语音和咨询。同级 `haha` 是后端，`haha_admin` 是管理后台，三者分别管理 Git 历史。

## 启动与验证

在本仓库目录执行 `flutter pub get`、`flutter run`。依赖与版本以 `pubspec.yaml`、`pubspec.lock` 为准；安装和运行会生成本地缓存及构建产物。

测试命令是 `flutter test`，静态分析是 `flutter analyze`；执行前确认 SDK 和依赖环境。本文不表示这些命令已执行。

## 主链路与目录

| 位置 | 职责 |
| --- | --- |
| `lib/main.dart` | 初始化设置、Token 和应用 |
| `lib/app/common/routers/` | 页面路由 |
| `lib/app/pages/system/login/controller.dart` | 登录、保存凭据和设置 API Token |
| `lib/core/network/api_client.dart` | Dio、Bearer Token、超时和 401 处理 |
| `lib/core/constants/app_constants.dart` | 后端地址；本地调试使用 baseUrlOverride |
| `lib/app/` | 启动、路由与现有页面，不能视作废弃代码 |
| `lib/features/` | 按业务划分的页面与服务 |
| `lib/core/`、`lib/shared/` | 公共基础能力与复用 UI |
| `android/`、`ios/` | 平台配置与原生桥接 |
| `assets/`、`images/` | 运行资源，可能通过动态路径加载 |
| `test/` | 单元、组件及回归测试 |
| `tools/` | 资源处理、发布素材、构建配置与手工诊断，参见目录内 README |

AI 对话入口是 `lib/features/message/ai_master_chat_page.dart`，通过后端 SSE 接收事件。真机与模拟器访问本地后端的地址不同，应同时核对监听地址和 Host 配置。

维护工具已统一到 [tools/](tools/README.md)，不再分散在顶层 `tool/`、`ops/` 和 `store_assets/`。

参见 [结构约定](docs/architecture.md) 和 [协作规则](AGENTS.md)。
