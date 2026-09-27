@echo off
rem Build the Windows version (TSF text service DLL + settings app) with MSVC (Visual Studio 2022 Build Tools).
rem Both x64 and x86 DLLs are needed (64-bit and 32-bit apps each load their own). The settings app is x64 only.
rem   build.bat         release build into desktop\build\dist (no input log code at all). package.ps1 makes the zip from dist only.
rem   build.bat debug   debug build WITH the input log (SHUNTI_INPUT_LOG) into desktop\build\dist_debug. Never distribute it.
setlocal
set HERE=%~dp0
set ROOT=%HERE%..\..
set DIST=%HERE%..\build\dist
set DEFS=
set SUFFIX=
if /I "%~1"=="debug" (
  set DIST=%HERE%..\build\dist_debug
  set DEFS=/DSHUNTI_INPUT_LOG
  set SUFFIX=_debug
)
set VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build
set CORE=%ROOT%\desktop\core
if not exist "%DIST%" mkdir "%DIST%"

call :build x64 vcvars64.bat || exit /b 1
call :build x86 vcvarsamd64_x86.bat || exit /b 1
call :settings || exit /b 1

rem dictionary and model (copied only when changed)
xcopy /D /Y /Q "%ROOT%\entry\src\main\resources\rawfile\kkc_lex.bin" "%DIST%\" >nul
xcopy /D /Y /Q "%ROOT%\entry\src\main\resources\rawfile\kkc_model.bin" "%DIST%\" >nul
copy /Y "%HERE%install.ps1" "%DIST%\" >nul
copy /Y "%HERE%install.bat" "%DIST%\" >nul
copy /Y "%HERE%uninstall.bat" "%DIST%\" >nul
copy /Y "%HERE%README.txt" "%DIST%\" >nul
copy /Y "%HERE%LICENSE.txt" "%DIST%\" >nul
echo built: %DIST%
exit /b 0

:build
setlocal
call "%VCVARS%\%2" >nul || exit /b 1
set OBJ=%HERE%..\build\obj_%1%SUFFIX%
if not exist "%OBJ%" mkdir "%OBJ%"
rc /nologo %DEFS% /fo "%OBJ%\shunti_ime.res" "%HERE%shunti_ime.rc" || exit /b 1
cl /nologo /c /O2 /MT /EHsc /std:c++17 /utf-8 /W3 /GS /guard:cf /DNOMINMAX /DUNICODE /D_UNICODE /D_CRT_SECURE_NO_WARNINGS %DEFS% ^
  /I"%ROOT%\entry\src\main\cpp" /Fo"%OBJ%\\" ^
  "%HERE%dllmain.cpp" "%HERE%globals.cpp" "%HERE%text_service.cpp" "%HERE%cand_window.cpp" "%HERE%display_attr.cpp" "%HERE%langbar.cpp" ^
  "%HERE%input_log.cpp" "%CORE%\text.cpp" "%CORE%\romaji.cpp" "%CORE%\store.cpp" "%CORE%\settings.cpp" ^
  "%CORE%\converter.cpp" "%CORE%\composer.cpp" "%ROOT%\entry\src\main\cpp\engine.cpp" || exit /b 1
link /nologo /DLL /guard:cf /DEF:"%HERE%shunti_ime.def" /OUT:"%DIST%\shunti_ime_%1.dll" "%OBJ%\*.obj" "%OBJ%\shunti_ime.res" ^
  ole32.lib oleaut32.lib uuid.lib advapi32.lib user32.lib gdi32.lib shell32.lib dwmapi.lib || exit /b 1
del "%DIST%\shunti_ime_%1.exp" "%DIST%\shunti_ime_%1.lib" 2>nul
exit /b 0

:settings
rem settings app: plain Win32 controls (common controls v6 for the list view)
setlocal
call "%VCVARS%\vcvars64.bat" >nul || exit /b 1
set OBJ=%HERE%..\build\obj_settings%SUFFIX%
if not exist "%OBJ%" mkdir "%OBJ%"
rc /nologo %DEFS% /fo "%OBJ%\settings_app.res" "%HERE%settings_app.rc" || exit /b 1
cl /nologo /O2 /MT /EHsc /std:c++17 /utf-8 /W3 /GS /guard:cf /DNOMINMAX /DUNICODE /D_UNICODE /D_CRT_SECURE_NO_WARNINGS %DEFS% /Fo"%OBJ%\\" ^
  "%HERE%settings_app.cpp" "%CORE%\text.cpp" "%CORE%\store.cpp" "%CORE%\settings.cpp" /Fe"%DIST%\shunti_settings.exe" ^
  /link /SUBSYSTEM:WINDOWS /guard:cf "%OBJ%\settings_app.res" comctl32.lib shell32.lib ole32.lib user32.lib gdi32.lib ^
  /MANIFEST:EMBED "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'" || exit /b 1
exit /b 0
