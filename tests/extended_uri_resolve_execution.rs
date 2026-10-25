#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    ffi::OsStr,
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
    let exe = common::TempArtifact::new("laniusc_uri_resolve", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(command: &mut Command) -> Output {
    common::short_process_output_with_timeout("uri", command)
}
fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
#[test]
fn uri_resolution_contracts_execute_limits_ownership_bounds_and_strided_inputs() {
    let exe = executable("tests/fixtures/extended/uri_resolve_contracts.lani");
    let output = run(&mut Command::new(exe.path()));
    checked(&output, 0);
    assert!(output.stdout.is_empty());
}

fn invoke(
    exe: &common::TempArtifact,
    compose: bool,
    base: &[u8],
    references: &[Vec<u8>],
) -> Vec<Result<Vec<u8>, i32>> {
    let output = common::process_output_with_timeout(
        "URI resolution model batch",
        Command::new(exe.path())
            .arg(if compose { "1" } else { "0" })
            .arg(OsStr::from_bytes(base))
            .args(references.iter().map(|s| OsStr::from_bytes(s))),
        std::time::Duration::from_secs(10),
    );
    checked(&output, 0);
    let rows: Vec<_> = output
        .stdout
        .split(|b| *b == b'\n')
        .filter(|s| !s.is_empty())
        .map(|row| {
            if let Some(value) = row.strip_prefix(b"0 ") {
                Ok(value.to_vec())
            } else {
                Err(std::str::from_utf8(row).unwrap().parse().unwrap())
            }
        })
        .collect();
    assert_eq!(rows.len(), references.len());
    rows
}
#[test]
fn all_rfc3986_normal_and_abnormal_resolution_vectors_execute() {
    let exe = executable("tests/fixtures/extended/uri_resolve_model.lani");
    let cases = &[
        ("g:h", "g:h"),
        ("g", "http://a/b/c/g"),
        ("./g", "http://a/b/c/g"),
        ("g/", "http://a/b/c/g/"),
        ("/g", "http://a/g"),
        ("//g", "http://g"),
        ("?y", "http://a/b/c/d;p?y"),
        ("g?y", "http://a/b/c/g?y"),
        ("#s", "http://a/b/c/d;p?q#s"),
        ("g#s", "http://a/b/c/g#s"),
        ("g?y#s", "http://a/b/c/g?y#s"),
        (";x", "http://a/b/c/;x"),
        ("g;x", "http://a/b/c/g;x"),
        ("g;x?y#s", "http://a/b/c/g;x?y#s"),
        ("", "http://a/b/c/d;p?q"),
        (".", "http://a/b/c/"),
        ("./", "http://a/b/c/"),
        ("..", "http://a/b/"),
        ("../", "http://a/b/"),
        ("../g", "http://a/b/g"),
        ("../..", "http://a/"),
        ("../../", "http://a/"),
        ("../../g", "http://a/g"),
        ("../../../g", "http://a/g"),
        ("../../../../g", "http://a/g"),
        ("/./g", "http://a/g"),
        ("/../g", "http://a/g"),
        ("g.", "http://a/b/c/g."),
        (".g", "http://a/b/c/.g"),
        ("g..", "http://a/b/c/g.."),
        ("..g", "http://a/b/c/..g"),
        ("./../g", "http://a/b/g"),
        ("./g/.", "http://a/b/c/g/"),
        ("g/./h", "http://a/b/c/g/h"),
        ("g/../h", "http://a/b/c/h"),
        ("g;x=1/./y", "http://a/b/c/g;x=1/y"),
        ("g;x=1/../y", "http://a/b/c/y"),
        ("g?y/./x", "http://a/b/c/g?y/./x"),
        ("g?y/../x", "http://a/b/c/g?y/../x"),
        ("g#s/./x", "http://a/b/c/g#s/./x"),
        ("g#s/../x", "http://a/b/c/g#s/../x"),
        ("http:g", "http:g"),
    ];
    let references: Vec<_> = cases.iter().map(|(r, _)| r.as_bytes().to_vec()).collect();
    for ((reference, expected), actual) in
        cases
            .iter()
            .zip(invoke(&exe, false, b"http://a/b/c/d;p?q", &references))
    {
        assert_eq!(
            actual,
            Ok(expected.as_bytes().to_vec()),
            "reference={reference}"
        );
    }
    for base in [
        b"".as_slice(),
        b"relative/path",
        b"//host/path",
        b"x:#",
        b"http://h/#fragment",
    ] {
        assert_eq!(
            invoke(&exe, false, base, &[b"absolute:reference".to_vec()]),
            vec![Err(-1)],
            "base={base:?}"
        );
    }
}
#[test]
fn no_authority_dot_paths_follow_literal_rfc_recomposition() {
    let exe = executable("tests/fixtures/extended/uri_resolve_model.lani");
    for (base, reference, expected) in [
        ("x:/", ".//a", "x://a"),
        ("x:/", ".///a", "x:///a"),
        ("x:a", "a/..//b", "x://b"),
        ("x:/a", "/..//b", "x://b"),
        ("http://h/a", "/..//b", "http://h//b"),
    ] {
        assert_eq!(
            invoke(
                &exe,
                false,
                base.as_bytes(),
                &[reference.as_bytes().to_vec()]
            ),
            vec![Ok(expected.as_bytes().to_vec())],
            "base={base:?}, reference={reference:?}"
        );
    }
}

#[derive(Clone, Debug)]
struct Parts {
    scheme: Option<String>,
    authority: Option<String>,
    path: String,
    query: Option<String>,
    fragment: Option<String>,
}
impl Parts {
    fn bytes(&self) -> Vec<u8> {
        let mut result = String::new();
        if let Some(scheme) = &self.scheme {
            result.push_str(scheme);
            result.push(':');
        }
        if let Some(authority) = &self.authority {
            result.push_str("//");
            result.push_str(authority);
        }
        result.push_str(&self.path);
        if let Some(query) = &self.query {
            result.push('?');
            result.push_str(query);
        }
        if let Some(fragment) = &self.fragment {
            result.push('#');
            result.push_str(fragment);
        }
        result.into_bytes()
    }
}
// The reference follows the specification's two separate string buffers.
// Production instead compacts one packed owner with read/write indices.
fn remove_dots(path: &str) -> String {
    let mut input = path.to_owned();
    let mut output = String::new();
    while !input.is_empty() {
        if input.starts_with("../") {
            input.drain(..3);
        } else if input.starts_with("./") {
            input.drain(..2);
        } else if input.starts_with("/./") {
            input.replace_range(..3, "/");
        } else if input == "/." {
            input = "/".into();
        } else if input.starts_with("/../") || input == "/.." {
            let remaining = if input == "/.." {
                "".to_owned()
            } else {
                input[4..].to_owned()
            };
            input = format!("/{remaining}");
            output.truncate(output.rfind('/').unwrap_or(0));
        } else if input == "." || input == ".." {
            input.clear();
        } else {
            let start = usize::from(input.starts_with('/'));
            let end = input[start..].find('/').map_or(input.len(), |n| n + start);
            output.push_str(&input[..end]);
            input.drain(..end);
        }
    }
    output
}
fn resolve_model(base: &Parts, reference: &Parts) -> Vec<u8> {
    let mut target = reference.clone();
    if reference.scheme.is_some() {
        target.path = remove_dots(&reference.path);
    } else {
        target.scheme = base.scheme.clone();
        if reference.authority.is_some() {
            target.path = remove_dots(&reference.path);
        } else {
            target.authority = base.authority.clone();
            if reference.path.is_empty() {
                target.path = base.path.clone();
                if reference.query.is_none() {
                    target.query = base.query.clone();
                }
            } else if reference.path.starts_with('/') {
                target.path = remove_dots(&reference.path);
            } else {
                let prefix = if base.authority.is_some() && base.path.is_empty() {
                    "/"
                } else {
                    base.path.rfind('/').map_or("", |at| &base.path[..at + 1])
                };
                target.path = remove_dots(&format!("{prefix}{}", reference.path));
            }
        }
    }
    target.bytes()
}
#[test]
fn generated_resolution_and_exact_recomposition_match_independent_buffer_model() {
    let exe = executable("tests/fixtures/extended/uri_resolve_model.lani");
    let bases = [
        Parts {
            scheme: Some("http".into()),
            authority: Some("a".into()),
            path: "/b/c/d;p".into(),
            query: Some("q".into()),
            fragment: None,
        },
        Parts {
            scheme: Some("x".into()),
            authority: Some("".into()),
            path: "".into(),
            query: Some("".into()),
            fragment: None,
        },
        Parts {
            scheme: Some("x".into()),
            authority: None,
            path: "".into(),
            query: None,
            fragment: None,
        },
        Parts {
            scheme: Some("X+1-.".into()),
            authority: None,
            path: "rootless/base".into(),
            query: Some("?/:@".into()),
            fragment: None,
        },
        Parts {
            scheme: Some("x".into()),
            authority: None,
            path: "/a/./b/../c".into(),
            query: None,
            fragment: None,
        },
        Parts {
            scheme: Some("HTTP".into()),
            authority: Some("u:p@[::1]:080".into()),
            path: "/a//b/%2E/".into(),
            query: Some("%2f/../".into()),
            fragment: None,
        },
    ];
    let paths = [
        "",
        "a",
        ".",
        "..",
        "./",
        "../",
        "../../g",
        "/",
        "//a",
        ".//a",
        "/a//b/../",
        "/%2e/%2E/%2f/%2F",
        "a/..",
        "a/../..",
        "/a/.b/..g/",
        "a/./b/../c",
        "/a////../b/.",
    ];
    let mut references = Vec::new();
    for scheme in [None, Some("x"), Some("http"), Some("HTTP")] {
        for authority in [None, Some(""), Some("u:p@HOST:00080"), Some("[Vf.a:!~]:")] {
            for path in paths {
                if authority.is_some() && !path.is_empty() && !path.starts_with('/') {
                    continue;
                }
                if authority.is_none() && path.starts_with("//") {
                    continue;
                }
                for query in [None, Some(""), Some("/../?%2F")] {
                    for fragment in [None, Some(""), Some("a/./?%23")] {
                        references.push(Parts {
                            scheme: scheme.map(str::to_owned),
                            authority: authority.map(str::to_owned),
                            path: path.into(),
                            query: query.map(str::to_owned),
                            fragment: fragment.map(str::to_owned),
                        });
                    }
                }
            }
        }
    }
    let mut state = 0x3986_5214_2026_u64;
    let mut next = || {
        state = state
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        state >> 16
    };
    let segments = ["", "a", "b", ".", "..", "...", "%2e", "%2E", "%2f", "a;b=1"];
    for index in 0..512 {
        let mut path = if index % 2 == 0 {
            "/".to_owned()
        } else {
            String::new()
        };
        for part in 0..next() % 12 {
            if part > 0 {
                path.push('/');
            }
            path.push_str(segments[next() as usize % segments.len()]);
        }
        if path.starts_with("//") {
            path.insert_str(0, "/.");
        }
        references.push(Parts {
            scheme: None,
            authority: None,
            path,
            query: if index % 3 == 0 {
                Some("../?%23".into())
            } else {
                None
            },
            fragment: if index % 5 == 0 {
                Some("".into())
            } else {
                None
            },
        });
    }
    for base in bases {
        for chunk in references.chunks(64) {
            let inputs: Vec<_> = chunk.iter().map(Parts::bytes).collect();
            let resolved = invoke(&exe, false, &base.bytes(), &inputs);
            for (reference, actual) in chunk.iter().zip(resolved) {
                assert_eq!(
                    actual,
                    Ok(resolve_model(&base, reference)),
                    "base={base:?}, reference={reference:?}"
                );
            }
        }
    }
    for chunk in references.chunks(64) {
        let inputs: Vec<_> = chunk.iter().map(Parts::bytes).collect();
        for (input, actual) in inputs.iter().zip(invoke(&exe, true, b"x:", &inputs)) {
            assert_eq!(actual, Ok(input.clone()), "input={input:?}");
        }
    }
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
    assert!(live.is_empty(), "leaked owners: {events}");
    count
}
#[test]
fn each_denied_allocation_releases_workspace_and_preserves_inputs_and_prior_results() {
    let exe = executable("tests/fixtures/extended/uri_resolve_failure.lani");
    let trace = common::TempArtifact::new("laniusc_uri_resolve", "failure", None);
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
fn large_dot_paths_compact_with_fixed_allocations_and_final_output_limits() {
    let exe = executable("tests/fixtures/extended/uri_resolve_large.lani");
    let trace = common::TempArtifact::new("laniusc_uri_resolve", "large", None);
    for count in [1024, 16384, 262144] {
        let output = common::process_output_with_timeout(
            "large linear URI resolution",
            Command::new("strace")
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args([
                    "-e",
                    "trace=mmap,munmap",
                    "-e",
                    "inject=mmap:error=ENOMEM:when=4+",
                ])
                .arg(exe.path())
                .arg(count.to_string()),
            std::time::Duration::from_secs(20),
        );
        checked(&output, 0);
        assert!(output.stdout.is_empty());
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert!(
            !events.contains("INJECTED"),
            "unexpected allocation: {events}"
        );
        assert_eq!(freed(&events), 3);
    }
}
