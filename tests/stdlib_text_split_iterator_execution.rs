//! Shared Text split cursors, generic adapters, and independent sequence models.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeSet,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Output},
    time::Duration,
};

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/text_split_iterators")
        .join(name);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("text split iterators {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_text_split_iterators", name, None);
    // Keep the unchanged strict ELF/jump checker on every emitted executable.
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

fn successful(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn split_cursors_compose_and_preserve_views_without_allocations() {
    let executable = executable("contracts.lani");
    let trace = common::TempArtifact::new("laniusc_text_split_iterators", "memory_trace", None);
    let output = common::process_output_with_timeout(
        "Text split cursor contracts",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,mremap,munmap,brk", "-e", "signal=none"])
            .arg(executable.path()),
        Duration::from_secs(5),
    );
    successful(&output);
    assert!(output.stdout.is_empty(), "{output:?}");
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(
        events.is_empty(),
        "split cursors and adapters must allocate nothing: {events}"
    );
}

fn whitespace(byte: u8) -> bool {
    // Lanius includes all six bytes, including VT (11). Rust's own ASCII
    // whitespace splitting is deliberately not the oracle for this contract.
    matches!(byte, 9 | 10 | 11 | 12 | 13 | 32)
}

fn whitespace_fields(text: &str) -> Vec<&[u8]> {
    text.as_bytes()
        .split(|byte| whitespace(*byte))
        .filter(|field| !field.is_empty())
        .collect()
}

fn word(output: &mut Vec<u8>, value: usize) {
    output.extend_from_slice(&(value as u64).to_le_bytes());
}

fn field(output: &mut Vec<u8>, value: Option<&[u8]>) {
    if let Some(bytes) = value {
        output.push(1);
        word(output, bytes.len());
        output.extend_from_slice(bytes);
    } else {
        output.push(0);
    }
}

#[derive(Default)]
struct Model {
    input: Vec<u8>,
    expected: Vec<u8>,
    cases: Vec<(usize, String)>,
}
impl Model {
    fn add(&mut self, op: u8, text: &str, separator: &str) {
        assert!(text.len() <= 192 && separator.len() <= 16);
        let fields: Vec<&[u8]> = if op == 0 {
            text.split(separator).map(str::as_bytes).collect()
        } else {
            whitespace_fields(text)
        };
        let quotas = BTreeSet::from([0, 1, fields.len(), fields.len() + 1]);
        for layout in 0..=1 {
            for &quota in &quotas {
                assert!(quota <= 255);
                self.input.extend_from_slice(&[
                    op,
                    layout,
                    quota as u8,
                    text.len() as u8,
                    separator.len() as u8,
                ]);
                self.input.extend_from_slice(text.as_bytes());
                self.input.extend_from_slice(separator.as_bytes());
                let selected = fields.len().min(quota);
                for &value in &fields[..selected] {
                    field(&mut self.expected, Some(value));
                }
                field(&mut self.expected, None);
                let direct = fields.get(selected).copied();
                field(&mut self.expected, direct);
                let remainder = &fields[selected + usize::from(direct.is_some())..];
                for value in remainder {
                    word(&mut self.expected, value.len() + 1);
                }
                word(&mut self.expected, 0);
                word(&mut self.expected, remainder.len());
                for &value in &fields {
                    field(&mut self.expected, Some(value));
                }
                field(&mut self.expected, None);
                self.cases.push((self.expected.len(), format!("op={op} layout={layout} quota={quota} text={text:?} separator={separator:?}")));
            }
        }
    }
}

fn next(seed: &mut u32) -> u32 {
    *seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
    *seed
}

#[test]
fn split_cursor_sequences_match_utf8_and_six_byte_whitespace_models() {
    let mut model = Model::default();
    for text in [
        "",
        "a",
        ",a,,b,",
        "aaaaa",
        "é🙂é🙂",
        "\0x\0",
        "\t\n\x0b\x0c\r ",
        "\u{a0}x \u{a0}",
        " e\u{301} é ",
        "\u{feff}\u{10ffff}\u{ffff}",
        "one\u{85}two\u{2028}three",
        "\x0bA\0é\x0cB\tC\r\n",
    ] {
        for separator in ["", ",", "aa", "é🙂", "\0", "missing"] {
            model.add(0, text, separator);
        }
        model.add(1, text, "");
    }
    let alphabet = [
        '\0',
        'a',
        'b',
        ',',
        ' ',
        '\t',
        '\n',
        '\x0b',
        '\x0c',
        '\r',
        '\u{a0}',
        '\u{85}',
        '\u{7ff}',
        '\u{800}',
        '\u{10000}',
        '\u{10ffff}',
        'é',
        '🙂',
        '\u{301}',
        '\u{feff}',
    ];
    let mut seed = 0x5a17_2026;
    for case in 0..32 {
        let length = next(&mut seed) % 25;
        let text: String = (0..length)
            .map(|_| alphabet[next(&mut seed) as usize % alphabet.len()])
            .collect();
        let characters: Vec<_> = text.chars().collect();
        let separator: String = if case % 4 == 0 {
            String::new()
        } else if characters.is_empty() {
            "q".to_owned()
        } else {
            let start = next(&mut seed) as usize % characters.len();
            characters[start..(start + 2).min(characters.len())]
                .iter()
                .collect()
        };
        model.add(0, &text, &separator);
        model.add(1, &text, "");
    }
    let input = common::TempArtifact::new("laniusc_text_split_iterators", "model_input", None);
    input.write_bytes(&model.input);
    let executable = executable("model.lani");
    let output = common::process_output_with_timeout(
        "Text split iterator independent models",
        Command::new(executable.path()).stdin(std::fs::File::open(input.path()).unwrap()),
        Duration::from_secs(10),
    );
    successful(&output);
    assert_eq!(
        output.stdout.len(),
        model.expected.len(),
        "complete model response"
    );
    let mut start = 0;
    for (end, description) in &model.cases {
        assert_eq!(
            &output.stdout[start..*end],
            &model.expected[start..*end],
            "{description}"
        );
        start = *end;
    }
    eprintln!(
        "{} independent split iterator cases passed in one native execution",
        model.cases.len()
    );
}
