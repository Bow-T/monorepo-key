/* viet_core.h — C ABI của engine gõ tiếng Việt (packages/viet_core, Rust).
 *
 * Dùng chung cho bộ gõ macOS (Swift, qua module CVietCore) và Windows (C++, lớp bọc
 * bowgo::VietEngine). Mọi hàm nhận `engine` đều đòi con trỏ hợp lệ từ bow_engine_new.
 * Engine không an toàn đa luồng: mỗi luồng/phiên gõ dùng một engine riêng.
 */
#ifndef VIET_CORE_H
#define VIET_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct BowEngine BowEngine;

#define BOW_METHOD_TELEX 0u
#define BOW_METHOD_VNI 1u
#define BOW_TONE_MODERN 0u
#define BOW_TONE_OLD 1u

/* Tạo engine; giải phóng bằng bow_engine_free. */
BowEngine *bow_engine_new(uint32_t method, uint32_t tone_style);
void bow_engine_free(BowEngine *engine);

/* Phím `ch` (Unicode scalar) có thuộc âm tiết không (false -> process sẽ chốt từ). */
bool bow_engine_is_word_char(const BowEngine *engine, uint32_t ch);

/* true: phím thuộc âm tiết, chuỗi mới lấy bằng bow_engine_text.
 * false: phím ngắt từ, âm tiết đã chốt — caller xuất phím nguyên bản. */
bool bow_engine_process(BowEngine *engine, uint32_t ch);

/* true: đã lùi 1 phím thô và dựng lại âm tiết; false: buffer rỗng, để Backspace đi qua. */
bool bow_engine_backspace(BowEngine *engine);

void bow_engine_clear(BowEngine *engine);

/* Chuỗi hiển thị UTF-8 (không có NUL cuối) của âm tiết hiện tại; số byte ghi vào *len.
 * Con trỏ hợp lệ tới lần gọi kế tiếp vào cùng engine. */
const uint8_t *bow_engine_text(BowEngine *engine, size_t *len);

#ifdef __cplusplus
}
#endif

#endif /* VIET_CORE_H */
