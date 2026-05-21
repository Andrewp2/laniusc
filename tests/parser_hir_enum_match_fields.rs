mod common;

use laniusc::{
    lexer::{
        driver::GpuLexer,
        test_cpu::{TestCpuToken, lex_on_test_cpu},
    },
    parser::{driver::GpuParser, tables::PrecomputedParseTables},
};

const INVALID: u32 = u32::MAX;

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

fn node_has_ancestor(parent: &[u32], node: u32, ancestor: u32) -> bool {
    let mut cur = node;
    for _ in 0..128 {
        if cur == ancestor {
            return true;
        }
        let next = parent.get(cur as usize).copied().unwrap_or(INVALID);
        if next == INVALID || next == cur {
            return false;
        }
        cur = next;
    }
    false
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
            res.hir_match_arm_next.len(),
            res.hir_match_arm_pattern_node.len(),
            res.hir_match_arm_payload_start.len(),
            res.hir_match_arm_payload_count.len(),
            res.hir_match_arm_result_node.len(),
            res.hir_match_payload_owner_arm.len(),
            res.hir_match_payload_match_node.len(),
            res.hir_match_payload_ordinal.len(),
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
                    hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        res.hir_match_arm_next[res.hir_match_arm_start[i] as usize],
                    ),
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
                .all(|(scrutinee, first_arm, second_arm, arm_count)| {
                    scrutinee.starts_with("value")
                        && first_arm.contains("Some")
                        && second_arm
                            .as_deref()
                            .is_some_and(|arm| arm.contains("None"))
                        && *arm_count == 2
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
                    hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        res.hir_match_arm_next[i],
                    ),
                ))
            })
            .collect::<Vec<_>>();

        assert!(
            arms.iter().any(|(pattern, payload, count, result, next)| {
                pattern == "Some(inner)"
                    && payload
                        .as_deref()
                        .is_some_and(|span| span.starts_with("inner"))
                    && *count == 1
                    && result.starts_with("inner")
                    && next.as_deref().is_some_and(|span| span.contains("None"))
            }),
            "missing local constructor arm metadata: {arms:?}"
        );
        assert!(
            arms.iter().any(|(pattern, payload, count, result, next)| {
                pattern == "core::option::Some(inner)"
                    && payload
                        .as_deref()
                        .is_some_and(|span| span.starts_with("inner"))
                    && *count == 1
                    && result.starts_with("inner")
                    && next.as_deref().is_some_and(|span| span.contains("None"))
            }),
            "missing qualified constructor arm metadata: {arms:?}"
        );
        assert!(
            arms.iter().any(|(pattern, payload, count, result, next)| {
                pattern.starts_with("None")
                    && payload.is_none()
                    && *count == 0
                    && result.starts_with("fallback")
                    && next.is_none()
            }),
            "missing unit constructor arm metadata: {arms:?}"
        );

        let payload_decls = res
            .hir_match_payload_owner_arm
            .iter()
            .enumerate()
            .filter_map(|(payload_node, &owner_arm)| {
                if owner_arm == INVALID {
                    return None;
                }
                Some((
                    hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        payload_node as u32,
                    )
                    .unwrap(),
                    hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        owner_arm,
                    )
                    .unwrap(),
                    hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        res.hir_match_payload_match_node[payload_node],
                    )
                    .unwrap(),
                    res.hir_match_payload_ordinal[payload_node],
                ))
            })
            .collect::<Vec<_>>();

        assert!(
            payload_decls
                .iter()
                .any(|(payload, arm, match_expr, ordinal)| {
                    payload.starts_with("inner")
                        && arm.contains("Some")
                        && match_expr.starts_with("match")
                        && *ordinal == 0
                }),
            "missing match payload owner/ordinal records: {payload_decls:?}"
        );

        let unwrap_or_fn = res
            .hir_kind
            .iter()
            .enumerate()
            .find_map(|(i, &kind)| {
                if kind != 3 {
                    return None;
                }
                let snippet = hir_node_snippet(
                    src,
                    &tokens,
                    &res.hir_token_pos,
                    &res.hir_token_end,
                    i as u32,
                )?;
                snippet.starts_with("fn unwrap_or").then_some(i as u32)
            })
            .expect("unwrap_or function HIR node");
        let unwrap_or_params = res
            .hir_kind
            .iter()
            .enumerate()
            .filter_map(|(i, &kind)| {
                if kind != 4 || !node_has_ancestor(&res.parent, i as u32, unwrap_or_fn) {
                    return None;
                }
                hir_node_snippet(
                    src,
                    &tokens,
                    &res.hir_token_pos,
                    &res.hir_token_end,
                    i as u32,
                )
            })
            .collect::<Vec<_>>();

        assert!(
            unwrap_or_params.len() == 2
                && unwrap_or_params[0] == "value: Option<i32>"
                && unwrap_or_params[1].starts_with("fallback: i32"),
            "generic multi-parameter function should publish HIR_PARAM records: {unwrap_or_params:?}"
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
                        hir_node_snippet(
                            src,
                            &tokens,
                            &res.hir_token_pos,
                            &res.hir_token_end,
                            res.hir_match_arm_next[i],
                        ),
                    ))
                })
                .collect::<Vec<_>>();

            for (pattern, result, next_pattern) in [
                ("Ordering::Less", "1", Some("Ordering::Equal")),
                ("Ordering::Equal", "2", Some("Ordering::Greater")),
                ("Ordering::Greater", "0", None),
            ] {
                assert!(
                    arms.iter()
                        .any(|(actual_pattern, actual_result, actual_next)| {
                            actual_pattern.starts_with(pattern)
                                && actual_result.starts_with(result)
                                && !actual_result.contains("Ordering::")
                                && match next_pattern {
                                    Some(next) => actual_next
                                        .as_deref()
                                        .is_some_and(|span| span.starts_with(next)),
                                    None => actual_next.is_none(),
                                }
                        }),
                    "missing match-arm metadata ({pattern} -> {result}, next {next_pattern:?}): {arms:?}"
                );
            }
        },
    );
}

#[test]
fn gpu_resident_ll1_hir_match_arms_ignore_nested_call_commas() {
    common::block_on_gpu_with_timeout(
        "GPU parser HIR match-arm metadata with nested call commas",
        async move {
            let lexer = GpuLexer::new().await.expect("GPU lexer init");
            let parser = GpuParser::new().await.expect("GPU parser init");
            let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(
                "../tables/parse_tables.bin"
            ))
            .expect("load generated parse tables");
            let src = r#"
enum Choice {
    Left,
    Right,
}

fn mix(a: i32, b: i32, c: i32, d: i32) -> i32 {
    return a + b + c + d;
}

fn main(choice: Choice, seed: i32) -> i32 {
    let out = match (choice) {
        Left -> (mix(1, 2, 3, 4)) + seed,
        Right -> seed * 2,
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

            let match_records = res
                .hir_match_arm_count
                .iter()
                .enumerate()
                .filter_map(|(i, &arm_count)| {
                    if arm_count == 0 {
                        return None;
                    }
                    let first_arm = res.hir_match_arm_start[i];
                    let second_arm = res
                        .hir_match_arm_next
                        .get(first_arm as usize)
                        .copied()
                        .unwrap_or(INVALID);
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
                            first_arm,
                        )
                        .unwrap(),
                        hir_node_snippet(
                            src,
                            &tokens,
                            &res.hir_token_pos,
                            &res.hir_token_end,
                            second_arm,
                        ),
                        arm_count,
                    ))
                })
                .collect::<Vec<_>>();

            assert!(
                match_records
                    .iter()
                    .any(|(scrutinee, first_arm, second_arm, arm_count)| {
                        scrutinee.starts_with("choice")
                            && first_arm.contains("Left")
                            && first_arm.contains("mix(1, 2, 3, 4)")
                            && second_arm
                                .as_deref()
                                .is_some_and(|arm| arm.contains("Right"))
                            && *arm_count == 2
                    }),
                "nested call argument commas must not split match-arm metadata: {match_records:?}"
            );
        },
    );
}
