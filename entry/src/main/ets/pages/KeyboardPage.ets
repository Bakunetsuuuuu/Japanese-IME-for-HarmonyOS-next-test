import inputMethodEngine from '@ohos.inputMethodEngine';
import util from '@ohos.util';
import { promptAction } from '@kit.ArkUI';
import { InputHandler, InputState, InputMode, applyKeyboardWidthsForVp } from '../ime/KeyboardController';
import { KanaKanjiConverter } from '../ime/KanaKanjiConverter';
import { CandidateBar } from '../components/CandidateBar';
import { PredictionBar } from '../components/PredictionBar';
import { KeyboardView } from '../components/KeyboardView';
import { FlickKeyboardView } from '../components/FlickKeyboardView';
import { AlphabetFlickKeyboardView } from '../components/AlphabetFlickKeyboardView';
import { SymbolView } from '../components/SymbolView';
import { EmojiView } from '../components/EmojiView';
import { NumericPadView } from '../components/NumericPadView';
import { BunsetsuBar } from '../components/BunsetsuBar';
import { ExpandedCandidateView } from '../components/ExpandedCandidateView';
import { SettingsBar } from '../components/SettingsBar';
import { SettingsStore, KeyboardSettings } from '../ime/SettingsStore';
import { kbTheme } from '../components/Theme';
import { JP_FONT_FAMILY, registerJpFont } from '../components/JpFont';

let _inputStartRegistered = false;
let _dictLoaded = false;
const USE_DICT_JSON: boolean = true;

@Entry
@Component
struct KeyboardPage {
  @StorageLink('inputState') inputState: string = InputState.IDLE;
  @StorageLink('inputMode') inputMode: string = InputMode.HIRAGANA;
  @StorageLink('composingText') composingText: string = '';
  @StorageLink('pendingRomaji') pendingRomaji: string = '';
  @StorageLink('candidates') candidates: string[] = [];
  @StorageLink('predictions') predictions: string[] = [];
  @StorageLink('selectedCandidateIndex') selectedIndex: number = 0;
  @StorageLink('isLandscape') isLandscape: boolean = false;
  @StorageLink('kanaKeyboardLayout') kanaKeyboardLayout: string = 'QWERTY';
  @StorageLink('alphabetKeyboardLayout') alphabetKeyboardLayout: string = 'QWERTY';
  @StorageLink('keyboardSubMode') keyboardSubMode: string = 'kana';
  @StorageLink('bunsetsuTexts') bunsetsuTexts: string[] = [];
  @StorageLink('bunsetsuRaw') bunsetsuRaw: string[] = [];
  @StorageLink('bunsetsuCurrent') bunsetsuCurrent: number = 0;
  @StorageLink('isDark') isDark: boolean = false;
  @StorageLink('clipboardPreview') clipboardPreview: string = '';
  @StorageLink('clipboardHistory') clipboardHistory: string[] = [];
  @StorageLink('oneHandedMode') oneHandedMode: boolean = false;
  @StorageLink('oneHandedSide') oneHandedSide: string = 'right';
  @StorageLink('candidateExpanded') candidateExpanded: boolean = false;
  @StorageLink('convEnd') convEnd: number = 0;

  aboutToAppear(): void {
    // The IME extension is its own process/UI root, so it needs its own
    // registration -- and it has to happen from inside the UI, not from
    // KeyboardController.onCreate (see registerJpFont's comment).
    registerJpFont(this.getUIContext());
    if (!_dictLoaded && USE_DICT_JSON) {
      _dictLoaded = true;
      getContext(this).resourceManager.getRawFileContent('dict.json')
        .then((data: Uint8Array) => {
          const decoder = new util.TextDecoder('utf-8');
          const text = decoder.decode(data);
          KanaKanjiConverter.loadDictionary(JSON.parse(text) as Record<string, string[]>);
        })
        .catch((_e: Error) => {});
    }

    // aboutToAppear runs every time this panel's content is (re)constructed —
    // a more reliable reload point than onPageShow, which per ArkUI docs is a
    // Navigation/Router page-lifecycle hook and may never fire for content
    // hosted in an InputMethodExtensionAbility's Panel (a window, not a routed
    // page). Kept unguarded (unlike the inputStart listener below) since
    // rereading a small preferences store is cheap.
    this.reloadSettingsIntoStorage();

    if (_inputStartRegistered) { return; }
    _inputStartRegistered = true;
    inputMethodEngine.getInputMethodAbility().on('inputStart', (
      kbCtrl: inputMethodEngine.KeyboardController,
      client: inputMethodEngine.InputClient
    ) => {
      InputHandler.getInstance().onInputStart(kbCtrl, client);
    });
  }

  onBackPress(): boolean {
    InputHandler.getInstance().hideKeyboard();
    return true;
  }

  // onInputStart only fires for a genuinely new input session — switching to
  // the main app to change the keyboard layout and back doesn't necessarily
  // trigger one if the panel itself just gets hidden/reshown. Kept alongside
  // aboutToAppear's call in case this panel *is* managed as a routed page on
  // some devices/OS versions after all.
  onPageShow(): void {
    console.info('shuntiIME KeyboardPage.onPageShow fired');
    this.reloadSettingsIntoStorage();
  }

  private reloadSettingsIntoStorage(): void {
    SettingsStore.load(getContext(this), true).then((s: KeyboardSettings) => {
      console.info('shuntiIME KeyboardPage settings reload applied', JSON.stringify(s));
      AppStorage.setOrCreate('kanaKeyboardLayout', s.kanaKeyboardLayout);
      AppStorage.setOrCreate('alphabetKeyboardLayout', s.alphabetKeyboardLayout);
      AppStorage.setOrCreate('oneHandedMode', s.oneHandedMode);
      AppStorage.setOrCreate('oneHandedSide', s.oneHandedSide);
      AppStorage.setOrCreate('numericPadEnabled', s.numericPadEnabled);
      // This panel and the extension's InputHandler share the same process/
      // KanaKanjiConverter static state (see setConversionEngine's own
      // lazy-load comment), but this aboutToAppear-driven reload is the more
      // reliable refresh point per the comment above -- route through
      // InputHandler.setConversionEngine so a setting persisted from the main
      // app (a different process) actually applies the mozc engine switch
      // here too, not just update the SettingsBar toggle's own display value.
      InputHandler.getInstance().setConversionEngine(s.conversionEngine);
    });
  }

  build() {
    Stack() {
      Column() {
        // Symbol/Emoji/Settings views take the full panel (no preview bar).
        // Numeric keeps the preview bar — without it the pad's rows stretch to
        // fill the whole panel height and end up uncomfortably tall.
        if (this.keyboardSubMode === 'symbol') {
          SymbolView()
        } else if (this.keyboardSubMode === 'emoji') {
          EmojiView()
        } else if (this.keyboardSubMode === 'settings') {
          SettingsBar()
        } else {
          // Preview bar
          if (this.inputState === InputState.BUNSETSU) {
            // Two-row preview: segment chips on top, candidates below
            Column() {
              BunsetsuBar({
                segments: this.bunsetsuTexts,
                currentIndex: this.bunsetsuCurrent
              })
              CandidateBar({
                candidates: this.candidates,
                selectedIndex: this.selectedIndex,
                showExpand: true
              })
            }
            .width('100%')
            .backgroundColor(kbTheme(this.isDark).panelBg)
            .borderWidth({ bottom: 1 })
            .borderColor(kbTheme(this.isDark).divider)
          } else {
            Column() {
              // Composing kana strip — always visible to prevent layout shifts.
              // Landscape has much less vertical room to spare for the keys below,
              // so this strip and the candidate row underneath both run compact.
              Row() {
                if (this.composingText.length > 0 || this.pendingRomaji.length > 0) {
                  if (this.convEnd > 0 && this.convEnd < this.composingText.length) {
                    Text(this.composingText.slice(0, this.convEnd))
                      .fontFamily(JP_FONT_FAMILY)
                      .fontSize(this.isLandscape ? 11 : 16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(kbTheme(this.isDark).textPrimary)
                      .maxLines(1)
                      .decoration({ type: TextDecorationType.Underline, color: kbTheme(this.isDark).accent })
                    Text(this.composingText.slice(this.convEnd))
                      .fontFamily(JP_FONT_FAMILY)
                      .fontSize(this.isLandscape ? 11 : 16)
                      .fontColor(kbTheme(this.isDark).textSecondary)
                      .maxLines(1)
                  } else {
                    Text(this.composingText + this.pendingRomaji)
                      .fontFamily(JP_FONT_FAMILY)
                      .fontSize(this.isLandscape ? 11 : 16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(kbTheme(this.isDark).textPrimary)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .padding({ left: 12, right: 8 })
                      .border((this.composingText + this.pendingRomaji).length > 0 ?
                        { width: { bottom: 2 }, color: kbTheme(this.isDark).accent } :
                        { width: { bottom: 0 } })
                      .layoutWeight(1)
                  }
                }
                Blank()
                Text('設定')
                  .fontFamily(JP_FONT_FAMILY)
                  .fontSize(this.isLandscape ? 10 : 13)
                  .fontColor(kbTheme(this.isDark).textSecondary)
                  .onClick(() => {
                    AppStorage.setOrCreate('keyboardSubMode', 'settings');
                  })
              }
              .width('100%')
              .height(this.isLandscape ? 14 : 28)
              .backgroundColor(kbTheme(this.isDark).panelBg)
              .alignItems(VerticalAlign.Center)
              .padding({ left: 12, right: 8 })

              // Candidate bar row + layout toggle
              Row() {
                Row() {
                  if (this.candidates.length > 0) {
                    CandidateBar({
                      candidates: this.candidates,
                      selectedIndex: this.selectedIndex,
                      showExpand: true
                    })
                  } else if (this.composingText.length === 0 && this.pendingRomaji.length === 0 &&
                    this.clipboardPreview.length > 0) {
                    // 未貼り付けのクリップボードがある限り、次の語の予測より先に出す。
                    // チップは貼るか、クリップボードの中身が変わるまで消えない
                    // (dismissedClipSig)ので、「まだ貼っていないコピーが1件ある」
                    // 状態と 1:1 に対応する。
                    //
                    // 以前は予測がこの枝より先にあり、確定直後はほぼ必ず予測が
                    // 出るため、貼り付けチップに一度も到達しなかった。
                    //
                    // Gboard-style: centered paste suggestion when nothing is composing,
                    // rather than left-aligned like an actual conversion candidate.
                    Text(this.clipboardPreview)
                      .fontFamily(JP_FONT_FAMILY)
                      .fontSize(this.isLandscape ? 11 : 16)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      // Cap how wide the chip can grow instead of letting it stretch to
                      // fill the row — short clips hug their text, long ones truncate
                      // with "…" at the cap instead of a background that runs on past
                      // where the (ellipsized) text actually ends.
                      .constraintSize({ maxWidth: '90%' })
                      .padding(this.isLandscape ?
                        { left: 8, right: 8, top: 2, bottom: 2 } :
                        { left: 12, right: 12, top: 6, bottom: 6 })
                      .borderRadius(this.isLandscape ? 11 : 17)
                      .backgroundColor(kbTheme(this.isDark).candidateBg)
                      .fontColor(kbTheme(this.isDark).textSecondary)
                      .onClick(() => {
                        const result = InputHandler.getInstance().pasteClipboard();
                        if (result === 'extendAction') {
                          // Fire-and-forget request to the focused field's own
                          // paste handler (see pasteClipboard's comment) --
                          // there's no reliable signal for whether it actually
                          // had anything to paste, so this can only say the
                          // request went out, not that it definitely worked.
                          promptAction.showToast({
                            message: '貼り付け操作を送信しました（アプリによっては反映されないことがあります）',
                          });
                        } else if (result === 'none') {
                          promptAction.showToast({
                            message: '画像・ファイルはキーボードから直接貼り付けできません。貼り付け先アプリ自体の貼り付け機能をご利用ください',
                          });
                        }
                      })
                  } else if (this.composingText.length === 0 && this.pendingRomaji.length === 0 &&
                    this.predictions.length > 0) {
                    // Idle right after a commit: offer the likely next words to tap.
                    PredictionBar({ predictions: this.predictions })
                  }
                }
                .width('100%')
                .height(this.isLandscape ? 22 : 48)
                .justifyContent(FlexAlign.Center)
                .alignItems(VerticalAlign.Center)
              }
              .width('100%')
              .height(this.isLandscape ? 22 : 48)
              .backgroundColor(kbTheme(this.isDark).panelBg)
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')
          }

          // Keyboard — fills all height remaining after the preview bar.
          // One-handed mode shrinks+docks this via a scale transform anchored to
          // an edge, rather than touching the pixel-tuned computeKeyWidths /
          // applyKeyboardWidthsForVp system: each inner view still measures and
          // lays out its keys at full intended size, then this wrapper visually
          // (and for hit-testing) scales the whole thing down toward one side.
          Column() {
            if (this.keyboardSubMode === 'numeric') {
              NumericPadView()
            } else if (this.alphabetKeyboardLayout === 'FLICK' && this.inputMode === InputMode.ALPHANUMERIC) {
              AlphabetFlickKeyboardView({
                inputMode: this.inputMode,
                isLandscape: this.isLandscape
              })
            } else if (this.kanaKeyboardLayout === 'FLICK' && this.inputMode !== InputMode.ALPHANUMERIC) {
              FlickKeyboardView({
                inputMode: this.inputMode,
                isLandscape: this.isLandscape
              })
            } else {
              KeyboardView({
                inputMode: this.inputMode,
                isLandscape: this.isLandscape
              })
            }
          }
          .width('100%')
          .layoutWeight(1)
          .scale(this.oneHandedMode ?
            { x: 0.78, y: 0.78, centerX: this.oneHandedSide === 'left' ? '0%' : '100%', centerY: '100%' } :
            { x: 1, y: 1 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(kbTheme(this.isDark).panelBg)
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        // Confirmed via on-device diagnostics: this device's IME panel framework
        // silently shrinks the panel to a fraction of the width requested via
        // panel.resize() (~76% observed, with no corresponding cutout reported —
        // a software policy, not a hardware inset), so it isn't queryable up
        // front. Correct key widths from what this root view actually measures,
        // and also record the (measured / raw guess) ratio as a learned scale
        // factor — see KeyboardController.computeKeyWidths for why: this panel
        // is reused across show/hide, so a later resize may not be followed by
        // a fresh onAreaChange, and the learned scale lets that next guess
        // start out already corrected instead of reverting to the raw width.
        const measuredVp = Number(newArea.width);
        if (measuredVp > 0) {
          const isTabletClass = AppStorage.get<boolean>('isTabletClass') ?? false;
          applyKeyboardWidthsForVp(measuredVp, isTabletClass);
          if (!isTabletClass) {
            const rawFullVp = AppStorage.get<number>('lastRawFullVp') ?? 0;
            if (rawFullVp > 0) {
              const ratio = Math.min(1, Math.max(0.3, measuredVp / rawFullVp));
              const isLand = AppStorage.get<boolean>('lastRawFullVpIsLandscape') ?? this.isLandscape;
              AppStorage.setOrCreate(isLand ? 'widthScaleLandscape' : 'widthScalePortrait', ratio);
            }
          }
        }
      })

      // Expanded candidate list — a top-level Stack sibling of the base panel
      // above, NOT nested inside the keyboard's own Column. That placement
      // matters for two reasons: (1) the keyboard Column only spans the area
      // below the preview/candidate-bar strip, so nesting it there capped the
      // grid to that same sliver instead of the fuller panel; (2) the keyboard
      // Column is what one-handed mode's .scale() transform shrinks and docks
      // to a corner — sitting outside it means the expanded grid always renders
      // at full size and full position regardless of one-handed mode. Full
      // width/height so it fully covers (not just overlaps) everything below,
      // preview strip included.
      if (this.candidateExpanded && this.candidates.length > 0) {
        ExpandedCandidateView({
          candidates: this.candidates,
          selectedIndex: this.selectedIndex
        })
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }
}
