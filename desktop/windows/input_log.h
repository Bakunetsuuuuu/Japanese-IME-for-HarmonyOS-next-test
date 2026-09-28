// ===========================================================================
//  ★ デバッグ用のビルドだけ・入力の記録 / DEBUG-BUILD-ONLY INPUT LOG ★
// ===========================================================================
// 変換の精度と学習の効き具合を、このパソコンの持ち主が実際に打った入力から測るための記録
// (HarmonyOS 版 InputLog.ets と同じ種別とキーの JSONL。shuntllim の評価のスクリプトがそのまま読む)。
//
// SHUNTI_INPUT_LOG を定義してビルドしたとき (desktop\windows\build.bat debug → desktop\build\dist_debug) だけ中身が入る。
// 定義しないリリース用のビルド (build.bat → dist、配る zip) では、下の関数はすべて何もしない空の inline になる。
//
// 記録する: 変換して確定 (読み・表記・候補・選んだ番号・左の文脈・文節)、文節の選び直し、リアルタイム確定、
//           かなのまま確定・変換の取り消し、入力欄の切り替え、確定したあとの Backspace (消した事実だけ)
// 記録しない: パスワードの欄 (入力の範囲が IS_PASSWORD など) の中身
// 置き場所: %APPDATA%\shunti IME\debug_input_log.jsonl だけ。送信は一切しない。
// ★ 記録は実際に打った文そのもの。git に入れない (*.jsonl は .gitignore 済み)。チャットには集計だけを出す。
// ===========================================================================
#pragma once
#include <string>

#include "../core/composer.h"

namespace shunti {
namespace win {

#ifdef SHUNTI_INPUT_LOG
constexpr bool INPUT_LOG_ENABLED = true;
void input_log(const LogEvent& e);
void input_log_simple(const char* kind, const std::string& extra = "");
#else
constexpr bool INPUT_LOG_ENABLED = false;
inline void input_log(const LogEvent&) {}
inline void input_log_simple(const char*, const std::string& = "") {}
#endif

}  // namespace win
}  // namespace shunti
