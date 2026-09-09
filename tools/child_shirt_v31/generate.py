"""Reproduce the bounded child shirt from pinned native source and accepted GLBs.

python generate.py --source ORIGINAL_CHILD_BLEND --baseline-models ORIGINAL_GLB_DIR
                   --output NEW_DIRECTORY [--blender blender]

All paths are explicit inputs. The output must be new and cannot contain inputs.
The four baseline GLBs are retained because a fresh unchanged standard LOD export
has seven unrelated hair UV differences; only authored shirt data is transferred.
"""
import argparse,copy,hashlib,json,shutil,subprocess,sys,time
from pathlib import Path
from transfer_shirt import transfer
P=Path(__file__).resolve().parent
C=json.loads((P/'native_contract.json').read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def run(command,log,marker):
 start=time.monotonic()
 with log.open('w')as f:r=subprocess.run(command,stdout=f,stderr=subprocess.STDOUT)
 result={'command':command,'returncode':r.returncode,'seconds':time.monotonic()-start,'log_sha256':sha(log),'marker_present':marker in log.read_text()}
 assert r.returncode==0 and result['marker_present'],f'Failed process retained in {log}'
 return result
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--source',type=Path,required=True);parser.add_argument('--baseline-models',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--blender',default='blender');args=parser.parse_args()
source=args.source.resolve();base=args.baseline_models.resolve();out=args.output.resolve()
assert not out.exists(),'Choose a new output directory'
assert out not in source.parents and out!=source and out not in base.parents and out!=base
assert sha(source)==C['source_sha256']
for stem,pin in C['baseline_glbs'].items():assert sha(base/(stem+'.glb'))==pin,stem
for name in ['art','assets/models','evidence','raw_exports']:(out/name).mkdir(parents=True,exist_ok=True)
launch={'input_source_sha256':sha(source),'input_glbs':C['baseline_glbs'],'script_pins':{f.name:sha(f)for f in sorted(P.glob('*'))if f.is_file()},'runs':[],'transfers':[]}
def blender(script,*arguments):return [args.blender,'--background','--factory-startup','-t','1','--python-exit-code','2','--python',str(P/script),'--',*map(str,arguments)]
launch['runs'].append(run(blender('native_witness.py','--source',source,'--output',out/'evidence/baseline_native.json'),out/'evidence/baseline_witness.log','CHILD_NATIVE_WITNESS_OK'))
launch['runs'].append(run(blender('sculpt.py','--source',source,'--output',out/'native_stage'),out/'evidence/sculpt.log','CHILD_SHIRT_SCULPT_OK'))
blend=out/'art/characters_child.blend';shutil.copy2(out/'native_stage/characters_child.blend',blend)
launch['runs'].append(run(blender('native_witness.py','--source',blend,'--output',out/'evidence/candidate_native.json'),out/'evidence/candidate_witness.log','CHILD_NATIVE_WITNESS_OK'))
a=json.loads((out/'evidence/baseline_native.json').read_text());b=json.loads((out/'evidence/candidate_native.json').read_text())
assert a['native_signature']==C['baseline_native_signature'] and b['native_signature']==C['candidate_native_signature']
assert a['scene']==b['scene'],'Authored startup scene, object membership and camera changed'
assert set(a['facts']['objects'])==set(b['facts']['objects'])
owned=C['scope']['object']
for name,old in a['facts']['objects'].items():
 new=b['facts']['objects'][name]
 assert old==new if name!=owned else {k:v for k,v in old.items()if k!='geometry_sha256'}=={k:v for k,v in new.items()if k!='geometry_sha256'},name
for key,value in a['facts']['owned'][owned].items():
 if key!='mesh_positions':assert value==b['facts']['owned'][owned][key],key
material_expected=copy.deepcopy(a['materials']);assert material_expected['Hair_shadow']['rna']['use_fake_user'] is False
material_expected['Hair_shadow']['rna']['use_fake_user']=True;assert material_expected==b['materials']
protection={'input_native_signature':a['native_signature'],'output_native_signature':b['native_signature'],'protected_objects_exact':361,'owned_topology_uv_weights_metadata_exact':True,'material_content_exact':True,'declared_maintenance_flag':C['scope']['material_flag'],'startup_scene_exact':True}
(out/'evidence/native_protection.json').write_text(json.dumps(protection,indent=2)+'\n')
for stem in C['baseline_glbs']:
 launch['runs'].append(run(blender('export_variant.py','--source',blend,'--source-sha256',sha(blend),'--output-root',out/'raw_exports','--variant',stem),out/'evidence'/('export_'+stem+'.log'),'ONE_CHILD_VARIANT_COMPLETE '+stem))
 result=transfer(base/(stem+'.glb'),out/'raw_exports'/(stem+'.glb'),out/'assets/models'/(stem+'.glb'),out/'evidence'/('transfer_'+stem+'.json'));launch['transfers'].append(result)
 assert result['output_sha256']==C['candidate_glbs'][stem],'Output differs from frozen visually qualified candidate: '+stem
assert sha(source)==C['source_sha256']
for stem,pin in C['baseline_glbs'].items():assert sha(base/(stem+'.glb'))==pin
launch['output_source_sha256']=sha(blend);launch['output_glbs']=C['candidate_glbs'];launch['source_inputs_unchanged']=True;launch['scope']=C['scope']
(out/'evidence/reproduction.json').write_text(json.dumps(launch,indent=2)+'\n')
print('CHILD_SHIRT_REPRODUCTION_OK 4 exact GLBs; 361 protected native objects; 338 protected exported meshes per variant')
