// bow_config.cpp — xem bow_config.h.

#include "bow_config.h"

#include <cstdio>
#include <cstdlib>

#include "text_codec.h"

namespace bowgo {

namespace {

// ── Parser JSON tối giản ─────────────────────────────────────────────────────
// Đủ cho settings.json: null/bool/số/chuỗi/mảng/object, escape \uXXXX (kể cả
// surrogate pair). Không hỗ trợ comment/trailing comma (JSON chuẩn không có).

struct Json {
    enum class Type { Null, Bool, Number, String, Array, Object };
    Type type = Type::Null;
    bool boolean = false;
    double number = 0;
    std::string string;  // UTF-8
    std::vector<Json> array;
    std::vector<std::pair<std::string, Json>> object;

    const Json* Find(const std::string& key) const {
        if (type != Type::Object) return nullptr;
        for (const auto& [k, v] : object) {
            if (k == key) return &v;
        }
        return nullptr;
    }
};

class Parser {
public:
    explicit Parser(const std::string& text) : s_(text) {}

    std::optional<Json> Parse() {
        SkipWs();
        auto v = ParseValue();
        if (!v) return std::nullopt;
        SkipWs();
        if (pos_ != s_.size()) return std::nullopt;  // rác sau JSON
        return v;
    }

private:
    const std::string& s_;
    size_t pos_ = 0;

    bool Eof() const { return pos_ >= s_.size(); }
    char Peek() const { return s_[pos_]; }

    void SkipWs() {
        while (!Eof()) {
            char c = Peek();
            if (c == ' ' || c == '\t' || c == '\n' || c == '\r') ++pos_;
            else break;
        }
    }

    bool Consume(char c) {
        if (Eof() || Peek() != c) return false;
        ++pos_;
        return true;
    }

    bool ConsumeWord(const char* w) {
        size_t len = 0;
        while (w[len]) ++len;
        if (s_.compare(pos_, len, w) != 0) return false;
        pos_ += len;
        return true;
    }

    std::optional<Json> ParseValue() {
        if (Eof()) return std::nullopt;
        switch (Peek()) {
            case '{': return ParseObject();
            case '[': return ParseArray();
            case '"': return ParseString();
            case 't':
                if (!ConsumeWord("true")) return std::nullopt;
                return MakeBool(true);
            case 'f':
                if (!ConsumeWord("false")) return std::nullopt;
                return MakeBool(false);
            case 'n':
                if (!ConsumeWord("null")) return std::nullopt;
                return Json{};
            default: return ParseNumber();
        }
    }

    static Json MakeBool(bool b) {
        Json j;
        j.type = Json::Type::Bool;
        j.boolean = b;
        return j;
    }

    std::optional<Json> ParseObject() {
        if (!Consume('{')) return std::nullopt;
        Json j;
        j.type = Json::Type::Object;
        SkipWs();
        if (Consume('}')) return j;
        while (true) {
            SkipWs();
            auto key = ParseString();
            if (!key) return std::nullopt;
            SkipWs();
            if (!Consume(':')) return std::nullopt;
            SkipWs();
            auto value = ParseValue();
            if (!value) return std::nullopt;
            j.object.emplace_back(std::move(key->string), std::move(*value));
            SkipWs();
            if (Consume(',')) continue;
            if (Consume('}')) return j;
            return std::nullopt;
        }
    }

    std::optional<Json> ParseArray() {
        if (!Consume('[')) return std::nullopt;
        Json j;
        j.type = Json::Type::Array;
        SkipWs();
        if (Consume(']')) return j;
        while (true) {
            SkipWs();
            auto value = ParseValue();
            if (!value) return std::nullopt;
            j.array.push_back(std::move(*value));
            SkipWs();
            if (Consume(',')) continue;
            if (Consume(']')) return j;
            return std::nullopt;
        }
    }

    std::optional<Json> ParseString() {
        if (!Consume('"')) return std::nullopt;
        Json j;
        j.type = Json::Type::String;
        std::u32string out;
        while (true) {
            if (Eof()) return std::nullopt;
            unsigned char c = static_cast<unsigned char>(s_[pos_]);
            if (c == '"') {
                ++pos_;
                break;
            }
            if (c == '\\') {
                ++pos_;
                if (Eof()) return std::nullopt;
                char e = s_[pos_++];
                switch (e) {
                    case '"': out.push_back('"'); break;
                    case '\\': out.push_back('\\'); break;
                    case '/': out.push_back('/'); break;
                    case 'b': out.push_back('\b'); break;
                    case 'f': out.push_back('\f'); break;
                    case 'n': out.push_back('\n'); break;
                    case 'r': out.push_back('\r'); break;
                    case 't': out.push_back('\t'); break;
                    case 'u': {
                        auto hi = ParseHex4();
                        if (!hi) return std::nullopt;
                        char32_t cp = *hi;
                        // Surrogate pair: \uD8xx phải đi kèm \uDCxx.
                        if (cp >= 0xD800 && cp <= 0xDBFF) {
                            if (pos_ + 1 < s_.size() && s_[pos_] == '\\' &&
                                s_[pos_ + 1] == 'u') {
                                pos_ += 2;
                                auto lo = ParseHex4();
                                if (!lo) return std::nullopt;
                                if (*lo >= 0xDC00 && *lo <= 0xDFFF) {
                                    cp = 0x10000 + ((cp - 0xD800) << 10) + (*lo - 0xDC00);
                                } else {
                                    cp = 0xFFFD;
                                }
                            } else {
                                cp = 0xFFFD;
                            }
                        } else if (cp >= 0xDC00 && cp <= 0xDFFF) {
                            cp = 0xFFFD;  // low surrogate lẻ loi
                        }
                        out.push_back(cp);
                        break;
                    }
                    default: return std::nullopt;
                }
                continue;
            }
            // Byte UTF-8 thô — gom trọn một chuỗi liên tục rồi decode một thể.
            size_t start = pos_;
            while (!Eof()) {
                unsigned char b = static_cast<unsigned char>(s_[pos_]);
                if (b == '"' || b == '\\') break;
                ++pos_;
            }
            out += Utf8ToU32(s_.substr(start, pos_ - start));
        }
        j.string = U32ToUtf8(out);
        return j;
    }

    std::optional<char32_t> ParseHex4() {
        if (pos_ + 4 > s_.size()) return std::nullopt;
        char32_t v = 0;
        for (int i = 0; i < 4; ++i) {
            char c = s_[pos_++];
            v <<= 4;
            if (c >= '0' && c <= '9') v |= c - '0';
            else if (c >= 'a' && c <= 'f') v |= c - 'a' + 10;
            else if (c >= 'A' && c <= 'F') v |= c - 'A' + 10;
            else return std::nullopt;
        }
        return v;
    }

    std::optional<Json> ParseNumber() {
        size_t start = pos_;
        if (!Eof() && Peek() == '-') ++pos_;
        while (!Eof() && Peek() >= '0' && Peek() <= '9') ++pos_;
        if (!Eof() && Peek() == '.') {
            ++pos_;
            while (!Eof() && Peek() >= '0' && Peek() <= '9') ++pos_;
        }
        if (!Eof() && (Peek() == 'e' || Peek() == 'E')) {
            ++pos_;
            if (!Eof() && (Peek() == '+' || Peek() == '-')) ++pos_;
            while (!Eof() && Peek() >= '0' && Peek() <= '9') ++pos_;
        }
        if (pos_ == start) return std::nullopt;
        Json j;
        j.type = Json::Type::Number;
        j.number = std::strtod(s_.substr(start, pos_ - start).c_str(), nullptr);
        return j;
    }
};

// ── Đọc từng khoá (khoá thiếu/kiểu sai -> giữ mặc định, như Swift) ───────────

bool ReadBool(const Json& root, const char* key, bool fallback) {
    const Json* v = root.Find(key);
    return (v && v->type == Json::Type::Bool) ? v->boolean : fallback;
}

long long ReadInt(const Json& root, const char* key, long long fallback) {
    const Json* v = root.Find(key);
    return (v && v->type == Json::Type::Number) ? static_cast<long long>(v->number)
                                                : fallback;
}

std::string ReadString(const Json& root, const char* key, const std::string& fallback) {
    const Json* v = root.Find(key);
    return (v && v->type == Json::Type::String) ? v->string : fallback;
}

}  // namespace

std::optional<BowConfig> ParseBowConfig(const std::string& json) {
    auto root = Parser(json).Parse();
    if (!root || root->type != Json::Type::Object) return std::nullopt;

    BowConfig cfg;
    cfg.enabled = ReadBool(*root, "enabled", cfg.enabled);
    cfg.method = ReadString(*root, "method", "telex") == "vni" ? InputMethod::Vni
                                                               : InputMethod::Telex;
    cfg.tone_style = ReadString(*root, "toneStyle", "modern") == "old"
                         ? ToneStyle::Old
                         : ToneStyle::Modern;
    cfg.hotkey_key_code = ReadInt(*root, "hotkeyKeyCode", cfg.hotkey_key_code);

    if (const Json* mods = root->Find("hotkeyModifiers");
        mods && mods->type == Json::Type::Array) {
        cfg.hotkey_modifiers.clear();
        for (const Json& m : mods->array) {
            if (m.type == Json::Type::String) cfg.hotkey_modifiers.insert(m.string);
        }
    }

    cfg.macro_enabled = ReadBool(*root, "macroEnabled", cfg.macro_enabled);
    if (const Json* macros = root->Find("macros");
        macros && macros->type == Json::Type::Array) {
        for (const Json& m : macros->array) {
            if (m.type != Json::Type::Object) continue;
            MacroDefinition def;
            def.keyword = Utf8ToU32(ReadString(m, "keyword", ""));
            def.content = Utf8ToU32(ReadString(m, "content", ""));
            def.type = MacroSnippetTypeFromString(ReadString(m, "type", "staticText"));
            if (!def.keyword.empty()) cfg.macros.push_back(std::move(def));
        }
    }

    cfg.auto_restore_english =
        ReadBool(*root, "autoRestoreEnglish", cfg.auto_restore_english);
    cfg.auto_correct = ReadBool(*root, "autoCorrect", cfg.auto_correct);
    if (const Json* pairs = root->Find("autoCorrectPairs");
        pairs && pairs->type == Json::Type::Array) {
        cfg.has_auto_correct_pairs = true;
        for (const Json& p : pairs->array) {
            if (p.type != Json::Type::Object) continue;
            BowAutoCorrectPair pair;
            pair.wrong = Utf8ToU32(ReadString(p, "wrong", ""));
            pair.right = Utf8ToU32(ReadString(p, "right", ""));
            if (!pair.wrong.empty() && !pair.right.empty()) {
                cfg.auto_correct_pairs.push_back(std::move(pair));
            }
        }
    }

    return cfg;
}

std::optional<BowConfig> LoadBowConfig(const std::string& path) {
    std::FILE* f = std::fopen(path.c_str(), "rb");
    if (!f) return std::nullopt;
    std::string data;
    char buf[4096];
    size_t n;
    while ((n = std::fread(buf, 1, sizeof buf, f)) > 0) data.append(buf, n);
    std::fclose(f);
    return ParseBowConfig(data);
}

std::string DefaultSettingsPath() {
#if defined(_WIN32)
    const char* appdata = std::getenv("APPDATA");
    if (!appdata || !*appdata) return "";
    return std::string(appdata) + "\\BowGo\\settings.json";
#else
    const char* home = std::getenv("HOME");
    if (!home || !*home) return "";
    return std::string(home) + "/Library/Application Support/BowGo/settings.json";
#endif
}

}  // namespace bowgo
