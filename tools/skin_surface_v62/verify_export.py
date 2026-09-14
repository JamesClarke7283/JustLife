"""Verify actual GLB colours and exact preservation of every geometry accessor."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--baseline', type=Path, required=True)
p.add_argument('--candidate', type=Path, required=True)
p.add_argument('--report', type=Path, required=True)
a = p.parse_args()


class GLB:
    def __init__(self, path):
        self.raw = path.read_bytes()
        assert struct.unpack_from('<4sII', self.raw) == (b'glTF', 2, len(self.raw))
        offset = 12
        while offset < len(self.raw):
            size, kind = struct.unpack_from('<II', self.raw, offset)
            chunk = self.raw[offset + 8:offset + 8 + size]
            if kind == 0x4E4F534A:
                self.data = json.loads(chunk)
            elif kind == 0x004E4942:
                self.binary = chunk
            offset += 8 + size
        # Bone and attachment nodes can legitimately share names (Head).
        # Mesh object names are unique; compare the complete node list below.
        mesh_nodes = [n for n in self.data['nodes'] if 'mesh' in n]
        self.nodes = {n['name']: n for n in mesh_nodes}
        assert len(self.nodes) == len(mesh_nodes)

    def accessor(self, index):
        acc = self.data['accessors'][index]
        components = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[acc['type']]
        code = {5120: 'b', 5121: 'B', 5122: 'h', 5123: 'H', 5125: 'I', 5126: 'f'}[acc['componentType']]
        fmt = '<' + code * components
        width = struct.calcsize(fmt)
        if 'bufferView' in acc:
            view = self.data['bufferViews'][acc['bufferView']]
            start = view.get('byteOffset', 0) + acc.get('byteOffset', 0)
            stride = view.get('byteStride', width)
            data = bytearray(b''.join(self.binary[start + i * stride:start + i * stride + width] for i in range(acc['count'])))
        else:
            data = bytearray(acc['count'] * width)
        if 'sparse' in acc:
            sparse = acc['sparse']
            idx, val = sparse['indices'], sparse['values']
            index_view = self.data['bufferViews'][idx['bufferView']]
            value_view = self.data['bufferViews'][val['bufferView']]
            index_start = index_view.get('byteOffset', 0) + idx.get('byteOffset', 0)
            value_start = value_view.get('byteOffset', 0) + val.get('byteOffset', 0)
            index_fmt = '<' + {5121: 'B', 5123: 'H', 5125: 'I'}[idx['componentType']]
            index_size = struct.calcsize(index_fmt)
            last = -1
            for i in range(sparse['count']):
                target = struct.unpack_from(index_fmt, self.binary, index_start + i * index_size)[0]
                assert last < target < acc['count']
                last = target
                data[target * width:(target + 1) * width] = self.binary[value_start + i * width:value_start + (i + 1) * width]
        return acc, bytes(data), fmt

    def mesh(self, name):
        return self.data['meshes'][self.nodes[name]['mesh']]


old, new = GLB(a.baseline), GLB(a.candidate)
owned = {'Skin_Head_continuous': 'Skin_Face_Surface',
         'Eyes_Iris': 'Eyes_Iris_Surface', 'Eyes_Iris.001': 'Eyes_Iris_Surface',
         'Eyes_Sclera': 'Eyes_Sclera_Surface', 'Eyes_Sclera.001': 'Eyes_Sclera_Surface'}
assert old.nodes.keys() == new.nodes.keys()
assert len(old.data['nodes']) == len(new.data['nodes'])
for node, nn in zip(old.data['nodes'], new.data['nodes']):
    for key in ('name', 'children', 'translation', 'rotation', 'scale', 'matrix', 'skin', 'extras'):
        assert node.get(key) == nn.get(key), (node.get('name'), key)
checked, surfaces = 0, {}


def exact_accessor(before, after):
    global checked
    ac, av, af = old.accessor(before)
    bc, bv, bf = new.accessor(after)
    assert (ac['type'], ac['componentType'], ac['count'], ac.get('normalized', False), av) == (
        bc['type'], bc['componentType'], bc['count'], bc.get('normalized', False), bv)
    checked += 1


for name, node in old.nodes.items():
    nn = new.nodes[name]
    for key in ('translation', 'rotation', 'scale', 'matrix', 'skin', 'extras'):
        assert node.get(key) == nn.get(key), (name, key)
    if 'mesh' not in node:
        continue
    om, nm = old.mesh(name), new.mesh(name)
    assert om.get('extras') == nm.get('extras') and om.get('weights') == nm.get('weights'), name
    assert len(om['primitives']) == len(nm['primitives'])
    for op, np in zip(om['primitives'], nm['primitives']):
        assert set(np['attributes']) == set(op['attributes']) | ({'COLOR_0'} if name in owned else set()), name
        for semantic, index in op['attributes'].items():
            exact_accessor(index, np['attributes'][semantic])
        exact_accessor(op['indices'], np['indices'])
        assert len(op.get('targets', [])) == len(np.get('targets', []))
        for ot, nt in zip(op.get('targets', []), np.get('targets', [])):
            assert ot.keys() == nt.keys()
            for semantic, index in ot.items():
                exact_accessor(index, nt[semantic])
        mat = new.data['materials'][np['material']]
        if name not in owned:
            assert old.data['materials'][op['material']] == mat, ('Unowned material changed', name)
            continue
        assert mat['name'] == owned[name], (name, mat['name'])
        acc, raw, fmt = new.accessor(np['attributes']['COLOR_0'])
        values = list(struct.iter_unpack(fmt, raw))
        scale = {5121: 255., 5123: 65535.}.get(acc['componentType'], 1.) if acc.get('normalized') else 1.
        values = [tuple(v / scale for v in row) for row in values]
        assert len(values) == new.data['accessors'][np['attributes']['POSITION']]['count']
        assert len({tuple(round(v, 4) for v in row) for row in values}) > 8
        assert all(0 <= v <= 1 for row in values for v in row)
        base = mat['pbrMetallicRoughness']['baseColorFactor']
        assert base != [1., 1., 1., 1.], 'Recolourable authored factor lost'
        surfaces[name] = {'material': mat['name'], 'vertex_colors': len(values),
                          'base_factor': base, 'roughness': mat['pbrMetallicRoughness']['roughnessFactor']}

assert set(surfaces) == set(owned)
assert old.data['skins'] == new.data['skins']
report = {'baseline': str(a.baseline.resolve()), 'baseline_sha256': hashlib.sha256(old.raw).hexdigest(),
          'candidate': str(a.candidate.resolve()), 'candidate_sha256': hashlib.sha256(new.raw).hexdigest(),
          'geometry_accessors_exact': checked, 'node_transforms_extras_skins_exact': True,
          'unowned_materials_exact': True, 'surfaces': surfaces, 'passed': True}
a.report.parent.mkdir(parents=True, exist_ok=True)
a.report.write_text(json.dumps(report, indent=2) + '\n')
print('SKIN_SURFACE_EXPORT_PASS', json.dumps(report))
