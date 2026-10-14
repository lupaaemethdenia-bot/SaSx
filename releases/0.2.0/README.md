# Chakra 0.2.0

Four techniques: the original fireball, a non-solid illusion SurvivorBot,
a three-second wide fire cone and a ten-second Rasengan with a shared damage
threshold. Each character receives three fixed random techniques per map.

[Download ZIP](https://github.com/lupaaemethdenia-bot/SaSx/raw/refs/heads/chakra-prototype/releases/0.2.0/l4d2-chakra-0.2.0.zip).
Update the `addons` folder in the game/server's `left4dead2` directory.
Keep your existing personal cfg. Full instructions are in the root README.

The ZIP includes the small CreateSurvivorBot helper, its source, engine
gamedata and GPL license. This helper is required for the clone and needs a
free client slot. Provenance: THIRD_PARTY.md.

Validation: both plugins compile with SourcePawn 1.12 with warnings treated as
errors. 30 chakra assertions and 405 technique assertions pass in the
official SourcePawn VM (435 total). ZIP contents and binaries are verified.
Actual 0.2.0 game behavior, helper signatures, clone AI, effects, and multiplayer
performance have not yet been tested on L4D2. See docs/TESTING.md.

Visual effects and hand-seal animations remain a later stage; ordinary game
resources are used for this mechanics build.
