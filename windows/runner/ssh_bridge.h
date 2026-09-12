#ifndef RUNNER_SSH_BRIDGE_H_
#define RUNNER_SSH_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <memory>


bool RunSshAskpass(int* exit_code);

class SshBridge {
 public:
  explicit SshBridge(flutter::BinaryMessenger* messenger);
  ~SshBridge();
  void Revoke();
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
#endif
