use super::support::{assert_contains_all, assert_contains_none, repo_file};

#[test]
fn high_volume_codegen_emitters_are_dispatch_indexed() {
    for (label, source, required) in [
        (
            "wasm_module.slang",
            repo_file("shaders/codegen/wasm_module.slang"),
            "uint word_i = linear_dispatch_id(tid);",
        ),
        (
            "pack_output.slang",
            repo_file("shaders/codegen/pack_output.slang"),
            "uint word_i = linear_dispatch_id(tid);",
        ),
        (
            "x86_text_offsets.slang",
            repo_file("shaders/codegen/x86_text_offsets.slang"),
            "uint inst_i = linear_dispatch_id(tid);",
        ),
        (
            "x86_encode.slang",
            repo_file("shaders/codegen/x86_encode.slang"),
            "uint word_i = linear_dispatch_id(tid);",
        ),
        (
            "x86_elf_write.slang",
            repo_file("shaders/codegen/x86_elf_write.slang"),
            "uint word_i = linear_dispatch_id(tid);",
        ),
    ] {
        assert!(
            source.contains(required),
            "{label} should assign output ownership from the dispatch id"
        );
        assert!(
            !source.contains("if (tid.x != 0u)"),
            "{label} should not be a one-lane emitter"
        );
    }
}

#[test]
fn x86_instruction_pipeline_keeps_selection_separate_from_encoding() {
    let inst_plan = repo_file("shaders/codegen/x86_inst_plan.slang");
    let select = repo_file("shaders/codegen/x86_select.slang");
    let encode = repo_file("shaders/codegen/x86_encode.slang");

    assert_contains_all(
        &inst_plan,
        "x86_inst_plan.slang",
        &[
            "RWStructuredBuffer<uint> x86_select_plan",
            "StructuredBuffer<uint> x86_entry_inst_status",
            "StructuredBuffer<uint> x86_func_return_inst_status",
        ],
    );
    assert_contains_none(
        &inst_plan,
        "x86_inst_plan.slang",
        &[
            "RWStructuredBuffer<uint> x86_planned_inst_kind",
            "RWStructuredBuffer<uint> x86_planned_inst_arg0",
            "X86_INST_CALL_REL32",
            "X86_INST_RET",
            "write_direct_call_template",
            "write_function_return_template",
        ],
    );
    assert_contains_all(
        &select,
        "x86_select.slang",
        &[
            "StructuredBuffer<uint> x86_select_plan",
            "StructuredBuffer<uint4> x86_virtual_inst_record",
            "StructuredBuffer<uint> x86_virtual_phys_reg",
            "StructuredBuffer<uint> x86_virtual_regalloc_status",
            "StructuredBuffer<uint> x86_planned_inst_kind",
            "RWStructuredBuffer<uint> x86_inst_kind",
            "RWStructuredBuffer<uint> x86_inst_arg1",
            "RWStructuredBuffer<uint> x86_inst_arg2",
        ],
    );
    assert_contains_none(&select, "x86_select.slang", &["le32_byte", "modrm(", "0x"]);
    assert_contains_all(
        &encode,
        "x86_encode.slang",
        &[
            "StructuredBuffer<uint> x86_inst_kind",
            "StructuredBuffer<uint> x86_inst_byte_offset",
            "RWStructuredBuffer<uint> x86_text_words",
        ],
    );
}
