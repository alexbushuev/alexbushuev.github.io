# Builds every 3D asset of "Газ и цепь" from code and writes plain glTF files.
#   python3 make_models.py <output_dir>      (needs the bpy module: Blender as a Python library)
#
# Nothing here depends on a game engine. Colours are stored as vertex colours:
#   alpha = 1            -> the RGB is the final colour
#   alpha = (slot+.5)/16 -> the engine paints this part from a palette slot, RGB is a shade multiplier
#   slot 15              -> self-lit part (lamps, windows at night), RGB is the light colour
# Axes in Blender: +X right, +Y forward, +Z up. In the glTF files forward becomes -Z and up +Y.
import bpy, json, math, os, sys
from mathutils import Vector

OUT = sys.argv[-1]
os.makedirs(OUT, exist_ok=True)


def col(*rgb):
    return (*rgb, 1.0)


def slot(i, shade=1.0):
    return (shade, shade, shade, (i + 0.5) / 16)


def glow(*rgb):
    return (*rgb, 15.5 / 16)


def hexc(h):
    h = h.lstrip('#')
    return col(int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255)


BLACK = hexc('#17171c')
RUBBER = hexc('#101013')
STEEL = hexc('#8d9098')
CHROME = hexc('#b8bcc4')
DARKM = hexc('#34353c')
GLASS = hexc('#1c2a38')
SEAT = hexc('#1e1c20')
LAMP = glow(1.0, 0.95, 0.72)
TAIL = glow(1.0, 0.1, 0.06)
AMBER = glow(1.0, 0.62, 0.1)


class Kit:
    """Collects primitives into named groups, then joins each group into one mesh object."""

    def __init__(self):
        self.groups = {}

    def _finish(self, o, c, group, smooth, bone=None):
        me = o.data
        attr = me.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
        for v in attr.data:
            v.color = c
        for p in me.polygons:
            p.use_smooth = smooth
        if bone:
            vg = o.vertex_groups.new(name=bone)
            vg.add(list(range(len(me.vertices))), 1.0, 'REPLACE')
        self.groups.setdefault(group, []).append(o)
        return o

    def tube(self, a, b, r, c, group='main', verts=8, smooth=True, bone=None, r2=None):
        a, b = Vector(a), Vector(b)
        d = b - a
        if r2 is None:
            bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=d.length, location=(a + b) / 2)
        else:
            bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2, depth=d.length, location=(a + b) / 2)
        o = bpy.context.object
        o.rotation_mode = 'QUATERNION'
        o.rotation_quaternion = d.to_track_quat('Z', 'Y')
        return self._finish(o, c, group, smooth, bone)

    def blob(self, loc, size, c, group='main', rot=(0, 0, 0), seg=10, rings=6, smooth=False, bone=None):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=1, location=loc)
        o = bpy.context.object
        o.scale = size
        o.rotation_euler = rot
        return self._finish(o, c, group, smooth, bone)

    def box(self, loc, size, c, group='main', rot=(0, 0, 0), bone=None):
        bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
        o = bpy.context.object
        o.scale = size
        o.rotation_euler = rot
        return self._finish(o, c, group, False, bone)

    def ring(self, loc, major, minor, c, group='main', seg=18, mseg=6, axis='x', smooth=True):
        rot = {'x': (0, math.pi / 2, 0), 'y': (math.pi / 2, 0, 0), 'z': (0, 0, 0)}[axis]
        bpy.ops.mesh.primitive_torus_add(major_segments=seg, minor_segments=mseg, major_radius=major,
                                         minor_radius=minor, location=loc, rotation=rot)
        return self._finish(bpy.context.object, c, group, smooth)

    def disc(self, loc, r, depth, c, group='main', verts=14, axis='x'):
        rot = {'x': (0, math.pi / 2, 0), 'y': (math.pi / 2, 0, 0), 'z': (0, 0, 0)}[axis]
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
        return self._finish(bpy.context.object, c, group, False)

    def join(self, group, name, origin=None):
        objs = self.groups[group]
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        if len(objs) > 1:
            bpy.ops.object.join()
        o = bpy.context.view_layer.objects.active
        o.name = name
        o.data.name = name
        if origin is not None:
            bpy.context.scene.cursor.location = origin
            bpy.ops.object.select_all(action='DESELECT')
            o.select_set(True)
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
            bpy.context.scene.cursor.location = (0, 0, 0)
        return o


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    m = bpy.data.materials.new('paint')
    m.use_nodes = True
    return m


def export(name, mat, skins=False):
    for o in bpy.data.objects:
        if o.type == 'MESH' and not o.data.materials:
            o.data.materials.append(mat)
    path = os.path.join(OUT, name + '.glb')
    kw = dict(filepath=path, export_format='GLB', export_apply=True, export_yup=True, export_skins=skins,
              export_animations=False, export_morph=False, export_cameras=False, export_lights=False,
              export_normals=True, export_texcoords=False, export_materials='EXPORT')
    try:
        bpy.ops.export_scene.gltf(export_vertex_color='ACTIVE', **kw)
    except TypeError:
        bpy.ops.export_scene.gltf(export_colors=True, **kw)
    return os.path.getsize(path)


# ---------- bikes ----------
ARTS = {
    # wb wheelbase, rr/rf wheel radius, tw tyre half-thickness, seat/bar/peg are where the rider touches the bike (y, z)
    'moped':     dict(fam='moped', wb=1.12, rr=.26, rf=.26, tw=.035, seat=(-.20, .80), bar=(.34, 1.02), peg=(-.02, .28), bw=.26, tuck=8),
    'underbone': dict(fam='underbone', wb=1.20, rr=.28, rf=.28, tw=.04, seat=(-.22, .80), bar=(.36, 1.00), peg=(-.02, .29), bw=.27, tuck=10),
    'scooter':   dict(fam='scooter', wb=1.22, rr=.20, rf=.21, tw=.05, seat=(-.24, .74), bar=(.33, 1.02), peg=(.08, .30), bw=.28, tuck=6),
    'maxi':      dict(fam='maxi', wb=1.50, rr=.23, rf=.24, tw=.06, seat=(-.30, .76), bar=(.36, 1.10), peg=(.14, .36), bw=.32, tuck=4),
    'naked':     dict(fam='naked', wb=1.38, rr=.30, rf=.30, tw=.06, seat=(-.26, .82), bar=(.38, 1.06), peg=(-.14, .36), bw=.34, tuck=18),
    'street':    dict(fam='street', wb=1.40, rr=.30, rf=.30, tw=.06, seat=(-.26, .84), bar=(.38, 1.04), peg=(-.14, .37), bw=.32, tuck=22),
    'scrambler': dict(fam='scrambler', wb=1.42, rr=.34, rf=.36, tw=.055, seat=(-.26, .90), bar=(.36, 1.16), peg=(-.10, .42), bw=.40, tuck=14),
    'tourer':    dict(fam='tourer', wb=1.55, rr=.32, rf=.32, tw=.07, seat=(-.32, .84), bar=(.34, 1.10), peg=(-.12, .40), bw=.34, tuck=8),
    'sport':     dict(fam='sport', wb=1.40, rr=.31, rf=.31, tw=.075, seat=(-.26, .86), bar=(.40, .98), peg=(-.20, .42), bw=.28, tuck=42),
    'hyper':     dict(fam='sport', wb=1.48, rr=.32, rf=.32, tw=.09, seat=(-.30, .87), bar=(.42, .99), peg=(-.22, .43), bw=.29, tuck=46, big=1),
}


def wheel(k, group, y, r, tw, spokes=True):
    k.ring((0, y, r), r - tw, tw, RUBBER, group, seg=20, mseg=6, axis='x')
    k.disc((0, y, r), .045, .13, DARKM, group, verts=8)
    if spokes:
        for i in range(5):
            a = i * 2 * math.pi / 5
            k.tube((0, y, r), (0, y + math.cos(a) * (r - tw * 1.7), r + math.sin(a) * (r - tw * 1.7)), .016, CHROME, group, verts=5, smooth=False)
    k.ring((0, y, r), r - tw * 1.8, .012, CHROME, group, seg=16, mseg=4, axis='x')


def make_bike(art):
    p = ARTS[art]
    mat = reset()
    k = Kit()
    wb, rr, rf, tw = p['wb'], p['rr'], p['rf'], p['tw']
    yr, yf = -wb * .5, wb * .5
    sy, sz = p['seat']
    by, bz = p['bar']
    py, pz = p['peg']
    bw = p['bw']
    fam = p['fam']
    body, body2 = slot(0), slot(1)
    # steering head: where the fork meets the frame. Everything forward of it steers.
    hy, hz = by - .03 + (.03 if fam in ('scooter', 'maxi') else 0), bz - .10
    front = 'front'

    wheel(k, 'wheel_r', yr, rr, tw)
    wheel(k, 'wheel_f', yf, rf, tw)

    # fork, bars, grips, mirror stalks: these turn with the wheel
    if fam in ('scooter', 'maxi'):
        k.tube((.05, yf, rf), (.03, hy, hz), .022, DARKM, front, verts=6)
    else:
        for s in (-1, 1):
            k.tube((s * .07, yf, rf), (s * .055, hy, hz), .022, CHROME, front, verts=6)
    k.tube((-bw, by, bz), (bw, by, bz), .012, BLACK, front, verts=6, smooth=False)
    for s in (-1, 1):
        k.tube((s * bw, by, bz), (s * (bw - .10), by, bz), .018, RUBBER, front, verts=6, smooth=False)
    k.tube((0, hy, hz - .05), (0, by, bz), .02, BLACK, front, verts=6, smooth=False)

    if fam == 'sport':
        big = p.get('big', 0) * .02
        # rear swingarm, engine, exhaust
        for s in (-1, 1):
            k.tube((s * .07, yr, rr), (s * .07, -.16, .50), .022, DARKM, verts=6)
            k.tube((s * .10, .34, .86), (s * .12, -.16, .58), .03, DARKM, verts=6)
        k.box((0, .02, .42), (.28, .44, .34), BLACK)
        k.blob((0, .0, .28), (.13, .26, .07), STEEL)
        k.tube((.12, .1, .24), (.15, yr + .22, .50), .045, STEEL, verts=8)
        k.tube((.15, yr + .42, .44), (.17, yr + .06, .56), .07 + big, CHROME, verts=8, r2=.05)
        # bodywork
        k.blob((0, .12, .86), (.15 + big, .30, .125), body, rot=(.10, 0, 0))
        k.blob((0, yf - .16, .80), (.115, .24, .13), body, rot=(.22, 0, 0))
        for s in (-1, 1):
            k.blob((s * .125, .32, .62), (.03, .28, .155), body, rot=(.2, 0, 0))
            k.blob((s * .155, .28, .60), (.012, .15, .04), body2, rot=(.2, 0, 0))
        k.blob((0, .22, .30), (.10, .24, .055), body2, rot=(.15, 0, 0))
        k.box((0, sy, sz), (.19, .38, .06), SEAT, rot=(-.06, 0, 0))
        k.blob((0, yr + .16, sz + .07), (.09, .25, .07), body, rot=(-.20, 0, 0))
        k.blob((0, yr + .0, sz + .06), (.05, .02, .022), TAIL)
        k.blob((0, yf - .03, .82), (.055, .018, .04), LAMP, front, seg=8, rings=4)
        k.blob((0, yf - .18, 1.00), (.095, .13, .012), GLASS, rot=(-.8, 0, 0))
        k.blob((0, yf + .0, rf + rf * .72), (.05, .17, .012), body, front, rot=(.1, 0, 0))
    elif fam in ('naked', 'street', 'scrambler', 'tourer'):
        for s in (-1, 1):
            k.tube((s * .08, yr, rr), (s * .08, -.14, .52), .022, DARKM, verts=6)
            k.tube((s * .085, -.20, sz - .02), (s * .07, yr + .08, rr + .05), .02, STEEL if fam == 'naked' else DARKM, verts=6)
        k.tube((0, hy - .02, hz - .04), (0, -.12, .74), .035, DARKM, verts=6)
        k.tube((0, hy - .04, hz - .14), (0, -.04, .34), .03, DARKM, verts=6)
        k.tube((0, -.12, .74), (0, -.14, .36), .03, DARKM, verts=6)
        k.box((0, .02, .44), (.26, .36, .30), BLACK)
        for i in range(3):
            k.box((0, -.08 + i * .1, .62), (.27, .05, .05), STEEL)
        k.blob((0, .08, sz + .06), (.14, .27, .12), body, rot=(.08, 0, 0))
        k.box((0, sy, sz + .02), (.20, .50, .07), SEAT, rot=(-.04, 0, 0))
        k.blob((0, yr + .22, sz + .05), (.08, .16, .045), body, rot=(-.2, 0, 0))
        k.blob((0, yr + .08, sz + .04), (.05, .02, .025), TAIL)
        k.blob((0, yr + .02, rr + rr * .72), (.055, .18, .012), body2)
        k.blob((0, yf + .0, rf + rf * .72), (.05, .19, .012), body2 if fam != 'scrambler' else body, front, rot=(.1, 0, 0))
        k.tube((.13, .05, .26), (.16, yr + .32, .30), .035, CHROME, verts=8)
        k.tube((.16, yr + .36, .30), (.18, yr + .02, .38), .058, CHROME, verts=8, r2=.04)
        if fam in ('naked', 'scrambler'):
            k.blob((0, hy + .12, hz - .05), (.075, .05, .075), BLACK, front)
            k.blob((0, hy + .17, hz - .05), (.058, .012, .058), LAMP, front, seg=8, rings=4)
        if fam == 'street':
            k.blob((0, hy + .14, hz - .06), (.14, .12, .15), body, rot=(.2, 0, 0))
            k.blob((0, hy + .25, hz - .06), (.05, .015, .04), LAMP, seg=8, rings=4)
            k.blob((0, hy + .12, hz + .1), (.10, .09, .012), GLASS, rot=(-1.0, 0, 0))
        if fam == 'scrambler':
            k.box((0, .02, .25), (.20, .34, .03), STEEL)
            k.blob((0, yf + .03, rf + rf * .50), (.05, .20, .012), body, front, rot=(.1, 0, 0))
        if fam == 'tourer':
            k.blob((0, hy + .17, hz - .08), (.21, .17, .22), body, rot=(.2, 0, 0))
            k.blob((0, hy + .31, hz - .1), (.06, .015, .05), LAMP, seg=8, rings=4)
            k.blob((0, hy + .14, hz + .22), (.14, .13, .012), GLASS, rot=(-1.15, 0, 0))
            for s in (-1, 1):
                k.box((s * .28, yr + .32, .54), (.15, .40, .30), body2)
            k.box((0, yr + .12, sz + .22), (.32, .30, .26), body2)
    elif fam == 'moped':
        k.tube((0, hy - .02, hz - .04), (0, .0, .42), .024, body, verts=6)
        k.tube((0, .0, .42), (0, -.26, sz - .08), .024, body, verts=6)
        k.tube((0, -.06, .40), (0, yr, rr), .018, DARKM, verts=6)
        k.tube((.05, -.26, sz - .06), (.05, yr, rr), .012, STEEL, verts=5)
        k.tube((-.05, -.26, sz - .06), (-.05, yr, rr), .012, STEEL, verts=5)
        k.blob((0, -.02, .34), (.09, .13, .09), DARKM)
        k.tube((.06, .0, .30), (.09, yr + .08, .30), .02, CHROME, verts=6)
        k.blob((0, .10, .70), (.07, .17, .08), body, rot=(.6, 0, 0))
        k.box((0, sy, sz), (.17, .30, .07), SEAT)
        k.box((0, yr + .14, sz + .02), (.20, .24, .03), STEEL)
        k.box((0, yr + .14, sz + .14), (.24, .26, .20), hexc('#8a6a3a'))
        k.blob((0, hy + .10, hz - .03), (.05, .04, .05), LAMP, front, seg=8, rings=4)
        k.blob((0, yr + .03, sz + .0), (.03, .02, .02), TAIL)
        k.blob((0, yf + .0, rf + rf * .66), (.035, .15, .010), body, front, rot=(.1, 0, 0))
        for s in (-1, 1):
            k.tube((s * .05, .0, .30), (s * .16, .0, .28), .008, STEEL, verts=5, smooth=False)
    elif fam == 'underbone':
        k.tube((0, hy - .02, hz - .05), (0, -.02, .46), .03, DARKM, verts=6)
        k.tube((0, -.02, .46), (0, -.24, sz - .08), .03, DARKM, verts=6)
        k.tube((0, -.04, .40), (0, yr, rr), .02, DARKM, verts=6)
        k.tube((.06, -.26, sz - .06), (.06, yr, rr), .013, STEEL, verts=5)
        k.tube((-.06, -.26, sz - .06), (-.06, yr, rr), .013, STEEL, verts=5)
        k.blob((0, -.02, .36), (.10, .14, .10), DARKM)
        k.tube((.07, .0, .30), (.11, yr + .06, .34), .026, CHROME, verts=6)
        k.blob((0, hy - .09, hz - .24), (.11, .10, .25), body, rot=(.35, 0, 0))
        k.box((0, -.24, sz - .13), (.18, .34, .17), body)
        k.box((0, sy, sz), (.17, .42, .07), SEAT)
        k.blob((0, yr + .10, sz - .06), (.09, .20, .07), body2)
        k.blob((0, yr - .08, sz - .06), (.04, .02, .025), TAIL)
        k.blob((0, hy + .09, hz - .03), (.06, .05, .05), LAMP, front, seg=8, rings=4)
        k.blob((0, yf + .0, rf + rf * .66), (.04, .15, .010), body, front, rot=(.1, 0, 0))
    else:  # scooter, maxi
        m = fam == 'maxi'
        k.box((0, .0, .25 + (.06 if m else 0)), (.26 + (.05 if m else 0), .82 if not m else 1.0, .05), body2)
        k.blob((0, hy - .1, hz - .32), (.16 + (.03 if m else 0), .09, .36), body, rot=(.26, 0, 0))
        k.blob((0, sy - (.04 if m else 0), sz - .20), (.17 + (.04 if m else 0), .36 + (.08 if m else 0), .20), body)
        k.box((0, sy, sz), (.22 + (.03 if m else 0), .46 + (.08 if m else 0), .08), SEAT)
        k.blob((0, yr + (.12 if m else .1), sz - .14), (.05, .02, .03), TAIL)
        k.blob((0, hy + .05, hz - .22), (.06, .02, .05), LAMP, seg=8, rings=4)
        k.tube((.09, -.2, .24), (.10, yr + .0, rr + .02), .05, DARKM, verts=6)
        k.tube((.14, yr + .3, rr), (.15, yr - .05, rr + .06), .04, CHROME, verts=8)
        k.blob((0, yf + .0, rf + rf * .68), (.06, .16, .012), body, front, rot=(.1, 0, 0))
        if m:
            k.blob((0, hy + .0, hz + .20), (.15, .12, .012), GLASS, rot=(-1.1, 0, 0))
            k.box((0, yr + .24, sz + .17), (.28, .26, .22), body2)

    origin_f = (0, hy, hz)
    ch = k.join('main', 'chassis')
    fr = k.join(front, 'front', origin_f)
    wf = k.join('wheel_f', 'wheel_f', (0, yf, rf))
    wr = k.join('wheel_r', 'wheel_r', (0, yr, rr))
    wf.parent = fr
    wf.matrix_parent_inverse = fr.matrix_world.inverted()
    size = export('bike_' + art, mat)
    d = Vector((0, yf - hy, rf - hz)).normalized()
    return {k2: v for k2, v in {
        'wb': wb, 'rr': rr, 'rf': rf, 'yr': yr, 'yf': yf, 'seat': [sy, sz], 'bar': [by, bz], 'bw': bw, 'peg': [py, pz],
        'tuck': p['tuck'], 'steer_axis': [d.y, d.z], 'steer_top': [hy, hz], 'kb': round(size / 1024, 1)}.items()}


# ---------- rider: one skinned mesh, all bones share one orientation so poses stay engine-independent ----------
JOINTS = {
    'hips': (None, (0, 0, .95)),
    'spine': ('hips', (0, 0, 1.03)),
    'head': ('spine', (0, 0, 1.52)),
    'arm_u.L': ('spine', (-.21, 0, 1.43)),
    'arm_l.L': ('arm_u.L', (-.21, 0, 1.14)),
    'arm_u.R': ('spine', (.21, 0, 1.43)),
    'arm_l.R': ('arm_u.R', (.21, 0, 1.14)),
    'leg_u.L': ('hips', (-.105, 0, .93)),
    'leg_l.L': ('leg_u.L', (-.105, 0, .51)),
    'leg_u.R': ('hips', (.105, 0, .93)),
    'leg_l.R': ('leg_u.R', (.105, 0, .51)),
}
JACKET, STRIPE, PANTS, BOOTS, GLOVE, SKIN, HELMET, HSTRIPE, SLEEVE = range(9)


def make_rider():
    mat = reset()
    k = Kit()
    J = {n: v[1] for n, v in JOINTS.items()}
    # torso
    k.blob((0, 0, .97), (.165, .12, .12), slot(PANTS), bone='hips', smooth=True)
    k.tube((0, 0, 1.0), (0, 0, 1.44), .155, slot(JACKET), bone='spine', verts=10, r2=.19)
    k.blob((0, 0, 1.43), (.215, .125, .085), slot(JACKET), bone='spine', smooth=True)
    k.box((0, -.135, 1.24), (.11, .03, .34), slot(STRIPE), bone='spine')
    k.box((0, .125, 1.28), (.09, .03, .22), slot(STRIPE), bone='spine')
    k.tube((0, 0, 1.46), (0, 0, 1.56), .05, slot(SKIN), bone='head', verts=8)
    # head stays bare under the helmets
    k.blob((0, .01, 1.645), (.098, .11, .118), slot(SKIN), bone='head', smooth=True)
    k.blob((0, -.015, 1.68), (.102, .105, .095), hexc('#3a2a20'), bone='head', smooth=True)
    for s, side in ((-1, 'L'), (1, 'R')):
        k.tube((s * .21, 0, 1.45), (s * .21, 0, 1.14), .058, slot(JACKET), bone='arm_u.' + side, verts=8, r2=.05)
        k.ring((s * .21, 0, 1.28), .056, .012, slot(STRIPE), seg=8, mseg=3, axis='z')
        v = k.groups['main'][-1]
        vg = v.vertex_groups.new(name='arm_u.' + side)
        vg.add(list(range(len(v.data.vertices))), 1.0, 'REPLACE')
        k.tube((s * .21, 0, 1.15), (s * .21, 0, .90), .046, slot(SLEEVE), bone='arm_l.' + side, verts=8, r2=.038)
        k.blob((s * .21, .01, .86), (.044, .052, .052), slot(GLOVE), bone='arm_l.' + side, smooth=True)
        k.tube((s * .105, 0, .94), (s * .105, 0, .52), .082, slot(PANTS), bone='leg_u.' + side, verts=8, r2=.062)
        k.blob((s * .105, .012, .50), (.066, .07, .07), slot(STRIPE), bone='leg_l.' + side, smooth=True)
        k.tube((s * .105, 0, .50), (s * .105, 0, .14), .058, slot(PANTS), bone='leg_l.' + side, verts=8, r2=.05)
        k.box((s * .105, .05, .08), (.095, .25, .15), slot(BOOTS), bone='leg_l.' + side)
    body = k.join('main', 'rider_body')
    # helmets are separate meshes on the head bone
    k.groups = {}
    k.blob((0, .005, 1.665), (.128, .145, .128), slot(HELMET), 'full', bone='head', seg=12, rings=8, smooth=True)
    k.blob((0, .112, 1.648), (.095, .05, .05), GLASS, 'full', bone='head', seg=10, rings=6, smooth=True)
    k.box((0, -.01, 1.79), (.03, .23, .02), slot(HSTRIPE), 'full', bone='head')
    k.blob((0, .115, 1.585), (.07, .04, .04), slot(HELMET, .8), 'full', bone='head', seg=8, rings=4)
    full = k.join('full', 'helm_full')
    k.blob((0, .0, 1.70), (.122, .135, .085), slot(HELMET), 'open', bone='head', seg=12, rings=6, smooth=True)
    k.box((0, .12, 1.675), (.17, .05, .018), slot(HELMET, .75), 'open', bone='head')
    k.tube((0, -.12, 1.66), (0, -.13, 1.70), .04, BLACK, 'open', bone='head', verts=6, smooth=False)
    op = k.join('open', 'helm_open')

    # armature
    bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
    arm = bpy.context.object
    arm.name = 'rig'
    ebs = arm.data.edit_bones
    for b in list(ebs):
        ebs.remove(b)
    for n, (par, head) in JOINTS.items():
        b = ebs.new(n)
        b.head = head
        b.tail = (head[0], head[1], head[2] + .1)
        b.roll = 0
        if par:
            b.parent = ebs[par]
            b.use_connect = False
    bpy.ops.object.mode_set(mode='OBJECT')
    for o in (body, full, op):
        o.parent = arm
        m = o.modifiers.new('arm', 'ARMATURE')
        m.object = arm
    size = export('rider', mat, skins=True)
    return {'joints': {n: [v[1][0], v[1][1], v[1][2]] for n, v in JOINTS.items()}, 'kb': round(size / 1024, 1)}


# ---------- weapons ----------
def make_weapons():
    mat = reset()
    k = Kit()
    # both held at the origin, pointing along +Y in Blender (forward)
    # police tonfa-style baton: black rubber, white band, visible at a distance
    k.tube((0, -.06, 0), (0, .62, 0), .024, hexc('#14141a'), 'baton', verts=8, r2=.034)
    k.tube((.0, -.08, 0), (0, .06, 0), .03, hexc('#3a3a42'), 'baton', verts=6)
    k.tube((0, .42, 0), (0, .50, 0), .034, hexc('#f3eedf'), 'baton', verts=8)
    k.blob((0, .62, 0), (.034, .034, .034), hexc('#14141a'), 'baton', seg=8, rings=5, smooth=True)
    b = k.join('baton', 'baton')
    n = 11
    for i in range(n):
        k.ring((0, .05 + i * .075, 0), .034, .008, CHROME, 'chain', seg=8, mseg=3, axis='x' if i % 2 else 'z', smooth=False)
    c = k.join('chain', 'chain')
    return export('weapons', mat)


# ---------- traffic ----------
def make_cars():
    mat = reset()
    k = Kit()
    win = GLASS
    def wheels(g, w, l, r=.32):
        for sy in (-1, 1):
            for s in (-1, 1):
                k.disc((s * (w - .06), sy * l, r), r, .2, RUBBER, g, verts=10)
                k.disc((s * (w + .045), sy * l, r), r * .55, .02, STEEL, g, verts=8)
    # sedan: 4.4 long, 1.8 wide
    g = 'sedan'
    k.box((0, 0, .58), (1.8, 4.4, .52), slot(0), g)
    k.box((0, -.25, 1.08), (1.56, 2.1, .50), win, g)
    k.box((0, -.25, 1.355), (1.5, 1.8, .05), slot(0), g)
    for s in (-1, 1):
        k.box((s * .5, 2.2, .68), (.32, .03, .14), LAMP, g)
        k.box((s * .55, -2.2, .72), (.34, .03, .13), TAIL, g)
    k.box((0, 2.21, .46), (1.4, .03, .12), BLACK, g)
    k.box((0, -2.21, .46), (1.4, .03, .12), BLACK, g)
    wheels(g, .85, 1.38)
    k.join(g, g)
    # van: 5.2 long, 2 wide
    g = 'van'
    k.box((0, 0, 1.22), (2.0, 5.2, 1.84), slot(0), g)
    k.box((0, 2.0, 1.62), (1.86, 1.25, .66), win, g)
    k.box((0, 0, 2.16), (1.9, 3.0, .03), slot(0, .85), g)
    for s in (-1, 1):
        k.box((s * .7, 2.6, .78), (.3, .03, .2), LAMP, g)
        k.box((s * .84, -2.6, 1.02), (.18, .03, .4), TAIL, g)
    k.box((0, -2.61, 1.5), (1.4, .02, .9), slot(0, .85), g)
    wheels(g, .95, 1.7)
    k.join(g, g)
    # truck: 8 long, 2.5 wide
    g = 'truck'
    k.box((0, 2.9, 1.5), (2.4, 2.2, 2.3), slot(0), g)
    k.box((0, 3.96, 1.95), (2.2, .05, .95), win, g)
    k.box((0, -1.0, 2.1), (2.5, 5.8, 2.7), hexc('#c9c7bb'), g)
    k.box((0, -1.0, .7), (2.3, 6.2, .3), DARKM, g)
    for s in (-1, 1):
        k.box((s * .9, 4.0, .95), (.3, .03, .2), LAMP, g)
        k.box((s * 1.0, -3.92, .85), (.3, .03, .16), TAIL, g)
    for sy, wr in ((2.9, 1), (-2.2, 1), (-3.2, 1)):
        for s in (-1, 1):
            k.disc((s * 1.08, sy, .5), .5, .3, RUBBER, g, verts=10)
    k.join(g, g)
    return export('cars', mat)


# ---------- roadside. Palette slots follow the theme tone table ----------
LEAF, LEAF2, TRUNK, DARK, WALL, WALL2, ROOF, WIN, METAL, WOOD, PLATE = range(11)


def make_decor():
    mat = reset()
    k = Kit()
    def done(g):
        k.join(g, g)

    def windows(g, x0, x1, y, z0, z1, nx, nz, w=.5, h=.6, face=-1):
        for i in range(nx):
            for j in range(nz):
                x = x0 + (x1 - x0) * (i + .5) / nx
                z = z0 + (z1 - z0) * (j + .5) / nz
                k.box((x, y, z), (w, .04, h), slot(WIN) if (i * 7 + j * 3) % 5 else slot(DARK), g)

    g = 'birch'
    k.tube((0, 0, 0), (0, 0, 7.0), .13, slot(TRUNK), g, verts=6, r2=.05, smooth=False)
    for i in range(4):
        k.box((0, .0, 1 + i * 1.5), (.27, .27, .1), slot(DARK), g)
    k.blob((.2, 0, 6.4), (1.6, 1.6, 2.2), slot(LEAF), g, seg=7, rings=5)
    k.blob((-.5, .2, 5.1), (1.25, 1.25, 1.5), slot(LEAF2), g, seg=7, rings=4)
    k.blob((.6, -.3, 7.6), (1.0, 1.0, 1.2), slot(LEAF2), g, seg=6, rings=4)
    done(g)
    g = 'pine'
    k.tube((0, 0, 0), (0, 0, 2.2), .22, slot(TRUNK), g, verts=6, smooth=False)
    for i, (r, h, z) in enumerate(((2.5, 3.6, 1.5), (2.0, 3.2, 3.5), (1.4, 3.0, 5.4), (.85, 2.6, 7.2))):
        k.tube((0, 0, z), (0, 0, z + h), r, slot(LEAF if i % 2 else LEAF2), g, verts=7, r2=.03, smooth=False)
    done(g)
    g = 'palm'
    k.tube((0, 0, 0), (.45, .1, 7.4), .17, slot(TRUNK), g, verts=6, r2=.09, smooth=False)
    for i in range(7):
        a = i * 2 * math.pi / 7
        c, s = math.cos(a), math.sin(a)
        k.blob((.45 + c * 1.7, .1 + s * 1.7, 7.0), (1.9, .42, .09), slot(LEAF if i % 2 else LEAF2), g,
               rot=(0, .38, a), seg=6, rings=3)
    done(g)
    g = 'bamboo'
    for x, y, h in ((0, 0, 8), (.45, .2, 6.5), (-.35, .3, 7.2), (.1, -.4, 5.8)):
        k.tube((x, y, 0), (x + .1, y, h), .06, slot(LEAF2), g, verts=5, smooth=False)
        k.blob((x + .1, y, h), (.6, .6, 1.2), slot(LEAF), g, seg=5, rings=3)
    done(g)
    g = 'bush'
    k.blob((0, 0, .5), (1.05, 1.05, .75), slot(LEAF), g, seg=7, rings=4)
    k.blob((.5, .2, .75), (.65, .65, .55), slot(LEAF2), g, seg=6, rings=3)
    done(g)
    g = 'house'
    k.box((0, 0, 1.6), (7, 6, 3.2), slot(WALL), g)
    k.tube((-3.8, 0, 4.2), (3.8, 0, 4.2), 2.75, slot(ROOF), g, verts=3, smooth=False).rotation_euler.rotate_axis('X', 0)
    windows(g, -2.6, 2.6, -3.03, .9, 2.5, 3, 1, 1.0, 1.0)
    k.box((1, -3.03, 1.0), (1, .05, 2), slot(WOOD), g)
    done(g)
    g = 'panel'
    k.box((0, 0, 12), (28, 12, 24), slot(WALL), g)
    for j in range(8):
        k.box((0, -6.02, 1.5 + j * 3), (28, .02, .22), slot(WALL2), g)
    windows(g, -13, 13, -6.04, 0, 24, 10, 8, 1.4, 1.4)
    k.box((0, 0, 24.2), (28.4, 12.4, .4), slot(ROOF), g)
    done(g)
    g = 'factory'
    k.box((0, 0, 8), (36, 22, 16), slot(WALL), g)
    for i in range(6):
        k.tube((-15 + i * 6, -11, 18.5), (-15 + i * 6, 11, 18.5), 3.4, slot(ROOF), g, verts=3, smooth=False)
    windows(g, -16, 16, -11.03, 4, 13, 8, 2, 2.4, 2.8)
    done(g)
    g = 'stack'
    k.tube((0, 0, 0), (0, 0, 34), 2.6, slot(WALL2), g, verts=8, r2=1.6, smooth=False)
    k.tube((0, 0, 26), (0, 0, 28), 2.0, slot(WALL), g, verts=8, smooth=False)
    k.tube((0, 0, 33), (0, 0, 34), 1.7, slot(DARK), g, verts=8, smooth=False)
    k.blob((0, 0, 34.2), (.4, .4, .4), glow(1, .2, .1), g, seg=5, rings=3)
    done(g)
    g = 'tower'
    k.box((0, 0, 30), (22, 22, 60), slot(WALL), g)
    for fy in (-11.04, 11.04):
        windows(g, -10, 10, fy, 0, 60, 8, 18, 1.4, 1.5)
    for fx in (-11.04, 11.04):
        for j in range(18):
            for i in range(8):
                if (i * 5 + j * 3) % 4:
                    k.box((fx, -9 + i * 2.6, 1.7 + j * 3.3), (.04, 1.4, 1.5), slot(WIN), g)
    done(g)
    g = 'lamp'
    k.tube((0, 0, 0), (0, 0, 8), .09, slot(METAL), g, verts=5, smooth=False)
    k.tube((0, 0, 8), (0, -1.5, 8.4), .05, slot(METAL), g, verts=5, smooth=False)
    k.box((0, -1.6, 8.35), (.25, .6, .12), glow(1, .85, .5), g)
    done(g)
    g = 'pole'
    k.tube((0, 0, 0), (0, 0, 8.5), .11, slot(WOOD), g, verts=5, smooth=False)
    k.box((0, 0, 8.0), (2, .1, .1), slot(WOOD), g)
    done(g)
    g = 'wpole'
    k.tube((0, 0, 0), (0, 0, 8), .1, slot(METAL), g, verts=5, smooth=False)
    k.box((0, 0, 7.6), (1.8, .08, .08), slot(METAL), g)
    k.ring((0, 0, 6.8), .4, .08, slot(DARK), g, seg=8, mseg=3, axis='z', smooth=False)
    done(g)
    g = 'post'
    k.box((0, 0, .5), (.12, .08, 1.0), hexc('#e8e8e0'), g)
    k.box((0, -.05, .85), (.12, .02, .18), glow(1, .75, .2), g)
    done(g)
    g = 'fence'
    for i in range(9):
        k.box((-2 + i * .5, 0, .7), (.1, .03, 1.4), slot(WOOD), g)
    for z in (.45, 1.05):
        k.box((0, 0, z), (4.2, .03, .1), slot(WOOD, .85), g)
    done(g)
    g = 'rail'
    k.box((0, 0, .6), (4.2, .05, .28), hexc('#a8acb0'), g)
    k.box((1.9, 0, .32), (.1, .1, .64), hexc('#6e7276'), g)
    k.box((-1.9, 0, .32), (.1, .1, .64), hexc('#6e7276'), g)
    done(g)
    g = 'conc'
    k.box((0, 0, 1.2), (4.2, .3, 2.4), slot(WALL), g)
    k.box((0, 0, 2.45), (4.2, .35, .1), slot(WALL2), g)
    done(g)
    g = 'wallb'
    k.box((0, 0, .5), (4.2, .6, 1.0), slot(WALL), g)
    k.box((0, -.31, .55), (4.2, .02, .16), slot(WIN), g)
    done(g)
    g = 'kiosk'
    k.box((0, 0, 1.3), (3.2, 2.4, 2.6), slot(WALL2), g)
    k.box((0, -1.22, 1.5), (2.6, .04, 1.1), slot(WIN), g)
    k.box((0, -.2, 2.72), (3.5, 3.0, .12), slot(ROOF), g)
    done(g)
    g = 'stop'
    k.box((0, .5, 2.3), (5, 1.8, .1), slot(ROOF), g)
    k.box((0, 1.2, 1.2), (4.8, .06, 2.2), slot(METAL), g)
    for x in (-2.3, 2.3):
        k.box((x, 0, 1.15), (.1, .1, 2.3), slot(METAL), g)
    k.box((0, .8, .5), (3, .4, .08), slot(WOOD), g)
    done(g)
    g = 'stall'
    k.box((0, 0, .55), (3, 1.6, 1.1), slot(WOOD), g)
    k.box((0, -.2, 2.35), (3.8, 2.4, .1), slot(ROOF), g, rot=(.14, 0, 0))
    for x in (-1.6, 1.6):
        k.box((x, -.9, 1.2), (.08, .08, 2.3), slot(METAL), g)
    done(g)
    g = 'trash'
    k.tube((0, 0, 0), (0, 0, 1.0), .35, slot(METAL), g, verts=8, smooth=False)
    done(g)
    g = 'barrel'
    k.tube((0, 0, 0), (0, 0, 1.0), .34, hexc('#b8541a'), g, verts=8, smooth=False)
    k.ring((0, 0, .5), .34, .02, slot(DARK), g, seg=8, mseg=3, axis='z', smooth=False)
    done(g)
    g = 'cafe'
    k.box((0, 0, 2), (12, 8, 4), slot(WALL), g)
    k.box((0, -4.03, 1.6), (10, .05, 2.2), slot(WIN), g)
    k.box((0, -4.1, 4.5), (9, .15, 1.2), glow(1, .35, .15), g)
    done(g)
    g = 'sign'
    k.tube((0, 0, 0), (0, 0, 2.3), .05, slot(METAL), g, verts=5, smooth=False)
    k.box((0, -.03, 2.5), (1.8, .04, .9), hexc('#2a66d9'), g)
    k.box((0, -.055, 2.5), (1.6, .01, .7), hexc('#f3eedf'), g)
    done(g)
    for i, c in enumerate(('#ff2e88', '#7ff5ff', '#ffc81f')):
        g = 'bill%d' % (i + 1)
        for x in (-3.5, 3.5):
            k.box((x, 0, 3), (.25, .25, 6), slot(METAL), g)
        k.box((0, 0, 7.5), (11, .3, 5), slot(DARK), g)
        v = c.lstrip('#')
        k.box((0, -.17, 7.5), (10, .04, 4.2), glow(int(v[:2], 16) / 255, int(v[2:4], 16) / 255, int(v[4:], 16) / 255), g)
        done(g)
    for i, (c, h) in enumerate(((WALL, 11), (WALL2, 14), (ROOF, 9))):
        g = 'tube%d' % (i + 1)
        k.box((0, 0, h / 2), (5, 14, h), slot(c), g)
        windows(g, -1.8, 1.8, -7.03, 1, h - .5, 2, max(2, int(h / 3)), 1.2, 1.5)
        k.box((0, -7.3, 3.2), (5.2, .6, .1), slot(ROOF), g)
        done(g)
    g = 'buffalo'
    k.blob((0, 0, 1.0), (.55, 1.05, .55), hexc('#3a3534'), g, seg=7, rings=5)
    k.blob((0, .95, 1.2), (.3, .42, .3), hexc('#3a3534'), g, seg=6, rings=4)
    for s in (-1, 1):
        k.tube((s * .15, 1.05, 1.42), (s * .6, 1.0, 1.55), .05, hexc('#d8d2c0'), g, verts=5, r2=.01, smooth=False)
        for y in (-.6, .6):
            k.tube((s * .3, y, .8), (s * .3, y, 0), .1, hexc('#2c2827'), g, verts=5, smooth=False)
    done(g)
    g = 'chev'
    k.tube((0, 0, 0), (0, 0, .9), .05, slot(METAL), g, verts=5, smooth=False)
    k.box((0, -.03, 1.25), (1.2, .03, .7), hexc('#ffc81f'), g)
    k.box((0, -.05, 1.25), (.4, .01, .55), hexc('#16151b'), g)
    done(g)
    # start and finish gantry, spans 19 m across all four lanes
    for g, c1 in (('start', '#ffc81f'), ('finish', '#f3eedf')):
        for x in (-9.6, 9.6):
            k.box((x, 0, 3.5), (.4, .4, 7), hexc('#2b2b33'), g)
        k.box((0, 0, 7.2), (19.6, .4, 1.5), hexc(c1), g)
        for i in range(20):
            if g == 'finish' or i % 2:
                k.box((-9.5 + i, -.22, 7.2 + (.38 if i % 2 else -.38)), (1, .03, .74), hexc('#16151b'), g)
        done(g)
    return export('decor', mat)


meta = {'bikes': {}}
for art in ARTS:
    meta['bikes'][art] = make_bike(art)
meta['rider'] = make_rider()
meta['weapons_kb'] = round(make_weapons() / 1024, 1)
meta['cars_kb'] = round(make_cars() / 1024, 1)
meta['decor_kb'] = round(make_decor() / 1024, 1)
json.dump(meta, open(os.path.join(OUT, 'models.json'), 'w'), indent=1)
print(json.dumps({k: (v['kb'] if isinstance(v, dict) and 'kb' in v else v) for k, v in meta.items() if k != 'bikes'}))
print({k: v['kb'] for k, v in meta['bikes'].items()})
