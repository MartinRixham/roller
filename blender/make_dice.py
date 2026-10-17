"""Generate a six-sided die and export it as GLB.

Run headless:
    blender --background --python blender/make_dice.py -- godot/assets/dice.glb

The die is described as data (STANDARD_D6) and realised by a builder that
touches no selection or active-object state: geometry is built with bmesh,
and the bevel and pip boolean stay as live modifiers that the glTF exporter
evaluates via export_apply. The only operators left are scene reset, shading
and export.

Face values follow the standard convention, opposite faces summing to 7:
    +Z = 1   -Z = 6   +Y = 2   -Y = 5   +X = 3   -X = 4
The export is Y-up, which rotates that mapping; see die.gd.
"""

import sys
from math import radians
from dataclasses import dataclass

import bpy
import bmesh
from mathutils import Matrix, Vector


# ---------------------------------------------------------------- spec


@dataclass(frozen=True)
class Material:
    name: str
    color: tuple
    roughness: float


@dataclass(frozen=True)
class Face:
    """One face of the die: which way it points, and where its pips sit.

    `pips` are (u, v) in units of `Die.pip_spread`, on the plane spanned
    by `u_axis` and `v_axis`.
    """
    normal: tuple
    u_axis: tuple
    v_axis: tuple
    pips: tuple


@dataclass(frozen=True)
class Die:
    size: float = 1.0
    bevel_width: float = 0.06
    bevel_segments: int = 4
    pip_radius: float = 0.085
    pip_depth: float = 0.045
    pip_spread: float = 0.22
    pip_segments: tuple = (24, 12)
    body: Material = Material("DieBody", (0.92, 0.91, 0.88), 0.35)
    pip: Material = Material("DiePips", (0.03, 0.03, 0.04), 0.5)
    faces: tuple = ()


CORNERS = ((-1, -1), (-1, 1), (1, -1), (1, 1))
LAYOUT = {
    1: ((0, 0),),
    2: ((-1, -1), (1, 1)),
    3: ((-1, -1), (0, 0), (1, 1)),
    4: CORNERS,
    5: CORNERS + ((0, 0),),
    6: ((-1, -1), (-1, 0), (-1, 1), (1, -1), (1, 0), (1, 1)),
}

# Opposite faces sum to 7.
STANDARD_D6 = Die(faces=(
    Face((0, 0, 1), (1, 0, 0), (0, 1, 0), LAYOUT[1]),
    Face((0, 0, -1), (1, 0, 0), (0, -1, 0), LAYOUT[6]),
    Face((0, 1, 0), (1, 0, 0), (0, 0, 1), LAYOUT[2]),
    Face((0, -1, 0), (-1, 0, 0), (0, 0, 1), LAYOUT[5]),
    Face((1, 0, 0), (0, -1, 0), (0, 0, 1), LAYOUT[3]),
    Face((-1, 0, 0), (0, 1, 0), (0, 0, 1), LAYOUT[4]),
))


# ------------------------------------------------------------- builder


def material(spec: Material) -> bpy.types.Material:
    mat = bpy.data.materials.new(spec.name)   # node-based by default
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*spec.color, 1.0)
    bsdf.inputs["Roughness"].default_value = spec.roughness
    return mat


def mesh_object(name: str, bm: bmesh.types.BMesh, mat) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def body_mesh(die: Die) -> bmesh.types.BMesh:
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=die.size)
    return bm


def pip_centres(die: Die):
    """Every pip's centre, in object space."""
    offset = die.size / 2.0 - die.pip_depth + die.pip_radius
    for face in die.faces:
        base = Vector(face.normal) * offset
        u, v = Vector(face.u_axis), Vector(face.v_axis)
        for du, dv in face.pips:
            yield base + u * (du * die.pip_spread) + v * (dv * die.pip_spread)


def pip_mesh(die: Die) -> bmesh.types.BMesh:
    """All pip cutters in a single mesh -- no join step."""
    bm = bmesh.new()
    u_seg, v_seg = die.pip_segments
    for centre in pip_centres(die):
        bmesh.ops.create_uvsphere(
            bm,
            u_segments=u_seg,
            v_segments=v_seg,
            radius=die.pip_radius,
            matrix=Matrix.Translation(centre),
        )
    for face in bm.faces:
        face.smooth = True
    return bm


def build(die: Die) -> bpy.types.Object:
    body = mesh_object("Die", body_mesh(die), material(die.body))
    cutters = mesh_object("Pips", pip_mesh(die), material(die.pip))
    cutters.hide_viewport = True   # kept out of the export; the boolean still reads it

    bevel = body.modifiers.new("Bevel", "BEVEL")
    bevel.width = die.bevel_width
    bevel.segments = die.bevel_segments
    bevel.limit_method = "ANGLE"

    carve = body.modifiers.new("Pips", "BOOLEAN")
    carve.operation = "DIFFERENCE"
    carve.object = cutters
    carve.solver = "EXACT"
    carve.material_mode = "TRANSFER"   # takes the black material from the cutters

    # Smooth the bevel and pip dishes while leaving the flat faces flat.
    # This appends a "Smooth by Angle" modifier, so it runs after the
    # boolean and needs no applied geometry.
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.shade_auto_smooth(angle=radians(30))
    return body


def main() -> None:
    argv = sys.argv
    out = argv[argv.index("--") + 1] if "--" in argv else "dice.glb"

    bpy.ops.wm.read_factory_settings(use_empty=True)   # one op: empty the scene
    body = build(STANDARD_D6)

    bpy.ops.export_scene.gltf(
        filepath=out,
        export_format="GLB",
        use_visible=True,          # the hidden cutter object is skipped
        export_apply=True,          # evaluates the modifier stack
        export_yup=True,
    )
    print(f"[make_dice] wrote {out}")


if __name__ == "__main__":
    main()
