//! Real SQLite storage, bit transport, ownership, state and persistence contracts.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    io::Write,
    os::unix::{ffi::OsStrExt, fs::PermissionsExt},
    path::{Path, PathBuf},
    process::{Child, Command, Output, Stdio},
    sync::OnceLock,
    time::{Duration, Instant},
};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
fn fixture(name: &str) -> PathBuf {
    root().join("tests/fixtures/extended/sqlite").join(name)
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("SQLite execution", command, Duration::from_secs(30))
}
fn success(output: &Output) {
    common::assert_command_success("SQLite execution", output);
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn compile(name: &str) -> common::TempArtifact {
    let entry = fixture(&format!("{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("SQLite native execution", move || {
        let options = laniusc_compiler::compiler::NativeLinkOptions {
            libraries: vec!["sqlite3".into()],
            ..Default::default()
        };
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                &entry, &roots, &options,
            ),
        )
    })
    .unwrap_or_else(|error| panic!("SQLite {name}: {error}"));
    let executable = common::TempArtifact::new("laniusc_sqlite", name, None);
    // This ELF includes platform startup and PLT code; use the linked checker.
    std::fs::write(executable.path(), bytes).unwrap();
    success(&run(Command::new("python3")
        .arg(root().join("tests/fixtures/native_c/validate_linked_elf.py"))
        .arg(executable.path())));
    let dynamic = run(Command::new("readelf").arg("-d").arg(executable.path()));
    success(&dynamic);
    assert!(String::from_utf8_lossy(&dynamic.stdout).contains("libsqlite3.so"));
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn protocol() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| compile("protocol"))
}
fn faults() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| compile("faults"))
}
fn input(bytes: &[u8]) -> common::TempArtifact {
    let file = common::TempArtifact::new("laniusc_sqlite", "input", None);
    file.write_bytes(bytes);
    file
}
fn words(bytes: &[u8]) -> Vec<u64> {
    assert_eq!(bytes.len() % 8, 0, "truncated SQLite protocol output");
    bytes
        .chunks_exact(8)
        .map(|word| u64::from_le_bytes(word.try_into().unwrap()))
        .collect()
}

#[derive(Clone, Debug)]
struct Case {
    op: u64,
    key: i64,
    integer: i64,
    real_bits: u64,
    text: Vec<u8>,
    blob: Vec<u8>,
    layout: u64,
    offset: u64,
}
impl Case {
    fn op(op: u64) -> Self {
        Self {
            op,
            key: 0,
            integer: 0,
            real_bits: 0,
            text: Vec::new(),
            blob: Vec::new(),
            layout: 0,
            offset: 3,
        }
    }
}
fn packet(cases: &[Case], mode: u64, path: Option<&Path>) -> Vec<u8> {
    let path = path.map_or(&[][..], |path| path.as_os_str().as_bytes());
    let mut output = Vec::new();
    for word in [mode, path.len() as u64, cases.len() as u64] {
        output.extend(word.to_le_bytes());
    }
    output.extend(path);
    for case in cases {
        for word in [
            case.op,
            case.key as u64,
            case.integer as u64,
            case.real_bits,
            case.text.len() as u64,
            case.blob.len() as u64,
            case.layout,
            case.offset,
        ] {
            output.extend(word.to_le_bytes());
        }
        output.extend(&case.text);
        output.extend(&case.blob);
    }
    output
}
fn oracle(packet: &[u8]) -> Vec<u64> {
    let source = input(packet);
    let output = run(Command::new("python3")
        .arg(fixture("oracle.py"))
        .stdin(std::fs::File::open(source.path()).unwrap()));
    success(&output);
    words(&output.stdout)
}
fn execute(packet: &[u8]) -> Vec<u64> {
    let source = input(packet);
    let output =
        run(Command::new(protocol().path()).stdin(std::fs::File::open(source.path()).unwrap()));
    success(&output);
    words(&output.stdout)
}
fn compare(cases: &[Case], mode: u64, path: Option<&Path>) {
    let packet = packet(cases, mode, path);
    let expected = oracle(&packet);
    let actual = execute(&packet);
    if actual != expected {
        let first = actual.iter().zip(&expected).position(|(a, b)| a != b);
        panic!(
            "SQLite protocol differs at word {first:?}; actual/expected lengths {}/{}; actual prefix {:?}; expected prefix {:?}; cases {cases:?}",
            actual.len(),
            expected.len(),
            &actual[..actual.len().min(80)],
            &expected[..expected.len().min(80)]
        );
    }
}
fn random(state: &mut u64) -> u64 {
    *state ^= *state << 13;
    *state ^= *state >> 7;
    *state ^= *state << 17;
    *state
}
fn binary(length: usize) -> Vec<u8> {
    (0..length)
        .map(|i| ((i * 73 + 11) ^ (i / 251)) as u8)
        .collect()
}

#[test]
fn storage_classes_full_integers_and_exact_binary64_cross_all_byte_layouts() {
    let integers = [
        i64::MIN,
        i64::MIN + 1,
        -(1 << 53) - 1,
        -4294967296,
        -2147483649,
        -1,
        0,
        1,
        2147483648,
        4294967296,
        (1 << 53) + 1,
        i64::MAX - 1,
        i64::MAX,
    ];
    let mut floating = vec![
        0,
        1,
        0x8000000000000000,
        0x8000000000000001,
        0x000fffffffffffff,
        0x0010000000000000,
        0x3fb999999999999a,
        0x3ff0000000000001,
        0x400921fb54442d18,
        0xbfd5555555555555,
        0x7fefffffffffffff,
        0xffefffffffffffff,
        0x7ff0000000000000,
        0xfff0000000000000,
    ];
    let mut seed = 0x97fa_541c_eb21_0d39;
    for _ in 0..48 {
        let value = random(&mut seed);
        if value & 0x7ff0000000000000 != 0x7ff0000000000000 {
            floating.push(value);
        }
    }
    let texts = [
        Vec::new(),
        b"ASCII\0with NUL".to_vec(),
        "café λ 🦅\n".as_bytes().to_vec(),
        b"x".repeat(1023),
        b"y".repeat(1024),
        "é".repeat(1024).into_bytes(),
    ];
    let blobs = [
        Vec::new(),
        vec![0],
        vec![0, 255, 128, 0, 1],
        binary(255),
        binary(1023),
        binary(1024),
        binary(1025),
        binary(2048),
    ];
    let mut cases = Vec::new();
    for layout in 0..9 {
        for (index, bits) in floating.iter().enumerate() {
            let mut case = Case::op(9);
            case.key = integers[index % integers.len()];
            case.integer = integers[(index * 7 + 3) % integers.len()];
            case.real_bits = *bits;
            case.text = texts[index % texts.len()].clone();
            case.blob = blobs[index % blobs.len()].clone();
            case.layout = layout;
            case.offset = (index % 16) as u64;
            cases.push(case);
        }
    }
    compare(&cases, 0, None);
}

#[test]
fn deterministic_transactions_and_changes_follow_an_independent_dictionary_model() {
    let mut cases = Vec::new();
    let mut seed = 0xc4eb_7319_0a2d_8165;
    for batch in 0..32 {
        cases.push(Case::op(5));
        for _ in 0..16 {
            let mut case = Case::op(random(&mut seed) % 4);
            case.key = (random(&mut seed) % 65) as i64 - 32;
            case.integer = random(&mut seed) as i64;
            case.real_bits = ((random(&mut seed) as i64 % 100000) as f64 / 8.0).to_bits();
            case.text = format!("record\0λ:{}", random(&mut seed) % 997).into_bytes();
            case.blob = binary((random(&mut seed) % 64) as usize);
            case.layout = random(&mut seed) % 9;
            case.offset = random(&mut seed) % 16;
            cases.push(case);
        }
        cases.push(Case::op(4));
        cases.push(Case::op(if batch % 3 == 0 { 7 } else { 6 }));
        cases.push(Case::op(4));
    }
    compare(&cases, 0, None);
}

struct LockHolder(Child);
impl Drop for LockHolder {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

#[test]
fn file_commit_rollback_readonly_and_native_write_locks_preserve_persistent_rows() {
    let database = common::TempArtifact::new("laniusc_sqlite", "persistent", Some("db"));
    let mut first = Case::op(0);
    first.key = i64::MIN + 1;
    first.integer = i64::MAX;
    first.real_bits = 0x8000000000000000;
    first.text = "committed\0λ".as_bytes().to_vec();
    first.blob = vec![0, 255, 128, 0];
    let mut second = first.clone();
    second.key = 7;
    second.text = b"rolled back".to_vec();
    let writes = [
        Case::op(5),
        first.clone(),
        Case::op(6),
        Case::op(5),
        second.clone(),
        Case::op(7),
        Case::op(4),
    ];
    compare(&writes, 0, Some(database.path()));
    compare(
        &[Case::op(4), second.clone(), Case::op(4)],
        1,
        Some(database.path()),
    );
    assert_eq!(
        &std::fs::read(database.path()).unwrap()[..16],
        b"SQLite format 3\0"
    );

    let ready = common::TempArtifact::new("laniusc_sqlite", "lock_ready", None);
    let holder = Command::new("python3")
        .args(["-c", "import sqlite3,sys,pathlib; c=sqlite3.connect(sys.argv[1],timeout=0,isolation_level=None); c.execute('begin immediate'); pathlib.Path(sys.argv[2]).write_text('ready'); sys.stdin.buffer.read(1); c.rollback(); c.close()"])
        .arg(database.path()).arg(ready.path())
        .stdin(Stdio::piped()).stdout(Stdio::null()).stderr(Stdio::piped()).spawn().unwrap();
    let mut holder = LockHolder(holder);
    let started = Instant::now();
    while !ready.path().exists() {
        assert!(
            started.elapsed() < Duration::from_secs(5),
            "SQLite lock holder did not become ready"
        );
        assert!(
            holder.0.try_wait().unwrap().is_none(),
            "SQLite lock holder exited early"
        );
        std::thread::sleep(Duration::from_millis(5));
    }
    assert_eq!(
        execute(&packet(&[second.clone()], 2, Some(database.path()))),
        vec![0, 1, 5]
    );
    holder.0.stdin.take().unwrap().write_all(b"x").unwrap();
    drop(holder);
    compare(&[Case::op(4)], 1, Some(database.path()));
    // Reopen normally after lock release and successfully commit the same row.
    assert_eq!(
        execute(&packet(&[second], 2, Some(database.path()))),
        vec![0, 0, 1, 7]
    );
    compare(&[Case::op(4)], 1, Some(database.path()));
}

#[test]
fn bounded_bulk_transaction_reuses_statements_and_reports_native_time_and_memory() {
    let mut benchmark = Case::op(10);
    benchmark.key = 32768;
    let packet = packet(&[benchmark], 0, None);
    let expected = oracle(&packet);
    let _ = protocol(); // GPU compilation is excluded from the runtime sample.
    let started = Instant::now();
    let actual = execute(&packet);
    let elapsed = started.elapsed();
    assert_eq!(actual.len(), expected.len() + 1);
    assert_eq!(&actual[..expected.len()], expected);
    let native_peak = *actual.last().unwrap();
    assert!(
        native_peak > 0 && native_peak < 64 * 1024 * 1024,
        "native SQLite peak: {native_peak}"
    );
    assert!(
        elapsed < Duration::from_secs(15),
        "bounded SQLite workload: {elapsed:?}"
    );
    eprintln!(
        "SQLite 32768 inserts + 32768 indexed selects: {elapsed:?}; sqlite3_memory_highwater={native_peak} bytes"
    );
}

#[test]
fn injected_native_failures_preserve_output_and_obey_resource_and_state_contracts() {
    let interposer = common::TempArtifact::new("laniusc_sqlite", "faults", Some("so"));
    success(&run(Command::new("cc")
        .args([
            "-shared", "-fPIC", "-std=c11", "-Wall", "-Wextra", "-Werror",
        ])
        .arg(fixture("fault_interposer.c"))
        .arg("-o")
        .arg(interposer.path())
        .args(["-ldl", "-lsqlite3"])));
    for (mode, phase, code, trace) in fault_cases() {
        let events = common::TempArtifact::new("laniusc_sqlite", mode, Some("trace"));
        let output = run(Command::new(faults().path())
            .env("LD_PRELOAD", interposer.path())
            .env("LANIUS_SQLITE_FAULT", mode)
            .env("LANIUS_SQLITE_TRACE", events.path()));
        success(&output);
        assert_eq!(words(&output.stdout), vec![phase, code], "fault {mode}");
        assert_eq!(
            std::fs::read_to_string(events.path()).unwrap(),
            trace,
            "fault trace {mode}"
        );
    }
}

fn fault_cases() -> Vec<(&'static str, u64, u64, &'static str)> {
    vec![
        ("open-null", 1, 14, "O"),
        ("open-handle", 1, 14, "OC"),
        ("open-ok-null", 1, 0, "O"),
        ("configure-extended", 2, 21, "OXC"),
        ("configure-busy", 2, 7, "OXYC"),
        ("readonly-fallback", 1, 8, "OXYRC"),
        ("prepare-handle", 3, 7, "OXYRPFC"),
        ("prepare-tail", 3, 0, "OXYRPFC"),
        ("bind-int", 4, 25, "OXYRPiFC"),
        ("bind-real", 4, 7, "OXYRPidFC"),
        ("bind-text", 4, 7, "OXYRPidtFC"),
        ("bind-blob", 4, 7, "OXYRPidtbFC"),
        ("clear", 7, 7, "OXYRPidtbKFC"),
        ("reset", 6, 19, "OXYRPidtbKQFC"),
        ("step", 5, 5, "OXYRPidtbKQSQFC"),
        ("column-text-null", 8, 7, "OXYRPidtbKQSTEQSFC"),
        ("column-blob-null", 8, 7, "OXYRPidtbKQSTNBEQSFC"),
        ("column-bytes-zero", 8, 7, "OXYRPidtbKQSTNEQSFC"),
        ("column-invalid-utf8", 8, 0, "OXYRPidtbKQSTNFC"),
        ("finalize", 9, 10, "OXYRPidtbKQSTNBNFC"),
        ("close", 10, 5, "OXYRPidtbKQSTNBNFCC"),
    ]
}
