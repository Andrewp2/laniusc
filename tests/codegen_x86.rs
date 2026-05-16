mod common;

use std::path::Path;

use laniusc::compiler::{
    CompileError,
    compile_explicit_source_pack_paths_to_x86_64_with_gpu_codegen,
    compile_source_pack_to_x86_64_with_gpu_codegen,
    compile_source_to_x86_64_with_gpu_codegen,
    compile_source_to_x86_64_with_gpu_codegen_from_path,
};

#[test]
fn x86_compiler_route_uses_direct_hir_elf_backend() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let compiler = include_str!("../src/compiler.rs");
    let codegen_mod = include_str!("../src/codegen/mod.rs");
    let x86_backend = [
        include_str!("../src/codegen/x86.rs"),
        include_str!("../src/codegen/x86/record.rs"),
        include_str!("../src/codegen/x86/record_init.rs"),
        include_str!("../src/codegen/x86/record_retained_expr.rs"),
        include_str!("../src/codegen/x86/support.rs"),
        include_str!("../src/codegen/x86/finish.rs"),
    ]
    .join("\n");
    let x86_shaders = [
        (
            "x86_node_tree_info.slang",
            include_str!("../shaders/codegen/x86_node_tree_info.slang"),
        ),
        (
            "x86_func_discover.slang",
            include_str!("../shaders/codegen/x86_func_discover.slang"),
        ),
        (
            "x86_call_records.slang",
            include_str!("../shaders/codegen/x86_call_records.slang"),
        ),
        (
            "x86_intrinsic_calls.slang",
            include_str!("../shaders/codegen/x86_intrinsic_calls.slang"),
        ),
        (
            "x86_const_values.slang",
            include_str!("../shaders/codegen/x86_const_values.slang"),
        ),
        (
            "x86_local_literals.slang",
            include_str!("../shaders/codegen/x86_local_literals.slang"),
        ),
        (
            "x86_call_abi.slang",
            include_str!("../shaders/codegen/x86_call_abi.slang"),
        ),
        (
            "x86_func_body_plan.slang",
            include_str!("../shaders/codegen/x86_func_body_plan.slang"),
        ),
        (
            "x86_node_inst_counts.slang",
            include_str!("../shaders/codegen/x86_node_inst_counts.slang"),
        ),
        (
            "x86_node_inst_order.slang",
            include_str!("../shaders/codegen/x86_node_inst_order.slang"),
        ),
        (
            "x86_node_inst_scan_local.slang",
            include_str!("../shaders/codegen/x86_node_inst_scan_local.slang"),
        ),
        (
            "x86_node_inst_scan_blocks.slang",
            include_str!("../shaders/codegen/x86_node_inst_scan_blocks.slang"),
        ),
        (
            "x86_node_inst_prefix_scan.slang",
            include_str!("../shaders/codegen/x86_node_inst_prefix_scan.slang"),
        ),
        (
            "x86_node_inst_locations.slang",
            include_str!("../shaders/codegen/x86_node_inst_locations.slang"),
        ),
        (
            "x86_node_inst_gen.slang",
            include_str!("../shaders/codegen/x86_node_inst_gen.slang"),
        ),
        (
            "x86_virtual_use_edges.slang",
            include_str!("../shaders/codegen/x86_virtual_use_edges.slang"),
        ),
        (
            "x86_virtual_liveness.slang",
            include_str!("../shaders/codegen/x86_virtual_liveness.slang"),
        ),
        (
            "x86_virtual_regalloc.slang",
            include_str!("../shaders/codegen/x86_virtual_regalloc.slang"),
        ),
        (
            "x86_lower_values.slang",
            include_str!("../shaders/codegen/x86_lower_values.slang"),
        ),
        (
            "x86_func_inst_counts.slang",
            include_str!("../shaders/codegen/x86_func_inst_counts.slang"),
        ),
        (
            "x86_func_layout.slang",
            include_str!("../shaders/codegen/x86_func_layout.slang"),
        ),
        (
            "x86_func_return_inst_plan.slang",
            include_str!("../shaders/codegen/x86_func_return_inst_plan.slang"),
        ),
        (
            "x86_entry_inst_plan.slang",
            include_str!("../shaders/codegen/x86_entry_inst_plan.slang"),
        ),
        (
            "x86_inst_plan.slang",
            include_str!("../shaders/codegen/x86_inst_plan.slang"),
        ),
        (
            "x86_reloc_plan.slang",
            include_str!("../shaders/codegen/x86_reloc_plan.slang"),
        ),
        (
            "x86_select.slang",
            include_str!("../shaders/codegen/x86_select.slang"),
        ),
        (
            "x86_inst_size.slang",
            include_str!("../shaders/codegen/x86_inst_size.slang"),
        ),
        (
            "x86_text_offsets.slang",
            include_str!("../shaders/codegen/x86_text_offsets.slang"),
        ),
        (
            "x86_encode.slang",
            include_str!("../shaders/codegen/x86_encode.slang"),
        ),
        (
            "x86_reloc_patch.slang",
            include_str!("../shaders/codegen/x86_reloc_patch.slang"),
        ),
        (
            "x86_elf_layout.slang",
            include_str!("../shaders/codegen/x86_elf_layout.slang"),
        ),
        (
            "x86_elf_write.slang",
            include_str!("../shaders/codegen/x86_elf_write.slang"),
        ),
    ];
    let plan = include_str!("../docs/X86_64_GPU_BACKEND_PLAN.md");

    assert!(compiler.contains("codegen::{wasm, x86}"));
    assert!(compiler.contains("record_x86_elf_from_gpu_hir"));
    assert!(compiler.contains("with_recorded_resident_source_pack_tokens"));
    assert!(!compiler.contains("record_x86_from_gpu_token_buffer"));
    assert!(codegen_mod.contains("pub mod x86;"));
    assert!(root.join("src/codegen/x86.rs").exists());
    assert!(root.join("src/codegen/x86/record.rs").exists());
    assert!(!root.join("src/codegen/gpu_x86.rs").exists());
    assert!(!root.join("shaders/codegen/x86_from_wasm.slang").exists());

    for shader_name in [
        "x86_node_tree_info",
        "x86_func_discover",
        "x86_call_records",
        "x86_const_values",
        "x86_param_regs",
        "x86_local_literals",
        "x86_func_return_stmts",
        "x86_block_return_stmts",
        "x86_terminal_ifs",
        "x86_return_calls",
        "x86_call_arg_values",
        "x86_call_arg_lookup",
        "x86_intrinsic_calls",
        "x86_call_abi",
        "x86_call_arg_widths",
        "x86_call_arg_prefix_seed",
        "x86_call_arg_prefix_scan",
        "x86_call_arg_vregs",
        "x86_node_inst_counts",
        "x86_node_inst_order",
        "x86_node_inst_scan_local",
        "x86_node_inst_scan_blocks",
        "x86_node_inst_prefix_scan",
        "x86_node_inst_locations",
        "x86_node_inst_gen",
        "x86_virtual_use_edges",
        "x86_virtual_liveness",
        "x86_virtual_regalloc",
        "x86_func_body_plan",
        "x86_lower_values",
        "x86_use_edges",
        "x86_liveness",
        "x86_regalloc",
        "x86_func_inst_counts",
        "x86_func_inst_order",
        "x86_func_inst_scan_local",
        "x86_func_inst_scan_blocks",
        "x86_func_inst_prefix_scan",
        "x86_func_layout",
        "x86_func_return_inst_plan",
        "x86_entry_inst_plan",
        "x86_inst_plan",
        "x86_reloc_plan",
        "x86_select",
        "x86_inst_size",
        "x86_text_offsets",
        "x86_encode",
        "x86_reloc_patch",
        "x86_elf_layout",
        "x86_elf_write",
    ] {
        assert!(
            root.join(format!("shaders/codegen/{shader_name}.slang"))
                .exists(),
            "missing x86 shader source {shader_name}"
        );
        assert!(
            x86_backend.contains(&format!("{shader_name}.spv")),
            "x86 backend should dispatch {shader_name}.spv"
        );
    }

    let backend_surfaces = std::iter::once(("src/codegen/x86/*.rs", x86_backend.as_str()))
        .chain(x86_shaders.iter().copied());
    for (label, source) in backend_surfaces {
        for forbidden in [
            "core::i32",
            "core::u32",
            "core::u8",
            "core::bool",
            "is_ascii_digit",
            "is_ascii_lowercase",
            "between_inclusive",
            "saturating_abs",
            "ByteAddressBuffer",
            "source_bytes",
            "source_at",
            "token_kind",
            "TokenKind",
            "token_text",
            "hir_token_pos",
            "hir_token_end",
            "PROD_",
            "TK_",
        ] {
            assert!(
                !source.contains(forbidden),
                "{label} should not inspect source/token spelling or stdlib helper names via {forbidden:?}"
            );
        }
    }

    for required in [
        "record_x86_elf_from_gpu_hir",
        "GpuX86CallMetadataBuffers",
        "node_tree_info_pass",
        "node_inst_counts_pass",
        "node_inst_order_pass",
        "node_inst_prefix_scan_pass",
        "node_inst_locations_pass",
        "node_inst_gen_pass",
        "virtual_use_edges_pass",
        "virtual_liveness_pass",
        "virtual_regalloc_pass",
        "func_inst_counts_pass",
        "func_layout_pass",
        "func_return_inst_plan_pass",
        "entry_inst_plan_pass",
        "reloc_plan_pass",
        "x86_elf_write.spv",
    ] {
        assert!(
            x86_backend.contains(required),
            "missing backend route marker {required}"
        );
    }

    let shader_contracts = [
        (
            "x86_node_tree_info.slang",
            [
                "StructuredBuffer<uint> parent",
                "StructuredBuffer<uint> first_child",
                "StructuredBuffer<uint> next_sibling",
                "StructuredBuffer<uint> subtree_end",
                "RWStructuredBuffer<uint4> x86_node_tree_record",
            ]
            .as_slice(),
        ),
        (
            "x86_func_discover.slang",
            [
                "StructuredBuffer<uint4> x86_node_tree_record",
                "RWStructuredBuffer<uint4> x86_func_record",
                "RWStructuredBuffer<uint> x86_func_lookup_key",
                "StructuredBuffer<uint> hir_item_decl_token",
            ]
            .as_slice(),
        ),
        (
            "x86_node_inst_counts.slang",
            [
                "StructuredBuffer<uint4> x86_node_tree_record",
                "StructuredBuffer<uint> hir_stmt_record",
                "StructuredBuffer<uint> hir_expr_record",
                "RWStructuredBuffer<uint4> x86_node_inst_count_record",
                "RWStructuredBuffer<uint> x86_node_inst_scan_input",
            ]
            .as_slice(),
        ),
        (
            "x86_node_inst_order.slang",
            [
                "StructuredBuffer<uint4> x86_node_tree_record",
                "StructuredBuffer<uint4> x86_node_inst_count_record",
                "RWStructuredBuffer<uint4> x86_node_inst_order_record",
                "RWStructuredBuffer<uint> x86_node_inst_scan_input",
            ]
            .as_slice(),
        ),
        (
            "x86_node_inst_prefix_scan.slang",
            [
                "StructuredBuffer<uint4> x86_node_inst_order_record",
                "StructuredBuffer<uint> x86_node_inst_scan_local_prefix",
                "RWStructuredBuffer<uint4> x86_node_inst_range_record",
            ]
            .as_slice(),
        ),
        (
            "x86_node_inst_locations.slang",
            [
                "StructuredBuffer<uint> hir_kind",
                "StructuredBuffer<uint> hir_stmt_record",
                "StructuredBuffer<uint4> x86_node_inst_count_record",
                "StructuredBuffer<uint4> x86_node_inst_range_record",
                "RWStructuredBuffer<uint4> x86_node_inst_location_record",
            ]
            .as_slice(),
        ),
        (
            "x86_node_inst_gen.slang",
            [
                "StructuredBuffer<uint4> x86_node_inst_range_record",
                "StructuredBuffer<uint4> x86_node_inst_location_record",
                "StructuredBuffer<uint> hir_stmt_record",
                "StructuredBuffer<uint> hir_expr_record",
                "RWStructuredBuffer<uint4> x86_virtual_inst_record",
                "RWStructuredBuffer<uint4> x86_node_value_record",
            ]
            .as_slice(),
        ),
        (
            "x86_virtual_use_edges.slang",
            [
                "StructuredBuffer<uint4> x86_virtual_inst_record",
                "StructuredBuffer<uint4> x86_virtual_inst_args",
                "RWStructuredBuffer<uint> x86_virtual_use_key",
                "RWStructuredBuffer<uint> x86_virtual_use_value",
            ]
            .as_slice(),
        ),
        (
            "x86_virtual_liveness.slang",
            [
                "StructuredBuffer<uint> x86_virtual_use_key",
                "StructuredBuffer<uint> x86_virtual_use_value",
                "RWStructuredBuffer<uint> x86_virtual_live_start",
                "RWStructuredBuffer<uint> x86_virtual_live_end",
            ]
            .as_slice(),
        ),
        (
            "x86_virtual_regalloc.slang",
            [
                "StructuredBuffer<uint> x86_virtual_live_start",
                "StructuredBuffer<uint> x86_virtual_live_end",
                "RWStructuredBuffer<uint> x86_virtual_phys_reg",
            ]
            .as_slice(),
        ),
        (
            "x86_call_records.slang",
            [
                "StructuredBuffer<uint> hir_call_callee_node",
                "RWStructuredBuffer<uint4> x86_call_record",
            ]
            .as_slice(),
        ),
        (
            "x86_intrinsic_calls.slang",
            [
                "StructuredBuffer<uint> call_intrinsic_tag",
                "StructuredBuffer<uint4> x86_call_record",
                "StructuredBuffer<uint4> x86_call_arg_lookup_record",
                "RWStructuredBuffer<uint4> x86_intrinsic_call_record",
            ]
            .as_slice(),
        ),
        (
            "x86_local_literals.slang",
            [
                "StructuredBuffer<uint> visible_decl",
                "StructuredBuffer<uint4> x86_const_value_record",
                "RWStructuredBuffer<uint4> x86_local_literal_record",
            ]
            .as_slice(),
        ),
        (
            "x86_call_abi.slang",
            [
                "StructuredBuffer<uint> call_intrinsic_tag",
                "StructuredBuffer<uint4> x86_call_arg_lookup_record",
                "RWStructuredBuffer<uint4> x86_call_abi_record",
            ]
            .as_slice(),
        ),
        (
            "x86_func_inst_counts.slang",
            [
                "StructuredBuffer<uint> hir_stmt_record",
                "StructuredBuffer<uint4> x86_intrinsic_call_record",
                "StructuredBuffer<uint4> x86_call_abi_record",
                "X86_INTRINSIC_TEXT_WRITE",
                "RWStructuredBuffer<uint4> x86_func_inst_count_record",
            ]
            .as_slice(),
        ),
        (
            "x86_func_return_inst_plan.slang",
            [
                "StructuredBuffer<uint4> x86_func_layout_record",
                "StructuredBuffer<uint4> x86_call_arg_eval_record",
                "RWStructuredBuffer<uint> x86_planned_inst_kind",
            ]
            .as_slice(),
        ),
        (
            "x86_entry_inst_plan.slang",
            [
                "StructuredBuffer<uint> hir_stmt_record",
                "StructuredBuffer<uint4> x86_intrinsic_call_record",
                "StructuredBuffer<uint4> x86_call_abi_record",
                "StructuredBuffer<uint4> x86_call_arg_eval_record",
                "X86_ENTRY_STATUS_RELOC_COUNT",
                "X86_INST_DATA_I32_NL",
                "RWStructuredBuffer<uint> x86_planned_inst_kind",
            ]
            .as_slice(),
        ),
        (
            "x86_reloc_plan.slang",
            [
                "StructuredBuffer<uint> hir_stmt_record",
                "StructuredBuffer<uint4> x86_intrinsic_call_record",
                "X86_ENTRY_STATUS_RELOC_COUNT",
                "StructuredBuffer<uint4> x86_func_layout_record",
                "RWStructuredBuffer<uint> x86_planned_reloc_kind",
            ]
            .as_slice(),
        ),
        (
            "x86_encode.slang",
            [
                "StructuredBuffer<uint> x86_inst_byte_offset",
                "RWStructuredBuffer<uint> x86_text_words",
            ]
            .as_slice(),
        ),
        (
            "x86_elf_write.slang",
            [
                "StructuredBuffer<uint> x86_text_words",
                "RWStructuredBuffer<uint> out_words",
            ]
            .as_slice(),
        ),
    ];
    for (label, required_terms) in shader_contracts {
        let source = x86_shaders
            .iter()
            .find_map(|(shader_label, shader_source)| {
                (*shader_label == label).then_some(*shader_source)
            })
            .expect("shader contract source should be listed");
        for required in required_terms {
            assert!(
                source.contains(required),
                "{label} missing stable contract term {required}"
            );
        }
    }

    let x86_api_tail = x86_backend
        .split("pub fn record_x86_elf_from_gpu_hir(")
        .nth(1)
        .expect("x86 backend API should be present");
    let x86_api_signature = x86_api_tail
        .split(") -> Result<RecordedX86Codegen>")
        .next()
        .expect("x86 backend API signature should be parseable");
    assert!(!x86_api_signature.contains("token_buf"));
    assert!(!x86_api_signature.contains("hir_token_pos_buf"));
    assert!(!x86_api_signature.contains("hir_token_end_buf"));
    for (offset, _) in compiler.match_indices("record_x86_elf_from_gpu_hir(") {
        let end = (offset + 1600).min(compiler.len());
        let call_site = &compiler[offset..end];
        assert!(!call_site.contains("&bufs.tokens_out"));
        assert!(!call_site.contains("&parse_bufs.hir_token_pos"));
        assert!(!call_site.contains("&parse_bufs.hir_token_end"));
    }

    assert!(plan.contains("The prior WASM-to-x86 prototype has been deleted"));
    assert!(plan.contains("direct HIR lowering"));
    assert!(plan.contains("source-pack x86 entrypoints"));
}

#[test]
fn x86_path_codegen_reports_missing_input_before_codegen() {
    let missing = common::temp_artifact_path("laniusc_missing_x86", "input", Some("lani"));
    if let Err(err) = std::fs::remove_file(&missing) {
        log::warn!(
            "failed to remove stale missing-input artifact {}: {err}",
            missing.display()
        );
    }

    let err = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen_from_path(
        &missing,
    ))
    .expect_err("missing x86 input should fail while preparing source");

    let message = err.to_string();
    match err {
        CompileError::GpuFrontend(_) => {}
        other => panic!("expected GPU frontend read error, got {other:?}: {message}"),
    }
    assert!(
        message.contains("read") && message.contains(&missing.display().to_string()),
        "missing input error should name the unreadable path: {message}"
    );
    assert!(
        !message.contains("GPU x86_64 codegen is not currently available"),
        "missing input should not be reported as backend codegen failure: {message}"
    );
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_integer_literal_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    return 7;\n}\n",
    ))
    .expect("x86 codegen should emit direct ELF bytes for the first HIR slice");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(bytes[4], 2, "ELF64 class");
    assert_eq!(bytes[5], 1, "little-endian ELF");
    assert_eq!(u16::from_le_bytes(bytes[18..20].try_into().unwrap()), 62);
    assert_eq!(
        u64::from_le_bytes(bytes[24..32].try_into().unwrap()),
        0x400078
    );
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(bytes[0x7d], 0xbf);
    assert_eq!(&bytes[0x7e..0x82], &7u32.to_le_bytes());
    assert_eq!(&bytes[0x82..0x84], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_zero_arg_direct_call_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn value() -> i32 {\n    return 7;\n}\nfn main() {\n    return value();\n}\n",
    ))
    .expect("x86 codegen should emit a direct call using backend call ABI records");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(
        u64::from_le_bytes(bytes[24..32].try_into().unwrap()),
        0x400078
    );
    assert_eq!(bytes[0x78], 0xe8, "main should start with call rel32");
    assert_eq!(&bytes[0x79..0x7d], &9u32.to_le_bytes());
    assert_eq!(&bytes[0x7d..0x7f], &[0x89, 0xc7]);
    assert_eq!(&bytes[0x7f..0x84], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x84..0x86], &[0x0f, 0x05]);
    assert_eq!(bytes[0x86], 0xb8);
    assert_eq!(&bytes[0x87..0x8b], &7u32.to_le_bytes());
    assert_eq!(bytes[0x8b], 0xc3);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_one_literal_arg_direct_call_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn value(x: i32) -> i32 {\n    return 9;\n}\nfn main() {\n    return value(7);\n}\n",
    ))
    .expect("x86 codegen should pass a literal SysV integer arg before a direct call");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(
        u64::from_le_bytes(bytes[24..32].try_into().unwrap()),
        0x400078
    );
    assert_eq!(bytes[0x78], 0xbf, "main should load arg0 into edi");
    assert_eq!(&bytes[0x79..0x7d], &7u32.to_le_bytes());
    assert_eq!(bytes[0x7d], 0xe8, "main should call rel32 after arg setup");
    assert_eq!(&bytes[0x7e..0x82], &9u32.to_le_bytes());
    assert_eq!(&bytes[0x82..0x84], &[0x89, 0xc7]);
    assert_eq!(&bytes[0x84..0x89], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x89..0x8b], &[0x0f, 0x05]);
    assert_eq!(bytes[0x8b], 0xb8);
    assert_eq!(&bytes[0x8c..0x90], &9u32.to_le_bytes());
    assert_eq!(bytes[0x90], 0xc3);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_one_arg_param_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn id(x: i32) -> i32 {\n    return x;\n}\nfn main() {\n    return id(7);\n}\n",
    ))
    .expect("x86 codegen should lower a direct call whose callee returns its first parameter");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(
        u64::from_le_bytes(bytes[24..32].try_into().unwrap()),
        0x400078
    );
    assert_eq!(bytes[0x78], 0xbf, "main should load arg0 into edi");
    assert_eq!(&bytes[0x79..0x7d], &7u32.to_le_bytes());
    assert_eq!(bytes[0x7d], 0xe8, "main should call rel32 after arg setup");
    assert_eq!(&bytes[0x7e..0x82], &9u32.to_le_bytes());
    assert_eq!(&bytes[0x82..0x84], &[0x89, 0xc7]);
    assert_eq!(&bytes[0x84..0x89], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x89..0x8b], &[0x0f, 0x05]);
    assert_eq!(&bytes[0x8b..0x8d], &[0x89, 0xf8]);
    assert_eq!(bytes[0x8d], 0xc3);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_local_call_arg_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn id(x: i32) -> i32 {\n    return x;\n}\nfn main() {\n    let value: i32 = 7;\n    return id(value);\n}\n",
    ))
    .expect("x86 codegen should lower a local scalar call argument through call-arg value records");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(bytes[0x78], 0xbf, "main should load arg0 into edi");
    assert_eq!(&bytes[0x79..0x7d], &7u32.to_le_bytes());
    assert_eq!(bytes[0x7d], 0xe8, "main should call rel32 after arg setup");
    assert_eq!(&bytes[0x8b..0x8d], &[0x89, 0xf8]);
    assert_eq!(bytes[0x8d], 0xc3);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_binary_call_arg_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn id(x: i32) -> i32 {\n    return x;\n}\nfn main() {\n    return id(4 + 5);\n}\n",
    ))
    .expect(
        "x86 codegen should lower a scalar binary call argument through call-arg value records",
    );

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(bytes[0x78], 0xb8, "main should evaluate arg left into eax");
    assert_eq!(&bytes[0x79..0x7d], &4u32.to_le_bytes());
    assert_eq!(
        bytes[0x7d], 0x05,
        "main should evaluate binary arg before call"
    );
    assert_eq!(&bytes[0x7e..0x82], &5u32.to_le_bytes());
    assert_eq!(
        &bytes[0x82..0x84],
        &[0x89, 0xc7],
        "main should move arg vreg result into edi"
    );
    assert_eq!(bytes[0x84], 0xe8, "main should call rel32 after arg setup");
    assert_eq!(&bytes[0x85..0x89], &9u32.to_le_bytes());
    assert_eq!(&bytes[0x92..0x94], &[0x89, 0xf8]);
    assert_eq!(bytes[0x94], 0xc3);
}

#[test]
fn x86_source_codegen_executes_intrinsic_output_for_hir_constant_locals() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    let a: i32 = 1 + 2 * 3;\n    let b: i32 = (1 + 2) * 3;\n    print(a);\n    print(b);\n    return 0;\n}\n",
    ))
    .expect("x86 codegen should emit semantic intrinsic output rows from HIR values");

    assert_eq!(&bytes[0..4], b"\x7fELF");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let stdout = common::run_x86_64_elf(
            "x86 intrinsic output for constant locals",
            "x86_intrinsic_output_constant_locals",
            &bytes,
        );
        assert_eq!(stdout, "7\n9\n");
    }
}

#[test]
fn x86_source_codegen_executes_intrinsic_output_for_chained_local_constants() {
    let source = "fn main() {\n    let x: i32 = (6 & 3) | (8 ^ 2);\n    let y: i32 = x << 1 >> 2;\n    print(y);\n    return 0;\n}\n";
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 intrinsic output for chained local constants",
        move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(source)),
    )
    .expect("x86 codegen should resolve chained local constants through HIR records");

    assert_eq!(&bytes[0..4], b"\x7fELF");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let stdout = common::run_x86_64_elf(
            "x86 intrinsic output for chained local constants",
            "x86_intrinsic_output_chained_local_constants",
            &bytes,
        );
        assert_eq!(stdout, "5\n");
    }
}

#[test]
fn x86_source_codegen_executes_hir_if_intrinsic_output_once_per_taken_branch() {
    let source = "fn main() {\n    let alpha_value: i32 = 7;\n    let beta_value: i32 = 3;\n    if (alpha_value >= beta_value) {\n        print(10);\n    } else {\n        print(11);\n    }\n    if ((alpha_value == beta_value) || false) {\n        print(20);\n    } else {\n        print(21);\n    }\n    if (beta_value < alpha_value) {\n        print(30);\n    }\n    return 0;\n}\n";
    let bytes = common::run_gpu_codegen_with_timeout("x86 HIR if intrinsic output", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(source))
    })
    .expect(
        "x86 codegen should lower HIR if statement intrinsic output without printing both arms",
    );

    assert_eq!(&bytes[0..4], b"\x7fELF");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let stdout = common::run_x86_64_elf(
            "x86 HIR if intrinsic output",
            "x86_hir_if_intrinsic_output",
            &bytes,
        );
        assert_eq!(stdout, "10\n21\n30\n");
    }
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_one_arg_param_add_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn inc(x: i32) -> i32 {\n    return x + 1;\n}\nfn main() {\n    return inc(7);\n}\n",
    ))
    .expect("x86 codegen should lower a direct call whose callee returns param plus literal");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(
        u64::from_le_bytes(bytes[24..32].try_into().unwrap()),
        0x400078
    );
    assert_eq!(bytes[0x78], 0xbf, "main should load arg0 into edi");
    assert_eq!(&bytes[0x79..0x7d], &7u32.to_le_bytes());
    assert_eq!(bytes[0x7d], 0xe8, "main should call rel32 after arg setup");
    assert_eq!(&bytes[0x7e..0x82], &9u32.to_le_bytes());
    assert_eq!(&bytes[0x82..0x84], &[0x89, 0xc7]);
    assert_eq!(&bytes[0x84..0x89], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x89..0x8b], &[0x0f, 0x05]);
    assert_eq!(&bytes[0x8b..0x8d], &[0x89, 0xf8]);
    assert_eq!(bytes[0x8d], 0x05);
    assert_eq!(&bytes[0x8e..0x92], &1u32.to_le_bytes());
    assert_eq!(bytes[0x92], 0xc3);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_two_arg_param_add_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn add(x: i32, y: i32) -> i32 {\n    return x + y;\n}\nfn main() {\n    return add(7, 5);\n}\n",
    ))
    .expect("x86 codegen should lower a direct call whose callee adds two parameters");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(
        u64::from_le_bytes(bytes[24..32].try_into().unwrap()),
        0x400078
    );
    assert_eq!(bytes[0x78], 0xbf, "main should load arg0 into edi");
    assert_eq!(&bytes[0x79..0x7d], &7u32.to_le_bytes());
    assert_eq!(bytes[0x7d], 0xbe, "main should load arg1 into esi");
    assert_eq!(&bytes[0x7e..0x82], &5u32.to_le_bytes());
    assert_eq!(bytes[0x82], 0xe8, "main should call rel32 after arg setup");
    assert_eq!(&bytes[0x83..0x87], &9u32.to_le_bytes());
    assert_eq!(&bytes[0x87..0x89], &[0x89, 0xc7]);
    assert_eq!(&bytes[0x89..0x8e], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x8e..0x90], &[0x0f, 0x05]);
    assert_eq!(&bytes[0x90..0x92], &[0x89, 0xf8]);
    assert_eq!(&bytes[0x92..0x94], &[0x01, 0xf0]);
    assert_eq!(bytes[0x94], 0xc3);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_three_arg_third_param_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn third(x: i32, y: i32, z: i32) -> i32 {\n    return z;\n}\nfn main() {\n    return third(7, 5, 3);\n}\n",
    ))
    .expect("x86 codegen should lower the third SysV integer argument through HIR call records");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(
        u64::from_le_bytes(bytes[24..32].try_into().unwrap()),
        0x400078
    );
    assert_eq!(bytes[0x78], 0xbf, "main should load arg0 into edi");
    assert_eq!(&bytes[0x79..0x7d], &7u32.to_le_bytes());
    assert_eq!(bytes[0x7d], 0xbe, "main should load arg1 into esi");
    assert_eq!(&bytes[0x7e..0x82], &5u32.to_le_bytes());
    assert_eq!(bytes[0x82], 0xba, "main should load arg2 into edx");
    assert_eq!(&bytes[0x83..0x87], &3u32.to_le_bytes());
    assert_eq!(
        bytes[0x87], 0xe8,
        "main should call rel32 after all arg setup"
    );
    assert_eq!(&bytes[0x88..0x8c], &9u32.to_le_bytes());
    assert_eq!(&bytes[0x8c..0x8e], &[0x89, 0xc7]);
    assert_eq!(&bytes[0x8e..0x93], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x93..0x95], &[0x0f, 0x05]);
    assert_eq!(&bytes[0x95..0x97], &[0x89, 0xd0]);
    assert_eq!(bytes[0x97], 0xc3);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_two_binary_arg_param_add_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn add(x: i32, y: i32) -> i32 {\n    return x + y;\n}\nfn main() {\n    return add(4 + 5, 6 + 7);\n}\n",
    ))
    .expect("x86 codegen should assign width-based vreg ranges for two binary call args");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(
        u64::from_le_bytes(bytes[24..32].try_into().unwrap()),
        0x400078
    );
    assert_eq!(bytes[0x78], 0xb8, "arg0 left should move to eax");
    assert_eq!(&bytes[0x79..0x7d], &4u32.to_le_bytes());
    assert_eq!(bytes[0x7d], 0x05, "arg0 binary should fold in eax");
    assert_eq!(&bytes[0x7e..0x82], &5u32.to_le_bytes());
    assert_eq!(
        &bytes[0x82..0x84],
        &[0x89, 0xc7],
        "arg0 result should move to edi"
    );
    assert_eq!(bytes[0x84], 0xb8, "arg1 left should move to eax");
    assert_eq!(&bytes[0x85..0x89], &6u32.to_le_bytes());
    assert_eq!(bytes[0x89], 0x05, "arg1 binary should fold in eax");
    assert_eq!(&bytes[0x8a..0x8e], &7u32.to_le_bytes());
    assert_eq!(
        &bytes[0x8e..0x90],
        &[0x89, 0xc6],
        "arg1 result should move to esi"
    );
    assert_eq!(
        bytes[0x90], 0xe8,
        "main should call rel32 after both arg ranges"
    );
    assert_eq!(&bytes[0x91..0x95], &9u32.to_le_bytes());
    assert_eq!(&bytes[0x95..0x97], &[0x89, 0xc7]);
    assert_eq!(&bytes[0x97..0x9c], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x9c..0x9e], &[0x0f, 0x05]);
    assert_eq!(&bytes[0x9e..0xa0], &[0x89, 0xf8]);
    assert_eq!(&bytes[0xa0..0xa2], &[0x01, 0xf0]);
    assert_eq!(bytes[0xa2], 0xc3);
}

#[test]
fn x86_source_pack_codegen_emits_direct_elf_for_module_main_literal_return() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() {\n    return 5;\n}\n",
    ];
    let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        .expect("x86 source-pack codegen should emit direct ELF bytes for a bounded main return");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(bytes[0x7d], 0xbf);
    assert_eq!(&bytes[0x7e..0x82], &5u32.to_le_bytes());
    assert_eq!(&bytes[0x82..0x84], &[0x0f, 0x05]);
}

#[test]
fn x86_source_pack_codegen_emits_direct_elf_for_qualified_scalar_const_return() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() {\n    return core::i32::MAX;\n}\n",
    ];
    let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        .expect("x86 source-pack codegen should lower a resolver-backed scalar const return");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(bytes[0x7d], 0xbf);
    assert_eq!(&bytes[0x7e..0x82], &2_147_483_647u32.to_le_bytes());
    assert_eq!(&bytes[0x82..0x84], &[0x0f, 0x05]);
}

#[test]
fn x86_source_pack_codegen_emits_direct_elf_for_stdlib_min_helper_branch() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() {\n    return core::i32::min(7, 5);\n}\n",
    ];
    let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        .expect("x86 source-pack codegen should lower a resolver-backed terminal-if helper");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(bytes[0x78], 0xbf, "main should load arg0 into edi");
    assert_eq!(&bytes[0x79..0x7d], &7u32.to_le_bytes());
    assert_eq!(bytes[0x7d], 0xbe, "main should load arg1 into esi");
    assert_eq!(&bytes[0x7e..0x82], &5u32.to_le_bytes());
    assert_eq!(bytes[0x82], 0xe8, "main should call rel32 after arg setup");
    assert_eq!(&bytes[0x83..0x87], &9u32.to_le_bytes());
    assert_eq!(&bytes[0x87..0x89], &[0x89, 0xc7]);
    assert_eq!(&bytes[0x89..0x8e], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x8e..0x90], &[0x0f, 0x05]);
    assert_eq!(&bytes[0x90..0x92], &[0x89, 0xf8]);
    assert_eq!(&bytes[0x92..0x94], &[0x39, 0xf0]);
    assert_eq!(&bytes[0x94..0x9a], &[0x0f, 0x8d, 7, 0, 0, 0]);
    assert_eq!(&bytes[0x9a..0x9c], &[0x89, 0xf8]);
    assert_eq!(&bytes[0x9c..0xa1], &[0xe9, 2, 0, 0, 0]);
    assert_eq!(&bytes[0xa1..0xa3], &[0x89, 0xf0]);
    assert_eq!(bytes[0xa3], 0xc3);
}

#[test]
fn x86_source_pack_codegen_executes_core_i32_abs_helper_branch() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() {\n    return core::i32::abs(-4);\n}\n",
    ];
    let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        .expect(
        "x86 source-pack codegen should lower a resolver-backed param/immediate terminal-if helper",
    );

    assert_eq!(&bytes[0..4], b"\x7fELF");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "x86 source-pack core::i32::abs(-4)",
            "core_i32_abs",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(4));
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_i32_saturating_abs_const_call_branch() {
    let cases = [
        ("negative", "-4", 0u32.wrapping_sub(4), Some(4)),
        ("positive", "4", 4u32, Some(4)),
        ("min", "-2147483648", 0x8000_0000u32, Some(255)),
    ];

    for (name, arg_source, _arg_bits, expected_status) in cases {
        let user_source = format!(
            "module app::main;\nimport core::i32;\nfn main() {{\n    return core::i32::saturating_abs({arg_source});\n}}\n"
        );
        let sources = [
            include_str!("../stdlib/core/i32.lani"),
            user_source.as_str(),
        ];
        let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
            .unwrap_or_else(|err| {
                panic!(
                    "x86 source-pack codegen should lower core::i32::saturating_abs {name}: {err}"
                )
            });

        assert_eq!(&bytes[0..4], b"\x7fELF");

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(
                &format!("x86 source-pack core::i32::saturating_abs {name}"),
                &format!("core_i32_saturating_abs_{name}"),
                &bytes,
            );
            assert_eq!(output.status.code(), expected_status);
        }
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_i32_clamp_nested_helper_branch() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() {\n    return core::i32::clamp(9, 0, 7);\n}\n",
    ];
    let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        .expect("x86 source-pack codegen should lower a resolver-backed nested terminal-if helper");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(bytes[0x78], 0xbf, "main should load value into edi");
    assert_eq!(&bytes[0x79..0x7d], &9u32.to_le_bytes());
    assert_eq!(bytes[0x7d], 0xbe, "main should load low into esi");
    assert_eq!(&bytes[0x7e..0x82], &0u32.to_le_bytes());
    assert_eq!(bytes[0x82], 0xba, "main should load high into edx");
    assert_eq!(&bytes[0x83..0x87], &7u32.to_le_bytes());
    assert_eq!(
        bytes[0x87], 0xe8,
        "main should call rel32 after three arg setup"
    );
    assert_eq!(&bytes[0x88..0x8c], &9u32.to_le_bytes());
    assert_eq!(&bytes[0x8c..0x8e], &[0x89, 0xc7]);
    assert_eq!(&bytes[0x8e..0x93], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x93..0x95], &[0x0f, 0x05]);
    assert_eq!(&bytes[0x95..0x97], &[0x89, 0xf8]);
    assert_eq!(&bytes[0x97..0x99], &[0x39, 0xf0]);
    assert_eq!(&bytes[0x99..0x9f], &[0x0f, 0x8d, 7, 0, 0, 0]);
    assert_eq!(&bytes[0x9f..0xa1], &[0x89, 0xf0]);
    assert_eq!(&bytes[0xa1..0xa6], &[0xe9, 0x13, 0, 0, 0]);
    assert_eq!(&bytes[0xa6..0xa8], &[0x89, 0xf8]);
    assert_eq!(&bytes[0xa8..0xaa], &[0x39, 0xd0]);
    assert_eq!(&bytes[0xaa..0xb0], &[0x0f, 0x8e, 7, 0, 0, 0]);
    assert_eq!(&bytes[0xb0..0xb2], &[0x89, 0xd0]);
    assert_eq!(&bytes[0xb2..0xb7], &[0xe9, 2, 0, 0, 0]);
    assert_eq!(&bytes[0xb7..0xb9], &[0x89, 0xf8]);
    assert_eq!(bytes[0xb9], 0xc3);

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "x86 source-pack core::i32::clamp(9, 0, 7)",
            "core_i32_clamp",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(7));
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_i32_signum_nested_literal_branch() {
    let cases = [
        ("negative", "-9", 0u32.wrapping_sub(9), Some(255)),
        ("zero", "0", 0u32, Some(0)),
        ("positive", "9", 9u32, Some(1)),
    ];

    for (name, arg_source, arg_bits, expected_status) in cases {
        let user_source = format!(
            "module app::main;\nimport core::i32;\nfn main() {{\n    return core::i32::signum({arg_source});\n}}\n"
        );
        let sources = [
            include_str!("../stdlib/core/i32.lani"),
            user_source.as_str(),
        ];
        let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
            .unwrap_or_else(|err| {
                panic!("x86 source-pack codegen should lower core::i32::signum {name}: {err}")
            });

        assert_eq!(&bytes[0..4], b"\x7fELF");
        assert_eq!(bytes[0x78], 0xbf, "main should load signum arg into edi");
        assert_eq!(&bytes[0x79..0x7d], &arg_bits.to_le_bytes());
        assert_eq!(bytes[0x7d], 0xe8, "main should call rel32 after arg setup");
        assert_eq!(&bytes[0x7e..0x82], &9u32.to_le_bytes());
        assert_eq!(&bytes[0x82..0x84], &[0x89, 0xc7]);
        assert_eq!(&bytes[0x84..0x89], &[0xb8, 0x3c, 0, 0, 0]);
        assert_eq!(&bytes[0x89..0x8b], &[0x0f, 0x05]);
        assert_eq!(&bytes[0x8b..0x8d], &[0x89, 0xf8]);
        assert_eq!(&bytes[0x8d..0x92], &[0x3d, 0, 0, 0, 0]);
        assert_eq!(&bytes[0x92..0x98], &[0x0f, 0x8d, 0x0a, 0, 0, 0]);
        assert_eq!(&bytes[0x98..0x9d], &[0xb8, 0xff, 0xff, 0xff, 0xff]);
        assert_eq!(&bytes[0x9d..0xa2], &[0xe9, 0x1c, 0, 0, 0]);
        assert_eq!(&bytes[0xa2..0xa4], &[0x89, 0xf8]);
        assert_eq!(&bytes[0xa4..0xa9], &[0x3d, 0, 0, 0, 0]);
        assert_eq!(&bytes[0xa9..0xaf], &[0x0f, 0x8e, 0x0a, 0, 0, 0]);
        assert_eq!(&bytes[0xaf..0xb4], &[0xb8, 1, 0, 0, 0]);
        assert_eq!(&bytes[0xb4..0xb9], &[0xe9, 5, 0, 0, 0]);
        assert_eq!(&bytes[0xb9..0xbe], &[0xb8, 0, 0, 0, 0]);
        assert_eq!(bytes[0xbe], 0xc3);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(
                &format!("x86 source-pack core::i32::signum {name}"),
                &format!("core_i32_signum_{name}"),
                &bytes,
            );
            assert_eq!(output.status.code(), expected_status);
        }
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_i32_compare_as_i32_nested_literal_branch() {
    let cases = [
        ("less", "4", "9", 4u32, 9u32, Some(255)),
        ("greater", "9", "4", 9u32, 4u32, Some(1)),
        ("equal", "4", "4", 4u32, 4u32, Some(0)),
    ];

    for (name, left_source, right_source, left_bits, right_bits, expected_status) in cases {
        let user_source = format!(
            "module app::main;\nimport core::i32;\nfn main() {{\n    return core::i32::compare_as_i32({left_source}, {right_source});\n}}\n"
        );
        let sources = [
            include_str!("../stdlib/core/i32.lani"),
            user_source.as_str(),
        ];
        let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
            .unwrap_or_else(|err| {
                panic!(
                    "x86 source-pack codegen should lower core::i32::compare_as_i32 {name}: {err}"
                )
            });

        assert_eq!(&bytes[0..4], b"\x7fELF");
        assert_eq!(bytes[0x78], 0xbf, "main should load left into edi");
        assert_eq!(&bytes[0x79..0x7d], &left_bits.to_le_bytes());
        assert_eq!(bytes[0x7d], 0xbe, "main should load right into esi");
        assert_eq!(&bytes[0x7e..0x82], &right_bits.to_le_bytes());
        assert_eq!(bytes[0x82], 0xe8, "main should call rel32 after arg setup");
        assert_eq!(&bytes[0x83..0x87], &9u32.to_le_bytes());
        assert_eq!(&bytes[0x87..0x89], &[0x89, 0xc7]);
        assert_eq!(&bytes[0x89..0x8e], &[0xb8, 0x3c, 0, 0, 0]);
        assert_eq!(&bytes[0x8e..0x90], &[0x0f, 0x05]);
        assert_eq!(&bytes[0x90..0x92], &[0x89, 0xf8]);
        assert_eq!(&bytes[0x92..0x94], &[0x39, 0xf0]);
        assert_eq!(&bytes[0x94..0x9a], &[0x0f, 0x8d, 0x0a, 0, 0, 0]);
        assert_eq!(&bytes[0x9a..0x9f], &[0xb8, 0xff, 0xff, 0xff, 0xff]);
        assert_eq!(&bytes[0x9f..0xa4], &[0xe9, 0x19, 0, 0, 0]);
        assert_eq!(&bytes[0xa4..0xa6], &[0x89, 0xf8]);
        assert_eq!(&bytes[0xa6..0xa8], &[0x39, 0xf0]);
        assert_eq!(&bytes[0xa8..0xae], &[0x0f, 0x8e, 0x0a, 0, 0, 0]);
        assert_eq!(&bytes[0xae..0xb3], &[0xb8, 1, 0, 0, 0]);
        assert_eq!(&bytes[0xb3..0xb8], &[0xe9, 5, 0, 0, 0]);
        assert_eq!(&bytes[0xb8..0xbd], &[0xb8, 0, 0, 0, 0]);
        assert_eq!(bytes[0xbd], 0xc3);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(
                &format!("x86 source-pack core::i32::compare_as_i32 {name}"),
                &format!("core_i32_compare_as_i32_{name}"),
                &bytes,
            );
            assert_eq!(output.status.code(), expected_status);
        }
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_i32_predicate_helpers() {
    let cases = [
        ("is_zero", "core::i32::is_zero(0)", 0u32, 0x94u8),
        (
            "is_negative",
            "core::i32::is_negative(-3)",
            0u32.wrapping_sub(3),
            0x9cu8,
        ),
        ("is_positive", "core::i32::is_positive(5)", 5u32, 0x9fu8),
    ];

    for (name, call, arg, setcc_opcode) in cases {
        let user_source = format!(
            "module app::main;\nimport core::i32;\nfn main() -> bool {{\n    return {call};\n}}\n"
        );
        let sources = [
            include_str!("../stdlib/core/i32.lani"),
            user_source.as_str(),
        ];
        let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
            .unwrap_or_else(|err| {
                panic!("x86 source-pack codegen should lower core::i32::{name}: {err}")
            });

        assert_eq!(&bytes[0..4], b"\x7fELF");
        assert_eq!(bytes[0x78], 0xbf, "main should load predicate arg into edi");
        assert_eq!(&bytes[0x79..0x7d], &arg.to_le_bytes());
        assert_eq!(bytes[0x7d], 0xe8, "main should call rel32 after arg setup");
        assert_eq!(&bytes[0x7e..0x82], &9u32.to_le_bytes());
        assert_eq!(&bytes[0x82..0x84], &[0x89, 0xc7]);
        assert_eq!(&bytes[0x84..0x89], &[0xb8, 0x3c, 0, 0, 0]);
        assert_eq!(&bytes[0x89..0x8b], &[0x0f, 0x05]);
        assert_eq!(&bytes[0x8b..0x8d], &[0x89, 0xf8]);
        assert_eq!(&bytes[0x8d..0x92], &[0x3d, 0, 0, 0, 0]);
        assert_eq!(&bytes[0x92..0x95], &[0x0f, setcc_opcode, 0xc0]);
        assert_eq!(&bytes[0x95..0x98], &[0x0f, 0xb6, 0xc0]);
        assert_eq!(bytes[0x98], 0xc3);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(
                &format!("x86 source-pack core::i32::{name}"),
                &format!("core_i32_{name}"),
                &bytes,
            );
            assert_eq!(output.status.code(), Some(1));
        }
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_i32_between_inclusive_compare_and_compare() {
    let cases = [
        ("true", "5", "1", "9", 5u32, 1u32, 9u32, Some(1)),
        ("low_false", "0", "1", "9", 0u32, 1u32, 9u32, Some(0)),
        ("high_false", "10", "1", "9", 10u32, 1u32, 9u32, Some(0)),
    ];

    for (
        name,
        value_source,
        low_source,
        high_source,
        _value_bits,
        _low_bits,
        _high_bits,
        expected,
    ) in cases
    {
        let user_source = format!(
            "module app::main;\nimport core::i32;\nfn main() -> bool {{\n    return core::i32::between_inclusive({value_source}, {low_source}, {high_source});\n}}\n"
        );
        let sources = [
            include_str!("../stdlib/core/i32.lani"),
            user_source.as_str(),
        ];
        let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
            .unwrap_or_else(|err| {
                panic!(
                    "x86 source-pack codegen should lower core::i32::between_inclusive {name}: {err}"
                )
            });

        assert_eq!(&bytes[0..4], b"\x7fELF");

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(
                &format!("x86 source-pack core::i32::between_inclusive {name}"),
                &format!("core_i32_between_inclusive_{name}"),
                &bytes,
            );
            assert_eq!(output.status.code(), expected);
        }
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_u32_min_with_unsigned_branch() {
    let sources = [
        include_str!("../stdlib/core/u32.lani"),
        "module app::main;\nimport core::u32;\nfn main() -> u32 {\n    return core::u32::min(4294967295, 1);\n}\n",
    ];
    let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        .expect("x86 source-pack codegen should lower core::u32::min with unsigned ordering");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(bytes[0x78], 0xbf, "main should load left into edi");
    assert_eq!(&bytes[0x79..0x7d], &u32::MAX.to_le_bytes());
    assert_eq!(bytes[0x7d], 0xbe, "main should load right into esi");
    assert_eq!(&bytes[0x7e..0x82], &1u32.to_le_bytes());
    assert_eq!(bytes[0x82], 0xe8, "main should call rel32 after arg setup");
    assert_eq!(&bytes[0x90..0x92], &[0x89, 0xf8]);
    assert_eq!(&bytes[0x92..0x94], &[0x39, 0xf0]);
    assert_eq!(
        &bytes[0x94..0x9a],
        &[0x0f, 0x83, 7, 0, 0, 0],
        "unsigned '<' branch should use JAE for the false arm"
    );
    assert_eq!(&bytes[0x9a..0x9c], &[0x89, 0xf8]);
    assert_eq!(&bytes[0xa1..0xa3], &[0x89, 0xf0]);
    assert_eq!(bytes[0xa3], 0xc3);

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "x86 source-pack core::u32::min unsigned",
            "core_u32_min_unsigned",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(1));
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_u32_max_with_unsigned_branch() {
    let sources = [
        include_str!("../stdlib/core/u32.lani"),
        "module app::main;\nimport core::u32;\nfn main() -> u32 {\n    return core::u32::max(4294967295, 1);\n}\n",
    ];
    let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        .expect("x86 source-pack codegen should lower core::u32::max with unsigned ordering");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(bytes[0x78], 0xbf, "main should load left into edi");
    assert_eq!(&bytes[0x79..0x7d], &u32::MAX.to_le_bytes());
    assert_eq!(bytes[0x7d], 0xbe, "main should load right into esi");
    assert_eq!(&bytes[0x7e..0x82], &1u32.to_le_bytes());
    assert_eq!(bytes[0x82], 0xe8, "main should call rel32 after arg setup");
    assert_eq!(&bytes[0x90..0x92], &[0x89, 0xf8]);
    assert_eq!(&bytes[0x92..0x94], &[0x39, 0xf0]);
    assert_eq!(
        &bytes[0x94..0x9a],
        &[0x0f, 0x86, 7, 0, 0, 0],
        "unsigned '>' branch should use JBE for the false arm"
    );
    assert_eq!(&bytes[0x9a..0x9c], &[0x89, 0xf8]);
    assert_eq!(&bytes[0xa1..0xa3], &[0x89, 0xf0]);
    assert_eq!(bytes[0xa3], 0xc3);

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "x86 source-pack core::u32::max unsigned",
            "core_u32_max_unsigned",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(255));
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_u32_between_inclusive_unsigned_setcc() {
    let sources = [
        include_str!("../stdlib/core/u32.lani"),
        "module app::main;\nimport core::u32;\nfn main() -> bool {\n    return core::u32::between_inclusive(2147483648, 1, 4294967295);\n}\n",
    ];
    let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        .expect(
            "x86 source-pack codegen should lower core::u32::between_inclusive with unsigned comparisons",
        );

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(bytes[0x78], 0xbf, "main should load value into edi");
    assert_eq!(&bytes[0x79..0x7d], &2_147_483_648u32.to_le_bytes());
    assert_eq!(bytes[0x7d], 0xbe, "main should load low into esi");
    assert_eq!(&bytes[0x7e..0x82], &1u32.to_le_bytes());
    assert_eq!(bytes[0x82], 0xba, "main should load high into edx");
    assert_eq!(&bytes[0x83..0x87], &u32::MAX.to_le_bytes());
    assert_eq!(bytes[0x87], 0xe8, "main should call after three args");
    assert_eq!(&bytes[0x95..0x97], &[0x89, 0xf8]);
    assert_eq!(&bytes[0x97..0x99], &[0x39, 0xf0]);
    assert_eq!(
        &bytes[0x99..0x9c],
        &[0x0f, 0x93, 0xc0],
        "unsigned '>=' return should use SETAE"
    );
    assert_eq!(&bytes[0xa1..0xa3], &[0x89, 0xf8]);
    assert_eq!(&bytes[0xa3..0xa5], &[0x39, 0xd0]);
    assert_eq!(
        &bytes[0xa5..0xa8],
        &[0x0f, 0x96, 0xc0],
        "unsigned '<=' return should use SETBE"
    );
    assert_eq!(bytes[0xad], 0xc3);

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "x86 source-pack core::u32::between_inclusive unsigned",
            "core_u32_between_inclusive_unsigned",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(1));
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_u8_max_above_signed_boundary() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> u8 {\n    return core::u8::max(255, 128);\n}\n",
    ];
    let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        .expect("x86 source-pack codegen should lower core::u8::max with unsigned ordering");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(bytes[0x78], 0xbf, "main should load left into edi");
    assert_eq!(&bytes[0x79..0x7d], &255u32.to_le_bytes());
    assert_eq!(bytes[0x7d], 0xbe, "main should load right into esi");
    assert_eq!(&bytes[0x7e..0x82], &128u32.to_le_bytes());
    assert_eq!(bytes[0x82], 0xe8, "main should call rel32 after arg setup");
    assert_eq!(&bytes[0x94..0x9a], &[0x0f, 0x86, 7, 0, 0, 0]);

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "x86 source-pack core::u8::max unsigned",
            "core_u8_max_unsigned",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(255));
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_u8_literal_range_predicates() {
    let cases = [
        ("digit_true", "is_ascii_digit", 53u32, 48u32, 57u32, Some(1)),
        (
            "digit_false",
            "is_ascii_digit",
            65u32,
            48u32,
            57u32,
            Some(0),
        ),
        (
            "lowercase_true",
            "is_ascii_lowercase",
            113u32,
            97u32,
            122u32,
            Some(1),
        ),
    ];

    for (name, helper, arg, _lower, _upper, expected_status) in cases {
        let user_source = format!(
            "module app::main;\nimport core::u8;\nfn main() -> bool {{\n    return core::u8::{helper}({arg});\n}}\n"
        );
        let sources = [include_str!("../stdlib/core/u8.lani"), user_source.as_str()];
        let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
            .unwrap_or_else(|err| {
                panic!("x86 source-pack codegen should lower core::u8::{helper} {name}: {err}")
            });

        assert_eq!(&bytes[0..4], b"\x7fELF");

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(
                &format!("x86 source-pack core::u8::{helper} {name}"),
                &format!("core_u8_{name}"),
                &bytes,
            );
            assert_eq!(output.status.code(), expected_status);
        }
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_bool_unary_and_conversion_helpers() {
    let cases = [
        (
            "not_false",
            "fn main() -> bool {\n    return core::bool::not(false);\n}\n",
            0u32,
            0x94u8,
            Some(1),
        ),
        (
            "not_true",
            "fn main() -> bool {\n    return core::bool::not(true);\n}\n",
            1u32,
            0x94u8,
            Some(0),
        ),
        (
            "from_i32_zero",
            "fn main() -> bool {\n    return core::bool::from_i32(0);\n}\n",
            0u32,
            0x95u8,
            Some(0),
        ),
        (
            "from_i32_nonzero",
            "fn main() -> bool {\n    return core::bool::from_i32(9);\n}\n",
            9u32,
            0x95u8,
            Some(1),
        ),
    ];

    for (name, main_body, arg_bits, setcc_opcode, expected_status) in cases {
        let user_source = format!("module app::main;\nimport core::bool;\n{main_body}");
        let sources = [
            include_str!("../stdlib/core/bool.lani"),
            user_source.as_str(),
        ];
        let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
            .unwrap_or_else(|err| {
                panic!("x86 source-pack codegen should lower core::bool::{name}: {err}")
            });

        assert_eq!(&bytes[0..4], b"\x7fELF");
        assert_eq!(bytes[0x78], 0xbf, "main should load unary arg into edi");
        assert_eq!(&bytes[0x79..0x7d], &arg_bits.to_le_bytes());
        assert_eq!(bytes[0x7d], 0xe8, "main should call rel32 after arg setup");
        assert_eq!(&bytes[0x7e..0x82], &9u32.to_le_bytes());
        assert_eq!(&bytes[0x82..0x84], &[0x89, 0xc7]);
        assert_eq!(&bytes[0x84..0x89], &[0xb8, 0x3c, 0, 0, 0]);
        assert_eq!(&bytes[0x89..0x8b], &[0x0f, 0x05]);
        assert_eq!(&bytes[0x8b..0x8d], &[0x89, 0xf8]);
        assert_eq!(&bytes[0x8d..0x92], &[0x3d, 0, 0, 0, 0]);
        assert_eq!(&bytes[0x92..0x95], &[0x0f, setcc_opcode, 0xc0]);
        assert_eq!(&bytes[0x95..0x98], &[0x0f, 0xb6, 0xc0]);
        assert_eq!(bytes[0x98], 0xc3);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(
                &format!("x86 source-pack core::bool::{name}"),
                &format!("core_bool_{name}"),
                &bytes,
            );
            assert_eq!(output.status.code(), expected_status);
        }
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_bool_binary_helpers() {
    let cases = [
        ("and_true", "core::bool::and(true, true)", Some(1)),
        ("and_false", "core::bool::and(true, false)", Some(0)),
        ("or_true", "core::bool::or(false, true)", Some(1)),
        ("or_false", "core::bool::or(false, false)", Some(0)),
        ("xor_true", "core::bool::xor(true, false)", Some(1)),
        ("xor_false", "core::bool::xor(true, true)", Some(0)),
        ("eq_true", "core::bool::eq(false, false)", Some(1)),
        ("eq_false", "core::bool::eq(true, false)", Some(0)),
    ];

    for (name, call, expected_status) in cases {
        let user_source = format!(
            "module app::main;\nimport core::bool;\nfn main() -> bool {{\n    return {call};\n}}\n"
        );
        let sources = [
            include_str!("../stdlib/core/bool.lani"),
            user_source.as_str(),
        ];
        let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
            .unwrap_or_else(|err| {
                panic!("x86 source-pack codegen should lower core::bool::{name}: {err}")
            });

        assert_eq!(&bytes[0..4], b"\x7fELF");

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(
                &format!("x86 source-pack core::bool::{name}"),
                &format!("core_bool_{name}"),
                &bytes,
            );
            assert_eq!(output.status.code(), expected_status);
        }
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_bool_terminal_param_branches() {
    let to_i32_cases = [
        ("to_i32_true", "true", 1u32, Some(1)),
        ("to_i32_false", "false", 0u32, Some(0)),
    ];

    for (name, arg_source, arg_bits, expected_status) in to_i32_cases {
        let user_source = format!(
            "module app::main;\nimport core::bool;\nfn main() {{\n    return core::bool::to_i32({arg_source});\n}}\n"
        );
        let sources = [
            include_str!("../stdlib/core/bool.lani"),
            user_source.as_str(),
        ];
        let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
            .unwrap_or_else(|err| {
                panic!("x86 source-pack codegen should lower core::bool::{name}: {err}")
            });

        assert_eq!(&bytes[0..4], b"\x7fELF");
        assert_eq!(bytes[0x78], 0xbf, "main should load condition into edi");
        assert_eq!(&bytes[0x79..0x7d], &arg_bits.to_le_bytes());
        assert_eq!(bytes[0x7d], 0xe8, "main should call rel32 after arg setup");
        assert_eq!(&bytes[0x7e..0x82], &9u32.to_le_bytes());
        assert_eq!(&bytes[0x82..0x84], &[0x89, 0xc7]);
        assert_eq!(&bytes[0x84..0x89], &[0xb8, 0x3c, 0, 0, 0]);
        assert_eq!(&bytes[0x89..0x8b], &[0x0f, 0x05]);
        assert_eq!(&bytes[0x8b..0x8d], &[0x89, 0xf8]);
        assert_eq!(&bytes[0x8d..0x92], &[0x3d, 0, 0, 0, 0]);
        assert_eq!(&bytes[0x92..0x98], &[0x0f, 0x84, 0x0a, 0, 0, 0]);
        assert_eq!(&bytes[0x98..0x9d], &[0xb8, 1, 0, 0, 0]);
        assert_eq!(&bytes[0x9d..0xa2], &[0xe9, 5, 0, 0, 0]);
        assert_eq!(&bytes[0xa2..0xa7], &[0xb8, 0, 0, 0, 0]);
        assert_eq!(bytes[0xa7], 0xc3);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(
                &format!("x86 source-pack core::bool::{name}"),
                &format!("core_bool_{name}"),
                &bytes,
            );
            assert_eq!(output.status.code(), expected_status);
        }
    }

    let select_cases = [
        ("select_true", "true", 1u32, Some(7)),
        ("select_false", "false", 0u32, Some(3)),
    ];

    for (name, condition_source, condition_bits, expected_status) in select_cases {
        let user_source = format!(
            "module app::main;\nimport core::bool;\nfn main() {{\n    return core::bool::select_i32({condition_source}, 7, 3);\n}}\n"
        );
        let sources = [
            include_str!("../stdlib/core/bool.lani"),
            user_source.as_str(),
        ];
        let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
            .unwrap_or_else(|err| {
                panic!("x86 source-pack codegen should lower core::bool::{name}: {err}")
            });

        assert_eq!(&bytes[0..4], b"\x7fELF");
        assert_eq!(bytes[0x78], 0xbf, "main should load condition into edi");
        assert_eq!(&bytes[0x79..0x7d], &condition_bits.to_le_bytes());
        assert_eq!(bytes[0x7d], 0xbe, "main should load when_true into esi");
        assert_eq!(&bytes[0x7e..0x82], &7u32.to_le_bytes());
        assert_eq!(bytes[0x82], 0xba, "main should load when_false into edx");
        assert_eq!(&bytes[0x83..0x87], &3u32.to_le_bytes());
        assert_eq!(bytes[0x87], 0xe8, "main should call after three args");
        assert_eq!(&bytes[0x88..0x8c], &9u32.to_le_bytes());
        assert_eq!(&bytes[0x8c..0x8e], &[0x89, 0xc7]);
        assert_eq!(&bytes[0x8e..0x93], &[0xb8, 0x3c, 0, 0, 0]);
        assert_eq!(&bytes[0x93..0x95], &[0x0f, 0x05]);
        assert_eq!(&bytes[0x95..0x97], &[0x89, 0xf8]);
        assert_eq!(&bytes[0x97..0x9c], &[0x3d, 0, 0, 0, 0]);
        assert_eq!(&bytes[0x9c..0xa2], &[0x0f, 0x84, 7, 0, 0, 0]);
        assert_eq!(&bytes[0xa2..0xa4], &[0x89, 0xf0]);
        assert_eq!(&bytes[0xa4..0xa9], &[0xe9, 2, 0, 0, 0]);
        assert_eq!(&bytes[0xa9..0xab], &[0x89, 0xd0]);
        assert_eq!(bytes[0xab], 0xc3);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(
                &format!("x86 source-pack core::bool::{name}"),
                &format!("core_bool_{name}"),
                &bytes,
            );
            assert_eq!(output.status.code(), expected_status);
        }
    }
}

#[test]
fn x86_explicit_source_pack_paths_emit_direct_elf_for_qualified_scalar_const_return() {
    let stdlib_path =
        common::TempArtifact::new("laniusc_x86_source_pack", "stdlib_core_i32", Some("lani"));
    let user_path = common::TempArtifact::new("laniusc_x86_source_pack", "user_main", Some("lani"));
    stdlib_path.write_str(include_str!("../stdlib/core/i32.lani"));
    user_path.write_str(
        "module app::main;\nimport core::i32;\nfn main() {\n    return core::i32::MAX;\n}\n",
    );
    let stdlib_paths = [stdlib_path.path().to_path_buf()];
    let user_paths = [user_path.path().to_path_buf()];

    let bytes = common::run_gpu_codegen_with_timeout(
        "GPU explicit source-pack path x86 compile",
        move || {
            pollster::block_on(
                compile_explicit_source_pack_paths_to_x86_64_with_gpu_codegen(
                    &stdlib_paths,
                    &user_paths,
                ),
            )
        },
    )
    .expect("x86 explicit source-pack path codegen should use the GPU source-pack pipeline");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(bytes[0x7d], 0xbf);
    assert_eq!(&bytes[0x7e..0x82], &2_147_483_647u32.to_le_bytes());
    assert_eq!(&bytes[0x82..0x84], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_true_literal_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() -> bool {\n    return true;\n}\n",
    ))
    .expect("x86 codegen should lower a HIR boolean literal into direct ELF bytes");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(bytes[0x7d], 0xbf);
    assert_eq!(&bytes[0x7e..0x82], &1u32.to_le_bytes());
    assert_eq!(&bytes[0x82..0x84], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_false_literal_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() -> bool {\n    return false;\n}\n",
    ))
    .expect("x86 codegen should lower a false HIR literal into direct ELF bytes");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(bytes[0x7d], 0xbf);
    assert_eq!(&bytes[0x7e..0x82], &0u32.to_le_bytes());
    assert_eq!(&bytes[0x82..0x84], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_logical_not_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() -> bool {\n    return !false;\n}\n",
    ))
    .expect("x86 codegen should lower HIR logical-not of a boolean literal");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(bytes[0x7d], 0xbf);
    assert_eq!(&bytes[0x7e..0x82], &1u32.to_le_bytes());
    assert_eq!(&bytes[0x82..0x84], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_integer_add_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    return 1 + 2;\n}\n",
    ))
    .expect("x86 codegen should emit direct ELF bytes for the first binary HIR slice");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(
        u64::from_le_bytes(bytes[24..32].try_into().unwrap()),
        0x400078
    );
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 1, 0, 0, 0]);
    assert_eq!(&bytes[0x7d..0x82], &[0x05, 2, 0, 0, 0]);
    assert_eq!(&bytes[0x82..0x84], &[0x89, 0xc7]);
    assert_eq!(&bytes[0x84..0x89], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x89..0x8b], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_local_integer_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    let value: i32 = 7;\n    return value;\n}\n",
    ))
    .expect("x86 codegen should lower one scalar local into direct ELF bytes");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(
        u64::from_le_bytes(bytes[24..32].try_into().unwrap()),
        0x400078
    );
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(bytes[0x7d], 0xbf);
    assert_eq!(&bytes[0x7e..0x82], &7u32.to_le_bytes());
    assert_eq!(&bytes[0x82..0x84], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_bool_local_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() -> bool {\n    let value: bool = true;\n    return value;\n}\n",
    ))
    .expect("x86 codegen should lower scalar locals initialized from HIR boolean literals");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(bytes[0x7d], 0xbf);
    assert_eq!(&bytes[0x7e..0x82], &1u32.to_le_bytes());
    assert_eq!(&bytes[0x82..0x84], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_logical_not_local_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() -> bool {\n    let value: bool = false;\n    return !value;\n}\n",
    ))
    .expect("x86 codegen should lower HIR logical-not of a scalar local");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(bytes[0x7d], 0xbf);
    assert_eq!(&bytes[0x7e..0x82], &1u32.to_le_bytes());
    assert_eq!(&bytes[0x82..0x84], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_negative_integer_literal_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    return -1;\n}\n",
    ))
    .expect("x86 codegen should lower a HIR unary signed literal into direct ELF bytes");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(bytes[0x7d], 0xbf);
    assert_eq!(&bytes[0x7e..0x82], &u32::MAX.to_le_bytes());
    assert_eq!(&bytes[0x82..0x84], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_negative_local_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    let value: i32 = -3;\n    return value;\n}\n",
    ))
    .expect("x86 codegen should lower a scalar local initialized from a HIR unary signed literal");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(bytes[0x7d], 0xbf);
    assert_eq!(&bytes[0x7e..0x82], &(0u32.wrapping_sub(3)).to_le_bytes());
    assert_eq!(&bytes[0x82..0x84], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_negated_local_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    let value: i32 = 3;\n    return -value;\n}\n",
    ))
    .expect("x86 codegen should lower HIR unary negation of a scalar local");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(bytes[0x7d], 0xbf);
    assert_eq!(&bytes[0x7e..0x82], &(0u32.wrapping_sub(3)).to_le_bytes());
    assert_eq!(&bytes[0x82..0x84], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_local_integer_add_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    let value: i32 = 7;\n    return value + 2;\n}\n",
    ))
    .expect("x86 codegen should lower one scalar local binary return into direct ELF bytes");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(
        u64::from_le_bytes(bytes[24..32].try_into().unwrap()),
        0x400078
    );
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 7, 0, 0, 0]);
    assert_eq!(&bytes[0x7d..0x82], &[0x05, 2, 0, 0, 0]);
    assert_eq!(&bytes[0x82..0x84], &[0x89, 0xc7]);
    assert_eq!(&bytes[0x84..0x89], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x89..0x8b], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_bool_and_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() -> bool {\n    let left: bool = true;\n    let right: bool = false;\n    return left && right;\n}\n",
    ))
    .expect("x86 codegen should lower bounded boolean and returns");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 1, 0, 0, 0]);
    assert_eq!(&bytes[0x7d..0x82], &[0x25, 0, 0, 0, 0]);
    assert_eq!(&bytes[0x82..0x84], &[0x89, 0xc7]);
    assert_eq!(&bytes[0x84..0x89], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x89..0x8b], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_bool_or_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() -> bool {\n    return false || true;\n}\n",
    ))
    .expect("x86 codegen should lower bounded boolean or returns");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 0, 0, 0, 0]);
    assert_eq!(&bytes[0x7d..0x82], &[0x0d, 1, 0, 0, 0]);
    assert_eq!(&bytes[0x82..0x84], &[0x89, 0xc7]);
    assert_eq!(&bytes[0x84..0x89], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x89..0x8b], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_negated_local_binary_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    let value: i32 = 3;\n    return -value + 5;\n}\n",
    ))
    .expect("x86 codegen should lower HIR unary local atoms in binary returns");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(bytes[0x78], 0xb8);
    assert_eq!(&bytes[0x79..0x7d], &(0u32.wrapping_sub(3)).to_le_bytes());
    assert_eq!(&bytes[0x7d..0x82], &[0x05, 5, 0, 0, 0]);
    assert_eq!(&bytes[0x82..0x84], &[0x89, 0xc7]);
    assert_eq!(&bytes[0x84..0x89], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x89..0x8b], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_two_local_integer_add_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    let left: i32 = 7;\n    let right: i32 = 2;\n    return left + right;\n}\n",
    ))
    .expect("x86 codegen should lower two scalar literal locals into direct ELF bytes");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(
        u64::from_le_bytes(bytes[24..32].try_into().unwrap()),
        0x400078
    );
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 7, 0, 0, 0]);
    assert_eq!(&bytes[0x7d..0x82], &[0x05, 2, 0, 0, 0]);
    assert_eq!(&bytes[0x82..0x84], &[0x89, 0xc7]);
    assert_eq!(&bytes[0x84..0x89], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x89..0x8b], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_terminal_if_else_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    let value: i32 = 4;\n    if (value > 3) { return 0; } else { return 1; }\n}\n",
    ))
    .expect("x86 codegen should lower one scalar terminal if/else into direct ELF bytes");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(
        u64::from_le_bytes(bytes[24..32].try_into().unwrap()),
        0x400078
    );
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 4, 0, 0, 0]);
    assert_eq!(&bytes[0x7d..0x82], &[0x3d, 3, 0, 0, 0]);
    assert_eq!(&bytes[0x82..0x88], &[0x0f, 0x8e, 10, 0, 0, 0]);
    assert_eq!(&bytes[0x88..0x8d], &[0xbf, 0, 0, 0, 0]);
    assert_eq!(&bytes[0x8d..0x92], &[0xe9, 5, 0, 0, 0]);
    assert_eq!(&bytes[0x92..0x97], &[0xbf, 1, 0, 0, 0]);
    assert_eq!(&bytes[0x97..0x9c], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x9c..0x9e], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_terminal_if_else_bool_returns() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() -> bool {\n    let value: i32 = 4;\n    if (value > 3) { return true; } else { return false; }\n}\n",
    ))
    .expect("x86 codegen should lower HIR boolean literals in terminal branch arms");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 4, 0, 0, 0]);
    assert_eq!(&bytes[0x7d..0x82], &[0x3d, 3, 0, 0, 0]);
    assert_eq!(&bytes[0x82..0x88], &[0x0f, 0x8e, 10, 0, 0, 0]);
    assert_eq!(&bytes[0x88..0x8d], &[0xbf, 1, 0, 0, 0]);
    assert_eq!(&bytes[0x8d..0x92], &[0xe9, 5, 0, 0, 0]);
    assert_eq!(&bytes[0x92..0x97], &[0xbf, 0, 0, 0, 0]);
    assert_eq!(&bytes[0x97..0x9c], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x9c..0x9e], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_terminal_if_else_negative_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    let value: i32 = 4;\n    if (value > 3) { return -1; } else { return 0; }\n}\n",
    ))
    .expect("x86 codegen should lower signed scalar atoms in terminal if/else arms");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 4, 0, 0, 0]);
    assert_eq!(&bytes[0x7d..0x82], &[0x3d, 3, 0, 0, 0]);
    assert_eq!(&bytes[0x82..0x88], &[0x0f, 0x8e, 10, 0, 0, 0]);
    assert_eq!(&bytes[0x88..0x8d], &[0xbf, 0xff, 0xff, 0xff, 0xff]);
    assert_eq!(&bytes[0x8d..0x92], &[0xe9, 5, 0, 0, 0]);
    assert_eq!(&bytes[0x92..0x97], &[0xbf, 0, 0, 0, 0]);
    assert_eq!(&bytes[0x97..0x9c], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x9c..0x9e], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_abs_shaped_negated_local_branch() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    let value: i32 = -4;\n    if (value < 0) { return -value; } else { return value; }\n}\n",
    ))
    .expect("x86 codegen should lower an abs-shaped terminal branch over a scalar local");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(bytes[0x78], 0xb8);
    assert_eq!(&bytes[0x79..0x7d], &(0u32.wrapping_sub(4)).to_le_bytes());
    assert_eq!(&bytes[0x7d..0x82], &[0x3d, 0, 0, 0, 0]);
    assert_eq!(&bytes[0x82..0x88], &[0x0f, 0x8d, 10, 0, 0, 0]);
    assert_eq!(&bytes[0x88..0x8d], &[0xbf, 4, 0, 0, 0]);
    assert_eq!(&bytes[0x8d..0x92], &[0xe9, 5, 0, 0, 0]);
    assert_eq!(&bytes[0x92..0x97], &[0xbf, 0xfc, 0xff, 0xff, 0xff]);
    assert_eq!(&bytes[0x97..0x9c], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x9c..0x9e], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_comparison_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() -> bool {\n    let value: i32 = 4;\n    return value > 3;\n}\n",
    ))
    .expect("x86 codegen should lower one scalar comparison return into direct ELF bytes");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(
        u64::from_le_bytes(bytes[24..32].try_into().unwrap()),
        0x400078
    );
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 4, 0, 0, 0]);
    assert_eq!(&bytes[0x7d..0x82], &[0x3d, 3, 0, 0, 0]);
    assert_eq!(&bytes[0x82..0x85], &[0x0f, 0x9f, 0xc0]);
    assert_eq!(&bytes[0x85..0x88], &[0x0f, 0xb6, 0xf8]);
    assert_eq!(&bytes[0x88..0x8d], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x8d..0x8f], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_negated_local_comparison_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() -> bool {\n    let value: i32 = 3;\n    return -value < 0;\n}\n",
    ))
    .expect("x86 codegen should lower HIR unary local atoms in comparison returns");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(bytes[0x78], 0xb8);
    assert_eq!(&bytes[0x79..0x7d], &(0u32.wrapping_sub(3)).to_le_bytes());
    assert_eq!(&bytes[0x7d..0x82], &[0x3d, 0, 0, 0, 0]);
    assert_eq!(&bytes[0x82..0x85], &[0x0f, 0x9c, 0xc0]);
    assert_eq!(&bytes[0x85..0x88], &[0x0f, 0xb6, 0xf8]);
    assert_eq!(&bytes[0x88..0x8d], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x8d..0x8f], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_rejects_non_constant_local_initializer_via_gpu_status() {
    let err = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn id(x: i32) -> i32 {\n    return x;\n}\nfn main() {\n    let value: i32 = id(1);\n    return value;\n}\n",
    ))
    .expect_err("x86 codegen should reject non-constant local initializers in the bounded slice");

    let message = err.to_string();
    match err {
        CompileError::GpuCodegen(_) => {}
        other => panic!("expected GPU codegen rejection, got {other:?}: {message}"),
    }
    assert!(
        message.contains("GPU x86 emitter rejected unsupported return expression"),
        "unexpected x86 codegen error: {message}"
    );
}

#[test]
fn x86_source_codegen_rejects_unsupported_return_expr_via_gpu_status() {
    let err = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    return 1 + 2 + 3;\n}\n",
    ))
    .expect_err("x86 codegen should reject unsupported return expressions");

    let message = err.to_string();
    match err {
        CompileError::GpuCodegen(_) => {}
        other => panic!("expected GPU codegen rejection, got {other:?}: {message}"),
    }
    assert!(
        message.contains("GPU x86 emitter rejected unsupported return expression"),
        "unexpected x86 codegen error: {message}"
    );
}

#[test]
fn x86_path_codegen_reads_existing_input_and_emits_elf() {
    let src_path = common::TempArtifact::new("laniusc_gpu_x86", "input", Some("lani"));
    src_path.write_str("fn main() {\n    return 0;\n}\n");

    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen_from_path(
        src_path.path(),
    ))
    .expect("x86 path codegen should read source and emit direct ELF bytes");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x7e..0x82], &0u32.to_le_bytes());
}
