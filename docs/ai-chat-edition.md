# AI 聊天入口版

本仓库以玄遇 Flutter 已提交版本 `b0fb093`（`1.0.73+74`）为基础创建独立快照，不携带原仓库完整历史或本地未提交文件。

## 应用入口

登录后打开底部「消息」，点击右上角「AI 聊天」，进入现有 AI 广场，可选择「AI 名师」或「骂醒恋爱脑」。原有真人咨询入口保留。

页面链路：`message_page.dart` → `ai_square_page.dart` → `ai_master_chat_page.dart`，均位于 `lib/features/message/`。

## 运行边界

本仓库只包含移动客户端，不包含 Django 后端。聊天继续使用 `lib/core/constants/app_constants.dart` 配置的后端及现有登录身份；打开入口不代表模型凭据、聊天服务或知识库已经可用。不要把后端密钥写入客户端。

本次不升级版本号、不修改包名或签名配置，不替换已安装应用，也不自动触发原仓库的构建流程。安装此改动仍需后续重新构建安装包。

导航测试：`flutter test --no-pub test/features/message/ai_chat_entry_test.dart`。测试通过拦截器模拟全部请求，不发送真实聊天消息。
