mod common;

use std::{
    fs,
    io::Write,
    path::PathBuf,
    process::{Child, Command, Output, Stdio},
    thread,
    time::{Duration, Instant},
};

const CLI_FORMATTER_TIMEOUT: Duration = Duration::from_secs(4);
const CHILD_PROCESS_POLL_INTERVAL: Duration = Duration::from_millis(2);

fn laniusc_bin() -> PathBuf {
    option_env!("CARGO_BIN_EXE_laniusc")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target/debug/laniusc"))
}

#[test]
fn cli_fmt_formats_source_file_in_place() {
    let source = common::TempArtifact::new("laniusc_cli_formatter", "format", Some("lani"));
    source.write_str("fn main(){return 1;}");

    let mut command = Command::new(laniusc_bin());
    command.arg("fmt").arg(source.path());
    let output = common::command_output_with_timeout("laniusc fmt", &mut command);
    common::assert_command_success("laniusc fmt", &output);

    assert!(
        output.stdout.is_empty(),
        "formatter should not print on a successful rewrite\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    assert!(
        output.stderr.is_empty(),
        "formatter should not print diagnostics on success\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        fs::read_to_string(source.path()).expect("read formatted source"),
        "\
fn main() {
    return 1;
}
"
    );
}

#[test]
fn cli_fmt_formats_multiple_source_files_in_place() {
    let first = common::TempArtifact::new("laniusc_cli_formatter", "format_many_a", Some("lani"));
    let second = common::TempArtifact::new("laniusc_cli_formatter", "format_many_b", Some("lani"));
    first.write_str("fn first(){return 1;}");
    second.write_str("fn second(){return 2;}");

    let mut command = Command::new(laniusc_bin());
    command.arg("fmt").arg(first.path()).arg(second.path());
    let output = common::command_output_with_timeout("laniusc fmt multiple files", &mut command);
    common::assert_command_success("laniusc fmt multiple files", &output);

    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "successful multi-file fmt should be quiet\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        fs::read_to_string(first.path()).expect("read first formatted source"),
        "\
fn first() {
    return 1;
}
"
    );
    assert_eq!(
        fs::read_to_string(second.path()).expect("read second formatted source"),
        "\
fn second() {
    return 2;
}
"
    );
}

#[test]
fn cli_fmt_formats_where_clauses_in_place() {
    let source = common::TempArtifact::new("laniusc_cli_formatter", "where", Some("lani"));
    source.write_str("fn keep<T>(value:T)->T where T:Eq<T>{return value;}");

    let mut command = Command::new(laniusc_bin());
    command.arg("fmt").arg(source.path());
    let output = common::command_output_with_timeout("laniusc fmt where", &mut command);
    common::assert_command_success("laniusc fmt where", &output);

    assert_eq!(
        fs::read_to_string(source.path()).expect("read formatted where source"),
        "\
fn keep<T>(value: T) -> T
where
    T: Eq<T>
{
    return value;
}
"
    );
}

#[test]
fn cli_fmt_keeps_where_predicates_one_per_line_and_check_accepts_rewrite() {
    let source =
        common::TempArtifact::new("laniusc_cli_formatter", "where_predicates", Some("lani"));
    source.write_str("fn keep<T,U,V>(left:T,right:U)->T where T:Rel<U,V>, U:Eq<U>{return left;}");

    let mut format_command = Command::new(laniusc_bin());
    format_command.arg("fmt").arg(source.path());
    let format_output =
        common::command_output_with_timeout("laniusc fmt where predicates", &mut format_command);
    common::assert_command_success("laniusc fmt where predicates", &format_output);
    assert!(
        format_output.stdout.is_empty() && format_output.stderr.is_empty(),
        "successful fmt should be quiet\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&format_output.stdout),
        String::from_utf8_lossy(&format_output.stderr)
    );

    let formatted = "\
fn keep<T, U, V>(left: T, right: U) -> T
where
    T: Rel<U, V>,
    U: Eq<U>
{
    return left;
}
";
    assert_eq!(
        fs::read_to_string(source.path()).expect("read formatted where predicate source"),
        formatted
    );

    let mut check_command = Command::new(laniusc_bin());
    check_command.arg("fmt").arg("--check").arg(source.path());
    let check_output = common::command_output_with_timeout(
        "laniusc fmt --check where predicates",
        &mut check_command,
    );
    common::assert_command_success("laniusc fmt --check where predicates", &check_output);
    assert!(
        check_output.stdout.is_empty() && check_output.stderr.is_empty(),
        "successful fmt --check should be quiet\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&check_output.stdout),
        String::from_utf8_lossy(&check_output.stderr)
    );
}

#[test]
fn cli_fmt_keeps_block_match_arms_on_separate_lines() {
    let mut command = Command::new(laniusc_bin());
    command.arg("fmt").arg("--stdin");
    let output = command_output_with_stdin(
        "laniusc fmt --stdin block match arms",
        &mut command,
        b"fn main(){match value{1=>{return 1;},_=>{return 0;}}}",
    );
    common::assert_command_success("laniusc fmt --stdin block match arms", &output);

    assert_eq!(
        String::from_utf8_lossy(&output.stdout),
        "\
fn main() {
    match value {
        1 => {
            return 1;
        },
        _ => {
            return 0;
        }
    }
}
"
    );
    assert!(
        output.stderr.is_empty(),
        "stdin formatter should not print diagnostics on success\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn cli_fmt_stdin_selectors_print_formatted_source_to_stdout_without_files() {
    for selector in ["--stdin", "-"] {
        let context = format!("laniusc fmt {selector}");
        let mut command = Command::new(laniusc_bin());
        command.arg("fmt").arg(selector);
        let output = command_output_with_stdin(&context, &mut command, b"fn main(){return 1;}");
        common::assert_command_success(&context, &output);

        assert_eq!(
            String::from_utf8_lossy(&output.stdout),
            "\
fn main() {
    return 1;
}
"
        );
        assert!(
            output.stderr.is_empty(),
            "stdin formatter should not print diagnostics on success\nstderr:\n{}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    let mut check_command = Command::new(laniusc_bin());
    check_command
        .arg("fmt")
        .arg("--stdin")
        .arg("--check")
        .arg("--diagnostic-format=json");
    let check_output = command_output_with_stdin(
        "laniusc fmt --stdin --check --diagnostic-format=json",
        &mut check_command,
        b"fn main(){return 1;}",
    );
    assert!(
        !check_output.status.success(),
        "stdin fmt --check should fail for unformatted input"
    );
    assert!(
        check_output.stdout.is_empty(),
        "stdin fmt --check JSON failure should not write formatted output\nstdout:\n{}",
        String::from_utf8_lossy(&check_output.stdout)
    );
    let stderr = String::from_utf8_lossy(&check_output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON formatter diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["code"], "LNC0019");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["primary_label"]["path"], "<stdin>");
    assert_eq!(
        diagnostic["primary_label"]["message"],
        "formatting differs here"
    );
}

#[test]
fn cli_fmt_check_reports_unformatted_source_without_writing() {
    let original = "fn main(){return 1;}";
    let source = common::TempArtifact::new("laniusc_cli_formatter", "check", Some("lani"));
    source.write_str(original);

    let mut command = Command::new(laniusc_bin());
    command.arg("fmt").arg("--check").arg(source.path());
    let output = common::command_output_with_timeout("laniusc fmt --check", &mut command);

    assert!(
        !output.status.success(),
        "fmt --check should fail for an unformatted file"
    );
    assert!(
        output.stdout.is_empty(),
        "fmt --check failure should not write normal output\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("fmt check failed"),
        "fmt --check should identify formatting failures\nstderr:\n{stderr}"
    );
    assert_eq!(
        fs::read_to_string(source.path()).expect("read checked source"),
        original,
        "fmt --check must not rewrite the input file"
    );
}

#[test]
fn cli_fmt_check_reports_first_unformatted_file_from_multiple_without_writing() {
    let formatted = "\
fn first() {
    return 1;
}
";
    let unformatted = "fn second(){return 2;}";
    let first = common::TempArtifact::new("laniusc_cli_formatter", "check_many_a", Some("lani"));
    let second = common::TempArtifact::new("laniusc_cli_formatter", "check_many_b", Some("lani"));
    first.write_str(formatted);
    second.write_str(unformatted);

    let mut command = Command::new(laniusc_bin());
    command
        .arg("fmt")
        .arg("--check")
        .arg("--diagnostic-format=json")
        .arg(first.path())
        .arg(second.path());
    let output = common::command_output_with_timeout("laniusc fmt --check multiple", &mut command);

    assert!(
        !output.status.success(),
        "fmt --check should fail when any selected file is unformatted"
    );
    assert!(
        output.stdout.is_empty(),
        "multi-file fmt --check JSON failure should not write normal output\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["code"], "LNC0019");
    assert_eq!(
        diagnostic["primary_label"]["path"],
        second.path().display().to_string()
    );
    assert_eq!(
        fs::read_to_string(first.path()).expect("read first checked source"),
        formatted,
        "fmt --check must not rewrite already formatted inputs"
    );
    assert_eq!(
        fs::read_to_string(second.path()).expect("read second checked source"),
        unformatted,
        "fmt --check must not rewrite unformatted inputs"
    );
}

#[test]
fn cli_fmt_check_can_render_json_diagnostic_without_writing() {
    let original = "fn main(){return 1;}";
    let source = common::TempArtifact::new("laniusc_cli_formatter", "check_json", Some("lani"));
    source.write_str(original);

    let mut command = Command::new(laniusc_bin());
    command
        .arg("fmt")
        .arg("--check")
        .arg("--diagnostic-format=json")
        .arg(source.path());
    let output = common::command_output_with_timeout(
        "laniusc fmt --check --diagnostic-format=json",
        &mut command,
    );

    assert!(
        !output.status.success(),
        "fmt --check should fail for an unformatted file"
    );
    assert!(
        output.stdout.is_empty(),
        "fmt --check JSON failure should not write normal output\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON formatter diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0019");
    assert_eq!(diagnostic["title"], "formatter check failed");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["message"], "formatter check failed");
    assert_eq!(
        diagnostic["primary_label"]["path"],
        source.path().display().to_string()
    );
    assert_eq!(diagnostic["primary_label"]["line"], 1);
    assert_eq!(diagnostic["primary_label"]["source_line"], original);
    assert_eq!(
        diagnostic["primary_label"]["message"],
        "formatting differs here"
    );
    let notes = diagnostic["notes"]
        .as_array()
        .expect("formatter diagnostic should include notes");
    assert!(notes.iter().any(|note| {
        note.as_str()
            .expect("formatter diagnostic note should be a string")
            .contains("fmt check failed")
    }));
    assert_eq!(
        fs::read_to_string(source.path()).expect("read checked source"),
        original,
        "fmt --check must not rewrite the input file"
    );
}

#[test]
fn cli_fmt_check_can_render_lsp_json_diagnostic_without_writing() {
    let original = "fn main(){return 1;}";
    let source = common::TempArtifact::new("laniusc_cli_formatter", "check_lsp_json", Some("lani"));
    source.write_str(original);

    let mut command = Command::new(laniusc_bin());
    command
        .arg("fmt")
        .arg("--check")
        .arg("--diagnostic-format=lsp-json")
        .arg(source.path());
    let output = common::command_output_with_timeout(
        "laniusc fmt --check --diagnostic-format=lsp-json",
        &mut command,
    );

    assert!(
        !output.status.success(),
        "fmt --check should fail for an unformatted file"
    );
    assert!(
        output.stdout.is_empty(),
        "fmt --check LSP JSON failure should not write normal output\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "LSP JSON formatter diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one LSP diagnostic object");
    assert_eq!(diagnostic["severity"], 1);
    assert_eq!(diagnostic["code"], "LNC0019");
    assert_eq!(diagnostic["source"], "laniusc");
    assert_eq!(diagnostic["message"], "formatter check failed");
    assert_eq!(diagnostic["data"]["registry_schema_version"], 5);
    assert_eq!(diagnostic["data"]["title"], "formatter check failed");
    assert_eq!(diagnostic["data"]["category"], "tooling");
    assert_eq!(diagnostic["data"]["primary_label_policy"], "required");
    assert!(diagnostic["range"]["start"]["line"].is_number());
    assert!(diagnostic["range"]["start"]["character"].is_number());
    assert!(diagnostic["range"]["end"]["line"].is_number());
    assert!(diagnostic["range"]["end"]["character"].is_number());
    assert!(diagnostic.get("primary_label").is_none());
    assert!(diagnostic.get("notes").is_none());
    assert_eq!(
        fs::read_to_string(source.path()).expect("read checked source"),
        original,
        "fmt --check must not rewrite the input file"
    );
}

#[test]
fn cli_fmt_missing_input_can_render_json_diagnostic_without_reading_source() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("fmt")
        .arg("--check")
        .arg("--diagnostic-format=json");
    let output = common::command_output_with_timeout(
        "laniusc fmt --check --diagnostic-format=json missing input",
        &mut command,
    );

    assert!(
        !output.status.success(),
        "fmt without an input file should fail"
    );
    assert!(
        output.stdout.is_empty(),
        "missing formatter input should not write normal output\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON formatter invocation diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0026");
    assert_eq!(diagnostic["title"], "missing CLI argument");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["message"], "missing CLI argument");
    assert!(diagnostic["primary_label"].is_null());
    let notes = diagnostic["notes"]
        .as_array()
        .expect("missing formatter input diagnostic should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("laniusc fmt")),
        "diagnostic notes should identify the formatter command\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("one or more input files")),
        "diagnostic notes should describe the required input\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_fmt_check_accepts_formatted_source() {
    let source = common::TempArtifact::new("laniusc_cli_formatter", "check_ok", Some("lani"));
    source.write_str(
        "\
fn main() {
    return 1;
}
",
    );

    let mut command = Command::new(laniusc_bin());
    command.arg("fmt").arg("--check").arg(source.path());
    let output = common::command_output_with_timeout("laniusc fmt --check formatted", &mut command);
    common::assert_command_success("laniusc fmt --check formatted", &output);

    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "successful fmt --check should be quiet\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn cli_fmt_help_describes_formatter_command() {
    let mut command = Command::new(laniusc_bin());
    command.arg("fmt").arg("--help");
    let output = common::command_output_with_timeout("laniusc fmt --help", &mut command);
    common::assert_command_success("laniusc fmt --help", &output);

    assert!(
        output.stdout.is_empty(),
        "help is written to stderr with the rest of this CLI\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains(
        "Usage: laniusc fmt [--check] [--diagnostic-format text|json|lsp-json] (<input.lani> [more-input.lani...]|--stdin|-)"
    ));
    assert!(stderr.contains("--check"));
    assert!(stderr.contains("--stdin"));
    assert!(stderr.contains("--diagnostic-format"));
}

fn command_output_with_stdin(context: &str, command: &mut Command, stdin: &[u8]) -> Output {
    let mut child = command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap_or_else(|err| panic!("{context}: spawn command: {err}"));
    child
        .stdin
        .as_mut()
        .expect("formatter child should expose stdin")
        .write_all(stdin)
        .unwrap_or_else(|err| panic!("{context}: write stdin: {err}"));
    drop(child.stdin.take());
    child_output_with_timeout(context, child)
}

fn child_output_with_timeout(context: &str, mut child: Child) -> Output {
    let start = Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(_status)) => {
                return child
                    .wait_with_output()
                    .unwrap_or_else(|err| panic!("{context}: collect command output: {err}"));
            }
            Ok(None) => {}
            Err(err) => panic!("{context}: wait for command: {err}"),
        }

        if start.elapsed() >= CLI_FORMATTER_TIMEOUT {
            let _ = child.kill();
            let output = child
                .wait_with_output()
                .unwrap_or_else(|err| panic!("{context}: collect timed-out output: {err}"));
            panic!(
                "{context}: timed out after {:?}\nstdout:\n{}\nstderr:\n{}",
                CLI_FORMATTER_TIMEOUT,
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            );
        }

        thread::sleep(CHILD_PROCESS_POLL_INTERVAL);
    }
}
