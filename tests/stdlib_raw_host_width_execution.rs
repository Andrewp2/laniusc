#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
    time::Duration,
};
fn executable(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    // Preserve a compile result even when the independent common jump gate
    // rejects it before TempArtifact::write_bytes writes the file.
    let preserved = root.join(format!("target/stdlib-work/{name}.elf"));
    std::fs::write(&preserved, &bytes).unwrap();
    let oracle = root.join("tests/fixtures/stdlib_foundation/raw_host_width_tables.py");
    let checked_runtime = common::process_output_with_timeout(
        "complete emitted runtime bytes",
        Command::new("python3")
            .arg(oracle)
            .arg("--elf")
            .arg(&preserved),
        Duration::from_secs(15),
    );
    assert!(checked_runtime.status.success(), "{checked_runtime:?}");
    let exe = common::TempArtifact::new("laniusc_raw_width", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

fn checked(out: &Output) {
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    assert!(out.stdout.is_empty() && out.stderr.is_empty(), "{out:?}");
}
fn traced(exe: &common::TempArtifact, args: &[String], syscall: &str, injection: &str) -> String {
    let trace = common::TempArtifact::new("laniusc_raw_width", "trace", None);
    let out = common::process_output_with_timeout(
        "raw host width fault transport",
        Command::new("timeout")
            .args(["--kill-after=1s", "4s", "strace"])
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e"])
            .arg(format!("trace={syscall}"))
            .args(["-e"])
            .arg(format!("raw={syscall}"))
            .args(["-e"])
            .arg(format!("inject={syscall}:{injection}"))
            .arg(exe.path())
            .args(args),
        Duration::from_secs(7),
    );
    checked(&out);
    std::fs::read_to_string(trace.path()).unwrap()
}
fn raw_arguments(trace: &str, syscall: &str) -> Vec<Vec<u64>> {
    trace
        .lines()
        .filter_map(|line| line.strip_prefix(&format!("{syscall}(")))
        .map(|line| {
            line.split_once(')')
                .unwrap()
                .0
                .split(',')
                .map(|value| {
                    let value = value.trim();
                    if let Some(hex) = value.strip_prefix("0x") {
                        u64::from_str_radix(hex, 16).unwrap()
                    } else {
                        value.parse().unwrap()
                    }
                })
                .collect()
        })
        .collect()
}
fn mapping_lifetimes(trace: &str) {
    let mut live = std::collections::BTreeMap::new();
    for line in trace.lines() {
        if !(line.starts_with("mmap(")
            || line.starts_with("mremap(")
            || line.starts_with("munmap("))
        {
            continue;
        }
        let arguments: Vec<&str> = line
            .split_once('(')
            .unwrap()
            .1
            .split_once(')')
            .unwrap()
            .0
            .split(',')
            .map(str::trim)
            .collect();
        let result = line
            .split_once(" = ")
            .unwrap()
            .1
            .split_whitespace()
            .next()
            .unwrap();
        if line.starts_with("mmap(") {
            assert!(result.starts_with("0x"), "{trace}");
            assert!(
                live.insert(result.to_owned(), arguments[1].parse::<usize>().unwrap())
                    .is_none(),
                "{trace}"
            );
        }
        if line.starts_with("mremap(") {
            assert_eq!(
                live.remove(arguments[0]),
                Some(arguments[1].parse::<usize>().unwrap()),
                "{trace}"
            );
            assert!(result.starts_with("0x"), "{trace}");
            assert!(
                live.insert(result.to_owned(), arguments[2].parse::<usize>().unwrap())
                    .is_none(),
                "{trace}"
            );
        }
        if line.starts_with("munmap(") {
            assert_eq!(
                live.remove(arguments[0]),
                Some(arguments[1].parse::<usize>().unwrap()),
                "{trace}"
            );
            assert_eq!(result, "0", "{trace}");
        }
    }
    assert!(live.is_empty(), "{trace}");
}
#[test]
fn assembly_oracle_matches_changed_tables_and_shifted_neighbor_entries() {
    let script = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/raw_host_width_tables.py");
    checked(&common::process_output_with_timeout(
        "raw width assembly oracle",
        Command::new("python3").arg(script),
        Duration::from_secs(15),
    ));
}
#[test]
fn synthetic_sizes_counts_and_capacity_words_reach_the_kernel_without_wrapping() {
    let exe = executable("raw_host_width_transport");
    let sizes = [
        4096u64,
        2147483648,
        4294967296,
        4294971392,
        9223372036854775808,
        u64::MAX,
    ];
    for (index, size) in sizes.into_iter().enumerate() {
        for (mode, syscall, position) in [
            (0, "mmap", 1),
            (1, "mremap", 2),
            (2, "mremap", 1),
            (3, "write", 2),
            (4, "write", 2),
            (5, "read", 2),
            (6, "write", 2),
            (7, "read", 2),
            (8, "getrandom", 1),
            (9, "munmap", 1),
        ] {
            let errno = if mode <= 2 { "ENOMEM" } else { "EIO" };
            let trace = traced(
                &exe,
                &[mode.to_string(), index.to_string()],
                syscall,
                &format!("error={errno}:when=1"),
            );
            assert!(
                trace.contains("INJECTED") && trace.contains(errno),
                "{mode}/{size}: {trace}"
            );
            let calls = raw_arguments(&trace, syscall);
            assert_eq!(calls.len(), 1, "{trace}");
            assert_eq!(calls[0][position], size, "{mode}/{size}: {trace}");
            if mode == 0 {
                assert_eq!(calls[0][3], 0x62, "MAP_32BIT retained: {trace}");
            }
            if mode == 2 {
                assert_eq!(calls[0][2], size, "new size: {trace}");
            }
        }
    }
}
#[test]
fn clock_and_cwd_compare_full_capacities_before_host_access() {
    let exe = executable("raw_host_width_capacity");
    let capacities = [
        0u64,
        15,
        16,
        4294967296,
        4294967297,
        4294967311,
        4294967312,
        u64::MAX,
    ];
    for mode in 0..3 {
        for (index, capacity) in capacities.into_iter().enumerate() {
            let syscall = if mode == 2 { "getcwd" } else { "clock_gettime" };
            let trace = traced(
                &exe,
                &[mode.to_string(), index.to_string()],
                syscall,
                "error=EIO:when=1",
            );
            let calls = raw_arguments(&trace, syscall);
            let valid = if mode == 2 {
                capacity > 0
            } else {
                capacity >= 16
            };
            assert_eq!(
                calls.len(),
                usize::from(valid),
                "{mode}/{capacity}: {trace}"
            );
            if valid {
                assert!(
                    trace.contains("EIO") && trace.contains("INJECTED"),
                    "{trace}"
                );
            }
            if valid && mode == 2 {
                assert_eq!(calls[0][1], capacity, "{trace}");
            }
        }
    }
}
#[test]
fn finite_argument_environment_copies_keep_full_bounds_and_exact_key_identity() {
    let exe = executable("raw_host_width_copy");
    let trace = common::TempArtifact::new("laniusc_raw_width", "copy_trace", None);
    let out = common::process_output_with_timeout(
        "finite source wide capacity probes",
        Command::new("timeout")
            .args(["--kill-after=1s", "4s", "strace"])
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,mprotect,munmap"])
            .arg(exe.path())
            .arg("abcde")
            .env_clear()
            .env("ABC", "value"),
        Duration::from_secs(7),
    );
    checked(&out);
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert_eq!(
        events
            .lines()
            .filter(|line| line.starts_with("mmap("))
            .count(),
        1,
        "{events}"
    );
    assert_eq!(
        events
            .lines()
            .filter(|line| line.starts_with("munmap("))
            .count(),
        1,
        "{events}"
    );
    assert!(
        events.contains("8192") && events.contains("PROT_NONE"),
        "{events}"
    );
    mapping_lifetimes(&events);
    // execve permits an environment entry with no '='. A test-only launcher
    // supplies that finite malformed entry so the native guard-page fixture
    // exercises NUL-before-key-end as well as delimiter-before-key-end.
    let launcher = "import ctypes,os,sys; p=os.fsencode(sys.argv[1]); v=ctypes.c_char_p; argv=(v*3)(p,b'n',None); env=(v*2)(b'ABC',None); f=ctypes.CDLL(None,use_errno=True).execve; f.argtypes=[v,ctypes.POINTER(v),ctypes.POINTER(v)]; f.restype=ctypes.c_int; f(p,argv,env); raise OSError(ctypes.get_errno(),'execve')";
    checked(&common::process_output_with_timeout(
        "NUL-terminated environment key guard",
        Command::new("python3")
            .args(["-c", launcher])
            .arg(exe.path()),
        Duration::from_secs(7),
    ));
}
#[test]
fn small_real_operations_and_allocator_rejections_preserve_owners_and_runtime_neighbors() {
    let exe = executable("raw_host_width_controls");
    let trace = common::TempArtifact::new("laniusc_raw_width", "controls_trace", None);
    let input = common::TempArtifact::new("laniusc_raw_width", "input", None);
    input.write_bytes(&[255, 0, 128]);
    let mut command = Command::new("timeout");
    command.args(["--kill-after=1s","4s","strace","-qq","-o"]).arg(trace.path()).args(["-e","trace=mmap,mremap,munmap,read,write,clock_gettime,getcwd,time,nanosleep,getrandom,open,close,getpid"]).arg(exe.path()).current_dir("/").stdin(std::fs::File::open(input.path()).unwrap());
    let out = common::process_output_with_timeout(
        "small raw host controls",
        &mut command,
        Duration::from_secs(7),
    );
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    assert_eq!(out.stdout, [0, 128, 255]);
    assert_eq!(out.stderr, [0, 128, 255]);
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert_eq!(
        events
            .lines()
            .filter(|line| line.starts_with("mmap("))
            .count(),
        4,
        "invalid sizes/alignments must not allocate: {events}"
    );
    assert_eq!(
        events
            .lines()
            .filter(|line| line.starts_with("mremap("))
            .count(),
        4,
        "invalid realloc must preserve owner without syscall: {events}"
    );
    assert_eq!(
        events
            .lines()
            .filter(|line| line.starts_with("munmap("))
            .count(),
        4,
        "{events}"
    );
    mapping_lifetimes(&events);
    let failed = common::process_output_with_timeout(
        "relocated allocation failure exit",
        Command::new(exe.path()).arg("1"),
        Duration::from_secs(5),
    );
    assert_eq!(failed.status.code(), Some(1), "{failed:?}");
    assert!(failed.stdout.is_empty() && failed.stderr.is_empty());
    let trapped = common::signal_process_output_with_timeout(
        "relocated assertion trap",
        Command::new(exe.path()).arg("2"),
    );
    use std::os::unix::process::ExitStatusExt;
    assert_eq!(trapped.status.signal(), Some(4), "{trapped:?}");
    assert!(trapped.stdout.is_empty() && trapped.stderr.is_empty());
}
#[test]
fn raw_allocation_high_word_is_transported_without_modulo_reduction() {
    let exe = executable("raw_host_width_admission");
    let trace = common::TempArtifact::new("laniusc_raw_width", "trace", None);
    let out = common::process_output_with_timeout(
        "raw width admission",
        Command::new("timeout")
            .args(["--kill-after=1s", "4s", "strace"])
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap", "-e", "inject=mmap:error=ENOMEM:when=1"])
            .arg(exe.path()),
        Duration::from_secs(7),
    );
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    assert!(out.stdout.is_empty() && out.stderr.is_empty(), "{out:?}");
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(
        events.contains("mmap(NULL, 4294971392,"),
        "full size must reach mmap: {events}"
    );
    assert!(
        events.contains("MAP_32BIT") && events.contains("ENOMEM") && events.contains("INJECTED"),
        "{events}"
    );
}
