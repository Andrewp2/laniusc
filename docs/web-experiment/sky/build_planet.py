"""Build the splash planet textures from NASA Earth imagery.

Inputs (in the raw dir), not checked in; both are public domain (NASA):
  day.jpg    Blue Marble land/ocean/ice/clouds, 8192x4096
             https://commons.wikimedia.org/wiki/File:Land_ocean_ice_cloud_hires.jpg
  night.jpg  Black Marble "City Lights 2012" flat map, 12150x6075
             https://commons.wikimedia.org/wiki/File:City_Lights_2012_-_Flat_map.jpg

Outputs (in the out dir), equirect AVIF:
  earth-day.avif  2048x1024 sRGB colour, clouds included.
  earth-aux.avif  1024x512 linear data: R city lights, G ocean mask (for the
                  sun glint), B cloud cover (dims the lights and the glint).

usage: build_planet.py <raw dir> <out dir> [avif crf]
"""
import os, subprocess, sys, tempfile
import cv2
import numpy as np

raw, out = sys.argv[1], sys.argv[2]
CRF = int(sys.argv[3]) if len(sys.argv) > 3 else 30
W, H = 2048, 1024

day = cv2.imread(os.path.join(raw, 'day.jpg'))[..., ::-1]
night = cv2.imread(os.path.join(raw, 'night.jpg'))[..., ::-1]
day_s = cv2.resize(day, (W, H), interpolation=cv2.INTER_AREA)

d = day.astype(np.float32) / 255
# Clouds are bright and nearly colourless (unlike desert or ice shelves).
sat = (d.max(-1) - d.min(-1)) / np.maximum(d.max(-1), 1e-3)
cloud = np.clip((d.min(-1) - 0.35) / 0.4, 0, 1) * np.clip(1 - (sat - 0.1) * 5, 0, 1)
n = night.astype(np.float32) / 255
# The night map tints land blue; the lights are yellow-white. Its ocean is
# one flat colour, about (0, 1, 31).
lights = np.clip((n[..., 0] - 0.45 * n[..., 2] - 0.04) / 0.8, 0, 1)
ocean = ((night[..., 0] < 2) & (night[..., 1] < 3) & (night[..., 2] < 34)).astype(np.float32)

def fit(a):
    return cv2.resize(a, (W // 2, H // 2), interpolation=cv2.INTER_AREA)

aux = np.stack([fit(lights) ** 0.8, cv2.GaussianBlur(fit(ocean), (0, 0), 1.0), fit(cloud)], -1)
aux = (np.clip(aux, 0, 1) * 255 + 0.5).astype(np.uint8)

os.makedirs(out, exist_ok=True)
with tempfile.TemporaryDirectory() as tmp:
    for name, img in (('earth-day', day_s), ('earth-aux', aux)):
        png = os.path.join(tmp, name + '.png')
        cv2.imwrite(png, img[..., ::-1])
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', png,
                        '-c:v', 'libaom-av1', '-still-picture', '1', '-crf', str(CRF + (4 if name == 'earth-aux' else 0)), '-cpu-used', '4',
                        '-pix_fmt', 'yuv444p', '-color_primaries', 'bt709', '-color_trc', 'iec61966-2-1',
                        '-colorspace', 'bt709', os.path.join(out, name + '.avif')], check=True)
for f in ('earth-day.avif', 'earth-aux.avif'):
    print(f, os.path.getsize(os.path.join(out, f)))
