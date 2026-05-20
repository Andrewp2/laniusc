mod common;

use laniusc::{
    lexer::{
        driver::GpuLexer,
        test_cpu::{lex_on_test_cpu, TestCpuToken},
    },
    parser::{driver::GpuParser, tables::PrecomputedParseTables},
};

const INVALID: u32 = u32::MAX;

fn token_text(src: &str, tokens: &[TestCpuToken], token: u32) -> Option<String> {
    let token = token as usize;
    let token = tokens.get(token)?;
    Some(src[token.start..token.start + token.len].to_string())
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

#[derive(Debug)]
struct MemberRecord {
    receiver_token: String,
    receiver_expr: String,
    member_name: String,
}

fn resident_member_records(
    src: &str,
    tokens: &[TestCpuToken],
    res: &laniusc::parser::driver::ResidentParseResult,
) -> Vec<MemberRecord> {
    res.hir_member_name_token
        .iter()
        .enumerate()
        .filter_map(|(node, &member_token)| {
            if member_token == INVALID {
                return None;
            }
            Some(MemberRecord {
                receiver_token: token_text(src, tokens, res.hir_member_receiver_token[node])?,
                receiver_expr: hir_node_snippet(
                    src,
                    tokens,
                    &res.hir_token_pos,
                    &res.hir_token_end,
                    res.hir_member_receiver_node[node],
                )?,
                member_name: token_text(src, tokens, member_token)?,
            })
        })
        .collect()
}

#[test]
fn gpu_resident_ll1_hir_member_fields_are_tree_derived() {
    common::block_on_gpu_with_timeout("GPU parser HIR member metadata", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");

        for (type_name, receiver_name, field_a, field_b, method_name, factory_name) in [
            (
                "Carrier17",
                "receiver_17",
                "field_alpha_17",
                "field_beta_17",
                "method_gamma_17",
                "factory_delta_17",
            ),
            (
                "Packet23",
                "packet_23",
                "left_23",
                "right_23",
                "probe_23",
                "build_23",
            ),
        ] {
            let src = format!(
                r#"
struct {type_name} {{
    {field_a}: i32,
    {field_b}: i32,
}}

fn {factory_name}() -> {type_name} {{
    return {type_name} {{ {field_a}: 1, {field_b}: 4, }};
}}

fn main({receiver_name}: {type_name}) -> bool {{
    let a = {receiver_name}.{field_a};
    let b = {receiver_name}.{field_b};
    let c = {receiver_name}.{method_name}(2);
    let d = {factory_name}().{method_name}(3);
    return a < b && c && d;
}}
"#
            );
            let tokens = lex_on_test_cpu(&src).expect("test CPU oracle lex fixture");

            let res = lexer
                .with_resident_tokens(&src, |_, _, bufs| {
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
            for field_len in [
                res.hir_member_receiver_node.len(),
                res.hir_member_receiver_token.len(),
                res.hir_member_name_token.len(),
            ] {
                assert_eq!(field_len, res.node_kind.len());
            }

            let members = resident_member_records(&src, &tokens, &res);
            assert!(
                members.iter().any(|record| {
                    record.receiver_token == receiver_name
                        && record.receiver_expr.starts_with(receiver_name)
                        && record.member_name == field_a
                }),
                "missing first field member metadata for {type_name}: {members:?}"
            );
            assert!(
                members.iter().any(|record| {
                    record.receiver_token == receiver_name
                        && record.receiver_expr.starts_with(receiver_name)
                        && record.member_name == field_b
                }),
                "missing second field member metadata for {type_name}: {members:?}"
            );
            assert!(
                members.iter().any(|record| {
                    record.receiver_token == receiver_name && record.member_name == method_name
                }),
                "missing receiver method-call member metadata for {type_name}: {members:?}"
            );
            assert!(
                members.iter().any(|record| {
                    record.receiver_token == factory_name && record.member_name == method_name
                }),
                "missing call-result method-call member metadata for {type_name}: {members:?}"
            );
        }
    });
}

#[test]
fn gpu_resident_ll1_hir_member_fields_include_impl_method_bodies() {
    common::block_on_gpu_with_timeout("GPU parser HIR impl member metadata", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = r#"
struct Range {
    start: i32,
    end: i32,
}

impl Range {
    fn contains(receiver: Range, value: i32) -> bool {
        return value >= receiver.start && value < receiver.end;
    }
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
        let members = resident_member_records(src, &tokens, &res);
        assert!(
            members.iter().any(|record| {
                record.receiver_token == "receiver" && record.member_name == "start"
            }),
            "missing impl body start member metadata: {members:?}"
        );
        assert!(
            members.iter().any(|record| {
                record.receiver_token == "receiver" && record.member_name == "end"
            }),
            "missing impl body end member metadata: {members:?}"
        );
    });
}
