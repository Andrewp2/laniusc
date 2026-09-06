#!/usr/bin/env python3
"""Fresh program-specific Surface check; reusable checker infrastructure must be built.

Outputs JSON lines with per-module wall times and the total. All frontend data,
indexes, and certificates are checked fresh. The default uses separate processes;
--batch reuses loaded imports in one process with a 12,000 MB Lean memory limit.
The existing Lake build is not modified. The default retains its output directory
for inspection; batch mode removes its temporary objects when the run exits.
"""
import importlib.util
import json
import os
import sys
from pathlib import Path
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('surface_build', root / 'check-surface.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
target = 'Lanius.Extraction.VerifiedFrontend.Surface.Data'
order = helper.dependency_order([target])
modules = [m for m in order
           if m.startswith('Lanius.Extraction.VerifiedFrontend.')]
if sys.argv[1:] == ['--list']:
    print('\n'.join(modules))
    raise SystemExit(0)
batch = sys.argv[1:] == ['--batch']
if sys.argv[1:] and not batch:
    raise SystemExit('usage: benchmark-surface.py [--list | --batch]')
lean = subprocess.check_output(['lake', 'env', 'which', 'lean'], cwd=root, text=True).strip()
original_path = subprocess.check_output(['lake', 'env', 'printenv', 'LEAN_PATH'], cwd=root, text=True).strip()
if batch:
    config = {
        'root': str(root),
        'shared': [m for m in order if m not in modules],
        'modules': modules,
        'finalName': 'Lanius.Extraction.verifiedFrontendPack_surface_data_checked_kernel',
    }
    with tempfile.TemporaryDirectory(prefix='lanius-batch-config-') as temporary:
        config['output'] = str(Path(temporary) / 'objects')
        manifest = Path(temporary) / 'manifest.json'
        manifest.write_text(json.dumps(config))
        before = time.monotonic()
        result = subprocess.run([
            lean, '-M', '12000', '--run', str(root / 'Lanius/Tools/SurfaceBatch.lean'),
            str(manifest),
        ], cwd=root, env=dict(os.environ, LEAN_PATH=original_path))
        print(json.dumps({'mode': 'batch', 'exit': result.returncode,
                          'process_wall_seconds': time.monotonic() - before}), flush=True)
        raise SystemExit(result.returncode)
output = Path(tempfile.mkdtemp(prefix='lanius-fresh-frontend-'))
# Lean resolves a namespace from its first search root. Populate that root
# with read-only symlinks to shared modules, but never to frontend outputs.
shared = root / '.lake/build/lib/lean'
for directory, folders, files in os.walk(shared):
    relative = Path(directory).relative_to(shared)
    if relative == Path('Lanius/Extraction'):
        folders[:] = [name for name in folders if name != 'VerifiedFrontend']
    (output / relative).mkdir(parents=True, exist_ok=True)
    for name in files:
        (output / relative / name).symlink_to(Path(directory) / name)
env = dict(os.environ, LEAN_PATH=str(output) + ':' + original_path)
print(json.dumps({'modules': len(modules), 'output': str(output), 'target': target}), flush=True)
start = time.monotonic()
totals = {}
for index, module in enumerate(modules, 1):
    relative = Path(module.replace('.', '/'))
    destination = output / relative.with_suffix('.olean')
    destination.parent.mkdir(parents=True, exist_ok=True)
    before = time.monotonic()
    result = subprocess.run([lean, '-o', str(destination), str(relative.with_suffix('.lean'))],
                            cwd=root, env=env, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    seconds = time.monotonic() - before
    family = module.split('.')[3]
    totals[family] = totals.get(family, 0) + seconds
    print(json.dumps({'index': index, 'module': module, 'seconds': round(seconds, 3),
                      'elapsed': round(time.monotonic() - start, 3), 'exit': result.returncode}), flush=True)
    if result.returncode:
        print(result.stdout, flush=True)
        raise SystemExit(result.returncode)
print(json.dumps({'complete': True, 'wall_seconds': time.monotonic() - start,
                  'by_family_seconds': totals, 'modules': len(modules)}), flush=True)
