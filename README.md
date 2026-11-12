# Ocarina of Time on Asahi Linux

Experimental native Linux/aarch64 port of *The Legend of Zelda: Ocarina of
Time* for Switch 2 (title `0400486024DEC000`, update `v131072`). The game's own
arm64 code runs directly; NVN2 commands and shaders are translated to Vulkan
for Mesa's Honeykrisp driver.

This is a research milestone, not a finished playable release. On the tested
M1 Pro it boots through the logo, title/loading screens and save selection into
live Kokiri Forest with audio, input, Link, Navi, terrain and HUD visible. The
tested outdoor save is correctly lit, but frame times remain heavy. The full
canonical mesh set still reclaim-livelocks above the 12 GiB soft limit during
the Kokiri load; later area transitions remain unvalidated.

## Known-good baseline

| Item | Tested value |
|---|---|
| Machine | Apple M1 Pro, 10 CPU cores, G13S C0 GPU, 32 GiB unified memory |
| OS | Fedora Asahi Remix 44, Linux aarch64, Wayland |
| Kernel | `7.2.12-402.asahi.fc44.aarch64+16k` |
| Game | title `0400486024DEC000`, update `v131072` |
| Port | `port/` commit `7612f6d8c939` |
| Driver | `mesa/` commit `059a6139be70` |
| Standard shader chain | `8b975cd27f6e` |
| Current performance | title and the first 85 seconds of the New Game WebM: 16.66 ms/frame and about 11.0--11.2 ms GPU; outdoor Kokiri frozen save at the launcher's tier 1: 38.3/35.0 ms with the game network, 33.7/31.0 ms with the near-network-quality opt-in FSR 1 scaler, or 33.8/30.2 ms with the softer opt-in linear scaler; full-size tier 0 is 40.7/37.2 ms |
| Current memory | story-movie route: 9.75 GB cgroup peak with no swap or limit event; later in-engine opening: 12.89 GB peak and 100 MB swap under the 12/15/2 GB limits; a 32 GiB host is strongly recommended |

These revisions collect separately validated milestones. The port propagates
the direct draw base instance into translated shader state, restoring split
dialogue glyph batches in a guarded matched-chain A/B, and reuses descriptor
sets only after their replay-ring fence has passed. The driver enables the
validated G13 local load/store control bit by default; its full Asahi suite
passes 122/122.

The exact combined revisions completed guarded title and opening routes. The
2560x1440 title background movie visibly advanced between captures, the menu
text and button label rendered, both scripted A presses landed, and the later
in-engine opening rendered subtitles. A second 130-second route enabled every
movie and played the first 85 seconds of the separate New Game WebM, from its
tapestry sequence through Link asleep. Its frame median stayed at 16.66 ms with
about 11.0--11.2 ms GPU, audio reported no underruns, and the cgroup used no
swap. The later in-engine scene remained about 30--35 ms per frame. This proves
title and sustained story video, input and opening presentation on the pinned
pair, not all eight minutes of the story movie, movement, an area transition or
smooth gameplay.

Matched 300-second frozen-save arms on the same host, driver, shader sets and
scripted route measured 40.73 ms/frame and 37.19 ms GPU at the full-size tier 0 (the port default),
and 38.30/35.02 ms at tier 1. Both used the compact compute timers only after
frame 6,000, produced zero audio underruns, stayed below 11.21 GB without swap,
and had no kernel GPU timeout. Tier 1 is therefore only a modest performance
option, not a route to 60 fps; gameplay remains GPU-bound and not yet smooth.

The pinned port supplies two opt-in Vulkan replacements for the title's
tensor-oriented NDSR reconstruction stage. `DM_UPSCALER=fsr1` builds AMD FSR 1
EASU and RCAS from pinned MIT source; its matched tier-1 arm measured 34.69
ms/frame and 31.03 ms GPU (p95 39.44/35.78) while retaining foliage and thin
edges close to the game network. `DM_UPSCALER=linear` measured 33.76/30.24 ms
(p95 39.17/35.50), but is visibly softer and aliases thin edges. The game
network measured 38.30/35.02 ms (p95 43.77/39.97). All three arms rendered the
complete picture; the replacement arms reported zero audio underruns and no GPU
timeout. The launcher keeps `game` as the default: both replacements change the
look, and neither result proves a stable 30 fps floor or smooth gameplay.

The current port pin removes steady-state descriptor-pool resets and per-cache-
miss descriptor-set allocation. In a matched FSR 1 tier-1 A/B, replay CPU
p50/p95/p99 fell from 17.44/18.96/19.69 ms to 15.34/16.81/17.49 ms. Delivered
frame p50/p95/p99 improved from 34.02/36.02/36.92 ms to
33.68/35.36/36.26 ms, and the share at or below 33.33 ms rose from 25.5% to
35.9%. Both 300-second arms had complete UI text and gameplay captures, zero
audio underruns and no GPU timeout. This is a measured CPU-side improvement,
not evidence of a stable 30 fps floor; the remaining limit is about 31 ms of
GPU work in this scene.

M2/M3/M4 Linux systems have not been validated. This is not a macOS build. A
BC-250/AMD target is planned, but the current Honeykrisp software-mesh path is
Apple-GPU-specific; BC-250 will need a separate RADV/AMD bring-up and its own
validation.

## Repository layout

Clone all submodules:

```sh
git clone --recurse-submodules https://github.com/biosed/ocarina-asahi-port.git
cd ocarina-asahi-port
```

This repository and both required submodules are public; no GitHub account or
private token is needed to clone them.

| Path | Contents |
|---|---|
| `port/` | merged Linux host, NVN/NVN2 replay, shader tools and title profile |
| `mesa/` | Honeykrisp fork with the experimental G13 software task/mesh path |
| `config/` | tested keyboard map and bounded guest-memory coherence profile |
| `scripts/run-oot-asahi.sh` | repeatable launcher for already prepared game files |

No game-derived material is included: no NUP, executable modules, RomFS,
shaders, saves, keys, screenshots or pipeline cache. Supply your own legally
obtained game dump. The NUP used by this project is not encrypted, so this path
uses no console keys or decryption step.

## 1. Install dependencies

These Fedora 44 package names cover the host, driver, extraction, rewrite,
translation and validation steps:

```sh
sudo dnf install \
  git make clang lld llvm pkgconf-pkg-config \
  SDL3-devel vulkan-loader-devel vulkan-headers vulkan-tools libdav1d-devel \
  python3 python3-capstone python3-zstandard \
  dotnet-sdk-10.0 \
  meson ninja-build gcc gcc-c++ \
  python3-mako python3-pyyaml python3-packaging \
  libdrm-devel wayland-devel glslang glslc spirv-tools mangohud
```

The NSO rewriter requires Capstone 5.x, not Capstone 6. Verify it:

```sh
python3 -c 'import capstone; assert capstone.cs_version()[0] == 5; print(capstone.__version__)'
dotnet --list-sdks
spirv-val --version
```

If the system Capstone is not version 5, create a virtual environment and use
its Python for every Python command below:

```sh
python3 -m venv .venv
.venv/bin/pip install 'capstone>=5,<6' 'backports.zstd; python_version < "3.14"'
```

Python 3.14 already supplies `compression.zstd`; older Python versions need
`backports.zstd` to read compressed NUP entries.

## 2. Build the Honeykrisp driver

Build the checked-out driver in place. The options below are the ones used for
the validated M1 Pro build:

```sh
meson setup mesa/build-g13-mesh mesa \
  -Dplatforms=wayland \
  -Dvulkan-drivers=asahi \
  -Dgallium-drivers= \
  -Dbuild-tests=true \
  -Dwerror=true \
  -Dglx=disabled \
  -Degl=disabled \
  -Dgbm=disabled \
  -Dllvm=enabled
ninja -C mesa/build-g13-mesh
```

The development ICD is then:

```text
mesa/build-g13-mesh/src/asahi/vulkan/asahi_devenv_icd.aarch64.json
```

Confirm that it selects Honeykrisp rather than llvmpipe:

```sh
VK_DRIVER_FILES="$PWD/mesa/build-g13-mesh/src/asahi/vulkan/asahi_devenv_icd.aarch64.json" \
  vulkaninfo --summary
```

The device name should be the Apple GPU and the driver name should be
`Honeykrisp`.

## 3. Build and test the Linux host

The host build does not need game files:

```sh
make -j"$(nproc)" -C port/dm/linux GAME=0400486024DEC000 dmhost-vulkan
```

The executable is:

```text
port/dm/linux/gen/0400486024DEC000/dmhost-vulkan
```

Run the device-free integration tests:

```sh
make -C port/dm/linux GAME=0400486024DEC000 \
  t_fs_linux t_vk_omap t_vk_mesh t_vk_shader_resolve \
  t_vk_descriptor_pool t_push t_skipcs t_gpstamp t_vk_stage
```

## 4. Prepare your own NUP

Allow at least 70 GiB free while retaining the original NUP. The tested NUP is
25.6 GiB and its current derived build directory is about 34 GiB: 25 GiB of
extraction, 102 MiB of rewritten modules and roughly 9 GiB of shader outputs
and caches.

Set two paths for the remaining commands:

```sh
OOT_NUP=/absolute/path/to/your/game.nup
OOT_BUILD=/absolute/path/to/0400486024DEC000_build
```

### Extract

```sh
python3 port/scripts/pack_nup.py "$OOT_NUP" --work-dir "$OOT_BUILD"
```

Expected inputs after extraction:

```text
$OOT_BUILD/extract/v131072/ExeFS/main
$OOT_BUILD/extract/v131072/ExeFS/subsdk0
$OOT_BUILD/extract/v131072/ExeFS/sdk
$OOT_BUILD/extract/v131072/RomFS.img
```

Stop if the selected version is not `v131072`; the tracked profile and tested
module layout are for that update.

### Rewrite the three arm64 modules for Linux

```sh
mkdir -p "$OOT_BUILD/patched_linux_v131072"
for OOT_MODULE in main subsdk0 sdk; do
  DM_PATCH_TP=linux DM_GAME=0400486024DEC000 \
    python3 port/dm/tools/patch_nso.py \
      "$OOT_BUILD/extract/v131072/ExeFS/$OOT_MODULE" \
      "$OOT_BUILD/patched_linux_v131072" \
      "$OOT_MODULE"
done
```

The launcher expects `main.patched.bin`, `subsdk0.patched.bin` and
`sdk.patched.bin` in that directory. Rewriting can use several GiB of RAM.

### Extract the NVN2 shader package

This scans the 25 GiB RomFS image and can take a while:

```sh
mkdir -p "$OOT_BUILD/shaders/pkg"
DM_GAME=0400486024DEC000 J="$(nproc)" \
  python3 port/dm/gfx/tools/shader_split.py \
    "$OOT_BUILD/extract/v131072/RomFS.img" \
    "$OOT_BUILD/extract/v131072/ExeFS/main" \
    "$OOT_BUILD/shaders/pkg" \
    "$OOT_BUILD/shaders/shader_map.tsv" \
    "$OOT_BUILD/shaders/shader_facts.tsv" \
    "$OOT_BUILD/shaders/shader_pairs.tsv" \
    "$OOT_BUILD/shaders/pso_pairs.tsv"
```

For this update the final summary should report 42,848 shaders: 4,125 compute,
500 mesh, 22,352 pixel, 20 task and 15,851 vertex.

### Build the separately licensed native task/mesh translator

Ordinary vertex/pixel/compute translation is in `port/`. The current game also
needs native Vulkan TaskEXT/MeshEXT modules. Their validated translator is a
GPL-3.0-or-later combined work from BananaNative commit `96cc0e88`; it is kept
outside this MIT port deliberately.

```sh
DONOR_DIR="$PWD/.external/BananaNative"
git clone https://github.com/moceure/BananaNative.git "$DONOR_DIR"
git -C "$DONOR_DIR" checkout 96cc0e883c80117e51342c60facfae2f0e600b9a
dotnet publish \
  "$DONOR_DIR/dm/gfx/tools/dmsh_xlate/dmsh_xlate.csproj" \
  -c Release -r linux-arm64 --self-contained false \
  -o "$DONOR_DIR/build/dmsh-xlate"
dotnet "$DONOR_DIR/build/dmsh-xlate/dmsh_xlate.dll" --source-sha
```

The last command must print `0f31637014ce4725`. The port rejects any other
source digest instead of silently accepting an incompatible translator.

### Translate shaders to Vulkan SPIR-V

```sh
DM_GAME=0400486024DEC000 \
DMSH_VK_MESH_XLATE="$DONOR_DIR/build/dmsh-xlate/dmsh_xlate.dll" \
DMSH_VK_MESH_MAP="$OOT_BUILD/shaders/shader_map.tsv" \
DMSH_VK_MESH_FACTS="$OOT_BUILD/shaders/shader_facts.tsv" \
DMSH_VK_MESH_ALLOW_FAILURES=1 \
SPIRV_VAL="$(command -v spirv-val)" \
J="$(nproc)" \
  python3 port/dm/gfx/tools/dmsh_spv.py \
    "$OOT_BUILD/shaders/pkg" \
    "$OOT_BUILD/shaders/vulkan"
```

This is the longest CPU stage when translating the full title. It validates
each native task/mesh output for Vulkan 1.3 and writes the usable modules under:

```text
$OOT_BUILD/shaders/vulkan/spv-60f00ba3b166/
```

Some title shaders are still unsupported. `DMSH_VK_MESH_ALLOW_FAILURES=1`
retains validated successes and records exact failures; it does not weaken
validation. Do not copy shader output from another game version.

## 5. Run the current baseline

Create writable runtime directories:

```sh
mkdir -p "$OOT_BUILD/runtime/save" "$OOT_BUILD/runtime/temp"
```

Launch under a memory guard. Passing the same SPIR-V directory twice is
intentional when the standard and native task/mesh modules came from the
combined command above:

```sh
OOT_SPV="$OOT_BUILD/shaders/vulkan/spv-60f00ba3b166"
systemd-run --user --scope --collect \
  -p MemoryHigh=12G \
  -p MemoryMax=15G \
  -p MemorySwapMax=2G \
  ./scripts/run-oot-asahi.sh "$OOT_BUILD" "$OOT_SPV" "$OOT_SPV"
```

The launcher answers the game's graphics scale tier 1 by default (an 80% render
size before the game's own upscaler): on the M1 Pro with the pinned pair it is
about 2.4 ms a frame faster than the full-size tier 0 (38.3 against 40.7 ms in
the outdoor Kokiri frozen-save route). Set `DM_GFX_SCALE=0` for the full-size
picture or `2` for a smaller, softer render size.

Press F1 (or Minus + Plus together on a controller) for the port's small
in-game menu. Its upscaler choice applies immediately; its graphics-tier choice
applies on the next launch. The launcher reads those saved choices from
`${XDG_CONFIG_HOME:-$HOME/.config}/nxnative-asahi/settings.conf` (or
`DM_SETTINGS`) without evaluating it as shell code. An explicitly supplied
`DM_GFX_SCALE` or `DM_UPSCALER` overrides the corresponding saved choice.

`DM_UPSCALER=fsr1` replaces the game's expensive NDSR reconstruction
stage with source-built AMD FSR 1 EASU and RCAS. It saved about 3.6 ms/frame in
the matched tier-1 outdoor route while keeping detail close to the network;
`DM_UPSCALER_SHARPNESS=0.25` is the tested RCAS reduction in stops (the port
accepts 0 through 8). `DM_UPSCALER=linear` saved about 4.5 ms/frame but is
visibly softer. FSR 1 is the launcher default (chosen by the player after an
in-game comparison; on the exact frame route at tier 1 it measured 35.52/32.12
ms frame/GPU against 38.36/34.91 for the network). `DM_UPSCALER=game` (or the F1
menu) keeps the title's network; `probe` preserves it while logging stage
shapes and formats.

The launcher enables a compact MangoHud FPS, frametime, GPU-name and
Vulkan-driver overlay by default; Right Shift+F12 toggles it and `DM_HUD=0`
disables it for captures or controlled measurements. MangoHud cannot currently
sample Asahi GPU utilisation, so this launcher does not display a fake load.

If standard and native mesh shaders were prepared into separate directories,
pass the native mesh directory as the third argument instead.

Controls in the supplied map:

| Input | Key |
|---|---|
| A / confirm | Return |
| B / back | Escape |
| Left stick and menu directions | Arrow keys |
| L / R | Q / E |
| ZL / ZR | Z / C |
| Plus / Minus | P / Tab |

SDL gamepads are also mapped and are preferable for gameplay.

The launcher enables the exact experimental G13 mesh proof and the learned
guest-memory coherence profile. It explicitly zeroes closed pages in placed
guest-memory chunks. `DM_VK_GMEM_DEMAND_ZERO=1` remains diagnostic-only: its
`PROT_NONE` fault-on-demand experiment cannot service kernel accesses to closed
guest pages, which corrupts the title's allocator state and aborts startup. It
does not skip arbitrary compute shaders.
On the M1 Pro baseline it defaults `DM_MOVIE_ENHANCE=0`: the movie library's
expensive clean-up network is replaced by a checked copy of the decoded frame,
while colour conversion and scaling still run. Set `DM_MOVIE_ENHANCE=1` to run
the full network. The generic runtime keeps enhancement on unless this switch
is explicitly set.
Movies themselves default to `DM_MOVIES=all`. Set `DM_MOVIES=opening` only for
a short development route that retains the title movies but hides the
eight-minute New Game WebM, or `DM_MOVIES=off` to hide every WebM.

## Expected problems

- **Audio but a black/dark picture:** first confirm the selected ICD says
  Honeykrisp, the shader directories use the expected current chain, and the
  log says mesh shading is on.
- **Logo/title works, gameplay is missing geometry:** the native task/mesh
  translator or `DMSH_VK_MESH_EXT_DIR` is missing, stale or from the wrong
  profile.
- **`ModuleNotFoundError: capstone`:** install `python3-capstone` or use the
  Capstone-5 virtual environment described above.
- **`glslangValidator` missing during Meson setup:** install Fedora's
  `glslang` package.
- **The desktop becomes unresponsive:** stop the scope, close memory-heavy
  applications and let swap drain before retrying. Do not remove the cgroup
  guard on a busy system.
- **First-area stalls:** shader-object compilation and the current software
  mesh path are expensive. A cache helps later starts but does not make the
  current renderer correct or fast.

## What is complete and what is not

The merged `asahi` port builds a complete Linux Vulkan host from one tree. Its
filesystem, audio/video, thread-slot and renderer self-tests pass, and the
exact merged executable has reached live Kokiri gameplay on the M1 Pro. The
fragment output-map and partial-colour-target depth fixes are included, and all
40 affected depth shaders validated.

Still open: render-target/coherence edge cases, missing geometry, meshlet
coverage, dynamic-resolution cost, pipeline stalls, the full-set memory
plateau and later-area stability. “It boots” and renders the tested outdoor
save; “it is comfortably playable” is not.

## Broader direction

Ocarina is the proving title for a more general native Linux stack: bounded
Switch 2 AArch64 module rewriting, Linux host services, reusable NVN2 command
replay, NVIDIA SM86 shader translation to validated SPIR-V, and a Vulkan 1.3
backend. This is deliberately not a CPU or console emulator—the title's own
arm64 code runs natively.

The long-term renderer should be title-independent and driver-independent.
Honeykrisp supplies the current Apple G13 path; RADV/BC-250 and conformant
desktop Vulkan drivers are the next portability targets. Title-specific facts
belong in profiles, while NVN2, shader and synchronization fixes belong in the
shared implementation. See [`AGENTS.md`](AGENTS.md) for the engineering rules,
test matrix and continuation workflow.

## Licences

The port submodule retains its MIT licence and upstream notices. Mesa retains
its own licences. The external native task/mesh translator pinned above is a
GPL-3.0-or-later combined work and must remain separately sourced and licensed.
No licence in this project grants rights to game content.

This project is independent and unaffiliated with Nintendo, the game's
developers, Mesa or the Asahi Linux project.
