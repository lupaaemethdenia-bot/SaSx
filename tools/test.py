#!/usr/bin/env python3
"""Execute the production gameplay math in the official SourcePawn VM."""

import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEFAULT = ROOT / ".toolchain"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path,
                        default=DEFAULT / "build/spcomp/linux-x86_64/spcomp")
    parser.add_argument("--shell", type=Path,
                        default=DEFAULT / "build/spshell/linux-x86_64/spshell")
    parser.add_argument("--sourcepawn", type=Path, default=DEFAULT / "sourcepawn")
    args = parser.parse_args()
    for path in (args.compiler, args.shell, args.sourcepawn / "tests/shell.inc"):
        if not path.is_file():
            parser.error(f"Missing toolchain file: {path}; run tools/bootstrap-linux.sh")
    output = ROOT / "dist/tests"
    output.mkdir(parents=True, exist_ok=True)
    binary = output / "chakra_core_test.smx"
    binary.unlink(missing_ok=True)
    subprocess.run([str(args.compiler.resolve()), str(ROOT / "tests/chakra_core_test.sp"),
                    f"-i{args.sourcepawn.resolve() / 'tests'}",
                    f"-i{args.sourcepawn.resolve() / 'include'}",
                    f"-o{binary}", "--warnings-as-errors"], cwd=ROOT, check=True)
    result = subprocess.run([str(args.shell.resolve()), str(binary)], check=True,
                            text=True, capture_output=True)
    print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
    if "PASS:" not in result.stdout:
        raise SystemExit("Test main did not report completion")


if __name__ == "__main__":
    main()
