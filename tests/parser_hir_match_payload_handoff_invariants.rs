use laniusc::parser::{
    hir_records::INVALID,
    passes::hir_nodes::{HIR_NODE_EXPR, HIR_NODE_MATCH_EXPR, HIR_NODE_NAME_EXPR, HIR_NODE_NONE},
    readback::validate_hir_match_records,
};

fn validate_match_payload_rows(
    first_payload_end: u32,
    second_payload_start: u32,
) -> anyhow::Result<()> {
    validate_hir_match_records(
        &[
            HIR_NODE_MATCH_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_NONE,
            HIR_NODE_NAME_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_NAME_EXPR,
            HIR_NODE_NAME_EXPR,
        ],
        &[0, 1, 3, 4, 10, 5, second_payload_start],
        &[14, 2, 13, 10, 12, first_payload_end, 9],
        &[0; 7],
        &[1, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID],
        &[2, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID],
        &[1, 0, 0, 0, 0, 0, 0],
        &[
            INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID,
        ],
        &[INVALID, INVALID, 3, INVALID, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, 5, INVALID, INVALID, INVALID, INVALID],
        &[0, 0, 2, 0, 0, 0, 0],
        &[INVALID, INVALID, 4, INVALID, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, INVALID, INVALID, INVALID, 2, 2],
        &[INVALID, INVALID, 0, INVALID, INVALID, 0, 0],
        &[INVALID, INVALID, 0, INVALID, INVALID, 0, 1],
    )
}

fn validate_match_payload_pattern_containment_rows(
    payload_start: u32,
    payload_end: u32,
) -> anyhow::Result<()> {
    validate_hir_match_records(
        &[
            HIR_NODE_MATCH_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_NONE,
            HIR_NODE_NAME_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_NAME_EXPR,
        ],
        &[0, 1, 3, 4, 10, payload_start],
        &[14, 2, 13, 8, 12, payload_end],
        &[0; 6],
        &[1, INVALID, INVALID, INVALID, INVALID, INVALID],
        &[2, INVALID, INVALID, INVALID, INVALID, INVALID],
        &[1, 0, 0, 0, 0, 0],
        &[INVALID, INVALID, INVALID, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, 3, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, 5, INVALID, INVALID, INVALID],
        &[0, 0, 1, 0, 0, 0],
        &[INVALID, INVALID, 4, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, INVALID, INVALID, INVALID, 2],
        &[INVALID, INVALID, 0, INVALID, INVALID, 0],
        &[INVALID, INVALID, 0, INVALID, INVALID, 0],
    )
}

fn validate_match_payload_source_file_rows(node_file_ids: [u32; 6]) -> anyhow::Result<()> {
    validate_hir_match_records(
        &[
            HIR_NODE_MATCH_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_NONE,
            HIR_NODE_NAME_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_NAME_EXPR,
        ],
        &[0, 1, 3, 4, 10, 5],
        &[14, 2, 13, 8, 12, 7],
        &node_file_ids,
        &[1, INVALID, INVALID, INVALID, INVALID, INVALID],
        &[2, INVALID, INVALID, INVALID, INVALID, INVALID],
        &[1, 0, 0, 0, 0, 0],
        &[INVALID, INVALID, INVALID, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, 3, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, 5, INVALID, INVALID, INVALID],
        &[0, 0, 1, 0, 0, 0],
        &[INVALID, INVALID, 4, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, INVALID, INVALID, INVALID, 2],
        &[INVALID, INVALID, 0, INVALID, INVALID, 0],
        &[INVALID, INVALID, 0, INVALID, INVALID, 0],
    )
}

#[test]
fn parser_hir_match_payload_rows_must_not_overlap_within_owner_arm() {
    validate_match_payload_rows(7, 8)
        .expect("source-ordered non-overlapping match payload rows should decode");

    let err = validate_match_payload_rows(9, 8)
        .expect_err("overlapping match payload spans must fail before type checking");
    assert!(
        err.to_string().contains("payload rows overlap"),
        "error should describe the parser-owned match payload sibling-span invariant"
    );
}

#[test]
fn parser_hir_match_payload_rows_must_not_cross_source_pack_files() {
    validate_match_payload_source_file_rows([0; 6])
        .expect("same-file match payload rows should decode");

    let err = validate_match_payload_source_file_rows([0, 0, 0, 0, 0, 1])
        .expect_err("match payload rows crossing source-pack files must fail closed");
    assert!(
        err.to_string().contains("different file id"),
        "error should describe the parser-owned match payload source-file contract"
    );
}

#[test]
fn parser_hir_match_payload_rows_must_stay_inside_owner_pattern() {
    validate_match_payload_pattern_containment_rows(5, 7)
        .expect("payload rows inside the owner arm pattern should decode");

    let err = validate_match_payload_pattern_containment_rows(8, 9)
        .expect_err("payload rows outside the owner pattern must fail before type checking");
    assert!(
        err.to_string().contains("outside owner arm"),
        "error should describe the parser-owned match payload pattern-containment invariant"
    );
}

#[test]
fn parser_hir_match_payload_rows_must_not_alias_pattern_head_token() {
    validate_match_payload_pattern_containment_rows(5, 7)
        .expect("payload rows after the owner pattern head should decode");

    let err = validate_match_payload_pattern_containment_rows(4, 6)
        .expect_err("payload rows at the pattern head token must fail before type checking");
    assert!(
        err.to_string().contains("pattern head"),
        "error should describe the parser-owned payload binder token invariant"
    );
}
