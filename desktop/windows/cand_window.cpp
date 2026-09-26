#include "cand_window.h"

#include <dwmapi.h>

#include <algorithm>
#include <string>

#include "../core/composer.h"
#include "globals.h"

namespace shunti {
namespace win {

namespace {
constexpr wchar_t CLASS_NAME[] = L"ShuntiImeCandidates";

struct Colors { COLORREF bg, border, text, sub, sel_bg, sel_text, accent; };
// Android 版・HarmonyOS 版の色 (LIGHT_THEME・DARK_THEME) に合わせる
Colors colors() {
    if (apps_dark()) return {RGB(0x2A, 0x2A, 0x2A), RGB(0x41, 0x41, 0x41), RGB(0xF2, 0xF2, 0xF7), RGB(0x9A, 0x9A, 0xA0),
                             RGB(0x27, 0x40, 0x70), RGB(0xFF, 0xFF, 0xFF), RGB(0x5B, 0x9B, 0xFF)};
    return {RGB(0xFB, 0xFB, 0xFC), RGB(0xD7, 0xD8, 0xDB), RGB(0x1C, 0x1C, 0x1E), RGB(0x7A, 0x7F, 0x87),
            RGB(0xDC, 0xE7, 0xFD), RGB(0x1C, 0x1C, 0x1E), RGB(0x1E, 0x54, 0xC7)};
}

const wchar_t* W(const u16& s) { return reinterpret_cast<const wchar_t*>(s.c_str()); }

bool register_class() {
    static bool done = false;
    if (done) return true;
    WNDCLASSEXW wc = {sizeof wc};
    wc.style = CS_IME | CS_DROPSHADOW;
    wc.lpfnWndProc = DefWindowProcW;   // 作ったあとで CandWindow::proc に差し替える
    wc.hInstance = g_inst;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.lpszClassName = CLASS_NAME;
    done = RegisterClassExW(&wc) != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
    return done;
}
}  // namespace

CandWindow::~CandWindow() { destroy(); }

void CandWindow::destroy() {
    if (hwnd_) DestroyWindow(hwnd_);
    hwnd_ = nullptr;
    if (font_) DeleteObject(font_);
    if (small_) DeleteObject(small_);
    font_ = small_ = nullptr;
    dpi_ = 0;
}

void CandWindow::hide() {
    if (hwnd_) ShowWindow(hwnd_, SW_HIDE);
}

LRESULT CALLBACK CandWindow::proc(HWND h, UINT m, WPARAM w, LPARAM l) {
    auto* self = reinterpret_cast<CandWindow*>(GetWindowLongPtrW(h, GWLP_USERDATA));
    switch (m) {
        case WM_MOUSEACTIVATE:
            return MA_NOACTIVATE;   // 触っても入力欄からフォーカスを奪わない
        case WM_PAINT: {
            PAINTSTRUCT ps;
            HDC dc = BeginPaint(h, &ps);
            if (self) self->paint(dc);
            EndPaint(h, &ps);
            return 0;
        }
        case WM_ERASEBKGND:
            return 1;
        case WM_LBUTTONUP:
            if (self && self->on_click) {
                int i = self->hit(short(LOWORD(l)), short(HIWORD(l)));
                if (i >= 0) self->on_click(i);
            }
            return 0;
        default:
            break;
    }
    return DefWindowProcW(h, m, w, l);
}

void CandWindow::show(const std::vector<u16>& cands, int sel, const RECT& anchor, HWND owner) {
    if (cands.empty()) { hide(); return; }
    if (!register_class()) return;
    if (!hwnd_ || owner_ != owner) {
        if (hwnd_) DestroyWindow(hwnd_);
        owner_ = owner;
        hwnd_ = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, CLASS_NAME, L"", WS_POPUP, 0, 0, 1, 1,
                                owner, nullptr, g_inst, nullptr);
        if (!hwnd_) return;
        SetWindowLongPtrW(hwnd_, GWLP_USERDATA, LONG_PTR(this));
        SetWindowLongPtrW(hwnd_, GWLP_WNDPROC, LONG_PTR(&CandWindow::proc));
        DWORD corner = 3;   // DWMWCP_ROUNDSMALL (Windows 11 の角の丸み)
        DwmSetWindowAttribute(hwnd_, 33 /* DWMWA_WINDOW_CORNER_PREFERENCE */, &corner, sizeof corner);
    }
    UINT dpi = owner ? GetDpiForWindow(owner) : 96;
    if (!dpi) dpi = GetDpiForSystem();
    if (dpi != dpi_) {
        if (font_) DeleteObject(font_);
        if (small_) DeleteObject(small_);
        dpi_ = dpi;
        font_ = CreateFontW(-MulDiv(16, int(dpi), 96), 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Yu Gothic UI");
        small_ = CreateFontW(-MulDiv(12, int(dpi), 96), 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Yu Gothic UI");
    }
    cands_ = cands;
    sel_ = std::clamp(sel, -1, int(cands.size()) - 1);   // -1 = まだ選んでいない (打っている間の候補)
    page_ = std::max(sel_, 0) / Composer::PAGE;
    layout();

    // 文節の下に出す (候補の字の頭を文節の頭にそろえる)。画面の下に入らなければ上に
    HMONITOR mon = MonitorFromRect(&anchor, MONITOR_DEFAULTTONEAREST);
    MONITORINFO mi = {sizeof mi};
    GetMonitorInfoW(mon, &mi);
    RECT wa = mi.rcWork;
    int x = anchor.left - pad_ - num_w_;
    int y = anchor.bottom + MulDiv(2, int(dpi_), 96);
    if (y + height_ > wa.bottom) y = anchor.top - height_ - MulDiv(2, int(dpi_), 96);
    x = std::max(int(wa.left), std::min(x, int(wa.right) - width_));
    y = std::max(int(wa.top), y);
    SetWindowPos(hwnd_, HWND_TOPMOST, x, y, width_, height_, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    InvalidateRect(hwnd_, nullptr, FALSE);
}

void CandWindow::layout() {
    HDC dc = GetDC(hwnd_);
    HGDIOBJ old = SelectObject(dc, font_);
    TEXTMETRICW tm;
    GetTextMetricsW(dc, &tm);
    row_h_ = tm.tmHeight + MulDiv(8, int(dpi_), 96);
    pad_ = MulDiv(8, int(dpi_), 96);
    SIZE sz;
    GetTextExtentPoint32W(dc, L"9", 1, &sz);
    num_w_ = sz.cx + MulDiv(12, int(dpi_), 96);
    int text_w = MulDiv(120, int(dpi_), 96);
    int start = page_ * Composer::PAGE;
    int end = std::min(int(cands_.size()), start + Composer::PAGE);
    for (int i = start; i < end; i++) {
        GetTextExtentPoint32W(dc, W(cands_[size_t(i)]), int(cands_[size_t(i)].size()), &sz);
        text_w = std::max(text_w, int(sz.cx));
    }
    text_w = std::min(text_w, MulDiv(640, int(dpi_), 96));
    SelectObject(dc, small_);
    GetTextMetricsW(dc, &tm);
    footer_h_ = tm.tmHeight + MulDiv(6, int(dpi_), 96);
    SelectObject(dc, old);
    ReleaseDC(hwnd_, dc);
    width_ = pad_ + num_w_ + text_w + pad_ * 2;
    height_ = pad_ / 2 + row_h_ * (end - start) + footer_h_;
}

int CandWindow::hit(int x, int y) const {
    (void)x;
    int start = page_ * Composer::PAGE;
    int row = (y - pad_ / 2) / std::max(1, row_h_);
    int n = std::min(int(cands_.size()) - start, Composer::PAGE);
    if (y < pad_ / 2 || row < 0 || row >= n) return -1;
    return start + row;
}

void CandWindow::paint(HDC wdc) {
    Colors c = colors();
    RECT rc = {0, 0, width_, height_};
    // ちらつかないように裏で描いてから写す
    HDC dc = CreateCompatibleDC(wdc);
    HBITMAP bmp = CreateCompatibleBitmap(wdc, width_, height_);
    HGDIOBJ oldb = SelectObject(dc, bmp);
    HBRUSH bg = CreateSolidBrush(c.bg);
    FillRect(dc, &rc, bg);
    DeleteObject(bg);
    HBRUSH border = CreateSolidBrush(c.border);
    FrameRect(dc, &rc, border);
    DeleteObject(border);
    SetBkMode(dc, TRANSPARENT);

    int start = page_ * Composer::PAGE;
    int end = std::min(int(cands_.size()), start + Composer::PAGE);
    HGDIOBJ oldf = SelectObject(dc, font_);
    for (int i = start; i < end; i++) {
        int top = pad_ / 2 + (i - start) * row_h_;
        RECT row = {MulDiv(3, int(dpi_), 96), top, width_ - MulDiv(3, int(dpi_), 96), top + row_h_};
        bool selected = i == sel_;
        if (selected) {
            HBRUSH sb = CreateSolidBrush(c.sel_bg);
            HGDIOBJ ob = SelectObject(dc, sb);
            HGDIOBJ op = SelectObject(dc, GetStockObject(NULL_PEN));
            int r = MulDiv(8, int(dpi_), 96);
            RoundRect(dc, row.left, row.top + 1, row.right, row.bottom - 1, r, r);
            SelectObject(dc, op);
            SelectObject(dc, ob);
            DeleteObject(sb);
        }
        wchar_t num[4] = {wchar_t(L'1' + (i - start)), 0};
        RECT nr = {pad_, top, pad_ + num_w_, top + row_h_};
        SetTextColor(dc, selected ? c.accent : c.sub);
        DrawTextW(dc, num, 1, &nr, DT_SINGLELINE | DT_VCENTER | DT_LEFT | DT_NOPREFIX);
        RECT tr = {pad_ + num_w_, top, width_ - pad_, top + row_h_};
        SetTextColor(dc, selected ? c.sel_text : c.text);
        const u16& s = cands_[size_t(i)];
        DrawTextW(dc, W(s), int(s.size()), &tr, DT_SINGLELINE | DT_VCENTER | DT_LEFT | DT_NOPREFIX | DT_END_ELLIPSIS);
    }
    SelectObject(dc, small_);
    std::wstring foot = sel_ < 0 ? L"Tab で選ぶ  " + std::to_wstring(cands_.size()) + L" 件"
                                 : std::to_wstring(sel_ + 1) + L" / " + std::to_wstring(cands_.size());
    RECT fr = {pad_, height_ - footer_h_, width_ - pad_, height_ - MulDiv(3, int(dpi_), 96)};
    SetTextColor(dc, c.sub);
    DrawTextW(dc, foot.c_str(), int(foot.size()), &fr, DT_SINGLELINE | DT_VCENTER | DT_RIGHT | DT_NOPREFIX);
    SelectObject(dc, oldf);

    BitBlt(wdc, 0, 0, width_, height_, dc, 0, 0, SRCCOPY);
    SelectObject(dc, oldb);
    DeleteObject(bmp);
    DeleteDC(dc);
}

}  // namespace win
}  // namespace shunti
