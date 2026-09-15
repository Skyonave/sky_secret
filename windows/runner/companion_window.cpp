#include "companion_window.h"

#include <cmath>

std::optional<RECT> CompanionWindow::Bounds() const {
  RECT client{};
  if (!GetClientRect(main_, &client)) return std::nullopt;
  POINT origin{client.left, client.top};
  if (!ClientToScreen(main_, &origin)) return std::nullopt;
  return RECT{origin.x, origin.y, origin.x + client.right - client.left,
              origin.y + client.bottom - client.top};
}

bool CompanionWindow::ValidChild(HWND child) const {
  DWORD process = 0;
  if (!child || child == main_ || !IsWindow(child) || GetAncestor(child, GA_ROOT) != child) return false;
  GetWindowThreadProcessId(child, &process);
  return process == GetCurrentProcessId();
}

bool CompanionWindow::Place(HWND child, double gap, bool above) {
  if (!ValidChild(child) || !std::isfinite(gap) || gap < 0 || gap > 100) return false;
  const auto bounds = Bounds();
  RECT tile{};
  MONITORINFO monitor{sizeof(MONITORINFO)};
  if (!bounds || !GetWindowRect(child, &tile) ||
      !GetMonitorInfo(MonitorFromWindow(main_, MONITOR_DEFAULTTONEAREST), &monitor)) return false;
  gap_ = gap;
  above_ = above;
  if (child_ != child) {
    const auto needed = tile.right - tile.left + std::lround(gap_ * GetDpiForWindow(main_) / 96.0);
    const auto left_room = bounds->left - monitor.rcWork.left;
    const auto right_room = monitor.rcWork.right - bounds->right;
    left_ = left_room >= needed || left_room >= right_room;
  }
  child_ = child;
  return Follow();
}

bool CompanionWindow::Follow() {
  if (!ValidChild(child_)) {
    child_ = nullptr;
    return false;
  }
  const auto bounds = Bounds();
  RECT tile{};
  if (!bounds || !GetWindowRect(child_, &tile)) return false;
  const auto gap = std::lround(gap_ * GetDpiForWindow(main_) / 96.0);
  auto x = left_ ? bounds->left - gap - (tile.right - tile.left) : bounds->right + gap;
  auto y = bounds->bottom - (tile.bottom - tile.top);
  if (above_) {
    MONITORINFO monitor{sizeof(MONITORINFO)};
    if (!GetMonitorInfo(MonitorFromWindow(main_, MONITOR_DEFAULTTONEAREST), &monitor)) return false;
    const auto width = tile.right - tile.left;
    const auto height = tile.bottom - tile.top;
    x = bounds->left + (bounds->right - bounds->left - width) / 2;
    y = bounds->top - gap - height;
    if (x + width > monitor.rcWork.right) x = monitor.rcWork.right - width;
    if (x < monitor.rcWork.left) x = monitor.rcWork.left;
    if (y < monitor.rcWork.top) y = monitor.rcWork.top;
  }
  if (tile.left == x && tile.top == y) return true;
  return SetWindowPos(child_, nullptr, x, y, 0, 0,
                      SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER) != FALSE;
}

void CompanionWindow::Detach() {
  if (ValidChild(child_)) ShowWindow(child_, SW_HIDE);
  child_ = nullptr;
}

void CompanionWindow::OnMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if ((message == WM_SHOWWINDOW && !wparam) || (message == WM_SIZE && wparam == SIZE_MINIMIZED)) {
    Detach();
  } else if (message == WM_WINDOWPOSCHANGED) {
    const auto position = reinterpret_cast<const WINDOWPOS*>(lparam);
    if (position && (position->flags & SWP_HIDEWINDOW)) {
      Detach();
    } else if (!IsIconic(main_)) {
      Follow();
    }
  }
}
