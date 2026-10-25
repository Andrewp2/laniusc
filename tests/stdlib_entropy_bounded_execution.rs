//! Nonblocking entropy: syscall byte provenance, bounded retries and prefix atomicity.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::VecDeque,
    os::unix::fs::PermissionsExt,
    process::Command,
    sync::OnceLock,
    time::Duration,
};
fn compile(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_entropy_bounded")
        .join(name);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("bounded entropy {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_entropy_bounded", name, None);
    file.write_bytes(bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn protocol() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| compile("protocol.lani"))
}
#[derive(Clone, Debug)]
struct Request {
    operation: u64,
    layout: u64,
    budget: u64,
    offset: i32,
    count: i32,
    second_offset: i32,
    second_count: i32,
    injection: Option<&'static str>,
    synthetic: Option<Vec<u8>>,
}
fn request(operation: u64, count: i32, budget: u64) -> Request {
    Request {
        operation,
        layout: 0,
        budget,
        offset: 3,
        count,
        second_offset: 600,
        second_count: 17,
        injection: None,
        synthetic: None,
    }
}
impl Request {
    fn input(&self) -> Vec<u8> {
        [
            self.operation,
            self.layout,
            self.budget,
            self.offset as u64,
            self.count as u64,
            self.second_offset as u64,
            self.second_count as u64,
        ]
        .into_iter()
        .flat_map(u64::to_le_bytes)
        .collect()
    }
}
#[derive(Clone, Debug)]
struct Call {
    requested: usize,
    status: i64,
    data: Vec<u8>,
    injected: bool,
}
fn errno(name: &str) -> i32 {
    match name {
        "EINTR" => 4,
        "EIO" => 5,
        "EAGAIN" => 11,
        "ENOSYS" => 38,
        "EFAULT" => 14,
        "EINVAL" => 22,
        "EPERM" => 1,
        _ => panic!("unrecognized errno {name}"),
    }
}
fn hex_string(value: &str) -> Vec<u8> {
    assert!(
        value.starts_with('"') && value.ends_with('"'),
        "non-string successful output {value}"
    );
    let inner = &value[1..value.len() - 1];
    assert_eq!(inner.len() % 4, 0);
    inner
        .as_bytes()
        .chunks_exact(4)
        .map(|chunk| {
            assert_eq!(&chunk[..2], b"\\x");
            u8::from_str_radix(std::str::from_utf8(&chunk[2..]).unwrap(), 16).unwrap()
        })
        .collect()
}
fn parse(trace: &str, synthetic: Option<&[u8]>) -> VecDeque<Call> {
    let mut calls = VecDeque::new();
    for line in trace.lines() {
        assert!(
            !["mmap(", "mremap(", "munmap(", "brk("]
                .iter()
                .any(|name| line.starts_with(name)),
            "allocation: {trace}"
        );
        if !line.starts_with("getrandom(") {
            continue;
        }
        // strace pads short syscall renderings to align the result column.
        let (head, result) = line
            .rsplit_once(" = ")
            .unwrap_or_else(|| panic!("missing getrandom result: {line}"));
        let head = head
            .trim_end()
            .strip_suffix(')')
            .unwrap_or_else(|| panic!("missing getrandom argument close: {line}"));
        let (head, flags) = head.rsplit_once(", ").unwrap();
        assert_eq!(flags, "GRND_NONBLOCK", "{line}");
        let (buffer, count) = head
            .strip_prefix("getrandom(")
            .unwrap()
            .rsplit_once(", ")
            .unwrap();
        let requested: usize = count.parse().unwrap();
        assert!((1..=256).contains(&requested), "{line}");
        let mut result = result.split_whitespace();
        let raw: i64 = result.next().unwrap().parse().unwrap();
        let status = if raw == -1 {
            -(errno(result.next().unwrap()) as i64)
        } else {
            raw
        };
        let injected = line.contains("INJECTED");
        let data = if status > 0 && status <= requested as i64 {
            if injected {
                let explicit = synthetic
                    .expect("a synthetic successful count must include explicit poke data");
                assert!(explicit.len() >= status as usize);
                explicit[..status as usize].to_vec()
            } else {
                let data = hex_string(buffer);
                assert_eq!(data.len(), status as usize, "{line}");
                data
            }
        } else {
            Vec::new()
        };
        calls.push_back(Call {
            requested,
            status,
            data,
            injected,
        });
    }
    calls
}
fn execute(
    file: &common::TempArtifact,
    input: &[u8],
    injection: Option<&str>,
) -> (Vec<u8>, String) {
    let source = common::TempArtifact::new("laniusc_entropy_bounded", "input", None);
    source.write_bytes(input);
    let log = common::TempArtifact::new("laniusc_entropy_bounded", "trace", None);
    let mut command = Command::new("strace");
    command
        .args(["-qq", "-xx", "-s", "512", "-o"])
        .arg(log.path())
        .args([
            "-e",
            "trace=getrandom,mmap,mremap,munmap,brk",
            "-e",
            "signal=none",
        ]);
    if let Some(spec) = injection {
        command.arg("-e").arg(format!("inject={spec}"));
    }
    command
        .arg(file.path())
        .stdin(std::fs::File::open(source.path()).unwrap());
    let output = common::process_output_with_timeout(
        "bounded entropy native process",
        &mut command,
        Duration::from_secs(15),
    );
    let trace = std::fs::read_to_string(log.path()).unwrap();
    assert_eq!(output.status.code(), Some(0), "{output:?}\n{trace}");
    // Some strace builds also prepare a compat-personality injection and warn
    // about its 32-bit limit. The native 64-bit trace/result assertions below
    // still require the full injected value and InvalidCount response.
    let wide_warning =
        b"strace: Injected return value 4294967296 will be clipped to 0 in compat personality\n";
    let expected_warning = injection.is_some_and(|spec| spec.contains("retval=4294967296:"))
        && output.stderr == wide_warning;
    assert!(
        output.stderr.is_empty() || expected_warning,
        "{output:?}\n{trace}"
    );
    (output.stdout, trace)
}
// Independent boundary model consumes observed host events, not native reports.
// Host bytes come from strace, while synthetic bytes come from declared pokes.
fn read_model(
    budget: &mut u64,
    bytes: &mut [u8],
    offset: i32,
    count: i32,
    calls: &mut VecDeque<Call>,
) -> Result<i32, u64> {
    if offset < 0 || count < 0 || (offset as i64) + (count as i64) > i32::MAX as i64 {
        return Err(1);
    }
    if count == 0 {
        return Ok(0);
    }
    if *budget == 0 {
        return Err(4);
    }
    *budget -= 1;
    let call = calls
        .pop_front()
        .expect("library failed to make a budgeted host attempt");
    let amount = count.min(256) as usize;
    assert_eq!(call.requested, amount);
    if call.status < 0 {
        return Err(100 + (-call.status) as u64);
    }
    if call.status == 0 {
        return Err(2);
    }
    if call.status > amount as i64 {
        return Err(3);
    }
    let received = call.status as usize;
    assert_eq!(call.data.len(), received);
    bytes[offset as usize..offset as usize + received].copy_from_slice(&call.data);
    Ok(received as i32)
}
fn perform_model(
    fill: bool,
    budget: &mut u64,
    bytes: &mut [u8],
    offset: i32,
    count: i32,
    calls: &mut VecDeque<Call>,
) -> (u64, u64) {
    if !fill {
        return match read_model(budget, bytes, offset, count, calls) {
            Ok(n) => (0, n as u64),
            Err(code) => (code, 0),
        };
    }
    if offset < 0 || count < 0 || (offset as i64) + (count as i64) > i32::MAX as i64 {
        return (1, 0);
    }
    let mut completed = 0;
    while completed < count {
        match read_model(budget, bytes, offset + completed, count - completed, calls) {
            Ok(n) => completed += n,
            Err(104) => {}
            Err(code) => return (code, completed as u64),
        }
    }
    (0, completed as u64)
}
fn words(bytes: &[u8]) -> Vec<u64> {
    assert_eq!(bytes.len() % 8, 0);
    bytes
        .chunks_exact(8)
        .map(|b| u64::from_le_bytes(b.try_into().unwrap()))
        .collect()
}
fn check(case: &Request) -> Vec<u64> {
    let (stdout, trace) = execute(protocol(), &case.input(), case.injection);
    let mut calls = parse(&trace, case.synthetic.as_deref());
    if case.injection.is_some() {
        assert!(
            calls.iter().any(|c| c.injected),
            "injection did not execute: {case:?}\n{trace}"
        );
    }
    if case
        .injection
        .is_some_and(|spec| spec.contains("retval=4294967296:"))
    {
        assert_eq!(calls.front().unwrap().status, 4_294_967_296);
    }
    let mut budget = case.budget;
    let mut bytes = vec![165; 1024];
    let mut expected = Vec::new();
    let mut operations = vec![(case.offset, case.count)];
    if case.operation >= 2 {
        operations.push((case.second_offset, case.second_count));
    }
    for (offset, count) in operations {
        let (code, completed) = perform_model(
            case.operation == 1 || case.operation == 3,
            &mut budget,
            &mut bytes,
            offset,
            count,
            &mut calls,
        );
        expected.extend([code, completed, budget]);
        expected.extend(bytes.iter().map(|&b| b as u64));
    }
    assert!(calls.is_empty(), "extra host attempts: {case:?}\n{trace}");
    let actual = words(&stdout);
    assert_eq!(actual, expected, "{case:?}\n{trace}");
    actual
}
#[test]
fn bounded_entropy_actual_host_bytes_layouts_and_chunks() {
    for layout in [0, 1] {
        for (operation, count, budget) in [
            (0, 700, 3),
            (0, 17, u64::MAX),
            (1, 700, 3),
            (1, 1, 1),
            (1, 256, 1),
            (1, 257, 2),
            (2, 300, 3),
        ] {
            let mut c = request(operation, count, budget);
            c.layout = layout;
            let got = check(&c);
            assert_eq!(got[0], 0, "ordinary OS entropy unavailable");
            assert_eq!(
                got[1],
                if operation == 0 || operation == 2 {
                    count.min(256) as u64
                } else {
                    count as u64
                }
            );
        }
        let mut c = request(3, 300, 3);
        c.layout = layout;
        c.second_count = 257;
        let got = check(&c);
        assert_eq!(&got[..3], &[0, 300, 1]);
        assert_eq!(&got[1027..1030], &[4, 256, 0]);
    }
}
#[test]
fn bounded_entropy_metadata_zero_and_shared_budget_priority() {
    for layout in [0, 1] {
        for operation in [0, 1] {
            for (offset, count, budget, code) in [
                (-1, 0, 0, 1),
                (0, -1, 0, 1),
                (i32::MAX, 1, 0, 1),
                (i32::MAX - 1, 3, 7, 1),
                (i32::MAX, 0, 0, 0),
                (3, 0, 9, 0),
                (3, 1, 0, 4),
                (3, 700, 0, 4),
            ] {
                let mut c = request(operation, count, budget);
                c.offset = offset;
                c.layout = layout;
                let got = check(&c);
                assert_eq!(&got[..3], &[code, 0, budget]);
            }
        }
        let mut c = request(2, 0, 0);
        c.offset = i32::MAX;
        c.layout = layout;
        let got = check(&c);
        assert_eq!(&got[..3], &[0, 0, 0]);
        assert_eq!(&got[1027..1030], &[4, 0, 0]);
        let mut c = request(2, 0, 1);
        c.offset = -1;
        c.layout = layout;
        let got = check(&c);
        assert_eq!(&got[..3], &[1, 0, 1]);
        assert_eq!(&got[1027..1030], &[0, 17, 0]);
        let mut c = request(3, 17, 1);
        c.layout = layout;
        let got = check(&c);
        assert_eq!(&got[..3], &[0, 17, 0]);
        assert_eq!(&got[1027..1030], &[4, 0, 0]);
    }
}
#[test]
fn bounded_entropy_injected_errors_short_reads_and_prefixes() {
    // Partial success is synthetic: strace skips the real syscall and writes
    // these exact five bytes. These are never described as sampled entropy.
    const SHORT: &str = "getrandom:retval=5:poke_exit=@arg1=0123456789:when=1";
    let mut cases = Vec::new();
    for (operation, count, budget, spec, code, completed, remaining) in [
        (0, 17, 3, "getrandom:error=EINTR:when=1", 104, 0, 2),
        (1, 257, 3, "getrandom:error=EINTR:when=1", 0, 257, 0),
        (1, 17, 3, "getrandom:error=EINTR:when=1+", 4, 0, 0),
        (1, 17, 100, "getrandom:error=EAGAIN:when=1+", 111, 0, 99),
        (0, 17, 100, "getrandom:error=EIO:when=1", 105, 0, 99),
        (1, 17, 5, "getrandom:error=ENOSYS:when=1", 138, 0, 4),
        (
            1,
            17,
            3,
            "getrandom:retval=0:poke_exit=@arg1=deadbeef:when=1",
            2,
            0,
            2,
        ),
        (
            1,
            17,
            3,
            "getrandom:retval=257:poke_exit=@arg1=deadbeef:when=1",
            3,
            0,
            2,
        ),
        (0, 17, 3, "getrandom:retval=4294967296:when=1", 3, 0, 2),
        (0, 17, 3, SHORT, 0, 5, 2),
        (1, 17, 3, SHORT, 0, 17, 1),
        (1, 17, 1, SHORT, 4, 5, 0),
        (
            1,
            17,
            3,
            "getrandom:retval=5:poke_exit=@arg1=0123456789:when=1+",
            4,
            15,
            0,
        ),
        (0, 3, 3, SHORT, 3, 0, 2),
        (
            1,
            700,
            5,
            "getrandom:error=EIO:poke_exit=@arg1=deadbeef:when=2",
            105,
            256,
            3,
        ),
        (1, 700, 5, "getrandom:error=EAGAIN:when=2", 111, 256, 3),
        (1, 700, 5, "getrandom:retval=0:when=2", 2, 256, 3),
        (1, 700, 5, "getrandom:retval=257:when=2", 3, 256, 3),
    ] {
        let mut c = request(operation, count, budget);
        c.injection = Some(spec);
        if spec.contains("retval=5:") {
            c.synthetic = Some(vec![1, 35, 69, 103, 137]);
        }
        cases.push((c, [code, completed, remaining]));
    }
    for layout in [0, 1] {
        for (c, header) in &cases {
            let mut c = c.clone();
            c.layout = layout;
            let got = check(&c);
            assert_eq!(&got[..3], header, "{c:?}");
        }
        let mut c = request(2, 17, 3);
        c.layout = layout;
        c.injection = Some("getrandom:error=EINTR:when=1");
        let got = check(&c);
        assert_eq!(&got[..3], &[104, 0, 2]);
        assert_eq!(&got[1027..1030], &[0, 17, 1]);
        let mut c = request(3, 17, 2);
        c.layout = layout;
        c.injection = Some("getrandom:error=EINTR:when=1+");
        let got = check(&c);
        assert_eq!(&got[..3], &[4, 0, 0]);
        assert_eq!(&got[1027..1030], &[4, 0, 0]);
    }
}
#[test]
fn bounded_entropy_ordinary_consumer_without_error_projection() {
    let file = compile("consumer.lani");
    let (stdout, trace) = execute(&file, &[], None);
    let calls = parse(&trace, None);
    assert_eq!(calls.len(), 3);
    assert_eq!(
        calls.iter().map(|c| c.requested).collect::<Vec<_>>(),
        [256, 1, 17]
    );
    let expected: Vec<u8> = calls
        .iter()
        .flat_map(|c| {
            assert!(c.status > 0);
            c.data.clone()
        })
        .collect();
    assert_eq!(stdout, expected);
    assert_eq!(stdout.len(), 274);
}
