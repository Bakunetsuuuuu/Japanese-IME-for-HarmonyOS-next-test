#!/usr/bin/env node
// 端末の入力ログ (デバッグビルドのみ) を USB デバッグ経由で PC に取り出す。
//
// IME の拡張プロセスからは、クリップボードへの書き込みは SELinux で拒否され、
// hdc からサンドボックスも読めない。確実に外へ出せるのは hilog だけなので、
// キーボード側 (InputLog.dumpToHilog) がログ全文を Base64 にして連番付きで
// hilog へ流し、このスクリプトがそれを拾って並べ直し、元の JSONL に戻す。
//
// 使い方:
//   1. 端末を USB でつなぎ、USB デバッグを有効にしておく
//   2. node tools/pull_input_log.js
//   3. 「待機中」と出たら、端末のキーボードで 設定 → 修復 → 入力ログ →
//      「USBへ書き出す」を押す
//   4. tools/.inputlog/input_log_<日時>.jsonl に保存される
//
// 保存先は .gitignore 済み。実際に打った文がそのまま入っているので、
// 絶対に git に入れないこと (リポジトリは public)。
//
// 環境変数:
//   HDC        hdc の実行ファイル (既定: PATH の hdc → DevEco Studio の既定位置)
//   HDC_TARGET 接続先の端末 ID (複数台つないでいるとき)
//   TIMEOUT_S  待ち時間の上限 (既定 900 秒)

'use strict';
const fs = require('fs');
const path = require('path');
const { spawn, spawnSync } = require('child_process');
const zlib = require('zlib');

const MARKER = 'SHUNTILOGDUMP';
const OUT_DIR = path.join(__dirname, '.inputlog');
const TIMEOUT_S = Number(process.env.TIMEOUT_S || 900);

function findHdc() {
  if (process.env.HDC) { return process.env.HDC; }
  const probe = spawnSync(process.platform === 'win32' ? 'where' : 'which', ['hdc'], { encoding: 'utf8' });
  if (probe.status === 0 && probe.stdout.trim().length > 0) {
    return probe.stdout.trim().split(/\r?\n/)[0];
  }
  const devEco = 'C:/Program Files/Huawei/DevEco Studio2/sdk/default/openharmony/toolchains/hdc.exe';
  if (fs.existsSync(devEco)) { return devEco; }
  return 'hdc';
}

const HDC = findHdc();
const targetArgs = process.env.HDC_TARGET ? ['-t', process.env.HDC_TARGET] : [];

function hdc(args) {
  return spawnSync(HDC, [...targetArgs, ...args], { encoding: 'utf8' });
}

function main() {
  const targets = spawnSync(HDC, ['list', 'targets'], { encoding: 'utf8' });
  const list = (targets.stdout || '').trim();
  if (targets.status !== 0 || list.length === 0 || list.includes('[Empty]')) {
    console.error('端末が見つかりません。USB 接続と USB デバッグを確認してください。');
    process.exit(1);
  }
  console.log(`端末: ${list.split(/\r?\n/).join(', ')}`);

  // 大量の行を短時間に流すので、できる範囲で hilog の取りこぼし対策をする。
  // どちらも端末/権限によっては効かないが、効かなくても続行する
  // (取りこぼしは連番の抜けとして下で検出する)。
  hdc(['shell', 'hilog', '-Q', 'pidoff']);
  hdc(['shell', 'hilog', '-Q', 'domainoff']);
  // 過去の書き出しの残りを拾わないよう、バッファを空にしてから待つ。
  hdc(['shell', 'hilog', '-r']);

  console.log('');
  console.log('待機中… 端末のキーボードで 設定 → 修復 → 入力ログ → 「USBへ書き出す」を押してください。');
  console.log(`(最大 ${TIMEOUT_S} 秒待ちます。Ctrl+C で中止)`);

  const child = spawn(HDC, [...targetArgs, 'hilog'], { stdio: ['ignore', 'pipe', 'inherit'] });
  child.stdout.setEncoding('utf8');

  let total = -1;
  let rawLen = -1;
  let enc = 'raw';
  const chunks = new Map();
  let carry = '';
  let lastReport = 0;
  let finished = false;

  const timer = setTimeout(() => {
    console.error(`\n${TIMEOUT_S} 秒待っても書き出しが完了しませんでした。`);
    finish(false);
  }, TIMEOUT_S * 1000);

  function finish(ended) {
    if (finished) { return; }
    finished = true;
    clearTimeout(timer);
    child.kill();
    if (total < 0) {
      console.error('書き出しの開始を受信できませんでした。');
      process.exit(1);
    }
    if (total === 0) {
      console.log('\n端末側のログは空でした (まだ何も記録されていません)。');
      process.exit(0);
    }
    const missing = [];
    for (let i = 0; i < total; i++) { if (!chunks.has(i)) { missing.push(i); } }
    if (missing.length > 0) {
      const head = missing.slice(0, 20).join(',');
      console.error(`\n${missing.length}/${total} チャンクが欠けています (例: ${head}${missing.length > 20 ? ',…' : ''})。`);
      console.error('hilog の取りこぼしです。もう一度このスクリプトを起動して書き出し直してください。');
      if (!ended) { console.error('(終了マーカーも受信できていません)'); }
      process.exit(2);
    }
    let b64 = '';
    for (let i = 0; i < total; i++) { b64 += chunks.get(i); }
    let payload = Buffer.from(b64, 'base64');
    if (enc === 'zlib') {
      try {
        payload = zlib.inflateSync(payload);
      } catch (e) {
        console.error(`\n圧縮の展開に失敗しました (${e.message})。書き出し直してください。`);
        process.exit(3);
      }
    }
    const text = payload.toString('utf8');
    if (rawLen >= 0 && text.length !== rawLen) {
      console.error(`\n復元した長さ (${text.length}) が端末側の申告 (${rawLen}) と一致しません。書き出し直してください。`);
      process.exit(3);
    }
    let records = 0;
    let broken = 0;
    for (const line of text.split('\n')) {
      if (line.length === 0) { continue; }
      try { JSON.parse(line); records++; } catch (_e) { broken++; }
    }
    fs.mkdirSync(OUT_DIR, { recursive: true });
    // ローカル時刻で付ける (toISOString は UTC なので、日本時間の深夜は前日の日付になる)。
    const d = new Date();
    const p2 = (n) => String(n).padStart(2, '0');
    const stamp = `${d.getFullYear()}${p2(d.getMonth() + 1)}${p2(d.getDate())}_${p2(d.getHours())}${p2(d.getMinutes())}${p2(d.getSeconds())}`;
    const out = path.join(OUT_DIR, `input_log_${stamp}.jsonl`);
    fs.writeFileSync(out, text, 'utf8');
    console.log(`\n保存しました: ${out}`);
    console.log(`  ${records} 件${broken > 0 ? ` (壊れた行 ${broken} 件は読み飛ばし対象)` : ''} / ${Math.round(Buffer.byteLength(text, 'utf8') / 1024)} KB`);
    console.log('  ※ 実際に打った文が入っています。git に入れないでください。');
    process.exit(0);
  }

  child.stdout.on('data', (data) => {
    const lines = (carry + data).split(/\r?\n/);
    carry = lines.pop();
    for (const line of lines) {
      const at = line.indexOf(MARKER);
      if (at < 0) { continue; }
      const rest = line.slice(at + MARKER.length);
      if (rest.startsWith('_BEGIN')) {
        const t = /total=(\d+)/.exec(rest);
        const r = /rawLen=(\d+)/.exec(rest);
        total = t ? Number(t[1]) : 0;
        rawLen = r ? Number(r[1]) : -1;
        // 端末側は zlib で圧縮してから流す (圧縮できなかったときは raw)。
        const e = /enc=(\w+)/.exec(rest);
        enc = e ? e[1] : 'raw';
        chunks.clear();
        console.log(`\n受信開始: ${total} チャンク (${enc === 'zlib' ? '圧縮あり' : '無圧縮'})`);
        if (total === 0) { finish(true); return; }
      } else if (rest.startsWith('_END')) {
        finish(true);
        return;
      } else {
        const m = /^ (\d+)\/(\d+) (\S+)/.exec(rest);
        if (m) {
          chunks.set(Number(m[1]), m[3]);
          const now = Date.now();
          if (total > 0 && now - lastReport > 1000) {
            lastReport = now;
            process.stdout.write(`\r  ${chunks.size}/${total} (${Math.floor(chunks.size * 100 / total)}%)`);
          }
        }
      }
    }
  });

  child.on('exit', () => {
    if (!finished) {
      console.error('\nhilog の読み取りが途中で終了しました。');
      finish(false);
    }
  });
}

main();
