//! Borrowed streaming encoding admission, contracts and bounded owner lifetimes.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    ffi::{c_char, c_int, c_uint, c_ulong, c_void},
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    time::{Duration, Instant},
};
fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/extended_streaming_deflate")
        .join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![
            root.join("extended"),
            root.join("tests/fixtures/extended_streaming_deflate"),
        ],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_streaming_deflate", name, None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn returned(line: &str) -> &str {
    line.rsplit_once('=').unwrap().1.trim()
}
fn args(line: &str) -> &str {
    line.rsplit_once('=')
        .unwrap()
        .0
        .trim_end()
        .strip_suffix(')')
        .unwrap()
        .split_once('(')
        .unwrap()
        .1
}
fn pointer(value: &str) -> u64 {
    u64::from_str_radix(value.trim().strip_prefix("0x").unwrap(), 16).unwrap()
}
#[derive(Debug, Default)]
struct Observed {
    allocations: Vec<usize>,
    releases: usize,
    phases: usize,
    output: usize,
}
fn ledger(events: &str, stderr: &[u8], expected: &[usize]) -> Observed {
    let mut live = BTreeMap::<u64, usize>::new();
    let mut observed = Observed::default();
    let mut markers = Vec::new();
    let (mut setup, mut sealed, mut pure, mut cleanup, mut done) =
        (false, false, false, false, false);
    let (mut entries, mut exits) = (0, 0);
    for line in events.lines() {
        if line.starts_with("write(2,") {
            assert!(!done);
            assert_eq!(returned(line), "1");
            let marker = *b"ASPpRED"
                .iter()
                .find(|&&byte| line.contains(&format!("\"{}\", 1)", char::from(byte))))
                .unwrap();
            markers.push(marker);
            match marker {
                b'A' => {
                    assert!(!setup && !sealed && live.is_empty());
                    setup = true;
                }
                b'S' => {
                    assert!(setup && !sealed);
                    sealed = true;
                    assert_eq!(observed.allocations, expected);
                }
                b'P' => {
                    assert!(sealed && !pure && !cleanup);
                    pure = true;
                }
                b'p' => {
                    assert!(pure);
                    pure = false;
                    observed.phases += 1;
                }
                b'R' => {
                    assert!(sealed && !pure && !cleanup);
                    cleanup = true;
                }
                b'E' => {
                    assert!(cleanup && live.is_empty());
                    sealed = false;
                }
                b'D' => {
                    assert!(cleanup && !sealed && live.is_empty());
                    done = true;
                }
                _ => unreachable!(),
            }
            continue;
        }
        assert!(!pure, "borrowed encoding performed a host effect: {line}");
        if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            assert!(done && live.is_empty());
            exits += 1;
            continue;
        }
        assert!(!done);
        if line.starts_with("execve(") {
            assert!(!setup);
            assert_eq!(returned(line), "0");
            entries += 1;
        } else if line.starts_with("mmap(") {
            assert!(setup && !sealed && !cleanup);
            let fields = args(line).split(',').map(str::trim).collect::<Vec<_>>();
            assert_eq!(fields.len(), 6);
            assert_eq!(fields[0], "NULL");
            assert_eq!(
                &fields[2..],
                &[
                    "PROT_READ|PROT_WRITE",
                    "MAP_PRIVATE|MAP_ANONYMOUS",
                    "-1",
                    "0"
                ]
            );
            let size: usize = fields[1].parse().unwrap();
            assert!(size > 0);
            let address = pointer(returned(line));
            let end = address.checked_add(size as u64).unwrap();
            assert!(
                live.iter()
                    .all(|(&start, &length)| end <= start || address >= start + length as u64)
            );
            assert!(live.insert(address, size).is_none());
            observed.allocations.push(size);
        } else if line.starts_with("munmap(") {
            assert!(cleanup);
            let (address, size) = args(line).split_once(',').unwrap();
            let size: usize = size.trim().parse().unwrap();
            assert_eq!(
                live.remove(&pointer(address)),
                Some(size),
                "full-width address and exact live extent: {line}"
            );
            assert_eq!(returned(line), "0");
            observed.releases += 1;
        } else if line.starts_with("write(1,") {
            assert!(sealed && !cleanup);
            assert_eq!(live.len(), expected.len());
            let count: usize = args(line)
                .rsplit_once(',')
                .unwrap()
                .1
                .trim()
                .parse()
                .unwrap();
            let used: usize = returned(line).parse().unwrap();
            assert!(used > 0 && used <= count);
            observed.output += used;
        } else {
            panic!("unexpected host effect: {line}");
        }
    }
    assert!(done && live.is_empty());
    assert_eq!((entries, exits), (1, 1));
    assert_eq!(observed.releases, expected.len());
    assert_eq!(stderr, markers);
    observed
}
fn execute(name: &str, expected: &[usize]) -> (Vec<u8>, Observed, Duration, Duration) {
    let started = Instant::now();
    let executable = executable(name);
    let compile = started.elapsed();
    let trace = common::TempArtifact::new("laniusc_streaming_deflate", "trace", None);
    let started = Instant::now();
    let output = common::process_output_with_timeout(
        name,
        Command::new("strace")
            .args(["--kill-on-exit", "-qq", "-s", "64", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=all", "-e", "signal=none"])
            .arg(executable.path()),
        Duration::from_secs(20),
    );
    let native = started.elapsed();
    let events = fs::read_to_string(trace.path()).unwrap();
    assert_eq!(
        output.status.code(),
        Some(0),
        "{name}: {output:?}\n{events}"
    );
    let observed = ledger(&events, &output.stderr, expected);
    assert_eq!(observed.output, output.stdout.len());
    (output.stdout, observed, compile, native)
}
const WORKSPACE: [usize; 3] = [32772, 32777, 32772 * 4];
#[test]
fn streaming_deflate_raw_zlib_gzip_native_admission() {
    let (output, observed, compile, native) = execute("admission.lani", &WORKSPACE);
    assert!(output.is_empty());
    assert_eq!(observed.phases, 1);
    eprintln!(
        "streaming-deflate admission formats=3 exact-maps=3 exact-releases=3 native-seconds={:.6} compile-seconds={:.6}",
        native.as_secs_f64(),
        compile.as_secs_f64()
    );
}

#[test]
fn streaming_deflate_metadata_first_recovery_reset_and_terminal_state_preserve_backing() {
    let expected: Vec<_> = WORKSPACE.into_iter().chain(WORKSPACE).collect();
    let (output, observed, compile, native) = execute("metadata.lani", &expected);
    assert!(output.is_empty());
    assert_eq!(observed.phases, 1);
    eprintln!(
        "streaming-deflate metadata descriptor-classes=9 step-metadata-classes=6 saved-workspace-bytes=196637 exact-maps=6 exact-releases=6 native-seconds={:.6} compile-seconds={:.6}",
        native.as_secs_f64(),
        compile.as_secs_f64()
    );
}

// System zlib is an independent test oracle, not a production dependency.
#[repr(C)]
struct ZStream {
    next_in: *const u8,
    avail_in: c_uint,
    total_in: c_ulong,
    next_out: *mut u8,
    avail_out: c_uint,
    total_out: c_ulong,
    message: *const c_char,
    state: *mut c_void,
    allocate: Option<unsafe extern "C" fn(*mut c_void, c_uint, c_uint) -> *mut c_void>,
    free: Option<unsafe extern "C" fn(*mut c_void, *mut c_void)>,
    opaque: *mut c_void,
    data_type: c_int,
    adler: c_ulong,
    reserved: c_ulong,
}
#[link(name = "z")]
unsafe extern "C" {
    fn zlibVersion() -> *const c_char;
    fn inflateInit2_(
        stream: *mut ZStream,
        window: c_int,
        version: *const c_char,
        size: c_int,
    ) -> c_int;
    fn inflate(stream: *mut ZStream, flush: c_int) -> c_int;
    fn inflateEnd(stream: *mut ZStream) -> c_int;
}
fn reference_decode(source: &[u8], expected: &[u8], format: usize) {
    let mut target = vec![0; expected.len() + 1];
    let mut stream: ZStream = unsafe { std::mem::zeroed() };
    assert_eq!(
        unsafe {
            inflateInit2_(
                &mut stream,
                [-15, 15, 31][format],
                zlibVersion(),
                std::mem::size_of::<ZStream>() as c_int,
            )
        },
        0
    );
    stream.next_in = source.as_ptr();
    stream.avail_in = source.len().try_into().unwrap();
    stream.next_out = target.as_mut_ptr();
    stream.avail_out = target.len().try_into().unwrap();
    let status = unsafe { inflate(&mut stream, 4) };
    let read = stream.total_in as usize;
    let written = stream.total_out as usize;
    assert_eq!(unsafe { inflateEnd(&mut stream) }, 0);
    assert_eq!(
        status,
        1,
        "format={format}, prefix={:?}",
        &source[..source.len().min(32)]
    );
    assert_eq!(read, source.len(), "no trailing encoded bytes");
    assert_eq!(written, expected.len());
    assert_eq!(&target[..written], expected);
}

#[test]
fn streaming_deflate_exact_limits_bytewise_framing_and_strided_recycled_input_execute() {
    let expected: Vec<_> = WORKSPACE.into_iter().chain([32775]).collect();
    let (output, observed, compile, native) = execute("contracts.lani", &expected);
    let mut original = vec![65; 32768];
    original.push(66);
    reference_decode(&output, &original, 0);
    assert_eq!(observed.phases, 1);
    eprintln!(
        "streaming-deflate contracts formats=3 empty-output-limits=12 bytewise-streams=3 recycled-input-bytes=32769 exact-maps=4 exact-releases=4 native-seconds={:.6} compile-seconds={:.6}",
        native.as_secs_f64(),
        compile.as_secs_f64()
    );
}
fn number(bytes: &[u8], position: &mut usize) -> usize {
    let value = u32::from_le_bytes(bytes[*position..*position + 4].try_into().unwrap());
    *position += 4;
    value as usize
}
fn original(profile: usize, length: usize) -> Vec<u8> {
    if profile == 0 {
        return (0..length).map(|index| (index % 31) as u8).collect();
    }
    let mut state = 305_419_896u32;
    (0..length)
        .map(|_| {
            state ^= state << 13;
            state ^= state >> 17;
            state ^= state << 5;
            state as u8
        })
        .collect()
}

#[test]
fn streaming_deflate_large_profiles_recycle_fixed_owners_and_match_complete_independent_decode() {
    let expected: Vec<_> = WORKSPACE.into_iter().chain([4099, 8197]).collect();
    let (output, observed, compile, native) = execute("scale.lani", &expected);
    let mut position = 0;
    let mut input_bytes = 0;
    let mut encoded_bytes = 0;
    let mut shapes = vec![(0, 0, 32769), (0, 1, 32769)];
    for format in 0..3 {
        for profile in 0..2 {
            shapes.push((format, profile, 1048593));
        }
    }
    for (format, profile, length) in &shapes {
        assert_eq!(
            (
                number(&output, &mut position),
                number(&output, &mut position),
                number(&output, &mut position)
            ),
            (*format, *profile, *length)
        );
        let mut encoded = Vec::new();
        loop {
            let size = number(&output, &mut position);
            if size == 0 {
                break;
            }
            assert!(size <= 8193);
            encoded.extend_from_slice(&output[position..position + size]);
            position += size;
        }
        reference_decode(&encoded, &original(*profile, *length), *format);
        // Full blocks plus the mandatory final partial block use at most
        // five stored bytes each, followed by the selected container framing.
        let overhead = [0, 6, 18][*format];
        assert!(encoded.len() <= length + 5 * (length / 32768 + 1) + overhead);
        input_bytes += length;
        encoded_bytes += encoded.len();
    }
    assert_eq!(position, output.len());
    assert!(observed.phases > shapes.len());
    eprintln!(
        "streaming-deflate scale streams={} complete-input-bytes={input_bytes} encoded-bytes={encoded_bytes} fixed-owned-bytes={} pure-phases={} exact-maps=5 exact-releases=5 native-seconds={:.6} compile-seconds={:.6}",
        shapes.len(),
        expected.iter().sum::<usize>(),
        observed.phases,
        native.as_secs_f64(),
        compile.as_secs_f64()
    );
}
