#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    ffi::{OsStr, OsString},
    os::unix::{
        ffi::{OsStrExt, OsStringExt},
        fs::PermissionsExt,
    },
    path::{Component, Path},
    process::{Command, Output},
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
    let exe = common::TempArtifact::new("laniusc_paths", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(command: &mut Command) -> Output {
    common::short_process_output_with_timeout("paths", command)
}
fn checked(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn numbers(bytes: &[u8]) -> Vec<i32> {
    std::str::from_utf8(bytes)
        .unwrap()
        .split_whitespace()
        .map(|v| v.parse().unwrap())
        .collect()
}
fn view(out: &mut Vec<i32>, bytes: &[u8]) {
    out.push(bytes.len() as i32);
    out.extend(bytes.iter().map(|&b| i32::from(b)));
}
fn optional(out: &mut Vec<i32>, value: Option<&OsStr>) {
    match value {
        Some(bytes) => view(out, bytes.as_bytes()),
        None => out.push(-1),
    }
}

// Rust's Unix component parser is the independent grammar reference. Locate
// its returned bytes in the source to model our documented remaining window.
fn parts(bytes: &[u8]) -> Vec<(i32, usize, usize)> {
    let mut offset = 0;
    Path::new(OsStr::from_bytes(bytes))
        .components()
        .map(|part| {
            let kind = match part {
                Component::RootDir => 0,
                Component::CurDir => 1,
                Component::ParentDir => 2,
                Component::Normal(_) => 3,
                _ => unreachable!(),
            };
            let raw = part.as_os_str().as_bytes();
            let start = offset
                + bytes[offset..]
                    .windows(raw.len())
                    .position(|s| s == raw)
                    .unwrap();
            offset = start + raw.len();
            (kind, start, offset)
        })
        .collect()
}
fn window<'a>(bytes: &'a [u8], components: &[(i32, usize, usize)]) -> &'a [u8] {
    match (components.first(), components.last()) {
        (Some(first), Some(last)) => &bytes[first.1..last.2],
        _ => &[],
    }
}
fn parent(bytes: &[u8]) -> Option<&[u8]> {
    let mut components = parts(bytes);
    let last = components.pop()?;
    if last.0 == 0 {
        None
    } else {
        Some(window(bytes, &components))
    }
}
fn normalized(bytes: &[u8]) -> Vec<u8> {
    let absolute = bytes.starts_with(b"/");
    let mut stack: Vec<&[u8]> = Vec::new();
    for part in Path::new(OsStr::from_bytes(bytes)).components() {
        match part {
            Component::Normal(v) => stack.push(v.as_bytes()),
            Component::ParentDir => {
                if stack.last().is_some_and(|p| *p != b"..") {
                    stack.pop();
                } else if !absolute {
                    stack.push(b"..");
                }
            }
            _ => {}
        }
    }
    let mut out = if absolute { b"/".to_vec() } else { Vec::new() };
    out.extend(stack.join(&b'/'));
    if out.is_empty() {
        out.push(b'.');
    }
    out
}
fn expected(bytes: &[u8], other: &[u8]) -> Vec<i32> {
    let path = Path::new(OsStr::from_bytes(bytes));
    let prefix = Path::new(OsStr::from_bytes(other));
    let mut out = vec![
        bytes.len() as i32,
        i32::from(path.is_absolute()),
        i32::from(std::str::from_utf8(bytes).is_ok()),
    ];
    optional(&mut out, path.file_name());
    optional(&mut out, path.file_stem());
    optional(&mut out, path.extension());
    for mode in 0..3 {
        let mut remaining = parts(bytes);
        let mut index = 0;
        loop {
            view(&mut out, window(bytes, &remaining));
            if remaining.is_empty() {
                out.push(4);
                break;
            }
            let part = if mode == 0 || (mode == 2 && index % 2 == 0) {
                remaining.remove(0)
            } else {
                remaining.pop().unwrap()
            };
            out.push(part.0);
            view(&mut out, &bytes[part.1..part.2]);
            index += 1;
        }
    }
    let mut ancestor = Some(bytes);
    while let Some(current) = ancestor {
        view(&mut out, current);
        ancestor = parent(current);
    }
    out.push(-1);
    if path.starts_with(prefix) {
        let components = parts(bytes);
        view(&mut out, window(bytes, &components[parts(other).len()..]));
    } else {
        out.push(-1);
    }
    out.push(i32::from(path.starts_with(prefix)));
    out.push(i32::from(path.ends_with(prefix)));
    // The documented kind order is explicit; compare component byte sequences.
    let keys = |raw: &[u8]| {
        parts(raw)
            .into_iter()
            .map(|(k, s, e)| (k, raw[s..e].to_vec()))
            .collect::<Vec<_>>()
    };
    out.push(match keys(bytes).cmp(&keys(other)) {
        std::cmp::Ordering::Less => -1,
        std::cmp::Ordering::Equal => 0,
        std::cmp::Ordering::Greater => 1,
    });
    view(&mut out, &normalized(bytes));
    out
}
#[test]
fn borrowed_paths_execute_without_allocation_or_filesystem_calls() {
    for fixture in [
        "tests/fixtures/stdlib_foundation/path_contracts.lani",
        "tests/fixtures/stdlib_foundation/path_view_dependency/from_view.lani",
    ] {
        let exe = executable(fixture);
        let trace = common::TempArtifact::new("laniusc_paths", "pure_trace", None);
        let output = run(Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,munmap,open,openat",
                "-e",
                "inject=mmap:error=ENOMEM:when=1+",
            ])
            .arg(exe.path()));
        checked(&output);
        assert!(output.stdout.is_empty());
        assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
    }
}
#[test]
fn components_names_ancestors_prefixes_and_normalization_match_models() {
    let exe = executable("tests/fixtures/stdlib_foundation/path_model.lani");
    let boundaries: &[&[u8]] = &[
        b"",
        b"/",
        b"//",
        b"///./",
        b".",
        b"./",
        b"././a/./b//",
        b"..",
        b"../..",
        b"a/../b",
        b"/../../a/../",
        b"a.",
        b".a",
        b"..a",
        b"a..",
        b"a.tar.gz",
        b"a\\b",
        b"C:\\a",
        b"a//./b/..//",
        b".//../a",
        b"\xff/\xfe.txt",
    ];
    let mut cases = Vec::new();
    for a in boundaries {
        for b in boundaries {
            cases.push((a.to_vec(), b.to_vec()));
        }
    }
    let atoms: &[&[u8]] = &[
        b"",
        b".",
        b"..",
        b"a",
        b"abc",
        b"a.txt",
        b".hidden",
        b"trailing.",
        b"\\",
        b"\xff\xfe",
    ];
    let mut state = 0x70617468_20261023_u64;
    let mut next = || {
        state = state
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        state
    };
    for _ in 0..192 {
        let mut pair = [Vec::new(), Vec::new()];
        for path in &mut pair {
            let count = next() % 12;
            for _ in 0..count {
                path.extend(atoms[(next() as usize) % atoms.len()]);
                path.extend(std::iter::repeat_n(b'/', (next() % 4) as usize));
            }
            path.extend(atoms[(next() as usize) % atoms.len()]);
        }
        cases.push((pair[0].clone(), pair[1].clone()));
    }
    for (index, (a, b)) in cases.into_iter().enumerate() {
        let output = run(Command::new(exe.path())
            .arg(OsStr::from_bytes(&a))
            .arg(OsStr::from_bytes(&b)));
        checked(&output);
        assert_eq!(
            numbers(&output.stdout),
            expected(&a, &b),
            "case {index}, path={a:?}, other={b:?}"
        );
    }
}

fn edit(model: &[u8], command: &[u8]) -> Result<Vec<u8>, i32> {
    let opcode = command[0];
    let data = &command[1..];
    let append = |base: &[u8], child: &[u8]| {
        if child.starts_with(b"/") {
            return child.to_vec();
        }
        let mut out = base.to_vec();
        if !out.is_empty() && !out.ends_with(b"/") {
            out.push(b'/');
        }
        out.extend(child);
        out
    };
    let path = Path::new(OsStr::from_bytes(model));
    let mut content = data.to_vec();
    if opcode == b'B' {
        content = path
            .file_name()
            .map_or(Vec::new(), |v| v.as_bytes().to_vec());
    }
    if opcode == b'C' {
        content = path
            .extension()
            .map_or(Vec::new(), |v| v.as_bytes().to_vec());
    }
    match opcode {
        b'0' => Ok(data.to_vec()),
        b'1' => Ok(append(model, data)),
        b'A' => Ok(append(model, model)),
        b'2' => Ok(parent(model).unwrap_or(model).to_vec()),
        b'5' => Ok(normalized(model)),
        b'6' | b'8' => Ok(model.to_vec()),
        b'9' => Ok(Vec::new()),
        b'7' => {
            let additional = std::str::from_utf8(data).unwrap().parse::<i32>().unwrap();
            if additional < 0 {
                Err(1)
            } else if additional as usize > i32::MAX as usize - model.len() {
                Err(5)
            } else {
                Ok(model.to_vec())
            }
        }
        b'3' | b'4' | b'B' | b'C' => {
            let extension = opcode == b'4' || opcode == b'B';
            if content.contains(&b'/')
                || (!extension && (content.is_empty() || content == b"." || content == b".."))
            {
                return Err(3);
            }
            let components = parts(model);
            let name = components.last().copied().filter(|p| p.0 == 3);
            if extension {
                let (_, start, end) = name.ok_or(4)?;
                let stem = Path::new(OsStr::from_bytes(&model[start..end]))
                    .file_stem()
                    .unwrap()
                    .as_bytes();
                let mut out = model[..start + stem.len()].to_vec();
                if !content.is_empty() {
                    out.push(b'.');
                    out.extend(content);
                }
                Ok(out)
            } else if let Some((_, start, _)) = name {
                let mut out = model[..start].to_vec();
                out.extend(content);
                Ok(out)
            } else {
                Ok(append(model, &content))
            }
        }
        b'D' => Err(2),
        b'E' => Err(1),
        _ => panic!("unknown opcode {opcode}"),
    }
}
fn check_edits(output: &Output, commands: &[Vec<u8>], allow_allocation_failure: bool) {
    checked(output);
    let tokens = numbers(&output.stdout);
    let mut tokens = tokens.iter();
    let mut model = Vec::new();
    let mut capacity = 0;
    for (step, command) in commands.iter().enumerate() {
        let status = *tokens.next().expect("status");
        let actual_capacity = *tokens.next().expect("capacity");
        let len = *tokens.next().expect("len");
        assert!(
            len >= 0 && actual_capacity >= len,
            "step={step} command={command:?}"
        );
        let actual: Vec<u8> = (0..len)
            .map(|_| u8::try_from(*tokens.next().unwrap()).unwrap())
            .collect();
        let expected = edit(&model, command);
        if status == 6 {
            assert!(
                allow_allocation_failure && expected.is_ok(),
                "step={step}, {command:?}"
            );
            assert_eq!(actual_capacity, capacity);
        } else {
            match expected {
                Ok(bytes) => {
                    assert_eq!(status, 0, "step={step}, {command:?}");
                    model = bytes;
                }
                Err(error) => {
                    assert_eq!(status, error, "step={step}, {command:?}");
                    assert_eq!(actual_capacity, capacity);
                }
            }
        }
        assert_eq!(actual, model, "step={step}, command={command:?}");
        capacity = actual_capacity;
    }
    assert!(tokens.next().is_none());
}
#[test]
fn owned_path_mutations_match_state_model_including_aliased_sources() {
    let exe = executable("tests/fixtures/stdlib_foundation/path_edits.lani");
    let mut commands: Vec<Vec<u8>> = [
        b"0a.txt".as_slice(),
        b"A",
        b"B",
        b"C",
        b"6",
        b"2",
        b"5",
        b"7-1",
        b"72147483647",
        b"D",
        b"E",
        b"8",
        b"9",
        b"8",
    ]
    .iter()
    .map(|c| c.to_vec())
    .collect();
    let atoms: &[&[u8]] = &[
        b"",
        b".",
        b"..",
        b"/",
        b"///",
        b"a",
        b"a/b.txt",
        b"././a/./",
        b"../x",
        b".a",
        b"a.",
        b"..a",
        b"\xff.txt",
        b"with space",
        b"\\a",
    ];
    let mut state = 0xb0ff7061_20261023_u64;
    let mut next = || {
        state = state
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        state
    };
    for step in 0..4000 {
        let op = if step % 16 == 0 {
            b'0'
        } else {
            b"0123456789ABCDE"[(next() % 15) as usize]
        };
        let mut command = vec![op];
        if op == b'7' {
            command.extend([b"-1".as_slice(), b"0", b"1", b"16", b"128"][(next() % 5) as usize]);
        } else {
            command.extend(atoms[(next() % atoms.len() as u64) as usize]);
        }
        commands.push(command);
    }
    let args: Vec<_> = commands.iter().cloned().map(OsString::from_vec).collect();
    let output = run(Command::new(exe.path()).args(&args));
    check_edits(&output, &commands, false);
}
fn freed(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut count = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let value = line.rsplit(" = ").next().unwrap();
            if value.starts_with("0x") {
                assert!(
                    live.insert(value.split_whitespace().next().unwrap().to_owned()),
                    "{events}"
                );
                count += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            assert!(
                line.ends_with(" = 0") && live.remove(tail.split(',').next().unwrap()),
                "{events}"
            );
        }
    }
    assert!(live.is_empty(), "leaked allocations: {events}");
    count
}
#[test]
fn every_owned_path_allocation_failure_preserves_contents_and_capacity() {
    let exe = executable("tests/fixtures/stdlib_foundation/path_edits.lani");
    let commands: Vec<Vec<u8>> = [
        b"0a.txt".as_slice(),
        b"1b",
        b"A",
        b"6",
        b"7100",
        b"A",
        b"B",
        b"C",
        b"3new",
        b"4tar.gz",
        b"4",
        b"5",
        b"8",
        b"1/absolute",
        b"A",
        b"D",
        b"E",
        b"9",
        b"8",
    ]
    .iter()
    .map(|s| s.to_vec())
    .collect();
    let trace = common::TempArtifact::new("laniusc_paths", "failure_trace", None);
    let execute = |when: Option<usize>| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"]);
        if let Some(when) = when {
            command
                .arg("-e")
                .arg(format!("inject=mmap:error=ENOMEM:when={when}"));
        }
        let output = run(command
            .arg(exe.path())
            .args(commands.iter().cloned().map(OsString::from_vec)));
        check_edits(&output, &commands, when.is_some());
        let events = std::fs::read_to_string(trace.path()).unwrap();
        if when.is_some() {
            assert!(events.contains("INJECTED") && events.contains("ENOMEM"));
        }
        freed(&events)
    };
    let allocations = execute(None);
    assert!(allocations >= 10);
    for when in 1..=allocations {
        execute(Some(when));
    }
}

#[test]
fn path_join_program_preserves_bytes_validates_before_output_and_cleans_up_failures() {
    let exe = executable("sample_programs/library/path_join.lani");
    let children: &[&[u8]] = &[
        b"file.txt",
        b"../a/./b",
        b"/absolute/../x",
        b"",
        b"\xff\nname",
    ];
    for lexical in [false, true] {
        let mut command = Command::new(exe.path());
        command
            .arg("base")
            .args(children.iter().map(|s| OsStr::from_bytes(s)));
        if lexical {
            command.arg("--lexical");
        }
        let output = run(&mut command);
        checked(&output);
        let mut expected = Vec::new();
        for child in children {
            let mut op = vec![b'1'];
            op.extend(*child);
            let joined = edit(b"base", &op).unwrap();
            expected.extend(if lexical { normalized(&joined) } else { joined });
            expected.push(0);
        }
        assert_eq!(output.stdout, expected);
    }
    for args in [vec![], vec!["base"], vec!["base", "file", "--unknown"]] {
        let output = run(Command::new(exe.path()).args(args));
        assert_eq!(output.status.code(), Some(2), "{output:?}");
        assert!(output.stdout.is_empty() && output.stderr.is_empty());
    }
    let output = run(Command::new(exe.path()).args(["--", "--lexical", "x"]));
    checked(&output);
    assert_eq!(output.stdout, b"--lexical/x\0");
    let output = run(Command::new(exe.path()).arg("--help"));
    checked(&output);
    assert_eq!(
        output.stdout,
        b"Usage: path-join [--lexical] [--] BASE CHILD... (NUL-delimited output)\n"
    );
    let args = ["--lexical", "base", "file", "../tail", "/absolute"];
    let expected = b"base/file\0tail\0/absolute\0";
    let trace = common::TempArtifact::new("laniusc_paths", "program_trace", None);
    let execute = |fault: Option<String>, status: i32| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,write"]);
        if let Some(fault) = &fault {
            command.arg("-e").arg(fault);
        }
        let output = run(command.arg(exe.path()).args(args));
        assert_eq!(output.status.code(), Some(status), "{fault:?} {output:?}");
        assert!(output.stderr.is_empty());
        if status == 0 {
            assert_eq!(output.stdout, expected);
        } else {
            assert!(expected.starts_with(&output.stdout), "{output:?}");
        }
        let events = std::fs::read_to_string(trace.path()).unwrap();
        if fault.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        let count = freed(&events);
        (count, events)
    };
    let (allocations, events) = execute(None, 0);
    assert!(allocations >= 8);
    for when in 1..=allocations {
        execute(Some(format!("inject=mmap:error=ENOMEM:when={when}")), 4);
    }
    let writes = events.lines().filter(|l| l.starts_with("write(")).count();
    for when in 1..=writes {
        execute(Some(format!("inject=write:error=EIO:when={when}")), 3);
    }
    execute(Some("inject=write:error=EINTR:when=1".into()), 0);
    execute(Some("inject=write:retval=0:when=1".into()), 3);
}

#[test]
fn large_component_batches_use_geometric_growth_and_one_normalization_buffer() {
    let exe = executable("tests/fixtures/stdlib_foundation/path_batch.lani");
    let trace = common::TempArtifact::new("laniusc_paths", "batch_trace", None);
    for count in [16_384, 262_144] {
        for mode in [0, 1] {
            let output = common::process_output_with_timeout(
                "large path batch",
                Command::new("strace")
                    .args(["-qq", "-o"])
                    .arg(trace.path())
                    .args(["-e", "trace=mmap,munmap"])
                    .arg(exe.path())
                    .args([count.to_string(), mode.to_string()]),
                std::time::Duration::from_secs(10),
            );
            checked(&output);
            assert_eq!(
                numbers(&output.stdout),
                vec![if mode == 0 { 2 * count - 1 } else { 1 }]
            );
            let allocations = freed(&std::fs::read_to_string(trace.path()).unwrap());
            assert!(
                allocations <= 24,
                "count={count} mode={mode} allocations={allocations}"
            );
        }
    }
}

#[test]
fn borrowed_and_owned_path_keys_share_component_equality_and_hashing() {
    let exe = executable("tests/fixtures/stdlib_foundation/path_collections.lani");
    let trace = common::TempArtifact::new("laniusc_paths", "collection_trace", None);
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap"])
        .arg(exe.path()));
    checked(&output);
    assert!(output.stdout.is_empty());
    assert!(freed(&std::fs::read_to_string(trace.path()).unwrap()) >= 4);
}
