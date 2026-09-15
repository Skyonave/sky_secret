#include <windows.h>
#include <cstdio>

namespace {
const auto main_window = reinterpret_cast<HWND>(static_cast<UINT_PTR>(1));
const auto code_window = reinterpret_cast<HWND>(static_cast<UINT_PTR>(2));
RECT main_bounds{1400, 400, 1870, 1010};
RECT code_bounds{0, 0, 227, 56};
RECT work_bounds{0, 0, 1920, 1040};
UINT dpi = 96;
DWORD child_process = 42;
int moves = 0;
int hides = 0;
UINT move_flags = 0;

BOOL WINAPI ClientBounds(HWND window, LPRECT rect) {
  if (window != main_window) return FALSE;
  *rect = RECT{0, 0, main_bounds.right - main_bounds.left - 16, main_bounds.bottom - main_bounds.top - 8};
  return TRUE;
}
BOOL WINAPI ScreenPoint(HWND, LPPOINT point) {
  point->x += main_bounds.left + 8;
  point->y += main_bounds.top;
  return TRUE;
}
BOOL WINAPI WindowBounds(HWND window, LPRECT rect) {
  *rect = window == main_window ? main_bounds : code_bounds;
  return TRUE;
}
BOOL WINAPI ValidWindow(HWND window) { return window == main_window || window == code_window; }
HWND WINAPI Ancestor(HWND window, UINT) { return window; }
DWORD WINAPI WindowProcess(HWND, LPDWORD process) { *process = child_process; return 7; }
DWORD WINAPI CurrentProcess() { return 42; }
UINT WINAPI WindowDpi(HWND) { return dpi; }
HMONITOR WINAPI WindowMonitor(HWND, DWORD) { return reinterpret_cast<HMONITOR>(1); }
BOOL WINAPI MonitorInfo(HMONITOR, LPMONITORINFO info) { info->rcWork = work_bounds; return TRUE; }
BOOL WINAPI Iconic(HWND) { return FALSE; }
BOOL WINAPI Visibility(HWND window, int command) {
  if (window == code_window && command == SW_HIDE) ++hides;
  return TRUE;
}
BOOL WINAPI Position(HWND window, HWND, int x, int y, int, int, UINT flags) {
  if (window != code_window) return FALSE;
  ++moves;
  move_flags = flags;
  code_bounds = RECT{x, y, x + code_bounds.right - code_bounds.left, y + code_bounds.bottom - code_bounds.top};
  return TRUE;
}
}

#define GetClientRect ClientBounds
#define ClientToScreen ScreenPoint
#define GetWindowRect WindowBounds
#define IsWindow ValidWindow
#define GetAncestor Ancestor
#define GetWindowThreadProcessId WindowProcess
#define GetCurrentProcessId CurrentProcess
#define GetDpiForWindow WindowDpi
#define MonitorFromWindow WindowMonitor
#undef GetMonitorInfo
#define GetMonitorInfo MonitorInfo
#define IsIconic Iconic
#define ShowWindow Visibility
#define SetWindowPos Position
#include "../../windows/runner/companion_window.cpp"

#define CHECK(condition) if (!(condition)) { std::fprintf(stderr, "Failed at line %d\n", __LINE__); return 1; }

int main() {
  CompanionWindow companion(main_window);
  CHECK(companion.Place(code_window, 12));
  CHECK(code_bounds.bottom == 1002);
  CHECK(code_bounds.right == 1396);
  CHECK(code_bounds.bottom != main_bounds.bottom);
  const auto initial_moves = moves;
  WINDOWPOS position{};
  for (int step = 0; step < 100; ++step) {
    OffsetRect(&main_bounds, -15, -2);
    companion.OnMessage(WM_WINDOWPOSCHANGED, 0, reinterpret_cast<LPARAM>(&position));
    CHECK(code_bounds.bottom == main_bounds.bottom - 8);
    CHECK(code_bounds.right == main_bounds.left + 8 - 12);
  }
  CHECK(moves == initial_moves + 100);
  CHECK((move_flags & (SWP_NOACTIVATE | SWP_NOSIZE | SWP_NOZORDER)) ==
        (SWP_NOACTIVATE | SWP_NOSIZE | SWP_NOZORDER));
  CHECK((move_flags & (SWP_SHOWWINDOW | SWP_ASYNCWINDOWPOS)) == 0);
  CHECK(companion.Place(code_window, 12));
  CHECK(moves == initial_moves + 100);
  companion.OnMessage(WM_SHOWWINDOW, FALSE, 0);
  CHECK(hides == 1);
  OffsetRect(&main_bounds, 30, 0);
  companion.OnMessage(WM_WINDOWPOSCHANGED, 0, reinterpret_cast<LPARAM>(&position));
  CHECK(moves == initial_moves + 100);
  main_bounds = RECT{-1910, 100, -1440, 710};
  work_bounds = RECT{-1920, 0, 0, 1040};
  CHECK(companion.Place(code_window, 12));
  CHECK(code_bounds.left == main_bounds.right - 8 + 12);
  CHECK(code_bounds.bottom == main_bounds.bottom - 8);
  dpi = 144;
  code_bounds.bottom = code_bounds.top + 180;
  companion.OnMessage(WM_WINDOWPOSCHANGED, 0, reinterpret_cast<LPARAM>(&position));
  CHECK(code_bounds.left == main_bounds.right - 8 + 18);
  CHECK(code_bounds.bottom == main_bounds.bottom - 8);
  CHECK(code_bounds.bottom - code_bounds.top == 180);
  companion.Detach();
  CHECK(!companion.Place(main_window, 12));
  child_process = 77;
  CHECK(!companion.Place(code_window, 12));
  const auto stopped = moves;
  companion.OnMessage(WM_WINDOWPOSCHANGED, 0, reinterpret_cast<LPARAM>(&position));
  CHECK(moves == stopped);
  child_process = 42;
  CHECK(companion.Place(code_window, 12));
  position.flags = SWP_HIDEWINDOW;
  companion.OnMessage(WM_WINDOWPOSCHANGED, 0, reinterpret_cast<LPARAM>(&position));
  CHECK(hides == 3);
  dpi = 96;
  main_bounds = RECT{1000, 400, 1470, 1010};
  work_bounds = RECT{0, 0, 1920, 1040};
  code_bounds = RECT{0, 0, 360, 64};
  CHECK(companion.Place(code_window, 12, true));
  CHECK(code_bounds.left == 1055);
  CHECK(code_bounds.bottom == main_bounds.top - 12);
  const auto fixed_width = code_bounds.right - code_bounds.left;
  main_bounds.right += 300;
  position.flags = 0;
  companion.OnMessage(WM_WINDOWPOSCHANGED, 0, reinterpret_cast<LPARAM>(&position));
  CHECK(code_bounds.left == 1205);
  CHECK(code_bounds.right - code_bounds.left == fixed_width);
  code_bounds.bottom = code_bounds.top + 256;
  main_bounds.top = 20;
  companion.OnMessage(WM_WINDOWPOSCHANGED, 0, reinterpret_cast<LPARAM>(&position));
  CHECK(code_bounds.top == work_bounds.top);
  CHECK(code_bounds.bottom - code_bounds.top == 256);
  CHECK((move_flags & SWP_NOACTIVATE) != 0);
  std::puts("Companion follows each native move, aligns client edges, preserves focus and detaches; no windows created");
  return 0;
}
