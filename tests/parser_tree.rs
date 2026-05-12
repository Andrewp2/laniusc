mod common;

use laniusc::{
    gpu::buffers::storage_ro_from_u32s,
    lexer::{
        gpu::driver::GpuLexer,
        tables::tokens::{N_KINDS, TokenKind},
        test_cpu::{TestCpuToken, lex_on_test_cpu},
    },
    parser::{
        gpu::{
            driver::GpuParser,
            passes::{
                hir_item_fields::{
                    HIR_ITEM_IMPORT_TARGET_PATH,
                    HIR_ITEM_IMPORT_TARGET_STRING,
                    HIR_ITEM_KIND_CONST,
                    HIR_ITEM_KIND_ENUM,
                    HIR_ITEM_KIND_EXTERN_FN,
                    HIR_ITEM_KIND_FN,
                    HIR_ITEM_KIND_IMPORT,
                    HIR_ITEM_KIND_MODULE,
                    HIR_ITEM_KIND_STRUCT,
                    HIR_ITEM_KIND_TYPE_ALIAS,
                    HIR_ITEM_NAMESPACE_MODULE,
                    HIR_ITEM_NAMESPACE_TYPE,
                    HIR_ITEM_NAMESPACE_VALUE,
                    HIR_ITEM_VIS_PRIVATE,
                    HIR_ITEM_VIS_PUBLIC,
                },
                hir_nodes::{
                    HIR_NODE_BINARY_EXPR,
                    HIR_NODE_CONST_ITEM,
                    HIR_NODE_ENUM_ITEM,
                    HIR_NODE_FILE,
                    HIR_NODE_FN,
                    HIR_NODE_IMPORT_ITEM,
                    HIR_NODE_LET_STMT,
                    HIR_NODE_LITERAL_EXPR,
                    HIR_NODE_MODULE_ITEM,
                    HIR_NODE_PATH_EXPR,
                    HIR_NODE_RETURN_STMT,
                    HIR_NODE_STRUCT_ITEM,
                    HIR_NODE_STRUCT_LITERAL_EXPR,
                },
                ll1_blocks_01::{
                    LL1_BLOCK_STATUS_ACCEPTED,
                    LL1_BLOCK_STATUS_BOUNDARY,
                    LL1_BLOCK_STATUS_DISABLED,
                    LL1_BLOCK_STATUS_ERROR,
                },
            },
            syntax::{check_token_buffer_on_gpu_with_file_ids, check_tokens_on_gpu},
        },
        tables::{INVALID_TABLE_ENTRY, PrecomputedParseTables, encode_pop, encode_push},
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

#[test]
#[ignore]
fn debug_parser_hir_positions_for_generic_return() {
    common::block_on_gpu_with_timeout("GPU parser generic return token spans", async move {
        let src = r#"
struct Range<T> {
    start: T,
    end: T,
}

fn make_range(start: i32, end: i32) -> Range<i32> {
    return Range { start: start, end: end };
}
"#;

        let tokens = lex_on_test_cpu(src).expect("test CPU oracle lex fixture");
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");

        let parsed = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.parse_resident_tokens(bufs.n, &bufs.tokens_out, &bufs.token_count, &tables)
            })
            .await
            .expect("resident GPU lex")
            .expect("resident GPU parse");

        println!(
            "hir_kind count={} token span count={}",
            parsed.hir_kind.len(),
            parsed.hir_token_pos.len()
        );
        for (i, (&kind, &pos)) in parsed
            .hir_kind
            .iter()
            .zip(parsed.hir_token_pos.iter())
            .enumerate()
        {
            if kind == HIR_NODE_RETURN_STMT {
                println!(
                    "hir node {} => kind={} pos={} token_text={:?}",
                    i,
                    kind,
                    pos,
                    tokens
                        .get(pos as usize)
                        .map(|t| &src[t.start..t.start + t.len])
                );
            }
        }

        for (i, &kind) in parsed.hir_kind.iter().enumerate() {
            if kind == 0 {
                continue;
            }
            let pos = parsed.hir_token_pos.get(i).copied().unwrap_or(u32::MAX);
            let end = parsed.hir_token_end.get(i).copied().unwrap_or(u32::MAX);
            if pos == u32::MAX || end == u32::MAX || pos >= end {
                continue;
            }
            if pos >= tokens.len() as u32 || end > tokens.len() as u32 {
                continue;
            }
            println!(
                "node {i}: kind={kind} span=({pos},{end}) text={:?}",
                &src[tokens[pos as usize].start
                    ..tokens[(end - 1u32) as usize].start + tokens[(end - 1u32) as usize].len]
            );
        }
    });
}

fn assert_tree_forest_shape(node_kind: &[u32], parent: &[u32], prod_arity: &[u32]) {
    assert_eq!(node_kind.len(), parent.len());
    let mut child_counts = vec![0usize; node_kind.len()];
    for (i, &parent_id) in parent.iter().enumerate() {
        if parent_id == u32::MAX {
            continue;
        }
        let parent_idx = parent_id as usize;
        assert!(
            parent_idx < i,
            "parent pointer must point backward at node {i}"
        );
        child_counts[parent_idx] += 1;
    }
    for (i, &kind) in node_kind.iter().enumerate() {
        let want = *prod_arity.get(kind as usize).unwrap_or(&0) as usize;
        assert_eq!(
            child_counts[i], want,
            "production arity mismatch at node {i}, production {kind}"
        );
    }
}

fn expected_subtree_end(i: usize, node_kind: &[u32], prod_arity: &[u32]) -> u32 {
    let mut need = prod_arity[node_kind[i] as usize] as usize;
    let mut j = i + 1;
    while j < node_kind.len() && need > 0 {
        need = need - 1 + prod_arity[node_kind[j] as usize] as usize;
        j += 1;
    }
    j as u32
}

fn assert_tree_navigation_shape(
    node_kind: &[u32],
    parent: &[u32],
    first_child: &[u32],
    next_sibling: &[u32],
    subtree_end: &[u32],
    prod_arity: &[u32],
) {
    assert_eq!(node_kind.len(), first_child.len());
    assert_eq!(node_kind.len(), next_sibling.len());
    assert_eq!(node_kind.len(), subtree_end.len());
    for (i, &kind) in node_kind.iter().enumerate() {
        let arity = prod_arity[kind as usize] as usize;
        let want_first = if arity > 0 && i + 1 < node_kind.len() {
            (i + 1) as u32
        } else {
            u32::MAX
        };
        let want_end = expected_subtree_end(i, node_kind, prod_arity);
        let want_next =
            if (want_end as usize) < node_kind.len() && parent[want_end as usize] == parent[i] {
                want_end
            } else {
                u32::MAX
            };
        assert_eq!(first_child[i], want_first, "first child at node {i}");
        assert_eq!(subtree_end[i], want_end, "subtree end at node {i}");
        assert_eq!(next_sibling[i], want_next, "next sibling at node {i}");
    }
}

fn assert_hir_token_spans(name: &str, hir_token_pos: &[u32], hir_token_end: &[u32], n_tokens: u32) {
    assert_eq!(
        hir_token_pos.len(),
        hir_token_end.len(),
        "{name} HIR span length"
    );
    assert_eq!(
        hir_token_end.first().copied(),
        Some(n_tokens),
        "{name} root HIR span end"
    );
    for (i, (&start, &end)) in hir_token_pos.iter().zip(hir_token_end).enumerate() {
        if start == u32::MAX {
            assert_eq!(end, u32::MAX, "{name} invalid HIR span end at node {i}");
            continue;
        }
        assert!(
            start <= end && end <= n_tokens,
            "{name} invalid HIR span at node {i}: {start}..{end} for {n_tokens} tokens"
        );
    }
}

fn assert_hir_kind_points_to_token(
    name: &str,
    hir_kind: &[u32],
    hir_token_pos: &[u32],
    tokens: &[TestCpuToken],
    kind: u32,
    token_kind: TokenKind,
) {
    let found = hir_kind
        .iter()
        .zip(hir_token_pos)
        .filter(|&(&hir, _)| hir == kind)
        .any(|(_, &pos)| {
            let pos = pos as usize;
            pos < tokens.len() && raw_parser_kind(tokens[pos].kind) == token_kind
        });
    assert!(
        found,
        "{name} should contain HIR kind {kind} pointing at {token_kind:?}"
    );
}

fn hir_span_snippets_for_kind(
    src: &str,
    hir_kind: &[u32],
    hir_token_pos: &[u32],
    hir_token_end: &[u32],
    tokens: &[TestCpuToken],
    kind: u32,
) -> Vec<String> {
    hir_kind
        .iter()
        .zip(hir_token_pos)
        .zip(hir_token_end)
        .filter_map(|((&hir, &start), &end)| {
            if hir != kind || start == u32::MAX || end == u32::MAX {
                return None;
            }
            let start = start as usize;
            let end = end as usize;
            if start >= end || end > tokens.len() {
                return None;
            }
            let byte_start = tokens[start].start;
            let last = tokens[end - 1];
            let byte_end = last.start + last.len;
            Some(src[byte_start..byte_end].to_string())
        })
        .collect()
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

fn hir_item_names_for_kind(
    src: &str,
    tokens: &[TestCpuToken],
    hir_item_kind: &[u32],
    hir_item_name_token: &[u32],
    item_kind: u32,
) -> Vec<String> {
    hir_item_kind
        .iter()
        .zip(hir_item_name_token)
        .filter_map(|(&kind, &name)| {
            if kind == item_kind {
                token_snippet(src, tokens, name)
            } else {
                None
            }
        })
        .collect()
}

#[test]
fn gpu_parser_builds_tree_from_resident_lexer_tokens() {
    common::block_on_gpu_with_timeout("GPU parser resident lexer tokens", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = include_str!("../parser_tests/function.lani");
        let token_kinds = kinds_with_sentinels(src);
        let (expected, expected_pos) = tables
            .test_cpu_ll1_production_stream_with_positions(&token_kinds)
            .expect("fixture should parse with LL(1)");

        let res = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.parse_resident_tokens(bufs.n, &bufs.tokens_out, &bufs.token_count, &tables)
            })
            .await
            .expect("resident GPU lex")
            .expect("resident GPU parse");

        assert!(res.ll1.accepted, "resident LL(1) parser rejected fixture");
        assert_eq!(res.ll1_emit_stream, expected);
        assert_eq!(res.ll1_emit_token_pos, expected_pos);
        assert_eq!(res.node_kind.len(), expected.len());
        assert_eq!(res.hir_kind.len(), expected.len());
        assert_eq!(res.hir_token_pos, expected_pos);
        assert_hir_token_spans(
            "resident",
            &res.hir_token_pos,
            &res.hir_token_end,
            token_kinds.len().saturating_sub(2) as u32,
        );
        assert_eq!(res.hir_kind.first().copied(), Some(HIR_NODE_FILE));
        assert!(res.hir_kind.contains(&HIR_NODE_FN));
        assert!(res.hir_kind.contains(&HIR_NODE_LET_STMT));
        assert!(res.hir_kind.contains(&HIR_NODE_RETURN_STMT));
        assert!(res.hir_kind.contains(&HIR_NODE_BINARY_EXPR));
        assert!(res.hir_kind.contains(&HIR_NODE_LITERAL_EXPR));
        assert_tree_forest_shape(&res.node_kind, &res.parent, &tables.prod_arity);
        assert_tree_navigation_shape(
            &res.node_kind,
            &res.parent,
            &res.first_child,
            &res.next_sibling,
            &res.subtree_end,
            &tables.prod_arity,
        );
    });
}

#[test]
fn gpu_parser_ll1_hir_classifies_current_item_and_struct_literal_productions() {
    common::block_on_gpu_with_timeout("GPU parser current HIR production ids", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = "const LIMIT: i32 = 7; enum Maybe { Some(i32), None } struct Point { x: i32, y: i32 } fn make() { let p = Point { x: 1, y: 2 }; return; }";
        let tokens = lex_on_test_cpu(src).expect("test CPU oracle lex fixture");

        let res = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.parse_resident_tokens(bufs.n, &bufs.tokens_out, &bufs.token_count, &tables)
            })
            .await
            .expect("resident GPU lex")
            .expect("resident GPU parse");

        assert!(res.ll1.accepted, "resident LL(1) parser rejected fixture");
        assert_hir_kind_points_to_token(
            "resident",
            &res.hir_kind,
            &res.hir_token_pos,
            &tokens,
            HIR_NODE_CONST_ITEM,
            TokenKind::Const,
        );
        assert_hir_kind_points_to_token(
            "resident",
            &res.hir_kind,
            &res.hir_token_pos,
            &tokens,
            HIR_NODE_ENUM_ITEM,
            TokenKind::Enum,
        );
        assert_hir_kind_points_to_token(
            "resident",
            &res.hir_kind,
            &res.hir_token_pos,
            &tokens,
            HIR_NODE_STRUCT_ITEM,
            TokenKind::Struct,
        );
        assert_hir_kind_points_to_token(
            "resident",
            &res.hir_kind,
            &res.hir_token_pos,
            &tokens,
            HIR_NODE_STRUCT_LITERAL_EXPR,
            TokenKind::LBrace,
        );
    });
}

#[test]
fn generated_ll1_tables_accept_bool_literals() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds =
        kinds_with_sentinels("fn main() { let flag: bool = false; if (true) { return 1; } }");

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("bool literal fixture should parse with LL(1)");
}

#[test]
fn generated_ll1_tables_accept_for_in_statements() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = kinds_with_sentinels(
        "fn sum(values: [i32]) -> i32 { let total: i32 = 0; for value in values { total += value; } return total; }",
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("for-in fixture should parse with LL(1)");
}

#[test]
fn generated_ll1_tables_accept_extern_function_declarations() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = kinds_with_sentinels(
        r#"pub extern "wasm" fn host_alloc(size: usize, align: usize,) -> u32; extern fn clock_ms() -> i64;"#,
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("extern function fixture with trailing parameter comma should parse with LL(1)");
}

#[test]
fn generated_ll1_tables_accept_top_level_constants() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = kinds_with_sentinels(
        "const LIMIT: i32 = 7; pub const PUBLIC_LIMIT: i32 = 9; fn main() { return LIMIT; }",
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("const fixture should parse with LL(1)");
}

#[test]
fn gpu_syntax_accepts_public_top_level_constants() {
    common::block_on_gpu_with_timeout("GPU syntax public const", async move {
        let src = "pub const PUBLIC_LIMIT: i32 = 9; fn main() { return PUBLIC_LIMIT; }";
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer.lex(src).await.expect("GPU lex public const fixture");
        check_tokens_on_gpu(&tokens)
            .await
            .expect("GPU syntax should accept public const fixture");
    });
}

#[test]
fn gpu_syntax_accepts_for_in_statement_shape() {
    common::block_on_gpu_with_timeout("GPU syntax for-in statement", async move {
        let src = "fn main(values: [i32]) { for value in values { continue; } return; }";
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer.lex(src).await.expect("GPU lex for-in fixture");
        check_tokens_on_gpu(&tokens)
            .await
            .expect("GPU syntax should accept for-in fixture");
    });
}

#[test]
fn gpu_syntax_accepts_extern_function_declaration_shape() {
    common::block_on_gpu_with_timeout("GPU syntax extern function declaration", async move {
        let src = r#"pub extern "wasm" fn host_alloc(size: usize, align: usize,) -> u32;"#;
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer.lex(src).await.expect("GPU lex extern fixture");
        check_tokens_on_gpu(&tokens).await.expect(
            "GPU syntax should accept extern function fixture with trailing parameter comma",
        );
    });
}

#[test]
fn gpu_syntax_rejects_invalid_token_file_ids_from_gpu_metadata() {
    common::block_on_gpu_with_timeout("GPU syntax token file-id validation", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        lexer
            .with_resident_tokens("fn main() { return 0; }", |device, queue, bufs| {
                let invalid_file_ids = vec![u32::MAX; bufs.token_file_id.count.max(1)];
                let invalid_file_id_buf = storage_ro_from_u32s(
                    device,
                    "test.parser.syntax.invalid_token_file_id",
                    &invalid_file_ids,
                );
                let err = check_token_buffer_on_gpu_with_file_ids(
                    device,
                    queue,
                    bufs.n,
                    &bufs.tokens_out,
                    &bufs.token_count,
                    &invalid_file_id_buf,
                )
                .expect_err("invalid token file ids should fail syntax validation");
                let message = err.to_string();
                assert!(
                    message.contains("UnexpectedToken"),
                    "expected invalid file id to be reported as syntax rejection, got {message}"
                );
            })
            .await
            .expect("resident lex");
    });
}

#[test]
fn generated_ll1_tables_accept_module_and_import_items() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = kinds_with_sentinels(
        "module core::numbers; import core::i32; import \"stdlib/bool.lani\"; fn main() { return; }",
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("module/import fixture should parse with LL(1)");
}

#[test]
fn gpu_ll1_hir_preserves_module_import_and_path_evidence() {
    common::block_on_gpu_with_timeout("GPU parser module/import/path HIR evidence", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = "module core::numbers; import core::i32; fn main() { return core::i32::abs(1); }";
        let tokens = lex_on_test_cpu(src).expect("test CPU oracle lex fixture");

        let res = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.parse_resident_tokens(bufs.n, &bufs.tokens_out, &bufs.token_count, &tables)
            })
            .await
            .expect("resident GPU lex")
            .expect("resident GPU parse");

        assert!(res.ll1.accepted, "resident LL(1) parser rejected fixture");
        assert_hir_kind_points_to_token(
            "resident",
            &res.hir_kind,
            &res.hir_token_pos,
            &tokens,
            HIR_NODE_MODULE_ITEM,
            TokenKind::Module,
        );
        assert_hir_kind_points_to_token(
            "resident",
            &res.hir_kind,
            &res.hir_token_pos,
            &tokens,
            HIR_NODE_IMPORT_ITEM,
            TokenKind::Import,
        );
        assert_hir_kind_points_to_token(
            "resident",
            &res.hir_kind,
            &res.hir_token_pos,
            &tokens,
            HIR_NODE_PATH_EXPR,
            TokenKind::Ident,
        );
        let path_spans = hir_span_snippets_for_kind(
            src,
            &res.hir_kind,
            &res.hir_token_pos,
            &res.hir_token_end,
            &tokens,
            HIR_NODE_PATH_EXPR,
        );
        assert!(
            path_spans.iter().any(|path| path == "core::numbers"),
            "resident HIR should span the full module path, got {path_spans:?}"
        );
        assert!(
            path_spans.iter().any(|path| path == "core::i32"),
            "resident HIR should span the full import path, got {path_spans:?}"
        );
        assert!(
            path_spans.iter().any(|path| path == "core::i32::abs"),
            "resident HIR should span the full qualified value path, got {path_spans:?}"
        );
    });
}

#[test]
fn gpu_ll1_hir_item_fields_are_ast_derived_and_exclude_methods() {
    common::block_on_gpu_with_timeout("GPU parser HIR item field metadata", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = r#"
module core::numbers;
import core::bool;
import "core/bool";

pub const MIN: i32 = 0;
fn private_fn() { return; }
pub fn abs(value: i32) -> i32 { return value; }
pub extern "wasm" fn host_alloc(size: usize,) -> u32;
extern fn clock_ms() -> i64;
pub struct Point { x: i32 }
enum Maybe { Some(i32), None }
type Alias = i32;

impl Point {
    pub fn method(self: Point) { return; }
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

        let module_paths = res
            .hir_item_kind
            .iter()
            .enumerate()
            .filter_map(|(i, &kind)| {
                if kind == HIR_ITEM_KIND_MODULE {
                    token_span_snippet(
                        src,
                        &tokens,
                        res.hir_item_path_start[i],
                        res.hir_item_path_end[i],
                    )
                } else {
                    None
                }
            })
            .collect::<Vec<_>>();
        assert_eq!(module_paths, vec!["core::numbers"]);

        let import_paths = res
            .hir_item_kind
            .iter()
            .enumerate()
            .filter_map(|(i, &kind)| {
                if kind == HIR_ITEM_KIND_IMPORT {
                    token_span_snippet(
                        src,
                        &tokens,
                        res.hir_item_path_start[i],
                        res.hir_item_path_end[i],
                    )
                } else {
                    None
                }
            })
            .collect::<Vec<_>>();
        assert_eq!(import_paths, vec!["core::bool", "\"core/bool\""]);

        let import_targets = res
            .hir_item_kind
            .iter()
            .enumerate()
            .filter_map(|(i, &kind)| {
                if kind == HIR_ITEM_KIND_IMPORT {
                    Some(res.hir_item_import_target_kind[i])
                } else {
                    None
                }
            })
            .collect::<Vec<_>>();
        assert_eq!(
            import_targets,
            vec![HIR_ITEM_IMPORT_TARGET_PATH, HIR_ITEM_IMPORT_TARGET_STRING]
        );

        for (item_kind, namespace, visibility, name) in [
            (
                HIR_ITEM_KIND_CONST,
                HIR_ITEM_NAMESPACE_VALUE,
                HIR_ITEM_VIS_PUBLIC,
                "MIN",
            ),
            (
                HIR_ITEM_KIND_FN,
                HIR_ITEM_NAMESPACE_VALUE,
                HIR_ITEM_VIS_PRIVATE,
                "private_fn",
            ),
            (
                HIR_ITEM_KIND_FN,
                HIR_ITEM_NAMESPACE_VALUE,
                HIR_ITEM_VIS_PUBLIC,
                "abs",
            ),
            (
                HIR_ITEM_KIND_EXTERN_FN,
                HIR_ITEM_NAMESPACE_VALUE,
                HIR_ITEM_VIS_PUBLIC,
                "host_alloc",
            ),
            (
                HIR_ITEM_KIND_EXTERN_FN,
                HIR_ITEM_NAMESPACE_VALUE,
                HIR_ITEM_VIS_PRIVATE,
                "clock_ms",
            ),
            (
                HIR_ITEM_KIND_STRUCT,
                HIR_ITEM_NAMESPACE_TYPE,
                HIR_ITEM_VIS_PUBLIC,
                "Point",
            ),
            (
                HIR_ITEM_KIND_ENUM,
                HIR_ITEM_NAMESPACE_TYPE,
                HIR_ITEM_VIS_PRIVATE,
                "Maybe",
            ),
            (
                HIR_ITEM_KIND_TYPE_ALIAS,
                HIR_ITEM_NAMESPACE_TYPE,
                HIR_ITEM_VIS_PRIVATE,
                "Alias",
            ),
        ] {
            let found = res.hir_item_kind.iter().enumerate().any(|(i, &kind)| {
                kind == item_kind
                    && res.hir_item_namespace[i] == namespace
                    && res.hir_item_visibility[i] == visibility
                    && token_snippet(src, &tokens, res.hir_item_name_token[i]).as_deref()
                        == Some(name)
                    && res.hir_item_file_id[i] == 0
            });
            assert!(found, "missing HIR item metadata for {name}");
        }

        let fn_names = hir_item_names_for_kind(
            src,
            &tokens,
            &res.hir_item_kind,
            &res.hir_item_name_token,
            HIR_ITEM_KIND_FN,
        );
        assert!(
            fn_names.contains(&"private_fn".to_string()) && fn_names.contains(&"abs".to_string()),
            "top-level function names should be recorded, got {fn_names:?}"
        );
        assert!(
            !fn_names.contains(&"method".to_string()),
            "impl methods must not be reported as top-level functions"
        );

        for (i, &kind) in res.hir_item_kind.iter().enumerate() {
            if kind == HIR_ITEM_KIND_MODULE || kind == HIR_ITEM_KIND_IMPORT {
                assert_eq!(res.hir_item_namespace[i], HIR_ITEM_NAMESPACE_MODULE);
                assert_eq!(res.hir_item_visibility[i], HIR_ITEM_VIS_PRIVATE);
                assert_eq!(res.hir_item_file_id[i], 0);
            }
        }
    });
}

#[test]
fn gpu_syntax_accepts_leading_module_metadata() {
    common::block_on_gpu_with_timeout("GPU syntax leading module metadata", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let src = "module app::main; fn main() { return 0; }";
        let tokens = lexer.lex(src).await.expect("GPU lex module fixture");
        check_tokens_on_gpu(&tokens)
            .await
            .expect("GPU syntax should accept leading module metadata");
    });
}

#[test]
fn gpu_syntax_accepts_leading_import_metadata_and_rejects_invalid_module_metadata() {
    common::block_on_gpu_with_timeout("GPU syntax module/import metadata", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        for src in [
            "import core::i32; fn main() { return 0; }",
            "import \"stdlib/core/i32.lani\"; fn main() { return 0; }",
            "module app::main; import core::i32; import test::assert; fn main() { return 0; }",
        ] {
            let tokens = lexer.lex(src).await.expect("GPU lex import fixture");
            check_tokens_on_gpu(&tokens)
                .await
                .expect("GPU syntax should accept leading import metadata");
        }
        for src in [
            "fn main() { return 0; } import core::i32;",
            "fn main() { return 0; } module app::late;",
            "module app::main; module app::again; fn main() { return 0; }",
        ] {
            let tokens = lexer.lex(src).await.expect("GPU lex module/import fixture");
            check_tokens_on_gpu(&tokens)
                .await
                .expect_err("GPU syntax should reject non-leading import/module metadata");
        }
    });
}

#[test]
fn gpu_syntax_treats_source_pack_module_import_metadata_file_locally() {
    common::block_on_gpu_with_timeout("GPU syntax source pack metadata", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let valid = [
            "module first; fn first() { return; } ",
            "module second; import first; fn second() { return; }",
        ];
        lexer
            .with_resident_source_pack_tokens(&valid, |device, queue, bufs| {
                check_token_buffer_on_gpu_with_file_ids(
                    device,
                    queue,
                    bufs.n,
                    &bufs.tokens_out,
                    &bufs.token_count,
                    &bufs.token_file_id,
                )
                .expect("GPU syntax should accept file-local source pack metadata");
            })
            .await
            .expect("resident source pack lex");

        for invalid in [
            [
                "module first; fn first() { return; } ",
                "fn second() { return; } import first;",
            ],
            [
                "module first; fn first() { return; } ",
                "module second; module duplicate; fn second() { return; }",
            ],
            [
                "module first; fn first() { return; } ",
                "module ; fn second() { return; }",
            ],
        ] {
            lexer
                .with_resident_source_pack_tokens(&invalid, |device, queue, bufs| {
                    check_token_buffer_on_gpu_with_file_ids(
                        device,
                        queue,
                        bufs.n,
                        &bufs.tokens_out,
                        &bufs.token_count,
                        &bufs.token_file_id,
                    )
                    .expect_err(
                        "GPU syntax should reject non-leading module/import metadata per file",
                    );
                })
                .await
                .expect("resident invalid source pack lex");
        }
    });
}

#[test]
fn gpu_syntax_accepts_simple_stdlib_module_seed_files() {
    common::block_on_gpu_with_timeout("GPU syntax stdlib seed module metadata", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        for (path, src) in [
            (
                "stdlib/core/i32.lani",
                include_str!("../stdlib/core/i32.lani"),
            ),
            (
                "stdlib/core/bool.lani",
                include_str!("../stdlib/core/bool.lani"),
            ),
            (
                "stdlib/test/assert.lani",
                include_str!("../stdlib/test/assert.lani"),
            ),
        ] {
            let tokens = lexer
                .lex(src)
                .await
                .unwrap_or_else(|err| panic!("GPU lex {path}: {err}"));
            let result = check_tokens_on_gpu(&tokens).await;
            assert!(
                result.is_ok(),
                "{path} should accept leading module metadata: {result:?}"
            );
        }
    });
}

#[test]
fn generated_ll1_tables_accept_namespaced_paths() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = kinds_with_sentinels(
        "fn main(value: core::option::Option<i32>, result: core::result::Result<i32, i32>) { let out = core::math::add_one(1); let p = core::point::Point { x: out }; let y = match (out) { core::option::Some(inner) -> inner, _ -> out }; return; }",
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("namespaced path fixture should parse with LL(1)");
}

#[test]
fn gpu_syntax_accepts_call_shaped_qualified_value_paths_only() {
    common::block_on_gpu_with_timeout("GPU syntax qualified value path call shape", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let accepted = r#"
module app::main;

fn helper() -> i32 {
    return 1;
}

fn main() {
    return app::main::helper();
}
"#;
        let tokens = lexer
            .lex(accepted)
            .await
            .expect("GPU lex same-source qualified call fixture");
        check_tokens_on_gpu(&tokens)
            .await
            .expect("GPU syntax should accept call-shaped qualified value paths");

        for src in [
            "fn main() { let value: i32 = core::i32::MIN; return value; }",
            "fn main() { return core::i32::abs + 1; }",
        ] {
            let tokens = lexer
                .lex(src)
                .await
                .expect("GPU lex non-call qualified value path fixture");
            check_tokens_on_gpu(&tokens)
                .await
                .expect_err("GPU syntax should still reject non-call qualified value paths");
        }
    });
}

#[test]
fn generated_ll1_tables_accept_enum_declarations() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = kinds_with_sentinels("enum ResultI32 { Ok(i32), Err([i32; 4]), Empty }");

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("enum fixture should parse with LL(1)");
}

#[test]
fn generated_ll1_tables_accept_generic_enum_declarations() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = kinds_with_sentinels("enum Result<T, E> { Ok(T), Err(E), Empty }");

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("generic enum fixture should parse with LL(1)");
}

#[test]
fn generated_ll1_tables_accept_struct_declarations() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds =
        kinds_with_sentinels("pub struct VecHeader<T> { ptr: i32, len: i32, value: Option<T> }");

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("struct fixture should parse with LL(1)");
}

#[test]
fn generated_ll1_tables_accept_struct_literal_expressions() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds =
        kinds_with_sentinels("fn make() { let p = Point { x: 1, y: 2 }; let q = Point { }; }");

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("struct literal fixture should parse with LL(1)");
}

#[test]
fn generated_ll1_tables_accept_match_expressions() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = kinds_with_sentinels(
        "fn choose(value: i32, fallback: i32) -> i32 { let out = match (value) { 0 -> fallback, Some(inner) -> inner, _ -> value }; return out; }",
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("match fixture should parse with LL(1)");
}

#[test]
fn generated_ll1_tables_accept_trailing_commas_in_stdlib_shapes() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = kinds_with_sentinels(
        "struct Pair { left: i32, right: bool, } enum Maybe<T,> { Some(T,), None, } type Alias<T,> = Maybe<T,>; fn main(values: [i32; 2],) { let xs = [1, 2,]; let p = Pair { left: 1, right: true, }; let out = match (value) { Some(inner,) -> inner, _ -> value, }; take(1, 2,); return; }",
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("trailing comma fixture should parse with LL(1)");
}

#[test]
fn generated_ll1_tables_accept_slice_type_syntax() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds =
        kinds_with_sentinels("fn first(values: [i32], nested: [[bool]]) -> i32 { return 0; }");

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("slice type fixture should parse with LL(1)");
}

#[test]
fn generated_ll1_tables_accept_reference_type_syntax() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds =
        kinds_with_sentinels("fn borrow(value: &i32, values: &[i32], nested: & &bool) { return; }");

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("reference type fixture should parse with LL(1)");
}

#[test]
fn gpu_syntax_rejects_general_references_until_borrow_semantics_exist() {
    common::block_on_gpu_with_timeout("GPU syntax general reference rejection", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        for src in [
            "fn read(value: &i32) -> i32 { return 0; }",
            "fn main() { let value: i32 = 7; let ptr: &i32 = &value; return value; }",
        ] {
            let tokens = lexer.lex(src).await.expect("GPU lex reference fixture");
            check_tokens_on_gpu(&tokens)
                .await
                .expect_err("GPU syntax should reject general references until borrowing exists");
        }
    });
}

#[test]
fn generated_ll1_tables_accept_generic_function_declarations() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = kinds_with_sentinels(
        "pub fn unwrap_or<T>(value: T, fallback: T) -> T { return fallback; }",
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("generic function fixture should parse with LL(1)");
}

#[test]
fn generated_ll1_tables_accept_generic_type_parameter_bounds() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = kinds_with_sentinels(
        "trait Eq<T> { fn eq(left: T, right: T) -> bool; } fn same<T: Eq<T>>(left: T, right: T) -> bool { return left.eq(right); }",
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("generic type parameter bound fixture should parse with LL(1)");
}

#[test]
fn generated_ll1_tables_accept_multiple_generic_type_parameter_bounds() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = kinds_with_sentinels(
        "trait Eq<T> { fn eq(left: T, right: T) -> bool; } trait Hash<T> { fn hash(value: T) -> u32; } fn key<T: Eq<T> + Hash<T>>(value: T) -> u32 { return value.hash(); }",
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("multiple generic type parameter bounds fixture should parse with LL(1)");
}

#[test]
fn generated_ll1_tables_accept_where_clause_declarations() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = kinds_with_sentinels(
        "pub trait Eq<T> where T: core::cmp::Eq<T> { pub fn eq(left: T, right: T) -> bool where T: core::cmp::Eq<T>; } pub struct Wrapper<T> where T: Eq<T> { value: T } pub enum Maybe<T> where T: Eq<T> { Some(T), None } pub type Wrapped<T> where T: Eq<T> = Wrapper<T>; pub impl<T> Eq<T> for Wrapper<T> where T: Eq<T> { pub fn eq(left: Wrapper<T>, right: Wrapper<T>) -> bool where T: Eq<T> { return true; } } pub fn keep<T>(value: T) -> T where T: Eq<T>, { return value; }",
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("where-clause fixture should parse with LL(1)");
}

#[test]
fn generated_ll1_tables_accept_self_receiver_methods() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = kinds_with_sentinels(
        "trait Len { fn len(self) -> i32; fn is_empty(&self) -> bool; } struct Range { start: i32, end: i32 } impl Range { fn start(self) -> i32 { return self.start; } fn end(self: Range) -> i32 { return self.end; } fn is_empty(&self) -> bool { return self.start == self.end; } }",
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("self receiver fixture should parse with LL(1)");
}

#[test]
fn generated_ll1_tables_accept_core_range_seed() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = kinds_with_sentinels(include_str!("../stdlib/core/range.lani"));

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("core range stdlib seed should parse with LL(1)");
}

#[test]
fn generated_ll1_tables_accept_stdlib_seed_files() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let fixtures = [
        (
            "stdlib/core/i32.lani",
            include_str!("../stdlib/core/i32.lani"),
        ),
        (
            "stdlib/core/u8.lani",
            include_str!("../stdlib/core/u8.lani"),
        ),
        (
            "stdlib/core/u32.lani",
            include_str!("../stdlib/core/u32.lani"),
        ),
        (
            "stdlib/core/i64.lani",
            include_str!("../stdlib/core/i64.lani"),
        ),
        (
            "stdlib/core/f32.lani",
            include_str!("../stdlib/core/f32.lani"),
        ),
        (
            "stdlib/core/char.lani",
            include_str!("../stdlib/core/char.lani"),
        ),
        (
            "stdlib/core/bool.lani",
            include_str!("../stdlib/core/bool.lani"),
        ),
        (
            "stdlib/core/array_i32.lani",
            include_str!("../stdlib/core/array_i32.lani"),
        ),
        (
            "stdlib/core/array_i32_4.lani",
            include_str!("../stdlib/core/array_i32_4.lani"),
        ),
        (
            "stdlib/core/option.lani",
            include_str!("../stdlib/core/option.lani"),
        ),
        (
            "stdlib/core/result.lani",
            include_str!("../stdlib/core/result.lani"),
        ),
        (
            "stdlib/core/ordering.lani",
            include_str!("../stdlib/core/ordering.lani"),
        ),
        (
            "stdlib/core/cmp.lani",
            include_str!("../stdlib/core/cmp.lani"),
        ),
        (
            "stdlib/core/hash.lani",
            include_str!("../stdlib/core/hash.lani"),
        ),
        (
            "stdlib/core/range.lani",
            include_str!("../stdlib/core/range.lani"),
        ),
        (
            "stdlib/core/slice.lani",
            include_str!("../stdlib/core/slice.lani"),
        ),
        (
            "stdlib/core/panic.lani",
            include_str!("../stdlib/core/panic.lani"),
        ),
        (
            "stdlib/core/target.lani",
            include_str!("../stdlib/core/target.lani"),
        ),
        (
            "stdlib/alloc/allocator.lani",
            include_str!("../stdlib/alloc/allocator.lani"),
        ),
        ("stdlib/std/io.lani", include_str!("../stdlib/std/io.lani")),
        (
            "stdlib/std/process.lani",
            include_str!("../stdlib/std/process.lani"),
        ),
        (
            "stdlib/std/env.lani",
            include_str!("../stdlib/std/env.lani"),
        ),
        (
            "stdlib/std/time.lani",
            include_str!("../stdlib/std/time.lani"),
        ),
        ("stdlib/std/fs.lani", include_str!("../stdlib/std/fs.lani")),
        (
            "stdlib/std/net.lani",
            include_str!("../stdlib/std/net.lani"),
        ),
        (
            "stdlib/test/assert.lani",
            include_str!("../stdlib/test/assert.lani"),
        ),
        ("stdlib/i32.lani", include_str!("../stdlib/i32.lani")),
        ("stdlib/bool.lani", include_str!("../stdlib/bool.lani")),
        (
            "stdlib/array_i32_4.lani",
            include_str!("../stdlib/array_i32_4.lani"),
        ),
    ];

    for (path, src) in fixtures {
        let token_kinds = kinds_with_sentinels(src);
        tables
            .test_cpu_ll1_production_stream_with_positions(&token_kinds)
            .unwrap_or_else(|err| panic!("{path} should parse with LL(1): {err:?}"));
    }
}

#[test]
fn gpu_parser_accepts_where_clause_declarations_from_resident_lexer_tokens() {
    common::block_on_gpu_with_timeout("GPU parser where clauses", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = "pub trait Eq<T> where T: core::cmp::Eq<T> { pub fn eq(left: T, right: T) -> bool where T: core::cmp::Eq<T>; } pub impl<T> Eq<T> for T where T: core::cmp::Eq<T> { pub fn eq(left: T, right: T) -> bool where T: core::cmp::Eq<T> { return true; } } pub fn keep<T>(value: T) -> T where T: core::cmp::Eq<T>, { return value; }";

        let res = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.parse_resident_tokens(bufs.n, &bufs.tokens_out, &bufs.token_count, &tables)
            })
            .await
            .expect("resident GPU lex")
            .expect("resident GPU parse");

        assert!(
            res.ll1.accepted,
            "where-clause fixture rejected by GPU parser"
        );
        assert!(!res.ll1_emit_stream.is_empty());
    });
}

#[test]
fn gpu_parser_accepts_self_receivers_from_resident_lexer_tokens() {
    common::block_on_gpu_with_timeout("GPU parser self receivers", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = "trait Len { fn len(self) -> i32; fn is_empty(&self) -> bool; } impl Range { fn start(self) -> i32 { return self.start; } fn end(self: Range) -> i32 { return self.end; } }";

        let res = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.parse_resident_tokens(bufs.n, &bufs.tokens_out, &bufs.token_count, &tables)
            })
            .await
            .expect("resident GPU lex")
            .expect("resident GPU parse");

        assert!(
            res.ll1.accepted,
            "self receiver fixture rejected by GPU parser"
        );
        assert!(!res.ll1_emit_stream.is_empty());
    });
}

#[test]
fn gpu_syntax_accepts_where_clause_shape() {
    common::block_on_gpu_with_timeout("GPU syntax where clauses", async move {
        let src = "pub fn keep<T>(value: T) -> T where T: core::cmp::Eq<T>, { return value; }";
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer.lex(src).await.expect("GPU lex where-clause fixture");
        check_tokens_on_gpu(&tokens)
            .await
            .expect("GPU syntax should accept where-clause fixture");
    });
}

#[test]
fn gpu_syntax_accepts_self_receiver_shape() {
    common::block_on_gpu_with_timeout("GPU syntax self receivers", async move {
        let src = "impl Range { fn start(self) -> i32 { return self.start; } fn end(self: Range) -> i32 { return self.end; } fn is_empty(&self) -> bool { return self.start == self.end; } }";
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer.lex(src).await.expect("GPU lex self receiver fixture");
        check_tokens_on_gpu(&tokens)
            .await
            .expect("GPU syntax should accept self receiver fixture");
    });
}

#[test]
fn gpu_syntax_accepts_generic_type_parameter_bounds() {
    common::block_on_gpu_with_timeout("GPU syntax generic type parameter bounds", async move {
        let src = "trait Eq<T> { fn eq(left: T, right: T) -> bool; } fn same<T: Eq<T> >(left: T, right: T) -> bool { return left.eq(right); }";
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer.lex(src).await.expect("GPU lex generic bound fixture");
        check_tokens_on_gpu(&tokens)
            .await
            .expect("GPU syntax should accept generic type parameter bounds");
    });
}

#[test]
fn gpu_syntax_accepts_multiple_generic_type_parameter_bounds() {
    common::block_on_gpu_with_timeout(
        "GPU syntax multiple generic type parameter bounds",
        async move {
            let src = "trait Eq<T> { fn eq(left: T, right: T) -> bool; } trait Hash<T> { fn hash(value: T) -> u32; } fn key<T: Eq<T> + Hash<T> >(value: T) -> u32 { return value.hash(); }";
            let lexer = GpuLexer::new().await.expect("GPU lexer init");
            let tokens = lexer
                .lex(src)
                .await
                .expect("GPU lex multiple generic bounds fixture");
            check_tokens_on_gpu(&tokens)
                .await
                .expect("GPU syntax should accept multiple generic type parameter bounds");
        },
    );
}

#[test]
fn generated_ll1_tables_accept_type_alias_declarations() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = kinds_with_sentinels(
        "pub type Count = i32; type Buffer<T, const N: usize> = [T; N]; fn keep(value: Count) -> Count { return value; }",
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("type alias fixture should parse with LL(1)");
}

#[test]
fn gpu_syntax_rejects_type_aliases_until_gpu_alias_resolution_exists() {
    common::block_on_gpu_with_timeout("GPU syntax type alias rejection", async move {
        let src = "type Count = i32; fn main() { return 0; }";
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer.lex(src).await.expect("GPU lex type alias fixture");
        check_tokens_on_gpu(&tokens)
            .await
            .expect_err("GPU syntax should reject type aliases until alias resolution exists");
    });
}

#[test]
fn generated_ll1_tables_accept_const_generic_params_and_named_array_lengths() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = kinds_with_sentinels(
        "pub struct ArrayVec<T, const N: usize> { values: [T; N], len: usize } fn first<T, const N: usize>(values: [T; N]) -> T { return values[0]; }",
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("const generic fixture should parse with LL(1)");
}

#[test]
fn generated_ll1_tables_accept_impl_and_trait_declarations() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = kinds_with_sentinels(
        "pub trait Eq<T> { pub fn eq(left: T, right: T) -> bool; } pub impl Eq<i32> for i32 { pub fn eq(left: i32, right: i32) -> bool { return left == right; } }",
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("trait impl fixture should parse with LL(1)");
}

#[test]
fn gpu_syntax_accepts_trait_impl_declaration_shape() {
    common::block_on_gpu_with_timeout("GPU syntax trait impl declaration", async move {
        let src = "pub trait Eq<T> { pub fn eq(left: T, right: T) -> bool; } pub impl Eq<i32> for i32 { pub fn eq(left: i32, right: i32) -> bool { return left == right; } }";
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer.lex(src).await.expect("GPU lex trait impl fixture");
        check_tokens_on_gpu(&tokens)
            .await
            .expect("GPU syntax should accept trait impl fixture");
    });
}

#[test]
fn gpu_syntax_accepts_trailing_commas_in_stdlib_shapes() {
    common::block_on_gpu_with_timeout("GPU syntax trailing commas", async move {
        let src = "struct Pair { left: i32, right: bool, } enum Maybe<T,> { Some(T,), None, } fn main(values: [i32; 2],) { let xs = [1, 2,]; let p = Pair { left: 1, right: true, }; let out = match (value) { Some(inner,) -> inner, _ -> value, }; take(1, 2,); return; }";
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer
            .lex(src)
            .await
            .expect("GPU lex trailing comma fixture");
        check_tokens_on_gpu(&tokens)
            .await
            .expect("GPU syntax should accept trailing comma fixture");
    });
}

#[test]
fn gpu_parser_builds_tree_from_emit_stream() {
    common::block_on_gpu_with_timeout("GPU parser emit stream", async move {
        let parser = GpuParser::new().await.expect("GPU parser init");
        let mut tables = PrecomputedParseTables::new(N_KINDS, 3);

        tables.prod_arity = vec![2, 0, 0];
        tables.set_pp_for_pair(0, TokenKind::Ident as u32, &[0]);
        tables.set_pp_for_pair(TokenKind::Ident as u32, TokenKind::InfixPlus as u32, &[1]);
        tables.set_pp_for_pair(TokenKind::InfixPlus as u32, TokenKind::Int as u32, &[2]);
        tables.finalize_bit_widths(0);

        let token_kinds = [
            0,
            TokenKind::Ident as u32,
            TokenKind::InfixPlus as u32,
            TokenKind::Int as u32,
        ];
        let res = parser
            .parse(&token_kinds, &tables)
            .await
            .expect("GPU parse");

        assert_eq!(res.emit_stream, vec![0, 1, 2]);
        assert_eq!(res.ll1_seeded_blocks[0].status, LL1_BLOCK_STATUS_DISABLED);
        assert_eq!(res.node_kind, vec![0, 1, 2]);
        assert_eq!(res.parent, vec![u32::MAX, 0, 0]);
        assert_eq!(res.first_child, vec![1, u32::MAX, u32::MAX]);
        assert_eq!(res.next_sibling, vec![u32::MAX, 2, u32::MAX]);
        assert_eq!(res.subtree_end, vec![3, 2, 3]);
    });
}

#[test]
#[ignore = "GPU parser stress test; run explicitly with --ignored"]
fn gpu_parser_recovers_large_flat_tree_with_prefix_blocks() {
    common::block_on_gpu_with_timeout("GPU parser large flat tree", async move {
        let parser = GpuParser::new().await.expect("GPU parser init");
        let mut tables = PrecomputedParseTables::new(N_KINDS, 2);

        let leaf_count = 256 * 256;
        tables.prod_arity = vec![leaf_count as u32, 0];
        tables.set_pp_for_pair(0, TokenKind::Ident as u32, &[0]);
        tables.set_pp_for_pair(TokenKind::Ident as u32, TokenKind::Ident as u32, &[1]);
        tables.finalize_bit_widths(0);

        let mut token_kinds = Vec::with_capacity(leaf_count + 2);
        token_kinds.push(0);
        token_kinds.extend(std::iter::repeat(TokenKind::Ident as u32).take(leaf_count + 1));

        let res = parser
            .parse(&token_kinds, &tables)
            .await
            .expect("GPU parse");

        assert_eq!(res.emit_stream.len(), leaf_count + 1);
        assert!(
            res.node_kind.len() > 256 * 256,
            "test must exercise tree prefix scans beyond one 256-lane workgroup"
        );
        assert_eq!(res.node_kind[0], 0);
        assert!(res.node_kind[1..].iter().all(|&kind| kind == 1));
        assert_tree_forest_shape(&res.node_kind, &res.parent, &tables.prod_arity);
        assert_tree_navigation_shape(
            &res.node_kind,
            &res.parent,
            &res.first_child,
            &res.next_sibling,
            &res.subtree_end,
            &tables.prod_arity,
        );
    });
}

#[test]
fn gpu_parser_emits_exact_ll1_stream_for_fixtures() {
    common::block_on_gpu_with_timeout("GPU parser LL(1) fixtures", async move {
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");

        for (name, src) in [
            ("control", include_str!("../parser_tests/control.lani")),
            ("file", include_str!("../parser_tests/file.lani")),
            ("function", include_str!("../parser_tests/function.lani")),
        ] {
            let token_kinds = kinds_with_sentinels(src);
            let (expected, expected_pos) = tables
                .test_cpu_ll1_production_stream_with_positions(&token_kinds)
                .unwrap_or_else(|err| panic!("{name} fixture should parse with LL(1): {err}"));
            let res = parser
                .parse(&token_kinds, &tables)
                .await
                .unwrap_or_else(|err| panic!("GPU parse {name}: {err}"));

            assert!(res.ll1.accepted, "{name} rejected by GPU LL(1) parser");
            assert_eq!(res.ll1_emit_stream, expected, "{name} LL(1) stream");
            assert_eq!(
                res.ll1_emit_token_pos, expected_pos,
                "{name} LL(1) production positions"
            );
            assert!(!res.emit_stream.is_empty(), "{name} LLP projected stream");
            assert!(!res.node_kind.is_empty(), "{name} tree length");
            assert_eq!(res.hir_kind.len(), res.node_kind.len(), "{name} HIR length");
            assert_tree_forest_shape(&res.node_kind, &res.parent, &tables.prod_arity);
            assert_tree_navigation_shape(
                &res.node_kind,
                &res.parent,
                &res.first_child,
                &res.next_sibling,
                &res.subtree_end,
                &tables.prod_arity,
            );
        }
    });
}

#[test]
fn gpu_parser_runs_seeded_ll1_acceptance_table() {
    common::block_on_gpu_with_timeout("GPU parser seeded LL(1) table", async move {
        let parser = GpuParser::new().await.expect("GPU parser init");
        let mut tables = PrecomputedParseTables::new(N_KINDS, 1);

        tables.prod_arity = vec![0];
        tables.n_nonterminals = 1;
        tables.start_nonterminal = 0;
        tables.ll1_predict = vec![INVALID_TABLE_ENTRY; N_KINDS as usize];
        tables.ll1_predict[TokenKind::Ident as usize] = 0;
        tables.prod_rhs_off = vec![0];
        tables.prod_rhs_len = vec![1];
        tables.prod_rhs = vec![TokenKind::Ident as u32];
        tables.finalize_bit_widths(0);

        let ok_tokens = [0, TokenKind::Ident as u32, 0];
        let ok = parser.parse(&ok_tokens, &tables).await.expect("GPU parse");
        assert!(ok.ll1.accepted);
        assert_eq!(ok.ll1.emit_len, 1);
        assert_eq!(ok.ll1_emit_stream, vec![0]);
        assert_eq!(
            tables.test_cpu_ll1_production_stream(&ok_tokens).unwrap(),
            vec![0]
        );
        assert!(ok.ll1_seed_plan.accepted);
        assert_eq!(ok.ll1_seed_plan.seed_count, 1);
        assert_eq!(ok.ll1_seeded_blocks[0].status, LL1_BLOCK_STATUS_ACCEPTED);
        assert_eq!(ok.ll1_seeded_blocks[0].emit_len, 1);
        assert_eq!(ok.ll1_seeded_emit[0], 0);
        assert_eq!(ok.node_kind, vec![0]);
        assert_eq!(ok.parent, vec![u32::MAX]);

        let bad_tokens = [0, TokenKind::Int as u32, 0];
        let bad = parser.parse(&bad_tokens, &tables).await.expect("GPU parse");
        assert!(!bad.ll1.accepted);
        assert_eq!(bad.ll1.error_code, 2);
        assert!(!bad.ll1_seed_plan.accepted);
        assert_eq!(bad.ll1_seeded_blocks[0].status, LL1_BLOCK_STATUS_ERROR);
        assert_eq!(bad.ll1_seeded_blocks[0].error_code, 2);
    });
}

#[test]
fn gpu_parser_seeds_ll1_stacks_across_blocks() {
    common::block_on_gpu_with_timeout("GPU parser seeded LL(1) stacks", async move {
        let parser = GpuParser::new().await.expect("GPU parser init");
        let mut tables = PrecomputedParseTables::new(N_KINDS, 2);

        tables.prod_arity = vec![1, 0];
        tables.n_nonterminals = 1;
        tables.start_nonterminal = 0;
        tables.ll1_predict = vec![INVALID_TABLE_ENTRY; N_KINDS as usize];
        tables.ll1_predict[TokenKind::Ident as usize] = 0;
        tables.ll1_predict[0] = 1;
        tables.prod_rhs_off = vec![0, 2];
        tables.prod_rhs_len = vec![2, 0];
        tables.prod_rhs = vec![TokenKind::Ident as u32, N_KINDS + 0];
        tables.finalize_bit_widths(0);

        let mut token_kinds = Vec::with_capacity(702);
        token_kinds.push(0);
        token_kinds.extend(std::iter::repeat(TokenKind::Ident as u32).take(700));
        token_kinds.push(0);

        let res = parser
            .parse(&token_kinds, &tables)
            .await
            .expect("GPU parse");

        assert!(res.ll1.accepted);
        assert_eq!(res.ll1_emit_stream.len(), 701);
        assert_eq!(res.ll1_seed_plan.seed_count, 3);
        assert_eq!(res.ll1_seeded_blocks.len(), 3);
        assert_eq!(res.ll1_seeded_blocks[0].status, LL1_BLOCK_STATUS_BOUNDARY);
        assert_eq!(res.ll1_seeded_blocks[0].emit_len, 256);
        assert_eq!(res.ll1_seeded_blocks[1].status, LL1_BLOCK_STATUS_BOUNDARY);
        assert_eq!(res.ll1_seeded_blocks[1].emit_len, 256);
        assert_eq!(res.ll1_seeded_blocks[2].status, LL1_BLOCK_STATUS_ACCEPTED);
        assert_eq!(res.ll1_seeded_blocks[2].emit_len, 189);

        let mut seeded_emit = Vec::new();
        for (i, block) in res.ll1_seeded_blocks.iter().enumerate() {
            let base = i * res.ll1_block_emit_stride as usize;
            let len = block.emit_len as usize;
            seeded_emit.extend_from_slice(&res.ll1_seeded_emit[base..base + len]);
        }
        assert_eq!(seeded_emit, res.ll1_emit_stream);
    });
}

#[test]
#[ignore = "GPU parser stress test; run explicitly with --ignored"]
fn gpu_parser_reduces_ll1_status_across_many_blocks() {
    common::block_on_gpu_with_timeout("GPU parser LL(1) status reduction", async move {
        let parser = GpuParser::new().await.expect("GPU parser init");
        let mut tables = PrecomputedParseTables::new(N_KINDS, 2);

        tables.prod_arity = vec![1, 0];
        tables.n_nonterminals = 1;
        tables.start_nonterminal = 0;
        tables.ll1_predict = vec![INVALID_TABLE_ENTRY; N_KINDS as usize];
        tables.ll1_predict[TokenKind::Ident as usize] = 0;
        tables.ll1_predict[0] = 1;
        tables.prod_rhs_off = vec![0, 2];
        tables.prod_rhs_len = vec![2, 0];
        tables.prod_rhs = vec![TokenKind::Ident as u32, N_KINDS + 0];
        tables.finalize_bit_widths(0);

        let ident_count = 256 * 256 + 1;
        let mut token_kinds = Vec::with_capacity(ident_count + 2);
        token_kinds.push(0);
        token_kinds.extend(std::iter::repeat(TokenKind::Ident as u32).take(ident_count));
        token_kinds.push(0);

        let res = parser
            .parse(&token_kinds, &tables)
            .await
            .expect("GPU parse");

        assert!(res.ll1.accepted);
        assert_eq!(res.ll1_emit_stream.len(), ident_count + 1);
        assert!(
            res.ll1_seed_plan.seed_count > 256,
            "test must exercise status reduction beyond one 256-lane workgroup"
        );
        assert_eq!(
            res.ll1_seed_plan.seed_count as usize,
            res.ll1_seeded_blocks.len()
        );
        assert_eq!(
            res.ll1_seeded_blocks.last().map(|block| block.status),
            Some(LL1_BLOCK_STATUS_ACCEPTED)
        );
    });
}

#[test]
fn gpu_parser_reports_typed_bracket_mismatches() {
    common::block_on_gpu_with_timeout("GPU parser bracket mismatch", async move {
        let parser = GpuParser::new().await.expect("GPU parser init");
        let mut tables = PrecomputedParseTables::new(N_KINDS, 1);

        tables.prod_arity = vec![0];
        tables.set_sc_for_pair(0, TokenKind::GroupLParen as u32, &[encode_push(0)]);
        tables.set_sc_for_pair(
            TokenKind::GroupLParen as u32,
            TokenKind::RBracket as u32,
            &[2],
        );
        tables.finalize_bit_widths(1);

        let token_kinds = [0, TokenKind::GroupLParen as u32, TokenKind::RBracket as u32];
        let res = parser
            .parse(&token_kinds, &tables)
            .await
            .expect("GPU parse");

        assert!(!res.brackets.valid);
        assert_eq!(res.brackets.final_depth, 0);
        assert_eq!(res.brackets.min_depth, 0);
    });
}

#[test]
#[ignore = "GPU parser stress test; run explicitly with --ignored"]
fn gpu_parser_scans_deep_bracket_histogram_offsets() {
    common::block_on_gpu_with_timeout("GPU parser deep bracket scan", async move {
        let parser = GpuParser::new().await.expect("GPU parser init");
        let mut tables = PrecomputedParseTables::new(N_KINDS, 1);

        tables.prod_arity = vec![0];
        tables.set_sc_for_pair(0, TokenKind::GroupLParen as u32, &[encode_push(0)]);
        tables.set_sc_for_pair(
            TokenKind::GroupLParen as u32,
            TokenKind::GroupLParen as u32,
            &[encode_push(0)],
        );
        tables.set_sc_for_pair(
            TokenKind::GroupLParen as u32,
            TokenKind::GroupRParen as u32,
            &[encode_pop(0)],
        );
        tables.set_sc_for_pair(
            TokenKind::GroupRParen as u32,
            TokenKind::GroupRParen as u32,
            &[encode_pop(0)],
        );
        tables.finalize_bit_widths(0);

        let depth = 33_000usize;
        let mut token_kinds = Vec::with_capacity(depth * 2 + 1);
        token_kinds.push(0);
        token_kinds.extend(std::iter::repeat(TokenKind::GroupLParen as u32).take(depth));
        token_kinds.extend(std::iter::repeat(TokenKind::GroupRParen as u32).take(depth));

        let res = parser
            .parse(&token_kinds, &tables)
            .await
            .expect("GPU parse");

        assert!(res.brackets.valid);
        assert_eq!(res.brackets.final_depth, 0);
        assert_eq!(res.brackets.min_depth, 0);
        assert_eq!(res.sc_stream.len(), depth * 2);
        assert!(
            res.sc_stream.len() > 256 * 256,
            "test must exercise block-prefix scan beyond one 256-lane workgroup"
        );
    });
}

#[test]
fn gpu_parser_pairs_many_flat_brackets_in_parallel() {
    common::block_on_gpu_with_timeout("GPU parser flat bracket pairing", async move {
        let parser = GpuParser::new().await.expect("GPU parser init");
        let mut tables = PrecomputedParseTables::new(N_KINDS, 1);

        tables.prod_arity = vec![0];
        tables.set_sc_for_pair(0, TokenKind::GroupLParen as u32, &[encode_push(0)]);
        tables.set_sc_for_pair(
            TokenKind::GroupLParen as u32,
            TokenKind::GroupRParen as u32,
            &[encode_pop(0)],
        );
        tables.set_sc_for_pair(
            TokenKind::GroupRParen as u32,
            TokenKind::GroupLParen as u32,
            &[encode_push(0)],
        );
        tables.finalize_bit_widths(0);

        let pair_count = 1024usize;
        let mut token_kinds = Vec::with_capacity(pair_count * 2 + 1);
        token_kinds.push(0);
        for _ in 0..pair_count {
            token_kinds.push(TokenKind::GroupLParen as u32);
            token_kinds.push(TokenKind::GroupRParen as u32);
        }

        let res = parser
            .parse(&token_kinds, &tables)
            .await
            .expect("GPU parse");

        assert!(res.brackets.valid);
        assert_eq!(res.brackets.final_depth, 0);
        assert_eq!(res.brackets.min_depth, 0);
        assert_eq!(res.sc_stream.len(), pair_count * 2);
    });
}
