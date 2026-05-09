use std::{
    fs,
    path::{Path, PathBuf},
};

#[test]
fn gpu_shader_entrypoints_are_wave_sized() {
    let shader_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("shaders");
    let mut checked = 0usize;
    for path in slang_files(&shader_dir) {
        let source = fs::read_to_string(&path)
            .unwrap_or_else(|err| panic!("read {}: {err}", path.display()));
        for (line_no, line) in source.lines().enumerate() {
            let Some(start) = line.find("[numthreads(") else {
                continue;
            };
            checked += 1;
            let args = &line[start + "[numthreads(".len()..];
            let first_arg = args
                .split(',')
                .next()
                .unwrap_or("")
                .trim()
                .trim_end_matches(')');
            assert!(
                matches!(first_arg, "256" | "WORKGROUP_SIZE" | "WG_SIZE"),
                "{}:{} uses non-wave numthreads: {}",
                path.display(),
                line_no + 1,
                line.trim()
            );
        }
    }
    assert!(checked > 0, "expected to find shader entrypoints");
}

#[test]
fn gpu_type_checker_has_no_generic_unsupported_language_error() {
    let type_checker_dir = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("shaders")
        .join("type_checker");
    for path in slang_files(&type_checker_dir) {
        let source = fs::read_to_string(&path)
            .unwrap_or_else(|err| panic!("read {}: {err}", path.display()));
        assert!(
            !source.contains("ERR_UNSUPPORTED"),
            "{} still contains a generic unsupported error",
            path.display()
        );
    }
}

#[test]
fn default_compiler_records_resident_gpu_pipeline() {
    let compiler = include_str!("../src/compiler.rs");
    assert!(compiler.contains("with_recorded_resident_tokens"));
    assert!(compiler.contains("record_checked_resident_syntax_hir_artifacts"));
    assert!(compiler.contains("record_resident_token_buffer_with_hir_on_gpu"));
    assert!(compiler.contains("compile_source_to_wasm"));
    assert!(compiler.contains("record_wasm_from_gpu_token_buffer"));
    assert!(compiler.contains("compile_source_to_x86_64"));
    assert!(compiler.contains("record_x86_from_gpu_token_buffer"));
    assert!(!compiler.contains("hir::parse_source"));
    assert!(!compiler.contains("emit_wasm"));
    assert!(!compiler.contains("emit_c"));
    assert!(!compiler.contains("compile_source_to_c"));
}

#[test]
fn cpu_codegen_backends_are_deleted() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    for rel in [
        "src/codegen/c.rs",
        "src/codegen/wasm.rs",
        "src/codegen/gpu_c.rs",
        "tests/codegen_c.rs",
        "tests/sample_programs.rs",
    ] {
        assert!(!root.join(rel).exists(), "{rel} should not exist");
    }

    let codegen_mod = include_str!("../src/codegen/mod.rs");
    assert!(codegen_mod.contains("pub mod gpu_wasm;"));
    assert!(codegen_mod.contains("pub mod gpu_x86;"));
    assert!(!codegen_mod.contains("pub mod wasm;"));
    assert!(!codegen_mod.contains("pub mod c;"));
    assert!(!codegen_mod.contains("pub mod gpu_c;"));
}

#[test]
fn gpu_codegen_has_no_source_recognition_patterns() {
    let codegen_dir = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("shaders")
        .join("codegen");
    for path in slang_files(&codegen_dir).into_iter().filter(|path| {
        path.file_stem().is_some_and(|stem| {
            let stem = stem.to_string_lossy();
            stem.starts_with("wasm") || stem.starts_with("x86")
        })
    }) {
        let shader = fs::read_to_string(&path)
            .unwrap_or_else(|err| panic!("read {}: {err}", path.display()));
        for forbidden in [
            "source_contains",
            "pattern_byte",
            "P_ABS",
            "P_ARITH",
            "fn fact",
            "factorial",
            "abs_i32",
            "arithmetic_precedence",
            "bool_branch",
            "function_calls",
            "loop_control",
            "sample-specific",
            "canned",
        ] {
            assert!(
                !shader.contains(forbidden),
                "{} contains forbidden recognition pattern {forbidden:?}",
                path.display()
            );
        }
    }

    let body = include_str!("../shaders/codegen/wasm_body.slang");
    let functions = include_str!("../shaders/codegen/wasm_functions.slang");
    assert!(body.contains("StructuredBuffer<uint> visible_decl"));
    assert!(functions.contains("StructuredBuffer<uint> visible_decl"));

    let gpu_wasm = include_str!("../src/codegen/gpu_wasm.rs");
    assert!(gpu_wasm.contains("hir_kind_buf"));
    assert!(gpu_wasm.contains("visible_decl_buf"));
    assert!(gpu_wasm.contains("codegen.wasm.arrays"));
    assert!(gpu_wasm.contains("codegen.wasm.body"));
    assert!(gpu_wasm.contains("codegen.wasm.bool_body"));
    assert!(gpu_wasm.contains("codegen.wasm.module"));
    assert!(gpu_wasm.contains("codegen.wasm.functions_probe"));
    assert!(gpu_wasm.contains("codegen.wasm.functions"));
}

#[test]
fn gpu_codegen_passes_do_not_use_one_lane_entrypoints() {
    for (name, source) in [
        (
            "wasm_simple_lets",
            include_str!("../shaders/codegen/wasm_simple_lets.slang"),
        ),
        (
            "wasm_arrays",
            include_str!("../shaders/codegen/wasm_arrays.slang"),
        ),
        (
            "wasm_body",
            include_str!("../shaders/codegen/wasm_body.slang"),
        ),
        (
            "wasm_bool_body",
            include_str!("../shaders/codegen/wasm_bool_body.slang"),
        ),
        (
            "wasm_module",
            include_str!("../shaders/codegen/wasm_module.slang"),
        ),
        (
            "wasm_functions_probe",
            include_str!("../shaders/codegen/wasm_functions_probe.slang"),
        ),
        (
            "wasm_functions",
            include_str!("../shaders/codegen/wasm_functions.slang"),
        ),
        (
            "x86_regalloc",
            include_str!("../shaders/codegen/x86_regalloc.slang"),
        ),
        (
            "x86_from_wasm",
            include_str!("../shaders/codegen/x86_from_wasm.slang"),
        ),
        (
            "pack_output",
            include_str!("../shaders/codegen/pack_output.slang"),
        ),
    ] {
        assert!(
            !source.contains("if (tid.x != 0u)"),
            "{name} should not gate shader work to a single lane"
        );
    }
}

#[test]
fn gpu_codegen_module_and_array_passes_are_parallel() {
    let arrays = include_str!("../shaders/codegen/wasm_arrays.slang");
    assert!(
        arrays.contains("uint i = tid.x;"),
        "wasm_arrays should assign token ownership from the dispatch id"
    );

    let module = include_str!("../shaders/codegen/wasm_module.slang");
    assert!(
        !module.contains("if (tid.x != 0u)"),
        "wasm_module should not copy the body from one lane"
    );
    assert!(
        module.contains("uint word_i = linear_dispatch_id(tid);"),
        "wasm_module should assign packed module words from the dispatch id"
    );
    assert!(
        !module.contains("word_i += WORKGROUP_SIZE"),
        "wasm_module should scale dispatch instead of looping one workgroup over output"
    );
    assert!(
        module.contains("status[1u] = ok ? 3u : 0u;"),
        "wasm_module should mark packed output for readback"
    );

    let gpu_wasm = include_str!("../src/codegen/gpu_wasm.rs");
    assert!(
        !gpu_wasm.contains("dispatch_workgroups(1, 1, 1)"),
        "WASM codegen should not dispatch any emitter as a single workgroup"
    );
    assert!(
        gpu_wasm.contains("compute.dispatch_workgroups(simple_groups, 1, 1);"),
        "WASM arrays dispatch should scale with token capacity"
    );
    assert!(
        gpu_wasm.contains("workgroup_grid_1d(packed_output_groups)")
            && gpu_wasm.contains(
                "compute.dispatch_workgroups(packed_output_groups_x, packed_output_groups_y, 1);"
            ),
        "WASM module dispatch should scale with output capacity"
    );

    let gpu_x86 = include_str!("../src/codegen/gpu_x86.rs");
    assert!(
        !gpu_x86.contains("dispatch_workgroups(1, 1, 1)"),
        "x86 codegen should not dispatch any emitter as a single workgroup"
    );
    assert!(
        gpu_x86.contains("let token_groups = token_capacity.div_ceil(256).max(1);"),
        "x86 reused WASM arrays dispatch should scale with token capacity"
    );
}

#[test]
fn gpu_codegen_emitters_write_output_across_lanes() {
    for (name, source, output) in [
        (
            "wasm_body",
            include_str!("../shaders/codegen/wasm_body.slang"),
            "body_words[cursor] = value & 0xffu;",
        ),
        (
            "wasm_functions",
            include_str!("../shaders/codegen/wasm_functions.slang"),
            "out_words[cursor] = value & 0xffu;",
        ),
        (
            "x86_from_wasm",
            include_str!("../shaders/codegen/x86_from_wasm.slang"),
            "out_words[cursor] = value & 0xffu;",
        ),
    ] {
        assert!(
            source.contains("uint lane = tid.x;")
                || source.contains("uint target = tid.x;")
                || source.contains("linear_dispatch_id(tid)")
                || source.contains("tid.x);"),
            "{name} should derive emission ownership from the dispatch id"
        );
        assert!(
            source.contains("cursor == target"),
            "{name} should shard byte emission across lanes"
        );
        assert!(
            source.contains(output),
            "{name} should still write generated bytes to the expected output buffer"
        );
    }
}

#[test]
fn gpu_wasm_bool_body_emits_top_level_statements_in_parallel() {
    let bool_body = include_str!("../shaders/codegen/wasm_bool_body.slang");
    assert!(
        bool_body.contains("is_top_level_statement(tid.x)"),
        "bool-body codegen should assign top-level statement ownership by dispatch id"
    );
    assert!(
        bool_body.contains("emit_statement(cursor, tid.x, true, tid.x);"),
        "bool-body codegen should emit each owned statement without replaying the full body"
    );
    assert!(
        bool_body.contains("BOOL_BODY_BYTES_PER_TOKEN")
            && bool_body.contains("tid.x * BOOL_BODY_BYTES_PER_TOKEN"),
        "bool-body codegen should compute per-statement output offsets without a quadratic prefix replay"
    );
    assert!(
        !bool_body.contains("top_level_statement_bytes_before(tid.x)"),
        "bool-body codegen should not rescan all prior tokens for every statement"
    );

    let gpu_wasm = include_str!("../src/codegen/gpu_wasm.rs");
    assert!(
        gpu_wasm.contains("compute.dispatch_workgroups(simple_groups, 1, 1);"),
        "WASM bool-body dispatch should scale with token capacity"
    );
    let gpu_x86 = include_str!("../src/codegen/gpu_x86.rs");
    assert!(
        gpu_x86.contains("compute.dispatch_workgroups(token_groups, 1, 1);"),
        "x86 reused bool-body dispatch should scale with token capacity"
    );
}

#[test]
fn gpu_wasm_simple_let_fast_path_packs_output_bytes() {
    let simple = include_str!("../shaders/codegen/wasm_simple_lets.slang");
    assert!(
        simple.contains("RWStructuredBuffer<uint> body_dispatch_args"),
        "simple-let fast path should enable body fallback through GPU-written indirect dispatch args"
    );
    assert!(
        simple.contains("emit_packed_out_word"),
        "simple-let fast path should pack final WASM bytes before readback"
    );
    assert!(
        simple.contains("out_words[word_i] = packed;"),
        "simple-let fast path should write one u32 per four output bytes"
    );

    let gpu_wasm = include_str!("../src/codegen/gpu_wasm.rs");
    assert!(
        gpu_wasm.contains("compute.dispatch_workgroups_indirect(&bufs.body_dispatch_buf, 0);"),
        "WASM body fallback should be launched by GPU-written indirect dispatch args"
    );
    assert!(
        gpu_wasm.contains("compute.dispatch_workgroups_indirect(&bufs.functions_dispatch_buf, 0);"),
        "WASM function module fallback should be launched by GPU-written indirect dispatch args"
    );
    assert!(
        gpu_wasm.contains("let (len, source_buf)"),
        "WASM readback should detect packed output"
    );
    assert!(
        gpu_wasm.contains("len.div_ceil(4) * 4"),
        "packed WASM readback should copy packed bytes, not one u32 per byte"
    );
    assert!(
        gpu_wasm.contains("mode == 1 || mode == 5"),
        "WASM readback should use the explicit pack buffer for function-path output"
    );
}

#[test]
fn gpu_codegen_packs_remaining_unpacked_outputs_before_readback() {
    let pack = include_str!("../shaders/codegen/pack_output.slang");
    assert!(
        pack.contains("uint word_i = linear_dispatch_id(tid);"),
        "pack pass should assign packed words from dispatch id"
    );
    assert!(
        pack.contains("packed_words[word_i] ="),
        "pack pass should write one u32 per four emitted bytes"
    );

    let gpu_wasm = include_str!("../src/codegen/gpu_wasm.rs");
    assert!(gpu_wasm.contains("codegen.wasm.pack_output"));
    assert!(gpu_wasm.contains("packed_out_buf"));
    assert!(gpu_wasm.contains("output_capacity.div_ceil(4)"));
    assert!(
        gpu_wasm.contains("mode == 1 || mode == 5"),
        "WASM readback should use pack output for function-path byte streams"
    );

    let gpu_x86 = include_str!("../src/codegen/gpu_x86.rs");
    assert!(gpu_x86.contains("codegen.x86.pack_output"));
    assert!(gpu_x86.contains("packed_out_buf"));
    assert!(gpu_x86.contains("output_capacity.div_ceil(4)"));
    assert!(
        gpu_x86.contains("for &byte in data.iter().take(len)"),
        "x86 readback should read packed bytes, not one u32 per byte"
    );
}

#[test]
fn gpu_x86_codegen_lowers_gpu_ir_and_register_allocates_on_gpu() {
    let gpu_x86 = include_str!("../src/codegen/gpu_x86.rs");
    assert!(gpu_x86.contains("x86_regalloc.spv"));
    assert!(gpu_x86.contains("x86_from_wasm.spv"));
    assert!(gpu_x86.contains("wasm_body.spv"));
    assert!(gpu_x86.contains("wasm_bool_body.spv"));
    assert!(gpu_x86.contains("wasm_functions_probe.spv"));
    assert!(gpu_x86.contains("wasm_functions.spv"));
    assert!(gpu_x86.contains("codegen.x86.regalloc"));
    assert!(gpu_x86.contains("codegen.x86.elf"));
    assert!(gpu_x86.contains("let output_groups = (output_capacity as u32).div_ceil(256).max(1);"));
    assert!(gpu_x86.contains("workgroup_grid_1d(output_groups)"));
    assert!(gpu_x86.contains("compute.dispatch_workgroups(output_groups_x, output_groups_y, 1);"));
    assert!(gpu_x86.contains("reg_map_buf"));
    assert!(gpu_x86.contains("reg_status_buf"));
    assert!(gpu_x86.contains("functions_status_buf"));
    assert!(gpu_x86.contains("codegen.x86.wasm_functions_probe"));
    assert!(
        gpu_x86.contains("compute.dispatch_workgroups_indirect(&bufs.functions_dispatch_buf, 0);"),
        "x86 reused function module lowering should launch through GPU-written indirect dispatch args"
    );
    assert!(gpu_x86.contains("compute.dispatch_workgroups(output_groups_x, output_groups_y, 1);"));

    let regalloc = include_str!("../shaders/codegen/x86_regalloc.slang");
    assert!(regalloc.contains("RWStructuredBuffer<uint> reg_map"));
    assert!(regalloc.contains("RWStructuredBuffer<uint> reg_status"));
    assert!(regalloc.contains("visible_decl"));

    let lowering = include_str!("../shaders/codegen/x86_from_wasm.slang");
    assert!(lowering.contains("StructuredBuffer<uint> body_words"));
    assert!(lowering.contains("StructuredBuffer<uint> functions_words"));
    assert!(lowering.contains("StructuredBuffer<uint> reg_map"));
    assert!(lowering.contains("RWStructuredBuffer<uint> out_words"));
    assert!(lowering.contains("ELF_HEADER_SIZE"));
}

fn slang_files(root: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    collect_slang_files(root, &mut out);
    out
}

fn collect_slang_files(dir: &Path, out: &mut Vec<PathBuf>) {
    let entries =
        fs::read_dir(dir).unwrap_or_else(|err| panic!("read dir {}: {err}", dir.display()));
    for entry in entries {
        let path = entry
            .unwrap_or_else(|err| panic!("read dir entry in {}: {err}", dir.display()))
            .path();
        if path.is_dir() {
            collect_slang_files(&path, out);
        } else if path.extension().is_some_and(|ext| ext == "slang") {
            out.push(path);
        }
    }
}
