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

VARIANT=release
LINK=static
THREADING=multi
RUNTIME_LINK=static
ADDRESS_MODEL=64
ARCHITECTURE=x86
LAYOUT=versioned
MODULES=system,date_time
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

	local WITH_MODULES=""
	if [[ ! -z "$MODULES" ]]; then 
		WITH_MODULES="--with-${MODULES//,/ --with-}"
	fi

	echo ./b2 $B2_OPTS
	./b2 $B2_OPTS $WITH_MODULES || error_exit "B2 Boost build failed"
	
	#boost build seems to try and link without the x64\x32 in the lib file name
	#    boost_system-gcc73-mt-s-1_68
	# libboost_system-gcc73-mt-s-x64-1_68
	GCC_LIB_VER="gcc$GCC_MAJ$GCC_MIN"
	cp stage/lib/libboost_system-$GCC_LIB_VER-mt-s-x$ADDRESS_MODEL-$BOOST_MAJ"_"$BOOST_MIN.a stage/lib/libboost_system-$GCC_LIB_VER-mt-s-$BOOST_MAJ"_"$BOOST_MIN.a || error_exit "lib copy failed"

	popd
}

BuildSsl() {
	SSL_TARGET="$TARGET_DIR/$SSL_VER"
	local SSL_ARCHIVE="$SSL_VER.tar.gz"
	
	if [[ -f "$SSL_TARGET/include/openssl/opensslconf.h" ]]; then
		echo "openssl present"
	else
		if [[ ! -d "$TEMP_DIR/$SSL_VER" ]]; then
			GetTarGz "$SSL_URL" "$SSL_ARCHIVE" "$TEMP_DIR"
		fi
		
		echo "building $SSL_TARGET"
		pushd "$TEMP_DIR/$SSL_VER"
		# chmod +x ./Configure || error_exit "chmod failed"
		#./Configure linux-generic64 --prefix="$SSL_TARGET" --openssldir="$SSL_TARGET\ssl" || error_exit "Configure failed"

		chmod +x ./config || error_exit "chmod failed"
		./config --prefix="$SSL_TARGET" --openssldir="$SSL_TARGET/ssl" || error_exit "config failed"
		
		make || error_exit "make failed"
		make install || error_exit "make install failed"
		popd

		#clean intermediate ssl...
		#rm -r "$TEMP_DIR/$SSL_VER" || error_exit "rm ssl temp dir failed"
	fi
}

BuildTestApp() {
	pushd "$ROOT/gcc"
	export BOOST_LIBRARY_PATH="$BOOST_TARGET"
	export SSL_LIBRARY_PATH="$SSL_TARGET"
	export BOOST_MAJ="$BOOST_MAJ"
	export BOOST_MIN="$BOOST_MIN"

	$BOOST_TARGET/b2 $B2_OPTS -sBOOST_ROOT=$BOOST_TARGET -d2 toolset=gcc || error_exit "Build failed"
	$APP_BUILD_DIR/App1 || error_exit "App1 failed"
	popd
}

Init() {
	ROOT=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
	TEMP_DIR="$ROOT/tempFiles"
	BUILD="$ROOT/gcc/bin"

	local ABOVE="$( FindDirectoryAbove $ROOT $DEP_DIR )"
	if [[ -z "$ABOVE" ]]; then
		TARGET_DIR="$TEMP_DIR"
	else
		TARGET_DIR="$ABOVE/$DEP_DIR"
	fi
	echo "TARGET_DIR = $TARGET_DIR"

	B2_OPTS="variant=$VARIANT link=$LINK threading=$THREADING runtime-link=$RUNTIME_LINK address-model=$ADDRESS_MODEL architecture=$ARCHITECTURE --layout=$LAYOUT"

	local GCC_VER="$(gcc --version | grep ^gcc | sed 's/^.* //g')"
	local REGEX="([0-9]+)\.([0-9]+)\.[0-9]"
	[[ $GCC_VER =~ $REGEX ]] || error_exit "failed to parse gcc version"
	GCC_MAJ="${BASH_REMATCH[1]}"
	GCC_MIN="${BASH_REMATCH[2]}"

	APP_BUILD_DIR="$BUILD/gcc-$GCC_VER/$VARIANT/address-model-$ADDRESS_MODEL/architecture-$ARCHITECTURE/link-$LINK/runtime-link-$RUNTIME_LINK/threading-$THREADING"
}

Build() {
	BuildBoost
	BuildSsl
	BuildTestApp
}

Clean() {
	rm -f -r "$TEMP_DIR" || error_exit "rm temp dir failed"
	rm -f -r "$BUILD" || error_exit "rm build dir failed"
}

###########################################################################

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
