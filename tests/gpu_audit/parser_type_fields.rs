#[test]
fn parser_hir_type_form_metadata_is_tree_driven() {
    let parser_buffers = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/src/parser/buffers.rs"
    ));
    let parser_passes = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/src/parser/passes/mod.rs"
    ));
    let parser_driver = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/src/parser/driver.rs"));
    let parser_readback = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/src/parser/readback.rs"
    ));
    let resident_tree = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/src/parser/driver/resident_tree.rs"
    ));
    let pass = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/src/parser/passes/hir_type_fields.rs"
    ));
    let shader = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/shaders/parser/hir_type_fields.slang"
    ));
    let generated_ids = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/shaders/parser/generated_parse_production_ids.slang"
    ));
    let table_generator = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/src/bin/parse_gen_tables.rs"
    ));
    let parser_tests = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/parser_hir_type_fields.rs"
    ));

    assert!(
        parser_buffers.contains("hir_type_fields_params"),
        "parser buffers should carry HIR type-form pass params"
    );

    for needle in [
        "hir_type_form",
        "hir_type_value_node",
        "hir_type_len_token",
        "hir_type_len_value",
        "hir_type_file_id",
    ] {
        assert!(
            parser_buffers.contains(needle),
            "parser buffers should carry HIR type-form metadata: {needle}"
        );
        assert!(
            parser_readback.contains(needle),
            "parser readback should expose HIR type-form metadata: {needle}"
        );
        assert!(
            parser_driver.contains(needle) && resident_tree.contains(needle),
            "resident parser result/readback should expose HIR type-form metadata: {needle}"
        );
    }

    assert!(
        parser_passes.contains("pub mod hir_type_fields;")
            && parser_passes.contains("hir_type_fields: hir_type_fields::HirTypeFieldsPass")
            && parser_passes.contains("p.hir_type_fields.record_pass"),
        "parser pass list should wire the HIR type-form pass"
    );
    assert!(
        parser_driver.contains("parser.hir_type_fields")
            && parser_driver.contains("self.passes.hir_type_fields.record_pass"),
        "resident LL(1) parser path should run HIR type-form metadata after HIR spans"
    );
    assert!(
        pass.contains("\"hir_type_fields\"")
            && pass.contains("\"node_kind\".into()")
            && pass.contains("\"first_child\".into()")
            && pass.contains("\"next_sibling\".into()")
            && pass.contains("\"hir_kind\".into()")
            && pass.contains("\"hir_token_pos\".into()")
            && pass.contains("\"hir_token_file_id\".into()"),
        "Rust pass wrapper should bind tree/HIR inputs"
    );
    assert!(
        shader.contains("import generated_parse_production_ids;")
            && !shader.contains("static const uint PROD_TYPE_IDENT =")
            && !shader.contains("static const uint PROD_TYPE_ARRAY =")
            && generated_ids.contains("static const uint PROD_TYPE_IDENT =")
            && generated_ids.contains("static const uint PROD_TYPE_ARRAY =")
            && generated_ids.contains("static const uint PROD_TYPE_ARRAY_TAIL =")
            && generated_ids.contains("static const uint PROD_TYPE_SLICE_TAIL =")
            && generated_ids.contains("static const uint PROD_TYPE_REF =")
            && table_generator.contains("write_production_id_slang")
            && table_generator.contains("generated_parse_production_ids.slang"),
        "HIR type metadata should import generated production IDs instead of embedding copied numeric ids"
    );

    for needle in [
        "StructuredBuffer<uint> node_kind",
        "StructuredBuffer<uint> first_child",
        "StructuredBuffer<uint> next_sibling",
        "RWStructuredBuffer<uint> hir_type_form",
        "PROD_TYPE_IDENT",
        "PROD_TYPE_ARRAY",
        "PROD_TYPE_ARRAY_TAIL",
        "PROD_TYPE_SLICE_TAIL",
        "PROD_TYPE_REF",
        "first_child_node",
        "next_sibling_node",
        "publish_array_or_slice_type",
    ] {
        assert!(
            shader.contains(needle),
            "HIR type metadata shader should derive type forms from AST/HIR arrays: {needle}"
        );
    }

    for forbidden in [
        "TokenIn",
        "token_words",
        "source_bytes",
        "token_kind(",
        "same_text(",
        "find_",
        "for (uint j",
        "i - 1u",
        "record_error",
        "RWStructuredBuffer<uint> status",
    ] {
        assert!(
            !shader.contains(forbidden),
            "HIR type metadata must not rediscover type forms from token neighborhoods: {forbidden}"
        );
    }

    assert!(
        parser_tests.contains("gpu_ll1_hir_type_fields_capture_array_slice_and_reference_forms")
            && parser_tests
                .contains("gpu_resident_ll1_hir_type_fields_are_exposed_to_downstream_passes")
            && parser_tests.contains("HIR_TYPE_FORM_ARRAY")
            && parser_tests.contains("HIR_TYPE_FORM_SLICE")
            && parser_tests.contains("HIR_TYPE_FORM_REF"),
        "parser tests should prove resident and non-resident array, slice, and reference type-form metadata"
    );
}
