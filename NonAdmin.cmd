@echo off
cls
setlocal EnableDelayedExpansion

set INSTALLDIR=%~dp0chocoportable
set BIN=%INSTALLDIR%\bin
set CHOCO=%BIN%\choco.exe

if "%1" EQU "" call :InstallChoco & goto :eof
if "%1" EQU "remove" call :RemoveChoco & goto :eof
echo Unknown: %1
goto :eof

:InstallChoco
call :RemoveChoco
mkdir %INSTALLDIR%
setx ChocolateyInstall %INSTALLDIR% 1>nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "(iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1')))"
if %ERRORLEVEL% NEQ 0 echo install failed & goto :eof

echo y|%CHOCO% feature disable -n=showNonElevatedWarnings
if %ERRORLEVEL% NEQ 0 echo feature disable failed & goto :eof

%CHOCO% install 7zip.portable;wget -y
if %ERRORLEVEL% NEQ 0 echo install failed & goto :eof
goto :eof

:RemoveChoco
REG delete HKCU\Environment /F /V ChocolateyInstall >nul 2>nul
REG delete HKCU\Environment /F /V ChocolateyLastPathUpdate >nul 2>nul
if exist %INSTALLDIR%\nul rd %INSTALLDIR% /S /Q
call :RemoveFromUserPath %BIN%
goto :eof

:RemoveFromUserPath
set REMOVE=%1
rem test with spaces
call :SetFromReg Path HKCU\Environment UserPath
if "%UserPath%" EQU "" echo NotFound & goto :EOF
set NewUserPath=!UserPath:%REMOVE%=!
if "%NewUserPath%" EQU "%UserPath%" goto :eof
%SystemRoot%\System32\reg.exe ADD HKCU\Environment /v Path /t REG_EXPAND_SZ /d %NewUserPath% /f 1>nul
if %ERRORLEVEL% NEQ 0 echo SetReg failed & goto :eof
echo "Path removed"
goto :eof

:SetFromReg
set "%~3="
for /F "skip=2 tokens=1,2*" %%N in ('%SystemRoot%\System32\reg.exe query "%~2" /v "%~1" 2^>nul') do if /I "%%N" == "%~1" set "%~3=%%P"
goto :eof
