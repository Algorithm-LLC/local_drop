#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "network_support.h"

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
  network_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "localdrop/network",
          &flutter::StandardMethodCodec::GetInstance());
  network_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "acquireMulticastLock" ||
            call.method_name() == "releaseMulticastLock") {
          result->Success();
          return;
        }

        if (call.method_name() == "getActiveInterfaces") {
          flutter::EncodableList interfaces;
          for (const auto& interface_info : GetActiveInterfaces()) {
            flutter::EncodableMap item;
            item[flutter::EncodableValue("interfaceName")] =
                flutter::EncodableValue(interface_info.interface_name);
            item[flutter::EncodableValue("address")] =
                flutter::EncodableValue(interface_info.address);
            item[flutter::EncodableValue("prefixLength")] =
                flutter::EncodableValue(interface_info.prefix_length);
            interfaces.emplace_back(item);
          }
          result->Success(flutter::EncodableValue(interfaces));
          return;
        }

        if (call.method_name() == "ensureFirewallRules") {
          const FirewallSetupInfo firewall_info =
              EnsureFirewallRulesInteractive();
          flutter::EncodableMap payload;
          payload[flutter::EncodableValue("status")] =
              flutter::EncodableValue(firewall_info.status);
          payload[flutter::EncodableValue("message")] =
              flutter::EncodableValue(firewall_info.message);
          result->Success(flutter::EncodableValue(payload));
          return;
        }

        result->NotImplemented();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

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
  network_channel_ = nullptr;

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
