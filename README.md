# ocarina-asahi-port

**One clone of this repository gets you the whole port.** It is the working repository
for *The Legend of Zelda: Ocarina of Time* (Switch 2 release, title `0400486024DEC000`,
update v131072) running natively on an **Apple M1 Pro under Asahi Linux on aarch64** —
the game's own arm64 code, executed directly, with its NVN graphics commands replayed
through Vulkan and Mesa's Honeykrisp driver.

```
git clone --recurse-submodules https://github.com/biosed/ocarina-asahi-port.git
cd ocarina-asahi-port
```

> **This repository and both of its submodule upstreams are private** (they were public
> until 9 November 2026, and are now invite-only). You need collaborator access, and
> `--recurse-submodules` needs credentials that can read the two submodules too —
> `gh auth setup-git` with an invited account, or a token with `repo` scope.

That gives you two working trees and this guide:

| path | what it is |
|---|---|
| `port/` | the port itself — the runtime, the renderer, the Linux platform layer (a submodule of [biosed/nxnative-asahi](https://github.com/biosed/nxnative-asahi), branch `asahi`) |
| `mesa/` | the driver — the Honeykrisp G13 fork with the software `VK_EXT_mesh_shader` path (a submodule of [biosed/mesa-honeykrisp-mesh](https://github.com/biosed/mesa-honeykrisp-mesh), branch `g13-mesh-ext`) |

The decisions, audits and measurements behind all of this live in the companion
[audit record](https://github.com/biosed/ocarina-asahi) — the `ACK-*.md` audits, the
`reports/` write-ups and the `scripts/` analysers.

---

## How to get where we are now

### 1. Build — and do it without the game

The renderer builds from the tracked game profile alone. **No game content is needed
for this step**, which is the quickest way to confirm your toolchain works:

```sh
make -C port/dm/linux GAME=0400486024DEC000 null-renderer
```

That produces `port/dm/linux/gen/0400486024DEC000/libdm-renderer-null.a`, a
relocatable renderer archive with the host/runtime integration seam left undefined.
Nothing game-derived is involved.

The device-free self-tests do not need a GPU or a game either:

```sh
make -C port/dm/linux GAME=0400486024DEC000 t_vk_mesh t_push t_skipcs t_gpstamp t_vk_stage
```

### 2. Supply the game yourself

You need your own legally obtained copy of the game on the Switch 2. **This project
contains no game content and never will** — no dump, no update, no keys, no RomFS, no
extracted shaders, no imagery.

The Switch 2 `.nup` container is **not encrypted**, so the port needs **no keys and no
decryption tooling** — the container's own files are extracted directly:

```sh
python3 port/scripts/pack_nup.py /path/to/your/title.nup
```

That writes `<title ID>_build/extract/v<version>/ExeFS/` (the code modules) and the
RomFS image, with every file checked against its SHA-256.

### 3. Build the Vulkan renderer and the driver

```sh
make -C port/dm/linux GAME=0400486024DEC000 nxasahi-renderer nxasahi-front
```

The driver is a separate tree (`mesa/`), because it is a fork of a different upstream
(Mesa). Build it as you would build Mesa, and install it so its ICD is the one your
runtime picks up — see `mesa/src/asahi/vulkan/` and the fork's own documentation. The
runtime queries `VK_EXT_mesh_shader` on the device; the M1's G13 has no hardware mesh
shaders, so the **software task/mesh path** in this fork is what carries NVN2's task
and mesh programs.

### 4. Run it

```sh
DM_WINDOW=1 ./port/dm/linux/gen/0400486024DEC000/oot-playable
```

`DM_WINDOW=1` opens the SDL3 window; without it the runtime runs headless.

---

## Where we are now

**Status: 8 November 2026.** The game boots, plays its title and loading movies, loads
a save, and renders playable Kokiri Forest with Link, Navi and the HUD at correct
colours. Gameplay runs at roughly **50 ms a frame (GPU ~33 ms)** at the game's own
**683×384** dynamic-resolution floor.

**Open, and what each one needs:**

| item | where it stands |
|---|---|
| **The gameplay stand-in** | The game's own gameplay upscaler produces nothing on this path and the stand-in covers only the movie path, so a visible Kokiri run still needs the fallback to the bound `raw_9e5` source. This is the one item blocking gameplay visibility. |
| **The resolution floor** | The game's GPU-time dynamic-resolution controller holds the 3D at 683×384. All three peer ports of this same build lift it by patching the game's own module; the patch is prepared but deliberately **off** — it is not the right trade at the current per-frame cost. |
| **The `gp_run()` timestamp guard** | The component (`vk_gpstamp.h`) and its unit test are in the tree and the test passes; the call site in `vk_replay.c` is not yet applied, so the run-level behaviour is unproven. |
| **Untranslated shaders** | A few dozen remain; translation runs in the background. |
| **The meshlet cap** | The software mesh path emits a single meshlet group; the tunic cutouts want more. |
| **The host memory guard** | The run is pinned under a cgroup cap; the footprint sits at the guard and throttles. |

**The three component branches.** The port was grown as three branches of one tree and
this repository tracks their merge:

| branch | what it holds |
|---|---|
| `asahi-renderer` | the Linux Vulkan replay, the NVN command-record format, the mesh/task ABI headers, the `dmsh_spv` translator tools |
| `asahi-runtime` | the Linux host port — filesystem, audio, video codec, threads, SVC — the NSO tools |
| `asahi-linux` | the Android and Linux platform layers, the host thread-slot plumbing |
| `asahi` | **the merge of the three** — what this repository's `port/` submodule points at |

> **The `asahi` branch is the merge of the three, and it is build-verified.** On
> 8 November 2026 the merged tree compiled clean under `-Wall -Wextra -Werror` — the
> null renderer, the Vulkan renderer objects, the SDL front end and the Vulkan
> self-test all built, and the five device-free self-tests passed (`t_vk_mesh`,
> `t_push`, `t_skipcs`, `t_gpstamp`, `t_vk_stage`, each "passed (0 failures)").
> What is *not* verified is a full game run from the merged tree: that needs the
> game and a GPU, and it is the owner's to run. The three component branches stay
> published and known-good in their own right.
>
> **The merged pointer does not yet build the game.** The merged `dm/linux/Makefile`
> carries the renderer's bring-up targets only — there is no `dmhost` target — and
> because the merge resolved conflicts file by file across three branches that are
> whole-architecture alternatives, it also breaks the Apple and Android host builds
> and the Linux game build (three defects, all reproduced). That is being repaired at
> *directory* granularity — the branch is the coherent unit, not the file — and this
> repository's `port/` pointer moves when it lands. Until then, the component
> branches build and run the game; the merged branch builds the renderer and its
> self-tests.
>
> **One design question is still open in the merge.** The guest thread-slot mechanism
> exists in two forms, and they are closer than they first look: the runtime branch's
> `pthread_key_t` form and the Linux branch's `dm_thread_slot_t` form. **Both publish
> a `tpidr_el0`-relative offset into the guest's key page**, so the guest reads the
> slots from `tpidr_el0` the way the console does either way. They differ only in
> *where the four values are stored* and *how the offset is obtained* — glibc's
> thread-local array, located by a start-up probe that writes a marker and searches
> for it, versus a host TLS array whose offset is computed arithmetically. The merge
> keeps the runtime's form, which is the one the game-running Linux tree used, and the
> Linux branch's form has never had a game run in it. Whether to swap in the
> deterministic host array — which would remove the probe's dependence on glibc
> internals — is a call for the owner.

---

## Working on it

- **Port changes** go in `port/` — the runtime, renderer and platform layer. Build it
  with `make -C port/dm/linux GAME=0400486024DEC000 …`.
- **Driver changes** go in `mesa/` — the Honeykrisp G13 fork and its software
  task/mesh path.
- Push branches to the two submodule upstreams (`biosed/nxnative-asahi`,
  `biosed/mesa-honeykrisp-mesh`), then bump the submodule pointer here.

Both submodules carry the upstream's MIT licence (see `NOTICE` in the audit record
for the full attributions). The native mesh translator is a **separate, GPL-3.0
component that is deliberately kept outside the MIT tree** — see
`port/dm/linux/README.md` for why, and for the `DMSH_VK_MESH_XLATE` route that uses it.

## Licence and conduct

This project is independent and unaffiliated. It is not endorsed by, licensed by, or
connected to Nintendo, the game's developers, Mesa, or the Asahi Linux project.

You must supply the game yourself. Nothing here reproduces Nintendo game content, and
nothing here circumvents any access control — the Switch 2 container this port reads
is not encrypted, so no keys are involved at any point.
