# 语音房断线、前后台与会话隔离回归（2026-09-28）

## 范围

只改 `voice_plaza_room_page.dart` 及独立测试；不改房间布局、命盘、收费公式、共享悬浮控制器、后端权限或真实用户数据。RTC、WebSocket、原生音频保活和 HTTP 都可在测试中替换为隔离假实现；生产默认路径仍使用既有 SDK/接口。

## 先复现再修复

仅添加可选测试注入点后，第一轮真实页面 widget 红测明确复现五项：

1. 切换账号只清消息，页面仍保留房间资料，RTC/事件连接未在页面层终止。
2. WebSocket 重连成功后没有立即 REST 补消息，必须等下一次 15 秒轮询。
3. 消息接口最多 100 条，恢复时只读取一页，无法一次补齐 205 条测试消息。
4. 已有刷新请求尚未返回时，resume 的 `await _refresh()` 实际立即返回，旧音频提前恢复。
5. HTTP 200 + 业务 403 的详情拒绝被吞掉，仍保留旧房间并尝试恢复。

首轮第六条测试直接 await 被 fake async 挂起的接口，主动停止后补齐 pump 调度。这不计为产品失败或有效测试通过。

最终复核另补慢网饥饿红测：连续两次权威请求各延迟超过 15 秒，周期轮询持续置 pending，旧实现额外启动第三轮而不能返回 resume。隔离断言实际得到 3 次请求（预期 2 次），已复现后修复。

## 修复

- 刷新合并为所有调用者都可等待的任务，并返回本轮权威读取是否成功；状态读取失败时不按旧席位恢复 RTC。每批至多初次加一次追赶，避免慢网被 15 秒轮询无限续接；保留第二轮权威结果，其余变更仍由后续事件/轮询同步。
- WS 每次成功建连立即补消息；按 100 条接口分页追赶，每轮最多 10 页，页面仍只保留最近 300 条。超出单轮上限可由后续推送/轮询继续追赶，不无限循环。
- 详情或已入房后的消息读取明确 401/403/404/410、房间结束、本人不再在成员列表时，清空旧资料/消息并停止旧 RTC、事件及轮询。
- join、leave、续期、ready、heartbeat 固定页面所属账号；授权弹窗、异步 RTC 初始化、WS 建连、退出确认都复核账号和实例代际。
- 旧 overlay generation 不可关闭、detach 或覆盖新一代同 ID 房间，旧页面清理不发送新房间的全局音频服务 stop。
- 私人通话主动暂停房间音频后，普通 resume 只更新房间状态与消息；明确恢复房间音频时才重新建立 RTC。
- leave 校验业务码，失败保留房间并可重试；多次退出/恢复请求防重。首次加载网络失败提供真实重试按钮。

## 验证方式

测试文件 `test/features/consultation/voice_room_recovery_test.dart`：真实 `VoicePlazaRoomPage`，fake RTC/WebSocket/native-service、Dio 拦截器，不会实际进房、发消息、支付、结束生产会话或写用户数据。

覆盖：切号清理、断线补消息、205 条分页、等待权威状态、业务 403、失败退出重试、私线暂停、缩小恢复、迟到 join/WS/RTC 初始化/token 续期、旧/新同 ID overlay 隔离、重复退出/resume、被移出、网络失败重试、席位下麦、授权/结束确认弹窗切号。

命令：

```sh
flutter test --no-pub --concurrency=1 test/features/consultation/voice_room_recovery_test.dart test/features/consultation/room_message_recall_test.dart
flutter analyze --no-pub lib/features/consultation/voice_plaza_room_page.dart test/features/consultation/voice_room_recovery_test.dart
```

最终执行结果：新增恢复测试 **24/24 通过**（含慢网饥饿红转绿），相邻房间撤回回归 **13/13 通过**，同一进程共 **37/37 通过**。上述两个 Dart 文件静态分析通过（No issues found）。首轮静态分析的 5 条 info 已补显式 mounted 检查和大括号消除。

## 仍需真机验收 / 未扩大范围

- Android/Huawei/iOS 真机切 Wi-Fi/移动网络、断网恢复、锁屏/后台回前台的实际音频、蓝牙和系统保活表现。
- 双账号/双设备上麦、踢出、关房、私人专线切换，真实 Agora SDK 和付费计费联动。本轮 fake 测试不是双真机验收。
- 原生音频服务调用已用注入回归隔离验证；不能据此宣称验证了具体设备系统限制。
- 房间内资料编辑、邀请、赠礼和管理菜单的全部业务码/权限属于其他操作链路，本轮未对每个操作逐一实测或声称完成全页审计。
- 仓库提交推送及远程出包由主代理统一执行，本文件不代表已发布新 APK。
