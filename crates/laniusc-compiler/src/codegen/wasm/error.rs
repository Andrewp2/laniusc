use std::fmt;

#[derive(Debug)]
/// Target-level error reported by the GPU WASM emitter.
pub struct WasmOutputError {
    error_name: &'static str,
    error_code: u32,
    error_detail: u32,
}

impl WasmOutputError {
    /// Creates a target-level WASM output error from backend status fields.
    fn new(error_name: &'static str, error_code: u32, error_detail: u32) -> Self {
        Self {
            error_name,
            error_code,
            error_detail,
        }
    }

    /// Returns the backend status name associated with this error.
    pub fn error_name(&self) -> &'static str {
        self.error_name
    }

    /// Returns a user-facing diagnostic message for this backend boundary.
    pub fn public_message(&self) -> String {
        self.error_name.replace('_', " ")
    }

    /// Returns the numeric backend status code.
    pub fn error_code(&self) -> u32 {
        self.error_code
    }

    /// Returns the status detail word reported by the backend.
    pub fn error_detail(&self) -> u32 {
        self.error_detail
    }

    /// Returns whether `error_detail` should be interpreted as a token index.
    pub fn detail_is_token(&self) -> bool {
        self.error_detail != u32::MAX
            && (self.error_code == 1
                || self.error_code == 2
                || ((800..=899).contains(&self.error_code)
                    && !matches!(self.error_code, 830 | 831)))
    }
}

impl fmt::Display for WasmOutputError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("WASM code generation reached an unsupported backend boundary")
    }
}

impl std::error::Error for WasmOutputError {}

pub(super) fn from_status(error_code: u32, error_detail: u32) -> WasmOutputError {
    let error_name = match error_code {
        2 => "unsupported for loop",
        3 => "unsupported WASM body HIR-node budget",
        830 => "unsupported array-helper body token budget",
        831 => "unsupported array-helper body HIR-node budget",
        800..=899 => "unsupported array-helper body shape",
        902 => "retired enum-match module token budget",
        903 => "retired enum-match module HIR-node budget",
        900..=999 => "unsupported retired enum-match module shape",
        _ => "unsupported source shape",
    };
    WasmOutputError::new(error_name, error_code, error_detail)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn display_is_user_facing() {
        let error = WasmOutputError::new("unsupported_struct_literal", 830, 27);
        let rendered = error.to_string();

        assert_eq!(
            rendered,
            "WASM code generation reached an unsupported backend boundary"
        );
        assert!(!rendered.contains("GPU"));
        assert!(!rendered.contains("emitter rejected"));
        assert!(!rendered.contains("unsupported_struct_literal"));
        assert!(!rendered.contains("code 830"));
        assert!(!rendered.contains("detail 27"));
    }

    #[test]
    fn public_message_humanizes_backend_status() {
        let error = WasmOutputError::new("unsupported_struct_literal", 830, 27);

        let message = error.public_message();
        assert_eq!(message, "unsupported struct literal");
        assert!(!message.contains("unsupported_struct_literal"));
        assert!(!message.contains("830"));
        assert!(!message.contains("27"));
    }

    #[test]
    fn unsupported_shape_detail_is_a_token() {
        let error = WasmOutputError::new("unsupported source shape", 1, 5);
        assert!(error.detail_is_token());

        let missing = WasmOutputError::new("unsupported source shape", 1, u32::MAX);
        assert!(!missing.detail_is_token());
    }
}
