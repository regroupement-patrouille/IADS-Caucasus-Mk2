# Red IADS: two hand-built Skynet networks

Date: 2026-11-14 · Mission: IADS-Caucasus Mk2 (VEAF MCT 6.36.0, Skynet IADS 3.6.0 vendored)

## Intent

The mission is a set of SEAD/DEAD practice scenarios against SAM sites driven by Skynet IADS. Today
the red IADS is built automatically by VEAF's `veafSkynet.initialize()` (called from
`src/scripts/missionSkynetLogic.lua`): one network per coalition holding every red group whose
unit types Skynet knows, with point defences assigned by proximity.

We replace that with networks the mission builds itself, with plain Skynet, from group and unit
names:

- **Two red networks.** The Tbilisi scenario gets its own network with a working command center,
  so that the README's promise ("the command center of the network is in the area: destroying it
  will disrupt the IADS") becomes true **for Tbilisi only**. Every other scenario stays in a second
  network, without a command center, as today.
- **Explicit membership by name prefix** (Skynet's own mechanism), so what belongs to which network,
  and which site protects which, is readable in the Mission Editor.
- **Normalized names** for every red ground group, static and unit, which are inconsistent today.
- `missionSkynetLogic.lua` goes away; `src/scripts/mission-iads-init.lua` (exists, empty) replaces it.

## Goals

1. Two Skynet IADS objects for red: **TBS** (Tbilisi) and **MAP** (rest of the map).
2. TBS has a command center (`CommandCenterRed`) with a power source (the diesel generator at the
   same spot). Destroying **either** makes the TBS sites autonomous; MAP is unaffected.
3. Sites, EW radars and point defences are added by name, following the naming scheme below.
4. Every red ground group and red static follows one naming rule, and so do their units.
5. The F10 menu offers what "Skynet Red" offers today, per network.
6. At startup, the script logs what each network received and every red group it left out, so a
   naming mistake is visible in `dcs.log` instead of silently dropping a site.
7. Each existing scenario keeps the same sites in an IADS and the same escorts controlled by
   Skynet. Deliberate differences: the TBS command center now works; point defences protect the
   site they stand next to, as their names say (see "Point defences"); TBS and MAP no longer share
   radar coverage (see "Coverage").

## Non-goals

- Integrating map-marker spawns into the IADS (`veafSkynet.DynamicSpawn`): not needed for this mission.
- A blue IADS (`EWR - Blue` stays a plain DCS unit; today's `veafSkynet` blue network had nothing in it).
- Changing the composition or placement of any site.
- Updating the Skynet version, or the VMCT issues discussed earlier.
- Kneeboard images (they may show old names; out of scope).

## Anti-goals (a failure even if it "works")

- Destroying the Tbilisi command center affects any site outside Tbilisi.
- A site or escort silently missing from its network (wrong name, typo) with nothing in the log.
- Renaming something a VEAF mechanism depends on (see Constraints).
- Escorts that are in the IADS today becoming always-emitting plain AI.

## Constraints

- **Skynet 3.6.0 matching rules** (`src/scripts/skynet-iads-vendored.lua`):
  `addSAMSitesByPrefix` matches **group** names; `addEarlyWarningRadarsByPrefix` matches **unit**
  names; both require the prefix at position 1. Point defences must themselves be SAM sites of the
  same IADS (`samSite:addPointDefence(pd)`, also available on EW radars). `addCommandCenter(static)`
  returns the command-center element, which accepts `addPowerSource(static)`. Two IADS of the same
  coalition coexist.
- **VMCT loads every `.lua` in `src/scripts`, declared or not** (project memory). So
  `missionSkynetLogic.lua` must be **deleted**, not just removed from `custom_scripts`.
- Load order (mission.yaml): `veaf-config.lua` → `mission-script.lua` → `custom_scripts` in order.
  `skynet-iads-vendored.lua` must stay before `mission-iads-init.lua`.
- **Names that must not change:** `Qra_Tbilissi-1…7` (red QRA aircraft) and the `Qra_Tbilissi` zone
  (named in `veaf-config.lua`); the blue `veafSpawn-…` aircraft templates (generated from
  `src/spawnables.yaml`). Verified: no mission trigger and no other script references a red ground
  group or the two red statics by name. DCS triggers reference units by id anyway.
- `src/mission/mission` is the source of truth for units. It is written by `veaf-tools mission
  extract` (bare Lua keys). Renames are applied to this file; the normal round trip afterwards
  (build → Mission Editor → extract) must keep working.

## Approaches considered

- **A. Explicit Lua tables** listing each network's EWRs, sites and point defences by their current
  names. No renames, but ~40 names to type and keep in sync with the editor.
- **B. Strict Skynet prefixes** (chosen by the user). Groups and units are renamed so that the
  prefix says network and role; the script uses Skynet's prefix functions plus one rule to link
  point defences. Shortest script, the way Skynet is meant to be used, and the editor shows the
  structure. Cost: renaming the red side once.
- **C. Parse the current names** (`<site>` / `<site> - Sol-N`) and classify by unit type, borrowing
  VEAF's rules. Fewest renames, but more code and silent misses on typos.
- Rejected: keep `veafSkynet` with two named networks — brings back its 4,600 lines (spotters,
  sweeps, its own menu) for a job plain Skynet does.

## Naming scheme (decided)

Network prefixes: `TBS` (Tbilisi), `MAP` (rest of the map). Roles: `EW`, `SAM`, `PD`, `CC`.

| What | Group name | Unit names |
|---|---|---|
| EW radar site | `<NET>-EW <Site>` | identical to the group (one unit) |
| SAM site | `<NET>-SAM <Site>` | `<group>-01`, `-02`, … |
| Point defence of a site | `<NET>-PD <Site> #<n>` | `<group>-01`, … |
| Escort in the IADS, not a point defence | `<NET>-SAM <Site> #<n>` | `<group>-01`, … |
| Escort that is an EW radar (Dog Ear) | `<NET>-EW <Site> #<n>` | identical to the group |
| Escort outside the IADS | `<Site> #<n>` (no prefix) | `<group>-01`, … |
| AWACS (A-50) | `<NET>-EW Awacs <Place>` | identical to the group (one unit) |
| Command center (static) | `TBS-CC <Site>` | (static: unit name = group name) |
| CC power source (static) | `TBS-CC <Site> Power` | |

- `<Site>` = `<system> <place>` with a normalized system label: `SA-2`, `SA-5`, `SA-6`, `SA-10`,
  `SA-11`, `SA-15`, `SA-19`, `SA-22`, `HQ-7`, `IRIS-T`, `Rapier`; EW sites are just `<place>`
  (`TBS-EW Tbilissi`, `MAP-EW Sochi`). Place spellings are kept as in the mission (Tbilissi,
  Turquie, Dzhvari…), except where group and unit disagree (`EWR - Gelen` holds unit
  `EWR - Laza`: use the group's place).
- Sites that are already numbered keep their number in `<Site>` (`MAP-SAM SA-15 Dzhvari-4`).
- `#<n>` numbers each site's escorts from 1, in their current `Sol-N` order, across all roles (so a
  site's escorts never share a number). Today's duplicates are resolved by this renumbering
  (`SA-2 - Shahe - Sol-1` and `SA-2 - Shahe- Sol-1`).
- The parent of an escort is decided by its current name (`<site> - Sol-N`, with today's typos
  read as meant: `SA2 - Maykop - Sol-1` and `SA2- Maykop - Sol-2` belong to `SA-2 - Maykop`, not to
  `SA-6 - Maykop`; `SA11 Nadezhnaya - Sol-1` to `SA-11 - Nadezhnaya`).

### Role of each escort (decided)

By unit type, using Skynet's database (`samTypesDB` in the vendored script):

- **PD** if Skynet marks its type `can_engage_harm`: Tor M2 (`CHAP_TorM2`), Pantsir
  (`CHAP_PantsirS1`), C-RAM Phalanx (`HEMTT_C-RAM_Phalanx`).
- **EW** if Skynet classifies it as an EWR: Dog Ear radar.
- **SAM (in the IADS, not a PD)** if Skynet knows the type but it cannot engage HARMs: 2S6
  Tunguska, Gepard, ZSU-23-4 Shilka, lone SA-11 launchers (`SA-11 Buk LN 9A310M1`). This keeps
  today's behavior: `veafSkynet` adds every Skynet-known group, so Skynet controls their emissions.
- **Outside the IADS** if Skynet does not know any unit of the group: Igla teams, Ural trucks.

Main and standalone sites (SA-2/5/6/10/11, HQ-7, IRIS-T, Rapier, and the standalone SA-15, SA-19,
SA-22, SA-11 sites at Dzhvari and in Turquie) are `SAM`; the `EWR - …` groups are `EW`.

### Point defences (decided)

A point defence is linked to the site named in its escort name, which is the site it stands next
to. Today `veafSkynet` links by distance instead (nearest EWR within 10 km first), which produced
links nobody intended; they are **not** kept:

- `IRIS-T - Gelendzhik - Sol-1/2` (Pantsir, Tor; 0.1 km from the IRIS-T) defend the IRIS-T, not
  `EWR - Gelen` (2.9 km).
- `HQ7 - Dzhvari - Sol-1` (C-RAM; 0.2 km from the HQ-7) defends the HQ-7, not `SA11 - Dzhvari` (9.5 km).
- `SA-22 - Dzhvari` is a site of its own (`MAP-SAM SA-22 Dzhvari`), not a point defence of
  `SA-10 - Dzhvari` as it is today (user's call).

What a point defence does in Skynet: it is a SAM site of the network like any other, engaging any
threat as usual; on top of that, it goes live when a HARM targets the site it protects, which lets
that site stay live under HARM attack. It is not a "dark until a HARM comes" unit.

### AWACS (decided)

The four red A-50s are in the IADS today (`veafSkynet` counts AWACS as EWRs) and stay in it, as EW
radars matched by unit name:

| Today | New name | Network | Flies near |
|---|---|---|---|
| `Awacs #3` | `TBS-EW Awacs Tbilisi` | TBS | 36 km from SA-2 Vaziani |
| `Awacs #1` | `MAP-EW Awacs Mozdok` | MAP | 48 km from SA-5 Mozdok |
| `Awacs #2` | `MAP-EW Awacs Turkey` | MAP | 29 km from EWR Turquie |
| `Awacs #4` | `MAP-EW Awacs Dzhvari` | MAP | 73 km from SA-10 Dzhvari (name: my call) |

The places are the user's own words (`Tbilisi`, `Turkey`), not the mission's spellings
(`Tbilissi`, `Turquie`). These are the only red aircraft renamed: `Qra_Tbilissi-*` and
`veafSpawn-*` keep their names.

### Network membership (decided)

- **TBS:** everything within 18 km of `CommandCenterRed` — `EWR - Tbilissi`, `SA-2 - Tbilissi`,
  `SA-2 - Vaziani`, `SA5 - Tbilissi`, `SA10 - Martkobi`, `SA10 - Kumisi`, `SA19 - Tbilissi-1/2/3`,
  their escorts, `CommandCenterRed` and `Static Diesel Power Station 5I57A-1`. The next nearest red
  group is 208 km away, so there is no borderline case.
- **MAP:** every other red ground group.
- AWACS: see above (`Awacs #3` in TBS, the other three in MAP).

### Coverage (decided)

With one network today, the Tbilisi sites are probably also covered by distant EW radars
(`EWR - Kutaisi`, 208 km; the A-50s), and `EWR - Tbilissi` covers some MAP sites. After the split
each network only uses its own radars: killing TBS's radars (`EWR - Tbilissi`, its Dog Ear,
`TBS-EW Awacs Tbilisi`) leaves the Tbilisi sites without early warning, whatever MAP holds. This is
the intended concept (user's call). Coverage gaps, if any, are found in game testing and fixed
then (for instance by moving or adding a radar); the design does not try to compensate in advance.

The generator was probably placed as a stand-in for the bunker, which is hard to destroy in DCS.
Making it the power source keeps both as valid targets (user agreed).

## Script: `src/scripts/mission-iads-init.lua`

Builds the two networks, then the menu. Behavior:

1. For each network `NET` in {TBS, MAP}: `SkynetIADS:create(<display name>)`, then
   `addEarlyWarningRadarsByPrefix(NET .. "-EW")` and `addSAMSitesByPrefix(NET .. "-SAM")`.
2. For each red group whose name starts with `NET .. "-PD "`: add it with `addSAMSite(name)`; strip
   the `NET-PD ` prefix and the trailing ` #<n>` to get `<Site>`; the parent is the SAM site
   `NET-SAM <Site>`, else the EW radar `NET-EW <Site>`; call `parent:addPointDefence(pd)`.
   No parent found → warning in the log, the group stays a plain SAM site of the network.
3. TBS only: `addCommandCenter(StaticObject.getByName("TBS-CC Tbilissi"))` and
   `:addPowerSource(StaticObject.getByName("TBS-CC Tbilissi Power"))`.
4. Activate both IADS.
5. Startup report (info level): per network, the EW radars, SAM sites and point defences (with
   their parent) it holds; then every red ground group, and every red aircraft except
  `Qra_Tbilissi-*` and `veafSpawn-*`, that is in no network. Warnings for: a
   prefixed group Skynet refused (no usable unit), a PD without parent, a red group whose name
   starts with neither prefix but whose units Skynet knows (likely a typo).
6. Settings mirrored from today's `missionSkynetLogic.lua` / `veafSkynet` defaults where Skynet
   offers them: debug output off unless a `DebugMode` flag at the top of the file is set.

### F10 menu (my call, mirrors today's "Skynet Red")

One submenu per network, `IADS Tbilissi` and `IADS Map`, each with:

- Display/hide Skynet status (toggles the same debug settings `SkynetNetworkDisplayState` sets today).
- Deactivate network: the IADS stops and every site goes live and fights on its own (today's
  `deactivateNetworkOfCoalition(..., Live)` semantics).

`IADS Tbilissi` adds **Disable network (destroy CC)**: explode the command center (today's
`destroyCommandCentersOfCoalition`). Commented-out entries of today's menu are not carried over,
and neither are the "Network desc to log" commands (user's call): the script no longer uses
`VeafSkynetMonitorDescriptor` or anything else from `veafSkynet`/`veafSkynetMonitor`.

## Renaming the mission (my call on the how)

A one-off, standard-library Python script `tools/rename-red-iads.py` applies a mapping table
`tools/red-iads-names.csv` (old group name, new group name, network, role, and per-unit old → new)
to `src/mission/mission`:

- The CSV is generated first from the rules above, committed, and **reviewed by the user before
  it is applied**. It is the place to catch a wrong role or parent.
- The script replaces only `name = "<old>"` entries that belong to a red ground group, a red
  static, one of the four A-50 groups, or one of their units (it walks the Lua structure, not a blind text replace); it refuses
  to run if an old name is missing or ambiguous, or if a new name collides.
- Waypoint names that copied the group name may stay as they are (not used by anything).

Then: build, check the `.miz` in DCS, and do one Mission Editor round trip (open, save, `mission
extract`) to confirm the renamed file is stable.

## Other changes

- Delete `src/scripts/missionSkynetLogic.lua`; in `mission.yaml`, replace it in `custom_scripts`
  with `src/scripts/mission-iads-init.lua` (after `skynet-iads-vendored.lua`).
- Remove the now-unused `veafSkynet.DynamicSpawn` / `veafSkynet.DelayForStartup` lines from
  `module_settings`; keep `SKYNET: false` and `SKYNET_MONITOR: false`.
- README: describe the two networks, the naming scheme, and the TBS command center/generator.

## Verification (in DCS, hotload available for live checks)

- `dcs.log`: Skynet 3.6.0 loads once; the startup report lists the expected sites per network and
  no unexpected "in no network" group (only Igla/Ural escorts).
- F10: two submenus; each command works.
- Destroy the generator (or use the menu): TBS sites go autonomous; a MAP site (e.g. SA-10 Gudauta)
  still reacts as part of its IADS.
- A HARM at SA-10 Gudauta wakes its Tor point defence, and the SA-10 keeps emitting.
- The four A-50s appear as EW radars in the startup report, in the right network.
- Coverage: note any site that goes autonomous unexpectedly (gap left by the split), for follow-up.
- QRA Tbilissi and the marker toolbox still work.

## Left to the builder

- Exact Lua structure, logging format, display names of the IADS objects.
- How "deactivate network" is implemented with Skynet's API, as long as the semantics above hold.
- Whether the rename script and CSV stay in `tools/` afterwards (default: yes, for traceability).
