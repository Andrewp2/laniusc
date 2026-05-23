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

#[test]
fn gpu_resident_ll1_hir_array_fields_rank_all_literal_elements() {
    common::block_on_gpu_with_timeout("GPU resident parser HIR array metadata", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = "fn sample(seed: i32) -> i32 { let values: [i32; 4] = [seed, 1, 24, 28]; return values[2]; }";
        let tokens = lex_on_test_cpu(src).expect("test CPU oracle lex fixture");

        let res = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.parse_resident_tokens(bufs.n, &bufs.tokens_out, &bufs.token_count, &tables)
            })
            .await
            .expect("resident GPU lex")
            .expect("resident GPU parse");

        assert!(res.ll1.accepted, "resident LL(1) parser rejected fixture");

        let array_node = res
            .hir_array_lit_element_count
            .iter()
            .enumerate()
            .find_map(|(node, &count)| {
                if count != 4 {
                    return None;
                }
                let snippet = hir_node_snippet(
                    src,
                    &tokens,
                    &res.hir_token_pos,
                    &res.hir_token_end,
                    node as u32,
                )?;
                (snippet == "[seed, 1, 24, 28]").then_some(node as u32)
            })
            .expect("expected four-element array literal metadata");

        let mut node = res.hir_array_lit_first_element[array_node as usize];
        let mut elements = Vec::new();
        while node != INVALID {
            let snippet =
                hir_node_snippet(src, &tokens, &res.hir_token_pos, &res.hir_token_end, node)
                    .expect("array element snippet");
            elements.push((
                snippet.trim_end_matches([',', ']']).to_string(),
                res.hir_array_element_parent_lit[node as usize],
                res.hir_array_element_ordinal[node as usize],
            ));
            node = res.hir_array_element_next[node as usize];
        }

        assert_eq!(
            elements,
            vec![
                ("seed".to_string(), array_node, 0),
                ("1".to_string(), array_node, 1),
                ("24".to_string(), array_node, 2),
                ("28".to_string(), array_node, 3),
            ]
        );
    });
}
