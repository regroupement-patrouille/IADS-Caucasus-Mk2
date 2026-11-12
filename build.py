"""build.py -- build the mission with VEAF MCT v6, then run this mission's post-build steps.

    python build.py [--hotload] [veaf-tools mission build options...]

1. `veaf-tools.exe mission build`, with any option not listed here passed through (`--profile X`,
   `--verbose`, ...). VEAF MCT v6 has no post-build hook, hence this script.
2. On every .miz that build wrote: `dcs-hotload/bin/hotload-setup.py boot-path --miz <miz> --clear`, so
   the "dcs-hotload boot" trigger names no folder of this machine and only logs "HOTLOAD: not booted".
   With --hotload, `--set` instead: the path names this machine's dcs-hotload/ copy and the .miz boots it,
   whatever src/mission/ holds: for local testing, not for handing out.

hotload-setup.py ships in the mission's copy of dcs-hotload (3.1.0+), dcs-hotload/bin/; its command line is
dcs-hotload's public interface from 3.1.0 on. Without it the build still runs and the path is left in the
.miz, which dcs-hotload says is safe to share (the folder is missing on other machines); a warning says so.

Python 3.8+, standard library only. Run from anywhere: paths are taken from this file's folder.
Exit code: veaf-tools' own when the build fails, else hotload-setup.py's (0 when every step passed).
"""

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VEAF_TOOLS = ROOT / "veaf-tools.exe"
HOTLOAD_SETUP = ROOT / "dcs-hotload" / "bin" / "hotload-setup.py"


def snapshot():
    """Each .miz of the mission folder, with what tells a rewrite: modification time and size."""
    return {p: (s.st_mtime_ns, s.st_size) for p in ROOT.glob("*.miz") for s in [p.stat()]}


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0], allow_abbrev=False,
                                     epilog="Other options go to veaf-tools.exe mission build.")
    parser.add_argument("--hotload", action="store_true",
                        help="set BASE_HOTLOAD_PATH to this machine's dcs-hotload: the .miz boots it here")
    args, passthrough = parser.parse_known_args()

    if not VEAF_TOOLS.is_file():
        print(f"build.py: no {VEAF_TOOLS.name} -- run .\\veaf-tools-updater.exe first", file=sys.stderr)
        return 1

    before = snapshot()
    print(f"build.py: veaf-tools.exe mission build {' '.join(passthrough)}", flush=True)
    code = subprocess.call([str(VEAF_TOOLS), "mission", "build", *passthrough], cwd=ROOT)
    if code != 0:
        print(f"build.py: veaf-tools.exe failed (exit {code})", file=sys.stderr)
        return code

    after = snapshot()
    written = sorted((p for p in after if before.get(p) != after[p]), key=lambda p: after[p][0])
    if not written:
        print(f"build.py: the build wrote no .miz in {ROOT}", file=sys.stderr)
        return 1

    if not HOTLOAD_SETUP.is_file():
        print(f"build.py: WARNING no dcs-hotload/bin/hotload-setup.py (dcs-hotload 3.1.0+ ships it):"
              f" BASE_HOTLOAD_PATH left as in src/mission/", file=sys.stderr)
        return 0

    result = 0
    for miz in written:
        print(f"build.py: hotload {'set in' if args.hotload else 'cleared in'} {miz.name}", flush=True)
        code = subprocess.call([sys.executable, "-I", str(HOTLOAD_SETUP), "boot-path", "--miz", str(miz),
                                "--set" if args.hotload else "--clear"], cwd=ROOT)
        result = result or code
        if args.hotload:
            print(f"build.py: local build -- before handing it out:"
                  f" python dcs-hotload/bin/hotload-setup.py boot-path --miz {miz.name} --clear")
    return result


if __name__ == "__main__":
    sys.exit(main())
