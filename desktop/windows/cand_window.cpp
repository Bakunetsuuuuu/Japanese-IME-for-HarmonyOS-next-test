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
Colors colors(const std::string& theme) {
    if (theme == "dark" || (theme != "light" && apps_dark())) return {RGB(0x2A, 0x2A, 0x2A), RGB(0x41, 0x41, 0x41), RGB(0xF2, 0xF2, 0xF7), RGB(0x9A, 0x9A, 0xA0),
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
            if (self && self->on_sugg_click) {
                int i = self->hit_sugg(short(LOWORD(l)), short(HIWORD(l)));
                if (i >= 0) { self->on_sugg_click(i); return 0; }
            }
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

void CandWindow::show(const std::vector<u16>& cands, int sel, const RECT& anchor, HWND owner, const std::vector<u16>& sugg,
                      int sugg_sel, const std::vector<u16>& notes) {
    notes_ = notes;
    if (cands.empty() && sugg.empty()) { hide(); return; }
    sugg_sel_ = sugg_sel;
    sugg_ = sugg;
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
    // いちばん下の行: 左に「提案 Shift+↓」+ 札 (小さい字)、右に「Tab で選ぶ n 件」。幅が足りなければ窓を広げる (640 まで)
    sugg_x_.clear();
    int foot_need = 0;
    SelectObject(dc, small_);
    TEXTMETRICW st;
    GetTextMetricsW(dc, &st);
    const int pill_h = st.tmHeight + MulDiv(10, int(dpi_), 96);
    SelectObject(dc, font_);
    if (!sugg_.empty()) {
        SelectObject(dc, small_);
        SIZE lz, fz;
        const std::wstring label = sugg_label();
        GetTextExtentPoint32W(dc, label.c_str(), int(label.size()), &lz);
        const std::wstring foot = foot_text(int(cands_.size()));
        GetTextExtentPoint32W(dc, foot.c_str(), int(foot.size()), &fz);
        int x = pad_ + lz.cx + MulDiv(8, int(dpi_), 96);
        for (auto& s : sugg_) {
            SIZE z;
            GetTextExtentPoint32W(dc, W(s), int(s.size()), &z);
            int w = z.cx + MulDiv(14, int(dpi_), 96);
            sugg_x_.push_back({x, x + w});
            x += w + MulDiv(6, int(dpi_), 96);
        }
        foot_need = x + MulDiv(10, int(dpi_), 96) + fz.cx + pad_;
        text_w = std::max(text_w, foot_need - pad_ * 3 - num_w_);
        SelectObject(dc, font_);
    }
    int start = page_ * Composer::PAGE;
    int end = std::min(int(cands_.size()), start + Composer::PAGE);
    for (int i = start; i < end; i++) {
        GetTextExtentPoint32W(dc, W(cands_[size_t(i)]), int(cands_[size_t(i)].size()), &sz);
        int nw = 0;   // 右に添える種類の幅
        if (size_t(i) < notes_.size() && !notes_[size_t(i)].empty()) {
            SIZE ns;
            const u16& n = notes_[size_t(i)];
            SelectObject(dc, small_);
            GetTextExtentPoint32W(dc, W(n), int(n.size()), &ns);
            SelectObject(dc, font_);
            nw = ns.cx + MulDiv(12, int(dpi_), 96);
        }
        text_w = std::max(text_w, int(sz.cx) + nw);
    }
    text_w = std::min(text_w, MulDiv(640, int(dpi_), 96));
    SelectObject(dc, small_);
    GetTextMetricsW(dc, &tm);
    footer_h_ = sugg_.empty() ? tm.tmHeight + MulDiv(6, int(dpi_), 96) : pill_h + MulDiv(2, int(dpi_), 96);
    SelectObject(dc, old);
    ReleaseDC(hwnd_, dc);
    width_ = pad_ + num_w_ + text_w + pad_ * 2;
    if (cands_.empty() && sugg_.empty()) footer_h_ = 0;
    height_ = cands_.empty() ? footer_h_ : pad_ / 2 + row_h_ * (end - start) + footer_h_;
}

// 提案の頭の文字: 列に入る方法 (入ったら出し方)
std::wstring CandWindow::sugg_label() const {
    if (!label.empty()) return label;
    return sugg_sel_ < 0 ? L"提案 Shift+↓" : L"提案";
}

// 下の行の右の文字
std::wstring CandWindow::foot_text(int n) const {
    if (sugg_sel_ >= 0) return L"←→ で選ぶ  Enter で確定  Esc で戻る";
    if (n == 0) return L"";
    return sel_ < 0 ? L"Tab で選ぶ  " + std::to_wstring(n) + L" 件" : std::to_wstring(sel_ + 1) + L" / " + std::to_wstring(n);
}

int CandWindow::hit_sugg(int x, int y) const {
    if (y < height_ - footer_h_ || y >= height_) return -1;
    for (size_t i = 0; i < sugg_x_.size(); i++)
        if (x >= sugg_x_[i].first && x < sugg_x_[i].second) return int(i);
    return -1;
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
    Colors c = colors(theme);
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
        u16 s = cands_[size_t(i)];
        SetTextColor(dc, selected ? c.sel_text : c.text);
        DrawTextW(dc, W(s), int(s.size()), &tr, DT_SINGLELINE | DT_VCENTER | DT_LEFT | DT_NOPREFIX | DT_END_ELLIPSIS);
        // 提案の種類を右に薄い字で (もしかして・絵文字 …。Windows の候補の窓の見た目に合わせる、2026-10-14)
        if (size_t(i) < notes_.size() && !notes_[size_t(i)].empty()) {
            const u16& n = notes_[size_t(i)];   // 括弧は付けない (薄い字で注釈だと分かる)
            SelectObject(dc, small_);
            SetTextColor(dc, selected ? c.sel_text : c.sub);
            DrawTextW(dc, W(n), int(n.size()), &tr, DT_SINGLELINE | DT_VCENTER | DT_RIGHT | DT_NOPREFIX);
            SelectObject(dc, font_);
        }
    }
    SelectObject(dc, small_);
    const int fy = height_ - footer_h_;
    if (!sugg_.empty()) {   // 提案 (青い字の札) を下の行の左に
        const std::wstring label = sugg_label();
        RECT lr = {pad_, fy, width_ - pad_, height_};
        SetTextColor(dc, c.accent);
        DrawTextW(dc, label.c_str(), int(label.size()), &lr, DT_SINGLELINE | DT_VCENTER | DT_LEFT | DT_NOPREFIX);
        HPEN pen = CreatePen(PS_SOLID, 1, c.accent);
        HGDIOBJ op = SelectObject(dc, pen);
        HGDIOBJ ob = SelectObject(dc, GetStockObject(NULL_BRUSH));
        int r = MulDiv(10, int(dpi_), 96), m = MulDiv(3, int(dpi_), 96);
        SIZE fz;
        const std::wstring ft = foot_text(int(cands_.size()));
        GetTextExtentPoint32W(dc, ft.c_str(), int(ft.size()), &fz);
        const int limit = width_ - pad_ - fz.cx - MulDiv(8, int(dpi_), 96);
        for (size_t i = 0; i < sugg_.size() && i < sugg_x_.size(); i++) {
            const auto& xs = sugg_x_[i];
            if (xs.second > limit) break;   // 右の文字に重なる札は出さない
            if (int(i) == sugg_sel_) {
                HBRUSH sb = CreateSolidBrush(c.sel_bg);
                HGDIOBJ obb = SelectObject(dc, sb);
                RoundRect(dc, xs.first, fy + m, xs.second, height_ - m, r, r);
                SelectObject(dc, obb);
                DeleteObject(sb);
            } else {
                RoundRect(dc, xs.first, fy + m, xs.second, height_ - m, r, r);
            }
            RECT tr2 = {xs.first, fy, xs.second, height_};
            DrawTextW(dc, W(sugg_[i]), int(sugg_[i].size()), &tr2, DT_SINGLELINE | DT_VCENTER | DT_CENTER | DT_NOPREFIX);
        }
        SelectObject(dc, ob);
        SelectObject(dc, op);
        DeleteObject(pen);
    }
    const std::wstring foot = foot_text(int(cands_.size()));
    RECT fr = {pad_, fy, width_ - pad_, height_ - MulDiv(3, int(dpi_), 96)};
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
