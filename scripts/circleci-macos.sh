#!/usr/bin/env bash

SCRIPTS=$(dirname "${BASH_SOURCE[0]}")

system_profiler SPHardwareDataType SPSoftwareDataType SPStorageDataType SPDeveloperToolsDataType

export HOMEBREW_NO_AUTO_UPDATE=1
brew install cmake pkgconfig libtool

# FIXME: Store this somewhere else to avoid having to manually update this script

LIBRARIES_CACHE_SHA512=b024093094bfffb14ca3afd1c36967a2015ef79ff409685eca75ac5e2546b7ba3a899de1ac7e3e34ee961b1eb6f77d01aef8b87df752a150262cbc2bdc6ccd78
CI_BASEDIR=$HOME/project
LIBRARIES_CACHE=libraries.tar.bz2
export OPENSCAD_LIBRARIES=$HOME/libraries/install
mkdir -p "$OPENSCAD_LIBRARIES"
( echo "Loading libraries cache..." ; cd /tmp && curl -f -s -O https://files.openscad.org/circleci/"$LIBRARIES_CACHE" ) || true
if [ -f /tmp/$LIBRARIES_CACHE ]; then
    tar xj -C "$OPENSCAD_LIBRARIES" -f /tmp/$LIBRARIES_CACHE || true
    if [ "$(shasum -a 512 /tmp/$LIBRARIES_CACHE | cut -d ' ' -f 1)" != "$LIBRARIES_CACHE_SHA512" ]; then
        echo "Failed to match sha512 for $LIBRARIES_CACHE"
        exit 1
    fi
fi
export PKG_CONFIG_PATH=$OPENSCAD_LIBRARIES/lib/pkgconfig
export DYLD_LIBRARY_PATH=$OPENSCAD_LIBRARIES/lib
export DYLD_FRAMEWORK_PATH=$OPENSCAD_LIBRARIES/lib
echo "DYLD_LIBRARY_PATH: $DYLD_LIBRARY_PATH"
# Our own Qt
export PATH=$OPENSCAD_LIBRARIES/bin:$PATH
unset QMAKESPEC
./scripts/macosx-build-dependencies.sh double_conversion
./scripts/macosx-build-dependencies.sh eigen
./scripts/macosx-build-dependencies.sh gmp
./scripts/macosx-build-dependencies.sh mpfr
./scripts/macosx-build-dependencies.sh glew
./scripts/macosx-build-dependencies.sh gettext
./scripts/macosx-build-dependencies.sh libffi
./scripts/macosx-build-dependencies.sh freetype
./scripts/macosx-build-dependencies.sh ragel
./scripts/macosx-build-dependencies.sh harfbuzz
./scripts/macosx-build-dependencies.sh libzip
./scripts/macosx-build-dependencies.sh libxml2
./scripts/macosx-build-dependencies.sh fontconfig || true
./scripts/macosx-build-dependencies.sh hidapi
./scripts/macosx-build-dependencies.sh libuuid
./scripts/macosx-build-dependencies.sh lib3mf
./scripts/macosx-build-dependencies.sh glib2
./scripts/macosx-build-dependencies.sh boost
./scripts/macosx-build-dependencies.sh cgal
./scripts/macosx-build-dependencies.sh qt5
./scripts/macosx-build-dependencies.sh opencsg
./scripts/macosx-build-dependencies.sh qscintilla
./scripts/macosx-build-dependencies.sh -d sparkle

mkdir -p /tmp/out
tar cj -C "$OPENSCAD_LIBRARIES" -f /tmp/out/"$LIBRARIES_CACHE" .
shasum -a 512 /tmp/out/"$LIBRARIES_CACHE" > /tmp/out/"$LIBRARIES_CACHE".sha512

VERSION=$(date "+%Y.%m.%d")
export NUMCPU=4
time ./scripts/release-common.sh -v $VERSION snapshot

echo "Sanity check of the app bundle..."
./scripts/macosx-sanity-check.py OpenSCAD.app/Contents/MacOS/OpenSCAD
if [[ $? != 0 ]]; then
  exit 1
fi

OPENSCAD_DMG=OpenSCAD-$VERSION.dmg
shasum -a 256 "$OPENSCAD_DMG" > "$OPENSCAD_DMG".sha256
shasum -a 512 "$OPENSCAD_DMG" > "$OPENSCAD_DMG".sha512

SIGNATURE=$(openssl dgst -sha1 -binary < "$OPENSCAD_DMG" | openssl dgst -dss1 -sign $HOME/.ssh/openscad-appcast.pem | openssl enc -base64)

APPCASTFILE=appcast-snapshots.xml

echo "Creating appcast $APPCASTFILE..."
FILESIZE=$(stat -f "%z" "$OPENSCAD_DMG")
sed -e "s,@VERSION@,$VERSION,g" -e "s,@SHORTVERSION@,$SHORTVERSION,g" -e "s,@VERSIONDATE@,$VERSIONDATE,g" -e "s,@DSASIGNATURE@,$SIGNATURE,g" -e "s,@FILESIZE@,$FILESIZE,g" $APPCASTFILE.in > $APPCASTFILE

cp -v "$OPENSCAD_DMG"* /tmp/out/
cp $APPCASTFILE /tmp/out/
