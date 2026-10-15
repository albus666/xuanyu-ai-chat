# 高德地图集成说明

发帖时可选择位置：获取当前定位、地图选点、手动输入。需要配置高德地图 API Key。

## 1. 申请 API Key

1. 登录 [高德开放平台](https://lbs.amap.com/)
2. 进入「应用管理」→「我的应用」→「创建新应用」
3. 添加 Key：
   - **Android Key**：包名 `com.xuanyu.android`，勾选「定位」「地图」「逆地理编码」服务
   - **iOS Key**：Bundle ID 与 Xcode 中一致，勾选「定位」「地图」「逆地理编码」服务

## 2. 配置 Key

在 `lib/core/constants/app_constants.dart` 中替换占位符：

```dart
static const String amapAndroidKey = '你的Android_Key';
static const String amapIosKey = '你的iOS_Key';
```

## 3. 权限说明

- **Android**：已在 AndroidManifest.xml 中声明定位、网络权限
- **iOS**：已在 Info.plist 中声明 NSLocationWhenInUseUsageDescription

首次使用定位或地图时，App 会向用户请求定位权限。
