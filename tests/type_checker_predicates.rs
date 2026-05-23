mod common;

use std::{
    collections::HashMap,
    env,
    fs,
    path::{Path, PathBuf},
    process::Command,
    sync::mpsc,
};

use laniusc::gpu::{
    device,
    passes_core::{bind_group, make_pass_data},
};
use wgpu::util::DeviceExt;

const INVALID: u32 = u32::MAX;
const PROD_IMPL_TRAIT: u32 = 18;
const PROD_IMPL_METHODS_SOME: u32 = 20;
const PROD_IMPL_METHOD: u32 = 21;
const PROD_TRAIT: u32 = 25;
const PROD_TRAIT_METHOD: u32 = 28;
const PROD_RET_TYPE: u32 = 34;
const PROD_IMPL_FN: u32 = 13;
const PROD_TYPE_IDENT: u32 = 64;
const PROD_INT: u32 = 161;
const PROD_TYPE_PATH: u32 = 51;
const PROD_TYPE_PATH_IDENT: u32 = 52;
const PROD_PARAM_NAMED: u32 = 57;
const PROD_TYPE_REF: u32 = 271;
const PROD_TYPE_ARGS_SOME: u32 = 213;
const PROD_ENUM_TYPE_PARAMS_NONE: u32 = 218;
const PROD_ENUM_TYPE_PARAM: u32 = 220;
const PROD_TYPE_PARAM_BOUND: u32 = 222;
const PROD_TYPE_PARAM_BOUND_LIST: u32 = 224;
const PROD_BOUND_TYPE_IDENT: u32 = 227;
const PROD_BOUND_TYPE_PATH: u32 = 229;
const PROD_BOUND_TYPE_PATH_IDENT: u32 = 230;
const PROD_BOUND_TYPE_PATH_END: u32 = 232;
const PROD_BOUND_TYPE_ARGS_SOME: u32 = 234;
const HIR_PARAM: u32 = 4;
const HIR_TYPE: u32 = 5;
const HIR_ITEM_KIND_FN: u32 = 4;
const HIR_ITEM_KIND_STRUCT: u32 = 6;
const HIR_ITEM_KIND_TRAIT: u32 = 10;
const HIR_ITEM_NAMESPACE_TYPE: u32 = 3;
const HIR_CALL_EXPR: u32 = 19;
const HIR_EXPR_INT: u32 = 3;
const HIR_EXPR_TRUE: u32 = 4;
const HIR_TYPE_FORM_PATH: u32 = 1;
const TYPE_REF_SCALAR: u32 = 1;
const TYPE_REF_GENERIC_PARAM: u32 = 2;
const TY_BOOL: u32 = 2;
const TY_INT: u32 = 3;
const ERR_BAD_HIR: u32 = 6;
const PREDICATE_STATUS_OK: u32 = 0;
const PREDICATE_STATUS_UNSATISFIED_BOUND: u32 = 9;
const PREDICATE_STATUS_AMBIGUOUS_BOUND: u32 = 10;

#[test]
fn gpu_predicate_collect_consumes_generic_param_and_trait_decl_records() {
    common::block_on_gpu_with_timeout("GPU predicate record collection", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let (spv, reflection) = compile_shader(&root, "type_check_predicates_01_collect");

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.type_checker.predicates.collect",
            "main",
            leak_bytes(spv),
            leak_bytes(reflection),
        )
        .expect("create predicate collect pass");

        let ok = run_predicate_fixture(device, queue, &pass, HIR_ITEM_KIND_TRAIT);
        assert_eq!(ok.status[6], 0, "trait bound predicate should validate");
        assert_eq!(
            ok.owner[6], 1,
            "predicate owner should be the generic fn HIR node"
        );
        assert_eq!(
            ok.subject[6], 10,
            "predicate subject should be generic param T"
        );
        assert_eq!(ok.bound[6], 11, "predicate bound should be trait name Eq");
        assert_eq!(
            ok.arg_count[6], 1,
            "predicate should record one bound argument"
        );
        assert_eq!(ok.first_arg[6], 10, "predicate first arg should be T");
        assert_eq!(
            ok.second_arg[6], INVALID,
            "single-argument predicate should leave the second arg empty"
        );
        assert_eq!(
            ok.status[11], INVALID,
            "bound type arguments are consumed by the predicate row, not published as predicate rows"
        );

        let bad = run_predicate_fixture(device, queue, &pass, HIR_ITEM_KIND_STRUCT);
        assert_eq!(
            bad.status[6], 2,
            "changing only the declaration kind from trait to struct must invalidate the bound"
        );
    });
}

#[test]
fn gpu_predicate_collect_consumes_module_records_for_qualified_trait_bounds() {
    common::block_on_gpu_with_timeout("GPU qualified predicate record collection", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let (spv, reflection) = compile_shader(&root, "type_check_predicates_01_collect");

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.type_checker.predicates.qualified_collect",
            "main",
            leak_bytes(spv),
            leak_bytes(reflection),
        )
        .expect("create predicate collect pass");

        let ok = run_qualified_predicate_fixture(device, queue, &pass, HIR_ITEM_KIND_TRAIT, 4);
        assert_eq!(
            ok.status[6], 0,
            "qualified trait bound should resolve through the module/type declaration key records"
        );
        assert_eq!(
            ok.bound[6], 11,
            "predicate bound should be qualified leaf Eq"
        );
        assert_eq!(
            ok.arg_count[6], 1,
            "qualified predicate should record its type argument"
        );
        assert_eq!(
            ok.first_arg[6], 10,
            "qualified predicate first arg should be T"
        );
        assert_eq!(
            ok.second_arg[6], INVALID,
            "qualified single-argument predicate should leave the second arg empty"
        );

        let wrong_decl_kind =
            run_qualified_predicate_fixture(device, queue, &pass, HIR_ITEM_KIND_STRUCT, 4);
        assert_eq!(
            wrong_decl_kind.status[6], 2,
            "qualified bound resolution must still require a trait declaration"
        );

        let wrong_module =
            run_qualified_predicate_fixture(device, queue, &pass, HIR_ITEM_KIND_TRAIT, 5);
        assert_eq!(
            wrong_module.status[6], 2,
            "changing only the module key record must make the qualified bound unresolved"
        );
    });
}

#[test]
fn gpu_predicate_collect_consumes_trait_impl_records() {
    common::block_on_gpu_with_timeout("GPU trait impl predicate record collection", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let (spv, reflection) = compile_shader(&root, "type_check_predicates_01_collect");

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.type_checker.predicates.trait_impl_collect",
            "main",
            leak_bytes(spv),
            leak_bytes(reflection),
        )
        .expect("create predicate collect pass");

        let ok = run_trait_impl_fixture(
            device,
            queue,
            &pass,
            HIR_ITEM_KIND_TRAIT,
            HIR_ITEM_NAMESPACE_TYPE,
            7,
            PROD_PARAM_NAMED,
            1,
            4,
        );
        assert_eq!(ok.status[12], 0, "trait impl header should validate");
        assert_eq!(
            ok.owner[12], 12,
            "trait impl status row should be keyed by the impl node"
        );
        assert_eq!(
            ok.bound[12], 13,
            "trait impl record should publish the implemented trait token"
        );
        assert_eq!(
            ok.subject[12], 15,
            "trait impl record should publish the target type token"
        );
        assert_eq!(
            ok.arg_count[12], 1,
            "trait impl record should publish the implemented trait argument count"
        );
        assert_eq!(
            ok.first_arg[12], 14,
            "trait impl record should publish the implemented trait argument token"
        );
        assert_eq!(
            ok.second_arg[12], INVALID,
            "single-argument trait impl should leave the second arg empty"
        );

        let non_trait = run_trait_impl_fixture(
            device,
            queue,
            &pass,
            HIR_ITEM_KIND_STRUCT,
            HIR_ITEM_NAMESPACE_TYPE,
            7,
            PROD_PARAM_NAMED,
            1,
            4,
        );
        assert_eq!(
            non_trait.status[12], 2,
            "changing only the implemented declaration kind from trait to struct must invalidate the impl"
        );

        let missing_target = run_trait_impl_fixture(
            device,
            queue,
            &pass,
            HIR_ITEM_KIND_TRAIT,
            0,
            7,
            PROD_PARAM_NAMED,
            1,
            4,
        );
        assert_eq!(
            missing_target.status[12], 5,
            "changing only the target declaration namespace must invalidate the impl target"
        );

        let missing_method = run_trait_impl_fixture(
            device,
            queue,
            &pass,
            HIR_ITEM_KIND_TRAIT,
            HIR_ITEM_NAMESPACE_TYPE,
            8,
            PROD_PARAM_NAMED,
            1,
            4,
        );
        assert_eq!(
            missing_method.status[12], 6,
            "changing only the impl method name id must invalidate required trait method coverage"
        );
        assert_eq!(
            missing_method.first_arg[12], 8,
            "missing method status should publish the required trait method token"
        );

        let wrong_arity = run_trait_impl_fixture(
            device,
            queue,
            &pass,
            HIR_ITEM_KIND_TRAIT,
            HIR_ITEM_NAMESPACE_TYPE,
            7,
            0,
            1,
            4,
        );
        assert_eq!(
            wrong_arity.status[12], 7,
            "changing only the impl method parameter record must invalidate trait method arity"
        );
        assert_eq!(
            wrong_arity.first_arg[12], 8,
            "arity mismatch status should publish the required trait method token"
        );

        let wrong_param_type = run_trait_impl_fixture(
            device,
            queue,
            &pass,
            HIR_ITEM_KIND_TRAIT,
            HIR_ITEM_NAMESPACE_TYPE,
            7,
            PROD_PARAM_NAMED,
            5,
            4,
        );
        assert_eq!(
            wrong_param_type.status[12], 8,
            "changing only the impl method parameter type record must invalidate trait method signature"
        );
        assert_eq!(
            wrong_param_type.first_arg[12], 8,
            "signature mismatch status should publish the required trait method token"
        );

        let wrong_return_type = run_trait_impl_fixture(
            device,
            queue,
            &pass,
            HIR_ITEM_KIND_TRAIT,
            HIR_ITEM_NAMESPACE_TYPE,
            7,
            PROD_PARAM_NAMED,
            1,
            5,
        );
        assert_eq!(
            wrong_return_type.status[12], 8,
            "changing only the impl method return type record must invalidate trait method signature"
        );

        let ref_ok = run_trait_impl_reference_signature_fixture(
            device,
            queue,
            &pass,
            HIR_ITEM_KIND_TRAIT,
            HIR_ITEM_NAMESPACE_TYPE,
            7,
            1,
        );
        assert_eq!(
            ref_ok.status[13], 0,
            "reference signature should validate through parser-owned type nodes"
        );
        assert_eq!(
            ref_ok.arg_count[13], 1,
            "reference trait impl record should publish the implemented trait argument count"
        );
        assert_eq!(
            ref_ok.first_arg[13], 14,
            "reference trait impl record should publish the implemented trait argument token"
        );
        assert_eq!(
            ref_ok.second_arg[13], INVALID,
            "reference single-argument impl should leave the second arg empty"
        );

        let ref_bad = run_trait_impl_reference_signature_fixture(
            device,
            queue,
            &pass,
            HIR_ITEM_KIND_TRAIT,
            HIR_ITEM_NAMESPACE_TYPE,
            7,
            5,
        );
        assert_eq!(
            ref_bad.status[13], 8,
            "changing only the referenced impl type record must invalidate trait method signature"
        );
        assert_eq!(
            ref_bad.first_arg[13], 8,
            "reference signature mismatch should publish the required trait method token"
        );
    });
}

#[test]
fn gpu_predicate_obligations_consume_call_param_and_impl_records() {
    common::block_on_gpu_with_timeout("GPU predicate obligation validation", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let (spv, reflection) = compile_shader(&root, "type_check_predicates_02_obligations");

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.type_checker.predicates.obligations",
            "main",
            leak_bytes(spv),
            leak_bytes(reflection),
        )
        .expect("create predicate obligation pass");

        let ok = run_predicate_obligation_fixture(device, queue, &pass, 1, true, 1, TY_BOOL);
        assert_eq!(ok[0], 1, "matching concrete impl should satisfy the call");
        assert_eq!(ok[1], INVALID, "matching impl should leave no error token");

        let missing_impl =
            run_predicate_obligation_fixture(device, queue, &pass, 0, true, 1, TY_BOOL);
        assert_eq!(
            missing_impl[0], 0,
            "removing only the concrete impl predicate row must reject the call"
        );
        assert_eq!(
            missing_impl[2], ERR_BAD_HIR,
            "unsatisfied call obligation should report a HIR semantic error"
        );
        assert_eq!(
            missing_impl[3], PREDICATE_STATUS_UNSATISFIED_BOUND,
            "unsatisfied call obligation should publish the predicate failure detail"
        );

        let ambiguous_impl =
            run_predicate_obligation_fixture(device, queue, &pass, 2, true, 1, TY_BOOL);
        assert_eq!(
            ambiguous_impl[0], 0,
            "adding only a second matching impl row must reject the ambiguous call"
        );
        assert_eq!(
            ambiguous_impl[3], PREDICATE_STATUS_AMBIGUOUS_BOUND,
            "ambiguous call obligation should publish the ambiguity detail"
        );

        let non_generic_param =
            run_predicate_obligation_fixture(device, queue, &pass, 1, false, 1, TY_BOOL);
        assert_eq!(
            non_generic_param[0], 0,
            "changing only the parser-owned parameter type record must prevent proving the bound"
        );

        let two_arg_ok =
            run_predicate_obligation_fixture(device, queue, &pass, 1, true, 2, TY_BOOL);
        assert_eq!(
            two_arg_ok[0], 1,
            "matching concrete impl should satisfy a two-argument bound"
        );
        assert_eq!(
            two_arg_ok[1], INVALID,
            "matching two-argument impl should leave no error token"
        );

        let wrong_second_arg =
            run_predicate_obligation_fixture(device, queue, &pass, 1, true, 2, TY_INT);
        assert_eq!(
            wrong_second_arg[0], 0,
            "changing only the second impl argument record must reject the call"
        );
        assert_eq!(
            wrong_second_arg[3], PREDICATE_STATUS_UNSATISFIED_BOUND,
            "wrong second impl argument should publish the unsatisfied-bound detail"
        );
    });
}

struct PredicateSnapshot {
    owner: Vec<u32>,
    subject: Vec<u32>,
    bound: Vec<u32>,
    arg_count: Vec<u32>,
    first_arg: Vec<u32>,
    second_arg: Vec<u32>,
    status: Vec<u32>,
}

fn pack_hir_node_ordinal(node: u32, ordinal: u32) -> u32 {
    node | (ordinal << 28)
}

fn run_predicate_obligation_fixture(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    pass: &laniusc::gpu::passes_core::PassData,
    impl_count: u32,
    param_is_generic: bool,
    bound_arg_count: u32,
    impl_second_arg_ty: u32,
) -> Vec<u32> {
    const NODES: usize = 12;
    const TOKENS: usize = 24;
    const EXPR_RECORD_STRIDE: usize = 4;
    const CALL_NODE: u32 = 8;
    const CALLEE_TOKEN: usize = 7;
    const FN_NODE: u32 = 1;
    const FN_TOKEN: u32 = 2;
    const GENERIC_PARAM_TOKEN: usize = 3;
    const SECOND_GENERIC_PARAM_TOKEN: usize = 4;
    const LEFT_PARAM_NODE: usize = 4;
    const LEFT_TYPE_TOKEN: usize = 5;
    const RIGHT_PARAM_NODE: usize = 6;
    const RIGHT_TYPE_TOKEN: usize = 6;
    const ARG_NODE: usize = 10;
    const SECOND_ARG_NODE: usize = 11;
    const WHERE_PRED_NODE: usize = 2;
    const IMPL_PRED_NODE: usize = 0;
    const WHERE_SUBJECT_TOKEN: usize = 9;
    const WHERE_BOUND_TOKEN: usize = 10;
    const WHERE_ARG_TOKEN: usize = 11;
    const WHERE_SECOND_ARG_TOKEN: usize = 12;
    const IMPL_BOUND_TOKEN: usize = 13;
    const IMPL_SUBJECT_TOKEN: usize = 14;
    const IMPL_ARG_TOKEN: usize = 15;
    const IMPL_SECOND_ARG_TOKEN: usize = 16;

    let params = uniform_words(
        device,
        "tests.predicates.obligations.params",
        &[TOKENS as u32, 0, NODES as u32],
    );
    let hir_status = storage_buffer(
        device,
        "tests.predicates.obligations.hir_status",
        &[0, 0, 0, 0, 0, NODES as u32],
    );
    let node_kind = storage_buffer(
        device,
        "tests.predicates.obligations.node_kind",
        &[
            0,
            0,
            PROD_ENUM_TYPE_PARAM,
            PROD_ENUM_TYPE_PARAM,
            PROD_PARAM_NAMED,
            PROD_TYPE_IDENT,
            PROD_PARAM_NAMED,
            PROD_TYPE_IDENT,
            0,
            0,
            PROD_INT,
            0,
        ],
    );
    let parent = storage_buffer(
        device,
        "tests.predicates.obligations.parent",
        &[INVALID, 0, 1, 1, 1, 4, 1, 6, 0, 8, 8, 8],
    );
    let first_child = storage_buffer(
        device,
        "tests.predicates.obligations.first_child",
        &[
            1, 2, INVALID, INVALID, 5, INVALID, 7, INVALID, 9, INVALID, INVALID, INVALID,
        ],
    );
    let next_sibling = storage_buffer(
        device,
        "tests.predicates.obligations.next_sibling",
        &[
            INVALID, 8, 3, 4, 6, INVALID, INVALID, INVALID, INVALID, 10, 11, INVALID,
        ],
    );
    let subtree_end = storage_buffer(
        device,
        "tests.predicates.obligations.subtree_end",
        &[12, 8, 3, 4, 6, 6, 8, 8, 12, 10, 11, 12],
    );
    let hir_kind = storage_buffer(
        device,
        "tests.predicates.obligations.hir_kind",
        &[
            0,
            0,
            0,
            0,
            HIR_PARAM,
            HIR_TYPE,
            HIR_PARAM,
            HIR_TYPE,
            HIR_CALL_EXPR,
            0,
            0,
            0,
        ],
    );
    let hir_token_pos = storage_buffer(
        device,
        "tests.predicates.obligations.hir_token_pos",
        &[
            0,
            FN_TOKEN,
            GENERIC_PARAM_TOKEN as u32,
            SECOND_GENERIC_PARAM_TOKEN as u32,
            4,
            LEFT_TYPE_TOKEN as u32,
            6,
            RIGHT_TYPE_TOKEN as u32,
            0,
            CALLEE_TOKEN as u32,
            8,
            9,
        ],
    );
    let mut hir_type_form_words = vec![0; NODES];
    hir_type_form_words[5] = HIR_TYPE_FORM_PATH;
    hir_type_form_words[7] = HIR_TYPE_FORM_PATH;
    let hir_type_form = storage_buffer(
        device,
        "tests.predicates.obligations.hir_type_form",
        &hir_type_form_words,
    );
    let hir_member_name_token = storage_buffer(
        device,
        "tests.predicates.obligations.hir_member_name_token",
        &vec![INVALID; NODES],
    );
    let hir_struct_lit_head_node = storage_buffer(
        device,
        "tests.predicates.obligations.hir_struct_lit_head_node",
        &vec![INVALID; NODES],
    );
    let mut expr_record_words = vec![INVALID; NODES * EXPR_RECORD_STRIDE];
    expr_record_words[ARG_NODE * EXPR_RECORD_STRIDE] = HIR_EXPR_INT;
    expr_record_words[SECOND_ARG_NODE * EXPR_RECORD_STRIDE] = HIR_EXPR_TRUE;
    let hir_expr_record = storage_buffer(
        device,
        "tests.predicates.obligations.hir_expr_record",
        &expr_record_words,
    );
    let mut param_record_words = vec![INVALID; NODES * 4];
    param_record_words[LEFT_PARAM_NODE * 4] = FN_NODE;
    param_record_words[LEFT_PARAM_NODE * 4 + 1] = 0;
    param_record_words[LEFT_PARAM_NODE * 4 + 2] = 4;
    param_record_words[LEFT_PARAM_NODE * 4 + 3] = LEFT_PARAM_NODE as u32;
    param_record_words[RIGHT_PARAM_NODE * 4] = FN_NODE;
    param_record_words[RIGHT_PARAM_NODE * 4 + 1] = 1;
    param_record_words[RIGHT_PARAM_NODE * 4 + 2] = 6;
    param_record_words[RIGHT_PARAM_NODE * 4 + 3] = RIGHT_PARAM_NODE as u32;
    let hir_param_record = storage_buffer(
        device,
        "tests.predicates.obligations.hir_param_record",
        &param_record_words,
    );
    let mut hir_call_callee_node_words = vec![INVALID; NODES];
    hir_call_callee_node_words[CALL_NODE as usize] = 9;
    let hir_call_callee_node = storage_buffer(
        device,
        "tests.predicates.obligations.hir_call_callee_node",
        &hir_call_callee_node_words,
    );
    let mut hir_call_arg_parent_call_words = vec![INVALID; NODES];
    hir_call_arg_parent_call_words[ARG_NODE] = pack_hir_node_ordinal(CALL_NODE, 0);
    hir_call_arg_parent_call_words[SECOND_ARG_NODE] = pack_hir_node_ordinal(CALL_NODE, 1);
    let hir_call_arg_parent_call = storage_buffer(
        device,
        "tests.predicates.obligations.hir_call_arg_parent_call",
        &hir_call_arg_parent_call_words,
    );
    let mut name_ids = vec![INVALID; TOKENS];
    name_ids[GENERIC_PARAM_TOKEN] = 1;
    name_ids[SECOND_GENERIC_PARAM_TOKEN] = 3;
    name_ids[WHERE_SUBJECT_TOKEN] = 1;
    name_ids[WHERE_ARG_TOKEN] = 1;
    name_ids[WHERE_SECOND_ARG_TOKEN] = 3;
    name_ids[WHERE_BOUND_TOKEN] = 2;
    name_ids[IMPL_BOUND_TOKEN] = 2;
    let name_id_by_token = storage_buffer(
        device,
        "tests.predicates.obligations.name_id_by_token",
        &name_ids,
    );
    let visible_decl = storage_buffer(
        device,
        "tests.predicates.obligations.visible_decl",
        &vec![INVALID; TOKENS],
    );
    let visible_type = storage_buffer(
        device,
        "tests.predicates.obligations.visible_type",
        &vec![0; TOKENS],
    );
    let mut call_fn_index_words = vec![INVALID; TOKENS];
    call_fn_index_words[CALLEE_TOKEN] = FN_TOKEN;
    let call_fn_index = storage_buffer(
        device,
        "tests.predicates.obligations.call_fn_index",
        &call_fn_index_words,
    );
    let call_return_type = storage_buffer(
        device,
        "tests.predicates.obligations.call_return_type",
        &vec![0; TOKENS],
    );
    let mut type_expr_ref_tag_words = vec![0; TOKENS];
    let mut type_expr_ref_payload_words = vec![INVALID; TOKENS];
    if param_is_generic {
        type_expr_ref_tag_words[LEFT_TYPE_TOKEN] = TYPE_REF_GENERIC_PARAM;
        type_expr_ref_payload_words[LEFT_TYPE_TOKEN] = GENERIC_PARAM_TOKEN as u32;
    } else {
        type_expr_ref_tag_words[LEFT_TYPE_TOKEN] = TYPE_REF_SCALAR;
        type_expr_ref_payload_words[LEFT_TYPE_TOKEN] = TY_INT;
    }
    type_expr_ref_tag_words[RIGHT_TYPE_TOKEN] = TYPE_REF_GENERIC_PARAM;
    type_expr_ref_payload_words[RIGHT_TYPE_TOKEN] = SECOND_GENERIC_PARAM_TOKEN as u32;
    type_expr_ref_tag_words[IMPL_SUBJECT_TOKEN] = TYPE_REF_SCALAR;
    type_expr_ref_payload_words[IMPL_SUBJECT_TOKEN] = TY_INT;
    type_expr_ref_tag_words[IMPL_ARG_TOKEN] = TYPE_REF_SCALAR;
    type_expr_ref_payload_words[IMPL_ARG_TOKEN] = TY_INT;
    type_expr_ref_tag_words[IMPL_SECOND_ARG_TOKEN] = TYPE_REF_SCALAR;
    type_expr_ref_payload_words[IMPL_SECOND_ARG_TOKEN] = impl_second_arg_ty;
    let type_expr_ref_tag = storage_buffer(
        device,
        "tests.predicates.obligations.type_expr_ref_tag",
        &type_expr_ref_tag_words,
    );
    let type_expr_ref_payload = storage_buffer(
        device,
        "tests.predicates.obligations.type_expr_ref_payload",
        &type_expr_ref_payload_words,
    );
    let mut type_generic_param_slot_words = vec![INVALID; TOKENS];
    type_generic_param_slot_words[GENERIC_PARAM_TOKEN] = 0;
    type_generic_param_slot_words[SECOND_GENERIC_PARAM_TOKEN] = 1;
    let type_generic_param_slot_by_token = storage_buffer(
        device,
        "tests.predicates.obligations.type_generic_param_slot_by_token",
        &type_generic_param_slot_words,
    );

    let mut owner = vec![INVALID; NODES];
    let mut subject = vec![INVALID; NODES];
    let mut bound = vec![INVALID; NODES];
    let mut arg_count = vec![0; NODES];
    let mut first_arg = vec![INVALID; NODES];
    let mut second_arg = vec![INVALID; NODES];
    let mut predicate_status = vec![INVALID; NODES];
    owner[WHERE_PRED_NODE] = FN_NODE;
    subject[WHERE_PRED_NODE] = WHERE_SUBJECT_TOKEN as u32;
    bound[WHERE_PRED_NODE] = WHERE_BOUND_TOKEN as u32;
    arg_count[WHERE_PRED_NODE] = bound_arg_count;
    if bound_arg_count >= 1 {
        first_arg[WHERE_PRED_NODE] = WHERE_ARG_TOKEN as u32;
    }
    if bound_arg_count >= 2 {
        second_arg[WHERE_PRED_NODE] = WHERE_SECOND_ARG_TOKEN as u32;
    }
    predicate_status[WHERE_PRED_NODE] = PREDICATE_STATUS_OK;
    if impl_count >= 1 {
        owner[IMPL_PRED_NODE] = IMPL_PRED_NODE as u32;
        subject[IMPL_PRED_NODE] = IMPL_SUBJECT_TOKEN as u32;
        bound[IMPL_PRED_NODE] = IMPL_BOUND_TOKEN as u32;
        arg_count[IMPL_PRED_NODE] = bound_arg_count;
        if bound_arg_count >= 1 {
            first_arg[IMPL_PRED_NODE] = IMPL_ARG_TOKEN as u32;
        }
        if bound_arg_count >= 2 {
            second_arg[IMPL_PRED_NODE] = IMPL_SECOND_ARG_TOKEN as u32;
        }
        predicate_status[IMPL_PRED_NODE] = PREDICATE_STATUS_OK;
    }
    if impl_count >= 2 {
        owner[9] = 9;
        subject[9] = IMPL_SUBJECT_TOKEN as u32;
        bound[9] = IMPL_BOUND_TOKEN as u32;
        arg_count[9] = bound_arg_count;
        if bound_arg_count >= 1 {
            first_arg[9] = IMPL_ARG_TOKEN as u32;
        }
        if bound_arg_count >= 2 {
            second_arg[9] = IMPL_SECOND_ARG_TOKEN as u32;
        }
        predicate_status[9] = PREDICATE_STATUS_OK;
    }
    let predicate_owner_node = storage_buffer(
        device,
        "tests.predicates.obligations.predicate_owner_node",
        &owner,
    );
    let predicate_subject_token = storage_buffer(
        device,
        "tests.predicates.obligations.predicate_subject_token",
        &subject,
    );
    let predicate_bound_token = storage_buffer(
        device,
        "tests.predicates.obligations.predicate_bound_token",
        &bound,
    );
    let predicate_bound_arg_count = storage_buffer(
        device,
        "tests.predicates.obligations.predicate_bound_arg_count",
        &arg_count,
    );
    let predicate_bound_first_arg_token = storage_buffer(
        device,
        "tests.predicates.obligations.predicate_bound_first_arg_token",
        &first_arg,
    );
    let predicate_bound_second_arg_token = storage_buffer(
        device,
        "tests.predicates.obligations.predicate_bound_second_arg_token",
        &second_arg,
    );
    let predicate_status = storage_buffer(
        device,
        "tests.predicates.obligations.predicate_status",
        &predicate_status,
    );
    let status = storage_buffer(
        device,
        "tests.predicates.obligations.status",
        &[1, INVALID, 0, 0],
    );

    let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("hir_status".into(), hir_status.as_entire_binding()),
        ("node_kind".into(), node_kind.as_entire_binding()),
        ("parent".into(), parent.as_entire_binding()),
        ("first_child".into(), first_child.as_entire_binding()),
        ("next_sibling".into(), next_sibling.as_entire_binding()),
        ("subtree_end".into(), subtree_end.as_entire_binding()),
        ("hir_kind".into(), hir_kind.as_entire_binding()),
        ("hir_token_pos".into(), hir_token_pos.as_entire_binding()),
        ("hir_type_form".into(), hir_type_form.as_entire_binding()),
        (
            "hir_member_name_token".into(),
            hir_member_name_token.as_entire_binding(),
        ),
        (
            "hir_struct_lit_head_node".into(),
            hir_struct_lit_head_node.as_entire_binding(),
        ),
        (
            "hir_expr_record".into(),
            hir_expr_record.as_entire_binding(),
        ),
        (
            "hir_param_record".into(),
            hir_param_record.as_entire_binding(),
        ),
        (
            "hir_call_callee_node".into(),
            hir_call_callee_node.as_entire_binding(),
        ),
        (
            "hir_call_arg_parent_call".into(),
            hir_call_arg_parent_call.as_entire_binding(),
        ),
        (
            "name_id_by_token".into(),
            name_id_by_token.as_entire_binding(),
        ),
        ("visible_decl".into(), visible_decl.as_entire_binding()),
        ("visible_type".into(), visible_type.as_entire_binding()),
        ("call_fn_index".into(), call_fn_index.as_entire_binding()),
        (
            "call_return_type".into(),
            call_return_type.as_entire_binding(),
        ),
        (
            "type_expr_ref_tag".into(),
            type_expr_ref_tag.as_entire_binding(),
        ),
        (
            "type_expr_ref_payload".into(),
            type_expr_ref_payload.as_entire_binding(),
        ),
        (
            "type_generic_param_slot_by_token".into(),
            type_generic_param_slot_by_token.as_entire_binding(),
        ),
        (
            "predicate_owner_node".into(),
            predicate_owner_node.as_entire_binding(),
        ),
        (
            "predicate_subject_token".into(),
            predicate_subject_token.as_entire_binding(),
        ),
        (
            "predicate_bound_token".into(),
            predicate_bound_token.as_entire_binding(),
        ),
        (
            "predicate_bound_arg_count".into(),
            predicate_bound_arg_count.as_entire_binding(),
        ),
        (
            "predicate_bound_first_arg_token".into(),
            predicate_bound_first_arg_token.as_entire_binding(),
        ),
        (
            "predicate_bound_second_arg_token".into(),
            predicate_bound_second_arg_token.as_entire_binding(),
        ),
        (
            "predicate_status".into(),
            predicate_status.as_entire_binding(),
        ),
        ("status".into(), status.as_entire_binding()),
    ]);
    let bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("tests.type_checker.predicates.obligations"),
        &pass.bind_group_layouts[0],
        &pass.reflection,
        0,
        &resources,
    )
    .expect("create predicate obligation bind group");

    let status_rb = readback_buffer(device, "tests.predicates.obligations.status.rb", 4);
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("tests.type_checker.predicates.obligations.encoder"),
    });
    {
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("tests.type_checker.predicates.obligations.pass"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, &bind_group, &[]);
        compute.dispatch_workgroups(1, 1, 1);
    }
    encoder.copy_buffer_to_buffer(&status, 0, &status_rb, 0, 16);
    queue.submit(Some(encoder.finish()));
    read_u32s(device, &status_rb, 4)
}

fn run_predicate_fixture(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    pass: &laniusc::gpu::passes_core::PassData,
    bound_decl_kind: u32,
) -> PredicateSnapshot {
    const NODES: usize = 14;
    const TOKENS: usize = 16;

    let params = uniform_words(
        device,
        "tests.predicates.params",
        &[TOKENS as u32, 0, NODES as u32],
    );
    let hir_status = storage_buffer(
        device,
        "tests.predicates.hir_status",
        &[0, 0, 0, 0, 0, NODES as u32],
    );
    let node_kind = storage_buffer(
        device,
        "tests.predicates.node_kind",
        &[
            0,
            0,
            219,
            PROD_ENUM_TYPE_PARAM,
            PROD_TYPE_PARAM_BOUND,
            PROD_TYPE_PARAM_BOUND_LIST,
            PROD_BOUND_TYPE_IDENT,
            PROD_BOUND_TYPE_PATH,
            PROD_BOUND_TYPE_PATH_IDENT,
            PROD_BOUND_TYPE_PATH_END,
            PROD_BOUND_TYPE_ARGS_SOME,
            PROD_BOUND_TYPE_IDENT,
            PROD_BOUND_TYPE_PATH,
            PROD_BOUND_TYPE_PATH_IDENT,
        ],
    );
    let parent = storage_buffer(
        device,
        "tests.predicates.parent",
        &[INVALID, 0, 1, 2, 3, 4, 5, 6, 7, 7, 6, 10, 11, 12],
    );
    let first_child = storage_buffer(
        device,
        "tests.predicates.first_child",
        &[
            1, 2, 3, 4, 5, 6, 7, 8, INVALID, INVALID, 11, 12, 13, INVALID,
        ],
    );
    let subtree_end = storage_buffer(
        device,
        "tests.predicates.subtree_end",
        &[
            NODES as u32,
            NODES as u32,
            NODES as u32,
            NODES as u32,
            NODES as u32,
            NODES as u32,
            NODES as u32,
            10,
            9,
            10,
            NODES as u32,
            NODES as u32,
            NODES as u32,
            NODES as u32,
        ],
    );
    let hir_token_pos = storage_buffer(
        device,
        "tests.predicates.hir_token_pos",
        &[0, 0, 2, 10, 0, 11, 11, 11, 11, 0, 0, 10, 10, 10],
    );
    let hir_type_len_value = storage_buffer(
        device,
        "tests.predicates.hir_type_len_value",
        &vec![INVALID; NODES],
    );
    let hir_item_kind = storage_buffer(
        device,
        "tests.predicates.hir_item_kind",
        &[0, HIR_ITEM_KIND_FN, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    );
    let mut name_ids = vec![INVALID; TOKENS];
    name_ids[10] = 1;
    name_ids[11] = 2;
    let name_id_by_token = storage_buffer(device, "tests.predicates.name_id_by_token", &name_ids);
    let mut generic_counts = vec![0; NODES];
    generic_counts[1] = 1;
    let type_decl_generic_param_count_by_node = storage_buffer(
        device,
        "tests.predicates.type_decl_generic_param_count_by_node",
        &generic_counts,
    );
    let language_type_code_by_name_id = storage_buffer(
        device,
        "tests.predicates.language_type_code_by_name_id",
        &[0, 0, 0, 0],
    );
    let decl_count_out = storage_buffer(device, "tests.predicates.decl_count_out", &[1]);
    let decl_name_id = storage_buffer(device, "tests.predicates.decl_name_id", &[2]);
    let decl_kind = storage_buffer(device, "tests.predicates.decl_kind", &[bound_decl_kind]);
    let decl_namespace = storage_buffer(
        device,
        "tests.predicates.decl_namespace",
        &[HIR_ITEM_NAMESPACE_TYPE],
    );
    let decl_hir_node = storage_buffer(device, "tests.predicates.decl_hir_node", &[INVALID]);
    let module_count_out = storage_buffer(device, "tests.predicates.module_count_out", &[0]);
    let sorted_module_key_order =
        storage_buffer(device, "tests.predicates.sorted_module_key_order", &[0]);
    let module_key_segment_count =
        storage_buffer(device, "tests.predicates.module_key_segment_count", &[0]);
    let module_key_segment_base =
        storage_buffer(device, "tests.predicates.module_key_segment_base", &[0]);
    let module_key_segment_name_id =
        storage_buffer(device, "tests.predicates.module_key_segment_name_id", &[0]);
    let decl_type_key_count_out =
        storage_buffer(device, "tests.predicates.decl_type_key_count_out", &[0]);
    let decl_type_key_to_decl_id = storage_buffer(
        device,
        "tests.predicates.decl_type_key_to_decl_id",
        &[INVALID],
    );
    let decl_module_id = storage_buffer(device, "tests.predicates.decl_module_id", &[INVALID]);

    let owner = storage_buffer(device, "tests.predicates.owner", &vec![INVALID; NODES]);
    let subject = storage_buffer(device, "tests.predicates.subject", &vec![INVALID; NODES]);
    let bound = storage_buffer(device, "tests.predicates.bound", &vec![INVALID; NODES]);
    let arg_count = storage_buffer(device, "tests.predicates.arg_count", &vec![0; NODES]);
    let first_arg = storage_buffer(device, "tests.predicates.first_arg", &vec![INVALID; NODES]);
    let second_arg = storage_buffer(device, "tests.predicates.second_arg", &vec![INVALID; NODES]);
    let status = storage_buffer(device, "tests.predicates.status", &vec![INVALID; NODES]);

    let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("hir_status".into(), hir_status.as_entire_binding()),
        ("node_kind".into(), node_kind.as_entire_binding()),
        ("parent".into(), parent.as_entire_binding()),
        ("first_child".into(), first_child.as_entire_binding()),
        ("subtree_end".into(), subtree_end.as_entire_binding()),
        ("hir_token_pos".into(), hir_token_pos.as_entire_binding()),
        (
            "hir_type_len_value".into(),
            hir_type_len_value.as_entire_binding(),
        ),
        ("hir_item_kind".into(), hir_item_kind.as_entire_binding()),
        (
            "name_id_by_token".into(),
            name_id_by_token.as_entire_binding(),
        ),
        (
            "type_decl_generic_param_count_by_node".into(),
            type_decl_generic_param_count_by_node.as_entire_binding(),
        ),
        (
            "language_type_code_by_name_id".into(),
            language_type_code_by_name_id.as_entire_binding(),
        ),
        ("decl_count_out".into(), decl_count_out.as_entire_binding()),
        ("decl_name_id".into(), decl_name_id.as_entire_binding()),
        ("decl_kind".into(), decl_kind.as_entire_binding()),
        ("decl_namespace".into(), decl_namespace.as_entire_binding()),
        ("decl_hir_node".into(), decl_hir_node.as_entire_binding()),
        (
            "module_count_out".into(),
            module_count_out.as_entire_binding(),
        ),
        (
            "sorted_module_key_order".into(),
            sorted_module_key_order.as_entire_binding(),
        ),
        (
            "module_key_segment_count".into(),
            module_key_segment_count.as_entire_binding(),
        ),
        (
            "module_key_segment_base".into(),
            module_key_segment_base.as_entire_binding(),
        ),
        (
            "module_key_segment_name_id".into(),
            module_key_segment_name_id.as_entire_binding(),
        ),
        (
            "decl_type_key_count_out".into(),
            decl_type_key_count_out.as_entire_binding(),
        ),
        (
            "decl_type_key_to_decl_id".into(),
            decl_type_key_to_decl_id.as_entire_binding(),
        ),
        ("decl_module_id".into(), decl_module_id.as_entire_binding()),
        ("predicate_owner_node".into(), owner.as_entire_binding()),
        (
            "predicate_subject_token".into(),
            subject.as_entire_binding(),
        ),
        ("predicate_bound_token".into(), bound.as_entire_binding()),
        (
            "predicate_bound_arg_count".into(),
            arg_count.as_entire_binding(),
        ),
        (
            "predicate_bound_first_arg_token".into(),
            first_arg.as_entire_binding(),
        ),
        (
            "predicate_bound_second_arg_token".into(),
            second_arg.as_entire_binding(),
        ),
        ("predicate_status".into(), status.as_entire_binding()),
    ]);
    let bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("tests.type_checker.predicates.collect"),
        &pass.bind_group_layouts[0],
        &pass.reflection,
        0,
        &resources,
    )
    .expect("create predicate collect bind group");

    let owner_rb = readback_buffer(device, "tests.predicates.owner.rb", NODES);
    let subject_rb = readback_buffer(device, "tests.predicates.subject.rb", NODES);
    let bound_rb = readback_buffer(device, "tests.predicates.bound.rb", NODES);
    let arg_count_rb = readback_buffer(device, "tests.predicates.arg_count.rb", NODES);
    let first_arg_rb = readback_buffer(device, "tests.predicates.first_arg.rb", NODES);
    let second_arg_rb = readback_buffer(device, "tests.predicates.second_arg.rb", NODES);
    let status_rb = readback_buffer(device, "tests.predicates.status.rb", NODES);

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("tests.type_checker.predicates.encoder"),
    });
    {
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("tests.type_checker.predicates.pass"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, &bind_group, &[]);
        compute.dispatch_workgroups(1, 1, 1);
    }
    for (src, dst) in [
        (&owner, &owner_rb),
        (&subject, &subject_rb),
        (&bound, &bound_rb),
        (&arg_count, &arg_count_rb),
        (&first_arg, &first_arg_rb),
        (&second_arg, &second_arg_rb),
        (&status, &status_rb),
    ] {
        encoder.copy_buffer_to_buffer(src, 0, dst, 0, (NODES * 4) as u64);
    }
    queue.submit(Some(encoder.finish()));

    PredicateSnapshot {
        owner: read_u32s(device, &owner_rb, NODES),
        subject: read_u32s(device, &subject_rb, NODES),
        bound: read_u32s(device, &bound_rb, NODES),
        arg_count: read_u32s(device, &arg_count_rb, NODES),
        first_arg: read_u32s(device, &first_arg_rb, NODES),
        second_arg: read_u32s(device, &second_arg_rb, NODES),
        status: read_u32s(device, &status_rb, NODES),
    }
}

fn run_qualified_predicate_fixture(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    pass: &laniusc::gpu::passes_core::PassData,
    bound_decl_kind: u32,
    module_tail_name_id: u32,
) -> PredicateSnapshot {
    const NODES: usize = 16;
    const TOKENS: usize = 16;

    let params = uniform_words(
        device,
        "tests.predicates.qualified.params",
        &[TOKENS as u32, 0, NODES as u32],
    );
    let hir_status = storage_buffer(
        device,
        "tests.predicates.qualified.hir_status",
        &[0, 0, 0, 0, 0, NODES as u32],
    );
    let node_kind = storage_buffer(
        device,
        "tests.predicates.qualified.node_kind",
        &[
            0,
            0,
            219,
            PROD_ENUM_TYPE_PARAM,
            PROD_TYPE_PARAM_BOUND,
            PROD_TYPE_PARAM_BOUND_LIST,
            PROD_BOUND_TYPE_IDENT,
            PROD_BOUND_TYPE_PATH,
            PROD_BOUND_TYPE_PATH_IDENT,
            PROD_BOUND_TYPE_PATH_IDENT,
            PROD_BOUND_TYPE_PATH_IDENT,
            PROD_BOUND_TYPE_PATH_END,
            PROD_BOUND_TYPE_ARGS_SOME,
            PROD_BOUND_TYPE_IDENT,
            PROD_BOUND_TYPE_PATH,
            PROD_BOUND_TYPE_PATH_IDENT,
        ],
    );
    let parent = storage_buffer(
        device,
        "tests.predicates.qualified.parent",
        &[INVALID, 0, 1, 2, 3, 4, 5, 6, 7, 7, 7, 7, 6, 12, 13, 14],
    );
    let first_child = storage_buffer(
        device,
        "tests.predicates.qualified.first_child",
        &[
            1, 2, 3, 4, 5, 6, 7, 8, INVALID, INVALID, INVALID, INVALID, 13, 14, 15, INVALID,
        ],
    );
    let subtree_end = storage_buffer(
        device,
        "tests.predicates.qualified.subtree_end",
        &[
            NODES as u32,
            NODES as u32,
            NODES as u32,
            NODES as u32,
            NODES as u32,
            NODES as u32,
            NODES as u32,
            12,
            9,
            10,
            11,
            12,
            NODES as u32,
            NODES as u32,
            NODES as u32,
            NODES as u32,
        ],
    );
    let hir_token_pos = storage_buffer(
        device,
        "tests.predicates.qualified.hir_token_pos",
        &[0, 0, 2, 10, 0, 11, 11, 12, 12, 13, 11, 0, 0, 10, 10, 10],
    );
    let hir_type_len_value = storage_buffer(
        device,
        "tests.predicates.qualified.hir_type_len_value",
        &vec![INVALID; NODES],
    );
    let hir_item_kind = storage_buffer(
        device,
        "tests.predicates.qualified.hir_item_kind",
        &[
            0,
            HIR_ITEM_KIND_FN,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
        ],
    );
    let mut name_ids = vec![INVALID; TOKENS];
    name_ids[10] = 1;
    name_ids[11] = 2;
    name_ids[12] = 3;
    name_ids[13] = 4;
    let name_id_by_token = storage_buffer(
        device,
        "tests.predicates.qualified.name_id_by_token",
        &name_ids,
    );
    let mut generic_counts = vec![0; NODES];
    generic_counts[1] = 1;
    let type_decl_generic_param_count_by_node = storage_buffer(
        device,
        "tests.predicates.qualified.type_decl_generic_param_count_by_node",
        &generic_counts,
    );
    let language_type_code_by_name_id = storage_buffer(
        device,
        "tests.predicates.qualified.language_type_code_by_name_id",
        &[0, 0, 0, 0, 0, 0],
    );
    let decl_count_out = storage_buffer(device, "tests.predicates.qualified.decl_count_out", &[1]);
    let decl_name_id = storage_buffer(device, "tests.predicates.qualified.decl_name_id", &[2]);
    let decl_kind = storage_buffer(
        device,
        "tests.predicates.qualified.decl_kind",
        &[bound_decl_kind],
    );
    let decl_namespace = storage_buffer(
        device,
        "tests.predicates.qualified.decl_namespace",
        &[HIR_ITEM_NAMESPACE_TYPE],
    );
    let decl_hir_node = storage_buffer(
        device,
        "tests.predicates.qualified.decl_hir_node",
        &[INVALID],
    );
    let module_count_out =
        storage_buffer(device, "tests.predicates.qualified.module_count_out", &[1]);
    let sorted_module_key_order = storage_buffer(
        device,
        "tests.predicates.qualified.sorted_module_key_order",
        &[0],
    );
    let module_key_segment_count = storage_buffer(
        device,
        "tests.predicates.qualified.module_key_segment_count",
        &[2],
    );
    let module_key_segment_base = storage_buffer(
        device,
        "tests.predicates.qualified.module_key_segment_base",
        &[0],
    );
    let module_key_segment_name_id = storage_buffer(
        device,
        "tests.predicates.qualified.module_key_segment_name_id",
        &[3, module_tail_name_id, 0, 0, 0, 0, 0, 0],
    );
    let decl_type_key_count_out = storage_buffer(
        device,
        "tests.predicates.qualified.decl_type_key_count_out",
        &[1],
    );
    let decl_type_key_to_decl_id = storage_buffer(
        device,
        "tests.predicates.qualified.decl_type_key_to_decl_id",
        &[0],
    );
    let decl_module_id = storage_buffer(device, "tests.predicates.qualified.decl_module_id", &[0]);

    let owner = storage_buffer(
        device,
        "tests.predicates.qualified.owner",
        &vec![INVALID; NODES],
    );
    let subject = storage_buffer(
        device,
        "tests.predicates.qualified.subject",
        &vec![INVALID; NODES],
    );
    let bound = storage_buffer(
        device,
        "tests.predicates.qualified.bound",
        &vec![INVALID; NODES],
    );
    let arg_count = storage_buffer(
        device,
        "tests.predicates.qualified.arg_count",
        &vec![0; NODES],
    );
    let first_arg = storage_buffer(
        device,
        "tests.predicates.qualified.first_arg",
        &vec![INVALID; NODES],
    );
    let second_arg = storage_buffer(
        device,
        "tests.predicates.qualified.second_arg",
        &vec![INVALID; NODES],
    );
    let status = storage_buffer(
        device,
        "tests.predicates.qualified.status",
        &vec![INVALID; NODES],
    );

    let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("hir_status".into(), hir_status.as_entire_binding()),
        ("node_kind".into(), node_kind.as_entire_binding()),
        ("parent".into(), parent.as_entire_binding()),
        ("first_child".into(), first_child.as_entire_binding()),
        ("subtree_end".into(), subtree_end.as_entire_binding()),
        ("hir_token_pos".into(), hir_token_pos.as_entire_binding()),
        (
            "hir_type_len_value".into(),
            hir_type_len_value.as_entire_binding(),
        ),
        ("hir_item_kind".into(), hir_item_kind.as_entire_binding()),
        (
            "name_id_by_token".into(),
            name_id_by_token.as_entire_binding(),
        ),
        (
            "type_decl_generic_param_count_by_node".into(),
            type_decl_generic_param_count_by_node.as_entire_binding(),
        ),
        (
            "language_type_code_by_name_id".into(),
            language_type_code_by_name_id.as_entire_binding(),
        ),
        ("decl_count_out".into(), decl_count_out.as_entire_binding()),
        ("decl_name_id".into(), decl_name_id.as_entire_binding()),
        ("decl_kind".into(), decl_kind.as_entire_binding()),
        ("decl_namespace".into(), decl_namespace.as_entire_binding()),
        ("decl_hir_node".into(), decl_hir_node.as_entire_binding()),
        (
            "module_count_out".into(),
            module_count_out.as_entire_binding(),
        ),
        (
            "sorted_module_key_order".into(),
            sorted_module_key_order.as_entire_binding(),
        ),
        (
            "module_key_segment_count".into(),
            module_key_segment_count.as_entire_binding(),
        ),
        (
            "module_key_segment_base".into(),
            module_key_segment_base.as_entire_binding(),
        ),
        (
            "module_key_segment_name_id".into(),
            module_key_segment_name_id.as_entire_binding(),
        ),
        (
            "decl_type_key_count_out".into(),
            decl_type_key_count_out.as_entire_binding(),
        ),
        (
            "decl_type_key_to_decl_id".into(),
            decl_type_key_to_decl_id.as_entire_binding(),
        ),
        ("decl_module_id".into(), decl_module_id.as_entire_binding()),
        ("predicate_owner_node".into(), owner.as_entire_binding()),
        (
            "predicate_subject_token".into(),
            subject.as_entire_binding(),
        ),
        ("predicate_bound_token".into(), bound.as_entire_binding()),
        (
            "predicate_bound_arg_count".into(),
            arg_count.as_entire_binding(),
        ),
        (
            "predicate_bound_first_arg_token".into(),
            first_arg.as_entire_binding(),
        ),
        (
            "predicate_bound_second_arg_token".into(),
            second_arg.as_entire_binding(),
        ),
        ("predicate_status".into(), status.as_entire_binding()),
    ]);
    let bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("tests.type_checker.predicates.qualified_collect"),
        &pass.bind_group_layouts[0],
        &pass.reflection,
        0,
        &resources,
    )
    .expect("create qualified predicate collect bind group");

    let owner_rb = readback_buffer(device, "tests.predicates.qualified.owner.rb", NODES);
    let subject_rb = readback_buffer(device, "tests.predicates.qualified.subject.rb", NODES);
    let bound_rb = readback_buffer(device, "tests.predicates.qualified.bound.rb", NODES);
    let arg_count_rb = readback_buffer(device, "tests.predicates.qualified.arg_count.rb", NODES);
    let first_arg_rb = readback_buffer(device, "tests.predicates.qualified.first_arg.rb", NODES);
    let second_arg_rb = readback_buffer(device, "tests.predicates.qualified.second_arg.rb", NODES);
    let status_rb = readback_buffer(device, "tests.predicates.qualified.status.rb", NODES);

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("tests.type_checker.predicates.qualified.encoder"),
    });
    {
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("tests.type_checker.predicates.qualified.pass"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, &bind_group, &[]);
        compute.dispatch_workgroups(1, 1, 1);
    }
    for (src, dst) in [
        (&owner, &owner_rb),
        (&subject, &subject_rb),
        (&bound, &bound_rb),
        (&arg_count, &arg_count_rb),
        (&first_arg, &first_arg_rb),
        (&second_arg, &second_arg_rb),
        (&status, &status_rb),
    ] {
        encoder.copy_buffer_to_buffer(src, 0, dst, 0, (NODES * 4) as u64);
    }
    queue.submit(Some(encoder.finish()));

    PredicateSnapshot {
        owner: read_u32s(device, &owner_rb, NODES),
        subject: read_u32s(device, &subject_rb, NODES),
        bound: read_u32s(device, &bound_rb, NODES),
        arg_count: read_u32s(device, &arg_count_rb, NODES),
        first_arg: read_u32s(device, &first_arg_rb, NODES),
        second_arg: read_u32s(device, &second_arg_rb, NODES),
        status: read_u32s(device, &status_rb, NODES),
    }
}

fn run_trait_impl_fixture(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    pass: &laniusc::gpu::passes_core::PassData,
    implemented_decl_kind: u32,
    target_decl_namespace: u32,
    impl_method_name_id: u32,
    impl_param_kind: u32,
    impl_param_type_name_id: u32,
    impl_return_type_name_id: u32,
) -> PredicateSnapshot {
    const NODES: usize = 35;
    const TOKENS: usize = 24;

    let params = uniform_words(
        device,
        "tests.predicates.trait_impl.params",
        &[TOKENS as u32, 0, NODES as u32],
    );
    let hir_status = storage_buffer(
        device,
        "tests.predicates.trait_impl.hir_status",
        &[0, 0, 0, 0, 0, NODES as u32],
    );
    let node_kind = storage_buffer(
        device,
        "tests.predicates.trait_impl.node_kind",
        &[
            0,
            PROD_TRAIT,
            PROD_ENUM_TYPE_PARAM,
            PROD_TRAIT_METHOD,
            PROD_PARAM_NAMED,
            PROD_TYPE_IDENT,
            PROD_TYPE_PATH,
            PROD_TYPE_PATH_IDENT,
            PROD_RET_TYPE,
            PROD_TYPE_IDENT,
            PROD_TYPE_PATH,
            PROD_TYPE_PATH_IDENT,
            PROD_IMPL_TRAIT,
            PROD_ENUM_TYPE_PARAMS_NONE,
            PROD_TYPE_IDENT,
            PROD_TYPE_PATH,
            PROD_TYPE_PATH_IDENT,
            PROD_TYPE_ARGS_SOME,
            PROD_TYPE_IDENT,
            PROD_TYPE_PATH,
            PROD_TYPE_PATH_IDENT,
            PROD_TYPE_IDENT,
            PROD_TYPE_PATH,
            PROD_TYPE_PATH_IDENT,
            PROD_IMPL_METHODS_SOME,
            PROD_IMPL_METHOD,
            PROD_IMPL_FN,
            impl_param_kind,
            PROD_TYPE_IDENT,
            PROD_TYPE_PATH,
            PROD_TYPE_PATH_IDENT,
            PROD_RET_TYPE,
            PROD_TYPE_IDENT,
            PROD_TYPE_PATH,
            PROD_TYPE_PATH_IDENT,
        ],
    );
    let parent = storage_buffer(
        device,
        "tests.predicates.trait_impl.parent",
        &[
            INVALID, 0, 1, 1, 3, 4, 5, 6, 3, 8, 9, 10, 0, 12, 12, 14, 15, 14, 17, 18, 19, 12, 21,
            22, 12, 24, 25, 26, 27, 28, 29, 26, 31, 32, 33,
        ],
    );
    let first_child = storage_buffer(
        device,
        "tests.predicates.trait_impl.first_child",
        &[
            1, 2, INVALID, 4, 5, 6, 7, INVALID, 9, 10, 11, INVALID, 13, INVALID, 15, 16, INVALID,
            18, 19, 20, INVALID, 22, 23, INVALID, 25, 26, 27, 28, 29, 30, INVALID, 32, 33, 34,
            INVALID,
        ],
    );
    let subtree_end = storage_buffer(
        device,
        "tests.predicates.trait_impl.subtree_end",
        &[
            35, 12, 3, 12, 8, 8, 8, 8, 12, 12, 12, 12, 35, 14, 21, 17, 17, 21, 21, 21, 21, 24, 24,
            24, 35, 35, 35, 31, 31, 31, 31, 35, 35, 35, 35,
        ],
    );
    let hir_token_pos = storage_buffer(
        device,
        "tests.predicates.trait_impl.hir_token_pos",
        &[
            0, 5, 6, 7, 9, 10, 10, 10, 0, 11, 11, 11, 12, 0, 13, 13, 13, 0, 14, 14, 14, 15, 15, 15,
            0, 0, 16, 18, 19, 19, 19, 0, 20, 20, 20,
        ],
    );
    let hir_type_len_value = storage_buffer(
        device,
        "tests.predicates.trait_impl.hir_type_len_value",
        &vec![INVALID; NODES],
    );
    let mut item_kinds = vec![0; NODES];
    item_kinds[1] = HIR_ITEM_KIND_TRAIT;
    let hir_item_kind = storage_buffer(
        device,
        "tests.predicates.trait_impl.hir_item_kind",
        &item_kinds,
    );
    let mut name_ids = vec![INVALID; TOKENS];
    name_ids[6] = 3;
    name_ids[8] = 7;
    name_ids[10] = 3;
    name_ids[11] = 4;
    name_ids[13] = 2;
    name_ids[14] = 1;
    name_ids[15] = 1;
    name_ids[17] = impl_method_name_id;
    name_ids[19] = impl_param_type_name_id;
    name_ids[20] = impl_return_type_name_id;
    let name_id_by_token = storage_buffer(
        device,
        "tests.predicates.trait_impl.name_id_by_token",
        &name_ids,
    );
    let mut generic_counts = vec![0; NODES];
    generic_counts[1] = 1;
    let type_decl_generic_param_count_by_node = storage_buffer(
        device,
        "tests.predicates.trait_impl.type_decl_generic_param_count_by_node",
        &generic_counts,
    );
    let mut language_types = vec![0; 8];
    language_types[4] = 2;
    language_types[5] = 3;
    let language_type_code_by_name_id = storage_buffer(
        device,
        "tests.predicates.trait_impl.language_type_code_by_name_id",
        &language_types,
    );
    let decl_count_out = storage_buffer(device, "tests.predicates.trait_impl.decl_count_out", &[2]);
    let decl_name_id = storage_buffer(device, "tests.predicates.trait_impl.decl_name_id", &[2, 1]);
    let decl_kind = storage_buffer(
        device,
        "tests.predicates.trait_impl.decl_kind",
        &[implemented_decl_kind, HIR_ITEM_KIND_STRUCT],
    );
    let decl_namespace = storage_buffer(
        device,
        "tests.predicates.trait_impl.decl_namespace",
        &[HIR_ITEM_NAMESPACE_TYPE, target_decl_namespace],
    );
    let decl_hir_node = storage_buffer(
        device,
        "tests.predicates.trait_impl.decl_hir_node",
        &[1, INVALID],
    );
    let module_count_out =
        storage_buffer(device, "tests.predicates.trait_impl.module_count_out", &[0]);
    let sorted_module_key_order = storage_buffer(
        device,
        "tests.predicates.trait_impl.sorted_module_key_order",
        &[0],
    );
    let module_key_segment_count = storage_buffer(
        device,
        "tests.predicates.trait_impl.module_key_segment_count",
        &[0],
    );
    let module_key_segment_base = storage_buffer(
        device,
        "tests.predicates.trait_impl.module_key_segment_base",
        &[0],
    );
    let module_key_segment_name_id = storage_buffer(
        device,
        "tests.predicates.trait_impl.module_key_segment_name_id",
        &[0],
    );
    let decl_type_key_count_out = storage_buffer(
        device,
        "tests.predicates.trait_impl.decl_type_key_count_out",
        &[0],
    );
    let decl_type_key_to_decl_id = storage_buffer(
        device,
        "tests.predicates.trait_impl.decl_type_key_to_decl_id",
        &[INVALID],
    );
    let decl_module_id = storage_buffer(
        device,
        "tests.predicates.trait_impl.decl_module_id",
        &[0, 0],
    );

    let owner = storage_buffer(
        device,
        "tests.predicates.trait_impl.owner",
        &vec![INVALID; NODES],
    );
    let subject = storage_buffer(
        device,
        "tests.predicates.trait_impl.subject",
        &vec![INVALID; NODES],
    );
    let bound = storage_buffer(
        device,
        "tests.predicates.trait_impl.bound",
        &vec![INVALID; NODES],
    );
    let arg_count = storage_buffer(
        device,
        "tests.predicates.trait_impl.arg_count",
        &vec![0; NODES],
    );
    let first_arg = storage_buffer(
        device,
        "tests.predicates.trait_impl.first_arg",
        &vec![INVALID; NODES],
    );
    let second_arg = storage_buffer(
        device,
        "tests.predicates.trait_impl.second_arg",
        &vec![INVALID; NODES],
    );
    let status = storage_buffer(
        device,
        "tests.predicates.trait_impl.status",
        &vec![INVALID; NODES],
    );

    let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("hir_status".into(), hir_status.as_entire_binding()),
        ("node_kind".into(), node_kind.as_entire_binding()),
        ("parent".into(), parent.as_entire_binding()),
        ("first_child".into(), first_child.as_entire_binding()),
        ("subtree_end".into(), subtree_end.as_entire_binding()),
        ("hir_token_pos".into(), hir_token_pos.as_entire_binding()),
        (
            "hir_type_len_value".into(),
            hir_type_len_value.as_entire_binding(),
        ),
        ("hir_item_kind".into(), hir_item_kind.as_entire_binding()),
        (
            "name_id_by_token".into(),
            name_id_by_token.as_entire_binding(),
        ),
        (
            "type_decl_generic_param_count_by_node".into(),
            type_decl_generic_param_count_by_node.as_entire_binding(),
        ),
        (
            "language_type_code_by_name_id".into(),
            language_type_code_by_name_id.as_entire_binding(),
        ),
        ("decl_count_out".into(), decl_count_out.as_entire_binding()),
        ("decl_name_id".into(), decl_name_id.as_entire_binding()),
        ("decl_kind".into(), decl_kind.as_entire_binding()),
        ("decl_namespace".into(), decl_namespace.as_entire_binding()),
        ("decl_hir_node".into(), decl_hir_node.as_entire_binding()),
        (
            "module_count_out".into(),
            module_count_out.as_entire_binding(),
        ),
        (
            "sorted_module_key_order".into(),
            sorted_module_key_order.as_entire_binding(),
        ),
        (
            "module_key_segment_count".into(),
            module_key_segment_count.as_entire_binding(),
        ),
        (
            "module_key_segment_base".into(),
            module_key_segment_base.as_entire_binding(),
        ),
        (
            "module_key_segment_name_id".into(),
            module_key_segment_name_id.as_entire_binding(),
        ),
        (
            "decl_type_key_count_out".into(),
            decl_type_key_count_out.as_entire_binding(),
        ),
        (
            "decl_type_key_to_decl_id".into(),
            decl_type_key_to_decl_id.as_entire_binding(),
        ),
        ("decl_module_id".into(), decl_module_id.as_entire_binding()),
        ("predicate_owner_node".into(), owner.as_entire_binding()),
        (
            "predicate_subject_token".into(),
            subject.as_entire_binding(),
        ),
        ("predicate_bound_token".into(), bound.as_entire_binding()),
        (
            "predicate_bound_arg_count".into(),
            arg_count.as_entire_binding(),
        ),
        (
            "predicate_bound_first_arg_token".into(),
            first_arg.as_entire_binding(),
        ),
        (
            "predicate_bound_second_arg_token".into(),
            second_arg.as_entire_binding(),
        ),
        ("predicate_status".into(), status.as_entire_binding()),
    ]);
    let bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("tests.type_checker.predicates.trait_impl_collect"),
        &pass.bind_group_layouts[0],
        &pass.reflection,
        0,
        &resources,
    )
    .expect("create trait impl predicate collect bind group");

    let owner_rb = readback_buffer(device, "tests.predicates.trait_impl.owner.rb", NODES);
    let subject_rb = readback_buffer(device, "tests.predicates.trait_impl.subject.rb", NODES);
    let bound_rb = readback_buffer(device, "tests.predicates.trait_impl.bound.rb", NODES);
    let arg_count_rb = readback_buffer(device, "tests.predicates.trait_impl.arg_count.rb", NODES);
    let first_arg_rb = readback_buffer(device, "tests.predicates.trait_impl.first_arg.rb", NODES);
    let second_arg_rb = readback_buffer(device, "tests.predicates.trait_impl.second_arg.rb", NODES);
    let status_rb = readback_buffer(device, "tests.predicates.trait_impl.status.rb", NODES);

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("tests.type_checker.predicates.trait_impl.encoder"),
    });
    {
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("tests.type_checker.predicates.trait_impl.pass"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, &bind_group, &[]);
        compute.dispatch_workgroups(1, 1, 1);
    }
    for (src, dst) in [
        (&owner, &owner_rb),
        (&subject, &subject_rb),
        (&bound, &bound_rb),
        (&arg_count, &arg_count_rb),
        (&first_arg, &first_arg_rb),
        (&second_arg, &second_arg_rb),
        (&status, &status_rb),
    ] {
        encoder.copy_buffer_to_buffer(src, 0, dst, 0, (NODES * 4) as u64);
    }
    queue.submit(Some(encoder.finish()));

    PredicateSnapshot {
        owner: read_u32s(device, &owner_rb, NODES),
        subject: read_u32s(device, &subject_rb, NODES),
        bound: read_u32s(device, &bound_rb, NODES),
        arg_count: read_u32s(device, &arg_count_rb, NODES),
        first_arg: read_u32s(device, &first_arg_rb, NODES),
        second_arg: read_u32s(device, &second_arg_rb, NODES),
        status: read_u32s(device, &status_rb, NODES),
    }
}

fn run_trait_impl_reference_signature_fixture(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    pass: &laniusc::gpu::passes_core::PassData,
    implemented_decl_kind: u32,
    target_decl_namespace: u32,
    impl_method_name_id: u32,
    impl_ref_inner_name_id: u32,
) -> PredicateSnapshot {
    const NODES: usize = 37;
    const TOKENS: usize = 24;

    let params = uniform_words(
        device,
        "tests.predicates.trait_ref.params",
        &[TOKENS as u32, 0, NODES as u32],
    );
    let hir_status = storage_buffer(
        device,
        "tests.predicates.trait_ref.hir_status",
        &[0, 0, 0, 0, 0, NODES as u32],
    );
    let node_kind = storage_buffer(
        device,
        "tests.predicates.trait_ref.node_kind",
        &[
            0,
            PROD_TRAIT,
            PROD_ENUM_TYPE_PARAM,
            PROD_TRAIT_METHOD,
            PROD_PARAM_NAMED,
            PROD_TYPE_REF,
            PROD_TYPE_IDENT,
            PROD_TYPE_PATH,
            PROD_TYPE_PATH_IDENT,
            PROD_RET_TYPE,
            PROD_TYPE_IDENT,
            PROD_TYPE_PATH,
            PROD_TYPE_PATH_IDENT,
            PROD_IMPL_TRAIT,
            PROD_ENUM_TYPE_PARAMS_NONE,
            PROD_TYPE_IDENT,
            PROD_TYPE_PATH,
            PROD_TYPE_PATH_IDENT,
            PROD_TYPE_ARGS_SOME,
            PROD_TYPE_IDENT,
            PROD_TYPE_PATH,
            PROD_TYPE_PATH_IDENT,
            PROD_TYPE_IDENT,
            PROD_TYPE_PATH,
            PROD_TYPE_PATH_IDENT,
            PROD_IMPL_METHODS_SOME,
            PROD_IMPL_METHOD,
            PROD_IMPL_FN,
            PROD_PARAM_NAMED,
            PROD_TYPE_REF,
            PROD_TYPE_IDENT,
            PROD_TYPE_PATH,
            PROD_TYPE_PATH_IDENT,
            PROD_RET_TYPE,
            PROD_TYPE_IDENT,
            PROD_TYPE_PATH,
            PROD_TYPE_PATH_IDENT,
        ],
    );
    let parent = storage_buffer(
        device,
        "tests.predicates.trait_ref.parent",
        &[
            INVALID, 0, 1, 1, 3, 4, 5, 6, 7, 3, 9, 10, 11, 0, 13, 13, 15, 16, 15, 18, 19, 20, 13,
            22, 23, 13, 25, 26, 27, 28, 29, 30, 31, 27, 33, 34, 35,
        ],
    );
    let first_child = storage_buffer(
        device,
        "tests.predicates.trait_ref.first_child",
        &[
            1, 2, INVALID, 4, 5, 6, 7, 8, INVALID, 10, 11, 12, INVALID, 14, INVALID, 16, 17,
            INVALID, 19, 20, 21, INVALID, 23, 24, INVALID, 26, 27, 28, 29, 30, 31, 32, INVALID, 34,
            35, 36, INVALID,
        ],
    );
    let subtree_end = storage_buffer(
        device,
        "tests.predicates.trait_ref.subtree_end",
        &[
            37, 13, 3, 13, 9, 9, 9, 9, 9, 13, 13, 13, 13, 37, 15, 22, 18, 18, 22, 22, 22, 22, 25,
            25, 25, 37, 37, 37, 33, 33, 33, 33, 33, 37, 37, 37, 37,
        ],
    );
    let hir_token_pos = storage_buffer(
        device,
        "tests.predicates.trait_ref.hir_token_pos",
        &[
            0, 5, 6, 7, 9, 9, 10, 10, 10, 0, 11, 11, 11, 12, 0, 13, 13, 13, 0, 14, 14, 14, 15, 15,
            15, 0, 0, 16, 18, 18, 19, 19, 19, 0, 20, 20, 20,
        ],
    );
    let hir_type_len_value = storage_buffer(
        device,
        "tests.predicates.trait_ref.hir_type_len_value",
        &vec![INVALID; NODES],
    );
    let mut item_kinds = vec![0; NODES];
    item_kinds[1] = HIR_ITEM_KIND_TRAIT;
    let hir_item_kind = storage_buffer(
        device,
        "tests.predicates.trait_ref.hir_item_kind",
        &item_kinds,
    );
    let mut name_ids = vec![INVALID; TOKENS];
    name_ids[6] = 3;
    name_ids[8] = 7;
    name_ids[10] = 3;
    name_ids[11] = 4;
    name_ids[13] = 2;
    name_ids[14] = 1;
    name_ids[15] = 1;
    name_ids[17] = impl_method_name_id;
    name_ids[19] = impl_ref_inner_name_id;
    name_ids[20] = 4;
    let name_id_by_token = storage_buffer(
        device,
        "tests.predicates.trait_ref.name_id_by_token",
        &name_ids,
    );
    let mut generic_counts = vec![0; NODES];
    generic_counts[1] = 1;
    let type_decl_generic_param_count_by_node = storage_buffer(
        device,
        "tests.predicates.trait_ref.type_decl_generic_param_count_by_node",
        &generic_counts,
    );
    let mut language_types = vec![0; 8];
    language_types[4] = 2;
    language_types[5] = 3;
    let language_type_code_by_name_id = storage_buffer(
        device,
        "tests.predicates.trait_ref.language_type_code_by_name_id",
        &language_types,
    );
    let decl_count_out = storage_buffer(device, "tests.predicates.trait_ref.decl_count_out", &[2]);
    let decl_name_id = storage_buffer(device, "tests.predicates.trait_ref.decl_name_id", &[2, 1]);
    let decl_kind = storage_buffer(
        device,
        "tests.predicates.trait_ref.decl_kind",
        &[implemented_decl_kind, HIR_ITEM_KIND_STRUCT],
    );
    let decl_namespace = storage_buffer(
        device,
        "tests.predicates.trait_ref.decl_namespace",
        &[HIR_ITEM_NAMESPACE_TYPE, target_decl_namespace],
    );
    let decl_hir_node = storage_buffer(
        device,
        "tests.predicates.trait_ref.decl_hir_node",
        &[1, INVALID],
    );
    let module_count_out =
        storage_buffer(device, "tests.predicates.trait_ref.module_count_out", &[0]);
    let sorted_module_key_order = storage_buffer(
        device,
        "tests.predicates.trait_ref.sorted_module_key_order",
        &[0],
    );
    let module_key_segment_count = storage_buffer(
        device,
        "tests.predicates.trait_ref.module_key_segment_count",
        &[0],
    );
    let module_key_segment_base = storage_buffer(
        device,
        "tests.predicates.trait_ref.module_key_segment_base",
        &[0],
    );
    let module_key_segment_name_id = storage_buffer(
        device,
        "tests.predicates.trait_ref.module_key_segment_name_id",
        &[0],
    );
    let decl_type_key_count_out = storage_buffer(
        device,
        "tests.predicates.trait_ref.decl_type_key_count_out",
        &[0],
    );
    let decl_type_key_to_decl_id = storage_buffer(
        device,
        "tests.predicates.trait_ref.decl_type_key_to_decl_id",
        &[INVALID],
    );
    let decl_module_id =
        storage_buffer(device, "tests.predicates.trait_ref.decl_module_id", &[0, 0]);

    let owner = storage_buffer(
        device,
        "tests.predicates.trait_ref.owner",
        &vec![INVALID; NODES],
    );
    let subject = storage_buffer(
        device,
        "tests.predicates.trait_ref.subject",
        &vec![INVALID; NODES],
    );
    let bound = storage_buffer(
        device,
        "tests.predicates.trait_ref.bound",
        &vec![INVALID; NODES],
    );
    let arg_count = storage_buffer(
        device,
        "tests.predicates.trait_ref.arg_count",
        &vec![0; NODES],
    );
    let first_arg = storage_buffer(
        device,
        "tests.predicates.trait_ref.first_arg",
        &vec![INVALID; NODES],
    );
    let second_arg = storage_buffer(
        device,
        "tests.predicates.trait_ref.second_arg",
        &vec![INVALID; NODES],
    );
    let status = storage_buffer(
        device,
        "tests.predicates.trait_ref.status",
        &vec![INVALID; NODES],
    );

    let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("hir_status".into(), hir_status.as_entire_binding()),
        ("node_kind".into(), node_kind.as_entire_binding()),
        ("parent".into(), parent.as_entire_binding()),
        ("first_child".into(), first_child.as_entire_binding()),
        ("subtree_end".into(), subtree_end.as_entire_binding()),
        ("hir_token_pos".into(), hir_token_pos.as_entire_binding()),
        (
            "hir_type_len_value".into(),
            hir_type_len_value.as_entire_binding(),
        ),
        ("hir_item_kind".into(), hir_item_kind.as_entire_binding()),
        (
            "name_id_by_token".into(),
            name_id_by_token.as_entire_binding(),
        ),
        (
            "type_decl_generic_param_count_by_node".into(),
            type_decl_generic_param_count_by_node.as_entire_binding(),
        ),
        (
            "language_type_code_by_name_id".into(),
            language_type_code_by_name_id.as_entire_binding(),
        ),
        ("decl_count_out".into(), decl_count_out.as_entire_binding()),
        ("decl_name_id".into(), decl_name_id.as_entire_binding()),
        ("decl_kind".into(), decl_kind.as_entire_binding()),
        ("decl_namespace".into(), decl_namespace.as_entire_binding()),
        ("decl_hir_node".into(), decl_hir_node.as_entire_binding()),
        (
            "module_count_out".into(),
            module_count_out.as_entire_binding(),
        ),
        (
            "sorted_module_key_order".into(),
            sorted_module_key_order.as_entire_binding(),
        ),
        (
            "module_key_segment_count".into(),
            module_key_segment_count.as_entire_binding(),
        ),
        (
            "module_key_segment_base".into(),
            module_key_segment_base.as_entire_binding(),
        ),
        (
            "module_key_segment_name_id".into(),
            module_key_segment_name_id.as_entire_binding(),
        ),
        (
            "decl_type_key_count_out".into(),
            decl_type_key_count_out.as_entire_binding(),
        ),
        (
            "decl_type_key_to_decl_id".into(),
            decl_type_key_to_decl_id.as_entire_binding(),
        ),
        ("decl_module_id".into(), decl_module_id.as_entire_binding()),
        ("predicate_owner_node".into(), owner.as_entire_binding()),
        (
            "predicate_subject_token".into(),
            subject.as_entire_binding(),
        ),
        ("predicate_bound_token".into(), bound.as_entire_binding()),
        (
            "predicate_bound_arg_count".into(),
            arg_count.as_entire_binding(),
        ),
        (
            "predicate_bound_first_arg_token".into(),
            first_arg.as_entire_binding(),
        ),
        (
            "predicate_bound_second_arg_token".into(),
            second_arg.as_entire_binding(),
        ),
        ("predicate_status".into(), status.as_entire_binding()),
    ]);
    let bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("tests.type_checker.predicates.trait_ref_collect"),
        &pass.bind_group_layouts[0],
        &pass.reflection,
        0,
        &resources,
    )
    .expect("create reference trait impl predicate collect bind group");

    let owner_rb = readback_buffer(device, "tests.predicates.trait_ref.owner.rb", NODES);
    let subject_rb = readback_buffer(device, "tests.predicates.trait_ref.subject.rb", NODES);
    let bound_rb = readback_buffer(device, "tests.predicates.trait_ref.bound.rb", NODES);
    let arg_count_rb = readback_buffer(device, "tests.predicates.trait_ref.arg_count.rb", NODES);
    let first_arg_rb = readback_buffer(device, "tests.predicates.trait_ref.first_arg.rb", NODES);
    let second_arg_rb = readback_buffer(device, "tests.predicates.trait_ref.second_arg.rb", NODES);
    let status_rb = readback_buffer(device, "tests.predicates.trait_ref.status.rb", NODES);

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("tests.type_checker.predicates.trait_ref.encoder"),
    });
    {
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("tests.type_checker.predicates.trait_ref.pass"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, &bind_group, &[]);
        compute.dispatch_workgroups(1, 1, 1);
    }
    for (src, dst) in [
        (&owner, &owner_rb),
        (&subject, &subject_rb),
        (&bound, &bound_rb),
        (&arg_count, &arg_count_rb),
        (&first_arg, &first_arg_rb),
        (&second_arg, &second_arg_rb),
        (&status, &status_rb),
    ] {
        encoder.copy_buffer_to_buffer(src, 0, dst, 0, (NODES * 4) as u64);
    }
    queue.submit(Some(encoder.finish()));

    PredicateSnapshot {
        owner: read_u32s(device, &owner_rb, NODES),
        subject: read_u32s(device, &subject_rb, NODES),
        bound: read_u32s(device, &bound_rb, NODES),
        arg_count: read_u32s(device, &arg_count_rb, NODES),
        first_arg: read_u32s(device, &first_arg_rb, NODES),
        second_arg: read_u32s(device, &second_arg_rb, NODES),
        status: read_u32s(device, &status_rb, NODES),
    }
}

fn compile_shader(root: &Path, stem: &str) -> (Vec<u8>, Vec<u8>) {
    let shader = root
        .join("shaders/type_checker")
        .join(format!("{stem}.slang"));
    let spv = common::TempArtifact::new("laniusc_predicates", stem, Some("spv"));
    let reflection = common::TempArtifact::new("laniusc_predicates", stem, Some("reflect.json"));
    let output = Command::new(slangc_command())
        .arg("-target")
        .arg("spirv")
        .arg("-profile")
        .arg("glsl_450")
        .arg("-fvk-use-entrypoint-name")
        .arg("-reflection-json")
        .arg(reflection.path())
        .arg("-emit-spirv-directly")
        .arg("-O1")
        .arg("-I")
        .arg(root.join("shaders"))
        .arg("-I")
        .arg(root.join("shaders/type_checker"))
        .arg("-I")
        .arg(root.join("shaders/parser"))
        .arg("-o")
        .arg(spv.path())
        .arg(&shader)
        .output()
        .unwrap_or_else(|err| panic!("run slangc for {}: {err}", shader.display()));
    common::assert_command_success(format!("compile {stem}"), &output);
    (
        fs::read(spv.path()).unwrap_or_else(|err| panic!("read {}: {err}", spv.path().display())),
        fs::read(reflection.path())
            .unwrap_or_else(|err| panic!("read {}: {err}", reflection.path().display())),
    )
}

fn slangc_command() -> PathBuf {
    env::var_os("SLANGC")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("slangc"))
}

fn uniform_words(device: &wgpu::Device, label: &str, words: &[u32]) -> wgpu::Buffer {
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &u32_bytes(words),
        usage: wgpu::BufferUsages::UNIFORM,
    })
}

fn storage_buffer(device: &wgpu::Device, label: &str, words: &[u32]) -> wgpu::Buffer {
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &u32_bytes(words),
        usage: wgpu::BufferUsages::STORAGE
            | wgpu::BufferUsages::COPY_DST
            | wgpu::BufferUsages::COPY_SRC,
    })
}

fn readback_buffer(device: &wgpu::Device, label: &str, count: usize) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: (count * 4) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    })
}

fn read_u32s(device: &wgpu::Device, buffer: &wgpu::Buffer, count: usize) -> Vec<u32> {
    let slice = buffer.slice(..);
    let (tx, rx) = mpsc::channel();
    slice.map_async(wgpu::MapMode::Read, move |result| {
        tx.send(result).expect("send map result");
    });
    device
        .poll(wgpu::PollType::wait_indefinitely())
        .expect("poll readback");
    rx.recv()
        .expect("receive map result")
        .expect("map readback");
    let data = slice.get_mapped_range();
    let words = data[..count * 4]
        .chunks_exact(4)
        .map(|bytes| u32::from_le_bytes(bytes.try_into().expect("u32 bytes")))
        .collect::<Vec<_>>();
    drop(data);
    buffer.unmap();
    words
}

fn leak_bytes(bytes: Vec<u8>) -> &'static [u8] {
    Box::leak(bytes.into_boxed_slice())
}

fn u32_bytes(words: &[u32]) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(words.len() * 4);
    for word in words {
        bytes.extend_from_slice(&word.to_le_bytes());
    }
    bytes
}
