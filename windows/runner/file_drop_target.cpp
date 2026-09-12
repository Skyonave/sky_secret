#include "file_drop_target.h"

#include <ole2.h>
#include <shellapi.h>
#include <utility>

namespace {
FORMATETC FileFormat() {
  return {CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
}
}

FileDropTarget::FileDropTarget(HWND window, Callback callback)
    : window_(window), callback_(std::move(callback)) {
  ole_ = SUCCEEDED(OleInitialize(nullptr));
  if (ole_) registered_ = SUCCEEDED(RegisterDragDrop(window_, this));
}

void FileDropTarget::Stop() {
  if (registered_) {
    registered_ = false;
    RevokeDragDrop(window_);
  }
  callback_ = nullptr;
}

FileDropTarget::~FileDropTarget() {
  if (ole_) OleUninitialize();
}

HRESULT STDMETHODCALLTYPE FileDropTarget::QueryInterface(REFIID iid, void** object) {
  if (!object) return E_POINTER;
  *object = nullptr;
  if (iid != IID_IUnknown && iid != IID_IDropTarget) return E_NOINTERFACE;
  *object = static_cast<IDropTarget*>(this);
  AddRef();
  return S_OK;
}

ULONG STDMETHODCALLTYPE FileDropTarget::AddRef() { return InterlockedIncrement(&references_); }
ULONG STDMETHODCALLTYPE FileDropTarget::Release() {
  const auto remaining = InterlockedDecrement(&references_);
  if (!remaining) delete this;
  return remaining;
}

bool FileDropTarget::CanCopy(DWORD keys, DWORD effects) const {
  return files_ && (effects & DROPEFFECT_COPY) && !(keys & (MK_RBUTTON | MK_MBUTTON));
}

HRESULT STDMETHODCALLTYPE FileDropTarget::DragEnter(IDataObject* data, DWORD keys, POINTL point, DWORD* effect) {
  position_ = {point.x, point.y};
  ScreenToClient(window_, &position_);
  if (!effect) return E_INVALIDARG;
  auto format = FileFormat();
  files_ = data && data->QueryGetData(&format) == S_OK;
  *effect = CanCopy(keys, *effect) ? DROPEFFECT_COPY : DROPEFFECT_NONE;
  if (*effect && callback_) callback_("entered", {});
  return S_OK;
}

HRESULT STDMETHODCALLTYPE FileDropTarget::DragOver(DWORD keys, POINTL point, DWORD* effect) {
  position_ = {point.x, point.y};
  ScreenToClient(window_, &position_);
  if (!effect) return E_INVALIDARG;
  *effect = CanCopy(keys, *effect) ? DROPEFFECT_COPY : DROPEFFECT_NONE;
  if (callback_) callback_(*effect ? "entered" : "exited", {});
  return S_OK;
}

HRESULT STDMETHODCALLTYPE FileDropTarget::DragLeave() {
  files_ = false;
  if (callback_) callback_("exited", {});
  return S_OK;
}

HRESULT STDMETHODCALLTYPE FileDropTarget::Drop(IDataObject* data, DWORD keys, POINTL point, DWORD* effect) {
  position_ = {point.x, point.y};
  ScreenToClient(window_, &position_);
  if (!effect) return E_INVALIDARG;
  const bool allowed = CanCopy(keys, *effect);
  *effect = DROPEFFECT_NONE;
  files_ = false;
  if (!allowed || !data) {
    if (callback_) callback_("exited", {});
    return S_OK;
  }
  auto format = FileFormat();
  STGMEDIUM medium{};
  if (FAILED(data->GetData(&format, &medium))) {
    if (callback_) callback_("rejected", {});
    return S_OK;
  }
  std::vector<std::string> paths;
  bool valid = medium.tymed == TYMED_HGLOBAL && medium.hGlobal;
  try {
    const auto drop = reinterpret_cast<HDROP>(medium.hGlobal);
    const UINT count = valid ? DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0) : 0;
    valid = count > 0 && count <= 100000;
    size_t total = 0;
    for (UINT i = 0; valid && i < count; ++i) {
      const UINT length = DragQueryFileW(drop, i, nullptr, 0);
      total += length;
      if (!length || length > 32767 || total > 8 * 1024 * 1024) { valid = false; break; }
      std::vector<wchar_t> path(static_cast<size_t>(length) + 1);
      if (DragQueryFileW(drop, i, path.data(), length + 1) != length) { valid = false; break; }
      const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, path.data(), length, nullptr, 0, nullptr, nullptr);
      if (!size) { valid = false; break; }
      std::string utf8(size, '\0');
      if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, path.data(), length, utf8.data(), size, nullptr, nullptr)) { valid = false; break; }
      paths.push_back(std::move(utf8));
    }
  } catch (...) {
    valid = false;
  }
  ReleaseStgMedium(&medium);
  if (callback_) callback_(valid ? "files" : "rejected", paths);

  if (valid) *effect = DROPEFFECT_COPY;
  return S_OK;
}
