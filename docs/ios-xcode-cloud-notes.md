# iOS / Xcode Cloud 构建笔记

本文记录玄遇 iOS 上架、Xcode Cloud 归档、TestFlight 分发过程中已经踩过的坑和当前约定。

## 当前约定

- 本地 MacBook Air 2017 的 Xcode 版本较旧，不能直接上传 App Store。上架与 TestFlight 分发优先走 Xcode Cloud。
- Xcode Cloud 使用 `ios/ci_scripts/ci_post_clone.sh` 准备 Flutter、CocoaPods 和 iOS 插件。
- 本项目 iOS 依赖仍走 CocoaPods，脚本会执行 `flutter config --no-enable-swift-package-manager` 关闭 Flutter Swift Package Manager。
- 高德地图 iOS SDK Key 配在 `lib/core/constants/app_constants.dart` 的 `amapIosKey`。
- 微信和支付宝 App 支付暂未完成正式申请，相关 URL Scheme / Universal Link 后续再配置。

## 常用验证命令

```sh
git status --short --branch
plutil -lint ios/Runner/Info.plist
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter build ios --config-only --release
flutter analyze
```

本地旧 Xcode 构建 iOS 只能作为配置验证参考，最终 App Store / TestFlight 仍以 Xcode Cloud 结果为准。

## Xcode Cloud 日志查看重点

下载日志后优先看：

- `ci_post_clone.log`
- `xcodebuild-archive.log`
- `resolve_package_dependencies.log`

快速定位错误：

```sh
rg -n "error:|ERROR:|Exception|ARCHIVE FAILED|BUILD FAILED|Module .* not found|Command exited" "/path/to/Build Logs"
```

如果下载目录里只有 `ci_post_clone.log`，说明还没进入 `xcodebuild archive`，问题在 clone 后脚本阶段。

## 已处理问题

### iOS SDK 版本不满足上传

本地 Xcode 15.2 构建出来的包上传失败：

```text
SDK version issue. This app was built with the iOS 17.2 SDK.
All iOS and iPadOS apps must be built with the iOS 26 SDK or later.
```

处理方式：不用本机上传，改走 Xcode Cloud / Apple 云端 Archive。

### AMap3DMap 二进制过大

高德 `MAMapKit.framework` 太大，不适合直接提交仓库，GitHub LFS 配额也容易失败。

处理方式：

- `ios/Podfile` 使用官方 CocoaPods：`pod 'AMap3DMap', '11.1.000'`
- `ios/Vendor/AMap3DMap/MAMapKit.framework/` 保持忽略
- CI 脚本只校验 Podfile 锁定版本，不再要求仓库内 vendored framework

### `assets/map.json` 太大且未提交

Xcode Cloud 曾失败：

```text
No file or variants found for asset: assets/map.json
```

处理方式：

- 原始 `assets/map.json` 太大且被忽略
- 生成并提交 `assets/region_map.json`
- `pubspec.yaml` 和地区加载代码改用 `assets/region_map.json`

### `Module 'agora_rtc_engine' not found`

Xcode Cloud 曾在 `GeneratedPluginRegistrant.m` 报：

```text
Module 'agora_rtc_engine' not found
```

原因：云端 Pod install 只装出 10 个依赖 / 17 个 Pods，缺少 Flutter iOS 插件 Pods。

处理方式：`ci_post_clone.sh` 会清理并重新生成 Flutter iOS 插件配置：

- 删除 `.flutter-plugins-dependencies`
- 删除 `ios/.symlinks`
- 删除 `ios/Flutter/Generated.xcconfig`
- 执行 `flutter pub get`
- 执行 `flutter build ios --config-only --release`
- 校验 `GeneratedPluginRegistrant.m` 和 `.flutter-plugins-dependencies`
- 校验 `Pods/Manifest.lock`

正常输出应类似：

```text
Pod installation complete! There are 17 dependencies from the Podfile and 27 total pods installed.
Pods Manifest OK
```

### Flutter 3.44 SwiftPM 自动迁移失败

Xcode Cloud Flutter 3.44.5 曾失败：

```text
An error occurred when adding Swift Package Manager integration:
Exception: Xcode workspace not found.
```

处理方式：

- `pubspec.yaml` 中关闭 SwiftPM：

```yaml
flutter:
  config:
    enable-swift-package-manager: false
```

- `ci_post_clone.sh` 中显式执行：

```sh
flutter config --no-enable-swift-package-manager
```

### WechatOpenSDK 下载偶发失败

CocoaPods 曾下载微信 SDK 时失败：

```text
Error installing WechatOpenSDK-XCFramework
curl: (52) Empty reply from server
```

这是腾讯 CDN / 网络偶发问题。`ci_post_clone.sh` 已加入重试：

- `flutter pub get` 最多 3 次
- `flutter build ios --config-only --release` 最多 4 次
- `pod install` 最多 4 次

## iOS 功能配置检查

已配置：

- iOS App 显示名：`玄遇`
- 高德 iOS SDK Key：`amapIosKey`
- 相机权限：`NSCameraUsageDescription`
- 相册权限：`NSPhotoLibraryUsageDescription`
- 麦克风权限：`NSMicrophoneUsageDescription`
- 定位权限：`NSLocationWhenInUseUsageDescription`
- 本地通知权限由 `flutter_local_notifications` 请求

暂未配置：

- 微信 AppID / Universal Link / iOS URL Scheme
- 支付宝 iOS 回跳 URL Scheme
- APNs 远程推送

## TestFlight 查找 App

App Store Connect 中测试员状态为“已邀请”时，手机还看不到 App。需要：

1. iPhone 安装 TestFlight。
2. 使用邀请邮箱对应的 Apple ID 登录。
3. 打开 Apple / TestFlight 邀请邮件。
4. 点“在 TestFlight 中查看”并接受邀请。
5. 在 TestFlight 中安装构建。

如果仍看不到，检查测试组的“构建版本”页是否已经分配了可测试构建。

## 后续建议

- 支付申请下来后，再补微信 / 支付宝 iOS 回跳配置。
- `amapWebKey` 目前在客户端，用于 REST 逆地理编码。后续更推荐由后端代理逆地理编码，减少 Web 服务 Key 暴露。
- `flutter analyze` 目前有不少既有 warning/info，主要是未使用代码、未使用 import、deprecated `withOpacity` 和 const lint，不影响当前构建，但后续可以分批清理。
