// Linux 版 (Fcitx5 の入力メソッドのアドオン)。変換の動きはすべて共通部分 (desktop/core の Composer) で、
// ここは Fcitx5 との受け渡し (キー → Composer、入力中の文字・候補の窓・確定する文 → Fcitx5) だけ。Windows 版の text_service と同じ役目。
#pragma once
#include <fcitx-config/configuration.h>
#include <fcitx-config/option.h>
#include <fcitx/addonfactory.h>
#include <fcitx/addonmanager.h>
#include <fcitx/inputcontextproperty.h>
#include <fcitx/inputmethodengine.h>
#include <fcitx/instance.h>

#include <memory>

#include "../../core/composer.h"
#include "../../core/converter.h"
#include "../../core/store.h"

namespace shunti {
namespace fx {

// 設定 (Fcitx5 の設定の画面から変える。~/.config/fcitx5/conf/shunti.conf)。Windows 版の設定画面と同じ項目
FCITX_CONFIGURATION(
    ShuntiConfig,
    fcitx::Option<bool> live{this, "Live", "打っている間も候補を出す", true};
    fcitx::Option<bool> liveCommit{this, "LiveCommit", "変換を自動で確定する", true};
    fcitx::Option<bool> spaceFullwidth{this, "SpaceFullwidth", "空白を全角にする (Shift を押すと逆)", true};
    fcitx::Option<bool> digitsFullwidth{this, "DigitsFullwidth", "数字を全角にする", false};
    fcitx::Option<int, fcitx::IntConstrain> punct{this, "Punct", "句読点 (0 = 、。 1 = ，． 2 = 、． 3 = ，。)", 0,
                                                  fcitx::IntConstrain(0, 3)};);

// 変換エンジン・学習・ユーザー辞書 (Fcitx5 のプロセスに 1 つ)
struct Core {
    Converter conv;
    Learning learning;
    UserDict dict;
    Core();
};

class ShuntiEngine;

// 入力欄ごとの状態 (Composer を 1 つずつ持つ)
class ShuntiState : public fcitx::InputContextProperty {
public:
    ShuntiState(ShuntiEngine* engine, fcitx::InputContext* ic);
    void keyEvent(fcitx::KeyEvent& event);
    void apply();                   // 確定する文・入力中の文字・候補の窓を Fcitx5 へ
    void finish();                  // 入力中のものを見えているまま確定する (入力欄を離れたとき・切り替えたとき)
    void cancel();                  // 入力中のものを捨てる (アプリが入力欄を作り直したとき)
    void selectCandidate(int index);
    void focusIn() { composer_.reset_history(); }

private:
    ShuntiEngine* engine_;
    fcitx::InputContext* ic_;
    Composer composer_;
};

class ShuntiEngine : public fcitx::InputMethodEngineV2 {
public:
    explicit ShuntiEngine(fcitx::Instance* instance);
    void keyEvent(const fcitx::InputMethodEntry& entry, fcitx::KeyEvent& event) override;
    void activate(const fcitx::InputMethodEntry& entry, fcitx::InputContextEvent& event) override;
    void deactivate(const fcitx::InputMethodEntry& entry, fcitx::InputContextEvent& event) override;
    void reset(const fcitx::InputMethodEntry& entry, fcitx::InputContextEvent& event) override;

    const fcitx::Configuration* getConfig() const override { return &config_; }
    void setConfig(const fcitx::RawConfig& raw) override;
    void reloadConfig() override;

    ShuntiState* state(fcitx::InputContext* ic) { return ic->propertyFor(&factory_); }
    Core& core();
    void applyConfig(Composer& c) const;

private:
    fcitx::Instance* instance_;
    ShuntiConfig config_;
    std::unique_ptr<Core> core_;
    fcitx::FactoryFor<ShuntiState> factory_;
};

class ShuntiEngineFactory : public fcitx::AddonFactory {
public:
    fcitx::AddonInstance* create(fcitx::AddonManager* manager) override { return new ShuntiEngine(manager->instance()); }
};

}  // namespace fx
}  // namespace shunti
