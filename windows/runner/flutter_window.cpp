#include "flutter_window.h"
#include "resource.h"

#include <optional>
#include <dwmapi.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <app_links/app_links_plugin_c_api.h>
#include <file_selector_windows/file_selector_windows.h>
#include <firebase_core/firebase_core_plugin_c_api.h>
#include <permission_handler_windows/permission_handler_windows_plugin.h>
#include <printing/printing_plugin.h>
#include <url_launcher_windows/url_launcher_windows.h>

#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"

// Must match the value registered in main.cpp.
// RegisterWindowMessage returns 0 on failure; we initialise lazily below.
static UINT WM_NEW_SUBWINDOW = 0;

static void RegisterPluginsForSubWindow(flutter::PluginRegistry* registry) {
  AppLinksPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("AppLinksPluginCApi"));
  // NOTE: We intentionally do NOT call DesktopMultiWindowPluginRegisterWithRegistrar
  // here. desktop_multi_window already registers its own sub-window channel with
  // its unique window ID in its internal constructor. Calling DesktopMultiWindowPluginRegisterWithRegistrar
  // here would re-register as window 0, corrupting the sub-window's IPC channel.
  FileSelectorWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FileSelectorWindows"));
  FirebaseCorePluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FirebaseCorePluginCApi"));
  PermissionHandlerWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("PermissionHandlerWindowsPlugin"));
  PrintingPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("PrintingPlugin"));
  UrlLauncherWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("UrlLauncherWindows"));
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  DesktopMultiWindowSetWindowCreatedCallback([](void *controller) {
    auto *flutter_view_controller = reinterpret_cast<flutter::FlutterViewController *>(controller);
    RegisterPluginsForSubWindow(flutter_view_controller->engine());

    // ── Dark title bar for sub-windows ─────────────────────────────────────
    // Get the native HWND of the sub-window via its child Flutter view:
    HWND viewHwnd = flutter_view_controller->view()->GetNativeWindow();
    HWND subHwnd = ::GetAncestor(viewHwnd, GA_ROOT);
    if (subHwnd) {
      BOOL darkMode = TRUE;
      // DWMWA_USE_IMMERSIVE_DARK_MODE = 20 (Windows 11) / 19 (Windows 10)
      ::DwmSetWindowAttribute(subHwnd, 20, &darkMode, sizeof(darkMode));
      ::DwmSetWindowAttribute(subHwnd, 19, &darkMode, sizeof(darkMode));

      // Set dark caption bar background (#101420) and white title text
      COLORREF captionColor = RGB(16, 20, 32);
      ::DwmSetWindowAttribute(subHwnd, 35 /* DWMWA_CAPTION_COLOR */, &captionColor, sizeof(captionColor));
      COLORREF textColor = RGB(255, 255, 255);
      ::DwmSetWindowAttribute(subHwnd, 36 /* DWMWA_TEXT_COLOR */, &textColor, sizeof(textColor));

      // ── Set App Logo Icon on Sub-Window Title Bar ────────────────────────
      HICON hIconBig = (HICON)::LoadImage(
          ::GetModuleHandle(nullptr),
          MAKEINTRESOURCE(IDI_APP_ICON),
          IMAGE_ICON,
          ::GetSystemMetrics(SM_CXICON),
          ::GetSystemMetrics(SM_CYICON),
          LR_DEFAULTCOLOR);
      HICON hIconSmall = (HICON)::LoadImage(
          ::GetModuleHandle(nullptr),
          MAKEINTRESOURCE(IDI_APP_ICON),
          IMAGE_ICON,
          ::GetSystemMetrics(SM_CXSMICON),
          ::GetSystemMetrics(SM_CYSMICON),
          LR_DEFAULTCOLOR);
      if (!hIconBig) {
        hIconBig = ::LoadIcon(::GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
      }
      if (!hIconSmall) {
        hIconSmall = ::LoadIcon(::GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
      }
      if (hIconBig) {
        ::SendMessage(subHwnd, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(hIconBig));
      }
      if (hIconSmall) {
        ::SendMessage(subHwnd, WM_SETICON, ICON_SMALL, reinterpret_cast<LPARAM>(hIconSmall));
      }
    }
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Apply dark title bar to the MAIN window too (respects system dark mode).
  HWND mainHwnd = GetHandle();
  if (mainHwnd) {
    BOOL darkMode = TRUE;
    ::DwmSetWindowAttribute(mainHwnd, 20, &darkMode, sizeof(darkMode));
    ::DwmSetWindowAttribute(mainHwnd, 19, &darkMode, sizeof(darkMode));
    COLORREF captionColor = RGB(16, 20, 32);
    ::DwmSetWindowAttribute(mainHwnd, 35 /* DWMWA_CAPTION_COLOR */, &captionColor, sizeof(captionColor));
    COLORREF textColor = RGB(255, 255, 255);
    ::DwmSetWindowAttribute(mainHwnd, 36 /* DWMWA_TEXT_COLOR */, &textColor, sizeof(textColor));

    HICON hIconBig = (HICON)::LoadImage(
        ::GetModuleHandle(nullptr),
        MAKEINTRESOURCE(IDI_APP_ICON),
        IMAGE_ICON,
        ::GetSystemMetrics(SM_CXICON),
        ::GetSystemMetrics(SM_CYICON),
        LR_DEFAULTCOLOR);
    HICON hIconSmall = (HICON)::LoadImage(
        ::GetModuleHandle(nullptr),
        MAKEINTRESOURCE(IDI_APP_ICON),
        IMAGE_ICON,
        ::GetSystemMetrics(SM_CXSMICON),
        ::GetSystemMetrics(SM_CYSMICON),
        LR_DEFAULTCOLOR);
    if (!hIconBig) {
      hIconBig = ::LoadIcon(::GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
    }
    if (!hIconSmall) {
      hIconSmall = ::LoadIcon(::GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
    }
    if (hIconBig) {
      ::SendMessage(mainHwnd, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(hIconBig));
    }
    if (hIconSmall) {
      ::SendMessage(mainHwnd, WM_SETICON, ICON_SMALL, reinterpret_cast<LPARAM>(hIconSmall));
    }
  }

  // Lazy-register the cross-process "new sub-window" message.
  WM_NEW_SUBWINDOW = ::RegisterWindowMessage(L"PerfectSolution_OpenNewSubWindow");

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // ── Cross-process "New Window" signal ────────────────────────────────────
  // Sent by a short-lived helper process launched from the taskbar jump list
  // (see main.cpp). We forward it to Flutter via the native method channel so
  // MultiWindowSyncService can call createNewWindow().
  if (WM_NEW_SUBWINDOW != 0 && message == WM_NEW_SUBWINDOW) {
    if (flutter_controller_) {
      auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.perfectsolution/desktop_window_manager",
          &flutter::StandardMethodCodec::GetInstance());
      channel->InvokeMethod("new_window", nullptr);
    }
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
