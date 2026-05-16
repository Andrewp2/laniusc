mod common;

use laniusc::{
    lexer::{
        driver::GpuLexer,
        tables::tokens::TokenKind,
        test_cpu::{TestCpuToken, lex_on_test_cpu},
    },
    parser::{driver::GpuParser, tables::PrecomputedParseTables},
};

const INVALID: u32 = u32::MAX;

fn raw_parser_kind(kind: TokenKind) -> TokenKind {
    use TokenKind::*;
    match kind {
        CallLParen | GroupLParen | ParamLParen => LParen,
        GroupRParen | CallRParen | ParamRParen => RParen,
        IndexLBracket | ArrayLBracket | TypeArrayLBracket => LBracket,
        ArrayRBracket | IndexRBracket | TypeArrayRBracket => RBracket,
        PrefixPlus | InfixPlus => Plus,
        PrefixMinus | InfixMinus => Minus,
        LetIdent | ParamIdent | TypeIdent => Ident,
        LetAssign => Assign,
        ArgComma | ArrayComma | ParamComma => Comma,
        TypeSemicolon => Semicolon,
        IfLBrace => LBrace,
        IfRBrace => RBrace,
        other => other,
    }
}

fn token_span_snippet(src: &str, tokens: &[TestCpuToken], start: u32, end: u32) -> Option<String> {
    if start == INVALID || end == INVALID || start >= end {
        return None;
    }
    let start = start as usize;
    let end = end as usize;
    if end > tokens.len() {
        return None;
    }
    let byte_start = tokens[start].start;
    let last = tokens[end - 1];
    Some(src[byte_start..last.start + last.len].to_string())
}

fn hir_node_snippet(
    src: &str,
    tokens: &[TestCpuToken],
    hir_token_pos: &[u32],
    hir_token_end: &[u32],
    node: u32,
) -> Option<String> {
    let node = node as usize;
    token_span_snippet(
        src,
        tokens,
        *hir_token_pos.get(node)?,
        *hir_token_end.get(node)?,
    )
}

#[test]
fn gpu_resident_ll1_hir_call_fields_are_tree_derived() {
    common::block_on_gpu_with_timeout("GPU parser HIR call metadata", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = r#"
fn pair(a: i32, b: i32) -> i32 {
    return a + b;
}

fn main() -> i32 {
    let x = pair(1, pair(2, 3));
    let y = core::range::contains_i32(core::range::range_i32(1, 4), 3);
    return x + y;
}
"#;
        let tokens = lex_on_test_cpu(src).expect("test CPU oracle lex fixture");

        let res = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.parse_resident_tokens(bufs.n, &bufs.tokens_out, &bufs.token_count, &tables)
            })
            .await
            .expect("resident GPU lex")
            .expect("resident GPU parse");

        assert!(res.ll1.accepted, "resident LL(1) parser rejected fixture");
        for field_len in [
            res.hir_call_callee_node.len(),
            res.hir_call_arg_start.len(),
            res.hir_call_arg_end.len(),
            res.hir_call_arg_count.len(),
            res.hir_call_arg_parent_call.len(),
            res.hir_call_arg_ordinal.len(),
        ] {
            assert_eq!(field_len, res.node_kind.len());
        }

        let calls = res
            .hir_call_arg_count
            .iter()
            .enumerate()
            .filter_map(|(i, &arg_count)| {
                if res.hir_call_callee_node[i] == INVALID {
                    return None;
                }
                Some((
                    hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        res.hir_call_callee_node[i],
                    )
                    .unwrap(),
                    hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        res.hir_call_arg_start[i],
                    ),
                    arg_count,
                ))
            })
            .collect::<Vec<_>>();

        assert!(
            calls.iter().any(|(callee, first_arg, count)| {
                callee == "pair"
                    && first_arg.as_deref().is_some_and(|arg| arg.starts_with("1"))
                    && *count == 2
            }),
            "missing outer pair call metadata: {calls:?}"
        );
        assert!(
            calls.iter().any(|(callee, first_arg, count)| {
                callee == "pair"
                    && first_arg.as_deref().is_some_and(|arg| arg.starts_with("2"))
                    && *count == 2
            }),
            "missing nested pair call metadata: {calls:?}"
        );
        assert!(
            calls.iter().any(|(callee, first_arg, count)| {
                callee == "core::range::contains_i32"
                    && first_arg
                        .as_deref()
                        .is_some_and(|arg| arg.starts_with("core::range::range_i32"))
                    && *count == 2
            }),
            "missing qualified call metadata: {calls:?}"
        );

        let args = res
            .hir_call_arg_parent_call
            .iter()
            .enumerate()
            .filter_map(|(i, &call)| {
                if call == INVALID {
                    return None;
                }
                Some((
                    hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        res.hir_call_callee_node[call as usize],
                    )
                    .unwrap(),
                    hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        i as u32,
                    )
                    .unwrap(),
                    token_span_snippet(src, &tokens, res.hir_token_pos[i], res.hir_call_arg_end[i])
                        .unwrap(),
                    res.hir_call_arg_ordinal[i],
                ))
            })
            .collect::<Vec<_>>();

        assert!(
            args.iter().any(|(callee, arg, exact_arg, ordinal)| {
                callee == "pair"
                    && arg.starts_with("pair(2, 3)")
                    && exact_arg == "pair(2, 3)"
                    && *ordinal == 1
            }),
            "outer call should treat nested call as one argument: {args:?}"
        );
        assert!(
            args.iter().any(|(callee, arg, exact_arg, ordinal)| {
                callee == "core::range::contains_i32"
                    && arg.starts_with("core::range::range_i32")
                    && exact_arg == "core::range::range_i32(1, 4)"
                    && *ordinal == 0
            }),
            "qualified call should publish first argument as a HIR node: {args:?}"
        );
    });
}

#[test]
fn hir_call_fields_pass_is_wired_without_token_text_access() {
    let shader = include_str!("../shaders/parser/hir_call_fields.slang");
    let pass = include_str!("../src/parser/passes/hir_call_fields.rs");
    let buffers = include_str!("../src/parser/buffers.rs");
    let driver = include_str!("../src/parser/driver.rs");
    let resident_tree = include_str!("../src/parser/driver/resident_tree.rs");
    let passes = include_str!("../src/parser/passes/mod.rs");

    for required in [
        "StructuredBuffer<uint> node_kind",
        "StructuredBuffer<uint> parent",
        "StructuredBuffer<uint> subtree_end",
        "PROD_POSTFIX_CALL",
        "PROD_ARGS_SOME",
        "PROD_ARGS_AFTER_COMMA_MORE",
        "hir_call_callee_node",
        "hir_call_arg_end",
        "hir_call_arg_parent_call",
    ] {
        assert!(
            shader.contains(required),
            "HIR call metadata should be derived from tree arrays: {required}"
        );
    }

    for forbidden in [
        "TokenIn",
        "token_words",
        "source_bytes",
        "token_kind(",
        "same_text(",
        "find_next_open_paren",
        "matching_paren",
        "unwrap_or",
        "record_error",
    ] {
        assert!(
            !shader.contains(forbidden),
            "HIR call metadata must not inspect token text or helper names: {forbidden}"
        );
    }

    for required in [
        "hir_call_fields",
        "hir_call_callee_node",
        "hir_call_arg_start",
        "hir_call_arg_end",
        "hir_call_arg_parent_call",
    ] {
        assert!(pass.contains(required) || buffers.contains(required));
        assert!(driver.contains(required) || resident_tree.contains(required));
    }
    assert!(passes.contains("pub mod hir_call_fields;"));
    assert!(passes.contains("hir_call_fields.record_pass"));
}

#[test]
fn gpu_ll1_hir_call_fields_capture_nonresident_parser_results() {
    common::block_on_gpu_with_timeout("GPU parser nonresident HIR call metadata", async move {
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = "fn pair(a: i32, b: i32) -> i32 { return a + b; } fn main() { let x = pair(1, pair(2, 3)); return; }";
        let mut token_kinds = lex_on_test_cpu(src)
            .expect("test CPU oracle lex fixture")
            .into_iter()
            .map(|token| raw_parser_kind(token.kind) as u32)
            .collect::<Vec<_>>();
        token_kinds.insert(0, 0);
        token_kinds.push(0);

        let res = parser
            .parse(&token_kinds, &tables)
            .await
            .expect("GPU parse call fixture");

        assert!(res.ll1.accepted, "LL(1) parser rejected fixture");
        assert_eq!(res.hir_call_arg_count.len(), res.node_kind.len());
        assert_eq!(res.hir_call_arg_end.len(), res.node_kind.len());
        assert!(
            res.hir_call_arg_count.iter().any(|&count| count == 2),
            "expected call metadata for two-argument calls"
        );
        assert!(
            res.hir_call_arg_ordinal.iter().any(|&ordinal| ordinal == 1),
            "expected ordinal metadata for second call arguments"
        );
    });
}
