use crate::compiler::Diagnostic;

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
            Self::Message(message) => f.write_str(message),
        }
    }
}
