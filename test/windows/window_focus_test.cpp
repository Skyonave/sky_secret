#include <windows.h>
#include <dwmapi.h>

#include <cstdio>
#include <cstring>

namespace {
bool visible = false;
HWND active_window = nullptr;
int focus_requests = 0;
int composition_requests = 0;
BOOL last_cloaked = FALSE;

HRESULT WINAPI RecordComposition(HWND, DWORD attribute, LPCVOID value, DWORD size) {
  if (attribute == DWMWA_CLOAK && size == sizeof(BOOL)) {
    ++composition_requests;
    last_cloaked = *static_cast<const BOOL*>(value);
  }
  return S_OK;
}

HWND WINAPI RecordFocus(HWND) {
  ++focus_requests;
  return nullptr;
}

BOOL WINAPI WindowVisible(HWND) { return visible; }
HWND WINAPI ActiveWindow() { return active_window; }
HWND WINAPI ParentWindow(HWND, HWND) { return nullptr; }
BOOL WINAPI ResizeWindow(HWND, int, int, int, int, BOOL) { return TRUE; }
BOOL WINAPI ClientArea(HWND, LPRECT rect) {
  *rect = RECT{0, 0, 640, 460};
  return TRUE;
}
}

#define SetFocus RecordFocus
#define IsWindowVisible WindowVisible
#define GetActiveWindow ActiveWindow
#define SetParent ParentWindow
#define MoveWindow ResizeWindow
#define GetClientRect ClientArea
#define DwmSetWindowAttribute RecordComposition
#include SKY_WINDOW_SOURCE
#undef SetFocus
#undef IsWindowVisible
#undef GetActiveWindow
#undef SetParent
#undef MoveWindow
#undef GetClientRect
#undef DwmSetWindowAttribute

class TestWindow : public Win32Window {
 public:
  using Win32Window::MessageHandler;
};

int main(int argc, char** argv) {
  TestWindow window;
  const auto child = reinterpret_cast<HWND>(static_cast<UINT_PTR>(1));
  window.SetChildContent(child);
  if (argc > 1 && std::strcmp(argv[1], "--activation") == 0) focus_requests = 0;
  if (focus_requests != 0) {
    std::fputs("Hidden child requested focus during attachment\n", stderr);
    return 1;
  }

  visible = true;
  window.MessageHandler(nullptr, WM_ACTIVATE, WA_INACTIVE, 0);
  if (focus_requests != 0) {
    std::fputs("Inactive window reclaimed focus\n", stderr);
    return 2;
  }

  window.MessageHandler(nullptr, WM_ACTIVATE, WA_ACTIVE, 0);
  if (focus_requests != 1) {
    std::fputs("Active window did not focus its content\n", stderr);
    return 3;
  }

  visible = false;
  window.MessageHandler(nullptr, WM_ACTIVATE, WA_ACTIVE, 0);
  if (focus_requests != 1) {
    std::fputs("Hidden window requested focus on activation\n", stderr);
    return 4;
  }

  window.MessageHandler(nullptr, WM_SHOWWINDOW, FALSE, 0);
  if (composition_requests != 1 || last_cloaked != TRUE) {
    std::fputs("Hidden window was not cloaked\n", stderr);
    return 5;
  }
  window.MessageHandler(nullptr, WM_SHOWWINDOW, TRUE, 0);
  if (composition_requests != 2 || last_cloaked != FALSE) {
    std::fputs("Shown window remained cloaked\n", stderr);
    return 6;
  }

  std::puts("Native focus and composition checks passed; no windows created");
  return 0;
}
