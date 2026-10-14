// 候補の窓 (変換の候補を 9 個ずつ番号つきで出す。GDI で描く小さな窓。入力欄のアプリのプロセスの中で動く)
#pragma once
#include <windows.h>

#include <functional>
#include <string>
#include <vector>

#include "../core/text.h"

namespace shunti {
namespace win {

class CandWindow {
public:
    ~CandWindow();
    // anchor = 選んでいる文節の字の画面上の四角。owner = 入力欄の窓
    // sugg = 提案 (候補の上の 1 行。空なら出さない)
    // sugg = 提案 (いちばん下の行の左に札で並べる)。sugg_sel = 選んでいる提案 (-1 = 提案の列に入っていない)
    void show(const std::vector<u16>& cands, int sel, const RECT& anchor, HWND owner, const std::vector<u16>& sugg = {},
              int sugg_sel = -1, const std::vector<u16>& notes = {});   // notes = 候補の右に薄く添える種類
    void hide();
    void destroy();
    bool visible() const { return hwnd_ && IsWindowVisible(hwnd_); }
    std::function<void(int)> on_click;   // 候補をマウスで選んだ (候補の番号)
    std::function<void(int)> on_sugg_click;   // 提案をマウスで選んだ (提案の番号)
    std::wstring label;                        // 下の行の頭の字 (空なら「提案 Shift+↓」。文の流れの続きでは「続き Tab」)
    std::string theme = "auto";          // auto (Windows に合わせる)・light・dark

private:
    static LRESULT CALLBACK proc(HWND h, UINT m, WPARAM w, LPARAM l);
    void paint(HDC dc);
    void layout();
    int hit(int x, int y) const;
    int hit_sugg(int x, int y) const;
    std::wstring sugg_label() const;
    std::wstring foot_text(int n) const;

    HWND hwnd_ = nullptr;
    HWND owner_ = nullptr;
    HFONT font_ = nullptr, small_ = nullptr;
    UINT dpi_ = 0;
    std::vector<u16> cands_;
    std::vector<u16> notes_;
    std::vector<u16> sugg_;
    std::vector<std::pair<int, int>> sugg_x_;   // 提案の札の左右 (当たり判定)
    int sugg_sel_ = -1;
    int sel_ = 0, page_ = 0;
    int row_h_ = 0, pad_ = 0, num_w_ = 0, width_ = 0, height_ = 0, footer_h_ = 0;
};

}  // namespace win
}  // namespace shunti
