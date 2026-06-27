import { router } from '@kit.ArkUI';
import display from '@ohos.display';

@Entry
@Component
struct PrivacyPolicy {
  @State isDark: boolean = false;

  aboutToAppear(): void {
    try {
      const dis = display.getDefaultDisplaySync();
      this.isDark = (dis as Record<string, number>)['colorMode'] === 0;
    } catch (_e) {
      this.isDark = false;
    }
  }

  build() {
    Column() {
      // Header
      Row() {
        Text('← 戻る')
          .fontSize(15)
          .fontColor(Color.White)
          .onClick(() => { router.back(); })
        Text('プライバシーポリシー')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .margin({ left: 12 })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16 })
      .backgroundColor('#4A90E2')

      Scroll() {
        Column({ space: 20 }) {
          this.Section('はじめに',
            'shunti Japanese IME（以下「本アプリ」）は、開発者 shuntilettuce が提供する HarmonyOS NEXT 向けの日本語入力メソッド（IME）です。\n\n' +
            'アプリ名：shunti Japanese IME\n' +
            '開発者名：shuntilettuce\n\n' +
            '本アプリをご利用いただく前に、このプライバシーポリシーをよくお読みください。')

          this.Section('収集する情報',
            '本アプリは、以下の情報をお客様のデバイス上でのみ処理します。\n\n' +
            '・入力テキスト（変換・候補表示のためにデバイス内でのみ処理）\n' +
            '・変換履歴（変換精度向上のためにデバイス内のみに保存）\n' +
            '・ユーザー登録単語（任意で登録した読み・単語のペア）\n\n' +
            '上記の情報は外部サーバーへ送信・アップロードされることはありません。')

          this.Section('情報の利用目的',
            '収集した情報は以下の目的にのみ使用します。\n\n' +
            '・かな漢字変換候補の生成\n' +
            '・変換精度向上のための学習（デバイス内のみ）\n' +
            '・ユーザー辞書機能の提供')

          this.Section('情報の保存',
            '変換履歴およびユーザー登録単語は、HarmonyOS の Preferences API を使用してお客様のデバイス内にのみ保存されます。外部サービスやクラウドへの保存は一切行いません。\n\n' +
            '保存データはアプリのアンインストールにより削除されます。')

          this.Section('第三者への提供',
            '本アプリは、お客様の入力データ・変換履歴・ユーザー辞書を第三者に提供・販売・共有することはありません。')

          this.Section('バンドルデータについて',
            '本アプリには変換辞書データ（dict.json）および文節分割用コストデータ（reading_cost.json, matrix.json）が含まれています。これらは読み取り専用のデータファイルであり、お客様の入力内容とは独立しています。\n\n' +
            '辞書データの出典：SKK-JISYO.L（GPL v2）、mecab-ipadic（NAIST License）')

          this.Section('クラッシュレポート・分析',
            '本アプリは分析ツールやクラッシュレポートサービスを使用していません。')

          this.Section('お子様のプライバシー',
            '本アプリは13歳未満のお子様からの個人情報を意図的に収集しません。')

          this.Section('ポリシーの変更',
            '本プライバシーポリシーは予告なく変更される場合があります。変更後も本アプリをご利用いただいた場合、変更後のポリシーに同意されたものとみなします。')

          this.Section('お問い合わせ',
            'プライバシーに関するご質問は、AppGallery の開発者情報に記載のメールアドレスまでお問い合わせください。')

          Text('最終更新: 2026年6月')
            .fontSize(12)
            .fontColor('#999999')
            .width('100%')
            .textAlign(TextAlign.End)
            .padding({ bottom: 32 })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 20 })
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isDark ? '#121212' : '#F5F5F5')
  }

  @Builder Section(title: string, body: string) {
    Column({ space: 8 }) {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.isDark ? '#E0E0E0' : '#333333')
        .width('100%')
      Text(body)
        .fontSize(14)
        .fontColor(this.isDark ? '#AAAAAA' : '#555555')
        .lineHeight(22)
        .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.isDark ? '#252525' : '#FFFFFF')
    .borderRadius(8)
  }
}
