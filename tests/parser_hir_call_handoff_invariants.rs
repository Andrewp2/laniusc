use laniusc::parser::{
    hir_records::INVALID,
    passes::hir_nodes::{HIR_NODE_CALL_EXPR, HIR_NODE_EXPR, HIR_NODE_NAME_EXPR},
    readback::validate_hir_call_argument_records,
};

#[test]
fn parser_hir_call_spans_must_start_at_parser_owned_callee() {
    validate_hir_call_argument_records(
        &[HIR_NODE_NAME_EXPR, HIR_NODE_CALL_EXPR],
        &[10, 10],
        &[11, 12],
        &[0, 0],
        &[INVALID, 0],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
        &[0, 0],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
    )
    .expect("zero-argument call rows should decode when the call starts at its callee");

    let err = validate_hir_call_argument_records(
        &[HIR_NODE_NAME_EXPR, HIR_NODE_CALL_EXPR],
        &[10, 9],
        &[11, 12],
        &[0, 0],
        &[INVALID, 0],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
        &[0, 0],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
    )
    .expect_err("call spans that start before the parser-owned callee must fail closed");

    assert!(
        err.to_string().contains("does not start at callee"),
        "error should describe the parser-owned call callee/span-start invariant"
    );
}

#[test]
fn parser_hir_call_arguments_must_not_cross_source_pack_files() {
    validate_hir_call_argument_records(
        &[HIR_NODE_NAME_EXPR, HIR_NODE_CALL_EXPR, HIR_NODE_EXPR],
        &[10, 10, 12],
        &[11, 20, 13],
        &[0, 0, 0],
        &[INVALID, 0, INVALID],
        &[INVALID, 2, INVALID],
        &[INVALID, INVALID, 13],
        &[0, 1, 0],
        &[INVALID, INVALID, 1],
        &[INVALID, INVALID, 0],
    )
    .expect("single-argument call rows should decode when argument and owner share a file");

    let err = validate_hir_call_argument_records(
        &[HIR_NODE_NAME_EXPR, HIR_NODE_CALL_EXPR, HIR_NODE_EXPR],
        &[10, 10, 12],
        &[11, 20, 13],
        &[0, 0, 1],
        &[INVALID, 0, INVALID],
        &[INVALID, 2, INVALID],
        &[INVALID, INVALID, 13],
        &[0, 1, 0],
        &[INVALID, INVALID, 1],
        &[INVALID, INVALID, 0],
    )
    .expect_err("call argument rows crossing source-pack files must fail closed");

    assert!(
        err.to_string().contains("different file id"),
        "error should describe the parser-owned call argument file-id contract"
    );
}

#[test]
fn parser_hir_call_argument_spans_must_follow_source_ordered_ordinals() {
    let mut token_pos = [10, 10, 12, 15];
    let token_end = [11, 24, 14, 17];

    validate_hir_call_argument_records(
        &[
            HIR_NODE_NAME_EXPR,
            HIR_NODE_CALL_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_EXPR,
        ],
        &token_pos,
        &token_end,
        &[0; 4],
        &[INVALID, 0, INVALID, INVALID],
        &[INVALID, 2, INVALID, INVALID],
        &[INVALID, INVALID, 14, 17],
        &[0, 2, 0, 0],
        &[INVALID, INVALID, 1, 1],
        &[INVALID, INVALID, 0, 1],
    )
    .expect("source-ordered call argument spans should decode");

    token_pos[3] = 13;
    let err = validate_hir_call_argument_records(
        &[
            HIR_NODE_NAME_EXPR,
            HIR_NODE_CALL_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_EXPR,
        ],
        &token_pos,
        &token_end,
        &[0; 4],
        &[INVALID, 0, INVALID, INVALID],
        &[INVALID, 2, INVALID, INVALID],
        &[INVALID, INVALID, 14, 17],
        &[0, 2, 0, 0],
        &[INVALID, INVALID, 1, 1],
        &[INVALID, INVALID, 0, 1],
    )
    .expect_err("call argument ordinals must not describe overlapping source spans");

    assert!(
        err.to_string()
            .contains("overlap or are not in source order"),
        "error should describe the parser-owned call argument span ordering contract"
    );
}
