import { font } from '@kit.ArkUI';

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

// Call once per process, before any Text renders -- both EntryAbility (main
// app) and InputMethodExtAbility/KeyboardController (keyboard panel, its own
// process) need this, since they're separate UI content roots.
export function registerJpFont(): void {
  if (registered) { return; }
  registered = true;
  try {
    font.registerFont({
      familyName: JP_FONT_FAMILY,
      familySrc: $rawfile('font/NotoSansJP-Regular.ttf'),
    });
  } catch (e) {
    console.error('shuntiIME JP font registration failed', e);
  }
}
