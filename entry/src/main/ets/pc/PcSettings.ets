// PCモードの設定。保存先は SettingsStore と同じ 'shunti_settings' だが、
// KeyboardSettings (ソフトキーボードの設定一式) には混ぜずにここで別に持つ
// -- PCモードを使わない端末の読み込み・既定値に手を入れないため。
import dataPreferences from '@ohos.data.preferences';
import type common from '@ohos.app.ability.common';
import { InputLog } from '../ime/InputLog';

// 'auto' = 物理キーボードがつながっている間だけ PCモード (既定)
// 'on'   = 常に PCモード (自動の判定が外れる端末向けの逃げ道)
// 'off'  = 使わない (今までどおりソフトキーボードだけ)
export const PC_MODE_AUTO: string = 'auto';
export const PC_MODE_ON: string = 'on';
export const PC_MODE_OFF: string = 'off';

export interface PcSettings {
  pcModePreference: string;
  // 言語バーの位置。画面に対する割合 (0〜1、左上の角)。負の値 = まだ動かして
  // いない (画面の右下に置く)。
  langBarXFrac: number;
  langBarYFrac: number;
}

const STORE: string = 'shunti_settings';

export class PcSettingsStore {
  static async load(context: common.Context): Promise<PcSettings> {
    try {
      const prefs = await dataPreferences.getPreferences(context, STORE);
      const pref = await prefs.get('pcModePreference', PC_MODE_AUTO);
      const x = await prefs.get('langBarXFrac', -1);
      const y = await prefs.get('langBarYFrac', -1);
      const p = String(pref);
      return {
        pcModePreference: (p === PC_MODE_ON || p === PC_MODE_OFF) ? p : PC_MODE_AUTO,
        langBarXFrac: Number(x),
        langBarYFrac: Number(y),
      };
    } catch (e) {
      console.error('shuntiIME PcSettingsStore.load error', JSON.stringify(e));
      return { pcModePreference: PC_MODE_AUTO, langBarXFrac: -1, langBarYFrac: -1 };
    }
  }

  static async savePreference(context: common.Context, pref: string): Promise<void> {
    InputLog.recordSetting('pcModePreference', pref);
    try {
      const prefs = await dataPreferences.getPreferences(context, STORE);
      await prefs.put('pcModePreference', pref);
      await prefs.flush();
    } catch (_e) {}
  }

  static async saveLangBarPosition(context: common.Context, xFrac: number, yFrac: number): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(context, STORE);
      await prefs.put('langBarXFrac', xFrac);
      await prefs.put('langBarYFrac', yFrac);
      await prefs.flush();
    } catch (_e) {}
  }
}
