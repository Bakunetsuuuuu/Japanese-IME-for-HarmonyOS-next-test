// 候補の窓 (変換の候補を 9 個ずつ番号つきで出す。GDI で描く小さな窓。入力欄のアプリのプロセスの中で動く)
#pragma once
#include <windows.h>

#include <functional>
#include <vector>

#include "../core/text.h"

namespace shunti {
namespace win {

class CandWindow {
public:
    ~CandWindow();
    // anchor = 選んでいる文節の字の画面上の四角。owner = 入力欄の窓
    void show(const std::vector<u16>& cands, int sel, const RECT& anchor, HWND owner);
    void hide();
    void destroy();
    bool visible() const { return hwnd_ && IsWindowVisible(hwnd_); }
    std::function<void(int)> on_click;   // 候補をマウスで選んだ (候補の番号)

private:
    static LRESULT CALLBACK proc(HWND h, UINT m, WPARAM w, LPARAM l);
    void paint(HDC dc);
    void layout();
    int hit(int x, int y) const;

    HWND hwnd_ = nullptr;
    HWND owner_ = nullptr;
    HFONT font_ = nullptr, small_ = nullptr;
    UINT dpi_ = 0;
    std::vector<u16> cands_;
    int sel_ = 0, page_ = 0;
    int row_h_ = 0, pad_ = 0, num_w_ = 0, width_ = 0, height_ = 0, footer_h_ = 0;
};

}  // namespace win
}  // namespace shunti
