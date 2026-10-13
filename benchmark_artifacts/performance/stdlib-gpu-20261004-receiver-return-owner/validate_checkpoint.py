from pathlib import Path
import hashlib,json,re,statistics,subprocess

out=Path('benchmark_artifacts/performance/stdlib-gpu-20261004-receiver-return-owner')
sha=lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
frozen=json.loads((out/'frozen-inputs.json').read_text())
transition=json.loads((out/'canonical-cli-build-transition.json').read_text())
for group in ['source_sha256','binary_sha256']:
    for name,expected in frozen[group].items():
        if group=='binary_sha256' and name=='target/release/laniusc':
            assert expected==transition['before_sha256']
            expected=transition['measured_sha256']
        assert sha(Path(name))==expected, f'{group} changed: {name}'
artifacts=Path('target/stdlib-perf/results/current-shaders')
payloads=sorted(list(artifacts.rglob('*.spv'))+list(artifacts.rglob('*.reflect.json')))
actual={str(p.relative_to(artifacts)):sha(p) for p in payloads}
assert actual==frozen['shader_artifacts'], 'shader payloads changed'
assert len(actual)==1484
assert artifacts.joinpath('artifacts.env').read_text()==frozen['shader_metadata']
assert 'size_guard_status=enforced\n' in frozen['shader_metadata']
assert 'size_guard_max_bytes=524288\n' in frozen['shader_metadata']
assert not artifacts.joinpath('type_checker/type/instances/01g_hash_arg_rows.spv').exists()
(out/'shader-artifact-sha256.json').write_text(json.dumps(actual,indent=2)+'\n')
old=Path('benchmark_artifacts/performance/stdlib-gpu-20261004-explicit-records')
baseline=dict((int(seed),digest) for seed,digest in re.findall(r'seed=(\d+) sha256=([0-9a-f]{64})',old.joinpath('canonical-runtime-validation.log').read_text()))
r=json.loads(out.joinpath('canonical-1mb.json').read_text())
assert len(r['measurements'])==1
m=r['measurements'][0]; assert m['target']=='x86_64'
samples=m['samples']; requests=m['commands']['sample_compile_requests']
assert len(samples)==len(requests)==20
assert [s['seed'] for s in samples]==list(range(20,40))
for sample,request in zip(samples,requests,strict=True):
    seed=sample['seed']; source=Path(request['input']); elf=Path(request['output'])
    manifest=json.loads(source.parent.parent.joinpath('manifest.json').read_text())
    spec=manifest['source_sets'][0]; source_spec=spec['sources']['lanius']
    digest=sha(source)
    assert digest==source_spec['sha256']==baseline[seed]
    assert sample['source_bytes']==source_spec['bytes']==source.stat().st_size==1000000
    assert sample['compiled_unit_cache']['hits_during_job']==0
    assert sample['resources_created']=={'buffers':0,'bind_groups':0,'compute_pipelines':0}
    assert elf.read_bytes().startswith(b'\x7fELF')
    elf.chmod(0o700)
    result=subprocess.run(['timeout','5s',str(elf)],capture_output=True,timeout=7)
    assert result.returncode==0 and not result.stderr and result.stdout==spec['expected_stdout'].encode(),(seed,result)
    print(f'seed={seed} sha256={digest} bytes=1000000 cache_hits=0 resource_creations=0 ELF_stdout_verified=true')
compiler=statistics.median(s['compiler_ms'] for s in samples)
wall=statistics.median(s['wall_ms'] for s in samples)
print(f'compiler_ms_median={compiler:.9f}\nwall_ms_median={wall:.9f}')
print('all_20_source_hashes_and_ELFs_verified=true')
print('tracked_live_bytes',sorted({s['gpu_memory']['bytes'] for s in samples}))
print('excluded_raw_buffers',sorted({s['gpu_memory']['untracked_allocations'] for s in samples}))
print('all_1484_shader_payloads_and_1725_sources_and_3_focused_binaries_unchanged=true')
print('canonical_CLI_build_transition_verified=true')
meta={
    'shader_metadata':frozen['shader_metadata'],
    'source_sha256':frozen['source_sha256'], 'binary_sha256':dict(frozen['binary_sha256'], **{'target/release/laniusc':transition['measured_sha256']}),
    'per_artifact_sha256':'shader-artifact-sha256.json',
    'canonical_compiler_ms':compiler,'canonical_wall_ms':wall,
    'canonical_change_unpaired_percent':(compiler/43.660002-1)*100,
    'tracked_live_bytes':sorted({s['gpu_memory']['bytes'] for s in samples}),
    'tracked_live_bytes_change':samples[0]['gpu_memory']['bytes']-1576111615,
    'excluded_raw_buffers_with_unavailable_sizes':5,
    'canonical_runner_status':'report_saved_then_existing_catalogue_list_get_exception',
    'all_shader_payloads_and_sources_unchanged':True,
    'canonical_cli_build_transition':'canonical-cli-build-transition.json',
}
for stem in ['generic-32','generic-32-repeat','receiver-32-local','receiver-32-imported']:
    content=out.joinpath(stem+'.log').read_text()
    rows=[float(ms) for ms in re.findall(r'^sample=\d+ ms=([0-9.]+)$',content,re.M)]
    assert len(rows)==10
    final=re.search(r'^entry=.* rebuild_entry=true warmups=3 iters=10 output_bytes=(\d+) min_ms=([0-9.]+) median_ms=([0-9.]+) avg_ms=([0-9.]+) max_ms=([0-9.]+) output_verified=true$',content,re.M)
    assert final,stem
    assert abs(statistics.median(rows)-float(final[3]))<=0.001
    assert abs(statistics.mean(rows)-float(final[4]))<=0.001
    assert min(rows)==float(final[2]) and max(rows)==float(final[5])
    info={'median_ms':float(final[3]),'mean_ms':float(final[4]),'min_ms':float(final[2]),'max_ms':float(final[5]),'final_elf_bytes':int(final[1]),'exact_output_verified':True,'warmups':3,'entry_recompiles':10}
    meta[stem]=info
    print(stem,json.dumps(info,sort_keys=True))
meta['generic_32_change_unpaired_percent']=(meta['generic-32']['median_ms']/270.681-1)*100
meta['generic_32_repeat_change_unpaired_percent']=(meta['generic-32-repeat']['median_ms']/270.681-1)*100
profile=out.joinpath('generic-32-profile.log').read_text()
rounds=[(int(r),int(n)) for r,n in re.findall(r'\[typecheck.call_inference\] round=(\d+) changed=(\d+)',profile)]
assert len(rounds)==32
assert all(rounds[i][0]==0 and rounds[i+1]==(1,0) for i in range(0,len(rounds),2))
assert 'warmups=1 iters=2 output_bytes=78746' in profile and 'output_verified=true' in profile
meta['instrumented_profile']={'log':'generic-32-profile.log','warmups':1,'samples':2,'observed_inference_closures':16,'rounds_per_closure':2,'final_elf_exact_output_verified':True,'performance_attribution_established':False}
print('instrumented_profile_all_16_inference_closures_converged_in_two_rounds=true')
out.joinpath('checkpoint-metadata.json').write_text(json.dumps(meta,indent=2)+'\n')
