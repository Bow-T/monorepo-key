# CMakeLists.txt — windows_ime (Bow Go)
# --------------------------------------
# Hai mục tiêu:
#   1. bowgo_engine_tests  — chạy MỌI NỀN (macOS/Linux/Windows). Đây là phần ĐÃ
#      kiểm chứng: engine C++ + 81 ca test chuẩn. Build & chạy để bảo đảm khớp
#      bản Dart/Swift.
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

# ── Thư viện engine (thuần, đa nền) ──────────────────────────────────────────
add_library(bowgo_engine STATIC
    engine/engine.cpp
    engine/viet_table.cpp
    engine/viet_syllable.cpp
    engine/macro.cpp
    engine/text_converter.cpp
)
target_include_directories(bowgo_engine PUBLIC engine)

# ── Test engine (đa nền) ─────────────────────────────────────────────────────
add_executable(bowgo_engine_tests engine/test_engine.cpp)
target_link_libraries(bowgo_engine_tests PRIVATE bowgo_engine)

enable_testing()
add_test(NAME engine_golden_cases COMMAND bowgo_engine_tests)

# ── Text service TSF (CHỈ Windows) ───────────────────────────────────────────
if(WIN32)
    add_library(BowGoTSF SHARED
        tsf/dll_main.cpp
        tsf/BowGoTextService.cpp
    )
    target_link_libraries(BowGoTSF PRIVATE bowgo_engine)
    # TSF cần các thư viện COM/Text Services của Windows.
    target_link_libraries(BowGoTSF PRIVATE ole32 oleaut32 uuid)
    set_target_properties(BowGoTSF PROPERTIES OUTPUT_NAME "BowGoTSF")
endif()
