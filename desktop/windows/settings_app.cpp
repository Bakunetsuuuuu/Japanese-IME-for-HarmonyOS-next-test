// shunti IME の設定 (shunti_settings.exe)。Windows の標準の部品だけで作った小さな窓。
// 変えるとすぐ %APPDATA%\shunti IME\settings.json に書き、IME は次に打ち始めたときに読み直す。
// ユーザー辞書 (userdict.json) の登録・削除と、学習 (learned.json) のリセットもここで行う。
#include <windows.h>
#include <commctrl.h>
#include <shellapi.h>
#include <shlobj.h>
#include <commdlg.h>
#include <fstream>
#include <iterator>

#include <algorithm>
#include <string>
#include <vector>

#include "../core/settings.h"
#include "../core/store.h"
#include "../core/text.h"
#include "shortcut_key.h"

using namespace shunti;
using namespace shunti::win;
namespace fs = std::filesystem;

namespace {

constexpr wchar_t VERSION[] = L"0.6.0";

enum Id {
    ID_THEME = 100, ID_PUNCT, ID_SPACE, ID_DIGITS, ID_LIVE, ID_LIVEDISPLAY, ID_LIVECOMMIT, ID_SUGGEST,
    ID_LIST, ID_READING, ID_WORD, ID_POS, ID_ADD, ID_REMOVE, ID_IMPORT, ID_ADVANCED, ID_RESET, ID_LICENSE, ID_GITHUB, ID_ICON, ID_MODEL,
};

// 変換モデル (settings.json の model の値と、画面の表示)。名前は配布の呼び名 (開発名は出さない)
const char* const MODELS[] = {"light", "standard"};

struct PosItem { const wchar_t* label; const char* pos; const char* group; };
// 品詞は MS-IME の分類にそろえる (MS-IME の一覧の出力をそのまま読み込めるように)
const PosItem POS[] = {
    {L"名詞", "noun", ""}, {L"短縮よみ", "abbrev", ""}, {L"顔文字", "kaomoji", ""}, {L"人名", "person", ""},
    {L"地名", "place", ""}, {L"固有名詞・組織", "org", ""},
    {L"動詞 (五段: 書く・ググる)", "verb", "godan"}, {L"動詞 (一段: 食べる)", "verb", "ichidan"}, {L"形容詞 (高い・エモい)", "adjective", ""},
    {L"副詞", "adverb", ""}, {L"感動詞", "interjection", ""},
};

fs::path g_dir;
Settings g_s;
UserDict* g_dict = nullptr;
HWND g_wnd = nullptr, g_list = nullptr;
HFONT g_font = nullptr;
UINT g_dpi = 96;
bool g_loading = false;

int S(int v) { return MulDiv(v, int(g_dpi), 96); }
std::wstring W(const u16& s) { return std::wstring(s.begin(), s.end()); }
u16 U(const std::wstring& s) { return u16(s.begin(), s.end()); }
std::wstring W8(const std::string& s) { return W(from_utf8(s)); }

std::wstring text_of(int id) {
    HWND h = GetDlgItem(g_wnd, id);
    int n = GetWindowTextLengthW(h);
    std::wstring s(size_t(n) + 1, L'\0');
    GetWindowTextW(h, s.data(), n + 1);
    s.resize(size_t(n));
    return s;
}

HWND make(const wchar_t* cls, const wchar_t* text, DWORD style, int x, int y, int w, int h, int id) {
    HWND c = CreateWindowExW(0, cls, text, WS_CHILD | WS_VISIBLE | style, S(x), S(y), S(w), S(h), g_wnd,
                             reinterpret_cast<HMENU>(INT_PTR(id)), GetModuleHandleW(nullptr), nullptr);
    SendMessageW(c, WM_SETFONT, WPARAM(g_font), TRUE);
    return c;
}

void group(const wchar_t* title, int y, int h) { make(L"BUTTON", title, BS_GROUPBOX, 10, y, 460, h, 0); }

HWND combo(int x, int y, int w, int id, std::initializer_list<const wchar_t*> items) {
    HWND c = make(WC_COMBOBOXW, L"", CBS_DROPDOWNLIST | WS_TABSTOP | WS_VSCROLL, x, y, w, 200, id);
    for (auto it : items) SendMessageW(c, CB_ADDSTRING, 0, LPARAM(it));
    return c;
}

void check(int id, bool on) { SendDlgItemMessageW(g_wnd, id, BM_SETCHECK, on ? BST_CHECKED : BST_UNCHECKED, 0); }
bool checked(int id) { return SendDlgItemMessageW(g_wnd, id, BM_GETCHECK, 0, 0) == BST_CHECKED; }
void select(int id, int i) { SendDlgItemMessageW(g_wnd, id, CB_SETCURSEL, WPARAM(i), 0); }
int selected(int id) { return int(SendDlgItemMessageW(g_wnd, id, CB_GETCURSEL, 0, 0)); }

void save() {
    if (g_loading) return;
    const char* themes[] = {"auto", "light", "dark"};
    g_s.theme = themes[std::max(0, selected(ID_THEME))];
    g_s.punct = std::max(0, selected(ID_PUNCT));
    g_s.space_fullwidth = checked(ID_SPACE);
    g_s.digits_fullwidth = checked(ID_DIGITS);
    g_s.live = checked(ID_LIVE);
    g_s.live_display = checked(ID_LIVEDISPLAY);
    g_s.live_commit = checked(ID_LIVECOMMIT);
    g_s.separate_suggest = checked(ID_SUGGEST);
    g_s.model = MODELS[std::clamp(selected(ID_MODEL), 0, 1)];
    if (!save_settings(g_dir / L"settings.json", g_s))
        MessageBoxW(g_wnd, L"設定を保存できませんでした。", L"shunti IME", MB_ICONWARNING);
}

std::wstring pos_label(const UserDict::Entry& e) {
    for (auto& p : POS)
        if (e.pos == p.pos && (e.pos != "verb" || e.group == p.group || (e.group.empty() && std::string(p.group) == "godan"))) return p.label;
    return W8(e.pos);
}

void refresh_list() {
    g_dict->refresh();
    ListView_DeleteAllItems(g_list);
    int i = 0;
    for (auto& e : g_dict->entries()) {
        std::wstring r = W(e.reading), w = W(e.word), p = pos_label(e);
        LVITEMW it = {};
        it.mask = LVIF_TEXT;
        it.iItem = i;
        it.pszText = r.data();
        ListView_InsertItem(g_list, &it);
        ListView_SetItemText(g_list, i, 1, w.data());
        ListView_SetItemText(g_list, i, 2, p.data());
        i++;
    }
}

void add_word() {
    std::wstring r = text_of(ID_READING), w = text_of(ID_WORD);
    int p = std::max(0, selected(ID_POS));
    std::string err = g_dict->add(U(r), U(w), POS[p].pos, POS[p].group);
    if (!err.empty()) {
        MessageBoxW(g_wnd, W8(err).c_str(), L"ユーザー辞書", MB_ICONINFORMATION);
        return;
    }
    SetDlgItemTextW(g_wnd, ID_READING, L"");
    SetDlgItemTextW(g_wnd, ID_WORD, L"");
    refresh_list();
    SetFocus(GetDlgItem(g_wnd, ID_READING));
}

// まとめて登録: MS-IME の「一覧の出力」の .txt (UTF-16) や、読み,語句,品詞 の CSV (UTF-8 / Shift_JIS)
void import_words() {
    wchar_t path[MAX_PATH] = L"";
    OPENFILENAMEW of = {};
    of.lStructSize = sizeof(of);
    of.hwndOwner = g_wnd;
    of.lpstrFilter = L"辞書の一覧 (*.txt;*.csv;*.tsv)\0*.txt;*.csv;*.tsv\0すべてのファイル\0*.*\0";
    of.lpstrFile = path;
    of.nMaxFile = MAX_PATH;
    of.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR;
    if (!GetOpenFileNameW(&of)) return;
    std::ifstream f(path, std::ios::binary);
    if (!f.is_open()) {
        MessageBoxW(g_wnd, L"ファイルを開けませんでした。", L"ユーザー辞書", MB_ICONWARNING);
        return;
    }
    std::string b((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    std::wstring text;
    if (b.size() >= 2 && uint8_t(b[0]) == 0xFF && uint8_t(b[1]) == 0xFE) {   // UTF-16 (MS-IME の出力)
        text.assign(reinterpret_cast<const wchar_t*>(b.data() + 2), (b.size() - 2) / 2);
    } else {
        size_t off = b.size() >= 3 && uint8_t(b[0]) == 0xEF && uint8_t(b[1]) == 0xBB && uint8_t(b[2]) == 0xBF ? 3 : 0;
        // UTF-8 として読めなければ Shift_JIS
        UINT cp = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, b.data() + off, int(b.size() - off), nullptr, 0) > 0 ? CP_UTF8 : 932;
        int n = MultiByteToWideChar(cp, 0, b.data() + off, int(b.size() - off), nullptr, 0);
        text.resize(size_t(std::max(n, 0)));
        if (n > 0) MultiByteToWideChar(cp, 0, b.data() + off, int(b.size() - off), text.data(), n);
    }
    auto res = g_dict->import_text(U(text));
    refresh_list();
    std::wstring msg = std::to_wstring(res.first) + L" 語を登録しました。";
    if (!res.second.empty()) {
        msg += L"\n\n登録できなかった行 (" + std::to_wstring(res.second.size()) + L"):";
        for (size_t i = 0; i < res.second.size() && i < 12; i++) msg += L"\n" + W8(res.second[i]);
        if (res.second.size() > 12) msg += L"\n…";
    }
    MessageBoxW(g_wnd, msg.c_str(), L"ユーザー辞書", MB_ICONINFORMATION);
}

// ---------------- 詳細設定 (別の窓) ----------------
// 記号ごとの全角/半角・テンキー・候補の数・無変換キー・再変換・プライベート・ローマ字の表・辞書の書き出し
const wchar_t SYMS[] = L"!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~";
enum { ADV_SYM0 = 500, ADV_NUMPAD = 600, ADV_PAGE, ADV_PRIVATE, ADV_ROMAJI, ADV_EXPORT, ADV_CLOSE,
       ADV_KEYMAP = 710, ADV_LAYOUT = 711, ADV_LAYOUT_NOTE = 712, ADV_LTHUMBS = 713, ADV_LCONT, ADV_LTAP, ADV_LREP, ADV_RLIST = 720, ADV_RKEY, ADV_RKANA, ADV_RADD, ADV_RDEL,
       ADV_SLIST = 800, ADV_SKEY, ADV_SFUNC, ADV_SADD, ADV_SCHG, ADV_SDEL, ADV_SUP, ADV_SDOWN, ADV_SRESET };
// キー割り当ての型 (Google 日本語入力 = Mozc の keymap と同じ字)
struct Keymap { const char* id; const wchar_t* name; };
const Keymap KEYMAPS[] = {{"msime", L"MS-IME"}, {"atok", L"ATOK"}, {"kotoeri", L"ことえり"}};
// キー配列: 置いてある layout_<id>.tsv を全部 (設定のフォルダ → インストール先)。名前・作者・公式ページは表の #! の行から
struct LayoutEntry { std::string id; std::wstring name, note; bool thumbs = false; };   // thumbs: 親指シフトの配列 (表に lthumb・rthumb がある)
HWND g_lgroup = nullptr, g_lthumb_label = nullptr, g_lother = nullptr;   // 詳細設定のキー配列の欄 (並べ直す部品)
int g_lgroup_y = 0;
std::vector<LayoutEntry> g_layouts;
void load_layouts() {
    g_layouts.clear();
    g_layouts.push_back({"", L"QWERTY ローマ字", L""});
    wchar_t exe[MAX_PATH];
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    std::vector<LayoutEntry> found;
    for (const std::filesystem::path& dir : {g_dir, std::filesystem::path(exe).parent_path()}) {
        std::error_code ec;
        for (auto& de : std::filesystem::directory_iterator(dir, ec)) {
            const std::wstring fn = de.path().filename().wstring();
            if (fn.size() < 12 || fn.compare(0, 7, L"layout_") != 0 || de.path().extension() != L".tsv") continue;
            const std::wstring idw = fn.substr(7, fn.size() - 11);
            const std::string id(idw.begin(), idw.end());
            bool dup = false;
            for (auto& f : found) dup = dup || f.id == id;
            if (dup) continue;   // 設定のフォルダに同じ名前があればそちら
            std::string t;
            if (!read_file(de.path(), t)) continue;
            LayoutEntry e{id, idw, L""};
            std::wstring author, url;
            size_t i = 0;
            while (i < t.size()) {
                size_t j = t.find('\n', i);
                if (j == std::string::npos) j = t.size();
                std::string line = t.substr(i, j - i);
                i = j + 1;
                if (!line.empty() && line.back() == '\r') line.pop_back();
                if (line.compare(0, 8, "#! name ") == 0) e.name = W8(line.substr(8));
                else if (line.compare(0, 10, "#! author ") == 0) author = W8(line.substr(10));
                else if (line.compare(0, 7, "#! url ") == 0) url = W8(line.substr(7));
                else if (line.compare(0, 7, "lthumb+") == 0 || line.compare(0, 7, "rthumb+") == 0) e.thumbs = true;
            }
            e.note = author.empty() ? url : (L"作: " + author + (url.empty() ? L"" : L"  " + url));
            found.push_back(std::move(e));
        }
    }
    std::sort(found.begin(), found.end(), [](const LayoutEntry& a, const LayoutEntry& b) { return a.name < b.name; });
    g_layouts.insert(g_layouts.end(), found.begin(), found.end());
}
int layout_index(const std::string& id);

void adv_layout_relayout();

int layout_index(const std::string& id) {
    for (size_t i = 0; i < g_layouts.size(); i++)
        if (g_layouts[i].id == id) return int(i);
    return 0;
}
HWND g_rlist = nullptr;   // ローマ字の表に足した綴りの一覧
HWND g_adv = nullptr;
std::string g_half;   // 詳細設定の窓で選んでいる「半角にする記号」

// その記号を打ったときに入る字 (半角ならそのまま、全角なら 、。・ー「」￥ や全角の記号)
std::wstring sym_shown(wchar_t c, bool half) {
    if (half) return std::wstring(1, c);
    switch (c) {
        case L',': return L"、";
        case L'.': return L"。";
        case L'/': return L"・";
        case L'-': return L"ー";
        case L'[': return L"「";
        case L']': return L"」";
        case L'\\': return L"￥";
        default: return std::wstring(1, wchar_t(c + 0xFEE0));
    }
}

void sym_label(int i) {
    const bool half = g_half.find(char(SYMS[i])) != std::string::npos;
    SetDlgItemTextW(g_adv, ADV_SYM0 + i, (sym_shown(SYMS[i], half) + (half ? L"  半" : L"  全")).c_str());
}

// 詳細設定の右の列の下端 (窓の高さを決める)。キー割り当て (341) + 間 (10) + ローマ字の表 (172)
constexpr int ADV_RIGHT_BOTTOM = 8 + 341 + 10 + 172;

// 詳細設定のキー配列の欄を並べ直す: 親指シフトの配列のときだけ親指の設定 (親指キー・連続シフト・単独打鍵) を出し、
// 欄と窓の高さをそれに合わせる (ユーザー 2026-10-16)
void adv_layout_relayout() {
    if (!g_adv || !g_lgroup) return;
    const int idx = layout_index(g_s.layout);
    const bool any = !g_s.layout.empty();
    const bool thumb = idx > 0 && idx < int(g_layouts.size()) && g_layouts[size_t(idx)].thumbs;
    auto place = [&](HWND h, int x, int y, int w, int hh, bool show) {
        if (!h) return;
        SetWindowPos(h, nullptr, S(x), S(y), S(w), S(hh), SWP_NOZORDER | SWP_NOACTIVATE);
        ShowWindow(h, show ? SW_SHOW : SW_HIDE);
    };
    place(GetDlgItem(g_adv, ADV_LAYOUT_NOTE), 24, g_lgroup_y + 52, 430, 20, any);   // 作者・公式ページ (配列を選んだときだけ)
    int y = g_lgroup_y + (any ? 74 : 52);   // 配列の名前 (と作者) の下
    place(g_lthumb_label, 24, y + 4, 80, 20, thumb);
    place(GetDlgItem(g_adv, ADV_LTHUMBS), 110, y, 200, 200, thumb);
    if (thumb) y += 28;
    place(GetDlgItem(g_adv, ADV_LCONT), 24, y, 430, 22, thumb);
    if (thumb) y += 22;
    place(GetDlgItem(g_adv, ADV_LTAP), 24, y, 430, 22, thumb);
    if (thumb) y += 22;
    place(GetDlgItem(g_adv, ADV_LREP), 24, y, 430, 22, any);
    if (any) y += 24;
    place(g_lother, 24, y + 2, 440, 20, true);
    y += 26;
    place(g_lgroup, 10, g_lgroup_y, 460, y - g_lgroup_y, true);
    // 閉じるボタンと窓の高さ (右の列の下端より下)
    const int bottom = std::max(y, ADV_RIGHT_BOTTOM) + 10;
    place(GetDlgItem(g_adv, ADV_CLOSE), 870, bottom, 80, 25, true);
    RECT r = {0, 0, S(960), S(bottom + 35)};
    AdjustWindowRectExForDpi(&r, WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU, FALSE, 0, g_dpi);
    SetWindowPos(g_adv, nullptr, 0, 0, r.right - r.left, r.bottom - r.top, SWP_NOZORDER | SWP_NOMOVE | SWP_NOACTIVATE);
    InvalidateRect(g_adv, nullptr, TRUE);
}

void adv_save() {
    if (g_loading) return;
    HWND keep = g_wnd;
    g_wnd = g_adv;
    g_s.half_symbols = g_half;
    g_s.numpad = std::max(0, selected(ADV_NUMPAD));
    g_s.page_size = 5 + std::max(0, selected(ADV_PAGE));
    g_s.private_mode = checked(ADV_PRIVATE);
    if (!g_layouts.empty()) {
        g_s.layout = g_layouts[size_t(std::clamp(selected(ADV_LAYOUT), 0, int(g_layouts.size()) - 1))].id;
        SetDlgItemTextW(g_adv, ADV_LAYOUT_NOTE, g_layouts[size_t(layout_index(g_s.layout))].note.c_str());
    }
    g_s.layout_thumbs = std::clamp(selected(ADV_LTHUMBS), 0, 2);
    g_s.layout_continuous = checked(ADV_LCONT);
    g_s.layout_thumb_tap = checked(ADV_LTAP);
    g_s.layout_repeat = checked(ADV_LREP);
    g_wnd = keep;
    if (!save_settings(g_dir / L"settings.json", g_s))
        MessageBoxW(g_adv, L"設定を保存できませんでした。", L"shunti IME", MB_ICONWARNING);
}

void open_romaji_table() {
    fs::path p = g_dir / L"romaji.tsv";
    std::error_code ec;
    if (!fs::exists(p, ec))
        write_file_atomic(p, "# ローマ字の表に足す綴り: 綴り<TAB>かな (1 行に 1 つ。既にある綴りは上書き)\n# 例:\n# xn\tん\n# la\tぁ\n");
    ShellExecuteW(g_adv, L"open", L"notepad.exe", (L"\"" + p.wstring() + L"\"").c_str(), nullptr, SW_SHOWNORMAL);
}

// ローマ字の表に足す綴り (romaji.tsv: 綴り<TAB>かな)
std::vector<std::pair<std::wstring, std::wstring>> romaji_rows() {
    std::vector<std::pair<std::wstring, std::wstring>> out;
    std::string t;
    if (!read_file(g_dir / L"romaji.tsv", t)) return out;
    size_t i = 0;
    while (i < t.size()) {
        size_t j = t.find('\n', i);
        if (j == std::string::npos) j = t.size();
        std::string line = t.substr(i, j - i);
        i = j + 1;
        if (!line.empty() && line.back() == '\r') line.pop_back();
        size_t tab = line.find('\t');
        if (line.empty() || line[0] == '#' || tab == std::string::npos) continue;
        out.push_back({W8(line.substr(0, tab)), W8(line.substr(tab + 1))});
    }
    return out;
}

void romaji_save(const std::vector<std::pair<std::wstring, std::wstring>>& rows) {
    std::string t = "# ローマ字の表に足す綴り: 綴り<TAB>かな (詳細設定で編集できます)\n";
    for (auto& r : rows) t += to_utf8(U(r.first)) + "\t" + to_utf8(U(r.second)) + "\n";
    write_file_atomic(g_dir / L"romaji.tsv", t);
}

void romaji_refresh() {
    ListView_DeleteAllItems(g_rlist);
    int i = 0;
    for (auto& r : romaji_rows()) {
        std::wstring a = r.first, b = r.second;
        LVITEMW it = {};
        it.mask = LVIF_TEXT;
        it.iItem = i;
        it.pszText = a.data();
        ListView_InsertItem(g_rlist, &it);
        ListView_SetItemText(g_rlist, i, 1, b.data());
        i++;
    }
}

std::wstring adv_text(int id) {
    HWND h = GetDlgItem(g_adv, id);
    int n = GetWindowTextLengthW(h);
    std::wstring s(size_t(n) + 1, L'\0');
    GetWindowTextW(h, s.data(), n + 1);
    s.resize(size_t(n));
    return s;
}

void romaji_add() {
    std::wstring k = adv_text(ADV_RKEY), v = adv_text(ADV_RKANA);
    if (k.empty() || v.empty()) return;
    for (auto& c : k) if (c >= L'A' && c <= L'Z') c = wchar_t(c + 32);
    auto rows = romaji_rows();
    rows.erase(std::remove_if(rows.begin(), rows.end(), [&](auto& r) { return r.first == k; }), rows.end());
    rows.push_back({k, v});
    romaji_save(rows);
    SetDlgItemTextW(g_adv, ADV_RKEY, L"");
    SetDlgItemTextW(g_adv, ADV_RKANA, L"");
    romaji_refresh();
}

void romaji_del() {
    int i = ListView_GetNextItem(g_rlist, -1, LVNI_SELECTED);
    auto rows = romaji_rows();
    if (i < 0 || i >= int(rows.size())) return;
    rows.erase(rows.begin() + i);
    romaji_save(rows);
    romaji_refresh();
}

// ---- ショートカットキー (既定も自分で追加も同じ一覧) ----
std::wstring shortcut_line(const std::string& key, const std::string& func) {
    const wchar_t* n = shortcut_func_name(func);
    const std::wstring name = n && *n ? n : W8(func);
    // 日本語キーボードのキーは日本語の名前で見せる (保存は英字の名前のまま)
    std::wstring k = W8(key);
    for (auto [en, ja] : {std::pair{L"Muhenkan", L"無変換"}, {L"Henkan", L"変換"}, {L"Hiragana", L"ひらがな"}, {L"Kana", L"カタカナひらがな"}})
        if (size_t i = k.rfind(en); i != std::wstring::npos && i + wcslen(en) == k.size()) { k = k.substr(0, i) + ja; break; }
    return k + L" → " + name;
}

void shortcut_refresh() {
    HWND lb = GetDlgItem(g_adv, ADV_SLIST);
    SendMessageW(lb, LB_RESETCONTENT, 0, 0);
    for (auto& p : g_s.shortcuts)
        SendMessageW(lb, LB_ADDSTRING, 0, LPARAM(shortcut_line(p.first, p.second).c_str()));
}

// キーと機能の欄の値を読む (キーが押されていなければ false)
bool shortcut_fields(std::string& key, std::string& func) {
    const WORD hot = WORD(SendMessageW(GetDlgItem(g_adv, ADV_SKEY), HKM_GETHOTKEY, 0, 0));
    const UINT vk = LOBYTE(hot);
    if (!vk) return false;
    key = shortcut_key_string(vk, (HIBYTE(hot) & HOTKEYF_CONTROL) != 0, (HIBYTE(hot) & HOTKEYF_SHIFT) != 0,
                              (HIBYTE(hot) & HOTKEYF_ALT) != 0);
    const int fi = int(SendDlgItemMessageW(g_adv, ADV_SFUNC, CB_GETCURSEL, 0, 0));
    if (fi < 0 || fi >= int(shortcut_funcs().size())) return false;
    func = shortcut_funcs()[size_t(fi)].id;
    return true;
}

// 一覧で選ぶとキーと機能の欄に入れる
void shortcut_select() {
    HWND lb = GetDlgItem(g_adv, ADV_SLIST);
    const int i = int(SendMessageW(lb, LB_GETCURSEL, 0, 0));
    if (i < 0 || i >= int(g_s.shortcuts.size())) return;
    const ShortcutKey k = parse_shortcut_key(g_s.shortcuts[size_t(i)].first);
    if (k.ok) {
        const WORD mods = WORD((k.ctrl ? HOTKEYF_CONTROL : 0) | (k.shift ? HOTKEYF_SHIFT : 0) | (k.alt ? HOTKEYF_ALT : 0));
        SendMessageW(GetDlgItem(g_adv, ADV_SKEY), HKM_SETHOTKEY, MAKEWPARAM(k.vk, mods), 0);
    }
    const std::string& func = g_s.shortcuts[size_t(i)].second;
    for (int f = 0; f < int(shortcut_funcs().size()); f++)
        if (shortcut_funcs()[size_t(f)].id == func) { SendDlgItemMessageW(g_adv, ADV_SFUNC, CB_SETCURSEL, WPARAM(f), 0); break; }
}

void shortcut_add() {
    std::string key, func;
    if (!shortcut_fields(key, func)) return;
    for (auto& p : g_s.shortcuts) {   // 同じキーは上書き
        if (p.first == key) { p.second = func; shortcut_refresh(); adv_save(); return; }
    }
    g_s.shortcuts.push_back({key, func});
    shortcut_refresh();
    adv_save();
}

void shortcut_change() {
    HWND lb = GetDlgItem(g_adv, ADV_SLIST);
    const int i = int(SendMessageW(lb, LB_GETCURSEL, 0, 0));
    if (i < 0 || i >= int(g_s.shortcuts.size())) return;
    std::string key, func;
    if (!shortcut_fields(key, func)) return;
    g_s.shortcuts[size_t(i)] = {key, func};
    shortcut_refresh();
    SendMessageW(lb, LB_SETCURSEL, WPARAM(i), 0);
    adv_save();
}

void shortcut_del() {
    HWND lb = GetDlgItem(g_adv, ADV_SLIST);
    const int i = int(SendMessageW(lb, LB_GETCURSEL, 0, 0));
    if (i < 0 || i >= int(g_s.shortcuts.size())) return;
    g_s.shortcuts.erase(g_s.shortcuts.begin() + i);
    shortcut_refresh();
    adv_save();
}

void shortcut_move(int delta) {
    HWND lb = GetDlgItem(g_adv, ADV_SLIST);
    const int i = int(SendMessageW(lb, LB_GETCURSEL, 0, 0));
    const int j = i + delta;
    if (i < 0 || i >= int(g_s.shortcuts.size()) || j < 0 || j >= int(g_s.shortcuts.size())) return;
    std::swap(g_s.shortcuts[size_t(i)], g_s.shortcuts[size_t(j)]);
    shortcut_refresh();
    SendMessageW(lb, LB_SETCURSEL, WPARAM(j), 0);
    adv_save();
}

void shortcut_reset() {
    const int kmi = std::clamp(int(SendDlgItemMessageW(g_adv, ADV_KEYMAP, CB_GETCURSEL, 0, 0)), 0, 2);
    if (MessageBoxW(g_adv, L"キー割り当てを初期状態 (選んだ型) に戻します。よろしいですか?", L"shunti IME",
                    MB_YESNO | MB_ICONQUESTION) != IDYES)
        return;
    g_s.keymap = KEYMAPS[kmi].id;
    g_s.shortcuts = default_shortcuts(g_s.keymap);
    shortcut_refresh();
    adv_save();
}

void export_words() {
    wchar_t path[MAX_PATH] = L"shunti_userdict.txt";
    OPENFILENAMEW of = {};
    of.lStructSize = sizeof(of);
    of.hwndOwner = g_adv;
    of.lpstrFilter = L"テキスト (*.txt)\0*.txt\0";
    of.lpstrFile = path;
    of.nMaxFile = MAX_PATH;
    of.lpstrDefExt = L"txt";
    of.Flags = OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR;
    if (!GetSaveFileNameW(&of)) return;
    g_dict->refresh();
    u16 t = g_dict->export_text();
    std::string b = "\xFF\xFE";   // MS-IME と同じ UTF-16 (読み込みにも使える)
    b.append(reinterpret_cast<const char*>(t.data()), t.size() * 2);
    std::ofstream f(path, std::ios::binary);
    f.write(b.data(), std::streamsize(b.size()));
    f.close();
    if (!f) {
        MessageBoxW(g_adv, L"書き出せませんでした (書き込めない場所かもしれません)。", L"ユーザー辞書", MB_ICONWARNING);
        return;
    }
    MessageBoxW(g_adv, (std::to_wstring(g_dict->entries().size()) + L" 語を書き出しました。").c_str(), L"ユーザー辞書", MB_ICONINFORMATION);
}

LRESULT CALLBACK adv_proc(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_COMMAND) {
        int id = LOWORD(w), code = HIWORD(w);
        if (id == ADV_CLOSE || id == IDCANCEL) DestroyWindow(h);
        else if ((id == ADV_NUMPAD || id == ADV_PAGE) && code == CBN_SELCHANGE) adv_save();
        else if (id >= ADV_SYM0 && id < ADV_SYM0 + 64 && code == BN_CLICKED) {   // 押すたびに全角 ⇔ 半角
            const char c = char(SYMS[id - ADV_SYM0]);
            const size_t at = g_half.find(c);
            if (at == std::string::npos) g_half += c; else g_half.erase(at, 1);
            sym_label(id - ADV_SYM0);
            adv_save();
        }
        else if (id == ADV_PRIVATE && code == BN_CLICKED) adv_save();
        else if (id == ADV_ROMAJI) open_romaji_table();
        else if ((id == ADV_LAYOUT || id == ADV_LTHUMBS) && code == CBN_SELCHANGE) { adv_save(); adv_layout_relayout(); }
        else if ((id == ADV_LCONT || id == ADV_LTAP || id == ADV_LREP) && code == BN_CLICKED) adv_save();
        else if (id == ADV_RADD) romaji_add();
        else if (id == ADV_RDEL) romaji_del();
        else if (id == ADV_SLIST && code == LBN_SELCHANGE) shortcut_select();
        else if (id == ADV_SADD) shortcut_add();
        else if (id == ADV_SCHG) shortcut_change();
        else if (id == ADV_SDEL) shortcut_del();
        else if (id == ADV_SUP) shortcut_move(-1);
        else if (id == ADV_SDOWN) shortcut_move(1);
        else if (id == ADV_SRESET) shortcut_reset();
        else if (id == ADV_EXPORT) export_words();
        return 0;
    }
    if (m == WM_DESTROY) { g_adv = nullptr; EnableWindow(g_wnd, TRUE); SetForegroundWindow(g_wnd); return 0; }
    return DefWindowProcW(h, m, w, l);
}

void open_advanced() {
    if (g_adv) { SetForegroundWindow(g_adv); return; }
    static bool reg = false;
    if (!reg) {
        WNDCLASSEXW wc = {sizeof wc};
        wc.lpfnWndProc = adv_proc;
        wc.hInstance = GetModuleHandleW(nullptr);
        wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
        wc.hbrBackground = GetSysColorBrush(COLOR_BTNFACE);
        wc.lpszClassName = L"ShuntiImeAdvanced";
        RegisterClassExW(&wc);
        reg = true;
    }
    RECT r = {0, 0, S(960), S(ADV_RIGHT_BOTTOM + 45)};
    AdjustWindowRectExForDpi(&r, WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU, FALSE, 0, g_dpi);
    g_adv = CreateWindowExW(0, L"ShuntiImeAdvanced", L"shunti IME の詳細設定", WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU,
                            CW_USEDEFAULT, CW_USEDEFAULT, r.right - r.left, r.bottom - r.top, g_wnd, nullptr, GetModuleHandleW(nullptr), nullptr);
    if (!g_adv) return;   // 窓を作れなかった: 設定の窓を使えないままにしない
    HWND keep = g_wnd;
    g_wnd = g_adv;
    int y = 8;
    group(L"日本語入力時の記号 (クリックで変更)", y, 138);
    for (int i = 0; SYMS[i]; i++)
        make(L"BUTTON", L"", BS_PUSHBUTTON | WS_TABSTOP, 24 + (i % 8) * 54, y + 24 + (i / 8) * 28, 50, 25, ADV_SYM0 + i);
    y += 146;
    group(L"入力", y, 84);
    make(L"STATIC", L"テンキー:", 0, 24, y + 27, 90, 20, 0);
    combo(130, y + 23, 240, ADV_NUMPAD, {L"常に半角", L"数字の全角/半角の設定に合わせる", L"常に全角"});
    make(L"STATIC", L"候補の窓の数:", 0, 24, y + 57, 100, 20, 0);
    combo(130, y + 53, 100, ADV_PAGE, {L"5", L"6", L"7", L"8", L"9"});
    y += 92;
    group(L"その他", y, 90);
    make(L"BUTTON", L"プライベート (学習機能を一時的にオフ。Ctrl+Shift+F10 でも切り替え)", BS_AUTOCHECKBOX | WS_TABSTOP, 24, y + 22, 430, 22, ADV_PRIVATE);
    make(L"BUTTON", L"ユーザー辞書を書き出す…", BS_PUSHBUTTON | WS_TABSTOP, 24, y + 54, 180, 25, ADV_EXPORT);
    y += 98;
    g_lgroup_y = y;
    g_lgroup = make(L"BUTTON", L"キー配列 (日本語入力がオンのとき)", BS_GROUPBOX, 10, y, 460, 198, 0);
    {
        load_layouts();
        HWND cb = make(WC_COMBOBOXW, L"", CBS_DROPDOWNLIST | WS_TABSTOP | WS_VSCROLL, 24, y + 23, 300, 400, ADV_LAYOUT);
        for (auto& l : g_layouts) SendMessageW(cb, CB_ADDSTRING, 0, LPARAM(l.name.c_str()));
    }
    make(L"STATIC", L"", 0, 24, y + 52, 430, 20, ADV_LAYOUT_NOTE);
    // 流儀の分かれる所 (配列ソフトの設定と同じ)。位置は adv_layout_relayout が決める
    g_lthumb_label = make(L"STATIC", L"親指キー:", 0, 24, y + 78, 80, 20, 0);
    combo(110, y + 74, 200, ADV_LTHUMBS, {L"無変換・変換", L"無変換・空白", L"空白・変換"});
    make(L"BUTTON", L"連続シフト (親指を押したまま続けて打つ)", BS_AUTOCHECKBOX | WS_TABSTOP, 24, y + 102, 430, 22, ADV_LCONT);
    make(L"BUTTON", L"親指キーを単独で押したら 本来のキー (空白・変換・無変換)", BS_AUTOCHECKBOX | WS_TABSTOP, 24, y + 124, 430, 22, ADV_LTAP);
    make(L"BUTTON", L"押しっぱなしで繰り返す", BS_AUTOCHECKBOX | WS_TABSTOP, 24, y + 146, 430, 22, ADV_LREP);
    g_lother = make(L"STATIC", L"その他の配列は 設定のフォルダに layout_名前.tsv を置くと ここに出ます", 0, 24, y + 172, 440, 20, 0);
    make(L"BUTTON", L"閉じる", BS_DEFPUSHBUTTON | WS_TABSTOP, 870, y, 80, 25, ADV_CLOSE);

    // ---- 右の列: ショートカットキー・ローマ字の表 ----
    auto rgroup = [](const wchar_t* t, int gy, int h) { make(L"BUTTON", t, BS_GROUPBOX, 490, gy, 460, h, 0); };
    int ry = 8;
    rgroup(L"キー割り当て", ry, 341);
    make(L"STATIC", L"型:", 0, 506, ry + 24, 30, 20, 0);
    {
        HWND cb = make(WC_COMBOBOXW, L"", CBS_DROPDOWNLIST | WS_TABSTOP, 542, ry + 20, 120, 200, ADV_KEYMAP);
        for (auto& km : KEYMAPS) SendMessageW(cb, CB_ADDSTRING, 0, LPARAM(km.name));
    }
    make(L"BUTTON", L"初期状態に戻す", BS_PUSHBUTTON | WS_TABSTOP, 820, ry + 20, 114, 25, ADV_SRESET);
    // 既定も自分で追加も同じ一覧 (上から順に、使える状態のものが効く)
    make(WC_LISTBOXW, L"", LBS_NOTIFY | WS_BORDER | WS_VSCROLL | WS_TABSTOP, 506, ry + 52, 428, 210, ADV_SLIST);
    make(L"STATIC", L"キー:", 0, 506, ry + 270, 40, 20, 0);
    make(HOTKEY_CLASSW, L"", WS_BORDER | WS_TABSTOP, 548, ry + 266, 130, 23, ADV_SKEY);
    make(L"STATIC", L"機能:", 0, 686, ry + 270, 40, 20, 0);
    {
        HWND cb = make(WC_COMBOBOXW, L"", CBS_DROPDOWNLIST | WS_TABSTOP | WS_VSCROLL, 728, ry + 266, 206, 300, ADV_SFUNC);
        for (auto& f : shortcut_funcs()) SendMessageW(cb, CB_ADDSTRING, 0, LPARAM(f.name));
        SendMessageW(cb, CB_SETCURSEL, 0, 0);
    }
    make(L"BUTTON", L"追加", BS_PUSHBUTTON | WS_TABSTOP, 506, ry + 296, 60, 25, ADV_SADD);
    make(L"BUTTON", L"変更", BS_PUSHBUTTON | WS_TABSTOP, 574, ry + 296, 60, 25, ADV_SCHG);
    make(L"BUTTON", L"削除", BS_PUSHBUTTON | WS_TABSTOP, 642, ry + 296, 60, 25, ADV_SDEL);
    make(L"BUTTON", L"上へ", BS_PUSHBUTTON | WS_TABSTOP, 800, ry + 296, 60, 25, ADV_SUP);
    make(L"BUTTON", L"下へ", BS_PUSHBUTTON | WS_TABSTOP, 868, ry + 296, 60, 25, ADV_SDOWN);
    shortcut_refresh();
    ry += 351;
    rgroup(L"ローマ字の表 (足した綴りは元の表より優先)", ry, 172);
    g_rlist = make(WC_LISTVIEWW, L"", LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS | WS_BORDER | WS_TABSTOP, 506, ry + 22, 428, 100, ADV_RLIST);
    ListView_SetExtendedListViewStyle(g_rlist, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER);
    {
        const wchar_t* cols[] = {L"綴り", L"かな"};
        for (int i = 0; i < 2; i++) {
            LVCOLUMNW c = {};
            c.mask = LVCF_TEXT | LVCF_WIDTH;
            c.pszText = const_cast<wchar_t*>(cols[i]);
            c.cx = S(200);
            ListView_InsertColumn(g_rlist, i, &c);
        }
    }
    make(L"STATIC", L"綴り:", 0, 506, ry + 135, 40, 20, 0);
    make(L"EDIT", L"", ES_AUTOHSCROLL | WS_BORDER | WS_TABSTOP, 548, ry + 132, 100, 23, ADV_RKEY);
    make(L"STATIC", L"かな:", 0, 660, ry + 135, 40, 20, 0);
    make(L"EDIT", L"", ES_AUTOHSCROLL | WS_BORDER | WS_TABSTOP, 702, ry + 132, 100, 23, ADV_RKANA);
    make(L"BUTTON", L"追加", BS_PUSHBUTTON | WS_TABSTOP, 810, ry + 131, 60, 25, ADV_RADD);
    make(L"BUTTON", L"削除", BS_PUSHBUTTON | WS_TABSTOP, 874, ry + 131, 60, 25, ADV_RDEL);
    romaji_refresh();
    g_loading = true;
    g_half = g_s.half_symbols;
    for (int i = 0; SYMS[i]; i++) sym_label(i);
    select(ADV_NUMPAD, g_s.numpad);
    select(ADV_PAGE, std::clamp(g_s.page_size, 5, 9) - 5);
    check(ADV_PRIVATE, g_s.private_mode);
    select(ADV_KEYMAP, g_s.keymap == "atok" ? 1 : g_s.keymap == "kotoeri" ? 2 : 0);
    select(ADV_LAYOUT, layout_index(g_s.layout));
    select(ADV_LTHUMBS, g_s.layout_thumbs);
    check(ADV_LCONT, g_s.layout_continuous);
    check(ADV_LTAP, g_s.layout_thumb_tap);
    check(ADV_LREP, g_s.layout_repeat);
    adv_layout_relayout();
    if (!g_layouts.empty()) SetWindowTextW(GetDlgItem(g_wnd, ADV_LAYOUT_NOTE), g_layouts[size_t(layout_index(g_s.layout))].note.c_str());
    g_loading = false;
    g_wnd = keep;
    EnableWindow(g_wnd, FALSE);
    ShowWindow(g_adv, SW_SHOW);
}

void remove_word() {
    int i = ListView_GetNextItem(g_list, -1, LVNI_SELECTED);
    if (i < 0) return;
    g_dict->refresh();
    if (i >= int(g_dict->entries().size())) return;
    UserDict::Entry e = g_dict->entries()[size_t(i)];
    g_dict->remove(e.reading, e.word);
    refresh_list();
}

void reset_learning() {
    if (MessageBoxW(g_wnd, L"変換で選び直して覚えた語を、すべて忘れます。よろしいですか?", L"学習をリセット",
                    MB_OKCANCEL | MB_ICONQUESTION) != IDOK)
        return;
    Learning(g_dir / L"learned.json").clear();
    MessageBoxW(g_wnd, L"学習をリセットしました。", L"shunti IME", MB_ICONINFORMATION);
}

void build() {
    int y = 8;
    group(L"表示", y, 86);
    make(L"STATIC", L"候補ウィンドウの色:", 0, 24, y + 27, 170, 20, 0);
    combo(200, y + 23, 250, ID_THEME, {L"Windows の設定に合わせる", L"ライト", L"ダーク"});
    make(L"BUTTON", L"アイコンの色をタスクバーに合わせる", BS_PUSHBUTTON | WS_TABSTOP, 24, y + 52, 250, 25, ID_ICON);
    y += 94;

    group(L"変換", y, 60);
    make(L"STATIC", L"変換モデル:", 0, 24, y + 27, 170, 20, 0);
    combo(200, y + 23, 250, ID_MODEL, {L"軽量 (XS5)", L"標準 (S7)　推奨"});
    y += 68;

    group(L"入力", y, 210);
    make(L"STATIC", L"句読点:", 0, 24, y + 27, 170, 20, 0);
    combo(200, y + 23, 120, ID_PUNCT, {L"、。", L"，．", L"、．", L"，。"});
    make(L"BUTTON", L"何も入力していないときのスペースを全角にする", BS_AUTOCHECKBOX | WS_TABSTOP, 24, y + 54, 430, 22, ID_SPACE);
    make(L"BUTTON", L"数字を全角で入力する", BS_AUTOCHECKBOX | WS_TABSTOP, 24, y + 79, 430, 22, ID_DIGITS);
    make(L"BUTTON", L"入力中も変換候補を表示する", BS_AUTOCHECKBOX | WS_TABSTOP, 24, y + 104, 430, 22, ID_LIVE);
    make(L"BUTTON", L"入力中の文字も変換して表示する (ライブ変換)", BS_AUTOCHECKBOX | WS_TABSTOP, 24, y + 129, 430, 22, ID_LIVEDISPLAY);
    make(L"BUTTON", L"変換演算を直近の文字にのみ適用 (より軽量)", BS_AUTOCHECKBOX | WS_TABSTOP, 24, y + 154, 430, 22, ID_LIVECOMMIT);
    make(L"BUTTON", L"提案 (打ち間違いの直し・日付・絵文字など) を候補と分けて表示する", BS_AUTOCHECKBOX | WS_TABSTOP, 24, y + 179, 430, 22, ID_SUGGEST);
    y += 218;

    group(L"ユーザー辞書", y, 216);
    g_list = make(WC_LISTVIEWW, L"", LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS | WS_BORDER | WS_TABSTOP, 24, y + 22, 432, 90, ID_LIST);
    ListView_SetExtendedListViewStyle(g_list, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER);
    const wchar_t* cols[] = {L"読み", L"単語", L"品詞"};
    int widths[] = {130, 130, 150};
    for (int i = 0; i < 3; i++) {
        LVCOLUMNW c = {};
        c.mask = LVCF_TEXT | LVCF_WIDTH;
        c.pszText = const_cast<wchar_t*>(cols[i]);
        c.cx = S(widths[i]);
        ListView_InsertColumn(g_list, i, &c);
    }
    make(L"STATIC", L"読み:", 0, 24, y + 125, 44, 20, 0);
    make(L"EDIT", L"", ES_AUTOHSCROLL | WS_BORDER | WS_TABSTOP, 70, y + 122, 150, 23, ID_READING);
    make(L"STATIC", L"単語:", 0, 232, y + 125, 44, 20, 0);
    make(L"EDIT", L"", ES_AUTOHSCROLL | WS_BORDER | WS_TABSTOP, 278, y + 122, 178, 23, ID_WORD);
    make(L"STATIC", L"品詞:", 0, 24, y + 156, 44, 20, 0);
    HWND pos = make(WC_COMBOBOXW, L"", CBS_DROPDOWNLIST | WS_TABSTOP | WS_VSCROLL, 70, y + 152, 210, 200, ID_POS);
    for (auto& p : POS) SendMessageW(pos, CB_ADDSTRING, 0, LPARAM(p.label));
    make(L"BUTTON", L"追加", BS_PUSHBUTTON | WS_TABSTOP, 290, y + 151, 80, 25, ID_ADD);
    make(L"BUTTON", L"削除", BS_PUSHBUTTON | WS_TABSTOP, 376, y + 151, 80, 25, ID_REMOVE);
    make(L"BUTTON", L"ファイルから辞書を登録…", BS_PUSHBUTTON | WS_TABSTOP, 24, y + 182, 190, 25, ID_IMPORT);
    make(L"STATIC", L"動詞・形容詞は終止形で\nMS-IME の一覧 (.txt) も登録可能",
         0, 222, y + 180, 240, 34, 0);
    y += 224;

    group(L"学習", y, 60);
    make(L"BUTTON", L"学習をリセット", BS_PUSHBUTTON | WS_TABSTOP, 24, y + 24, 140, 25, ID_RESET);
    y += 68;
    make(L"BUTTON", L"詳細設定…", BS_PUSHBUTTON | WS_TABSTOP, 10, y, 120, 25, ID_ADVANCED);
    y += 35;

    std::wstring about = std::wstring(L"shunti IME ") + VERSION;
#ifdef SHUNTI_INPUT_LOG
    about += L" (デバッグ版: 入力を記録しています)";
#endif
    make(L"STATIC", about.c_str(), 0, 14, y + 6, 200, 36, 0);
    make(L"BUTTON", L"ライセンス", BS_PUSHBUTTON | WS_TABSTOP, 222, y, 80, 25, ID_LICENSE);
    make(L"BUTTON", L"GitHub", BS_PUSHBUTTON | WS_TABSTOP, 308, y, 76, 25, ID_GITHUB);
    make(L"BUTTON", L"閉じる", BS_DEFPUSHBUTTON | WS_TABSTOP, 390, y, 80, 25, IDCANCEL);

    g_loading = true;
    select(ID_THEME, g_s.theme == "light" ? 1 : g_s.theme == "dark" ? 2 : 0);
    select(ID_PUNCT, g_s.punct);
    select(ID_MODEL, g_s.model == "light" ? 0 : 1);
    select(ID_POS, 0);
    check(ID_SPACE, g_s.space_fullwidth);
    check(ID_DIGITS, g_s.digits_fullwidth);
    check(ID_LIVE, g_s.live);
    check(ID_LIVEDISPLAY, g_s.live_display);
    check(ID_LIVECOMMIT, g_s.live_commit);
    check(ID_SUGGEST, g_s.separate_suggest);
    g_loading = false;
    refresh_list();
}

LRESULT CALLBACK proc(HWND h, UINT m, WPARAM w, LPARAM l) {
    switch (m) {
        case WM_COMMAND: {
            int id = LOWORD(w), code = HIWORD(w);
            if ((id == ID_THEME || id == ID_PUNCT || id == ID_MODEL) && code == CBN_SELCHANGE) save();
            else if (id == IDCANCEL) DestroyWindow(h);   // 「閉じる」と Esc
            else if (((id >= ID_SPACE && id <= ID_LIVECOMMIT) || id == ID_SUGGEST) && code == BN_CLICKED) save();
            else if (id == ID_ADD) add_word();
            else if (id == ID_IMPORT) import_words();
            else if (id == ID_ADVANCED) open_advanced();
            else if (id == ID_REMOVE) remove_word();
            else if (id == ID_RESET) reset_learning();
            else if (id == ID_ICON) {
                // IME を登録し直すと、登録アイコンをいまのタスクバーの色 (ダーク = 白、ライト = 黒) で選び直す (管理者の許可が要る)
                wchar_t exe[MAX_PATH], sys[MAX_PATH];
                GetModuleFileNameW(nullptr, exe, MAX_PATH);
                GetSystemDirectoryW(sys, MAX_PATH);
                std::wstring args = L"/s \"" + (fs::path(exe).parent_path() / L"shunti_ime_x64.dll").wstring() + L"\"";
                std::wstring reg = std::wstring(sys) + L"\\regsvr32.exe";
                if (reinterpret_cast<INT_PTR>(ShellExecuteW(h, L"runas", reg.c_str(), args.c_str(), nullptr, SW_HIDE)) > 32)
                    MessageBoxW(h, L"アイコンの色を合わせました。タスクバーに出るまで、IME を切り替え直すか、少し待ってください。",
                                L"shunti IME", MB_ICONINFORMATION);
            }
            else if (id == ID_LICENSE) {
                wchar_t exe[MAX_PATH];
                GetModuleFileNameW(nullptr, exe, MAX_PATH);
                std::wstring lic = (fs::path(exe).parent_path() / L"LICENSE.txt").wstring();
                ShellExecuteW(h, L"open", L"notepad.exe", lic.c_str(), nullptr, SW_SHOWNORMAL);
            } else if (id == ID_GITHUB) {
                ShellExecuteW(h, L"open", L"https://github.com/shuntilettuce/Japanese-IME-for-HarmonyOS-next", nullptr, nullptr, SW_SHOWNORMAL);
            }
            return 0;
        }
        case WM_DESTROY:
            PostQuitMessage(0);
            return 0;
        default:
            return DefWindowProcW(h, m, w, l);
    }
}

}  // namespace

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE, PWSTR cmd, int show) {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    // ショートカットキー「ユーザー辞書を開く」: --dict なら起動後にユーザー辞書の欄に移る
    const bool open_dict = cmd && wcsstr(cmd, L"--dict") != nullptr;
    // 2 つ目は開かずに、開いている窓を前に出す
    HANDLE once = CreateMutexW(nullptr, TRUE, L"ShuntiImeSettings");
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        if (HWND other = FindWindowW(L"ShuntiImeSettings", nullptr)) SetForegroundWindow(other);
        return 0;
    }
    INITCOMMONCONTROLSEX icc = {sizeof icc, ICC_LISTVIEW_CLASSES | ICC_STANDARD_CLASSES | ICC_HOTKEY_CLASS};
    InitCommonControlsEx(&icc);

    PWSTR app = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr, &app))) g_dir = fs::path(app) / L"shunti IME";
    CoTaskMemFree(app);
    std::error_code ec;
    fs::create_directories(g_dir, ec);
    load_settings(g_dir / L"settings.json", g_s);
    UserDict dict(g_dir / L"userdict.json");
    g_dict = &dict;

    WNDCLASSEXW wc = {sizeof wc};
    wc.lpfnWndProc = proc;
    wc.hInstance = inst;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.hbrBackground = GetSysColorBrush(COLOR_BTNFACE);   // ダイアログの既定の色
    wc.hIcon = LoadIconW(inst, MAKEINTRESOURCEW(101));
    wc.lpszClassName = L"ShuntiImeSettings";
    RegisterClassExW(&wc);

    g_dpi = GetDpiForSystem();
    RECT rc = {0, 0, S(480), S(791)};
    AdjustWindowRectExForDpi(&rc, WS_OVERLAPPEDWINDOW & ~(WS_MAXIMIZEBOX | WS_THICKFRAME), FALSE, 0, g_dpi);
    g_wnd = CreateWindowExW(0, wc.lpszClassName, L"shunti IME の設定", WS_OVERLAPPEDWINDOW & ~(WS_MAXIMIZEBOX | WS_THICKFRAME),
                            CW_USEDEFAULT, CW_USEDEFAULT, rc.right - rc.left, rc.bottom - rc.top, nullptr, nullptr, inst, nullptr);
    g_dpi = GetDpiForWindow(g_wnd);
    // Windows の既定のメッセージ用の文字 (ダイアログと同じ)
    NONCLIENTMETRICSW ncm = {sizeof ncm};
    SystemParametersInfoForDpi(SPI_GETNONCLIENTMETRICS, sizeof ncm, &ncm, 0, g_dpi);
    g_font = CreateFontIndirectW(&ncm.lfMessageFont);
    build();
    ShowWindow(g_wnd, show);
    if (open_dict) SetFocus(GetDlgItem(g_wnd, ID_READING));

    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0)) {
        if (!IsDialogMessageW(g_wnd, &msg)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }
    CloseHandle(once);
    return 0;
}
