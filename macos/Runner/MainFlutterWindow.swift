import Cocoa
import FlutterMacOS
import WebKit
import UserNotifications

class MainFlutterWindow: NSWindow {
  private var walletStatusBar: WalletStatusBar?
  private var transferNotifications: TransferNotificationBridge?

  @IBAction func hideWindow(_ sender: Any?) {
    saveFrame(usingName: NSWindow.FrameAutosaveName("LinkWalletMainWindow"))
    orderOut(sender)
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = NSRect(x: self.frame.origin.x, y: self.frame.origin.y, width: 1200, height: 860)
    self.minSize = NSSize(width: 1000, height: 860)
    self.contentViewController = flutterViewController
    // Use the default size only on first launch; AppKit persists subsequent
    // window moves and resizes in this app's preferences.
    let frameName = NSWindow.FrameAutosaveName("LinkWalletMainWindow")
    if !self.setFrameUsingName(frameName, force: true) {
      self.setFrame(windowFrame, display: true)
    }
    if self.frame.height < self.minSize.height {
      var restoredFrame = self.frame
      restoredFrame.origin.y -= self.minSize.height - restoredFrame.height
      restoredFrame.size.height = self.minSize.height
      self.setFrame(restoredFrame, display: true)
    }
    self.setFrameAutosaveName(frameName)

    self.isReleasedWhenClosed = false
    walletStatusBar = WalletStatusBar(messenger: flutterViewController.engine.binaryMessenger, window: self)

    transferNotifications = TransferNotificationBridge(messenger: flutterViewController.engine.binaryMessenger, window: self)

    RegisterGeneratedPlugins(registry: flutterViewController)
    flutterViewController.registrar(forPlugin: "MarketChart").register(
      MarketChartFactory(), withId: "linkwallet/market-chart")

    super.awakeFromNib()
  }
}


final class MarketChartFactory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    MarketChartView(arguments: args)
  }
}

final class MarketChartView: NSView, WKNavigationDelegate, WKUIDelegate {
  private let webView: WKWebView

  init(arguments: Any?) {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    webView = WKWebView(frame: .zero, configuration: configuration)
    super.init(frame: .zero)
    webView.navigationDelegate = self
    webView.uiDelegate = self
    webView.autoresizingMask = [.width, .height]
    addSubview(webView)
    guard let params = arguments as? [String: Any],
          let text = params["url"] as? String, let url = URL(string: text),
          url.scheme == "https",
          ["www.tradingview.com", "dexscreener.com", "tronscan.org"].contains(url.host ?? "") else { return }
    if url.host == "www.tradingview.com",
       let symbol = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "symbol" })?.value {
      let options: [String: Any] = [
        "autosize": true, "symbol": symbol, "interval": "60",
        "timezone": "Etc/UTC", "theme": (params["dark"] as? Bool == true ? "dark" : "light"),
        "style": "1", "locale": "zh_CN", "allow_symbol_change": false,
        "hide_side_toolbar": false, "withdateranges": true
      ]
      guard let data = try? JSONSerialization.data(withJSONObject: options),
            let json = String(data: data, encoding: .utf8) else { return }
      webView.loadHTMLString("""
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body,.tradingview-widget-container{height:100%;width:100%;margin:0}body{background:#171717}</style></head>
        <body><div class="tradingview-widget-container">
        <div class="tradingview-widget-container__widget" style="height:calc(100% - 32px);width:100%"></div>
        <div class="tradingview-widget-copyright"><a href="https://www.tradingview.com/">Charts by TradingView</a></div>
        <script src="https://s3.tradingview.com/external-embedding/embed-widget-advanced-chart.js" async>\(json)</script>
        </div></body></html>
        """, baseURL: URL(string: "https://www.tradingview.com"))
    } else if url.host == "tronscan.org" {
      webView.load(URLRequest(url: url))
    } else {
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
      components?.queryItems = [URLQueryItem(name: "embed", value: "1"), URLQueryItem(name: "chartLeftToolbar", value: "1"), URLQueryItem(name: "chartStyle", value: "1")]
      if let embedded = components?.url { webView.load(URLRequest(url: embedded)) }
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layout() { super.layout(); webView.frame = bounds }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    let scheme = navigationAction.request.url?.scheme
    decisionHandler(scheme == "https" || scheme == "about" ? .allow : .cancel)
  }

  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
               for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
    if navigationAction.targetFrame == nil, navigationAction.request.url?.scheme == "https" {
      webView.load(navigationAction.request)
    }
    return nil
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    if (error as NSError).code == NSURLErrorCancelled { return }
    webView.loadHTMLString("<html><body><p>行情加载失败，请检查网络后点击上方刷新。</p></body></html>", baseURL: nil)
  }
}

// Local notifications use public transaction data only; no signing access.
final class TransferNotificationBridge: NSObject, UNUserNotificationCenterDelegate {
  private let channel: FlutterMethodChannel
  private weak var window: NSWindow?
  init(messenger: FlutterBinaryMessenger, window: NSWindow) {
    self.channel = FlutterMethodChannel(name: "linkwallet/transfer_notifications", binaryMessenger: messenger)
    self.window = window
    super.init()
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "requestPermission":
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
          DispatchQueue.main.async {
            if let error = error { result(FlutterError(code: "notification_permission", message: error.localizedDescription, details: nil)) }
            else { result(granted) }
          }
        }
      case "show":
        guard let args = call.arguments as? [String: String], let id = args["id"],
              let title = args["title"], let body = args["body"] else {
          result(FlutterError(code: "invalid_notification", message: "Invalid notification", details: nil)); return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
          DispatchQueue.main.async {
            if let error = error { result(FlutterError(code: "notification_delivery", message: error.localizedDescription, details: nil)) }
            else { result(nil) }
          }
        }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.banner, .list, .sound])
  }
  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                              withCompletionHandler completionHandler: @escaping () -> Void) {
    DispatchQueue.main.async { [weak self] in
      NSApp.activate(ignoringOtherApps: true)
      if self?.window?.isMiniaturized == true { self?.window?.deminiaturize(nil) }
      self?.window?.makeKeyAndOrderFront(nil)
      completionHandler()
    }
  }
}
