# iOS 内购与上架验证（2026-09-13）

Bundle ID：`com.xuanyu.ios`。APP 备案号：`豫ICP备2026007950号-1A`。

## 当前实现

- StoreKit 2 获取真实商品及本地化价格；服务端验签并绑定登录账号。
- 服务端确认到账后才 finish；未确认交易在登录、回到前台或手动同步时重试。
- 手动同步区分无待处理交易、已到账和失败；不会把失败报告为成功。
- 交易通知触发钱包余额刷新。
- iOS 退款入口指向 Apple 报告问题；苹果购买的玄遇币不设有效期。
- iOS 公开连麦（房间内多人可收听）只使用玄遇币结算，不提供支付宝选项，也不采用账号保存的支付宝偏好。
- iOS 用户协议补充条款与公开 `/ios/user-agreement` 页面保持一致。
- 五个商品：`com.xuanyu.ios.coins.{30,50,100,200,500}`，中国大陆价格对应同数量玄遇币。

## 加密声明依据

当前仅在中国大陆发行。应用代码未实现自定义加密算法，也未调用 Agora 自定义或媒体加密配置接口；认证、签名校验及网络连接采用平台或 SDK 的标准能力。依此按不使用非豁免加密填写 `ITSAppUsesNonExemptEncryption=false`。这不表示应用不使用 HTTPS。

- Apple 说明：[加密出口声明](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)。
- Apple 文稿要求：[加密文稿与法国发行](https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption/)。
- Agora 官方接口说明：[内置 AES 加密](https://github.com/AgoraIO/full-sdk/blob/master/rtc-full-aar/src/main/jniLibs/include/IAgoraRtcChannel.h)。

引入自定义加密、变更 SDK 或扩展发行区域时重新核对声明。

## 沙盒验收

自动化测试不等同于 Apple 真机购买验证。以下项目需在 TestFlight 或 Apple 沙盒设备上操作并核对服务端交易状态，不能用伪造凭证替代：

1. 同一玄遇账号登录，打开「我的 → 玄遇币 → 充值」，确认五档商品与 Apple 价格均可加载。
2. 取消购买：无新增交易或余额。
3. 完成一笔沙盒购买：客户端提示沙盒成功，服务端仅增加沙盒账本，不增加正式钱包资金。
4. 支付完成前后断网，再恢复网络并同步：同一 transactionId 仅记账一次。
5. 待批准交易完成后回到应用：自动处理，不必再次付费。
6. 切换玄遇账号：另一账号不能认领原账号购买；切回后可重试。
7. 重启应用后处理未完成交易；已成功交易不重复充值。
8. Apple 退款、重复通知和退款撤销按签名时间顺序处理，不重复扣款。

沙盒账本与正式钱包隔离，因此还不能在生产服务上使用测试币消费。完整付费服务体验须在隔离测试环境验证；不能把“服务端签名/记账测试通过”报告为“支付全流程验收通过”。

## 仍需补齐

- Apple 沙盒设备操作和真实交易回执验证。
- 6.5 或 6.9 英寸真实应用截图、内购充值页审核截图；现有 5.5 英寸截图不足。
- 商业协议、税务/收款信息及 App 隐私声明的后台确认。
- Apple 后台的中国大陆 APP 备案号校验。
- 最终审核提交须由用户确认；不要自动提交。
