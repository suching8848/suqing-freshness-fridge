"""Build original SuQing fridge mesh, four matching sprites, PZ pack/tiledef.

Pure offline asset authoring. Does not launch or connect to Project Zomboid.
Only Python, numpy and Pillow are required. Coordinates: X east, Y up, Z south.
"""
from __future__ import annotations
import io, json, math, struct, hashlib
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / 'mods/SuQingFreshnessFridge/42/media'
ART = ROOT / 'art/model'
MODEL = MEDIA / 'models/SuQingFreshnessFridge'
SPRITES = MEDIA / 'textures/SuQingFreshnessFridge'
SHEET = 'suqing_freshness_fridge_01'
PACK = 'SuQingFreshnessFridge_tiles'
FACING = ['S', 'E', 'N', 'W']
# ObjReader flips source horizontal axes into Viewpoint's renderer space.
# Current native mini-fridge binds S=0, E=-90, N=180, W=90.
VIEWPOINT_ROTATION = [0, -90, 180, 90]
TILEDEF_NUMBER = 7825
for directory in [ART, MODEL, SPRITES, MEDIA/'viewpoint', MEDIA/'texturepacks', MEDIA/'lua/client']:
    directory.mkdir(parents=True, exist_ok=True)

def font(size, bold=False):
    return ImageFont.truetype('C:/Windows/Fonts/' + ('arialbd.ttf' if bold else 'arial.ttf'), size)

# Original texture atlas: subdued enamel, lilac control trim, an analog clock.
atlas = Image.new('RGBA', (1024, 1024), (255, 0, 255, 255))
draw = ImageDraw.Draw(atlas)
regions = {}
palette = {
    'enamel': (222, 223, 220), 'side': (208, 211, 208),
    'purple': (126, 111, 155), 'lightpurple': (173, 160, 193),
    'seam': (61, 57, 70), 'metal': (176, 179, 178),
    'vent': (65, 67, 72), 'black': (39, 43, 48),
}
rng = np.random.default_rng(20261105)
for index, (key, color) in enumerate(palette.items()):
    x, y = (index % 4)*128, (index//4)*128
    noise = rng.normal(0, 1.25, (128,128,1))
    a = np.clip(np.array(color)[None,None,:]+noise, 0,255).astype('uint8')
    tile = Image.fromarray(a, 'RGB').convert('RGBA')
    td = ImageDraw.Draw(tile)
    td.line((0,127,127,127), fill=tuple(max(0,c-12) for c in color), width=2)
    atlas.paste(tile, (x,y))
    regions[key] = (x+3,y+3,x+125,y+125)

# Rectangular control-panel artwork, made for both model and sprite readability.
panel = Image.new('RGBA', (512,256),(124,109,154,255)); pd=ImageDraw.Draw(panel)
pd.rounded_rectangle((7,7,505,249),16,fill=(139,123,166),outline=(102,91,124),width=4)
pd.rectangle((28,42,161,156),fill=(42,47,55),outline=(193,182,207),width=3)
pd.text((45,61),'04:00',font=font(34,True),fill=(182,225,218))
pd.text((49,113),'FRESH',font=font(18,True),fill=(186,197,203))
for cx,color in [(48,(108,206,183)),(84,(214,194,120)),(120,(175,159,198))]:
    pd.ellipse((cx-8,181,cx+8,197),fill=color,outline=(65,63,75),width=2)
pd.text((206,195),'SUQING',font=font(20,True),fill=(225,222,234))
pd.text((388,193),'REV. 1',font=font(15),fill=(211,204,224))
atlas.paste(panel,(0,256)); regions['panel']=(0,256,512,512)

clock=Image.new('RGBA',(256,256),(232,230,220,255)); cd=ImageDraw.Draw(clock)
cd.ellipse((4,4,251,251),fill=(222,218,204),outline=(96,83,116),width=6)
cd.ellipse((16,16,239,239),fill=(239,237,225),outline=(171,160,174),width=2)
for n in range(60):
    a=math.pi*n/30; r0=98 if n%5 else 87
    cd.line((128+math.sin(a)*r0,128-math.cos(a)*r0,128+math.sin(a)*106,128-math.cos(a)*106),fill=(105,89,127),width=3 if n%5 else 6)
cd.line((128,128,128,59),fill=(95,72,120),width=7)
cd.line((128,128,174,150),fill=(95,72,120),width=10)
cd.line((128,128,85,85),fill=(110,166,157),width=3)
cd.ellipse((119,119,137,137),fill=(143,118,166))
atlas.paste(clock,(512,256));regions['clock']=(512,256,768,512)

logo=Image.new('RGBA',(256,128),(222,223,220,255)); ld=ImageDraw.Draw(logo)
ld.text((21,19),'SUQING',font=font(42,True),fill=(119,100,149))
ld.text((24,76),'FRESHNESS SYSTEM',font=font(18),fill=(126,130,131))
atlas.paste(logo,(768,256));regions['logo']=(768,256,1024,384)

# Back condenser and grille use geometry as well as original material texture.
grille=Image.new('RGBA',(256,128),(60,62,68,255)); gd=ImageDraw.Draw(grille)
for y in range(8,128,13):
    gd.rectangle((8,y,247,y+5),fill=(29,31,37))
    gd.line((9,y+6,245,y+6),fill=(95,94,100),width=1)
atlas.paste(grille,(768,384));regions['grille']=(768,384,1024,512)
atlas.save(MODEL/'fridge_atlas.png')

verts=[]; uv=[]; faces=[]
def mapped_uv(material, u, v):
    x0,y0,x1,y1=regions[material]
    return ((x0+(x1-x0)*u)/1024, 1-(y0+(y1-y0)*v)/1024)

def polygon(points, material, coords=None):
    start=len(verts)
    if coords is None:
        coords=[(0,1),(1,1),(1,0),(0,0)] if len(points)==4 else [(0.5,0.5)]+[(0,0)]*(len(points)-1)
    verts.extend(points); uv.extend(mapped_uv(material,*c) for c in coords)
    for i in range(1,len(points)-1): faces.append((start,start+i,start+i+1))

def box(cx,cy,cz,w,h,d,material,front=None):
    x0,x1=cx-w/2,cx+w/2;y0,y1=cy-h/2,cy+h/2;z0,z1=cz-d/2,cz+d/2
    polygon([(x0,y0,z1),(x1,y0,z1),(x1,y1,z1),(x0,y1,z1)],front or material)
    polygon([(x1,y0,z0),(x0,y0,z0),(x0,y1,z0),(x1,y1,z0)],material)
    polygon([(x1,y0,z1),(x1,y0,z0),(x1,y1,z0),(x1,y1,z1)],material)
    polygon([(x0,y0,z0),(x0,y0,z1),(x0,y1,z1),(x0,y1,z0)],material)
    polygon([(x0,y1,z1),(x1,y1,z1),(x1,y1,z0),(x0,y1,z0)],material)
    polygon([(x0,y0,z0),(x1,y0,z0),(x1,y0,z1),(x0,y0,z1)],material)

def bevelbox(cx,cy,cz,w,h,d,b,material):
    x0,x1=cx-w/2,cx+w/2;y0,y1=cy-h/2,cy+h/2;z0,z1=cz-d/2,cz+d/2
    shape=[(x0+b,y0+b),(x1-b,y0+b),(x1-b,y1-b),(x0+b,y1-b)]
    outer=[(x0,y0),(x1,y0),(x1,y1),(x0,y1)]
    rings=[[(x,y,z) for x,y in s] for s,z in [(shape,z1),(outer,z1-b),(outer,z0+b),(shape,z0)]]
    polygon(rings[0],material)
    polygon(list(reversed(rings[3])),material)
    for a,b_ in zip(rings,rings[1:]):
        for j in range(4): polygon([a[j],b_[j],b_[(j+1)%4],a[(j+1)%4]],material)

def plane(x0,y0,x1,y1,z,material):
    polygon([(x0,y0,z),(x1,y0,z),(x1,y1,z),(x0,y1,z)],material)

def cylinder_front(cx,cy,z,radius,depth,material,n=40,face=None):
    for j in range(n):
        a,b=2*math.pi*j/n,2*math.pi*(j+1)/n
        p0=(cx+radius*math.cos(a),cy+radius*math.sin(a),z)
        p1=(cx+radius*math.cos(b),cy+radius*math.sin(b),z)
        polygon([p0,(p0[0],p0[1],z-depth),(p1[0],p1[1],z-depth),p1],material)
        polygon([(cx,cy,z),p0,p1],face or material,[(.5,.5),(.5+.5*math.cos(a),.5-.5*math.sin(a)),(.5+.5*math.cos(b),.5-.5*math.sin(b))])

# Compact original low refrigerator, about the vanilla mini-fridge's proportions.
for x in [-.235,.235]:
    for z in [-.225,.225]: box(x,.032,z,.076,.064,.076,'black')
bevelbox(0,.445,0,.64,.79,.59,.018,'side')
box(0,.08,.012,.65,.045,.60,'seam')
bevelbox(0,.818,0,.66,.055,.61,.013,'lightpurple')
# Door seal and the large cream enamel door; handle mounted on its right edge.
box(0,.444,.304,.608,.684,.025,'seam')
bevelbox(0,.444,.329,.59,.665,.045,.014,'enamel')
bevelbox(0,.720,.362,.553,.119,.018,.007,'purple')
plane(-.267,.665,.267,.776,.373,'panel')
cylinder_front(.065,.722,.382,.047,.011,'metal',40,'clock')
box(.245,.465,.370,.020,.21,.024,'metal')
box(.245,.365,.357,.024,.025,.028,'purple')
box(.245,.565,.357,.024,.025,.028,'purple')
plane(-.125,.495,.155,.610,.354,'logo')
plane(-.252,.125,.252,.205,.354,'grille')
for x in [-.245,.245]:
    cylinder_front(x,.224,.356,.006,.003,'metal',8)
# Back compressor/vent and visible condenser tubes, independently modeled.
box(0,.28,-.305,.49,.30,.023,'vent')
for x in np.linspace(-.20,.20,8): box(float(x),.39,-.324,.012,.38,.012,'seam')
for y in [.22,.34,.46,.58]: box(0,y,-.328,.44,.009,.014,'metal')
box(.15,.14,-.315,.15,.09,.08,'black')

v=np.array(verts,dtype=float); t=np.array(uv,dtype=float)
# The installed Viewpoint 0.1.6.1 packs use PZ coordinates, Z up. Keep the
# renderer's Y-up geometry internal, and explicitly convert exported geometry.
export_v=v[:,[0,2,1]]
export_faces=[(f[0],f[2],f[1]) for f in faces]
obj=['# Original SuQing Freshness Fridge. X east, Y south, Z up; one unit = one tile.', 'mtllib fridge.mtl','o SuQingFreshnessFridge','usemtl fridge_atlas']
obj += ['v %.7f %.7f %.7f'%tuple(p) for p in export_v]
obj += ['vt %.7f %.7f'%tuple(p) for p in t]
for f in export_faces:
    a,b,c=export_v[list(f)];normal=np.cross(b-a,c-a);normal/=np.linalg.norm(normal)
    obj.append('vn %.7f %.7f %.7f'%tuple(normal))
obj += ['f '+' '.join(f'{i+1}/{i+1}/{n+1}' for i in f) for n,f in enumerate(export_faces)]
(MODEL/'fridge.obj').write_text('\n'.join(obj)+'\n',encoding='ascii')
(MODEL/'fridge.mtl').write_text('newmtl fridge_atlas\nKa 1 1 1\nKd 1 1 1\nKs 0.12 0.12 0.12\nNs 22\nd 1\nillum 2\nmap_Kd fridge_atlas.png\n',encoding='ascii')

def rotate_y(points,degrees):
    a=math.radians(degrees);c,s=math.cos(a),math.sin(a)
    return points@np.array([[c,0,-s],[0,1,0],[s,0,c]])

def render(degrees=0,size=(512,768),scale=300,origin=None,background=None):
    """Orthographic isometric z-buffer renderer of the exported textured mesh."""
    w,h=size;origin=origin or (w*.5,h*.83)
    points=rotate_y(v,degrees)
    # Matches PZ tile projection: 128px diamond, 64px diamond height.
    px=(points[:,0]-points[:,2])*scale+origin[0]
    py=(points[:,0]+points[:,2])*scale*.5-points[:,1]*scale*1.5+origin[1]
    depth=points[:,0]+points[:,2]+points[:,1]*1.3
    out=np.zeros((h,w,4),dtype=np.uint8)
    if background is not None: out[:]=background
    zbuf=np.full((h,w),-1e10)
    tex=np.asarray(atlas)
    light=np.array([-.25,.85,.75]);light/=np.linalg.norm(light)
    for face in faces:
        ids=np.array(face);a,b,c=points[ids]
        normal=np.cross(b-a,c-a); norm=np.linalg.norm(normal)
        if norm<1e-10:continue
        normal/=norm
        shade=.72+.30*max(0,np.dot(normal,light))
        x=px[ids];y=py[ids];zz=depth[ids]
        xa=max(0,int(np.floor(x.min())));xb=min(w-1,int(np.ceil(x.max())))
        ya=max(0,int(np.floor(y.min())));yb=min(h-1,int(np.ceil(y.max())))
        if xb<xa or yb<ya:continue
        xx,yy=np.meshgrid(np.arange(xa,xb+1)+.5,np.arange(ya,yb+1)+.5)
        den=(y[1]-y[2])*(x[0]-x[2])+(x[2]-x[1])*(y[0]-y[2])
        if abs(den)<1e-9:continue
        q0=((y[1]-y[2])*(xx-x[2])+(x[2]-x[1])*(yy-y[2]))/den
        q1=((y[2]-y[0])*(xx-x[2])+(x[0]-x[2])*(yy-y[2]))/den;q2=1-q0-q1
        inside=(q0>=-1e-7)&(q1>=-1e-7)&(q2>=-1e-7)
        dz=q0*zz[0]+q1*zz[1]+q2*zz[2]
        target=zbuf[ya:yb+1,xa:xb+1];mask=inside&(dz>target)
        if not mask.any():continue
        fu=q0*t[ids[0],0]+q1*t[ids[1],0]+q2*t[ids[2],0]
        fv=q0*t[ids[0],1]+q1*t[ids[1],1]+q2*t[ids[2],1]
        tx=np.clip((fu*1024).astype(int),0,1023);ty=np.clip(((1-fv)*1024).astype(int),0,1023)
        colors=tex[ty,tx].copy();colors[:,:,:3]=np.clip(colors[:,:,:3]*shade,0,255).astype('uint8')
        mask &= colors[:,:,3]>0
        out[ya:yb+1,xa:xb+1][mask]=colors[mask];target[mask]=dz[mask]
    return Image.fromarray(out,'RGBA')

sprites=[]
for index,facing in enumerate(FACING):
    sprite=render(index*90,(512,1024),256,(256,896)).resize((128,256),Image.Resampling.LANCZOS)
    sprite.save(SPRITES/f'{SHEET}_{index}.png');sprites.append(sprite)

item_icon=render(0,(256,256),180,(128,224)).resize((128,128),Image.Resampling.LANCZOS)
item_icon.save(MEDIA/'textures/Item_SuQingFreshnessFridge.png')

sheet=Image.new('RGBA',(512,256))
for n,sprite in enumerate(sprites):sheet.paste(sprite,(n*128,0))
sheet.save(ART/f'{SHEET}.png')

preview=Image.new('RGB',(1400,1060),(29,31,40));pv=ImageDraw.Draw(preview)
pv.text((48,30),'SUQING / FRESHNESS FRIDGE',font=font(32,True),fill=(227,224,237))
pv.text((48,78),'Original low-poly model + four matching PZ sprites',font=font(19),fill=(171,167,186))
for n,(angle,label) in enumerate([(0,'SOUTH / FRONT'),(90,'EAST'),(180,'NORTH / BACK'),(270,'WEST')]):
    x=(n%2)*700;y=120+(n//2)*445
    pv.rounded_rectangle((x+24,y+8,x+676,y+435),16,fill=(40,42,53))
    im=render(angle,(560,400),240,(280,340))
    preview.paste(im,(x+70,y+12),im)
    pv.text((x+48,y+386),label,font=font(17,True),fill=(183,173,205))
preview.save(ART/'model_four_views.png')
hero=render(0,(900,1050),620,(450,910));hero.save(ART/'model_front_transparent.png')

def wi(n):return struct.pack('<i',n)
def ws(s):
    data=s.encode('utf-8');return wi(len(data))+data

# PZPK v1: one page, four named subtextures, PNG byte length then PNG data.
png=io.BytesIO();sheet.save(png,format='PNG');png_bytes=png.getvalue()
pack=bytearray(b'PZPK'+wi(1)+wi(1)+ws(PACK+'_0')+wi(4)+wi(1))
for n in range(4):
    pack+=ws(f'{SHEET}_{n}')+struct.pack('<8i',n*128,0,128,256,0,0,128,256)
pack+=wi(len(png_bytes))+png_bytes
(MEDIA/'texturepacks'/f'{PACK}.pack').write_bytes(pack)

# TileZed .tiles v1. Property strings are newline-terminated, integers little-endian.
properties={
    'BlocksPlacement':'','CanScrap':'','ContainerCapacity':'200',
    'ContainerCloseSound':'CloseFridge','ContainerOpenSound':'OpenFridge',
    'ContainerPosition':'Low','ContainerPutSound':'PutItemInFridge',
    'ContainerTakeSound':'PutItemInFridge','CustomName':'FreshnessFridge',
    'CustomItem':'SuQingFreshnessFridge.Mov_FreshnessFridge',
    'GroupName':'SuQing','IsFridge':'','IsLow':'','IsMoveAble':'',
    'Material':'Fridge','Material2':'MetalScrap','Material3':'Electric',
    'PickUpWeight':'100','ScrapSize':'Small','Surface':'32',
    'container':'fridge','solidtrans':'',
}
tile=bytearray(b'tdef'+wi(1)+wi(1)+(SHEET+'\n'+SHEET+'.png\n').encode('ascii')+struct.pack('<4i',4,1,1,4))
tile_records=[]
for facing in FACING:
    props={**properties,'Facing':facing}
    tile+=wi(len(props))
    for key,value in sorted(props.items()):tile+=(key+'\n'+value+'\n').encode('ascii')
    tile_records.append(props)
(MEDIA/f'{SHEET}.tiles').write_bytes(tile)
(ART/'tile_properties.json').write_text(json.dumps({'tiledef':TILEDEF_NUMBER,'sprites':[{'name':f'{SHEET}_{n}','properties':p} for n,p in enumerate(tile_records)]},indent=2),encoding='utf-8')

# Independent optional Viewpoint model pack. No changes to Viewpoint's files.
vp=['# Original SuQing model; one tile unit, Z up (Viewpoint 0.1.6.1).','id=suqing-freshness-fridge','name=SuQing Freshness Fridge','version=1','model.suqing_fridge=fridge.obj']
for n in range(4):vp.append(f'bind.{SHEET}_{n}=suqing_fridge,{VIEWPOINT_ROTATION[n]},0,0,0,1')
(MEDIA/'viewpoint/package.properties').write_text('\n'.join(vp)+'\n',encoding='ascii')
for asset_name in ['fridge.obj','fridge.mtl','fridge_atlas.png']:
    (MEDIA/'viewpoint'/asset_name).write_bytes((MODEL/asset_name).read_bytes())
manifest={
    'generator':'tools/assets_build.py','seed':20261105,'mesh_vertices':len(v),'mesh_triangles':len(faces),
    'obj_axes':'X east / Y south / Z up; current installed Viewpoint convention',
    'bounds_xyz':[export_v.min(axis=0).tolist(),export_v.max(axis=0).tolist()],
    'sprite_names':[f'{SHEET}_{n}' for n in range(4)],'facings':FACING,
    'viewpoint_rotations_degrees':VIEWPOINT_ROTATION,
    'pack':PACK,'tiledef_name':SHEET,'tiledef_number':TILEDEF_NUMBER,
    'source':'Original procedural mesh and hand-authored texture atlas, inspired by vanilla mini-fridge proportions. No third-party mesh or texture copied.',
    'validation_scope':'Offline generation/readback. In-game 2D/Viewpoint placement and appearance remain for user acceptance.',
}
(ART/'model_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print(json.dumps(manifest,indent=2))
