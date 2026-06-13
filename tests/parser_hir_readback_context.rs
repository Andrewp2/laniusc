use laniusc::parser::{
    hir_records::INVALID,
    passes::{
        hir_nodes::{
            HIR_NODE_ARRAY_EXPR,
            HIR_NODE_BLOCK,
            HIR_NODE_BREAK_STMT,
            HIR_NODE_CALL_EXPR,
            HIR_NODE_FN,
            HIR_NODE_IF_STMT,
            HIR_NODE_LET_STMT,
            HIR_NODE_NAME_EXPR,
            HIR_NODE_STRUCT_LITERAL_EXPR,
            HIR_NODE_WHILE_STMT,
        },
        hir_stmt_fields::{
            HIR_STMT_RECORD_KIND_BREAK as STMT_RECORD_KIND_BREAK,
            HIR_STMT_RECORD_KIND_IF as STMT_RECORD_KIND_IF,
            HIR_STMT_RECORD_KIND_LET as STMT_RECORD_KIND_LET,
            HIR_STMT_RECORD_KIND_NONE as STMT_RECORD_KIND_NONE,
            HIR_STMT_RECORD_KIND_WHILE as STMT_RECORD_KIND_WHILE,
        },
    },
    readback::validate_hir_context_relation_records,
};

#[test]
fn parser_hir_context_readback_rejects_specialized_context_function_mismatch() {
    let err = validate_hir_context_relation_records(
        &[
            HIR_NODE_FN,
            HIR_NODE_BLOCK,
            HIR_NODE_LET_STMT,
            HIR_NODE_CALL_EXPR,
            HIR_NODE_FN,
        ],
        &[0, 1, 2, 3, 0],
        &[10, 9, 6, 4, 10],
        &[0; 5],
        &[
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_LET,
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_NONE,
        ],
        &[INVALID, INVALID, 2, 2, INVALID],
        &[INVALID, 1, 1, 1, INVALID],
        &[INVALID; 5],
        &[INVALID; 5],
        &[0, 0, 0, 4, 4],
        &[INVALID, INVALID, INVALID, 2, INVALID],
        &[INVALID; 5],
        &[INVALID; 5],
    )
    .expect_err("specialized call context rows must inherit their statement's nearest function");

    assert!(
        err.to_string().contains("nearest function relation")
            && err
                .to_string()
                .contains("disagrees with context nearest function relation"),
        "error should describe the parser-owned contextual nearest-function contract"
    );
}

#[test]
fn parser_hir_context_readback_rejects_specialized_context_statement_mismatch() {
    let mut call_context_stmt_nodes = [INVALID, INVALID, INVALID, INVALID, 2];

    validate_hir_context_relation_records(
        &[
            HIR_NODE_FN,
            HIR_NODE_BLOCK,
            HIR_NODE_LET_STMT,
            HIR_NODE_LET_STMT,
            HIR_NODE_CALL_EXPR,
        ],
        &[0, 1, 2, 3, 4],
        &[12, 11, 10, 9, 5],
        &[0; 5],
        &[
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_LET,
            STMT_RECORD_KIND_LET,
            STMT_RECORD_KIND_NONE,
        ],
        &[INVALID, INVALID, 2, 3, 2],
        &[INVALID, 1, 1, 1, 1],
        &[INVALID; 5],
        &[INVALID; 5],
        &[0; 5],
        &call_context_stmt_nodes,
        &[INVALID; 5],
        &[INVALID; 5],
    )
    .expect("canonical call context rows should decode");

    call_context_stmt_nodes[4] = 3;
    let err = validate_hir_context_relation_records(
        &[
            HIR_NODE_FN,
            HIR_NODE_BLOCK,
            HIR_NODE_LET_STMT,
            HIR_NODE_LET_STMT,
            HIR_NODE_CALL_EXPR,
        ],
        &[0, 1, 2, 3, 4],
        &[12, 11, 10, 9, 5],
        &[0; 5],
        &[
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_LET,
            STMT_RECORD_KIND_LET,
            STMT_RECORD_KIND_NONE,
        ],
        &[INVALID, INVALID, 2, 3, 2],
        &[INVALID, 1, 1, 1, 1],
        &[INVALID; 5],
        &[INVALID; 5],
        &[0; 5],
        &call_context_stmt_nodes,
        &[INVALID; 5],
        &[INVALID; 5],
    )
    .expect_err("specialized contextual rows must match the generic nearest statement");

    assert!(
        err.to_string().contains("disagrees with nearest statement"),
        "error should describe the parser-owned generic/specialized statement bridge"
    );
}

#[test]
fn parser_hir_context_readback_rejects_statement_block_context_mismatch() {
    let kinds = [
        HIR_NODE_FN,
        HIR_NODE_BLOCK,
        HIR_NODE_LET_STMT,
        HIR_NODE_NAME_EXPR,
        HIR_NODE_BLOCK,
    ];
    let token_pos = [0, 1, 2, 5, 4];
    let token_end = [20, 19, 12, 6, 8];
    let stmt_record_kinds = [
        STMT_RECORD_KIND_NONE,
        STMT_RECORD_KIND_NONE,
        STMT_RECORD_KIND_LET,
        STMT_RECORD_KIND_NONE,
        STMT_RECORD_KIND_NONE,
    ];
    let nearest_stmt_nodes = [INVALID, INVALID, 2, 2, INVALID];
    let mut nearest_block_nodes = [INVALID, 1, 1, 1, 4];

    validate_hir_context_relation_records(
        &kinds,
        &token_pos,
        &token_end,
        &[0; 5],
        &stmt_record_kinds,
        &nearest_stmt_nodes,
        &nearest_block_nodes,
        &[INVALID; 5],
        &[INVALID; 5],
        &[0; 5],
        &[INVALID; 5],
        &[INVALID; 5],
        &[INVALID; 5],
    )
    .expect("canonical generic context rows should keep statements inside their nearest block");

    nearest_block_nodes[3] = 4;
    let err = validate_hir_context_relation_records(
        &kinds,
        &token_pos,
        &token_end,
        &[0; 5],
        &stmt_record_kinds,
        &nearest_stmt_nodes,
        &nearest_block_nodes,
        &[INVALID; 5],
        &[INVALID; 5],
        &[0; 5],
        &[INVALID; 5],
        &[INVALID; 5],
        &[INVALID; 5],
    )
    .expect_err("generic context rows must not mix statement and block contexts");

    let message = err.to_string();
    assert!(
        message.contains("nearest block relation")
            && message.contains("does not contain nearest statement relation"),
        "error should describe the parser-owned statement/block context chain"
    );
}

#[test]
fn parser_hir_context_readback_rejects_literal_context_statement_mismatch() {
    for (owner_kind, context_index, label) in [
        (
            HIR_NODE_ARRAY_EXPR,
            0usize,
            "array literal contextual statement",
        ),
        (
            HIR_NODE_STRUCT_LITERAL_EXPR,
            1usize,
            "struct literal contextual statement",
        ),
    ] {
        let mut array_context_stmt_nodes = [INVALID; 5];
        let mut struct_context_stmt_nodes = [INVALID; 5];
        if context_index == 0 {
            array_context_stmt_nodes[4] = 2;
        } else {
            struct_context_stmt_nodes[4] = 2;
        }

        validate_hir_context_relation_records(
            &[
                HIR_NODE_FN,
                HIR_NODE_BLOCK,
                HIR_NODE_LET_STMT,
                HIR_NODE_LET_STMT,
                owner_kind,
            ],
            &[0, 1, 2, 3, 4],
            &[12, 11, 10, 9, 5],
            &[0; 5],
            &[
                STMT_RECORD_KIND_NONE,
                STMT_RECORD_KIND_NONE,
                STMT_RECORD_KIND_LET,
                STMT_RECORD_KIND_LET,
                STMT_RECORD_KIND_NONE,
            ],
            &[INVALID, INVALID, 2, 3, 2],
            &[INVALID, 1, 1, 1, 1],
            &[INVALID; 5],
            &[INVALID; 5],
            &[0; 5],
            &[INVALID; 5],
            &array_context_stmt_nodes,
            &struct_context_stmt_nodes,
        )
        .expect("canonical literal context rows should decode");

        if context_index == 0 {
            array_context_stmt_nodes[4] = 3;
        } else {
            struct_context_stmt_nodes[4] = 3;
        }
        let err = validate_hir_context_relation_records(
            &[
                HIR_NODE_FN,
                HIR_NODE_BLOCK,
                HIR_NODE_LET_STMT,
                HIR_NODE_LET_STMT,
                owner_kind,
            ],
            &[0, 1, 2, 3, 4],
            &[12, 11, 10, 9, 5],
            &[0; 5],
            &[
                STMT_RECORD_KIND_NONE,
                STMT_RECORD_KIND_NONE,
                STMT_RECORD_KIND_LET,
                STMT_RECORD_KIND_LET,
                STMT_RECORD_KIND_NONE,
            ],
            &[INVALID, INVALID, 2, 3, 2],
            &[INVALID, 1, 1, 1, 1],
            &[INVALID; 5],
            &[INVALID; 5],
            &[0; 5],
            &[INVALID; 5],
            &array_context_stmt_nodes,
            &struct_context_stmt_nodes,
        )
        .expect_err("literal context rows must match the generic nearest statement");

        let message = err.to_string();
        assert!(
            message.contains(label) && message.contains("disagrees with nearest statement"),
            "error should describe the parser-owned {label} bridge"
        );
    }
}

#[test]
fn parser_hir_context_readback_rejects_control_relations_without_parser_owned_records() {
    let stale_if_err = validate_hir_context_relation_records(
        &[
            HIR_NODE_FN,
            HIR_NODE_BLOCK,
            HIR_NODE_IF_STMT,
            HIR_NODE_BLOCK,
            HIR_NODE_LET_STMT,
            HIR_NODE_CALL_EXPR,
        ],
        &[0, 1, 2, 3, 4, 5],
        &[12, 11, 10, 9, 8, 6],
        &[0; 6],
        &[
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_LET,
            STMT_RECORD_KIND_NONE,
        ],
        &[INVALID, INVALID, INVALID, INVALID, 4, 4],
        &[INVALID, 1, 1, 3, 3, 3],
        &[INVALID, INVALID, INVALID, 2, 2, 2],
        &[INVALID; 6],
        &[0; 6],
        &[INVALID, INVALID, INVALID, INVALID, INVALID, 4],
        &[INVALID; 6],
        &[INVALID; 6],
    )
    .expect_err("nearest-control rows must point at parser-owned control statement records");

    assert!(
        stale_if_err
            .to_string()
            .contains("nearest enclosing control relation")
            && stale_if_err
                .to_string()
                .contains("parser-owned control statement record"),
        "error should describe the parser-owned control-context record contract"
    );

    let stale_loop_err = validate_hir_context_relation_records(
        &[
            HIR_NODE_FN,
            HIR_NODE_BLOCK,
            HIR_NODE_WHILE_STMT,
            HIR_NODE_BLOCK,
            HIR_NODE_BREAK_STMT,
        ],
        &[0, 1, 2, 3, 4],
        &[12, 11, 10, 9, 5],
        &[0; 5],
        &[
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_BREAK,
        ],
        &[INVALID, INVALID, INVALID, INVALID, 4],
        &[INVALID, 1, 1, 3, 3],
        &[INVALID, INVALID, INVALID, 2, 2],
        &[INVALID, INVALID, 2, 2, 2],
        &[0; 5],
        &[INVALID; 5],
        &[INVALID; 5],
        &[INVALID; 5],
    )
    .expect_err("nearest-loop rows must point at parser-owned loop statement records");

    assert!(
        stale_loop_err.to_string().contains("nearest loop relation")
            && stale_loop_err
                .to_string()
                .contains("parser-owned loop statement record"),
        "error should describe the parser-owned loop-context record contract"
    );
}

#[test]
fn parser_hir_context_readback_rejects_context_rows_that_drop_loop_membership() {
    let kinds = [
        HIR_NODE_FN,
        HIR_NODE_BLOCK,
        HIR_NODE_WHILE_STMT,
        HIR_NODE_BLOCK,
        HIR_NODE_LET_STMT,
        HIR_NODE_CALL_EXPR,
    ];
    let token_pos = [0, 1, 2, 3, 4, 5];
    let token_end = [30, 29, 20, 19, 18, 8];
    let stmt_record_kinds = [
        STMT_RECORD_KIND_NONE,
        STMT_RECORD_KIND_NONE,
        STMT_RECORD_KIND_WHILE,
        STMT_RECORD_KIND_NONE,
        STMT_RECORD_KIND_LET,
        STMT_RECORD_KIND_NONE,
    ];
    let nearest_stmt_nodes = [INVALID, INVALID, 2, INVALID, 4, 4];
    let nearest_block_nodes = [INVALID, 1, 1, 3, 3, 3];
    let canonical_nearest_control_nodes = [INVALID, INVALID, INVALID, 2, 2, 2];
    let canonical_nearest_loop_nodes = [INVALID, INVALID, 2, 2, 2, 2];
    let nearest_fn_nodes = [0; 6];
    let call_context_stmt_nodes = [INVALID, INVALID, INVALID, INVALID, INVALID, 4];

    validate_hir_context_relation_records(
        &kinds,
        &token_pos,
        &token_end,
        &[0; 6],
        &stmt_record_kinds,
        &nearest_stmt_nodes,
        &nearest_block_nodes,
        &canonical_nearest_control_nodes,
        &canonical_nearest_loop_nodes,
        &nearest_fn_nodes,
        &call_context_stmt_nodes,
        &[INVALID; 6],
        &[INVALID; 6],
    )
    .expect("canonical call context rows inside a loop should decode");

    let mut stale_nearest_control_nodes = canonical_nearest_control_nodes;
    let mut stale_nearest_loop_nodes = canonical_nearest_loop_nodes;
    stale_nearest_control_nodes[5] = INVALID;
    stale_nearest_loop_nodes[5] = INVALID;

    let err = validate_hir_context_relation_records(
        &kinds,
        &token_pos,
        &token_end,
        &[0; 6],
        &stmt_record_kinds,
        &nearest_stmt_nodes,
        &nearest_block_nodes,
        &stale_nearest_control_nodes,
        &stale_nearest_loop_nodes,
        &nearest_fn_nodes,
        &call_context_stmt_nodes,
        &[INVALID; 6],
        &[INVALID; 6],
    )
    .expect_err("contextual rows must inherit loop membership from their statement context");

    assert!(
        err.to_string().contains("call contextual statement")
            && err
                .to_string()
                .contains("without matching nearest loop relation"),
        "error should describe the parser-owned contextual loop-membership bridge"
    );
}

#[test]
fn parser_hir_context_readback_rejects_context_rows_that_add_control_membership() {
    let kinds = [
        HIR_NODE_FN,
        HIR_NODE_BLOCK,
        HIR_NODE_IF_STMT,
        HIR_NODE_BLOCK,
        HIR_NODE_LET_STMT,
        HIR_NODE_CALL_EXPR,
    ];
    let token_pos = [0, 1, 2, 3, 4, 5];
    let token_end = [30, 29, 20, 19, 18, 8];
    let stmt_record_kinds = [
        STMT_RECORD_KIND_NONE,
        STMT_RECORD_KIND_NONE,
        STMT_RECORD_KIND_IF,
        STMT_RECORD_KIND_NONE,
        STMT_RECORD_KIND_LET,
        STMT_RECORD_KIND_NONE,
    ];
    let nearest_stmt_nodes = [INVALID, INVALID, 2, INVALID, 4, 4];
    let nearest_block_nodes = [INVALID, 1, 1, 3, 3, 3];
    let nearest_fn_nodes = [0; 6];
    let call_context_stmt_nodes = [INVALID, INVALID, INVALID, INVALID, INVALID, 4];

    validate_hir_context_relation_records(
        &kinds,
        &token_pos,
        &token_end,
        &[0; 6],
        &stmt_record_kinds,
        &nearest_stmt_nodes,
        &nearest_block_nodes,
        &[INVALID; 6],
        &[INVALID; 6],
        &nearest_fn_nodes,
        &call_context_stmt_nodes,
        &[INVALID; 6],
        &[INVALID; 6],
    )
    .expect("context rows without a control relation should decode when the statement lacks one");

    let stale_nearest_control_nodes = [INVALID, INVALID, INVALID, 2, INVALID, 2];
    let err = validate_hir_context_relation_records(
        &kinds,
        &token_pos,
        &token_end,
        &[0; 6],
        &stmt_record_kinds,
        &nearest_stmt_nodes,
        &nearest_block_nodes,
        &stale_nearest_control_nodes,
        &[INVALID; 6],
        &nearest_fn_nodes,
        &call_context_stmt_nodes,
        &[INVALID; 6],
        &[INVALID; 6],
    )
    .expect_err(
        "contextual rows must not invent control membership absent from their statement context",
    );

    let message = err.to_string();
    assert!(
        message.contains("call contextual statement")
            && message.contains("extra nearest enclosing control relation"),
        "error should describe the parser-owned contextual control-membership bridge"
    );
}

#[test]
fn parser_hir_context_readback_rejects_call_context_rows_with_stale_control_membership() {
    let kinds = [
        HIR_NODE_FN,
        HIR_NODE_BLOCK,
        HIR_NODE_WHILE_STMT,
        HIR_NODE_BLOCK,
        HIR_NODE_IF_STMT,
        HIR_NODE_BLOCK,
        HIR_NODE_LET_STMT,
        HIR_NODE_CALL_EXPR,
    ];
    let token_pos = [0, 1, 2, 3, 4, 5, 6, 10];
    let token_end = [40, 39, 35, 34, 30, 29, 20, 18];
    let stmt_record_kinds = [
        STMT_RECORD_KIND_NONE,
        STMT_RECORD_KIND_NONE,
        STMT_RECORD_KIND_WHILE,
        STMT_RECORD_KIND_NONE,
        STMT_RECORD_KIND_IF,
        STMT_RECORD_KIND_NONE,
        STMT_RECORD_KIND_LET,
        STMT_RECORD_KIND_NONE,
    ];
    let nearest_stmt_nodes = [INVALID, INVALID, 2, INVALID, 4, INVALID, 6, 6];
    let nearest_block_nodes = [INVALID, 1, 1, 3, 3, 5, 5, 5];
    let nearest_loop_nodes = [INVALID, INVALID, 2, 2, 2, 2, 2, 2];
    let nearest_fn_nodes = [0; 8];
    let call_context_stmt_nodes = [
        INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, 6,
    ];
    let mut nearest_control_nodes = [INVALID, INVALID, INVALID, 2, 2, 4, 4, 4];

    validate_hir_context_relation_records(
        &kinds,
        &token_pos,
        &token_end,
        &[0; 8],
        &stmt_record_kinds,
        &nearest_stmt_nodes,
        &nearest_block_nodes,
        &nearest_control_nodes,
        &nearest_loop_nodes,
        &nearest_fn_nodes,
        &call_context_stmt_nodes,
        &[INVALID; 8],
        &[INVALID; 8],
    )
    .expect("canonical call context rows inside nested control should decode");

    nearest_control_nodes[7] = 2;
    let err = validate_hir_context_relation_records(
        &kinds,
        &token_pos,
        &token_end,
        &[0; 8],
        &stmt_record_kinds,
        &nearest_stmt_nodes,
        &nearest_block_nodes,
        &nearest_control_nodes,
        &nearest_loop_nodes,
        &nearest_fn_nodes,
        &call_context_stmt_nodes,
        &[INVALID; 8],
        &[INVALID; 8],
    )
    .expect_err("call context rows must inherit their statement's nearest control");

    let message = err.to_string();
    assert!(
        message.contains("call contextual statement")
            && message.contains("nearest enclosing control")
            && message.contains("disagrees with context"),
        "error should describe the parser-owned call control-context bridge"
    );
}

#[test]
fn parser_hir_context_readback_rejects_literal_context_rows_with_stale_control_membership() {
    for (owner_kind, context_index, label) in [
        (
            HIR_NODE_ARRAY_EXPR,
            0usize,
            "array literal contextual statement",
        ),
        (
            HIR_NODE_STRUCT_LITERAL_EXPR,
            1usize,
            "struct literal contextual statement",
        ),
    ] {
        let kinds = [
            HIR_NODE_FN,
            HIR_NODE_BLOCK,
            HIR_NODE_WHILE_STMT,
            HIR_NODE_BLOCK,
            HIR_NODE_IF_STMT,
            HIR_NODE_BLOCK,
            HIR_NODE_LET_STMT,
            owner_kind,
        ];
        let token_pos = [0, 1, 2, 3, 4, 5, 6, 10];
        let token_end = [40, 39, 35, 34, 30, 29, 20, 18];
        let stmt_record_kinds = [
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_WHILE,
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_IF,
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_LET,
            STMT_RECORD_KIND_NONE,
        ];
        let nearest_stmt_nodes = [INVALID, INVALID, 2, INVALID, 4, INVALID, 6, 6];
        let nearest_block_nodes = [INVALID, 1, 1, 3, 3, 5, 5, 5];
        let nearest_loop_nodes = [INVALID, INVALID, 2, 2, 2, 2, 2, 2];
        let nearest_fn_nodes = [0; 8];
        let mut nearest_control_nodes = [INVALID, INVALID, INVALID, 2, 2, 4, 4, 4];
        let mut array_context_stmt_nodes = [INVALID; 8];
        let mut struct_context_stmt_nodes = [INVALID; 8];
        if context_index == 0 {
            array_context_stmt_nodes[7] = 6;
        } else {
            struct_context_stmt_nodes[7] = 6;
        }

        validate_hir_context_relation_records(
            &kinds,
            &token_pos,
            &token_end,
            &[0; 8],
            &stmt_record_kinds,
            &nearest_stmt_nodes,
            &nearest_block_nodes,
            &nearest_control_nodes,
            &nearest_loop_nodes,
            &nearest_fn_nodes,
            &[INVALID; 8],
            &array_context_stmt_nodes,
            &struct_context_stmt_nodes,
        )
        .expect("canonical literal context rows inside nested control should decode");

        nearest_control_nodes[7] = 2;
        let err = validate_hir_context_relation_records(
            &kinds,
            &token_pos,
            &token_end,
            &[0; 8],
            &stmt_record_kinds,
            &nearest_stmt_nodes,
            &nearest_block_nodes,
            &nearest_control_nodes,
            &nearest_loop_nodes,
            &nearest_fn_nodes,
            &[INVALID; 8],
            &array_context_stmt_nodes,
            &struct_context_stmt_nodes,
        )
        .expect_err("literal context rows must inherit their statement's nearest control");

        let message = err.to_string();
        assert!(
            message.contains(label)
                && message.contains("nearest enclosing control")
                && message.contains("disagrees with context"),
            "error should describe the parser-owned {label} control-context bridge"
        );
    }
}
