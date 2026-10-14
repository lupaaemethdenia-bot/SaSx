#!/usr/bin/env python3
"""Build and package the plugin using a supplied SourceMod SDK (Windows/Linux)."""

import argparse
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "addons/sourcemod/scripting/l4d2_chakra.sp"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sourcemod", required=True, type=Path,
                        help="Path to addons/sourcemod, or an SDK checkout with plugins/include")
    parser.add_argument("--compiler", type=Path, help="Override spcomp/spcomp64 executable")
    args = parser.parse_args()
    sdk = args.sourcemod.resolve()
    includes = sdk / "scripting/include"
    if not (includes / "sourcemod.inc").is_file():
        includes = sdk / "plugins/include"
    if not (includes / "sdkhooks.inc").is_file():
        parser.error("SourceMod includes not found at the supplied path")
    compiler = args.compiler
    if compiler is None:
        compiler = next((p for name in ("spcomp.exe", "spcomp64", "spcomp")
                         if (p := sdk / "scripting" / name).is_file()), None)
    if compiler is None or not compiler.is_file():
        parser.error("Compiler not found; specify --compiler")

    output = ROOT / "dist"
    output.mkdir(exist_ok=True)
    binary = output / "l4d2_chakra.smx"
    # Never package a stale binary if compilation fails.
    binary.unlink(missing_ok=True)
    archive = output / "l4d2-chakra-prototype.zip"
    archive.unlink(missing_ok=True)
    subprocess.run([str(compiler.resolve()), str(SOURCE), f"-i{includes}",
                    f"-o{binary}", "--warnings-as-errors"], cwd=ROOT, check=True)
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as package:
        package.write(binary, "addons/sourcemod/plugins/l4d2_chakra.smx")
        for relative in (
            "cfg/sourcemod/l4d2_chakra.cfg",
            "addons/sourcemod/scripting/l4d2_chakra.sp",
            "addons/sourcemod/scripting/include/chakra_core.inc",
            "README.md",
            "docs/TESTING.md",
            "tools/build.py",
            "tools/bootstrap-linux.sh",
            "tools/test.py",
            "tests/chakra_core_test.sp",
        ):
            package.write(ROOT / relative, relative)
    print(f"Plugin: {binary}")
    print(f"Install archive: {archive}")


if __name__ == "__main__":
    main()
