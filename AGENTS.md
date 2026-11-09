# Engineering guide for agents

This file is the working contract for humans and coding agents contributing to
`ocarina-asahi-port`. The objective is bigger than making one screenshot look
better: build a clean, reproducible native Linux path from Switch 2 arm64 and
NVN2/NVIDIA programs to Vulkan, prove it on real hardware, and keep title data
out of the public source tree.

The `port/` and `mesa/` submodules have their own `AGENTS.md` files. Read and
obey the applicable nested file before changing either submodule. This root
file governs integration, release, testing and the direction shared by both.

## Non-negotiable project identity

- This is native execution, not a console or CPU emulator. The game's own
  AArch64 instructions execute on a Linux AArch64 CPU after bounded static NSO
  rewriting for host thread-pointer, syscall and platform differences.
- Do not introduce QEMU, Unicorn, Box64, an instruction interpreter, a guest
  CPU JIT, a Switch firmware image, or a guest kernel as the production path.
  A differential test tool may emulate a tiny isolated instruction sequence,
  but it must never become part of the shipped runtime.
- Do not reimplement the game. Preserve its code, data flow, renderer choices,
  timing and save format. Fix the compatibility boundary rather than replacing
  game systems with native lookalikes.
- Graphics are translated, not replaced: NVN2 command/state semantics become
  Vulkan commands and NVIDIA shader programs become validated SPIR-V.
- Task and mesh work must remain Vulkan task/mesh semantics. The runtime may
  target `VK_EXT_mesh_shader`; a Vulkan driver may lower that feature internally
  for hardware without native mesh instructions. Do not add a CPU renderer or
  silently replace mesh draws with unrelated ordinary draws.
- **Pure-code rule:** keep the implementation source-first and human-reviewable.
  Never add ROMs, NUPs, NSOs, RomFS
  files, extracted shaders, translated title SPIR-V, screenshots from the game,
  saves, pipeline caches, keys or other game-derived bytes.
- Do not add opaque binary-only functionality. A checked-in tool binary is
  acceptable only when its corresponding public source, licence, pinned digest
  and rebuild procedure are present and verified.
- Only use code whose licence permits the use. Preserve notices. The native
  task/mesh translator is a separate GPL-3.0-or-later combined work and stays
  outside the MIT port; invoke it as an external tool instead of copying it in.

## Repository boundaries

| Path | Responsibility |
|---|---|
| root | integration guide, launch configuration and pinned submodule revisions |
| `port/` | NSO rewrite, Linux host/services, NVN/NVN2 replay and shader tools |
| `mesa/` | Honeykrisp Vulkan driver and the experimental G13 mesh implementation |
| `config/` | small, reviewable, non-game-derived test configuration |
| `scripts/` | user-facing integration commands only |

Put a general mechanism in `port/` or `mesa/`, not in the root launcher. Put a
title fact in `port/dm/games/<title-id>/`. The root should pin a tested pair of
submodule commits and explain how to reproduce it.

Never edit or commit these generated trees:

```text
port/dm/linux/gen/
mesa/build*/
<game>_build/
translated shader directories
runtime saves and caches
```

## Supported baseline

The release gate is currently an Apple M1 Pro/G13S C0 with 32 GiB RAM running
Fedora Asahi Remix 44 on Linux/aarch64 and Wayland. The tracked title is
`0400486024DEC000`, update `v131072`. Other Apple generations and the BC-250 are
targets, not established working configurations.

Do not weaken a general implementation merely to match this machine. Keep
capabilities queried and paths selected by Vulkan/driver facts. Apple-specific
driver work belongs in Mesa; title-specific facts belong in the game profile.

## Initial setup

Clone everything and install the packages listed in the root README:

```sh
git clone --recurse-submodules https://github.com/biosed/ocarina-asahi-port.git
cd ocarina-asahi-port
```

The important toolchain requirements are:

- Clang, LLD, LLVM and GNU Make for the Linux host.
- SDL3, dav1d and Vulkan development packages.
- Meson/Ninja and Mesa's build dependencies for Honeykrisp.
- Python 3 with Capstone 5.x and zstd support for extraction/rewriting.
- .NET 10 for rebuilding the shader translator.
- SPIRV-Tools for `spirv-val`; glslang and `glslc` for shader fixtures.

Confirm Capstone before a rewrite:

```sh
python3 -c 'import capstone; assert capstone.cs_version()[0] == 5'
```

## Build

Build the Vulkan host from the merged port tree:

```sh
make -j"$(nproc)" -C port/dm/linux \
  GAME=0400486024DEC000 dmhost-vulkan
```

Expected result:

```text
port/dm/linux/gen/0400486024DEC000/dmhost-vulkan
```

It must be an AArch64 PIE executable. Check it with:

```sh
file port/dm/linux/gen/0400486024DEC000/dmhost-vulkan
```

Configure and build Honeykrisp with the exact options in `README.md`:

```sh
meson setup mesa/build-g13-mesh mesa \
  -Dplatforms=wayland \
  -Dvulkan-drivers=asahi \
  -Dgallium-drivers= \
  -Dbuild-tests=true \
  -Dwerror=true \
  -Dglx=disabled -Degl=disabled -Dgbm=disabled \
  -Dllvm=enabled
ninja -C mesa/build-g13-mesh
```

Do not install this experimental Mesa system-wide. Select its development ICD
with `VK_DRIVER_FILES`, as the root launcher does.

## Required tests

Run this fast integration set after every port/runtime change:

```sh
make -C port/dm/linux GAME=0400486024DEC000 \
  t_fs_linux t_vk_omap t_vk_mesh t_vk_shader_resolve \
  t_vk_descriptor_pool t_push t_skipcs t_gpstamp t_vk_stage
```

Every test must report `passed (0 failures)`.

For shader-chain, packaging or translator changes, also run:

```sh
python3 port/dm/gfx/tests/test_dmsh_spv_stage.py
python3 port/dm/gfx/tests/test_dmsh_spv_native.py
python3 port/dm/tools/tests/test_nsp_chain.py
python3 port/dm/tools/tests/test_xlate_anycpu.py
python3 port/dm/tools/tests/test_docs.py
```

The mesh-first fixture currently uses the port's legacy workspace-local
SPIRV-Tools lookup. On a fresh clone, point that lookup at the packaged
validator, then run it:

```sh
DMSH_FIXTURE_TOOLS="$(cd .. && pwd)/.deps/spirv-tools-cli-root/usr/bin"
mkdir -p "$DMSH_FIXTURE_TOOLS"
ln -sf "$(command -v spirv-val)" "$DMSH_FIXTURE_TOOLS/spirv-val"
python3 port/dm/gfx/tests/test_dmsh_spv_mesh_first.py
```

When a shader-chain input changes, regenerate
`port/dm/gfx/nvn/dmsh_chain.h`, rebuild affected shaders, validate every changed
module with `spirv-val --target-env vulkan1.3`, and invalidate only cache entries
whose shader bytes or ABI changed.

For Honeykrisp mesh work, build Mesa and run at minimum:

```sh
meson test -C mesa/build-g13-mesh --print-errorlogs \
  hk_mesh_emulation agx3-m5-mesh-program
```

Run the full Asahi suite before publishing a driver-wide change:

```sh
meson test -C mesa/build-g13-mesh --print-errorlogs --suite asahi
```

Finish every change with:

```sh
git diff --check
bash -n scripts/run-oot-asahi.sh
```

## Hardware/gameplay test discipline

- Never run the game unbounded on a busy machine. Use the README's cgroup
  limits (`MemoryHigh=12G`, `MemoryMax=15G`, `MemorySwapMax=2G`) and close
  memory-heavy applications first.
- Start with a short boot/title test, then save-load/Kokiri, then a longer area
  transition. A logo is not a gameplay pass.
- Record the exact port commit, Mesa commit, shader-chain ID, shader directory,
  driver ICD, environment differences, elapsed route and peak memory.
- Judge audio, input, presentation cadence and image together. “Sound with a
  black screen”, “HUD only”, or “one correct screenshot followed by a hang” is
  not playable.
- Compare screenshots only at deterministic route points. Keep screenshots and
  logs outside git.
- A workaround such as `DM_VK_SKIP_CS` must name exact shader keys, default off
  in generic code, be bounded by a test, and be documented as a workaround.
  Do not expand skip lists to hide a regression.
- Never call an experimental path conformant or hardware-accelerated without
  evidence. State whether work is native hardware, driver-lowered, or host-side.

## How to continue debugging

Work from the first wrong boundary, not the final black pixel:

1. Reproduce with a fixed route and preserve the first error, hang or wrong
   frame.
2. Decide whether the fault is module rewrite/host service, NVN command state,
   shader translation/reflection, descriptor binding, Vulkan synchronization,
   or the driver.
3. Reduce it to a title-independent invariant or a small device-free test.
4. Fix the producer of the wrong value. Avoid sleeps, arbitrary flushes,
   clamps, disabled draws and broad fallbacks.
5. Run the narrow tests, then the integration set, then the guarded hardware
   route.
6. Update the title note for a title fact and the general reference docs for a
   reusable mechanism. Include before/after measurements.

Useful first checks for this title:

- Audio with no picture: verify the ICD, shader-chain directory and native mesh
  directory before changing rendering code.
- Missing geometry: inspect task/mesh admission, stage ownership, descriptor
  layouts and indirect draw conversion.
- Dark/black occlusion: inspect attachment lifetime, depth/stencil state,
  render-target aliasing and raw-global-memory/image coherence.
- Wrong colours: trace format selection, output-map components, resolves,
  YUV/movie conversion and final presentation independently.
- Massive stalls: separate shader compilation, cgroup reclaim, driver time and
  guest CPU time; do not infer GPU slowness from wall time alone.
- OOM: measure guest reservation, bound images, caches and driver allocations;
  do not simply raise the limit until the desktop locks.

## The “make it awesome” quality bar

- Prefer one correct general rule over a title-specific exception.
- Make every failure loud, bounded and diagnosable. Include the shader key,
  stage, command, resource or guest address needed to reproduce it.
- Query capabilities; never infer them from GPU names alone.
- Keep ABI and cache keys explicit. A changed descriptor layout, shader chain,
  driver cache format or command record must change the corresponding version.
- Keep hot paths allocation-free where practical and measure CPU, GPU and
  memory separately.
- Make first-run compilation finite and visible; make later runs reuse only
  validated caches.
- Preserve deterministic builds: pin external sources and tool versions, and
  document the command that rebuilds each generated tool.
- Add a regression test for every bug with a stable isolated cause.
- Do not claim success above the evidence. “Boots”, “renders first scene”,
  “completes the route” and “playable” are different milestones.
- Leave the tree easier for the next contributor: clear names, short comments
  explaining *why*, no dead experiments, and updated public instructions.

## Direction: a generic Switch 2 NVIDIA-to-Vulkan layer

Ocarina is the proving title, not the desired architectural limit. General
work should converge on a reusable pipeline for Switch 2 NVN2 titles:

```text
owned NUP/dump
  -> verified extraction and title profile
  -> bounded AArch64 NSO rewrite
  -> native Linux host/services
  -> NVN2 command and resource model
  -> NVIDIA SM86 shader decode/translation
  -> validated canonical SPIR-V
  -> Vulkan 1.3 + explicit extensions
  -> conformant driver, or a clearly isolated driver lowering
```

The reusable boundary should be driven by observed NVN2/ISA/Vulkan semantics,
not `if title == Ocarina`. A new title should normally add a profile, shader
facts and tests—not a fork of the runtime.

Keep three layers separable:

1. **Native execution/host:** Linux AArch64 module loading, thread state,
   syscalls and SDK services, independent of the GPU vendor.
2. **NVN2-to-Vulkan:** command recording/replay, resources, synchronization,
   descriptor ABI and NVIDIA shader translation, targeting standard Vulkan.
3. **Driver adaptation:** Honeykrisp for Apple G13 today; RADV for BC-250 and
   conformant AMD/NVIDIA drivers later. Driver work must not leak title hacks
   back into the generic renderer.

Long-term portability gates should include at least Honeykrisp/Apple Silicon
and RADV/BC-250. Prefer Vulkan conformance and extensions already supported by
desktop drivers. Keep the Honeykrisp software-mesh implementation as an
explicit compatibility layer for Apple hardware, not as an assumption of the
generic NVN2 renderer.

## Git and release workflow

- Make changes in the repository that owns them. Push a `port/` or `mesa/`
  commit first, then update the root submodule pointer.
- Do not mix unrelated port, driver and documentation experiments in one
  commit.
- Before pushing the root, verify both submodule commits are reachable from
  their public remotes and `git diff --check` passes.
- A release handoff names the root commit, both submodule commits, shader-chain
  ID, tests run and actual hardware result.
- Keep all three repositories publicly cloneable. Never commit credentials or
  rely on private-only dependencies for the documented baseline.

## Agent message board

Agents working on this repo (Claude, Codex, Gemini, MiniMax, human) share a
local message board at `~/.agent-board`, driven by the `board` command. The
channel is the repo name, so every worktree and submodule posts to one board.

- Session start: `board new` shows unread messages addressed to you or all.
- Before stopping or handing off: `board post --tag done "what you did, what
  is unverified, next step"`, naming the commits involved.
- Ask another agent: `board post --to codex --tag request "..."`. Reply with
  `--tag done` or `--tag blocked`.
- `board read` shows recent history. Keep posts to a few lines; the board is
  for coordination, not a substitute for commits or docs.
