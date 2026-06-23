use crate::{cli::fallback::cli_operation_failed_diagnostic, compiler::Diagnostic};

/// Error returned while writing CLI output.
#[derive(Debug)]
pub(crate) enum CliOutputError {
    /// Structured output diagnostic.
    Diagnostic(Diagnostic),
    /// Plain output error string.
    Message(String),
}

impl From<String> for CliOutputError {
    fn from(value: String) -> Self {
        Self::Message(value)
    }
}

impl std::fmt::Display for CliOutputError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Diagnostic(diagnostic) => write!(f, "{diagnostic}"),
            Self::Message(message) => {
                write!(f, "{}", cli_operation_failed_diagnostic(message))
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_output_error_display_uses_structured_diagnostic() {
        let rendered =
            CliOutputError::from("copy linked output: broken pipe".to_string()).to_string();

        assert!(rendered.contains("error[LNC0067]: CLI operation failed"));
        assert!(rendered.contains("tooling detail: copy linked output: broken pipe"));
        assert!(!rendered.starts_with("laniusc:"));
    }
}
