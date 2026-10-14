# Third-party component

`l4d_CreateSurvivorBot` supplies a native API for creating a real SurvivorBot
actor. The chakra plugin uses it only for a temporary non-solid illusion.

- Authors: MicroLeo, Dragokas (port), Harry.
- Upstream: https://github.com/fbef0102/L4D1_2-Plugins/tree/74e66e3d4a0892b1fde632c32b11e12ac329026c/l4d_CreateSurvivorBot
- Version: `1.0h-2024/12/13`.
- License: GNU GPL v3, included as `LICENSE`.
- Included unchanged: `scripting/l4d_CreateSurvivorBot.sp`,
  `scripting/include/l4d_CreateSurvivorBot.inc`,
  `gamedata/l4d_CreateSurvivorBot.txt` under `addons/sourcemod`.
- The shipped `.smx` is compiled from the included source using SourcePawn 1.12.
  No upstream precompiled plugin is used.

The upstream gamedata contains engine signatures. Correct compilation cannot
validate those signatures against a particular game binary; check helper
loading in `sm plugins list` on the actual L4D2 server. If it fails, clone
activation is rejected before spending chakra; the other techniques remain
available. Do not edit signatures blindly or fabricate successful validation.

The SaSx project is distributed under the accompanying GPL v3 license.
