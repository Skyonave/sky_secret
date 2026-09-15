#ifndef RUNNER_VIRTUAL_FILE_DATA_H_
#define RUNNER_VIRTUAL_FILE_DATA_H_

#include <windows.h>
#include <objidl.h>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

class VirtualFilePayload {
 public:
  static constexpr size_t kChunkSize = 16 * 1024;
  static constexpr size_t kMaxSize = 20 * 1024 * 1024;
  VirtualFilePayload(std::wstring name, size_t size, std::vector<uint8_t> protected_bytes);
  ~VirtualFilePayload();
  bool valid() const;
  bool available() const;
  void AuthorizeDrop();
  void Revoke();
  HRESULT Read(size_t offset, void* destination, ULONG count, ULONG* read);
  const std::wstring name;
  const size_t size;

 private:
  mutable std::mutex mutex_;
  std::vector<uint8_t> bytes_;
  bool revoked_ = false;
  bool dropping_ = false;
};

bool ValidVirtualFileName(const std::wstring& name);
HRESULT CreateVirtualFileData(const std::shared_ptr<VirtualFilePayload>& payload, IDataObject** result);

#endif
