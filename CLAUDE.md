# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

    make          # regenerate godot/assets/dice.glb if make_dice.py changed, then reimport
    make run      # play the sim (needs a display)
    make test     # headless fairness check: 120 rolls, fails if any face never comes up
    make shot     # run the sim ~3s and save a frame to shot.png (needs a display)
    make import   # force a Godot asset reimport
    make export   # standalone Linux x86_64 binary at build/dice-sim.x86_64
    make test-export  # export, then drive the binary headless over a socket (1-5 dice, every input)
    make clean    # drop godot/.godot, the GLB, shot.png and build/

Override the binaries with `make GODOT=/path/to/godot BLENDER=/path/to/blender`.

There is one test scene, so `make test` is also how you run a single test. To run
it directly, or to iterate on it:

    godot --headless --path godot --fixed-fps 60 tests/roll_test.tscn

`--fixed-fps` decouples the engine from wall-clock time, so 120 physics rolls
finish in seconds instead of minutes. Without it the test runs in real time.
Roll count and the per-roll settle timeout are constants at the top of
`tests/roll_test.gd`.

Developed against Blender 5.2 and Godot 4.7.

`make export` needs the official Godot export templates for the exact engine
version (here `~/.local/share/godot/export_templates/4.7.2.stable/`, Linux
x86_64 only). The preset in `godot/export_presets.cfg` embeds the pack in the
binary and excludes `tests/`.

Because `tests/` is not shipped, `make test-export` drives the binary from
outside: `tests/export_test.py` listens on a localhost port and launches the
game with `-- --remote-input=127.0.0.1:PORT`. The `RemoteInput` autoload
(`scripts/remote_input.gd`) is inert without that flag; with it, it connects
out, holds the game paused until `resume`, and turns line commands (`key`,
`click`, `wait`, `get`, `watch`) into input events and replies. It knows
nothing about dice; the test relies on `main.gd`'s `rolled(results)` signal.

## Architecture

Two stages with a generated artifact between them:

    blender/make_dice.py  --(GLB)-->  godot/assets/dice.glb  -->  Godot scenes

`godot/assets/dice.glb` is **generated output and is gitignored**, so a fresh
checkout has no mesh until `make` runs — assume it may be missing rather than
reading it as a fixture. Never hand-edit it; change `make_dice.py` and re-run
`make`. Godot caches imports, so a new GLB needs `--import` before it takes
effect, which the `make` targets already do.

The export is **not byte-reproducible** — Blender's EXACT boolean solver orders
vertices differently run to run, so two builds of identical source differ in the
binary buffer while the glTF JSON stays identical. That is why the mesh is not
committed, and why you cannot diff two GLBs to check whether a change had an
effect; compare the JSON chunk or render a frame instead.

`godot/assets/dice.glb.import` **is** tracked, and stays byte-identical across
regeneration. It pins `uid://dgmrqp1c04rfl`, and the scenes reference the mesh
by path anyway, so import settings survive a rebuild.

`die.gd` owns one die: it throws itself, watches for rest, and reports the face
pointing up by taking whichever local axis has the largest dot product with
world up. `main.gd` owns the session: it spawns dice, routes input, tallies the
total, and does not know how a face is read. Dice report upward through the
`settled(value)` signal.

### Face mapping spans two files

`STANDARD_D6` in `make_dice.py` decides which face gets which pip count;
`FACE_VALUES` in `die.gd` decodes it. The glTF export is Y-up while Blender
is Z-up, so the mapping is rotated between them (Blender +Z becomes Godot +Y). Changing the
layout in one file requires updating the other, or the sim silently reports
wrong numbers. The resulting table is in README.md.

To verify a change, render a frame with `make shot` and check that the pips
visible on top match the on-screen readout. `make test` only proves all six
faces occur, not that they are labelled correctly.

### Arena geometry is defined twice

`scenes/main.tscn` builds the table and walls as nodes; `tests/roll_test.gd`
`_build_table()` rebuilds an equivalent arena in code so the test does not drag
in the camera, lighting and UI. Resize one and you must resize the other, or the
test stops exercising the geometry the game actually uses.

## Gotchas that have already cost time here

**`.tscn` `Transform3D` floats are row-major**, i.e. the transpose of three
consecutive axis vectors: the order is `(x.x, y.x, z.x, x.y, y.y, z.y, ...)`.
Writing axes as consecutive triples silently aims cameras and lights the wrong
way. To get correct values, build the transform in code with `look_at()` and
print `var_to_str(node.global_transform)`, then paste that in.

**Blender's boolean modifier defaults to `material_mode = 'INDEX'`**, which
clamps the cutter's material to the target's slot 0 and renders the pips white.
`make_dice.py` sets `'TRANSFER'` so the carved faces take the black material
from the cutter object. If pips ever come out the wrong colour, check that
setting first — the symptom looks like a UV or shading bug but is neither.

**The modifier stack is never applied.** The exporter's `export_apply=True`
evaluates it, so the bevel and boolean stay live and the die is still editable
as a cube. Code that needs the *carved* geometry (rather than the base cube)
must evaluate the depsgraph itself; reading `body.data` gives you a plain cube.

**Gravity is 18**, not 9.8, in `project.godot`. A 1-unit die under Earth gravity
drifts down like a beach ball. Throw strength, spin and rest thresholds in
`die.gd` are tuned against this value; changing gravity means retuning them and
re-running `make test`.

**Impact sounds come from velocity deltas**, not contact signals: `die.gd`
treats any per-tick change in `linear_velocity` beyond gravity as a hit. Anything
that sets velocity or applies an impulse on purpose (`roll()`, the cocked-die
nudge) must set `_quiet_ticks`, or it plays a phantom knock. The sounds use a
private RNG in the `DiceSounds` autoload so they never perturb the seeded roll
sequence in `roll_test.gd`. Under `--fixed-fps` the audio thread falls behind,
which is why the test's `quit()` pauses before exiting; without that pause,
finished playbacks show up as leaked instances.

**A die can land cocked** on an edge or against a wall. `top_face()` returns 0
when no axis is within ~45° of up, and `die.gd` nudges the die rather than
reporting a bogus value, so the settle logic must tolerate a roll that takes
several attempts to resolve.
