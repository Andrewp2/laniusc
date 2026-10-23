mod common;
use std::path::PathBuf;

use laniusc_compiler::compiler::{EntrySourceRoots, compile_entry_to_x86_64_with_source_roots};
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn executable(name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(if name == "csv_table" {
        "sample_programs/library/csv_table.lani".to_owned()
    } else {
        format!("tests/fixtures/extended/{name}.lani")
    });
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
fn freed(trace: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut count = 0;
    for line in trace.lines() {
        if line.starts_with("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            if result.starts_with("0x") {
                assert!(live.insert(result.split_whitespace().next().unwrap().to_owned()));
                count += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            assert!(line.ends_with(" = 0"), "{line}");
            assert!(live.remove(tail.split(',').next().unwrap()), "{line}");
        }
    }
    assert!(live.is_empty(), "leaked allocations: {live:?}\n{trace}");
    count
}
#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn table_layout_limits_borrows_and_allocation_cleanup() {
    let exe = executable("table_contracts");
    let output = common::short_process_output_with_timeout(
        "table contracts",
        &mut std::process::Command::new(exe.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    let exe = executable("table_allocation_failure");
    let trace = common::TempArtifact::new("laniusc_table", "allocations", None);
    for when in 0..=3 {
        let mut cmd = std::process::Command::new("strace");
        cmd.args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"]);
        if when > 0 {
            cmd.arg("-e")
                .arg(format!("inject=mmap:error=ENOMEM:when={when}+"));
        }
        cmd.arg(exe.path());
        let output =
            common::short_process_output_with_timeout("table allocation failure", &mut cmd);
        assert_eq!(
            output.status.code(),
            Some(if when == 0 { 1 } else { 0 }),
            "{output:?}"
        );
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
        let events = std::fs::read_to_string(trace.path()).unwrap();
        let count = freed(&events);
        if when == 0 {
            assert_eq!(count, 3);
        } else {
            assert_eq!(count, when - 1);
            assert!(events.contains("INJECTED"));
        }
    }
}
#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn generated_tables_match_an_independent_rectangular_layout_model() {
    let exe = executable("csv_table");
    let dictionary = [
        ("", 0, 0),
        ("a", 1, 1),
        ("long", 4, 4),
        ("界", 2, 2),
        ("é", 1, 2),
        ("e\u{301}", 1, 1),
        ("🙂", 2, 2),
        ("❤\u{fe0f}", 2, 2),
        ("👩\u{200d}💻", 2, 2),
        ("Ω", 1, 2),
        ("a,b", 3, 3),
    ];
    let mut seed = 0x3159_u32;
    for case in 0..48 {
        let count = case % 7 + 1;
        let columns = case % 5 + 1;
        let bare = case % 2 == 0;
        let right = case % 3 == 0;
        let wide = case % 4 == 0;
        let mut rows = Vec::new();
        let mut widths = vec![0; columns];
        let mut source = String::new();
        for _ in 0..count {
            let mut row = Vec::new();
            for column in 0..columns {
                seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
                let item = dictionary[seed as usize % dictionary.len()];
                let width = if wide { item.2 } else { item.1 };
                widths[column] = widths[column].max(width);
                row.push((item.0, width));
                if column > 0 {
                    source.push(',');
                }
                source.push('"');
                source.push_str(item.0);
                source.push('"');
            }
            rows.push(row);
            source.push('\n');
        }
        let border = format!(
            "+{}\n",
            widths
                .iter()
                .map(|width| format!("{}+", "-".repeat(width + 2)))
                .collect::<String>()
        );
        let mut expected = String::new();
        if !bare {
            expected.push_str(&border);
        }
        for row in rows {
            if !bare {
                expected.push('|');
            }
            for (column, (text, width)) in row.iter().enumerate() {
                if !bare {
                    expected.push(' ');
                } else if column > 0 {
                    expected.push_str("  ");
                }
                if right {
                    expected.push_str(&" ".repeat(widths[column] - width));
                }
                expected.push_str(text);
                if !right {
                    expected.push_str(&" ".repeat(widths[column] - width));
                }
                if !bare {
                    expected.push_str(" |");
                }
            }
            expected.push('\n');
        }
        if !bare {
            expected.push_str(&border);
        }
        let input = common::TempArtifact::new("laniusc_table", "model", None);
        input.write_bytes(source.as_bytes());
        let mut cmd = std::process::Command::new(exe.path());
        if bare {
            cmd.arg("--bare");
        }
        if right {
            cmd.arg("--right");
        }
        if wide {
            cmd.arg("--wide");
        }
        cmd.stdin(std::process::Stdio::from(
            std::fs::File::open(input.path()).unwrap(),
        ));
        let output = common::short_process_output_with_timeout("generated table model", &mut cmd);
        assert_eq!(output.status.code(), Some(0), "case {case}: {output:?}");
        assert_eq!(output.stdout, expected.as_bytes(), "case {case}");
        assert!(output.stderr.is_empty());
    }
}
