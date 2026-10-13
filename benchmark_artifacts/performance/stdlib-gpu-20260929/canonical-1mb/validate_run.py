import hashlib
import json
import sys
from pathlib import Path
sys.path.insert(0, str(Path.cwd() / 'tools'))
from run_compiler_stress_matrix import validate_executable
path = Path(sys.argv[1])
run = json.loads(path.read_text())
validations = []
for measurement in run['measurements']:
    requests = measurement['commands']['sample_compile_requests']
    for sample, request in zip(measurement['samples'], requests, strict=True):
        source = Path(request['input'])
        manifest = json.loads(source.parents[1].joinpath('manifest.json').read_text())['source_sets'][0]
        output = Path(request['output'])
        output.chmod(0o755)
        stdout = validate_executable(output, manifest['expected_stdout'])
        validations.append({'seed': sample['seed'], 'configuration': measurement['configuration'], 'stdout': stdout, 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'output_sha256': hashlib.sha256(output.read_bytes()).hexdigest(), 'exit_status': 0})
validation_path = path.with_suffix('.validation.json')
validation_path.write_text(json.dumps(validations, indent=2) + '\n')
print(f'{path.name}: executed and validated {len(validations)} artifacts')
for m in run['measurements']:
    print(f"{m['configuration']}: wall median {m['summary']['wall_ms']['median']:.3f} ms, compile median {m['summary']['compiler_ms']['median']:.3f} ms")
    print(next(line for line in m['compiler']['version'].splitlines() if line.startswith('shader-artifact-digest:')))
