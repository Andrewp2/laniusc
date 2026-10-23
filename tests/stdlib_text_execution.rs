mod common;
use laniusc_compiler::compiler::{compile_entry_to_x86_64_with_source_roots, EntrySourceRoots};

fn executable(name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
    let roots = EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_roots(&entry, &roots))
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let file = common::TempArtifact::new("laniusc_text", name, None);
    file.write_bytes(&bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn text_views_execute_with_stack_packed_owned_and_hash_map_storage() {
    let exe = executable("core_text");
    let output = common::short_process_output_with_timeout(
        "text contracts",
        &mut std::process::Command::new(exe.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn physical_text_view_overclaims_trigger_native_slice_bounds() {
    let exe = executable("core_text_bounds");
    let output = common::short_process_output_with_timeout(
        "text physical bounds",
        &mut std::process::Command::new(exe.path()),
    );
    assert_eq!(output.status.code(), Some(101), "{output:?}");
}

fn field(out: &mut Vec<u8>, value: &str) {
    out.extend_from_slice(format!("{}:", value.len()).as_bytes());
    out.extend_from_slice(value.as_bytes());
    out.push(b'\n');
}
fn reference(text: &str, separator: &str) -> Vec<u8> {
    let hash = text.bytes().fold(2166136261_u32, |h, b| {
        (h ^ u32::from(b)).wrapping_mul(16777619)
    });
    let mut out = format!("{} {} {hash}\n", text.len(), text.chars().count()).into_bytes();
    for (offset, ch) in text.char_indices() {
        out.extend_from_slice(format!("{offset}:{}\n", ch as u32).as_bytes());
    }
    out.extend_from_slice(b"|\n");
    for part in text.split(separator) {
        field(&mut out, part);
    }
    out.extend_from_slice(b"|\n");
    field(
        &mut out,
        text.trim_matches(|c: char| matches!(c, ' ' | '\t' | '\n' | '\r' | '\x0b' | '\x0c')),
    );
    out.extend_from_slice(
        format!(
            "{} {}\n",
            text.find(separator).map_or(-1, |n| n as i32),
            text.rfind(separator).map_or(-1, |n| n as i32)
        )
        .as_bytes(),
    );
    for offset in 0..=text.len() {
        out.push(if text.is_char_boundary(offset) {
            b'1'
        } else {
            b'0'
        });
    }
    out.push(b'\n');
    out
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn text_validation_search_splits_and_scalars_match_reference_models() {
    let exe = executable("text_input");
    let input = common::TempArtifact::new("laniusc_text", "input", None);
    let check = |bytes: &[u8], separator: &[u8]| {
        assert!(separator.len() <= 255);
        let mut payload = vec![separator.len() as u8];
        payload.extend_from_slice(separator);
        payload.extend_from_slice(bytes);
        input.write_bytes(&payload);
        let output = common::short_process_output_with_timeout(
            "text input",
            std::process::Command::new(exe.path()).stdin(std::process::Stdio::from(
                std::fs::File::open(input.path()).unwrap(),
            )),
        );
        let (status, expected) = match std::str::from_utf8(bytes) {
            Err(error) => (2, error.valid_up_to().to_string().into_bytes()),
            Ok(text) => match std::str::from_utf8(separator) {
                Err(error) => (3, error.valid_up_to().to_string().into_bytes()),
                Ok(separator) => (0, reference(text, separator)),
            },
        };
        assert_eq!(
            output.status.code(),
            Some(status),
            "bytes={bytes:?}, separator={separator:?}: {output:?}"
        );
        assert_eq!(
            output.stdout, expected,
            "bytes={bytes:?}, separator={separator:?}"
        );
        assert!(output.stderr.is_empty(), "{output:?}");
    };
    for text in [
        "",
        "a",
        ",a,,b,",
        "aaaaa",
        "é🙂é🙂",
        "\0x\0",
        " \t\r\n\x0b\x0c",
        "\u{a0} x \u{a0}",
        "e\u{301}é",
        "\u{feff}\u{10ffff}\u{ffff}",
    ] {
        for separator in ["", ",", "aa", "é🙂", "\0"] {
            check(text.as_bytes(), separator.as_bytes());
        }
    }
    // Reproducible mixtures include scalar-width boundaries, combining marks,
    // controls, noncharacters and a BOM. None is silently normalized/dropped.
    let alphabet = [
        '\0',
        'a',
        'b',
        ',',
        ' ',
        '\t',
        '\n',
        '\u{7f}',
        '\u{80}',
        '\u{7ff}',
        '\u{800}',
        '\u{d7ff}',
        '\u{e000}',
        '\u{ffff}',
        '\u{10000}',
        '\u{10ffff}',
        'é',
        '🙂',
        '\u{301}',
    ];
    let mut seed = 0x7e87_2026_u32;
    let mut next = || {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        seed
    };
    for case in 0..96 {
        let mut text = String::new();
        for _ in 0..(next() % 48) {
            text.push(alphabet[next() as usize % alphabet.len()]);
        }
        let separator = if case % 3 == 0 {
            String::new()
        } else {
            let chars: Vec<char> = text.chars().collect();
            if chars.is_empty() {
                "x".into()
            } else {
                let start = next() as usize % chars.len();
                chars[start..(start + 2).min(chars.len())].iter().collect()
            }
        };
        check(text.as_bytes(), separator.as_bytes());
    }
    for malformed in [
        &b"\x80"[..],
        b"\xc0\x80",
        b"\xc1\xbf",
        b"\xc2",
        b"\xc2x",
        b"\xe0\x9f\xbf",
        b"\xed\xa0\x80",
        b"\xed\xbf\xbf",
        b"\xf0\x8f\xbf\xbf",
        b"\xf4\x90\x80\x80",
        b"\xf5\x80\x80\x80",
        b"\xff",
        b"\xe2\x82",
        b"\xf0\x9f\x99",
    ] {
        let mut bytes = "Aé".as_bytes().to_vec();
        bytes.extend_from_slice(malformed);
        check(&bytes, b",");
        check(b"valid", &bytes);
    }
    for _ in 0..96 {
        let mut bytes = Vec::new();
        for _ in 0..(next() % 12 + 1) {
            bytes.push((next() >> 24) as u8);
        }
        check(&bytes, b",");
    }
}

fn assert_freed(trace: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut allocations = 0;
    for line in trace.lines() {
        if line.starts_with("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            if result.starts_with("0x") {
                assert!(
                    live.insert(result.split_whitespace().next().unwrap().to_owned()),
                    "{line}"
                );
                allocations += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            assert!(
                line.ends_with(" = 0") && live.remove(tail.split(',').next().unwrap()),
                "{line}"
            );
        }
    }
    assert!(live.is_empty(), "leaked: {live:?}\n{trace}");
    allocations
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn copying_and_appending_borrowed_text_preserve_owners_on_allocation_failure() {
    let exe = executable("alloc_text_failure");
    let trace = common::TempArtifact::new("laniusc_text", "trace", None);
    let run = |when: Option<usize>| {
        let mut command = std::process::Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"]);
        if let Some(n) = when {
            command
                .arg("-e")
                .arg(format!("inject=mmap:error=ENOMEM:when={n}+"));
        }
        command.arg(exe.path());
        let output =
            common::short_process_output_with_timeout("text allocation failure", &mut command);
        let events = std::fs::read_to_string(trace.path()).unwrap();
        if when.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        let count = assert_freed(&events);
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
        assert_eq!(
            output.status.code(),
            Some(if when.is_some() { 0 } else { 1 }),
            "{when:?}: {output:?}"
        );
        count
    };
    let count = run(None);
    assert!(count > 0);
    for when in 1..=count {
        run(Some(when));
    }
}
