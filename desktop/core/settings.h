// PC 版の設定 (設定画面が書き、IME が読む。%APPDATA%\shunti IME\settings.json)。
// IME はアプリごとのプロセスに読み込まれるので、入力を始めるたびにファイルの更新を見て読み直す。
#pragma once
#include <filesystem>
#include <string>

namespace shunti {

struct Settings {
    std::string theme = "auto";      // 候補の窓の色: auto (Windows に合わせる)・light・dark
    bool space_fullwidth = true;     // 何も打っていないときの空白を全角に (Shift で逆)
    int punct = 0;                   // 句読点: 0 = 、。 1 = ，． 2 = 、． 3 = ，。
    bool digits_fullwidth = false;   // 数字を全角で入れる
    bool live = true;                // 打っている間も候補を出す
    bool live_commit = true;         // リアルタイム確定
    bool live_display = false;       // ライブ変換: 入力中の文字を、空白を押す前から変換して見せる
    bool ctrl_space = false;         // Ctrl+Space でも日本語入力のオン・オフ
    std::string model = "standard";  // 変換モデル: light (XS・メモリの少ない PC 向け)・standard (S6)・high (M4・速い PC 向け)
};

// 変換モデルの設定の値 -> モデルのファイル名 (辞書と同じフォルダ)。知らない値は standard
const char* model_file_name(const std::string& model);

// 読む (無い・壊れていれば既定のまま)。書く (一時ファイルから置き換える)
bool load_settings(const std::filesystem::path& p, Settings& s);
bool save_settings(const std::filesystem::path& p, const Settings& s);

// ファイルが変わっていたら読み直すための控え
class SettingsFile {
public:
    explicit SettingsFile(std::filesystem::path p) : path_(std::move(p)) {}
    // 変わっていれば読み直して true
    bool refresh();
    const Settings& get() const { return s_; }

private:
    std::filesystem::path path_;
    std::filesystem::file_time_type stamp_{};
    bool loaded_ = false;
    Settings s_;
};

}  // namespace shunti
