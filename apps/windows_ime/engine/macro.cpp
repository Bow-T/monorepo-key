// macro.cpp
// ---------
// Cài đặt gõ tắt / macro (bản C++). Port từ Macro.swift; phải khớp Swift/Dart.

#include "macro.h"

#include <ctime>

namespace bowkey {

namespace {

// Số nguyên -> chuỗi u32.
std::u32string ToU32(long long v) {
    if (v == 0) return U"0";
    bool neg = v < 0;
    unsigned long long n = neg ? -v : v;
    std::u32string s;
    while (n > 0) {
        s.insert(s.begin(), U'0' + (n % 10));
        n /= 10;
    }
    if (neg) s.insert(s.begin(), U'-');
    return s;
}

std::u32string TwoDigit(int v) {
    std::u32string s = ToU32(v);
    if (s.size() < 2) s.insert(s.begin(), U'0');
    return s;
}

MacroClock SystemClock() {
    std::time_t t = std::time(nullptr);
    std::tm lt{};
#if defined(_WIN32)
    localtime_s(&lt, &t);
#else
    localtime_r(&t, &lt);
#endif
    return {lt.tm_year + 1900, lt.tm_mon + 1, lt.tm_mday, lt.tm_hour, lt.tm_min, lt.tm_sec};
}

bool IsToken(char32_t c) {
    return c == U'd' || c == U'M' || c == U'y' || c == U'H' || c == U'm' || c == U's';
}

}  // namespace

MacroSnippetType MacroSnippetTypeFromString(const std::string& s) {
    if (s == "date") return MacroSnippetType::Date;
    if (s == "time") return MacroSnippetType::Time;
    if (s == "dateTime") return MacroSnippetType::DateTime;
    if (s == "random") return MacroSnippetType::Random;
    if (s == "counter") return MacroSnippetType::Counter;
    return MacroSnippetType::StaticText;
}

MacroStore::MacroStore(const std::vector<MacroDefinition>& definitions,
                       MacroEnvironment environment)
    : env_(std::move(environment)) {
    for (const auto& d : definitions) by_keyword_[d.keyword] = d;
}

void MacroStore::Set(const MacroDefinition& definition) {
    by_keyword_[definition.keyword] = definition;
}

void MacroStore::Clear() {
    by_keyword_.clear();
    counters_.clear();
}

std::optional<std::u32string> MacroStore::Expand(const std::u32string& keyword) {
    auto it = by_keyword_.find(keyword);
    if (it == by_keyword_.end()) return std::nullopt;
    return Render(it->second);
}

std::u32string MacroStore::Render(const MacroDefinition& def) {
    switch (def.type) {
        case MacroSnippetType::StaticText:
            return def.content;
        case MacroSnippetType::Date:
            return FormatDateTime(def.content.empty() ? U"dd/MM/yyyy" : def.content);
        case MacroSnippetType::Time:
            return FormatDateTime(def.content.empty() ? U"HH:mm:ss" : def.content);
        case MacroSnippetType::DateTime:
            return FormatDateTime(def.content.empty() ? U"dd/MM/yyyy HH:mm" : def.content);
        case MacroSnippetType::Random:
            return RandomValue(def.content);
        case MacroSnippetType::Counter:
            return CounterValue(def.content);
    }
    return def.content;
}

std::u32string MacroStore::FormatDateTime(const std::u32string& format) {
    MacroClock c = env_.now ? env_.now() : SystemClock();
    std::u32string out;
    char32_t lastChar = 0;
    int repeatCount = 0;

    auto flush = [&] {
        if (lastChar == 0 || repeatCount == 0) return;
        switch (lastChar) {
            case U'd': out += (repeatCount >= 2 ? TwoDigit(c.day) : ToU32(c.day)); break;
            case U'M': out += (repeatCount >= 2 ? TwoDigit(c.month) : ToU32(c.month)); break;
            case U'y': out += (repeatCount >= 4 ? ToU32(c.year) : TwoDigit(c.year % 100)); break;
            case U'H': out += (repeatCount >= 2 ? TwoDigit(c.hour) : ToU32(c.hour)); break;
            case U'm': out += (repeatCount >= 2 ? TwoDigit(c.minute) : ToU32(c.minute)); break;
            case U's': out += (repeatCount >= 2 ? TwoDigit(c.second) : ToU32(c.second)); break;
            default:
                for (int i = 0; i < repeatCount; ++i) out.push_back(lastChar);
                break;
        }
        repeatCount = 0;
    };

    for (char32_t ch : format) {
        if (ch == lastChar && IsToken(ch)) {
            ++repeatCount;
        } else {
            flush();
            lastChar = ch;
            repeatCount = 1;
        }
    }
    flush();
    return out;
}

std::u32string MacroStore::RandomValue(const std::u32string& list) {
    std::vector<std::u32string> items;
    std::u32string cur;
    auto push = [&] {
        // trim space/tab
        size_t a = cur.find_first_not_of(U" \t");
        size_t b = cur.find_last_not_of(U" \t");
        if (a != std::u32string::npos) items.push_back(cur.substr(a, b - a + 1));
    };
    for (char32_t ch : list) {
        if (ch == U',') {
            push();
            cur.clear();
        } else {
            cur.push_back(ch);
        }
    }
    push();
    if (items.empty()) return list;
    int idx = env_.randomIndex ? env_.randomIndex(static_cast<int>(items.size())) : 0;
    return items[static_cast<size_t>(idx) % items.size()];
}

std::u32string MacroStore::CounterValue(const std::u32string& prefix) {
    int next = counters_[prefix] + 1;
    counters_[prefix] = next;
    return prefix + ToU32(next);
}

}  // namespace bowkey
