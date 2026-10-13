import json
import random
import statistics
import subprocess
import sys
from pathlib import Path
repo = Path.cwd()
sys.path.insert(0, str(repo / 'tools'))
from run_compiler_stress_matrix import compiler_commands, compile_process, materialize, sha256_bytes, sha256_file, source_path, validate_executable
root = repo / 'target/stdlib-perf/canonical/external'
root.mkdir(exist_ok=True)
bins = root / 'bin'
bins.mkdir(exist_ok=True)
corpus = repo / 'target/lanius-perf-workloads/single-file-1mb-x86_64'
templates = compiler_commands(repo)
(root / 'commands.json').write_text(json.dumps(templates, indent=2) + '\n')
tasks = [(language, seed) for seed in range(20, 40) for language in ['c', 'cpp', 'rust', 'zig', 'tcc']]
random.Random(0x1A9105).shuffle(tasks)
sample_file = root / 'samples.json'
rows = json.loads(sample_file.read_text())['samples'] if sample_file.exists() else []
versions_file = root / 'versions.json'
versions = json.loads(versions_file.read_text()) if versions_file.exists() else {}
lo, hi = map(int, sys.argv[1:])
for index in range(lo, hi):
    language, seed = tasks[index]
    if any(row['order'] == index for row in rows):
        continue
    lane = 'default' if language == 'tcc' else 'o0'
    template = templates[lane][language]
    executable = template[0]
    if language not in versions:
        flag = 'version' if language == 'zig' else '--version'
        v = subprocess.run([executable, flag], text=True, capture_output=True, timeout=5)
        versions[language] = (v.stdout + v.stderr).strip()
        versions_file.write_text(json.dumps(versions, indent=2) + '\n')
    source = source_path(corpus, seed, language)
    manifest = json.loads(source.parents[1].joinpath('manifest.json').read_text())['source_sets'][0]
    output = bins / f'{language}-{lane}-{seed}'
    command = materialize(template, source, output)
    sample = compile_process(command, repo)
    stdout = validate_executable(output, manifest['expected_stdout'])
    row = {'order': index, 'phase': 'external_randomized', 'language': language, 'lane': lane, 'seed': seed, 'source_bytes': source.stat().st_size, 'source_sha256': sha256_file(source), 'output_sha256': sha256_file(output), 'stdout_sha256': sha256_bytes(stdout.encode()), 'exit_status': 0, 'command': command, **sample}
    rows.append(row)
    sample_file.write_text(json.dumps({'samples': sorted(rows, key=lambda row: row['order'])}, indent=2) + '\n')
    print(f"{index + 1}/100 {language}/{seed}: {sample['wall_ms']:.3f} ms, output verified", flush=True)
for language in ['c', 'cpp', 'rust', 'zig', 'tcc']:
    values = [row['wall_ms'] for row in rows if row['language'] == language]
    if values:
        print(f'{language}: {len(values)} samples, median {statistics.median(values):.3f} ms', flush=True)
