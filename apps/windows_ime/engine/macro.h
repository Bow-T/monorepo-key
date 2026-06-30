// macro.h
// -------
// GÕ TẮT (macro/snippet) — bản C++ của Macro.swift. Gõ từ khoá ASCII (vd "vn")
// rồi nhấn phím ngắt từ -> thay bằng nội dung. Hỗ trợ tĩnh + động.

#pragma once

#include <functional>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

namespace bowgo {

enum class MacroSnippetType { StaticText, Date, Time, DateTime, Random, Counter };

MacroSnippetType MacroSnippetTypeFromString(const std::string& s);

struct MacroDefinition {
    std::u32string keyword;  // phím thô ASCII kích hoạt, vd U"vn"
    std::u32string content;  // nội dung (tĩnh) hoặc format/tham số (động)
    MacroSnippetType type = MacroSnippetType::StaticText;
};

// Thời điểm phân rã (để format ngày giờ). Tiêm vào để test xác định.
struct MacroClock {
    int year, month, day, hour, minute, second;
};

// Môi trường tiêm (đồng hồ + random).
struct MacroEnvironment {
    std::function<MacroClock()> now;            // null -> dùng đồng hồ thật
    std::function<int(int count)> randomIndex;  // null -> 0
};

class MacroStore {
public:
    explicit MacroStore(const std::vector<MacroDefinition>& definitions = {},
                        MacroEnvironment environment = {});

    void Set(const MacroDefinition& definition);
    void Clear();
    bool IsEmpty() const { return by_keyword_.empty(); }

    // Tra macro theo từ khoá thô. Trả nội dung ĐÃ BUNG, hoặc nullopt.
    std::optional<std::u32string> Expand(const std::u32string& keyword);

private:
    std::u32string Render(const MacroDefinition& def);
    std::u32string FormatDateTime(const std::u32string& format);
    std::u32string RandomValue(const std::u32string& list);
    std::u32string CounterValue(const std::u32string& prefix);

    std::unordered_map<std::u32string, MacroDefinition> by_keyword_;
    std::unordered_map<std::u32string, int> counters_;
    MacroEnvironment env_;
};

}  // namespace bowgo
