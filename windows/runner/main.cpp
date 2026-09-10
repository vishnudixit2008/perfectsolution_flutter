#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shobjidl.h>
#include <propkey.h>
#include <propvarutil.h>

#include "flutter_window.h"
#include "utils.h"

// Global registered message ID for "open new sub-window" cross-process signal.
// Both the new process and the existing process use this same name so the ID matches.
static UINT WM_NEW_SUBWINDOW = 0;

static void SetupWindowsJumpList() {
  ICustomDestinationList* pDestList = nullptr;
  HRESULT hr = CoCreateInstance(CLSID_DestinationList, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&pDestList));
  if (FAILED(hr)) return;

  UINT maxSlots;
  IObjectArray* pRemovedList = nullptr;
  hr = pDestList->BeginList(&maxSlots, IID_PPV_ARGS(&pRemovedList));
  if (SUCCEEDED(hr)) {
    IObjectCollection* pTasks = nullptr;
    hr = CoCreateInstance(CLSID_EnumerableObjectCollection, nullptr, CLSCTX_INPROC_SERVER,
                          IID_PPV_ARGS(&pTasks));
    if (SUCCEEDED(hr)) {
      wchar_t exePath[MAX_PATH];
      GetModuleFileNameW(nullptr, exePath, MAX_PATH);

      IShellLinkW* pLink = nullptr;
      hr = CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                            IID_PPV_ARGS(&pLink));
      if (SUCCEEDED(hr)) {
        pLink->SetPath(exePath);
        pLink->SetArguments(L"--new-window");
        pLink->SetIconLocation(exePath, 0);

        IPropertyStore* pPropStore = nullptr;
        hr = pLink->QueryInterface(IID_PPV_ARGS(&pPropStore));
        if (SUCCEEDED(hr)) {
          PROPVARIANT pv;
          InitPropVariantFromString(L"New Window", &pv);
          pPropStore->SetValue(PKEY_Title, pv);
          PropVariantClear(&pv);
          pPropStore->Commit();
          pPropStore->Release();
        }

        pTasks->AddObject(pLink);
        pLink->Release();
      }

      IObjectArray* pTaskArray = nullptr;
      hr = pTasks->QueryInterface(IID_PPV_ARGS(&pTaskArray));
      if (SUCCEEDED(hr)) {
        pDestList->AddUserTasks(pTaskArray);
        pTaskArray->Release();
      }
      pTasks->Release();
    }
    pDestList->CommitList();
    if (pRemovedList) pRemovedList->Release();
  }
  pDestList->Release();
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Register the cross-process "open new sub-window" message (both processes
  // must call RegisterWindowMessage with the SAME string to get matching IDs).
  WM_NEW_SUBWINDOW = ::RegisterWindowMessage(L"PerfectSolution_OpenNewSubWindow");

  // ── Handle --new-window from Windows taskbar jump list ────────────────────
  // When the user right-clicks the taskbar icon and picks "New Window", Windows
  // launches a fresh process with the "--new-window" argument. Rather than
  // starting a duplicate main window, we signal the EXISTING process to open
  // a new sub-window and then exit cleanly.
  if (command_line && wcsstr(command_line, L"--new-window") != nullptr) {
    // Find the existing main Flutter window by its title.
    HWND existingHwnd = ::FindWindow(nullptr, L"Perfect Solution");
    if (existingHwnd != nullptr && ::IsWindow(existingHwnd)) {
      ::PostMessage(existingHwnd, WM_NEW_SUBWINDOW, 0, 0);
      ::CoUninitialize();
      return EXIT_SUCCESS;  // Exit this helper process.
    }
    // No existing window found — fall through and start normally (first launch).
  }

  // Setup Windows Taskbar Jump List tasks ("New Window")
  SetupWindowsJumpList();

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Perfect Solution", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
