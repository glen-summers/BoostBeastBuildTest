:: Build boost beast, openssl and test application from on-line sources
:: assumption: visual studio is installed with support for vswhere and c++ components are present

:: todos
:: convert this to msbuild or powershell as will be present with vs, for potentially a less esoteric version?
:: store downloads in user profile and\or dont delete with clean
@echo off
cls
setlocal EnableDelayedExpansion

set ROOT=%~dp0
set TEMP_DIR=%ROOT%tempFiles
set BUILD=%ROOT%bin

set NugetVer=v5.4.0
set NugetUrl=https://dist.nuget.org/win-x86-commandline/%NugetVer%/nuget.exe

set SevenZipNuget=7-Zip.CommandLine
set SevenZipVer=18.1.0
set SevenZip=%TEMP_DIR%\%SevenZipNuget%.%SevenZipVer%\tools\x64\7za.exe

set BOOST_MAJ=1
set BOOST_MIN=72
set BOOST_PATCH=0
set BOOST_VER=%BOOST_MAJ%.%BOOST_MIN%.%BOOST_PATCH%
set BOOST_URL=https://dl.bintray.com/boostorg/release/%BOOST_VER%/source
set VS_TOOLS_VER=vc142

set SSL_VER=openssl-1.1.1d
set SSL_URL=https://www.openssl.org/source

set PERL_VER=5.30.1.1
set PERL_URL=http://strawberryperl.com/download/%PERL_VER%

::###########################################################################

set VSWHERE_CMD="%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -property installationPath

call :FindDirectoryAbove .\ExternalDependencies\ && set "TARGET_DIR=!DIR_ABOVE!\ExternalDependencies" || set "TARGET_DIR=!TEMP_DIR!"

set BOOST_VER_UND=boost_%BOOST_VER:.=_%
set BOOST_ARCHIVE=%BOOST_VER_UND%.7z
set BOOST_TARGET=%TARGET_DIR%\%BOOST_VER_UND%

set SSL_TARGET=%TARGET_DIR%\%SSL_VER%

set PERL_ARCHIVE=strawberry-perl-%PERL_VER%-64bit-portable.zip
set PERL=%TEMP_DIR%\perl\perl\bin\perl.exe

::###########################################################################

for /F "tokens=* usebackq" %%i in (`%VSWHERE_CMD%`) do set VS_INSTALLATION_PATH=%%i
if "%VS_INSTALLATION_PATH%" equ "" echo Visual studio not found & exit /b 1
set VC_VARS_64="%VS_INSTALLATION_PATH%\VC\Auxiliary\Build\vcvars64.bat"

if "%1" EQU "" goto :default
call :%* || exit /b 1
exit /b 0

:default
echo Targeting "%TARGET_DIR%"
call :TimingStart

mkdir %TEMP_DIR% 2>nul
call :Download %NugetUrl% %TEMP_DIR%\Nuget.exe || exit /b 1
call :DownloadNuget %SevenZipNuget% %SevenZipVer% %TEMP_DIR% || exit /b 1
call :InstallBoost || exit /b 1

call :InstallPerl || exit /b 1
call :InstallSsl || exit /b 1

call :build || exit /b 1

call :TimingEnd
exit /b 0

:Nuke
call :DeleteTree %BOOST_TARGET% || exit /b 1
call :DeleteTree %SSL_TARGET% || exit /b 1

:Clean
call :DeleteTree %TEMP_DIR%
call :DeleteTree %BUILD%
exit /b 0

:rebuild
call :DeleteTree %BUILD% || (echo Clean failed & exit /b 1)
:build
echo %0
setlocal
cd %ROOT%
set BOOST_LIBRARY_PATH=%BOOST_TARGET%
set SSL_LIBRARY_PATH=%SSL_TARGET%
%BOOST_TARGET%\b2.exe release -sBOOST_ROOT=%BOOST_TARGET% -d2 || (echo B2 failed & exit /b 1)

:: this adds local ssl\bin to end of path, so cld still find dlls in system32 installed by existing openssl installation
:: add warning if dlls found on existing path, or just add path to front?
call :AddToLocalPath %SSL_TARGET%\bin
:: cld set to env block to extend use after this script exits: setx PATH %PATH% || (echo setx failed & exit /b 1)
::vars for all these path pieces...
%BUILD%\msvc-14.0\release\address-model-64\architecture-x86\link-static\runtime-link-static\threading-multi\app1.exe || (echo app1 failed & exit /b 1)
exit /b 0

:build2
echo %0
setlocal
call %VC_VARS_64% || (echo vc vars failed & exit /b 1)
cd %ROOT%
mkdir bin\build2\release
cl App1.cpp -Fo"bin\build2\release\App1.obj" -TP /O2 /Ob2 /W3 /GR /MT /Zc:forScope /Zc:wchar_t /favor:blend /wd4675 /EHs -c -DBOOST_ALL_NO_LIB -DNDEBUG -I%BOOST_TARGET% -I%SLL_TARGET%\include || (echo cl failed & exit /b 1)
link bin\build2\release\App1.obj %BOOST_TARGET%\stage\lib\libboost_system-%VS_TOOLS_VER%-mt-s-x64-%BOOST_MAJ%_%BOOST_MIN%.lib || (echo link failed && exit /b 1)
exit /b 0

:InstallBoost
echo %0
setlocal
if not exist %BOOST_TARGET% (
	call :Download %BOOST_URL%/%BOOST_ARCHIVE% %TEMP_DIR%\%BOOST_ARCHIVE% || exit /b 1
	%SevenZip% x -aos -o%TARGET_DIR% %TEMP_DIR%\%BOOST_ARCHIVE% || (echo Boost Extract failed & exit /b 1)
)

cd %BOOST_TARGET% || exit /b 1
if not exist .\b2.exe call .\bootstrap.bat || (echo Boost Bootstrap failed & exit /b 1)
rem if exist libs?

set VARIANT=debug,release
set LINK=static
set THREADING=multi
set RUNTIME_LINK=static
set ADDRESS_MODEL=32,64
set ARCHITECTURE=x86
set MODULES=system,date_time,test

if "%MODULES%" NEQ "" ( set WITH_MODULES=--with-!MODULES:,= --with-! ) else (set "WITH_MODULES=")

set B2_OPTS=variant=%VARIANT% link=%LINK% threading=%THREADING% runtime-link=%RUNTIME_LINK% address-model=%ADDRESS_MODEL% architecture=%ARCHITECTURE% %WITH_MODULES%

call .\b2.exe %B2_OPTS% || (echo B2 Boost build failed & exit /b 1)

:: boost build seems to try and link without the x64 in the lib file name, differing to auto_link.hpp rules when used in visual studio!
copy stage\lib\libboost_system-%VS_TOOLS_VER%-mt-s-x64-%BOOST_MAJ%_%BOOST_MIN%.lib stage\lib\libboost_system-%VS_TOOLS_VER%-mt-s-%BOOST_MAJ%_%BOOST_MIN%.lib || (echo lib copy failed & exit /b 1)
exit /b 0

:InstallPerl
echo %0
if exist %TEMP_DIR%\perl\nul exit /b 0
call :Download %PERL_URL%/%PERL_ARCHIVE% %TEMP_DIR%\%PERL_ARCHIVE% || exit /b 1
mkdir %TEMP_DIR%\perl
%SevenZip% x -aos -o%TEMP_DIR%\perl %TEMP_DIR%\%PERL_ARCHIVE% || (echo Boost Extract failed & exit /b 1)
exit /b 0

:InstallSsl
echo %0
setlocal
if exist %SSL_TARGET%\include\openssl\opensslconf.h (echo OpenSsl present & exit /b 0)

call :Download %SSL_URL%/%SSL_VER%.tar.gz %TEMP_DIR%\%SSL_VER%.tar.gz || exit /b 1
if not exist %TEMP_DIR%\%SSL_VER%\nul %SevenZip% x -so %TEMP_DIR%\%SSL_VER%.tar.gz | %SevenZip% x -si -ttar -o%TEMP_DIR% || (echo Extract failed & exit /b 1)

if not exist %SSL_TARGET% mkdir %SSL_TARGET% || (echo mkdir openssl failed & exit /b 1)
pushd %TEMP_DIR%\%SSL_VER%
%PERL% .\Configure VC-WIN64A no-asm --prefix=%SSL_TARGET% --openssldir=%SSL_TARGET%\ssl || (echo Ssl config failed & exit /b 1)
call %VC_VARS_64% || (echo vc vars failed & exit /b 1)
del /q %TEMP_DIR%\ssl.log %TEMP_DIR%\sslerr.log 2>nul
nmake 1>%TEMP_DIR%\ssl.log 2>%TEMP_DIR%\sslerr.log || (echo nmake failed check ssl.log & exit /b 1)
nmake install 1>>%TEMP_DIR%\ssl.log 2>>%TEMP_DIR%\sslerr.log || (echo nmake install failed check ssl.log & exit /b 1)
::lots of 'pod2html' is not recognized but no failure code?
:: verify by headers\libs\dlls generated?
popd
call :DeleteTree %TEMP_DIR%\%SSL_VER%
exit /b 0

:AddToLocalPath
if "!PATH:%1=!" NEQ "%PATH%" exit /b 0
echo adding %1 to path 
set PATH=%PATH%;%1
set PATH=!PATH:;;=;!
exit /b 0

:PrintNoRet
<nul set /p="%*" & exit /b 0

:DeleteTree
if not exist "%~1" exit /b 0
call :PrintNoRet deleting "%~1"...
setlocal
set /a tries=0
:loop
set /a tries+=1
rd "%~1" /s /q || call :PrintNoRet %tries%.
timeout 1 >nul
if not exist "%~1" (echo deleted & exit /b 0)
if %tries% neq 10 goto :loop
echo failed to delete, retries exceeded 
exit /b 1

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

:FindDirectoryAbove
setlocal
cd %ROOT%
set "DIR_ABOVE="
:dirLoop
set "CURRENT_DIR=%cd%"
if EXIST %1 (endlocal & set "DIR_ABOVE=%CURRENT_DIR%" & exit /b 0)
cd..
if "%cd%" neq "%CURRENT_DIR%" goto :dirLoop 
exit /b 1

:Download
if exist %2 exit /b 0
echo "Downloading %1 -> %2"
powershell -NoProfile -ExecutionPolicy Bypass -Command "(((new-object net.webclient).DownloadFile('%1', '%2')))" || (echo download failed & exit /b 1)
exit /b 0

:DownloadNuget
if exist "%3\%1.%2" exit /b 0
echo "Nuget %1 %2 -> %3\%1.%2"
%TEMP_DIR%\Nuget.exe install %1 -version %2 -OutputDirectory %TEMP_DIR% -PackageSaveMode nuspec || (echo nuget failed & exit /b 1)
exit /b 0