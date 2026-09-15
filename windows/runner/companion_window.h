#ifndef RUNNER_COMPANION_WINDOW_H_
#define RUNNER_COMPANION_WINDOW_H_

#include <windows.h>
#include <optional>

class CompanionWindow {
 public:
  explicit CompanionWindow(HWND main) : main_(main) {}
  std::optional<RECT> Bounds() const;
  bool Place(HWND child, double gap);
  void Detach();
  void OnMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  bool ValidChild(HWND child) const;
  bool Follow();
  HWND main_;
  HWND child_ = nullptr;
  bool left_ = true;
  double gap_ = 12;
};

#endif
