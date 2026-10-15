import Flutter
import UIKit
import AVFoundation
import Photos
import StoreKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var audioRecorder: AVAudioRecorder?
  private var audioRecordingURL: URL?
  private var appleStoreBridge: AppleStoreBridge?
  private var flutterEngine: FlutterEngine?
  private var deepLinkChannel: FlutterMethodChannel?
  private var pendingDeepLink: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let url = launchOptions?[.url] as? URL {
      receiveDeepLink(url)
    }
    let launched = super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
    return launched
  }

  /// 首次同意隐私协议后才创建 FlutterEngine 和注册第三方插件。
  func launchFlutter(in sceneWindow: UIWindow? = nil) {
    guard flutterEngine == nil else { return }
    guard let appWindow = sceneWindow ?? activeSceneWindow else { return }
    let engine = FlutterEngine(name: "xuanyu_engine")
    guard engine.run() else { return }
    GeneratedPluginRegistrant.register(with: engine)

    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    configureFlutterBridges(controller)
    flutterEngine = engine

    if let sceneDelegate = appWindow.windowScene?.delegate as? SceneDelegate {
      _ = sceneDelegate.registerSceneLifeCycle(with: engine)
    }
    let replaceRoot = {
      appWindow.rootViewController = controller
      appWindow.makeKeyAndVisible()
    }
    if UIAccessibility.isReduceMotionEnabled {
      replaceRoot()
    } else {
      UIView.transition(
        with: appWindow,
        duration: 0.18,
        options: [.transitionCrossDissolve, .allowAnimatedContent],
        animations: replaceRoot
      )
    }
  }

  func sceneWillConnect(window: UIWindow?, initialURL: URL?) {
    if let initialURL {
      receiveDeepLink(initialURL)
    }
    if PrivacyConsentStore.hasValidConsent {
      launchFlutter(in: window)
    }
  }

  func handleSceneURL(_ url: URL) -> Bool {
    guard receiveDeepLink(url) else { return false }
    if PrivacyConsentStore.hasValidConsent {
      launchFlutter()
    }
    return true
  }

  private var activeSceneWindow: UIWindow? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first(where: { $0.activationState == .foregroundActive })
      ?? scenes.first(where: { $0.activationState == .foregroundInactive })
      ?? scenes.first
    return scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first
  }

  private func configureFlutterBridges(_ controller: FlutterViewController) {
    appleStoreBridge = AppleStoreBridge(messenger: controller.binaryMessenger)
    let deepLinks = FlutterMethodChannel(
      name: "xuanyu/deep_links",
      binaryMessenger: controller.binaryMessenger
    )
    deepLinks.setMethodCallHandler { [weak self] call, result in
      guard call.method == "getInitialLink" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.pendingDeepLink)
      self?.pendingDeepLink = nil
    }
    deepLinkChannel = deepLinks
    let channel = FlutterMethodChannel(
      name: "xuanyu/audio_recorder",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "startRecording":
        self?.startAudioRecording(result: result)
      case "stopRecording":
        self?.stopAudioRecording(result: result)
      case "cancelRecording":
        self?.cancelAudioRecording()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    let mediaSave = FlutterMethodChannel(
      name: "xuanyu/media_save",
      binaryMessenger: controller.binaryMessenger
    )
    mediaSave.setMethodCallHandler { [weak self] call, result in
      guard call.method == "savePng" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.savePngToPhotoLibrary(call: call, result: result)
    }
  }

  private func savePngToPhotoLibrary(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let arguments = call.arguments as? [String: Any],
          let typedData = arguments["bytes"] as? FlutterStandardTypedData,
          !typedData.data.isEmpty else {
      result(FlutterError(code: "IMAGE_EMPTY", message: "图片生成失败", details: nil))
      return
    }
    let rawName = (arguments["fileName"] as? String) ?? "xuanyu_card.png"
    let fileName = rawName.hasSuffix(".png") ? rawName : "\(rawName).png"
    let save = {
      PHPhotoLibrary.shared().performChanges({
        let request = PHAssetCreationRequest.forAsset()
        let options = PHAssetResourceCreationOptions()
        options.originalFilename = fileName
        request.addResource(with: .photo, data: typedData.data, options: options)
      }) { success, error in
        DispatchQueue.main.async {
          if success {
            result("photos://\(fileName)")
          } else {
            result(FlutterError(
              code: "PHOTO_SAVE_FAILED",
              message: "保存到相册失败",
              details: error?.localizedDescription
            ))
          }
        }
      }
    }
    let handleAuthorization: (PHAuthorizationStatus) -> Void = { status in
      switch status {
      case .authorized, .limited:
        save()
      case .denied, .restricted:
        DispatchQueue.main.async {
          result(FlutterError(
            code: "PHOTO_PERMISSION_DENIED",
            message: "需要相册权限才能保存图片",
            details: nil
          ))
        }
      case .notDetermined:
        break
      @unknown default:
        DispatchQueue.main.async {
          result(FlutterError(
            code: "PHOTO_PERMISSION_DENIED",
            message: "无法取得相册权限",
            details: nil
          ))
        }
      }
    }
    if #available(iOS 14, *) {
      let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
      if status == .notDetermined {
        PHPhotoLibrary.requestAuthorization(for: .addOnly, handler: handleAuthorization)
      } else {
        handleAuthorization(status)
      }
    } else {
      let status = PHPhotoLibrary.authorizationStatus()
      if status == .notDetermined {
        PHPhotoLibrary.requestAuthorization(handleAuthorization)
      } else {
        handleAuthorization(status)
      }
    }
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if handleSceneURL(url) { return true }
    return super.application(app, open: url, options: options)
  }

  @discardableResult
  private func receiveDeepLink(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "xuanyu",
          url.host?.lowercased() == "group" else { return false }
    let value = url.absoluteString
    if let channel = deepLinkChannel {
      channel.invokeMethod("onLink", arguments: value)
    } else {
      pendingDeepLink = value
    }
    return true
  }

  private func startAudioRecording(result: @escaping FlutterResult) {
    cancelAudioRecording()
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
      try session.setActive(true)
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("xuanyu_voice_\(UUID().uuidString).m4a")
      let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44100,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 128000,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]
      let recorder = try AVAudioRecorder(url: url, settings: settings)
      guard recorder.record() else {
        result(FlutterError(code: "AUDIO_RECORD_START", message: "无法开始录音", details: nil))
        return
      }
      audioRecorder = recorder
      audioRecordingURL = url
      result(nil)
    } catch {
      cancelAudioRecording()
      result(FlutterError(code: "AUDIO_RECORD_START", message: "无法开始录音", details: error.localizedDescription))
    }
  }

  private func stopAudioRecording(result: FlutterResult) {
    guard let recorder = audioRecorder, let url = audioRecordingURL else {
      result(FlutterError(code: "AUDIO_RECORD_EMPTY", message: "当前没有正在进行的录音", details: nil))
      return
    }
    recorder.stop()
    audioRecorder = nil
    audioRecordingURL = nil
    try? AVAudioSession.sharedInstance().setActive(false)
    result(url.path)
  }

  private func cancelAudioRecording() {
    audioRecorder?.stop()
    audioRecorder = nil
    if let url = audioRecordingURL {
      try? FileManager.default.removeItem(at: url)
    }
    audioRecordingURL = nil
    try? AVAudioSession.sharedInstance().setActive(false)
  }
}

private enum PrivacyConsentStore {
  private static let acceptedKey = "flutter.agreement_accepted"
  private static let acceptedAtKey = "flutter.agreement_accepted_at"
  private static let versionKey = "flutter.agreement_version"
  private static let acceptedVersion = "2026-10-02|2026-10-14"

  static var hasValidConsent: Bool {
    let defaults = UserDefaults.standard
    return defaults.bool(forKey: acceptedKey) &&
      defaults.string(forKey: versionKey) == acceptedVersion
  }

  static func persistConsent() {
    let defaults = UserDefaults.standard
    defaults.set(true, forKey: acceptedKey)
    defaults.set(ISO8601DateFormatter().string(from: Date()), forKey: acceptedAtKey)
    defaults.set(acceptedVersion, forKey: versionKey)
    defaults.synchronize()
  }
}

/// iOS 原生隐私门禁。未同意前不创建 FlutterEngine，也不注册第三方插件。
@objc(PrivacyConsentViewController)
final class PrivacyConsentViewController: UIViewController, UITextViewDelegate {
  private let gradientLayer = CAGradientLayer()

  override func viewDidLoad() {
    super.viewDidLoad()
    configureBackground()
    if PrivacyConsentStore.hasValidConsent {
      showStartupAppearance()
    } else {
      showConsent()
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    gradientLayer.frame = view.bounds
  }

  private func configureBackground() {
    gradientLayer.colors = [
      UIColor(red: 0.984, green: 0.992, blue: 1, alpha: 1).cgColor,
      UIColor(red: 0.957, green: 0.965, blue: 1, alpha: 1).cgColor,
      UIColor(red: 0.929, green: 0.973, blue: 1, alpha: 1).cgColor,
    ]
    gradientLayer.startPoint = CGPoint(x: 0, y: 0)
    gradientLayer.endPoint = CGPoint(x: 1, y: 1)
    view.layer.insertSublayer(gradientLayer, at: 0)
  }

  private func clearContent() {
    view.subviews.forEach { $0.removeFromSuperview() }
  }

  private func showStartupAppearance() {
    clearContent()
    let icon = UIImageView(image: UIImage(named: "LaunchImage"))
    icon.translatesAutoresizingMaskIntoConstraints = false
    icon.contentMode = .scaleAspectFit
    icon.layer.cornerRadius = 22
    icon.layer.masksToBounds = true
    icon.accessibilityLabel = "玄遇"

    let quote = UILabel()
    quote.translatesAutoresizingMaskIntoConstraints = false
    quote.text = "慢一点，也没关系。"
    quote.textColor = UIColor(red: 0.157, green: 0.294, blue: 0.467, alpha: 1)
    quote.font = UIFont.systemFont(ofSize: 22, weight: .medium)
    quote.textAlignment = .center

    view.addSubview(icon)
    view.addSubview(quote)
    NSLayoutConstraint.activate([
      icon.widthAnchor.constraint(equalToConstant: 96),
      icon.heightAnchor.constraint(equalToConstant: 96),
      icon.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      icon.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -54),
      quote.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 30),
      quote.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
      quote.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
    ])
  }

  private func showConsent() {
    clearContent()
    let scrollView = UIScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.alwaysBounceVertical = true

    let card = UIStackView()
    card.translatesAutoresizingMaskIntoConstraints = false
    card.axis = .vertical
    card.alignment = .fill
    card.spacing = 20
    card.isLayoutMarginsRelativeArrangement = true
    card.layoutMargins = UIEdgeInsets(top: 34, left: 28, bottom: 28, right: 28)
    card.backgroundColor = .white
    card.layer.cornerRadius = 24
    card.layer.shadowColor = UIColor.black.cgColor
    card.layer.shadowOpacity = 0.10
    card.layer.shadowRadius = 18
    card.layer.shadowOffset = CGSize(width: 0, height: 8)

    let title = UILabel()
    title.text = "用户服务与隐私保护"
    title.textAlignment = .center
    title.font = UIFont.systemFont(ofSize: 25, weight: .semibold)
    title.textColor = UIColor(white: 0.12, alpha: 1)

    let body = UITextView()
    body.translatesAutoresizingMaskIntoConstraints = false
    body.isEditable = false
    body.isScrollEnabled = false
    body.backgroundColor = .clear
    body.delegate = self
    body.textContainerInset = .zero
    body.textContainer.lineFragmentPadding = 0
    body.linkTextAttributes = [
      .foregroundColor: UIColor(red: 0.08, green: 0.73, blue: 0.73, alpha: 1),
      .underlineStyle: 0,
    ]
    let copy = "感谢您选择玄遇！在您使用前，请认真阅读并同意《用户协议》与《隐私政策》。平台对违规内容及骚扰、欺凌等滥用行为零容忍；核实后将下架内容并限制或封禁违规账号。您同意遵守《用户协议》中的社区规则。我们将严格保护您的个人信息安全。点击「同意并继续」前，应用不会初始化第三方 SDK，也不会读取传感器等个人信息。"
    let attributed = NSMutableAttributedString(
      string: copy,
      attributes: [
        .font: UIFont.systemFont(ofSize: 17),
        .foregroundColor: UIColor(red: 0.30, green: 0.35, blue: 0.43, alpha: 1),
      ]
    )
    attributed.addAttribute(.paragraphStyle, value: paragraphStyle(), range: NSRange(location: 0, length: attributed.length))
    addLink("《用户协议》", url: "xuanyu-legal://user", to: attributed)
    addLink("《隐私政策》", url: "xuanyu-legal://privacy", to: attributed)
    body.attributedText = attributed

    let agree = UIButton(type: .system)
    agree.setTitle("同意并继续", for: .normal)
    agree.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
    agree.setTitleColor(.white, for: .normal)
    agree.backgroundColor = UIColor(red: 0.08, green: 0.76, blue: 0.76, alpha: 1)
    agree.layer.cornerRadius = 12
    agree.heightAnchor.constraint(equalToConstant: 54).isActive = true
    agree.addTarget(self, action: #selector(acceptConsent), for: .touchUpInside)

    let disagree = UIButton(type: .system)
    disagree.setTitle("不同意", for: .normal)
    disagree.titleLabel?.font = UIFont.systemFont(ofSize: 17)
    disagree.setTitleColor(UIColor(red: 0.27, green: 0.31, blue: 0.39, alpha: 1), for: .normal)
    disagree.heightAnchor.constraint(equalToConstant: 44).isActive = true
    disagree.addTarget(self, action: #selector(declineConsent), for: .touchUpInside)

    [title, body, agree, disagree].forEach(card.addArrangedSubview)
    view.addSubview(scrollView)
    let content = UIView()
    content.translatesAutoresizingMaskIntoConstraints = false
    scrollView.addSubview(content)
    content.addSubview(card)
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
      content.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),
      card.centerXAnchor.constraint(equalTo: content.centerXAnchor),
      card.centerYAnchor.constraint(equalTo: content.centerYAnchor),
      card.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor, constant: 28),
      card.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -28),
      card.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 24),
      card.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
      card.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -48).withPriority(750),
      card.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
    ])
  }

  private func paragraphStyle() -> NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = 7
    return style
  }

  private func addLink(_ label: String, url: String, to text: NSMutableAttributedString) {
    let range = (text.string as NSString).range(of: label)
    guard range.location != NSNotFound, let destination = URL(string: url) else { return }
    text.addAttribute(.link, value: destination, range: range)
  }

  @objc private func acceptConsent() {
    PrivacyConsentStore.persistConsent()
    showStartupAppearance()
    (UIApplication.shared.delegate as? AppDelegate)?.launchFlutter(in: view.window)
  }

  @objc private func declineConsent() {
    let alert = UIAlertController(
      title: "需要您的同意",
      message: "不同意用户协议和隐私政策将无法使用玄遇。您可以继续阅读后再决定。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "继续阅读", style: .default))
    present(alert, animated: true)
  }

  func textView(
    _ textView: UITextView,
    shouldInteractWith URL: URL,
    in characterRange: NSRange,
    interaction: UITextItemInteraction
  ) -> Bool {
    guard URL.scheme == "xuanyu-legal" else { return false }
    let type: LegalDocumentViewController.Document = URL.host == "user" ? .userAgreement : .privacyPolicy
    let document = LegalDocumentViewController(document: type)
    let navigation = UINavigationController(rootViewController: document)
    navigation.modalPresentationStyle = .fullScreen
    present(navigation, animated: true)
    return false
  }
}

private extension NSLayoutConstraint {
  func withPriority(_ value: Float) -> NSLayoutConstraint {
    priority = UILayoutPriority(value)
    return self
  }
}

private final class LegalDocumentViewController: UIViewController {
  enum Document {
    case userAgreement
    case privacyPolicy

    var title: String { self == .userAgreement ? "用户协议" : "隐私政策" }
    var resource: String { self == .userAgreement ? "user_agreement" : "privacy_policy" }
  }

  private let document: Document

  init(document: Document) {
    self.document = document
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = document.title
    view.backgroundColor = UIColor(red: 0.965, green: 0.976, blue: 0.992, alpha: 1)
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      title: "返回",
      style: .plain,
      target: self,
      action: #selector(close)
    )

    let textView = UITextView()
    textView.translatesAutoresizingMaskIntoConstraints = false
    textView.isEditable = false
    textView.backgroundColor = .clear
    textView.textColor = UIColor(red: 0.20, green: 0.24, blue: 0.31, alpha: 1)
    textView.font = UIFont.systemFont(ofSize: 16)
    textView.textContainerInset = UIEdgeInsets(top: 22, left: 18, bottom: 30, right: 18)
    if let url = Bundle.main.url(forResource: document.resource, withExtension: "txt", subdirectory: "legal"),
       let content = try? String(contentsOf: url, encoding: .utf8) {
      let body = NSMutableAttributedString(string: content, attributes: [
        .font: UIFont.systemFont(ofSize: 16),
        .foregroundColor: textView.textColor ?? UIColor.label,
      ])
      let source = content as NSString
      let notice = source.range(of: "重要提示：剪切板")
      if notice.location != NSNotFound {
        let rest = NSRange(location: notice.location, length: source.length - notice.location)
        let end = source.range(of: "\n", range: rest)
        let length = (end.location == NSNotFound ? source.length : end.location) - notice.location
        body.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 16),
                          range: NSRange(location: notice.location, length: length))
      }
      textView.attributedText = body
    } else {
      textView.text = "协议内容暂时无法加载，请返回后重试。"
    }
    view.addSubview(textView)
    NSLayoutConstraint.activate([
      textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
  }

  @objc private func close() { dismiss(animated: true) }
}

@MainActor
private final class AppleStoreBridge {
  private let channel: FlutterMethodChannel
  private var updates: Task<Void, Never>?
  private var pending: [UInt64: StoreKit.Transaction] = [:]

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "xuanyu/apple_iap", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      Task { @MainActor in
        guard let self = self else { return }
        await self.handle(call, result: result)
      }
    }
    updates = Task { [weak self] in
      for await verification in StoreKit.Transaction.updates {
        guard let self = self else { return }
        if let payload = try? self.payload(verification) {
          self.channel.invokeMethod("transaction", arguments: payload)
        }
      }
    }
  }

  deinit { updates?.cancel() }

  private func payload(_ verification: VerificationResult<StoreKit.Transaction>) throws -> [String: Any] {
    let transaction = try verification.payloadValue
    pending[transaction.id] = transaction
    return ["transactionId": String(transaction.id), "signedTransaction": verification.jwsRepresentation]
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) async {
    let args = call.arguments as? [String: Any] ?? [:]
    do {
      switch call.method {
      case "products":
        let ids = args["ids"] as? [String] ?? []
        let products = try await Product.products(for: ids)
        result(products.map { ["id": $0.id, "title": $0.displayName, "price": $0.displayPrice] })
      case "productDiagnostics":
        let ids = args["ids"] as? [String] ?? []
        let products = try await Product.products(for: ids)
        let storefront = await Storefront.current
        let legacy = await LegacyProductProbe().load(ids)
        result([
          "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
          "buildNumber": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
          "bundleId": Bundle.main.bundleIdentifier ?? "",
          "storefrontId": storefront?.id ?? "",
          "storefrontCountryCode": storefront?.countryCode ?? "",
          "canMakePayments": AppStore.canMakePayments,
          "requestedCount": ids.count,
          "storeKit2Count": products.count,
          "legacyCount": legacy.products.count,
          "invalidProductIds": legacy.invalidProductIdentifiers,
          "legacyError": legacy.error ?? ""
        ])
      case "purchase":
        guard let id = args["id"] as? String,
              let token = args["appAccountToken"] as? String,
              let uuid = UUID(uuidString: token),
              let product = try await Product.products(for: [id]).first,
              product.type == .consumable else {
          result(FlutterError(code: "PRODUCT_UNAVAILABLE", message: "商品暂不可购买，请稍后重试", details: nil))
          return
        }
        switch try await product.purchase(options: [.appAccountToken(uuid)]) {
        case .success(let verification):
          result(try payload(verification))
        case .userCancelled:
          result(["status": "cancelled"])
        case .pending:
          result(["status": "pending"])
        @unknown default:
          result(["status": "pending"])
        }
      case "unfinished":
        var transactions: [[String: Any]] = []
        for await verification in StoreKit.Transaction.unfinished {
          if let item = try? payload(verification) { transactions.append(item) }
        }
        result(transactions)
      case "finish":
        guard let raw = args["transactionId"] as? String, let id = UInt64(raw),
              let transaction = pending[id] else {
          result(FlutterError(code: "TRANSACTION_UNAVAILABLE", message: "交易将在下次打开时重新同步", details: nil))
          return
        }
        await transaction.finish()
        pending.removeValue(forKey: id)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "APPLE_PURCHASE_ERROR", message: "暂时无法完成苹果购买，请重试", details: nil))
    }
  }
}

private final class LegacyProductProbe: NSObject, SKProductsRequestDelegate {
  private var request: SKProductsRequest?
  private var continuation: CheckedContinuation<(products: [SKProduct], invalidProductIdentifiers: [String], error: String?), Never>?

  func load(_ ids: [String]) async -> (products: [SKProduct], invalidProductIdentifiers: [String], error: String?) {
    await withCheckedContinuation { continuation in
      self.continuation = continuation
      let request = SKProductsRequest(productIdentifiers: Set(ids))
      self.request = request
      request.delegate = self
      request.start()
    }
  }

  func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
    finish((response.products, response.invalidProductIdentifiers, nil))
  }

  func request(_ request: SKRequest, didFailWithError error: Error) {
    finish(([], [], String(describing: error)))
  }

  private func finish(_ value: (products: [SKProduct], invalidProductIdentifiers: [String], error: String?)) {
    continuation?.resume(returning: value)
    continuation = nil
    request = nil
  }
}
