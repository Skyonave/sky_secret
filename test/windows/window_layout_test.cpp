#include <windows.h>
#include <dwmapi.h>

#include <cstdio>
#include <cstring>
#include <flutter/standard_method_codec.h>

namespace {
const auto manager_handle = reinterpret_cast<HWND>(static_cast<UINT_PTR>(1));
const auto search_handle = reinterpret_cast<HWND>(static_cast<UINT_PTR>(2));
HWND focused_window = manager_handle;
int position_requests = 0;
UINT last_flags = 0;
RECT last_bounds = {};

BOOL WINAPI RecordPosition(HWND window, HWND, int x, int y, int width, int height, UINT flags) {
  ++position_requests;
  last_flags = flags;
  last_bounds = RECT{x, y, width, height};
  if ((flags & SWP_NOACTIVATE) == 0) focused_window = window;
  return TRUE;
}

BOOL WINAPI WindowBounds(HWND, LPRECT rect) {
  *rect = RECT{10, 10, 650, 470};
  return TRUE;
}

HWND WINAPI ChildWindow(HWND window, UINT) { return window; }
HRESULT WINAPI ExtendFrame(HWND, const MARGINS*) { return S_OK; }
}

#define SetWindowPos RecordPosition
#define GetWindowRect WindowBounds
#define GetWindow ChildWindow
#define DwmExtendFrameIntoClientArea ExtendFrame
#include SKY_WINDOW_MANAGER_SOURCE
#undef SetWindowPos
#undef GetWindowRect
#undef GetWindow
#undef DwmExtendFrameIntoClientArea

int main(int argc, char** argv) {
  WindowManager window;
  window.native_window = search_handle;
  if (argc > 1 && std::strcmp(argv[1], "--frame") == 0) {
    window.SetTitleBarStyle({{flutter::EncodableValue("titleBarStyle"), flutter::EncodableValue("hidden")}});
    window.ForceRefresh();
    window.ForceChildRefresh();
    window.SetAsFrameless();
    if (position_requests != 6 || (last_flags & SWP_FRAMECHANGED) == 0) return 3;
  } else {
    window.SetBounds({
        {flutter::EncodableValue("devicePixelRatio"), flutter::EncodableValue(1.5)},
        {flutter::EncodableValue("width"), flutter::EncodableValue(640.0)},
        {flutter::EncodableValue("height"), flutter::EncodableValue(460.0)},
    });
    if (position_requests != 1 || (last_flags & SWP_NOMOVE) == 0 ||
        last_bounds.right != 960 || last_bounds.bottom != 690) return 4;
    if (focused_window != manager_handle) {
      std::fputs("Search preparation stole manager focus while resizing\n", stderr);
      return 1;
    }
    window.SetBounds({
        {flutter::EncodableValue("devicePixelRatio"), flutter::EncodableValue(1.0)},
        {flutter::EncodableValue("x"), flutter::EncodableValue(320.0)},
        {flutter::EncodableValue("y"), flutter::EncodableValue(240.0)},
    });
    if (position_requests != 2 || (last_flags & SWP_NOSIZE) == 0 ||
        last_bounds.left != 320 || last_bounds.top != 240) return 5;
  }
  if (focused_window != manager_handle) {
    std::fputs("Window preparation stole manager focus\n", stderr);
    return 1;
  }
  std::puts("Layout preserves focus and geometry; no windows created");
  return 0;
}
