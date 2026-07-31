import { font, UIContext } from '@kit.ArkUI';

// HarmonyOS's own system font (HarmonyOS Sans) only ships Simplified/Traditional
// Chinese regional variants, no Japanese one -- on a China-region device this
// makes Han-unified kanji render with Simplified Chinese glyph shapes even
// though the text is Japanese. Bundling and registering an explicit Japanese
// font is the only fix; there's no system font-family name to switch to
// instead. Subset to exactly the characters this app's dictionaries/UI can
// ever output (see tools/ for how NotoSansJP-Regular.ttf was generated) to
// keep the bundled font small.
export const JP_FONT_FAMILY = 'NotoSansJP';

let registered = false;

// Register the bundled font, once per process.
//
// MUST be called from a UI instance -- pass the page's this.getUIContext() from
// aboutToAppear. It used to be called from the ability lifecycle instead
// (EntryAbility.onWindowStageCreate before loadContent, and
// KeyboardController.onCreate before initPanel/setUiContent), i.e. at a point
// where no UI instance exists yet. The global `font` object registers into the
// *current* UI instance, so with none created the call had nothing to register
// into and every Text silently kept rendering in the system font -- exactly the
// Han-unification problem this font is here to fix. Both processes still need
// their own call (main app and IME extension are separate UI content roots),
// they just have to make it from inside the UI.
//
// `registered` is set only after the call actually returns, so a failed attempt
// doesn't permanently block a later one. Setting it up-front was what turned a
// single bad early call into "the font is never registered at all".
export function registerJpFont(ui?: UIContext): void {
  if (registered) { return; }
  try {
    const options: font.FontOptions = {
      familyName: JP_FONT_FAMILY,
      familySrc: $rawfile('font/NotoSansJP-Regular.ttf'),
    };
    if (ui !== undefined) {
      ui.getFont().registerFont(options);
    } else {
      font.registerFont(options);
    }
    registered = true;
  } catch (e) {
    console.error('shuntiIME JP font registration failed', e);
  }
}
