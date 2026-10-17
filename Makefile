BLENDER ?= blender
GODOT   ?= godot
GLB     := godot/assets/dice.glb

.PHONY: all run test import clean

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

clean:
	rm -rf godot/.godot $(GLB) shot.png
