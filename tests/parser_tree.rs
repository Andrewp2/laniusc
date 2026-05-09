use laniusc::{
    lexer::{
        cpu::lex_on_cpu,
        gpu::driver::GpuLexer,
        tables::tokens::{N_KINDS, TokenKind},
    },
    parser::{
        gpu::{
            driver::GpuParser,
            passes::{
                hir_nodes::{
                    HIR_NODE_BINARY_EXPR,
                    HIR_NODE_FILE,
                    HIR_NODE_FN,
                    HIR_NODE_LET_STMT,
                    HIR_NODE_LITERAL_EXPR,
                    HIR_NODE_RETURN_STMT,
                },
                ll1_blocks_01::{
                    LL1_BLOCK_STATUS_ACCEPTED,
                    LL1_BLOCK_STATUS_BOUNDARY,
                    LL1_BLOCK_STATUS_DISABLED,
                    LL1_BLOCK_STATUS_ERROR,
                },
            },
        },
        tables::{INVALID_TABLE_ENTRY, PrecomputedParseTables, encode_pop, encode_push},
    },
};

fn kinds_with_sentinels(src: &str) -> Vec<u32> {
    let mut kinds = lex_on_cpu(src)
        .expect("CPU lex fixture")
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

#[test]
fn gpu_parser_builds_tree_from_resident_lexer_tokens() {
    pollster::block_on(async {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = include_str!("../parser_tests/function.lani");
        let token_kinds = kinds_with_sentinels(src);
        let (expected, expected_pos) = tables
            .ll1_production_stream_with_positions(&token_kinds)
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
fn generated_ll1_tables_accept_bool_literals() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds =
        kinds_with_sentinels("fn main() { let flag: bool = false; if (true) { return 1; } }");

    tables
        .ll1_production_stream_with_positions(&token_kinds)
        .expect("bool literal fixture should parse with LL(1)");
}

#[test]
fn generated_ll1_tables_accept_top_level_constants() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = kinds_with_sentinels("const LIMIT: i32 = 7; fn main() { return LIMIT; }");

    tables
        .ll1_production_stream_with_positions(&token_kinds)
        .expect("const fixture should parse with LL(1)");
}

#[test]
fn generated_ll1_tables_accept_enum_declarations() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = kinds_with_sentinels("enum ResultI32 { Ok(i32), Err([i32; 4]), Empty }");

    tables
        .ll1_production_stream_with_positions(&token_kinds)
        .expect("enum fixture should parse with LL(1)");
}

#[test]
fn generated_ll1_tables_accept_generic_enum_declarations() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = kinds_with_sentinels("enum Result<T, E> { Ok(T), Err(E), Empty }");

    tables
        .ll1_production_stream_with_positions(&token_kinds)
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
        .ll1_production_stream_with_positions(&token_kinds)
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
        .ll1_production_stream_with_positions(&token_kinds)
        .expect("struct literal fixture should parse with LL(1)");
}

#[test]
fn gpu_parser_builds_tree_from_emit_stream() {
    pollster::block_on(async {
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
fn gpu_parser_recovers_large_flat_tree_with_prefix_blocks() {
    pollster::block_on(async {
        let parser = GpuParser::new().await.expect("GPU parser init");
        let mut tables = PrecomputedParseTables::new(N_KINDS, 2);

        let leaf_count = 70_000usize;
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
    pollster::block_on(async {
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
                .ll1_production_stream_with_positions(&token_kinds)
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
    pollster::block_on(async {
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
        assert_eq!(tables.ll1_production_stream(&ok_tokens).unwrap(), vec![0]);
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
    pollster::block_on(async {
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
fn gpu_parser_reduces_ll1_status_across_many_blocks() {
    pollster::block_on(async {
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
    pollster::block_on(async {
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
fn gpu_parser_scans_deep_bracket_histogram_offsets() {
    pollster::block_on(async {
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
    pollster::block_on(async {
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
