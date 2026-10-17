# Dice Sim

A physics dice roller. The die mesh is generated in Blender by script, exported
as GLB, and rolled by Godot's rigid-body physics on Linux.

    Blender (make_dice.py) --> glTF/GLB --> Godot 4 --> Linux

## Run it

    make run      # build the mesh if needed, then play
    make test     # headless: 120 rolls, checks every face comes up
    make shot     # save a frame to shot.png

Space or click rolls. Keys `1`-`5` change how many dice. Esc quits.

The mesh is **not** in the repository — it is generated, so a fresh clone needs
Blender on PATH and one `make` before the project will open in Godot.

Built against Blender 5.2 and Godot 4.7. Override with `make GODOT=/path/to/godot`.

## Layout

    blender/make_dice.py   die spec + builder, writes godot/assets/dice.glb
    godot/assets/dice.glb  generated mesh -- gitignored, rebuilt by make
    godot/scenes/die.tscn  RigidBody3D + box collider wrapping the GLB
    godot/scenes/main.tscn table, camera, light, UI
    godot/scripts/die.gd   throws the die, reports the face pointing up
    godot/scripts/main.gd  spawns dice, handles input, totals the result
    godot/scripts/dice_sounds.gd  autoload: synthesises the impact sounds
    godot/tests/           headless fairness check and screenshot helper

## How the die is made

The die is a data description — `STANDARD_D6`, giving size, bevel, pip
geometry, materials and the per-face pip layout — plus a builder that realises
it. To change the die, edit the spec, not the builder.

The builder makes a cube and one mesh holding all 21 pip spheres, then declares
a bevel and a boolean difference as modifiers. Nothing is applied: the glTF
exporter evaluates the stack via `export_apply`, so the die stays editable and
the script keeps no selection or active-object state. The boolean uses
`material_mode = 'TRANSFER'` so the carved pips take the black material
directly from the cutter object.

## Face numbering

Faces are laid out so opposite sides sum to 7. The glTF export converts
Blender's Z-up to Y-up, which rotates the mapping; `die.gd` encodes the result:

| Godot axis | +Y | -Y | +X | -X | +Z | -Z |
|------------|----|----|----|----|----|----|
| value      | 1  | 6  | 3  | 4  | 5  | 2  |

`die.gd` reads the roll by taking whichever local axis has the largest dot
product with world up. A die resting on an edge matches no axis within
tolerance, so it gets nudged and allowed to fall flat rather than reported.

## Sound

There are no audio files. The `DiceSounds` autoload renders a small bank of
impact sounds at startup by modal synthesis: a short noise burst for the
contact plus a few exponentially decaying sine modes for whatever rings
afterwards. There are three families: a dull thud on the felt, a hollow knock on
the wooden rails, and a bright clack when two dice hit each other.

Each die listens for impacts by comparing its velocity tick to tick. Any change
beyond what gravity explains came from a contact, and its size sets the volume.
Horizontal kicks read as a wall and vertical ones as the felt; touching another
die overrides both. The recipes are in `_recipe()` in `dice_sounds.gd`, and the
sensitivity constants (`IMPACT_*`) are at the top of `die.gd`.

## Tuning

Mesh proportions (bevel, pip size, depth, spread) are fields of the `Die`
dataclass in `make_dice.py`; re-run `make` after changing them. Throw strength, spin and the
rest thresholds are constants at the top of `die.gd`. Gravity is set to 18 in
`project.godot` — heavier than Earth, so a 1-unit die settles quickly instead
of drifting like a beach ball.
