"""Fit the authored Bob coordinate frame to a measured, evaluated family skull.

The template landmarks below were measured from the original adult source; they
are design coordinates, not an assumption about another family's world scale.
Only coordinates returned for newly authored Bob meshes are changed.
"""
import math
import statistics
from pathlib import Path

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

REFERENCE_PIVOT = Vector((0, .004999999888241291, 1.4579999446868896))
REFERENCE_SOURCE_SHA256 = 'b5895903f64331e840304f8f106398024cefeebe55b64bb9f2314cd6250213e7'
REFERENCE_TOP = 1.7478077411651611
REFERENCE_ROWS = (
    (.55, .22074493049398727, .2103503970080454, .006039805154014644),
    (.70, .20617966790831155, .20567975090595964, .010352766080065075),
    (.82, .17077754702735992, .1729859650619579, .011971572535883837),
)


def runtime_expansion(settings):
    return 1+.04*settings.get('Face_Round',0)+.03*settings.get('Jaw_Strong',0)


def assert_runtime_contract():
    actor = Path(__file__).resolve().parents[2]/'scripts'/'actor.gd'
    expected = '1.0 + .04 * float(profile.get("face_round", 0.0)) + .03 * float(profile.get("jaw_strong", 0.0))'
    assert expected in actor.read_text(), 'Bob runtime expansion changed; review the fitting/QA contract'


def evaluated_mesh(o):
    active = o.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = active.to_mesh()
    points = [active.matrix_world @ v.co for v in mesh.vertices]
    faces = [tuple(p.vertices) for p in mesh.polygons]
    active.to_mesh_clear()
    return points, faces


def bounds(points):
    return [[min(p[i] for p in points), max(p[i] for p in points)] for i in range(3)]


def smooth(x):
    x = max(0.0, min(1.0, x))
    return x*x*(3-2*x)


class SkullFit:
    def __init__(self, head, attachment, bob):
        assert_runtime_contract()
        points, faces = evaluated_mesh(head)
        self.skull = BVHTree.FromPolygons(points, faces)
        self.bounds = bounds(points)
        self.pivot = attachment.matrix_world.translation.copy()
        self.span = self.bounds[2][1]-self.pivot.z
        assert self.span > .1, 'Unexpected head attachment or skull bounds'
        self.rows = []
        widths, depths, centers = [], [], []
        for fraction, ref_width, ref_depth, ref_center in REFERENCE_ROWS:
            z = self.pivot.z+self.span*fraction
            row = [p for p in points if abs(p.z-z) < self.span*.012]
            assert len(row) >= 8, 'Insufficient evaluated skull cross-section'
            b = bounds(row)
            widths.append((b[0][1]-b[0][0])/ref_width)
            depths.append((b[1][1]-b[1][0])/ref_depth)
            centers.append(((b[1][1]+b[1][0])/2, ref_center))
            self.rows.append({'fraction':fraction, 'bounds':b, 'sample_count':len(row)})
        self.sx = statistics.median(widths)
        self.sy = statistics.median(depths)
        self.sz = self.span/(REFERENCE_TOP-REFERENCE_PIVOT.z)
        self.offset_y = statistics.median(actual-(self.pivot.y+(ref-REFERENCE_PIVOT.y)*self.sy)
                                          for actual, ref in centers)
        # Linear detail/thickness follows head size, not torso/age height.
        self.detail_scale = (self.sx*self.sy*self.sz)**(1/3)
        assert all(.35 < s < 1.4 for s in (self.sx, self.sy, self.sz))
        # Face silhouettes can enlarge the temple/cheek below the cap. Keep
        # this haircut clear over the supported silhouette envelope after the
        # game's existing X expansion (actor.gd set_face_feature). Transform
        # each expanded-head case back through the inverse runtime Bob scale;
        # do NOT bake a full worst-case skull and then expand the hair again.
        self.skulls = [self.skull]
        self.envelope_cases = [{'morphs':{}, 'runtime_bob_x_expansion':1.0}]
        bob_world = bob.matrix_world.copy()
        if head.data.shape_keys:
            keys = head.data.shape_keys.key_blocks
            saved = {k.name:k.value for k in keys}
            try:
                for settings in ({'Face_Round':1.0}, {'Jaw_Strong':1.0},
                                 {'Face_Round':1.0,'Jaw_Strong':1.0}):
                    if not all(name in keys for name in settings):
                        continue
                    for k in keys:
                        k.value = settings.get(k.name,0.0)
                    bpy.context.view_layer.update()
                    pts, polys = evaluated_mesh(head)
                    expansion = runtime_expansion(settings)
                    compensate = bob_world @ Matrix.Diagonal(Vector((1/expansion,1,1,1))) @ bob_world.inverted()
                    pts = [compensate @ point for point in pts]
                    self.skulls.append(BVHTree.FromPolygons(pts,polys))
                    self.envelope_cases.append({'morphs':settings,'runtime_bob_x_expansion':expansion})
            finally:
                for k in keys:
                    k.value = saved[k.name]
                bpy.context.view_layer.update()
        self.corrected = 0
        self.max_radial_adjustment = 0.0

    def map(self, p, a, t, extra):
        p = Vector((self.pivot.x+(p.x-REFERENCE_PIVOT.x)*self.sx,
                    self.pivot.y+(p.y-REFERENCE_PIVOT.y)*self.sy+self.offset_y,
                    self.pivot.z+(p.z-REFERENCE_PIVOT.z)*self.sz))
        # At the opening only, let the haircut meet the evaluated forehead.
        # Elsewhere keep the authored fullness, while guaranteeing that the
        # inner shell cannot intersect the neutral scalp at the same latitude.
        direction = Vector((math.sin(a)*self.sx, -math.cos(a)*self.sy, 0)).normalized()
        origin = Vector((self.pivot.x, self.pivot.y+.007*self.sy+self.offset_y, p.z))
        targets = []
        for skull in self.skulls:
            hit, normal, _, distance = skull.ray_cast(origin, direction, .4)
            if hit is not None:
                # A horizontal offset alone underestimates clearance on the
                # sloping forehead. Compensate for the actual surface normal
                # so the inward Solidify side remains outside the skin too.
                required = (.007+extra)*self.detail_scale
                normal_projection = max(.30, normal.dot(direction))
                targets.append(hit+direction*(required/normal_projection))
        if targets:
            target = max(targets,key=lambda v:(v-origin).dot(direction))
            contact = smooth((1.03-abs((a+math.pi)%(2*math.pi)-math.pi))/.28)*smooth((t-.83)/.17)
            delta = p-origin
            radius = delta.dot(direction)
            minimum = (target-origin).dot(direction)
            correction = max(0.0, minimum-radius)
            if contact > 0:
                desired = p.lerp(target, contact)
                correction = max(correction, (desired-p).dot(direction))
                # A negative contact correction brings the front rim into the
                # scalp; signed layer offsets remain embedded at their roots.
                if (desired-p).dot(direction) < 0 and minimum <= radius:
                    p = desired
                    radius = (p-origin).dot(direction)
                    correction = max(0.0, minimum-radius)
            if correction > 0:
                p += direction*correction
                self.corrected += 1
                self.max_radial_adjustment = max(self.max_radial_adjustment, correction)
        return p

    def report(self):
        return {'method':'evaluated skull cross-sections and runtime-compensated silhouette envelope clearance',
                'canonical_landmark_source_sha256':REFERENCE_SOURCE_SHA256,
                'head_pivot':list(self.pivot), 'head_evaluated_bounds':self.bounds,
                'cross_sections':self.rows, 'linear_scale':[self.sx,self.sy,self.sz],
                'detail_scale':self.detail_scale, 'center_offset_y':self.offset_y,
                'clearance_envelope':self.envelope_cases, 'contact_normal_clearance':.007*self.detail_scale,
                'radial_correction_count':self.corrected,
                'max_radial_correction':self.max_radial_adjustment}
