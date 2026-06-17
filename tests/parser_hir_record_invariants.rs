use laniusc_compiler::parser::{
    hir_records::INVALID,
    passes::hir::{
        item::fields::{
            HIR_ITEM_IMPORT_TARGET_NONE,
            HIR_ITEM_IMPORT_TARGET_PATH,
            HIR_ITEM_KIND_ENUM,
            HIR_ITEM_KIND_ENUM_VARIANT,
            HIR_ITEM_KIND_FN,
            HIR_ITEM_KIND_IMPORT,
            HIR_ITEM_KIND_MODULE,
            HIR_ITEM_KIND_NONE,
            HIR_ITEM_KIND_STRUCT,
        },
        nodes::{
            HIR_NODE_ARRAY_EXPR,
            HIR_NODE_ENUM_ITEM,
            HIR_NODE_EXPR,
            HIR_NODE_FN,
            HIR_NODE_IMPORT_ITEM,
            HIR_NODE_ITEM,
            HIR_NODE_MATCH_EXPR,
            HIR_NODE_MEMBER_EXPR,
            HIR_NODE_MODULE_ITEM,
            HIR_NODE_NAME_EXPR,
            HIR_NODE_NONE,
            HIR_NODE_PARAM,
            HIR_NODE_PATH_EXPR,
            HIR_NODE_STRUCT_ITEM,
            HIR_NODE_STRUCT_LITERAL_EXPR,
            HIR_NODE_TYPE,
        },
        types::fields::{HIR_TYPE_FORM_NONE, HIR_TYPE_FORM_PATH},
    },
    readback::{
        validate_hir_array_literal_records,
        validate_hir_enum_variant_records,
        validate_hir_item_path_records,
        validate_hir_match_records,
        validate_hir_member_records,
        validate_hir_parameter_records,
        validate_hir_source_address_records,
        validate_hir_struct_declaration_field_records,
        validate_hir_struct_literal_field_records,
        validate_hir_type_records,
    },
};

#[derive(Clone, Copy)]
struct HirSourceAddressRow {
    hir_kind: u32,
    token_pos: u32,
    token_end: u32,
    node_file_id: u32,
    type_form: u32,
    type_file_id: u32,
    item_kind: u32,
    item_file_id: u32,
}

const EMPTY_ROW: HirSourceAddressRow = HirSourceAddressRow {
    hir_kind: HIR_NODE_NONE,
    token_pos: INVALID,
    token_end: INVALID,
    node_file_id: INVALID,
    type_form: HIR_TYPE_FORM_NONE,
    type_file_id: INVALID,
    item_kind: HIR_ITEM_KIND_NONE,
    item_file_id: INVALID,
};

const PLAIN_EXPR_ROW: HirSourceAddressRow = HirSourceAddressRow {
    hir_kind: HIR_NODE_NAME_EXPR,
    token_pos: 12,
    token_end: 13,
    node_file_id: 0,
    ..EMPTY_ROW
};

const FIRST_ITEM_ROW: HirSourceAddressRow = HirSourceAddressRow {
    hir_kind: HIR_NODE_FN,
    token_pos: 2,
    token_end: 8,
    node_file_id: 0,
    item_kind: HIR_ITEM_KIND_FN,
    item_file_id: 0,
    ..EMPTY_ROW
};

const TYPE_ROW: HirSourceAddressRow = HirSourceAddressRow {
    hir_kind: HIR_NODE_TYPE,
    token_pos: 9,
    token_end: 11,
    node_file_id: 0,
    type_form: HIR_TYPE_FORM_PATH,
    type_file_id: 0,
    ..EMPTY_ROW
};

const TYPE_ROW_WITH_SHARED_START_AND_LONGER_END: HirSourceAddressRow = HirSourceAddressRow {
    token_end: 12,
    ..TYPE_ROW
};

const NEXT_FILE_ITEM_ROW: HirSourceAddressRow = HirSourceAddressRow {
    hir_kind: HIR_NODE_FN,
    token_pos: 1,
    token_end: 6,
    node_file_id: 1,
    item_kind: HIR_ITEM_KIND_FN,
    item_file_id: 1,
    ..EMPTY_ROW
};

fn validate_rows(rows: &[HirSourceAddressRow]) -> anyhow::Result<()> {
    validate_hir_source_address_records(
        &rows.iter().map(|row| row.hir_kind).collect::<Vec<_>>(),
        &rows.iter().map(|row| row.token_pos).collect::<Vec<_>>(),
        &rows.iter().map(|row| row.token_end).collect::<Vec<_>>(),
        &rows.iter().map(|row| row.node_file_id).collect::<Vec<_>>(),
        &rows.iter().map(|row| row.type_form).collect::<Vec<_>>(),
        &rows.iter().map(|row| row.type_file_id).collect::<Vec<_>>(),
        &rows.iter().map(|row| row.item_kind).collect::<Vec<_>>(),
        &rows.iter().map(|row| row.item_file_id).collect::<Vec<_>>(),
    )
}

#[test]
fn parser_hir_source_address_records_keep_public_rows_in_flat_source_order() {
    validate_rows(&[
        EMPTY_ROW,
        FIRST_ITEM_ROW,
        PLAIN_EXPR_ROW,
        TYPE_ROW,
        NEXT_FILE_ITEM_ROW,
    ])
    .expect("public item/type rows should accept flat file/token ordering");

    let out_of_order_cases = [
        [TYPE_ROW, FIRST_ITEM_ROW, NEXT_FILE_ITEM_ROW, EMPTY_ROW],
        [NEXT_FILE_ITEM_ROW, FIRST_ITEM_ROW, TYPE_ROW, PLAIN_EXPR_ROW],
        [FIRST_ITEM_ROW, NEXT_FILE_ITEM_ROW, TYPE_ROW, EMPTY_ROW],
        [
            TYPE_ROW_WITH_SHARED_START_AND_LONGER_END,
            TYPE_ROW,
            NEXT_FILE_ITEM_ROW,
            EMPTY_ROW,
        ],
    ];

    for rows in out_of_order_cases {
        assert!(
            validate_rows(&rows).is_err(),
            "public item/type rows must reject non-monotonic file/token ordering"
        );
    }
}

fn validate_item_path_rows(module_owner_kind: u32) -> anyhow::Result<()> {
    validate_hir_item_path_records(
        &[
            module_owner_kind,
            HIR_NODE_PATH_EXPR,
            HIR_NODE_IMPORT_ITEM,
            HIR_NODE_PATH_EXPR,
        ],
        &[0, 1, 4, 5],
        &[3, 3, 7, 7],
        &[0, 0, 0, 0],
        &[
            HIR_ITEM_KIND_MODULE,
            HIR_ITEM_KIND_NONE,
            HIR_ITEM_KIND_IMPORT,
            HIR_ITEM_KIND_NONE,
        ],
        &[0, INVALID, 0, INVALID],
        &[1, INVALID, 5, INVALID],
        &[3, INVALID, 7, INVALID],
        &[1, INVALID, 3, INVALID],
        &[
            HIR_ITEM_IMPORT_TARGET_NONE,
            HIR_ITEM_IMPORT_TARGET_NONE,
            HIR_ITEM_IMPORT_TARGET_PATH,
            HIR_ITEM_IMPORT_TARGET_NONE,
        ],
    )
}

fn validate_path_type_leaf_rows(path_leaf_start: u32, path_leaf_end: u32) -> anyhow::Result<()> {
    validate_hir_type_records(
        &[HIR_NODE_TYPE, HIR_NODE_PATH_EXPR, HIR_NODE_NONE],
        &[0, 0, path_leaf_start],
        &[4, 4, path_leaf_end],
        &[0; 3],
        &[HIR_TYPE_FORM_PATH, HIR_TYPE_FORM_NONE, HIR_TYPE_FORM_NONE],
        &[1, INVALID, INVALID],
        &[INVALID; 3],
        &[INVALID; 3],
        &[0, INVALID, INVALID],
        &[2, 2, INVALID],
    )
}

#[test]
fn parser_hir_path_type_leaf_rows_must_be_terminal_path_segments() {
    validate_path_type_leaf_rows(2, 4)
        .expect("path type rows should accept a parser-owned terminal path leaf");

    let err = validate_path_type_leaf_rows(1, 3)
        .expect_err("non-terminal path leaves should fail closed before type resolution");
    assert!(
        err.to_string().contains("terminal segment"),
        "error should describe the parser-owned path leaf terminal-segment invariant"
    );
}

#[test]
fn parser_hir_item_path_rows_require_module_or_import_owner_kind() {
    validate_item_path_rows(HIR_NODE_MODULE_ITEM)
        .expect("module/import path rows should decode on matching HIR owner kinds");

    let err = validate_item_path_rows(HIR_NODE_FN)
        .expect_err("module item path metadata on a non-module HIR row should fail closed");
    assert!(
        err.to_string().contains("expected path owner kind"),
        "error should describe the parser-owned item path owner-kind invariant"
    );
}

fn validate_struct_field_rows(second_field_start: u32) -> anyhow::Result<()> {
    validate_hir_struct_declaration_field_records(
        &[
            HIR_NODE_STRUCT_ITEM,
            HIR_NODE_NONE,
            HIR_NODE_TYPE,
            HIR_NODE_NONE,
            HIR_NODE_TYPE,
        ],
        &[0, 2, 4, second_field_start, 7],
        &[10, 6, 5, 9, 8],
        &[0; 5],
        &[
            HIR_TYPE_FORM_NONE,
            HIR_TYPE_FORM_NONE,
            HIR_TYPE_FORM_PATH,
            HIR_TYPE_FORM_NONE,
            HIR_TYPE_FORM_PATH,
        ],
        &[INVALID, INVALID, 0, INVALID, 0],
        &[
            HIR_ITEM_KIND_STRUCT,
            HIR_ITEM_KIND_NONE,
            HIR_ITEM_KIND_NONE,
            HIR_ITEM_KIND_NONE,
            HIR_ITEM_KIND_NONE,
        ],
        &[0, INVALID, INVALID, INVALID, INVALID],
        &[INVALID, 0, INVALID, 0, INVALID],
        &[INVALID, 0, INVALID, 1, INVALID],
        &[INVALID, 2, INVALID, 4, INVALID],
        &[1, INVALID, INVALID, INVALID, INVALID],
        &[2, 0, 0, 0, 0],
    )
}

#[test]
fn parser_hir_struct_declaration_fields_reject_overlapping_sibling_spans() {
    validate_struct_field_rows(6)
        .expect("adjacent source-ordered struct declaration fields should decode");

    let err = validate_struct_field_rows(5)
        .expect_err("overlapping struct declaration field spans should fail closed");
    assert!(
        err.to_string().contains("fields overlap"),
        "error should describe the parser-owned struct field sibling span invariant"
    );
}

fn validate_struct_literal_field_rows(second_field_start: u32) -> anyhow::Result<()> {
    validate_hir_struct_literal_field_records(
        &[
            HIR_NODE_STRUCT_LITERAL_EXPR,
            HIR_NODE_PATH_EXPR,
            HIR_NODE_NONE,
            HIR_NODE_EXPR,
            HIR_NODE_NONE,
            HIR_NODE_EXPR,
        ],
        &[0, 0, 2, 4, second_field_start, 7],
        &[10, 1, 5, 5, 8, 8],
        &[0; 6],
        &[1, INVALID, INVALID, INVALID, INVALID, INVALID],
        &[2, INVALID, INVALID, INVALID, INVALID, INVALID],
        &[2, 0, 0, 0, 0, 0],
        &[INVALID, INVALID, 0, INVALID, 0, INVALID],
        &[INVALID, INVALID, 3, INVALID, 5, INVALID],
        &[INVALID, INVALID, 4, INVALID, INVALID, INVALID],
    )
}

#[test]
fn parser_hir_struct_literal_fields_reject_overlapping_chain_spans() {
    validate_struct_literal_field_rows(5)
        .expect("adjacent source-ordered struct literal fields should decode");

    let err = validate_struct_literal_field_rows(4)
        .expect_err("overlapping struct literal field spans should fail closed");
    assert!(
        err.to_string().contains("field chain rows overlap"),
        "error should describe the parser-owned struct literal field chain span invariant"
    );
}

fn validate_member_rows(owner_start: u32) -> anyhow::Result<()> {
    validate_hir_member_records(
        &[HIR_NODE_MEMBER_EXPR, HIR_NODE_NAME_EXPR],
        &[owner_start, 10],
        &[13, 11],
        &[0, 0],
        &[1, INVALID],
        &[10, INVALID],
        &[12, INVALID],
    )
}

fn validate_member_rows_with_receiver_end(receiver_end: u32) -> anyhow::Result<()> {
    validate_hir_member_records(
        &[HIR_NODE_MEMBER_EXPR, HIR_NODE_NAME_EXPR],
        &[10, 10],
        &[13, receiver_end],
        &[0, 0],
        &[1, INVALID],
        &[10, INVALID],
        &[12, INVALID],
    )
}

#[test]
fn parser_hir_member_rows_start_at_receiver_span() {
    validate_member_rows(10)
        .expect("member expression spans should decode when they start at receiver span");

    let err =
        validate_member_rows(9).expect_err("too-wide member expression spans should fail closed");
    assert!(
        err.to_string().contains("does not start at receiver row"),
        "error should describe the parser-owned member receiver/span-start invariant"
    );
}

#[test]
fn parser_hir_member_rows_require_separator_between_receiver_and_name() {
    validate_member_rows_with_receiver_end(11)
        .expect("member expression spans should decode when a separator follows the receiver");

    let err = validate_member_rows_with_receiver_end(12)
        .expect_err("member expression spans without a separator should fail closed");
    assert!(
        err.to_string()
            .contains("does not leave a member separator"),
        "error should describe the parser-owned member separator span invariant"
    );
}

fn validate_array_literal_rows(first_element_start: u32) -> anyhow::Result<()> {
    validate_hir_array_literal_records(
        &[HIR_NODE_ARRAY_EXPR, HIR_NODE_EXPR, HIR_NODE_EXPR],
        &[10, first_element_start, 14],
        &[20, 12, 16],
        &[0, 0, 0],
        &[1, INVALID, INVALID],
        &[2, 0, 0],
        &[INVALID, 0, 0],
        &[INVALID, 0, 1],
        &[INVALID, 2, INVALID],
    )
}

#[test]
fn parser_hir_array_literal_first_element_follows_owner_start() {
    validate_array_literal_rows(11)
        .expect("array literal element rows should decode after the opening delimiter");

    let err = validate_array_literal_rows(10).expect_err(
        "array literal element spans that include the opening delimiter should fail closed",
    );
    assert!(
        err.to_string()
            .contains("does not follow the array literal start token"),
        "error should describe the parser-owned array literal first-element span invariant"
    );
}

fn validate_enum_variant_rows(second_variant_ordinal: u32) -> anyhow::Result<()> {
    validate_hir_enum_variant_records(
        &[HIR_NODE_ENUM_ITEM, HIR_NODE_ITEM, HIR_NODE_ITEM],
        &[0, 2, 4],
        &[8, 3, 5],
        &[0, 0, 0],
        &[HIR_TYPE_FORM_NONE; 3],
        &[INVALID; 3],
        &[
            HIR_ITEM_KIND_ENUM,
            HIR_ITEM_KIND_ENUM_VARIANT,
            HIR_ITEM_KIND_ENUM_VARIANT,
        ],
        &[0, 0, 0],
        &[INVALID, 0, 0],
        &[INVALID, 0, second_variant_ordinal],
        &[INVALID; 3],
        &[0; 3],
        &[INVALID; 12],
    )
}

#[test]
fn parser_hir_enum_variant_ordinals_are_contiguous_per_enum_owner() {
    validate_enum_variant_rows(1)
        .expect("enum variant rows with contiguous owner ordinals should decode");

    validate_enum_variant_rows(2)
        .expect_err("enum variant ordinal gaps under one owner should fail closed");
}

fn validate_enum_variant_payload_rows(second_payload_start: u32) -> anyhow::Result<()> {
    validate_hir_enum_variant_records(
        &[
            HIR_NODE_ENUM_ITEM,
            HIR_NODE_ITEM,
            HIR_NODE_TYPE,
            HIR_NODE_TYPE,
        ],
        &[0, 2, 4, second_payload_start],
        &[12, 10, 7, 9],
        &[0; 4],
        &[
            HIR_TYPE_FORM_NONE,
            HIR_TYPE_FORM_NONE,
            HIR_TYPE_FORM_PATH,
            HIR_TYPE_FORM_PATH,
        ],
        &[INVALID, INVALID, 0, 0],
        &[
            HIR_ITEM_KIND_ENUM,
            HIR_ITEM_KIND_ENUM_VARIANT,
            HIR_ITEM_KIND_NONE,
            HIR_ITEM_KIND_NONE,
        ],
        &[0, 0, INVALID, INVALID],
        &[INVALID, 0, INVALID, INVALID],
        &[INVALID, 0, INVALID, INVALID],
        &[INVALID, 2, INVALID, INVALID],
        &[0, 2, 0, 0],
        &[
            INVALID, INVALID, INVALID, INVALID, 2, 3, INVALID, INVALID, INVALID, INVALID, INVALID,
            INVALID, INVALID, INVALID, INVALID, INVALID,
        ],
    )
}

#[test]
fn parser_hir_enum_variant_payload_slots_reject_overlapping_spans() {
    validate_enum_variant_payload_rows(7)
        .expect("adjacent source-ordered enum variant payload rows should decode");

    assert!(
        validate_enum_variant_payload_rows(6).is_err(),
        "overlapping enum variant payload rows must fail closed before type checking"
    );
}

fn validate_parameter_rows(second_param_start: u32) -> anyhow::Result<()> {
    validate_hir_parameter_records(
        &[
            HIR_NODE_FN,
            HIR_NODE_PARAM,
            HIR_NODE_TYPE,
            HIR_NODE_PARAM,
            HIR_NODE_TYPE,
        ],
        &[0, 2, 4, second_param_start, 7],
        &[10, 6, 5, 9, 8],
        &[0; 5],
        &[
            HIR_TYPE_FORM_NONE,
            HIR_TYPE_FORM_NONE,
            HIR_TYPE_FORM_PATH,
            HIR_TYPE_FORM_NONE,
            HIR_TYPE_FORM_PATH,
        ],
        &[INVALID, INVALID, 0, INVALID, 0],
        &[INVALID, 0, INVALID, 0, INVALID],
        &[INVALID, 0, INVALID, 1, INVALID],
        &[INVALID, 2, INVALID, second_param_start, INVALID],
        &[INVALID, 1, INVALID, 3, INVALID],
        &[INVALID, 2, INVALID, 4, INVALID],
    )
}

#[test]
fn parser_hir_parameter_ordinals_reject_overlapping_sibling_spans() {
    validate_parameter_rows(6).expect("adjacent source-ordered parameter rows should decode");

    let err = validate_parameter_rows(5)
        .expect_err("overlapping parameter spans should fail closed before type checking");
    assert!(
        err.to_string().contains("parameter rows overlap"),
        "error should describe the parser-owned parameter owner/ordinal span invariant"
    );
}

fn validate_match_arm_rank_rows(
    second_arm_match_rank: u32,
    second_arm_ordinal: u32,
) -> anyhow::Result<()> {
    validate_hir_match_records(
        &[
            HIR_NODE_MATCH_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_NONE,
            HIR_NODE_NAME_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_NONE,
            HIR_NODE_NAME_EXPR,
            HIR_NODE_EXPR,
        ],
        &[0, 1, 3, 3, 5, 7, 8, 10],
        &[12, 2, 6, 4, 6, 11, 9, 11],
        &[0; 8],
        &[
            1, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID,
        ],
        &[
            2, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID,
        ],
        &[2, 0, 0, 0, 0, 0, 0, 0],
        &[
            INVALID, INVALID, 5, INVALID, INVALID, INVALID, INVALID, INVALID,
        ],
        &[INVALID, INVALID, 3, INVALID, INVALID, 6, INVALID, INVALID],
        &[INVALID; 8],
        &[0; 8],
        &[INVALID, INVALID, 4, INVALID, INVALID, 7, INVALID, INVALID],
        &[INVALID; 8],
        &[
            INVALID,
            INVALID,
            0,
            INVALID,
            INVALID,
            second_arm_match_rank,
            INVALID,
            INVALID,
        ],
        &[
            INVALID,
            INVALID,
            0,
            INVALID,
            INVALID,
            second_arm_ordinal,
            INVALID,
            INVALID,
        ],
    )
}

#[test]
fn parser_hir_match_arm_rank_rows_follow_the_parser_owned_arm_chain() {
    validate_match_arm_rank_rows(0, 1)
        .expect("match arm rank rows should agree with the source-order arm chain");

    let err = validate_match_arm_rank_rows(0, 0)
        .expect_err("stale match arm rank rows should fail closed before type checking");
    assert!(
        err.to_string()
            .contains("arm rank metadata that disagrees with its match arm chain"),
        "error should describe the parser-owned match arm rank contract"
    );
}
