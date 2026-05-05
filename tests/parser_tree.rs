use laniusc::{
    lexer::tables::tokens::{N_KINDS, TokenKind},
    parser::{
        gpu::driver::GpuParser,
        tables::{PrecomputedParseTables, encode_push},
    },
};

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
        assert_eq!(res.node_kind, vec![0, 1, 2]);
        assert_eq!(res.parent, vec![u32::MAX, 0, 0]);
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
