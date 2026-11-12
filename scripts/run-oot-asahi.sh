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
OOT_SAVE="${DM_SAVE:-$OOT_BUILD_DIR/runtime/save}"
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
# Opt-in only (=1 needs VK_EXT_zero_initialize_device_memory): its PROT_NONE
# fault-on-demand experiment cannot service kernel accesses to closed guest
# pages, so the title aborts at startup (Horizon 0xd401).
: "${DM_VK_GMEM_DEMAND_ZERO:=0}"
: "${DM_VK_BINDLESS_IMAGE_MB:=512}"
: "${DM_VK_BINDLESS_IMAGE_MAX_MB:=128}"
: "${DM_VK_BINDLESS_FEEDBACK:=0}"
# The replay records ahead of the GPU through a ring of command buffers, and a
# frame is about 14 of them. A ring of 2 made every part wait for an earlier
# part of the same frame: outdoors in Kokiri Forest 83.5 ms a frame; 8 gave
# 64.2 ms and 16 gives 58.5 ms, all at the same 12.3 GiB memory peak
# (2026-11-10, M1 Pro; mesa 71ce0ae7 pools the mesh scratch).
: "${DM_VK_CB_RING:=16}"
: "${DM_VK_ROBUST:=1}"
: "${DM_VK_PRECOMPILE:=0}"
: "${DM_VK_GPU_HEARTBEAT:=1}"
: "${DM_VK_OPS:=1}"
: "${DM_VK_MESH_LOG:=0}"
: "${DM_VK_SHADER_COMPILE_LOG:=0}"
: "${DM_WINDOW:=1}"
: "${DM_AUDIO:=1}"
: "${DM_FOCUS_KEEP:=1}"
: "${DM_MOVIES:=all}"
: "${DM_MOVIE_ENHANCE:=0}"
: "${DM_CODEC_ACQUIRE_RESERVES:=1}"
: "${DM_CODEC_MOVIE_B2T_LATEST:=1}"
: "${DM_HUD:=0}"
# Graphics scale tier answered to the game (port hle_oe.c: 0 full size, 1 = 0.8, 2 = 0.67 of
# the docked render size; the game's own upscaler still produces the full picture). The port's
# default is tier 0; on the M1 Pro baseline that costs about 2.4 ms a frame, so this launcher
# answers tier 1 (outdoor Kokiri, frozen save, port 6f6de38 + Mesa 059a613, 2026-11-12: tier 0
# 40.7 ms/frame and 37.2 ms GPU, tier 1 38.3 / 35.0). Set DM_GFX_SCALE=0 for the full-size picture.
: "${DM_GFX_SCALE:=1}"
# Preserve the game's NDSR network unless the player explicitly chooses the
# faster, visibly softer bilinear replacement. probe logs stages but preserves
# the network (port vk_upscaler.h).
: "${DM_UPSCALER:=game}"

case "$DM_UPSCALER" in
    game|linear|probe) ;;
    *)
        echo "error: DM_UPSCALER must be game, linear or probe (got: $DM_UPSCALER)" >&2
        exit 2
        ;;
esac

case "$DM_HUD" in
    0)
        OOT_HUD_STATUS="off (set DM_HUD=1 to enable)"
        ;;
    1)
        if ! command -v mangohud >/dev/null 2>&1; then
            echo "error: DM_HUD=1 requires MangoHud (Fedora: sudo dnf install mangohud)" >&2
            exit 1
        fi
        MANGOHUD=1
        if [[ -z ${MANGOHUD_CONFIG+x} && -z ${MANGOHUD_CONFIGFILE+x} ]]; then
            # MangoHud does not sample Asahi GPU utilisation yet. Show the
            # Vulkan GPU/driver identity without inventing a load figure.
            MANGOHUD_CONFIG="fps,frametime,gpu_name,vulkan_driver,gpu_stats=0,cpu_stats=0,frame_timing=0,throttling_status=0,position=top-left,toggle_hud=Shift_R+F12"
        fi
        export MANGOHUD MANGOHUD_CONFIG
        OOT_HUD_STATUS="MangoHud (Right Shift+F12 toggles visibility)"
        ;;
    *)
        echo "error: DM_HUD must be 0 or 1 (got: $DM_HUD)" >&2
        exit 2
        ;;
esac

# Run the translated NDVE/NDSR chain by default. DM_VK_SKIP_CS remains an
# explicit exact-key diagnostic; setting it deliberately makes the rendered
# chain incomplete and never substitutes another image operation.
: "${DM_VK_SKIP_CS:=}"

export \
    VK_DRIVER_FILES NIR_DEBUG ASAHI_G13_SOFTWARE_MESH \
    DM_VK_MESH_TITLE_PROFILE DM_VK_MESH_PROOF DM_VK_GMEM_TRACE DM_VK_GMEM_DEMAND_ZERO \
    DM_VK_BINDLESS_IMAGE_MB DM_VK_BINDLESS_IMAGE_MAX_MB \
    DM_VK_BINDLESS_FEEDBACK DM_VK_CB_RING DM_VK_ROBUST \
    DM_VK_PRECOMPILE DM_VK_GPU_HEARTBEAT DM_VK_OPS DM_VK_MESH_LOG \
    DM_VK_SHADER_COMPILE_LOG DM_WINDOW DM_AUDIO DM_FOCUS_KEEP DM_MOVIES DM_MOVIE_ENHANCE \
    DM_CODEC_ACQUIRE_RESERVES DM_CODEC_MOVIE_B2T_LATEST DM_VK_SKIP_CS DM_GFX_SCALE \
    DM_UPSCALER

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
echo "HUD:         $OOT_HUD_STATUS"
echo "gfx tier:    $DM_GFX_SCALE (0 full size, 1 = 0.8, 2 = 0.67; DM_GFX_SCALE)"
echo "upscaler:    $DM_UPSCALER (game preserves NDSR; linear is faster/softer; probe logs)"

exec "$OOT_HOST" "$OOT_MODULES"
