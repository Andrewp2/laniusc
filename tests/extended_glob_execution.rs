#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    ffi::{c_char, c_int, c_void, CString, OsStr},
    os::unix::{ffi::OsStrExt, fs::PermissionsExt},
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
    .unwrap_or_else(|e| panic!("{path}: {e}"));
    let exe = common::TempArtifact::new("laniusc_glob", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(command: &mut Command) -> Output {
    common::short_process_output_with_timeout("glob", command)
}
fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn numbers(bytes: &[u8]) -> Vec<i32> {
    std::str::from_utf8(bytes)
        .unwrap()
        .split_whitespace()
        .map(|s| s.parse().unwrap())
        .collect()
}
fn freed(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut count = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            if result.starts_with("0x") {
                assert!(
                    live.insert(result.split_whitespace().next().unwrap().to_owned()),
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
    assert!(live.is_empty(), "leaked allocation: {events}");
    count
}
#[test]
fn compiled_glob_contracts_execute_errors_limits_ownership_and_scratch_bounds() {
    let exe = executable("tests/fixtures/extended/glob_contracts.lani");
    let trace = common::TempArtifact::new("laniusc_glob", "contracts", None);
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap"])
        .arg(exe.path()));
    checked(&output, 0);
    assert!(output.stdout.is_empty());
    assert!(freed(&std::fs::read_to_string(trace.path()).unwrap()) > 10);
}

// Reference only: use libc in a thread-local C locale, independent of the test
// process environment. The Lanius implementation never calls this interface.
unsafe extern "C" {
    fn fnmatch(pattern: *const c_char, input: *const c_char, flags: c_int) -> c_int;
    fn newlocale(mask: c_int, name: *const c_char, base: *mut c_void) -> *mut c_void;
    fn uselocale(locale: *mut c_void) -> *mut c_void;
    fn freelocale(locale: *mut c_void);
}
struct ReferenceLocale {
    locale: *mut c_void,
    previous: *mut c_void,
}
impl ReferenceLocale {
    fn new() -> Self {
        // glibc locale.h: LC_CTYPE=0, LC_COLLATE=3.
        let locale = unsafe {
            newlocale(
                (1 << 0) | (1 << 3),
                b"C\0".as_ptr().cast(),
                std::ptr::null_mut(),
            )
        };
        assert!(!locale.is_null());
        let previous = unsafe { uselocale(locale) };
        assert!(!previous.is_null());
        Self { locale, previous }
    }
    fn matches(&self, pattern: &[u8], input: &[u8], flags: i32) -> bool {
        let pattern = CString::new(pattern).unwrap();
        let input = CString::new(input).unwrap();
        let result = unsafe { fnmatch(pattern.as_ptr(), input.as_ptr(), flags) };
        assert!(result == 0 || result == 1);
        result == 0
    }
}
impl Drop for ReferenceLocale {
    fn drop(&mut self) {
        unsafe {
            uselocale(self.previous);
            freelocale(self.locale);
        }
    }
}
fn invoke(
    exe: &common::TempArtifact,
    pattern: &[u8],
    candidates: &[Vec<u8>],
    flags: i32,
) -> Vec<i32> {
    let output = run(Command::new(exe.path())
        .arg(flags.to_string())
        .arg(OsStr::from_bytes(pattern))
        .args(candidates.iter().map(|s| OsStr::from_bytes(s))));
    checked(&output, 0);
    let row = numbers(&output.stdout);
    assert_eq!(
        row[0], 0,
        "compile pattern={pattern:?}, flags={flags}, row={row:?}"
    );
    assert_eq!(row.len(), candidates.len() + 2);
    row[2..].to_vec()
}
#[test]
fn byte_globs_match_libc_in_c_locale_across_flags_classes_and_generated_patterns() {
    let reference = ReferenceLocale::new();
    let exe = executable("tests/fixtures/extended/glob_model.lani");
    let flags: Vec<i32> = (0..8).flat_map(|f| [f, f | 16]).collect();
    let patterns: &[&[u8]] = &[
        b"",
        b"*",
        b"?",
        b"**",
        b"***",
        b"*a*b",
        b"a*b*c",
        b"a/*",
        b"*/b",
        b"*.*",
        b".*",
        b"a/*.*",
        b"[.]x",
        b"[ab]",
        b"[!ab]",
        b"[^ab]",
        b"[a-z]",
        b"[A-z]",
        b"[-a]",
        b"[a-]",
        b"[]a]",
        b"[!]]",
        b"[--0]",
        b"a\\?",
        b"\\.*",
        b"\\*",
        b"[\\]]",
        b"[\\a]",
        b"[a-b-c]",
        b"[\x80-\xff]",
        b"\xff*",
        b"[[:upper:]a]",
        b"[A[:lower:]]",
        b"[[:space:][:digit:]]",
    ];
    let candidates: Vec<Vec<u8>> = [
        b"".as_slice(),
        b"a",
        b"A",
        b"b",
        b"c",
        b"z",
        b"Z",
        b"0",
        b"-",
        b"/",
        b"//",
        b".",
        b".x",
        b"x.x",
        b"abc",
        b"a/b",
        b"a/.x",
        b"a/b/c",
        b"a?",
        b"*",
        b"?",
        b"\\",
        b"]",
        b"[",
        b"\n",
        b" ",
        b"\xff",
        b"\x80",
        b"x\xff",
    ]
    .into_iter()
    .map(|s| s.to_vec())
    .collect();
    for pattern in patterns {
        for &flags in &flags {
            let actual = invoke(&exe, pattern, &candidates, flags);
            for (input, result) in candidates.iter().zip(actual) {
                assert_eq!(
                    result,
                    i32::from(reference.matches(pattern, input, flags)),
                    "pattern={pattern:?} input={input:?} flags={flags}"
                );
            }
        }
    }
    let all_bytes: Vec<Vec<u8>> = (1..=255).map(|v| vec![v as u8]).collect();
    for name in [
        "alnum", "alpha", "blank", "cntrl", "digit", "graph", "lower", "print", "punct", "space",
        "upper", "xdigit",
    ] {
        for flags in [0, 1 | 4, 16, 1 | 4 | 16] {
            let pattern = format!("[[:{name}:]]").into_bytes();
            let actual = invoke(&exe, &pattern, &all_bytes, flags);
            for (input, result) in all_bytes.iter().zip(actual) {
                assert_eq!(
                    result,
                    i32::from(reference.matches(&pattern, input, flags)),
                    "class={name} input={input:?} flags={flags}"
                );
            }
        }
    }
    let mut state = 0x610b2026_10231234_u64;
    let mut next = || {
        state = state
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        state
    };
    let atoms: &[&[u8]] = &[
        b"a",
        b"A",
        b"/",
        b".",
        b"*",
        b"?",
        b"[ab]",
        b"[!b]",
        b"[a-c]",
        b"[A-Z]",
        b"[[:digit:]]",
        b"\\?",
        b"\\*",
        b"\xff",
    ];
    let alphabet = b"aAbc09./*?\xff";
    for case in 0..256 {
        let mut pattern = Vec::new();
        for _ in 0..next() % 10 {
            pattern.extend(atoms[(next() % atoms.len() as u64) as usize]);
        }
        let mut inputs = vec![pattern.clone(), Vec::new()];
        for _ in 0..24 {
            let mut input = Vec::new();
            for _ in 0..next() % 24 {
                input.push(alphabet[(next() % alphabet.len() as u64) as usize]);
            }
            inputs.push(input);
        }
        let flags = flags[(next() % flags.len() as u64) as usize];
        let actual = invoke(&exe, &pattern, &inputs, flags);
        for (input, result) in inputs.iter().zip(actual) {
            assert_eq!(result,i32::from(reference.matches(&pattern,input,flags)),"seed=0x610b202610231234 case={case} pattern={pattern:?} input={input:?} flags={flags}");
        }
    }
}
#[test]
fn recursive_components_preserve_whole_path_and_hidden_component_rules() {
    let exe = executable("tests/fixtures/extended/glob_model.lani");
    let cases: &[(&[u8], &[u8], bool)] = &[
        (b"**/a", b"a", true),
        (b"**/a", b"x/y/a", true),
        (b"**/a", b"/a", true),
        (b"**/a", b".x/a", false),
        (b"a/**/b", b"a/b", true),
        (b"a/**/b", b"a//b", true),
        (b"a/**/b", b"a/x/y/b", true),
        (b"a/**/b", b"a/.x/b", false),
        (b"a/**", b"a/", true),
        (b"a/**", b"a", false),
        (b"a/**", b"a/x/y", true),
        (b"**", b"", true),
        (b"**", b"a/b", true),
        (b"**", b".a", false),
        (b"**/.*", b".a", true),
        (b"**/.*", b"a/.b", true),
        (b"**/.x/**", b"a/.x/b", true),
        (b"**/.x/**", b".a/.x/b", false),
        (b"a/***/b", b"a/b", false),
        (b"a/***/b", b"a/x/y/b", false),
        (b"a/***/b", b"a/x/b", true),
        (b"a/**b/c", b"a/x/b/c", false),
        (b"a/**b/c", b"a/xxb/c", true),
        (b"**/**/x", b"x", true),
        (b"**/**/x", b"a/b/x", true),
        (b"\\*\\*", b"**", true),
        (b"**\\/a", b"a", true),
        (b"**\\/a", b"x/y/a", true),
        (b"**\\/a", b".x/a", false),
        (b"a\\/**\\/b", b"a/b", true),
        (b"a\\/**\\/b", b"a/x/y/b", true),
    ];
    for &(pattern, input, expected) in cases {
        assert_eq!(
            invoke(&exe, pattern, &[input.to_vec()], 1 | 4 | 256),
            vec![i32::from(expected)],
            "{pattern:?} {input:?}"
        );
    }
    assert_eq!(invoke(&exe, b"**/x", &[b".a/x".to_vec()], 1 | 256), vec![1]);
    assert_eq!(invoke(&exe, b"**/x", &[b"x".to_vec()], 1 | 4), vec![0]);
    // A quoted separator is still the same literal byte and component
    // boundary. This property applies before, between and after globstars.
    let pairs: &[(&[u8], &[u8])] = &[
        (b"**/a", b"**\\/a"),
        (b"a/**/b", b"a\\/**\\/b"),
        (b"**/**/x", b"**\\/**\\/x"),
        (b"a/**", b"a\\/**"),
        (b"**/.x/**", b"**\\/.x\\/**"),
    ];
    let candidates: Vec<Vec<u8>> = [
        b"".as_slice(),
        b"a",
        b"A",
        b"x/y/a",
        b"x/y/A",
        b".x/a",
        b"a/b",
        b"a/x/y/b",
        b"a/.x/b",
        b"x",
        b"a/x",
        b"a/",
        b"a",
        b".x/",
        b"a/.x/y",
        b".a/.x/b",
    ]
    .into_iter()
    .map(|s| s.to_vec())
    .collect();
    for &(plain, quoted) in pairs {
        for flags in [1, 5, 17, 21] {
            assert_eq!(
                invoke(&exe, plain, &candidates, flags | 256),
                invoke(&exe, quoted, &candidates, flags | 256),
                "plain={plain:?} quoted={quoted:?} flags={flags}"
            );
        }
    }
    assert_eq!(
        invoke(
            &exe,
            b"**\\/x",
            &[b"x".to_vec(), b"a/x".to_vec(), b"a\\/x".to_vec()],
            1 | 2 | 4 | 256
        ),
        vec![0, 0, 1]
    );
}

fn recursive_reference(
    reference: &ReferenceLocale,
    pattern: &[u8],
    input: &[u8],
    flags: i32,
) -> bool {
    fn walk(reference: &ReferenceLocale, p: &[&[u8]], s: &[&[u8]], flags: i32) -> bool {
        if p.is_empty() {
            return s.is_empty();
        }
        if p[0] == b"**" {
            if p.len() == 1 {
                return s
                    .iter()
                    .all(|part| flags & 4 == 0 || !part.starts_with(b"."));
            }
            if walk(reference, &p[1..], s, flags) {
                return true;
            }
            for consumed in 0..s.len().saturating_sub(1) {
                if flags & 4 != 0 && s[consumed].starts_with(b".") {
                    break;
                }
                if walk(reference, &p[1..], &s[consumed + 1..], flags) {
                    return true;
                }
            }
            false
        } else {
            !s.is_empty()
                && reference.matches(p[0], s[0], flags & !1)
                && (p.len() == 1 || s.len() > 1)
                && walk(reference, &p[1..], &s[1..], flags)
        }
    }
    walk(
        reference,
        &pattern.split(|b| *b == b'/').collect::<Vec<_>>(),
        &input.split(|b| *b == b'/').collect::<Vec<_>>(),
        flags,
    )
}
#[test]
fn generated_recursive_patterns_match_independent_component_model() {
    let reference = ReferenceLocale::new();
    let exe = executable("tests/fixtures/extended/glob_model.lani");
    let patterns: &[&[u8]] = &[
        b"", b"**", b"***", b"*", b"?", b"a", b"a*", b"A", b".a", b"*.txt", b"[ab]",
    ];
    let parts: &[&[u8]] = &[
        b"",
        b"a",
        b"A",
        b"b",
        b"aa",
        b"file.txt",
        b".a",
        b"..",
        b"\xff",
    ];
    let mut state = 0x610b57a2_20261023_u64;
    let mut next = || {
        state = state
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        state
    };
    for case in 0..512 {
        let mut pattern_parts = Vec::new();
        for _ in 0..1 + next() % 6 {
            pattern_parts.push(patterns[(next() % patterns.len() as u64) as usize]);
        }
        let pattern = pattern_parts.join(&b'/');
        let mut candidates = vec![Vec::new(), pattern.clone()];
        for _ in 0..16 {
            let mut pieces = Vec::new();
            for _ in 0..1 + next() % 6 {
                pieces.push(parts[(next() % parts.len() as u64) as usize]);
            }
            candidates.push(pieces.join(&b'/'));
        }
        // The LCG's low bit alternates; taking consecutive low bits would
        // exercise only two of the four independent dot/case combinations.
        let flags = [1, 5, 17, 21][case % 4];
        let actual = invoke(&exe, &pattern, &candidates, flags | 256);
        for (input, result) in candidates.iter().zip(actual) {
            assert_eq!(
                result,
                i32::from(recursive_reference(&reference, &pattern, input, flags)),
                "case={case} pattern={pattern:?} input={input:?} flags={flags}"
            );
        }
    }
}
#[test]
fn denied_glob_allocations_release_partial_owners_and_preserve_live_patterns() {
    let exe = executable("tests/fixtures/extended/glob_failure.lani");
    let trace = common::TempArtifact::new("laniusc_glob", "failure", None);
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
        let output = run(command.arg(exe.path()));
        checked(&output, if when.is_some() { 4 } else { 0 });
        assert!(output.stdout.is_empty());
        let events = std::fs::read_to_string(trace.path()).unwrap();
        if when.is_some() {
            assert!(events.contains("INJECTED") && events.contains("ENOMEM"));
        }
        freed(&events)
    };
    let allocations = execute(None);
    assert_eq!(allocations, 4);
    for when in 1..=allocations {
        execute(Some(when));
    }
}
#[test]
fn adversarial_and_repeated_matches_use_fixed_storage_and_bounded_work() {
    let exe = executable("tests/fixtures/extended/glob_batch.lani");
    let trace = common::TempArtifact::new("laniusc_glob", "batch", None);
    for (count, mode) in [(1024, 0), (16383, 0), (4096, 1), (65536, 1)] {
        let output = common::process_output_with_timeout(
            "large glob batch",
            Command::new("strace")
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args([
                    "-e",
                    "trace=mmap,munmap",
                    "-e",
                    "inject=mmap:error=ENOMEM:when=3+",
                ])
                .arg(exe.path())
                .args([count.to_string(), mode.to_string()]),
            std::time::Duration::from_secs(20),
        );
        checked(&output, 0);
        assert_eq!(
            numbers(&output.stdout),
            vec![if mode == 0 { 0 } else { count }]
        );
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert_eq!(freed(&events), 2);
        assert!(
            !events.contains("INJECTED"),
            "matching tried to allocate: {events}"
        );
    }
}
