#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "usage: $0 <0400486024DEC000_build> <standard-spv-dir> [native-mesh-spv-dir]" >&2
    exit 2
fi

OOT_REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
OOT_BUILD_DIR=$1
OOT_STANDARD_SPV=$2
OOT_NATIVE_SPV=${3:-$2}
OOT_TITLE=0400486024DEC000
OOT_VERSION=v131072

if [[ $(uname -m) != aarch64 ]]; then
    echo "error: this launcher executes the game's arm64 code and requires Linux/aarch64" >&2
    exit 1
fi

OOT_HOST="$OOT_REPO_ROOT/port/dm/linux/gen/$OOT_TITLE/dmhost-vulkan"
OOT_ICD_DEFAULT="$OOT_REPO_ROOT/mesa/build-g13-mesh/src/asahi/vulkan/asahi_devenv_icd.aarch64.json"
OOT_MODULES="$OOT_BUILD_DIR/patched_linux_$OOT_VERSION"
OOT_ROMFS="$OOT_BUILD_DIR/extract/$OOT_VERSION/RomFS.img"
OOT_SHADER_MAP="$OOT_BUILD_DIR/shaders/shader_map.tsv"
OOT_SAVE="$OOT_BUILD_DIR/runtime/save"
OOT_TEMP="$OOT_BUILD_DIR/runtime/temp"
OOT_CACHE="$OOT_BUILD_DIR/runtime/vkcache-g13"

OOT_REQUIRED=(
    "$OOT_HOST"
    "${VK_DRIVER_FILES:-$OOT_ICD_DEFAULT}"
    "$OOT_MODULES/main.patched.bin"
    "$OOT_MODULES/subsdk0.patched.bin"
    "$OOT_MODULES/sdk.patched.bin"
    "$OOT_ROMFS"
    "$OOT_SHADER_MAP"
    "$OOT_STANDARD_SPV"
    "$OOT_NATIVE_SPV"
    "$OOT_REPO_ROOT/config/oot-v131072-gmem32.profile"
    "$OOT_REPO_ROOT/config/oot-keyboard.map"
)

for OOT_PATH in "${OOT_REQUIRED[@]}"; do
    if [[ ! -e $OOT_PATH ]]; then
        echo "error: required path does not exist: $OOT_PATH" >&2
        exit 1
    fi
done

mkdir -p "$OOT_SAVE" "$OOT_TEMP" "$OOT_CACHE"

: "${VK_DRIVER_FILES:=$OOT_ICD_DEFAULT}"
: "${NIR_DEBUG:=novalidate}"
: "${ASAHI_G13_SOFTWARE_MESH:=1}"
: "${DM_VK_MESH_TITLE_PROFILE:=1}"
: "${DM_VK_MESH_PROOF:=root-physical-proof}"
: "${DM_VK_GMEM_TRACE:=1}"
: "${DM_VK_BINDLESS_IMAGE_MB:=512}"
: "${DM_VK_BINDLESS_IMAGE_MAX_MB:=128}"
: "${DM_VK_BINDLESS_FEEDBACK:=0}"
: "${DM_VK_CB_RING:=2}"
: "${DM_VK_ROBUST:=1}"
: "${DM_VK_PRECOMPILE:=0}"
: "${DM_VK_GPU_HEARTBEAT:=1}"
: "${DM_VK_OPS:=1}"
: "${DM_VK_MESH_LOG:=0}"
: "${DM_VK_SHADER_COMPILE_LOG:=0}"
: "${DM_WINDOW:=1}"
: "${DM_AUDIO:=1}"
: "${DM_FOCUS_KEEP:=1}"
: "${DM_MOVIES:=opening}"
: "${DM_CODEC_ACQUIRE_RESERVES:=1}"
: "${DM_CODEC_MOVIE_B2T_LATEST:=1}"

# Exact bounded workaround used by the latest M1 Pro visual run. These compute
# programs are skipped deliberately; unset DM_VK_SKIP_CS only for a controlled
# renderer test, not as an assumed improvement.
: "${DM_VK_SKIP_CS:=d15370a382630d4e,e6be82d835fbe4d3,9442573ee4ace011,0a56002cdc7e1fce,a8b4fb48fee0ccf8,ba079f68ae288dba,e2eebd7ba18fe35f,7f7ff0f36b54d90f,5a7d69b067a7f011,4f41ccf24f163e0d,f8965bffbdf51d78,d17eefaff4f0bc23,a335c1db6270c355,fa3033d05c0a41d6,d99fbeeb53d38847}"

export \
    VK_DRIVER_FILES NIR_DEBUG ASAHI_G13_SOFTWARE_MESH \
    DM_VK_MESH_TITLE_PROFILE DM_VK_MESH_PROOF DM_VK_GMEM_TRACE \
    DM_VK_BINDLESS_IMAGE_MB DM_VK_BINDLESS_IMAGE_MAX_MB \
    DM_VK_BINDLESS_FEEDBACK DM_VK_CB_RING DM_VK_ROBUST \
    DM_VK_PRECOMPILE DM_VK_GPU_HEARTBEAT DM_VK_OPS DM_VK_MESH_LOG \
    DM_VK_SHADER_COMPILE_LOG DM_WINDOW DM_AUDIO DM_FOCUS_KEEP DM_MOVIES \
    DM_CODEC_ACQUIRE_RESERVES DM_CODEC_MOVIE_B2T_LATEST DM_VK_SKIP_CS

export DM_ROOT="$OOT_BUILD_DIR"
export DM_ROMFS="$OOT_ROMFS"
export DM_SAVE="$OOT_SAVE"
export DM_TEMP="$OOT_TEMP"
export DM_NVN_SHMAP="$OOT_SHADER_MAP"
export DM_VK_SPV="$OOT_STANDARD_SPV"
export DMSH_VK_MESH_EXT_DIR="$OOT_NATIVE_SPV"
export DM_VK_SHCACHE="$OOT_CACHE"
export DM_VK_GMEM_PROFILE="$OOT_REPO_ROOT/config/oot-v131072-gmem32.profile"
export DM_INPUT_MAP="$OOT_REPO_ROOT/config/oot-keyboard.map"
export DM_VK_MISSING_LOG="$OOT_TEMP/missing-shaders.log"

echo "host:        $OOT_HOST"
echo "ICD:         $VK_DRIVER_FILES"
echo "game build:  $OOT_BUILD_DIR"
echo "SPIR-V:      $DM_VK_SPV"
echo "native mesh: $DMSH_VK_MESH_EXT_DIR"
echo "save:        $DM_SAVE"

exec "$OOT_HOST" "$OOT_MODULES"
