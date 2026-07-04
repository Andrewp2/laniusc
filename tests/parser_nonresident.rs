mod common;

use laniusc_compiler::{
    lexer::{driver::GpuLexer, test_cpu::lex_on_test_cpu},
    parser::{driver::GpuParser, syntax, tables::PrecomputedParseTables},
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

#[test]
fn parser_nonresident_accepts_float_literal_local() {
    common::block_on_gpu_with_timeout("nonresident parser f32 literal local", async move {
        let source = r#"
module app::main;

fn main() -> i32 {
    let one: f32 = 1.0;
    return 0;
}
"#;
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
            "nonresident parser rejected f32 literal local: error_pos={} code={} detail={}",
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
    });
}

#[test]
fn parser_pair_table_matches_ll1_for_float_literal_local() {
    common::block_on_gpu_with_timeout("parser pair table f32 literal local", async move {
        let source = include_str!("fixtures/wasm/f32_literal_local.lani");
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

        let semantic_kinds = parser
            .debug_semantic_token_kinds_for_raw_token_kinds(&raw_kinds, &tables)
            .expect("classify parser semantic tokens");
        let ll1_stream = tables
            .test_cpu_ll1_production_stream(&semantic_kinds)
            .expect("CPU LL(1) oracle should accept fixture");
        let pair_stream = tables.test_cpu_partial_parse_stream(&semantic_kinds);

        assert_eq!(
            pair_stream, ll1_stream,
            "adjacent-pair production table must reproduce the LL(1) production stream"
        );
    });
}

#[test]
fn lexer_source_pack_counts_float_literal_local_tokens() {
    common::block_on_gpu_with_timeout("source-pack lexer f32 literal local", async move {
        let source = include_str!("fixtures/wasm/f32_literal_local.lani");
        let lexer = GpuLexer::new().await.expect("create GPU lexer");
        let single = lexer.lex(source).await.expect("lex single source");
        let source_pack = lexer
            .lex_source_pack(&[source])
            .await
            .expect("lex source pack");
        assert_eq!(
            source_pack.len(),
            single.len(),
            "source-pack lexer should retain the same token count as single-source lexing"
        );
    });
}

#[test]
fn lexer_source_pack_after_count_reports_token_count() {
    common::block_on_gpu_with_timeout("source-pack lexer after-count contract", async move {
        let source = r#"
module app::main;

fn main() -> i32 {
    let one: f32 = 1.0;
    return 0;
}
"#;
        let lexer = GpuLexer::new().await.expect("create GPU lexer");
        let expected = lex_on_test_cpu(source)
            .expect("test CPU lexer should accept source")
            .len() as u32;
        assert!(
            expected > 10,
            "fixture should produce a real parser token stream, got {expected}"
        );
        let observed = lexer
            .with_recorded_resident_source_pack_tokens_after_count(
                &[source],
                |_, _, _, token_count, _, _| Ok::<_, anyhow::Error>(token_count),
                |_, _, token_count| Ok::<_, anyhow::Error>(token_count),
            )
            .await
            .expect("after-count source-pack lex should run")
            .expect("after-count callback should succeed");
        assert_eq!(
            observed, expected,
            "source-pack after-count callback should receive lexer token count"
        );
    });
}

#[test]
fn parser_syntax_accepts_float_literal_local() {
    common::block_on_gpu_with_timeout("syntax f32 literal local", async move {
        let source = include_str!("fixtures/wasm/f32_literal_local.lani");
        let lexer = GpuLexer::new().await.expect("create GPU lexer");
        let tokens = lexer.lex(source).await.expect("lex source");
        syntax::check_tokens_on_gpu(&tokens)
            .await
            .expect("syntax checker should accept f32 literal local");
    });
}

#[test]
fn parser_rejects_tokenizable_grammar_errors() {
    common::block_on_gpu_with_timeout("parser rejects tokenizable grammar errors", async move {
        let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tables/parse_tables.bin"
        )))
        .expect("load precomputed parse tables");
        let lexer = GpuLexer::new().await.expect("create GPU lexer");
        let parser = GpuParser::new().await.expect("create GPU parser");

        for source in [
            "fn main() { let x = 1 + 2 return x; }",
            "fn main() { else { return; } }",
            "fn main() { return (1 + 2; }",
        ] {
            let tokens = lexer.lex(source).await.expect("lex invalid source");
            let mut raw_kinds = tokens
                .iter()
                .map(|token| token.kind as u32)
                .collect::<Vec<_>>();
            raw_kinds.insert(0, 0);
            raw_kinds.push(0);

            let semantic_kinds = parser
                .debug_semantic_token_kinds_for_raw_token_kinds(&raw_kinds, &tables)
                .expect("classify parser semantic tokens");
            assert!(
                tables
                    .test_cpu_ll1_production_stream(&semantic_kinds)
                    .is_err(),
                "test fixture should be invalid according to the LL(1) oracle: {source}"
            );

            let nonresident = parser
                .parse(&raw_kinds, &tables)
                .await
                .expect("nonresident parse should run for invalid source");
            assert!(
                !nonresident.ll1.accepted,
                "nonresident parser accepted invalid source {source:?}; brackets valid={} final_depth={} min_depth={}",
                nonresident.brackets.valid,
                nonresident.brackets.final_depth,
                nonresident.brackets.min_depth
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
                .expect("resident parse should run for invalid source");
            assert!(
                !resident.ll1.accepted,
                "resident parser accepted invalid source {source:?}"
            );
        }
    });
}
