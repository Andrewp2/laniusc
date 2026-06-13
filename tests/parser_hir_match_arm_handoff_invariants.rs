use laniusc::parser::{
    hir_records::INVALID,
    passes::hir_nodes::{HIR_NODE_EXPR, HIR_NODE_MATCH_EXPR, HIR_NODE_NAME_EXPR, HIR_NODE_NONE},
    readback::validate_hir_match_records,
};

fn validate_match_arm_rows(first_arm_kind: u32) -> anyhow::Result<()> {
    validate_hir_match_records(
        &[
            HIR_NODE_MATCH_EXPR,
            HIR_NODE_EXPR,
            first_arm_kind,
            HIR_NODE_NONE,
            HIR_NODE_NAME_EXPR,
            HIR_NODE_NAME_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_EXPR,
        ],
        &[0, 1, 3, 8, 4, 9, 6, 11],
        &[14, 2, 7, 12, 5, 10, 7, 12],
        &[0; 8],
        &[
            1, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID,
        ],
        &[
            2, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID,
        ],
        &[2, 0, 0, 0, 0, 0, 0, 0],
        &[
            INVALID, INVALID, 3, INVALID, INVALID, INVALID, INVALID, INVALID,
        ],
        &[INVALID, INVALID, 4, 5, INVALID, INVALID, INVALID, INVALID],
        &[INVALID; 8],
        &[0; 8],
        &[INVALID, INVALID, 6, 7, INVALID, INVALID, INVALID, INVALID],
        &[INVALID; 8],
        &[INVALID, INVALID, 0, 0, INVALID, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, 0, 1, INVALID, INVALID, INVALID, INVALID],
    )
}

#[test]
fn parser_hir_match_arm_rows_must_remain_parser_owned_synthetic_rows() {
    validate_match_arm_rows(HIR_NODE_NONE)
        .expect("canonical parser-owned match arm rows should decode");

    assert!(
        validate_match_arm_rows(HIR_NODE_EXPR).is_err(),
        "concrete HIR rows must not double as parser-owned match arm rows"
    );
}

#[test]
fn parser_hir_match_rows_must_publish_parser_owned_match_records() {
    let err = validate_hir_match_records(
        &[HIR_NODE_MATCH_EXPR, HIR_NODE_EXPR],
        &[0, 1],
        &[4, 2],
        &[0, 0],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
        &[0, 0],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
        &[0, 0],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
    )
    .expect_err("match HIR rows without parser-owned match records must fail closed");

    assert!(
        err.to_string().contains("no parser-owned match record"),
        "error should describe the parser-owned match record contract"
    );
}
