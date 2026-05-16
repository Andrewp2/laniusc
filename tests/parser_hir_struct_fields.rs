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

fn kinds_with_sentinels(src: &str) -> Vec<u32> {
    let mut kinds = lex_on_test_cpu(src)
        .expect("test CPU oracle lex fixture")
        .into_iter()
        .map(|token| raw_parser_kind(token.kind) as u32)
        .collect::<Vec<_>>();
    kinds.insert(0, 0);
    kinds.push(0);
    kinds
}

#[test]
fn gpu_resident_ll1_hir_struct_fields_are_tree_derived() {
    common::block_on_gpu_with_timeout("GPU parser HIR struct metadata", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = r#"
struct Range<T> {
    start: T,
    end: T,
}

fn make(start: i32, end: i32) {
    let range = Range { start: start, end: end, };
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
            res.hir_struct_field_parent_struct.len(),
            res.hir_struct_field_ordinal.len(),
            res.hir_struct_field_type_node.len(),
            res.hir_struct_decl_field_start.len(),
            res.hir_struct_decl_field_count.len(),
            res.hir_struct_lit_head_node.len(),
            res.hir_struct_lit_field_start.len(),
            res.hir_struct_lit_field_count.len(),
            res.hir_struct_lit_field_parent_lit.len(),
            res.hir_struct_lit_field_value_node.len(),
        ] {
            assert_eq!(field_len, res.node_kind.len());
        }

        let decls = res
            .hir_struct_decl_field_count
            .iter()
            .enumerate()
            .filter_map(|(i, &field_count)| {
                if field_count == 0 {
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
                        res.hir_struct_decl_field_start[i],
                    )
                    .unwrap(),
                    field_count,
                ))
            })
            .collect::<Vec<_>>();

        assert!(
            decls.iter().any(|(decl, first_field, count)| {
                decl.starts_with("struct Range") && first_field.starts_with("start") && *count == 2
            }),
            "missing struct declaration field metadata: {decls:?}"
        );

        let fields = res
            .hir_struct_field_parent_struct
            .iter()
            .enumerate()
            .filter_map(|(i, &parent_struct)| {
                if parent_struct == INVALID {
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
                        parent_struct,
                    )
                    .unwrap(),
                    res.hir_struct_field_ordinal[i],
                    hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        res.hir_struct_field_type_node[i],
                    )
                    .unwrap(),
                ))
            })
            .collect::<Vec<_>>();

        assert!(
            fields.iter().any(|(field, parent, ordinal, ty)| {
                field.starts_with("start")
                    && parent.starts_with("struct Range")
                    && *ordinal == 0
                    && ty.starts_with("T")
            }),
            "missing first struct field metadata: {fields:?}"
        );
        assert!(
            fields.iter().any(|(field, parent, ordinal, ty)| {
                field.starts_with("end")
                    && parent.starts_with("struct Range")
                    && *ordinal == 1
                    && ty.starts_with("T")
            }),
            "missing second struct field metadata: {fields:?}"
        );

        let literals = res
            .hir_struct_lit_field_count
            .iter()
            .enumerate()
            .filter_map(|(i, &field_count)| {
                if field_count == 0 {
                    return None;
                }
                Some((
                    hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        res.hir_struct_lit_head_node[i],
                    )
                    .unwrap(),
                    hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        res.hir_struct_lit_field_start[i],
                    )
                    .unwrap(),
                    field_count,
                ))
            })
            .collect::<Vec<_>>();

        assert_eq!(
            literals,
            vec![("Range".to_string(), "start: start,".to_string(), 2)],
            "unexpected struct literal metadata"
        );

        let literal_fields = res
            .hir_struct_lit_field_parent_lit
            .iter()
            .enumerate()
            .filter_map(|(i, &literal)| {
                if literal == INVALID {
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
                        literal,
                    )
                    .unwrap(),
                    hir_node_snippet(
                        src,
                        &tokens,
                        &res.hir_token_pos,
                        &res.hir_token_end,
                        res.hir_struct_lit_field_value_node[i],
                    )
                    .unwrap(),
                ))
            })
            .collect::<Vec<_>>();

        assert!(
            literal_fields.iter().any(|(field, literal, value)| {
                field.starts_with("start")
                    && literal.starts_with("{ start")
                    && value.starts_with("start")
            }),
            "missing start literal field metadata: {literal_fields:?}"
        );
        assert!(
            literal_fields.iter().any(|(field, literal, value)| {
                field.starts_with("end")
                    && literal.starts_with("{ start")
                    && value.starts_with("end")
            }),
            "missing end literal field metadata: {literal_fields:?}"
        );
    });
}

#[test]
fn gpu_ll1_hir_struct_fields_capture_nonresident_parser_results() {
    common::block_on_gpu_with_timeout("GPU parser nonresident HIR struct metadata", async move {
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = "struct Pair { left: i32, right: bool } fn main() { let p = Pair { left: 1, right: true, }; return; }";
        let res = parser
            .parse(&kinds_with_sentinels(src), &tables)
            .await
            .expect("GPU parse struct metadata fixture");

        assert!(res.ll1.accepted, "LL(1) parser rejected fixture");
        assert_eq!(
            res.hir_struct_field_parent_struct.len(),
            res.node_kind.len()
        );
        assert_eq!(
            res.hir_struct_lit_field_value_node.len(),
            res.node_kind.len()
        );
        assert!(
            res.hir_struct_decl_field_count
                .iter()
                .any(|&count| count == 2),
            "expected struct declaration metadata for two fields"
        );
        assert!(
            res.hir_struct_lit_field_count
                .iter()
                .any(|&count| count == 2),
            "expected struct literal metadata for two fields"
        );
    });
}

#[test]
fn hir_struct_fields_pass_is_wired_without_token_text_access() {
    let shader = include_str!("../shaders/parser/hir_struct_fields.slang");
    let pass = include_str!("../src/parser/passes/hir_struct_fields.rs");
    let buffers = include_str!("../src/parser/buffers.rs");
    let driver = include_str!("../src/parser/driver.rs");
    let resident_tree = include_str!("../src/parser/driver/resident_tree.rs");
    let passes = include_str!("../src/parser/passes/mod.rs");

    for required in [
        "StructuredBuffer<uint> node_kind",
        "StructuredBuffer<uint> parent",
        "StructuredBuffer<uint> subtree_end",
        "StructuredBuffer<uint> hir_kind",
        "PROD_STRUCT",
        "PROD_STRUCT_FIELD",
        "PROD_STRUCT_LIT",
        "PROD_STRUCT_LIT_FIELD",
        "first_hir_type_child",
        "previous_sibling_node",
    ] {
        assert!(
            shader.contains(required),
            "HIR struct metadata should be derived from tree arrays: {required}"
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
            "HIR struct metadata must not inspect token text: {forbidden}"
        );
    }

    for required in [
        "hir_struct_fields",
        "hir_struct_field_parent_struct",
        "hir_struct_lit_field_value_node",
    ] {
        assert!(pass.contains(required) || buffers.contains(required));
        assert!(driver.contains(required) || resident_tree.contains(required));
    }
    assert!(passes.contains("pub mod hir_struct_fields;"));
    assert!(passes.contains("hir_struct_fields.record_pass"));
}
