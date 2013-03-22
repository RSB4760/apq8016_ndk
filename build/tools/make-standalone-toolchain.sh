# Copyright (C) 2010 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Create a standalone toolchain package for Android.

. `dirname $0`/prebuilt-common.sh

PROGRAM_PARAMETERS=""
PROGRAM_DESCRIPTION=\
"Generate a customized Android toolchain installation that includes
a working sysroot. The result is something that can more easily be
used as a standalone cross-compiler, e.g. to run configure and
make scripts."

# For now, this is the only toolchain that works reliably.
TOOLCHAIN_NAME=
register_var_option "--toolchain=<name>" TOOLCHAIN_NAME "Specify toolchain name"

LLVM_VERSION=
register_var_option "--llvm-version=<ver>" LLVM_VERSION "Specify LLVM version"

STL=gnustl
register_var_option "--stl=<name>" STL "Specify C++ STL"

ARCH=
register_option "--arch=<name>" do_arch "Specify target architecture" "arm"
do_arch () { ARCH=$1; }

NDK_DIR=`dirname $0`
NDK_DIR=`dirname $NDK_DIR`
NDK_DIR=`dirname $NDK_DIR`
register_var_option "--ndk-dir=<path>" NDK_DIR "Take source files from NDK at <path>"

# Create 32-bit host toolchain by default
SYSTEM=$HOST_TAG32
register_var_option "--system=<name>" SYSTEM "Specify host system"

PACKAGE_DIR=/tmp/ndk-$USER
register_var_option "--package-dir=<path>" PACKAGE_DIR "Place package file in <path>"

INSTALL_DIR=
register_var_option "--install-dir=<path>" INSTALL_DIR "Don't create package, install files to <path> instead."

PLATFORM=
register_option "--platform=<name>" do_platform "Specify target Android platform/API level." "android-3"
do_platform () { PLATFORM=$1; }

extract_parameters "$@"

# Check NDK_DIR
if [ ! -d "$NDK_DIR/build/core" ] ; then
    echo "Invalid source NDK directory: $NDK_DIR"
    echo "Please use --ndk-dir=<path> to specify the path of an installed NDK."
    exit 1
fi

# Check ARCH
if [ -z "$ARCH" ]; then
    case $TOOLCHAIN_NAME in
        arm-*)
            ARCH=arm
            ;;
        x86-*)
            ARCH=x86
            ;;
        mips*)
            ARCH=mips
            ;;
        *)
            ARCH=arm
            ;;
    esac
    log "Auto-config: --arch=$ARCH"
fi

# Check toolchain name
if [ -z "$TOOLCHAIN_NAME" ]; then
    TOOLCHAIN_NAME=$(get_default_toolchain_name_for_arch $ARCH)
    echo "Auto-config: --toolchain=$TOOLCHAIN_NAME"
fi

# Detect LLVM version from toolchain name
if [ -z "$LLVM_VERSION" ]; then
    LLVM_VERSION_EXTRACT=$(echo "$TOOLCHAIN_NAME" | grep 'clang[0-9]\.[0-9]$' | sed -e 's/.*-clang//')
    if [ -n "$LLVM_VERSION_EXTRACT" ]; then
        TOOLCHAIN_NAME=$(get_default_toolchain_name_for_arch $ARCH)
        LLVM_VERSION=$LLVM_VERSION_EXTRACT
        echo "Auto-config: --toolchain=$TOOLCHAIN_NAME, --llvm-version=$LLVM_VERSION"
    fi
fi

# Check PLATFORM
if [ -z "$PLATFORM" ]; then
    case $ARCH in
        arm) PLATFORM=android-3
            ;;
        x86)
            PLATFORM=android-9
            ;;
        mips)
            # Set it to android-9
            PLATFORM=android-9
            ;;
    esac
    log "Auto-config: --platform=$PLATFORM"
fi

if [ ! -d "$NDK_DIR/platforms/$PLATFORM" ] ; then
    echo "Invalid platform name: $PLATFORM"
    echo "Please use --platform=<name> with one of:" `(cd "$NDK_DIR/platforms" && ls)`
    exit 1
fi

# Check toolchain name
TOOLCHAIN_PATH="$NDK_DIR/toolchains/$TOOLCHAIN_NAME"
if [ ! -d "$TOOLCHAIN_PATH" ] ; then
    echo "Invalid toolchain name: $TOOLCHAIN_NAME"
    echo "Please use --toolchain=<name> with the name of a toolchain supported by the source NDK."
    echo "Try one of: " `(cd "$NDK_DIR/toolchains" && ls)`
    exit 1
fi

# Extract architecture from platform name
parse_toolchain_name $TOOLCHAIN_NAME

# Check that there are any platform files for it!
(cd $NDK_DIR/platforms && ls -d */arch-${ARCH} >/dev/null 2>&1 )
if [ $? != 0 ] ; then
    echo "Platform $PLATFORM doesn't have any files for this architecture: $ARCH"
    echo "Either use --platform=<name> or --toolchain=<name> to select a different"
    echo "platform or arch-dependent toolchain name (respectively)!"
    exit 1
fi

# Compute source sysroot
SRC_SYSROOT="$NDK_DIR/platforms/$PLATFORM/arch-$ARCH"
if [ ! -d "$SRC_SYSROOT" ] ; then
    echo "No platform files ($PLATFORM) for this architecture: $ARCH"
    exit 1
fi

# Check that we have any prebuilts GCC toolchain here
if [ ! -d "$TOOLCHAIN_PATH/prebuilt" ] ; then
    echo "Toolchain is missing prebuilt files: $TOOLCHAIN_NAME"
    echo "You must point to a valid NDK release package!"
    exit 1
fi

if [ ! -d "$TOOLCHAIN_PATH/prebuilt/$SYSTEM" ] ; then
    echo "Host system '$SYSTEM' is not supported by the source NDK!"
    echo "Try --system=<name> with one of: " `(cd $TOOLCHAIN_PATH/prebuilt && ls) | grep -v gdbserver`
    exit 1
fi

TOOLCHAIN_PATH="$TOOLCHAIN_PATH/prebuilt/$SYSTEM"
TOOLCHAIN_GCC=$TOOLCHAIN_PATH/bin/$ABI_CONFIGURE_TARGET-gcc

if [ ! -f "$TOOLCHAIN_GCC" ] ; then
    echo "Toolchain $TOOLCHAIN_GCC is missing!"
    exit 1
fi

if [ -n "$LLVM_VERSION" ]; then
    LLVM_TOOLCHAIN_PATH="$NDK_DIR/toolchains/llvm-$LLVM_VERSION"
    # Check that we have any prebuilts LLVM toolchain here
    if [ ! -d "$LLVM_TOOLCHAIN_PATH/prebuilt" ] ; then
        echo "LLVM Toolchain is missing prebuilt files"
        echo "You must point to a valid NDK release package!"
        exit 1
    fi

    if [ ! -d "$LLVM_TOOLCHAIN_PATH/prebuilt/$SYSTEM" ] ; then
        echo "Host system '$SYSTEM' is not supported by the source NDK!"
        echo "Try --system=<name> with one of: " `(cd $LLVM_TOOLCHAIN_PATH/prebuilt && ls)`
        exit 1
    fi
    LLVM_TOOLCHAIN_PATH="$LLVM_TOOLCHAIN_PATH/prebuilt/$SYSTEM"
fi

# Get GCC_BASE_VERSION.  Note that GCC_BASE_VERSION may be slightly different from GCC_VERSION.
# eg. In gcc4.6 GCC_BASE_VERSION is "4.6.x-google"
LIBGCC_PATH=`$TOOLCHAIN_GCC -print-libgcc-file-name`
LIBGCC_BASE_PATH=${LIBGCC_PATH%/*}         # base path of libgcc.a
GCC_BASE_VERSION=${LIBGCC_BASE_PATH##*/}   # stuff after the last /

# Create temporary directory
TMPDIR=$NDK_TMPDIR/standalone/$TOOLCHAIN_NAME

dump "Copying prebuilt binaries..."
# Now copy the GCC toolchain prebuilt binaries
run copy_directory "$TOOLCHAIN_PATH" "$TMPDIR"

if [ -n "$LLVM_VERSION" ]; then
  # Copy the clang/llvm toolchain prebuilt binaries
  run copy_directory "$LLVM_TOOLCHAIN_PATH" "$TMPDIR"

  # Move clang and clang++ to clang${LLVM_VERSION} and clang${LLVM_VERSION}++,
  # then create scripts linking them with predefined -target flag.  This is to
  # make clang/++ easier drop-in replacement for gcc/++ in NDK standalone mode.
  # Note that the file name of "clang" isn't important, and the trailing
  # "++" tells clang to compile in C++ mode
  LLVM_TARGET=
  case "$ARCH" in
      arm) # NOte: -target may change by clang based on the
           #        presence of subsequent -march=armv7-a and/or -mthumb
          LLVM_TARGET=armv5te-none-linux-androideabi
          ;;
      x86)
          LLVM_TARGET=i686-none-linux-android
          ;;
      mips)
          LLVM_TARGET=mipsel-none-linux-android
          ;;
      *)
        dump "ERROR: Unsupported NDK architecture!"
  esac
  # Need to remove '.' from LLVM_VERSION when constructing new clang name,
  # otherwise clang3.1++ may still compile *.c code as C, not C++, which
  # is not consistent with g++
  LLVM_VERSION_WITHOUT_DOT=$(echo "$LLVM_VERSION" | sed -e "s!\.!!")
  mv "$TMPDIR/bin/clang${HOST_EXE}" "$TMPDIR/bin/clang${LLVM_VERSION_WITHOUT_DOT}${HOST_EXE}"
  if [ -h "$TMPDIR/bin/clang++${HOST_EXE}" ] ; then
    ## clang++ is a link to clang.  Remove it and reconstruct
    rm "$TMPDIR/bin/clang++${HOST_EXE}"
    ln -s "clang${LLVM_VERSION_WITHOUT_DOT}${HOST_EXE}" "$TMPDIR/bin/clang${LLVM_VERSION_WITHOUT_DOT}++${HOST_EXE}"
  else
    mv "$TMPDIR/bin/clang++${HOST_EXE}" "$TMPDIR/bin/clang$LLVM_VERSION_WITHOUT_DOT++${HOST_EXE}"
  fi

  cat > "$TMPDIR/bin/clang" <<EOF
if [ "\$1" != "-cc1" ]; then
    \`dirname \$0\`/clang$LLVM_VERSION_WITHOUT_DOT -target $LLVM_TARGET "\$@"
else
    # target/triple already spelled out.
    \`dirname \$0\`/clang$LLVM_VERSION_WITHOUT_DOT "\$@"
fi
EOF
  cat > "$TMPDIR/bin/clang++" <<EOF
if [ "\$1" != "-cc1" ]; then
    \`dirname \$0\`/clang$LLVM_VERSION_WITHOUT_DOT++ -target $LLVM_TARGET "\$@"
else
    # target/triple already spelled out.
    \`dirname \$0\`/clang$LLVM_VERSION_WITHOUT_DOT++ "\$@"
fi
EOF
  chmod 0755 "$TMPDIR/bin/clang" "$TMPDIR/bin/clang++"

  if [ -n "$HOST_EXE" ] ; then
    cat > "$TMPDIR/bin/clang.cmd" <<EOF
@echo off
if "%1" == "-cc1" goto :L
%~dp0\\clang${LLVM_VERSION_WITHOUT_DOT}${HOST_EXE} -target $LLVM_TARGET %*
if ERRORLEVEL 1 exit /b 1
goto :done
:L
rem target/triple already spelled out.
%~dp0\\clang${LLVM_VERSION_WITHOUT_DOT}${HOST_EXE} %*
if ERRORLEVEL 1 exit /b 1
:done
EOF
    cat > "$TMPDIR/bin/clang++.cmd" <<EOF
@echo off
if "%1" == "-cc1" goto :L
%~dp0\\clang${LLVM_VERSION_WITHOUT_DOT}++${HOST_EXE} -target $LLVM_TARGET %*
if ERRORLEVEL 1 exit /b 1
goto :done
:L
rem target/triple already spelled out.
%~dp0\\clang${LLVM_VERSION_WITHOUT_DOT}++${HOST_EXE} %*
if ERRORLEVEL 1 exit /b 1
:done
EOF
  fi
fi

dump "Copying sysroot headers and libraries..."
# Copy the sysroot under $TMPDIR/sysroot. The toolchain was built to
# expect the sysroot files to be placed there!
run copy_directory_nolinks "$SRC_SYSROOT" "$TMPDIR/sysroot"

dump "Copying libstdc++ headers and libraries..."

GNUSTL_DIR=$NDK_DIR/$GNUSTL_SUBDIR/$GCC_VERSION
GNUSTL_LIBS=$GNUSTL_DIR/libs

STLPORT_DIR=$NDK_DIR/$STLPORT_SUBDIR
STLPORT_LIBS=$STLPORT_DIR/libs

ABI_STL="$TMPDIR/$ABI_CONFIGURE_TARGET"
ABI_STL_INCLUDE="$TMPDIR/include/c++/$GCC_BASE_VERSION"
ABI_STL_INCLUDE_TARGET="$ABI_STL_INCLUDE/$ABI_CONFIGURE_TARGET"

# Copy common STL headers (i.e. the non-arch-specific ones)
copy_stl_common_headers () {
    case $STL in
        gnustl)
            copy_directory "$GNUSTL_DIR/include" "$ABI_STL_INCLUDE"
            ;;
        stlport)
            copy_directory "$STLPORT_DIR/stlport" "$ABI_STL_INCLUDE"
            copy_directory "$STLPORT_DIR/../gabi++/include" "$ABI_STL_INCLUDE/../../gabi++/include"
            (cd $ABI_STL_INCLUDE && ln -s ../../gabi++/include/cxxabi.h cxxabi.h)
            ;;
    esac
}

# $1: Source ABI (e.g. 'armeabi')
# $2: Optional extra ABI variant, or empty (e.g. "", "thumb", "armv7-a/thumb")
copy_stl_libs () {
    local ABI=$1
    local ABI2=$2
    case $STL in
        gnustl)
            copy_directory "$GNUSTL_LIBS/$ABI/include/bits" "$ABI_STL_INCLUDE_TARGET/$ABI2/bits"
            copy_file_list "$GNUSTL_LIBS/$ABI" "$ABI_STL/lib/$ABI2" "libgnustl_shared.so"
            copy_file_list "$GNUSTL_LIBS/$ABI" "$ABI_STL/lib/$ABI2" "libsupc++.a"
            cp -p "$GNUSTL_LIBS/$ABI/libgnustl_static.a" "$ABI_STL/lib/$ABI2/libstdc++.a"
            ;;
        stlport)
            copy_file_list "$STLPORT_LIBS/$ABI" "$ABI_STL/lib/$ABI2" "libstlport_shared.so"
            cp -p "$STLPORT_LIBS/$ABI/libstlport_static.a" "$ABI_STL/lib/$ABI2/libstdc++.a"
            ;;
        *)
            dump "ERROR: Unsupported STL: $STL"
            exit 1
            ;;
    esac
}

mkdir -p "$ABI_STL_INCLUDE_TARGET"
fail_panic "Can't create directory: $ABI_STL_INCLUDE_TARGET"
copy_stl_common_headers
case $ARCH in
    arm)
        copy_stl_libs armeabi ""
        copy_stl_libs armeabi "thumb"
        copy_stl_libs armeabi-v7a "armv7-a"
        copy_stl_libs armeabi-v7a "armv7-a/thumb"
        ;;
    x86|mips)
        copy_stl_libs "$ARCH" ""
        ;;
    *)
        dump "ERROR: Unsupported NDK architecture: $ARCH"
        exit 1
        ;;
esac

# Install or Package
if [ -n "$INSTALL_DIR" ] ; then
    dump "Copying files to: $INSTALL_DIR"
    run copy_directory "$TMPDIR" "$INSTALL_DIR"
else
    PACKAGE_FILE="$PACKAGE_DIR/$TOOLCHAIN_NAME.tar.bz2"
    dump "Creating package file: $PACKAGE_FILE"
    pack_archive "$PACKAGE_FILE" "`dirname $TMPDIR`" "$TOOLCHAIN_NAME"
    fail_panic "Could not create tarball from $TMPDIR"
fi
dump "Cleaning up..."
run rm -rf $TMPDIR

dump "Done."
