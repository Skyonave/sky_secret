cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "companion_window.cpp"
  "file_drop_target.cpp"
  "file_drag_source.cpp"
  "virtual_file_data.cpp"
  "main.cpp"
  "ssh_bridge.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

apply_standard_settings(${BINARY_NAME})

target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "wtsapi32.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "advapi32.lib" "bcrypt.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "ole32.lib" "shell32.lib" "uuid.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "crypt32.lib" "shlwapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

add_dependencies(${BINARY_NAME} flutter_assemble)

add_executable(companion_window_test EXCLUDE_FROM_ALL "../../test/windows/companion_window_test.cpp")
apply_standard_settings(companion_window_test)
target_compile_definitions(companion_window_test PRIVATE NOMINMAX)

add_executable(virtual_file_data_test EXCLUDE_FROM_ALL
  "../../test/windows/virtual_file_data_test.cpp" "virtual_file_data.cpp")
apply_standard_settings(virtual_file_data_test)
target_compile_definitions(virtual_file_data_test PRIVATE NOMINMAX)
target_link_libraries(virtual_file_data_test PRIVATE "ole32.lib" "shell32.lib" "uuid.lib" "crypt32.lib" "shlwapi.lib")
