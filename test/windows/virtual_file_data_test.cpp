#include "../../windows/runner/virtual_file_data.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <ole2.h>
#include <shlobj.h>
#include <wincrypt.h>

namespace {
void Check(bool condition, const char* description) {
  if (!condition) {
    std::fprintf(stderr, "FAILED: %s\n", description);
    std::exit(1);
  }
}

std::vector<uint8_t> Synthetic(size_t length) {
  std::vector<uint8_t> result(length);
  for (size_t index = 0; index < length; ++index) result[index] = static_cast<uint8_t>(index % 251);
  return result;
}

std::vector<uint8_t> Protect(const std::vector<uint8_t>& plain) {
  auto encrypted = plain;
  encrypted.resize(((plain.size() + 15) / 16) * 16);
  for (size_t offset = 0; offset < encrypted.size(); offset += VirtualFilePayload::kChunkSize) {
    const auto count = std::min(VirtualFilePayload::kChunkSize, encrypted.size() - offset);
    Check(CryptProtectMemory(encrypted.data() + offset, static_cast<DWORD>(count), CRYPTPROTECTMEMORY_SAME_PROCESS) != FALSE,
          "protect synthetic block");
  }
  return encrypted;
}

FORMATETC Format(const wchar_t* name, LONG index, DWORD medium) {
  return {static_cast<CLIPFORMAT>(RegisterClipboardFormatW(name)), nullptr, DVASPECT_CONTENT, index, medium};
}

IStream* Contents(IDataObject* object) {
  auto format = Format(CFSTR_FILECONTENTS, 0, TYMED_ISTREAM);
  STGMEDIUM medium{};
  Check(object->GetData(&format, &medium) == S_OK, "file stream offered");
  Check(medium.tymed == TYMED_ISTREAM && medium.pUnkForRelease == nullptr, "stream medium ownership");
  return medium.pstm;
}
}

int main() {
  Check(SUCCEEDED(OleInitialize(nullptr)), "initialize COM without windows");
  for (const auto* name : {L"", L"../a", L"C:\\a.txt", L"file.", L"file ", L"CON.txt", L"lpt1.log", L"a:b", L"a?b"}) {
    Check(!ValidVirtualFileName(name), "unsafe filename rejected");
  }
  const std::wstring filename = L"\x0444\x0430\x0439\x043b \xD83D\xDD12.txt";
  Check(ValidVirtualFileName(filename), "Unicode filename accepted");
  auto invalid = std::make_shared<VirtualFilePayload>(L"file.txt", 17, std::vector<uint8_t>(16));
  IDataObject* bad = nullptr;
  Check(CreateVirtualFileData(invalid, &bad) == E_INVALIDARG && !bad, "invalid protected length rejected");
  auto too_large = std::make_shared<VirtualFilePayload>(L"file.txt", VirtualFilePayload::kMaxSize + 1, std::vector<uint8_t>{});
  Check(!too_large->valid(), "oversize transfer rejected");

  const auto plain = Synthetic(33001);
  auto payload = std::make_shared<VirtualFilePayload>(filename, plain.size(), Protect(plain));
  IDataObject* object = nullptr;
  Check(CreateVirtualFileData(payload, &object) == S_OK, "create virtual file");
  auto descriptor = Format(CFSTR_FILEDESCRIPTORW, -1, TYMED_HGLOBAL);
  STGMEDIUM medium{};
  Check(object->GetData(&descriptor, &medium) == S_OK, "descriptor available before drop");
  auto* group = static_cast<FILEGROUPDESCRIPTORW*>(GlobalLock(medium.hGlobal));
  Check(group && group->cItems == 1 && group->fgd[0].nFileSizeLow == plain.size(), "descriptor exact size");
  Check(group->fgd[0].cFileName == filename, "Unicode name and extension retained");
  GlobalUnlock(medium.hGlobal);
  ReleaseStgMedium(&medium);
  auto preferred = Format(CFSTR_PREFERREDDROPEFFECT, -1, TYMED_HGLOBAL);
  Check(object->GetData(&preferred, &medium) == S_OK, "preferred effect available");
  const auto* effect = static_cast<const DWORD*>(GlobalLock(medium.hGlobal));
  Check(effect && *effect == DROPEFFECT_COPY, "copy only");
  GlobalUnlock(medium.hGlobal);
  ReleaseStgMedium(&medium);

  IEnumFORMATETC* enumeration = nullptr;
  Check(object->EnumFormatEtc(DATADIR_GET, &enumeration) == S_OK, "enumerate formats");
  FORMATETC formats[4]{};
  ULONG fetched = 0;
  Check(enumeration->Next(4, formats, &fetched) == S_FALSE && fetched == 3, "three virtual formats only");
  for (ULONG index = 0; index < fetched; ++index) Check(formats[index].cfFormat != CF_HDROP, "no plaintext filesystem path");
  enumeration->Release();
  auto wrong_index = Format(CFSTR_FILECONTENTS, 1, TYMED_ISTREAM);
  Check(object->QueryGetData(&wrong_index) == DV_E_LINDEX, "invalid content index rejected");
  auto wrong_medium = Format(CFSTR_FILECONTENTS, 0, TYMED_HGLOBAL);
  Check(object->QueryGetData(&wrong_medium) == DV_E_TYMED, "no independent plaintext global memory");

  auto* stream = Contents(object);
  uint8_t output[64]{};
  ULONG read = 99;
  Check(stream->Read(output, sizeof(output), &read) == STG_E_ACCESSDENIED && read == 0, "no reading on hover");
  payload->AuthorizeDrop();
  LARGE_INTEGER offset{};
  offset.QuadPart = 16379;
  Check(stream->Seek(offset, STREAM_SEEK_SET, nullptr) == S_OK, "seek before chunk edge");
  Check(stream->Read(output, sizeof(output), &read) == S_OK && read == sizeof(output), "read across protected chunk edge");
  Check(std::equal(output, output + sizeof(output), plain.begin() + 16379), "decrypted chunk bytes match");
  IStream* clone = nullptr;
  Check(stream->Clone(&clone) == S_OK, "clone stream");
  offset.QuadPart = -1;
  Check(stream->Seek(offset, STREAM_SEEK_SET, nullptr) == STG_E_INVALIDFUNCTION, "negative seek rejected");
  offset.QuadPart = 0;
  Check(stream->Seek(offset, STREAM_SEEK_SET, nullptr) == S_OK, "rewind source");
  Check(clone->Read(output, 1, &read) == S_OK && output[0] == plain[16379 + 64], "clone has independent position");
  IStream* target = nullptr;
  Check(CreateStreamOnHGlobal(nullptr, TRUE, &target) == S_OK, "create synthetic memory destination");
  ULARGE_INTEGER amount{};
  amount.QuadPart = plain.size() + 10;
  ULARGE_INTEGER copied{}, written{};
  Check(stream->CopyTo(target, amount, &copied, &written) == S_FALSE, "copy reaches EOF");
  Check(copied.QuadPart == plain.size() && written.QuadPart == plain.size(), "copy reports exact totals");
  Check(target->Seek(offset, STREAM_SEEK_SET, nullptr) == S_OK, "rewind target");
  std::vector<uint8_t> received(plain.size());
  Check(target->Read(received.data(), static_cast<ULONG>(received.size()), &read) == S_OK && received == plain,
        "full binary contents preserved");
  target->Release();
  payload->Revoke();
  payload->AuthorizeDrop();
  Check(clone->Read(output, 1, &read) == STG_E_ACCESSDENIED && read == 0, "retained clone revoked permanently");
  Check(object->GetData(&descriptor, &medium) == E_ACCESSDENIED, "metadata revoked after transfer");
  clone->Release();
  stream->Release();
  object->Release();

  auto empty = std::make_shared<VirtualFilePayload>(L"empty.txt", 0, std::vector<uint8_t>{});
  Check(CreateVirtualFileData(empty, &object) == S_OK, "empty file supported");
  stream = Contents(object);
  empty->AuthorizeDrop();
  Check(stream->Read(output, 1, &read) == S_FALSE && read == 0, "empty file EOF");
  STATSTG stat{};
  Check(stream->Stat(&stat, STATFLAG_NONAME) == S_OK && stat.cbSize.QuadPart == 0, "empty stream size");
  stream->Release();
  object->Release();
  OleUninitialize();
  std::puts("Virtual file native unit checks passed.");
  return 0;
}
