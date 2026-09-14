"""Prove decoded non-Bob primitives and the skeleton survived the Bob export."""
import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'child_bob_v36'))
from decoded_gltf import decoded_document

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--before', type=Path, required=True)
p.add_argument('--after', type=Path, required=True)
p.add_argument('--report', type=Path, required=True)
a = p.parse_args()
left, right = decoded_document(a.before), decoded_document(a.after)


def node_map(doc):
    return {n['name']: n for n in doc['nodes']}


def values(doc, accessor, indices=None):
    v = doc['accessors'][accessor]['decoded_values']
    return v if indices is None else [v[i] for i in indices]


def primitives(doc, node):
    if 'mesh' not in node:
        return []
    return doc['meshes'][node['mesh']]['primitives']


def skin(doc, item):
    return {'joints': [doc['nodes'][i]['name'] for i in item['joints']],
            'inverse_bind': values(doc, item['inverseBindMatrices'])}


ln, rn = node_map(left), node_map(right)
protected = sorted(n for n in ln if not n.startswith('Hair_Bob_'))
assert set(protected) == {n for n in rn if not n.startswith('Hair_Bob_')}
checked_primitives = 0; checked_targets = 0
for name in protected:
    n1, n2 = ln[name], rn[name]
    # Children are references and move when the Bob subtree is replaced. All
    # scalar/local transform metadata stays exact for every protected node.
    excluded = ('children', 'mesh', 'skin')
    assert {k:v for k,v in n1.items() if k not in excluded} == \
           {k:v for k,v in n2.items() if k not in excluded}, name
    if name != 'Hair_Bob':
        assert [left['nodes'][i]['name'] for i in n1.get('children', [])] == \
               [right['nodes'][i]['name'] for i in n2.get('children', [])], name
    p1, p2 = primitives(left, n1), primitives(right, n2)
    assert len(p1) == len(p2), name
    if 'mesh' in n1:
        assert left['meshes'][n1['mesh']].get('extras') == right['meshes'][n2['mesh']].get('extras'), name
    for i, (x, y) in enumerate(zip(p1, p2)):
        label = name + '/' + str(i)
        ix = [v[0] for v in values(left, x['indices'])]
        iy = [v[0] for v in values(right, y['indices'])]
        assert len(ix) == len(iy), label
        assert set(x['attributes']) == set(y['attributes']), label
        assert left['materials'][x['material']] == right['materials'][y['material']], label
        for key in x['attributes']:
            assert values(left, x['attributes'][key], ix) == values(right, y['attributes'][key], iy), (label, key)
        assert len(x.get('targets', [])) == len(y.get('targets', [])), label
        for j, (tx, ty) in enumerate(zip(x.get('targets', []), y.get('targets', []))):
            assert set(tx) == set(ty), (label, j)
            for key in tx:
                assert values(left, tx[key], ix) == values(right, ty[key], iy), (label, j, key)
            checked_targets += 1
        checked_primitives += 1

assert [skin(left, s) for s in left.get('skins', [])] == [skin(right, s) for s in right.get('skins', [])]
report = {'before': str(a.before), 'after': str(a.after),
          'protected_nodes': len(protected), 'protected_primitives': checked_primitives,
          'protected_morph_targets': checked_targets, 'skeleton_exact': True,
          'bob_nodes_before': sorted(n for n in ln if n.startswith('Hair_Bob_')),
          'bob_nodes_after': sorted(n for n in rn if n.startswith('Hair_Bob_')),
          'result': 'All decoded non-Bob primitives, morphs, materials and skeleton are exact'}
a.report.parent.mkdir(parents=True, exist_ok=True)
a.report.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
