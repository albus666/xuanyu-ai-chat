# 小米审核前两项修复（2026-10-12）

## 图标白边

图标保留玄遇字样和渐变配色。使用内置 imagegen 修复原图，提示为：保留原有文字与配色，将背景延展为不透明的完整正方形，清除白边、透明圆角和边缘杂点。

- 图标原图：`assets/app_icon.png`
- 小米平台上传图：`tools/release/store_assets/xiaomi/app_icon.png`（512×512、不透明 PNG）
- Android 各密度启动图标和自适应前景均由修复后的原图缩放生成，不预裁切圆角。

平台上的图标需重新上传这份图片，已上传的旧素材不会随源码提交自动替换。

## 隐私政策一致性

Flutter 的 `lib/features/profile/legal_document_page.dart` 是正文来源；Android Gradle 和 iOS 构建脚本从这里生成首次启动弹窗使用的离线正文。网页同步应用现有正文；存储权限移除后，也需通过同步脚本更新网页。版本继续统一为 2026-09-16，避免仅同步副本就改变现有用户的同意记录或登录条件。

平台建议统一填写：<https://www.lingshu.uno/privacy-policy>。`/privacy`、`/privacy_policy`、`/ios/privacy-policy`、`/huawei/privacy-policy` 同步提供相同隐私正文。网页响应的 `X-Legal-Document-SHA256` 用于核对原文身份。

同步与检查：

```sh
python3 tools/release/sync_privacy_policy.py --backend-root /path/to/haha
python3 tools/release/sync_privacy_policy.py --check --backend-root /path/to/haha --apk /path/to/new.apk
```

本次未处理审核通知中的第三项资质要求。平台中的链接、图标与 APK 需使用本次修复后的内容重新提交；代码和构建验证不等同于商店审核通过。
