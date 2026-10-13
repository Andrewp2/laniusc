"""Compare entry rebuilds with the existing stdlib_gpu_perf example harness.
The source entry is identical. The previous stdlib omits the two new predicates,
because the previous compiler cannot lower those generic bodies.
"""
from pathlib import Path
import os, subprocess, statistics, re, json
repo=Path.cwd();work=repo/'target/stdlib-perf/generic-enum-tag-perf'
art=Path(__file__).resolve().parent
root=repo/'target/stdlib-perf/build/laniusc-shader-artifacts/release/shaders'
snapshots=repo/'target/stdlib-perf/results'
samples={"previous":[],"fixed":[]};runs=[]
try:
    for pair in range(4):
        order=['previous','fixed'] if pair%2==0 else ['fixed','previous']
        for name in order:
            shader='method-parameters-validated-shaders' if name=='previous' else 'generic-enum-tag-validated-shaders'
            root.unlink();root.symlink_to(snapshots/shader)
            stdlib=work/'previous-stdlib' if name=='previous' else repo/'stdlib'
            argv=['timeout','105s',str(work/f'{name}-perf'),str(work/'boolean_window_control.lani'),str(stdlib),str(work/'expected.stdout'),'3','10']
            env=dict(os.environ,LANIUS_PERF_REBUILD_ENTRY='1')
            result=subprocess.run(argv,env=env,text=True,capture_output=True)
            (art/f'boolean-window-{name}-{pair}.log').write_text(result.stdout+result.stderr)
            assert result.returncode==0, result.stderr
            assert 'output_verified=true' in result.stdout, result.stdout
            rows=[float(v) for v in re.findall(r'^sample=\d+ ms=([\d.]+)$',result.stdout,re.M)]
            assert len(rows)==10
            samples[name].extend(rows);runs.append({'revision':name,'pair':pair,'command':argv,'exit_status':result.returncode,'final_output_verified':True,'samples_ms':rows})
            print(f'{name} pair {pair}: median {statistics.median(rows):.3f} ms; final output passed',flush=True)
finally:
    root.unlink();root.symlink_to(snapshots/'current-shaders')
previous=statistics.median(samples['previous']);fixed=statistics.median(samples['fixed'])
summary={'previous_median_ms':previous,'fixed_median_ms':fixed,'pooled_median_change_percent':(fixed/previous-1)*100,'runs':runs}
(art/'imported-entry-summary.txt').write_text(json.dumps(summary,indent=2)+'\n')
print(f'previous={previous:.3f} ms fixed={fixed:.3f} ms change={(fixed/previous-1)*100:.3f}%; all 80 rebuilds succeeded and eight final outputs passed',flush=True)
