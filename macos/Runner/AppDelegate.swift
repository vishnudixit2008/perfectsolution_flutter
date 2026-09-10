import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    setupFileMenu()
  }

  override func applicationDidBecomeActive(_ notification: Notification) {
    for window in NSApplication.shared.windows {
      window.contentViewController?.view.needsDisplay = true
      window.displayIfNeeded()
    }
  }

  override func applicationDidResignActive(_ notification: Notification) {
    for window in NSApplication.shared.windows {
      window.contentViewController?.view.needsDisplay = true
    }
  }

  // Required: forwards the OAuth callback URL to supabase_flutter via Flutter's plugin system.
  // Without super.application(), app_links plugin never receives the deep link.
  override func application(_ application: NSApplication, open urls: [URL]) {
    super.application(application, open: urls)
  }

  override func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    let menu = NSMenu()
    let newWindowItem = NSMenuItem(title: "New Window", action: #selector(handleNewWindowAction), keyEquivalent: "n")
    newWindowItem.target = self
    menu.addItem(newWindowItem)
    return menu
  }

  @IBAction @objc func handleNewWindowAction(_ sender: Any? = nil) {
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "com.perfectsolution/desktop_window_manager", binaryMessenger: controller.engine.binaryMessenger)
      channel.invokeMethod("new_window", arguments: nil)
    }
  }

  private func setupFileMenu() {
    guard let mainMenu = NSApplication.shared.mainMenu else { return }

    // Check if File menu already exists
    if mainMenu.item(withTitle: "File") != nil { return }

    let fileMenu = NSMenu(title: "File")
    let newWindowItem = NSMenuItem(title: "New Window", action: #selector(handleNewWindowAction), keyEquivalent: "n")
    newWindowItem.keyEquivalentModifierMask = .command
    newWindowItem.target = self
    fileMenu.addItem(newWindowItem)

    let closeWindowItem = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    closeWindowItem.keyEquivalentModifierMask = .command
    fileMenu.addItem(closeWindowItem)

    let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
    fileMenuItem.submenu = fileMenu

    // Insert File menu right after the App Name menu (index 1)
    if mainMenu.items.count > 1 {
      mainMenu.insertItem(fileMenuItem, at: 1)
    } else {
      mainMenu.addItem(fileMenuItem)
    }
  }
}

