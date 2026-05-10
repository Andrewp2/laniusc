pub mod gpu;
pub mod tables;

/// TEST-ONLY CPU lexer oracle.
///
/// This module exists for integration tests and fuzz-test tooling that compare
/// GPU lexer output against an intentionally named host oracle. Compiler code
/// must not call it or use it as a fallback.
#[doc(hidden)]
pub mod test_cpu;
