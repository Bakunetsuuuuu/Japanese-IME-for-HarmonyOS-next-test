import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import { execFileSync } from 'child_process';
import * as path from 'path';

// 手書きの基本辞書 (KanaKanjiConverter.ets の buildInlineDictionary) を
// rawfile/inline_dict.* のバイナリに書き出す。アプリはバイナリしか読まないので、
// ソースを直してこれを回し忘れると古い辞書が同梱される。ビルドのたびに呼び、
// 中身が変わっていなければ何もしない (ハッシュ比較だけ)。
const packer = path.resolve(__dirname, '..', 'tools', 'pack_inline_dict.js');
execFileSync(process.execPath, [packer, '--quiet'], { stdio: 'inherit' });

export default {
  system: hapTasks,
  plugins: []
};
