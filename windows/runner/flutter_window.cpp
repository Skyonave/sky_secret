#include "flutter_window.h"

#include <optional>
#include <wtsapi32.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();



  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);

  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  ssh_bridge_ = std::make_unique<SshBridge>(flutter_controller_->engine()->messenger());
  DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
    auto* view_controller = reinterpret_cast<flutter::FlutterViewController*>(controller);
    RegisterPlugins(view_controller->engine());
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  companion_ = std::make_unique<CompanionWindow>(GetHandle());
  search_companion_ = std::make_unique<CompanionWindow>(GetHandle());
  companion_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "skysecret/companion",
      &flutter::StandardMethodCodec::GetInstance());
  companion_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "bounds") {
      const auto bounds = companion_->Bounds();
      const double scale = GetDpiForWindow(GetHandle()) / 96.0;
      if (!bounds || scale <= 0) {
        result->Error("WINDOW_UNAVAILABLE", "Window bounds unavailable");
        return;
      }
      result->Success(flutter::EncodableValue(flutter::EncodableMap{
          {flutter::EncodableValue("x"), flutter::EncodableValue(bounds->left / scale)},
          {flutter::EncodableValue("y"), flutter::EncodableValue(bounds->top / scale)},
          {flutter::EncodableValue("width"), flutter::EncodableValue((bounds->right - bounds->left) / scale)},
          {flutter::EncodableValue("height"), flutter::EncodableValue((bounds->bottom - bounds->top) / scale)},
      }));
    } else if (call.method_name() == "place" || call.method_name() == "placeSearch") {
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      if (!args || args->count(flutter::EncodableValue("window")) == 0 ||
          args->count(flutter::EncodableValue("gap")) == 0) {
        result->Success(flutter::EncodableValue(false));
        return;
      }
      const auto& id = args->at(flutter::EncodableValue("window"));
      const auto* gap = std::get_if<double>(&args->at(flutter::EncodableValue("gap")));
      const bool integer = std::holds_alternative<int32_t>(id) || std::holds_alternative<int64_t>(id);
      const bool search = call.method_name() == "placeSearch";
      auto* target = search ? search_companion_.get() : companion_.get();
      result->Success(flutter::EncodableValue(integer && gap &&
          target->Place(reinterpret_cast<HWND>(id.LongValue()), *gap, search)));
    } else if (call.method_name() == "detachSearch") {
      search_companion_->Detach();
      result->Success();
    } else if (call.method_name() == "detach") {
      companion_->Detach();
      result->Success();
    } else {
      result->NotImplemented();
    }
  });
  file_drop_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "skysecret/file_drop",
      &flutter::StandardMethodCodec::GetInstance());
  file_drop_ = new FileDropTarget(flutter_controller_->view()->GetNativeWindow(),
      [this](const char* event, const std::vector<std::string>& paths) {
        if (file_drop_ && (std::string(event) == "entered" || std::string(event) == "files")) {
          const auto point = file_drop_->position();
          const double scale = GetDpiForWindow(flutter_controller_->view()->GetNativeWindow()) / 96.0;
          flutter::EncodableList position{flutter::EncodableValue(point.x / scale), flutter::EncodableValue(point.y / scale)};
          file_drop_channel_->InvokeMethod("position", std::make_unique<flutter::EncodableValue>(position));
        }
        flutter::EncodableList values;
        for (const auto& path : paths) values.emplace_back(path);
        file_drop_channel_->InvokeMethod(event, std::make_unique<flutter::EncodableValue>(values));
      });
  file_drop_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "ready") {
      result->Success(flutter::EncodableValue(file_drop_ && file_drop_->ready()));
    } else {
      result->NotImplemented();
    }
  });
  security_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "skysecret/system_lock",
      &flutter::StandardMethodCodec::GetInstance());
  session_notifications_ = WTSRegisterSessionNotification(GetHandle(), NOTIFY_FOR_THIS_SESSION) != FALSE;
  security_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "ready") {
      if (!session_notifications_) {
        session_notifications_ = WTSRegisterSessionNotification(GetHandle(), NOTIFY_FOR_THIS_SESSION) != FALSE;
      }
      result->Success(flutter::EncodableValue(session_notifications_));
    } else {
      result->NotImplemented();
    }
  });



  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (companion_) companion_->Detach();
  if (search_companion_) search_companion_->Detach();
  companion_channel_.reset();
  companion_.reset();
  search_companion_.reset();
  ssh_bridge_.reset();
  if (file_drop_) {
    file_drop_->Stop();
    file_drop_->Release();
    file_drop_ = nullptr;
  }
  file_drop_channel_.reset();
  if (session_notifications_) WTSUnRegisterSessionNotification(GetHandle());
  security_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {



  if (message == WM_SYSCOMMAND && (wparam & 0xFFF0) == SC_KEYMENU &&
      lparam == 0) {
    return 0;
  }
  if (companion_) companion_->OnMessage(message, wparam, lparam);
  if (search_companion_) search_companion_->OnMessage(message, wparam, lparam);
  if (message == WM_SHOWWINDOW && !wparam && file_drop_) {

    file_drop_->DragLeave();
  }

  if (security_channel_ &&
      ((message == WM_WTSSESSION_CHANGE &&
        (wparam == WTS_SESSION_LOCK || wparam == WTS_SESSION_LOGOFF ||
         wparam == WTS_CONSOLE_DISCONNECT || wparam == WTS_REMOTE_DISCONNECT)) ||
       (message == WM_POWERBROADCAST &&
        (wparam == PBT_APMSUSPEND || wparam == PBT_APMRESUMEAUTOMATIC ||
         wparam == PBT_APMRESUMESUSPEND)))) {
    if (ssh_bridge_) ssh_bridge_->Revoke();
    security_channel_->InvokeMethod("lock", nullptr);
  }

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
