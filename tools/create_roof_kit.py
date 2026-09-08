"""Original JustLife rectangular gable kit. Run with Blender in a private copy."""
import bpy,bmesh,json,math,hashlib,random,os
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];ART=ROOT/'art/architecture';OUT=ROOT/'assets/models';EVIDENCE=ROOT/'evidence'
parameters=json.loads((ART/'roof_parameters.json').read_text());EAVE=.28;SHELL=.10
h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
for data in list(bpy.data.materials):bpy.data.materials.remove(data)
bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=1
print('OWNED ROOF BLENDER PID',os.getpid(),flush=True)
def bl(p):return Vector((p[0],-p[2],p[1]))
def srgb(x):return ((x+.055)/1.055)**2.4 if x>.04045 else x/12.92
def material(name,color,rough=.72):
 m=bpy.data.materials.new(name);m.diffuse_color=tuple(int(color[i:i+2],16)/255 for i in [0,2,4])+(1,);m.use_nodes=True
 bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=tuple(srgb(int(color[i:i+2],16)/255) for i in [0,2,4])+(1,);bs.inputs['Roughness'].default_value=rough
 return m
palette={'cream':'e4dccb','oak':'927353','ridge':'40554e','tile':['57736a','526e64','5c776e','506b62']}
cream=material('Fascia_Cream',palette['cream']);oak=material('Soffit_Oak',palette['oak']);ridge=material('Ridge_Charcoal',palette['ridge']);tilemats=[material('RoofTile_Sage_%d'%i,c,.80) for i,c in enumerate(palette['tile'])]
audit=[]
def mesh(name,verts,faces,mats,parent=None,indices=None):
 data=bpy.data.meshes.new(name);data.from_pydata([bl(p) for p in verts],[],faces);data.update()
 for mat in mats:data.materials.append(mat)
 ob=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(ob)
 if parent:ob.parent=parent
 bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));nm=sum(not e.is_manifold for e in bm.edges);tiny=sum(f.calc_area()<1e-12 for f in bm.faces);bm.to_mesh(data);bm.free();assert nm==0 and tiny==0,(name,nm,tiny)
 if indices:
  for p,mi in zip(data.polygons,indices):p.material_index=mi
 uv=data.uv_layers.new(name='RoofUV')
 for poly in data.polygons:
  for li in poly.loop_indices:
   co=data.vertices[data.loops[li].vertex_index].co;uv.data[li].uv=(co.x,co.y)
 audit.append({'name':name,'vertices':len(verts),'triangles':sum(len(f)-2 for f in faces),'nonmanifold_edges':nm,'tiny_faces':tiny});return ob

def extrusion(name,profile,z0,z1,mat,parent):
 n=len(profile);vs=[(x,y,z) for z in [z0,z1] for x,y in profile];fs=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]
 for i in range(n):j=(i+1)%n;fs.append((i,j,n+j,n+i))
 return mesh(name,vs,fs,[mat],parent)
def box(name,lo,hi,mat,parent):
 return extrusion(name,[(lo[0],lo[1]),(hi[0],lo[1]),(hi[0],hi[1]),(lo[0],hi[1])],lo[2],hi[2],mat,parent)
def empty(name,position,parent=None):
 ob=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(ob);ob.location=bl(position)
 if parent:ob.parent=parent
 return ob
def descendants(root):
 yield root
 for ch in root.children:yield from descendants(ch)
def export(root,name):
 bpy.ops.object.select_all(action='DESELECT')
 for ob in descendants(root):ob.select_set(True)
 bpy.context.view_layer.objects.active=root
 path=OUT/name;bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,export_extras=True,export_apply=True,export_cameras=False,export_lights=False,export_animations=False,export_materials='EXPORT')
 return path

def tile_geometry(width,depth):
 # A closed bevel-edged slate tile with a thicker leading butt and gentle crown.
 b=min(.007,width*.12,depth*.12);poly=[(-width/2+b,-depth/2),(width/2-b,-depth/2),(width/2,-depth/2+b),(width/2,depth/2-b),(width/2-b,depth/2),(-width/2+b,depth/2),(-width/2,depth/2-b),(-width/2,-depth/2+b)]
 vs=[]
 for inset,layer in [(0,0),(0,1),(.002,2)]:
  for x,z in poly:
   xx=x*(1-2*inset/width);zz=z*(1-2*inset/depth);height=.012+.008*(.5-z/depth)
   vs.append((xx,0 if layer==0 else height-.003 if layer==1 else height,zz))
 vs.append((0,.019,0));fs=[tuple(range(7,-1,-1))]
 for ring in [0,1]:
  for j in range(8):k=(j+1)%8;fs.append((ring*8+j,ring*8+k,(ring+1)*8+k,(ring+1)*8+j))
 for j in range(8):fs.append((16+j,16+(j+1)%8,24))
 return vs,fs

fixtures=[]
for rec in parameters['fixtures']:
 assert all(isinstance(rec[k],(int,float)) and not isinstance(rec[k],bool) and math.isfinite(rec[k]) for k in ['w','d','pitch','rotation'])
 assert rec['w']>0 and rec['d']>0 and .2<=rec['pitch']<=1 and rec['rotation'] in [0,90]
 ident=rec['id'];span=rec['w'] if rec['rotation']==0 else rec['d'];length=rec['d'] if rec['rotation']==0 else rec['w'];p=rec['pitch'];sec=math.sqrt(1+p*p);sn=p/sec;cs=1/sec;H=p*span/2;X=span/2+EAVE;Z=length/2+EAVE
 top=lambda x:H-p*x+SHELL*sec
 root=empty('Roof_'+ident,(0,0,0));root.rotation_euler.z=math.radians(rec['rotation']);root['contract_version']=1
 for k,val in {'support_width':rec['w'],'support_depth':rec['d'],'pitch':p,'rotation_degrees':rec['rotation'],'canonical_span':span,'canonical_ridge_length':length,'eave':EAVE,'shell_thickness_normal':SHELL,'structural_ridge_height':H,'material_hex':rec['material'],'local_datum':'support wall-top; world Y=Building.level_y(level)+2.6'}.items():root[k]=val
 # The top external eave remains exactly X; lower edge offsets account for
 # the normal thickness, preserving fixed total plan overhang.
 lower_x=X-SHELL*sn;lower_y=H-p*lower_x
 for side,label in [(-1,'Left'),(1,'Right')]:
  profile=[(0,H),(side*lower_x,lower_y),(side*X,lower_y+SHELL*cs),(side*SHELL*sn,H+SHELL*cs)]
  extrusion('RoofDeck_'+label+'_'+ident,profile,-Z+.012,Z-.012,oak,root)
  fy=top(X)-.025
  box('EaveFascia_'+label+'_'+ident,(min(side*(X-.06),side*X),fy-.18,-Z+.10),(max(side*(X-.06),side*X),fy,Z-.10),cream,root)
  box('EaveOakLip_'+label+'_'+ident,(min(side*(X-.062),side*(X-.045)),fy-.18,-Z+.10),(max(side*(X-.062),side*(X-.045)),fy-.145,Z-.10),oak,root)
  for end in [-1,1]:
   za=end*(Z-.10);zb=end*Z
   extrusion('RakeFascia_%s_%s_%s'%(label,'Front' if end<0 else 'Back',ident),[(0,top(0)-.025),(side*X,fy),(side*X,fy-.18),(0,top(0)-.205)],min(za,zb),max(za,zb),cream,root)
 # Full triangular infill meets wall-top Y0 at both bearing endpoints. The
 # gable faces are inside the support rectangle, beneath the overhang.
 for end in [-1,1]:
  za=end*(length/2-.08);zb=end*(length/2)
  extrusion('GableInfill_%s_%s'%('Front' if end<0 else 'Back',ident),[(-span/2,0),(span/2,0),(0,H)],min(za,zb),max(za,zb),cream,root)
  box('GableOakTie_%s_%s'%(end,ident),(-span/2,.015,min(za,zb)-.004),(span/2,.085,max(za,zb)+.004),oak,root)
 # Ridge caps are true closed convex profiles in short segments, with a
 # subtle joint rhythm and no open tube at the gable end.
 ridge_width=min(.16,X*.28);profile_top=[]
 for j in range(9):
  x=-ridge_width+2*ridge_width*j/8;profile_top.append((x,top(abs(x))+.018+.047*(1-(x/ridge_width)**2)))
 profile=profile_top+[(x,y-.027) for x,y in reversed(profile_top)]
 segments=max(1,math.ceil((2*Z-.04)/.80));ridge_segment=(2*Z-.04)/segments
 for j in range(segments):
  z0=-Z+.02+j*ridge_segment;z1=z0+ridge_segment-.002
  extrusion('RidgeCap_%02d_%s'%(j,ident),profile,z0,z1,ridge,root)
 # Tiles retain their dimensions instead of being stretched with a roof.
 # End tiles are clipped by adjusting their authored rectangle before lofting.
 tileverts=[];tilefaces=[];tileindices=[];rng=random.Random(6817)
 rows=max(1,math.ceil((X-.065)*sec/.32));cols=max(1,math.ceil((2*Z-.04)/.36));row_span=(X-.065)/rows;col_span=(2*Z-.04)/cols
 for side in [-1,1]:
  for row in range(rows):
   xc=.04+row_span*(row+.5);depth=max(.01,row_span*sec-.005)
   for col in range(cols):
    zc=-Z+.02+col_span*(col+.5);width=max(.01,col_span-.006);vs,fs=tile_geometry(width,depth)
    normal=Vector((side*sn,cs,0));along=Vector((0,0,-side));down=Vector((side*cs,-sn,0));base=Vector((side*xc,top(xc)+.002,zc))
    offset=len(tileverts);tileverts.extend([tuple(base+along*x+normal*y+down*z) for x,y,z in vs]);tilefaces.extend([tuple(offset+i for i in face) for face in fs]);tileindices.extend([rng.randrange(len(tilemats))]*len(fs))
 mesh('RoofTiles_'+ident,tileverts,tilefaces,tilemats,root,tileindices)
 for side in [-1,1]:
  for end in [-1,1]:empty('Support_%s_%s_%s'%(side,end,ident),(side*span/2,0,end*length/2),root)
 empty('RidgeStart_'+ident,(0,H,-length/2),root);empty('RidgeEnd_'+ident,(0,H,length/2),root)
 bpy.context.view_layer.update();path=export(root,'roof_gable_'+ident+'.glb')
 coords=[ob.matrix_world@v.co for ob in descendants(root) if ob.type=='MESH' for v in ob.data.vertices];godotcoords=[(v.x,v.z,-v.y) for v in coords]
 bounds=[[min(v[i] for v in godotcoords),max(v[i] for v in godotcoords)] for i in range(3)]
 expected=[[-rec['w']/2-EAVE,rec['w']/2+EAVE],[top(X)-.205,H+SHELL*sec+.065],[-rec['d']/2-EAVE,rec['d']/2+EAVE]]
 assert all(abs(bounds[i][j]-expected[i][j])<1e-5 for i in range(3) for j in range(2)),(ident,bounds,expected)
 fixtures.append({'parameters':rec,'root':root.name,'canonical_span':span,'canonical_length':length,'structural_ridge_height':H,'actual_godot_bounds':bounds,'expected_godot_bounds':expected,'rows_per_slope':rows,'columns':cols,'tile_count':2*rows*cols,'glb':str(path.relative_to(ROOT)),'glb_sha256':h(path)})
# Reusable native-size tile and trim modules; parent may assemble variable
# roofs from the contract, without ever scaling shell thickness or tile size.
kit=empty('RoofModules',(0,0,0));vs,fs=tile_geometry(.36,.32);mesh('Tile_036x032',vs,fs,[tilemats[0]],kit)
box('Fascia_100',(-.03,-.18,-.50),(.03,0,.50),cream,kit)
box('OakLip_100',(-.0085,-.035,-.50),(.0085,0,.50),oak,kit)
kitpath=export(kit,'roof_gable_modules.glb')
bpy.context.preferences.filepaths.save_version=0;source=ART/'justlife_roof_kit.blend';bpy.ops.wm.save_as_mainfile(filepath=str(source))
contract={'version':1,'units':'metres','axes':'Godot X right, Y up, Z ridge at yaw0; Blender mapping=(x,-z,y)','origin':'Center of support footprint at wall-top Y0. Place at(x, Building.level_y(level)+2.6,z).','record_dimensions':'w/d are world support footprint; yaw0 span=w/length=d; yaw90 span=d/length=w, then +90Y yaw.','pitch':'rise/run; structural ridge H=pitch*span/2, shell underside meets wall top at support eave points.','eave':EAVE,'shell_thickness_normal':SHELL,'end_trim_offsets':{'deck_behind_rake_outer_face':.012,'eave_trim_behind_rake_outer_face':.10},'roof_envelope':'Plan bounds support rectangle grown0.28 each side. Structural ridge plus material cap height recorded per fixture.','formulas':{'sec':'sqrt(1+pitch*pitch)','X':'span/2+.28','Z':'length/2+.28','top_at_x':'H-pitch*abs(x)+.10*sec','minimum_y':'top_at_x(X)-.205','maximum_y':'H+.10*sec+.065','panel_lower_eave_x':'X-.10*pitch/sec','panel_lower_eave_y':'H-pitch*panel_lower_eave_x'},'parts':['two closed normal-thickness roof panels','two closed triangular gable infills at support ends','cream eave/rake fascia and oak lower lip/tie','closed segmented ridge cap','original bevel-edged sage slate tiles, cropped to edge extents'],'module_contract':{'Tile_036x032':{'size':[.36,.020,.32],'origin':'base center','local_axes':'X along ridge, Y outward from roof, Z downslope','slope_basis':'X=(0,0,-side), Y=(side*pitch/sec,1/sec,0), Z=(side/sec,-pitch/sec,0)','placement':'(side*xc, top_at_x(xc)+.002, zc)'},'Fascia_100':{'size':[.06,.18,1.0],'origin':'upper edge center','scale':'Z length only; thickness/height fixed'},'OakLip_100':{'size':[.017,.035,1.0],'origin':'upper edge center','scale':'Z length only'}},'palette':palette,'fixtures':fixtures,'modules_glb_sha256':h(kitpath),'source_sha256':h(source),'generator_sha256':h(Path(__file__)),'mesh_audit':audit,'limitations':'Rectangular gables only. No valleys/dormers/intersecting junctions, weatherproofing or structural-engineering certification. Runtime must validate full eave/headroom envelope independently of current support rectangle schema.'}
(ART/'roof_geometry_contract.json').write_text(json.dumps(contract,indent=2)+'\n');print('ROOF KIT COMPLETE',h(source),[(f['parameters']['id'],f['tile_count']) for f in fixtures],flush=True)
