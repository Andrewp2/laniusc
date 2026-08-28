use anyhow::{Context, Result, anyhow};
use laniusc_compiler::lexer::test_cpu::lex_on_test_cpu;

use crate::artifact::{SourceFile, Span, Token};

pub fn extract_tokens(path: String, bytes: Vec<u8>) -> Result<(SourceFile, Vec<Token>)> {
    let source = std::str::from_utf8(&bytes)
        .with_context(|| format!("formal extraction source {path:?} is not UTF-8"))?;
    let raw = lex_on_test_cpu(source).map_err(|message| anyhow!(message))?;
    let mut tokens = Vec::with_capacity(raw.len());
    for token in raw {
        let start = u32::try_from(token.start).context("token start exceeds u32")?;
        let end_usize = token
            .start
            .checked_add(token.len)
            .context("token end overflow")?;
        let end = u32::try_from(end_usize).context("token end exceeds u32")?;
        tokens.push(Token {
            kind: token.kind as u32,
            span: Span {
                file: 0,
                start,
                finish: end,
            },
        });
    }
    Ok((SourceFile { path, bytes }, tokens))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exports_exact_source_bytes_and_half_open_token_spans() {
        let bytes = b"pub fn f() { return 12; }".to_vec();
        let (source, tokens) = extract_tokens("f.lani".into(), bytes.clone()).unwrap();

        assert_eq!(source.bytes, bytes);
        assert_eq!(tokens[0].kind, 66);
        assert_eq!((tokens[0].span.start, tokens[0].span.finish), (0, 3));
        assert_eq!(
            &source.bytes[tokens[1].span.start as usize..tokens[1].span.finish as usize],
            b"fn"
        );
        assert!(
            tokens
                .windows(2)
                .all(|pair| pair[0].span.finish <= pair[1].span.start)
        );
    }
}
