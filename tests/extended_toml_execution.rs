#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeMap,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Stdio},
    sync::OnceLock,
    time::Duration,
};

fn executable(path: &str, name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
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
    let output = common::TempArtifact::new("laniusc_toml", name, None);
    output.write_bytes(bytes);
    std::fs::set_permissions(output.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    output
}

fn model() -> &'static common::TempArtifact {
    static MODEL: OnceLock<common::TempArtifact> = OnceLock::new();
    MODEL.get_or_init(|| executable("tests/fixtures/extended_library/toml_model.lani", "model"))
}

#[derive(Clone, Debug, PartialEq)]
enum Value {
    Table(BTreeMap<String, Value>),
    Array(Vec<Value>),
    String(String),
    Integer(i64),
    Float(u64),
    Boolean(bool),
    Temporal(u32, String),
}

fn temporal_normal_form(kind: u32, input: &str) -> String {
    // Compare the oracle's typed time representation, never TOML syntax.
    // Seconds are optional in 1.1; insignificant fractional zeroes and UTC
    // spellings do not change values. Preserve every nonzero fractional digit.
    let mut value = input.replace(['t', ' '], "T").replace('z', "Z");
    if kind == 8 {
        return value;
    }
    let time_start = if kind == 9 { 0 } else { 11 };
    let mut time_end = value.len();
    if kind == 6 {
        time_end = value[time_start..]
            .find(['Z', '+', '-'])
            .map(|index| index + time_start)
            .unwrap();
    }
    if time_end - time_start == 5 {
        value.insert_str(time_end, ":00");
        time_end += 3;
    }
    if let Some(dot) = value[time_start..time_end].find('.') {
        let dot = dot + time_start;
        let mut end = time_end;
        while end > dot + 1 && value.as_bytes()[end - 1] == b'0' {
            end -= 1;
        }
        if end == dot + 1 {
            end = dot;
        }
        value.replace_range(end..time_end, "");
    }
    if kind == 6 {
        if let Some(prefix) = value.strip_suffix('Z') {
            return format!("{prefix}+00:00");
        }
    }
    value
}

fn oracle(value: &serde_json::Value) -> Value {
    match value {
        serde_json::Value::Array(values) => Value::Array(values.iter().map(oracle).collect()),
        serde_json::Value::Object(values) => {
            if let Some(kind) = values.get("type").and_then(serde_json::Value::as_str) {
                assert_eq!(values.len(), 2);
                let text = values["value"].as_str().unwrap();
                match kind {
                    "string" => Value::String(text.to_owned()),
                    "integer" => Value::Integer(text.parse().unwrap()),
                    "float" => Value::Float(text.parse::<f64>().unwrap().to_bits()),
                    "bool" => Value::Boolean(text.parse().unwrap()),
                    "datetime" => Value::Temporal(6, text.to_owned()),
                    "datetime-local" => Value::Temporal(7, text.to_owned()),
                    "date-local" => Value::Temporal(8, text.to_owned()),
                    "time-local" => Value::Temporal(9, text.to_owned()),
                    _ => panic!("unsupported official type {kind}"),
                }
            } else {
                Value::Table(
                    values
                        .iter()
                        .map(|(key, value)| (key.clone(), oracle(value)))
                        .collect(),
                )
            }
        }
        _ => panic!("untyped official oracle {value}"),
    }
}

fn compare(actual: &Value, expected: &Value, path: &str, exact_nan: bool) {
    match (actual, expected) {
        (Value::Table(actual), Value::Table(expected)) => {
            assert_eq!(
                actual.keys().collect::<Vec<_>>(),
                expected.keys().collect::<Vec<_>>(),
                "{path}: keys"
            );
            for (key, value) in expected {
                compare(&actual[key], value, &format!("{path}.{key}"), exact_nan);
            }
        }
        (Value::Array(actual), Value::Array(expected)) => {
            assert_eq!(actual.len(), expected.len(), "{path}: array length");
            for (index, (actual, expected)) in actual.iter().zip(expected).enumerate() {
                compare(actual, expected, &format!("{path}[{index}]"), exact_nan);
            }
        }
        (Value::Float(actual), Value::Float(expected)) => {
            if exact_nan || !f64::from_bits(*expected).is_nan() {
                assert_eq!(actual, expected, "{path}: binary64 value/sign");
            } else {
                assert!(
                    f64::from_bits(*actual).is_nan(),
                    "{path}: expected NaN, got {actual:#x}"
                );
            }
        }
        (Value::Temporal(actual_kind, actual), Value::Temporal(expected_kind, expected)) => {
            assert_eq!(actual_kind, expected_kind, "{path}: temporal type");
            assert_eq!(
                temporal_normal_form(*actual_kind, actual),
                temporal_normal_form(*expected_kind, expected),
                "{path}: temporal value"
            );
        }
        _ => assert_eq!(actual, expected, "{path}: typed value"),
    }
}

#[derive(Clone)]
struct Request {
    label: String,
    source: Vec<u8>,
    limits: [i32; 6],
    work: u64,
    text_entry: bool,
}

impl Request {
    fn new(label: impl Into<String>, source: impl AsRef<[u8]>) -> Self {
        Self {
            label: label.into(),
            source: source.as_ref().to_vec(),
            limits: [262144, 1000000, 256, 262144, 262144, 1048576],
            work: 100000000,
            text_entry: false,
        }
    }
}

#[derive(Debug)]
enum Reply {
    Value(Value, Vec<u8>),
    Error {
        stage: u32,
        kind: u32,
        allocation: bool,
        offset: i32,
    },
}

struct Reader<'a> {
    bytes: &'a [u8],
    position: usize,
}
impl<'a> Reader<'a> {
    fn take(&mut self, count: usize) -> &'a [u8] {
        let end = self.position.checked_add(count).unwrap();
        let bytes = self
            .bytes
            .get(self.position..end)
            .expect("truncated model response");
        self.position = end;
        bytes
    }
    fn word(&mut self) -> u32 {
        u32::from_le_bytes(self.take(4).try_into().unwrap())
    }
    fn wide(&mut self) -> u64 {
        u64::from_le_bytes(self.take(8).try_into().unwrap())
    }
    fn text(&mut self) -> String {
        let count = self.word() as usize;
        String::from_utf8(self.take(count).to_vec()).unwrap()
    }
    fn value(&mut self, depth: usize) -> Value {
        assert!(depth <= 1024, "bad model tree");
        match self.word() {
            0 => {
                let count = self.word();
                let mut table = BTreeMap::new();
                for _ in 0..count {
                    let key = self.text();
                    assert!(
                        table.insert(key.clone(), self.value(depth + 1)).is_none(),
                        "duplicate output key {key:?}"
                    );
                }
                Value::Table(table)
            }
            1 => {
                let count = self.word();
                Value::Array((0..count).map(|_| self.value(depth + 1)).collect())
            }
            2 => Value::String(self.text()),
            3 => Value::Integer(self.wide() as i64),
            4 => Value::Float(self.wide()),
            5 => {
                let value = self.word();
                assert!(value <= 1);
                Value::Boolean(value == 1)
            }
            kind @ 6..=9 => Value::Temporal(kind, self.text()),
            kind => panic!("unknown model type {kind}"),
        }
    }
    fn reply(&mut self) -> Reply {
        let stage = self.word();
        if stage != 0 {
            let kind = self.word();
            return Reply::Error {
                stage,
                kind,
                allocation: kind == 16,
                offset: self.word() as i32,
            };
        }
        let value = self.value(0);
        let count = self.word() as usize;
        Reply::Value(value, self.take(count).to_vec())
    }
}

fn execute(requests: &[Request]) -> Vec<Reply> {
    let mut replies = Vec::new();
    for batch in requests.chunks(32) {
        let mut input = Vec::new();
        for request in batch {
            input.extend_from_slice(&(request.source.len() as u32).to_le_bytes());
            for limit in request.limits {
                input.extend_from_slice(&limit.to_le_bytes());
            }
            input.extend_from_slice(&request.work.to_le_bytes());
            input.extend_from_slice(&u32::from(request.text_entry).to_le_bytes());
            input.extend_from_slice(&request.source);
        }
        let file = common::TempArtifact::new("laniusc_toml", "input", None);
        file.write_bytes(input);
        let output = common::process_output_with_timeout(
            "TOML typed execution",
            Command::new(model().path())
                .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())),
            Duration::from_secs(15),
        );
        assert_eq!(
            output.status.code(),
            Some(0),
            "batch {:?}: {output:?}",
            batch.iter().map(|r| &r.label).collect::<Vec<_>>()
        );
        assert!(output.stderr.is_empty(), "{output:?}");
        let mut reader = Reader {
            bytes: &output.stdout,
            position: 0,
        };
        for _ in batch {
            replies.push(reader.reply());
        }
        assert_eq!(
            reader.position,
            output.stdout.len(),
            "unexpected trailing model output"
        );
    }
    replies
}

#[test]
fn typed_queries_bounds_copied_ownership_and_atomic_encoding_execute() {
    let executable = executable(
        "tests/fixtures/extended_library/toml_contracts.lani",
        "contracts",
    );
    let output = common::process_output_with_timeout(
        "TOML public contracts",
        &mut Command::new(executable.path()),
        Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

fn assert_all_allocations_freed(trace: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut allocations = 0;
    for line in trace.lines() {
        if line.starts_with("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            if result.starts_with("0x") {
                let address = result.split_whitespace().next().unwrap().to_owned();
                assert!(live.insert(address), "duplicate live mapping: {line}");
                allocations += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            let address = tail.split(',').next().unwrap();
            assert!(line.ends_with(" = 0"), "deallocation failed: {line}");
            assert!(live.remove(address), "unknown/double deallocation: {line}");
        }
    }
    assert!(live.is_empty(), "leaked mappings: {live:?}\n{trace}");
    allocations
}

#[test]
fn every_observed_allocation_denial_and_partial_syntax_failure_release_owners() {
    let executable = executable(
        "tests/fixtures/extended_library/toml_allocation_failure.lani",
        "allocation_failure",
    );
    let trace = common::TempArtifact::new("laniusc_toml", "allocation_trace", None);
    let baseline = common::process_output_with_timeout(
        "TOML allocation baseline",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"])
            .arg(executable.path()),
        Duration::from_secs(10),
    );
    assert_eq!(baseline.status.code(), Some(1), "{baseline:?}");
    assert!(
        baseline.stdout.is_empty() && baseline.stderr.is_empty(),
        "{baseline:?}"
    );
    let baseline_trace = std::fs::read_to_string(trace.path()).unwrap();
    let allocation_count = assert_all_allocations_freed(&baseline_trace);
    assert!(
        allocation_count > 20,
        "fixture must exercise nested owners: {baseline_trace}"
    );
    for when in 1..=allocation_count {
        let output = common::process_output_with_timeout(
            "TOML individual allocation denial",
            Command::new("strace")
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=mmap,munmap", "-e"])
                .arg(format!("inject=mmap:error=ENOMEM:when={when}"))
                .arg(executable.path()),
            Duration::from_secs(10),
        );
        assert_eq!(
            output.status.code(),
            Some(0),
            "mmap {when}/{allocation_count}: {output:?}"
        );
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert!(
            events.contains("INJECTED") && events.contains("ENOMEM"),
            "denial not reached: {events}"
        );
        assert_all_allocations_freed(&events);
    }
    eprintln!("TOML exercised every one of {allocation_count} individual mmap denials");

    for source in [
        "a=['hello',{nested=[1,2,3]}]\nb='unfinished",
        "a=['hello',{nested=[1,2,3]}]\nb=\"bad\\uZZZZ\"",
        "a=['hello',{nested=[1,2,3]}]\nb=\"bad\\uD800\"",
        "[table]\nx='hello'\n[table]\ny='world'\n",
        "a={b={c=[1,2,3]}}\na.b.d=4\n",
        "[[a]]\nb=['hello']\n[a.b]\nx=3\n",
    ] {
        let request = Request::new("partial syntax cleanup", source);
        let mut frame = Vec::new();
        frame.extend_from_slice(&(request.source.len() as u32).to_le_bytes());
        for limit in request.limits {
            frame.extend_from_slice(&limit.to_le_bytes());
        }
        frame.extend_from_slice(&request.work.to_le_bytes());
        frame.extend_from_slice(&0u32.to_le_bytes());
        frame.extend_from_slice(&request.source);
        let input = common::TempArtifact::new("laniusc_toml", "partial_input", None);
        input.write_bytes(frame);
        let output = common::process_output_with_timeout(
            "TOML partial syntax cleanup",
            Command::new("strace")
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=mmap,munmap"])
                .arg(model().path())
                .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())),
            Duration::from_secs(10),
        );
        assert_eq!(output.status.code(), Some(0), "{source:?}: {output:?}");
        let mut reader = Reader {
            bytes: &output.stdout,
            position: 0,
        };
        assert!(
            matches!(
                reader.reply(),
                Reply::Error {
                    stage: 1,
                    allocation: false,
                    ..
                }
            ),
            "{source:?}: {output:?}"
        );
        assert_eq!(reader.position, output.stdout.len());
        assert_all_allocations_freed(&std::fs::read_to_string(trace.path()).unwrap());
    }
}

fn check_values(cases: &[(Request, Value)]) {
    let requests: Vec<_> = cases.iter().map(|(request, _)| request.clone()).collect();
    let first = execute(&requests);
    let mut roundtrip = Vec::new();
    for ((request, expected), reply) in cases.iter().zip(&first) {
        match reply {
            Reply::Value(actual, encoded) => {
                compare(actual, expected, &request.label, false);
                let mut next =
                    Request::new(format!("{} canonical roundtrip", request.label), encoded);
                next.text_entry = true;
                roundtrip.push(next);
            }
            reply => panic!(
                "{}: valid input rejected: {reply:?}; input={:?}",
                request.label,
                String::from_utf8_lossy(&request.source)
            ),
        }
    }
    for (((request, _), original), repeated) in cases.iter().zip(first).zip(execute(&roundtrip)) {
        match (original, repeated) {
            (Reply::Value(original, encoded), Reply::Value(repeated, encoded_again)) => {
                compare(
                    &repeated,
                    &original,
                    &format!("{}: roundtrip", request.label),
                    true,
                );
                assert_eq!(
                    encoded_again, encoded,
                    "{}: canonical output must be idempotent",
                    request.label
                );
            }
            (_, repeated) => panic!("{}: canonical output rejected: {repeated:?}", request.label),
        }
    }
}

#[test]
fn official_corpus_provenance_and_complete_1_1_index_are_verified() {
    let output = common::process_output_with_timeout(
        "TOML corpus integrity",
        Command::new("python3")
            .arg(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tools/toml_test/corpus.py"))
            .arg("--verify"),
        Duration::from_secs(5),
    );
    assert!(output.status.success(), "{output:?}");
}

#[test]
fn official_toml_1_1_valid_typed_values_and_canonical_roundtrips_execute() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("data/toml-test/v2.2.0");
    let index = std::fs::read_to_string(root.join("files-toml-1.1.0")).unwrap();
    let mut cases = Vec::new();
    for label in index
        .lines()
        .filter(|name| name.starts_with("valid/") && name.ends_with(".toml"))
    {
        let source = std::fs::read(root.join("tests").join(label)).unwrap();
        let expected: serde_json::Value = serde_json::from_slice(
            &std::fs::read(root.join("tests").join(label.replace(".toml", ".json"))).unwrap(),
        )
        .unwrap();
        cases.push((Request::new(label, source), oracle(&expected)));
    }
    assert_eq!(cases.len(), 214, "full pinned TOML 1.1 valid coverage");
    check_values(&cases);
}

#[test]
fn official_toml_1_1_invalid_inputs_all_reject_during_execution() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("data/toml-test/v2.2.0");
    let index = std::fs::read_to_string(root.join("files-toml-1.1.0")).unwrap();
    let requests: Vec<_> = index
        .lines()
        .filter(|name| name.starts_with("invalid/") && name.ends_with(".toml"))
        .map(|label| {
            Request::new(
                label,
                std::fs::read(root.join("tests").join(label)).unwrap(),
            )
        })
        .collect();
    assert_eq!(requests.len(), 467, "full pinned TOML 1.1 invalid coverage");
    let mut failures = Vec::new();
    for (request, reply) in requests.iter().zip(execute(&requests)) {
        match reply {
            Reply::Error {
                stage: 1 | 3,
                allocation: false,
                offset,
                ..
            } => {
                assert!(
                    offset >= -1 && offset <= request.source.len() as i32,
                    "{}: error offset {offset}",
                    request.label
                );
            }
            reply => failures.push(format!("{}: {reply:?}", request.label)),
        }
    }
    assert!(
        failures.is_empty(),
        "official invalid conformance failures:\n{}",
        failures.join("\n")
    );
}

fn next(seed: &mut u64) -> u64 {
    *seed ^= *seed << 13;
    *seed ^= *seed >> 7;
    *seed ^= *seed << 17;
    *seed
}

fn generated(seed: &mut u64, depth: usize) -> (String, Value) {
    let choice = next(seed) % if depth == 0 { 8 } else { 10 };
    match choice {
        0 => {
            let value = next(seed) as i64;
            (value.to_string(), Value::Integer(value))
        }
        1 => {
            let values = [
                "0.0",
                "-0.0",
                "+0.0",
                "inf",
                "-inf",
                "nan",
                "-nan",
                "5e-324",
                "1.7976931348623157e308",
                "2.2250738585072014e-308",
                "9007199254740993.0",
                "1_234.5_625e-02",
            ];
            let text = values[(next(seed) as usize) % values.len()];
            (
                text.into(),
                Value::Float(text.replace('_', "").parse::<f64>().unwrap().to_bits()),
            )
        }
        2 => {
            let value = next(seed) & 1 != 0;
            (value.to_string(), Value::Boolean(value))
        }
        3 => {
            let values = [
                "",
                "é🙂",
                "\0\t\r\n\u{1b}",
                "\\\"#='",
                "line\u{2028}end",
                " dotted.key ",
            ];
            let value = values[(next(seed) as usize) % values.len()].to_owned();
            (serde_json::to_string(&value).unwrap(), Value::String(value))
        }
        kind @ 4..=7 => {
            let (tag, texts): (u32, &[&str]) = match kind {
                4 => (
                    6,
                    &[
                        "0000-02-29t23:59:59.123456789012z",
                        "2000-02-29 07:32-00:00",
                        "1979-05-27T00:32:00.500+07:30",
                    ],
                ),
                5 => (7, &["0000-01-01T00:00", "2400-02-29t23:59:59.999999999999"]),
                6 => (8, &["0000-02-29", "2000-02-29", "9999-12-31"]),
                _ => (
                    9,
                    &["00:00", "23:59:59.123456789123456789", "07:32:00.500000"],
                ),
            };
            let text = texts[(next(seed) as usize) % texts.len()].to_owned();
            (text.clone(), Value::Temporal(tag, text))
        }
        8 => {
            let count = next(seed) % 5;
            let children: Vec<_> = (0..count).map(|_| generated(seed, depth - 1)).collect();
            let source = if children.is_empty() {
                "[]".to_owned()
            } else {
                format!(
                    "[{},]",
                    children
                        .iter()
                        .map(|(text, _)| text.clone())
                        .collect::<Vec<_>>()
                        .join(", # generated\n")
                )
            };
            (
                source,
                Value::Array(children.into_iter().map(|(_, value)| value).collect()),
            )
        }
        _ => {
            let count = next(seed) % 5;
            let mut fields = Vec::new();
            let mut values = BTreeMap::new();
            for index in 0..count {
                let key = format!("{}é.{}", index, next(seed) % 17);
                let (text, value) = generated(seed, depth - 1);
                fields.push(format!("{} = {text}", serde_json::to_string(&key).unwrap()));
                values.insert(key, value);
            }
            let text = if fields.is_empty() {
                "{}".to_owned()
            } else {
                format!("{{\n{}, # 1.1 trailing comma\n}}", fields.join(",\n"))
            };
            (text, Value::Table(values))
        }
    }
}

#[test]
fn seeded_typed_trees_and_stateful_table_sequences_roundtrip() {
    let mut seed = 0x746f_6d6c_3131_5eed;
    let mut cases = Vec::new();
    for case in 0..192 {
        let initial_seed = seed;
        let (source, value) = generated(&mut seed, 4);
        cases.push((
            Request::new(
                format!("generated case {case} seed {initial_seed:#x}"),
                format!("root = {source}\n"),
            ),
            Value::Table(BTreeMap::from([("root".into(), value)])),
        ));
    }
    for case in 0..32 {
        let count = 1 + next(&mut seed) % 7;
        let mut source = "title = 'events'\n".to_owned();
        let mut events = Vec::new();
        for event in 0..count {
            let id = next(&mut seed) as i64;
            let flag = next(&mut seed) & 1 != 0;
            source.push_str(&format!("[[event]]\nid={id}\n[event.meta]\nflag={flag}\n"));
            let mut items = Vec::new();
            for item in 0..(event % 3 + 1) {
                source.push_str(&format!("[[event.items]]\nindex={item}\n"));
                items.push(Value::Table(BTreeMap::from([(
                    "index".into(),
                    Value::Integer(item as i64),
                )])));
            }
            events.push(Value::Table(BTreeMap::from([
                ("id".into(), Value::Integer(id)),
                (
                    "meta".into(),
                    Value::Table(BTreeMap::from([("flag".into(), Value::Boolean(flag))])),
                ),
                ("items".into(), Value::Array(items)),
            ])));
        }
        cases.push((
            Request::new(format!("stateful AoT case {case}"), source),
            Value::Table(BTreeMap::from([
                ("title".into(), Value::String("events".into())),
                ("event".into(), Value::Array(events)),
            ])),
        ));
    }
    check_values(&cases);
}

#[test]
fn configurable_limits_reject_at_their_public_boundaries() {
    let mut requests = Vec::new();
    for (field, source, maximum) in [
        (0, "a=1\n", 3),
        (1, "a=1\n", 1),
        (2, "a=[[1]]\n", 1),
        (3, "a='abc'\n", 2),
        (4, "a=123\n", 2),
        (5, "a=1\n", 0),
    ] {
        let mut request = Request::new(format!("limit field {field}"), source);
        request.limits[field] = maximum;
        requests.push(request);
    }
    let mut work = Request::new("zero work", "a=1\n");
    work.work = 0;
    requests.push(work);
    for field in 0..6 {
        let mut invalid = Request::new(format!("negative option {field}"), "a=1\n");
        invalid.limits[field] = -1;
        requests.push(invalid);
    }
    for (index, (request, reply)) in requests.iter().zip(execute(&requests)).enumerate() {
        let expected_kind = match index {
            0..=5 => 9 + index as u32,
            6 => 15,
            _ => 17,
        };
        assert!(
            matches!(reply, Reply::Error { stage: 1 | 2, allocation: false, kind, .. } if kind == expected_kind),
            "{}: expected error kind {expected_kind}, got {reply:?}",
            request.label
        );
    }
    let mut at_limit = Request::new(
        "input, node, string and number limits inclusive",
        "a=123\nb='abc'\n",
    );
    at_limit.limits[0] = at_limit.source.len() as i32;
    at_limit.limits[1] = 3;
    at_limit.limits[3] = 3;
    at_limit.limits[4] = 3;
    let mut empty = Request::new("all empty limits inclusive", "");
    empty.limits = [0, 1, 0, 0, 0, 0];
    empty.work = u64::MAX;
    let mut depth = Request::new("nested array depth inclusive", "a=[[1]]\n");
    depth.limits[2] = 3;
    let mut output = Request::new("canonical output byte limit inclusive", "a=1\n");
    output.limits[5] = 6;
    let mut unicode = Request::new("decoded UTF-8 string byte limit inclusive", "a='é'\n");
    unicode.limits[3] = 2;
    check_values(&[
        (
            at_limit,
            Value::Table(BTreeMap::from([
                ("a".into(), Value::Integer(123)),
                ("b".into(), Value::String("abc".into())),
            ])),
        ),
        (empty, Value::Table(BTreeMap::new())),
        (
            depth,
            Value::Table(BTreeMap::from([(
                "a".into(),
                Value::Array(vec![Value::Array(vec![Value::Integer(1)])]),
            )])),
        ),
        (
            output,
            Value::Table(BTreeMap::from([("a".into(), Value::Integer(1))])),
        ),
        (
            unicode,
            Value::Table(BTreeMap::from([("a".into(), Value::String("é".into()))])),
        ),
    ]);
}

#[test]
fn canonical_scalar_values_ignore_equivalent_source_spellings() {
    for spellings in [
        vec!["42", "+42", "4_2", "0x2a", "0o52", "0b101010"],
        vec!["1.0", "+1.0", "1e0", "1.000000e+00", "1_0e-1"],
        vec!["-0.0", "-0e0", "-0.000e+100"],
        vec![
            "1979-05-27t07:32z",
            "1979-05-27T07:32:00Z",
            "1979-05-27 07:32:00.000+00:00",
        ],
        vec!["07:32", "07:32:00", "07:32:00.000"],
    ] {
        let requests: Vec<_> = spellings
            .iter()
            .map(|text| Request::new(*text, format!("a={text}\n")))
            .collect();
        let replies = execute(&requests);
        let mut canonical = None;
        for (request, reply) in requests.iter().zip(replies) {
            let Reply::Value(_, encoded) = reply else {
                panic!("{}: {reply:?}", request.label);
            };
            if let Some(expected) = &canonical {
                assert_eq!(
                    &encoded, expected,
                    "{}: canonical scalar value",
                    request.label
                );
            } else {
                canonical = Some(encoded);
            }
        }
    }
    let requests: Vec<_> = ["nan", "+nan", "-nan", "-0.0", "+0.0"]
        .iter()
        .map(|text| Request::new(*text, format!("a={text}\n")))
        .collect();
    for (request, reply) in requests.iter().zip(execute(&requests)) {
        let Reply::Value(Value::Table(table), _) = reply else {
            panic!("{}: {reply:?}", request.label);
        };
        let Value::Float(bits) = table["a"] else {
            panic!("{}: wrong scalar type", request.label);
        };
        let value = f64::from_bits(bits);
        assert_eq!(
            value.is_sign_negative(),
            request.label.starts_with('-'),
            "{}: documented NaN/zero sign",
            request.label
        );
        assert_eq!(
            value.is_nan(),
            request.label.ends_with("nan"),
            "{}: NaN kind",
            request.label
        );
    }
}

#[test]
fn binary64_rounding_extremes_seeded_values_and_precision_limits_execute() {
    let mut cases = Vec::new();
    for source in [
        "1.00000000000000011102230246251565404236316680908203125",
        "1.00000000000000033306690738754696212708950042724609375",
        "2.4703282292062327e-324",
        "2.4703282292062328e-324",
        "2.2250738585072012e-308",
        "1.7976931348623157e308",
        "1.7976931348623159e308",
        "1e1000000",
        "-1e1000000",
        "1e-1000000",
        "-1e-1000000",
    ] {
        let value = source.parse::<f64>().unwrap();
        cases.push((
            Request::new(
                format!("binary64 boundary {source}"),
                format!("a={source}\n"),
            ),
            Value::Table(BTreeMap::from([(
                "a".into(),
                Value::Float(value.to_bits()),
            )])),
        ));
    }
    let mut seed = 0x6269_6e36_342e_746f;
    for index in 0..128 {
        let bits = next(&mut seed);
        let value = f64::from_bits(bits);
        if !value.is_finite() {
            continue;
        }
        let source = format!("a={value:e}\n");
        cases.push((
            Request::new(format!("binary64 seeded {index} bits {bits:#x}"), source),
            Value::Table(BTreeMap::from([("a".into(), Value::Float(bits))])),
        ));
    }
    let at_precision = format!("a=0.{}\n", "0".repeat(767));
    cases.push((
        Request::new("768 significand digits inclusive", at_precision),
        Value::Table(BTreeMap::from([("a".into(), Value::Float(0))])),
    ));
    check_values(&cases);
    let too_precise = Request::new(
        "769 significand digits rejected explicitly",
        format!("a=0.{}\n", "0".repeat(768)),
    );
    assert!(matches!(
        execute(&[too_precise]).as_slice(),
        [Reply::Error {
            stage: 1,
            kind: 13,
            allocation: false,
            ..
        }]
    ));
}
