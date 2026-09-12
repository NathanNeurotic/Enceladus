# AGENTS

Last updated: 2026-09-11 (release 1.2.1; master, dev, and experimental aligned at this cut)

Operational guidance and entry point for AI agents (cloud or interactive) working in this repository. This file is self-contained: it absorbs the former `AGENTS_START_HERE.md` orientation content. For current code/hardware status, behavioral invariants, preservation contracts, and the canonical known-issues list, defer to **`STATE.md`** rather than restating them here.

## Start Here / Orientation

POPSLoader is a PS2 launcher for POPStarter built on Enceladus runtime pieces, with behavior primarily orchestrated by **embedded Lua** modules (`system.lua`, `ui.lua`, `images.lua`). The Lua is bin2c'd into the EE ELF at build time, so a *runtime* Lua error (nil global, type error, **load-order** error) is invisible to `luac -p` and to CI and only surfaces on real PS2 / PCSX2. (`pops_profiles.lua` was removed 2026-07-13 with the profile-preset system.)

- Released line: **1.2.1** (2026-09-11). At this cut, `master`, `dev`, and `experimental` share one commit and the `v1.2.1` stamp.
- Dev branch: **`dev`** (the active/rolling branch; `BETA-12-PLAY` is now **archival/frozen**). The rolling-release workflow publishes from `dev`.
- Testers: maintainer + Nuno (primary), CosmicScale (secondary), plus **provato** and **nuno6573**. Agents cannot run hardware tests — claims of hardware verification must cite a recorded result in `QA_REGRESSION_MATRIX.md`.

> **Historical note**: Earlier entry-point docs framed D-10 (HDD POPSTARTER + HDD game) as the single urgent unresolved objective. D-10 was resolved by the B2 PFS-unmount fix at commit `4ae6679` and is now a **preservation contract, not an open blocker** (see `STATE.md > Preservation Contracts`).

### Where to look first

| File | What's there |
|---|---|
| [STATE.md](STATE.md) | **Canonical.** Current code + hardware status, behavioral invariants, preservation contracts, the single known-issues list, hardware-verification table. Start here for ground truth. |
| [QA_REGRESSION_MATRIX.md](QA_REGRESSION_MATRIX.md) | Authoritative detailed hardware/CI run ledger with per-artifact history. |
| [ROADMAP.md](ROADMAP.md) | Prioritized backlog / open work. |
| [DECISIONS.md](DECISIONS.md) | Decision log with rationale and evidence. |
| [docs/archive/](docs/archive/) | Investigation artifacts: `U10_INVESTIGATION.md`, `LAUNCH_HYGIENE.md` (launch-path architecture, V2 mimicry, Layer A/B/C), `HDD_POPSTARTER_HANDOFF.md`. |

## Source-of-Truth Rule
- Prefer claims tied to current repository files, workflow definitions, and recorded hardware outcomes in `QA_REGRESSION_MATRIX.md`.
- If a hardware/runtime claim cannot be proven from code or a recorded run result, mark it `Unknown (verify on hardware)`.
- Separate repo-verified facts from hardware-reported results in task output.
- The 2026-06 HDD/PAL/BDMA features are repo-verified and **boot on PCSX2**; provato confirmed the **HDD is RW-writable on real hardware**, but the full flows are **not yet broadly hardware-confirmed**. Describe them as "implemented / boots on PCSX2 / HDD RW confirmed on hardware (provato) / full flow validating on hardware" — never "confirmed working on hardware", and do not keep calling the shipped HDD save/`.hide` features "a probe" or "read-only".

## Scope
- Allowed: task-focused edits to requested files; documentation, tests, and narrow fixes directly tied to the active task.
- Avoid touching unrelated Lua/C/C++ files unless required by task scope.
- Preserve boot/launch and storage detection pipelines unless the task explicitly targets them.

## Preservation Contracts & Known Issues
These are shared, volatile facts maintained in one place. **Do not restate or fork them here.**
- **Preservation contracts** (D-10 / D-14 / D-15 / DKWDRV-MC / BOOT.ELF-USB-booted / `EnsureBootPartitionWritable`): see **`STATE.md > Preservation Contracts`** and the **Reported Hardware Status** table. Write these as contracts hardware-confirmed in the BETA line, not as open failures.
- **Known issues** (open / in-testing / recently-resolved): see **`STATE.md > Known Issues`**. Notable status deltas already reflected there: **U-10 (BOOT.ELF from HDD-boot)** and **DKWDRV from a custom HDD path** are **RESOLVED** (were known-broken); Class-A **HOSDmenu / wLaunchELF** start failures are **resolved**. The old "HDD installs save to `mc0:` because `ps2hdd-osd.irx` can't write PFS / needs an IRX swap" claim is **OBSOLETE** — HDD installs now save on the HDD boot partition via the RW mount take-over (single-device parity; see `STATE.md > Settings`).

## High-Risk Surfaces
Changes in these files can break core behavior and require extra care:
- `bin/POPSLDR/system.lua` (LaunchEngine, RunPOPStarterGame, ResolveBootContext, classify_mass_boot, AutoInitStartupBackends, EnsureMmceReadyOnce, **`PLDR.ResolveLaunchPopstarterPath`** — the per-device POPSTARTER.ELF resolver: the explicit user-configured absolute path (the "POPSTARTER Path" setting; empty = **Automatic** — the 16-preset profile system was removed 2026-07-13, UI/config layer only, the ladder is untouched) wins first, then for removable devices the game's own `<device>:/POPS/POPSTARTER.ELF`, then the cwd copy beside POPSLOADER.ELF, then the `mc0:`→`mc1:` net (for internal-PFS HDD the device step is `hdd0:__common/POPS/POPSTARTER.ELF`, resolved through the same `__common` partition machinery that preserves the D-10/D-15 partition context); the device + cwd steps are existence-gated so a device without a copy falls through. Not yet hardware-tested. And **`PLDR.HDD.EnsureBootPartitionWritable`** — the boot pfs-slot unmount→remount-RW "take over the mount" that is now load-bearing for HDD settings save and HDD in-app `.hide`; a launch-path or mount change must not break it. Note also the **load-order trap**: `PLDR.HDD` methods must be defined *after* `PLDR.HDD` exists — defining them early bricked recent HDD-feature rolling builds, fixed `d4b04be`. New 2026-07-09 launch-path residents: **`PLDR.MaybeApplyAdaptiveBdma`** (launch-time BDMA staging — runs after the launch validations, cancels the launch on a staging failure; nothing queued after exec can render, so don't move its toast past the exec) and the **partition-installed game arm** in `RunPOPStarterGame` (argv0 = the literal `PP.`/`__.` partition label — case-sensitive, never sanitized).)
- `bin/POPSLDR/ui.lua` (LaunchSelectedGame — its POPSTARTER **preflight must resolve with the SAME root the `RunPOPStarterGame` call gets**: the game entry's own device root on encoded-entry pages (USB entries = `"<root>POPS/|name.vcd"`, `PLDR.GAMEPATH` deliberately empty there), `GAMEPATH` on bare-name pages, scene-guarded on GHDD. Resolving the preflight with `GAMEPATH` blocked every drive-resident-only USB POPSTARTER with "No POPSTARTER.ELF found" while the launch itself would have worked (sAGA/oldman63, fixed 2026-07-16) — do not reintroduce the divergence. Also LaunchBootElf, OpenDKWDRV; `BuildCoverCandidates` — the per-device cover-art seeker: it returns **exactly ONE candidate** (EXP71, maintainer directive). Removable devices: `<device>:/ART/<gamefilename>_COV.png`, device root matched with `%w+:/` so a digit-bearing device name like `mx4sio0:` still resolves (`%a+%d*:` did not, and MX4SIO covers were unfindable). APA/PFS: `hdd0:__common/POPS/ART/<gamefilename>_COV.png` via `PLDR.ResolveHddPartitionReadablePath`, which existence-confirms. The user-selectable folder (`ART_LOCATION`, the *Cover/details folder* row) was REMOVED in EXP35 and the key is inert; the disc-marker-stripped family name, the always-appended `POPS/` fallback, the legacy `<name>.png` and the additive legacy families are ALL GONE — a stripped candidate can shadow exact per-disc art and every extra candidate is a full dir-chain walk on a big ART folder. The `.txt` details sidecar (`<device>:/ART/<gamefilename>.txt`) is read on the RESIDENT COVER WORKER via `Graphics.coverLoadTextPath` + `coverLoadText`, never on the render thread; `System.listDirectory` on the cover folder must NOT come back (implicated three times). **INVARIANT: selecting a game performs ZERO blocking file reads**, pinned by harness T30/T35/T40; external launches drain the worker first (T39). Canonical detail: **STATE.md > Cover art** plus the EXP71/EXP73 bullets; also `UI.Pad.Listen`/`resolve_nav` — the frame-counted nav auto-repeat and the `Pads.getMode()`-gated analog-stick fold; do not reintroduce wall-clock timing or an ungated stick read — see Gotchas)
- `src/main.cpp` (detectBootDeviceHintFromArgv0, parseLaunchArgs, eager IRX load order, conditional mmceman)
- `src/luasystem.cpp` (lua_loadELF*, EnsureBDM*, EnsureMmceman, lua_mx4sio_init with mandatory EnsureUsbMass-first ordering, getMassMountDriver)
- `src/luaplayer.cpp`
- `src/elf_loader/src/elf.c` (LoadELFFromFile*, ExecuteViaEmbeddedLoader, ExecuteHddBackedViaEmbeddedLoader, LoadELFFromFileWithPartition)
- `src/elf_loader/src/loader/src/loader.c` (BRAM child loader; HDD partition-context branch must preserve B2 dynamic PFS unmount)
- `etc/boot.lua` (pfs1: boot mount normalization)
- `Makefile`
- `.github/workflows/compilation.yml`
- `.github/workflows/rolling-release.yml` (builds and harness-gates on push to `dev` **and** on PR events, but the publish step carries `if: success() && github.event_name == 'push'` — only a push to `dev` moves the canonical `rolling-release` tag and its bare-ELF + zip assets; gated since PR #511, 2026-07-16)

## Change Discipline
- Keep diffs minimal and localized. One objective per branch/PR when feasible.
- No drive-by refactors or formatting churn.
- Do not rename or move files unless required.
- Prefer additive and reversible changes.

## Safety Rules
- Never run destructive commands (`rm -rf`, `git reset --hard`, force-push) without explicit instruction.
- Do not overwrite user-authored changes outside task scope.
- Pause and report if unexpected repository changes appear during work.
- Avoid adding new runtime logging unless explicitly requested.

## Build / Test Reality
- GitHub Actions is the canonical build path. The pinned CI image is `ps2dev/ps2dev:v2.0.0`.
- **The embedded-Lua syntax gate is now LIVE** (`luac5.4 -p` on `bin/POPSLDR/*.lua` + `etc/boot.lua`; the workflows `apk add lua5.4` and hard-fail on a syntax error). It used to silently skip because the ps2dev image shipped no `luac`. It catches **SYNTAX only** — runtime nil-global / type / **load-order** errors stay invisible to it (the `d4b04be` boot brick was exactly such a case).
- **A host-execution gate covers the runtime class** (2026-07-10): `tools/host_harness.py` EXECUTES the real `system.lua` chunk (ui.lua require'd at its real point) under a mocked PS2 environment on host Lua 5.4 (lupa), then runs a functional battery (Adaptive BDMA staging cycle, partition-game scan, settings round-trips). Both workflows run it after the syntax gate — a real failure hard-fails the build; a container that can't install lupa skips cleanly (check the step log: "skipping host harness" means only the syntax gate ran). Run it locally with `python tools/host_harness.py`. It executes up to the splash/main-loop handoff only, with mocked I/O — hardware remains the only truth for launch paths.
- Rolling-release publishes the bare `POPSLOADER.ELF` and the zip from one build to the floating `rolling-release` GitHub Release; only a push to `dev` publishes; PR events run the same build and gates but never overwrite the release assets (the publish step is gated on `github.event_name == 'push'`). `POPSTARTER.ELF` (the redistributable homebrew launcher — the POPS engine binaries are NOT redistributable) now ships in both the rolling zip and the formal install zip; do not strip it from a packaging step.
- Hardware testing happens on real PS2 hardware via the maintainer and the testers. Agents cannot run hardware tests.

## Gotchas / Footguns
High-value traps that have actually burned agents in this repo. Verify the unit/binding from the toolchain or source, never from assumption.

- **`Timer.getTime()` returns MICROSECONDS, not milliseconds.** `lua_time` (`src/luatimer.cpp:41`, registered `getTime`) returns raw `clock() - tick` ticks with *no* conversion, and `CLOCKS_PER_SEC == 1e6` on the EE toolchain (confirmed by `src/main.cpp:243`, which multiplies by 1000 then divides by `CLOCKS_PER_SEC` to get ms). Code that treats a `getTime()` delta as ms runs **1000x too fast**. The canonical Enceladus idiom is **frame-counting** for any per-frame timing (nav auto-repeat, scroll rate), not wall-clock reads — the UI nav repeat (`resolve_nav` / `NavHoldFrames` / `nav_fps`, `bin/POPSLDR/ui.lua:4607`) and the description right-stick scroll (`DescScrollFrames`, `ui.lua:2686`) are frame-counted. Stock-Lua `os.clock()` returns SECONDS (pre-converted) but is currently unused in the Lua. The action debounce (formerly `MIN_ACTION_MS`) has been **removed** — action emits ride the rising edge only (`pressed = GPAD & ~OLDPAD`), so a held button fires once per press without a timer; the scene-fade / boot-fade / carousel transitions were frame-paced. Don't reintroduce a wall-clock action debounce.

- **Embedding/removing an asset is THREE explicit, hand-coordinated places** (no auto-glob; missing any one fails the build or yields a blank image):
  1. `Makefile` — add a `BIN2S` rule for the file **and** list its `.o` in `EMBEDDED_RSC` (`Makefile:96`).
  2. `src/embed_assets.cpp` — add the `extern` symbol + size, and an `ASSET_ENTRY(...)` in **both** the bare-name and the `POPSLDR/IMG/`-prefixed sections of `g_embedded_assets[]` (`src/embed_assets.cpp:97`).
  3. `bin/POPSLDR/images.lua` — add a row to `IMG_REGISTRATIONS` (`images.lua:11`); it looks the asset up by **bare filename**.
  Removal is the same three places in reverse (the `MISSING.png` removal also had to drop a `default.png` fallback hook and `IMG_FALLBACKS` wiring — grep the whole tree for the bare name before declaring an asset gone).

- **Pad mode: use `Pads.getMode()`, NOT `Pads.getType()`.** `Pads.getMode` → `lua_getmode` returns `padInfoMode(..., PAD_MODECURID, ...)` — the **live negotiated** controller mode (high nibble: `0x7` DualShock, `0x5` analog, `0x4` digital, `0` no-data), and is what the analog-stick→d-pad fold must gate on (`bin/POPSLDR/ui.lua:4498`). `Pads.getType` → `lua_gettype` returns a `PAD_MODETABLE` *capability-table* entry and is the wrong signal for "is the stick live" — an ungated fold injected a phantom `-127` on a digital pad and broke up/down nav.

- **Verify every file:line / function / `PLDR.X` / `UI.X` / flag / asset name against the actual source before you write or repeat it.** A prior doc pass's per-doc agents self-reported "zero stale" yet left ~15 wrong anchors. `grep`/Read the source; do not trust a ledger, an audit report, or a sibling doc's anchor blindly. Codex/audit reports are *reference, not fact* — verify before acting on them.

## Testing Expectations
- Choose the smallest test plan that can prove the change.
- Docs-only changes: run lightweight sanity checks when available; otherwise note `not run`.
- Runtime/build changes: run targeted checks first, then broader checks only if risk requires.
- Hardware-only behavior should be tracked in `QA_REGRESSION_MATRIX.md` and marked if unverified.

## Documentation / Evidence Discipline
When updating status after changes:
- **`STATE.md` is canonical** for runtime state, invariants, preservation contracts, the known-issues list, and hardware status; the other root docs (`README`, this file, `ROADMAP`, `DECISIONS`) point there instead of duplicating. Treat `QA_REGRESSION_MATRIX.md` as the detailed hardware/CI run ledger.
- Hardware pass/fail claims must have a matching `QA_REGRESSION_MATRIX.md` row with a date and result.
- In-flight / unreleased work is `Unknown (verify on hardware)` unless explicitly recorded. **Do not enumerate stale PR numbers here** — for the current in-flight/known-open work list, see `STATE.md > Known Open Work` (and `ROADMAP.md`).
- Released changelog entries should not be retroactively edited; new work goes in `[Unreleased]` at the top of `bin/changelog`.
- Remove stale branch names, stale feature claims, and outdated decisions.
- Do not silently carry forward old "fixed" claims when the only evidence is a prior chat report. If a regression was reported on hardware, record that result explicitly.

## Communication Format
Use this report structure in task responses:
- Summary: what changed and why.
- Diffstat: file-level change summary.
- Diff: key hunks or full patch when requested.
- Test plan: what was run, what passed/failed, and what was not run.

## Summary For The Next Agent
POPSLoader's stable backbone (HDD POPSTARTER paths, DKWDRV-MC, BOOT.ELF for USB- and HDD-booted, settings sidecar) is hardware-confirmed in the BETA line. The 2026-06 work — HDD-resident settings save + in-app `.hide` via the boot-partition RW take-over, PAL native 640×512, the BDMA `bdma_mode.txt` marker + POPSTARTER-MC-folder toggle/interlock — is implemented and boots on PCSX2, with HDD RW confirmed on hardware (provato) and the full flows still validating on hardware. Your job is most likely: drive doc/feature work, hardware-verify the in-flight HDD/PAL features, complete a queued PR, react to a tester report, or (once D-10/D-14/U-10 and the new features settle) the queued Settings UI redesign. Whatever it is: preserve the contracts in `STATE.md`, hardware-verify before claiming any new fix, and keep the docs pointed at `STATE.md` rather than re-duplicating the shared facts.
