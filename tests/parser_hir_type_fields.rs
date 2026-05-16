mod common;

use laniusc::{
    lexer::{
        driver::GpuLexer,
        tables::tokens::TokenKind,
        test_cpu::{TestCpuToken, lex_on_test_cpu},
    },
    parser::{
        driver::GpuParser,
        passes::hir_type_fields::{
            HIR_TYPE_FORM_ARRAY,
            HIR_TYPE_FORM_PATH,
            HIR_TYPE_FORM_REF,
            HIR_TYPE_FORM_SLICE,
        },
        tables::PrecomputedParseTables,
    },
};

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
fn gpu_resident_ll1_hir_type_fields_are_exposed_to_downstream_passes() {
    common::block_on_gpu_with_timeout("GPU resident parser HIR type-form metadata", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = "fn sample<const N: usize>(value: &i32, values: [i32; N], bytes: [u8], nested: &[i32]) -> &[i32] { return nested; }";
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
                Some((form, snippet, value_form, len, res.hir_type_file_id[i]))
            })
            .collect::<Vec<_>>();

        assert!(
            type_records
                .iter()
                .any(|(form, snippet, value_form, len, file_id)| {
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
                .any(|(form, snippet, value_form, len, file_id)| {
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
                .any(|(form, snippet, value_form, len, file_id)| {
                    *form == HIR_TYPE_FORM_REF
                        && snippet.starts_with("&[i32")
                        && *value_form == HIR_TYPE_FORM_SLICE
                        && len.is_none()
                        && *file_id == 0
                }),
            "expected resident reference type metadata for &[i32], got {type_records:?}"
        );
    });
}

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

#[test]
fn gpu_ll1_hir_type_fields_capture_array_slice_and_reference_forms() {
    common::block_on_gpu_with_timeout("GPU parser HIR type-form metadata", async move {
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = "fn sample<const N: usize>(value: &i32, values: [i32; N], bytes: [u8], nested: &[i32]) -> &[i32] { return nested; }";
        let tokens = lex_on_test_cpu(src).expect("test CPU oracle lex fixture");
        let token_kinds = kinds_with_sentinels(src);

        let res = parser
            .parse(&token_kinds, &tables)
            .await
            .expect("GPU parse type-form fixture");

        assert!(res.ll1.accepted, "resident LL(1) parser rejected fixture");
        assert_eq!(res.hir_type_form.len(), res.node_kind.len());
        assert_eq!(res.hir_type_value_node.len(), res.node_kind.len());
        assert_eq!(res.hir_type_len_token.len(), res.node_kind.len());
        assert_eq!(res.hir_type_file_id.len(), res.node_kind.len());

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
                let value = hir_node_snippet(
                    src,
                    &tokens,
                    &res.hir_token_pos,
                    &res.hir_token_end,
                    res.hir_type_value_node[i],
                )
                .unwrap_or_else(|| "<none>".to_string());
                let len = token_snippet(src, &tokens, res.hir_type_len_token[i]);
                let value_form = res
                    .hir_type_value_node
                    .get(i)
                    .and_then(|&value_node| res.hir_type_form.get(value_node as usize))
                    .copied()
                    .unwrap_or(0);
                Some((
                    form,
                    snippet,
                    value,
                    value_form,
                    len,
                    res.hir_type_file_id[i],
                ))
            })
            .collect::<Vec<_>>();

        assert!(
            type_records
                .iter()
                .any(|(form, snippet, _, value_form, len, file_id)| {
                    *form == HIR_TYPE_FORM_ARRAY
                        && snippet.starts_with("[i32;")
                        && *value_form == HIR_TYPE_FORM_PATH
                        && len.as_deref() == Some("N")
                        && *file_id == 0
                }),
            "expected array type metadata for [i32; N], got {type_records:?}"
        );
        assert!(
            type_records
                .iter()
                .any(|(form, snippet, _, value_form, len, file_id)| {
                    *form == HIR_TYPE_FORM_SLICE
                        && snippet.starts_with("[u8")
                        && *value_form == HIR_TYPE_FORM_PATH
                        && len.is_none()
                        && *file_id == 0
                }),
            "expected slice type metadata for [u8], got {type_records:?}"
        );
        assert!(
            type_records
                .iter()
                .any(|(form, snippet, _, value_form, len, file_id)| {
                    *form == HIR_TYPE_FORM_REF
                        && snippet.starts_with("&[i32")
                        && *value_form == HIR_TYPE_FORM_SLICE
                        && len.is_none()
                        && *file_id == 0
                }),
            "expected reference type metadata for &[i32], got {type_records:?}"
        );
        assert!(
            type_records.iter().any(|(form, snippet, _, _, _, _)| {
                *form == HIR_TYPE_FORM_PATH && snippet.starts_with("usize")
            }),
            "expected named path type metadata, got {type_records:?}"
        );
    });
}
