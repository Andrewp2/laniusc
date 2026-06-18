use std::{
    fs,
    io::{self, Read, Write},
    path::{Path, PathBuf},
};

use super::{
    common::{
        CliError,
        LANIUS_DIAGNOSTIC_FORMATS,
        incompatible_cli_options_error,
        missing_cli_argument_error,
        missing_cli_option_value_error,
        unknown_cli_option_error,
        validate_diagnostic_format,
    },
    help::print_fmt_help,
    output::write_output_stream_bytes,
};
use crate::{
    compiler::{Diagnostic, DiagnosticLabel},
    formatter::format_source,
};

/// Runs the lexical formatter subcommand.
pub(crate) fn run(args: impl IntoIterator<Item = String>) -> Result<(), CliError> {
    let mut check = false;
    let mut stdin = false;
    let mut inputs: Vec<PathBuf> = Vec::new();

    let mut args = args.into_iter();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "-h" | "--help" => {
                print_fmt_help();
                return Ok(());
            }
            "--check" => {
                check = true;
            }
            "--stdin" => {
                stdin = true;
            }
            "--diagnostic-format" => {
                let value = args.next().ok_or_else(|| {
                    missing_cli_option_value_error(
                        "--diagnostic-format",
                        format!("one of: {LANIUS_DIAGNOSTIC_FORMATS}"),
                    )
                })?;
                validate_diagnostic_format(&value)?;
            }
            flag if flag.starts_with("--diagnostic-format=") => {
                validate_diagnostic_format(flag.trim_start_matches("--diagnostic-format="))?;
            }
            "-" => {
                stdin = true;
            }
            flag if flag.starts_with('-') => {
                return Err(unknown_cli_option_error(
                    "laniusc fmt",
                    flag,
                    "--help, --check, --stdin, --diagnostic-format",
                ));
            }
            path => {
                inputs.push(PathBuf::from(path));
            }
        }
    }

    if stdin {
        if !inputs.is_empty() {
            return Err(incompatible_cli_options_error(
                "laniusc fmt",
                "--stdin/-",
                "input files",
                "omit input files when formatting standard input",
            ));
        }

        let mut source = String::new();
        io::stdin()
            .read_to_string(&mut source)
            .map_err(|err| CliError::Diagnostic(stdin_read_failed_diagnostic(err)))?;
        let formatted = format_source(&source);

        if check {
            if source == formatted {
                return Ok(());
            }
            return Err(CliError::Diagnostic(formatter_check_failed_diagnostic(
                Path::new("<stdin>"),
                &source,
                &formatted,
                "pipe the source through `laniusc fmt --stdin` to print the rewrite".to_string(),
            )));
        }

        write_formatted_stdout(formatted.as_bytes())?;
        return Ok(());
    }

    if inputs.is_empty() {
        return Err(missing_cli_argument_error(
            "laniusc fmt",
            "one or more input files or --stdin",
        ));
    }

    if check {
        let mut failures = Vec::new();
        for input in inputs {
            let source = fs::read_to_string(&input)
                .map_err(|err| CliError::Diagnostic(input_read_failed_diagnostic(&input, err)))?;
            let formatted = format_source(&source);
            if source != formatted {
                failures.push(FormatterCheckFailure {
                    input,
                    source,
                    formatted,
                });
            }
        }

        if failures.is_empty() {
            return Ok(());
        }

        return Err(CliError::Diagnostic(
            formatter_check_failed_for_files_diagnostic(&failures),
        ));
    }

    for input in inputs {
        let source = fs::read_to_string(&input)
            .map_err(|err| CliError::Diagnostic(input_read_failed_diagnostic(&input, err)))?;
        let formatted = format_source(&source);

        if source == formatted {
            continue;
        }

        fs::write(&input, formatted).map_err(|err| {
            CliError::Diagnostic(formatter_output_write_failed_diagnostic(&input, err))
        })?;
    }
    Ok(())
}

struct FormatterCheckFailure {
    input: PathBuf,
    source: String,
    formatted: String,
}

fn write_formatted_stdout(bytes: &[u8]) -> Result<(), CliError> {
    let mut stdout = io::stdout();
    write_formatted_output_stream("stdout", &mut stdout, bytes)
}

fn write_formatted_output_stream<W: Write>(
    stream: &str,
    writer: &mut W,
    bytes: &[u8],
) -> Result<(), CliError> {
    write_output_stream_bytes(stream, "fmt", "write formatted stdout", writer, bytes)
        .map_err(CliError::from)
}

fn input_read_failed_diagnostic(input: &Path, err: io::Error) -> Diagnostic {
    Diagnostic::error("LNC0040", "input read failed")
        .with_primary_label(DiagnosticLabel::primary(
            input,
            1,
            1,
            1,
            None,
            "could not read this input file",
        ))
        .with_help("create the file or pass --stdin to format standard input")
        .with_note(format!("formatter input path: {}", input.display()))
        .with_note("operation: read formatter input".to_string())
        .with_note(format!("I/O error kind: {:?}", err.kind()))
        .with_note(format!("I/O error: {err}"))
        .with_note("create the file or pass --stdin to format standard input".to_string())
}

#[cfg(test)]
mod tests {
    use std::io;

    use super::{CliError, write_formatted_output_stream};

    struct FailingWriter;

    impl io::Write for FailingWriter {
        fn write(&mut self, _bytes: &[u8]) -> io::Result<usize> {
            Err(io::Error::from(io::ErrorKind::BrokenPipe))
        }

        fn flush(&mut self) -> io::Result<()> {
            Ok(())
        }
    }

    #[test]
    fn formatter_stdout_stream_failure_is_structured_diagnostic() {
        let mut writer = FailingWriter;
        let err = write_formatted_output_stream("stdout", &mut writer, b"fn main() {}\n")
            .expect_err("formatter stdout write failure should fail");

        let CliError::Diagnostic(diagnostic) = err else {
            panic!("formatter stdout write failure should be a diagnostic");
        };

        assert_eq!(diagnostic.code, "LNC0035");
        assert_eq!(diagnostic.category, "tooling");
        assert!(
            diagnostic.primary_label.is_none(),
            "stream failures are intentionally spanless"
        );
        assert!(
            diagnostic
                .help
                .as_deref()
                .expect("stream diagnostic should include public recovery help")
                .contains("-o/--out")
        );
        assert!(
            diagnostic
                .notes
                .iter()
                .any(|note| note == "output stream: stdout"),
            "stream diagnostic should preserve stream context"
        );
        assert!(
            diagnostic.notes.iter().any(|note| note == "emit mode: fmt"),
            "stream diagnostic should preserve formatter mode context"
        );
        assert!(
            diagnostic
                .notes
                .iter()
                .any(|note| note == "operation: write formatted stdout"),
            "stream diagnostic should preserve formatter operation context"
        );
        assert!(
            diagnostic
                .notes
                .iter()
                .any(|note| note == "I/O error kind: BrokenPipe"),
            "stream diagnostic should preserve stable I/O error kind"
        );
    }
}

fn stdin_read_failed_diagnostic(err: io::Error) -> Diagnostic {
    Diagnostic::error("LNC0040", "input read failed")
        .with_primary_label(DiagnosticLabel::primary(
            Path::new("<stdin>"),
            1,
            1,
            1,
            None,
            "could not read formatter input from stdin",
        ))
        .with_help("pass UTF-8 Lanius source on stdin or format a source file path")
        .with_note("formatter input path: <stdin>".to_string())
        .with_note("operation: read formatter stdin".to_string())
        .with_note(format!("I/O error kind: {:?}", err.kind()))
        .with_note(format!("I/O error: {err}"))
        .with_note("pass UTF-8 Lanius source on stdin or format a source file path".to_string())
}

fn formatter_output_write_failed_diagnostic(output: &Path, err: io::Error) -> Diagnostic {
    Diagnostic::error("LNC0034", "output write failed")
        .with_primary_label(DiagnosticLabel::primary(
            output,
            1,
            1,
            1,
            None,
            "could not rewrite this formatter output file",
        ))
        .with_help("choose a writable source file path or run `laniusc fmt --check` to check formatting without rewriting")
        .with_note(format!("formatter output path: {}", output.display()))
        .with_note("operation: write formatter output".to_string())
        .with_note(format!("I/O error kind: {:?}", err.kind()))
        .with_note(format!("I/O error: {err}"))
}

fn formatter_check_failed_diagnostic(
    input: &Path,
    source: &str,
    formatted: &str,
    rewrite_hint: String,
) -> Diagnostic {
    Diagnostic::error("LNC0019", "formatter check failed")
        .with_primary_label(formatter_check_label(input, source, formatted))
        .with_note(format!(
            "fmt check failed: {} is not formatted",
            input.display()
        ))
        .with_note(rewrite_hint)
}

fn formatter_check_failed_for_files_diagnostic(failures: &[FormatterCheckFailure]) -> Diagnostic {
    let first = failures
        .first()
        .expect("formatter check diagnostic requires at least one failure");
    let mut diagnostic = Diagnostic::error("LNC0019", "formatter check failed").with_primary_label(
        formatter_check_label(&first.input, &first.source, &first.formatted),
    );

    if failures.len() == 1 {
        return diagnostic
            .with_note(format!(
                "fmt check failed: {} is not formatted",
                first.input.display()
            ))
            .with_note(format!(
                "run `laniusc fmt {}` to rewrite the file",
                first.input.display()
            ));
    }

    diagnostic = diagnostic.with_note(format!(
        "fmt check failed: {} input files are not formatted",
        failures.len()
    ));
    for failure in failures {
        diagnostic =
            diagnostic.with_note(format!("unformatted input: {}", failure.input.display()));
    }
    diagnostic.with_note(format!(
        "run `laniusc fmt {}` to rewrite these files",
        failures
            .iter()
            .map(|failure| failure.input.display().to_string())
            .collect::<Vec<_>>()
            .join(" ")
    ))
}

fn formatter_check_label(input: &Path, source: &str, formatted: &str) -> DiagnosticLabel {
    let diff_byte = first_format_difference_byte(source, formatted);
    let label_start = if diff_byte < source.len() {
        diff_byte
    } else {
        source
            .char_indices()
            .last()
            .map(|(index, _)| index)
            .unwrap_or(0)
    };
    let line_start = source[..label_start]
        .rfind('\n')
        .map(|index| index + 1)
        .unwrap_or(0);
    let line_end = source[label_start..]
        .find('\n')
        .map(|index| label_start + index)
        .unwrap_or(source.len());
    let line = source[..line_start]
        .bytes()
        .filter(|byte| *byte == b'\n')
        .count()
        + 1;
    let column = source[line_start..label_start].chars().count() + 1;
    let source_line = if line_start < line_end {
        source.get(line_start..line_end).map(ToOwned::to_owned)
    } else {
        None
    };

    DiagnosticLabel::primary(
        input,
        line,
        column,
        1,
        source_line,
        "formatting differs here",
    )
}

fn first_format_difference_byte(source: &str, formatted: &str) -> usize {
    let mut source_chars = source.char_indices();
    let mut formatted_chars = formatted.chars();
    loop {
        match (source_chars.next(), formatted_chars.next()) {
            (Some((_, source_char)), Some(formatted_char)) if source_char == formatted_char => {}
            (Some((index, _)), _) => return index,
            (None, Some(_)) => return source.len(),
            (None, None) => return 0,
        }
    }
}
