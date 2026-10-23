#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, time::Duration};

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
    let exe = common::TempArtifact::new("laniusc_inflate", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

#[test]
fn inflate_contracts_execute_strided_offset_views_bounds_windows_and_partial_progress_without_heap()
{
    let exe = executable("tests/fixtures/extended/inflate_contracts.lani");
    let trace = common::TempArtifact::new("laniusc_inflate", "trace", None);
    let output = common::short_process_output_with_timeout(
        "inflate contracts",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,munmap",
                "-e",
                "inject=mmap:error=ENOMEM:when=1+",
            ])
            .arg(exe.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}

#[derive(Debug)]
struct Case {
    input: Vec<u8>,
    capacity: usize,
    window: i32,
}
#[derive(Debug)]
struct Outcome {
    code: i32,
    read: usize,
    bytes: Vec<u8>,
}
fn case(input: &[u8], capacity: usize) -> Case {
    Case {
        input: input.to_vec(),
        capacity,
        window: 32768,
    }
}
fn batch(cases: &[Case]) -> Vec<Outcome> {
    let exe = executable("tests/fixtures/extended/inflate_model.lani");
    let input = common::TempArtifact::new("laniusc_inflate", "input", None);
    let mut data = Vec::new();
    for case in cases {
        assert!(case.input.len() <= 262144 && case.capacity <= 262144);
        data.extend_from_slice(&(case.input.len() as i32).to_le_bytes());
        data.extend_from_slice(&(case.capacity as i32).to_le_bytes());
        data.extend_from_slice(&case.window.to_le_bytes());
        data.extend_from_slice(&case.input);
    }
    input.write_bytes(&data);
    let trace = common::TempArtifact::new("laniusc_inflate", "trace", None);
    let output = common::process_output_with_timeout(
        "inflate reference batch",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,munmap",
                "-e",
                "inject=mmap:error=ENOMEM:when=1+",
            ])
            .arg(exe.path())
            .stdin(std::fs::File::open(input.path()).unwrap()),
        Duration::from_secs(25),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
    let mut position = 0;
    let mut outcomes = Vec::new();
    for (index, case) in cases.iter().enumerate() {
        let header = output
            .stdout
            .get(position..position + 12)
            .unwrap_or_else(|| panic!("case{index}: missing header: {case:?}"));
        let code = i32::from_le_bytes(header[..4].try_into().unwrap());
        let read = i32::from_le_bytes(header[4..8].try_into().unwrap());
        let written = i32::from_le_bytes(header[8..12].try_into().unwrap());
        position += 12;
        assert!(
            read >= 0
                && read as usize <= case.input.len()
                && written >= 0
                && written as usize <= case.capacity,
            "case{index}: {case:?}"
        );
        let bytes = output
            .stdout
            .get(position..position + written as usize)
            .unwrap()
            .to_vec();
        position += written as usize;
        outcomes.push(Outcome {
            code,
            read: read as usize,
            bytes,
        });
    }
    assert_eq!(position, output.stdout.len());
    outcomes
}
fn python_corpus() -> Vec<(Vec<u8>, Vec<u8>)> {
    let script = r#"
import zlib,struct,sys,random
r=random.Random(0x1951)
sources=[b'',b'hello world',bytes(range(256)),b'a'*196608,(b'abcd\x00\xff'*20000),bytes(r.randrange(256) for _ in range(65536)),b'The quick brown fox jumps over the lazy dog. '*1000]
sources += [bytes(r.randrange(1+(i%31)) for _ in range(r.randrange(0,4096))) for i in range(48)]
for index,plain in enumerate(sources):
  for level,strategy in [(0,zlib.Z_DEFAULT_STRATEGY),(1,zlib.Z_DEFAULT_STRATEGY),(6,zlib.Z_DEFAULT_STRATEGY),(9,zlib.Z_FIXED),(6,zlib.Z_HUFFMAN_ONLY),(6,zlib.Z_RLE)]:
    c=zlib.compressobj(level,zlib.DEFLATED,-15,8,strategy)
    if index%3==0:
      middle=len(plain)//2
      encoded=c.compress(plain[:middle])+c.flush(zlib.Z_SYNC_FLUSH)+c.compress(plain[middle:])+c.flush()
    else: encoded=c.compress(plain)+c.flush()
    assert zlib.decompress(encoded,-15)==plain
    sys.stdout.buffer.write(struct.pack('<II',len(encoded),len(plain))+encoded+plain)
"#;
    let output = common::process_output_with_timeout(
        "Python zlib raw reference",
        Command::new("python3").args(["-c", script]),
        Duration::from_secs(15),
    );
    assert!(output.status.success(), "{output:?}");
    let mut position = 0;
    let mut result = Vec::new();
    while position < output.stdout.len() {
        let compressed =
            u32::from_le_bytes(output.stdout[position..position + 4].try_into().unwrap()) as usize;
        let plain = u32::from_le_bytes(
            output.stdout[position + 4..position + 8]
                .try_into()
                .unwrap(),
        ) as usize;
        position += 8;
        let bytes = output.stdout[position..position + compressed].to_vec();
        position += compressed;
        let source = output.stdout[position..position + plain].to_vec();
        position += plain;
        result.push((bytes, source));
    }
    result
}

#[test]
fn inflate_matches_zlib_for_stored_fixed_dynamic_binary_and_multiblock_corpus_and_capacity_prefixes()
 {
    let corpus = python_corpus();
    let mut cases = Vec::new();
    let mut expected = Vec::new();
    for (index, (compressed, plain)) in corpus.iter().enumerate() {
        let mut input = compressed.clone();
        input.extend_from_slice(&[0xaa, 0xbb, 0xcc]);
        cases.push(case(&input, plain.len()));
        expected.push((0, compressed.len(), plain.clone()));
        if !plain.is_empty() && index % 4 == 0 {
            for capacity in [0, plain.len() / 2, plain.len() - 1] {
                cases.push(case(&input, capacity));
                expected.push((8, usize::MAX, plain[..capacity].to_vec()));
            }
        }
    }
    let outcomes = batch(&cases);
    for (index, (actual, (code, read, bytes))) in outcomes.iter().zip(expected).enumerate() {
        assert_eq!(actual.code, code, "case{index}: {actual:?}");
        if read != usize::MAX {
            assert_eq!(actual.read, read, "case{index}");
        }
        assert_eq!(actual.bytes, bytes, "case{index}");
    }
}

#[derive(Default)]
struct Bits {
    bytes: Vec<u8>,
    used: u8,
}
impl Bits {
    fn bits(&mut self, value: u32, count: u32) {
        for bit in 0..count {
            if self.used == 0 {
                self.bytes.push(0);
            }
            let last = self.bytes.len() - 1;
            self.bytes[last] |= (((value >> bit) & 1) as u8) << self.used;
            self.used = (self.used + 1) % 8;
        }
    }
    fn code(&mut self, value: u32, count: u32) {
        for bit in (0..count).rev() {
            self.bits((value >> bit) & 1, 1);
        }
    }
    fn fixed(&mut self, symbol: u32) {
        match symbol {
            0..=143 => self.code(symbol + 48, 8),
            144..=255 => self.code(symbol - 144 + 400, 9),
            256..=279 => self.code(symbol - 256, 7),
            280..=287 => self.code(symbol - 280 + 192, 8),
            _ => panic!(),
        }
    }
    fn stored(&mut self, plain: &[u8], last: bool) {
        self.bits(last as u32, 1);
        self.bits(0, 2);
        while self.used != 0 {
            self.bits(0, 1);
        }
        let n = plain.len() as u16;
        assert!(plain.len() <= 65535);
        self.bytes.extend_from_slice(&n.to_le_bytes());
        self.bytes.extend_from_slice(&(!n).to_le_bytes());
        self.bytes.extend_from_slice(plain);
    }
    fn reference(&mut self, length: u32, distance: u32) {
        let bases = [
            3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99,
            115, 131, 163, 195, 227, 258,
        ];
        let mut symbol = 28;
        while bases[symbol] > length {
            symbol -= 1;
        }
        self.fixed(257 + symbol as u32);
        let extra = if symbol < 8 || symbol == 28 {
            0
        } else {
            (symbol as u32 - 4) / 4
        };
        self.bits(length - bases[symbol], extra);
        let mut ds = 0;
        while ds < 29 {
            let next = ds + 1;
            let e = if next < 4 { 0 } else { next / 2 - 1 };
            let base = if next < 4 {
                next + 1
            } else {
                ((2 + (next & 1)) << e) + 1
            };
            if base > distance {
                break;
            }
            ds = next;
        }
        self.code(ds, 5);
        let e = if ds < 4 { 0 } else { ds / 2 - 1 };
        let base = if ds < 4 {
            ds + 1
        } else {
            ((2 + (ds & 1)) << e) + 1
        };
        self.bits(distance - base, e);
    }
}
fn append_reference(plain: &mut Vec<u8>, length: usize, distance: usize) {
    for _ in 0..length {
        plain.push(plain[plain.len() - distance]);
    }
}

#[test]
fn inflate_accepts_every_legal_length_and_distance_including_32768_cross_block_history_and_overlap()
{
    let mut cases = Vec::new();
    let mut expected = Vec::new();
    let mut bits = Bits::default();
    let mut plain: Vec<u8> = (0..32768)
        .map(|i| ((i * 31 + i / 37) % 256) as u8)
        .collect();
    bits.stored(&plain, false);
    bits.bits(1, 1);
    bits.bits(1, 2);
    for distance in 1..=32768 {
        bits.reference(3, distance);
        append_reference(&mut plain, 3, distance as usize);
    }
    bits.fixed(256);
    cases.push(case(&bits.bytes, plain.len()));
    expected.push((0, bits.bytes.len(), plain));
    let mut bits = Bits::default();
    let mut plain = vec![0xff];
    bits.bits(1, 1);
    bits.bits(1, 2);
    bits.fixed(255);
    for length in 3..=258 {
        bits.reference(length, 1);
        append_reference(&mut plain, length as usize, 1);
    }
    // The alternate symbol 284 + 31 representation of length 258 is valid.
    bits.fixed(284);
    bits.bits(31, 5);
    bits.code(0, 5);
    append_reference(&mut plain, 258, 1);
    bits.fixed(256);
    cases.push(case(&bits.bytes, plain.len()));
    expected.push((0, bits.bytes.len(), plain));
    let seed: Vec<u8> = (0..512).map(|i| (i % 251) as u8).collect();
    let mut bits = Bits::default();
    bits.stored(&seed, false);
    bits.bits(1, 1);
    bits.bits(1, 2);
    bits.reference(258, 257);
    bits.fixed(256);
    let mut plain = seed.clone();
    append_reference(&mut plain, 258, 257);
    let mut limited = case(&bits.bytes, plain.len());
    limited.window = 256;
    cases.push(limited);
    expected.push((7, usize::MAX, seed));
    let mut larger = case(&bits.bytes, plain.len());
    larger.window = 512;
    cases.push(larger);
    expected.push((0, bits.bytes.len(), plain));
    for (index, (actual, (code, read, bytes))) in batch(&cases).iter().zip(expected).enumerate() {
        assert_eq!(actual.code, code, "case{index}");
        if read != usize::MAX {
            assert_eq!(actual.read, read);
        }
        assert_eq!(actual.bytes, bytes, "case{index}");
    }
}

// Describe a complete code-length alphabet {0,1,16,18}, all with length two.
fn dynamic_header(bits: &mut Bits, nlit: u32, ndist: u32) {
    bits.bits(1, 1);
    bits.bits(2, 2);
    bits.bits(nlit - 257, 5);
    bits.bits(ndist - 1, 5);
    bits.bits(14, 4);
    for i in [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1] {
        bits.bits(if [0, 1, 16, 18].contains(&i) { 2 } else { 0 }, 3);
    }
}
fn cl(bits: &mut Bits, symbol: u32) {
    bits.code(
        match symbol {
            0 => 0,
            1 => 1,
            16 => 2,
            18 => 3,
            _ => panic!(),
        },
        2,
    );
}
fn lengths(bits: &mut Bits, values: &[u32]) {
    for &value in values {
        cl(bits, value);
    }
}

fn canonical(lengths: &[u32], symbol: usize) -> (u32, u32) {
    let mut counts = [0u32; 16];
    for &length in lengths {
        if length != 0 {
            counts[length as usize] += 1;
        }
    }
    let mut first = [0u32; 16];
    for size in 1..=15 {
        first[size] = (first[size - 1] + counts[size - 1]) * 2;
    }
    let size = lengths[symbol];
    assert!(size != 0);
    let offset = lengths[..symbol].iter().filter(|&&n| n == size).count() as u32;
    (first[size as usize] + offset, size)
}
fn dynamic_direct(bits: &mut Bits, literals: &[u32], distances: &[u32]) {
    bits.bits(1, 1);
    bits.bits(2, 2);
    bits.bits(literals.len() as u32 - 257, 5);
    bits.bits(distances.len() as u32 - 1, 5);
    bits.bits(15, 4);
    for symbol in [
        16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
    ] {
        bits.bits(if symbol < 16 { 4 } else { 0 }, 3);
    }
    for &length in literals.iter().chain(distances) {
        bits.code(length, 4);
    }
}

#[test]
fn inflate_dynamic_extremes_repeat_boundaries_empty_history_and_incomplete_trees() {
    let mut cases = Vec::new();
    let mut expected = Vec::new();
    // A complete comb with maximum code length fifteen, including the EOB.
    let mut lit = vec![0; 257];
    for i in 0..14 {
        lit[i] = i as u32 + 1;
    }
    lit[65] = 15;
    lit[256] = 15;
    let mut b = Bits::default();
    dynamic_direct(&mut b, &lit, &[0]);
    let plain: Vec<u8> = (0..14).chain([65]).collect();
    for &symbol in &plain {
        let (code, size) = canonical(&lit, symbol as usize);
        b.code(code, size);
    }
    let (code, size) = canonical(&lit, 256);
    b.code(code, size);
    cases.push(case(&b.bytes, plain.len()));
    expected.push((0, Some(plain)));
    // A depth-fifteen distance tree referring across a stored block.
    let mut distances = vec![0; 30];
    for i in 0..14 {
        distances[i] = i as u32 + 1;
    }
    distances[28] = 15;
    distances[29] = 15;
    let mut lit = vec![0; 258];
    lit[256] = 1;
    lit[257] = 1;
    let mut b = Bits::default();
    let mut plain: Vec<u8> = (0..32768).map(|i| (i % 239) as u8).collect();
    b.stored(&plain, false);
    dynamic_direct(&mut b, &lit, &distances);
    b.code(1, 1);
    let (code, size) = canonical(&distances, 29);
    b.code(code, size);
    b.bits(8191, 13);
    b.code(0, 1);
    append_reference(&mut plain, 3, 32768);
    cases.push(case(&b.bytes, plain.len()));
    expected.push((0, Some(plain)));
    // Incomplete trees with two symbols at depth two, and singleton at depth
    // two, must both fail. Only a singleton at depth one is permitted.
    for two in [false, true] {
        let mut lit = vec![0; 257];
        lit[256] = 2;
        if two {
            lit[65] = 2;
        }
        let mut b = Bits::default();
        dynamic_direct(&mut b, &lit, &[0]);
        cases.push(case(&b.bytes, 100));
        expected.push((5, None));
        let mut lit = vec![0; 257];
        lit[256] = 1;
        let mut distances = vec![0; 2];
        distances[0] = 2;
        if two {
            distances[1] = 2;
        }
        let mut b = Bits::default();
        dynamic_direct(&mut b, &lit, &distances);
        cases.push(case(&b.bytes, 100));
        expected.push((5, None));
    }
    // Repeat16 of zero from the last literal entry through all three distance
    // entries. Repeat18 also reaches its maximum run of 138 zero lengths.
    let mut b = Bits::default();
    dynamic_header(&mut b, 258, 3);
    cl(&mut b, 18);
    b.bits(127, 7);
    cl(&mut b, 18);
    b.bits(107, 7);
    cl(&mut b, 1);
    cl(&mut b, 0);
    cl(&mut b, 16);
    b.bits(0, 2);
    b.bits(0, 1);
    cases.push(case(&b.bytes, 0));
    expected.push((0, Some(vec![])));
    // Alphabet {0,1,17,18} with two-bit codes; runs of 3 and 10 zeros.
    let mut b = Bits::default();
    b.bits(1, 1);
    b.bits(2, 2);
    b.bits(0, 5);
    b.bits(0, 5);
    b.bits(14, 4);
    for symbol in [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1] {
        b.bits(
            if [0, 1, 17, 18].contains(&symbol) {
                2
            } else {
                0
            },
            3,
        );
    }
    b.code(2, 2);
    b.bits(0, 3);
    b.code(2, 2);
    b.bits(7, 3);
    b.code(3, 2);
    b.bits(127, 7);
    b.code(3, 2);
    b.bits(94, 7);
    b.code(1, 2);
    b.code(0, 2);
    b.bits(0, 1);
    cases.push(case(&b.bytes, 0));
    expected.push((0, Some(vec![])));
    // One-bit singleton distance alphabet: the unused bit is an invalid code.
    let mut lit = vec![0; 258];
    lit[256] = 1;
    lit[257] = 1;
    let mut b = Bits::default();
    b.stored(b"a", false);
    dynamic_direct(&mut b, &lit, &[1]);
    b.bits(1, 1);
    b.bits(1, 1);
    cases.push(case(&b.bytes, 10));
    expected.push((6, Some(b"a".to_vec())));
    for (index, (actual, (code, bytes))) in batch(&cases).iter().zip(expected).enumerate() {
        assert_eq!(actual.code, code, "case{index}: {actual:?}");
        if let Some(bytes) = bytes {
            assert_eq!(actual.bytes, bytes, "case{index}");
        }
    }
}

#[test]
fn inflate_rejects_malformed_blocks_trees_repeats_reserved_symbols_distances_and_all_truncated_prefixes()
 {
    let mut cases = Vec::new();
    let mut expected = Vec::new();
    for (input, code) in [
        (vec![], 2),
        (vec![7], 3),
        (vec![1, 1, 0, 0, 0], 4),
        (vec![1, 0, 0, 255, 255], 0),
    ] {
        cases.push(case(&input, 100));
        expected.push((code, None));
    }
    // Code-length trees: empty, oversubscribed, incomplete multi-symbol.
    for lens in [[0, 0, 0, 0], [1, 1, 1, 0], [2, 2, 0, 0]] {
        let mut b = Bits::default();
        b.bits(1, 1);
        b.bits(2, 2);
        b.bits(0, 5);
        b.bits(0, 5);
        b.bits(0, 4);
        for n in lens {
            b.bits(n, 3);
        }
        cases.push(case(&b.bytes, 100));
        expected.push((5, None));
    }
    let mut b = Bits::default();
    dynamic_header(&mut b, 257, 1);
    cl(&mut b, 16);
    b.bits(0, 2);
    cases.push(case(&b.bytes, 100));
    expected.push((5, None));
    let mut b = Bits::default();
    dynamic_header(&mut b, 257, 1);
    cl(&mut b, 18);
    b.bits(127, 7);
    cl(&mut b, 18);
    b.bits(127, 7);
    cases.push(case(&b.bytes, 100));
    expected.push((5, None));
    for mode in 0..6 {
        let mut b = Bits::default();
        dynamic_header(&mut b, 258, 1);
        let mut v = vec![0; 259];
        match mode {
            0 => {
                v[65] = 1;
            } // missing end marker
            1 => {
                v[65] = 1;
                v[66] = 1;
                v[256] = 1;
            } // oversubscribed literal tree
            2 => {
                v[65] = 1;
                v[256] = 1;
                v[258] = 1;
            } // valid one-bit literal/distance trees
            3 => {
                v[256] = 1;
            } // permitted singleton EOB and empty distance
            4 => {
                v[65] = 1;
                v[256] = 1;
                v[257] = 1;
            }
            _ => {
                v[256] = 1;
                v[257] = 1;
            } // length with an empty distance alphabet
        }
        lengths(&mut b, &v);
        if mode == 2 {
            b.bits(0, 1);
            b.bits(1, 1);
        } else if mode == 3 {
            b.bits(0, 1);
        } else if mode == 5 {
            b.bits(1, 1);
        }
        cases.push(case(&b.bytes, 100));
        expected.push((
            if mode == 2 || mode == 3 {
                0
            } else if mode == 5 {
                6
            } else {
                5
            },
            if mode == 2 { Some(vec![65]) } else { None },
        ));
    }
    // Singleton EOB with unused distance descriptors through HDIST=32.
    let mut b = Bits::default();
    dynamic_header(&mut b, 257, 32);
    let mut v = vec![0; 289];
    v[256] = 1;
    lengths(&mut b, &v);
    b.bits(0, 1);
    cases.push(case(&b.bytes, 0));
    expected.push((0, Some(vec![])));
    for symbol in [286, 287] {
        let mut b = Bits::default();
        b.bits(1, 1);
        b.bits(1, 2);
        b.fixed(symbol);
        cases.push(case(&b.bytes, 100));
        expected.push((6, None));
    }
    for distance_symbol in [30, 31] {
        let mut b = Bits::default();
        b.bits(1, 1);
        b.bits(1, 2);
        b.fixed(65);
        b.fixed(257);
        b.code(distance_symbol, 5);
        cases.push(case(&b.bytes, 100));
        expected.push((6, Some(vec![65])));
    }
    let mut b = Bits::default();
    b.bits(1, 1);
    b.bits(1, 2);
    b.reference(3, 1);
    cases.push(case(&b.bytes, 100));
    expected.push((7, None));
    // Dynamic HLIT cannot encode 287 or 288 symbols.
    for count in [30, 31] {
        let mut b = Bits::default();
        b.bits(1, 1);
        b.bits(2, 2);
        b.bits(count, 5);
        b.bits(0, 5);
        b.bits(0, 4);
        cases.push(case(&b.bytes, 100));
        expected.push((5, None));
    }
    let corpus = python_corpus();
    for (compressed, plain) in corpus
        .iter()
        .filter(|(c, _)| c.len() > 4 && c.len() < 180)
        .take(18)
    {
        for count in 0..compressed.len() {
            cases.push(case(&compressed[..count], plain.len() + 1));
            expected.push((2, None));
        }
    }
    for (index, (actual, (code, bytes))) in batch(&cases).iter().zip(expected).enumerate() {
        assert_eq!(
            actual.code, code,
            "case{index},input{:02x?}: {actual:?}",
            cases[index].input
        );
        if let Some(bytes) = bytes {
            assert_eq!(actual.bytes, bytes, "case{index}");
        }
    }
}
