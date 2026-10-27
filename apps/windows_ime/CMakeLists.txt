# CMakeLists.txt — windows_ime (Bow Go)
# --------------------------------------
# Hai mục tiêu:
#   1. bowgo_engine_tests  — chạy MỌI NỀN (macOS/Linux/Windows). Đây là phần ĐÃ
#      kiểm chứng: engine C++ + ca riêng + bộ ca chuẩn dùng chung với Dart/Swift
#      (packages/viet_engine/spec/typing_cases.tsv).
#   2. BowGoTSF (DLL)      — CHỈ trên Windows. Text service TSF (skeleton, chưa
#      hoàn thiện) — cần Windows SDK (msctf).
#
# Build engine + test (mọi nền):
#   cmake -S . -B build && cmake --build build
#   ./build/bowgo_engine_tests
#
# Trên Windows, cấu hình trên cũng dựng thêm DLL BowGoTSF.

cmake_minimum_required(VERSION 3.18)
project(bowgo_windows_ime CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Mã nguồn là UTF-8 không BOM, chứa chữ Việt trong U"..." — thiếu /utf-8 thì MSVC
# đọc theo codepage máy (1252) và dựng sai chuỗi.
if(MSVC)
    add_compile_options(/utf-8)
endif()

# ── Core gõ Rust (packages/viet_core) ────────────────────────────────────────
# cargo build mỗi lần build (không đổi gì thì cargo bỏ qua ngay), ra thư viện tĩnh
# trong thư mục build. rustup qua Homebrew là keg-only nên tìm thêm ở đó.
find_program(CARGO cargo HINTS "$ENV{HOME}/.cargo/bin" /opt/homebrew/opt/rustup/bin REQUIRED)
find_program(RUSTC rustc HINTS "$ENV{HOME}/.cargo/bin" /opt/homebrew/opt/rustup/bin REQUIRED)
set(VIET_CORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../packages/viet_core")
set(VIET_CORE_TARGET_DIR "${CMAKE_BINARY_DIR}/viet_core")
set(VIET_CORE_LIB "${VIET_CORE_TARGET_DIR}/release/${CMAKE_STATIC_LIBRARY_PREFIX}viet_core${CMAKE_STATIC_LIBRARY_SUFFIX}")
add_custom_target(viet_core_build
    COMMAND "${CMAKE_COMMAND}" -E env "RUSTC=${RUSTC}"
            "${CARGO}" build --release --manifest-path "${VIET_CORE_DIR}/Cargo.toml"
            --target-dir "${VIET_CORE_TARGET_DIR}"
    BYPRODUCTS "${VIET_CORE_LIB}"
    USES_TERMINAL)
add_library(viet_core STATIC IMPORTED)
set_target_properties(viet_core PROPERTIES
    IMPORTED_LOCATION "${VIET_CORE_LIB}"
    INTERFACE_INCLUDE_DIRECTORIES "${VIET_CORE_DIR}/include")
# Thư viện hệ thống mà std của Rust cần trên MSVC (cargo rustc -- --print native-static-libs).
if(MSVC)
    set_property(TARGET viet_core PROPERTY
        INTERFACE_LINK_LIBRARIES kernel32 ntdll userenv ws2_32 dbghelp)
endif()

# ── Thư viện engine (thuần, đa nền) ──────────────────────────────────────────
add_library(bowgo_engine STATIC
    engine/engine.cpp
    engine/viet_table.cpp
    engine/viet_syllable.cpp
    engine/macro.cpp
    engine/auto_correct.cpp
    engine/text_converter.cpp
)
target_include_directories(bowgo_engine PUBLIC engine)
target_link_libraries(bowgo_engine PUBLIC viet_core)
add_dependencies(bowgo_engine viet_core_build)

# ── Tầng common (đa nền): controller + đọc settings.json + chuyển mã ─────────
add_library(bowgo_common STATIC
    common/text_codec.cpp
    common/bow_config.cpp
    common/ime_controller.cpp
)
target_include_directories(bowgo_common PUBLIC common)
target_link_libraries(bowgo_common PUBLIC bowgo_engine)

# ── Test engine + test common (đa nền) ───────────────────────────────────────
add_executable(bowgo_engine_tests engine/test_engine.cpp)
target_link_libraries(bowgo_engine_tests PRIVATE bowgo_engine)
# Bộ ca gõ chuẩn dùng chung với engine Dart/Swift.
target_compile_definitions(bowgo_engine_tests PRIVATE
    BOWGO_TYPING_CASES="${CMAKE_CURRENT_SOURCE_DIR}/../../packages/viet_engine/spec/typing_cases.tsv")

add_executable(bowgo_common_tests common/test_common.cpp)
target_link_libraries(bowgo_common_tests PRIVATE bowgo_common)

enable_testing()
add_test(NAME engine_golden_cases COMMAND bowgo_engine_tests)
add_test(NAME common_controller_config COMMAND bowgo_common_tests)

# ── Text service TSF (CHỈ Windows) ───────────────────────────────────────────
if(WIN32)
    add_library(BowGoTSF SHARED
        tsf/dll_main.cpp
        tsf/BowGoTextService.cpp
        tsf/lang_bar.cpp
        tsf/badge_icon.cpp
    )
    target_link_libraries(BowGoTSF PRIVATE bowgo_common)
    # TSF cần các thư viện COM/Text Services + Win32 + GDI của Windows.
    target_link_libraries(BowGoTSF PRIVATE ole32 oleaut32 uuid user32 advapi32 imm32 gdi32)
    set_target_properties(BowGoTSF PROPERTIES OUTPUT_NAME "BowGoTSF")
    # DLL export các hàm COM chuẩn (DllGetClassObject...) qua .def.
    if(MSVC)
        target_sources(BowGoTSF PRIVATE tsf/BowGoTSF.def)
    endif()
endif()
