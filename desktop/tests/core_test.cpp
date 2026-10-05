// PC 版の共通部分 (desktop/core) の試験。IME なしで打鍵を流し込み、入力中の見せ方と確定した文を確かめる。
//   core_test.exe <kkc_lex.bin> <kkc_model.bin> [作業用のフォルダ]
// 期待と違えば FAIL を出し、終了コードを 1 にする。変換の時間も出す。
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

#include "../core/composer.h"
#include "../core/pos_classes.h"
#include "../core/romaji.h"
#include "../core/text.h"

#ifdef _WIN32
#include <windows.h>
#endif

using namespace shunti;
namespace fs = std::filesystem;

static int failures = 0;

static std::string u8(const u16& s) { return to_utf8(s); }

static void expect(const char* name, const u16& got, const u16& want) {
    if (got == want) { printf("ok   %s: %s\n", name, u8(got).c_str()); return; }
    printf("FAIL %s: got [%s] want [%s]\n", name, u8(got).c_str(), u8(want).c_str());
    failures++;
}

static std::vector<char> slurp(const char* p) {
    std::ifstream f(p, std::ios::binary);
    return std::vector<char>((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
}

// 打鍵の列: 普通の字はそのまま、{sp} {enter} {esc} {bs} {del} {left} {right} {up} {down} {home} {end} {tab}
// {pgdn} {pgup} {f6}〜{f10} {henkan} {muhenkan}、Shift つきは {S-left} のように
static void keys(Composer& c, const std::string& seq) {
    u16 s = from_utf8(seq);
    for (size_t i = 0; i < s.size(); i++) {
        KeyEvent ev;
        if (s[i] == u'{') {
            size_t j = s.find(u'}', i);
            std::string name = to_utf8(s.substr(i + 1, j - i - 1));
            i = j;
            if (name.rfind("S-", 0) == 0) { ev.shift = true; name = name.substr(2); }
            struct { const char* n; Key k; } names[] = {
                {"sp", Key::Space}, {"enter", Key::Enter}, {"esc", Key::Escape}, {"bs", Key::Backspace}, {"del", Key::Delete},
                {"left", Key::Left}, {"right", Key::Right}, {"up", Key::Up}, {"down", Key::Down}, {"home", Key::Home},
                {"end", Key::End}, {"tab", Key::Tab}, {"pgdn", Key::PageDown}, {"pgup", Key::PageUp}, {"f6", Key::F6},
                {"f7", Key::F7}, {"f8", Key::F8}, {"f9", Key::F9}, {"f10", Key::F10}, {"henkan", Key::Henkan},
                {"muhenkan", Key::Muhenkan},
            };
            bool found = false;
            for (auto& n : names) if (name == n.n) { ev.key = n.k; found = true; }
            if (!found) { printf("unknown key %s\n", name.c_str()); failures++; }
        } else {
            ev.key = Key::Char;
            ev.ch = s[i];
            ev.shift = s[i] >= u'A' && s[i] <= u'Z';
        }
        c.press(ev);
    }
}

static u16 segs_of(const View& v) {
    u16 o;
    for (auto& sp : v.spans) {
        if (!o.empty()) o += u"|";
        if (sp.kind == SpanKind::Focused) o += u"[";
        o += v.text.substr(size_t(sp.start), size_t(sp.len));
        if (sp.kind == SpanKind::Focused) o += u"]";
    }
    return o;
}

int main(int argc, char** argv) {
#ifdef _WIN32
    SetConsoleOutputCP(CP_UTF8);
#endif
    if (argc < 3) { printf("usage: core_test <lex> <model> [workdir]\n"); return 2; }
    fs::path work = argc > 3 ? fs::path(argv[3]) : fs::temp_directory_path() / "shunti_core_test";
    fs::create_directories(work);
    fs::remove(work / "learned.json");
    fs::remove(work / "userdict.json");

    // ---- ローマ字
    {
        Romaji r;
        auto run = [&](const char* in) {
            u16 out;
            for (const char* p = in; *p; p++) out += r.process(char16_t(*p)).committed;
            out += r.flush();
            return out;
        };
        expect("romaji konnnichiha", run("konnnichiha"), u"こんにちは");
        expect("romaji kanji", run("kanji"), u"かんじ");
        expect("romaji n'a", run("kan'i"), u"かんい");
        expect("romaji tte", run("kitte"), u"きって");
        expect("romaji z/", run("z/"), u"・");
        expect("romaji ca", run("cocoa"), u"ここあ");
        expect("romaji end n", run("hon"), u"ほん");
        expect("to_romaji", r.to_romaji(u"とうきょうでしゅっぱつ"), u"toukyoudeshuppatsu");
        expect("to_romaji n", r.to_romaji(u"かんい"), u"kanni");
    }
    expect("halfwidth kana", to_halfwidth_kana(u"ガッコウ　パン"), u"ｶﾞｯｺｳ ﾊﾟﾝ");

    auto lex = slurp(argv[1]);
    auto model = slurp(argv[2]);
    Converter conv;
    const char* th = getenv("SHUNTI_THREADS");
    auto t_open = std::chrono::steady_clock::now();
    if (!conv.open(lex.data(), lex.size(), model.data(), model.size(), th ? atoi(th) : 1)) { printf("engine open failed\n"); return 2; }
    printf("     engine open %.1f ms (threads %d)\n",
           std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t_open).count(), th ? atoi(th) : 1);
    Learning learning(work / "learned.json");
    UserDict dict(work / "userdict.json");
    Composer c(&conv, &learning, &dict);
    c.options.live_commit = false;   // リアルタイム確定は下でまとめて試す

    // ---- 語の区切りと品詞 (文節の分け方を見る)
    for (const char16_t* r : {u"きょうはいいてんきですね", u"わたしはがくせいです", u"たべさせられなかった"}) {
        Conversion cv = conv.convert(u"", r, 3);
        printf("     words:");
        for (auto& w : cv.words) printf(" %s/%s(%d:%c,%d:%c)", u8(w.reading).c_str(), u8(w.surface).c_str(), w.lid,
                                        POS_CLASSES[w.lid], w.rid, POS_CLASSES[w.rid]);
        printf("\n");
    }

    // ---- 1 打鍵ごとの重さ (打っている間の変換と予測)
    {
        auto ms_of = [](auto f) {
            auto t = std::chrono::steady_clock::now();
            for (int i = 0; i < 20; i++) f();
            return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t).count() / 20;
        };
        printf("     convert 8 kana %.1f ms, 16 kana %.1f ms, complete %.1f ms\n",
               ms_of([&] { conv.convert(u"今日は", u"いいてんきです", 10); }),
               ms_of([&] { conv.convert(u"今日は", u"いいてんきですねさんぽにいき", 10); }),
               ms_of([&] { conv.complete(u"いいてんき", 4); }));
    }

    // ---- 入力中の見せ方
    keys(c, "kyouha");
    expect("input text", c.view().text, u"きょうは");
    keys(c, "k");
    expect("pending romaji", c.view().text, u"きょうはk");
    keys(c, "{bs}{esc}");
    expect("esc clears", c.view().text, u"");

    // ---- 変換と文節
    auto t0 = std::chrono::steady_clock::now();
    keys(c, "kyouhaiitenkidesune{sp}");
    double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    printf("     convert took %.1f ms\n", ms);
    expect("convert", c.view().text, u"今日はいい天気ですね");
    printf("     phrases: %s\n", u8(segs_of(c.view())).c_str());
    keys(c, "{enter}");
    expect("commit", c.take_commit(), u"今日はいい天気ですね");

    keys(c, "watashihagakuseidesu{sp}");
    printf("     phrases: %s\n", u8(segs_of(c.view())).c_str());
    keys(c, "{right}{sp}");
    printf("     2nd phrase cands:");
    for (auto& x : c.view().cands) printf(" %s", u8(x).c_str());
    printf("\n");
    keys(c, "{esc}");
    expect("back to input", c.view().text, u"わたしはがくせいです");
    keys(c, "{esc}");

    // Shift+← で文節を縮める
    keys(c, "kaisyanidenwasuru{sp}");
    printf("     phrases: %s\n", u8(segs_of(c.view())).c_str());
    keys(c, "{S-left}");
    printf("     after S-left: %s\n", u8(segs_of(c.view())).c_str());
    keys(c, "{esc}{esc}");

    // ---- F6〜F10
    keys(c, "toukyou{f7}");
    expect("F7", c.view().text, u"トウキョウ");
    keys(c, "{f10}");
    expect("F10", c.view().text, u"toukyou");
    keys(c, "{f10}");
    expect("F10 again", c.view().text, u"TOUKYOU");
    keys(c, "{f10}");
    expect("F10 3rd", c.view().text, u"Toukyou");
    keys(c, "{f9}");
    expect("F9", c.view().text, u"ｔｏｕｋｙｏｕ");
    keys(c, "{f8}");
    expect("F8", c.view().text, u"ﾄｳｷｮｳ");
    keys(c, "{esc}{esc}");

    // ---- 無変換キーは押すたびに カタカナ → 半角カタカナ → ひらがな
    keys(c, "toukyou{muhenkan}");
    expect("muhenkan 1", c.view().text, u"トウキョウ");
    keys(c, "{muhenkan}");
    expect("muhenkan 2", c.view().text, u"ﾄｳｷｮｳ");
    keys(c, "{muhenkan}");
    expect("muhenkan 3", c.view().text, u"とうきょう");
    keys(c, "{esc}{esc}");

    // ---- 打っている間の候補と、↓ で選んで確定
    keys(c, "konnnichiha");
    printf("     live cands:");
    for (auto& x : c.view().cands) printf(" %s", u8(x).c_str());
    printf("\n");
    if (!c.view().cand_open) { printf("FAIL live cands not shown\n"); failures++; }
    keys(c, "{down}{enter}");
    expect("live select", c.take_commit(), u"こんにちは");

    // ---- 変換したらすぐ候補の窓が出る
    keys(c, "kawa{sp}");
    if (!c.view().cand_open) { printf("FAIL cands not open after convert\n"); failures++; }
    keys(c, "{esc}{esc}");

    // ---- リアルタイム確定: 長く打つと前の方が確定されていく
    c.options.live_commit = true;
    keys(c, "kyouhaiitenkidesunesanponiikitaikedoamegafurisoudesu");
    u16 auto_commit = c.take_commit();
    printf("     live commit: [%s] + composing [%s]\n", u8(auto_commit).c_str(), u8(c.view().text).c_str());
    if (auto_commit.empty()) { printf("FAIL no live commit\n"); failures++; }
    keys(c, "{sp}{enter}");
    printf("     rest: %s\n", u8(c.take_commit()).c_str());

    // ---- ライブ変換: 入力中の文字を、空白を押す前から変換して見せ、Enter でそのまま確定する
    c.options.live_commit = false;
    c.options.live_display = true;
    keys(c, "kyouhaiitenki");
    printf("     live display: [%s]\n", u8(c.view().text).c_str());
    if (c.view().text == u"きょうはいいてんき") { printf("FAIL live display shows kana\n"); failures++; }
    u16 shown = c.view().text;
    keys(c, "{enter}");
    expect("live display enter commits what is shown", c.take_commit(), shown);
    keys(c, "kyouhaiiten{left}{enter}");   // 読みの途中にカーソルを動かしたら、かなで見せてかなで確定
    expect("live display falls back to kana mid-reading", c.take_commit(), u"きょうはいいてん");
    c.options.live_display = false;

    // ---- 打ち間違いを消して子音だけが残ったとき、続けて打った字とつながる
    keys(c, "ps{bs}a{enter}");
    expect("typo p+a", c.take_commit(), u"ぱ");
    keys(c, "kx{bs}ya{enter}");
    expect("typo k+ya", c.take_commit(), u"きゃ");
    keys(c, "kitx{bs}te{enter}");
    expect("typo t+te", c.take_commit(), u"きって");
    keys(c, "tq{bs}su{enter}");
    expect("typo t+su", c.take_commit(), u"つ");

    // ---- 英字・数字・記号
    keys(c, "Google{enter}");
    expect("uppercase run", c.take_commit(), u"Google");
    keys(c, "03-1234{enter}");
    expect("digits", c.take_commit(), u"03-1234");
    keys(c, "hai,sou.{enter}");
    expect("punct", c.take_commit(), u"はい、そう。");
    keys(c, "{sp}");
    expect("idle space", c.take_commit(), u"　");

    // ---- 変換中に次を打つと確定してから
    keys(c, "neko{sp}ga");
    expect("type after convert", c.take_commit(), u"猫");
    expect("new input", c.view().text, u"が");
    keys(c, "{esc}");

    // ---- 学習: 選び直した文節を覚える
    keys(c, "kawa{sp}");
    u16 first = c.view().text;
    keys(c, "{sp}");
    u16 second = c.view().text;
    keys(c, "{enter}");
    c.take_commit();
    keys(c, "kawa{sp}");
    expect("learned", c.view().text, second);
    printf("     (first was %s)\n", u8(first).c_str());
    keys(c, "{esc}{esc}");

    // ---- ユーザー辞書
    std::string err = dict.add(u"しゅんてぃ", u"shunti", "noun", "");
    if (!err.empty()) { printf("FAIL userdict add: %s\n", err.c_str()); failures++; }
    keys(c, "shunnthiha{sp}");
    printf("     userdict: %s\n", u8(c.view().text).c_str());
    keys(c, "{esc}{esc}");

    // ---- 長い文
    std::string longr;
    for (int i = 0; i < 12; i++) longr += "kyouhaiitenkidesune";
    t0 = std::chrono::steady_clock::now();
    keys(c, longr + "{sp}");
    ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    printf("     long (%zu kana) convert %.1f ms: %s\n", size_t(12 * 11), ms, u8(c.view().text).substr(0, 60).c_str());
    keys(c, "{esc}{esc}");

    // ---- 括弧は全種類を候補に出す (24 種類。打った字が 1 位、かっこ は組で)
    {
        auto count_in = [](const std::vector<u16>& cands, std::initializer_list<const char16_t*> want) {
            int n = 0;
            for (auto* w : want) n += std::find(cands.begin(), cands.end(), u16(w)) != cands.end();
            return n;
        };
        auto check = [&](const char* name, const std::string& seq, const char16_t* top, std::initializer_list<const char16_t*> want) {
            keys(c, seq);
            const std::vector<u16>& cs = c.view().cands;
            expect(name, cs.empty() ? u"" : cs[0], top);
            int n = count_in(cs, want);
            if (n != int(want.size())) { printf("FAIL %s: %d / %zu kinds in cands\n", name, n, want.size()); failures++; }
            keys(c, "{esc}{esc}");
        };
        std::initializer_list<const char16_t*> opens = {u"（", u"(", u"「", u"『", u"【", u"［", u"[", u"｛", u"{", u"〔", u"〈", u"《",
                                                         u"〖", u"〘", u"〚", u"｢", u"＜", u"<", u"«", u"‹", u"“", u"‘", u"〝", u"｟"};
        std::initializer_list<const char16_t*> closes = {u"）", u")", u"」", u"』", u"】", u"］", u"]", u"｝", u"}", u"〕", u"〉", u"》",
                                                          u"〗", u"〙", u"〛", u"｣", u"＞", u">", u"»", u"›", u"”", u"’", u"〟", u"｠"};
        check("bracket open (live)", "[", u"「", opens);
        check("bracket open (convert)", "[{sp}", u"「", opens);
        check("bracket close (convert)", "]{sp}", u"」", closes);
        check("bracket paren (convert)", "({sp}", u"（", opens);
        keys(c, "kakko{sp}");
        int pairs = count_in(c.view().cands, {u"（）", u"「」", u"『』", u"【】", u"〘〙", u"〚〛", u"｟｠", u"«»", u"“”", u"〝〟"});
        if (pairs != 10) { printf("FAIL kakko: %d / 10 pairs in cands\n", pairs); failures++; }
        else printf("ok   kakko: all pairs in cands\n");
        keys(c, "{esc}{esc}");
    }

    printf(failures ? "\n%d FAILED\n" : "\nall ok\n", failures);
    return failures ? 1 : 0;
}
