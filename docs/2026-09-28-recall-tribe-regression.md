# 消息撤回与部落主页定向回归

日期：2026-09-28。全 APP 排查第四批第三段；目标版本 `1.0.18+19`。

## 用户范围与实现

- 用户明确要求继续排查，并增加两分钟内撤回消息、多个任务并行处理。本段分为聊天前端、部落主页、IM 后端、房间撤回；不新增平台审核或改变部落成员身份规则。
- 私聊/群聊/部落聊天：本人成功发出的文字、图片、视频、语音、帖子/个人主页/语音房分享、拍一拍可在两分钟内撤回。沿用邻近消息的操作菜单，服务器再次判断本人、会话成员、类型和时间。礼物、订单、通话等系统记录不支持撤回，删除聊天记录与撤回分开。
- 发送者显示“你撤回了一条消息”，接收者显示撤回提示。引用快照及编辑器中的引用失效；迟到刷新不能恢复已确认撤回的原文。收到撤回事件、重连或前台恢复时分批校准已加载历史及引用源 ID，不能只刷新最近 50 条。普通消息事件不反复校准全部历史。
- 免费/付费语音房使用独立房间接口，同样增加本人文字/图片两分钟撤回及旧缓存同步。私人专线通话页本身没有独立文字消息流，不凭本任务新增一套聊天功能。
- 部落主页修复按分区加载、失败重试、业务结果校验、重复操作、切号/迟到结果保护、资料操作后的列表更新。公众主页不再把非成员的群详情 404 当作整页失败；完整用例见本段测试文件。
- 后端群设置先验证整份修改，再事务更新；无权或数据库字段缺失不能假成功或留下部分修改。部落名称与关联群聊名称同步。
- 部落公开案例读取重新核对源帖公开/未删除、求助者公开同意、采纳仍有效及查看者可见性，避免旧案例摘要继续暴露。资料仍沿用 public/members/admins 可见性与管理员写删权限，不擅自扩大作者权限。

## 数据与验证边界

- 测试使用虚构消息、账号、房间；Flutter 请求本地拦截，后端使用隔离设置和 SQLite 内存数据库/模拟响应。不向真实用户发消息，不撤回、删除、退出或创建真实会话，不做资金操作。
- 撤回是当前聊天内容与引用的失效，不承诺抹去对方已经看过、截图、下载、收到的系统通知或先前独立收藏/转发副本。
- 撤回不返还陌生人消息额度，避免利用撤回绕过既有三条消息限制。成功撤回接口可安全重复确认，不重复广播。
- 双手机实时网络、系统推送通知、真机前后台及慢网行为仍须单独验收；自动化通过不等同于真机全功能通过。
- 前端合并回归 **180 项通过**，包含新增的撤回、部落可靠性及房间操作用例；修改的 13 个 Dart 文件静态检查通过。后端隔离回归 **83 项通过**，Python 语法及差异检查通过。安装包仅走既有远程构建流程，不把代码推送当作真机已更新。

## 可复跑验证

前端执行 `flutter test --no-pub --concurrency=1`，文件如下（为降低业务主机内存压力串行执行）：

```text
test/features/message/chat_recall_test.dart
test/features/message/chat_recall_sync_test.dart
test/features/community/team_home_reliability_test.dart
test/features/consultation/room_message_recall_test.dart
test/features/message/chat_reliability_test.dart
test/features/message/chat_settings_regression_test.dart
test/features/message/im_workflow_request_test.dart
test/features/message/conversation_lifecycle_test.dart
test/features/message/chat_local_preferences_test.dart
test/features/message/group_workflow_reliability_test.dart
test/features/message/tribe_and_account_workflow_test.dart
test/features/community/tribe_help_workflow_test.dart
test/features/community/team_resource_interaction_test.dart
test/features/community/team_resource_library_test.dart
test/features/community/user_relationship_settings_test.dart
test/features/community/profile_reliability_test.dart
```

后端提交 `2255db7` 已推送并部署；隔离 runner 与测试集合见后端 `docs/2026-09-28-message-recall-and-group-settings.md`。本次不需要数据库迁移或生产依赖变更。生产仓库快进拉取后语法检查通过，服务重启后 `active/running`，健康接口 HTTP 200 且 `UP`，近期启动日志无 ERROR/CRITICAL/Traceback。新房间撤回路由用只读 GET 验证返回 405，不执行真实撤回。生产目录原有本地文件保留。

## 工作区保护

本轮发现构建程序 `prepare()` 在开发目录执行重置/清理，导致未提交修改和测试环境被覆盖。使用已有构建租约临时暂停自动轮询，恢复本轮文件并重跑验证；没有修改构建程序，也没有操作线上用户数据。后续必须将开发目录与一次性构建检出分离；本次提交推送完成后解除临时租约。

## 仍需继续

- 本轮审查发现的社区评论可见范围风险已在随后专项中独立复现并修复，见 `2026-09-28-post-comment-regression.md`；其他社区互动及通知接口仍需分别验收，不能把部落案例过滤通过视为整个社区权限验收。
- 部落公开案例列表展开/进入详情、个人档案笔记的完整权限与跨页刷新尚不能算全部验收。
- 关系备注图片、特别关心、隐身子页，二维码落地及双端即时状态仍待检查。
- 下一批继续免费房/付费房/专线/预约的进出、恢复与断线流程；真实音视频与扣费须专门安排。
