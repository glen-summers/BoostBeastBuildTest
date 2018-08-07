# BoostBeastBuildTest

After being frustrated by struggling to compile boost beast web\websocket samples that include use of OpenSSL and targeting Windows I created a script to download and build dependencies from the original source
Base requirement is that VisualStudio 2017 is installed, which is located by VsWhere https://github.com/Microsoft/vswhere

The sequence is:
* Bootstrap a non-admin Chocolatey install https://chocolatey.org/docs/installation#non-administrative-install
* Obtain wget and 7z from Chocolatey
* Download Boost source code archive, https://dl.bintray.com/boostorg/release/ 
* Boostrap and build required boost libs
* Download Open-SSL source code archive https://www.openssl.org/source
* Download non-admin Strawberry Perl http://strawberryperl.com/releases.html
* Use Perl to configure OpenSSL Windows configuration
* Build OpenSSL from a Visual Studio command prompt
* Build sample application using Boost Build and run executable

Caveat
Currently the build steps include a rename of the boost system lib from
_libboost_system-vc141-mt-s-**x64**-1_67.lib_ to _libboost_system-vc141-mt-s-1_67.lib_
This appears to be a bug in boost build where the emitted link dependency is missing the x64 part in the name
When compiling inside visual studio it is ok as the boost/config/auto_link.hpp
