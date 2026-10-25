mod common;
use std::path::PathBuf;

use laniusc_compiler::compiler::{EntrySourceRoots, compile_entry_to_x86_64_with_source_roots};

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn executable(name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/extended/{name}.lani"));
    let roots = EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_roots(&entry, &roots))
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let exe = common::TempArtifact::new("laniusc_terminal", name, None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn decoded(name: &str) -> String {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::short_process_output_with_timeout(
        "Unicode 17 source",
        std::process::Command::new("gzip")
            .arg("-dc")
            .arg(root.join("data/unicode/17.0.0").join(name)),
    );
    assert!(output.status.success(), "{output:?}");
    String::from_utf8(output.stdout).unwrap()
}
#[test]
fn terminal_data_reproduces_from_pinned_unicode_17_sources() {
    let output = common::short_process_output_with_timeout(
        "terminal data reproducibility",
        std::process::Command::new("python3")
            .arg(
                PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                    .join("tools/unicode17/generate_terminal.py"),
            )
            .arg("--check"),
    );
    assert!(output.status.success(), "{output:?}");
}
#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn width_policy_vectors_unicode_property_intervals_and_long_clusters_allocate_nothing() {
    // Reference scalar policy built independently from official property files.
    let mut narrow = vec![1i32; 0x110000];
    let mut wide = narrow.clone();
    let mut controls = vec![false; 0x110000];
    let mut points = std::collections::BTreeSet::new();
    for line in decoded("terminal-EastAsianWidth.txt.gz").lines() {
        let body = line.split('#').next().unwrap().trim();
        if body.is_empty() {
            continue;
        }
        let (span, kind) = body.split_once(';').unwrap();
        let ends: Vec<_> = span
            .trim()
            .split("..")
            .map(|x| u32::from_str_radix(x, 16).unwrap())
            .collect();
        let a = ends[0];
        let b = *ends.last().unwrap();
        for cp in a..=b {
            if matches!(kind.trim(), "W" | "F") {
                narrow[cp as usize] = 2;
                wide[cp as usize] = 2;
            }
            if kind.trim() == "A" {
                wide[cp as usize] = 2;
            }
        }
        points.extend([a, b, a + (b - a) / 2]);
    }
    let mut zero = vec![false; 0x110000];
    let mut pending = 0;
    for line in decoded("UnicodeData.txt.gz").lines() {
        let f: Vec<_> = line.split(';').collect();
        let cp = u32::from_str_radix(f[0], 16).unwrap();
        if f[1].ends_with(", First>") {
            pending = cp;
            continue;
        }
        let a = if f[1].ends_with(", Last>") {
            pending
        } else {
            cp
        };
        for cp in a..=cp {
            if f[2].starts_with('M') || f[2] == "Cf" {
                zero[cp as usize] = true;
            }
            if matches!(f[2], "Cc" | "Zl" | "Zp") {
                controls[cp as usize] = true;
            }
        }
    }
    for (file, property) in [
        (
            "DerivedCoreProperties.txt.gz",
            "Default_Ignorable_Code_Point",
        ),
        ("PropList.txt.gz", "Bidi_Control"),
        ("emoji/emoji-data.txt.gz", "Emoji_Modifier"),
        ("auxiliary/GraphemeBreakProperty.txt.gz", "V"),
        ("auxiliary/GraphemeBreakProperty.txt.gz", "T"),
    ] {
        for line in decoded(file).lines() {
            let body = line.split('#').next().unwrap().trim();
            if body.is_empty() {
                continue;
            }
            let f: Vec<_> = body.split(';').map(str::trim).collect();
            if f[1] != property {
                continue;
            }
            let ends: Vec<_> = f[0]
                .split("..")
                .map(|x| u32::from_str_radix(x, 16).unwrap())
                .collect();
            for cp in ends[0]..=*ends.last().unwrap() {
                if property == "Bidi_Control" {
                    controls[cp as usize] = true;
                } else {
                    zero[cp as usize] = true;
                }
            }
            points.extend([ends[0], *ends.last().unwrap()]);
        }
    }
    let mut cases: Vec<(Vec<u8>, [i32; 4])> = Vec::new();
    for cp in points {
        if let Some(ch) = char::from_u32(cp) {
            let result = if controls[cp as usize] {
                [-1000000; 4]
            } else {
                let n = if zero[cp as usize] {
                    0
                } else {
                    narrow[cp as usize]
                };
                let w = if zero[cp as usize] {
                    0
                } else {
                    wide[cp as usize]
                };
                [n, w, n, w]
            };
            cases.push((ch.to_string().into_bytes(), result));
        }
    }
    for (value, widths) in [
        ("", [0, 0, 0, 0]),
        ("e\u{301}", [1, 1, 1, 1]),
        ("\u{301}", [0, 0, 0, 0]),
        ("東京", [4, 4, 4, 4]),
        ("🙂", [2, 2, 2, 2]),
        ("❤", [1, 1, 1, 1]),
        ("❤\u{fe0f}", [2, 2, 1, 1]),
        ("🙂\u{fe0e}", [2, 2, 2, 2]),
        ("⌚\u{fe0e}", [1, 1, 2, 2]),
        ("🇺🇸", [2, 2, 2, 2]),
        ("🇺", [1, 1, 1, 1]),
        ("👩\u{200d}💻", [2, 2, 4, 4]),
        ("👩🏽\u{200d}💻", [2, 2, 4, 4]),
        ("1\u{fe0f}\u{20e3}", [2, 2, 1, 1]),
        ("a\u{200d}b", [2, 2, 2, 2]),
        ("क\u{94d}क", [1, 1, 2, 2]),
        ("\u{ad}", [0, 0, 0, 0]),
        ("Ω", [1, 2, 1, 2]),
        ("a\t", [-1000001; 4]),
        ("a\n", [-1000001; 4]),
        ("\u{1b}[31m", [-1000000; 4]),
        ("a\u{9b}31m", [-1000001; 4]),
        ("a\u{202e}", [-1000001; 4]),
    ] {
        cases.push((value.as_bytes().to_vec(), widths));
    }
    cases.push((vec![0xf0, 0x80, 0x80, 0x80], [-2000000; 4]));
    cases.push((b"a\xff".to_vec(), [-2000001; 4]));
    cases.push((
        format!("a{}b", "\u{301}".repeat(16000)).into_bytes(),
        [2, 2, 2, 2],
    ));
    cases.push((
        format!("🙂{}", "\u{200d}🙂".repeat(8192)).into_bytes(),
        [2, 2, 16386, 16386],
    ));
    let mut payload = Vec::new();
    for (bytes, _) in &cases {
        payload.extend_from_slice(&(bytes.len() as u32).to_le_bytes());
        payload.extend(bytes);
    }
    let input = common::TempArtifact::new("laniusc_terminal", "corpus", None);
    input.write_bytes(&payload);
    let trace = common::TempArtifact::new("laniusc_terminal", "noalloc", None);
    let exe = executable("terminal_input");
    let output = common::process_output_with_timeout(
        "terminal width corpus",
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
        std::time::Duration::from_secs(30),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let lines: Vec<_> = std::str::from_utf8(&output.stdout)
        .unwrap()
        .lines()
        .collect();
    assert_eq!(lines.len(), cases.len());
    for (index, ((bytes, expected), line)) in cases.iter().zip(lines).enumerate() {
        let actual: Vec<i32> = line
            .split(',')
            .filter(|s| !s.is_empty())
            .map(|s| s.parse().unwrap())
            .collect();
        assert_eq!(actual, *expected, "vector {index}: {bytes:?}");
    }
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
    let contracts = executable("terminal_contracts");
    let output = common::short_process_output_with_timeout(
        "terminal bounds and budgets",
        &mut std::process::Command::new(contracts.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
}
