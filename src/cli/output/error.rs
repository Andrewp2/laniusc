use laniusc::compiler::Diagnostic;

#[derive(Debug)]
pub(crate) enum CliOutputError {
    Diagnostic(Diagnostic),
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
