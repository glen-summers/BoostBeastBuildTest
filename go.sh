#!/bin/bash

###########################################################################
BOOST_MAJ=1
BOOST_MIN=68
BOOST_PATCH=0
BOOST_VER=$BOOST_MAJ.$BOOST_MIN.$BOOST_PATCH
BOOST_URL=https://dl.bintray.com/boostorg/release/$BOOST_VER/source
DEP_DIR=ExternalDependencies

SSL_VER=openssl-1.1.0i
SSL_URL=https://www.openssl.org/source

WGET_OPT="--secure-protocol=auto --no-check-certificate"
###########################################################################

error_exit() {
	echo "$1" 1>&2
	exit 1
}

FindDirectoryAbove() {
	local path="$1"
	while [[ "$path" != "" && ! -d "$path/$2" ]]; do
		path="${path%/*}"
	done
	echo "$path"
}

Download() {
	local URL=$1
	local ARCHIVE=$2

	if [[ ! -f "$TEMP_DIR/$ARCHIVE" ]]; then
		echo wget "$URL/$ARCHIVE" -P "$TEMP_DIR" $WGET_OPT
		wget "$URL/$ARCHIVE" -P "$TEMP_DIR" $WGET_OPT || error_exit "wget failed"
	else
		echo "$TEMP_DIR/$ARCHIVE present"
	fi
}

Get7z() {
	local URL=$1
	local ARCHIVE=$2
	local DIR=$3

	Download "$URL" "$ARCHIVE"
	7z x -aos -o"$DIR" "$TEMP_DIR/$ARCHIVE" || error_exit "7z failed"
}

GetTarGz() {
	local URL=$1
	local ARCHIVE=$2
	local DIR=$3

	Download "$URL" "$ARCHIVE"
	7z x -so "$TEMP_DIR/$ARCHIVE" | 7z x -si -ttar -o"$DIR" #|| error_exit "extract failed"
}

BuildBoost() {
	local BOOST_VER_UND="boost_${BOOST_VER//./_}"
	local BOOST_ARCHIVE="$BOOST_VER_UND.7z"
	BOOST_TARGET="$TARGET_DIR/$BOOST_VER_UND"

	if [[ -d "$BOOST_TARGET" ]]; then
		echo "$BOOST_TARGET present, skipping download"
	else
		Get7z "$BOOST_URL" "$BOOST_ARCHIVE" "$TARGET_DIR"
	fi

	echo "building $BOOST_TARGET"
	pushd "$BOOST_TARGET"
	if [[ ! -f "./b2" ]]; then
		./bootstrap.sh || error_exit "bootstrap failed"
	fi

	#local VARIANT=debug,release
	local VARIANT=release
	local LINK=static
	local THREADING=multi
	local RUNTIME_LINK=static
	local ADDRESS_MODEL=64
	local ARCHITECTURE=x86
	local MODULES=system,date_time,test
	
	# causes debug,release build error, tagged causes link error
	local LAYOUT=versioned

	local WITH_MODULES=""
	if [[ ! -z "$MODULES" ]]; then 
		WITH_MODULES="--with-${MODULES//,/ --with-}"
	fi

	local B2_OPTS="variant=$VARIANT link=$LINK threading=$THREADING runtime-link=$RUNTIME_LINK address-model=$ADDRESS_MODEL architecture=$ARCHITECTURE $WITH_MODULES --layout=$LAYOUT"

	echo ./b2 $B2_OPTS
	./b2 $B2_OPTS || error_exit "B2 Boost build failed"
	popd
}

BuildSsl() {
	SSL_TARGET="$TARGET_DIR/$SSL_VER"
	local SSL_ARCHIVE="$SSL_VER.tar.gz"
	
	if [[ -f "$SSL_TARGET/include/openssl/opensslconf.h" ]]; then
		echo "openssl present"
	else
		GetTarGz "$SSL_URL" "$SSL_ARCHIVE" "$SSL_TARGET"

		echo "building $SSL_TARGET"
		pushd "$TEMP_DIR/$SSL_VER"
		# chmod +x ./Configure || error_exit "chmod failed"
		#./Configure linux-generic64 --prefix="$SSL_TARGET" --openssldir="$SSL_TARGET\ssl" || error_exit "Configure failed"

		chmod +x ./config || error_exit "chmod failed"
		./config --prefix="$SSL_TARGET" --openssldir="$SSL_TARGET/ssl" || error_exit "config failed"
		
		echo make || error_exit "make failed"
		echo make install || error_exit "make install failed"
		popd

		#rm -r "$TEMP_DIR/$SSL_VER" || error_exit "rm ssl temp dir failed"
	fi
}

BuildTestApp() {
	pushd "$ROOT"
	export BOOST_LIBRARY_PATH="$BOOST_TARGET"
	export SSL_LIBRARY_PATH="$SSL_TARGET"
	export BOOST_MAJ="$BOOST_MAJ"
	export BOOST_MIN="$BOOST_MIN"

	$BOOST_TARGET/b2 Jamroot -sBOOST_ROOT=$BOOST_TARGET -d2 --layout=versioned || error_exit "Build failed"

	#parms
	#./bin/gcc-7.3.0/release/address-model-64/architecture-x86/link-static/runtime-link-static/threading-multi/App1
	popd
}

Init() {
	ROOT=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
	TEMP_DIR="$ROOT/tempFiles"
	BUILD="$ROOT/bin"

	ABOVE="$( FindDirectoryAbove $ROOT $DEP_DIR )"
	if [[ -z "$ABOVE" ]]; then
		TARGET_DIR="$TEMP_DIR"
	else
		TARGET_DIR="$ABOVE/$DEP_DIR"
	fi
	echo "TARGET_DIR = $TARGET_DIR"
}

Build() {
	BuildBoost
	BuildSsl
	BuildTestApp
}

Clean() {
	rm -r "$TEMP_DIR" || error_exit "rm temp dir failed"
}

clear
echo "go $1..."
case "$1" in
	"")
		Init
		Build
		;;
	clean)
		Init
		Clean
		;;
	*)
		error_exit "Usage: $0 {|clean}"
esac
