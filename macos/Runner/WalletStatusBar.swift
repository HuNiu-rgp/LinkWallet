import Cocoa
import FlutterMacOS

/// Native menu-bar display. This class never loads or handles private keys.
final class WalletStatusBar: NSObject, NSMenuDelegate {
  private let statusItem: NSStatusItem
  private let channel: FlutterMethodChannel
  private weak var window: NSWindow?
  private var snapshot: [String: Any] = [:]

  init(messenger: FlutterBinaryMessenger, window: NSWindow) {
    self.window = window
    channel = FlutterMethodChannel(name: "linkwallet/menu_bar", binaryMessenger: messenger)
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    super.init()
    if let button = statusItem.button {
      let image = NSImage(named: "WalletMenuIcon")
      image?.size = NSSize(width: 18, height: 18)
      image?.isTemplate = true
      button.image = image
      button.toolTip = "LinkWallet 钱包"
      button.setAccessibilityLabel("LinkWallet 钱包菜单")
    }
    let menu = NSMenu(title: "LinkWallet")
    menu.autoenablesItems = false
    menu.delegate = self
    statusItem.menu = menu
    // The application menu exposes the same live data when the status item is
    // hidden by macOS due to limited menu-bar space.
    DispatchQueue.main.async { [weak self] in self?.installApplicationMenu() }
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update", let data = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.snapshot = data
      result(nil)
    }
  }

  private func installApplicationMenu() {
    guard let root = NSApp.mainMenu else { return }
    let identifier = NSUserInterfaceItemIdentifier("linkwallet.walletMenu")
    guard !root.items.contains(where: { $0.identifier == identifier }) else { return }
    let item = NSMenuItem(title: "钱包", action: nil, keyEquivalent: "")
    item.identifier = identifier
    let menu = NSMenu(title: "钱包")
    menu.autoenablesItems = false
    menu.delegate = self
    item.submenu = menu
    root.insertItem(item, at: min(1, root.numberOfItems))
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    add("LinkWallet", to: menu)
    add(snapshot["network"] as? String ?? "多链钱包", to: menu)
    menu.addItem(.separator())
    let address = snapshot["address"] as? String
    if snapshot["loading"] as? Bool == true || snapshot.isEmpty {
      add("正在加载钱包…", to: menu)
    } else if snapshot["error"] as? Bool == true {
      add("钱包读取失败，请打开应用重试", to: menu)
    } else if let address = address {
      add(snapshot["name"] as? String ?? "当前钱包", to: menu)
      let copy = add(address, to: menu, action: #selector(copyAddress(_:)))
      copy.representedObject = address
      copy.toolTip = "点击复制完整钱包地址"
      menu.addItem(.separator())
      for asset in snapshot["assets"] as? [[String: String]] ?? [] {
        add("\(asset["symbol"] ?? "")    \(asset["balance"] ?? "—")", to: menu)
      }
      if snapshot["refreshing"] as? Bool == true { add("正在更新余额…", to: menu) }
    } else {
      add("此网络暂无钱包", to: menu)
    }

    let wallets = snapshot["wallets"] as? [[String: String]] ?? []
    if !wallets.isEmpty {
      menu.addItem(.separator())
      let item = add("切换钱包", to: menu)
      item.isEnabled = true
      let submenu = NSMenu(title: "切换钱包")
      submenu.autoenablesItems = false
      for wallet in wallets {
        let accountAddress = wallet["address"] ?? ""
        let short = accountAddress.count > 12 ? "\(accountAddress.prefix(5))…\(accountAddress.suffix(4))" : accountAddress
        let row = add("\(wallet["name"] ?? "钱包") · \(short)", to: submenu, action: #selector(selectWallet(_:)))
        row.representedObject = wallet["id"]
        row.toolTip = accountAddress
        row.state = wallet["id"] == snapshot["selectedId"] as? String ? .on : .off
      }
      item.submenu = submenu
    }
    menu.addItem(.separator())
    let refresh = add("刷新余额", to: menu, action: #selector(refreshAssets(_:)))
    refresh.isEnabled = address != nil && snapshot["refreshing"] as? Bool != true
    add("打开 LinkWallet", to: menu, action: #selector(openWindow(_:)))
    menu.addItem(.separator())
    add("退出 LinkWallet", to: menu, action: #selector(quit(_:)))
  }

  @discardableResult
  private func add(_ title: String, to menu: NSMenu, action: Selector? = nil) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    item.isEnabled = action != nil
    menu.addItem(item)
    return item
  }

  @objc private func copyAddress(_ sender: NSMenuItem) {
    guard let address = sender.representedObject as? String else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(address, forType: .string)
  }

  @objc private func selectWallet(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    channel.invokeMethod("selectWallet", arguments: id)
  }

  @objc private func refreshAssets(_ sender: NSMenuItem) {
    channel.invokeMethod("refreshAssets", arguments: nil)
  }

  @objc private func openWindow(_ sender: NSMenuItem) {
    NSApp.activate(ignoringOtherApps: true)
    if window?.isMiniaturized == true { window?.deminiaturize(nil) }
    window?.makeKeyAndOrderFront(nil)
  }

  @objc private func quit(_ sender: NSMenuItem) {
    NSApp.terminate(nil)
  }
}
