// 物理キーボードがつながっているかを見張る。
//
// inputDevice の一覧から「文字キーを持つ (ALPHABETIC_KEYBOARD)・仮想でない」
// 入力機器を探す。電源ボタンや音量キーも 'keyboard' として登録されている
// ことがあるので、sources だけでなく getKeyboardType まで見る。
// 抜き差しは inputDevice.on('change') で追う。
//
// それでも判定が外れる端末に備えて、実際に文字キーの打鍵が届いたら
// その機器を調べ直す口 (noteKeyFrom) も持つ。
import { inputDevice } from '@kit.InputKit';

export class KeyboardDeviceMonitor {
  private connected: boolean = false;
  private started: boolean = false;
  private onChanged: (connected: boolean) => void;
  // 文字キーを持つと確かめた機器 (打鍵から調べ直したもの・一覧から見つけたもの)
  private alphabeticIds: Set<number> = new Set<number>();

  private listener = (_data: inputDevice.DeviceListener): void => {
    this.refresh();
  };

  constructor(onChanged: (connected: boolean) => void) {
    this.onChanged = onChanged;
  }

  isConnected(): boolean {
    return this.connected;
  }

  start(): void {
    if (this.started) { return; }
    this.started = true;
    try {
      inputDevice.on('change', this.listener);
    } catch (err) {
      console.error('shuntiIME inputDevice.on error', JSON.stringify(err));
    }
    this.refresh();
  }

  stop(): void {
    if (!this.started) { return; }
    this.started = false;
    try {
      inputDevice.off('change', this.listener);
    } catch (_e) {}
  }

  refresh(): void {
    inputDevice.getDeviceList()
      .then((ids: Array<number>) => {
        const found = new Set<number>();
        for (const id of ids) {
          if (KeyboardDeviceMonitor.isPhysicalAlphabetic(id)) { found.add(id); }
        }
        this.alphabeticIds = found;
        this.setConnected(found.size > 0);
      })
      .catch((err: Error) => {
        console.error('shuntiIME inputDevice.getDeviceList error', JSON.stringify(err));
      });
  }

  // 文字キーの打鍵が届いたとき (PCモードがまだ入っていないとき) に呼ぶ。
  // 打鍵した機器が文字キーを持つ物理キーボードなら、その場で「接続あり」にする。
  // 同期で決める (この打鍵自体を PCモードで処理するため)。
  noteKeyFrom(deviceId: number): boolean {
    if (this.alphabeticIds.has(deviceId)) { return this.connected; }
    if (KeyboardDeviceMonitor.isPhysicalAlphabetic(deviceId)) {
      this.alphabeticIds.add(deviceId);
      this.setConnected(true);
    }
    return this.connected;
  }

  private setConnected(v: boolean): void {
    if (v === this.connected) { return; }
    this.connected = v;
    console.info(`shuntiIME hardware keyboard ${v ? 'connected' : 'disconnected'}`);
    this.onChanged(v);
  }

  private static isPhysicalAlphabetic(id: number): boolean {
    try {
      const info = inputDevice.getDeviceInfoSync(id);
      if (info.isVirtual === true) { return false; }
      if (info.sources.indexOf('keyboard') < 0) { return false; }
      return inputDevice.getKeyboardTypeSync(id) === inputDevice.KeyboardType.ALPHABETIC_KEYBOARD;
    } catch (_e) {
      return false;
    }
  }
}
