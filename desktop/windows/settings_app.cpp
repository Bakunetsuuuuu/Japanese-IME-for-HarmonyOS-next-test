// shunti IME の設定 (shunti_settings.exe)。Windows の標準の部品だけで作った小さな窓。
// 変えるとすぐ %APPDATA%\shunti IME\settings.json に書き、IME は次に打ち始めたときに読み直す。
// ユーザー辞書 (userdict.json) の登録・削除と、学習 (learned.json) のリセットもここで行う。
#include <windows.h>
#include <commctrl.h>
#include <shellapi.h>
#include <shlobj.h>

#include <string>
#include <vector>

#include "../core/settings.h"
#include "../core/store.h"
#include "../core/text.h"

using namespace shunti;
namespace fs = std::filesystem;

namespace {

constexpr wchar_t VERSION[] = L"0.1.0";

enum Id {
    ID_THEME = 100, ID_PUNCT, ID_SPACE, ID_DIGITS, ID_LIVE, ID_LIVECOMMIT, ID_CTRLSPACE,
    ID_LIST, ID_READING, ID_WORD, ID_POS, ID_ADD, ID_REMOVE, ID_RESET, ID_LICENSE, ID_GITHUB, ID_ICON,
};

struct PosItem { const wchar_t* label; const char* pos; const char* group; };
const PosItem POS[] = {
    {L"名詞", "noun", ""}, {L"人名", "person", ""}, {L"地名", "place", ""},
    {L"動詞 (五段: 書く・ググる)", "verb", "godan"}, {L"動詞 (一段: 食べる)", "verb", "ichidan"}, {L"形容詞 (高い・エモい)", "adjective", ""},
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
    g_s.live_commit = checked(ID_LIVECOMMIT);
    g_s.ctrl_space = checked(ID_CTRLSPACE);
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

    group(L"入力", y, 184);
    make(L"STATIC", L"句読点:", 0, 24, y + 27, 170, 20, 0);
    combo(200, y + 23, 120, ID_PUNCT, {L"、。", L"，．", L"、．", L"，。"});
    make(L"BUTTON", L"何も入力していないときのスペースを全角にする", BS_AUTOCHECKBOX | WS_TABSTOP, 24, y + 54, 430, 22, ID_SPACE);
    make(L"BUTTON", L"数字を全角で入力する", BS_AUTOCHECKBOX | WS_TABSTOP, 24, y + 79, 430, 22, ID_DIGITS);
    make(L"BUTTON", L"入力中も変換候補を表示する", BS_AUTOCHECKBOX | WS_TABSTOP, 24, y + 104, 430, 22, ID_LIVE);
    make(L"BUTTON", L"変換を自動で確定する", BS_AUTOCHECKBOX | WS_TABSTOP, 24, y + 129, 430, 22, ID_LIVECOMMIT);
    make(L"BUTTON", L"Ctrl + Space でも日本語入力をオン/オフする", BS_AUTOCHECKBOX | WS_TABSTOP, 24, y + 154, 430, 22, ID_CTRLSPACE);
    y += 192;

    group(L"ユーザー辞書", y, 266);
    g_list = make(WC_LISTVIEWW, L"", LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS | WS_BORDER | WS_TABSTOP, 24, y + 22, 432, 140, ID_LIST);
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
    make(L"STATIC", L"読み:", 0, 24, y + 175, 44, 20, 0);
    make(L"EDIT", L"", ES_AUTOHSCROLL | WS_BORDER | WS_TABSTOP, 70, y + 172, 150, 23, ID_READING);
    make(L"STATIC", L"単語:", 0, 232, y + 175, 44, 20, 0);
    make(L"EDIT", L"", ES_AUTOHSCROLL | WS_BORDER | WS_TABSTOP, 278, y + 172, 178, 23, ID_WORD);
    make(L"STATIC", L"品詞:", 0, 24, y + 206, 44, 20, 0);
    HWND pos = make(WC_COMBOBOXW, L"", CBS_DROPDOWNLIST | WS_TABSTOP | WS_VSCROLL, 70, y + 202, 210, 200, ID_POS);
    for (auto& p : POS) SendMessageW(pos, CB_ADDSTRING, 0, LPARAM(p.label));
    make(L"BUTTON", L"追加", BS_PUSHBUTTON | WS_TABSTOP, 290, y + 201, 80, 25, ID_ADD);
    make(L"BUTTON", L"削除", BS_PUSHBUTTON | WS_TABSTOP, 376, y + 201, 80, 25, ID_REMOVE);
    make(L"STATIC", L"読みはひらがなで入力します。動詞と形容詞は終止形で登録します (例: ぐぐる / ググる)",
         0, 24, y + 232, 432, 30, 0);
    y += 274;

    group(L"学習", y, 60);
    make(L"BUTTON", L"学習をリセット", BS_PUSHBUTTON | WS_TABSTOP, 24, y + 24, 140, 25, ID_RESET);
    y += 70;

    std::wstring about = std::wstring(L"shunti IME ") + VERSION;
    make(L"STATIC", about.c_str(), 0, 14, y + 6, 150, 20, 0);
    make(L"BUTTON", L"ライセンス", BS_PUSHBUTTON | WS_TABSTOP, 222, y, 80, 25, ID_LICENSE);
    make(L"BUTTON", L"GitHub", BS_PUSHBUTTON | WS_TABSTOP, 308, y, 76, 25, ID_GITHUB);
    make(L"BUTTON", L"閉じる", BS_DEFPUSHBUTTON | WS_TABSTOP, 390, y, 80, 25, IDCANCEL);

    g_loading = true;
    select(ID_THEME, g_s.theme == "light" ? 1 : g_s.theme == "dark" ? 2 : 0);
    select(ID_PUNCT, g_s.punct);
    select(ID_POS, 0);
    check(ID_SPACE, g_s.space_fullwidth);
    check(ID_DIGITS, g_s.digits_fullwidth);
    check(ID_LIVE, g_s.live);
    check(ID_LIVECOMMIT, g_s.live_commit);
    check(ID_CTRLSPACE, g_s.ctrl_space);
    g_loading = false;
    refresh_list();
}

LRESULT CALLBACK proc(HWND h, UINT m, WPARAM w, LPARAM l) {
    switch (m) {
        case WM_COMMAND: {
            int id = LOWORD(w), code = HIWORD(w);
            if ((id == ID_THEME || id == ID_PUNCT) && code == CBN_SELCHANGE) save();
            else if (id == IDCANCEL) DestroyWindow(h);   // 「閉じる」と Esc
            else if (id >= ID_SPACE && id <= ID_CTRLSPACE && code == BN_CLICKED) save();
            else if (id == ID_ADD) add_word();
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

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE, PWSTR, int show) {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    // 2 つ目は開かずに、開いている窓を前に出す
    HANDLE once = CreateMutexW(nullptr, TRUE, L"ShuntiImeSettings");
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        if (HWND other = FindWindowW(L"ShuntiImeSettings", nullptr)) SetForegroundWindow(other);
        return 0;
    }
    INITCOMMONCONTROLSEX icc = {sizeof icc, ICC_LISTVIEW_CLASSES | ICC_STANDARD_CLASSES};
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
    RECT rc = {0, 0, S(480), S(712)};
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
