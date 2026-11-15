# IADS-Caucasus - Mk2

## The mission

This mission provides quick scenarios to practice engaging, evading and destroying air defence systems that are part of an IADS managed by Skynet.
In addition to the ready-to-fire air starts, some free ground slots are available in Krasnodar and Kutaisi.

Check your kneeboard for target coordinates and maps.

*SA-2 defended. SA-2 sites with SA-15 point defences, deployed between Maykop and Shahe.

*SA-2 undefended. SA-2 sites with no defences along the coast between Batumi and Poti.

*SA-10. Full SA-10 sites with SA-15 point defences. One at Zelen for an over ground approach, one near Gudauta for an over water approch. A trickier one at Dzhvari with a protected approach and additional C-RAM defences.

*SA-5. One SA-5 in Mozdok.

*TALD training. SA-19 and SA-15 sites on the Turkish coast to experiment with TALD timings.

*SLAM-ER training. SA-11 near Nadezhnaya.

*Tbilisi. For a challenge, the Tbilisi zone is fully defended by SAM defences (SA-2, SA-5, SA-10 and more). It is an IADS of its own, separate from the rest of the map, and its command center is in the area: destroying the command center bunker, or the diesel generator next to it that powers it, will disrupt the Tbilisi IADS (its sites go autonomous). The other scenarios are not affected.

The F10 menus "IADS Tbilissi" and "IADS Map" show or hide the Skynet status of each network and can deactivate it (every site then fights on its own); "IADS Tbilissi" can also blow up the command center.

## Building the mission

Built with [VEAF Mission Creation Tools](https://github.com/VEAF/VEAF-Mission-Creation-Tools) v6 and [Skynet IADS](https://github.com/VEAF/Skynet-IADS) 3.6.0.

```powershell
.\veaf-tools-updater.exe                         # install / update the VEAF tools and scripts (published/)
python build.py                                  # IADS-Caucasus_<date>.miz, ready to hand out
python build.py --hotload                        # same, but it boots dcs-hotload on this machine
```

VEAF MCT v6 has no post-build hook, so `build.py` runs `.\veaf-tools.exe mission build` (other options, such as `--profile X`, are passed through), then this mission's post-build step on each `.miz` it wrote: `python dcs-hotload/bin/hotload-setup.py boot-path --miz <miz> --clear`, unless `--hotload`.

- `mission.yaml` — enabled modules (Skynet, QRA, map-marker toolbox), scripts, build steps.
- `src/mission/` — the mission as saved by the DCS Mission Editor. After editing a built `.miz` in the editor, extract it back with `.\veaf-tools.exe mission extract <file>.miz .`. If that `.miz` came from `python build.py --hotload`, first run `python dcs-hotload/bin/hotload-setup.py boot-path --miz <file>.miz --clear`: otherwise the extract brings this machine's `BASE_HOTLOAD_PATH` into `src/mission/`, where it would be committed (`build.py` clears it in the `.miz` it writes, but a bare `.\veaf-tools.exe mission build` would keep it).
- `src/scripts/` — `skynet-iads-vendored.lua` (Skynet IADS 3.6.0) and `mission-iads.lua` (builds the two red networks from names, logs a `MISSION IADS:` report to `dcs.log`, adds the F10 menus). The mission loads and starts Skynet itself: VEAF MCT's SKYNET module is off, so the Skynet it bundles is not in the `.miz`. Keep SKYNET and SKYNET_MONITOR off in `mission.yaml`, otherwise VMCT loads its own copy as well. To update Skynet, replace `skynet-iads-vendored.lua` with the new release's compiled script. VMCT loads every `.lua` in `src/scripts/`, so keep nothing else there.
- `tools/` and `tests/` — `check_red_iads_names.py`, which checks the red names against the scheme below, and the tests (`python -m unittest discover -s tests/python`, `lua tests/lua/test_iads_init.lua` from the repo root).

### Red IADS naming

The IADS is built from names, so red ground units must follow this scheme (network `TBS` = Tbilisi, `MAP` = the rest of the map):

| What | Group name | Unit names |
|---|---|---|
| EW radar | `<NET>-EW <Site>` | same as the group (Skynet matches EW radars by **unit** name) |
| SAM site | `<NET>-SAM <Site>` | `<group>-01`, `-02`… |
| Point defence of a site | `<NET>-PD <Site> #<n>` | `<group>-01`… |
| Escort in the IADS (SHORAD, Dog Ear) | `<NET>-SAM <Site> #<n>` / `<NET>-EW <Site> #<n>` | as above |
| Escort outside the IADS (Igla, trucks) | `<Site> #<n>` | `<group>-01`… |
| A-50 | `<NET>-EW Awacs <Place>` | same as the group |
| Tbilisi command center / its generator | `TBS-CC Tbilissi` / `TBS-CC Tbilissi Power` | |

`<Site>` is `<system> <place>` (`SA-10 Gudauta`), or just `<place>` for an EW site. A point defence protects the site whose name follows its `PD` (`MAP-PD SA-10 Gudauta #1` protects `MAP-SAM SA-10 Gudauta`). After editing red units in the Mission Editor and extracting, run `python tools/check_red_iads_names.py src/mission/mission`: it catches what the game does not report, such as a copied `TBS-EW` group whose unit kept its old name (Skynet then silently skips that radar); the `MISSION IADS:` lines in `dcs.log` also list every red group left out of the IADS.

### dcs-hotload

[dcs-hotload](https://github.com/MacFlorent/dcs-hotload) 3.1.0 lives in `dcs-hotload/`, outside the VEAF framework: the mission's own MISSION START trigger "dcs-hotload boot" (in `src/mission/`, written by dcs-hotload's `patch-miz`) sets `BASE_HOTLOAD_PATH` to that folder and loads `dcs-hotload.lua` from it. When the value is empty or the file cannot be loaded (any machine but this one), it writes `HOTLOAD: not booted: <why>` to `dcs.log` and does nothing else. Where the folder is there but DCS's `Scripts/MissionScripting.lua` is not unlocked, hotload itself loads and says on screen that `io`/`lfs` are missing.

The value is managed with `dcs-hotload/bin/hotload-setup.py`, which ships in the copy (dcs-hotload 3.1.0+; run this copy, not the plugin's, since `patch-miz` and `boot-path --set` point the mission at the copy they run from):

```powershell
python dcs-hotload/bin/hotload-setup.py status --dcs <DCS World folder>                  # copy, unlock, boot trigger
python dcs-hotload/bin/hotload-setup.py boot-path --miz IADS-Caucasus_<date>.miz           # show it
python dcs-hotload/bin/hotload-setup.py boot-path --miz IADS-Caucasus_<date>.miz --clear   # empty it
python dcs-hotload/bin/hotload-setup.py boot-path --miz IADS-Caucasus_<date>.miz --set     # point it back at this copy
```

If a `.miz` with the value set goes out anyway, players only get the log line. To change the trigger itself (after moving this folder, for instance), treat it like any Mission Editor edit: `python build.py --hotload`, run `hotload-setup.py patch-miz --miz <file>.miz` or `boot-path --miz <file>.miz --set`, then `.\veaf-tools.exe mission extract <file>.miz .` brings it into `src/mission/`.
