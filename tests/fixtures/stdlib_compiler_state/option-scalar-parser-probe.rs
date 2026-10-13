mod common;

use laniusc_compiler::{
    lexer::driver::GpuLexer,
    parser::{driver::GpuParser, tables::PrecomputedParseTables},
};

#[test]
fn inspect_option_function_name_classification() {
    common::block_on_gpu_with_timeout("Option parser probe", async move {
        let source = include_str!("../stdlib/core/option.lani");
        let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"), "/tables/parse_tables.bin"
        ))).unwrap();
        let lexer = GpuLexer::new().await.unwrap();
        let parser = GpuParser::new().await.unwrap();
        let tokens = lexer.lex(source).await.unwrap();
        let raw: Vec<u32> = tokens.iter().map(|token| token.kind as u32).collect();
        let semantic = parser.debug_semantic_token_kinds_for_raw_token_kinds(&raw, &tables).unwrap();
        inspect_names("raw fresh", source, &tokens, &semantic);
        for warm in [
            "fn main() -> i32 { return 0; }",
            include_str!("../stdlib/core/result_bool.lani"),
            source,
        ] {
            let current = lexer.lex(warm).await.unwrap();
            let semantic = lexer.with_resident_tokens(warm, |_, _, buffers| {
                parser.debug_semantic_token_kinds_for_resident_tokens(
                    buffers.n, &buffers.tokens_out, &buffers.token_count, &tables
                )
            }).await.unwrap().unwrap();
            inspect_names("resident sequence", warm, &current, &semantic);
            let parsed = lexer.with_resident_tokens(warm, |_, _, buffers| {
                parser.parse_resident_tokens(
                    buffers.n, &buffers.tokens_out, &buffers.token_count, &tables
                )
            }).await.unwrap().unwrap();
            assert!(parsed.ll1.accepted, "resident parse failed at {} code={} detail={}",
                parsed.ll1.error_pos, parsed.ll1.error_code, parsed.ll1.detail);
        }
    });
}

fn inspect_names(name: &str, source: &str, tokens: &[laniusc_compiler::lexer::Token], semantic: &[u32]) {
        let mut incorrect = 0;
        for (index, token) in tokens.iter().enumerate() {
            if token.kind as u32 == 67 && semantic[index + 2] != 1 {
                incorrect += 1;
                for row in index.saturating_sub(10)..(index + 15).min(tokens.len()) {
                    let token = &tokens[row];
                    let start = token.start as usize;
                    let spelling = &source[start..start + token.len as usize];
                    eprintln!("{row}: {spelling:?} raw={} semantic={}", token.kind as u32, semantic[row + 1]);
                }
            }
        }
        assert_eq!(incorrect, 0, "{name}: function names must remain identifiers");
}
