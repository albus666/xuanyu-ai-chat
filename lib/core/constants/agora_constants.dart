/// Agora 声网 RTC 常量
/// 注意：App ID 用于客户端初始化；证书（App Certificate）仅放在服务端，用于生成 RTC Token，切勿泄露到客户端
class AgoraConstants {
  AgoraConstants._();

  /// 声网 App ID（从 server/Agora.txt 同步，客户端初始化 RTC 需要）
  static const String appId = '04c9bffd0b604a93812f5bc51fe9a7bc';
}
