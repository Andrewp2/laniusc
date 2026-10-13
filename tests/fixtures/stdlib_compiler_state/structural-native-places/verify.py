import hashlib,json,pathlib,subprocess,sys,time
root=pathlib.Path(__file__).resolve().parents[4]
out=pathlib.Path(__file__).resolve().parent
out.mkdir(parents=True,exist_ok=True)
label,binary,*tests=sys.argv[1:]
exact=len(tests)==1
if tests and tests[0]=='--filter':
    tests=tests[1:]
    exact=False
binary=(root/binary).resolve()
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def freeze():
    names=subprocess.check_output(['git','ls-files','-co','--exclude-standard','-z'],cwd=root).decode(errors='surrogateescape').split('\0')
    return {n:sha(root/n) for n in sorted(set(names)) if n and pathlib.Path(n).suffix in ['.rs','.slang','.lani','.toml','.lock','.py','.bnf'] and (root/n).is_file()}
artifact_root=root/'target/stdlib-perf/build/laniusc-shader-artifacts/release/shaders'
artifacts={str(p.relative_to(artifact_root)):sha(p) for p in sorted(artifact_root.rglob('*.spv'))}
(out/(label+'-shaders.json')).write_text(json.dumps(artifacts,indent=2)+'\n')
before=freeze()
(out/(label+'-sources.json')).write_text(json.dumps(before,indent=2)+'\n')
start=time.monotonic()
args=[str(binary),'--nocapture','--test-threads=1',*tests]
if exact:args.append('--exact')
with (out/(label+'.log')).open('w') as log:
    try:
        proc=subprocess.run(args,cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=90)
        code=proc.returncode
    except subprocess.TimeoutExpired:code='timeout90'
result=dict(args=args,exit_code=code,seconds=time.monotonic()-start,binary_sha256=sha(binary),sources_unchanged=before==freeze(),shader_artifacts_unchanged=artifacts=={str(p.relative_to(artifact_root)):sha(p) for p in sorted(artifact_root.rglob("*.spv"))})
(out/(label+'.json')).write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
print((out/(label+'.log')).read_text()[-10000:])

assert code == 0 and result["sources_unchanged"] and result["shader_artifacts_unchanged"]
