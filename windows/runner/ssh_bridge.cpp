#include "ssh_bridge.h"

#include <windows.h>
#include <sddl.h>
#include <tlhelp32.h>
#include <bcrypt.h>
#include <shellapi.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <algorithm>
#include <map>
#include <string>
#include <vector>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using List = flutter::EncodableList;
constexpr DWORD kMaxMessage = 16384;

std::wstring Wide(const std::string& value) {
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                                     static_cast<int>(value.size()), nullptr, 0);
  std::wstring result(size, 0);
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                     static_cast<int>(value.size()), result.data(), size);
  return result;
}

std::string Utf8(const std::wstring& value) {
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
      static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  std::string result(size, 0);
  WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                     result.data(), size, nullptr, nullptr);
  return result;
}

std::wstring Environment(const wchar_t* name) {
  const DWORD size = GetEnvironmentVariableW(name, nullptr, 0);
  if (size == 0 || size > 32768) return {};
  std::wstring result(size, 0);
  GetEnvironmentVariableW(name, result.data(), size);
  result.resize(size - 1);
  return result;
}

std::wstring ImagePath(HANDLE process) {
  std::wstring result(32768, 0);
  DWORD size = static_cast<DWORD>(result.size());
  if (!QueryFullProcessImageNameW(process, 0, result.data(), &size)) return {};
  result.resize(size);
  return result;
}

DWORD ParentPid(DWORD pid) {
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return 0;
  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  DWORD parent = 0;
  if (Process32FirstW(snapshot, &entry)) {
    do {
      if (entry.th32ProcessID == pid) {
        parent = entry.th32ParentProcessID;
        break;
      }
    } while (Process32NextW(snapshot, &entry));
  }
  CloseHandle(snapshot);
  return parent;
}

bool HasImage(DWORD pid, const std::wstring& expected) {
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, pid);
  if (!process) return false;
  const bool valid = WaitForSingleObject(process, 0) == WAIT_TIMEOUT &&
      _wcsicmp(ImagePath(process).c_str(), expected.c_str()) == 0;
  CloseHandle(process);
  return valid;
}

std::string StringArg(const Map& args, const char* key) {
  const auto found = args.find(Value(key));
  if (found == args.end()) return {};
  const auto* value = std::get_if<std::string>(&found->second);
  return value ? *value : std::string();
}

bool SafeToken(const std::string& value, const std::string& extra, size_t limit) {
  if (value.empty() || value.size() > limit || value[0] == '-') return false;
  for (const unsigned char c : value) {
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') || extra.find(c) != std::string::npos) continue;
    return false;
  }
  return true;
}

HANDLE PrivatePipe(const std::wstring& name) {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return INVALID_HANDLE_VALUE;
  DWORD size = 0;
  GetTokenInformation(token, TokenUser, nullptr, 0, &size);
  std::vector<BYTE> info(size);
  const bool queried = GetTokenInformation(token, TokenUser, info.data(), size, &size) != FALSE;
  CloseHandle(token);
  if (!queried) return INVALID_HANDLE_VALUE;
  LPWSTR sid = nullptr;
  if (!ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(info.data())->User.Sid, &sid)) {
    return INVALID_HANDLE_VALUE;
  }
  const std::wstring sddl = L"D:P(A;;GA;;;" + std::wstring(sid) + L")";
  LocalFree(sid);
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
          sddl.c_str(), SDDL_REVISION_1, &descriptor, nullptr)) return INVALID_HANDLE_VALUE;
  SECURITY_ATTRIBUTES attributes{sizeof(SECURITY_ATTRIBUTES), descriptor, FALSE};
  HANDLE pipe = CreateNamedPipeW(name.c_str(), PIPE_ACCESS_DUPLEX | FILE_FLAG_FIRST_PIPE_INSTANCE,
      PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_NOWAIT | PIPE_REJECT_REMOTE_CLIENTS,
      1, kMaxMessage, kMaxMessage, 0, &attributes);
  LocalFree(descriptor);
  return pipe;
}

std::vector<wchar_t> ChildEnvironment(const std::wstring& pipe, const std::wstring& app) {
  std::vector<std::wstring> entries;
  LPWCH environment = GetEnvironmentStringsW();
  if (environment) {
    for (const wchar_t* p = environment; *p; p += wcslen(p) + 1) {
      const std::wstring entry(p);
      if (_wcsnicmp(p, L"SSH_ASKPASS", 11) == 0 ||
          _wcsnicmp(p, L"SKYSECRET_SSH_PIPE=", 18) == 0) continue;
      entries.push_back(entry);
    }
    FreeEnvironmentStringsW(environment);
  }
  entries.push_back(L"SSH_ASKPASS=" + app);
  entries.push_back(L"SSH_ASKPASS_REQUIRE=force");
  entries.push_back(L"SKYSECRET_SSH_PIPE=" + pipe);
  std::sort(entries.begin(), entries.end(), [](const auto& a, const auto& b) {
    return _wcsicmp(a.c_str(), b.c_str()) < 0;
  });
  std::vector<wchar_t> result;
  for (const auto& entry : entries) {
    result.insert(result.end(), entry.begin(), entry.end());
    result.push_back(0);
  }
  result.push_back(0);
  return result;
}

struct Session {
  std::string key;
  std::string password_prompt;
  std::wstring ssh_path;
  std::wstring app_path;
  HANDLE process = nullptr;
  DWORD pid = 0;
  HANDLE pipe = INVALID_HANDLE_VALUE;
  ULONGLONG deadline = 0;
  bool connected = false;
  bool pending = false;
  bool replied = false;
  bool password_issued = false;
  bool confirmation_issued = false;
  std::string request;

  void Revoke() {
    if (pipe != INVALID_HANDLE_VALUE) CloseHandle(pipe);
    pipe = INVALID_HANDLE_VALUE;
    pending = false;
  }
  ~Session() {
    Revoke();
    if (process) CloseHandle(process);
  }
  bool OwnClient() const {
    ULONG client = 0;
    if (!GetNamedPipeClientProcessId(pipe, &client)) return false;
    const DWORD ssh = ParentPid(client);
    return WaitForSingleObject(process, 0) == WAIT_TIMEOUT &&
        ParentPid(ssh) == pid && HasImage(ssh, ssh_path) && HasImage(client, app_path);
  }
};
}

struct SshBridge::Impl {
  std::unique_ptr<flutter::MethodChannel<Value>> channel;
  std::map<std::string, std::unique_ptr<Session>> sessions;

  std::string Start(const Map& args) {
    const auto key = StringArg(args, "key");
    const auto host = StringArg(args, "host");
    const auto user = StringArg(args, "user");
    const auto port = StringArg(args, "port");
    if (key.empty() || key.size() > 131072 || !SafeToken(host, ".-:", 253) ||
        !SafeToken(user, "_.-$", 128) || !SafeToken(port, "", 5) ||
        port.find_first_not_of("0123456789") != std::string::npos ||
        std::stoi(port) < 1 || std::stoi(port) > 65535) return "invalid";
    if (sessions.count(key)) return "active";
    if (sessions.size() >= 8) return "limit";
    wchar_t system[MAX_PATH]{};
    if (!GetSystemDirectoryW(system, MAX_PATH)) return "launch";
    const std::wstring directory(system);
    if (directory.find_first_of(L"\"%&!^\r\n") != std::wstring::npos) return "launch";
    const std::wstring ssh = directory + L"\\OpenSSH\\ssh.exe";
    if (GetFileAttributesW(ssh.c_str()) == INVALID_FILE_ATTRIBUTES) return "missing";
    BYTE random[16];
    if (BCryptGenRandom(nullptr, random, sizeof(random), BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0) return "launch";
    std::wstring pipe = L"\\\\.\\pipe\\SkySecret.Ssh.";
    for (BYTE byte : random) {
      pipe += L"0123456789abcdef"[byte >> 4];
      pipe += L"0123456789abcdef"[byte & 15];
    }
    auto session = std::make_unique<Session>();
    session->key = key;
    session->ssh_path = ssh;
    session->app_path = ImagePath(GetCurrentProcess());
    session->password_prompt = user + "@" + host + "'s password: ";
    session->pipe = PrivatePipe(pipe);
    if (session->pipe == INVALID_HANDLE_VALUE || session->app_path.empty()) return "launch";
    auto environment = ChildEnvironment(pipe, session->app_path);
    const std::wstring cmd = directory + L"\\cmd.exe";


    std::wstring command = L"\"" + cmd + L"\" /d /s /c \"\"" + ssh +
        L"\" -F NUL -o StrictHostKeyChecking=ask -o PreferredAuthentications=password"
        L" -o PubkeyAuthentication=no -o KbdInteractiveAuthentication=no"
        L" -o NumberOfPasswordPrompts=1 -o ConnectTimeout=15 -o ForwardAgent=no"
        L" -o ClearAllForwardings=yes -o PermitLocalCommand=no -p " + Wide(port) +
        L" -l " + Wide(user) + L" -- " + Wide(host) + L"\"";
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(cmd.c_str(), command.data(), nullptr, nullptr, FALSE,
                        CREATE_NEW_CONSOLE | CREATE_UNICODE_ENVIRONMENT,
                        environment.data(), directory.c_str(), &startup, &process)) return "launch";
    CloseHandle(process.hThread);
    session->process = process.hProcess;
    session->pid = process.dwProcessId;
    session->deadline = GetTickCount64() + 120000;
    sessions.emplace(key, std::move(session));
    return {};
  }

  List Poll() {
    List events;
    for (auto it = sessions.begin(); it != sessions.end();) {
      auto& s = *it->second;
      if (WaitForSingleObject(s.process, 0) == WAIT_OBJECT_0) {
        DWORD code = 1;
        GetExitCodeProcess(s.process, &code);
        events.emplace_back(Map{{Value("key"), Value(s.key)}, {Value("type"), Value("exit")},
                                {Value("ok"), Value(code == 0)}});
        it = sessions.erase(it);
        continue;
      }
      ++it;
      if (GetTickCount64() > s.deadline) s.Revoke();
      if (s.pipe == INVALID_HANDLE_VALUE || s.pending) continue;
      if (!s.connected) {
        const BOOL connected = ConnectNamedPipe(s.pipe, nullptr);
        const DWORD error = connected ? ERROR_SUCCESS : GetLastError();
        if (error == ERROR_PIPE_LISTENING) continue;
        if (!connected && error != ERROR_PIPE_CONNECTED) { s.Revoke(); continue; }
        s.connected = true;
        if (!s.OwnClient()) { s.Revoke(); continue; }
      }
      DWORD available = 0;
      if (!PeekNamedPipe(s.pipe, nullptr, 0, nullptr, &available, nullptr)) {
        if (s.replied && s.request == "password") {
          events.emplace_back(Map{{Value("key"), Value(s.key)}, {Value("type"), Value("released")}});
          s.Revoke();
          continue;
        }
        DisconnectNamedPipe(s.pipe);
        s.connected = false;
        s.replied = false;
        continue;
      }
      if (s.replied || available == 0) continue;
      if (available > kMaxMessage) { s.Revoke(); continue; }
      std::string prompt(available, 0);
      DWORD read = 0;
      if (!ReadFile(s.pipe, prompt.data(), available, &read, nullptr) || read != available) {
        s.Revoke(); continue;
      }
      std::string type;
      if (prompt == s.password_prompt && !s.password_issued) {
        type = "password";
        s.password_issued = true;
      } else if (!s.confirmation_issued && prompt.find("Are you sure you want to continue connecting") != std::string::npos &&
                 prompt.find("fingerprint") != std::string::npos) {
        type = "hostKey";
        s.confirmation_issued = true;
      } else { s.Revoke(); continue; }
      s.pending = true;
      s.request = type;
      events.emplace_back(Map{{Value("key"), Value(s.key)}, {Value("type"), Value(type)},
                              {Value("prompt"), Value(prompt)}});
    }
    return events;
  }

  void Reply(const Map& args) {
    auto found = sessions.find(StringArg(args, "key"));
    if (found == sessions.end()) return;
    auto& s = *found->second;
    if (!s.pending || s.pipe == INVALID_HANDLE_VALUE || GetTickCount64() > s.deadline) return;
    auto answer = StringArg(args, "answer");
    const bool valid = !answer.empty() && answer.size() <= 1000 &&
        answer.find_first_of(std::string("\0\r\n", 3)) == std::string::npos &&
        (s.request == "password" || answer == "yes" || answer == "no");
    if (valid && s.OwnClient()) {
      DWORD written = 0;
      if (!WriteFile(s.pipe, answer.data(), static_cast<DWORD>(answer.size()), &written, nullptr) ||
          written != answer.size()) s.Revoke();
    } else { s.Revoke(); }
    SecureZeroMemory(answer.data(), answer.size());
    s.pending = false;
    s.replied = true;
  }
};

SshBridge::SshBridge(flutter::BinaryMessenger* messenger) : impl_(std::make_unique<Impl>()) {
  impl_->channel = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "skysecret/ssh", &flutter::StandardMethodCodec::GetInstance());
  impl_->channel->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
    if (call.method_name() == "start" && args) {
      const auto error = impl_->Start(*args);
      if (error.empty()) result->Success(); else result->Error(error, "SSH start failed");
    } else if (call.method_name() == "poll") {
      result->Success(Value(impl_->Poll()));
    } else if (call.method_name() == "reply" && args) {
      impl_->Reply(*args);
      result->Success();
    } else if (call.method_name() == "revoke") {
      Revoke();
      result->Success();
    } else { result->NotImplemented(); }
  });
}

SshBridge::~SshBridge() = default;
void SshBridge::Revoke() {
  for (auto& item : impl_->sessions) item.second->Revoke();
}

bool RunSshAskpass(int* exit_code) {
  const auto name = Environment(L"SKYSECRET_SSH_PIPE");
  if (name.empty()) return false;
  *exit_code = 1;
  const std::wstring prefix = L"\\\\.\\pipe\\SkySecret.Ssh.";
  if (name.size() != prefix.size() + 32 || name.compare(0, prefix.size(), prefix) != 0 ||
      name.find_first_not_of(L"0123456789abcdef", prefix.size()) != std::wstring::npos) return true;
  int count = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &count);
  if (!argv) return true;
  const auto prompt = count == 2 ? Utf8(argv[1]) : std::string();
  LocalFree(argv);
  if (prompt.empty() || prompt.size() > kMaxMessage) return true;
  HANDLE pipe = CreateFileW(name.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                            OPEN_EXISTING, FILE_FLAG_OVERLAPPED, nullptr);
  if (pipe == INVALID_HANDLE_VALUE) return true;

  ULONG server = 0;
  if (!GetNamedPipeServerProcessId(pipe, &server) || !HasImage(server, ImagePath(GetCurrentProcess()))) {
    CloseHandle(pipe); return true;
  }
  HANDLE event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (!event) { CloseHandle(pipe); return true; }
  auto transfer = [&](bool reading, void* buffer, DWORD size, DWORD* done) {
    OVERLAPPED operation{};
    operation.hEvent = event;
    ResetEvent(event);
    BOOL ok = reading ? ReadFile(pipe, buffer, size, done, &operation) :
                        WriteFile(pipe, buffer, size, done, &operation);
    if (!ok && GetLastError() == ERROR_IO_PENDING) {
      if (WaitForSingleObject(event, 125000) == WAIT_OBJECT_0) {
        ok = GetOverlappedResult(pipe, &operation, done, FALSE);
      } else {
        CancelIoEx(pipe, &operation);
        GetOverlappedResult(pipe, &operation, done, TRUE);
        return false;
      }
    }
    return ok != FALSE;
  };
  DWORD done = 0;
  if (transfer(false, const_cast<char*>(prompt.data()), static_cast<DWORD>(prompt.size()), &done) &&
      done == prompt.size()) {
    char answer[1001]{};
    if (transfer(true, answer, 1000, &done) && done > 0) {

      HANDLE output = GetStdHandle(STD_OUTPUT_HANDLE);
      DWORD written = 0;
      if (GetFileType(output) == FILE_TYPE_PIPE && WriteFile(output, answer, done, &written, nullptr) && written == done) {
        *exit_code = 0;
      }
    }
    SecureZeroMemory(answer, sizeof(answer));
  }
  CloseHandle(event);
  CloseHandle(pipe);
  return true;
}
