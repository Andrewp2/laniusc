use laniusc::parser::{
    hir_records::INVALID,
    passes::{
        hir_nodes::{
            HIR_NODE_CALL_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_NONE,
            HIR_NODE_PATH_EXPR,
            HIR_NODE_TYPE,
        },
        hir_type_fields::{HIR_TYPE_FORM_NONE, HIR_TYPE_FORM_PATH},
    },
    readback::{
        validate_hir_expression_result_root_records,
        validate_hir_type_argument_records,
        validate_hir_type_records,
    },
};

#[test]
fn parser_hir_expression_result_roots_must_not_cross_source_pack_files() {
    validate_hir_expression_result_root_records(
        &[HIR_NODE_EXPR, HIR_NODE_CALL_EXPR],
        &[0, 1],
        &[4, 3],
        &[0, 0],
        &[1, 1],
    )
    .expect("canonical in-file expression-result root rows should decode");

    let err = validate_hir_expression_result_root_records(
        &[HIR_NODE_EXPR, HIR_NODE_CALL_EXPR],
        &[0, 1],
        &[4, 3],
        &[0, 1],
        &[1, 1],
    )
    .expect_err("expression-result roots crossing source-pack files must fail closed");

    assert!(
        err.to_string().contains("different file id"),
        "error should describe the parser-owned expression-result root file-id contract"
    );
}

#[test]
fn parser_hir_generic_type_arguments_must_not_cross_source_pack_files() {
    validate_hir_type_argument_records(
        &[HIR_NODE_TYPE, HIR_NODE_TYPE],
        &[0, 2],
        &[5, 4],
        &[0, 0],
        &[HIR_TYPE_FORM_PATH, HIR_TYPE_FORM_PATH],
        &[1, INVALID],
        &[1, 0],
        &[INVALID, INVALID],
    )
    .expect("generic type-argument chains should decode inside one source-pack file");

    let err = validate_hir_type_argument_records(
        &[HIR_NODE_TYPE, HIR_NODE_TYPE],
        &[0, 2],
        &[5, 4],
        &[0, 1],
        &[HIR_TYPE_FORM_PATH, HIR_TYPE_FORM_PATH],
        &[1, INVALID],
        &[1, 0],
        &[INVALID, INVALID],
    )
    .expect_err("generic type-argument chains crossing source-pack files must fail closed");

    assert!(
        err.to_string().contains("different file id than owner row"),
        "error should describe the parser-owned generic type-argument source-file contract"
    );
}

#[test]
fn parser_hir_path_type_leaf_must_match_parser_owned_path_leaf() {
    validate_hir_type_records(
        &[
            HIR_NODE_TYPE,
            HIR_NODE_PATH_EXPR,
            HIR_NODE_NONE,
            HIR_NODE_NONE,
        ],
        &[0, 0, 0, 5],
        &[6, 6, 1, 6],
        &[0, 0, 0, 0],
        &[
            HIR_TYPE_FORM_PATH,
            HIR_TYPE_FORM_NONE,
            HIR_TYPE_FORM_NONE,
            HIR_TYPE_FORM_NONE,
        ],
        &[1, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, INVALID, INVALID],
        &[0, 0, 0, 0],
        &[3, 3, INVALID, INVALID],
    )
    .expect("path type rows should decode when they use the parser-owned path leaf");

    let err = validate_hir_type_records(
        &[
            HIR_NODE_TYPE,
            HIR_NODE_PATH_EXPR,
            HIR_NODE_NONE,
            HIR_NODE_NONE,
        ],
        &[0, 0, 0, 5],
        &[6, 6, 1, 6],
        &[0, 0, 0, 0],
        &[
            HIR_TYPE_FORM_PATH,
            HIR_TYPE_FORM_NONE,
            HIR_TYPE_FORM_NONE,
            HIR_TYPE_FORM_NONE,
        ],
        &[1, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, INVALID, INVALID],
        &[0, 0, 0, 0],
        &[2, 3, INVALID, INVALID],
    )
    .expect_err("path types must not substitute a different in-span path leaf");

    assert!(
        err.to_string()
            .contains("different from parser-owned path node"),
        "error should describe the parser-owned path type leaf contract"
    );
}

#[test]
fn parser_hir_path_type_span_must_start_at_parser_owned_path_row() {
    let validate = |type_start| {
        validate_hir_type_records(
            &[HIR_NODE_TYPE, HIR_NODE_PATH_EXPR, HIR_NODE_NONE],
            &[type_start, 4, 6],
            &[9, 7, 7],
            &[0; 3],
            &[HIR_TYPE_FORM_PATH, HIR_TYPE_FORM_NONE, HIR_TYPE_FORM_NONE],
            &[1, INVALID, INVALID],
            &[INVALID; 3],
            &[INVALID; 3],
            &[0, INVALID, INVALID],
            &[2, 2, INVALID],
        )
    };

    validate(4).expect("path type rows may extend past the parser-owned path row");

    let err =
        validate(3).expect_err("path type rows must not start before their parser-owned path row");

    assert!(
        err.to_string().contains("path type span does not start"),
        "error should describe the parser-owned path type span anchor contract"
    );
}
