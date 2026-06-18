use std::sync::OnceLock;

use anyhow::{Result, anyhow};

use super::GpuLexer;
use crate::lexer::types::Token;

static GPU_LEXER: OnceLock<Result<GpuLexer, String>> = OnceLock::new();

/// Returns the lazily initialized process-global lexer or a recoverable error.
pub fn try_global_lexer() -> Result<&'static GpuLexer> {
    GPU_LEXER
        .get_or_init(|| pollster::block_on(GpuLexer::new()).map_err(|err| err.to_string()))
        .as_ref()
        .map_err(|err| anyhow!("GPU init: {err}"))
}

/// Returns the process-global lexer, panicking if GPU initialization fails.
pub async fn get_global_lexer() -> &'static GpuLexer {
    try_global_lexer().expect("GPU init")
}

/// Lexes one source string through the process-global lexer.
pub async fn lex_on_gpu(input: &str) -> Result<Vec<Token>> {
    get_global_lexer().await.lex(input).await
}
