#!/bin/bash

###########################################################################
BOOST_MAJ=1
BOOST_MIN=68
BOOST_PATCH=0
BOOST_VER=$BOOST_MAJ.$BOOST_MIN.$BOOST_PATCH
BOOST_URL=https://dl.bintray.com/boostorg/release/$BOOST_VER/source
DEP_DIR=ExternalDependencies
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

# use tar?
Get7z() {
	local DIR=$1
	local ARCHIVE=$2
	local URL=$3
	local PARENTDIR="$(dirname "$DIR")"

	if [[ -d "$DIR" ]]; then
		echo "$DIR present, skipping download"
	else
		local WGET_OPT="--secure-protocol=auto --no-check-certificate"

		if [[ ! -f "$TEMP_DIR/$ARCHIVE" ]]; then
			echo wget "$URL/$ARCHIVE" -P "$TEMP_DIR" $WGET_OPT
			wget "$URL/$ARCHIVE" -P "$TEMP_DIR" $WGET_OPT || error_exit "wget failed"
		else
			echo "$TEMP_DIR/$ARCHIVE present"
		fi

		7z x -aos -o"$PARENTDIR" "$TEMP_DIR" || error_exit "7z failed"
	fi
}

BuildBoost() {
	local BOOST_VER_UND="boost_${BOOST_VER//./_}"
	local BOOST_ARCHIVE="$BOOST_VER_UND.7z"
	local BOOST_TARGET="$TARGET_DIR/$BOOST_VER_UND"

	Get7z "$BOOST_TARGET" "$BOOST_ARCHIVE" "$BOOST_URL"

	echo "building $BOOST_TARGET"
	pushd "$BOOST_TARGET"
	if [[ ! -f "./b2" ]]; then
		./bootstrap.sh || error_exit "bootstrap failed"
	fi

	local VARIANT=debug,release
	local LINK=static
	local THREADING=multi
	local RUNTIME_LINK=static
	local ADDRESS_MODEL=64
	local ARCHITECTURE=x86
	local MODULES=system,date_time,test
	local LAYOUT=tagged

	local WITH_MODULES=""
	if [[ ! -z "$MODULES" ]]; then 
		WITH_MODULES="--with-${MODULES//,/ --with-}"
	fi

	local B2_OPTS="variant=$VARIANT link=$LINK threading=$THREADING runtime-link=$RUNTIME_LINK address-model=$ADDRESS_MODEL architecture=$ARCHITECTURE $WITH_MODULES --layout=$LAYOUT"

	echo ./b2 $B2_OPTS
	./b2 $B2_OPTS || error_exit "B2 Boost build failed"
	popd
}

clear
# echo "go $1..."
# switch $1 clean etc. 

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

BuildBoost
