use super::support::{assert_contains_all, assert_contains_none, type_checker_gpu_sources};

#[test]
fn generic_type_instance_metadata_and_bounded_consumers_are_gpu_resident() {
    let generics_plan = include_str!("../../docs/GENERICS_GPU_PLAN.md");
    let semantics_paper = include_str!("../../docs/ParallelLexingParsingSemanticAnalysis.md");
    let requirements = include_str!("../../stdlib/LANGUAGE_REQUIREMENTS.md");
    let semantics_tests = include_str!("../../tests/type_checker_semantics.rs");
    let module_tests = include_str!("../../tests/type_checker_modules.rs");
    let type_checker = type_checker_gpu_sources();
    let parser_member_shader = include_str!("../../shaders/parser/hir_member_fields.slang");
    let parser_passes = include_str!("../../src/parser/passes/mod.rs");
    let tokens_shader = include_str!("../../shaders/type_checker/type_check_tokens_min.slang");
    let clear_shader =
        include_str!("../../shaders/type_checker/type_check_type_instances_00_clear.slang");
    let decl_generic_params_shader = include_str!(
        "../../shaders/type_checker/type_check_type_instances_00b_decl_generic_params.slang"
    );
    let collect_shader =
        include_str!("../../shaders/type_checker/type_check_type_instances_01_collect.slang");
    let collect_named_shader = include_str!(
        "../../shaders/type_checker/type_check_type_instances_01b_collect_named_instances.slang"
    );
    let collect_aggregate_refs_shader = include_str!(
        "../../shaders/type_checker/type_check_type_instances_01c_collect_aggregate_refs.slang"
    );
    let collect_aggregate_details_shader = include_str!(
        "../../shaders/type_checker/type_check_type_instances_01d_collect_aggregate_details.slang"
    );
    let collect_named_arg_refs_shader = include_str!(
        "../../shaders/type_checker/type_check_type_instances_01e_collect_named_arg_refs.slang"
    );
    let decl_refs_shader =
        include_str!("../../shaders/type_checker/type_check_type_instances_01f_decl_refs.slang");
    let member_receiver_shader = include_str!(
        "../../shaders/type_checker/type_check_type_instances_03a_member_receivers.slang"
    );
    let member_shader = include_str!(
        "../../shaders/type_checker/type_check_type_instances_03_member_results.slang"
    );
    let member_substitute_shader = include_str!(
        "../../shaders/type_checker/type_check_type_instances_03b_member_substitute.slang"
    );
    let init_shader = include_str!(
        "../../shaders/type_checker/type_check_type_instances_04_struct_init_fields.slang"
    );
    let init_clear_shader = include_str!(
        "../../shaders/type_checker/type_check_type_instances_04a_struct_init_clear.slang"
    );
    let init_substitute_shader = include_str!(
        "../../shaders/type_checker/type_check_type_instances_04b_struct_init_substitute.slang"
    );
    let array_return_shader = include_str!(
        "../../shaders/type_checker/type_check_type_instances_05_array_return_refs.slang"
    );
    let array_literal_return_shader = include_str!(
        "../../shaders/type_checker/type_check_type_instances_05b_array_literal_return_refs.slang"
    );
    let enum_ctor_shader =
        include_str!("../../shaders/type_checker/type_check_type_instances_06_enum_ctors.slang");
    let array_index_shader = include_str!(
        "../../shaders/type_checker/type_check_type_instances_07_array_index_results.slang"
    );
    let aggregate_validate_shader = include_str!(
        "../../shaders/type_checker/type_check_type_instances_08_validate_aggregate_access.slang"
    );
    let match_payload_shader = include_str!(
        "../../shaders/type_checker/type_check_modules_10m2_type_match_payloads.slang"
    );
    let project_type_instances_shader = include_str!(
        "../../shaders/type_checker/type_check_modules_10k_project_type_instances.slang"
    );
    let match_expr_shader =
        include_str!("../../shaders/type_checker/type_check_modules_10n_type_match_exprs.slang");
    let value_call_shader =
        include_str!("../../shaders/type_checker/type_check_modules_10h_consume_value_calls.slang");
    let visible_shader =
        include_str!("../../shaders/type_checker/type_check_visible_02_scatter.slang");

    assert!(
        generics_plan.contains("## Next Slice: GPU Type-Instance Metadata"),
        "GENERICS_GPU_PLAN should name the next generics slice"
    );
    assert!(
        generics_plan.contains("enables narrow consumers")
            && generics_plan.contains("GENERIC_ENUM_CTOR_OK"),
        "GENERICS_GPU_PLAN should distinguish metadata from bounded consumers"
    );
    assert!(
        generics_plan.contains("must not rediscover generic")
            && generics_plan.contains("arguments by walking item headers"),
        "generic substitution must not move into token-local scans"
    );
    assert!(
        semantics_paper.contains("data type resolution tree")
            && semantics_paper.contains("evaluating")
            && semantics_paper.contains("the node-local rules"),
        "paper text should describe type resolution forests and local validation"
    );
    assert!(
        requirements.contains("type_check_type_instances_07_array_index_results.slang")
            && requirements.contains("Generic array/slice calls")
            && requirements.contains("remain rejected"),
        "LANGUAGE_REQUIREMENTS should describe bounded generic array acceptance without claiming calls/codegen"
    );
    assert!(
        requirements.contains("bounded GPU-only consumer")
            && requirements.contains("concrete identifier returns"),
        "LANGUAGE_REQUIREMENTS should describe the bounded array-return consumer"
    );
    assert!(
        requirements.contains("Bounded generic enum constructor")
            && requirements.contains("Maybe<i32> = Some(1)"),
        "LANGUAGE_REQUIREMENTS should describe the bounded generic enum constructor consumer"
    );
    assert!(
        requirements.contains("Bounded stdlib-shaped matches")
            || requirements.contains("bounded stdlib-shaped matches"),
        "LANGUAGE_REQUIREMENTS should describe the bounded GPU match consumer"
    );
    assert!(
        requirements.contains("core::option")
            && requirements.contains("core::result")
            && requirements.contains("explicitly supplied source-pack seeds"),
        "LANGUAGE_REQUIREMENTS should document the Option/Result source-pack seed checkpoint"
    );
    assert!(
        semantics_tests.contains("type_checker_accepts_concrete_identifier_array_returns_on_gpu")
            && semantics_tests
                .contains("type_checker_accepts_concrete_i32_array_literal_returns_on_gpu")
            && semantics_tests
                .contains("type_checker_rejects_array_returns_outside_bounded_gpu_slice")
            && semantics_tests
                .contains("type_checker_accepts_contextual_generic_enum_constructors_on_gpu")
            && semantics_tests
                .contains("type_checker_accepts_symbolic_generic_enum_constructor_returns_on_gpu")
            && semantics_tests
                .contains("type_checker_rejects_invalid_generic_enum_constructor_payloads_on_gpu")
            && semantics_tests
                .contains("type_checker_accepts_generic_array_and_slice_elements_on_gpu")
            && semantics_tests
                .contains("type_checker_rejects_invalid_generic_array_element_returns_on_gpu")
            && semantics_tests.contains("type_checker_accepts_bounded_match_result_types_on_gpu")
            && semantics_tests.contains("type_checker_accepts_generic_enum_match_payloads_on_gpu"),
        "semantic tests should cover accepted and still-rejected bounded consumer slices"
    );
    assert!(
        module_tests.contains("type_checker_accepts_core_option_and_result_source_pack_seeds")
            && module_tests
                .contains("type_checker_accepts_qualified_generic_option_and_result_calls")
            && module_tests.contains("type_checker_accepts_array_i32_4_seed_files"),
        "module type-check tests should cover Option/Result source-pack seeds, array_i32_4 seeds, and bounded qualified helpers"
    );

    for needle in [
        "type_check_type_instances_01_collect",
        "type_check_type_instances_01b_collect_named_instances",
        "type_check_type_instances_01c_collect_aggregate_refs",
        "type_check_type_instances_01d_collect_aggregate_details",
        "type_check_type_instances_01e_collect_named_arg_refs",
        "type_check_type_instances_01f_decl_refs",
        "type_check_type_instances_00_clear",
        "type_check_type_instances_00b_decl_generic_params",
        "type_check.resident.type_instances_clear.pass",
        "type_check.type_instances_clear.pass",
        "type_check.resident.type_instances_decl_generic_params.pass",
        "type_check.type_instances_decl_generic_params.pass",
        "type_check.resident.type_instances_collect.pass",
        "type_check.type_instances_collect.pass",
        "type_check.resident.type_instances_collect_named.pass",
        "type_check.type_instances_collect_named.pass",
        "type_check.resident.type_instances_collect_aggregate_refs.pass",
        "type_check.type_instances_collect_aggregate_refs.pass",
        "type_check.resident.type_instances_collect_aggregate_details.pass",
        "type_check.type_instances_collect_aggregate_details.pass",
        "type_check.resident.type_instances_collect_named_arg_refs.pass",
        "type_check.type_instances_collect_named_arg_refs.pass",
        "type_check.resident.type_instances_decl_refs.pass",
        "type_check.type_instances_decl_refs.pass",
        "type_expr_ref_tag",
        "decl_type_ref_tag",
        "type_instance_kind",
        "type_decl_generic_param_count",
        "type_instance_decl_token",
        "type_instance_arg_count",
        "type_instance_arg_ref_tag",
        "type_instance_elem_ref_tag",
        "type_instance_len_kind",
        "fn_return_ref_tag",
        "member_result_context_instance",
        "hir_member_receiver_node",
        "hir_member_receiver_token",
        "hir_member_name_token",
        "member_result_ref_tag",
        "struct_init_field_expected_ref_tag",
        "type_check_type_instances_03a_member_receivers",
        "type_check_type_instances_03_member_results",
        "type_check_type_instances_03b_member_substitute",
        "type_check.resident.methods.decls.attach_metadata",
        "type_check.methods.decls.attach_metadata",
        "type_check.resident.type_instances_member_receivers.pass",
        "type_check.resident.type_instances_member_substitute.pass",
        "type_check.type_instances_member_receivers.pass",
        "type_check.type_instances_member_substitute.pass",
        "type_check_type_instances_04a_struct_init_clear",
        "type_check_type_instances_04_struct_init_fields",
        "type_check_type_instances_04b_struct_init_substitute",
        "type_check.resident.type_instances_struct_init_clear.pass",
        "type_check.resident.type_instances_struct_init_fields.pass",
        "type_check.resident.type_instances_struct_init_substitute.pass",
        "type_check.type_instances_struct_init_clear.pass",
        "type_check.type_instances_struct_init_fields.pass",
        "type_check.type_instances_struct_init_substitute.pass",
        "type_check_type_instances_05_array_return_refs",
        "type_check.resident.type_instances_array_return_refs.pass",
        "type_check.type_instances_array_return_refs.pass",
        "type_check_type_instances_05b_array_literal_return_refs",
        "type_check.resident.type_instances_array_literal_return_refs.pass",
        "type_check.type_instances_array_literal_return_refs.pass",
        "type_check_type_instances_06_enum_ctors",
        "type_check.resident.type_instances_enum_ctors.pass",
        "type_check.type_instances_enum_ctors.pass",
        "type_check_type_instances_07_array_index_results",
        "type_check.resident.type_instances_array_index_results.pass",
        "type_check.type_instances_array_index_results.pass",
        "type_check_type_instances_08_validate_aggregate_access",
        "type_check.resident.type_instances_validate_aggregate_access.pass",
        "type_check.type_instances_validate_aggregate_access.pass",
        "type_check_modules_10m_bind_match_patterns",
        "type_check_modules_10m2_type_match_payloads",
        "type_check_modules_10n_type_match_exprs",
        "type_check.modules.bind_match_patterns",
        "type_check.modules.type_match_payloads",
        "type_check.modules.type_match_exprs",
    ] {
        assert!(
            type_checker.contains(needle),
            "GPU type checker should wire type-instance metadata artifact: {needle}"
        );
    }
    for needle in [
        "RWStructuredBuffer<uint> type_expr_ref_tag",
        "StructuredBuffer<uint> hir_type_form",
        "StructuredBuffer<uint> module_type_path_type",
        "StructuredBuffer<uint> name_id_by_token",
        "StructuredBuffer<uint> language_decl_name_id",
        "LANGUAGE_DECL_KIND_PRIMITIVE_TYPE",
        "language_type_code_for_token",
    ] {
        assert!(
            collect_shader.contains(needle),
            "type-instance scalar/path shader should build metadata artifact: {needle}"
        );
    }
    for needle in [
        "TYPE_REF_INSTANCE",
        "type_instance_arg_count",
        "StructuredBuffer<uint> hir_type_value_node",
        "StructuredBuffer<uint> hir_token_end",
        "top_level_type_arg_count",
        "nearest_type_ancestor",
        "path_leaf_token_for_type_node",
    ] {
        assert!(
            collect_named_shader.contains(needle),
            "named instance shader should build metadata artifact: {needle}"
        );
    }
    for needle in [
        "TYPE_INSTANCE_ARRAY",
        "TYPE_INSTANCE_SLICE",
        "RWStructuredBuffer<uint> type_instance_kind",
        "RWStructuredBuffer<uint> type_instance_head_token",
    ] {
        assert!(
            collect_aggregate_refs_shader.contains(needle),
            "aggregate instance shader should build metadata artifact: {needle}"
        );
    }
    for needle in [
        "RWStructuredBuffer<uint> type_instance_elem_ref_tag",
        "RWStructuredBuffer<uint> type_instance_len_kind",
        "HIR_TYPE_FORM_REF",
        "child_ref",
    ] {
        assert!(
            collect_aggregate_details_shader.contains(needle),
            "aggregate detail shader should build metadata artifact: {needle}"
        );
    }
    for needle in [
        "RWStructuredBuffer<uint> type_instance_arg_ref_tag",
        "StructuredBuffer<uint> type_expr_ref_tag",
        "top_level_type_arg",
        "nearest_type_ancestor",
        "TYPE_INSTANCE_ARG_REF_STRIDE",
    ] {
        assert!(
            collect_named_arg_refs_shader.contains(needle),
            "named generic argument shader should build metadata artifact: {needle}"
        );
    }
    for needle in [
        "RWStructuredBuffer<uint> type_expr_ref_tag",
        "RWStructuredBuffer<uint> type_instance_kind",
        "RWStructuredBuffer<uint> type_decl_generic_param_count",
        "RWStructuredBuffer<uint> fn_return_ref_tag",
        "RWStructuredBuffer<uint> decl_type_ref_tag",
        "TYPE_INSTANCE_EMPTY",
    ] {
        assert!(
            clear_shader.contains(needle),
            "type-instance clear shader should initialize metadata artifact: {needle}"
        );
    }
    for needle in [
        "RWStructuredBuffer<uint> type_decl_generic_param_count",
        "StructuredBuffer<uint> hir_item_kind",
        "StructuredBuffer<uint> hir_item_name_token",
        "StructuredBuffer<uint> node_kind",
        "PROD_ENUM_TYPE_PARAM",
        "generic_decl_ancestor",
    ] {
        assert!(
            decl_generic_params_shader.contains(needle),
            "declaration generic arity shader should derive metadata from HIR records: {needle}"
        );
    }
    for needle in [
        "StructuredBuffer<uint> type_decl_generic_param_count",
        "StructuredBuffer<uint> resolved_type_decl",
        "StructuredBuffer<uint> decl_name_token",
        "type_decl_generic_param_count[decl_token]",
        "type_instance_decl_token[leaf_token]",
    ] {
        assert!(
            project_type_instances_shader.contains(needle),
            "module type-instance projection should consume resolver and generic-arity records: {needle}"
        );
    }
    for (label, shader) in [
        ("decl generic params", decl_generic_params_shader),
        ("scalar/path", collect_shader),
        ("named", collect_named_shader),
        ("aggregate refs", collect_aggregate_refs_shader),
        ("aggregate details", collect_aggregate_details_shader),
        ("named arg refs", collect_named_arg_refs_shader),
        (
            "module type-instance projection",
            project_type_instances_shader,
        ),
    ] {
        for forbidden in [
            "TokenIn",
            "ByteAddressBuffer",
            "source_bytes",
            "token_words",
            "token_kind",
            "generic_param_list",
            "find_matching_gt",
            "top_level_type_arg_head",
            "same_text",
            "primitive_type_code",
            "parse_uint_token",
            "TK_",
        ] {
            assert!(
                !shader.contains(forbidden),
                "type-instance {label} collection should consume HIR/resolver records, not token/source syntax: {forbidden}"
            );
        }
    }
    for needle in [
        "RWStructuredBuffer<uint> decl_type_ref_tag",
        "StructuredBuffer<uint> hir_stmt_record",
        "StructuredBuffer<uint4> hir_param_record",
        "PROD_LET_TYPE",
        "publish_decl_ref",
    ] {
        assert!(
            decl_refs_shader.contains(needle),
            "declaration type-ref shader should publish HIR-derived declaration refs: {needle}"
        );
    }
    for forbidden in [
        "TokenIn",
        "ByteAddressBuffer",
        "source_bytes",
        "token_words",
        "token_kind",
        "same_text",
        "decl_i + 2u",
    ] {
        assert!(
            !decl_refs_shader.contains(forbidden),
            "declaration type-ref shader must consume HIR/type records, not token/source layout: {forbidden}"
        );
    }
    assert!(
        !type_checker.contains("type_check_type_instances_02_struct_fields")
            && !type_checker.contains("type_instances_struct_fields"),
        "same-source token fallback for generic instance binding should stay deleted; module resolver projection owns declaration binding"
    );
    assert!(
        parser_passes.contains("pub mod hir_member_fields;")
            && parser_passes.contains("hir_member_fields.record_pass")
            && parser_member_shader.contains("RWStructuredBuffer<uint> hir_member_receiver_token")
            && parser_member_shader.contains("RWStructuredBuffer<uint> hir_member_name_token")
            && parser_member_shader.contains("PROD_POSTFIX_MEMBER")
            && parser_member_shader.contains("PROD_SELF_VALUE")
            && parser_member_shader.contains("hir_token_end")
            && !parser_member_shader.contains("source_bytes")
            && !parser_member_shader.contains("token_words")
            && !parser_member_shader.contains("token_kind"),
        "parser should publish HIR member receiver/name records from the inverted tree and grammar spans"
    );
    assert!(
        member_receiver_shader.contains("HIR_MEMBER_EXPR")
            && member_receiver_shader.contains("receiver_token_for_member")
            && member_receiver_shader.contains("StructuredBuffer<uint> hir_member_receiver_token")
            && member_receiver_shader.contains("StructuredBuffer<uint> hir_member_name_token")
            && member_receiver_shader.contains("StructuredBuffer<uint> decl_type_ref_tag")
            && member_receiver_shader
                .contains("StructuredBuffer<uint> method_decl_receiver_ref_tag")
            && member_receiver_shader
                .contains("RWStructuredBuffer<uint> member_result_context_instance")
            && member_shader.contains("StructuredBuffer<uint> hir_member_name_token")
            && member_shader.contains("StructuredBuffer<uint> hir_struct_field_parent_struct")
            && member_shader.contains("StructuredBuffer<uint> hir_struct_field_type_node")
            && member_shader.contains("StructuredBuffer<uint> name_id_by_token")
            && member_shader.contains("generic_param_slot_for_name")
            && member_shader.contains("receiver_decl_token")
            && member_substitute_shader
                .contains("StructuredBuffer<uint> type_instance_arg_ref_tag")
            && member_substitute_shader.contains("RWStructuredBuffer<uint> visible_type"),
        "member-result passes should project HIR member refs from declaration refs, struct metadata, interned names, and type-instance arguments"
    );
    for (label, shader) in [
        ("member receivers", member_receiver_shader),
        ("member fields", member_shader),
        ("member substitution", member_substitute_shader),
    ] {
        for forbidden in [
            "TokenIn",
            "ByteAddressBuffer",
            "source_bytes",
            "token_words",
            "token_kind",
            "same_text",
            "generic_param_list",
            "struct_decl_open",
            "decl_i + 2u",
            "visible_decl[base_i]",
        ] {
            assert!(
                !shader.contains(forbidden),
                "type-instance {label} pass should consume HIR/semantic records, not token/source layout: {forbidden}"
            );
        }
    }
    assert!(
        init_shader.contains("RWStructuredBuffer<uint> struct_init_field_expected_ref_tag")
            && init_shader.contains("StructuredBuffer<uint> hir_struct_lit_field_parent_lit")
            && init_shader.contains("StructuredBuffer<uint> hir_struct_lit_head_node")
            && init_shader.contains("StructuredBuffer<uint> hir_struct_field_parent_struct")
            && init_shader.contains("StructuredBuffer<uint> hir_struct_field_type_node")
            && init_shader.contains("StructuredBuffer<uint> hir_item_name_token")
            && init_shader.contains("StructuredBuffer<uint> name_id_by_token")
            && init_shader.contains("StructuredBuffer<uint> type_expr_ref_tag")
            && init_shader.contains("RWStructuredBuffer<uint> struct_init_field_context_instance")
            && init_shader.contains("context_instance_for_struct_literal_node")
            && init_shader.contains("generic_param_slot_for_name")
            && init_substitute_shader.contains("StructuredBuffer<uint> type_instance_arg_start")
            && init_substitute_shader.contains("StructuredBuffer<uint> type_instance_arg_ref_tag")
            && init_substitute_shader.contains("RWStructuredBuffer<uint> visible_type")
            && init_clear_shader.contains("struct_init_field_context_instance[i] = INVALID"),
        "struct-init passes should publish and substitute expected field refs from HIR struct metadata and contextual instances"
    );
    assert!(
        !init_shader.contains("source_bytes")
            && !init_shader.contains("token_words")
            && !init_shader.contains("token_kind")
            && !init_shader.contains("same_text")
            && !init_shader.contains("generic_param_list_open")
            && !init_shader.contains("struct_literal_open_for_field")
            && !init_substitute_shader.contains("source_bytes")
            && !init_substitute_shader.contains("token_words")
            && !init_substitute_shader.contains("token_kind"),
        "struct-init pass must not rediscover declaration or literal structure from token layout"
    );
    assert!(
        aggregate_validate_shader.contains("StructuredBuffer<uint> hir_member_name_token")
            && aggregate_validate_shader.contains("StructuredBuffer<uint> parent")
            && aggregate_validate_shader.contains("StructuredBuffer<uint> first_child")
            && aggregate_validate_shader.contains("StructuredBuffer<uint> next_sibling")
            && aggregate_validate_shader
                .contains("StructuredBuffer<uint> hir_struct_lit_head_node")
            && aggregate_validate_shader
                .contains("StructuredBuffer<uint> hir_struct_lit_field_parent_lit")
            && aggregate_validate_shader
                .contains("StructuredBuffer<uint> hir_struct_field_parent_struct")
            && aggregate_validate_shader.contains("StructuredBuffer<uint> name_id_by_token")
            && aggregate_validate_shader.contains("member_result_field_ordinal")
            && aggregate_validate_shader.contains("PROD_STRUCT_LIT_FIELD")
            && aggregate_validate_shader.contains("HIR_CALL_EXPR")
            && aggregate_validate_shader.contains("HIR_MEMBER_EXPR")
            && aggregate_validate_shader.contains("member_expr_is_call")
            && aggregate_validate_shader.contains("record_error"),
        "aggregate validator should consume HIR member/call/struct records and field-result records"
    );
    assert!(
        !aggregate_validate_shader.contains("token_words")
            && !aggregate_validate_shader.contains("token_kind")
            && !aggregate_validate_shader.contains("source_bytes")
            && !aggregate_validate_shader.contains("TK_DOT")
            && !aggregate_validate_shader.contains("TK_LBRACE")
            && !aggregate_validate_shader.contains("method_call_name_id"),
        "aggregate validator must not inspect token spelling, token-neighborhood punctuation, or method name-key tables as call classifiers"
    );
    assert!(
        !collect_shader.contains("RWStructuredBuffer<uint> status")
            && !collect_named_shader.contains("RWStructuredBuffer<uint> status")
            && !collect_aggregate_refs_shader.contains("RWStructuredBuffer<uint> status")
            && !collect_aggregate_details_shader.contains("RWStructuredBuffer<uint> status")
            && !collect_named_arg_refs_shader.contains("RWStructuredBuffer<uint> status")
            && !collect_shader.contains("record_error")
            && !collect_named_shader.contains("record_error")
            && !collect_aggregate_refs_shader.contains("record_error")
            && !collect_aggregate_details_shader.contains("record_error")
            && !collect_named_arg_refs_shader.contains("record_error"),
        "metadata-only slice must not accept or reject programs by itself"
    );
    assert!(
        array_return_shader.contains("ARRAY_RETURN_OK")
            && array_return_shader.contains("hir_stmt_record")
            && array_return_shader.contains("visible_decl")
            && array_return_shader.contains("decl_type_ref_tag")
            && array_return_shader.contains("fn_return_ref_tag")
            && array_return_shader.contains("same_bounded_array_instance")
            && !array_return_shader.contains("token_words")
            && !array_return_shader.contains("token_kind")
            && !array_return_shader.contains("source_bytes")
            && !array_return_shader.contains("record_error"),
        "identifier array-return consumer should compare HIR return records and type-instance refs without issuing errors"
    );
    assert!(
        array_literal_return_shader.contains("ARRAY_RETURN_OK")
            && array_literal_return_shader.contains("top_level_array_element_expr")
            && array_literal_return_shader.contains("array_literal_matches_return_instance")
            && array_literal_return_shader.contains("visible_type")
            && array_literal_return_shader.contains("call_return_type[index_token]")
            && !array_literal_return_shader.contains("token_words")
            && !array_literal_return_shader.contains("token_kind")
            && !array_literal_return_shader.contains("source_bytes")
            && !array_literal_return_shader.contains("record_error"),
        "array-literal return consumer should use HIR element expressions, visible scalar types, and precomputed index result records"
    );
    assert!(
        tokens_shader.contains("ARRAY_RETURN_OK")
            && tokens_shader.contains("call_return_type[return_i] != ARRAY_RETURN_OK"),
        "token checker should only consume the precomputed array-return sentinel"
    );
    assert!(
        enum_ctor_shader.contains("GENERIC_ENUM_CTOR_OK")
            && enum_ctor_shader.contains("instance_from_annotated_let")
            && enum_ctor_shader.contains("substituted_ref")
            && enum_ctor_shader.contains("StructuredBuffer<uint> name_id_by_token")
            && enum_ctor_shader.contains("same_name_id")
            && enum_ctor_shader.contains("type_instance_arg_ref_tag")
            && enum_ctor_shader.contains("fn_return_ref_tag")
            && enum_ctor_shader.contains("call_return_type[return_i] = GENERIC_ENUM_CTOR_OK")
            && enum_ctor_shader.contains("kind == TK_LET_ASSIGN || kind == TK_ASSIGN")
            && !enum_ctor_shader.contains("ByteAddressBuffer")
            && !enum_ctor_shader.contains("source_bytes")
            && !enum_ctor_shader.contains("same_text")
            && !enum_ctor_shader.contains("record_error"),
        "generic enum constructor consumer should validate contextual refs and publish a sentinel without issuing errors"
    );
    assert!(
        tokens_shader.contains("GENERIC_ENUM_CTOR_OK")
            && tokens_shader.contains("call_return_type[callee_i] == GENERIC_ENUM_CTOR_OK")
            && tokens_shader.contains("call_return_type[return_i] == GENERIC_ENUM_CTOR_OK"),
        "token checker should only consume the precomputed generic enum constructor sentinel"
    );
    assert!(
        array_index_shader.contains("type_instance_elem_ref_tag")
            && array_index_shader.contains("StructuredBuffer<uint> hir_kind")
            && array_index_shader.contains("StructuredBuffer<uint> parent")
            && array_index_shader.contains("StructuredBuffer<uint> next_sibling")
            && array_index_shader.contains("StructuredBuffer<uint> decl_type_ref_tag")
            && array_index_shader.contains("StructuredBuffer<uint> name_id_by_token")
            && array_index_shader.contains("hir_kind[node] != HIR_INDEX_EXPR")
            && array_index_shader.contains("call_return_type[result_token] = elem_ty")
            && !array_index_shader.contains("token_words")
            && !array_index_shader.contains("token_kind")
            && !array_index_shader.contains("generic_param_decl_for_use")
            && !array_index_shader.contains("is_type_name_token")
            && !array_index_shader.contains("ByteAddressBuffer")
            && !array_index_shader.contains("source_bytes")
            && !array_index_shader.contains("same_text")
            && !array_index_shader.contains("record_error"),
        "array-index consumer should publish precomputed element types without issuing errors"
    );
    assert!(
        tokens_shader.contains("call_return_type[cur + 1u]")
            && tokens_shader.contains("indexed_ty != TY_UNKNOWN"),
        "token checker should consume precomputed generic array index result types"
    );
    assert!(
        !tokens_shader.contains("check_member"),
        "member access validation should live in HIR/type-instance aggregate validation, not in the legacy token checker"
    );
    assert!(
        match_payload_shader.contains("HIR_MATCH_EXPR")
            && match_payload_shader.contains("scrutinee_instance_for_match")
            && match_payload_shader.contains("substituted_ref")
            && match_payload_shader.contains("bind_payload_uses")
            && !match_payload_shader.contains("record_error"),
        "match payload consumer should publish enum payload types from HIR/type-instance metadata without issuing errors"
    );
    assert!(
        match_expr_shader.contains("HIR_MATCH_EXPR")
            && match_expr_shader.contains("call_return_type[match_i] = result_ty")
            && match_expr_shader.contains("expr_type")
            && match_expr_shader.contains("same_result_type"),
        "match expression consumer should type HIR match arms and publish the match result type"
    );
    assert!(
        value_call_shader.contains("StructuredBuffer<uint4> call_arg_record")
            && value_call_shader.contains("StructuredBuffer<uint> module_value_path_call_open")
            && value_call_shader.contains("valid_function_decl")
            && value_call_shader.contains("call_fn_index[token_i] != token_i")
            && value_call_shader.contains("uint ret_ty = call_return_type[owner_token]")
            && value_call_shader.contains("uint decl_ret_ty = call_return_type[fn_token]")
            && value_call_shader.contains("!is_generic_type(decl_ret_ty)")
            && value_call_shader.contains("if (ret_ty != TY_UNKNOWN)")
            && !value_call_shader.contains("is_generic_type(ret_ty)")
            && !value_call_shader.contains("ByteAddressBuffer")
            && !value_call_shader.contains("token_words")
            && !value_call_shader.contains("token_kind")
            && !value_call_shader.contains("token_hash")
            && !value_call_shader.contains("same_text")
            && !value_call_shader.contains("inferred_generic_return_type")
            && !value_call_shader.contains("find_call_close")
            && !value_call_shader.contains("call_arg_start(")
            && !value_call_shader.contains("call_arg_count("),
        "qualified call consumer should use resolver and HIR call records, not source text or token argument scans"
    );
    let direct_call_shader =
        include_str!("../../shaders/type_checker/type_check_calls_03_resolve.slang");
    assert!(
        direct_call_shader.contains("StructuredBuffer<uint4> call_arg_record")
            && direct_call_shader.contains("call_node_for_callee_token")
            && direct_call_shader.contains("call_arg_token_range")
            && !direct_call_shader.contains("hir_call_callee_node")
            && !direct_call_shader.contains("hir_call_arg_parent_call")
            && !direct_call_shader.contains("find_call_close")
            && !direct_call_shader.contains("call_arg_start(")
            && !direct_call_shader.contains("call_arg_count(")
            && !direct_call_shader.contains("cur + 1u < arg_end_i"),
        "direct generic call resolver should infer from packed parser-owned HIR call argument records, not token call syntax"
    );
    let call_pack_shader =
        include_str!("../../shaders/type_checker/type_check_calls_02e_pack_hir_call_args.slang");
    assert!(
        call_pack_shader.contains("StructuredBuffer<uint> hir_call_callee_node")
            && call_pack_shader.contains("StructuredBuffer<uint> hir_call_arg_parent_call")
            && call_pack_shader.contains("RWStructuredBuffer<uint4> call_arg_record")
            && call_pack_shader.contains("callee_token * PARAM_CACHE_STRIDE")
            && !call_pack_shader.contains("source_bytes")
            && !call_pack_shader.contains("token_words")
            && !call_pack_shader.contains("token_kind"),
        "HIR call argument packer should materialize parser-owned call records into a compact resolver table"
    );
    assert!(
        visible_shader.contains("enclosing_match_token")
            && visible_shader.contains("prev == TK_ARROW && enclosing_match_token(i) == INVALID"),
        "visible-name resolution should allow match arm result identifiers after arrows without treating function return types as uses"
    );
}

#[test]
fn scope_name_lookup_uses_interned_name_records_not_source_text() {
    let scope_shader = include_str!("../../shaders/type_checker/type_check_scope.slang");

    assert_contains_all(
        scope_shader,
        "scope shader",
        &[
            "StructuredBuffer<uint> name_id_by_token",
            "StructuredBuffer<uint> language_decl_name_id",
            "same_name_id",
            "language_type_code_for_token",
            "LANGUAGE_PRIMITIVE_DECL_FIRST",
        ],
    );
    assert_contains_none(
        scope_shader,
        "scope shader",
        &[
            "import utils",
            "ByteAddressBuffer",
            "source_bytes",
            "source_at",
            "token_start",
            "token_len",
            "token_text_eq",
            "same_text",
            "span2",
            "span3",
            "span4",
            "span5",
            "primitive_type_code",
        ],
    );
}

#[test]
fn visible_decl_scatter_uses_interned_name_records_not_source_text() {
    let visible_shader =
        include_str!("../../shaders/type_checker/type_check_visible_02_scatter.slang");

    assert_contains_all(
        visible_shader,
        "visible declaration scatter shader",
        &[
            "StructuredBuffer<uint> name_id_by_token",
            "same_name_id",
            "resolve_visible_declaration",
            "RWStructuredBuffer<uint> visible_decl",
        ],
    );
    assert_contains_none(
        visible_shader,
        "visible declaration scatter shader",
        &[
            "import utils",
            "ByteAddressBuffer",
            "source_bytes",
            "source_at",
            "token_start",
            "token_len",
            "same_text",
        ],
    );
}

#[test]
fn call_resolver_uses_interned_name_records_not_source_text() {
    let call_clear_shader =
        include_str!("../../shaders/type_checker/type_check_calls_01_resolve.slang");
    let call_resolve_shader =
        include_str!("../../shaders/type_checker/type_check_calls_03_resolve.slang");

    assert_contains_all(
        call_clear_shader,
        "call metadata clear shader",
        &[
            "RWStructuredBuffer<uint> call_fn_index",
            "RWStructuredBuffer<uint> call_return_type",
            "RWStructuredBuffer<uint> function_lookup_key",
            "lookup_capacity",
        ],
    );
    assert_contains_none(
        call_clear_shader,
        "call metadata clear shader",
        &[
            "import utils",
            "TokenIn",
            "token_words",
            "token_count",
            "ByteAddressBuffer",
            "source_bytes",
        ],
    );
    assert_contains_all(
        call_resolve_shader,
        "call resolver shader",
        &[
            "StructuredBuffer<uint> name_id_by_token",
            "StructuredBuffer<uint> language_decl_name_id",
            "same_name_id",
            "language_type_code_for_token",
            "function_lookup_key[slot] == key",
        ],
    );
    assert_contains_none(
        call_resolve_shader,
        "call resolver shader",
        &[
            "import utils",
            "ByteAddressBuffer",
            "source_bytes",
            "source_at",
            "token_start",
            "token_len",
            "same_text",
            "primitive_type_code",
            "span2",
            "span3",
            "span4",
            "span5",
        ],
    );
}

#[test]
fn match_semantic_passes_do_not_reread_source_text() {
    let bind_patterns_shader =
        include_str!("../../shaders/type_checker/type_check_modules_10m_bind_match_patterns.slang");
    let type_match_exprs_shader =
        include_str!("../../shaders/type_checker/type_check_modules_10n_type_match_exprs.slang");

    assert_contains_all(
        bind_patterns_shader,
        "match pattern binder",
        &[
            "StructuredBuffer<uint> name_id_by_token",
            "StructuredBuffer<uint> language_name_id",
            "LANGUAGE_SYMBOL_WILDCARD",
            "token_is_wildcard",
        ],
    );
    assert_contains_none(
        bind_patterns_shader,
        "match pattern binder",
        &[
            "import utils",
            "ByteAddressBuffer",
            "source_bytes",
            "source_at",
            "token_start",
            "token_len",
            "same_text",
            "span4",
            "span5",
        ],
    );

    assert_contains_all(
        type_match_exprs_shader,
        "match expression typing shader",
        &[
            "StructuredBuffer<uint> hir_kind",
            "StructuredBuffer<uint> hir_token_pos",
            "StructuredBuffer<uint> name_id_by_token",
            "kind == TK_TRUE || kind == TK_FALSE",
        ],
    );
    assert_contains_none(
        type_match_exprs_shader,
        "match expression typing shader",
        &[
            "import utils",
            "ByteAddressBuffer",
            "source_bytes",
            "source_at",
            "token_start",
            "token_len",
            "same_text",
            "span4",
            "span5",
            "token_text_eq",
        ],
    );
}

#[test]
fn live_token_validation_pass_does_not_reread_source_text() {
    let tokens_shader = include_str!("../../shaders/type_checker/type_check_tokens_min.slang");

    assert_contains_all(
        tokens_shader,
        "live token validation shader",
        &[
            "StructuredBuffer<uint> name_id_by_token",
            "StructuredBuffer<uint> language_decl_name_id",
            "same_name_id",
            "language_type_code_for_token",
            "LANGUAGE_PRIMITIVE_DECL_FIRST",
        ],
    );
    assert_contains_none(
        tokens_shader,
        "live token validation shader",
        &[
            "import utils",
            "ByteAddressBuffer",
            "source_bytes",
            "source_at",
            "token_start",
            "token_len",
            "token_text_eq",
            "same_text",
            "span2",
            "span3",
            "span4",
            "span5",
            "primitive_type_code",
        ],
    );
}

#[test]
fn type_alias_projection_consumes_hir_type_refs_not_source_tokens() {
    let alias_shader = include_str!(
        "../../shaders/type_checker/type_check_modules_10e2_project_type_aliases.slang"
    );
    let type_checker = type_checker_gpu_sources();

    assert_contains_all(
        alias_shader,
        "type alias shader",
        &[
            "StructuredBuffer<uint> hir_status",
            "StructuredBuffer<uint> hir_kind",
            "StructuredBuffer<uint> first_child",
            "StructuredBuffer<uint> next_sibling",
            "StructuredBuffer<uint> hir_type_form",
            "StructuredBuffer<uint> decl_hir_node",
            "StructuredBuffer<uint> type_expr_ref_tag",
            "StructuredBuffer<uint> type_expr_ref_payload",
            "alias_target_type_node",
            "TYPE_REF_SCALAR",
        ],
    );
    assert_contains_none(
        alias_shader,
        "type alias shader",
        &[
            "ByteAddressBuffer",
            "source_bytes",
            "TokenIn",
            "token_words",
            "token_count",
            "token_kind",
            "token_start",
            "token_len",
            "span2",
            "span3",
            "span4",
            "span5",
            "primitive_type_code",
            "find_alias_assign",
        ],
    );
    assert!(
        type_checker.contains("type_check.modules.project_type_aliases")
            && type_checker.contains("type_check.modules.project_type_paths.after_aliases")
            && type_checker.contains("type_expr_ref_tag.as_entire_binding()")
            && type_checker.contains("decl_hir_node.as_entire_binding()"),
        "type checker should schedule alias projection after HIR type-ref collection and bind HIR/type-ref records"
    );
}

#[test]
fn method_lookup_slice_is_gpu_resident_and_bounded() {
    let semantics_paper = include_str!("../../docs/ParallelLexingParsingSemanticAnalysis.md");
    let requirements = include_str!("../../stdlib/LANGUAGE_REQUIREMENTS.md");
    let type_checker = type_checker_gpu_sources();
    let gpu_wasm = include_str!("../../src/codegen/wasm.rs");
    let clear_shader = include_str!("../../shaders/type_checker/type_check_methods_01_clear.slang");
    let collect_shader =
        include_str!("../../shaders/type_checker/type_check_methods_02_collect.slang");
    let attach_shader =
        include_str!("../../shaders/type_checker/type_check_methods_02b_attach_metadata.slang");
    let bind_self_shader =
        include_str!("../../shaders/type_checker/type_check_methods_02c_bind_self_receivers.slang");
    let seed_key_shader =
        include_str!("../../shaders/type_checker/type_check_methods_03_seed_key_order.slang");
    let sort_key_shader =
        include_str!("../../shaders/type_checker/type_check_methods_04_sort_keys.slang");
    let scatter_key_shader =
        include_str!("../../shaders/type_checker/type_check_methods_04b_sort_keys_scatter.slang");
    let validate_key_shader =
        include_str!("../../shaders/type_checker/type_check_methods_05_validate_keys.slang");
    let mark_call_shader =
        include_str!("../../shaders/type_checker/type_check_methods_06_mark_call_keys.slang");
    let mark_call_return_shader = include_str!(
        "../../shaders/type_checker/type_check_methods_06b_mark_call_return_keys.slang"
    );
    let resolve_table_shader =
        include_str!("../../shaders/type_checker/type_check_methods_07_resolve_table.slang");
    let resolve_shader =
        include_str!("../../shaders/type_checker/type_check_methods_03_resolve.slang");

    assert!(
        semantics_paper.contains("Function Resolution")
            && semantics_paper.contains("function application nodes")
            && semantics_paper.contains("corresponding function declaration node"),
        "paper text should describe function-call resolution to declaration nodes"
    );
    assert!(
        requirements.contains("bounded GPU table resolver")
            && requirements.contains("concrete inherent calls")
            && requirements.contains("sorted method key order")
            && requirements.contains("canonicalizes named type-instance payloads"),
        "LANGUAGE_REQUIREMENTS should describe the current method-call slice"
    );

    for needle in [
        "type_check_methods_01_clear",
        "type_check_methods_02_collect",
        "type_check_methods_02b_attach_metadata",
        "type_check_methods_02c_bind_self_receivers",
        "type_check_methods_03_seed_key_order",
        "type_check_methods_04_sort_keys",
        "type_check_methods_04b_sort_keys_scatter",
        "type_check_methods_05_validate_keys",
        "type_check_methods_06_mark_call_keys",
        "type_check_methods_06b_mark_call_return_keys",
        "type_check_methods_07_resolve_table",
        "type_check_methods_03_resolve",
        "type_check_resident_methods_clear",
        "type_check_resident_methods_attach_metadata",
        "type_check_resident_methods_bind_self_receivers",
        "type_check.methods.bind_self_receivers",
        "type_check.methods.seed_key_order",
        "type_check.methods.sort_keys_histogram",
        "type_check.methods.sort_keys_scatter",
        "type_check.methods.validate_keys",
        "type_check.methods.mark_call_keys",
        "type_check.methods.mark_call_return_keys",
        "type_check.methods.resolve_table",
        "type_check_resident_methods_resolve",
        "type_check.methods.collect",
        "type_check.methods.attach_metadata",
        "type_check.methods.resolve",
        "method_decl_receiver_ref_tag",
        "method_decl_receiver_ref_payload",
        "method_decl_module_id",
        "method_decl_impl_node",
        "method_decl_param_offset",
        "method_decl_receiver_mode",
        "method_decl_visibility",
        "method_decl_name_id",
        "method_key_to_fn_token",
        "method_key_order_tmp",
        "method_key_status",
        "method_key_duplicate_of",
        "method_call_receiver_ref_tag",
        "method_call_receiver_ref_payload",
        "method_call_name_id",
        "name_id_by_token",
        "module_id_by_file_id",
        "type_instance_decl_token",
        "fn_return_ref_tag",
        "fn_return_ref_payload",
        "decl_type_ref_tag",
        "decl_type_ref_payload",
        "member_result_context_instance",
        "member_result_ref_tag",
        "member_result_ref_payload",
        "struct_init_field_expected_ref_tag",
        "struct_init_field_expected_ref_payload",
        "struct_init_field_context_instance",
    ] {
        assert!(
            type_checker.contains(needle),
            "GPU type checker should wire method metadata artifact: {needle}"
        );
    }
    assert!(
        bind_self_shader.contains("hir_member_receiver_node")
            && bind_self_shader.contains("method_decl_param_offset")
            && bind_self_shader.contains("visible_decl[self_token] = self_decl")
            && !bind_self_shader.contains("token_words")
            && !bind_self_shader.contains("token_kind")
            && !bind_self_shader.contains("source_bytes"),
        "self receiver binding should use HIR member records and method declaration metadata"
    );

    for needle in [
        "pub name_id_by_token",
        "pub type_expr_ref_tag",
        "pub type_expr_ref_payload",
        "pub method_decl_receiver_ref_tag",
        "pub method_decl_receiver_ref_payload",
        "pub method_decl_param_offset",
        "pub method_decl_receiver_mode",
        "pub method_call_receiver_ref_tag",
        "pub method_call_receiver_ref_payload",
        "pub type_instance_decl_token",
        "pub type_instance_arg_start",
        "pub type_instance_arg_count",
        "pub type_instance_arg_ref_tag",
        "pub type_instance_arg_ref_payload",
        "pub fn_return_ref_tag",
        "pub fn_return_ref_payload",
        "pub member_result_ref_tag",
        "pub member_result_ref_payload",
        "pub struct_init_field_expected_ref_tag",
        "pub struct_init_field_expected_ref_payload",
    ] {
        assert!(
            type_checker.contains(needle),
            "codegen buffer surface should expose aggregate/method metadata: {needle}"
        );
    }

    for needle in [
        "node_kind_buf",
        "parent_buf",
        "first_child_buf",
        "next_sibling_buf",
        "name_id_by_token_buf",
        "type_expr_ref_tag_buf",
        "type_expr_ref_payload_buf",
        "GpuWasmStructMetadataBuffers",
        "hir_struct_field_parent_struct",
        "hir_struct_field_ordinal",
        "hir_struct_lit_field_parent_lit",
        "wasm_agg_layout_clear.spv",
        "wasm_agg_layout.spv",
        "struct_field_count_by_decl_token",
        "struct_field_index_by_token",
        "struct_field_decl_by_token",
        "struct_field_name_id",
        "struct_field_ref_tag",
        "struct_field_ref_payload",
        "struct_field_scalar_offset",
        "struct_field_scalar_width",
        "struct_init_field_index",
        "member_result_field_index",
        "method_decl_receiver_ref_tag_buf",
        "method_decl_receiver_ref_payload_buf",
        "method_decl_param_offset_buf",
        "method_decl_receiver_mode_buf",
        "method_call_receiver_ref_tag_buf",
        "method_call_receiver_ref_payload_buf",
        "type_instance_decl_token_buf",
        "type_instance_arg_start_buf",
        "type_instance_arg_count_buf",
        "type_instance_arg_ref_tag_buf",
        "type_instance_arg_ref_payload_buf",
        "fn_return_ref_tag_buf",
        "fn_return_ref_payload_buf",
        "member_result_ref_tag_buf",
        "member_result_ref_payload_buf",
        "struct_init_field_expected_ref_tag_buf",
        "struct_init_field_expected_ref_payload_buf",
    ] {
        assert!(
            gpu_wasm.contains(needle),
            "WASM codegen boundary should receive aggregate/method metadata: {needle}"
        );
    }

    for needle in [
        "RWStructuredBuffer<uint> method_decl_receiver_ref_tag",
        "RWStructuredBuffer<uint> method_decl_receiver_ref_payload",
        "RWStructuredBuffer<uint> method_decl_module_id",
        "RWStructuredBuffer<uint> method_decl_name_id",
        "RWStructuredBuffer<uint> method_decl_visibility",
    ] {
        assert!(
            clear_shader.contains(needle),
            "method clear shader should initialize metadata artifact: {needle}"
        );
    }

    for needle in [
        "StructuredBuffer<uint> node_kind",
        "StructuredBuffer<uint> parent",
        "StructuredBuffer<uint> first_child",
        "StructuredBuffer<uint> next_sibling",
        "ancestor_impl_node",
        "first_method_param_token",
        "method_receiver_mode",
        "PROD_IMPL_METHOD",
        "method_decl_param_offset",
        "method_decl_receiver_mode",
        "method_decl_visibility",
        "PROD_IMPL_METHOD_PUB",
    ] {
        assert!(
            collect_shader.contains(needle),
            "method collect shader should derive method metadata from parser/HIR tree artifact: {needle}"
        );
    }
    for forbidden in [
        "ByteAddressBuffer",
        "source_bytes",
        "token_hash",
        "same_text",
        "method_lookup",
        "InterlockedCompareExchange",
        "impl_body_open",
        "matching_block_close_bounded",
        "token_kind(i) == TK_IMPL",
    ] {
        assert!(
            !collect_shader.contains(forbidden),
            "method collect shader should only publish tree-derived declaration records, not text/direct lookup artifacts: {forbidden}"
        );
    }
    assert!(
        !collect_shader.contains("RWStructuredBuffer<uint> status")
            && !collect_shader.contains("record_error"),
        "metadata-only method slice must not accept or reject programs by itself"
    );

    for needle in [
        "StructuredBuffer<uint> module_id_by_file_id",
        "StructuredBuffer<uint> name_id_by_token",
        "StructuredBuffer<uint> type_expr_ref_tag",
        "StructuredBuffer<uint> type_expr_ref_payload",
        "StructuredBuffer<uint> method_decl_impl_node",
        "method_decl_receiver_ref_tag",
        "method_decl_receiver_ref_payload",
        "method_decl_module_id",
        "method_decl_name_id",
        "impl_receiver_type_node",
    ] {
        assert!(
            attach_shader.contains(needle),
            "method metadata attach shader should publish artifact: {needle}"
        );
    }

    for needle in [
        "method_key_to_fn_token",
        "method_key_status",
        "method_key_duplicate_of",
    ] {
        assert!(
            seed_key_shader.contains(needle),
            "method key seed shader should initialize artifact: {needle}"
        );
    }

    for needle in [
        "method_decl_module_id",
        "method_decl_receiver_ref_tag",
        "method_decl_receiver_ref_payload",
        "method_decl_name_id",
        "method_key_order_in",
        "radix_block_histogram",
        "method_key_radix_key",
        "type_instance_decl_token",
        "receiver_payload_key",
        "InterlockedAdd",
    ] {
        assert!(
            sort_key_shader.contains(needle),
            "method key sort shader should build sorted key artifact: {needle}"
        );
    }

    for needle in [
        "method_key_order_out",
        "radix_bucket_base",
        "radix_block_bucket_prefix",
        "local_same_key_rank",
        "type_instance_decl_token",
        "receiver_payload_key",
    ] {
        assert!(
            scatter_key_shader.contains(needle),
            "method key scatter shader should stable-sort artifact: {needle}"
        );
    }

    for needle in [
        "sorted_method_key_order",
        "module_count_out",
        "method_keys_equal",
        "method_decl_visibility",
        "METHOD_KEY_STATUS_PRIVATE_OK",
        "METHOD_KEY_STATUS_PUBLIC_OK",
        "type_instance_decl_token",
        "receiver_payload_key",
        "METHOD_KEY_STATUS_DUPLICATE",
        "method_key_duplicate_of",
    ] {
        assert!(
            validate_key_shader.contains(needle),
            "method key validation shader should validate artifact: {needle}"
        );
    }

    for forbidden in [
        "ByteAddressBuffer",
        "source_bytes",
        "token_hash",
        "same_text",
        "method_lookup_fn",
    ] {
        assert!(
            !seed_key_shader.contains(forbidden)
                && !sort_key_shader.contains(forbidden)
                && !scatter_key_shader.contains(forbidden)
                && !validate_key_shader.contains(forbidden),
            "method key table passes should use interned ids and type-ref records, not token text shortcuts: {forbidden}"
        );
    }

    for needle in [
        "HIR_MEMBER_EXPR",
        "HIR_CALL_EXPR",
        "hir_call_callee_node",
        "hir_member_receiver_token",
        "hir_member_name_token",
        "visible_decl",
        "decl_type_ref_tag",
        "decl_type_ref_payload",
        "method_call_receiver_ref_tag",
        "method_call_name_id",
        "method_call_site_module_id",
    ] {
        assert!(
            mark_call_shader.contains(needle),
            "method call key shader should publish table query artifact: {needle}"
        );
    }
    assert!(
        !mark_call_shader.contains("token_kind")
            && !mark_call_shader.contains("TK_DOT")
            && !mark_call_shader.contains("TK_CALL_LPAREN")
            && !mark_call_shader.contains("hir_token_pos[i] + 1u")
            && !mark_call_shader.contains("receiver_token_for_member")
            && !mark_call_shader.contains("call_descendant_for_member"),
        "method call key marking should use parser-owned HIR call/member records, not token-neighborhood call detection"
    );
    for needle in [
        "call_fn_index",
        "fn_return_ref_tag",
        "fn_return_ref_payload",
        "receiver_call_return_type_ref",
        "hir_call_callee_node",
        "hir_member_receiver_token",
        "hir_member_name_token",
        "method_call_receiver_ref_tag",
        "method_call_site_module_id",
        "HIR_MEMBER_EXPR",
        "HIR_CALL_EXPR",
    ] {
        assert!(
            mark_call_return_shader.contains(needle),
            "method call-return key shader should consume resolved call metadata: {needle}"
        );
    }
    assert!(
        !mark_call_return_shader.contains("token_kind")
            && !mark_call_return_shader.contains("TK_DOT")
            && !mark_call_return_shader.contains("TK_CALL_LPAREN")
            && !mark_call_return_shader.contains("same_text")
            && !mark_call_return_shader.contains("hir_token_pos[i] + 1u")
            && !mark_call_return_shader.contains("receiver_token_for_member")
            && !mark_call_return_shader.contains("call_descendant_for_member"),
        "method call-return key marking should use parser-owned HIR call/member records and call/type-ref metadata, not token text shortcuts"
    );

    for needle in [
        "sorted_method_key_order",
        "method_key_status",
        "compare_method_key",
        "find_method",
        "visibility_checked_method",
        "module_count_out",
        "active_module_count",
        "method_decl_module_id",
        "type_instance_decl_token",
        "module_type_path_type",
        "receiver_payload_key",
        "method_call_site_module_id",
        "method_call_name_id[i] == INVALID",
        "call_fn_index[i] = INVALID",
        "call_fn_index",
        "call_return_type",
    ] {
        assert!(
            resolve_table_shader.contains(needle),
            "method table resolver should consume sorted key artifact: {needle}"
        );
    }
    assert!(
        !resolve_table_shader.contains("token_file_id")
            && !resolve_table_shader.contains("module_id_by_file_id"),
        "method table resolver should use HIR-derived call-site module ids, not token file/module fallback maps"
    );

    for forbidden in [
        "ByteAddressBuffer",
        "source_bytes",
        "token_hash",
        "same_text",
        "method_lookup_fn",
    ] {
        assert!(
            !mark_call_shader.contains(forbidden)
                && !resolve_table_shader.contains(forbidden)
                && !resolve_shader.contains(forbidden),
            "method call resolution should consume AST/HIR-derived ids and sorted tables, not text/direct lookup shortcuts: {forbidden}"
        );
    }

    for needle in [
        "call_fn_index[method_i]",
        "HIR_MEMBER_EXPR",
        "PROD_ARG_LIST",
        "next_arg_from_tail",
        "method_decl_receiver_mode",
        "method_explicit_receiver_consumes_param",
        "RWStructuredBuffer<uint> call_fn_index",
        "RWStructuredBuffer<uint> call_return_type",
        "RWStructuredBuffer<uint> visible_type",
        "validate_method_args",
    ] {
        assert!(
            resolve_shader.contains(needle),
            "method argument resolver should validate table-resolved method calls: {needle}"
        );
    }
    for forbidden in [
        "token_kind",
        "token_words",
        "find_call_close",
        "call_arg_count(",
        "call_arg_start(",
        "call_arg_end(",
        "simple_arg_type",
    ] {
        assert!(
            !resolve_shader.contains(forbidden),
            "method argument resolver should walk HIR call/arg records, not token-range syntax scans: {forbidden}"
        );
    }
}

#[test]
fn condition_type_validation_consumes_hir_expression_records() {
    let shader = include_str!("../../shaders/type_checker/type_check_conditions_hir.slang");

    assert_contains_all(
        shader,
        "type_check_conditions_hir.slang",
        &[
            "StructuredBuffer<uint> hir_stmt_record",
            "StructuredBuffer<uint> hir_expr_record",
            "HIR_EXPR_EQ",
            "HIR_EXPR_NE",
            "HIR_EXPR_LT",
            "HIR_EXPR_GT",
            "HIR_EXPR_LE",
            "HIR_EXPR_GE",
            "HIR_EXPR_AND",
            "HIR_EXPR_OR",
            "direct_expr_record_type",
        ],
    );
    assert_contains_none(
        shader,
        "type_check_conditions_hir.slang",
        &[
            "TokenIn",
            "token_words",
            "token_count",
            "token_kind",
            "source_bytes",
            "token_text",
            "same_text",
        ],
    );
}
