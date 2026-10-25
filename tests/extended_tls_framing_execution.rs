//! Incremental wire framing against an independent stream model; no TLS policy.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    os::unix::fs::PermissionsExt,
    process::{Command, Stdio},
    sync::OnceLock,
    time::Duration,
};

fn compile(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/extended/tls_framing").join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("TLS incremental framing", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("TLS framing {name}: {error}"));
    let exe = common::TempArtifact::new("laniusc_tls_framing", "fixture", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn protocol() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile("protocol.lani"))
}
fn checked(output: &std::process::Output) {
    assert_eq!(
        output.status.code(),
        Some(0),
        "stdoutlen={}, prefix={:?}, stderr={:?}",
        output.stdout.len(),
        &output.stdout[..output.stdout.len().min(32)],
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "{:?}",
        String::from_utf8_lossy(&output.stderr)
    );
}
fn run(exe: &common::TempArtifact, input: &[u8], label: &str) -> (Vec<u8>, String) {
    let source = common::TempArtifact::new("laniusc_tls_framing", "input", None);
    source.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_tls_framing", "memory", None);
    let output = common::process_output_with_timeout(
        label,
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,mremap,brk"])
            .arg(exe.path())
            .stdin(Stdio::from(std::fs::File::open(source.path()).unwrap())),
        Duration::from_secs(30),
    );
    checked(&output);
    (
        output.stdout,
        std::fs::read_to_string(trace.path()).unwrap(),
    )
}
fn word(bytes: &[u8], at: &mut usize) -> u64 {
    assert!(*at + 8 <= bytes.len(), "truncated response at {at}");
    let value = u64::from_le_bytes(bytes[*at..*at + 8].try_into().unwrap());
    *at += 8;
    value
}
#[derive(Clone, Debug)]
struct Action {
    op: u64,
    bad: u64,
    bytes: Vec<u8>,
}
fn feed(bytes: impl AsRef<[u8]>) -> Action {
    Action {
        op: 0,
        bad: 0,
        bytes: bytes.as_ref().to_vec(),
    }
}
fn op(op: u64) -> Action {
    Action {
        op,
        bad: 0,
        bytes: Vec::new(),
    }
}
#[derive(Clone, Debug)]
struct Case {
    handshake: bool,
    layout: u64,
    maximum: i32,
    capacity: usize,
    bad: u64,
    actions: Vec<Action>,
}
fn case(handshake: bool, maximum: i32, actions: Vec<Action>) -> Case {
    Case {
        handshake,
        layout: 0,
        maximum,
        capacity: (if handshake { 4 } else { 5 }) + maximum as usize,
        bad: 0,
        actions,
    }
}
fn header(handshake: bool) -> usize {
    if handshake { 4 } else { 5 }
}
fn wire(handshake: bool, length: usize, salt: u8) -> Vec<u8> {
    let mut bytes = if handshake {
        vec![253, (length >> 16) as u8, (length >> 8) as u8, length as u8]
    } else {
        // Framing retains even unknown types and nonstandard legacy versions.
        vec![254, 0x91, 0x07, (length >> 8) as u8, length as u8]
    };
    bytes.extend((0..length).map(|index| (index as u8).wrapping_mul(73).wrapping_add(salt)));
    bytes
}
#[derive(Default)]
struct Stream {
    prefix: Vec<u8>,
    storage: Vec<u8>,
    complete: bool,
    poisoned: bool,
}
impl Stream {
    fn action(&mut self, case: &Case, action: &Action) -> (u64, usize) {
        match action.op {
            0 | 5 => {
                // Model one stream prefix, independently of the decoder's internal
                // header/body copy loops. Derive the next boundary from concatenation.
                if action.bad != 0 {
                    return (1, 0);
                }
                if self.poisoned {
                    return (7, 0);
                }
                if self.complete {
                    return (4, 0);
                }
                let old = self.prefix.len();
                let mut candidate = self.prefix.clone();
                candidate.extend(&action.bytes);
                let h = header(case.handshake);
                let (end, oversized) = if candidate.len() < h {
                    (candidate.len(), false)
                } else {
                    let length_start = if case.handshake { 1 } else { 3 };
                    let announced = candidate[length_start..h]
                        .iter()
                        .fold(0usize, |n, &byte| (n << 8) | byte as usize);
                    if announced > case.maximum as usize {
                        (h, true)
                    } else {
                        (candidate.len().min(h + announced), false)
                    }
                };
                self.prefix = candidate[..end].to_vec();
                self.storage[old..end].copy_from_slice(&self.prefix[old..end]);
                self.poisoned = oversized;
                if !oversized && end >= h {
                    let length_start = if case.handshake { 1 } else { 3 };
                    let announced = self.prefix[length_start..h]
                        .iter()
                        .fold(0usize, |n, &byte| (n << 8) | byte as usize);
                    self.complete = end == h + announced;
                }
                (if oversized { 6 } else { 0 }, end - old)
            }
            1 | 4 => (
                if self.poisoned {
                    7
                } else if !self.complete {
                    5
                } else {
                    0
                },
                0,
            ),
            2 => {
                if self.poisoned {
                    (7, 0)
                } else if !self.complete {
                    (5, 0)
                } else {
                    let n = self.prefix.len();
                    self.prefix.clear();
                    self.complete = false;
                    (0, n)
                }
            }
            3 => {
                let n = self.prefix.len();
                self.prefix.clear();
                self.complete = false;
                self.poisoned = false;
                (0, n)
            }
            _ => unreachable!(),
        }
    }
}
fn compare(mut cases: Vec<Case>, label: &str) {
    // Every logical case is exercised over independently backed strided and packed storage.
    let logical = cases.len();
    cases = cases
        .into_iter()
        .flat_map(|case| {
            [
                Case {
                    layout: 0,
                    ..case.clone()
                },
                Case { layout: 1, ..case },
            ]
        })
        .collect();
    let mut input = (cases.len() as u64).to_le_bytes().to_vec();
    for case in &cases {
        for n in [
            case.handshake as u64,
            case.layout,
            case.maximum as i64 as u64,
            case.capacity as u64,
            case.bad,
            case.actions.len() as u64,
        ] {
            input.extend(n.to_le_bytes());
        }
        for action in &case.actions {
            for n in [action.op, action.bad, action.bytes.len() as u64] {
                input.extend(n.to_le_bytes());
            }
            input.extend(&action.bytes);
        }
    }
    let (output, trace) = run(protocol(), &input, label);
    assert!(
        trace.is_empty(),
        "caller-backed framing must allocate nothing: {trace}"
    );
    let mut at = 0;
    let mut actions = 0;
    for (number, case) in cases.iter().enumerate() {
        let stride = word(&output, &mut at);
        assert_eq!(
            word(&output, &mut at),
            stride,
            "case {number}: input/storage layout"
        );
        if case.layout == 1 {
            assert_eq!(stride, 1);
        } else {
            assert!(stride > 1);
        }
        let domain = if case.handshake { 16777215 } else { 65535 };
        let constructor = if case.bad != 0 {
            1
        } else if !(0..=domain).contains(&case.maximum) {
            2
        } else if case.capacity < header(case.handshake) + case.maximum as usize {
            3
        } else {
            0
        };
        assert_eq!(
            word(&output, &mut at),
            constructor,
            "case {number}: constructor {case:?}"
        );
        if constructor != 0 {
            assert!(case.actions.is_empty());
            continue;
        }
        let mut model = Stream {
            storage: vec![222; case.capacity],
            ..Stream::default()
        };
        for (turn, action) in case.actions.iter().enumerate() {
            let (status, consumed) = model.action(case, action);
            let fields = [
                action.op,
                status,
                consumed as u64,
                model.prefix.len() as u64,
                model.complete as u64,
                model.poisoned as u64,
                if model.complete {
                    model.prefix[0] as u64
                } else {
                    0
                },
                if model.complete && !case.handshake {
                    u16::from_be_bytes([model.prefix[1], model.prefix[2]]) as u64
                } else {
                    0
                },
                if model.complete {
                    model.prefix.len() as u64
                } else {
                    0
                },
                if model.complete {
                    (model.prefix.len() - header(case.handshake)) as u64
                } else {
                    0
                },
            ];
            for (field, expected) in fields.into_iter().enumerate() {
                assert_eq!(
                    word(&output, &mut at),
                    expected,
                    "case {number} turn {turn} field {field}, op={} bad={} offered={}",
                    action.op,
                    action.bad,
                    action.bytes.len()
                );
            }
            if model.complete {
                assert_eq!(
                    &output[at..at + model.prefix.len()],
                    model.prefix,
                    "case {number} turn {turn}: borrowed complete wire"
                );
                at += model.prefix.len();
            }
            assert_eq!(
                &output[at..at + case.capacity],
                model.storage,
                "case {number} turn {turn}: storage incl untouched tail"
            );
            at += case.capacity;
            assert_eq!(
                &output[at..at + action.bytes.len()],
                action.bytes,
                "case {number} turn {turn}: input immutable"
            );
            at += action.bytes.len();
            actions += 1;
        }
    }
    assert_eq!(at, output.len(), "no trailing protocol bytes");
    eprintln!(
        "{label}: {logical} logical cases / {} layouts, {actions} actions",
        cases.len()
    );
}

#[test]
fn incremental_record_and_handshake_streams_match_independent_model() {
    let mut cases = Vec::new();
    for handshake in [false, true] {
        for length in [0usize, 1, 2, 15, 16, 17, 255, 256, 4096] {
            let bytes = wire(handshake, length, 19);
            // All single splits of short frames; representative header/body/end cuts for larger ones.
            let cuts: Vec<_> = if length <= 17 {
                (0..=bytes.len()).collect()
            } else {
                vec![
                    0,
                    1,
                    header(handshake) - 1,
                    header(handshake),
                    header(handshake) + 1,
                    bytes.len() - 1,
                    bytes.len(),
                ]
            };
            for cut in cuts {
                cases.push(case(
                    handshake,
                    length as i32,
                    vec![
                        op(1),
                        feed(&bytes[..cut]),
                        op(4),
                        feed(&bytes[cut..]),
                        op(1),
                        feed([]),
                        op(4),
                        op(2),
                        op(1),
                        op(3),
                    ],
                ));
            }
            // One byte at a time including empty feeds between every header byte.
            if length <= 17 {
                let mut actions = vec![feed([])];
                for byte in &bytes {
                    actions.push(feed([*byte]));
                    actions.push(feed([]));
                    actions.push(op(4));
                }
                actions.extend([op(2), op(3)]);
                cases.push(case(handshake, length as i32, actions));
            }
        }
        // Coalesced frames: retain the unconsumed suffix and offer it after consume.
        let first = wire(handshake, 0, 1);
        let second = wire(handshake, 17, 2);
        let third = wire(handshake, 1, 3);
        let joined = [first.clone(), second.clone(), third.clone()].concat();
        cases.push(case(
            handshake,
            17,
            vec![
                feed(&joined),
                op(4),
                op(2),
                feed([second.clone(), third.clone()].concat()),
                op(2),
                feed(third),
                op(2),
            ],
        ));
        // Exact record wire maximum and a larger configured handshake body, in real backing.
        let length = if handshake { 65536 } else { 65535 };
        let bytes = wire(handshake, length, 97);
        let mut actions = Vec::new();
        for chunk in bytes.chunks(4093) {
            actions.push(feed(chunk));
            actions.push(op(4));
        }
        actions.extend([op(1), op(2), op(3)]);
        cases.push(case(handshake, length as i32, actions));
        // Repeated deterministic partition/coalescing schedules, independent of the decoder.
        for seed in 1..=8u64 {
            let frames: Vec<_> = (0..9)
                .map(|i| wire(handshake, (i * 7 + seed as usize) % 32, i as u8))
                .collect();
            let stream = frames.concat();
            let mut pos = 0;
            let mut end = 0;
            let mut state = seed;
            let mut actions = Vec::new();
            for frame in frames {
                end += frame.len();
                while pos < end {
                    state ^= state << 13;
                    state ^= state >> 7;
                    state ^= state << 17;
                    let offered = (state as usize % 23 + 1).min(stream.len() - pos);
                    actions.push(feed(&stream[pos..pos + offered]));
                    pos = (pos + offered).min(end);
                    actions.push(op(4));
                }
                actions.push(op(2));
            }
            cases.push(case(handshake, 31, actions));
        }
    }
    compare(cases, "TLS framing stream partitions");
}

#[test]
fn framing_error_priority_backpressure_and_alias_handoff_match_model() {
    let mut cases = Vec::new();
    for handshake in [false, true] {
        let h = header(handshake);
        for maximum in [-1, i32::MAX, if handshake { 16777216 } else { 65536 }] {
            cases.push(Case {
                maximum,
                capacity: h,
                bad: 0,
                actions: vec![],
                ..case(handshake, 0, vec![])
            });
        }
        for capacity in [0, h - 1, h, h + 7] {
            cases.push(Case {
                capacity,
                actions: vec![],
                ..case(handshake, 8, vec![])
            });
        }
        // Wire-domain-valid limit but insufficient actual physical storage.
        cases.push(Case {
            capacity: 65540,
            maximum: if handshake { 16777215 } else { 65535 },
            actions: if handshake { vec![] } else { vec![op(1)] },
            ..case(handshake, 0, vec![])
        });
        for bad in 1..=3 {
            cases.push(Case {
                bad,
                maximum: -1,
                capacity: 0,
                actions: vec![],
                ..case(handshake, 0, vec![])
            });
        }
        let bytes = wire(handshake, 3, 43);
        for cut in 0..h {
            let mut actions = vec![feed(&bytes[..cut]), op(1), op(2)];
            for bad in 1..=3 {
                actions.push(Action {
                    bad,
                    ..feed([9, 8, 7])
                });
            }
            actions.extend([op(4), op(3), feed(&bytes), op(4)]);
            for bad in 1..=3 {
                actions.push(Action { bad, ..feed([]) });
            }
            actions.extend([feed([1, 2, 3]), feed([]), op(4), op(2), op(3)]);
            cases.push(case(handshake, 3, actions));
        }
        // Oversize announced length rejects exactly at the header boundary, even
        // when the same feed also offers body and subsequent frame bytes.
        let oversized = wire(handshake, 4, 12);
        for cut in 0..h {
            let mut actions = vec![
                feed(&oversized[..cut]),
                feed(&oversized[cut..]),
                op(1),
                op(2),
                feed([]),
            ];
            for bad in 1..=3 {
                actions.push(Action { bad, ..feed([1]) });
            }
            actions.extend([op(4), op(3), feed(&bytes), op(2)]);
            cases.push(case(handshake, 3, actions));
        }
        // Copy metadata while partial, then retire the old writable authority.
        let mut actions = vec![
            feed(&bytes[..h - 1]),
            op(4),
            Action {
                op: 5,
                ..feed(&bytes[h - 1..])
            },
            op(4),
            op(2),
            op(3),
        ];
        actions.extend([
            Action {
                op: 5,
                ..feed(&bytes)
            },
            op(4),
            op(2),
        ]);
        cases.push(case(handshake, 3, actions));
        // Reset discards each truncated header/body prefix, with stale tail retained.
        for cut in 0..bytes.len() {
            cases.push(case(
                handshake,
                3,
                vec![feed(&bytes[..cut]), op(1), op(3), feed(&bytes), op(2)],
            ));
        }
        cases.push(Case {
            capacity: h + 19,
            ..case(
                handshake,
                3,
                vec![
                    feed(&bytes),
                    op(4),
                    op(2),
                    feed(wire(handshake, 0, 0)),
                    op(2),
                    op(3),
                ],
            )
        });
        // Configured zero limit admits exactly header-only frames and rejects body1.
        cases.push(case(
            handshake,
            0,
            vec![
                feed(wire(handshake, 0, 0)),
                op(2),
                feed(wire(handshake, 1, 0)),
                op(3),
            ],
        ));
    }
    compare(cases, "TLS framing rejection/reset/copy contract");
}

#[test]
fn ordinary_record_payload_to_handshake_consumer_executes() {
    let exe = compile("plain.lani");
    let (bytes, trace) = run(&exe, &[], "ordinary TLS framing consumer");
    assert!(bytes.is_empty());
    assert!(trace.is_empty(), "{trace}");
}

#[test]
fn full_u24_handshake_uses_one_explicit_owned_backing() {
    let exe = compile("full_u24.lani");
    let (bytes, trace) = run(&exe, &[], "full u24 handshake with owned backing");
    let mut at = 0;
    let body = 16_777_215u64;
    let checksum = (body / 256) * (255 * 256 / 2) + (body % 256) * (body % 256 - 1) / 2;
    let observed: Vec<_> = (0..7).map(|_| word(&bytes, &mut at)).collect();
    assert_eq!(
        &observed[..5],
        &[body, body + 4, body, body.div_ceil(4096), checksum]
    );
    assert!(
        observed[5] >= body + 10,
        "reported caller-owned capacity includes initialized storage"
    );
    assert_eq!(observed[6], 1, "owned u8 backing is packed");
    assert_eq!(at, bytes.len());
    // This boundary fixture intentionally allocates once; it is not part of the
    // zero-allocation claim for the caller-backed model/ordinary consumer.
    let mut live = BTreeMap::new();
    let mut allocations = 0;
    let mut releases = 0;
    for line in trace.lines() {
        if let Some(args) = line.strip_prefix("mmap(") {
            let size: usize = args.split(", ").nth(1).unwrap().parse().unwrap();
            let address = line.rsplit_once(" = ").unwrap().1.to_owned();
            assert!(
                address.starts_with("0x"),
                "allocation must succeed: {trace}"
            );
            assert!(
                size >= observed[5] as usize,
                "mapping includes the complete owned backing: {trace}"
            );
            assert!(live.insert(address, size).is_none(), "{trace}");
            allocations += 1;
        } else if let Some(args) = line.strip_prefix("munmap(") {
            let (fields, result) = args.split_once(')').unwrap();
            let (address, size) = fields.split_once(',').unwrap();
            assert_eq!(
                live.remove(address.trim()),
                Some(size.trim().parse::<usize>().unwrap()),
                "exact owner address/size release: {trace}"
            );
            assert_eq!(result.trim(), "= 0", "{trace}");
            releases += 1;
        } else {
            panic!("unexpected memory event: {trace}");
        }
    }
    assert_eq!(
        (allocations, releases),
        (1, 1),
        "one setup allocation and one explicit destroy: {trace}"
    );
    assert!(live.is_empty(), "{trace}");
}
