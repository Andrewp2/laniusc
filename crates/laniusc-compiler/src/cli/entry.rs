use std::{env, process::ExitCode};

use super::{
    common::{CliError, DiagnosticFormat, diagnostic_format_from_args},
    dispatch,
    fallback::cli_operation_failed_diagnostic,
};
use crate::compiler::Diagnostic;

/// Runs the CLI from process arguments and returns the process exit code.
///
/// Error rendering is selected before dispatch so subcommand parsing errors can
/// still honor `--diagnostic-format`.
pub fn run_from_env() -> ExitCode {
    let args = env::args().skip(1).collect::<Vec<_>>();
    let diagnostic_format = diagnostic_format_from_args(args.iter().cloned());
    match dispatch::run(args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            report_error(diagnostic_format, err);
            ExitCode::FAILURE
        }
    }
}

fn report_error(diagnostic_format: DiagnosticFormat, err: CliError) {
    eprintln!("{}", render_error(diagnostic_format, err));
}

fn render_error(diagnostic_format: DiagnosticFormat, err: CliError) -> String {
    let diagnostic = err.into_public_diagnostic();
    match diagnostic_format {
        DiagnosticFormat::Json => render_json_diagnostic(diagnostic),
        DiagnosticFormat::LspJson => render_lsp_json_diagnostic(diagnostic),
        DiagnosticFormat::Text => diagnostic.render(),
    }
}

fn render_json_diagnostic(diagnostic: Diagnostic) -> String {
    match diagnostic.render_json_pretty() {
        Ok(json) => json,
        Err(err) => render_json_serialization_failure("serialize diagnostic JSON", err),
    }
}

fn render_lsp_json_diagnostic(diagnostic: Diagnostic) -> String {
    match diagnostic.render_lsp_json_pretty() {
        Ok(json) => json,
        Err(err) => render_lsp_json_serialization_failure("serialize LSP diagnostic JSON", err),
    }
}

fn render_json_serialization_failure(operation: &'static str, err: serde_json::Error) -> String {
    let fallback = cli_operation_failed_diagnostic(format!("{operation}: {err}"));
    fallback
        .render_json_pretty()
        .unwrap_or_else(|_| last_resort_json_diagnostic(operation))
}

fn render_lsp_json_serialization_failure(
    operation: &'static str,
    err: serde_json::Error,
) -> String {
    let fallback = cli_operation_failed_diagnostic(format!("{operation}: {err}"));
    fallback
        .render_lsp_json_pretty()
        .unwrap_or_else(|_| last_resort_lsp_json_diagnostic(operation))
}

fn last_resort_json_diagnostic(operation: &str) -> String {
    serde_json::json!({
        "severity": "error",
        "code": "LNC0067",
        "message": "CLI operation failed",
        "category": "tooling",
        "notes": [
            "the CLI stopped before it could render a structured diagnostic",
            format!("operation: {operation}")
        ]
    })
    .to_string()
}

fn last_resort_lsp_json_diagnostic(operation: &str) -> String {
    serde_json::json!({
        "range": {
            "start": { "line": 0, "character": 0 },
            "end": { "line": 0, "character": 0 }
        },
        "severity": 1,
        "code": "LNC0067",
        "source": "laniusc",
        "message": "CLI operation failed",
        "data": {
            "title": "CLI operation failed",
            "category": "tooling",
            "notes": [
                "the CLI stopped before it could render an LSP diagnostic",
                format!("operation: {operation}")
            ]
        }
    })
    .to_string()
}

#[cfg(test)]
mod tests {
    use super::{
        render_error,
        render_json_serialization_failure,
        render_lsp_json_serialization_failure,
    };
    use crate::cli::common::{CliError, DiagnosticFormat};

    #[test]
    fn json_error_renderer_lowers_plain_cli_messages_to_diagnostics() {
        let rendered = render_error(
            DiagnosticFormat::Json,
            CliError::from("serialize doctor report: broken pipe"),
        );

        let diagnostic: serde_json::Value =
            serde_json::from_str(&rendered).expect("rendered CLI error should be JSON");
        assert_eq!(diagnostic["code"], "LNC0067");
        assert_eq!(diagnostic["message"], "CLI operation failed");
        assert_eq!(diagnostic["category"], "tooling");
        assert!(
            diagnostic["notes"]
                .as_array()
                .expect("diagnostic notes should be present")
                .iter()
                .any(|note| note
                    .as_str()
                    .is_some_and(|note| note.contains("serialize doctor report: broken pipe")))
        );
        assert!(
            !rendered.starts_with("laniusc:"),
            "machine-readable diagnostic formats must not fall back to text prefixes"
        );
    }

    #[test]
    fn json_serialization_fallback_stays_structured() {
        let err = serde_json::from_str::<serde_json::Value>("{")
            .expect_err("fixture should produce a serde error");
        let rendered = render_json_serialization_failure("serialize diagnostic JSON", err);

        let diagnostic: serde_json::Value =
            serde_json::from_str(&rendered).expect("serialization fallback should still be JSON");
        assert_eq!(diagnostic["code"], "LNC0067");
        assert_eq!(diagnostic["message"], "CLI operation failed");
        assert_eq!(diagnostic["category"], "tooling");
        assert!(
            diagnostic["notes"]
                .as_array()
                .expect("fallback diagnostic should include notes")
                .iter()
                .any(|note| note
                    .as_str()
                    .is_some_and(|note| note.contains("serialize diagnostic JSON"))),
            "fallback diagnostic should explain the serialization failure\n{rendered}"
        );
        assert!(
            !rendered.starts_with("laniusc:"),
            "JSON diagnostics must not fall back to text prefixes on serialization failure"
        );
    }

    #[test]
    fn lsp_json_error_renderer_lowers_plain_cli_messages_to_diagnostics() {
        let rendered = render_error(
            DiagnosticFormat::LspJson,
            CliError::from("serialize LSP response: broken pipe"),
        );

        let diagnostic: serde_json::Value =
            serde_json::from_str(&rendered).expect("rendered CLI error should be LSP JSON");
        assert_eq!(diagnostic["code"], "LNC0067");
        assert_eq!(diagnostic["message"], "CLI operation failed");
        assert_eq!(diagnostic["data"]["category"], "tooling");
        assert_eq!(
            diagnostic["data"]["explain_command"],
            "laniusc diagnostics explain LNC0067"
        );
        assert!(
            !rendered.starts_with("laniusc:"),
            "machine-readable diagnostic formats must not fall back to text prefixes"
        );
    }

    #[test]
    fn lsp_json_serialization_fallback_stays_lsp_shaped() {
        let err = serde_json::from_str::<serde_json::Value>("{")
            .expect_err("fixture should produce a serde error");
        let rendered = render_lsp_json_serialization_failure("serialize LSP diagnostic JSON", err);

        let diagnostic: serde_json::Value =
            serde_json::from_str(&rendered).expect("serialization fallback should be LSP JSON");
        assert_eq!(diagnostic["code"], "LNC0067");
        assert_eq!(diagnostic["message"], "CLI operation failed");
        assert_eq!(diagnostic["source"], "laniusc");
        assert_eq!(diagnostic["data"]["category"], "tooling");
        assert!(
            diagnostic["data"]["notes"]
                .as_array()
                .expect("fallback diagnostic data should include notes")
                .iter()
                .any(|note| note
                    .as_str()
                    .is_some_and(|note| note.contains("serialize LSP diagnostic JSON"))),
            "fallback diagnostic should explain the LSP serialization failure\n{rendered}"
        );
        assert!(
            !rendered.starts_with("laniusc:"),
            "LSP JSON diagnostics must not fall back to text prefixes on serialization failure"
        );
    }

    #[test]
    fn text_error_renderer_lowers_plain_cli_messages_to_diagnostics() {
        let rendered = render_error(
            DiagnosticFormat::Text,
            CliError::from("serialize doctor report: broken pipe"),
        );

        assert!(rendered.contains("error[LNC0067]: CLI operation failed"));
        assert!(rendered.contains("tooling detail: serialize doctor report: broken pipe"));
        assert!(
            !rendered.starts_with("laniusc:"),
            "text diagnostics should render through the same diagnostic spine as JSON/LSP"
        );
    }
}
