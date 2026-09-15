#ifndef RUNNER_FILE_DRAG_SOURCE_H_
#define RUNNER_FILE_DRAG_SOURCE_H_

#include <windows.h>
#include <flutter/encodable_value.h>
#include <flutter/method_result.h>
#include <cstdint>
#include <memory>

#include "virtual_file_data.h"

class FileDragSource {
 public:
  explicit FileDragSource(HWND window) : window_(window) {}
  void Start(const flutter::EncodableValue* arguments, flutter::MethodResult<flutter::EncodableValue>* result);
  void Cancel(int64_t through);
  void Revoke();
  void Stop();
  int64_t Prepare() const;
  void SetSuspended(bool suspended);
  bool stopped() const { return stopped_; }

 private:
  HWND window_;
  int64_t revoked_through_ = 0;
  int64_t active_id_ = 0;
  bool stopped_ = false;
  bool suspended_ = false;
  int64_t generation_ = 1;
  std::shared_ptr<VirtualFilePayload> active_;
};

#endif
