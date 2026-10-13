import hashlib
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys
import time

root = Path(__file__).resolve().parents[4]
case, sequence, version = sys.argv[1:]
assert version in ('baseline', 'current')
entry, expected = {
    'contracts': ('tests/fixtures/stdlib_compiler_state/trait-type-graphs/thirty-two-mixed.lani', '-'),
    'ordinary': ('tests/fixtures/stdlib_foundation/generic_many_parameter_composition_32.lani',
                 'benchmark_artifacts/performance/stdlib-gpu-20261010-implementation-evidence/generic-32.expected.txt'),
}[case]
out = root / 'tests/fixtures/stdlib_compiler_state/structural-native-places' / ('performance-' + case)
out.mkdir(parents=True, exist_ok=True)
link = root / 'target/stdlib-perf/build/laniusc-shader-artifacts/release/shaders'
assert link.is_symlink()
original_shaders = link.resolve()
binary = root / ('target/program-sibling-integrated/stdlib_gpu_perf' if version == 'baseline'
                 else 'target/stdlib-perf/build/release/examples/stdlib_gpu_perf')
shaders = root / 'target/program-sibling-integrated/shaders' if version == 'baseline' else original_shaders
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
manifest = {str(p.relative_to(shaders)): sha(p) for p in sorted(shaders.rglob('*.spv'))}
(out / (version + '-shaders.json')).write_text(json.dumps(manifest, indent=2) + '\n')
args = [str(binary), entry, 'stdlib', expected, '3', '10']
log_path = out / (sequence + '-' + version + '.log')
assert not log_path.exists(), 'do not overwrite prior measurements'
start = time.monotonic()
try:
    link.unlink()
    link.symlink_to(shaders)
    with log_path.open('w') as log:
        try:
            code = subprocess.run(args, cwd=root,
                env={**os.environ, 'LANIUS_PERF_REBUILD_ENTRY': '1'},
                stdout=log, stderr=subprocess.STDOUT, timeout=90).returncode
        except subprocess.TimeoutExpired:
            code = 'timeout90'
finally:
    link.unlink()
    link.symlink_to(original_shaders)
log = log_path.read_text()
samples = [float(x) for x in re.findall(r'^sample=\d+ ms=([0-9.]+)$', log, re.M)]
result = {
    'version': version, 'command': args,
    'environment': {'LANIUS_PERF_REBUILD_ENTRY': '1'},
    'exit_code': code, 'seconds': time.monotonic() - start,
    'binary_sha256': sha(binary), 'samples_ms': samples,
    'median_ms': statistics.median(samples) if samples else None,
    'output_verified': 'output_verified=true' in log,
    'shader_link_restored': link.resolve() == original_shaders,
    'shader_artifacts_unchanged': manifest == {
        str(p.relative_to(shaders)): sha(p) for p in sorted(shaders.rglob('*.spv'))},
}
(out / (sequence + '-' + version + '.json')).write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result), flush=True)
if code != 0:
    print(log[-5000:])
assert code == 0 and len(samples) == 10 and result['output_verified']
assert result['shader_link_restored'] and result['shader_artifacts_unchanged']
