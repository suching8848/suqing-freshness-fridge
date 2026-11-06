"""Read back shipped binary assets, meshes and mappings; never start the game."""
from pathlib import Path
import io, json, hashlib, struct
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
MEDIA=ROOT/'mods/SuQingFreshnessFridge/42/media'
ART=ROOT/'art/model'
SHEET='suqing_freshness_fridge_01'
NAMES=[f'{SHEET}_{i}' for i in range(4)]
checks=[]
def check(condition,label):
    if not condition: raise AssertionError(label)
    checks.append(label)
def ri(f):
    b=f.read(4);check(len(b)==4,'complete little-endian integer');return struct.unpack('<i',b)[0]
def rs(f):
    n=ri(f);check(0<=n<100000,'valid string length');return f.read(n).decode('utf-8')
def line(f):
    b=f.readline();check(b.endswith(b'\n'),'terminated tile-property string');return b[:-1].decode('ascii')

packpath=MEDIA/'texturepacks/SuQingFreshnessFridge_tiles.pack'
f=io.BytesIO(packpath.read_bytes())
check(f.read(4)==b'PZPK','PZPK magic')
check(ri(f)==1,'pack version 1')
check(ri(f)==1,'exactly one page')
check(rs(f)=='SuQingFreshnessFridge_tiles_0','page name')
check(ri(f)==4,'four subtextures')
check(ri(f)==1,'RGBA page')
subtextures=[]
for i in range(4):
    name=rs(f);rect=struct.unpack('<8i',f.read(32));subtextures.append((name,rect))
    check(name==NAMES[i],f'subtexture name {i}')
    check(rect==(i*128,0,128,256,0,0,128,256),f'complete sprite rectangle and origin {i}')
pnglen=ri(f);png=f.read(pnglen)
check(len(png)==pnglen and not f.read(),'pack image length/eof')
page=Image.open(io.BytesIO(png));page.load()
check(page.mode=='RGBA' and page.size==(512,256),'decoded page image')
for i in range(4):
    shipped=Image.open(MEDIA/f'textures/SuQingFreshnessFridge/{NAMES[i]}.png').convert('RGBA')
    check(page.crop((i*128,0,(i+1)*128,256)).tobytes()==shipped.tobytes(),f'packed and source pixels identical {i}')
    check(shipped.getbbox() is not None,f'nonempty sprite {i}')
    box=shipped.getbbox();check(box[0]>0 and box[2]<128 and box[1]>0 and box[3]<256,f'no clipped sprite {i}')
check(len({hashlib.sha256(page.crop((i*128,0,(i+1)*128,256)).tobytes()).hexdigest() for i in range(4)})==4,'four distinct views')

f=io.BytesIO((MEDIA/f'{SHEET}.tiles').read_bytes())
check(f.read(4)==b'tdef','tile magic')
check(ri(f)==1 and ri(f)==1,'tile version and set count')
check(line(f)==SHEET and line(f)==SHEET+'.png','tileset names')
check(tuple(ri(f) for _ in range(4))==(4,1,1,4),'tileset dimensions, id, count')
for i in range(4):
    count=ri(f);props={}
    for _ in range(count):
        key=line(f);value=line(f);props[key]=value
    check(props.get('Facing')==['S','E','N','W'][i],f'direction {i}')
    check(props.get('container')=='fridge' and 'IsFridge' in props,f'native fridge properties {i}')
    check('Freezer' not in props and 'FreezerCapacity' not in props,f'no freezer {i}')
    check(props.get('ContainerCapacity')=='200',f'initial capacity {i}')
    check(props.get('CustomItem')=='SuQingFreshnessFridge.Mov_FreshnessFridge',f'explicit moveable item {i}')
    check({'IsMoveAble','solidtrans','BlocksPlacement'}<=props.keys(),f'placement/moving properties {i}')
check(not f.read(),'tile file EOF')

model=MEDIA/'models/SuQingFreshnessFridge';verts=[];uvs=[];faces=[]
for line_ in (model/'fridge.obj').read_text().splitlines():
    s=line_.split()
    if not s:continue
    if s[0]=='v':verts.append([float(x) for x in s[1:]])
    if s[0]=='vt':uvs.append([float(x) for x in s[1:]])
    if s[0]=='f':faces.append([[int(x) for x in p.split('/')] for p in s[1:]])
v=np.array(verts);uv=np.array(uvs)
check(np.isfinite(v).all() and np.isfinite(uv).all(),'finite mesh and UV')
check(v.shape==(1180,3) and len(faces)==562,'mesh geometry count')
check((v.min(axis=0)>=np.array([-.5,-.5,0])).all() and (v.max(axis=0)<=np.array([.5,.5,1])).all(),'Z-up one-tile footprint with floor at zero')
check(uv.min()>=0 and uv.max()<=1,'UV inside original atlas')
for face in faces:
    check(len(face)==3 and all(1<=p[0]<=len(v) and 1<=p[1]<=len(uv) for p in face),'valid triangle indices')
    a,b,c=[v[p[0]-1] for p in face]
    check(np.linalg.norm(np.cross(b-a,c-a))>1e-10,'nondegenerate triangle')
check('map_Kd fridge_atlas.png' in (model/'fridge.mtl').read_text(),'resolvable material texture')
atlas=Image.open(model/'fridge_atlas.png');atlas.load()
check(atlas.size==(1024,1024),'atlas decode')
vp=MEDIA/'viewpoint';props={}
for line_ in (vp/'package.properties').read_text().splitlines():
    if '=' in line_ and not line_.startswith('#'):
        key,value=line_.split('=',1);props[key]=value
check(props['model.suqing_fridge']=='fridge.obj','safe sibling model path')
for name in ['fridge.obj','fridge.mtl','fridge_atlas.png']:
    check((vp/name).read_bytes()==(model/name).read_bytes(),f'Viewpoint asset matches canonical {name}')
for i,degrees in enumerate([0,-90,180,90]):
    check(props[f'bind.{NAMES[i]}']==f'suqing_fridge,{degrees},0,0,0,1',f'Viewpoint explicit facing {i}')
icon=Image.open(MEDIA/'textures/Item_SuQingFreshnessFridge.png');icon.load()
check(icon.size==(128,128) and icon.getbbox() is not None,'usable inventory/build icon')

assets=[p for p in (MEDIA/'models').rglob('*') if p.is_file()]+[p for p in vp.rglob('*') if p.is_file()]+[packpath,MEDIA/f'{SHEET}.tiles']
report={'result':'PASS','assertions':len(checks),'meaningful_checks':sorted(set(checks)),
        'scope':'Offline binary/PNG/OBJ/MTL/four-facing mapping verification; no OpenGL or game launch.',
        'files':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in assets}}
(ART/'asset_validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in report.items() if k!='files'},indent=2))
