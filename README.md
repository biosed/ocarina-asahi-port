# Ocarina of Time on Asahi Linux

Experimental native Linux/aarch64 port of *The Legend of Zelda: Ocarina of
Time* for Switch 2 (title `0400486024DEC000`, update `v131072`). The game's own
arm64 code runs directly; NVN2 commands and shaders are translated to Vulkan
for Mesa's Honeykrisp driver.

This is a research milestone, not a finished playable release. On the tested
M1 Pro it boots through the logo, title/loading screens and save selection into
live Kokiri Forest with audio, input, Link, Navi, terrain and HUD visible. The
picture still has large dark/black occlusion, missing or incorrect geometry,
wrong lighting/colour and heavy frame times. Area transitions can hang or run
out of memory.

## Known-good baseline

| Item | Tested value |
|---|---|
| Machine | Apple M1 Pro, 10 CPU cores, G13S C0 GPU, 32 GiB unified memory |
| OS | Fedora Asahi Remix 44, Linux aarch64, Wayland |
| Kernel | `7.2.12-402.asahi.fc44.aarch64+16k` |
| Game | title `0400486024DEC000`, update `v131072` |
| Port | `port/` commit `35f233be` |
| Driver | `mesa/` commit `3be2825e` |
| Standard shader chain | `60f00ba3b166` |
| Current performance | about 33–50 ms per rendered frame in the tested first scene |
| Current memory | about 12–13 GiB for the game process; a 32 GiB host is strongly recommended |

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
  libdrm-devel wayland-devel glslang spirv-tools
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

The launcher enables the exact experimental G13 mesh proof, the learned
guest-memory coherence profile and the bounded compute-skip list used in the
latest test. The skip list deliberately omits unsafe compute effects and is one
reason this is not a correctness baseline. Override an environment variable
before launching only when testing a specific change.

## Expected problems

- **Audio but a black/dark picture:** first confirm the selected ICD says
  Honeykrisp, the shader chain is `60f00ba3b166`, and the log says mesh shading
  is on. A large dark occlusion in Kokiri Forest is still a known renderer bug.
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
fragment output-map and partial-colour-target depth fixes are included; all 40
affected depth shaders validated, but that correction did not remove the
remaining dark scene occlusion.

Still open: render-target/coherence correctness, missing geometry, lighting
and colour, meshlet coverage, dynamic-resolution cost, pipeline stalls, memory
growth and later-area stability. “It boots” is established; “it is comfortably
playable” is not.

## Licences

The port submodule retains its MIT licence and upstream notices. Mesa retains
its own licences. The external native task/mesh translator pinned above is a
GPL-3.0-or-later combined work and must remain separately sourced and licensed.
No licence in this project grants rights to game content.

This project is independent and unaffiliated with Nintendo, the game's
developers, Mesa or the Asahi Linux project.
