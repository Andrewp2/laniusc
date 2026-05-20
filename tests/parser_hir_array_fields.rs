mod common;

use laniusc::{
    lexer::{
        driver::GpuLexer,
        test_cpu::{lex_on_test_cpu, TestCpuToken},
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

#[test]
fn gpu_resident_ll1_hir_array_fields_are_tree_derived() {
    common::block_on_gpu_with_timeout("GPU parser HIR array metadata", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = r#"
fn main() {
    let values = [1, 2 + 3, 4,];
    return;
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
            res.hir_array_lit_first_element.len(),
            res.hir_array_lit_element_count.len(),
            res.hir_array_element_parent_lit.len(),
            res.hir_array_element_ordinal.len(),
            res.hir_array_element_next.len(),
        ] {
            assert_eq!(field_len, res.node_kind.len());
        }

        let arrays = res
            .hir_array_lit_element_count
            .iter()
            .enumerate()
            .filter_map(|(i, &element_count)| {
                if element_count == 0 {
                    return None;
                }
                Some((
                    i as u32,
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
                        res.hir_array_lit_first_element[i],
                    )
                    .unwrap(),
                    element_count,
                ))
            })
            .collect::<Vec<_>>();

        let (array_node, _array_span, _first_element, count) = arrays
            .iter()
            .find(|(_, span, first, count)| {
                span.starts_with("[1, 2 + 3, 4") && first.starts_with("1") && *count == 3
            })
            .unwrap_or_else(|| panic!("missing array literal metadata: {arrays:?}"));

        let elements = res
            .hir_array_element_parent_lit
            .iter()
            .enumerate()
            .filter_map(|(i, &parent_array)| {
                if parent_array != *array_node {
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
                    res.hir_array_element_ordinal[i],
                    hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        res.hir_array_element_next[i],
                    ),
                ))
            })
            .collect::<Vec<_>>();

        assert_eq!(*count, 3);
        assert!(
            elements.iter().any(|(span, ordinal, next)| {
                span.starts_with("1")
                    && *ordinal == 0
                    && next
                        .as_deref()
                        .is_some_and(|next| next.starts_with("2 + 3"))
            }),
            "missing first array element metadata: {elements:?}"
        );
        assert!(
            elements.iter().any(|(span, ordinal, next)| {
                span.starts_with("2 + 3")
                    && *ordinal == 1
                    && next.as_deref().is_some_and(|next| next.starts_with("4"))
            }),
            "missing second array element metadata: {elements:?}"
        );
        assert!(
            elements
                .iter()
                .any(|(span, ordinal, next)| span.starts_with("4")
                    && *ordinal == 2
                    && next.is_none()),
            "missing third array element metadata: {elements:?}"
        );
    });
}
