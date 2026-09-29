"""
Linux 版の動作の試験。画面を通さず、アプリと同じやり方 (Fcitx5 の DBus の入力欄) で shunti IME にキーを送り、
入力中の文字・候補・確定した文を受け取って確かめる。

  dbus-run-session -- python3 desktop/linux/tests/dbus_test.py      (fcitx5 と shunti IME を入れた Linux で)

fcitx5 をこの中で起動する (画面は要らない)。期待と違えば FAIL を出し、終了コードを 1 にする。
"""
import os
import shutil
import subprocess
import sys
import tempfile
import time

import dbus
import dbus.mainloop.glib
from gi.repository import GLib

# Fcitx5 の CapabilityFlag
PREEDIT = 1 << 1
FORMATTED_PREEDIT = 1 << 4
CLIENT_SIDE_INPUT_PANEL = 1 << 39

SYM = {' ': 0x20, '\n': 0xFF0D, 'down': 0xFF54, 'up': 0xFF52, 'esc': 0xFF1B, 'bs': 0xFF08, 'pgdn': 0xFF56}

# desktop/core/composer.cpp の BRACKETS と同じ
BRACKETS = ['（）', '()', '「」', '『』', '【】', '［］', '[]', '｛｝', '{}', '〔〕', '〈〉', '《》', '〖〗', '〘〙',
            '〚〛', '｢｣', '＜＞', '<>', '«»', '‹›', '“”', '‘’', '〝〟', '｟｠']
OPENS = [b[0] for b in BRACKETS]
PAIRS = BRACKETS

failures = 0


def main():
    global failures
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    # 学習・ユーザー辞書は使い捨てのフォルダに (使っている人の学習を汚さない・前回の試験の学習に左右されない)
    env = dict(os.environ, XDG_DATA_HOME=tempfile.mkdtemp(prefix='shunti-test-'))
    os.makedirs(os.path.join(env['XDG_DATA_HOME'], 'shunti-ime'))
    with open(os.path.join(env['XDG_DATA_HOME'], 'shunti-ime', 'userdict.json'), 'w', encoding='utf-8') as f:
        f.write('[{"r":"ぞりちゃん","w":"ゾリ茶ん","p":"person","g":""}]')
    fc = subprocess.Popen(['fcitx5', '--replace', '--disable=wayland,waylandim,xcb,xim,ibusfrontend,fcitx4frontend,clipboard'],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)
    bus = dbus.SessionBus()
    for _ in range(60):
        if bus.name_has_owner('org.fcitx.Fcitx5'):
            break
        time.sleep(0.25)
    time.sleep(1)
    im = dbus.Interface(bus.get_object('org.fcitx.Fcitx5', '/org/freedesktop/portal/inputmethod'), 'org.fcitx.Fcitx.InputMethod1')
    path, _ = im.CreateInputContext([('program', 'shunti-test')])
    ic = dbus.Interface(bus.get_object('org.fcitx.Fcitx5', path), 'org.fcitx.Fcitx.InputContext1')
    commits, ui = [], {}

    def on_commit(s):
        commits.append(str(s))

    def on_preedit(preedit, cursor):
        ui['preedit'] = ''.join(str(t) for t, _ in preedit)

    def on_ui(preedit, cursor, aux_up, aux_down, cands, index, *_):
        ui['cands'] = [str(c) for _, c in cands]
        ui['index'] = int(index)

    bus.add_signal_receiver(on_commit, 'CommitString', 'org.fcitx.Fcitx.InputContext1', path=path)
    bus.add_signal_receiver(on_preedit, 'UpdateFormattedPreedit', 'org.fcitx.Fcitx.InputContext1', path=path)
    bus.add_signal_receiver(on_ui, 'UpdateClientSideUI', 'org.fcitx.Fcitx.InputContext1', path=path)
    ic.SetCapability(dbus.UInt64(PREEDIT | FORMATTED_PREEDIT | CLIENT_SIDE_INPUT_PANEL))
    ic.FocusIn()
    ctl = dbus.Interface(bus.get_object('org.fcitx.Fcitx5', '/controller'), 'org.fcitx.Fcitx.Controller1')
    ctl.SetCurrentIM('shunti')

    def pump(sec=0.3):
        end = time.time() + sec
        ctx = GLib.MainContext.default()
        while time.time() < end:
            ctx.iteration(False)
            time.sleep(0.005)

    def press(keys):
        for k in keys:
            sym = SYM.get(k, ord(k) if len(k) == 1 else None)
            ic.ProcessKeyEvent(dbus.UInt32(sym), dbus.UInt32(0), dbus.UInt32(0), False, dbus.UInt32(0))
            pump(0.05)
        pump(0.5)

    def expect(name, got, want):
        global failures
        if got == want:
            print(f'ok   {name}: {got}')
        else:
            print(f'FAIL {name}: got [{got}] want [{want}]')
            failures += 1

    pump(1)
    print('current IM:', ctl.CurrentInputMethod())
    press(list('kyouhaiitenkidesune'))
    # リアルタイム確定 (初期設定でオン) で前の方は打つそばから確定していくので、入力中の字は読みの後ろの部分
    pre = ui.get('preedit', '')
    expect('preedit while typing (tail of reading)', bool(pre) and 'きょうはいいてんきですね'.endswith(pre), True)
    press([' '])
    expect('converted', ''.join(commits) + ui.get('preedit', ''), '今日はいい天気ですね')
    press(['\n'])
    expect('commit', ''.join(commits), '今日はいい天気ですね')
    commits.clear()

    press(['['])
    expect('bracket preedit', ui.get('preedit'), '「')
    expect('bracket live page 1', ui.get('cands'), ['「', '（', '(', '『', '【', '［', '[', '｛', '{'])
    press([' ', 'down', '\n'])
    expect('bracket pick 2nd after convert', ''.join(commits), '（')
    commits.clear()

    # 全ページをめくって、開き括弧 24 種類がすべて出るか
    press(['[', ' '])
    seen = set(ui.get('cands', []))
    for _ in range(3):
        press(['pgdn'])
        seen |= set(ui.get('cands', []))
    expect('all 24 opening brackets reachable', len(seen & set(OPENS)), len(OPENS))
    press(['esc', 'esc'])

    press(list('kakko') + [' '])
    expect('kakko page 1 (common pairs first)', ui.get('cands', [])[:4], ['かっこ', '（）', '()', '「」'])
    seen = set(ui.get('cands', []))
    for _ in range(3):
        press(['pgdn'])
        seen |= set(ui.get('cands', []))
    expect('all 24 pairs reachable', len(seen & set(PAIRS)), len(PAIRS))
    press(['esc', 'esc'])
    expect('esc clears', ui.get('preedit', ''), '')
    press(list('kakko') + [' ', '4'])
    expect('digit picks on page', ui.get('preedit'), '「」')
    press(['\n'])
    expect('commit picked', ''.join(commits), '「」')
    commits.clear()

    press(list('zorichannhakawaii') + [' '])
    expect('user dictionary word', ''.join(commits) + ui.get('preedit', ''), 'ゾリ茶んは可愛い')
    press(['esc', 'esc'])
    commits.clear()
    ic.FocusOut()
    pump(0.3)
    fc.terminate()
    fc.wait()
    shutil.rmtree(env['XDG_DATA_HOME'], ignore_errors=True)
    print('\n%d FAILED' % failures if failures else '\nall ok')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
