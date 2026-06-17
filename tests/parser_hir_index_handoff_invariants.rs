use laniusc_compiler::parser::{
    hir_records::INVALID,
    passes::hir::{
        expr::fields::{HIR_EXPR_FORM_INDEX, HIR_EXPR_FORM_INT, HIR_EXPR_FORM_NAME},
        nodes::{HIR_NODE_INDEX_EXPR, HIR_NODE_LITERAL_EXPR, HIR_NODE_NAME_EXPR},
    },
    readback::validate_hir_expression_records,
};

#[test]
fn parser_hir_index_operand_edges_must_not_cross_source_pack_files() {
    validate_hir_expression_records(
        &[
            HIR_NODE_INDEX_EXPR,
            HIR_NODE_NAME_EXPR,
            HIR_NODE_LITERAL_EXPR,
        ],
        &[1, 1, 3],
        &[5, 2, 4],
        &[0, 0, 0],
        &[HIR_EXPR_FORM_INDEX, HIR_EXPR_FORM_NAME, HIR_EXPR_FORM_INT],
        &[1, INVALID, INVALID],
        &[2, INVALID, INVALID],
        &[INVALID, 1, 3],
    )
    .expect("canonical in-file index operand rows should decode");

    let err = validate_hir_expression_records(
        &[
            HIR_NODE_INDEX_EXPR,
            HIR_NODE_NAME_EXPR,
            HIR_NODE_LITERAL_EXPR,
        ],
        &[1, 1, 3],
        &[5, 2, 4],
        &[0, 0, 1],
        &[HIR_EXPR_FORM_INDEX, HIR_EXPR_FORM_NAME, HIR_EXPR_FORM_INT],
        &[1, INVALID, INVALID],
        &[2, INVALID, INVALID],
        &[INVALID, 1, 3],
    )
    .expect_err("index operand edges crossing source-pack files must fail closed");

    assert!(
        err.to_string().contains("different file id"),
        "error should describe the parser-owned index operand source-file contract"
    );
}

#[test]
fn parser_hir_index_rows_must_start_at_parser_owned_base_operand() {
    validate_hir_expression_records(
        &[
            HIR_NODE_INDEX_EXPR,
            HIR_NODE_NAME_EXPR,
            HIR_NODE_LITERAL_EXPR,
        ],
        &[2, 2, 4],
        &[6, 3, 5],
        &[0, 0, 0],
        &[HIR_EXPR_FORM_INDEX, HIR_EXPR_FORM_NAME, HIR_EXPR_FORM_INT],
        &[1, INVALID, INVALID],
        &[2, INVALID, INVALID],
        &[INVALID, 2, 4],
    )
    .expect("index expression rows should decode when anchored to their base operand");

    let err = validate_hir_expression_records(
        &[
            HIR_NODE_INDEX_EXPR,
            HIR_NODE_NAME_EXPR,
            HIR_NODE_LITERAL_EXPR,
        ],
        &[1, 2, 4],
        &[6, 3, 5],
        &[0, 0, 0],
        &[HIR_EXPR_FORM_INDEX, HIR_EXPR_FORM_NAME, HIR_EXPR_FORM_INT],
        &[1, INVALID, INVALID],
        &[2, INVALID, INVALID],
        &[INVALID, 2, 4],
    )
    .expect_err("index rows that start before the base operand must fail closed");

    assert!(
        err.to_string().contains("index span does not start"),
        "error should describe the parser-owned index base/span anchor contract"
    );
}
