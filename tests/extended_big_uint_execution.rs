#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, sync::OnceLock, time::Duration};

fn executable(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/extended_library/{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let label = name.to_owned();
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{label}: {error}"));
    let exe = common::TempArtifact::new("laniusc_big_uint", name, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn model() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| executable("big_uint_model"))
}

#[test]
fn python_integer_oracle_radices_carry_borrow_long_division_sequences_and_aliases() {
    let oracle = r#"
import math, random, struct, subprocess, sys
rng = random.Random(0xb162026)
digits = '0123456789abcdefghijklmnopqrstuvwxyz'
def fmt(n, radix):
    if n == 0: return '0'
    out = ''
    while n:
        n, d = divmod(n, radix)
        out = digits[d] + out
    return out
cases = []
def add(op, a, b=1, radix=10, argument=0):
    if op == 2 and a < b: expected = (9, '', '')
    elif op in (4,14) and (b if op == 4 else a) == 0: expected = (10, '', '')
    elif op == 15 and a >= 2**64: expected = (11, '', '')
    else:
        rem = 0
        if op in (0,15): value = a
        elif op == 1: value = a+b
        elif op == 2: value = a-b
        elif op == 3: value = a*b
        elif op == 4: value, rem = divmod(a,b)
        elif op == 5: value = a << argument
        elif op == 6: value = a >> argument
        elif op == 7: value = a & b
        elif op == 8: value = a | b
        elif op == 9: value = a ^ b
        elif op == 10: value = math.gcd(a,b)
        elif op == 11: value = a**argument
        elif op == 12: value = a+a
        elif op == 13: value = a*a
        elif op == 14: value = 1
        expected = (0, fmt(value,radix), fmt(rem,radix))
    cases.append((op,fmt(a,radix),fmt(b,radix),radix,argument,expected))
B=2**32
edge=[0,1,2,B-1,B,B+1,B**2-1,B**2,B**2+1,2**127-1,2**128,2**1024-1]
for radix in range(2,37):
    for value in edge: add(0,value,radix=radix)
    # Case-insensitive digits and strict full input consumption.
    cases.append((0,'000'+fmt(2**191+47,radix).upper(),'1',radix,0,(0,fmt(2**191+47,radix),'0')))
for a in edge:
    for b in edge:
        for op in (1,2,3,4,7,8,9): add(op,a,b,radix=16)
    for shift in (0,1,31,32,33,63,64,65,129,2048):
        add(5,a,argument=shift); add(6,a,argument=shift)
    for op in (12,13,14,15): add(op,a)
# v has a nonzero low digit: a lower division step sees v-1 but
# its leading three digits suggest qhat=1, requiring the final addback.
for low in (1,37,B-1):
    for middle in (0,B//2,B-1):
        v=(B//2)*B**2+middle*B+low
        for u in (v*B+v-1,v*B-1,v*(B-1),v*(B-1)+v-1): add(4,u,v,16)
# The first estimate is two too high, requiring both permitted refinements.
add(4,int('79b3f003b39b2366d5a3dcdf10defe02871307c7',16),int('800d9d65fdb735f92714c642901c942d',16),16)
for _ in range(160):
    a=rng.getrandbits(rng.choice([31,32,33,63,64,65,127,256,512,1024,2048]))
    b=rng.getrandbits(rng.choice([1,32,64,96,192,512]))
    add(rng.randrange(1,11),a,b,radix=rng.randrange(2,37),argument=rng.randrange(200))
# Evolving values exercise sequences with carry-heavy and sparse state.
for _ in range(20):
    a=rng.getrandbits(256)
    for _ in range(20):
        b=rng.getrandbits(160)+1; op=rng.choice([1,2,3,4,7,8,9])
        add(op,a,b,16)
        if op==1: a+=b
        elif op==2: a=abs(a-b)
        elif op==3: a*=b
        elif op==4: a//=b
        elif op==7: a&=b
        elif op==8: a|=b
        else: a^=b
for a,exp in [(0,0),(0,32),(1,2**32-1),(3,137),(B-1,31),(2,4096)]: add(11,a,argument=exp)
for text,radix,err in [('',10,8),('+1',10,7),('-0',10,7),(' 1',10,7),('1 ',10,7),('1_0',10,7),('0x10',16,7),('2',2,7),('z',35,7),('1\x00',10,7),('1',1,6),('1',37,6)]:
    cases.append((0,text,'1',radix,0,(err,'','')))
packet=bytearray()
for op,a,b,radix,arg,expected in cases:
    aa=a.encode(); bb=b.encode(); packet+=struct.pack('<IIIII',op,radix,arg,len(aa),len(bb))+aa+bb
result=subprocess.run([sys.argv[1]],input=packet,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=35)
assert result.returncode==0,(result.returncode,result.stderr,len(result.stdout))
offset=0
for index,case in enumerate(cases):
    status,alen,blen=struct.unpack_from('<III',result.stdout,offset); offset+=12
    a=result.stdout[offset:offset+alen].decode(); offset+=alen
    b=result.stdout[offset:offset+blen].decode(); offset+=blen
    assert (status,a,b)==case[-1],('seed=0xb162026',index,case,(status,a,b))
assert offset==len(result.stdout)
print('verified',len(cases),'oracle cases')
"#;
    let result = common::process_output_with_timeout(
        "BigUint Python integer differential oracle",
        Command::new("python3")
            .args(["-c", oracle])
            .arg(model().path()),
        Duration::from_secs(45),
    );
    assert_eq!(result.status.code(), Some(0), "{result:?}");
}

#[test]
fn ownership_limits_malformed_views_and_atomic_format_output() {
    let exe = executable("big_uint_contracts");
    let result = common::process_output_with_timeout(
        "BigUint contracts",
        &mut Command::new(exe.path()),
        Duration::from_secs(10),
    );
    assert_eq!(result.status.code(), Some(0), "{result:?}");
    assert!(
        result.stdout.is_empty() && result.stderr.is_empty(),
        "{result:?}"
    );
}

#[test]
fn allocator_denial_at_every_attempt_preserves_inputs_and_releases_all_storage() {
    let exe = executable("big_uint_faults");
    let run = |failure: Option<usize>| {
        let trace = common::TempArtifact::new("laniusc_big_uint", "trace", None);
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"]);
        if let Some(attempt) = failure {
            command.args(["-e", &format!("inject=mmap:error=ENOMEM:when={attempt}")]);
        }
        command.arg(exe.path());
        let output = common::process_output_with_timeout(
            "BigUint allocator denial",
            &mut command,
            Duration::from_secs(10),
        );
        assert_eq!(
            output.status.code(),
            Some(0),
            "failure={failure:?} {output:?}"
        );
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
        let text = std::fs::read_to_string(trace.path()).unwrap();
        let mut live = std::collections::BTreeSet::new();
        let mut attempts = 0;
        for line in text.lines() {
            if line.starts_with("mmap(") {
                attempts += 1;
                if !line.contains("= -1") {
                    let pointer = line
                        .split(" = ")
                        .nth(1)
                        .unwrap()
                        .split_whitespace()
                        .next()
                        .unwrap();
                    assert!(live.insert(pointer.to_owned()), "{text}");
                }
            } else if line.starts_with("munmap(") {
                let pointer = line
                    .trim_start_matches("munmap(")
                    .split(',')
                    .next()
                    .unwrap();
                assert!(live.remove(pointer), "{text}");
                assert!(line.ends_with("= 0"), "{text}");
            } else {
                panic!("unexpected syscall: {line}");
            }
        }
        assert!(live.is_empty(), "failure={failure:?}: {text}");
        attempts
    };
    let attempts = run(None);
    assert!(attempts > 10);
    for attempt in 1..=attempts {
        run(Some(attempt));
    }
}
