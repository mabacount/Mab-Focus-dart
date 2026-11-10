#include "flutter_window.h"

#include <optional>
#include <shobjidl.h>

#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"

namespace {

constexpr UINT_PTR kPinVirtualDesktopTimerId = 1001;
constexpr int kMaxPinRetries = 6;

const CLSID CLSID_ImmersiveShell = { 0xC2F03A33, 0x21F5, 0x47FA, { 0xB4, 0xBB, 0x15, 0x63, 0x62, 0xA2, 0xF2, 0x39 } };
const IID IID_IApplicationViewCollection = { 0x1841C6D7, 0x4F9D, 0x42C0, { 0xAF, 0x41, 0x87, 0x47, 0x53, 0x8F, 0x10, 0xE5 } };
const CLSID CLSID_VirtualDesktopPinnedApps = { 0xB5A399E7, 0x1C87, 0x46B8, { 0x88, 0xE9, 0xFC, 0x57, 0x47, 0xB1, 0x71, 0xBD } };
const IID IID_IVirtualDesktopPinnedApps = { 0x4CE81583, 0x1E4C, 0x4632, { 0xA6, 0x21, 0x07, 0xA5, 0x35, 0x43, 0x14, 0x8F } };

MIDL_INTERFACE("372E1D3B-38D3-42E4-A15B-8AB2B178F513")
IApplicationView : public IUnknown {
public:
    virtual HRESULT STDMETHODCALLTYPE GetIids(ULONG* iidCount, IID** iids) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetRuntimeClassName(void** className) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetTrustLevel(int* trustLevel) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetFocus() = 0;
};

MIDL_INTERFACE("1841C6D7-4F9D-42C0-AF41-8747538F10E5")
IApplicationViewCollection : public IUnknown {
public:
    virtual HRESULT STDMETHODCALLTYPE GetViews(IObjectArray** views) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetViewsByZOrder(IObjectArray** views) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetViewsByAppUserModelId(PCWSTR id, IObjectArray** views) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetViewForHwnd(HWND hwnd, IApplicationView** view) = 0;
};

MIDL_INTERFACE("4CE81583-1E4C-4632-A621-07A53543148F")
IVirtualDesktopPinnedApps : public IUnknown {
public:
    virtual HRESULT STDMETHODCALLTYPE IsAppIdPinned(PCWSTR appId, BOOL* pfPinned) = 0;
    virtual HRESULT STDMETHODCALLTYPE PinAppID(PCWSTR appId) = 0;
    virtual HRESULT STDMETHODCALLTYPE UnpinAppID(PCWSTR appId) = 0;
    virtual HRESULT STDMETHODCALLTYPE IsViewPinned(IApplicationView* pView, BOOL* pfPinned) = 0;
    virtual HRESULT STDMETHODCALLTYPE PinView(IApplicationView* pView) = 0;
    virtual HRESULT STDMETHODCALLTYPE UnpinView(IApplicationView* pView) = 0;
};

bool PinWindowToAllVirtualDesktops(HWND hwnd) {
  if (!hwnd || !::IsWindow(hwnd)) return false;

  HRESULT hrInit = ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  bool didCoInit = (hrInit == S_OK || hrInit == S_FALSE);

  bool pinned = false;
  IServiceProvider* pServiceProvider = nullptr;
  HRESULT hr = ::CoCreateInstance(
      CLSID_ImmersiveShell, nullptr, CLSCTX_LOCAL_SERVER,
      IID_IServiceProvider, reinterpret_cast<void**>(&pServiceProvider));

  if (SUCCEEDED(hr) && pServiceProvider) {
    IApplicationViewCollection* pViewCollection = nullptr;
    hr = pServiceProvider->QueryService(
        IID_IApplicationViewCollection, IID_IApplicationViewCollection,
        reinterpret_cast<void**>(&pViewCollection));

    if (SUCCEEDED(hr) && pViewCollection) {
      IVirtualDesktopPinnedApps* pPinnedApps = nullptr;
      hr = pServiceProvider->QueryService(
          CLSID_VirtualDesktopPinnedApps, IID_IVirtualDesktopPinnedApps,
          reinterpret_cast<void**>(&pPinnedApps));

      if (SUCCEEDED(hr) && pPinnedApps) {
        IApplicationView* pAppView = nullptr;
        hr = pViewCollection->GetViewForHwnd(hwnd, &pAppView);
        if (SUCCEEDED(hr) && pAppView) {
          BOOL alreadyPinned = FALSE;
          if (SUCCEEDED(pPinnedApps->IsViewPinned(pAppView, &alreadyPinned)) &&
              alreadyPinned) {
            pinned = true;
          } else {
            hr = pPinnedApps->PinView(pAppView);
            pinned = SUCCEEDED(hr);
          }
          pAppView->Release();
        }
        pPinnedApps->Release();
      }
      pViewCollection->Release();
    }
    pServiceProvider->Release();
  }

  if (didCoInit) {
    ::CoUninitialize();
  }
  return pinned;
}

}  // namespace

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
    auto *flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController *>(controller);
    auto *registry = flutter_view_controller->engine();
    RegisterPlugins(registry);
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  HWND hwnd = GetHandle();
  // تلاش اولیه بلافاصله پس از دریافت HWND در OnCreate
  PinWindowToAllVirtualDesktops(hwnd);

  vdesktop_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.mabfocus.app/virtual_desktop",
          &flutter::StandardMethodCodec::GetInstance());

  vdesktop_channel_->SetMethodCallHandler(
      [hwnd](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name().compare("pinToAllDesktops") == 0) {
          bool success = PinWindowToAllVirtualDesktops(hwnd);
          result->Success(flutter::EncodableValue(success));
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([this, hwnd]() {
    this->Show();
    if (!PinWindowToAllVirtualDesktops(hwnd)) {
      pin_retry_count_ = 0;
      ::SetTimer(hwnd, kPinVirtualDesktopTimerId, 250, nullptr);
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (HWND hwnd = GetHandle()) {
    ::KillTimer(hwnd, kPinVirtualDesktopTimerId);
  }
  if (vdesktop_channel_) {
    vdesktop_channel_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

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
    case WM_TIMER:
      if (wparam == kPinVirtualDesktopTimerId) {
        ++pin_retry_count_;
        if (PinWindowToAllVirtualDesktops(hwnd) ||
            pin_retry_count_ >= kMaxPinRetries) {
          ::KillTimer(hwnd, kPinVirtualDesktopTimerId);
        }
        return 0;
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
