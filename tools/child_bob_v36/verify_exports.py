"""Exact named-consumer comparison of baseline, raw and final Bob exports."""
import hashlib
from decoded_facts import expand, digest

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def sharing(document, names):
    groups = [[use for use in group if use[0] in names]
              for group in document['aliases']]
    return sorted(group for group in groups if len(group) > 1)

def verify(original, raw, final, owned):
    a, b, c = [expand(path) for path in [original, raw, final]]
    assert a['root'] == b['root'] == c['root']
    assert a['meshes'].keys() == b['meshes'].keys() == c['meshes'].keys()
    protected = set(a['meshes']) - owned
    assert len(owned) == 25 and len(protected) == 314
    assert all(a['meshes'][name] == c['meshes'][name] for name in protected)
    assert all(b['meshes'][name] == c['meshes'][name] for name in owned)
    assert sharing(a, protected) == sharing(c, protected)
    assert sharing(b, owned) == sharing(c, owned)
    changed = sorted(name for name in a['meshes'] if a['meshes'][name] != c['meshes'][name])
    assert set(changed) == owned
    return {
        'status': 'pass',
        'files': [{'path': str(path), 'sha256': sha(path)} for path in [original, raw, final]],
        'protected_meshes_exact': 314, 'owned_meshes_exact_to_Blender': 25,
        'root_material_rig_exact': True, 'protected_sharing_exact': True,
        'owned_internal_sharing_exact_to_Blender': True,
        'accessor_counts_baseline_raw_final': [x['accessor_count'] for x in [a, b, c]],
        'raw_protected_drift': sorted(name for name in protected if a['meshes'][name] != b['meshes'][name]),
        'owned_uv_exact_to_baseline': {
            name: a['meshes'][name]['primitives'][0]['attributes']['TEXCOORD_0'] == c['meshes'][name]['primitives'][0]['attributes']['TEXCOORD_0']
            for name in sorted(owned)},
        'owned_indices_exact_to_baseline': {
            name: a['meshes'][name]['primitives'][0]['indices'] == c['meshes'][name]['primitives'][0]['indices']
            for name in sorted(owned)},
        'protected_payload_sha256': digest({name: a['meshes'][name] for name in sorted(protected)}),
        'changed_alias_groups': {
            'removed': [group for group in a['aliases'] if group not in c['aliases']],
            'added': [group for group in c['aliases'] if group not in a['aliases']]},
        'storage_identity_rule': 'Exact named decoded consumer values and projected protected sharing; numeric accessor IDs are storage. Only owned geometry may re-tessellate.'}
