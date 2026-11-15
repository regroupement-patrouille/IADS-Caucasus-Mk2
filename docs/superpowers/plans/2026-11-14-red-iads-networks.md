# Red IADS Networks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the automatic `veafSkynet` red IADS with two hand-built Skynet networks (TBS, MAP) driven by normalized group/unit name prefixes.

**Architecture:** Python tools (stdlib only) read `src/mission/mission`, generate a reviewed rename table (CSV), and apply it in place. A single mission script, `src/scripts/mission-iads-init.lua`, builds both IADS from the prefixes with plain Skynet 3.6.0, logs a startup report, and adds the F10 menus. `missionSkynetLogic.lua` is deleted.

**Tech Stack:** Python 3.10+ (stdlib, `unittest`), Lua 5.1 (DCS; local tests with `"C:/Program Files (x86)/Lua/5.1/lua.exe"`), Skynet IADS 3.6.0 (`src/scripts/skynet-iads-vendored.lua`), VEAF MCT 6.36.0 (`python build.py`), dcs-hotload 3.1.0 for live checks.

**Spec:** `docs/superpowers/specs/2026-11-14-red-iads-networks-design.md`

## Global Constraints

- Network codes `TBS`, `MAP`; roles `EW`, `SAM`, `PD`, `CC`. Prefix form `<NET>-<ROLE>` followed by one space.
- Group names: EW site `<NET>-EW <Site>`; SAM site `<NET>-SAM <Site>`; escorts `<NET>-PD <Site> #<n>`, `<NET>-SAM <Site> #<n>`, `<NET>-EW <Site> #<n>`, or `<Site> #<n>` (outside the IADS); AWACS `<NET>-EW Awacs <Place>`; statics `TBS-CC Tbilissi`, `TBS-CC Tbilissi Power`.
- Unit names: `<group>-01`, `-02`… (two digits); a group in role EW has one unit named exactly like the group; static unit name = group name.
- `<Site>` = `<system> <place>` with system ∈ `SA-2 SA-5 SA-6 SA-10 SA-11 SA-15 SA-19 SA-22 HQ-7 IRIS-T Rapier`; EW sites are `<place>` only. Mission spellings kept (Tbilissi, Turquie, Dzhvari…); `EWR - Gelen` → place `Gelen`.
- Never rename `Qra_Tbilissi-*`, the `Qra_Tbilissi` zone, `veafSpawn-*`, or anything blue.
- AWACS: `Awacs #3`→`TBS-EW Awacs Tbilisi`, `Awacs #1`→`MAP-EW Awacs Mozdok`, `Awacs #2`→`MAP-EW Awacs Turkey`, `Awacs #4`→`MAP-EW Awacs Dzhvari`.
- TBS places: Tbilissi, Vaziani, Kumisi, Martkobi (all within 18 km of `CommandCenterRed`; next red group 208 km away). Everything else red → MAP.
- `SA-22 - Dzhvari` is a SAM site, not a point defence.
- Escort role by unit types: any of `CHAP_TorM2`, `CHAP_PantsirS1`, `HEMTT_C-RAM_Phalanx` → PD; `Dog Ear radar` → EW; any of `2S6 Tunguska`, `Gepard`, `ZSU-23-4 Shilka`, `SA-11 Buk LN 9A310M1` → SAM; only `SA-18 Igla comm`, `SA-18 Igla manpad`, `SA-18 Igla-S comm`, `SA-18 Igla-S manpad`, `Ural-375`, `Ural-4320-31`, `Ural-4320T` → outside. Any other type in an escort → error.
- `src/scripts/` must hold no `.lua` VMCT should not load (VMCT loads every `.lua` there): tests live in `tests/`.
- Commits only with the user's go-ahead; work on branch `red-iads-networks`.

## Review Focus

- A Python rename that touches a waypoint, zone, or blue object named like a red group → expect only red group/unit/static names and the four A-50 groups changed (Task 1 test `test_only_targeted_names_change`).
- A red group whose current name matches no rule (new site added in the editor) → expect the generator to stop with that name listed, never to guess (Task 2 test `test_unknown_group_name_is_an_error`).
- A PD whose parent site was renamed or deleted → expect a warning naming the PD at startup, and the PD still a SAM site of its network (Task 4 test `test_parent_site_name_rejects_non_pd`, plus the report in Task 6).
- Running the rename twice → expect the second run to refuse (old names missing), leaving the file untouched (Task 1 test `test_missing_old_name_refuses`).
- A red group carrying a prefix whose Skynet element cannot be created (no usable unit) → expect a warning, not a script error that stops the other network (Task 4 `addSamSiteSafe` returning nil is logged).

---

### Task 0: Branch

- [ ] **Step 1:** Ask the user to commit (or let you commit) the pending working-tree changes (vendored Skynet switch, README, mission.yaml, scripts), so the branch starts clean.
- [ ] **Step 2:** `git switch -c red-iads-networks`. Expected: `git status` clean apart from the design/plan docs.

### Task 1: Mission name reader and renamer

**Files:**
- Create: `tools/mission_names.py`
- Test: `tests/python/test_mission_names.py`, fixture `tests/python/fixtures/mini_mission.lua`

**Interfaces:**
- Produces:
  - `@dataclass Entry: coalition: str, category: str ("vehicle"|"static"|"plane"|...), group_name: str, unit_names: list[str], unit_types: list[str], x: float, y: float` (x, y = first unit)
  - `@dataclass NameSpan: start: int, end: int, value: str` (span of the string literal's content in the file text)
  - `read_entries(text: str) -> list[Entry]`
  - `apply_renames(text: str, groups: dict[str, str], units: dict[str, str], scope: Callable[[Entry], bool]) -> str` — renames only the `name` fields of groups and their units for entries where `scope(entry)` is true; raises `RenameError` if an old name in `groups`/`units` is not found in scope, is found more than once in scope, or if a new name collides with any existing group/unit name in the file.

- [ ] **Step 1: Write the fixture and failing tests.** Fixture: a `mission = { coalition = { red = { country = { [1] = { vehicle = { group = { ... } }, static = {...}, plane = {...} } } }, blue = {...} } }` in the bare-key style of `src/mission/mission`, with one red vehicle group of 2 units whose first waypoint has the same `name` as the group, one red static, one red plane, one blue vehicle group with the same name as the red one's unit. Tests:
  - `test_read_entries` — returns 4 entries with the right coalition/category/names/types.
  - `test_only_targeted_names_change` — renaming the red group and its units changes exactly those 3 literals; the waypoint name and the blue group are byte-identical.
  - `test_missing_old_name_refuses` — `RenameError`, and the caller's text is unchanged.
  - `test_collision_refuses` — new name equal to an existing name → `RenameError`.
  - `test_real_mission_parses` — `read_entries` on `src/mission/mission` finds `CommandCenterRed`, `Awacs #3`, `SA10 - Kumisi` with 11 units.
- [ ] **Step 2:** Run `python -m unittest discover -s tests/python -v`. Expected: FAIL (module missing).
- [ ] **Step 3: Implement `tools/mission_names.py`.** A small recursive-descent reader for the Lua table subset the file uses (`{ }`, `key = value`, `[n] = value`, strings with `\"` escapes, numbers, `true/false/nil`, trailing commas) that records the span of every string value. Walk `mission.coalition.<side>.country[i].<category>.group[j]` for `name`, `units[k].name`, `units[k].type`, `units[1].x/y`. Only those `name` keys are ever replaced (not `route.points[*].name`). Apply replacements from the end of the text backwards.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit `tools/mission_names.py tests/python` — "Add mission name reader and renamer".

### Task 2: Rename table generator

**Files:**
- Create: `tools/make_red_iads_names.py` (CLI: `python tools/make_red_iads_names.py src/mission/mission tools/red-iads-names.csv`)
- Test: `tests/python/test_red_iads_names.py`

**Interfaces:**
- Consumes: `read_entries`, `Entry` (Task 1).
- Produces:
  - CSV `tools/red-iads-names.csv`, one row per unit (statics: one row), columns `old_group,new_group,network,role,parent_site,old_unit,new_unit,unit_type`; `role` ∈ `EW SAM PD CC none`; `parent_site` = new `<Site>` of the parent for escorts, empty otherwise.
  - `parse_site_name(old: str) -> tuple[str, str] | None` → `(system, place)`, `system` normalized (`EWR` for EW sites).
  - `parse_escort_name(old: str) -> tuple[str, str, int] | None` → `(system, place, sol_number)`.
  - `escort_role(unit_types: list[str]) -> str` → `PD|EW|SAM|none`, raises `NameRuleError` on an unknown type.
  - `build_rows(entries: list[Entry]) -> list[dict]`, raises `NameRuleError` listing every red ground group it cannot classify.

- [ ] **Step 1: Write failing tests** (values from the real mission):
  - `test_parse_site_name`: `"SA10 - Kumisi"`→`("SA-10","Kumisi")`; `"SA-22 Pantsir - Turquie"`→`("SA-22","Turquie")`; `"HQ7 - Dzhvari"`→`("HQ-7","Dzhvari")`; `"SA-15 - Dzhvari-4"`→`("SA-15","Dzhvari-4")`; `"EWR - Gelen"`→`("EWR","Gelen")`; `"SA-11 - Nadezhnaya"`→`("SA-11","Nadezhnaya")`.
  - `test_parse_escort_name`: `"SA2- Maykop - Sol-2"`→`("SA-2","Maykop",2)`; `"SA-2 - Shahe- Sol-1"`→`("SA-2","Shahe",1)`; `"SA11 Nadezhnaya - Sol-1"`→`("SA-11","Nadezhnaya",1)`; `"EWR - Pervo - Sol-3"`→`("EWR","Pervo",3)`.
  - `test_escort_role`: `["CHAP_TorM2"]`→PD; `["Dog Ear radar"]`→EW; `["Gepard"]`→SAM; `["SA-18 Igla-S comm","SA-18 Igla-S manpad","Ural-4320T"]`→none; `["T-72B"]`→`NameRuleError`.
  - `test_rows_on_real_mission` (reads `src/mission/mission`): `SA10 - Kumisi` → `TBS-SAM SA-10 Kumisi`, units `TBS-SAM SA-10 Kumisi-01`…`-11`; `EWR - Gelen` unit `EWR - Laza` → `MAP-EW Gelen`; `SA-10 - Gudauta - Sol-1` (Tor) → `MAP-PD SA-10 Gudauta #1`, parent `SA-10 Gudauta`; `SA-10 - Gudauta - Sol-6` (Shilka) → `MAP-SAM SA-10 Gudauta #6`; `SA-10 - Gudauta - Sol-3` (Dog Ear) → `MAP-EW SA-10 Gudauta #3`; `Rapier - Dzhvari - Sol-1` → `Rapier Dzhvari #1`, role none; `SA-22 - Dzhvari` → `MAP-SAM SA-22 Dzhvari`; Shahe's two `Sol-1` get distinct numbers 1 and 2 and its next escort continues the sequence; `CommandCenterRed`→`TBS-CC Tbilissi`; `Static Diesel Power Station 5I57A-1`→`TBS-CC Tbilissi Power`; the four A-50s per Global Constraints; no `Qra_`/`veafSpawn-`/blue row; every TBS row's group is < 18 km from `CommandCenterRed` and every MAP ground row > 18 km; all new names unique.
  - `test_unknown_group_name_is_an_error`: an extra red vehicle entry `"Random group"` → `NameRuleError` mentioning it.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3: Implement** per Global Constraints. Escort numbering: per parent site, sort by `(sol_number, old_name)` and number from 1. Parent lookup: the site whose `(system, place)` equals the escort's. An escort without a parent site → `NameRuleError`.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Generate `tools/red-iads-names.csv`, commit tool + tests + CSV — "Add red IADS rename table".
- [ ] **Step 6: Gate — the user reviews the CSV.** Present a summary (counts per network/role, every PD with its parent, every `none`) and the file link. Do not go on until the user approves; apply their corrections in the generator (not by hand in the CSV) and regenerate.

### Task 3: Apply the renames

**Files:**
- Create: `tools/rename_red_iads.py` (CLI: `python tools/rename_red_iads.py src/mission/mission tools/red-iads-names.csv`; `--check` only validates)
- Modify: `src/mission/mission`
- Test: `tests/python/test_rename_red_iads.py`

**Interfaces:**
- Consumes: `read_entries`, `apply_renames` (Task 1); the CSV (Task 2).
- Produces: `check_names(entries: list[Entry]) -> list[str]` — problems found against the naming rule (empty = OK); used after the rename and later by anyone editing the mission.

- [ ] **Step 1: Failing tests:** `test_check_names_flags_bad_unit_suffix` (group `MAP-SAM SA-2 Poti`, unit `foo` → 1 problem); `test_check_names_ew_unit_must_equal_group`; `test_check_names_ignores_blue_qra_veafspawn`; `test_apply_from_csv_on_fixture` (scope = red, plus the A-50 groups).
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3: Implement.** Scope: coalition `red` and (category `vehicle`/`static`, or group name in the CSV). Write the file only if `apply_renames` succeeds and `check_names` on the result is empty; keep the original encoding and line endings.
- [ ] **Step 4:** Run tests. Expected: PASS.
- [ ] **Step 5:** Run the CLI on the real mission, then `python tools/rename_red_iads.py src/mission/mission tools/red-iads-names.csv --check`. Expected: "0 problems"; `git diff --stat src/mission/mission` shows only `mission` changed.
- [ ] **Step 6:** `python build.py`. Expected: build succeeds (the mission still uses `missionSkynetLogic.lua` at this point; that is fine).
- [ ] **Step 7:** Commit — "Rename red IADS groups and units".

### Task 4: Network builder in `mission-iads-init.lua`

**Files:**
- Modify: `src/scripts/mission-iads-init.lua` (currently empty)
- Create: `tests/lua/test_iads_init.lua`, `tests/lua/stubs.lua`

**Interfaces:**
- Produces (global table `MissionIads`):
  - `MissionIads.Networks = { { code = "TBS", menu = "IADS Tbilissi", commandCenter = "TBS-CC Tbilissi", powerSource = "TBS-CC Tbilissi Power" }, { code = "MAP", menu = "IADS Map" } }`
  - `MissionIads.DebugMode = false`, `MissionIads.ActivationDelay = 5` (seconds, today's `DelayForStartup`)
  - `MissionIads.parentSiteName(groupName: string, code: string) -> string|nil` — `"MAP-PD SA-10 Gudauta #1"`,`"MAP"` → `"SA-10 Gudauta"`; nil if not a `code`-PD name.
  - `MissionIads.networkCodeOf(name: string) -> string|nil` — `"TBS"`/`"MAP"` from any `<NET>-…` name.
  - `MissionIads.build(network: table) -> iads` — creates `SkynetIADS:create(network.menu)`, adds EW by prefix `code.."-EW"`, SAM by prefix `code.."-SAM"`, then each red group named `code.."-PD …"` with `addSAMSite`, linked to `iads:getSAMSiteByGroupName(code.."-SAM "..site)` or else `iads:getEarlyWarningRadarByUnitName(code.."-EW "..site)` via `parent:addPointDefence(pd)`; command center + power source when the network defines them. Stores `network.iads = iads`.
  - `MissionIads.start()` — builds every network, schedules `iads:activate()` after `ActivationDelay`, then calls `MissionIads.report()` and `MissionIads.addMenus()` (Tasks 5–6).
  - The file ends with `if not MISSION_IADS_TEST then MissionIads.start() end`.

- [ ] **Step 1: Failing Lua tests** with stubs (`stubs.lua` fakes `coalition.getGroups`, `Group`, `StaticObject.getByName`, `timer`, `env.info`, and a recording `SkynetIADS`): `parentSiteName` cases (`"TBS-PD SA-10 Kumisi #1"`→`"SA-10 Kumisi"`; `"MAP-PD Pervo #3"`→`"Pervo"`; `"MAP-SAM SA-2 Poti"`→nil; `"TBS-PD SA-10 Kumisi #1"` with code `MAP`→nil — `test_parent_site_name_rejects_non_pd`); `build` on a fake red side calls `addEarlyWarningRadarsByPrefix("TBS-EW")`, `addSAMSitesByPrefix("TBS-SAM")`, links the PD to its SAM parent, and for TBS calls `addCommandCenter` then `addPowerSource`; a PD whose parent is missing produces one warning line and no error.
- [ ] **Step 2:** Run `"C:/Program Files (x86)/Lua/5.1/lua.exe" tests/lua/test_iads_init.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.** Wrap each element creation in `pcall`; a failure logs a warning naming the group and continues. Debug settings from today's `SkynetNetworkDisplayState(…, DebugMode)`.
- [ ] **Step 4:** Run the Lua tests. Expected: PASS.
- [ ] **Step 5:** Commit — "Build TBS and MAP IADS from name prefixes".

### Task 5: F10 menus

**Files:** Modify `src/scripts/mission-iads-init.lua`; extend `tests/lua/test_iads_init.lua`.

**Interfaces:**
- Produces: `MissionIads.addMenus()`, `MissionIads.toggleStatus(network)`, `MissionIads.deactivate(network)`, `MissionIads.destroyCommandCenter(network)`.

- [ ] **Step 1: Failing tests** (stubbed `missionCommands`): two submenus `IADS Tbilissi`, `IADS Map`; each has `Display/hide Skynet status` and `Deactivate network`; only `IADS Tbilissi` has `Disable network (destroy CC)`. `toggleStatus` flips `IADSStatus`, `radarWentDark`, `contacts`, `radarWentLive`, `noWorkingCommmandCenter`, `harmDefence` together (as today's `SkynetNetworkDisplayState`). `destroyCommandCenter` calls `trigger.action.explosion(<CC position>, 200)` for each existing CC.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3: Implement.** `deactivate`: `iads:deactivate()`, then for every EW radar and SAM site: `finishHarmDefence()`, `cleanUp()`, `goLive()` (today's `veafSkynet.deactivateNetwork(…, Live)` behavior; every site goes live and fights on its own). No `veafSkynet`/`veafSkynetMonitor` reference anywhere in the file.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit — "Add per-network F10 menus".

### Task 6: Startup report, cleanup, and build

**Files:**
- Modify: `src/scripts/mission-iads-init.lua`, `mission.yaml`, `README.md`
- Delete: `src/scripts/missionSkynetLogic.lua`

**Interfaces:**
- Produces: `MissionIads.report()` — after activation, `env.info` lines prefixed `MISSION IADS:`: per network the EW radars, SAM sites, point defences with parent, and CC state; then each red ground group and red aircraft (excluding `Qra_Tbilissi-*`, `veafSpawn-*`) in no network; warnings for a PD without parent and for an unprefixed red ground group containing a type from the PD/SAM/EW lists.

- [ ] **Step 1: Failing test:** on the fake red side, `report()` lists a group `Rapier Dzhvari #1` as "in no network" and warns about an unprefixed `SA-15 Somewhere`.
- [ ] **Step 2:** Run. Expected: FAIL. **Step 3:** Implement. **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Delete `src/scripts/missionSkynetLogic.lua`. In `mission.yaml`: `custom_scripts` = `skynet-iads-vendored.lua` then `mission-iads-init.lua`; remove `veafSkynet.DynamicSpawn` and `veafSkynet.DelayForStartup` from `module_settings`; keep `SKYNET: false`, `SKYNET_MONITOR: false`, update their comment. README: two networks, naming scheme (table from the spec), TBS CC + generator, `tools/` usage (`rename_red_iads.py --check` after editing red units).
- [ ] **Step 6:** `python build.py`. Expected: success; the `.miz` contains `l10n/DEFAULT/mission-iads-init.lua` and no `missionSkynetLogic.lua` and no `skynet-iads-compiled.lua`.
- [ ] **Step 7:** Commit — "Start red IADS from mission-iads-init.lua; drop missionSkynetLogic.lua".

### Task 7: In-game verification and editor round trip (with the user)

- [ ] **Step 1:** `python build.py --hotload`, user starts the mission in DCS. Via hotload (skill `dcs-hotload:piloting-dcs-hotload`) or `dcs.log`: Skynet 3.6.0 loaded once; `MISSION IADS:` report matches the CSV (counts per network/role); A-50s listed as EW in the right network; only Igla/Ural escorts "in no network".
- [ ] **Step 2:** F10: both submenus and their commands work; destroying `TBS-CC Tbilissi Power` (hotload `trigger.action.explosion`) makes TBS lose its command center while a MAP site stays networked.
- [ ] **Step 3:** HARM test at `MAP-SAM SA-10 Gudauta` (user, in game): its Tor PD goes live and the SA-10 keeps emitting. QRA Tbilissi and the marker toolbox still work.
- [ ] **Step 4:** Mission Editor round trip: open the built `.miz`, save, `.\veaf-tools.exe mission extract <file>.miz .`, then `python tools/rename_red_iads.py src/mission/mission tools/red-iads-names.csv --check` → 0 problems; `git diff src/mission/mission` shows no renamed name reverted.
- [ ] **Step 5:** Record coverage gaps observed (spec: handled later). Update project memory (`mk2-port-status.md`) with the new IADS setup. Commit any extract result — "Verify red IADS in game".
