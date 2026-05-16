use std::{
    fs,
    path::{Path, PathBuf},
};

fn shader_path(file_name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("shaders")
        .join("type_checker")
        .join(file_name)
}

fn read_shader(file_name: &str) -> String {
    let path = shader_path(file_name);
    fs::read_to_string(&path).unwrap_or_else(|err| panic!("read {}: {err}", path.display()))
}

fn name_shader_files() -> [&'static str; 11] {
    [
        "type_check_names_00_mark_lexemes.slang",
        "type_check_names_scan_00_local.slang",
        "type_check_names_scan_01_blocks.slang",
        "type_check_names_scan_02_apply.slang",
        "type_check_names_01_scatter_lexemes.slang",
        "type_check_names_radix_00_histogram.slang",
        "type_check_names_radix_00b_bucket_prefix.slang",
        "type_check_names_radix_00c_bucket_bases.slang",
        "type_check_names_radix_01_scatter.slang",
        "type_check_names_radix_02_adjacent_dedup.slang",
        "type_check_names_radix_03_assign_ids.slang",
    ]
}

fn all_name_shader_sources() -> String {
    name_shader_files()
        .into_iter()
        .map(read_shader)
        .collect::<Vec<_>>()
        .join("\n")
}

fn read_repo_file(rel: &str) -> String {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join(rel);
    fs::read_to_string(&path).unwrap_or_else(|err| panic!("read {}: {err}", path.display()))
}

#[test]
fn name_radix_foundation_files_are_standalone_compute_shaders() {
    for file_name in name_shader_files() {
        let shader = read_shader(file_name);
        assert!(
            shader.contains("[shader(\"compute\")]"),
            "{file_name} should declare a compute entrypoint"
        );
        assert!(
            shader.contains("[numthreads(256, 1, 1)]"),
            "{file_name} should use the repository wave-sized workgroup"
        );
        assert!(
            !shader
                .lines()
                .any(|line| line.trim_start().starts_with("import ")),
            "{file_name} should compile as a standalone Slang shader"
        );
    }
}

#[test]
fn name_radix_foundation_documents_gpu_only_schedule() {
    let shaders = all_name_shader_sources();
    assert!(
        shaders.contains("GPU-only scheduling contract")
            && shaders.contains("identifier/string names")
            && shaders.contains("GPU-friendly parallel radix sort"),
        "radix name shaders should document the paper-aligned GPU scheduling contract"
    );
    assert!(
        shaders.contains(
            "The host may bind buffers and dispatch passes, but does not read or classify"
        ),
        "the scheduling contract should keep name inspection on the device"
    );
}

#[test]
fn name_scan_foundation_produces_exclusive_prefixes_on_gpu() {
    let local = read_shader("type_check_names_scan_00_local.slang");
    assert!(
        local.contains("scan_local_prefix[i] = scan_values[lane] - value")
            && local.contains("scan_block_sum[block_i] = scan_values[lane]")
            && local.contains("GroupMemoryBarrierWithGroupSync"),
        "local scan should produce per-item exclusive prefixes and per-block sums"
    );

    let blocks = read_shader("type_check_names_scan_01_blocks.slang");
    assert!(
        blocks.contains("scan_step == 0u")
            && blocks.contains("scan_block_prefix_out[i] = scan_block_sum[i]")
            && blocks.contains("value += scan_block_prefix_in[i - gScan.scan_step]"),
        "block scan should build inclusive prefixes over block sums"
    );

    let apply = read_shader("type_check_names_scan_02_apply.slang");
    assert!(
        apply.contains("prior_blocks + scan_local_prefix[i]")
            && apply.contains("scan_total[0]")
            && apply.contains("scan_block_prefix[gScan.n_blocks - 1u]"),
        "apply scan should convert local prefixes to global exclusive prefixes and total count"
    );
}

#[test]
fn name_extraction_marks_and_scatters_lexical_name_spans() {
    let mark = read_shader("type_check_names_00_mark_lexemes.slang");
    assert!(
        mark.contains("name_lexeme_flag")
            && mark.contains("name_lexeme_kind")
            && mark.contains("TK_IDENT")
            && mark.contains("TK_LET_IDENT")
            && mark.contains("TK_PARAM_IDENT")
            && mark.contains("TK_TYPE_IDENT")
            && mark.contains("TK_STRING")
            && mark.contains("NAME_KIND_IDENTIFIER")
            && mark.contains("NAME_KIND_STRING"),
        "mark pass should classify lexer-produced name-bearing tokens without resolving semantics"
    );

    let scatter = read_shader("type_check_names_01_scatter_lexemes.slang");
    assert!(
        scatter.contains("name_lexeme_prefix")
            && scatter.contains("NameSpan")
            && scatter.contains("span.token_index = token_i")
            && scatter.contains("name_order_in[slot] = slot")
            && scatter.contains("name_id_by_token[i] = INVALID")
            && scatter.contains("name_count_out[0] = prefix + flag")
            && scatter.contains("MAX_NAME_RADIX_BYTES = 64u")
            && scatter.contains("MAX_NAME_RADIX_ITEMS = 65536u")
            && scatter.contains("record_error(i, ERR_NAME_LIMIT, span.len)"),
        "scatter pass should consume GPU prefix output, create compact NameSpan records, and reject unsupported radix bounds"
    );
}

#[test]
fn name_radix_foundation_uses_radix_histogram_and_stable_scatter() {
    let histogram = read_shader("type_check_names_radix_00_histogram.slang");
    assert!(
        histogram.contains("RADIX_BUCKETS = 257u")
            && histogram.contains("radix_byte_offset")
            && histogram.contains("name_count_in")
            && histogram.contains("active_name_count")
            && histogram.contains("span_radix_key")
            && histogram.contains("return b + 1u")
            && histogram.contains("InterlockedAdd(radix_block_histogram"),
        "histogram shader should expose a byte-sentinel radix histogram bounded by the GPU-written name count"
    );

    let bucket_prefix = read_shader("type_check_names_radix_00b_bucket_prefix.slang");
    assert!(
        bucket_prefix.contains("radix_block_histogram")
            && bucket_prefix.contains("radix_block_bucket_prefix")
            && bucket_prefix.contains("radix_bucket_total")
            && bucket_prefix.contains("MAX_RADIX_BLOCKS = 256u")
            && bucket_prefix.contains("groupshared uint scan_values[256]")
            && bucket_prefix.contains("GroupMemoryBarrierWithGroupSync")
            && bucket_prefix.contains("scan_values[lane] - value"),
        "bucket-prefix helper should scan per-bucket block histograms on the GPU"
    );

    let bucket_bases = read_shader("type_check_names_radix_00c_bucket_bases.slang");
    assert!(
        bucket_bases.contains("radix_bucket_total")
            && bucket_bases.contains("radix_bucket_base")
            && bucket_bases.contains("SCAN_SLOTS = 512u")
            && bucket_bases.contains("groupshared uint scan_values[512]")
            && bucket_bases.contains("GroupMemoryBarrierWithGroupSync")
            && bucket_bases.contains("radix_bucket_base[lane] = scan_values[lane] - value0"),
        "bucket-base helper should scan bucket totals into stable scatter bases on the GPU"
    );

    let scatter = read_shader("type_check_names_radix_01_scatter.slang");
    assert!(
        scatter.contains("stable scatter")
            && scatter.contains("name_count_in")
            && scatter.contains("active_name_count")
            && scatter.contains("radix_bucket_base[key]")
            && scatter.contains("radix_block_bucket_prefix")
            && scatter.contains("for (uint j = 0u; j < lane; j += 1u)")
            && scatter.contains("name_order_out[dst] = name_i"),
        "scatter shader should use scanned radix offsets and preserve local order over the GPU-written name count"
    );
}

#[test]
fn name_radix_foundation_deduplicates_with_adjacent_byte_equality() {
    let dedup = read_shader("type_check_names_radix_02_adjacent_dedup.slang");
    assert!(
        dedup.contains("byte_equal_name_spans")
            && dedup.contains("name_count_in")
            && dedup.contains("active_name_count")
            && dedup.contains("if (i >= gParams.name_count)")
            && dedup.contains("run_head_mask[i] = 0u")
            && dedup.contains("a.len != b.len")
            && dedup.contains("load_source_byte(a.start + i) != load_source_byte(b.start + i)")
            && dedup.contains("sorted_name_order[i - 1u]")
            && dedup.contains("adjacent_equal_mask[i] = equal_prev")
            && dedup.contains("run_head_mask[i] = is_head"),
        "dedup shader should compare adjacent sorted strings by byte equality"
    );
}

#[test]
fn name_radix_foundation_assigns_ids_from_run_head_prefix() {
    let assign = read_shader("type_check_names_radix_03_assign_ids.slang");
    assert!(
        assign.contains("run_head_prefix")
            && assign.contains("name_count_in")
            && assign.contains("active_name_count")
            && assign.contains("name_id_from_run_head")
            && assign.contains("return run_prefix")
            && assign.contains("return run_prefix - 1u")
            && assign.contains("name_id_by_input[name_i] = id")
            && assign.contains("name_id_by_token[name_spans[name_i].token_index] = id")
            && assign.contains("unique_name_count[0] = id + 1u"),
        "id assignment should derive final ids from run_head prefix sums"
    );
}

#[test]
fn name_radix_foundation_forbids_non_paper_shortcuts() {
    let lower = all_name_shader_sources().to_lowercase();
    for forbidden in [
        "bitonic",
        "cpu",
        "fallback",
        "source_contains",
        "semantic scan",
        "semantic_scan",
        "token-level semantic",
        "token level semantic",
        "source semantic",
        "hash-only",
        "hash only",
        "hash",
    ] {
        assert!(
            !lower.contains(forbidden),
            "radix name foundation should not contain forbidden shortcut language: {forbidden}"
        );
    }
}

#[test]
fn resident_type_checker_wires_name_extraction_without_deleted_module_shortcuts() {
    let gpu = read_repo_file("src/type_checker/mod.rs");

    for required in [
        "names_mark_lexemes",
        "names_scan_local",
        "names_scan_blocks",
        "names_scan_apply",
        "names_scatter_lexemes",
        "names_radix_histogram",
        "names_radix_bucket_prefix",
        "names_radix_bucket_bases",
        "names_radix_scatter",
        "names_radix_dedup",
        "names_radix_assign_ids",
        "name_lexeme_flag",
        "name_lexeme_prefix",
        "name_spans",
        "name_order_in",
        "name_order_tmp",
        "name_id_by_token",
        "name_scan_total",
        "radix_block_histogram",
        "radix_block_bucket_prefix",
        "radix_bucket_total",
        "radix_bucket_base",
        "run_head_mask",
        "run_head_prefix",
        "sorted_name_id",
        "name_id_by_input",
        "unique_name_count",
        "record_name_bind_groups_with_passes",
        "type_check.names.mark_lexemes",
        "type_check.names.scan_local",
        "type_check.names.scan_blocks",
        "type_check.names.scan_apply",
        "type_check.names.scatter_lexemes",
        "type_check.names.radix_histogram",
        "type_check.names.radix_bucket_prefix",
        "type_check.names.radix_bucket_bases",
        "type_check.names.radix_scatter",
        "type_check.names.radix_dedup",
        "type_check.names.run_head_scan_local",
        "type_check.names.run_head_scan_blocks",
        "type_check.names.run_head_scan_apply",
        "type_check.names.radix_assign_ids",
        "NAME_RADIX_MAX_BYTES",
        "NameLimit",
    ] {
        assert!(
            gpu.contains(required),
            "resident type checker should wire GPU name extraction/radix buffer/pass: {required}"
        );
    }

    for forbidden in [
        "type_check_names_00_hash",
        "module_id_for_file",
        "import_resolved_module_token",
        "type_check_modules_00_collect",
        "type_check_modules_00_resolve_imports",
        "type_check_modules_01_same_source_types",
        "type_check_modules_02_patch_visible_types",
        "same_source_qualified",
        "qualified_leaf_token",
    ] {
        assert!(
            !gpu.contains(forbidden),
            "resident type checker should not wire deleted module/import shortcut: {forbidden}"
        );
    }
}
