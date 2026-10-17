BLENDER ?= blender
GODOT   ?= godot
GLB     := godot/assets/dice.glb

.PHONY: all run test import export test-export clean

all: $(GLB)

## Blender -> glTF: rebuild the die mesh whenever the generator changes.
$(GLB): blender/make_dice.py
	$(BLENDER) --background --python $< -- $(CURDIR)/$@
	$(GODOT) --headless --path godot --import

import: $(GLB)
	$(GODOT) --headless --path godot --import

## Play it.
run: $(GLB)
	XMODIFIERS= $(GODOT) --path godot

## Headless fairness check: 120 rolls, every face must come up.
test: $(GLB)
	$(GODOT) --headless --path godot --fixed-fps 60 tests/roll_test.tscn

## Save a frame of the running sim to shot.png (needs a display).
shot: $(GLB)
	XMODIFIERS= $(GODOT) --path godot tests/shot.tscn -- $(CURDIR)/shot.png

## Standalone Linux binary with the game embedded, in build/.
export: $(GLB)
	mkdir -p build
	$(GODOT) --headless --path godot --export-release Linux

## Drive the exported binary headless over its remote-input socket.
test-export: export
	python3 godot/tests/export_test.py build/dice-sim.x86_64

clean:
	rm -rf godot/.godot $(GLB) shot.png build
