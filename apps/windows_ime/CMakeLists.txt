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

cmake_minimum_required(VERSION 3.16)
project(bowgo_windows_ime CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Mã nguồn là UTF-8 không BOM, chứa chữ Việt trong U"..." — thiếu /utf-8 thì MSVC
# đọc theo codepage máy (1252) và dựng sai chuỗi.
if(MSVC)
    add_compile_options(/utf-8)
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
