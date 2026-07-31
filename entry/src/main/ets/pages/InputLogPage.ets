// ===========================================================================
//  ★ デバッグ専用画面 / DEBUG-ONLY SCREEN ★
//  ★ リリースビルドではこのファイルごと削除すること。                     ★
//    (main_pages.json の "pages/InputLogPage" と Index.ets の入口も一緒に)
// ===========================================================================
//
// ime/InputLog.ets が集めた入力ログの閲覧・書き出し・消去。
//
// IME拡張は本体アプリと別プロセスなので、ここでは InputHandler を経由せず
// ログファイルを直接読む(SuppressedList.ets が shunti_suppressed を直接読むのと
// 同じ理由)。場所は dir() 参照。
//
// 拡張プロセスは書き出しを 4件 / 800ms でまとめているので、直前の変換が
// まだ出ていないことがある。ページに戻るたび読み直す(onPageShow)ほか、
// キーボードを閉じた時点(onInputStop)で必ず flush される。

import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import pasteboard from '@ohos.pasteboard';
import dataPreferences from '@ohos.data.preferences';
import { JP_FONT_FAMILY } from '../components/JpFont';
import { kbTheme } from '../components/Theme';
import {
  InputLog, InputLogEntry, INPUT_LOG_FILE,
  LK_COMMIT, LK_RAW, LK_RANGE, LK_BUNSETSU, LK_BSEG,
  LK_DELCAND, LK_UNKNOWN, LK_DELCHAR, LK_UNDO, LK_FIELD, LK_DIAG,
  LF_KATAKANA, LF_ALNUM, LF_KANA
} from '../ime/InputLog';

// IME拡張プロセスだけが書き込むストア。本体アプリからこれらが1つも読めなければ、
// 問題は入力ログ固有ではなく「拡張が書いたものが本体に届いていない」ことになる
// (「削除した候補」が空なのも同じ原因、という切り分けができる)。
interface ProbeStore {
  label: string;
  store: string;
  key: string;
}

interface ProbeResult {
  label: string;
  detail: string;
  ok: boolean;
}

const CARD_RADIUS = 16;

// 画面に出す最大件数。全部読み込むと 2万件のリストになるので、閲覧は直近だけ
// にして、全量はエクスポートで取る。
const VIEW_LIMIT = 400;

interface KindStyle {
  label: string;
  color: string;
}

interface KindFilter {
  label: string;
  kind: string;
}

// 種別ごとの見出し。色は「確定=中立」「消した=赤系」「構造をいじった=青系」の
// 3系統だけにして、スクロールしたときに種類が形で分かるようにする。
function kindStyle(k: string): KindStyle {
  if (k === LK_COMMIT) { return { label: '確定', color: '#4B5563' }; }
  if (k === LK_RAW) { return { label: 'かな確定', color: '#4B5563' }; }
  if (k === LK_RANGE) { return { label: '変換範囲', color: '#2563EB' }; }
  if (k === LK_BUNSETSU) { return { label: '文節区切り', color: '#2563EB' }; }
  if (k === LK_BSEG) { return { label: '文節選択', color: '#2563EB' }; }
  if (k === LK_DELCAND) { return { label: '候補削除', color: '#DC2626' }; }
  if (k === LK_UNKNOWN) { return { label: '未知語学習', color: '#7C3AED' }; }
  if (k === LK_DELCHAR) { return { label: '文字削除', color: '#DC2626' }; }
  if (k === LK_UNDO) { return { label: '取消', color: '#059669' }; }
  if (k === LK_FIELD) { return { label: '入力欄', color: '#6B7280' }; }
  if (k === LK_DIAG) { return { label: '診断', color: '#B45309' }; }
  return { label: k, color: '#6B7280' };
}

function flagLabel(x: string): string {
  if (x === LF_KATAKANA) { return 'カタカナ'; }
  if (x === LF_ALNUM) { return '英数'; }
  if (x === LF_KANA) { return 'かな'; }
  return x;
}

function hhmmss(t: number): string {
  const d = new Date(t);
  const p = (n: number): string => (n < 10 ? '0' + n : String(n));
  return `${p(d.getMonth() + 1)}/${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}

@Entry
@Component
struct InputLogPage {
  @StorageLink('isDark') isDark: boolean = false;
  @State entries: InputLogEntry[] = [];
  @State total: number = 0;
  @State bytes: number = 0;
  @State filter: string = '';
  // 消去は取り返しがつかないので二段階にする(SuppressedList の「すべて戻す」と同じ)。
  @State confirmClear: boolean = false;
  @State showDiag: boolean = false;
  @State probes: ProbeResult[] = [];
  // 拡張プロセスが自己申告したパス (LK_DIAG 記録より)。読み手側の実パスと
  // 突き合わせるためのもの。
  @State writerPaths: string = '(記録なし)';
  // 拡張プロセスが起動した回数(diag 記録の数)。ここが入力のたびに増えるなら、
  // 拡張は入力欄ごとに作り直されている = デバウンス待ちの保存が消える環境。
  @State writerStarts: number = 0;
  private probeGen: number = 0;

  private stores: ProbeStore[] = [
    { label: '削除した候補', store: 'shunti_suppressed', key: 'v1' },
    { label: '変換学習', store: 'shunti_learning', key: 'v1' },
    { label: '次の語の学習', store: 'shunti_nextword', key: 'v1' },
    { label: '未知語学習', store: 'shunti_unknown', key: 'v1' },
    { label: '記号の使用頻度', store: 'shunti_symbol_freq', key: 'v1' },
  ];
  // 絞り込みチップ。'' は「すべて」。ArkTS では interface のオブジェクトリテラル
  // 配列をトップレベル const に置けないので、クラスメンバ初期化子で持つ。
  private filters: KindFilter[] = [
    { label: 'すべて', kind: '' },
    { label: '確定', kind: LK_COMMIT },
    { label: '文節', kind: LK_BSEG },
    { label: '区切り', kind: LK_BUNSETSU },
    { label: '範囲', kind: LK_RANGE },
    { label: '候補削除', kind: LK_DELCAND },
    { label: '未知語', kind: LK_UNKNOWN },
    { label: '文字削除', kind: LK_DELCHAR },
    { label: '入力欄', kind: LK_FIELD },
  ];

  aboutToAppear(): void {
    this.reload();
  }

  // キーボードで入力してからここに戻ってきたときに古い内容が出たままにならない
  // ように読み直す。件数表示のタップでも読み直せる(下)。
  onPageShow(): void {
    this.reload();
  }

  // アプリ単位の filesDir を優先する。ability ごとの context.filesDir は
  // モジュール単位で、IME拡張と本体で一致する「はず」だが、そこを仮定すると
  // 外れたときに「拡張は書いているのに本体からは空に見える」という切り分けの
  // 難しい壊れ方をする。
  private dir(): string {
    const ctx = getContext(this) as common.UIAbilityContext;
    // 拡張側は アプリ単位を優先しつつ、取れなければモジュール単位に落ちる。
    // 片方しか見ないと、落ちた場合に「空」としか見えないので両方見る。
    return InputLog.findDir([ctx.getApplicationContext().filesDir, ctx.filesDir]);
  }

  private reload(): void {
    const d = this.dir();
    // 数MBになりうるので読むのは1回だけ。件数も一覧もこの1回から作る。
    const raw = InputLog.readRaw(d);
    this.entries = InputLog.parse(raw, VIEW_LIMIT);
    this.total = InputLog.countLines(raw);
    this.bytes = InputLog.sizeBytes(d);
    const diag = this.entries.filter((e: InputLogEntry) => e.k === LK_DIAG);
    const paths = diag.filter((e: InputLogEntry) => e.x.indexOf('log=') === 0);
    this.writerStarts = paths.length;
    this.writerPaths = paths.length > 0 ? paths[0].x.split(' ').join('\n') : '(記録なし)';
    this.runProbes();
  }

  // 拡張プロセスだけが書き込むストアを片っ端から読んでみる。例外は握り潰さず
  // そのまま表示する ── 全部空に見える画面から原因を当てられなかったのは、
  // 読み取り側が一律 try/catch で空を返していたせい。
  private runProbes(): void {
    const ctx = getContext(this);
    // 世代番号。ここを見ずに this.probes へ concat していたら、前回の呼び出しの
    // 未解決 Promise が新しい配列に後から積まれて、画面を開き直すたび行が増え、
    // 「診断」を押すと減る、という挙動になっていた。
    this.probeGen++;
    const gen = this.probeGen;
    const head: ProbeResult[] = [
      {
        label: '本体アプリ(読み手)',
        detail: `log=${this.dir()}\nfiles=${(ctx as common.UIAbilityContext).filesDir}\n`
          + `prefs=${(ctx as common.UIAbilityContext).preferencesDir}`,
        ok: true,
      },
      {
        label: `IME拡張(書き手) 起動 ${this.writerStarts} 回`,
        detail: this.writerPaths,
        ok: this.writerPaths !== '(記録なし)',
      },
    ];
    this.probes = head;
    // 5本まとめて解決させて一度に入れ替える。1本ずつ concat すると上の競合が起きる。
    const jobs: Promise<ProbeResult>[] = this.stores.map((s: ProbeStore) =>
      dataPreferences.getPreferences(ctx, s.store)
        .then((prefs: dataPreferences.Preferences) => prefs.get(s.key, ''))
        .then((v: dataPreferences.ValueType) => {
          const n = String(v).length;
          const r: ProbeResult = {
            label: s.label,
            detail: n === 0 ? '空 (このストアには何も書かれていない)' : `${n} バイト`,
            ok: n > 0,
          };
          return r;
        })
        .catch((e: Error) => {
          const r: ProbeResult = {
            label: s.label, detail: '読み取り失敗: ' + JSON.stringify(e), ok: false,
          };
          return r;
        }));
    Promise.all(jobs).then((rows: ProbeResult[]) => {
      if (gen !== this.probeGen) { return; }   // もっと新しい診断が走っている
      this.probes = head.concat(rows);
    });
  }

  private visible(): InputLogEntry[] {
    if (this.filter.length === 0) { return this.entries; }
    return this.entries.filter((e: InputLogEntry) => e.k === this.filter);
  }

  // 全量をクリップボードへ。JSONL のまま出すので、そのまま
  // `node -e` や jq で集計できる。
  private exportLog(): void {
    const raw = InputLog.readRaw(this.dir());
    if (raw.length === 0) {
      promptAction.showToast({ message: 'ログがありません' });
      return;
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, raw);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: `${this.total}件（${Math.round(this.bytes / 1024)}KB）をコピーしました` });
    }).catch(() => {
      promptAction.showToast({ message: 'コピーに失敗しました（大きすぎる場合はファイルを直接取得してください）' });
    });
  }

  private clearLog(): void {
    InputLog.clear(this.dir());
    this.confirmClear = false;
    this.reload();
    promptAction.showToast({ message: '入力ログを消去しました' });
  }

  build() {
    Column() {
      // ── Header ────────────────────────────────────────────────
      Row() {
        Row() {
          Text('‹ 戻る')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(kbTheme(this.isDark).accent)
            .onClick(() => { router.back(); })
        }
        .width(96)
        .justifyContent(FlexAlign.Start)

        Text('入力ログ（開発用）')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(kbTheme(this.isDark).textPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Row() {
          Text(this.confirmClear ? '本当に消す？' : '消去')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#DC2626')
            .onClick(() => {
              if (this.confirmClear) { this.clearLog(); } else { this.confirmClear = true; }
            })
        }
        .width(96)
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .border({ width: { bottom: 1 }, color: kbTheme(this.isDark).divider })

      // ── Summary + export ──────────────────────────────────────
      Row() {
        Column({ space: 2 }) {
          Text(`${this.total} 件 / ${Math.round(this.bytes / 1024)} KB`)
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(kbTheme(this.isDark).textPrimary)
          Text(`表示は直近 ${VIEW_LIMIT} 件・エクスポートは全件（タップで再読込）`)
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(11)
            .fontColor(kbTheme(this.isDark).textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .onClick(() => { this.reload(); })

        Text('診断')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(kbTheme(this.isDark).accent)
          .backgroundColor(kbTheme(this.isDark).funcBg)
          .borderRadius(14)
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .margin({ right: 8 })
          .onClick(() => { this.showDiag = !this.showDiag; this.runProbes(); })

        Text('JSONLをコピー')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor(kbTheme(this.isDark).accent)
          .borderRadius(14)
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .onClick(() => { this.exportLog(); })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 10 })
      .alignItems(VerticalAlign.Center)

      // ── 診断 ──────────────────────────────────────────────────
      // 「削除した候補」も「入力ログ」も、拡張が書いたものを本体が読む構造で、
      // どちらの読み取りも例外を握り潰して空を返す。だから画面からは
      // 「書けていない」「書き先と読み先が違う」「そもそも記録が無い」の
      // どれなのか区別できなかった。ここはその3つを直接見分けるためにある。
      //   ・書き手と読み手のパスが違う      -> 保存先の不一致
      //   ・拡張(書き手)が「記録なし」       -> 拡張がこのファイルに書けていない
      //   ・どのストアも空                  -> 拡張の書き込み自体が届いていない
      //   ・削除した候補だけ空              -> 削除の保存パスの問題
      if (this.showDiag || this.total === 0) {
        Column({ space: 6 }) {
          ForEach(this.probes, (p: ProbeResult) => {
            Row({ space: 8 }) {
              Text(p.ok ? '●' : '○')
                .fontSize(11)
                .fontColor(p.ok ? '#059669' : '#DC2626')
              Column({ space: 1 }) {
                Text(p.label)
                  .fontFamily(JP_FONT_FAMILY)
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(kbTheme(this.isDark).textPrimary)
                Text(p.detail)
                  .fontFamily(JP_FONT_FAMILY)
                  .fontSize(10)
                  .fontColor(kbTheme(this.isDark).textSecondary)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }, (p: ProbeResult, i: number) => `${p.label}-${i}`)
        }
        .width('100%')
        .padding(12)
        .margin({ left: 16, right: 16, bottom: 10 })
        .backgroundColor(kbTheme(this.isDark).cardBg)
        .borderRadius(12)
        .alignItems(HorizontalAlign.Start)
      }

      // ── Kind filter ───────────────────────────────────────────
      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.filters, (f: KindFilter) => {
            Text(f.label)
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(12)
              .fontColor(this.filter === f.kind ? Color.White : kbTheme(this.isDark).textSecondary)
              .backgroundColor(this.filter === f.kind
                ? kbTheme(this.isDark).accent : kbTheme(this.isDark).funcBg)
              .borderRadius(13)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .onClick(() => { this.filter = f.kind; })
          }, (f: KindFilter) => f.kind)
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .margin({ bottom: 10 })

      // ── Entries ───────────────────────────────────────────────
      if (this.visible().length === 0) {
        // 空のときこそ理由が要る。「ファイルが無い」= 書き手に届いていない
        // (パス違い/収集が動いていない)、「ファイルはあるが field だけ」=
        // 収集は動いているが記録の条件で落ちている、と切り分けられるように、
        // 保存先の実パスと状態をそのまま出す。
        Column({ space: 8 }) {
          Text(this.total === 0
            ? '入力ログはまだありません\nキーボードで変換すると記録されます'
            : 'この種別の記録はありません')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(13)
            .fontColor(kbTheme(this.isDark).textSecondary)
            .textAlign(TextAlign.Center)
          if (this.total === 0) {
            Text(`保存先: ${this.dir()}/${INPUT_LOG_FILE}\n` +
              `ファイル: ${this.bytes > 0 ? 'あり' : 'なし'}\n` +
              '上の診断で、拡張が書いたストアが1つでも読めているかを見てください')
              .fontFamily(JP_FONT_FAMILY)
              .fontSize(10)
              .fontColor(kbTheme(this.isDark).textSecondary)
              .textAlign(TextAlign.Center)
          }
        }
        .width('100%')
        .padding({ top: 48, left: 20, right: 20 })
      } else {
        List() {
          ForEach(this.visible(), (e: InputLogEntry) => {
            ListItem() {
              Row() {
                Column({ space: 3 }) {
                  Row({ space: 6 }) {
                    Text(kindStyle(e.k).label)
                      .fontFamily(JP_FONT_FAMILY)
                      .fontSize(10)
                      .fontColor(Color.White)
                      .backgroundColor(kindStyle(e.k).color)
                      .borderRadius(4)
                      .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                    Text(hhmmss(e.t))
                      .fontFamily(JP_FONT_FAMILY)
                      .fontSize(10)
                      .fontColor(kbTheme(this.isDark).textSecondary)
                    if (e.x.length > 0 && (e.k === LK_COMMIT || e.k === LK_BSEG)) {
                      Text(flagLabel(e.x))
                        .fontFamily(JP_FONT_FAMILY)
                        .fontSize(10)
                        .fontColor(kbTheme(this.isDark).textSecondary)
                    }
                  }
                  Text(e.r.length > 0 ? `${e.r} → ${e.s}` : e.s)
                    .fontFamily(JP_FONT_FAMILY)
                    .fontSize(15)
                    .fontColor(kbTheme(this.isDark).textPrimary)
                  // 区切り位置・変換範囲はここが本体なので、確定系と違って
                  // x をそのまま出す。
                  if (e.x.length > 0 && (e.k === LK_BUNSETSU || e.k === LK_RANGE || e.k === LK_DELCHAR ||
                      e.k === LK_FIELD || e.k === LK_DIAG)) {
                    Text(e.x)
                      .fontFamily(JP_FONT_FAMILY)
                      .fontSize(11)
                      .fontColor(kbTheme(this.isDark).textSecondary)
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                // 何番目の候補を選んだか。ここが 0 以外に散っている読みが、
                // 並び順を直すべき対象そのもの。
                if (e.i >= 0) {
                  Text(e.n > 0 ? `${e.i + 1}/${e.n}` : `${e.i + 1}`)
                    .fontFamily(JP_FONT_FAMILY)
                    .fontSize(13)
                    .fontWeight(e.i === 0 ? FontWeight.Normal : FontWeight.Bold)
                    .fontColor(e.i === 0 ? kbTheme(this.isDark).textSecondary : '#DC2626')
                }
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 9, bottom: 9 })
              .backgroundColor(kbTheme(this.isDark).cardBg)
              .alignItems(VerticalAlign.Center)
            }
          }, (e: InputLogEntry, idx: number) => `${e.t}-${idx}`)
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(kbTheme(this.isDark).cardBg)
        .borderRadius(CARD_RADIUS)
        .clip(true)
        .margin({ left: 16, right: 16 })
        .divider({ strokeWidth: 1, color: kbTheme(this.isDark).divider })
      }

      Text(`端末内 files/${INPUT_LOG_FILE} に保存・送信はしません（リリース版には含めない機能です）`)
        .fontFamily(JP_FONT_FAMILY)
        .fontSize(11)
        .fontColor(kbTheme(this.isDark).textSecondary)
        .textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24, top: 12, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(kbTheme(this.isDark).panelBg)
  }
}
