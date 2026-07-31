// ===========================================================================
//  ★ デバッグ専用画面 / DEBUG-ONLY SCREEN ★
//  ★ リリースビルドではこのファイルごと削除すること。                     ★
//    (main_pages.json の "pages/InputLogPage" と Index.ets の入口も一緒に)
// ===========================================================================
//
// ime/InputLog.ets が集めた入力ログの閲覧・書き出し・消去。
//
// IME拡張は本体アプリと別プロセスなので、ここでは InputHandler を経由せず
// filesDir 上のログファイルを直接読む(SuppressedList.ets が
// shunti_suppressed を直接読むのと同じ理由)。同じモジュール(entry)の
// ability 同士なので filesDir は一致する。

import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import pasteboard from '@ohos.pasteboard';
import { JP_FONT_FAMILY } from '../components/JpFont';
import { kbTheme } from '../components/Theme';
import {
  InputLog, InputLogEntry, INPUT_LOG_FILE,
  LK_COMMIT, LK_RAW, LK_RANGE, LK_BUNSETSU, LK_BSEG,
  LK_DELCAND, LK_UNKNOWN, LK_DELCHAR, LK_UNDO,
  LF_KATAKANA, LF_ALNUM, LF_KANA
} from '../ime/InputLog';

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
  ];

  aboutToAppear(): void {
    this.reload();
  }

  // IME拡張は module 'entry' の extensionAbility、この画面は同じ module の
  // UIAbility なので filesDir は同じディレクトリを指す。だから拡張が書いた
  // ファイルをここからそのまま読める。
  private dir(): string {
    return (getContext(this) as common.UIAbilityContext).filesDir;
  }

  private reload(): void {
    const d = this.dir();
    // 数MBになりうるので読むのは1回だけ。件数も一覧もこの1回から作る。
    const raw = InputLog.readRaw(d);
    this.entries = InputLog.parse(raw, VIEW_LIMIT);
    this.total = InputLog.countLines(raw);
    this.bytes = InputLog.sizeBytes(d);
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
          Text(`表示は直近 ${VIEW_LIMIT} 件・エクスポートは全件`)
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(11)
            .fontColor(kbTheme(this.isDark).textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

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
        Column() {
          Text(this.total === 0
            ? '入力ログはまだありません\nキーボードで変換すると記録されます'
            : 'この種別の記録はありません')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(13)
            .fontColor(kbTheme(this.isDark).textSecondary)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding({ top: 48 })
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
                  if (e.x.length > 0 && (e.k === LK_BUNSETSU || e.k === LK_RANGE || e.k === LK_DELCHAR)) {
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
