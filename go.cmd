:: Build boost beast application with ssl from inet sources
:: assumption: visual studio is installed with support for vswhere and c++ components are present
@echo off
cls
setlocal EnableDelayedExpansion

::###########################################################################

set VSWHERE_CMD="%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -property installationPath

set ROOT=%~dp0
set TMP=%ROOT%tmp
set BUILD=%ROOT%bin
set TARGET_DIR=%TMP%

if "%~1" EQU "-target" (
	set TARGET_DIR=%~2
	shift & shift
)

set CHOCO_DIR=%TMP%\chocoportable
set CHOCO_BIN=%CHOCO_DIR%\bin
set CHOCO=%CHOCO_BIN%\choco.exe
set ChocoPackages=7zip.portable;wget

set BOOST_VER=1.67.0
set BOOST_VER_UND=boost_%BOOST_VER:.=_%
set BOOST_URL=https://dl.bintray.com/boostorg/release/%BOOST_VER%/source
set BOOST_ARCHIVE=%BOOST_VER_UND%.7z
set BOOST_TARGET=%TARGET_DIR%\%BOOST_VER_UND%

set SSL_URL=https://www.openssl.org/source
set SSL_VER=openssl-1.1.0h
set SSL_TARGET=%TARGET_DIR%\openssl

set PERL_VER=5.28.0.1
set PERL_URL=http://strawberryperl.com/download/%PERL_VER%
set PERL_ARCHIVE=strawberry-perl-%PERL_VER%-64bit-portable
set PERL=%TMP%\perl\perl\bin\perl.exe

set WGET_OPT=--secure-protocol=auto --no-check-certificate
::###########################################################################

for /F "tokens=* usebackq" %%i in (`%VSWHERE_CMD%`) do set VS_INSTALLATION_PATH=%%i
if "%VS_INSTALLATION_PATH%" equ "" echo Visual studio not found & exit /b 1
set VC_VARS_64="%VS_INSTALLATION_PATH%\VC\Auxiliary\Build\vcvars64.bat"

if "%1" EQU "" goto :default
call :%1 || exit /b 1
exit /b 0

:default
call :TimingStart

call :InstallChoco || exit /b 1
call :InstallBoost || exit /b 1
call :InstallPerl || exit /b 1
call :InstallSsl || exit /b 1

call :build || exit /b 1

call :TimingEnd
exit /b 0

:Clean
call :RemoveChoco
call :DeleteTree %TMP%
call :DeleteTree %BUILD%
exit /b 0

:rebuild
call :DeleteTree %BUILD% || (echo Clean failed & exit /b 1)
:build
echo %0
pushd %ROOT%
set BOOST_LIBRARY_PATH=%BOOST_TARGET%
set SSL_LIBRARY_PATH=%SSL_TARGET%
%BOOST_TARGET%\b2.exe release -sBOOST_ROOT=%BOOST_TARGET% -d2 || (echo B2 failed & exit /b 1)
::var
%BUILD%\msvc-14.1\release\address-model-64\architecture-x86\link-static\runtime-link-static\threading-multi\app1.exe || (echo app1 failed & exit /b 1)
exit /b 0

:build2
echo %0
call %VC_VARS_64% || (echo vc vars failed & exit /b 1)
pushd %ROOT%
md bin\build2\release
cl App1.cpp -Fo"bin\build2\release\App1.obj" -TP /O2 /Ob2 /W3 /GR /MT /Zc:forScope /Zc:wchar_t /favor:blend /wd4675 /EHs -c -DBOOST_ALL_NO_LIB -DNDEBUG -I%BOOST_TARGET% -I%SLL_TARGET%\include || (echo cl failed & exit /b 1)
link bin\build2\release\App1.obj %BOOST_TARGET%\stage\lib\libboost_system-vc141-mt-s-x64-1_67.lib || (echo link failed && exit /b 1)
exit /b 0

:InstallChoco
echo %0
if exist %CHOCO% (echo Choco present & exit /b 0)
mkdir %CHOCO_DIR% 2>nul
setx ChocolateyInstall %CHOCO_DIR% 1>nul
set ChocolateyInstall=%CHOCO_DIR%
powershell -NoProfile -ExecutionPolicy Bypass -Command "(iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1')))" || (echo choco install failed & exit /b 1)
echo y|%CHOCO% feature disable -n=showNonElevatedWarnings || (echo choco feature disable failed & exit /b 1)
%CHOCO% install %ChocoPackages% -y || (echo package install failed & exit /b 1)
exit /b 0

:RemoveChoco
REG delete HKCU\Environment /F /V ChocolateyInstall >nul 2>nul
REG delete HKCU\Environment /F /V ChocolateyLastPathUpdate >nul 2>nul
call :RemoveFromUserPath %CHOCO_BIN%
call :DeleteTree %CHOCO_DIR%
exit /b 0

:InstallBoost
echo %0

if not exist %TMP%\%BOOST_ARCHIVE% %CHOCO_BIN%\wget.exe %BOOST_URL%/%BOOST_ARCHIVE% -P %TMP% %WGET_OPT% || (echo Boost wget failed & exit /b 1)
if not exist %BOOST_TARGET% %CHOCO_BIN%\7z.exe x -aos -o%TARGET_DIR% %TMP%\%BOOST_ARCHIVE% || (echo Boost Extract failed & exit /b 1)
::pops ok on error?
pushd %BOOST_TARGET%
if not exist .\b2.exe call .\bootstrap.bat || (echo Boost Bootstrap failed & exit /b 1)
rem if exist libs?

set VARIANT=debug,release
set LINK=static
set THREADING=multi
set RUNTIME_LINK=static
set ADDRESS_MODEL=64
set ARCHITECTURE=x86
set MODULES=system,date_time

if "%MODULES%" NEQ "" ( set WITH_MODULES=--with-!MODULES:,= --with-! ) else (set "WITH_MODULES=")

set B2_OPTS=variant=%VARIANT% link=%LINK% threading=%THREADING% runtime-link=%RUNTIME_LINK% address-model=%ADDRESS_MODEL% architecture=%ARCHITECTURE% %WITH_MODULES%

call .\b2.exe %B2_OPTS% || (echo B2 Boost build failed & exit /b 1)

:: boost build seems to try and link without the x64 in the lib file name, differing to auto_link.hpp rules when used in visual studio!
copy stage\lib\libboost_system-vc141-mt-s-x64-1_67.lib stage\lib\libboost_system-vc141-mt-s-1_67.lib || (echo lib copy failed & exit /b 1)
exit /b 0

:InstallPerl
echo %0
if not exist %TMP%\%PERL_ARCHIVE%.zip %CHOCO_BIN%\wget.exe %PERL_URL%/%PERL_ARCHIVE%.zip -P %TMP% %WGET_OPT% || (echo wget failed & exit /b 1)
if not exist %TMP%\perl\nul %CHOCO_BIN%\7z.exe x -aos -o%TMP%\perl %TMP%\%PERL_ARCHIVE%.zip || (echo Extract failed & exit /b 1)
exit /b 0

:InstallSsl
echo %0
if exist %SSL_TARGET%\include\openssl\opensslconf.h (echo OpenSsl present & exit /b 0)
if not exist %TMP%\%SSL_VER%.tar.gz %CHOCO_BIN%\wget.exe %SSL_URL%/%SSL_VER%.tar.gz -P %TMP% %WGET_OPT% || (echo wget failed & exit /b 1)
if not exist %TMP%\%SSL_VER%.tar %CHOCO_BIN%\7z.exe x -aos -o%TMP% %TMP%\%SSL_VER%.tar.gz || (echo Extract failed & exit /b 1)
if not exist %TMP%\%SSL_VER%\nul %CHOCO_BIN%\7z.exe x -aos -o%TMP% %TMP%\%SSL_VER%.tar || (echo Extract failed & exit /b 1)
if not exist %SSL_TARGET% md %SSL_TARGET% || (echo md openssl failed & exit /b 1)
pushd %TMP%\%SSL_VER%
%PERL% .\Configure VC-WIN64A no-asm --prefix=%SSL_TARGET% --openssldir=%SSL_TARGET%\ssl || (echo Ssl config failed & exit /b 1)
call %VC_VARS_64% || (echo vc vars failed & exit /b 1)
nmake 1>nul || (echo nmake failed & exit /b 1)
nmake install 1>nul 2>nul || (echo nmake install failed & exit /b 1)
::lots of 'pod2html' is not recognized but nofailure code?
:: verify by headers\libs\dlls generated?
exit /b 0

:RemoveFromUserPath
set REMOVE=%1
rem test with spaces
call :SetFromReg Path HKCU\Environment UserPath
if "%UserPath%" EQU "" (echo NotFound & exit /b 1)
set NewUserPath=!UserPath:%REMOVE%=!
set NewUserPath=!NewUserPath:;;=;!
if "%NewUserPath%" EQU "%UserPath%" exit /b 0
%SystemRoot%\System32\reg.exe ADD HKCU\Environment /v Path /t REG_EXPAND_SZ /d %NewUserPath% /f 1>nul || (echo SetReg failed & exit /b 1)
echo %REMOVE% removed from path
exit /b 0

:SetFromReg
set "%~3="
for /F "skip=2 tokens=1,2*" %%N in ('%SystemRoot%\System32\reg.exe query "%~2" /v "%~1" 2^>nul') do if /I "%%N" == "%~1" set "%~3=%%P"
exit /b 0

:DeleteTree
SET /A tries=3
:loop
if not exist %1 exit /b 0
if %tries% EQU 0 (echo Failed to delete %1 & exit /b 1)
set /A tries-=1
rd %1 /S /Q
if exist %1 echo Retry... Err:%ERRORLEVEL% & goto :loop
exit /b 0

:TimingStart
for /F "tokens=1-4 delims=:.," %%a in ("%time%") do (
   set /A "start=(((%%a*60)+1%%b %% 100)*60+1%%c %% 100)*100+1%%d %% 100"
)
exit /b 0

:TimingEnd
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