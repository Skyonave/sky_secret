#ifndef RUNNER_FILE_DROP_TARGET_H_
#define RUNNER_FILE_DROP_TARGET_H_

#include <windows.h>
#include <oleidl.h>
#include <functional>
#include <string>
#include <vector>

class FileDropTarget final : public IDropTarget {
 public:
  using Callback = std::function<void(const char*, const std::vector<std::string>&)>;
  FileDropTarget(HWND window, Callback callback);
  bool ready() const { return registered_; }
  POINT position() const { return position_; }
  void Stop();
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** object) override;
  ULONG STDMETHODCALLTYPE AddRef() override;
  ULONG STDMETHODCALLTYPE Release() override;
  HRESULT STDMETHODCALLTYPE DragEnter(IDataObject*, DWORD, POINTL, DWORD*) override;
  HRESULT STDMETHODCALLTYPE DragOver(DWORD, POINTL, DWORD*) override;
  HRESULT STDMETHODCALLTYPE DragLeave() override;
  HRESULT STDMETHODCALLTYPE Drop(IDataObject*, DWORD, POINTL, DWORD*) override;

 private:
  ~FileDropTarget();
  bool CanCopy(DWORD keys, DWORD effects) const;
  HWND window_;
  Callback callback_;
  LONG references_ = 1;
  bool ole_ = false;
  bool registered_ = false;
  bool files_ = false;
  POINT position_{};
};
#endif
