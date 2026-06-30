# CMakeLists.txt — windows_ime (Bow Key)
# --------------------------------------
# Hai mục tiêu:
#   1. bowkey_engine_tests  — chạy MỌI NỀN (macOS/Linux/Windows). Đây là phần ĐÃ
#      kiểm chứng: engine C++ + 81 ca test chuẩn. Build & chạy để bảo đảm khớp
#      bản Dart/Swift.
#   2. BowKeyTSF (DLL)      — CHỈ trên Windows. Text service TSF (skeleton, chưa
#      hoàn thiện) — cần Windows SDK (msctf).
#
# Build engine + test (mọi nền):
#   cmake -S . -B build && cmake --build build
#   ./build/bowkey_engine_tests
#
# Trên Windows, cấu hình trên cũng dựng thêm DLL BowKeyTSF.

cmake_minimum_required(VERSION 3.16)
project(bowkey_windows_ime CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── Thư viện engine (thuần, đa nền) ──────────────────────────────────────────
add_library(bowkey_engine STATIC
    engine/engine.cpp
    engine/viet_table.cpp
)
target_include_directories(bowkey_engine PUBLIC engine)

# ── Test engine (đa nền) ─────────────────────────────────────────────────────
add_executable(bowkey_engine_tests engine/test_engine.cpp)
target_link_libraries(bowkey_engine_tests PRIVATE bowkey_engine)

enable_testing()
add_test(NAME engine_golden_cases COMMAND bowkey_engine_tests)

# ── Text service TSF (CHỈ Windows) ───────────────────────────────────────────
if(WIN32)
    add_library(BowKeyTSF SHARED
        tsf/dll_main.cpp
        tsf/BowKeyTextService.cpp
    )
    target_link_libraries(BowKeyTSF PRIVATE bowkey_engine)
    # TSF cần các thư viện COM/Text Services của Windows.
    target_link_libraries(BowKeyTSF PRIVATE ole32 oleaut32 uuid)
    set_target_properties(BowKeyTSF PROPERTIES OUTPUT_NAME "BowKeyTSF")
endif()
