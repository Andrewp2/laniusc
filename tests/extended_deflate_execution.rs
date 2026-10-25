#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeSet,
    ffi::{c_char, c_int, c_uint, c_ulong, c_void},
    os::unix::fs::PermissionsExt,
    process::Command,
    sync::OnceLock,
    time::{Duration, Instant},
};

fn executable(path: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    let result = common::TempArtifact::new("laniusc_deflate", "executable", None);
    result.write_bytes(bytes);
    std::fs::set_permissions(result.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    result
}
fn batch_exe() -> &'static common::TempArtifact {
    static BATCH: OnceLock<common::TempArtifact> = OnceLock::new();
    BATCH.get_or_init(|| executable("tests/fixtures/extended/deflate_batch.lani"))
}
fn encoded(cases: &[Vec<u8>], trace: bool) -> Vec<Vec<u8>> {
    encoded_mode(cases, trace, false)
}
fn encoded_mode(cases: &[Vec<u8>], trace: bool, encode_only: bool) -> Vec<Vec<u8>> {
    let packet = common::TempArtifact::new("laniusc_deflate", "input", None);
    let mut bytes = Vec::new();
    for case in cases {
        assert!(case.len() <= 524288);
        bytes.extend_from_slice(&(case.len() as u32).to_le_bytes());
        bytes.extend_from_slice(case);
    }
    packet.write_bytes(&bytes);
    let trace_file = common::TempArtifact::new("laniusc_deflate", "allocation_trace", None);
    let mut command = if trace {
        let mut command = Command::new("strace");
        command.args(["-qq", "-o"]).arg(trace_file.path()).args([
            "-e",
            "trace=mmap,munmap,brk",
            "-e",
            "inject=mmap:error=ENOMEM:when=1+",
        ]);
        command.arg(batch_exe().path());
        command
    } else {
        Command::new(batch_exe().path())
    };
    if encode_only {
        command.arg("encode-only");
    }
    let result = common::process_output_with_timeout(
        "deflate native batch",
        command.stdin(std::fs::File::open(packet.path()).unwrap()),
        Duration::from_secs(20),
    );
    assert_eq!(result.status.code(), Some(0), "{result:?}");
    assert!(result.stderr.is_empty(), "{result:?}");
    if trace {
        assert!(
            std::fs::read_to_string(trace_file.path())
                .unwrap()
                .is_empty()
        );
    }
    let mut remaining = result.stdout.as_slice();
    let mut records = Vec::new();
    while !remaining.is_empty() {
        assert!(remaining.len() >= 4);
        let count = u32::from_le_bytes(remaining[..4].try_into().unwrap()) as usize;
        assert!(count <= remaining.len() - 4);
        records.push(remaining[4..4 + count].to_vec());
        remaining = &remaining[4 + count..];
    }
    assert_eq!(records.len(), cases.len());
    records
}

// zlib is a test oracle only. Production code imports no foreign codec.
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
fn reference_decode(source: &[u8], expected: &[u8]) {
    let mut target = vec![0; expected.len() + 1];
    let mut stream: ZStream = unsafe { std::mem::zeroed() };
    let init = unsafe {
        inflateInit2_(
            &mut stream,
            -15,
            zlibVersion(),
            std::mem::size_of::<ZStream>() as c_int,
        )
    };
    assert_eq!(init, 0);
    stream.next_in = source.as_ptr();
    stream.avail_in = source.len() as c_uint;
    stream.next_out = target.as_mut_ptr();
    stream.avail_out = target.len() as c_uint;
    let status = unsafe { inflate(&mut stream, 4) };
    let total_in = stream.total_in;
    let total_out = stream.total_out;
    assert_eq!(unsafe { inflateEnd(&mut stream) }, 0);
    assert_eq!(
        status,
        1,
        "encoded prefix={:?}",
        &source[..source.len().min(32)]
    );
    assert_eq!(total_in as usize, source.len());
    assert_eq!(total_out as usize, expected.len());
    assert_eq!(&target[..expected.len()], expected);
}

#[test]
fn contracts_execute_strides_offsets_guards_bounds_and_atomic_capacity_failures_without_allocation()
{
    let exe = executable("tests/fixtures/extended/deflate_contracts.lani");
    let trace = common::TempArtifact::new("laniusc_deflate", "contracts_trace", None);
    let output = common::process_output_with_timeout(
        "deflate contracts",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,munmap,brk,open,openat,socket,connect",
                "-e",
                "inject=mmap:error=ENOMEM:when=1+",
            ])
            .arg(exe.path()),
        Duration::from_secs(5),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}

fn next(state: &mut u64) -> u64 {
    *state ^= *state << 13;
    *state ^= *state >> 7;
    *state ^= *state << 17;
    *state
}
fn random(count: usize, state: &mut u64) -> Vec<u8> {
    (0..count).map(|_| next(state) as u8).collect()
}
#[test]
fn generated_binary_text_periodic_and_incompressible_inputs_round_trip_through_zlib() {
    let mut cases = vec![vec![], b"hello".to_vec(), b"abcabcabc".to_vec()];
    cases.extend((0..=255).map(|byte| vec![byte]));
    cases.push((0..=255).cycle().take(8192).collect());
    let mut state = 0xfedc_ba98_7654_3210;
    for index in 0..384 {
        let length = next(&mut state) as usize % 8193;
        let value = match index % 6 {
            0 => random(length, &mut state),
            1 => vec![(index & 255) as u8; length],
            2 => {
                let period = 1 + next(&mut state) as usize % 513;
                random(period, &mut state)
                    .into_iter()
                    .cycle()
                    .take(length)
                    .collect()
            }
            3 => b"entry=12345\tstatus=ok\n"
                .iter()
                .copied()
                .cycle()
                .take(length)
                .collect(),
            4 => (0..length).map(|_| (next(&mut state) % 8) as u8).collect(),
            _ => {
                let mut result = random(length, &mut state);
                let start = length / 3;
                for byte in &mut result[start..length * 2 / 3] {
                    *byte = 0;
                }
                result
            }
        };
        cases.push(value);
    }
    let mut endings = BTreeSet::new();
    for (index, (input, output)) in cases.iter().zip(encoded(&cases, false)).enumerate() {
        reference_decode(&output, input);
        endings.insert(shape(&output).used_bits % 8);
        let bound = input.len() + 5 * input.len().div_ceil(65535).max(1);
        assert!(
            output.len() <= bound,
            "case {index}: {} -> {}",
            input.len(),
            output.len()
        );
    }
    assert_eq!(endings, (0..8).collect());
}

struct Bits<'a> {
    bytes: &'a [u8],
    position: usize,
}
impl Bits<'_> {
    fn take(&mut self, count: usize) -> usize {
        let mut result = 0;
        for shift in 0..count {
            assert!(self.position / 8 < self.bytes.len());
            result |=
                (((self.bytes[self.position / 8] >> (self.position % 8)) & 1) as usize) << shift;
            self.position += 1;
        }
        result
    }
    fn symbol(&mut self) -> usize {
        let mut code = 0;
        for width in 1..=9 {
            code = (code << 1) | self.take(1);
            match width {
                7 if code <= 23 => return 256 + code,
                8 if (48..=191).contains(&code) => return code - 48,
                8 if (192..=199).contains(&code) => return code + 88,
                9 if (400..=511).contains(&code) => return code - 256,
                _ => (),
            }
        }
        panic!("invalid fixed symbol");
    }
}
#[derive(Default)]
struct Shape {
    literals: BTreeSet<usize>,
    lengths: BTreeSet<usize>,
    distances: BTreeSet<usize>,
    stored: Vec<usize>,
    used_bits: usize,
}
fn shape(bytes: &[u8]) -> Shape {
    let mut reader = Bits { bytes, position: 0 };
    let mut result = Shape::default();
    let length_base = [
        3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115,
        131, 163, 195, 227, 258,
    ];
    let length_extra = [
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
    ];
    let distance_base = [
        1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537,
        2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
    ];
    let distance_extra = [
        0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12,
        13, 13,
    ];
    loop {
        let final_block = reader.take(1) == 1;
        match reader.take(2) {
            0 => {
                reader.position = reader.position.div_ceil(8) * 8;
                let count = reader.take(16);
                let complement = reader.take(16);
                assert_eq!(count ^ complement, 65535);
                result.stored.push(count);
                reader.position += count * 8;
            }
            1 => loop {
                let symbol = reader.symbol();
                match symbol {
                    0..=255 => {
                        result.literals.insert(symbol);
                    }
                    256 => break,
                    257..=285 => {
                        let length =
                            length_base[symbol - 257] + reader.take(length_extra[symbol - 257]);
                        result.lengths.insert(length);
                        let code = reader.take(5).reverse_bits() >> (usize::BITS - 5);
                        assert!(code < 30);
                        let distance = distance_base[code] + reader.take(distance_extra[code]);
                        result.distances.insert(distance);
                    }
                    _ => panic!("reserved length code"),
                }
            },
            _ => panic!("encoder emitted unexpected block type"),
        }
        if final_block {
            break;
        }
    }
    assert_eq!(reader.position.div_ceil(8), bytes.len());
    result.used_bits = reader.position;
    if reader.position % 8 != 0 {
        assert_eq!(bytes[bytes.len() - 1] >> (reader.position % 8), 0);
    }
    result
}
fn hash(bytes: &[u8], at: usize) -> usize {
    ((bytes[at] as usize * 251 + bytes[at + 1] as usize) * 251 + bytes[at + 2] as usize) & 32767
}
fn distance_input(distance: usize) -> Vec<u8> {
    // Ensure the deliberately selected prefix has survived the encoder's
    // one-entry hash policy. Other triplets remain unconstrained random data.
    for seed in 1..10000 {
        let mut state = seed;
        let prefix = random(distance, &mut state);
        let result: Vec<_> = prefix
            .iter()
            .copied()
            .cycle()
            .take(distance + 8192)
            .collect();
        let wanted = hash(&result, 0);
        if (1..distance).all(|index| hash(&result, index) != wanted) {
            return result;
        }
    }
    panic!("could not generate distance {distance}");
}
#[test]
fn every_match_length_literal_byte_and_distance_code_boundary_uses_real_backreferences() {
    let mut cases: Vec<_> = (3..=258).map(|length| vec![97; length + 1]).collect();
    cases.push((0..=255).cycle().take(8192).collect());
    let mut distances: BTreeSet<usize> = (1..=4).collect();
    for power in 1..=13 {
        for value in [1 << power, (1 << power) + (1 << (power - 1))] {
            for adjustment in [0, 1] {
                if value + adjustment <= 32768 {
                    distances.insert(value + adjustment);
                }
            }
        }
    }
    distances.extend([24577, 32767, 32768]);
    cases.extend(distances.iter().copied().map(distance_input));
    let outputs = encoded_mode(&cases, false, true);
    assert_eq!(outputs.len(), cases.len());
    for (length, (input, output)) in (3..=258).zip(cases.iter().zip(&outputs)) {
        reference_decode(output, input);
        assert!(
            shape(output).lengths.contains(&length),
            "length {length}: {output:?}"
        );
    }
    let literals = shape(&outputs[256]);
    assert_eq!(literals.literals, (0..=255).collect());
    for (distance, (input, output)) in distances
        .iter()
        .zip(cases[257..].iter().zip(&outputs[257..]))
    {
        reference_decode(output, input);
        let info = shape(output);
        assert!(
            info.distances.contains(distance),
            "wanted {distance}, got {:?}",
            info.distances
        );
    }
}

#[test]
fn incompressible_inputs_choose_stored_blocks_at_65535_boundaries_and_repetitions_shrink() {
    let mut state = 0x0123_4567_89ab_cdef;
    let mut cases: Vec<_> = [65534, 65535, 65536, 131070, 131071, 524288]
        .into_iter()
        .map(|count| random(count, &mut state))
        .collect();
    cases.push(vec![0; 524288]);
    cases.push(
        b"record=abcdef0123456789\tstatus=200\n"
            .iter()
            .copied()
            .cycle()
            .take(524288)
            .collect(),
    );
    let outputs = encoded(&cases, false);
    for (index, (input, output)) in cases.iter().zip(&outputs).enumerate() {
        reference_decode(output, input);
        let info = shape(output);
        if index < 6 {
            assert_eq!(output.len(), input.len() + 5 * input.len().div_ceil(65535));
            let mut sizes = vec![65535; input.len() / 65535];
            if input.len() % 65535 != 0 {
                sizes.push(input.len() % 65535);
            }
            assert_eq!(info.stored, sizes);
        } else {
            assert!(
                output.len() < input.len() / 50,
                "{} -> {}",
                input.len(),
                output.len()
            );
            assert!(!info.distances.is_empty());
        }
    }
}

#[test]
fn binary_encoding_has_no_allocation_and_reuses_arbitrary_prior_scratch() {
    let mut state = 0x8796_abcd_ef01_2345;
    let cases = vec![
        vec![],
        vec![0; 8192],
        random(65536, &mut state),
        (0..=255).cycle().take(131072).collect(),
    ];
    for (input, output) in cases.iter().zip(encoded(&cases, true)) {
        reference_decode(&output, input);
    }
}

#[test]
fn larger_native_inputs_execute_with_documented_compression_and_bounded_work() {
    let mut state = 0x1234_abcd_8765_fedc;
    let cases = vec![
        random(524288, &mut state),
        vec![120; 524288],
        b"data=123456789\tstatus=success\n"
            .iter()
            .copied()
            .cycle()
            .take(524288)
            .collect(),
    ];
    // Warm compiler initialization before recording native execution only.
    batch_exe();
    let start = Instant::now();
    let outputs = encoded_mode(&cases, false, true);
    eprintln!(
        "three native 512 KiB cases (encode only): {:.3} ms; sizes {:?}",
        start.elapsed().as_secs_f64() * 1000.0,
        outputs.iter().map(Vec::len).collect::<Vec<_>>()
    );
    for (input, output) in cases.iter().zip(outputs) {
        reference_decode(&output, input);
    }
}
