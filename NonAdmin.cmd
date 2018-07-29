@echo off
cls
setlocal EnableDelayedExpansion

set INSTALLDIR=%~dp0chocoportable
set BIN=%INSTALLDIR%\bin
set CHOCO=%BIN%\choco.exe
set TMP=%~dp0tmp

if "%1" EQU "" call :InstallChoco & goto :eof
if "%1" EQU "clean" call :Clean & goto :eof
if "%1" equ "boost" call :InstallBoost & goto :eof
echo Unknown: %1
goto :eof

:Clean
call :RemoveChoco
call :DeleteTree %TMP%
goto :eof

:InstallChoco
if exist %CHOCO% echo Choco present & goto :eof
mkdir %INSTALLDIR%
setx ChocolateyInstall %INSTALLDIR% 1>nul
set ChocolateyInstall=%INSTALLDIR%
powershell -NoProfile -ExecutionPolicy Bypass -Command "(iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1')))"
if %ERRORLEVEL% NEQ 0 echo install failed & goto :eof

echo y|%CHOCO% feature disable -n=showNonElevatedWarnings
if %ERRORLEVEL% NEQ 0 echo feature disable failed & goto :eof

%CHOCO% install 7zip.portable;wget -y
if %ERRORLEVEL% NEQ 0 echo install failed & goto :eof
echo installed
goto :eof

:RemoveChoco
REG delete HKCU\Environment /F /V ChocolateyInstall >nul 2>nul
REG delete HKCU\Environment /F /V ChocolateyLastPathUpdate >nul 2>nul
call :RemoveFromUserPath %BIN%
call :DeleteTree %INSTALLDIR%
goto :eof

:RemoveFromUserPath
set REMOVE=%1
rem test with spaces
call :SetFromReg Path HKCU\Environment UserPath
if "%UserPath%" EQU "" echo NotFound & goto :EOF
set NewUserPath=!UserPath:%REMOVE%=!
set NewUserPath=!NewUserPath:;;=;!
if "%NewUserPath%" EQU "%UserPath%" goto :eof
%SystemRoot%\System32\reg.exe ADD HKCU\Environment /v Path /t REG_EXPAND_SZ /d %NewUserPath% /f 1>nul
if %ERRORLEVEL% NEQ 0 echo SetReg failed & goto :eof
echo %REMOVE% removed from path
goto :eof

:SetFromReg
set "%~3="
for /F "skip=2 tokens=1,2*" %%N in ('%SystemRoot%\System32\reg.exe query "%~2" /v "%~1" 2^>nul') do if /I "%%N" == "%~1" set "%~3=%%P"
goto :eof

:DeleteTree
if not exist %1 goto :eof
SET /A tries=3
:loop
if %tries% EQU 0 echo Failed to delete %1 & exit /b 1
set /A tries-=1
rd %1 /S /Q && (echo Deleted %1) || (goto :loop)
exit /b 0

:InstallBoost
set URL=https://dl.bintray.com/boostorg/release/1.67.0/source
set BOOST_VER=boost_1_67_0
set BOOST_ARCHIVE=%BOOST_VER%.7z
set opt=--secure-protocol=auto --no-check-certificate

rem use procedure
for /F "tokens=1-4 delims=:.," %%a in ("%time%") do (
   set /A "start=(((%%a*60)+1%%b %% 100)*60+1%%c %% 100)*100+1%%d %% 100"
)

if exist %TMP%\%BOOST_ARCHIVE% goto :skipDl
%bin%\wget.exe %URL%/%BOOST_ARCHIVE% -P %TMP% %OPT%
if %ERRORLEVEL% NEQ 0 echo wget failed & exit /b 1
:skipDl

if exist %TMP%\%BOOST_VER% goto :skipExtract
%bin%\7z.exe x -aos -o%TMP% %TMP%\%BOOST_ARCHIVE%
if %ERRORLEVEL% NEQ 0 echo Extract failed & exit /b 1
:skipExtract

pushd %TMP%\%BOOST_VER%
if exist .\b2.exe goto :skipB2
call .\bootstrap.bat || (echo Bootstrap failed & exit /b 1)
:skipB2

rem if exist libs?
call .\b2.exe || (echo B2 failed & exit /b 1)

rem use procedure
for /F "tokens=1-4 delims=:.," %%a in ("%time%") do (
   set /A "end=(((%%a*60)+1%%b %% 100)*60+1%%c %% 100)*100+1%%d %% 100"
)
set /A elapsed=end-start
set /A hh=elapsed/(60*60*100), rest=elapsed%%(60*60*100), mm=rest/(60*100), rest%%=60*100, ss=rest/100, cc=rest%%100
if %mm% lss 10 set mm=0%mm%
if %ss% lss 10 set ss=0%ss%
if %cc% lss 10 set cc=0%cc%
echo %hh%:%mm%:%ss%.%cc%

exit /b 0
