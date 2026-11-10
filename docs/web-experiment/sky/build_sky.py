"""Build the splash skybox from NASA SVS Deep Star Maps 2020 and Hipparcos.

Inputs (in the raw dir), not checked in:
  milkyway_2020_8k.exr, hiptyc_2020_8k.exr
      https://svs.gsfc.nasa.gov/4851 (NASA/GSFC SVS; Gaia DR2: ESA/Gaia/DPAC)
  hip.tsv
      Hipparcos main catalogue (ESA 1997) from VizieR, e.g.
      https://vizier.cfa.harvard.edu/viz-bin/asu-tsv?-source=I/239/hip_main&-out=RAICRS,DEICRS,Vmag,B-V&-out.max=unlimited&Vmag=%3C8.5

Outputs (in the out dir):
  milkyway.avif  4096x2048 equirect in the scene's frame: the Milky Way glow
                 plus the faint Tycho/Gaia stars, with the stars that the page
                 draws as sprites masked out. Encoded with ffmpeg/libaom.
  stars.bin      Hipparcos stars brighter than VMAX, brightest first: per star
                 uint16 RA, int16 Dec, uint8 V, uint8 B-V (6 bytes, LE).

The scene frame puts the galactic centre at CORE and the galactic pole at
BAND; both must match the constants in index.html.

usage: build_sky.py <raw dir> <out dir> [gain] [black level] [avif crf]
"""
import os, subprocess, sys, tempfile
os.environ['OPENCV_IO_ENABLE_OPENEXR'] = '1'
import cv2
import numpy as np
from scipy.ndimage import map_coordinates

raw, out = sys.argv[1], sys.argv[2]
GAIN = float(sys.argv[3]) if len(sys.argv) > 3 else 3.5
BLACK = float(sys.argv[4]) if len(sys.argv) > 4 else 0.002
CRF = int(sys.argv[5]) if len(sys.argv) > 5 else 30
VMAX = 8.0

def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)

def radec(ra, dec):
    ra, dec = np.radians(ra), np.radians(dec)
    return np.stack([np.cos(dec) * np.cos(ra), np.cos(dec) * np.sin(ra), np.sin(dec)], -1)

# Scene frame targets (must match BAND/CORE in index.html).
CORE = unit([-0.47, 0.44, -0.76])
BAND = unit([0.19, -0.79, -0.58])
BAND = unit(BAND - CORE * BAND.dot(CORE))
GC = radec(266.40499, -28.93617)      # galactic centre, ICRS
NGP = radec(192.85948, 27.12825)      # north galactic pole, ICRS
NGP = unit(NGP - GC * NGP.dot(GC))
C = np.stack([GC, NGP, np.cross(GC, NGP)], 1)     # celestial basis as columns
T = np.stack([CORE, BAND, np.cross(CORE, BAND)], 1)
M = T @ C.T                                        # celestial -> scene
print('M =', np.round(M, 6).tolist())

# Catalogue.
rows = []
for line in open(os.path.join(raw, 'hip.tsv')):
    p = line.rstrip('\n').split('\t')
    if len(p) < 4 or not p[0].strip()[:1].isdigit():
        continue
    try:
        ra, de, v = float(p[0]), float(p[1]), float(p[2])
    except ValueError:
        continue
    try:
        bv = float(p[3])
    except ValueError:
        bv = 0.6
    if v < VMAX:
        rows.append((ra, de, v, bv))
cat = np.array(rows)
print('stars', len(cat))

def load(name):
    a = cv2.imread(os.path.join(raw, name), cv2.IMREAD_UNCHANGED)
    return a[..., ::-1].astype(np.float32)  # BGR -> RGB

mw = load('milkyway_2020_8k.exr')
ht = load('hiptyc_2020_8k.exr')
H, W = mw.shape[:2]

# Mask the sprite stars out of the star layer, bigger for brighter stars.
mask = np.ones((H, W), np.float32)
xs = ((0.5 - cat[:, 0] / 360.0) % 1.0) * W
ys = (0.5 - cat[:, 1] / 180.0) * H
for x, y, v in zip(xs, ys, cat[:, 2]):
    r = 2.5 + max(0.0, VMAX - v) * 2.2
    cv2.circle(mask, (int(round(x)), int(round(y))), int(np.ceil(r)), 0.0, -1, lineType=cv2.LINE_AA)
    if x < r: cv2.circle(mask, (int(round(x + W)), int(round(y))), int(np.ceil(r)), 0.0, -1)
    if x > W - r: cv2.circle(mask, (int(round(x - W)), int(round(y))), int(np.ceil(r)), 0.0, -1)
mask = cv2.GaussianBlur(mask, (0, 0), 1.0)
sky = mw + ht * mask[..., None]
del mw, ht

# Resample into the scene frame at 8k, then area-downsample to 4k.
OW, OH = 8192, 4096
u = (np.arange(OW) + 0.5) / OW
v = 1 - (np.arange(OH) + 0.5) / OH
lon = (u - 0.5) * 2 * np.pi
lat = (v - 0.5) * np.pi
out_img = np.zeros((OH, OW, 3), np.float32)
for y0 in range(0, OH, 512):
    la = lat[y0:y0 + 512][:, None]
    d = np.stack([np.cos(la) * np.cos(lon)[None], np.sin(la) * np.ones_like(lon)[None], np.cos(la) * np.sin(lon)[None]], -1)
    c = d @ M          # scene -> celestial (M is orthonormal: c = M^T d)
    ra = np.arctan2(c[..., 1], c[..., 0])
    de = np.arcsin(np.clip(c[..., 2], -1, 1))
    sx = ((0.5 - ra / (2 * np.pi)) % 1.0) * W - 0.5
    sy = (0.5 - de / np.pi) * H - 0.5
    for ch in range(3):
        out_img[y0:y0 + 512, :, ch] = map_coordinates(sky[..., ch], [sy, sx], order=1, mode='wrap')
del sky
small = cv2.resize(out_img, (4096, 2048), interpolation=cv2.INTER_AREA)
del out_img

# Treat the maps as linear light, stretch, and encode as sRGB with dither.
x = 1 - np.exp(-np.maximum(small - BLACK, 0) * GAIN)
x = np.where(x <= 0.0031308, 12.92 * x, 1.055 * np.power(np.maximum(x, 0), 1 / 2.4) - 0.055)
rng = np.random.default_rng(1)
x = np.clip(x * 255 + rng.uniform(-0.5, 0.5, x.shape), 0, 255).astype(np.uint8)
os.makedirs(out, exist_ok=True)
with tempfile.TemporaryDirectory() as tmp:
    master = os.path.join(tmp, 'master.png')
    cv2.imwrite(master, x[..., ::-1])
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', master,
                    '-c:v', 'libaom-av1', '-still-picture', '1', '-crf', str(CRF), '-cpu-used', '4',
                    '-pix_fmt', 'yuv444p', '-color_primaries', 'bt709', '-color_trc', 'iec61966-2-1',
                    '-colorspace', 'bt709', os.path.join(out, 'milkyway.avif')], check=True)

# Stars: brightest first so a page can stop early if it wants fewer.
cat = cat[np.argsort(cat[:, 2])]
rec = np.zeros(len(cat), dtype=[('ra', '<u2'), ('de', '<i2'), ('v', 'u1'), ('bv', 'u1')])
rec['ra'] = np.round(cat[:, 0] / 360.0 * 65535).astype(np.uint16)
rec['de'] = np.round(cat[:, 1] / 90.0 * 32767).astype(np.int16)
rec['v'] = np.clip(np.round((cat[:, 2] + 2.0) * 25), 0, 255).astype(np.uint8)   # V = b/25 - 2
rec['bv'] = np.clip(np.round((cat[:, 3] + 0.5) * 80), 0, 255).astype(np.uint8)  # B-V = b/80 - 0.5
rec.tofile(os.path.join(out, 'stars.bin'))
for f in ('milkyway.avif', 'stars.bin'):
    print(f, os.path.getsize(os.path.join(out, f)))
