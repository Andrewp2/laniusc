import os,pathlib,hashlib,json,subprocess,sys,time,re,statistics
root=pathlib.Path('/home/andrew-peterson/.codex/worktrees/stdlib-foundation/laniusc')
case,seq,version=sys.argv[1:]
entry,expected={
 'contracts':('tests/fixtures/stdlib_compiler_state/trait-type-graphs/thirty-two-mixed.lani','-'),
 'ordinary':('tests/fixtures/stdlib_foundation/generic_many_parameter_composition_32.lani','benchmark_artifacts/performance/stdlib-gpu-20261010-implementation-evidence/generic-32.expected.txt')
}[case]
out=root/'tests/fixtures/stdlib_compiler_state/program-native-replay'/('performance-sibling-'+case)
out.mkdir(exist_ok=True)
link=root/'target/stdlib-perf/build/laniusc-shader-artifacts/release/shaders'
assert link.is_symlink()
current=link.resolve()
binary=root/('target/program-native-integrated/stdlib_gpu_perf' if version=='baseline' else 'target/program-sibling-integrated/stdlib_gpu_perf')
shaders=(root/'target/program-native-integrated/shaders') if version=='baseline' else root/'target/program-sibling-integrated/shaders'
args=[str(binary),entry,'stdlib',expected,'3','10']
logpath=out/(seq+'-'+version+'.log')
start=time.monotonic()
try:
 link.unlink();link.symlink_to(shaders)
 with logpath.open('w') as log:
  try: code=subprocess.run(args,cwd=root,env={**os.environ,'LANIUS_PERF_REBUILD_ENTRY':'1'},stdout=log,stderr=subprocess.STDOUT,timeout=90).returncode
  except subprocess.TimeoutExpired:code='timeout90'
finally:
 link.unlink();link.symlink_to(current)
log=logpath.read_text()
samples=[float(x) for x in re.findall(r'^sample=\d+ ms=([0-9.]+)$',log,re.M)]
result={'version':version,'command':args,'environment':{'LANIUS_PERF_REBUILD_ENTRY':'1'},'exit_code':code,'seconds':time.monotonic()-start,'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'samples_ms':samples,'median_ms':statistics.median(samples) if samples else None,'output_verified':'output_verified=true' in log,'shader_link_restored':link.resolve()==current}
(out/(seq+'-'+version+'.json')).write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
if code!=0:print(log[-5000:])
assert code==0 and len(samples)==10 and result['output_verified']
