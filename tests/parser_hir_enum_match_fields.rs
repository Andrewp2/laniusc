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
fn gpu_resident_ll1_hir_enum_match_fields_are_tree_derived() {
    common::block_on_gpu_with_timeout("GPU parser HIR enum/match metadata", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = r#"
enum Option<T> {
    Some(T),
    None,
}

fn unwrap_or(value: Option<i32>, fallback: i32) -> i32 {
    let out = match (value) {
        Some(inner) -> inner,
        None -> fallback,
    };
    return out;
}

fn qualified(value: Option<i32>) -> i32 {
    let out = match (value) {
        core::option::Some(inner) -> inner,
        None -> 0,
    };
    return out;
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
            res.hir_variant_parent_enum.len(),
            res.hir_variant_ordinal.len(),
            res.hir_variant_payload_start.len(),
            res.hir_variant_payload_count.len(),
            res.hir_match_scrutinee_node.len(),
            res.hir_match_arm_start.len(),
            res.hir_match_arm_count.len(),
            res.hir_match_arm_pattern_node.len(),
            res.hir_match_arm_payload_start.len(),
            res.hir_match_arm_payload_count.len(),
            res.hir_match_arm_result_node.len(),
        ] {
            assert_eq!(field_len, res.node_kind.len());
        }

        let variants = res
            .hir_variant_parent_enum
            .iter()
            .enumerate()
            .filter_map(|(i, &parent_enum)| {
                if parent_enum == INVALID {
                    return None;
                }
                Some((
                    hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        i as u32,
                    )
                    .unwrap(),
                    hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        parent_enum,
                    )
                    .unwrap(),
                    res.hir_variant_ordinal[i],
                    res.hir_variant_payload_count[i],
                    hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        res.hir_variant_payload_start[i],
                    ),
                ))
            })
            .collect::<Vec<_>>();

        assert!(
            variants
                .iter()
                .any(|(variant, parent, ordinal, count, payload)| {
                    variant.starts_with("Some")
                        && parent.starts_with("enum Option")
                        && *ordinal == 0
                        && *count == 1
                        && payload.as_deref().is_some_and(|span| span.starts_with("T"))
                }),
            "missing Some(T) enum variant metadata: {variants:?}"
        );
        assert!(
            variants
                .iter()
                .any(|(variant, parent, ordinal, count, payload)| {
                    variant.starts_with("None")
                        && parent.starts_with("enum Option")
                        && *ordinal == 1
                        && *count == 0
                        && payload.is_none()
                }),
            "missing None enum variant metadata: {variants:?}"
        );

        let match_records = res
            .hir_match_arm_count
            .iter()
            .enumerate()
            .filter_map(|(i, &arm_count)| {
                if arm_count == 0 {
                    return None;
                }
                Some((
                    hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        res.hir_match_scrutinee_node[i],
                    )
                    .unwrap(),
                    hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        res.hir_match_arm_start[i],
                    )
                    .unwrap(),
                    arm_count,
                ))
            })
            .collect::<Vec<_>>();
        assert_eq!(
            match_records.len(),
            2,
            "expected both match expressions to publish metadata: {match_records:?}"
        );
        assert!(
            match_records
                .iter()
                .all(|(scrutinee, first_arm, arm_count)| {
                    scrutinee.starts_with("value") && first_arm.contains("Some") && *arm_count == 2
                }),
            "unexpected match expression metadata: {match_records:?}"
        );

        let arms = res
            .hir_match_arm_pattern_node
            .iter()
            .enumerate()
            .filter_map(|(i, &pattern)| {
                if pattern == INVALID {
                    return None;
                }
                Some((
                    hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        pattern,
                    )
                    .unwrap(),
                    hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        res.hir_match_arm_payload_start[i],
                    ),
                    res.hir_match_arm_payload_count[i],
                    hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        res.hir_match_arm_result_node[i],
                    )
                    .unwrap(),
                ))
            })
            .collect::<Vec<_>>();

        assert!(
            arms.iter().any(|(pattern, payload, count, result)| {
                pattern == "Some(inner)"
                    && payload
                        .as_deref()
                        .is_some_and(|span| span.starts_with("inner"))
                    && *count == 1
                    && result.starts_with("inner")
            }),
            "missing local constructor arm metadata: {arms:?}"
        );
        assert!(
            arms.iter().any(|(pattern, payload, count, result)| {
                pattern == "core::option::Some(inner)"
                    && payload
                        .as_deref()
                        .is_some_and(|span| span.starts_with("inner"))
                    && *count == 1
                    && result.starts_with("inner")
            }),
            "missing qualified constructor arm metadata: {arms:?}"
        );
        assert!(
            arms.iter().any(|(pattern, payload, count, result)| {
                pattern.starts_with("None")
                    && payload.is_none()
                    && *count == 0
                    && result.starts_with("fallback")
            }),
            "missing unit constructor arm metadata: {arms:?}"
        );
    });
}

#[test]
fn gpu_resident_ll1_hir_match_arm_results_follow_qualified_unit_patterns() {
    common::block_on_gpu_with_timeout(
        "GPU parser HIR match-arm result metadata for qualified unit patterns",
        async move {
            let lexer = GpuLexer::new().await.expect("GPU lexer init");
            let parser = GpuParser::new().await.expect("GPU parser init");
            let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(
                "../tables/parse_tables.bin"
            ))
            .expect("load generated parse tables");
            let src = r#"
enum Ordering {
    Less,
    Equal,
    Greater,
}

fn main(order: Ordering) -> i32 {
    let out = match (order) {
        Ordering::Less -> 1,
        Ordering::Equal -> 2,
        Ordering::Greater -> 0,
    };
    return out;
}
"#;
            let tokens = lex_on_test_cpu(src).expect("test CPU oracle lex fixture");

            let res = lexer
                .with_resident_tokens(src, |_, _, bufs| {
                    parser.parse_resident_tokens(
                        bufs.n,
                        &bufs.tokens_out,
                        &bufs.token_count,
                        &tables,
                    )
                })
                .await
                .expect("resident GPU lex")
                .expect("resident GPU parse");

            assert!(res.ll1.accepted, "resident LL(1) parser rejected fixture");

            let arms = res
                .hir_match_arm_pattern_node
                .iter()
                .enumerate()
                .filter_map(|(i, &pattern)| {
                    if pattern == INVALID {
                        return None;
                    }
                    Some((
                        hir_node_snippet(
                            src,
                            &tokens,
                            &res.hir_token_pos,
                            &res.hir_token_end,
                            pattern,
                        )
                        .unwrap(),
                        hir_node_snippet(
                            src,
                            &tokens,
                            &res.hir_token_pos,
                            &res.hir_token_end,
                            res.hir_match_arm_result_node[i],
                        )
                        .unwrap(),
                    ))
                })
                .collect::<Vec<_>>();

            for (pattern, result) in [
                ("Ordering::Less", "1"),
                ("Ordering::Equal", "2"),
                ("Ordering::Greater", "0"),
            ] {
                assert!(
                    arms.iter().any(|(actual_pattern, actual_result)| {
                        actual_pattern.starts_with(pattern)
                            && actual_result.starts_with(result)
                            && !actual_result.contains("Ordering::")
                    }),
                    "missing match-arm metadata ({pattern} -> {result}): {arms:?}"
                );
            }
        },
    );
}

#[test]
fn hir_enum_match_fields_pass_is_wired_without_token_text_access() {
    let shader = include_str!("../shaders/parser/hir_enum_match_fields.slang");
    let pass = include_str!("../src/parser/passes/hir_enum_match_fields.rs");
    let buffers = include_str!("../src/parser/buffers.rs");
    let driver = include_str!("../src/parser/driver.rs");
    let resident_tree = include_str!("../src/parser/driver/resident_tree.rs");
    let passes = include_str!("../src/parser/passes/mod.rs");

    for required in [
        "StructuredBuffer<uint> node_kind",
        "StructuredBuffer<uint> parent",
        "StructuredBuffer<uint> subtree_end",
        "PROD_ENUM_VARIANT",
        "PROD_MATCH_EXPR",
        "PROD_MATCH_ARM",
        "nearest_pattern_ancestor_before",
        "has_hir_type_ancestor_before",
    ] {
        assert!(
            shader.contains(required),
            "HIR enum/match metadata should be derived from tree arrays: {required}"
        );
    }

    for forbidden in [
        "TokenIn",
        "token_words",
        "source_bytes",
        "token_kind(",
        "same_text(",
        "is_type_name_token",
        "record_error",
    ] {
        assert!(
            !shader.contains(forbidden),
            "HIR enum/match metadata must not inspect token text: {forbidden}"
        );
    }

    for required in [
        "hir_enum_match_fields",
        "hir_variant_parent_enum",
        "hir_match_scrutinee_node",
        "hir_match_arm_result_node",
    ] {
        assert!(pass.contains(required) || buffers.contains(required));
        assert!(driver.contains(required) || resident_tree.contains(required));
    }
    assert!(passes.contains("pub mod hir_enum_match_fields;"));
    assert!(passes.contains("hir_enum_match_fields.record_pass"));
}

#[test]
fn gpu_ll1_hir_enum_match_fields_capture_nonresident_parser_results() {
    common::block_on_gpu_with_timeout(
        "GPU parser nonresident HIR enum/match metadata",
        async move {
            let parser = GpuParser::new().await.expect("GPU parser init");
            let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(
                "../tables/parse_tables.bin"
            ))
            .expect("load generated parse tables");
            let src = "enum Maybe { Some(i32), None } fn main(value: Maybe) { let out = match (value) { Some(inner) -> inner, None -> 0, }; return; }";
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
                .expect("GPU parse enum/match fixture");

            assert!(res.ll1.accepted, "LL(1) parser rejected fixture");
            assert_eq!(res.hir_variant_parent_enum.len(), res.node_kind.len());
            assert_eq!(res.hir_match_arm_result_node.len(), res.node_kind.len());
            assert!(
                res.hir_variant_ordinal.iter().any(|&ordinal| ordinal == 1),
                "expected variant ordinals to include the second variant"
            );
            assert!(
                res.hir_match_arm_count.iter().any(|&count| count == 2),
                "expected match expression metadata for two arms"
            );
        },
    );
}
