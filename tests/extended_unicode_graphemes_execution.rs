mod common;

use std::path::PathBuf;

use laniusc_compiler::compiler::{EntrySourceRoots, compile_entry_to_x86_64_with_source_roots};

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn executable(name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/extended_library/{name}.lani"));
    let roots = EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_roots(&entry, &roots))
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let exe = common::TempArtifact::new("laniusc_unicode_graphemes", name, None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

fn official_cases() -> Vec<(String, Vec<usize>)> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let decoded = common::short_process_output_with_timeout(
        "decode official Unicode 17 grapheme break tests",
        std::process::Command::new("gzip")
            .arg("-dc")
            .arg(root.join("data/unicode/17.0.0/auxiliary/GraphemeBreakTest.txt.gz")),
    );
    assert!(decoded.status.success(), "{decoded:?}");
    let source = String::from_utf8(decoded.stdout).unwrap();
    assert!(source.starts_with("# GraphemeBreakTest-17.0.0.txt"));
    let mut cases = Vec::new();
    for line in source.lines() {
        let body = line.split('#').next().unwrap().trim();
        if body.is_empty() {
            continue;
        }
        let mut text = String::new();
        let mut ends = Vec::new();
        for token in body.split_whitespace() {
            match token {
                "÷" if !text.is_empty() => ends.push(text.len()),
                "÷" | "×" => {}
                _ => text.push(char::from_u32(u32::from_str_radix(token, 16).unwrap()).unwrap()),
            }
        }
        assert_eq!(ends.last().copied(), Some(text.len()));
        cases.push((text, ends));
    }
    assert_eq!(cases.len(), 766, "official corpus must be complete");
    cases
}

#[test]
fn grapheme_tables_reproduce_from_the_vendored_unicode_17_sources() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::short_process_output_with_timeout(
        "reproduce Unicode 17 grapheme property tables",
        std::process::Command::new("python3")
            .arg(root.join("tools/unicode17/generate_graphemes.py"))
            .arg("--check"),
    );
    assert!(output.status.success(), "{output:?}");
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn grapheme_views_fork_positions_preserve_storage_and_reject_bad_logical_bounds() {
    let exe = executable("unicode_graphemes_contracts");
    let output = common::short_process_output_with_timeout(
        "grapheme cursor view contracts",
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
fn every_official_unicode_17_grapheme_vector_and_long_contexts_execute_without_allocation() {
    let mut cases = official_cases();
    cases.extend([
        (String::new(), vec![]),
        (
            "\0\r\n\u{b}\u{c}\u{85}\u{2028}\u{2029}".to_owned(),
            vec![1, 3, 4, 5, 7, 10, 13],
        ),
        ("a\u{301}\u{200d}b".to_owned(), vec![6, 7]),
        ("\u{600}\u{903}x".to_owned(), vec![5, 6]),
        (
            "\u{1100}\u{1161}\u{11a8}\u{ac00}\u{11a8}".to_owned(),
            vec![9, 15],
        ),
        ("\u{16d63}\u{16d67}\u{16d6a}".to_owned(), vec![12]),
        // RI parity counts only an immediately preceding RI run.
        ("🇦🇧\u{301}🇨🇩🇪".to_owned(), vec![10, 18, 22]),
        // GB11 requires Extend before ZWJ; Extend after it breaks its context.
        ("🙂\u{200d}\u{301}🙂".to_owned(), vec![9, 13]),
        ("a\u{200d}🙂".to_owned(), vec![4, 8]),
        // GB9c needs a consonant prefix and at least one linker.
        ("क\u{94d}\u{200d}क".to_owned(), vec![12]),
        ("क\u{93c}क".to_owned(), vec![6, 9]),
        ("\u{94d}क".to_owned(), vec![3, 6]),
        // Unassigned EP ranges, noncharacters and private use retain scalars.
        (
            "\u{1fc00}\u{200d}\u{1fc01}\u{10ffff}\u{e000}".to_owned(),
            vec![11, 15, 18],
        ),
    ]);
    let marks = "\u{301}".repeat(16000);
    let text = format!("a{marks}b");
    cases.push((text.clone(), vec![text.len() - 1, text.len()]));
    let emoji = format!("🙂{marks}\u{200d}🙂{marks}\u{200d}🙂!");
    cases.push((emoji.clone(), vec![emoji.len() - 1, emoji.len()]));
    let joined = format!("🙂{}!", "\u{200d}🙂".repeat(8192));
    cases.push((joined.clone(), vec![joined.len() - 1, joined.len()]));
    // Long ZWJ runs attach under GB9 but cannot act as an EP prefix for GB11.
    let joiners = format!("🙂{}🙂", "\u{200d}".repeat(16000));
    cases.push((joiners.clone(), vec![joiners.len() - 4, joiners.len()]));
    let indic = format!(
        "क{}\u{94d}{}क!",
        "\u{93c}".repeat(8000),
        "\u{93c}".repeat(8000)
    );
    cases.push((indic.clone(), vec![indic.len() - 1, indic.len()]));
    let consonants = format!("क{}!", "\u{94d}क".repeat(8192));
    cases.push((
        consonants.clone(),
        vec![consonants.len() - 1, consonants.len()],
    ));
    let regional = "🇦".repeat(8193);
    let mut regional_ends: Vec<usize> = (8..regional.len()).step_by(8).collect();
    regional_ends.push(regional.len());
    cases.push((regional, regional_ends));
    let mut payload = Vec::new();
    for (text, _) in &cases {
        payload.extend_from_slice(&(text.len() as u32).to_le_bytes());
        payload.extend_from_slice(text.as_bytes());
    }
    let exe = executable("unicode_graphemes_input");
    let input = common::TempArtifact::new("laniusc_unicode_graphemes", "corpus", None);
    input.write_bytes(&payload);
    let trace = common::TempArtifact::new("laniusc_unicode_graphemes", "noalloc", None);
    let output = common::process_output_with_timeout(
        "official Unicode 17 grapheme corpus and long contexts",
        std::process::Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,munmap",
                "-e",
                "inject=mmap:error=ENOMEM:when=1+",
            ])
            .arg(exe.path())
            .stdin(std::process::Stdio::from(
                std::fs::File::open(input.path()).unwrap(),
            )),
        std::time::Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let actual = std::str::from_utf8(&output.stdout).unwrap();
    let lines: Vec<_> = actual.lines().collect();
    assert_eq!(lines.len(), cases.len());
    for (index, ((text, expected), actual)) in cases.iter().zip(lines).enumerate() {
        let ends: Vec<usize> = actual
            .split(',')
            .filter(|part| !part.is_empty())
            .map(|part| part.parse().unwrap())
            .collect();
        assert_eq!(&ends, expected, "vector {index}: {text:?}");
    }
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(
        events.is_empty(),
        "segmentation allocated heap storage: {events}"
    );
}
