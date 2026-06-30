// text_converter.cpp
// ------------------
// Cài đặt công cụ chuyển mã (bản C++). Port từ TextConverter.swift.

#include "text_converter.h"

#include <unordered_map>

namespace bowgo {

namespace {

char32_t ToLower(char32_t c) {
  if (c >= U'A' && c <= U'Z') return c + 32;
  return c;
}
char32_t ToUpper(char32_t c) {
  if (c >= U'a' && c <= U'z') return c - 32;
  return c;
}
bool IsLetter(char32_t c) { return ToLower(c) != ToUpper(c) || (c >= U'a' && c <= U'z'); }

  // Unicode -> kUnicodeToTcvn: 134 ký tự (chuẩn bảng mã).
  const std::unordered_map<char32_t, std::u32string> kUnicodeToTcvn = {
      {U'\U000000C0', U"\U000000B5"},
      {U'\U000000C1', U"\U000000B8"},
      {U'\U000000C2', U"\U000000A2"},
      {U'\U000000C3', U"\U000000B7"},
      {U'\U000000C8', U"\U000000CC"},
      {U'\U000000C9', U"\U000000D0"},
      {U'\U000000CA', U"\U000000A3"},
      {U'\U000000CC', U"\U000000D7"},
      {U'\U000000CD', U"\U000000DD"},
      {U'\U000000D2', U"\U000000DF"},
      {U'\U000000D3', U"\U000000E3"},
      {U'\U000000D4', U"\U000000A4"},
      {U'\U000000D5', U"\U000000E2"},
      {U'\U000000D9', U"\U000000EF"},
      {U'\U000000DA', U"\U000000F3"},
      {U'\U000000DD', U"\U000000FD"},
      {U'\U000000E0', U"\U000000B5"},
      {U'\U000000E1', U"\U000000B8"},
      {U'\U000000E2', U"\U000000A9"},
      {U'\U000000E3', U"\U000000B7"},
      {U'\U000000E8', U"\U000000CC"},
      {U'\U000000E9', U"\U000000D0"},
      {U'\U000000EA', U"\U000000AA"},
      {U'\U000000EC', U"\U000000D7"},
      {U'\U000000ED', U"\U000000DD"},
      {U'\U000000F2', U"\U000000DF"},
      {U'\U000000F3', U"\U000000E3"},
      {U'\U000000F4', U"\U000000AB"},
      {U'\U000000F5', U"\U000000E2"},
      {U'\U000000F9', U"\U000000EF"},
      {U'\U000000FA', U"\U000000F3"},
      {U'\U000000FD', U"\U000000FD"},
      {U'\U00000102', U"\U000000A1"},
      {U'\U00000103', U"\U000000A8"},
      {U'\U00000110', U"\U000000A7"},
      {U'\U00000111', U"\U000000AE"},
      {U'\U00000128', U"\U000000DC"},
      {U'\U00000129', U"\U000000DC"},
      {U'\U00000168', U"\U000000F2"},
      {U'\U00000169', U"\U000000F2"},
      {U'\U000001A0', U"\U000000A5"},
      {U'\U000001A1', U"\U000000AC"},
      {U'\U000001AF', U"\U000000A6"},
      {U'\U000001B0', U"\U000000AD"},
      {U'\U00001EA0', U"\U000000B9"},
      {U'\U00001EA1', U"\U000000B9"},
      {U'\U00001EA2', U"\U000000B6"},
      {U'\U00001EA3', U"\U000000B6"},
      {U'\U00001EA4', U"\U000000CA"},
      {U'\U00001EA5', U"\U000000CA"},
      {U'\U00001EA6', U"\U000000C7"},
      {U'\U00001EA7', U"\U000000C7"},
      {U'\U00001EA8', U"\U000000C8"},
      {U'\U00001EA9', U"\U000000C8"},
      {U'\U00001EAA', U"\U000000C9"},
      {U'\U00001EAB', U"\U000000C9"},
      {U'\U00001EAC', U"\U000000CB"},
      {U'\U00001EAD', U"\U000000CB"},
      {U'\U00001EAE', U"\U000000BE"},
      {U'\U00001EAF', U"\U000000BE"},
      {U'\U00001EB0', U"\U000000BB"},
      {U'\U00001EB1', U"\U000000BB"},
      {U'\U00001EB2', U"\U000000BC"},
      {U'\U00001EB3', U"\U000000BC"},
      {U'\U00001EB4', U"\U000000BD"},
      {U'\U00001EB5', U"\U000000BD"},
      {U'\U00001EB6', U"\U000000C6"},
      {U'\U00001EB7', U"\U000000C6"},
      {U'\U00001EB8', U"\U000000D1"},
      {U'\U00001EB9', U"\U000000D1"},
      {U'\U00001EBA', U"\U000000CE"},
      {U'\U00001EBB', U"\U000000CE"},
      {U'\U00001EBC', U"\U000000CF"},
      {U'\U00001EBD', U"\U000000CF"},
      {U'\U00001EBE', U"\U000000D5"},
      {U'\U00001EBF', U"\U000000D5"},
      {U'\U00001EC0', U"\U000000D2"},
      {U'\U00001EC1', U"\U000000D2"},
      {U'\U00001EC2', U"\U000000D3"},
      {U'\U00001EC3', U"\U000000D3"},
      {U'\U00001EC4', U"\U000000D4"},
      {U'\U00001EC5', U"\U000000D4"},
      {U'\U00001EC6', U"\U000000D6"},
      {U'\U00001EC7', U"\U000000D6"},
      {U'\U00001EC8', U"\U000000D8"},
      {U'\U00001EC9', U"\U000000D8"},
      {U'\U00001ECA', U"\U000000DE"},
      {U'\U00001ECB', U"\U000000DE"},
      {U'\U00001ECC', U"\U000000E4"},
      {U'\U00001ECD', U"\U000000E4"},
      {U'\U00001ECE', U"\U000000E1"},
      {U'\U00001ECF', U"\U000000E1"},
      {U'\U00001ED0', U"\U000000E8"},
      {U'\U00001ED1', U"\U000000E8"},
      {U'\U00001ED2', U"\U000000E5"},
      {U'\U00001ED3', U"\U000000E5"},
      {U'\U00001ED4', U"\U000000E6"},
      {U'\U00001ED5', U"\U000000E6"},
      {U'\U00001ED6', U"\U000000E7"},
      {U'\U00001ED7', U"\U000000E7"},
      {U'\U00001ED8', U"\U000000E9"},
      {U'\U00001ED9', U"\U000000E9"},
      {U'\U00001EDA', U"\U000000ED"},
      {U'\U00001EDB', U"\U000000ED"},
      {U'\U00001EDC', U"\U000000EA"},
      {U'\U00001EDD', U"\U000000EA"},
      {U'\U00001EDE', U"\U000000EB"},
      {U'\U00001EDF', U"\U000000EB"},
      {U'\U00001EE0', U"\U000000EC"},
      {U'\U00001EE1', U"\U000000EC"},
      {U'\U00001EE2', U"\U000000EE"},
      {U'\U00001EE3', U"\U000000EE"},
      {U'\U00001EE4', U"\U000000F4"},
      {U'\U00001EE5', U"\U000000F4"},
      {U'\U00001EE6', U"\U000000F1"},
      {U'\U00001EE7', U"\U000000F1"},
      {U'\U00001EE8', U"\U000000F8"},
      {U'\U00001EE9', U"\U000000F8"},
      {U'\U00001EEA', U"\U000000F5"},
      {U'\U00001EEB', U"\U000000F5"},
      {U'\U00001EEC', U"\U000000F6"},
      {U'\U00001EED', U"\U000000F6"},
      {U'\U00001EEE', U"\U000000F7"},
      {U'\U00001EEF', U"\U000000F7"},
      {U'\U00001EF0', U"\U000000F9"},
      {U'\U00001EF1', U"\U000000F9"},
      {U'\U00001EF2', U"\U000000FA"},
      {U'\U00001EF3', U"\U000000FA"},
      {U'\U00001EF4', U"\U000000FE"},
      {U'\U00001EF5', U"\U000000FE"},
      {U'\U00001EF6', U"\U000000FB"},
      {U'\U00001EF7', U"\U000000FB"},
      {U'\U00001EF8', U"\U000000FC"},
      {U'\U00001EF9', U"\U000000FC"},
  };

  // Unicode -> kUnicodeToVni: 134 ký tự (chuẩn bảng mã).
  const std::unordered_map<char32_t, std::u32string> kUnicodeToVni = {
      {U'\U000000C0', U"\U00000041\U000000D8"},
      {U'\U000000C1', U"\U00000041\U000000D9"},
      {U'\U000000C2', U"\U00000041\U000000C2"},
      {U'\U000000C3', U"\U00000041\U000000D5"},
      {U'\U000000C8', U"\U00000045\U000000D8"},
      {U'\U000000C9', U"\U00000045\U000000D9"},
      {U'\U000000CA', U"\U00000045\U000000C2"},
      {U'\U000000CC', U"\U000000CC"},
      {U'\U000000CD', U"\U000000CD"},
      {U'\U000000D2', U"\U0000004F\U000000D8"},
      {U'\U000000D3', U"\U0000004F\U000000D9"},
      {U'\U000000D4', U"\U0000004F\U000000C2"},
      {U'\U000000D5', U"\U0000004F\U000000D5"},
      {U'\U000000D9', U"\U00000055\U000000D8"},
      {U'\U000000DA', U"\U00000055\U000000D9"},
      {U'\U000000DD', U"\U00000059\U000000D9"},
      {U'\U000000E0', U"\U00000061\U000000F8"},
      {U'\U000000E1', U"\U00000061\U000000F9"},
      {U'\U000000E2', U"\U00000061\U000000E2"},
      {U'\U000000E3', U"\U00000061\U000000F5"},
      {U'\U000000E8', U"\U00000065\U000000F8"},
      {U'\U000000E9', U"\U00000065\U000000F9"},
      {U'\U000000EA', U"\U00000065\U000000E2"},
      {U'\U000000EC', U"\U000000EC"},
      {U'\U000000ED', U"\U000000ED"},
      {U'\U000000F2', U"\U0000006F\U000000F8"},
      {U'\U000000F3', U"\U0000006F\U000000F9"},
      {U'\U000000F4', U"\U0000006F\U000000E2"},
      {U'\U000000F5', U"\U0000006F\U000000F5"},
      {U'\U000000F9', U"\U00000075\U000000F8"},
      {U'\U000000FA', U"\U00000075\U000000F9"},
      {U'\U000000FD', U"\U00000079\U000000F9"},
      {U'\U00000102', U"\U00000041\U000000CA"},
      {U'\U00000103', U"\U00000061\U000000EA"},
      {U'\U00000110', U"\U000000D1"},
      {U'\U00000111', U"\U000000F1"},
      {U'\U00000128', U"\U000000D3"},
      {U'\U00000129', U"\U000000F3"},
      {U'\U00000168', U"\U00000055\U000000D5"},
      {U'\U00000169', U"\U00000075\U000000F5"},
      {U'\U000001A0', U"\U000000D4"},
      {U'\U000001A1', U"\U000000F4"},
      {U'\U000001AF', U"\U000000D6"},
      {U'\U000001B0', U"\U000000F6"},
      {U'\U00001EA0', U"\U00000041\U000000CF"},
      {U'\U00001EA1', U"\U00000061\U000000EF"},
      {U'\U00001EA2', U"\U00000041\U000000DB"},
      {U'\U00001EA3', U"\U00000061\U000000FB"},
      {U'\U00001EA4', U"\U00000041\U000000C1"},
      {U'\U00001EA5', U"\U00000061\U000000E1"},
      {U'\U00001EA6', U"\U00000041\U000000C0"},
      {U'\U00001EA7', U"\U00000061\U000000E0"},
      {U'\U00001EA8', U"\U00000041\U000000C5"},
      {U'\U00001EA9', U"\U00000061\U000000E5"},
      {U'\U00001EAA', U"\U00000041\U000000C3"},
      {U'\U00001EAB', U"\U00000061\U000000E3"},
      {U'\U00001EAC', U"\U00000041\U000000C4"},
      {U'\U00001EAD', U"\U00000061\U000000E4"},
      {U'\U00001EAE', U"\U00000041\U000000C9"},
      {U'\U00001EAF', U"\U00000061\U000000E9"},
      {U'\U00001EB0', U"\U00000041\U000000C8"},
      {U'\U00001EB1', U"\U00000061\U000000E8"},
      {U'\U00001EB2', U"\U00000041\U000000DA"},
      {U'\U00001EB3', U"\U00000061\U000000FA"},
      {U'\U00001EB4', U"\U00000041\U000000DC"},
      {U'\U00001EB5', U"\U00000061\U000000FC"},
      {U'\U00001EB6', U"\U00000041\U000000CB"},
      {U'\U00001EB7', U"\U00000061\U000000EB"},
      {U'\U00001EB8', U"\U00000045\U000000CF"},
      {U'\U00001EB9', U"\U00000065\U000000EF"},
      {U'\U00001EBA', U"\U00000045\U000000DB"},
      {U'\U00001EBB', U"\U00000065\U000000FB"},
      {U'\U00001EBC', U"\U00000045\U000000D5"},
      {U'\U00001EBD', U"\U00000065\U000000F5"},
      {U'\U00001EBE', U"\U00000045\U000000C1"},
      {U'\U00001EBF', U"\U00000065\U000000E1"},
      {U'\U00001EC0', U"\U00000045\U000000C0"},
      {U'\U00001EC1', U"\U00000065\U000000E0"},
      {U'\U00001EC2', U"\U00000045\U000000C5"},
      {U'\U00001EC3', U"\U00000065\U000000E5"},
      {U'\U00001EC4', U"\U00000045\U000000C3"},
      {U'\U00001EC5', U"\U00000065\U000000E3"},
      {U'\U00001EC6', U"\U00000045\U000000C4"},
      {U'\U00001EC7', U"\U00000065\U000000E4"},
      {U'\U00001EC8', U"\U000000C6"},
      {U'\U00001EC9', U"\U000000E6"},
      {U'\U00001ECA', U"\U000000D2"},
      {U'\U00001ECB', U"\U000000F2"},
      {U'\U00001ECC', U"\U0000004F\U000000CF"},
      {U'\U00001ECD', U"\U0000006F\U000000EF"},
      {U'\U00001ECE', U"\U0000004F\U000000DB"},
      {U'\U00001ECF', U"\U0000006F\U000000FB"},
      {U'\U00001ED0', U"\U0000004F\U000000C1"},
      {U'\U00001ED1', U"\U0000006F\U000000E1"},
      {U'\U00001ED2', U"\U0000004F\U000000C0"},
      {U'\U00001ED3', U"\U0000006F\U000000E0"},
      {U'\U00001ED4', U"\U0000004F\U000000C5"},
      {U'\U00001ED5', U"\U0000006F\U000000E5"},
      {U'\U00001ED6', U"\U0000004F\U000000C3"},
      {U'\U00001ED7', U"\U0000006F\U000000E3"},
      {U'\U00001ED8', U"\U0000004F\U000000C4"},
      {U'\U00001ED9', U"\U0000006F\U000000E4"},
      {U'\U00001EDA', U"\U000000D4\U000000D9"},
      {U'\U00001EDB', U"\U000000F4\U000000F9"},
      {U'\U00001EDC', U"\U000000D4\U000000D8"},
      {U'\U00001EDD', U"\U000000F4\U000000F8"},
      {U'\U00001EDE', U"\U000000D4\U000000DB"},
      {U'\U00001EDF', U"\U000000F4\U000000FB"},
      {U'\U00001EE0', U"\U000000D4\U000000D5"},
      {U'\U00001EE1', U"\U000000F4\U000000F5"},
      {U'\U00001EE2', U"\U000000D4\U000000CF"},
      {U'\U00001EE3', U"\U000000F4\U000000EF"},
      {U'\U00001EE4', U"\U00000055\U000000CF"},
      {U'\U00001EE5', U"\U00000075\U000000EF"},
      {U'\U00001EE6', U"\U00000055\U000000DB"},
      {U'\U00001EE7', U"\U00000075\U000000FB"},
      {U'\U00001EE8', U"\U000000D6\U000000D9"},
      {U'\U00001EE9', U"\U000000F6\U000000F9"},
      {U'\U00001EEA', U"\U000000D6\U000000D8"},
      {U'\U00001EEB', U"\U000000F6\U000000F8"},
      {U'\U00001EEC', U"\U000000D6\U000000DB"},
      {U'\U00001EED', U"\U000000F6\U000000FB"},
      {U'\U00001EEE', U"\U000000D6\U000000D5"},
      {U'\U00001EEF', U"\U000000F6\U000000F5"},
      {U'\U00001EF0', U"\U000000D6\U000000CF"},
      {U'\U00001EF1', U"\U000000F6\U000000EF"},
      {U'\U00001EF2', U"\U00000059\U000000D8"},
      {U'\U00001EF3', U"\U00000079\U000000F8"},
      {U'\U00001EF4', U"\U000000CE"},
      {U'\U00001EF5', U"\U000000EE"},
      {U'\U00001EF6', U"\U00000059\U000000DB"},
      {U'\U00001EF7', U"\U00000079\U000000FB"},
      {U'\U00001EF8', U"\U00000059\U000000D5"},
      {U'\U00001EF9', U"\U00000079\U000000F5"},
  };

  // Cặp hoa/thường nguyên âm tiếng Việt (lower -> upper).
  const std::unordered_map<char32_t, char32_t> kVietLowerToUpper = {
      {U'\U000000E0', U'\U000000C0'},
      {U'\U000000E1', U'\U000000C1'},
      {U'\U00001EA3', U'\U00001EA2'},
      {U'\U000000E3', U'\U000000C3'},
      {U'\U00001EA1', U'\U00001EA0'},
      {U'\U00000103', U'\U00000102'},
      {U'\U00001EB1', U'\U00001EB0'},
      {U'\U00001EAF', U'\U00001EAE'},
      {U'\U00001EB3', U'\U00001EB2'},
      {U'\U00001EB5', U'\U00001EB4'},
      {U'\U00001EB7', U'\U00001EB6'},
      {U'\U000000E2', U'\U000000C2'},
      {U'\U00001EA7', U'\U00001EA6'},
      {U'\U00001EA5', U'\U00001EA4'},
      {U'\U00001EA9', U'\U00001EA8'},
      {U'\U00001EAB', U'\U00001EAA'},
      {U'\U00001EAD', U'\U00001EAC'},
      {U'\U000000E8', U'\U000000C8'},
      {U'\U000000E9', U'\U000000C9'},
      {U'\U00001EBB', U'\U00001EBA'},
      {U'\U00001EBD', U'\U00001EBC'},
      {U'\U00001EB9', U'\U00001EB8'},
      {U'\U000000EA', U'\U000000CA'},
      {U'\U00001EC1', U'\U00001EC0'},
      {U'\U00001EBF', U'\U00001EBE'},
      {U'\U00001EC3', U'\U00001EC2'},
      {U'\U00001EC5', U'\U00001EC4'},
      {U'\U00001EC7', U'\U00001EC6'},
      {U'\U000000EC', U'\U000000CC'},
      {U'\U000000ED', U'\U000000CD'},
      {U'\U00001EC9', U'\U00001EC8'},
      {U'\U00000129', U'\U00000128'},
      {U'\U00001ECB', U'\U00001ECA'},
      {U'\U000000F2', U'\U000000D2'},
      {U'\U000000F3', U'\U000000D3'},
      {U'\U00001ECF', U'\U00001ECE'},
      {U'\U000000F5', U'\U000000D5'},
      {U'\U00001ECD', U'\U00001ECC'},
      {U'\U000000F4', U'\U000000D4'},
      {U'\U00001ED3', U'\U00001ED2'},
      {U'\U00001ED1', U'\U00001ED0'},
      {U'\U00001ED5', U'\U00001ED4'},
      {U'\U00001ED7', U'\U00001ED6'},
      {U'\U00001ED9', U'\U00001ED8'},
      {U'\U000001A1', U'\U000001A0'},
      {U'\U00001EDD', U'\U00001EDC'},
      {U'\U00001EDB', U'\U00001EDA'},
      {U'\U00001EDF', U'\U00001EDE'},
      {U'\U00001EE1', U'\U00001EE0'},
      {U'\U00001EE3', U'\U00001EE2'},
      {U'\U000000F9', U'\U000000D9'},
      {U'\U000000FA', U'\U000000DA'},
      {U'\U00001EE7', U'\U00001EE6'},
      {U'\U00000169', U'\U00000168'},
      {U'\U00001EE5', U'\U00001EE4'},
      {U'\U000001B0', U'\U000001AF'},
      {U'\U00001EEB', U'\U00001EEA'},
      {U'\U00001EE9', U'\U00001EE8'},
      {U'\U00001EED', U'\U00001EEC'},
      {U'\U00001EEF', U'\U00001EEE'},
      {U'\U00001EF1', U'\U00001EF0'},
      {U'\U00001EF3', U'\U00001EF2'},
      {U'\U000000FD', U'\U000000DD'},
      {U'\U00001EF7', U'\U00001EF6'},
      {U'\U00001EF9', U'\U00001EF8'},
      {U'\U00001EF5', U'\U00001EF4'},
      {U'\U00000111', U'\U00000110'},
  };

  // Đảo cặp hoa->thường (sinh từ map trên).
  const std::unordered_map<char32_t, char32_t>& VietUpperToLower() {
    static const std::unordered_map<char32_t, char32_t> m = [] {
      std::unordered_map<char32_t, char32_t> r;
      for (const auto& [lo, up] : kVietLowerToUpper) r[up] = lo;
      return r;
    }();
    return m;
  }

  char32_t VietLower(char32_t c) {
    auto it = VietUpperToLower().find(c);
    if (it != VietUpperToLower().end()) return it->second;
    return ToLower(c);
  }
  char32_t VietUpper(char32_t c) {
    auto it = kVietLowerToUpper.find(c);
    if (it != kVietLowerToUpper.end()) return it->second;
    return ToUpper(c);
  }

  // Bỏ dấu: nguyên âm tiếng Việt -> chữ Latin cơ bản.
  const std::unordered_map<char32_t, char32_t>& StripMap() {
    static const std::unordered_map<char32_t, char32_t> m = [] {
      std::unordered_map<char32_t, char32_t> map;
      auto add = [&](char32_t base, const std::u32string& variants) {
        for (char32_t ch : variants) map[ch] = base;
      };
      add(U'a', U"àáảãạăằắẳẵặâầấẩẫậ");
      add(U'e', U"èéẻẽẹêềếểễệ");
      add(U'i', U"ìíỉĩị");
      add(U'o', U"òóỏõọôồốổỗộơờớởỡợ");
      add(U'u', U"ùúủũụưừứửữự");
      add(U'y', U"ỳýỷỹỵ");
      add(U'd', U"đ");
      add(U'A', U"ÀÁẢÃẠĂẰẮẲẴẶÂẦẤẨẪẬ");
      add(U'E', U"ÈÉẺẼẸÊỀẾỂỄỆ");
      add(U'I', U"ÌÍỈĨỊ");
      add(U'O', U"ÒÓỎÕỌÔỒỐỔỖỘƠỜỚỞỠỢ");
      add(U'U', U"ÙÚỦŨỤƯỪỨỬỮỰ");
      add(U'Y', U"ỲÝỶỸỴ");
      add(U'D', U"Đ");
      return map;
    }();
    return m;
  }

  // TCVN3 -> Unicode (đảo; ưu tiên thường vì TCVN3 chung byte hoa/thường).
  const std::unordered_map<char32_t, char32_t>& TcvnToUnicode() {
    static const std::unordered_map<char32_t, char32_t> m = [] {
      std::unordered_map<char32_t, char32_t> r;
      for (const auto& [uni, legacy] : kUnicodeToTcvn) {
        if (legacy.size() != 1) continue;
        char32_t key = legacy[0];
        auto it = r.find(key);
        if (it == r.end()) {
          r[key] = uni;
        } else {
          // giữ bản thường nếu đang là hoa
          bool existingUpper = (kVietLowerToUpper.count(it->second) == 0) &&
                               (VietUpperToLower().count(it->second) > 0);
          bool uniLower = VietUpperToLower().count(uni) == 0 &&
                          kVietLowerToUpper.count(uni) > 0;
          if (existingUpper && uniLower) r[key] = uni;
        }
      }
      return r;
    }();
    return m;
  }

  // VNI -> Unicode (đảo; khoá là chuỗi 1-2 ký tự).
  const std::unordered_map<std::u32string, char32_t>& VniToUnicode() {
    static const std::unordered_map<std::u32string, char32_t> m = [] {
      std::unordered_map<std::u32string, char32_t> r;
      for (const auto& [uni, legacy] : kUnicodeToVni) r[legacy] = uni;
      return r;
    }();
    return m;
  }

  std::u32string ToUnicode(const std::u32string& text, CodeTable from) {
    switch (from) {
      case CodeTable::Unicode:
        return text;
      case CodeTable::Tcvn3: {
        std::u32string out;
        for (char32_t ch : text) {
          auto it = TcvnToUnicode().find(ch);
          out.push_back(it != TcvnToUnicode().end() ? it->second : ch);
        }
        return out;
      }
      case CodeTable::VniWindows: {
        std::u32string out;
        size_t i = 0;
        while (i < text.size()) {
          bool matched = false;
          if (i + 1 < text.size()) {
            std::u32string two = text.substr(i, 2);
            auto it = VniToUnicode().find(two);
            if (it != VniToUnicode().end()) {
              out.push_back(it->second);
              i += 2;
              matched = true;
            }
          }
          if (!matched) {
            std::u32string one(1, text[i]);
            auto it = VniToUnicode().find(one);
            out.push_back(it != VniToUnicode().end() ? it->second : text[i]);
            ++i;
          }
        }
        return out;
      }
    }
    return text;
  }

  std::u32string FromUnicode(const std::u32string& text, CodeTable to) {
    switch (to) {
      case CodeTable::Unicode:
        return text;
      case CodeTable::Tcvn3: {
        std::u32string out;
        for (char32_t ch : text) {
          auto it = kUnicodeToTcvn.find(ch);
          if (it != kUnicodeToTcvn.end()) out += it->second; else out.push_back(ch);
        }
        return out;
      }
      case CodeTable::VniWindows: {
        std::u32string out;
        for (char32_t ch : text) {
          auto it = kUnicodeToVni.find(ch);
          if (it != kUnicodeToVni.end()) out += it->second; else out.push_back(ch);
        }
        return out;
      }
    }
    return text;
  }

  bool IsWhitespace(char32_t c) { return c == U' ' || c == U'\t' || c == U'\n' || c == U'\r'; }

}  // namespace

std::u32string TextConverter::RemoveDiacritics(const std::u32string& text) {
  std::u32string out;
  out.reserve(text.size());
  for (char32_t ch : text) {
    auto it = StripMap().find(ch);
    out.push_back(it != StripMap().end() ? it->second : ch);
  }
  return out;
}

std::u32string TextConverter::ChangeCase(const std::u32string& text, LetterCase mode) {
  if (mode == LetterCase::AllUpper) {
    std::u32string out;
    for (char32_t ch : text) out.push_back(VietUpper(ch));
    return out;
  }
  if (mode == LetterCase::AllLower) {
    std::u32string out;
    for (char32_t ch : text) out.push_back(VietLower(ch));
    return out;
  }
  // capitalizeFirst / capitalizeWords
  const bool eachWord = (mode == LetterCase::CapitalizeWords);
  static const std::u32string breaks = U".?!";
  std::u32string out;
  bool shouldUpper = true;
  bool pendingBreak = false;
  for (char32_t ch : text) {
    if (IsLetter(ch)) {
      out.push_back(shouldUpper ? VietUpper(ch) : VietLower(ch));
      shouldUpper = false;
      pendingBreak = false;
    } else {
      out.push_back(ch);
      if (eachWord) {
        if (IsWhitespace(ch)) shouldUpper = true;
      } else {
        if (ch == U'\n') {
          shouldUpper = true;
          pendingBreak = false;
        } else if (breaks.find(ch) != std::u32string::npos) {
          pendingBreak = true;
        } else if (IsWhitespace(ch)) {
          if (pendingBreak) shouldUpper = true;
          pendingBreak = false;
        } else {
          pendingBreak = false;
        }
      }
    }
  }
  return out;
}

std::u32string TextConverter::Convert(const std::u32string& text, CodeTable from, CodeTable to) {
  if (from == to) return text;
  return FromUnicode(ToUnicode(text, from), to);
}

}  // namespace bowgo
