mod common;

use laniusc_compiler::{
    lexer::driver::GpuLexer,
    parser::{driver::GpuParser, tables::PrecomputedParseTables},
};

#[test]
fn parser_nonresident_parse_classifies_raw_lexer_tokens() {
    common::block_on_gpu_with_timeout("nonresident parser raw token classification", async move {
        let source = "fn main() { let x = 1 + 2; return x; }";
        let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tables/parse_tables.bin"
        )))
        .expect("load precomputed parse tables");
        let lexer = GpuLexer::new().await.expect("create GPU lexer");
        let parser = GpuParser::new().await.expect("create GPU parser");

        let tokens = lexer.lex(source).await.expect("lex source");
        let mut raw_kinds = tokens
            .iter()
            .map(|token| token.kind as u32)
            .collect::<Vec<_>>();
        raw_kinds.insert(0, 0);
        raw_kinds.push(0);

        let nonresident = parser
            .parse(&raw_kinds, &tables)
            .await
            .expect("nonresident parse should accept raw lexer token kinds");
        assert!(
            nonresident.ll1.accepted,
            "nonresident parser rejected raw lexer token stream: error_pos={} code={} detail={}",
            nonresident.ll1.error_pos, nonresident.ll1.error_code, nonresident.ll1.detail
        );

        let resident = lexer
            .with_resident_tokens(source, |_, _, buffers| {
                parser.parse_resident_tokens(
                    buffers.n,
                    &buffers.tokens_out,
                    &buffers.token_count,
                    &tables,
                )
            })
            .await
            .expect("resident lex should succeed")
            .expect("resident parse should succeed");

        assert!(
            resident.ll1.accepted,
            "resident parser should accept fixture"
        );
        assert_eq!(nonresident.ll1.emit_len, resident.ll1.emit_len);
        assert_eq!(nonresident.node_kind, resident.node_kind);
        assert_eq!(nonresident.parent, resident.parent);
    });
}
