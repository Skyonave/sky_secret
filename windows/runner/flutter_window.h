#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>

#include <memory>

#include "win32_window.h"
#include "file_drop_target.h"
#include "ssh_bridge.h"


class FlutterWindow : public Win32Window {
 public:

  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:

  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:

  flutter::DartProject project_;


  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> security_channel_;
  std::unique_ptr<SshBridge> ssh_bridge_;
  bool session_notifications_ = false;
  FileDropTarget* file_drop_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> file_drop_channel_;
};

#endif
