/// 应用常量
class AppConstants {
  AppConstants._();

  static const String appVersion = '1.0.6';

  /// 与 Android `PrivacyConsentStore` 共用。Android 必须在原生层同意后再启动 Flutter 引擎，
  /// 否则引擎 / flutter_compass 会在弹窗同意前读取传感器列表。
  static const String keyAgreementAccepted = 'agreement_accepted';
  static const String keyAgreementAcceptedAt = 'agreement_accepted_at';
  static const String keyAgreementVersion = 'agreement_version';
  static const String userAgreementVersion = '2026-10-02';
  static const String privacyPolicyVersion = '2026-10-14';
  static const String keyMinorMode = 'minor_mode';
  static const String keyToken = 'token';
  static const String keyUserId = 'user_id';
  static const String keySavedAccountSessions = 'saved_account_sessions_v1';

  /// 本地通知偏好。关闭后仍可在站内查看发布结果，不再弹系统通知。
  static const String keyPostPublishNotificationEnabled =
      'post_publish_notification_enabled';

  /// 新用户登录/注册后是否尚未完成三段式问卷（昵称、出生日期时间、简介）
  static const String keyNeedOnboarding = 'need_onboarding';

  /// 今日运势/今日养生本地缓存（按日期，当天有缓存则不重复拉取）
  static const String keyDailyFortuneCache = 'daily_fortune_cache';
  static const String keyDailyFortuneDate = 'daily_fortune_date';
  static const String keyDailyHealthCache =
      'daily_health_cache_v7_account_profile';
  static const String keyDailyHealthDate =
      'daily_health_date_v7_account_profile';

  /// 后端 base URL。正式环境使用线上接口；本地调试见 baseUrlOverride
  static const String baseUrl = 'https://www.lingshu.uno';

  /// 本地调试时设为电脑 IP，如 'http://192.168.1.219:8080'；设为 null 则使用 baseUrl（线上）
  static const String? baseUrlOverride = null;

  /// 高德地图 API Key（2026-09-17 发布版账号，无调试 Key）
  /// Android Key「Xuanyu安卓」：地图 / 定位 SDK
  static const String amapAndroidKey = '8b724e3c523fac13bed1d4c3caa281fd';
  /// iOS Key「Xuanyu ios」：地图 / 定位 SDK
  static const String amapIosKey = '7d8214f52d9d0e5d6f651fe9f05d4a5d';

  /// Web 服务 Key「Xuanyu」：REST 逆地理编码。Android/iOS SDK Key 不能调 restapi。
  static const String amapWebKey = '3740610a8b2b14c241b2924d8dc24c15';

  /// 外部分享时使用的 APP 名称与下载/落地页说明（可改为实际下载链接）
  static const String appNameForShare = '玄遇';
  static const String appDownloadHint = '扫码下载玄遇 APP';

  /// 二维码默认先指向 APK 直链，保证安卓扫码可直接下载。
  /// 后续若 /download 页面已稳定上线，可改回 '$baseUrl/download?ch=share_qr'。
  static const String appDownloadUrl = '$baseUrl/static/app/xuanyu-latest.apk';

  /// 微信开放平台 AppID（与 Pay.txt 中 WECHAT_APPID 一致，用于 fluwx 注册、APP 支付）
  static const String? wxAppId = null; // 例如 'wxd930ea5d5a228f5f'
  /// 微信 iOS Universal Link（fluwx 注册必填，需在微信开放平台配置）
  static const String? wxUniversalLink =
      null; // 例如 'https://your-domain.com/wx/'
}
