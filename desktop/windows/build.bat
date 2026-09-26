@echo off
rem Build the Windows version (TSF text service DLL) with MSVC (Visual Studio 2022 Build Tools).
rem Both x64 and x86 DLLs are needed (64-bit and 32-bit apps each load their own).
rem Output: desktop\build\dist\ (shunti_ime_x64.dll, shunti_ime_x86.dll, dictionary and model)
setlocal
set HERE=%~dp0
set ROOT=%HERE%..\..
set DIST=%HERE%..\build\dist
set VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build
if not exist "%DIST%" mkdir "%DIST%"

call :build x64 vcvars64.bat || exit /b 1
call :build x86 vcvarsamd64_x86.bat || exit /b 1

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
set OBJ=%HERE%..\build\obj_%1
if not exist "%OBJ%" mkdir "%OBJ%"
rc /nologo /fo "%OBJ%\shunti_ime.res" "%HERE%shunti_ime.rc" || exit /b 1
cl /nologo /c /O2 /MT /EHsc /std:c++17 /utf-8 /W3 /GS /guard:cf /DNOMINMAX /DUNICODE /D_UNICODE /D_CRT_SECURE_NO_WARNINGS ^
  /I"%ROOT%\entry\src\main\cpp" /Fo"%OBJ%\\" ^
  "%HERE%dllmain.cpp" "%HERE%globals.cpp" "%HERE%text_service.cpp" "%HERE%cand_window.cpp" "%HERE%display_attr.cpp" "%HERE%langbar.cpp" ^
  "%ROOT%\desktop\core\text.cpp" "%ROOT%\desktop\core\romaji.cpp" "%ROOT%\desktop\core\store.cpp" ^
  "%ROOT%\desktop\core\converter.cpp" "%ROOT%\desktop\core\composer.cpp" "%ROOT%\entry\src\main\cpp\engine.cpp" || exit /b 1
link /nologo /DLL /guard:cf /DEF:"%HERE%shunti_ime.def" /OUT:"%DIST%\shunti_ime_%1.dll" "%OBJ%\*.obj" "%OBJ%\shunti_ime.res" ^
  ole32.lib oleaut32.lib uuid.lib advapi32.lib user32.lib gdi32.lib shell32.lib dwmapi.lib || exit /b 1
del "%DIST%\shunti_ime_%1.exp" "%DIST%\shunti_ime_%1.lib" 2>nul
exit /b 0
