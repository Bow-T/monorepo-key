// badge_icon.cpp — xem badge_icon.h.

#if defined(_WIN32)

#include "badge_icon.h"

#include <vector>

namespace bowgo {

namespace {

// Lưới glyph pixel 5 hàng — TRÙNG bản macOS (AppDelegate.pixelGlyphs) để đồng
// nhất phong cách. 1 = pixel bật.
struct Glyph {
    int width;
    const unsigned char (*rows)[5];  // [width] cột mỗi hàng, 5 hàng
};

// V, I, E, N (rộng 3 hoặc 4 cột).
const unsigned char kV[5][5] = {
    {1, 0, 1, 0, 0}, {1, 0, 1, 0, 0}, {1, 0, 1, 0, 0}, {1, 0, 1, 0, 0}, {0, 1, 0, 0, 0}};
const unsigned char kI[5][5] = {
    {1, 1, 1, 0, 0}, {0, 1, 0, 0, 0}, {0, 1, 0, 0, 0}, {0, 1, 0, 0, 0}, {1, 1, 1, 0, 0}};
const unsigned char kE[5][5] = {
    {1, 1, 1, 0, 0}, {1, 0, 0, 0, 0}, {1, 1, 0, 0, 0}, {1, 0, 0, 0, 0}, {1, 1, 1, 0, 0}};
const unsigned char kN[5][5] = {
    {1, 0, 0, 1, 0}, {1, 1, 0, 1, 0}, {1, 0, 1, 1, 0}, {1, 0, 0, 1, 0}, {1, 0, 0, 1, 0}};

// Trả glyph theo ký tự (chỉ V/I/E/N cần cho VI/EN).
bool GlyphFor(char c, int* width, const unsigned char (**rows)[5]) {
    switch (c) {
        case 'V': *width = 3; *rows = kV; return true;
        case 'I': *width = 3; *rows = kI; return true;
        case 'E': *width = 3; *rows = kE; return true;
        case 'N': *width = 4; *rows = kN; return true;
        default: return false;
    }
}

// Bật một pixel màu trắng (kênh alpha 255) tại (x,y) trong đệm BGRA.
void PutWhite(std::vector<DWORD>& px, int side, int x, int y) {
    if (x < 0 || y < 0 || x >= side || y >= side) return;
    px[y * side + x] = 0xFFFFFFFF;  // ARGB: trắng đục
}

}  // namespace

HICON CreateBadgeIcon(bool vietnamese, int side) {
    if (side < 8) side = 8;

    // Đệm màu BGRA (premultiplied alpha) cho bitmap 32-bit top-down.
    std::vector<DWORD> pixels(static_cast<size_t>(side) * side, 0);

    // Màu nền badge (ARGB đục). VI = xanh grass #5DA130; EN = xám.
    DWORD bg = vietnamese ? 0xFF5DA130 : 0xFF999999;

    // Nền bo góc đơn giản: bỏ 4 pixel góc để trông "bo" (đủ với icon nhỏ).
    for (int y = 0; y < side; ++y) {
        for (int x = 0; x < side; ++x) {
            bool corner =
                (x == 0 && y == 0) || (x == side - 1 && y == 0) ||
                (x == 0 && y == side - 1) || (x == side - 1 && y == side - 1);
            if (!corner) pixels[y * side + x] = bg;
        }
    }

    // Hai glyph: "VI" hoặc "EN".
    const char* text = vietnamese ? "VI" : "EN";
    int widths[2];
    const unsigned char (*rows[2])[5];
    int totalCols = 0;
    for (int i = 0; i < 2; ++i) {
        GlyphFor(text[i], &widths[i], &rows[i]);
        totalCols += widths[i];
    }
    totalCols += 1;  // 1 cột trống giữa 2 glyph
    const int glyphH = 5;

    // Kích thước ô pixel: vừa trong badge, chừa lề 2px mỗi chiều.
    const int pad = 2;
    int innerW = side - pad * 2;
    int innerH = side - pad * 2;
    int cell = innerW / totalCols;
    int cellH = innerH / glyphH;
    if (cellH < cell) cell = cellH;
    if (cell < 1) cell = 1;

    int usedW = cell * totalCols;
    int usedH = cell * glyphH;
    int ox = (side - usedW) / 2;
    int oy = (side - usedH) / 2;

    // Vẽ từng glyph (trắng), hàng 0 ở đỉnh.
    int colBase = 0;
    for (int i = 0; i < 2; ++i) {
        for (int r = 0; r < glyphH; ++r) {
            for (int c = 0; c < widths[i]; ++c) {
                if (rows[i][r][c]) {
                    for (int dy = 0; dy < cell; ++dy) {
                        for (int dx = 0; dx < cell; ++dx) {
                            PutWhite(pixels, side, ox + (colBase + c) * cell + dx,
                                     oy + r * cell + dy);
                        }
                    }
                }
            }
        }
        colBase += widths[i] + 1;
    }

    // Dựng HICON từ đệm BGRA (bitmap màu + mask AND rỗng vì đã dùng alpha).
    BITMAPV5HEADER bi = {};
    bi.bV5Size = sizeof(BITMAPV5HEADER);
    bi.bV5Width = side;
    bi.bV5Height = -side;  // top-down
    bi.bV5Planes = 1;
    bi.bV5BitCount = 32;
    bi.bV5Compression = BI_BITFIELDS;
    bi.bV5RedMask = 0x00FF0000;
    bi.bV5GreenMask = 0x0000FF00;
    bi.bV5BlueMask = 0x000000FF;
    bi.bV5AlphaMask = 0xFF000000;

    HDC hdc = GetDC(nullptr);
    void* bits = nullptr;
    HBITMAP color = CreateDIBSection(hdc, reinterpret_cast<BITMAPINFO*>(&bi),
                                     DIB_RGB_COLORS, &bits, nullptr, 0);
    ReleaseDC(nullptr, hdc);
    if (!color || !bits) {
        if (color) DeleteObject(color);
        return nullptr;
    }
    memcpy(bits, pixels.data(), pixels.size() * sizeof(DWORD));

    // Mask AND toàn 0 (icon 32-bit dùng alpha; CreateBitmap với nullptr KHÔNG
    // bảo đảm zero -> tự cấp đệm 0 để chắc chắn).
    std::vector<BYTE> zero_mask(static_cast<size_t>(((side + 31) / 32) * 4) * side, 0);
    HBITMAP mask = CreateBitmap(side, side, 1, 1, zero_mask.data());

    ICONINFO ii = {};
    ii.fIcon = TRUE;
    ii.hbmColor = color;
    ii.hbmMask = mask;
    HICON icon = CreateIconIndirect(&ii);

    DeleteObject(color);
    if (mask) DeleteObject(mask);
    return icon;
}

}  // namespace bowgo

#endif  // _WIN32
