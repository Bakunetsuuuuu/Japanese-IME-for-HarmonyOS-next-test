# shunti IME (Windows 版) を入れる・外す。管理者の権限が要る (無ければ UAC で頼む)。
#   入れる: powershell -ExecutionPolicy Bypass -File install.ps1
#   外す:   powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall
# このスクリプトと同じフォルダの shunti_ime_x64.dll・shunti_ime_x86.dll・kkc_lex.bin・kkc_model.bin を
# C:\Program Files\shunti IME に写し、64 ビットと 32 ビットの両方を登録する。
# 使っているアプリが DLL を開いたままでも入れ直せるように、古いファイルは名前を変えて残し、次の再起動で消す。
param([switch]$Uninstall, [switch]$Elevated)
$ErrorActionPreference = 'Stop'

$Dest = Join-Path $env:ProgramFiles 'shunti IME'
$Files = @('shunti_ime_x64.dll', 'shunti_ime_x86.dll', 'kkc_lex.bin', 'kkc_model.bin', 'LICENSE.txt')
$Reg64 = Join-Path $env:windir 'System32\regsvr32.exe'
$Reg32 = Join-Path $env:windir 'SysWOW64\regsvr32.exe'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Elevated')
    if ($Uninstall) { $args2 += '-Uninstall' }
    $p = Start-Process powershell -Verb RunAs -ArgumentList $args2 -Wait -PassThru
    exit $p.ExitCode
}

Add-Type -Namespace Shunti -Name Native -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern bool MoveFileEx(string from, string to, int flags);
'@

# 使用中なら名前を変えて、次の再起動で消す
function Remove-OrRetire([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return }
    try { Remove-Item -LiteralPath $path -Force; return } catch {}
    $old = "$path.old-" + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    Rename-Item -LiteralPath $path -NewName (Split-Path $old -Leaf) -Force
    [void][Shunti.Native]::MoveFileEx($old, $null, 4)   # MOVEFILE_DELAY_UNTIL_REBOOT
}

function Unregister-All {
    foreach ($pair in @(@($Reg64, 'shunti_ime_x64.dll'), @($Reg32, 'shunti_ime_x86.dll'))) {
        $dll = Join-Path $Dest $pair[1]
        if ((Test-Path -LiteralPath $dll) -and (Test-Path -LiteralPath $pair[0])) {
            Start-Process $pair[0] -ArgumentList @('/u', '/s', "`"$dll`"") -Wait
        }
    }
}

try {
    if ($Uninstall) {
        Unregister-All
        if (Test-Path -LiteralPath $Dest) {
            Get-ChildItem -LiteralPath $Dest -File | ForEach-Object { Remove-OrRetire $_.FullName }
            try { Remove-Item -LiteralPath $Dest -Force -ErrorAction SilentlyContinue } catch {}
        }
        Write-Host 'shunti IME を外しました。使っていたアプリを閉じるか、再起動すると残りのファイルも消えます。'
    } else {
        $src = $PSScriptRoot
        foreach ($f in $Files) {
            if (-not (Test-Path -LiteralPath (Join-Path $src $f))) { throw "$f が見つかりません ($src)" }
        }
        Unregister-All
        New-Item -ItemType Directory -Force -Path $Dest | Out-Null
        Get-ChildItem -LiteralPath $Dest -Filter '*.old-*' -File -ErrorAction SilentlyContinue | ForEach-Object {
            try { Remove-Item -LiteralPath $_.FullName -Force } catch {}
        }
        foreach ($f in $Files) {
            $to = Join-Path $Dest $f
            Remove-OrRetire $to
            Copy-Item -LiteralPath (Join-Path $src $f) -Destination $to -Force
        }
        $p64 = Start-Process $Reg64 -ArgumentList @('/s', "`"$(Join-Path $Dest 'shunti_ime_x64.dll')`"") -Wait -PassThru
        $p32 = Start-Process $Reg32 -ArgumentList @('/s', "`"$(Join-Path $Dest 'shunti_ime_x86.dll')`"") -Wait -PassThru
        if ($p64.ExitCode -ne 0 -or $p32.ExitCode -ne 0) { throw "登録に失敗しました (x64: $($p64.ExitCode), x86: $($p32.ExitCode))" }
        Write-Host 'shunti IME を入れました。'
        Write-Host '設定 → 時刻と言語 → 言語と地域 → 日本語 の「…」→ 言語のオプション → キーボードの追加 で「shunti IME」を選び、'
        Write-Host 'Windows キー + スペース で切り替えて使ってください。'
    }
    if ($Elevated) { Start-Sleep -Seconds 4 }
    exit 0
} catch {
    Write-Host "失敗しました: $_" -ForegroundColor Red
    if ($Elevated) { Start-Sleep -Seconds 10 }
    exit 1
}
