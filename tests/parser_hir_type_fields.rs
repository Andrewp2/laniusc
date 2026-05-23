mod common;

use laniusc::{
    lexer::{
        driver::GpuLexer,
        test_cpu::{TestCpuToken, lex_on_test_cpu},
    },
    parser::{
        driver::GpuParser,
        passes::{
            hir_item_fields::HIR_ITEM_KIND_TYPE_ALIAS,
            hir_type_fields::{
                HIR_TYPE_FORM_ARRAY,
                HIR_TYPE_FORM_PATH,
                HIR_TYPE_FORM_REF,
                HIR_TYPE_FORM_SLICE,
            },
        },
        tables::PrecomputedParseTables,
    },
};

#[test]
fn gpu_resident_ll1_hir_type_fields_are_exposed_to_downstream_passes() {
    common::block_on_gpu_with_timeout("GPU resident parser HIR type-form metadata", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = "fn sample<const N: usize>(value: &i32, values: [i32; N], bytes: [u8], nested: &[i32], qualified: core::slice::Slice<i32>) -> &[i32] { return nested; }";
        let tokens = lex_on_test_cpu(src).expect("test CPU oracle lex fixture");

        let res = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.parse_resident_tokens(bufs.n, &bufs.tokens_out, &bufs.token_count, &tables)
            })
            .await
            .expect("resident GPU lex")
            .expect("resident GPU parse");

        assert!(res.ll1.accepted, "resident LL(1) parser rejected fixture");
        assert_eq!(res.hir_type_form.len(), res.node_kind.len());
        assert_eq!(res.hir_type_value_node.len(), res.node_kind.len());
        assert_eq!(res.hir_type_len_token.len(), res.node_kind.len());
        assert_eq!(res.hir_type_file_id.len(), res.node_kind.len());
        assert_eq!(res.hir_type_path_leaf_node.len(), res.node_kind.len());
        assert_eq!(res.hir_type_arg_start.len(), res.node_kind.len());
        assert_eq!(res.hir_type_arg_count.len(), res.node_kind.len());
        assert_eq!(res.hir_type_arg_next.len(), res.node_kind.len());

        let type_records = res
            .hir_type_form
            .iter()
            .enumerate()
            .filter_map(|(i, &form)| {
                if form == 0 {
                    return None;
                }
                let snippet = hir_node_snippet(
                    src,
                    &tokens,
                    &res.hir_token_pos,
                    &res.hir_token_end,
                    i as u32,
                )
                .unwrap_or_else(|| "<bad-span>".to_string());
                let value_form = res
                    .hir_type_value_node
                    .get(i)
                    .and_then(|&value_node| res.hir_type_form.get(value_node as usize))
                    .copied()
                    .unwrap_or(0);
                let len = token_snippet(src, &tokens, res.hir_type_len_token[i]);
                let leaf = res.hir_type_path_leaf_node.get(i).and_then(|&leaf_node| {
                    res.hir_token_pos
                        .get(leaf_node as usize)
                        .and_then(|&token| token_snippet(src, &tokens, token))
                });
                Some((
                    form,
                    snippet,
                    value_form,
                    len,
                    res.hir_type_file_id[i],
                    leaf,
                ))
            })
            .collect::<Vec<_>>();

        assert!(
            type_records
                .iter()
                .any(|(form, snippet, value_form, len, file_id, _leaf)| {
                    *form == HIR_TYPE_FORM_ARRAY
                        && snippet.starts_with("[i32;")
                        && *value_form == HIR_TYPE_FORM_PATH
                        && len.as_deref() == Some("N")
                        && *file_id == 0
                }),
            "expected resident array type metadata for [i32; N], got {type_records:?}"
        );
        assert!(
            type_records
                .iter()
                .any(|(form, snippet, value_form, len, file_id, _leaf)| {
                    *form == HIR_TYPE_FORM_SLICE
                        && snippet.starts_with("[u8")
                        && *value_form == HIR_TYPE_FORM_PATH
                        && len.is_none()
                        && *file_id == 0
                }),
            "expected resident slice type metadata for [u8], got {type_records:?}"
        );
        assert!(
            type_records
                .iter()
                .any(|(form, snippet, value_form, len, file_id, _leaf)| {
                    *form == HIR_TYPE_FORM_REF
                        && snippet.starts_with("&[i32")
                        && *value_form == HIR_TYPE_FORM_SLICE
                        && len.is_none()
                        && *file_id == 0
                }),
            "expected resident reference type metadata for &[i32], got {type_records:?}"
        );
        assert!(
            type_records
                .iter()
                .any(|(form, snippet, _value_form, _len, file_id, leaf)| {
                    *form == HIR_TYPE_FORM_PATH
                        && snippet.starts_with("core::slice::Slice")
                        && leaf.as_deref() == Some("Slice")
                        && *file_id == 0
                }),
            "expected pointer-jumped qualified type path leaf metadata, got {type_records:?}"
        );
    });
}

#[test]
fn gpu_resident_ll1_hir_type_fields_include_array_type_alias_targets() {
    common::block_on_gpu_with_timeout(
        "GPU resident parser array type-alias target metadata",
        async move {
            let lexer = GpuLexer::new().await.expect("GPU lexer init");
            let parser = GpuParser::new().await.expect("GPU parser init");
            let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(
                "../tables/parse_tables.bin"
            ))
            .expect("load generated parse tables");
            let src = "type Four = [i32; 4]; fn main(values: Four) { return; }";
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
            let records = res
                .hir_type_form
                .iter()
                .enumerate()
                .filter_map(|(i, &form)| {
                    if form == 0 {
                        return None;
                    }
                    let snippet = hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        i as u32,
                    )
                    .unwrap_or_else(|| "<bad-span>".to_string());
                    let value_form = res
                        .hir_type_value_node
                        .get(i)
                        .and_then(|&value_node| res.hir_type_form.get(value_node as usize))
                        .copied()
                        .unwrap_or(0);
                    let value_snippet = res.hir_type_value_node.get(i).and_then(|&value_node| {
                        hir_node_snippet(
                            src,
                            &tokens,
                            &res.hir_token_pos,
                            &res.hir_token_end,
                            value_node,
                        )
                    });
                    Some((form, snippet, value_form, value_snippet))
                })
                .collect::<Vec<_>>();
            let array_node = res
                .hir_type_form
                .iter()
                .enumerate()
                .find_map(|(i, &form)| {
                    if form != HIR_TYPE_FORM_ARRAY {
                        return None;
                    }
                    let snippet = hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        i as u32,
                    )?;
                    snippet.starts_with("[i32;").then_some(i as u32)
                })
                .expect("array type-alias target node");
            let alias_node = res
                .hir_item_kind
                .iter()
                .position(|&kind| kind == HIR_ITEM_KIND_TYPE_ALIAS)
                .expect("type alias item node");

            assert!(
                records.iter().any(|(form, snippet, value_form, value)| {
                    *form == HIR_TYPE_FORM_ARRAY
                        && snippet.starts_with("[i32;")
                        && *value_form == HIR_TYPE_FORM_PATH
                        && value
                            .as_deref()
                            .is_some_and(|snippet| snippet.starts_with("i32"))
                }),
                "expected array type-alias target metadata, got {records:?}"
            );
            assert_eq!(
                res.hir_type_alias_target_node[alias_node], array_node,
                "type alias item should publish its array target node"
            );
        },
    );
}

#[test]
fn gpu_resident_ll1_hir_type_args_are_link_rank_scattered() {
    common::block_on_gpu_with_timeout(
        "GPU resident parser HIR type argument metadata",
        async move {
            let lexer = GpuLexer::new().await.expect("GPU lexer init");
            let parser = GpuParser::new().await.expect("GPU parser init");
            let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(
                "../tables/parse_tables.bin"
            ))
            .expect("load generated parse tables");
            let src = "fn sample(value: Result<i32, u8>) { return; }";
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
            let records = res
                .hir_type_form
                .iter()
                .enumerate()
                .filter_map(|(i, &form)| {
                    if form != HIR_TYPE_FORM_PATH || res.hir_type_arg_count[i] == 0 {
                        return None;
                    }
                    let arg_start = res.hir_type_arg_start[i];
                    let first = hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        arg_start,
                    );
                    let second = if arg_start != u32::MAX {
                        hir_node_snippet(
                            src,
                            &tokens,
                            &res.hir_token_pos,
                            &res.hir_token_end,
                            res.hir_type_arg_next[arg_start as usize],
                        )
                    } else {
                        None
                    };
                    Some((
                        hir_node_snippet(
                            src,
                            &tokens,
                            &res.hir_token_pos,
                            &res.hir_token_end,
                            i as u32,
                        )
                        .unwrap_or_else(|| "<bad-span>".to_string()),
                        res.hir_type_arg_count[i],
                        first,
                        second,
                    ))
                })
                .collect::<Vec<_>>();

            assert!(
                records.iter().any(|(snippet, count, first, second)| {
                    snippet.starts_with("Result")
                        && *count == 2
                        && first.as_deref().is_some_and(|arg| arg.starts_with("i32"))
                        && second.as_deref().is_some_and(|arg| arg.starts_with("u8"))
                }),
                "expected generic type argument records for Result<i32, u8>, got {records:?}"
            );

            let qualified_src = "fn sample(value: core::result::Result<i32, u8>) { return; }";
            let qualified_tokens =
                lex_on_test_cpu(qualified_src).expect("test CPU oracle lex fixture");
            let qualified_res = lexer
                .with_resident_tokens(qualified_src, |_, _, bufs| {
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
            assert!(
                qualified_res.ll1.accepted,
                "resident LL(1) parser rejected qualified generic fixture"
            );
            let qualified_records = qualified_res
                .hir_type_form
                .iter()
                .enumerate()
                .filter_map(|(i, &form)| {
                    if form != HIR_TYPE_FORM_PATH || qualified_res.hir_type_arg_count[i] == 0 {
                        return None;
                    }
                    Some((
                        hir_node_snippet(
                            qualified_src,
                            &qualified_tokens,
                            &qualified_res.hir_token_pos,
                            &qualified_res.hir_token_end,
                            i as u32,
                        )
                        .unwrap_or_else(|| "<bad-span>".to_string()),
                        qualified_res.hir_type_arg_count[i],
                    ))
                })
                .collect::<Vec<_>>();
            assert!(
                qualified_records.iter().any(|(snippet, count)| snippet
                    .starts_with("core::result::Result")
                    && *count == 2),
                "expected qualified generic type arguments on path root, got {qualified_records:?}"
            );
        },
    );
}

fn token_snippet(src: &str, tokens: &[TestCpuToken], token: u32) -> Option<String> {
    let token = token as usize;
    let t = tokens.get(token)?;
    Some(src[t.start..t.start + t.len].to_string())
}

fn token_span_snippet(src: &str, tokens: &[TestCpuToken], start: u32, end: u32) -> Option<String> {
    if start == u32::MAX || end == u32::MAX || start >= end {
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
