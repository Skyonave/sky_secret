#include "file_drag_source.h"

#include <algorithm>
#include <ole2.h>
#include <utility>

namespace {
const flutter::EncodableValue* Argument(const flutter::EncodableMap* map, const char* key) {
  if (!map) return nullptr;
  const auto found = map->find(flutter::EncodableValue(key));
  return found == map->end() ? nullptr : &found->second;
}

int64_t Integer(const flutter::EncodableValue* value) {
  if (!value || (!std::holds_alternative<int32_t>(*value) && !std::holds_alternative<int64_t>(*value))) return -1;
  return value->LongValue();
}

class DropSource final : public IDropSource {
 public:
  DropSource(HWND window, std::shared_ptr<VirtualFilePayload> payload)
      : window_(window), payload_(std::move(payload)), started_(GetTickCount64()) {}
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** result) override {
    if (!result) return E_POINTER;
    *result = nullptr;
    if (iid != IID_IUnknown && iid != IID_IDropSource) return E_NOINTERFACE;
    *result = static_cast<IDropSource*>(this);
    AddRef();
    return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&references_); }
  ULONG STDMETHODCALLTYPE Release() override {
    const auto remaining = InterlockedDecrement(&references_);
    if (!remaining) delete this;
    return remaining;
  }
  HRESULT STDMETHODCALLTYPE QueryContinueDrag(BOOL escape, DWORD keys) override {
    if (escape || (keys & (MK_RBUTTON | MK_MBUTTON)) || !IsWindowVisible(window_) ||
        !payload_->available() || GetTickCount64() - started_ > 120000) {
      payload_->Revoke();
      return DRAGDROP_S_CANCEL;
    }
    if (!(keys & MK_LBUTTON)) {
      payload_->AuthorizeDrop();
      return DRAGDROP_S_DROP;
    }
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GiveFeedback(DWORD) override { return DRAGDROP_S_USEDEFAULTCURSORS; }

 private:
  LONG references_ = 1;
  HWND window_;
  std::shared_ptr<VirtualFilePayload> payload_;
  ULONGLONG started_;
};
}

void FileDragSource::Start(const flutter::EncodableValue* arguments,
                           flutter::MethodResult<flutter::EncodableValue>* result) {
  const auto* args = arguments ? std::get_if<flutter::EncodableMap>(arguments) : nullptr;
  const auto id = Integer(Argument(args, "id"));
  const auto epoch = Integer(Argument(args, "epoch"));
  const auto size = Integer(Argument(args, "size"));
  const auto* name_value = Argument(args, "name");
  const auto* data_value = Argument(args, "data");
  const auto* name = name_value ? std::get_if<std::string>(name_value) : nullptr;
  const auto* data = data_value ? std::get_if<std::vector<uint8_t>>(data_value) : nullptr;
  if (id <= 0 || size < 0 || size > static_cast<int64_t>(VirtualFilePayload::kMaxSize) || !name || !data ||
      name->size() > 960 || data->size() != static_cast<size_t>(((size + 15) / 16) * 16)) {
    result->Error("INVALID_DRAG", "Invalid file transfer");
    return;
  }
  POINT cursor{};
  RECT client{};
  const bool positioned = GetCursorPos(&cursor) && ScreenToClient(window_, &cursor) && GetClientRect(window_, &client);
  if (stopped_ || suspended_ || active_ || epoch != generation_ || id <= revoked_through_ || !IsWindowVisible(window_) ||
      !(GetAsyncKeyState(VK_LBUTTON) & 0x8000) || !positioned || PtInRect(&client, cursor)) {
    result->Success(flutter::EncodableValue(false));
    return;
  }
  const auto length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, name->data(), static_cast<int>(name->size()), nullptr, 0);
  if (length <= 0 || length > 240) {
    result->Error("INVALID_DRAG", "Invalid file transfer");
    return;
  }
  std::wstring file_name(length, L'\0');
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, name->data(), static_cast<int>(name->size()), file_name.data(), length) ||
      !ValidVirtualFileName(file_name)) {
    result->Error("INVALID_DRAG", "Invalid file transfer");
    return;
  }
  const auto initialized = OleInitialize(nullptr);
  if (FAILED(initialized)) {
    result->Error("DRAG_UNAVAILABLE", "File transfer unavailable");
    return;
  }
  HRESULT status = E_FAIL;
  DWORD effect = DROPEFFECT_NONE;
  IDataObject* object = nullptr;
  DropSource* source = nullptr;
  try {
    active_id_ = id;
    active_ = std::make_shared<VirtualFilePayload>(std::move(file_name), static_cast<size_t>(size), *data);
    status = CreateVirtualFileData(active_, &object);
    if (SUCCEEDED(status)) {
      source = new DropSource(window_, active_);
      ReleaseCapture();
      status = DoDragDrop(object, source, DROPEFFECT_COPY, &effect);
    }
  } catch (...) {
    status = E_OUTOFMEMORY;
  }
  Revoke();
  if (source) source->Release();
  if (object) object->Release();
  active_.reset();
  active_id_ = 0;
  OleUninitialize();
  if (stopped_) return;
  if (FAILED(status)) result->Error("DRAG_FAILED", "File transfer failed");
  else result->Success(flutter::EncodableValue(status == DRAGDROP_S_DROP && (effect & DROPEFFECT_COPY) != 0));
}

void FileDragSource::Cancel(int64_t through) {
  revoked_through_ = std::max(revoked_through_, through);
  if (active_id_ > 0 && active_id_ <= revoked_through_) Revoke();
}

void FileDragSource::Revoke() {
  ++generation_;
  if (active_) {
    revoked_through_ = std::max(revoked_through_, active_id_);
    active_->Revoke();
    PostMessageW(window_, WM_MOUSEMOVE, 0, 0);
  }
}

int64_t FileDragSource::Prepare() const {
  return stopped_ || suspended_ || active_ || !IsWindowVisible(window_) ? -1 : generation_;
}

void FileDragSource::SetSuspended(bool suspended) {
  suspended_ = suspended;
  if (suspended) Revoke();
}

void FileDragSource::Stop() {
  stopped_ = true;
  Revoke();
}
