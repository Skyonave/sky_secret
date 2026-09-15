#include "virtual_file_data.h"

#include <algorithm>
#include <cwctype>
#include <limits>
#include <new>
#include <shlobj.h>
#include <shlwapi.h>
#include <wincrypt.h>

bool ValidVirtualFileName(const std::wstring& name) {
  if (name.empty() || name.size() > 240 || name.back() == L'.' || name.back() == L' ') return false;
  for (const auto value : name) {
    if (value < 32 || std::wstring(L"<>:\"/\\|?*").find(value) != std::wstring::npos) return false;
  }
  auto stem = name.substr(0, name.find(L'.'));
  std::transform(stem.begin(), stem.end(), stem.begin(), [](wchar_t c) { return static_cast<wchar_t>(towupper(c)); });
  if (stem == L"CON" || stem == L"PRN" || stem == L"AUX" || stem == L"NUL") return false;
  if (stem.size() == 4 && (stem.substr(0, 3) == L"COM" || stem.substr(0, 3) == L"LPT")) {
    const auto digit = stem[3];
    if ((digit >= L'0' && digit <= L'9') || digit == 0xB9 || digit == 0xB2 || digit == 0xB3) return false;
  }
  return true;
}

VirtualFilePayload::VirtualFilePayload(std::wstring file_name, size_t file_size, std::vector<uint8_t> protected_bytes)
    : name(std::move(file_name)), size(file_size), bytes_(std::move(protected_bytes)) {}

VirtualFilePayload::~VirtualFilePayload() { Revoke(); }

bool VirtualFilePayload::valid() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return !revoked_ && ValidVirtualFileName(name) && size <= kMaxSize && bytes_.size() == ((size + 15) / 16) * 16;
}

bool VirtualFilePayload::available() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return !revoked_;
}

void VirtualFilePayload::AuthorizeDrop() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!revoked_) dropping_ = true;
}

void VirtualFilePayload::Revoke() {
  std::lock_guard<std::mutex> lock(mutex_);
  revoked_ = true;
  dropping_ = false;
  if (!bytes_.empty()) SecureZeroMemory(bytes_.data(), bytes_.size());
  bytes_.clear();
}

HRESULT VirtualFilePayload::Read(size_t offset, void* destination, ULONG count, ULONG* read) {
  if (read) *read = 0;
  if (!destination && count) return STG_E_INVALIDPOINTER;
  std::lock_guard<std::mutex> lock(mutex_);
  if (revoked_ || !dropping_) return STG_E_ACCESSDENIED;
  if (offset >= size || count == 0) return count == 0 ? S_OK : S_FALSE;
  const auto requested = std::min<size_t>(count, size - offset);
  auto* scratch = static_cast<uint8_t*>(VirtualAlloc(nullptr, kChunkSize, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE));
  if (!scratch) return E_OUTOFMEMORY;
  const bool locked = VirtualLock(scratch, kChunkSize) != FALSE;
  HRESULT result = locked ? S_OK : E_ACCESSDENIED;
  size_t copied = 0;
  while (SUCCEEDED(result) && copied < requested) {
    const auto position = offset + copied;
    const auto start = (position / kChunkSize) * kChunkSize;
    const auto length = std::min(kChunkSize, bytes_.size() - start);
    memcpy(scratch, bytes_.data() + start, length);
    if (!CryptUnprotectMemory(scratch, static_cast<DWORD>(length), CRYPTPROTECTMEMORY_SAME_PROCESS)) {
      result = E_ACCESSDENIED;
      break;
    }
    const auto within = position - start;
    const auto amount = std::min(requested - copied, length - within);
    memcpy(static_cast<uint8_t*>(destination) + copied, scratch + within, amount);
    SecureZeroMemory(scratch, kChunkSize);
    copied += amount;
  }
  SecureZeroMemory(scratch, kChunkSize);
  if (locked) VirtualUnlock(scratch, kChunkSize);
  VirtualFree(scratch, 0, MEM_RELEASE);
  if (FAILED(result)) {
    if (copied) SecureZeroMemory(destination, copied);
    return result;
  }
  if (read) *read = static_cast<ULONG>(copied);
  return copied == count ? S_OK : S_FALSE;
}

namespace {
class VirtualFileStream final : public IStream {
 public:
  explicit VirtualFileStream(std::shared_ptr<VirtualFilePayload> payload, ULONGLONG position = 0)
      : payload_(std::move(payload)), position_(position) {}

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** result) override {
    if (!result) return E_POINTER;
    *result = nullptr;
    if (iid != IID_IUnknown && iid != IID_ISequentialStream && iid != IID_IStream) return E_NOINTERFACE;
    *result = static_cast<IStream*>(this);
    AddRef();
    return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&references_); }
  ULONG STDMETHODCALLTYPE Release() override {
    const auto remaining = InterlockedDecrement(&references_);
    if (!remaining) delete this;
    return remaining;
  }
  HRESULT STDMETHODCALLTYPE Read(void* destination, ULONG count, ULONG* read) override {
    ULONG copied = 0;
    const auto result = payload_->Read(static_cast<size_t>(position_), destination, count, &copied);
    position_ += copied;
    if (read) *read = copied;
    return result;
  }
  HRESULT STDMETHODCALLTYPE Write(const void*, ULONG, ULONG* written) override {
    if (written) *written = 0;
    return STG_E_ACCESSDENIED;
  }
  HRESULT STDMETHODCALLTYPE Seek(LARGE_INTEGER move, DWORD origin, ULARGE_INTEGER* position) override {
    if (!payload_->available()) return STG_E_ACCESSDENIED;
    ULONGLONG base = 0;
    if (origin == STREAM_SEEK_CUR) base = position_;
    else if (origin == STREAM_SEEK_END) base = payload_->size;
    else if (origin != STREAM_SEEK_SET) return STG_E_INVALIDFUNCTION;
    if (base > static_cast<ULONGLONG>(std::numeric_limits<LONGLONG>::max())) return STG_E_INVALIDFUNCTION;
    const auto signed_base = static_cast<LONGLONG>(base);
    if ((move.QuadPart < 0 && move.QuadPart < -signed_base) ||
        (move.QuadPart > 0 && signed_base > std::numeric_limits<LONGLONG>::max() - move.QuadPart)) {
      return STG_E_INVALIDFUNCTION;
    }
    position_ = static_cast<ULONGLONG>(signed_base + move.QuadPart);
    if (position) position->QuadPart = position_;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE SetSize(ULARGE_INTEGER) override { return STG_E_ACCESSDENIED; }
  HRESULT STDMETHODCALLTYPE CopyTo(IStream* target, ULARGE_INTEGER count, ULARGE_INTEGER* read,
                                   ULARGE_INTEGER* written) override {
    if (read) read->QuadPart = 0;
    if (written) written->QuadPart = 0;
    if (!target || target == this) return STG_E_INVALIDPOINTER;
    auto* buffer = static_cast<uint8_t*>(VirtualAlloc(nullptr, VirtualFilePayload::kChunkSize,
                                                    MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE));
    if (!buffer) return E_OUTOFMEMORY;
    const bool locked = VirtualLock(buffer, VirtualFilePayload::kChunkSize) != FALSE;
    HRESULT result = locked ? S_OK : E_ACCESSDENIED;
    ULONGLONG total_read = 0;
    ULONGLONG total_written = 0;
    while (SUCCEEDED(result) && total_read < count.QuadPart) {
      ULONG got = 0;
      result = Read(buffer, static_cast<ULONG>(std::min<ULONGLONG>(VirtualFilePayload::kChunkSize,
                                                                count.QuadPart - total_read)), &got);
      total_read += got;
      if (FAILED(result) || !got) break;
      ULONG sent = 0;
      const auto write_result = target->Write(buffer, got, &sent);
      SecureZeroMemory(buffer, VirtualFilePayload::kChunkSize);
      total_written += sent;
      if (FAILED(write_result)) { result = write_result; break; }
      if (sent != got) { result = STG_E_MEDIUMFULL; break; }
      if (result == S_FALSE) break;
    }
    SecureZeroMemory(buffer, VirtualFilePayload::kChunkSize);
    if (locked) VirtualUnlock(buffer, VirtualFilePayload::kChunkSize);
    VirtualFree(buffer, 0, MEM_RELEASE);
    if (read) read->QuadPart = total_read;
    if (written) written->QuadPart = total_written;
    return result;
  }
  HRESULT STDMETHODCALLTYPE Commit(DWORD) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE Revert() override { return STG_E_INVALIDFUNCTION; }
  HRESULT STDMETHODCALLTYPE LockRegion(ULARGE_INTEGER, ULARGE_INTEGER, DWORD) override { return STG_E_INVALIDFUNCTION; }
  HRESULT STDMETHODCALLTYPE UnlockRegion(ULARGE_INTEGER, ULARGE_INTEGER, DWORD) override { return STG_E_INVALIDFUNCTION; }
  HRESULT STDMETHODCALLTYPE Stat(STATSTG* stat, DWORD flags) override {
    if (!stat) return STG_E_INVALIDPOINTER;
    *stat = {};
    if (!payload_->available()) return STG_E_ACCESSDENIED;
    stat->type = STGTY_STREAM;
    stat->cbSize.QuadPart = payload_->size;
    stat->grfMode = STGM_READ;
    if (!(flags & STATFLAG_NONAME)) {
      const auto bytes = (payload_->name.size() + 1) * sizeof(wchar_t);
      stat->pwcsName = static_cast<LPOLESTR>(CoTaskMemAlloc(bytes));
      if (!stat->pwcsName) return E_OUTOFMEMORY;
      memcpy(stat->pwcsName, payload_->name.c_str(), bytes);
    }
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE Clone(IStream** result) override {
    if (!result) return E_POINTER;
    *result = nullptr;
    if (!payload_->available()) return STG_E_ACCESSDENIED;
    *result = new (std::nothrow) VirtualFileStream(payload_, position_);
    return *result ? S_OK : E_OUTOFMEMORY;
  }

 private:
  LONG references_ = 1;
  std::shared_ptr<VirtualFilePayload> payload_;
  ULONGLONG position_ = 0;
};

class VirtualFileData final : public IDataObject {
 public:
  explicit VirtualFileData(std::shared_ptr<VirtualFilePayload> payload) : payload_(std::move(payload)) {
    descriptor_ = static_cast<CLIPFORMAT>(RegisterClipboardFormatW(CFSTR_FILEDESCRIPTORW));
    contents_ = static_cast<CLIPFORMAT>(RegisterClipboardFormatW(CFSTR_FILECONTENTS));
    preferred_ = static_cast<CLIPFORMAT>(RegisterClipboardFormatW(CFSTR_PREFERREDDROPEFFECT));
  }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** result) override {
    if (!result) return E_POINTER;
    *result = nullptr;
    if (iid != IID_IUnknown && iid != IID_IDataObject) return E_NOINTERFACE;
    *result = static_cast<IDataObject*>(this);
    AddRef();
    return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&references_); }
  ULONG STDMETHODCALLTYPE Release() override {
    const auto remaining = InterlockedDecrement(&references_);
    if (!remaining) delete this;
    return remaining;
  }
  HRESULT STDMETHODCALLTYPE QueryGetData(FORMATETC* format) override {
    if (!format) return E_POINTER;
    if (!payload_->available()) return E_ACCESSDENIED;
    if (format->dwAspect != DVASPECT_CONTENT) return DV_E_DVASPECT;
    if (format->ptd) return DV_E_DVTARGETDEVICE;
    if (format->cfFormat == contents_) {
      if (format->lindex != 0) return DV_E_LINDEX;
      return format->tymed & TYMED_ISTREAM ? S_OK : DV_E_TYMED;
    }
    if (format->cfFormat != descriptor_ && format->cfFormat != preferred_) return DV_E_FORMATETC;
    if (format->lindex != -1) return DV_E_LINDEX;
    return format->tymed & TYMED_HGLOBAL ? S_OK : DV_E_TYMED;
  }
  HRESULT STDMETHODCALLTYPE GetData(FORMATETC* format, STGMEDIUM* medium) override {
    if (!medium) return E_POINTER;
    *medium = {};
    const auto accepted = QueryGetData(format);
    if (FAILED(accepted)) return accepted;
    if (format->cfFormat == contents_) {
      medium->pstm = new (std::nothrow) VirtualFileStream(payload_);
      if (!medium->pstm) return E_OUTOFMEMORY;
      medium->tymed = TYMED_ISTREAM;
      return S_OK;
    }
    const auto size = format->cfFormat == descriptor_ ? sizeof(FILEGROUPDESCRIPTORW) : sizeof(DWORD);
    const auto memory = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, size);
    if (!memory) return E_OUTOFMEMORY;
    auto* data = GlobalLock(memory);
    if (!data) { GlobalFree(memory); return E_OUTOFMEMORY; }
    if (format->cfFormat == descriptor_) {
      auto* group = static_cast<FILEGROUPDESCRIPTORW*>(data);
      group->cItems = 1;
      auto& descriptor = group->fgd[0];
      descriptor.dwFlags = static_cast<DWORD>(FD_ATTRIBUTES | FD_FILESIZE | FD_UNICODE | FD_PROGRESSUI);
      descriptor.dwFileAttributes = FILE_ATTRIBUTE_NORMAL;
      descriptor.nFileSizeLow = static_cast<DWORD>(payload_->size);
      memcpy(descriptor.cFileName, payload_->name.c_str(), (payload_->name.size() + 1) * sizeof(wchar_t));
    } else {
      *static_cast<DWORD*>(data) = DROPEFFECT_COPY;
    }
    GlobalUnlock(memory);
    medium->tymed = TYMED_HGLOBAL;
    medium->hGlobal = memory;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetDataHere(FORMATETC*, STGMEDIUM*) override { return DATA_E_FORMATETC; }
  HRESULT STDMETHODCALLTYPE GetCanonicalFormatEtc(FORMATETC*, FORMATETC* result) override {
    if (!result) return E_POINTER;
    result->ptd = nullptr;
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE SetData(FORMATETC*, STGMEDIUM*, BOOL) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE EnumFormatEtc(DWORD direction, IEnumFORMATETC** result) override {
    if (!result) return E_POINTER;
    *result = nullptr;
    if (direction != DATADIR_GET) return E_NOTIMPL;
    if (!payload_->available()) return E_ACCESSDENIED;
    FORMATETC formats[] = {
      {descriptor_, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL},
      {contents_, nullptr, DVASPECT_CONTENT, 0, TYMED_ISTREAM},
      {preferred_, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL},
    };
    return SHCreateStdEnumFmtEtc(ARRAYSIZE(formats), formats, result);
  }
  HRESULT STDMETHODCALLTYPE DAdvise(FORMATETC*, DWORD, IAdviseSink*, DWORD*) override { return OLE_E_ADVISENOTSUPPORTED; }
  HRESULT STDMETHODCALLTYPE DUnadvise(DWORD) override { return OLE_E_ADVISENOTSUPPORTED; }
  HRESULT STDMETHODCALLTYPE EnumDAdvise(IEnumSTATDATA**) override { return OLE_E_ADVISENOTSUPPORTED; }

 private:
  LONG references_ = 1;
  std::shared_ptr<VirtualFilePayload> payload_;
  CLIPFORMAT descriptor_ = 0;
  CLIPFORMAT contents_ = 0;
  CLIPFORMAT preferred_ = 0;
};
}

HRESULT CreateVirtualFileData(const std::shared_ptr<VirtualFilePayload>& payload, IDataObject** result) {
  if (!result) return E_POINTER;
  *result = nullptr;
  if (!payload || !payload->valid()) return E_INVALIDARG;
  *result = new (std::nothrow) VirtualFileData(payload);
  return *result ? S_OK : E_OUTOFMEMORY;
}
