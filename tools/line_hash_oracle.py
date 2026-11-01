"""Oracle for sample_programs/library/line_hash.lani: records, bytes, hash."""
import sys
data = open(sys.argv[1], "rb").read()
lines = [x for x in data.split(b"\n")]
recs = [x + b"\n" for x in lines[:-1]] + ([lines[-1]] if lines[-1] else [])
h, mask = 2166136, 0xFFFFFFFF
for r in recs:
    for b in r: h = ((h ^ b) * 16777619) & mask
    h = ((h ^ len(r)) * 16777619) & mask
print(len(recs), sum(map(len, recs)), h)
