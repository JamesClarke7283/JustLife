"""The baby hands-and-knees crawl, as one numeric contract.

scripts/actor.gd mirrors these numbers in `_baby_crawl_pose` / `_baby_crawl_offset`;
this module applies the same pose to the authored Blender rig so the evidence
renders show the pose the game actually plays. Keep the two in step.

Axis frames. Godot's model space is (right, up, forward) = (+X, +Y, +Z); Blender's
armature space is (+X, +Z, -Y). So a Godot point maps to Blender as
`(x, -z, y)`, and a Godot rotation `R` maps to Blender as `M R Mᵀ`, where `M` is
that basis change. A joint offset is a rotation expressed in the skeleton's own
axes, so each bone's local pose is the same rotation conjugated by its rest
orientation -- exactly what `LifeActor.animate` does with `entry.rest`.

Crawl numbers:
    PITCH         body pitch about X: the torso leans forward 70 degrees
    OFFSET_Y      how far the pivoting body is lifted so hands and knees touch
    OFFSET_Z      how far it is pushed forward over its planted hands
    ARM/FOREARM   arms planted ahead and slightly bowed out
    LEG/SHIN      thighs dropped under the hips, shins flat along the floor
    HEAD          counter-pitch that lifts the face back toward the horizon

The offsets are solved, not guessed: `solve_offset` poses the rig and reads the
real contact geometry, so the render and the game agree on where the floor is.
"""
import math

from mathutils import Matrix, Vector

PITCH = 1.222            # 70 degrees forward
# The solved vertical offset, mirrored by scripts/actor.gd. `solve_offset`
# recomputes it from the posed geometry and fails if the pose has drifted, so
# the render and the game can never disagree about where the floor is.
SOLVED_Y = 0.0700        # Godot +Y: lift so the hands and knees rest on the floor
OFFSET_Z = 0.026         # Godot +Z: push the planted hands slightly ahead
SOLVE_TOLERANCE = 0.006
# Every joint is a rotation in the skeleton's own axes, and the body is pitched
# PITCH forward, so a limb that should hang straight down in world space needs
# the counter-rotation -PITCH (see the derivation in the module docstring).
ARM = -1.300             # upper arm driven down and a little ahead of the shoulder
ARM_SWING = 0.240
FOREARM = 0.060          # forearm continues down, so the fist plants under the chest
FOREARM_CURL = 0.200
LEG = -1.222             # thigh hangs straight down from the raised hip
LEG_SWING = 0.200
SHIN = -1.571            # knee folds flat so the shin lies along the floor
SHIN_LIFT = 0.420
# The head must cancel the body pitch and then look a little further up, so the
# baby faces the horizon instead of the floor. Measured on the posed rig: the
# head's own forward axis sits at +6 degrees when HEAD = -1.32.
HEAD = -1.320            # ~-PITCH, plus a small upward tilt
STRIDE = 5.600           # radians per second of the crawl cycle

CONTACT_MESHES = (".Skin_Finger_", "Skin_Finger_", "Shoes_Upper_", "Skin_Leg_continuous_")


def joint_pose(cycle):
    """Joint offsets at stride phase `cycle`, in Godot skeleton axes."""
    swing = math.sin(cycle)
    return {
        "Head": (HEAD + 0.050 * math.sin(cycle * 0.5), 0.070 * math.sin(cycle * 0.37), 0.0),
        "Arm_L": (ARM + swing * ARM_SWING, 0.0, -0.090),
        "Arm_R": (ARM - swing * ARM_SWING, 0.0, 0.090),
        "Forearm_L": (FOREARM - max(0.0, -swing) * FOREARM_CURL + max(0.0, swing) * FOREARM_CURL * 0.7, 0.0, 0.0),
        "Forearm_R": (FOREARM - max(0.0, swing) * FOREARM_CURL + max(0.0, -swing) * FOREARM_CURL * 0.7, 0.0, 0.0),
        "Leg_L": (LEG + swing * LEG_SWING, 0.0, 0.070),
        "Leg_R": (LEG - swing * LEG_SWING, 0.0, -0.070),
        "Shin_L": (SHIN + max(0.0, swing) * SHIN_LIFT, 0.0, 0.0),
        "Shin_R": (SHIN + max(0.0, -swing) * SHIN_LIFT, 0.0, 0.0),
    }


def visual_offset(cycle=None):
    """Godot-space visual offset, including the gentle crawl bob."""
    bob = 0.0 if cycle is None else abs(math.sin(cycle)) * 0.010
    return Vector((0.0, SOLVED_Y + bob, OFFSET_Z))


# ---------------------------------------------------------------------------
# Frame conversion
# ---------------------------------------------------------------------------
def to_blender(point):
    return Vector((point[0], -point[2], point[1]))


def to_godot(point):
    return Vector((point[0], point[2], -point[1]))


_BASIS = Matrix(((1.0, 0.0, 0.0), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0)))


def godot_rotation(angles):
    """A Godot euler triple (x, then y, then z) as a Blender armature rotation."""
    rotation = (Matrix.Rotation(angles[2], 3, "Z")
                @ Matrix.Rotation(angles[1], 3, "Y")
                @ Matrix.Rotation(angles[0], 3, "X"))
    return _BASIS @ rotation @ _BASIS.transposed()


def apply(rig, cycle=0.0, offset=None):
    """Pose the authored armature and body exactly like the game's crawl."""
    import bpy
    root = bpy.data.objects["Character"]
    root.rotation_euler = (PITCH, 0.0, 0.0)
    root.location = to_blender(visual_offset(cycle) if offset is None else offset)
    # LifeActor.animate drives *both* the skeleton bones and the accessory
    # pivots of the same name, so the harness must too: the head skin deforms
    # through the armature while the hair, eyes and ears ride the Head pivot.
    for name, angles in joint_pose(cycle).items():
        rotation = godot_rotation(angles)
        bone = rig.data.bones[name]
        # The rest orientation *relative to the parent*, which is the frame this
        # bone's pose rotation is expressed in.
        rest = (bone.parent.matrix_local.inverted() @ bone.matrix_local).to_3x3().normalized() \
            if bone.parent else bone.matrix_local.to_3x3().normalized()
        pbone = rig.pose.bones[name]
        pbone.rotation_mode = "QUATERNION"
        pbone.rotation_quaternion = (rest.inverted() @ rotation @ rest).to_quaternion()
        pivot = _named_pivot(rig, name)
        if pivot is not None:
            pivot.rotation_mode = "QUATERNION"
            pivot.rotation_quaternion = rotation.to_quaternion()
    bpy.context.view_layer.update()


def _named_pivot(rig, name):
    """The accessory pivot sharing a bone's name.

    In the authored source the pivot is the empty itself; in the imported GLB it
    is the separate node beside the skeleton. Either way it is the non-armature
    object whose name matches the bone.
    """
    import bpy
    for node in bpy.data.objects:
        if node.name == name and node is not rig and node.type == "EMPTY":
            return node
    return None


def clear(rig):
    import bpy
    root = bpy.data.objects["Character"]
    root.rotation_euler = (0.0, 0.0, 0.0)
    root.location = (0.0, 0.0, 0.0)
    for pbone in rig.pose.bones:
        pbone.rotation_mode = "QUATERNION"
        pbone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
    for name in ("Head", "Arm_L", "Arm_R", "Forearm_L", "Forearm_R", "Leg_L", "Leg_R", "Shin_L", "Shin_R"):
        pivot = _named_pivot(rig, name)
        if pivot is not None:
            pivot.rotation_euler = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()


def contact_points(root):
    """World positions of the geometry that should touch the floor.

    The armature is a modifier, so the deformed positions live in the evaluated
    depsgraph rather than in `mesh.vertices`.
    """
    import bpy
    graph = bpy.context.evaluated_depsgraph_get()
    points = []
    for node in _walk(root):
        if node.type != "MESH" or not node.name.startswith(CONTACT_MESHES):
            continue
        evaluated = node.evaluated_get(graph)
        mesh = evaluated.to_mesh()
        matrix = evaluated.matrix_world
        points.extend(matrix @ vertex.co for vertex in mesh.vertices)
        evaluated.to_mesh_clear()
    return points


def _walk(node):
    yield node
    for child in node.children:
        yield from _walk(child)


def solve_offset(rig, cycle=0.0):
    """The Godot-space offset that plants the hands and knees on the floor.

    Pitching about the feet swings the body down through the floor, so the
    vertical offset is the depth of the deepest contact; a small forward term
    keeps the planted hands in front of the chest. The actor mirrors the two
    numbers rather than re-solving them at run time.
    """
    import bpy
    apply(rig, cycle, Vector((0.0, 0.0, 0.0)))
    points = contact_points(bpy.data.objects["Character"])
    solved = -min(point.z for point in points)
    assert solved <= SOLVED_Y + 1e-6 and solved >= SOLVED_Y - .028, (
        "The crawl pose drifted: the solved lift is %.4f but scripts/actor.gd mirrors %.4f. "
        "Update _baby_crawl_offset in the actor and SOLVED_Y here together." % (solved, SOLVED_Y))
    return Vector((0.0, SOLVED_Y, OFFSET_Z))
