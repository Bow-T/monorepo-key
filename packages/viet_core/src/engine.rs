//! Bộ não bộ gõ: nhận từng phím, giữ âm tiết đang gõ (chữ gốc + dấu biến âm + dấu
//! thanh) và dựng chuỗi hiển thị. Port từ apps/macos_ime/Sources/VietEngine/Engine.swift;
//! bộ ca chuẩn packages/viet_engine/spec/typing_cases.tsv là spec chung với bản Dart.

use crate::table::{compose, low, Mark, Tone};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum InputMethod {
    Telex,
    Vni,
}

/// Kiểu đặt dấu: modern (hoà, khoẻ) hoặc old (hòa, khỏe).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum ToneStyle {
    Modern,
    Old,
}

#[derive(Clone, Copy)]
struct Letter {
    base: char,
    mark: Mark,
}

impl Letter {
    fn new(base: char) -> Self {
        Letter { base, mark: Mark::None }
    }
}

/// Kết quả khi thử coi một phím là phím-dấu.
enum Diacritic {
    /// Đã áp dấu/biến âm.
    Applied,
    /// Gõ lại trùng dấu -> đã GỠ dấu; phím hiện ra như chữ thường.
    Cancelled,
    /// Không phải phím-dấu -> nối như chữ thường.
    Plain,
}

/// Tổ hợp phụ âm đầu không có trong tiếng Việt (blue, clear, print...): âm tiết mở đầu
/// bằng một cụm này là từ phi-Việt, không áp dấu. Không có cụm chứa 'w' (tw/sw là gõ tắt).
const NON_VIET_INITIAL_CLUSTERS: [[char; 2]; 18] = [
    ['b', 'l'], ['b', 'r'], ['c', 'l'], ['c', 'r'], ['d', 'r'], ['f', 'l'], ['f', 'r'],
    ['g', 'l'], ['g', 'r'], ['p', 'l'], ['p', 'r'], ['s', 'c'], ['s', 'k'], ['s', 'l'],
    ['s', 'm'], ['s', 'n'], ['s', 'p'], ['s', 't'],
];

fn is_viet_vowel(c: char) -> bool {
    matches!(low(c), 'a' | 'e' | 'i' | 'o' | 'u' | 'y')
}

pub struct Engine {
    method: InputMethod,
    tone_style: ToneStyle,
    letters: Vec<Letter>,
    tone: Tone,
    /// Phím thô của âm tiết hiện tại — để dựng lại (replay) khi Backspace.
    raw_keys: Vec<char>,
}

impl Engine {
    pub fn new(method: InputMethod, tone_style: ToneStyle) -> Self {
        Engine { method, tone_style, letters: Vec::new(), tone: Tone::None, raw_keys: Vec::new() }
    }

    /// Phím `ch` có thuộc âm tiết không (chữ cái; với VNI thêm chữ số khi đã có âm tiết).
    /// Sai thì `process` sẽ chốt âm tiết và trả None.
    pub fn is_word_char(&self, ch: char) -> bool {
        ch.is_alphabetic() || (self.method == InputMethod::Vni && ch.is_numeric() && !self.letters.is_empty())
    }

    /// Nhận một phím. Trả chuỗi hiển thị của âm tiết, hoặc None nếu phím ngắt từ
    /// (caller xuất phím nguyên bản và bắt đầu âm tiết mới).
    pub fn process(&mut self, ch: char) -> Option<String> {
        if self.is_word_char(ch) {
            self.raw_keys.push(ch);
        }
        self.step(ch)
    }

    /// Xoá 1 phím thô cuối rồi dựng lại âm tiết từ đầu. None nếu buffer đã rỗng
    /// (caller để Backspace đi qua).
    pub fn backspace(&mut self) -> Option<String> {
        self.raw_keys.pop()?;
        self.reset_syllable();
        let keys = std::mem::take(&mut self.raw_keys);
        let mut current = String::new();
        for key in keys {
            self.raw_keys.push(key);
            current = self.step(key).unwrap_or_default();
        }
        Some(current)
    }

    /// Reset thủ công (con trỏ nhảy chỗ, click chuột...).
    pub fn clear(&mut self) {
        self.reset_syllable();
        self.raw_keys.clear();
    }

    /// Chuỗi hiển thị của âm tiết, dấu thanh đặt lên nguyên âm theo chính tả.
    pub fn render(&self) -> String {
        let tone_index = self.tone_target_index();
        self.letters
            .iter()
            .enumerate()
            .map(|(i, l)| {
                let tone = if Some(i) == tone_index { self.tone } else { Tone::None };
                compose(l.base, l.mark, tone).unwrap_or(l.base)
            })
            .collect()
    }

    fn reset_syllable(&mut self) {
        self.letters.clear();
        self.tone = Tone::None;
    }

    /// Một bước xử lý thuần (không ghi raw_keys) — replay dùng lại được.
    fn step(&mut self, ch: char) -> Option<String> {
        if !self.is_word_char(ch) {
            self.clear();
            return None;
        }
        match self.apply_as_diacritic(ch) {
            Diacritic::Applied => {}
            // Gõ lại để bỏ dấu ("hoaf"+"f" -> "hoaf"): phím hiện ra như chữ thường.
            Diacritic::Cancelled => self.letters.push(Letter::new(ch)),
            Diacritic::Plain => {
                self.letters.push(Letter::new(ch));
                self.propagate_uo_horn();
            }
        }
        Some(self.render())
    }

    /// Lan móc trên "uo" -> "ươ" khi gặp âm đóng {n,c,i,m,p,t} ngay sau và đúng MỘT
    /// trong u/o đang có móc ("tưon" -> "tươn"; không đụng "huow" đang gõ dở).
    fn propagate_uo_horn(&mut self) {
        let n = self.letters.len();
        if n < 3 || !matches!(low(self.letters[n - 1].base), 'n' | 'c' | 'i' | 'm' | 'p' | 't') {
            return;
        }
        if low(self.letters[n - 3].base) != 'u' || low(self.letters[n - 2].base) != 'o' {
            return;
        }
        if (self.letters[n - 3].mark == Mark::Horn) != (self.letters[n - 2].mark == Mark::Horn) {
            self.letters[n - 3].mark = Mark::Horn;
            self.letters[n - 2].mark = Mark::Horn;
        }
    }

    // MARK: - Áp dụng phím-dấu

    /// Có mở đầu bằng cụm phụ âm phi-Việt không, khi xét thêm phím `ch`: đã có ≥2 chữ
    /// thì xét 2 chữ đầu; mới 1 chữ thì xét chữ đó + `ch`.
    fn starts_with_non_viet_cluster(&self, ch: char) -> bool {
        let pair = match self.letters.as_slice() {
            [] => return false,
            [a] => [low(a.base), low(ch)],
            [a, b, ..] => [low(a.base), low(b.base)],
        };
        NON_VIET_INITIAL_CLUSTERS.contains(&pair)
    }

    fn apply_as_diacritic(&mut self, ch: char) -> Diacritic {
        if self.starts_with_non_viet_cluster(ch) {
            return Diacritic::Plain;
        }
        match self.method {
            InputMethod::Telex => self.apply_telex(ch),
            InputMethod::Vni => self.apply_vni(ch),
        }
    }

    fn apply_telex(&mut self, ch: char) -> Diacritic {
        let lower = low(ch);
        match lower {
            's' => self.set_tone(Tone::Acute),
            'f' => self.set_tone(Tone::Grave),
            'r' => self.set_tone(Tone::Hook),
            'x' => self.set_tone(Tone::Tilde),
            'j' => self.set_tone(Tone::Dot),
            'z' => self.set_tone(Tone::None),
            'a' | 'e' | 'o' => self.apply_circumflex_repeat(lower),
            'w' => {
                // ww -> w: phím trước cũng là w và trước nó không có nguyên âm -> 'ư' do
                // w gõ tắt tạo ra trở về 'w' thô. Có nguyên âm (uww, oww) thì gỡ móc/trăng.
                let n = self.raw_keys.len();
                let consecutive_w = n >= 2 && low(self.raw_keys[n - 2]) == 'w';
                let vowel_before_prev_w = n >= 3 && matches!(low(self.raw_keys[n - 3]), 'u' | 'o' | 'a');
                if consecutive_w && !vowel_before_prev_w {
                    if let Some(last) = self.letters.last_mut() {
                        if last.mark == Mark::Horn && (last.base == 'u' || last.base == 'U') {
                            *last = Letter::new(ch);
                            return Diacritic::Applied;
                        }
                    }
                }
                self.apply_horn_to_nucleus(true).unwrap_or_else(|| self.insert_standalone_w())
            }
            'd' => match self.letters.last() {
                Some(last) if low(last.base) == 'd' && last.mark == Mark::Dyet => self.remove_mark_on_last(),
                Some(last) if low(last.base) == 'd' && last.mark == Mark::None => self.set_mark_on_last(Mark::Dyet),
                _ => Diacritic::Plain,
            },
            _ => Diacritic::Plain,
        }
    }

    /// Lặp a/e/o: lần gõ thứ 2 trong run tạo mũ (aa->â, asa->ấ), lần 3 gỡ mũ (aaa->aa),
    /// từ lần 4 kéo dài thô (aaaa->aaa). Phím-thanh xen giữa không phá run.
    fn apply_circumflex_repeat(&mut self, lower: char) -> Diacritic {
        let Some(last) = self.letters.last().copied() else {
            return Diacritic::Plain;
        };
        if low(last.base) != lower {
            return Diacritic::Plain;
        }
        match last.mark {
            Mark::Circumflex => self.remove_mark_on_last(),
            Mark::None
                if self.trailing_vowel_press_count(lower) == 2
                    && compose(last.base, Mark::Circumflex, Tone::None).is_some() =>
            {
                self.set_mark_on_last(Mark::Circumflex)
            }
            _ => Diacritic::Plain,
        }
    }

    /// Số lần nguyên âm `lower` được gõ trong run cuối của raw_keys, bỏ qua phím-thanh
    /// xen giữa ("casa" -> 2, "asaa" -> 3).
    fn trailing_vowel_press_count(&self, lower: char) -> usize {
        let mut n = 0;
        for &key in self.raw_keys.iter().rev() {
            let k = low(key);
            if k == lower {
                n += 1;
            } else if !matches!(k, 's' | 'f' | 'r' | 'x' | 'j' | 'z') {
                break;
            }
        }
        n
    }

    fn apply_vni(&mut self, ch: char) -> Diacritic {
        match ch {
            '1' => self.set_tone(Tone::Acute),
            '2' => self.set_tone(Tone::Grave),
            '3' => self.set_tone(Tone::Hook),
            '4' => self.set_tone(Tone::Tilde),
            '5' => self.set_tone(Tone::Dot),
            '0' => self.set_tone(Tone::None),
            '6' => self.set_mark_on_nucleus(Mark::Circumflex).unwrap_or(Diacritic::Plain),
            '7' => self.apply_horn_to_nucleus(false).unwrap_or(Diacritic::Plain),
            '8' => self.set_mark_on_nucleus(Mark::Breve).unwrap_or(Diacritic::Plain),
            '9' => match self.letters.last() {
                Some(last) if last.mark == Mark::Dyet => self.remove_mark_on_last(),
                _ => self.set_mark_on_last(Mark::Dyet),
            },
            _ => Diacritic::Plain,
        }
    }

    /// Cụm nguyên âm (start, end) quét ngược qua phụ âm cuối — để dấu gõ SAU phụ âm
    /// cuối vẫn đặt đúng ("đuoc"+w -> "đươc"). None nếu chưa có nguyên âm.
    fn vowel_nucleus_range(&self) -> Option<(usize, usize)> {
        let end = self.letters.iter().rposition(|l| is_viet_vowel(l.base))?;
        let mut start = end;
        while start > 0 && is_viet_vowel(self.letters[start - 1].base) {
            start -= 1;
        }
        Some((start, end))
    }

    /// Bỏ 'u' sau 'q' và 'i' sau 'g' (bán phụ âm của phụ âm đầu) khỏi đầu cụm.
    fn skip_qu_gi(&self, start: usize) -> usize {
        if start == 0 {
            return start;
        }
        match (low(self.letters[start - 1].base), low(self.letters[start].base)) {
            ('q', 'u') | ('g', 'i') => start + 1,
            _ => start,
        }
    }

    /// Đặt móc (và trăng nếu `allow_breve`) lên cụm nguyên âm. None nếu không áp được
    /// (Telex -> gõ tắt 'ư', VNI -> giữ số thô).
    fn apply_horn_to_nucleus(&mut self, allow_breve: bool) -> Option<Diacritic> {
        let (vs, ve) = self.vowel_nucleus_range()?;
        if ve > vs {
            let a = low(self.letters[vs].base);
            let b = low(self.letters[vs + 1].base);
            let part_of_qu = vs >= 1 && low(self.letters[vs - 1].base) == 'q';
            if a == 'u' && b == 'o' && !part_of_qu {
                // "thuo": luôn móc 'o', móc thêm 'u' khi có phụ âm cuối (thương / thuở).
                let is_thuo = vs >= 2 && low(self.letters[vs - 2].base) == 't' && low(self.letters[vs - 1].base) == 'h';
                if is_thuo {
                    if self.letters[vs + 1].mark == Mark::Horn {
                        self.letters[vs].mark = Mark::None;
                        self.letters[vs + 1].mark = Mark::None;
                        return Some(Diacritic::Cancelled);
                    }
                    self.letters[vs + 1].mark = Mark::Horn;
                    if ve < self.letters.len() - 1 {
                        self.letters[vs].mark = Mark::Horn;
                    }
                    return Some(Diacritic::Applied);
                }
                if self.letters[vs].mark == Mark::Horn && self.letters[vs + 1].mark == Mark::Horn {
                    self.letters[vs].mark = Mark::None;
                    self.letters[vs + 1].mark = Mark::None;
                    return Some(Diacritic::Cancelled);
                }
                self.letters[vs].mark = Mark::Horn;
                self.letters[vs + 1].mark = Mark::Horn;
                return Some(Diacritic::Applied);
            }
            if a == 'u' && b == 'a' && !part_of_qu {
                if self.letters[vs].mark == Mark::Horn {
                    self.letters[vs].mark = Mark::None;
                    return Some(Diacritic::Cancelled);
                }
                self.letters[vs].mark = Mark::Horn;
                return Some(Diacritic::Applied);
            }
        }

        // Một nguyên âm nhận móc/trăng: nguyên âm hợp lệ gần cuối cụm nhất.
        let start = self.skip_qu_gi(vs);
        let allowed: &[char] = if allow_breve { &['a', 'o', 'u'] } else { &['o', 'u'] };
        let target = (start..=ve).rev().find(|&i| allowed.contains(&low(self.letters[i].base)))?;
        let mark = if low(self.letters[target].base) == 'a' { Mark::Breve } else { Mark::Horn };
        Some(if self.letters[target].mark == mark { self.remove_mark_at(target) } else { self.set_mark_at(mark, target) })
    }

    /// VNI 6/8: mũ/trăng lên nguyên âm gần cuối cụm nhận được mark ("muoi"+6 -> "muôi").
    /// Chữ đích đã mang đúng mark -> gỡ + số thô. None nếu không chữ nào nhận được.
    fn set_mark_on_nucleus(&mut self, mark: Mark) -> Option<Diacritic> {
        let (vs, ve) = self.vowel_nucleus_range()?;
        let start = self.skip_qu_gi(vs);
        let target = (start..=ve).rev().find(|&i| compose(self.letters[i].base, mark, Tone::None).is_some())?;
        Some(if self.letters[target].mark == mark { self.remove_mark_at(target) } else { self.set_mark_at(mark, target) })
    }

    /// Gõ tắt 'w' -> 'ư' khi không áp được móc/trăng; giữ 'w' thô sau w/e/y/f/j/k/z.
    fn insert_standalone_w(&mut self) -> Diacritic {
        if let Some(last) = self.letters.last() {
            if matches!(low(last.base), 'w' | 'e' | 'y' | 'f' | 'j' | 'k' | 'z') {
                return Diacritic::Plain;
            }
        }
        self.letters.push(Letter { base: 'u', mark: Mark::Horn });
        Diacritic::Applied
    }

    // MARK: - Thao tác trên âm tiết

    fn set_tone(&mut self, tone: Tone) -> Diacritic {
        // Chưa có nguyên âm thì phím-thanh là phụ âm thường ('r' trong "tre", 's' trong "sai").
        if !self.letters.iter().any(|l| is_viet_vowel(l.base)) {
            return Diacritic::Plain;
        }
        if self.tone == tone && tone != Tone::None {
            self.tone = Tone::None;
            return Diacritic::Cancelled;
        }
        self.tone = tone;
        Diacritic::Applied
    }

    fn set_mark_on_last(&mut self, mark: Mark) -> Diacritic {
        match self.letters.len() {
            0 => Diacritic::Plain,
            n => self.set_mark_at(mark, n - 1),
        }
    }

    fn remove_mark_on_last(&mut self) -> Diacritic {
        match self.letters.len() {
            0 => Diacritic::Plain,
            n => self.remove_mark_at(n - 1),
        }
    }

    fn set_mark_at(&mut self, mark: Mark, i: usize) -> Diacritic {
        if compose(self.letters[i].base, mark, Tone::None).is_none() {
            return Diacritic::Plain;
        }
        self.letters[i].mark = mark;
        Diacritic::Applied
    }

    fn remove_mark_at(&mut self, i: usize) -> Diacritic {
        self.letters[i].mark = Mark::None;
        Diacritic::Cancelled
    }

    /// Nguyên âm nhận dấu thanh:
    ///   1. nguyên âm mang mũ/trăng/móc;
    ///   2. có phụ âm cuối -> nguyên âm cuối cụm;
    ///   3. cụm hở 2 nguyên âm -> nguyên âm đầu, trừ oa/oe/uy (modern) -> nguyên âm sau;
    ///      3 nguyên âm -> nguyên âm giữa;
    ///   4. 1 nguyên âm -> chính nó.
    fn tone_target_index(&self) -> Option<usize> {
        if let Some(i) = self
            .letters
            .iter()
            .rposition(|l| matches!(l.mark, Mark::Circumflex | Mark::Breve | Mark::Horn))
        {
            return Some(i);
        }

        let mut vowels: Vec<usize> = (0..self.letters.len()).filter(|&i| is_viet_vowel(self.letters[i].base)).collect();
        // Kéo dài nguyên âm: gộp nguyên âm trùng liên tiếp về chữ đầu ("oiii" tính như "oi").
        vowels.dedup_by(|cur, prev| low(self.letters[*cur].base) == low(self.letters[*prev].base));
        // "gi"/"qu": 'i'/'u' là bán phụ âm, bỏ khỏi cụm khi còn nguyên âm khác ("già", "quà").
        if vowels.len() >= 2 && self.skip_qu_gi(vowels[0]) != vowels[0] {
            vowels.remove(0);
        }

        let (&start, &end) = (vowels.first()?, vowels.last()?);
        let has_final_consonant = end + 1 < self.letters.len() && !is_viet_vowel(self.letters[end + 1].base);
        if has_final_consonant {
            return Some(end);
        }
        match vowels.len() {
            1 => Some(start),
            2 => {
                if self.tone_style == ToneStyle::Old {
                    return Some(start);
                }
                let open_tail = matches!(
                    (low(self.letters[start].base), low(self.letters[end].base)),
                    ('o', 'a') | ('o', 'e') | ('u', 'y')
                );
                Some(if open_tail { end } else { start })
            }
            _ => Some(vowels[1]),
        }
    }
}
