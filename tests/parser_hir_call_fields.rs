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
    let z = match (true) {
        true -> pair(4, (5 + 6)) + y,
        false -> x,
    };
    return x + y + z;
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
        assert!(
            calls.iter().any(|(callee, first_arg, count)| {
                callee == "pair"
                    && first_arg.as_deref().is_some_and(|arg| arg.starts_with("4"))
                    && *count == 2
            }),
            "call inside match result should keep grouped arguments: {calls:?}"
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
        assert!(
            args.iter().any(|(callee, arg, exact_arg, ordinal)| {
                callee == "pair"
                    && arg.starts_with("(5 + 6)")
                    && exact_arg == "(5 + 6)"
                    && *ordinal == 1
            }),
            "call inside match result should publish grouped argument as one argument: {args:?}"
        );
    });
}
