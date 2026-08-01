import { InputHandler } from '../ime/KeyboardController';
import { kbTheme } from './Theme';
import { JP_FONT_FAMILY } from './JpFont';
import { promptAction } from '@kit.ArkUI';

// ユーザー辞書の「任意の語を手で登録する」欄。
//
// 設定パネル (SettingsBar) の中に置くことはできない。あのパネルは
// SymbolView/EmojiView と同じくキーボードの代わりに全面を占有するので、
// 欄をタップしても打つためのキーが画面に無いため。
// そこで候補バーの位置にこの細いバーだけを出し、下のキーボードはそのまま
// 使えるようにしている。打った文字がこの欄に入る仕組みは
// InputHandler.insertText 側の差し替えで実現している。
//
// ★ 2つの欄は共通の @Builder にまとめず、それぞれ直接書いてある。
//   引数付きの @Builder に値を渡すと、元の @StorageLink が変わっても
//   再描画されない (SettingsBar のセグメント切替にも同じ注意書きがある)。
//   実際、値を引数で渡していたときは「入力中は見えるのに確定すると消える」
//   という症状が出た。入力中の文字は this.composingText を直に読んでいたので
//   更新され、確定後の値は引数のまま古い空文字が表示されていたため。
@Component
export struct DictEditBar {
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('dictEditYomi') dictEditYomi: string = '';
  @StorageLink('dictEditWord') dictEditWord: string = '';
  // いまどちらの欄に打鍵が入るか ('yomi' | 'word' | '')。
  @StorageLink('dictCaptureTarget') dictCaptureTarget: string = '';
  // 入力途中のかな。欄に入るのは確定した文字だけなので、これを足して
  // 表示しないと打っている最中に何も起きていないように見える。
  @StorageLink('composingText') composingText: string = '';
  @StorageLink('pendingRomaji') pendingRomaji: string = '';
  // 品詞。活用展開を駆動するので、動詞・形容詞はここで指定しないと
  // 「〜ます」「〜た」等で引けない (ConjugationEngine.buildUserExpansion)。
  @StorageLink('dictEditPos') dictEditPos: string = 'noun';
  // 動詞のみ。読みが「る」で終わると五段/一段が字面で区別できないため必要。
  @StorageLink('dictEditVerbGroup') dictEditVerbGroup: string = '';

  // 品詞の選択チップ。引数付き @Builder は @StorageLink の変化で再描画されない
  // ため使わず、呼び出し側で直接書いている (このファイル冒頭の注意書き参照)。
  private posLabel(pos: string): string {
    if (pos === 'verb') { return '動詞'; }
    if (pos === 'adjective') { return '形容詞'; }
    if (pos === 'person') { return '人名'; }
    if (pos === 'place') { return '地名'; }
    return '名詞';
  }

  // 欄に出す文字。選択中は入力途中の文字も続けて見せる。
  // 空でも '' を返さない ── Text が空だと高さが潰れて欄が線になってしまうため
  // (実機で単語欄だけ細い線になっていた)。
  private shownYomi(): string {
    const v = this.dictCaptureTarget === 'yomi'
      ? this.dictEditYomi + this.composingText + this.pendingRomaji
      : this.dictEditYomi;
    return v.length > 0 ? v : (this.dictCaptureTarget === 'yomi' ? '入力中' : 'タップ');
  }

  private shownWord(): string {
    const v = this.dictCaptureTarget === 'word'
      ? this.dictEditWord + this.composingText + this.pendingRomaji
      : this.dictEditWord;
    return v.length > 0 ? v : (this.dictCaptureTarget === 'word' ? '入力中' : 'タップ');
  }

  build() {
    Column({ space: 4 }) {
    // ── 品詞。名詞以外は活用展開に効くので必ず選べるようにしておく ──
    Row({ space: 6 }) {
      ForEach(['noun', 'verb', 'adjective', 'person', 'place'], (pos: string) => {
        Text(this.posLabel(pos))
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(11)
          .fontColor(this.dictEditPos === pos
            ? kbTheme(this.isDark).onAccent
            : kbTheme(this.isDark).textSecondary)
          .backgroundColor(this.dictEditPos === pos
            ? kbTheme(this.isDark).accent
            : kbTheme(this.isDark).keyBg)
          .borderRadius(10)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .onClick(() => {
            AppStorage.setOrCreate('dictEditPos', pos);
            if (pos !== 'verb') { AppStorage.setOrCreate('dictEditVerbGroup', ''); }
          })
      }, (pos: string) => pos)

      // 五段/一段は「る」で終わる動詞でのみ意味を持つ。
      if (this.dictEditPos === 'verb') {
        ForEach(['godan', 'ichidan'], (g: string) => {
          Text(g === 'godan' ? '五段' : '一段')
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(11)
            .fontColor(this.dictEditVerbGroup === g
              ? kbTheme(this.isDark).onAccent
              : kbTheme(this.isDark).textSecondary)
            .backgroundColor(this.dictEditVerbGroup === g
              ? kbTheme(this.isDark).accentStrong
              : kbTheme(this.isDark).keyBg)
            .borderRadius(10)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .onClick(() => { AppStorage.setOrCreate('dictEditVerbGroup', g); })
        }, (g: string) => g)
      }
    }
    .width('100%')

    Row({ space: 6 }) {
      // ── よみ ──
      Column({ space: 2 }) {
        Text('よみ')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(9)
          .fontColor(kbTheme(this.isDark).textSecondary)
          .width('100%')
        // 高さを固定して2つの欄を必ず同じ大きさに保つ。
        Row() {
          Text(this.shownYomi())
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(14)
            .fontColor(this.dictEditYomi.length > 0
              ? kbTheme(this.isDark).textPrimary
              : kbTheme(this.isDark).textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .height(34)
        .padding({ left: 8, right: 8 })
        .alignItems(VerticalAlign.Center)
        .backgroundColor(kbTheme(this.isDark).keyBg)
        .borderRadius(6)
        .border({
          width: this.dictCaptureTarget === 'yomi' ? 2 : 0,
          color: kbTheme(this.isDark).accent,
        })
        .onClick(() => { InputHandler.getInstance().startCapture('yomi'); })
      }
      .layoutWeight(1)

      // ── 単語 ──
      Column({ space: 2 }) {
        Text('単語')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(9)
          .fontColor(kbTheme(this.isDark).textSecondary)
          .width('100%')
        Row() {
          Text(this.shownWord())
            .fontFamily(JP_FONT_FAMILY)
            .fontSize(14)
            .fontColor(this.dictEditWord.length > 0
              ? kbTheme(this.isDark).textPrimary
              : kbTheme(this.isDark).textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .height(34)
        .padding({ left: 8, right: 8 })
        .alignItems(VerticalAlign.Center)
        .backgroundColor(kbTheme(this.isDark).keyBg)
        .borderRadius(6)
        .border({
          width: this.dictCaptureTarget === 'word' ? 2 : 0,
          color: kbTheme(this.isDark).accent,
        })
        .onClick(() => { InputHandler.getInstance().startCapture('word'); })
      }
      .layoutWeight(1)

      // 操作ボタンは欄と同じ高さに揃える (ラベル分だけ下げる)。
      Row({ space: 6 }) {
        Text('⌫')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(13)
          .width(34).height(34)
          .textAlign(TextAlign.Center)
          .fontColor(kbTheme(this.isDark).textSecondary)
          .backgroundColor(kbTheme(this.isDark).funcBg)
          .borderRadius(6)
          .onClick(() => { InputHandler.getInstance().clearDictEdit(); })

        Text('登録')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .height(34)
          .textAlign(TextAlign.Center)
          .fontColor(kbTheme(this.isDark).onAccent)
          .backgroundColor(kbTheme(this.isDark).accent)
          .borderRadius(6)
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            const msg = InputHandler.getInstance().commitDictEdit();
            promptAction.showToast({ message: msg.length > 0 ? msg : '登録しました' });
          })

        Text('✕')
          .fontFamily(JP_FONT_FAMILY)
          .fontSize(13)
          .width(34).height(34)
          .textAlign(TextAlign.Center)
          .fontColor(kbTheme(this.isDark).textSecondary)
          .backgroundColor(kbTheme(this.isDark).funcBg)
          .borderRadius(6)
          .onClick(() => { InputHandler.getInstance().endDictEdit(); })
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    .backgroundColor(kbTheme(this.isDark).panelBg)
    .borderWidth({ bottom: 1 })
    .borderColor(kbTheme(this.isDark).divider)
  }
}
