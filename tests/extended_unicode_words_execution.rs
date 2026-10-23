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
    let exe = common::TempArtifact::new("laniusc_unicode_words", name, None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

fn official_cases() -> Vec<(String, Vec<usize>)> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let decoded = common::short_process_output_with_timeout(
        "decode official Unicode 17 word break tests",
        std::process::Command::new("gzip")
            .arg("-dc")
            .arg(root.join("data/unicode/17.0.0/auxiliary/WordBreakTest.txt.gz")),
    );
    assert!(decoded.status.success(), "{decoded:?}");
    let source = String::from_utf8(decoded.stdout).unwrap();
    assert!(source.starts_with("# WordBreakTest-17.0.0.txt"));
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
    assert_eq!(cases.len(), 1944, "official corpus must be complete");
    cases
}

#[test]
fn word_tables_reproduce_from_the_vendored_unicode_17_sources() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::short_process_output_with_timeout(
        "reproduce Unicode 17 word property tables",
        std::process::Command::new("python3")
            .arg(root.join("tools/unicode17/generate_words.py"))
            .arg("--check"),
    );
    assert!(output.status.success(), "{output:?}");
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn word_views_fork_positions_preserve_storage_and_reject_bad_logical_bounds() {
    let exe = executable("unicode_words_contracts");
    let output = common::short_process_output_with_timeout(
        "word cursor view contracts",
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
fn every_official_unicode_17_word_vector_and_long_contexts_execute_without_allocation() {
    let mut cases = official_cases();
    cases.extend([
        (String::new(), vec![]),
        (
            "\0\r\n\u{b}\u{c}\u{85}\u{2028}\u{2029}".to_owned(),
            vec![1, 3, 4, 5, 7, 10, 13],
        ),
        ("can't'".to_owned(), vec![5, 6]),
        ("a.b.c.".to_owned(), vec![5, 6]),
        ("1,234.5!".to_owned(), vec![7, 8]),
        ("א\"ב'".to_owned(), vec![6]),
        ("a_2カ_".to_owned(), vec![3, 7]),
        ("a_2_カ_".to_owned(), vec![8]),
        ("漢字あいう".to_owned(), vec![3, 6, 9, 12, 15]),
        (" ́ ".to_owned(), vec![3, 4]),
        ("\u{200d}🙂".to_owned(), vec![7]),
        ("\u{200d}\u{301}🙂".to_owned(), vec![5, 9]),
        ("a\u{200d}🙂".to_owned(), vec![8]),
        ("🇦\u{301}🇧🇨🇩🇪".to_owned(), vec![10, 18, 22]),
        ("\u{200e}a".to_owned(), vec![3, 4]),
        (
            "\u{10ffff}\u{e000}\u{1fc00}\u{200d}\u{1fc01}".to_owned(),
            vec![4, 7, 18],
        ),
    ]);
    let marks = "\u{301}".repeat(16000);
    let letters = format!("a{marks}b!");
    cases.push((letters.clone(), vec![letters.len() - 1, letters.len()]));
    let punctuation = format!("a:{marks}b!");
    cases.push((
        punctuation.clone(),
        vec![punctuation.len() - 1, punctuation.len()],
    ));
    let failed_lookahead = format!("a:{marks}!");
    cases.push((
        failed_lookahead.clone(),
        vec![1, failed_lookahead.len() - 1, failed_lookahead.len()],
    ));
    let initial = format!(":{marks}a");
    cases.push((initial.clone(), vec![initial.len() - 1, initial.len()]));
    let numeric = format!("1,{marks}2!");
    cases.push((numeric.clone(), vec![numeric.len() - 1, numeric.len()]));
    let hebrew = format!("א\"{marks}ב!");
    cases.push((hebrew.clone(), vec![hebrew.len() - 1, hebrew.len()]));
    // Each ignored run is looked ahead once, then consumed once. Repeating
    // punctuation candidates must not repeatedly rescan earlier context.
    let candidates = format!("{}a", format!("a:{}", "\u{301}".repeat(128)).repeat(256));
    cases.push((candidates.clone(), vec![candidates.len()]));
    let ignored = "\u{301}\u{200e}\u{200d}".repeat(4096);
    let mixed = format!("a:{ignored}b");
    cases.push((mixed.clone(), vec![mixed.len()]));
    let spaces = format!(" {ignored} ");
    cases.push((spaces.clone(), vec![spaces.len() - 1, spaces.len()]));
    let after_newline = format!("\n{ignored}a");
    cases.push((
        after_newline.clone(),
        vec![1, after_newline.len() - 1, after_newline.len()],
    ));
    let initial_ignored = format!("{ignored}a");
    cases.push((
        initial_ignored.clone(),
        vec![initial_ignored.len() - 1, initial_ignored.len()],
    ));
    let joiners = format!("🙂{}🙂!", "\u{200d}".repeat(16000));
    cases.push((joiners.clone(), vec![joiners.len() - 1, joiners.len()]));
    let regional = "🇦".repeat(8193);
    let mut regional_ends: Vec<usize> = (8..regional.len()).step_by(8).collect();
    regional_ends.push(regional.len());
    cases.push((regional, regional_ends));
    let regional_ignored = format!("🇦{ignored}🇧🇨");
    cases.push((
        regional_ignored.clone(),
        vec![regional_ignored.len() - 4, regional_ignored.len()],
    ));
    let mut payload = Vec::new();
    for (text, _) in &cases {
        payload.extend_from_slice(&(text.len() as u32).to_le_bytes());
        payload.extend_from_slice(text.as_bytes());
    }
    let exe = executable("unicode_words_input");
    let input = common::TempArtifact::new("laniusc_unicode_words", "corpus", None);
    input.write_bytes(&payload);
    let trace = common::TempArtifact::new("laniusc_unicode_words", "noalloc", None);
    let output = common::process_output_with_timeout(
        "official Unicode 17 word corpus and long contexts",
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
