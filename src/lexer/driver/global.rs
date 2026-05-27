use std::sync::OnceLock;

use anyhow::{Result, anyhow};

use super::GpuLexer;
use crate::lexer::types::Token;

static GPU_LEXER: OnceLock<Result<GpuLexer, String>> = OnceLock::new();

pub fn try_global_lexer() -> Result<&'static GpuLexer> {
    GPU_LEXER
        .get_or_init(|| pollster::block_on(GpuLexer::new()).map_err(|err| err.to_string()))
        .as_ref()
        .map_err(|err| anyhow!("GPU init: {err}"))
}

pub async fn get_global_lexer() -> &'static GpuLexer {
    try_global_lexer().expect("GPU init")
}

pub async fn lex_on_gpu(input: &str) -> Result<Vec<Token>> {
    get_global_lexer().await.lex(input).await
}
