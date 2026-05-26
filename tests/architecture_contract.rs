#[cfg(unix)]
use std::process::Command;
use std::{
    fs,
    path::{Path, PathBuf},
};

const BANNED_BACKEND_MARKERS: &[&str] = &[
    "RETURN_EVAL",
    "extract_return",
    "extract_terminal",
    "PARAM_IMM_COMPARE",
    "COMPARE_OR_CHAIN",
    "MOD_POW2",
    "PAIR_BINARY_LIMIT_BRANCH",
    "token_text_eq",
    "token_text_same",
    "find_called_helper",
    "helper_return",
    "helper_array_scan",
];

const QUARANTINED_LEGACY_BACKEND_FILES: &[&str] = &[
    "shaders/codegen/wasm_body.slang",
    "shaders/codegen/wasm_bool_body.slang",
    "shaders/codegen/wasm_hir_array_body.slang",
    "shaders/codegen/wasm_hir_enum_match_module.slang",
];

#[test]
fn architecture_contract_is_checked_in() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let contract_path = root.join("AGENTS.MD");
    let contract = fs::read_to_string(&contract_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", contract_path.display()));

    for required in [
        "Compiler architecture contract",
        "Backend lowering consumes attributed AST or HIR records only.",
        "Instruction counting is per node.",
        "Instruction records use virtual registers before register allocation.",
        "No helper-name matching in semantic analysis or backend lowering.",
        "Follow docs/TESTING_STRATEGY.md",
        "Required review output for every change:",
    ] {
        assert!(
            contract.contains(required),
            "{} must preserve architecture-contract clause {required:?}",
            contract_path.display()
        );
    }

    let testing_strategy_path = root.join("docs/TESTING_STRATEGY.md");
    let testing_strategy = fs::read_to_string(&testing_strategy_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", testing_strategy_path.display()));
    for required in [
        "Before adding, changing, or running tests, state the behavior contract",
        "## Per-Change Test Charter",
        "**Contract:**",
        "**State space:**",
        "**Fault model:**",
        "**Smallest test shape:**",
        "**Plausible bug:**",
        "**Stop condition:**",
        "Use this order by default:",
        "## Lane Boundaries",
        "**CPU/model lane:**",
        "**Small GPU record lane:**",
        "**Generated semantic lane:**",
        "**Scale/performance lane:**",
        "For GPU data-plane changes, prove record invariants:",
        "Large generated tests are opt-in.",
        "Classify failures before editing:",
    ] {
        assert!(
            testing_strategy.contains(required),
            "{} must preserve testing-strategy clause {required:?}",
            testing_strategy_path.display()
        );
    }
}

#[test]
fn testing_strategy_commands_stay_focused_and_explicit() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let testing_strategy_path = root.join("docs/TESTING_STRATEGY.md");
    let testing_strategy = fs::read_to_string(&testing_strategy_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", testing_strategy_path.display()));
    let acceptance_path = root.join("tools/compiler_acceptance.sh");
    let acceptance = fs::read_to_string(&acceptance_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", acceptance_path.display()));
    let generated_gates_path = root.join("tests/generated_10k_gates.rs");
    let generated_gates = fs::read_to_string(&generated_gates_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", generated_gates_path.display()));

    for required in [
        "## Default Lanes",
        "tools/compiler_acceptance.sh --tier focused --run",
        "All scripted Cargo test commands should use `-j1`",
        "Generated and Pareas subprocesses must have explicit command timeouts.",
        "`LANIUS_GENERATED_GATE_COMMAND_TIMEOUT_MS=120000`",
        "`LANIUS_X86_READBACK_TIMEOUT_MS=60000`",
        "**Shader loop budget:**",
        "Scale/performance lanes require a second opt-in before execution:",
        "`LANIUS_ACCEPTANCE_ALLOW_SCALE=1`",
        "Escalation must cross only one boundary at a time.",
        "Do not use `--tier all` for normal development.",
        "Generator design matters more than case count.",
        "Track shader loop budgets as CPU-only tripwires",
        "Do not extend inherited marker-inventory architecture tests.",
        "replace the touched expectation with a higher-signal contract",
        "Do not add a test that cannot answer the plausible-bug question.",
        "Do not append to `TEST_RUN_LOG.md`",
        "capacity-gate size is 5k lines",
        "A 10k generated case is an explicit",
        "20k generated case",
        "capacity checkpoint, not a normal",
        "Anything above 20k must",
        "`LANIUS_ALLOW_LARGE_GENERATED_TESTS=1`",
        "Pareas comparisons default to one measured iteration.",
    ] {
        assert!(
            testing_strategy.contains(required),
            "{} must keep testing strategy actionable clause {required:?}",
            testing_strategy_path.display()
        );
    }

    assert!(
        acceptance.contains("tier=focused"),
        "{} must default to the focused lane",
        acceptance_path.display()
    );
    assert!(
        acceptance.contains("describe_tier()")
            && acceptance.contains("testing-strategy tier=focused lane=CPU/model")
            && acceptance.contains("testing-strategy tier=properties lane=targeted-property")
            && acceptance.contains("testing-strategy mode=dry-run"),
        "{} must print the selected test lane and contract before listing commands",
        acceptance_path.display()
    );
    assert!(
        acceptance.contains("LANIUS_GENERATED_LINES                         default 5000")
            && acceptance.contains("LANIUS_CAPACITY_STRESS_LINES                   default 5000")
            && acceptance
                .contains("LANIUS_GENERATED_GATE_COMMAND_TIMEOUT_MS        default 120000")
            && acceptance.contains("LANIUS_X86_READBACK_TIMEOUT_MS                  default 60000"),
        "{} generated gate defaults must stay small and bounded",
        acceptance_path.display()
    );
    assert!(
        acceptance.contains("run_focused()") && acceptance.contains("cargo check --lib -j1"),
        "{} must keep a small CPU-only focused checkpoint",
        acceptance_path.display()
    );
    assert!(
        acceptance.contains("--allow-scale")
            && acceptance.contains("LANIUS_ACCEPTANCE_ALLOW_SCALE")
            && acceptance.contains("require_scale_opt_in()"),
        "{} must require a second opt-in before running scale/performance lanes",
        acceptance_path.display()
    );
    let focused = source_between(&acceptance, "run_focused() {", "run_smoke() {");
    assert!(
        focused.contains("testing_strategy_commands_stay_focused_and_explicit")
            && focused
                .contains("compiler_acceptance_default_is_dry_run_focused_without_scale_work")
            && focused.contains("shader_loop_budgets")
            && focused.contains("shader_tree_loop_budget_does_not_grow")
            && focused.contains("type_checker_shader_loop_budget_does_not_grow"),
        "focused acceptance must include CPU-only testing-strategy and shader-loop tripwires"
    );
    for line in acceptance.lines() {
        let trimmed = line.trim_start();
        if trimmed.starts_with("run_cmd cargo test") {
            assert!(
                trimmed.contains("-j1"),
                "{} scripted cargo test line must be single-job: {trimmed}",
                acceptance_path.display()
            );
        }
    }

    let properties = source_between(&acceptance, "run_properties() {", "run_pareas() {");
    assert!(
        properties.contains("generated_x86_programs_are_name_and_shape_independent")
            && properties.contains("type_checker_accepts_generated_let_chain_from_hir_records")
            && properties
                .contains("type_checker_accepts_generated_call_argument_shapes_from_hir_records"),
        "property lane must run named property tests instead of whole GPU-heavy files"
    );
    assert!(
        !properties
            .contains("run_cmd cargo test --test codegen_x86_properties -- --test-threads=1")
            && !properties
                .contains("run_cmd cargo test --test type_checker_semantics -- --test-threads=1"),
        "property lane must not run entire GPU-heavy integration files"
    );
    assert!(
        generated_gates.contains("DEFAULT_GENERATED_GATE_COMMAND_TIMEOUT_MS")
            && generated_gates.contains("LANIUS_GENERATED_GATE_COMMAND_TIMEOUT_MS")
            && generated_gates.contains("const DEFAULT_GENERATED_LINES: &str = \"5000\"")
            && generated_gates.contains("const DEFAULT_CAPACITY_STRESS_LINES: &str = \"5000\"")
            && generated_gates
                .contains("const GENERATED_X86_READBACK_TIMEOUT_MS: &str = \"60000\"")
            && generated_gates
                .contains("const DEFAULT_GENERATED_GATE_COMMAND_TIMEOUT_MS: u64 = 120_000")
            && generated_gates.contains("child.try_wait()")
            && generated_gates.contains("child.kill()"),
        "{} must bound generated/Pareas subprocesses with a timeout watchdog",
        generated_gates_path.display()
    );
    assert!(
        !generated_gates.contains(".output()"),
        "{} generated/Pareas gates must not use unbounded Command::output()",
        generated_gates_path.display()
    );
    assert!(
        generated_gates.contains("const DEFAULT_PAREAS_COMPARE_ITERS: &str = \"1\"")
            && generated_gates.contains("LANIUS_PAREAS_COMPARE_ITERS")
            && generated_gates.contains("MAX_PAREAS_COMPARE_ITERS_WITHOUT_OPT_IN"),
        "{} Pareas comparison gate must default to one measured iteration with an explicit opt-in for more",
        generated_gates_path.display()
    );
}

#[cfg(unix)]
#[test]
fn compiler_acceptance_scale_lanes_require_second_opt_in_before_run() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let acceptance_path = root.join("tools/compiler_acceptance.sh");

    for tier in ["generated", "pareas", "all"] {
        let output = Command::new("bash")
            .arg(&acceptance_path)
            .arg("--tier")
            .arg(tier)
            .arg("--run")
            .output()
            .unwrap_or_else(|err| panic!("run {}: {err}", acceptance_path.display()));
        let stdout = String::from_utf8_lossy(&output.stdout);
        let stderr = String::from_utf8_lossy(&output.stderr);
        let combined = format!("{stdout}{stderr}");

        assert_eq!(
            output.status.code(),
            Some(2),
            "{} --tier {tier} --run must fail before executing scale work",
            acceptance_path.display()
        );
        assert!(
            combined.contains("requires --allow-scale")
                && combined.contains("LANIUS_ACCEPTANCE_ALLOW_SCALE=1"),
            "{} --tier {tier} --run should explain the scale opt-in",
            acceptance_path.display()
        );
        assert!(
            !combined.contains("+ cargo "),
            "{} --tier {tier} --run must not start Cargo before the scale opt-in",
            acceptance_path.display()
        );
    }
}

#[cfg(unix)]
#[test]
fn compiler_acceptance_default_is_dry_run_focused_without_scale_work() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let acceptance_path = root.join("tools/compiler_acceptance.sh");
    let output = Command::new("bash")
        .arg(&acceptance_path)
        .output()
        .unwrap_or_else(|err| panic!("run {}: {err}", acceptance_path.display()));
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    let combined = format!("{stdout}{stderr}");

    assert!(
        output.status.success(),
        "{} default dry-run failed:\n{combined}",
        acceptance_path.display()
    );
    assert!(
        combined.contains("tier=focused")
            && combined.contains("mode=dry-run")
            && combined.contains("cargo check --lib -j1")
            && combined.contains("architecture_contract_is_checked_in"),
        "{} default invocation must stay a focused dry-run checkpoint",
        acceptance_path.display()
    );
    for forbidden in [
        "generated_10k_gates",
        "generated_pareas_comparison_when_available",
        "--ignored",
        "--allow-large",
    ] {
        assert!(
            !combined.contains(forbidden),
            "{} default dry-run must not include scale/Pareas work marker {forbidden:?}",
            acceptance_path.display()
        );
    }
}

#[test]
fn backend_shape_recognizers_stay_quarantined() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let mut files = vec![root.join("src/compiler.rs")];
    collect_files(&root.join("src/codegen"), &mut files);
    collect_files(&root.join("shaders/codegen"), &mut files);
    files.sort();

    let mut violations = Vec::new();
    for path in files {
        let relative = path
            .strip_prefix(root)
            .expect("backend file should be under repo root")
            .to_string_lossy()
            .replace('\\', "/");
        if QUARANTINED_LEGACY_BACKEND_FILES.contains(&relative.as_str()) {
            continue;
        }
        let contents = fs::read_to_string(&path)
            .unwrap_or_else(|err| panic!("read {}: {err}", path.display()));
        for marker in BANNED_BACKEND_MARKERS {
            if contents.contains(marker) {
                violations.push(format!("{relative} contains {marker}"));
            }
        }
    }

    assert!(
        violations.is_empty(),
        "backend files must not add helper/body-shape recognizers outside the legacy quarantine:\n{}",
        violations.join("\n")
    );
}

#[test]
fn x86_decl_width_projection_uses_decl_records_not_subtree_scans() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let decl_widths_path = root.join("shaders/codegen/x86_decl_widths.slang");
    let decl_layout_path = root.join("shaders/codegen/x86_decl_layout.slang");
    let param_regs_path = root.join("shaders/codegen/x86_param_regs.slang");
    let decl_widths = fs::read_to_string(&decl_widths_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", decl_widths_path.display()));
    let decl_layout = fs::read_to_string(&decl_layout_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", decl_layout_path.display()));
    let param_regs = fs::read_to_string(&param_regs_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", param_regs_path.display()));

    for (path, source) in [
        (&decl_widths_path, decl_widths.as_str()),
        (&decl_layout_path, decl_layout.as_str()),
        (&param_regs_path, param_regs.as_str()),
    ] {
        assert!(
            !source.contains("array_type_width_for_decl_node")
                && !source.contains("first_array_type_width_in_subtree")
                && !source.contains("for (uint cursor =")
                && !source.contains("cursor < end && cursor < active_hir_node_count()"),
            "{} must not recover declaration widths by scanning whole HIR subtrees",
            path.display()
        );
    }
    assert!(
        decl_widths.contains("decl_type_ref_tag")
            && decl_widths.contains("decl_type_ref_payload")
            && decl_widths.contains("type_instance_kind")
            && decl_widths.contains("type_instance_len_kind"),
        "x86 declaration-width projection must consume declaration/type-instance record arrays"
    );
    assert!(
        decl_layout.contains("x86_decl_width_by_node")
            && decl_layout.contains("x86_decl_layout_record"),
        "x86 declaration-layout projection must consume the width record array and produce layout records"
    );
    assert!(
        param_regs.contains("decl_type_ref_tag")
            && param_regs.contains("decl_type_ref_payload")
            && param_regs.contains("write_param_reg_record("),
        "x86 parameter register projection must consume declaration/type-instance records and produce parameter-register records"
    );
}

#[test]
fn compiler_source_pack_input_model_lives_in_dedicated_module() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let compiler_path = root.join("src/compiler.rs");
    let compiler = fs::read_to_string(&compiler_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", compiler_path.display()));
    let inputs_path = root.join("src/compiler/source_pack_inputs.rs");
    let inputs = fs::read_to_string(&inputs_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", inputs_path.display()));

    assert!(
        compiler.contains("mod source_pack_inputs;")
            && compiler.contains("pub use source_pack_inputs::{")
            && compiler.contains("ExplicitSourcePack")
            && compiler.contains("ExplicitSourcePackPathManifest"),
        "compiler root must re-export the source-pack input API from a dedicated module"
    );
    for moved_type in [
        "pub struct ExplicitSourceLibrary",
        "pub struct ExplicitSourceLibraryPaths",
        "pub struct ExplicitSourceLibraryPathStream",
        "pub struct ExplicitSourceLibraryPathDependencyStream",
        "pub struct ExplicitSourcePathFile",
        "pub struct ExplicitSourcePackPathManifest",
        "pub struct ExplicitSourcePack",
    ] {
        assert!(
            inputs.contains(moved_type),
            "{} must own source-pack input type {moved_type:?}",
            inputs_path.display()
        );
        assert!(
            !compiler.contains(moved_type),
            "{} must not keep source-pack input type {moved_type:?} in the root execution module",
            compiler_path.display()
        );
    }
    assert!(
        inputs.contains("pub(super) fn validate_explicit_source_library_entries(")
            && compiler
                .contains("use source_pack_inputs::validate_explicit_source_library_entries;"),
        "library dependency validation must stay available to root-level streaming helpers without making it public API"
    );
    assert!(
        !inputs.contains("struct GpuCompiler")
            && !inputs.contains("execute_source_pack_filesystem_work_queue")
            && !inputs.contains("GpuSourcePackArtifactExecutor"),
        "source-pack input module must not absorb GPU execution or filesystem work-queue machinery"
    );
}

#[test]
fn source_pack_filesystem_prepare_uses_paged_artifact_refs() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let compiler_path = root.join("src/compiler.rs");
    let compiler = fs::read_to_string(&compiler_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", compiler_path.display()));
    let source_pack_inputs_path = root.join("src/compiler/source_pack_inputs.rs");
    let source_pack_inputs = fs::read_to_string(&source_pack_inputs_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", source_pack_inputs_path.display()));
    let artifact_descriptor_path = root.join("src/compiler/artifact_descriptor.rs");
    let artifact_descriptor = fs::read_to_string(&artifact_descriptor_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", artifact_descriptor_path.display()));
    let source_pack_records_path = root.join("src/compiler/source_pack_records.rs");
    let source_pack_records = fs::read_to_string(&source_pack_records_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", source_pack_records_path.display()));
    let work_queue_progress_path = root.join("src/compiler/work_queue_progress.rs");
    let work_queue_progress = fs::read_to_string(&work_queue_progress_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", work_queue_progress_path.display()));
    let build_progress_path = root.join("src/compiler/build_progress.rs");
    let build_progress = fs::read_to_string(&build_progress_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", build_progress_path.display()));
    let unit_path = root.join("src/codegen/unit.rs");
    let unit = fs::read_to_string(&unit_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", unit_path.display()));
    let bench_path = root.join("src/bin/gpu_compile_bench.rs");
    let bench = fs::read_to_string(&bench_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", bench_path.display()));
    let source_pack_surface = format!(
        "{compiler}\n{source_pack_inputs}\n{artifact_descriptor}\n{source_pack_records}\n{work_queue_progress}\n{build_progress}"
    );

    for required in [
        "SourcePackBuildArtifactRefIndex",
        "SourcePackBuildArtifactRefPage",
        "SourcePackLibraryScheduleJobPage",
        "SourcePackLibraryScheduleJobDependencyPage",
        "SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_PAGE_VERSION",
        "SourcePackJobBatchDependencyRange",
        "SourcePackBuildJobBatchDependencyPage",
        "SourcePackBuildJobBatchDependencyRangePage",
        "SOURCE_PACK_BUILD_JOB_BATCH_INLINE_JOB_DEFAULT_RECORD_CAP",
        "SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_PAGE_VERSION",
        "SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_PAGE_VERSION",
        "SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE",
        "SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE",
        "store_build_job_batch_dependency_page",
        "store_build_job_batch_dependency_range_page",
        "load_build_job_batch_dependency_page_for_target",
        "load_build_job_batch_dependency_range_page_for_target",
        "store_source_pack_build_job_batch_dependency_pages",
        "store_source_pack_build_job_batch_dependency_range_pages",
        "source_pack_for_each_stored_job_batch_dependency_index",
        "SourcePackBuildJobBatchDependentsPage",
        "SourcePackBuildJobBatchDependentBatchPage",
        "SourcePackLinkInputShardRange",
        "SourcePackWorkQueueDependenciesPage",
        "SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_PAGE_VERSION",
        "SourcePackWorkQueueDependentsPage",
        "SOURCE_PACK_WORK_QUEUE_DEPENDENTS_PAGE_VERSION",
        "SourcePackHierarchicalLinkExecutionInterfacePage",
        "SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_PAGE_VERSION",
        "store_hierarchical_link_execution_interface_page",
        "load_hierarchical_link_execution_interface_page_for_target",
        "SourcePackLibraryFrontendJobLocatorPage",
        "SOURCE_PACK_LIBRARY_FRONTEND_JOB_LOCATOR_PAGE_VERSION",
        "SourcePackLibraryPartitionLocatorPage",
        "SOURCE_PACK_LIBRARY_PARTITION_LOCATOR_PAGE_VERSION",
        "SourcePackLibraryDependencyPage",
        "SOURCE_PACK_LIBRARY_DEPENDENCY_PAGE_VERSION",
        "SOURCE_PACK_READY_STATE_BATCH_DEFAULT_LIMIT",
        "SourcePackLibraryCodegenUnitPage",
        "SOURCE_PACK_LIBRARY_CODEGEN_UNIT_PAGE_VERSION",
        "SourcePackLibrarySourceFileRecordPage",
        "SOURCE_PACK_LIBRARY_SOURCE_FILE_RECORD_PAGE_VERSION",
        "store_source_pack_library_source_file_record_pages_from_paths",
        "source_pack_compact_library_source_file_page_from_partition",
        "load_library_source_file_record_page_for_target",
        "try_for_each_from_fallible_files",
        "SourcePackStoredBuildUnitSummaryBuilder",
        "source_pack_summarize_library_build_units_from_stored_source_file_records",
        "pub job_batch_shard_count: usize",
        "pub completed_batch_count: usize",
        "let library_schedule_index = SourcePackLibraryScheduleIndex",
        "store_library_partition_compact_index",
        "store_library_partition_locator_page",
        "store_source_pack_library_dependency_pages",
        "load_library_dependency_page_for_target",
        "source_pack_load_library_dependency_ids",
        "source_pack_write_library_dependency_frontend_job_ranges",
        "store_source_pack_library_schedule_job_page_with_dependency_writer",
        "SourcePackLibraryFrontendUnitPage",
        "SOURCE_PACK_LIBRARY_FRONTEND_UNIT_PAGE_VERSION",
        "store_source_pack_library_frontend_unit_pages_from_stored_source_file_records",
        "load_library_frontend_unit_page_for_target",
        "pub frontend_job_count: usize",
        "source_pack_library_schedule_index_frontend_job_count",
        "source_pack_for_each_stored_schedule_frontend_job",
        "store_source_pack_library_codegen_unit_pages_from_stored_source_file_records",
        "source_pack_compact_library_build_unit_page_from_stored_source_file_records",
        "source_pack_library_schedule_page_with_stored_codegen_units",
        "source_pack_library_schedule_page_with_stored_codegen_units_from_partition_dependencies",
        "load_source_file_for_index",
        "load_source_files_for_range",
        "store_source_pack_build_artifact_ref_pages_from_stored_schedule_pages",
        "store_source_pack_build_link_batch_pages_from_stored_artifact_ref_pages",
        "store_source_pack_job_batch_dependents_pages_from_stored_job_batch_pages",
        "source_pack_for_each_job_batch_dependent_index",
        "load_build_job_batch_dependents_page_with_embedded_count_for_target",
        "SourcePackStoredJobBatchPagesPrepareResult",
        "store_source_pack_library_schedule_job_page",
        "store_source_pack_library_schedule_job_dependency_pages",
        "load_library_schedule_job_dependency_page_for_target",
        "source_pack_load_schedule_job_dependencies",
        "source_pack_write_work_queue_dependencies_from_stored_schedule_job",
        "source_pack_stored_schedule_job_metadata",
        "source_pack_for_each_stored_schedule_frontend_job",
        "source_pack_stored_codegen_job_dependency_count",
        "source_pack_schedule_job_page_dependency_count",
        "SourcePackJobIndexRange",
        "dependency_job_ranges",
        "input_interface_ranges",
        "SourcePackJobArtifactInputInterfacePage",
        "store_source_pack_job_artifact_input_interface_pages_from_stored_schedule_dependencies",
        "source_pack_execution_shard_job_input_interface_refs",
        "SourcePackPathPagedArtifactBuildExecutor",
        "SourcePackPathAsyncPagedArtifactBuildExecutor",
        "SourcePackPathPagedHierarchicalLinkExecutor",
        "SourcePackPathAsyncHierarchicalLinkExecutor",
        "SourcePackPathAsyncPagedHierarchicalLinkExecutor",
        "SourcePackFilesystemArtifactPath",
        "SourcePackFilesystemArtifactPathStore",
        "mod artifact_descriptor;",
        "GPU_SOURCE_PACK_ARTIFACT_DESCRIPTOR_VERSION",
        "GpuSourcePackDependencyInterfaceSummary",
        "GpuSourcePackArtifactDescriptor",
        "partial_link_contract_for_page",
        "hierarchical_linked_output_contract_for_page",
        "GpuSourcePackArtifactExecutor",
        "impl<'compiler, 'gpu> SourcePackPathAsyncHierarchicalLinkExecutor",
        "submit_path_artifact_work_queue_step",
        "submit_path_artifact_work_queue_step_async",
        "submit_gpu_descriptor_work_queue_step_using",
        "execute_prepared_source_pack_filesystem_work_queue_worker_step_with_gpu_descriptors_for_target",
        "execute_prepared_source_pack_filesystem_work_queue_worker_step_to_wasm_with_gpu_descriptors",
        "execute_prepared_source_pack_filesystem_work_queue_worker_step_to_x86_64_with_gpu_descriptors",
        "execute_prepared_source_pack_filesystem_work_queue_worker_run_with_gpu_descriptors_for_target",
        "execute_prepared_source_pack_filesystem_work_queue_worker_run_to_wasm_with_gpu_descriptors",
        "execute_prepared_source_pack_filesystem_work_queue_worker_run_to_x86_64_with_gpu_descriptors",
        "execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_with_gpu_descriptors_for_target",
        "execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_to_wasm_with_gpu_descriptors",
        "execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_to_x86_64_with_gpu_descriptors",
        "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_with_gpu_descriptors_for_target",
        "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_with_gpu_descriptors_for_target",
        "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors",
        "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_to_wasm_with_gpu_descriptors",
        "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_to_x86_64_with_gpu_descriptors",
        "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_to_x86_64_with_gpu_descriptors",
        "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_with_gpu_descriptors_for_target",
        "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_with_gpu_descriptors_for_target",
        "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors",
        "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_to_wasm_with_gpu_descriptors",
        "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_to_x86_64_with_gpu_descriptors",
        "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_to_x86_64_with_gpu_descriptors",
        "execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_with_gpu_descriptors_for_target",
        "execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_with_gpu_descriptors_for_target",
        "execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors",
        "execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_to_wasm_with_gpu_descriptors",
        "execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_to_x86_64_with_gpu_descriptors",
        "execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_to_x86_64_with_gpu_descriptors",
        "copy_source_pack_filesystem_artifact_file_atomically",
        "execute_source_pack_build_artifact_execution_shard_batch_paged",
        "execute_source_pack_build_artifact_execution_shard_batch_paged_async",
        "execute_source_pack_build_artifact_execution_shard_job_paged",
        "execute_source_pack_build_artifact_execution_shard_job_paged_async",
        "execute_source_pack_link_input_interface_shards_async",
        "execute_source_pack_link_input_object_shards_async",
        "execute_source_pack_hierarchical_link_execution_page_async",
        "source_pack_for_each_execution_shard_job_input_interface_batch",
        "execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_for_target_at",
        "execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_with_path_artifacts_for_target_at",
        "execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_async_for_target_at",
        "execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_async_with_path_artifacts_for_target_at",
        "execute_source_pack_filesystem_artifact_manifest_worker_step_async_for_target_at",
        "execute_source_pack_filesystem_artifact_manifest_worker_step_async_with_path_artifacts_for_target_at",
        "execute_source_pack_filesystem_artifact_manifest_worker_run_async",
        "execute_source_pack_filesystem_artifact_manifest_worker_run_async_for_target",
        "execute_source_pack_filesystem_artifact_manifest_worker_run_async_for_target_at",
        "execute_source_pack_filesystem_artifact_manifest_worker_run_async_with_path_artifacts",
        "execute_source_pack_filesystem_artifact_manifest_worker_run_async_with_path_artifacts_for_target",
        "execute_source_pack_filesystem_artifact_manifest_worker_run_async_with_path_artifacts_for_target_at",
        "execute_source_pack_filesystem_artifact_manifest_worker_run_with_path_artifacts_for_target",
        "execute_source_pack_filesystem_work_queue_claimed_item_with_path_artifacts_for_target_at",
        "execute_source_pack_filesystem_work_queue_claimed_link_item_with_path_artifacts_for_target_at",
        "execute_source_pack_filesystem_work_queue_worker_run_with_path_artifacts_for_target",
        "execute_source_pack_filesystem_work_queue_claimed_artifact_item_async_with_path_artifacts_for_target_at",
        "execute_source_pack_filesystem_work_queue_claimed_item_async_with_path_artifacts_for_target_at",
        "execute_source_pack_filesystem_work_queue_claimed_link_item_async_with_path_artifacts_for_target_at",
        "execute_source_pack_filesystem_work_queue_worker_step_async_with_path_artifacts_for_target_at",
        "execute_source_pack_filesystem_work_queue_worker_run_async_with_path_artifacts",
        "execute_source_pack_filesystem_work_queue_worker_run_async_with_path_artifacts_for_target",
        "execute_source_pack_filesystem_work_queue_worker_run_async_with_path_artifacts_for_target_at",
        "execute_source_pack_filesystem_work_queue_claimed_artifact_item_paged_for_target_at",
        "source_pack_for_each_link_input_shard_index",
        "source_pack_singleton_artifact_batch_index_for_job_from_stored_locator",
        "source_pack_library_partition_for_source_index_from_stored_pages",
        "source_pack_artifact_refs_for_indices_from_stored_pages",
        "source_pack_extend_link_input_shard_range",
        "source_pack_build_progress_first_ready_batch_index_from_summary_pages_bounded",
        "source_pack_build_progress_directory_page_from_store_or_summaries",
        "source_pack_build_progress_directory_index_page_from_store_or_directory_pages",
        "source_pack_build_progress_earliest_claim_lease_from_summary_shards_bounded",
        "source_pack_build_progress_summary_ready_batches_are_claimed",
        "pub ready_claimed_batch_count: usize",
        "source_pack_work_queue_progress_ready_unclaimed_item_indices_from_index_limited",
        "source_pack_work_queue_progress_page_summary_from_index_or_store",
        "source_pack_work_queue_progress_directory_index_page_from_changes_or_store",
        "source_pack_filesystem_work_queue_final_linked_output_for_progress",
        "SourcePackInitialWorkQueueProgressPageWriter",
        "source_pack_work_queue_append_dependent_page",
        "store_source_pack_work_queue_page_with_dependency_writer",
        "source_pack_for_each_work_queue_dependency_item",
        "source_pack_for_each_work_queue_dependent_item",
        "store_path_build_manifest_with_shard_limits",
        "store_source_pack_hierarchical_link_execution_interface_pages_from_stored_leaf_group",
        "source_pack_for_each_stored_schedule_codegen_job",
        "prepare_ordered_explicit_source_libraries_filesystem_artifact_build_for_target",
        "prepare_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits_for_target",
        "execute_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits_for_target",
        "execute_ordered_explicit_source_libraries_filesystem_artifact_build_worker_run_for_target",
        "execute_ordered_explicit_source_libraries_filesystem_artifact_build_worker_run_with_shard_limits_for_target",
        "execute_ordered_explicit_source_libraries_filesystem_artifact_build_worker_run_with_path_artifacts_for_target",
        "execute_ordered_explicit_source_libraries_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target",
        "execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_run_with_path_artifacts_for_target",
        "execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target",
        "execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_with_path_artifacts_for_target",
        "execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target",
        "execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_run_async_with_path_artifacts_for_target",
        "execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target",
        "execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_async_with_path_artifacts_for_target",
        "execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target",
        "source_pack_prepare_ordered_library_schedule_pages_from_explicit_source_libraries",
        "ExplicitSourceLibraryPathStream",
        "prepare_ordered_explicit_source_library_path_streams_filesystem_artifact_build_for_target",
        "prepare_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits_for_target",
        "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_for_target",
        "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits_for_target",
        "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_for_target",
        "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_worker_run_with_path_artifacts_for_target",
        "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target",
        "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_with_path_artifacts_for_target",
        "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target",
        "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_with_path_artifacts_for_target",
        "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target",
        "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_path_artifacts_for_target",
        "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target",
        "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_path_artifacts_for_target",
        "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target",
        "source_pack_prepare_ordered_library_schedule_pages_from_explicit_source_library_path_streams",
        "ExplicitSourceLibraryPathDependencyStream",
        "prepare_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target",
        "execute_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target",
        "execute_explicit_source_pack_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_for_target",
        "execute_explicit_source_pack_path_streams_filesystem_artifact_build_worker_run_with_path_artifacts_for_target",
        "execute_explicit_source_pack_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target",
        "execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_with_path_artifacts_for_target",
        "execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target",
        "execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_with_path_artifacts_for_target",
        "execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target",
        "execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_path_artifacts_for_target",
        "execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target",
        "execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_path_artifacts_for_target",
        "execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target",
        "execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_with_path_artifacts_for_target",
        "execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target",
        "execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_with_path_artifacts_for_target",
        "execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target",
        "execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_async_with_path_artifacts_for_target",
        "execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target",
        "execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_async_with_path_artifacts_for_target",
        "prepare_explicit_source_pack_paths_filesystem_artifact_build_with_shard_limits_for_target",
        "execute_explicit_source_pack_paths_filesystem_artifact_build_with_shard_limits_for_target",
        "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_for_target",
        "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target",
        "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_for_target",
        "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target",
        "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_worker_run_with_shard_limits_for_target",
        "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_worker_run_with_path_artifacts_for_target",
        "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target",
        "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_with_path_artifacts_for_target",
        "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target",
        "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_with_path_artifacts_for_target",
        "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target",
        "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_async_with_path_artifacts_for_target",
        "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target",
        "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_async_with_path_artifacts_for_target",
        "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target",
        "source_pack_prepare_ordered_library_schedule_pages_from_explicit_source_library_path_dependency_streams",
        "store_source_pack_library_dependency_pages_from_ids",
        "source_pack_filesystem_artifact_manifest_ready_state_batches_limited_for_target",
        "SOURCE_PACK_ARTIFACT_MANIFEST_FULL_BUILD_DEFAULT_BATCH_LIMIT",
        "prepare_explicit_source_pack_path_streams_filesystem_metadata_for_target",
        "prepare_ordered_explicit_source_libraries_filesystem_metadata_for_target",
        "source_pack_prepare_ordered_library_metadata_pages_from_explicit_source_libraries",
        "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_for_target",
        "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_for_target",
        "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_from_progress_for_target",
        "source_pack_prepare_ordered_library_metadata_pages_from_explicit_source_library_path_dependency_streams",
        "SOURCE_PACK_LIBRARY_METADATA_PREPARE_DEFAULT_CHUNK_LIMIT",
        "SOURCE_PACK_LIBRARY_METADATA_FULL_PREPARE_DEFAULT_LIBRARY_LIMIT",
        "SOURCE_PACK_LIBRARY_METADATA_PREPARE_DEFAULT_SOURCE_FILE_LIMIT",
        "SOURCE_PACK_LIBRARY_METADATA_PREPARE_DEFAULT_DEPENDENCY_LIMIT",
        "SourcePackFilesystemLibraryMetadataPrepareStepResult",
        "SourcePackFilesystemLibrarySchedulePrepareStepResult",
        "SourcePackFilesystemArtifactRefPrepareStepResult",
        "SourcePackFilesystemJobBatchPrepareStepResult",
        "SourcePackFilesystemJobBatchDependentsPrepareStepResult",
        "SourcePackFilesystemArtifactShardPrepareStepResult",
        "SourcePackFilesystemLinkBatchPrepareStepResult",
        "SourcePackFilesystemHierarchicalLinkLeafPrepareStepResult",
        "SourcePackFilesystemHierarchicalLinkPlanPrepareStepResult",
        "SourcePackFilesystemHierarchicalLinkExecutionPrepareStepResult",
        "SourcePackFilesystemWorkQueuePrepareStepResult",
        "SourcePackFilesystemWorkQueueProgressPrepareStepResult",
        "SourcePackFilesystemArtifactBuildPrepareStage",
        "SourcePackFilesystemArtifactBuildPrepareStepResult",
        "pub new_library_count: usize",
        "pub new_library_build_unit_page_count: usize",
        "prepare_source_pack_filesystem_library_schedule_from_metadata_chunk_for_target",
        "prepare_source_pack_filesystem_artifact_refs_from_schedule_chunk_for_target",
        "prepare_source_pack_filesystem_job_batches_from_schedule_chunk_for_target",
        "prepare_source_pack_filesystem_job_batch_dependents_from_batches_chunk_for_target",
        "prepare_source_pack_filesystem_artifact_shards_from_batches_chunk_for_target",
        "prepare_source_pack_filesystem_link_batches_from_artifact_refs_chunk_for_target",
        "prepare_source_pack_filesystem_hierarchical_link_leaf_groups_from_schedule_chunk_for_target",
        "prepare_source_pack_filesystem_hierarchical_link_plan_reduce_groups_from_schedule_chunk_for_target",
        "prepare_source_pack_filesystem_hierarchical_link_execution_from_plan_chunk_for_target",
        "prepare_source_pack_filesystem_work_queue_pages_from_schedule_chunk_for_target",
        "prepare_source_pack_filesystem_work_queue_progress_from_queue_chunk_for_target",
        "prepare_source_pack_filesystem_artifact_build_from_metadata_chunk_with_shard_limits_for_target",
        "SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_FULL_PREPARE_DEFAULT_STEP_LIMIT",
        "SourcePackHierarchicalLinkPlanPrepareProgress",
        "SourcePackHierarchicalLinkExecutionPrepareProgress",
        "SourcePackWorkQueuePrepareProgress",
        "SourcePackInitialWorkQueueProgressPrepareProgress",
        "SourcePackJobBatchDependentsPrepareProgress",
        "SourcePackBuildArtifactShardPrepareProgress",
        "pub library_partition_count: usize",
        "pub library_source_file_page_count: usize",
        "pub library_build_unit_page_count: usize",
        "pub library_schedule_page_count: usize",
        "pub artifact_shard_count: usize",
        "pub artifact_execution_shard_count: usize",
        "pub batch_shard_locator_count: usize",
        "pub build_progress_shard_count: usize",
        "let mut executed_batch_count = 0usize;",
        "library_dependencies: Vec::new()",
        "completed_batch_count: summary.completed_batch_count",
        "let mut executed_item_count = 0usize;",
        "let mut newly_ready_item_count = 0usize;",
    ] {
        assert!(
            source_pack_surface.contains(required),
            "filesystem source-pack prepare must retain paged artifact-ref stage {required:?}"
        );
    }
    assert!(
        !compiler.contains("source_pack_library_schedule_output_refs_from_stored_pages"),
        "filesystem source-pack prepare must not rebuild a whole-schedule output-ref map"
    );
    let execution_shard_validation = source_between(
        &compiler,
        "fn validate_source_pack_build_artifact_execution_shard_with_mode",
        "fn source_pack_build_artifact_execution_shard_materialized_artifact_indices",
    );
    assert!(
        execution_shard_validation
            .contains("SourcePackBuildArtifactExecutionShardValidationMode::Persisted =>")
            && execution_shard_validation.contains("shard.artifact_record_count()")
            && execution_shard_validation
                .contains("SourcePackBuildArtifactExecutionShardValidationMode::StoreInput")
            && execution_shard_validation.contains("shard.artifact_count()"),
        "persisted execution-shard validation must cap retained artifact-ref records without expanding artifact ranges"
    );
    let execution_shard_store = source_between(
        &compiler,
        "fn store_build_artifact_execution_shard_with_batch_count",
        "    fn store_job_artifact_input_interface_pages_from_refs",
    );
    assert!(
        execution_shard_store.contains("source_pack_prune_persisted_execution_shard_artifact_refs")
            && execution_shard_store.contains("input_interface_artifact_ranges"),
        "filesystem execution-shard storage must prune expanded range refs while retaining ranged dependency records"
    );
    let execution_shard_from_pages = source_between(
        &compiler,
        "fn source_pack_build_artifact_execution_shard_from_stored_pages",
        "fn source_pack_stored_source_file_for_index",
    );
    assert!(
        execution_shard_from_pages.contains("input_artifact_indices")
            && execution_shard_from_pages.contains("output_artifact_indices")
            && !execution_shard_from_pages.contains("input_artifact_ranges"),
        "execution shards rebuilt from persisted pages must load retained artifact refs, not expanded range refs"
    );
    let paged_input_interface_loader = source_between(
        &compiler,
        "fn source_pack_for_each_execution_shard_job_input_interface_batch",
        "fn execute_source_pack_build_artifact_execution_shard_link_job",
    );
    assert!(
        paged_input_interface_loader.contains("input_interface_artifact_ranges")
            && paged_input_interface_loader.contains("load_build_artifact_ref_page"),
        "paged job input-interface loading must stream ranged artifact inputs from artifact-ref pages"
    );
    let paged_input_interface_ref_loader = source_between(
        &compiler,
        "fn source_pack_execution_shard_job_input_interface_ref",
        "fn source_pack_for_each_execution_shard_job_input_interface_batch",
    );
    assert!(
        paged_input_interface_ref_loader.contains("input_interface_artifact_ranges")
            && paged_input_interface_ref_loader.contains("range.contains(producing_job_index)")
            && !paged_input_interface_ref_loader.contains("for artifact_index in indices"),
        "single ranged interface-ref lookup must use range containment and one artifact-ref page load, not scan expanded artifact ranges"
    );
    let library_unit_plan = source_between(
        &unit,
        "impl LibraryUnitPlan",
        "#[derive(Clone, Debug, PartialEq, Eq)]\npub struct SourcePackJobPlan",
    );
    assert!(
        library_unit_plan.contains("pub fn try_for_each_from_fallible_files"),
        "library-unit planning must expose a bounded streaming iterator"
    );
    assert!(
        library_unit_plan.contains("Self::try_for_each_from_files("),
        "library-unit plan constructors must route through bounded streaming"
    );
    assert!(
        !library_unit_plan.contains(".collect::<Vec<_>>()"),
        "library-unit plan constructors must not collect every source file before planning natural library units"
    );
    let frontend_unit_plan = source_between(
        &unit,
        "impl FrontendUnitPlan",
        "#[derive(Clone, Debug, PartialEq, Eq)]\npub struct SourcePackJobPlan",
    );
    assert!(
        frontend_unit_plan.contains("pub fn try_for_each_from_fallible_files"),
        "frontend-unit planning must expose a bounded streaming iterator"
    );
    assert!(
        frontend_unit_plan.contains("Self::try_for_each_from_files("),
        "frontend-unit plan constructors must route through bounded streaming"
    );
    assert!(
        frontend_unit_plan.contains("current.take_frontend("),
        "frontend-unit planning must split library frontend work through bounded frontend units"
    );
    assert!(
        !frontend_unit_plan.contains(".collect::<Vec<_>>()"),
        "frontend-unit plan constructors must not collect every source file before planning bounded frontend units"
    );
    let codegen_unit_plan = source_between(
        &unit,
        "impl CodegenUnitPlan",
        "#[derive(Clone, Copy, Debug, Default)]\nstruct UnitBuilder",
    );
    assert!(
        codegen_unit_plan.contains("pub fn try_for_each_from_fallible_files"),
        "codegen-unit planning must expose a bounded streaming iterator"
    );
    assert!(
        codegen_unit_plan.contains("Self::try_for_each_from_files("),
        "codegen-unit plan constructors must route through bounded streaming"
    );
    assert!(
        !codegen_unit_plan.contains(".collect::<Vec<_>>()"),
        "codegen-unit plan constructors must not collect every source file before planning bounded codegen units"
    );
    let source_pack_job_plan_constructors = source_between(
        &unit,
        "impl SourcePackJobPlan",
        "    pub fn requires_multiple_codegen_jobs",
    );
    assert!(
        source_pack_job_plan_constructors
            .contains("pub fn try_from_fallible_file_stream_with_dependencies"),
        "source-pack job planning must expose a bounded fallible source-file-input stream"
    );
    assert!(
        source_pack_job_plan_constructors.contains("Self::from_file_stream_with_dependencies("),
        "source-pack job-plan constructors must route through one-pass source-file-input streaming"
    );
    assert!(
        !source_pack_job_plan_constructors.contains(".collect::<Vec<_>>()"),
        "source-pack job-plan constructors must not collect every source-file input before planning jobs"
    );
    let batch_dependency_plan = source_between(
        &unit,
        "impl SourcePackJobBatchDependencyPlan",
        "#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]\npub struct SourcePackJobWaveSchedule",
    );
    assert!(
        batch_dependency_plan.contains("pub fn ready_batch_count(")
            && batch_dependency_plan.contains("pub fn ready_batch_indices_limited(")
            && batch_dependency_plan.contains("pub fn ready_batch_count_with_completed_ranges(")
            && batch_dependency_plan
                .contains("pub fn ready_batch_indices_limited_with_completed_ranges(")
            && batch_dependency_plan.contains("max_batches: Option<usize>"),
        "in-memory batch dependency plans must expose count-only and caller-capped ready-frontier queries for explicit and ranged completion records"
    );
    assert!(
        !batch_dependency_plan.contains("pub fn ready_batch_indices("),
        "in-memory batch dependency plans must not expose an unbounded all-ready-batch convenience query"
    );
    let completed_range_dependency_query = source_between(
        &unit,
        "    pub fn dependencies_completed_by_ranges",
        "#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]\npub struct SourcePackJobBatchDependencyPlan",
    );
    assert!(
        completed_range_dependency_query
            .contains("completed_batch_ranges: &[SourcePackJobBatchDependencyRange]")
            && completed_range_dependency_query
                .contains("source_pack_job_batch_range_covered_by_ranges("),
        "ranged batch-dependency readiness must consume completed batch-range records"
    );
    assert!(
        !completed_range_dependency_query.contains("range.iter()"),
        "completed-range batch-dependency readiness must not expand every batch in a ranged dependency"
    );
    let bounded_frontend_schedule = source_between(
        &unit,
        "    pub fn bounded_frontend_job_schedule",
        "    pub fn build_plan",
    );
    assert!(
        bounded_frontend_schedule.contains("self.frontend_units_for_library(library)"),
        "bounded frontend scheduling must emit frontend jobs from bounded frontend-unit records"
    );
    assert!(
        bounded_frontend_schedule.contains("let mut frontend_unit_cursor = 0usize")
            && bounded_frontend_schedule.contains("self.frontend_unit_for_range_from_cursor("),
        "bounded frontend scheduling must attach codegen units to frontend-unit records with a monotonic cursor rather than repeated whole-plan scans"
    );
    assert!(
        !bounded_frontend_schedule.contains("source_file_count: library.source_file_count"),
        "bounded frontend scheduling must not size frontend jobs from whole-library source counts"
    );
    assert!(
        !bounded_frontend_schedule.contains("let codegen_job_indices = jobs")
            && bounded_frontend_schedule.contains("dependency_job_indices: Vec::new()"),
        "bounded frontend scheduling must not materialize every codegen job index on the link job"
    );
    assert!(
        bounded_frontend_schedule
            .contains("push_unique(&mut dependency_job_indices, library_job_index)")
            && bounded_frontend_schedule.contains("dependency_job_ranges_by_job_index")
            && bounded_frontend_schedule.contains("frontend_job_ranges_by_library_index")
            && bounded_frontend_schedule.contains("SourcePackJobIndexRange")
            && !bounded_frontend_schedule.contains("frontend_job_indices_by_library_index")
            && !bounded_frontend_schedule
                .contains("for &frontend_job_index in frontend_job_indices")
            && !bounded_frontend_schedule
                .contains("for &dependency_job_index in frontend_job_indices"),
        "bounded codegen jobs must keep their owning frontend as an explicit dependency and preserve same/dependency-library frontend fan-in as compact job ranges"
    );
    let bounded_frontend_helpers = source_between(
        &unit,
        "    fn frontend_units_for_library",
        "    fn topological_library_indices",
    );
    assert!(
        bounded_frontend_helpers.contains("impl Iterator<Item = &'a FrontendUnit>")
            && !bounded_frontend_helpers.contains(".collect"),
        "bounded frontend helper must stream frontend units for a library instead of collecting a per-library vector"
    );
    assert!(
        bounded_frontend_helpers.contains("frontend_unit_cursor: &mut usize")
            && bounded_frontend_helpers.contains(".get(*frontend_unit_cursor)")
            && !bounded_frontend_helpers.contains(".iter().find("),
        "bounded codegen-to-frontend attachment must use cursor lookup instead of a repeated scan from the first frontend unit"
    );
    let library_dependency_lookup = source_between(
        &unit,
        "    fn dependency_library_indices_for_library",
        "    fn frontend_units_for_library",
    );
    assert!(
        library_dependency_lookup.contains(") -> &'a [usize]")
            && library_dependency_lookup.contains(".map(Vec::as_slice)")
            && !library_dependency_lookup.contains(".cloned()")
            && !library_dependency_lookup.contains(".unwrap_or_default()"),
        "source-pack scheduling must borrow dependency-index records instead of cloning dependency lists for each scheduled library or codegen unit"
    );
    let source_pack_job_schedule = source_between(
        &unit,
        "impl SourcePackJobSchedule",
        "#[derive(Clone, Debug, PartialEq, Eq)]\npub struct SourcePackBuildPlan",
    );
    assert!(
        source_pack_job_schedule.contains("emitted_codegen_count")
            && source_pack_job_schedule.contains("codegen_job_count")
            && source_pack_job_schedule.contains("SourcePackJobPhase::Link")
            && source_pack_job_schedule.contains("codegen_batch_ranges")
            && source_pack_job_schedule.contains("dependency_batch_ranges"),
        "in-memory source-pack scheduling must handle the link job as an aggregate codegen barrier with ranged batch dependencies"
    );
    assert!(
        !source_pack_job_schedule.contains("let mut codegen_batch_indices"),
        "in-memory batch-dependency planning must not materialize every codegen batch index before recording link dependencies"
    );
    let bounded_frontend_build_plan = source_between(
        &unit,
        "    pub fn bounded_frontend_build_plan",
        "    fn library_dependency_index",
    );
    assert!(
        bounded_frontend_build_plan
            .contains("self.build_plan_for_schedule(self.bounded_frontend_job_schedule())"),
        "bounded frontend build planning must derive artifacts from the bounded frontend schedule"
    );
    let batch_limit_default = source_between(
        &unit,
        "impl Default for SourcePackJobBatchLimits",
        "impl SourcePackJobBatchLimits",
    );
    assert!(
        batch_limit_default
            .contains("Self::from_codegen_unit_limits(CodegenUnitLimits::default())"),
        "source-pack batch limits must default to bounded codegen-unit limits"
    );
    assert!(
        !batch_limit_default.contains("usize::MAX"),
        "source-pack batch-limit defaults must not create unbounded execution/link batches"
    );
    let batch_limit_normalize = source_between(
        &unit,
        "impl SourcePackJobBatchLimits",
        "#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]\npub struct SourcePackJobBatch",
    );
    assert!(
        batch_limit_normalize.contains("let record_caps = Self::from_codegen_unit_limits")
            && batch_limit_normalize.contains("CodegenUnitLimits::default()")
            && batch_limit_normalize.contains(".min(record_caps.max_jobs_per_batch)")
            && batch_limit_normalize.contains(".min(record_caps.max_source_bytes_per_batch)")
            && batch_limit_normalize.contains(".min(record_caps.max_source_files_per_batch)"),
        "source-pack job-batch limits must normalize caller limits down to bounded record caps"
    );
    let explicit_source_pack_execution = source_between(
        &source_pack_inputs,
        "impl ExplicitSourcePack {",
        "impl ExplicitSourcePackPathManifest",
    );
    assert!(
        explicit_source_pack_execution.contains("self.bounded_frontend_build_plan(limits)"),
        "explicit source-pack execution must use bounded frontend build plans by default"
    );
    let explicit_source_pack_build_plan = source_between(
        explicit_source_pack_execution,
        "    pub fn build_plan",
        "    pub fn whole_library_frontend_build_plan",
    );
    assert!(
        explicit_source_pack_build_plan.contains("self.bounded_frontend_build_plan(limits)")
            && !explicit_source_pack_build_plan.contains("self.job_plan(limits).build_plan()"),
        "explicit source-pack build_plan must default to bounded frontend jobs"
    );
    let explicit_source_pack_whole_library_build_plan = source_between(
        explicit_source_pack_execution,
        "    pub fn whole_library_frontend_build_plan",
        "    pub fn bounded_frontend_build_plan",
    );
    assert!(
        explicit_source_pack_whole_library_build_plan
            .contains("self.job_plan(limits).build_plan()"),
        "explicit source packs must make whole-library frontend planning opt-in and visibly named"
    );
    assert!(
        !explicit_source_pack_execution.contains("let build_plan = self.build_plan(limits);"),
        "explicit source-pack execution must not silently use whole-library frontend jobs"
    );
    let explicit_source_pack_compact_manifest = source_between(
        &source_pack_inputs,
        "    pub fn compact_build_artifact_manifest_for_target",
        "    pub fn source_slice_for_unit",
    );
    assert!(
        explicit_source_pack_compact_manifest.contains("self.job_plan(limits)")
            && explicit_source_pack_compact_manifest
                .contains("let schedule = plan.bounded_frontend_job_schedule()")
            && explicit_source_pack_compact_manifest
                .contains(".try_compact_build_artifact_manifest_for_schedule("),
        "explicit source packs must expose compact artifact manifests from bounded job-plan schedules"
    );
    assert!(
        !explicit_source_pack_compact_manifest.contains("build_plan(limits)")
            && !explicit_source_pack_compact_manifest.contains("bounded_frontend_build_plan"),
        "explicit source-pack compact manifests must not construct retained build plans"
    );
    let explicit_path_manifest = source_between(
        &source_pack_inputs,
        "impl ExplicitSourcePackPathManifest",
        "    pub fn library_partition_index_for_target",
    );
    assert!(
        explicit_path_manifest.contains("pub fn source_file_input_iter(&self)"),
        "path manifests must expose source-file unit records as an iterator"
    );
    assert!(
        explicit_path_manifest
            .contains("CodegenUnitPlan::try_for_each_from_files(self.source_file_input_iter(),"),
        "path-manifest codegen planning must consume source-file records through the bounded codegen-unit iterator"
    );
    assert!(
        explicit_path_manifest
            .contains("FrontendUnitPlan::try_for_each_from_files(self.source_file_input_iter(),"),
        "path-manifest frontend planning must consume source-file records through the bounded frontend-unit iterator"
    );
    assert!(
        explicit_path_manifest.contains("pub fn bounded_frontend_build_plan"),
        "path manifests must expose a bounded frontend build-plan surface"
    );
    let explicit_path_manifest_build_plan = source_between(
        explicit_path_manifest,
        "    pub fn build_plan",
        "    pub fn whole_library_frontend_build_plan",
    );
    assert!(
        explicit_path_manifest_build_plan.contains("self.bounded_frontend_build_plan(limits)")
            && !explicit_path_manifest_build_plan.contains("self.job_plan(limits).build_plan()"),
        "path-manifest build_plan must default to bounded frontend jobs"
    );
    let explicit_path_manifest_whole_library_build_plan = source_between(
        explicit_path_manifest,
        "    pub fn whole_library_frontend_build_plan",
        "    pub fn bounded_frontend_build_plan",
    );
    assert!(
        explicit_path_manifest_whole_library_build_plan
            .contains("self.job_plan(limits).build_plan()"),
        "path manifests must make whole-library frontend planning opt-in and visibly named"
    );
    assert!(
        explicit_path_manifest.contains("pub fn compact_build_artifact_manifest_for_target")
            && explicit_path_manifest.contains("self.job_plan(limits)")
            && explicit_path_manifest
                .contains("let schedule = plan.bounded_frontend_job_schedule()")
            && explicit_path_manifest
                .contains(".try_compact_build_artifact_manifest_for_schedule("),
        "path manifests must expose compact artifact manifests directly from metadata-backed bounded job plans"
    );
    assert!(
        explicit_path_manifest.contains("SourcePackJobPlan::from_file_stream_with_dependencies("),
        "path-manifest job planning must consume source-file records through the one-pass job-plan stream"
    );
    assert!(
        !explicit_path_manifest.contains("CodegenUnitPlan::from_files(&self.source_file_inputs()"),
        "path-manifest codegen planning must not build a source-file-input Vec first"
    );
    assert!(
        !explicit_path_manifest.contains("FrontendUnitPlan::from_files(&self.source_file_inputs()"),
        "path-manifest frontend planning must not build a source-file-input Vec first"
    );
    assert!(
        !explicit_path_manifest.contains("&self.source_file_inputs(),"),
        "path-manifest job planning must not pass a freshly collected source-file-input Vec"
    );
    let explicit_path_manifest_execution = source_between(
        &source_pack_inputs,
        "    pub fn library_partition_index_for_target",
        "fn validate_explicit_source_library_entries",
    );
    assert!(
        explicit_path_manifest_execution.contains("self.bounded_frontend_build_plan(limits)"),
        "path-manifest execution must use bounded frontend build plans by default"
    );
    assert!(
        !explicit_path_manifest_execution.contains("let build_plan = self.build_plan(limits);"),
        "path-manifest execution must not silently use whole-library frontend jobs"
    );
    let source_pack_compact_artifact_manifest_planning = source_between(
        &compiler,
        "pub fn plan_explicit_source_pack_compact_artifact_manifest_from_paths",
        "pub fn plan_explicit_source_libraries_build_from_paths",
    );
    assert!(
        source_pack_compact_artifact_manifest_planning
            .contains("plan_explicit_source_pack_compact_artifact_manifest_from_path_metadata(")
            && source_pack_compact_artifact_manifest_planning
                .contains("plan_explicit_source_pack_path_streams_compact_artifact_manifest_from_path_metadata(")
            && source_pack_compact_artifact_manifest_planning
                .contains("stdlib_paths.iter().map(|path| path.as_ref())")
            && source_pack_compact_artifact_manifest_planning
                .contains("user_paths.iter().map(|path| path.as_ref())"),
        "stdlib/user path compact artifact-manifest planning must stream path metadata into compact job-plan summaries"
    );
    assert!(
        !source_pack_compact_artifact_manifest_planning.contains(".build_plan(limits)")
            && !source_pack_compact_artifact_manifest_planning
                .contains(".bounded_frontend_build_plan(limits)")
            && !source_pack_compact_artifact_manifest_planning
                .contains(".build_artifact_manifest(")
            && !source_pack_compact_artifact_manifest_planning
                .contains("load_explicit_source_pack_path_manifest_from_paths"),
        "stdlib/user path compact artifact-manifest planning must not construct retained path manifests, build plans, or full manifests"
    );
    let source_libraries_compact_artifact_manifest_planning = source_between(
        &compiler,
        "pub fn plan_explicit_source_libraries_compact_artifact_manifest_from_paths",
        "pub fn execute_explicit_source_pack_paths_artifact_store_build",
    );
    assert!(
        source_libraries_compact_artifact_manifest_planning.contains(
            "plan_explicit_source_libraries_compact_artifact_manifest_from_path_metadata("
        ) && source_libraries_compact_artifact_manifest_planning.contains(
            "source_pack_ordered_library_path_dependency_streams_from_explicit_source_libraries("
        ) && source_libraries_compact_artifact_manifest_planning.contains(
            "source_pack_compact_artifact_manifest_from_ordered_library_path_dependency_streams("
        ),
        "library path compact artifact-manifest planning must stream ordered path metadata into compact job-plan summaries"
    );
    assert!(
        !source_libraries_compact_artifact_manifest_planning.contains(".build_plan(limits)")
            && !source_libraries_compact_artifact_manifest_planning
                .contains(".bounded_frontend_build_plan(limits)")
            && !source_libraries_compact_artifact_manifest_planning
                .contains(".build_artifact_manifest(")
            && !source_libraries_compact_artifact_manifest_planning
                .contains("load_explicit_source_libraries_path_manifest"),
        "library path compact artifact-manifest planning must not construct retained path manifests, build plans, or full manifests"
    );
    let source_libraries_stream_compact_artifact_manifest_planning = source_between(
        &compiler,
        "fn source_pack_compact_artifact_manifest_from_ordered_library_path_dependency_streams",
        "pub fn plan_explicit_source_pack_jobs_from_paths",
    );
    assert!(
        source_libraries_stream_compact_artifact_manifest_planning
            .contains("SourcePackJobPlanBuilder::new(limits)")
            && source_libraries_stream_compact_artifact_manifest_planning
                .contains("let mut library_count = 0usize")
            && source_libraries_stream_compact_artifact_manifest_planning
                .contains("if library_count == 0")
            && source_libraries_stream_compact_artifact_manifest_planning
                .contains("plan_builder.push(SourceFileUnitInput")
            && source_libraries_stream_compact_artifact_manifest_planning
                .contains("let plan = plan_builder.finish(&library_dependencies)")
            && source_libraries_stream_compact_artifact_manifest_planning
                .contains("read_explicit_source_path_metadata(")
            && source_libraries_stream_compact_artifact_manifest_planning
                .contains("let schedule = plan.bounded_frontend_job_schedule()")
            && source_libraries_stream_compact_artifact_manifest_planning
                .contains(".try_compact_build_artifact_manifest_for_schedule("),
        "streamed compact artifact-manifest planning must stat paths into source-file records and summarize a bounded job-plan schedule"
    );
    assert!(
        !source_libraries_stream_compact_artifact_manifest_planning
            .contains("read_explicit_source_path_files(")
            && !source_libraries_stream_compact_artifact_manifest_planning
                .contains("read_explicit_source_paths(")
            && !source_libraries_stream_compact_artifact_manifest_planning
                .contains("load_explicit_source_libraries_path_manifest")
            && !source_libraries_stream_compact_artifact_manifest_planning
                .contains("let mut normalized_libraries = Vec::new()")
            && !source_libraries_stream_compact_artifact_manifest_planning
                .contains("let mut library_entries = Vec::new()")
            && !source_libraries_stream_compact_artifact_manifest_planning
                .contains("validate_explicit_source_library_entries(")
            && !source_libraries_stream_compact_artifact_manifest_planning
                .contains("try_from_fallible_file_stream_with_dependencies(")
            && !source_libraries_stream_compact_artifact_manifest_planning
                .contains(".build_plan(limits)")
            && !source_libraries_stream_compact_artifact_manifest_planning
                .contains(".build_artifact_manifest("),
        "streamed compact artifact-manifest planning must not read source text or retain all library streams/manifests/build plans"
    );
    let source_pack_job_schedule = source_between(
        &unit,
        "impl SourcePackJobSchedule",
        "#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]\npub enum SourcePackArtifactKind",
    );
    assert!(
        source_pack_job_schedule.contains("pub fn try_for_each_execution_wave"),
        "source-pack job scheduling must expose a bounded execution-wave visitor"
    );
    assert!(
        source_pack_job_schedule.contains("pub fn try_for_each_execution_batch"),
        "source-pack job scheduling must expose a bounded execution-batch visitor"
    );
    assert!(
        source_pack_job_schedule.contains("pub fn try_for_each_batch_dependency"),
        "source-pack job scheduling must expose a bounded batch-dependency visitor"
    );
    assert!(
        source_pack_job_schedule.contains("self.try_for_each_execution_wave("),
        "collected execution-wave schedules must route through the streaming wave visitor"
    );
    assert!(
        source_pack_job_schedule.contains("self.try_for_each_batch_dependency("),
        "collected batch-dependency plans must route through the streaming dependency visitor"
    );
    let source_pack_execution_batch_visitor = source_between(
        &unit,
        "pub fn try_for_each_execution_batch",
        "    pub fn try_batch_dependency_plan",
    );
    assert!(
        source_pack_execution_batch_visitor.contains("try_for_each_execution_wave_positions("),
        "execution-batch streaming must consume scheduler-ready position records directly"
    );
    assert!(
        !source_pack_execution_batch_visitor.contains("try_execution_waves()")
            && !source_pack_execution_batch_visitor.contains("try_for_each_execution_wave(")
            && !source_pack_execution_batch_visitor.contains("wave.job_indices"),
        "execution-batch streaming must not prebuild public execution-wave records before batching"
    );
    let source_pack_execution_wave_positions = source_between(
        &unit,
        "    fn try_for_each_execution_wave_positions",
        "    pub fn try_execution_batches",
    );
    assert!(
        source_pack_execution_wave_positions.contains("completed_job_ranges")
            && source_pack_execution_wave_positions
                .contains("source_pack_job_ready_from_completed_ranges(")
            && source_pack_execution_wave_positions
                .contains("source_pack_push_completed_job_index_as_range("),
        "execution-wave scheduling must keep ranged dependencies as compact completed-job ranges"
    );
    assert!(
        !source_pack_execution_wave_positions.contains("dependents_by_job_index")
            && !source_pack_execution_wave_positions.contains("range.iter()"),
        "execution-wave scheduling must not expand dependency ranges into per-job dependent lists"
    );
    let source_pack_build_plan = source_between(
        &unit,
        "impl SourcePackBuildPlan",
        "fn artifact_refs_from_indices",
    );
    assert!(
        source_pack_build_plan.contains("pub fn try_for_each_link_interface_batch"),
        "source-pack build planning must expose bounded streaming interface link batches"
    );
    assert!(
        source_pack_build_plan.contains("pub fn try_for_each_link_object_batch"),
        "source-pack build planning must expose bounded streaming object link batches"
    );
    assert!(
        source_pack_build_plan.contains("pub fn try_for_each_job_artifact_io"),
        "source-pack build planning must expose bounded streaming job artifact I/O records"
    );
    assert!(
        source_pack_build_plan.contains("pub fn try_for_each_job_artifact_manifest_for_target"),
        "source-pack build planning must expose bounded streaming job artifact manifest records"
    );
    assert!(
        source_pack_build_plan.contains("pub fn try_compact_build_artifact_manifest_for_target"),
        "source-pack build planning must expose a compact count-only artifact manifest path"
    );
    assert!(
        source_pack_build_plan.contains("pub fn retained_build_artifact_manifest")
            && source_pack_build_plan
                .contains("pub fn try_retained_build_artifact_manifest_for_target"),
        "source-pack build planning must make full inline artifact manifests explicit as retained manifests"
    );
    assert!(
        unit.contains("pub struct SourcePackArtifactIndexRange")
            && source_pack_build_plan.contains("try_for_each_input_interface_artifact_index(")
            && source_pack_build_plan.contains("try_for_each_input_object_artifact_index("),
        "source-pack build planning must stream link input artifact ranges instead of requiring whole link input vectors"
    );
    assert!(
        source_pack_build_plan.contains("pub fn artifact_last_use_plan(&self)"),
        "source-pack build planning must expose compact last-consumer artifact lifetime records"
    );
    assert!(
        source_pack_build_plan.contains("pub fn artifact_last_use_index(&self)"),
        "source-pack build planning must expose a dense last-consumer artifact lifetime index"
    );
    assert!(
        source_pack_build_plan.contains("self.try_for_each_link_interface_batch(limits, |batch|"),
        "collected interface link-batch plans must route through the streaming visitor"
    );
    assert!(
        source_pack_build_plan.contains("self.try_for_each_link_object_batch(limits, |batch|"),
        "collected object link-batch plans must route through the streaming visitor"
    );
    assert!(
        unit.contains("pub const SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE")
            && source_pack_build_plan.contains("source_pack_link_batch_input_limit(limits)")
            && source_pack_build_plan.contains("max_input_artifacts_per_batch"),
        "source-pack link-batch planning must cap input records to a fixed page size even when caller limits are larger"
    );
    assert!(
        source_pack_build_plan.contains("current_source_lines")
            && source_pack_build_plan.contains("artifact.source_lines")
            && source_pack_build_plan.contains("source_lines: current_source_lines"),
        "source-pack build planning must preserve source-line totals through streamed link batches"
    );
    assert!(
        source_pack_build_plan.contains("self.try_for_each_job_artifact_io("),
        "collected job artifact I/O plans must route through the streaming visitor"
    );
    assert!(
        source_pack_build_plan.contains("self.try_for_each_job_artifact_manifest_for_target("),
        "collected job artifact manifest plans must route through the streaming visitor"
    );
    let source_pack_job_artifact_io_visitor = source_between(
        &unit,
        "    pub fn try_for_each_job_artifact_io",
        "    pub fn job_artifact_manifest_plan",
    );
    assert!(
        source_pack_job_artifact_io_visitor.contains("input_interface_artifact_ranges")
            && source_pack_job_artifact_io_visitor.contains("input_object_artifact_ranges")
            && source_pack_job_artifact_io_visitor
                .contains("self.schedule.dependency_job_ranges_for_job(job)")
            && source_pack_job_artifact_io_visitor
                .contains("source_pack_push_interface_artifact_inputs_for_job_range(")
            && source_pack_job_artifact_io_visitor
                .contains("self.link.input_interface_artifact_ranges.clone()")
            && source_pack_job_artifact_io_visitor
                .contains("self.link.input_object_artifact_ranges.clone()"),
        "source-pack job artifact I/O must preserve ranged job dependency and link input artifact records"
    );
    assert!(
        !source_pack_job_artifact_io_visitor
            .contains("try_for_each_input_interface_artifact_index(")
            && !source_pack_job_artifact_io_visitor
                .contains("try_for_each_input_object_artifact_index("),
        "source-pack job artifact I/O must not expand link input artifact ranges into whole job vectors"
    );
    let source_pack_build_plan_for_schedule = source_between(
        &unit,
        "    fn build_plan_for_schedule",
        "    fn library_dependency_index",
    );
    assert!(
        source_pack_build_plan_for_schedule.contains("input_interface_artifact_ranges")
            && source_pack_build_plan_for_schedule.contains("input_object_artifact_ranges")
            && source_pack_build_plan_for_schedule
                .contains("source_pack_artifact_index_ranges_from_first_count(")
            && source_pack_build_plan_for_schedule
                .contains("input_interface_artifact_indices: Vec::new()")
            && source_pack_build_plan_for_schedule
                .contains("input_object_artifact_indices: Vec::new()"),
        "source-pack build plans must record link inputs as compact artifact-index ranges"
    );
    assert!(
        !source_pack_build_plan_for_schedule.contains("let mut interface_artifacts = Vec::new()")
            && !source_pack_build_plan_for_schedule
                .contains("let mut object_artifacts = Vec::new()"),
        "source-pack build plans must not materialize whole link input artifact vectors"
    );
    let job_batch_shard_builder = source_between(
        &unit,
        "    fn job_batch_shard_builder",
        "fn append_source_pack_build_shards",
    );
    assert!(
        job_batch_shard_builder.contains("input_artifact_ranges")
            && job_batch_shard_builder
                .contains(".extend(io.input_interface_artifact_ranges.iter().cloned())")
            && !job_batch_shard_builder.contains("range.iter()"),
        "source-pack job-batch shard planning must preserve ranged input artifacts instead of expanding them into per-artifact shard indices"
    );
    let compact_artifact_manifest_builder = source_between(
        &unit,
        "    pub fn try_compact_build_artifact_manifest_for_target",
        "    pub fn try_build_artifact_manifest_for_target",
    );
    assert!(
        compact_artifact_manifest_builder.contains("try_for_each_execution_batch(")
            && compact_artifact_manifest_builder.contains("try_for_each_link_interface_batch(")
            && compact_artifact_manifest_builder.contains("try_for_each_link_object_batch(")
            && compact_artifact_manifest_builder.contains("job_schedule: Default::default()")
            && compact_artifact_manifest_builder.contains("artifact_uses: Default::default()"),
        "compact source-pack artifact manifests must compute counts by streaming bounded records and leave inline arrays empty"
    );
    assert!(
        !compact_artifact_manifest_builder.contains("try_execution_batches(")
            && !compact_artifact_manifest_builder.contains("try_batch_dependency_plan(")
            && !compact_artifact_manifest_builder.contains("artifact_use_plan(")
            && !compact_artifact_manifest_builder.contains("job_artifact_io_plan(")
            && !compact_artifact_manifest_builder.contains("job_artifact_manifest_plan"),
        "compact source-pack artifact manifests must not build full record plans before dropping them"
    );
    let default_artifact_manifest_builder = source_between(
        &unit,
        "    pub fn build_artifact_manifest(",
        "    pub fn retained_build_artifact_manifest(",
    );
    assert!(
        default_artifact_manifest_builder
            .contains("self.compact_build_artifact_manifest_for_target(")
            && default_artifact_manifest_builder
                .contains("self.try_compact_build_artifact_manifest_for_target("),
        "default source-pack artifact manifests must route to compact manifests"
    );
    assert!(
        !default_artifact_manifest_builder.contains("try_execution_batches(")
            && !default_artifact_manifest_builder.contains("try_batch_dependency_plan(")
            && !default_artifact_manifest_builder.contains("self.artifact_manifest_for_target(")
            && !default_artifact_manifest_builder.contains("job_artifact_io_plan(")
            && !default_artifact_manifest_builder.contains("artifact_use_plan("),
        "default source-pack artifact manifests must not materialize retained manifest arrays"
    );
    let retained_artifact_manifest_builder = source_between(
        &unit,
        "    pub fn try_retained_build_artifact_manifest_for_target",
        "    pub fn artifact_use_plan(&self)",
    );
    assert!(
        retained_artifact_manifest_builder.contains("self.schedule.try_execution_batches(")
            && retained_artifact_manifest_builder.contains("self.artifact_manifest_for_target(")
            && retained_artifact_manifest_builder
                .contains("self.job_artifact_manifest_plan_for_target(")
            && retained_artifact_manifest_builder.contains("self.job_artifact_io_plan()")
            && retained_artifact_manifest_builder.contains("self.artifact_use_plan()"),
        "retained source-pack artifact manifests must be the explicit path that materializes full inline arrays"
    );
    let source_pack_job_plan_compact_manifest = source_between(
        &unit,
        "    pub fn try_compact_build_artifact_manifest_for_schedule",
        "    pub fn build_artifact_estimate_summary",
    );
    assert!(
        source_pack_job_plan_compact_manifest.contains("schedule: &SourcePackJobSchedule")
            && source_pack_job_plan_compact_manifest
                .contains("schedule.try_execution_batch_summary(batch_limits)")
            && source_pack_job_plan_compact_manifest
                .contains("schedule.try_execution_batch_dependency_summary(batch_limits)")
            && source_pack_job_plan_compact_manifest
                .contains("build_artifact_estimate_summary_for_schedule(")
            && source_pack_job_plan_compact_manifest.contains("job_schedule: Default::default()")
            && source_pack_job_plan_compact_manifest.contains("artifact_uses: Default::default()"),
        "direct source-pack compact manifests must consume scheduled job records and direct artifact summaries"
    );
    assert!(
        !source_pack_job_plan_compact_manifest.contains("SourcePackBuildPlan")
            && !source_pack_job_plan_compact_manifest.contains("build_plan_for_schedule")
            && !source_pack_job_plan_compact_manifest.contains("try_execution_batches(")
            && !source_pack_job_plan_compact_manifest.contains("try_batch_dependency_plan(")
            && !source_pack_job_plan_compact_manifest.contains("artifact_manifest()")
            && !source_pack_job_plan_compact_manifest.contains("job_artifact_io_plan(")
            && !source_pack_job_plan_compact_manifest.contains("job_artifact_manifest_plan(")
            && !source_pack_job_plan_compact_manifest.contains("artifact_use_plan("),
        "direct source-pack compact manifests must not construct retained build plans or full manifest record arrays"
    );
    let source_pack_job_plan_artifact_estimate = source_between(
        &unit,
        "    pub fn build_artifact_estimate_summary_for_schedule",
        "    pub fn build_plan(&self)",
    );
    assert!(
        source_pack_job_plan_artifact_estimate.contains("schedule: &SourcePackJobSchedule")
            && source_pack_job_plan_artifact_estimate.contains("for job in &schedule.jobs")
            && source_pack_job_plan_artifact_estimate
                .contains("source_pack_job_phase_by_job_index(schedule)")
            && source_pack_job_plan_artifact_estimate
                .contains("record_source_pack_job_artifact_io_estimate(")
            && source_pack_job_plan_artifact_estimate
                .contains("record_source_pack_link_input_batch_summary(")
            && source_pack_job_plan_artifact_estimate
                .contains("SourcePackArtifactKind::LibraryInterface")
            && source_pack_job_plan_artifact_estimate
                .contains("SourcePackArtifactKind::CodegenObject"),
        "source-pack artifact estimates must consume scheduled job records and artifact-kind records directly"
    );
    assert!(
        !source_pack_job_plan_artifact_estimate.contains("SourcePackBuildPlan")
            && !source_pack_job_plan_artifact_estimate.contains("build_plan_for_schedule")
            && !source_pack_job_plan_artifact_estimate.contains("artifact_manifest_summary")
            && !source_pack_job_plan_artifact_estimate.contains("job_artifact_io_summary")
            && !source_pack_job_plan_artifact_estimate.contains("link_interface_batch_summary")
            && !source_pack_job_plan_artifact_estimate.contains("link_object_batch_summary"),
        "source-pack artifact estimates must not construct or call through retained build-plan summaries"
    );
    let source_pack_artifact_estimate_helpers = source_between(
        &unit,
        "fn source_pack_artifact_plan_for_job",
        "fn record_artifact_last_consumer",
    );
    assert!(
        source_pack_artifact_estimate_helpers.contains("SourcePackArtifactPlan")
            && source_pack_artifact_estimate_helpers
                .contains("source_pack_artifact_key_for_target(")
            && source_pack_artifact_estimate_helpers.contains("SourcePackJobArtifactIoSummary")
            && source_pack_artifact_estimate_helpers.contains("SourcePackJobBatchLimits"),
        "source-pack artifact estimate helpers must derive manifest/job/link summaries from artifact and job records"
    );
    let source_pack_estimate = source_between(
        &bench,
        "fn print_codegen_unit_estimate",
        "fn print_live_capacity_estimate",
    );
    assert!(
        source_pack_estimate.contains("build_artifact_estimate_summary_for_schedule(")
            && source_pack_estimate.contains("bounded_frontend_job_schedule()")
            && source_pack_estimate.contains("try_execution_wave_summary()")
            && source_pack_estimate.contains("try_execution_batch_summary(batch_limits)")
            && source_pack_estimate
                .contains("try_execution_batch_dependency_summary(batch_limits)")
            && !source_pack_estimate.contains("plan.build_plan()")
            && !source_pack_estimate.contains("build_plan.")
            && !source_pack_estimate.contains(".artifact_manifest()")
            && !source_pack_estimate.contains("artifact_manifest_summary()")
            && !source_pack_estimate.contains("try_execution_waves()")
            && !source_pack_estimate.contains("try_execution_batches(batch_limits)")
            && !source_pack_estimate.contains("try_batch_dependency_plan(")
            && !source_pack_estimate.contains("artifact_last_use_index()")
            && !source_pack_estimate.contains("artifact_lifetime_summary()")
            && !source_pack_estimate.contains("job_artifact_io_summary()")
            && !source_pack_estimate.contains("job_artifact_io_plan(")
            && !source_pack_estimate.contains("job_artifact_manifest_summary()")
            && !source_pack_estimate.contains("job_artifact_manifest_plan(")
            && !source_pack_estimate.contains("link_interface_batch_summary(batch_limits)")
            && !source_pack_estimate.contains("link_interface_batches(batch_limits)")
            && !source_pack_estimate.contains("link_object_batch_summary(batch_limits)")
            && !source_pack_estimate.contains("link_object_batches(batch_limits)"),
        "source-pack estimates must compute artifact/job/link metrics through streaming summaries instead of full retained plans"
    );
    let compact_artifact_manifest_store = source_between(
        &compiler,
        "fn source_pack_compact_build_artifact_manifest",
        "fn ensure_inline_build_artifact_records_for_manifest_execution",
    );
    assert!(
        compact_artifact_manifest_store.contains("version: manifest.version")
            && compact_artifact_manifest_store.contains("job_count: manifest.job_count")
            && compact_artifact_manifest_store.contains("job_schedule: Default::default()")
            && compact_artifact_manifest_store.contains("artifact_uses: Default::default()"),
        "source-pack artifact-manifest compaction must copy scalar counts while leaving inline arrays empty"
    );
    assert!(
        !compact_artifact_manifest_store.contains("manifest.clone()"),
        "source-pack artifact-manifest compaction must not clone full inline record arrays before dropping them"
    );
    let source_pack_job_artifact_manifest_visitor = source_between(
        &unit,
        "pub fn try_for_each_job_artifact_manifest_for_target",
        "    fn artifact_indices_by_producing_job",
    );
    assert!(
        !source_pack_job_artifact_manifest_visitor.contains("artifact_manifest_for_target("),
        "streamed job artifact manifests must not build the full target artifact manifest before visiting jobs"
    );
    assert!(
        source_pack_job_artifact_manifest_visitor.contains("artifact_refs_from_indices("),
        "streamed job artifact manifests must map artifact indices directly while visiting each job"
    );
    assert!(
        source_pack_job_artifact_manifest_visitor
            .contains("self.schedule.dependency_job_ranges_for_job(job).to_vec()")
            && source_pack_job_artifact_manifest_visitor
                .contains("source_pack_job_index_range_dependency_count(")
            && source_pack_job_artifact_manifest_visitor
                .contains("self.link.input_interface_artifact_ranges.clone()")
            && source_pack_job_artifact_manifest_visitor
                .contains("self.link.input_object_artifact_ranges.clone()"),
        "streamed job artifact manifests must preserve frontend/codegen dependency job ranges while keeping link artifact ranges compact"
    );
    assert!(
        !source_pack_job_artifact_manifest_visitor.contains("self.try_for_each_job_artifact_io(")
            && !source_pack_job_artifact_manifest_visitor
                .contains("source_pack_push_interface_artifact_inputs_for_job_range("),
        "streamed job artifact manifests must not convert scheduled dependency ranges through artifact-I/O expansion"
    );
    let batched_link_executor = source_between(
        &compiler,
        "fn execute_source_pack_path_batched_link_build",
        "fn execute_source_pack_path_artifact_store_build",
    );
    assert!(
        batched_link_executor.contains("build_plan.try_for_each_link_interface_batch("),
        "batched path-link execution must stream interface link batches"
    );
    assert!(
        batched_link_executor.contains("build_plan.try_for_each_link_object_batch("),
        "batched path-link execution must stream object link batches"
    );
    assert!(
        !batched_link_executor.contains("let link_interface_batches ="),
        "batched path-link execution must not prebuild every interface link batch"
    );
    assert!(
        !batched_link_executor.contains("let link_object_batches ="),
        "batched path-link execution must not prebuild every object link batch"
    );
    let handle_executor = source_between(
        &compiler,
        "fn execute_source_pack_path_handle_build",
        "fn execute_source_pack_path_batched_link_build",
    );
    assert!(
        handle_executor.contains("release_link_input_handles("),
        "handle path execution must release retained handles from compact link input ranges after link"
    );
    assert!(
        !handle_executor.contains("build_plan.artifact_last_use_index()")
            && !handle_executor.contains("build_plan.artifact_last_use_plan()"),
        "handle path execution must not build dense last-use records for per-job release scans"
    );
    assert!(
        !handle_executor.contains("build_plan.artifact_use_plan()"),
        "handle path execution must not build full per-artifact consumer lists for releases"
    );
    assert!(
        batched_link_executor.contains("release_library_interface_handles_for_link_batch(")
            && batched_link_executor.contains("release_codegen_object_handles_for_link_batch("),
        "batched path-link execution must release handles from streamed link input batches"
    );
    assert!(
        !batched_link_executor.contains("build_plan.artifact_last_use_index()")
            && !batched_link_executor.contains("build_plan.artifact_last_use_plan()"),
        "batched path-link execution must not build dense last-use records for per-job release scans"
    );
    assert!(
        !batched_link_executor.contains("build_plan.artifact_use_plan()"),
        "batched path-link execution must not build full per-artifact consumer lists for releases"
    );
    let link_input_handle_release = source_between(
        &compiler,
        "fn release_link_input_handles",
        "fn release_codegen_object_handles_for_link_batch",
    );
    assert!(
        link_input_handle_release.contains("try_for_each_input_interface_artifact_index(")
            && link_input_handle_release.contains("try_for_each_input_object_artifact_index(")
            && !link_input_handle_release.contains("last_consumer_job_indices")
            && !link_input_handle_release.contains(".artifact_last_use_index()"),
        "handle release must consume compact link artifact ranges directly instead of dense last-use vectors"
    );
    let interface_dependency_collector = source_between(
        &compiler,
        "fn for_each_interface_dependency_job_index",
        "fn collect_link_interface_refs",
    );
    assert!(
        interface_dependency_collector.contains("schedule.dependency_job_ranges_for_job(job)")
            && interface_dependency_collector.contains("dependency_range.iter()")
            && interface_dependency_collector.contains("job.dependency_job_indices")
            && interface_dependency_collector.contains("excluded_job_index"),
        "in-memory source-pack executors must consume explicit and ranged interface dependency records"
    );
    let retained_manifest_input_resolver = source_between(
        &compiler,
        "fn source_pack_manifest_job_input_interface_refs",
        "fn single_output_artifact_ref",
    );
    assert!(
        retained_manifest_input_resolver.contains("job_manifest.input_interface_ranges")
            && retained_manifest_input_resolver
                .contains("source_pack_manifest_library_interface_artifact_for_producing_job("),
        "retained artifact-manifest execution must resolve ranged interface dependency job records"
    );
    let retained_manifest_job_validator = source_between(
        &compiler,
        "fn validate_source_pack_manifest_job_artifacts",
        "fn validate_source_pack_manifest_job_output_shape",
    );
    let retained_manifest_io_validator = source_between(
        &compiler,
        "fn validate_source_pack_manifest_job_artifact_io",
        "fn validate_source_pack_manifest_artifact_uses",
    );
    assert!(
        retained_manifest_job_validator.contains("job_manifest.input_interface_ranges")
            && retained_manifest_job_validator
                .contains("source_pack_manifest_library_interface_artifact_for_producing_job(")
            && retained_manifest_io_validator
                .contains("source_pack_insert_manifest_interface_job_range_indices("),
        "retained artifact-manifest validation must compare ranged interface dependency job records against artifact IO"
    );
    let artifact_store_job = source_between(
        &compiler,
        "fn execute_source_pack_path_artifact_manifest_store_job",
        "fn execute_source_pack_build_artifact_execution_shard_batch",
    );
    let artifact_store_build = source_between(
        &compiler,
        "fn execute_source_pack_path_artifact_store_build",
        "fn execute_source_pack_path_artifact_manifest_store_build",
    );
    assert!(
        artifact_store_build.contains(".try_retained_build_artifact_manifest(")
            && !artifact_store_build.contains(".try_build_artifact_manifest("),
        "legacy artifact-store execution must opt into retained inline manifests explicitly"
    );
    let artifact_manifest_executor = source_between(
        &compiler,
        "fn execute_source_pack_path_artifact_manifest_store_build",
        "fn execute_source_pack_build_artifact_execution_shard_batch",
    );
    assert!(
        artifact_manifest_executor
            .contains("ensure_inline_build_artifact_records_for_manifest_execution")
            && compiler.contains("persisted execution shards"),
        "legacy artifact-manifest execution must reject compact manifests and leave count-only manifests to persisted execution shards"
    );
    assert!(
        !artifact_store_job.contains("let artifact_refs = artifact_refs_for_indices("),
        "artifact-store link execution must not build temporary artifact-ref vectors for link batches"
    );
    assert!(
        !artifact_store_job.contains(".cloned()\n                .collect::<Vec<_>>()"),
        "artifact-store codegen execution must not collect cloned interface refs before loading dependencies"
    );
    let link_input_release = source_between(
        &compiler,
        "fn release_source_pack_link_input_artifacts",
        "#[cfg(test)]\nfn source_pack_artifact_shard_for_job_batch",
    );
    assert!(
        !link_input_release.contains("let artifact_refs = artifact_refs_for_indices("),
        "artifact-store link-input release must not build temporary artifact-ref vectors"
    );
    assert!(
        !compiler.contains("source_pack_job_batch_dependents_by_batch_from_stored_pages"),
        "filesystem source-pack prepare must not rebuild all reverse batch dependents in memory"
    );
    assert!(
        !compiler.contains("dependents_page.dependents.dependent_batch_indices.push(batch_index)"),
        "filesystem source-pack prepare must not append all reverse batch dependents into one page"
    );
    assert!(
        !compiler
            .contains("let mut dependent_batches_by_shard = BTreeMap::<usize, Vec<usize>>::new()"),
        "filesystem source-pack progress updates must not group every dependent batch in memory"
    );
    assert!(
        !compiler.contains("source_pack_singleton_batch_by_job_from_stored_pages"),
        "filesystem source-pack work-queue prepare must not build a global job-to-batch map"
    );
    assert!(
        compiler.contains("stored_page.dependency.dependency_batch_ranges.clear();"),
        "filesystem source-pack job-batch pages must compact inline dependency ranges into range pages"
    );
    assert!(
        !compiler.contains("schedule_entries.push"),
        "filesystem source-pack prepare must not accumulate all schedule entries before storing pages"
    );
    assert!(
        !compiler.contains("let mut partitions = Vec::with_capacity(partition_count);"),
        "filesystem source-pack prepare must not accumulate all library partitions before storing pages"
    );
    assert!(
        !compiler
            .contains("let mut partitions = Vec::with_capacity(topological_library_ids.len());"),
        "filesystem source-pack metadata prepare must not accumulate all library partitions before storing pages"
    );
    let library_partition_index_record = source_between(
        &source_pack_records,
        "pub struct SourcePackLibraryPartitionIndex",
        "#[derive(Clone, Debug, PartialEq, Eq)]\npub struct SourcePackLibraryPartitionPlan",
    );
    assert!(
        library_partition_index_record.contains("pub partition_count: usize")
            && library_partition_index_record.contains("pub source_file_count: usize")
            && library_partition_index_record.contains("pub source_byte_count: usize")
            && !library_partition_index_record.contains("pub partitions: Vec<"),
        "filesystem source-pack library partition indexes must persist compact counts, not inline partition records"
    );
    let library_partition_plan_record = source_between(
        &source_pack_records,
        "#[derive(Clone, Debug, PartialEq, Eq)]\npub struct SourcePackLibraryPartitionPlan",
        "#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]\npub struct SourcePackLibraryPartitionLocatorPage",
    );
    assert!(
        library_partition_plan_record.contains("pub index: SourcePackLibraryPartitionIndex")
            && library_partition_plan_record
                .contains("pub partitions: Vec<SourcePackLibraryPartition>"),
        "inline library partition records must be isolated to the in-memory partition plan"
    );
    let library_schedule_index_record = source_between(
        &source_pack_records,
        "pub struct SourcePackLibraryScheduleIndex",
        "#[derive(Clone, Debug, PartialEq, Eq)]\npub struct SourcePackLibrarySchedulePlan",
    );
    assert!(
        library_schedule_index_record.contains("pub partition_count: usize")
            && library_schedule_index_record.contains("pub frontend_job_count: usize")
            && library_schedule_index_record.contains("pub codegen_job_count: usize")
            && library_schedule_index_record.contains("pub link_job_index: usize")
            && !library_schedule_index_record.contains("pub entries: Vec<"),
        "filesystem source-pack schedule indexes must persist compact counts, not inline per-library entries"
    );
    let library_schedule_plan_record = source_between(
        &source_pack_records,
        "#[derive(Clone, Debug, PartialEq, Eq)]\npub struct SourcePackLibrarySchedulePlan",
        "#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]\npub struct SourcePackLibraryFrontendJobLocatorPage",
    );
    assert!(
        library_schedule_plan_record.contains("pub index: SourcePackLibraryScheduleIndex")
            && library_schedule_plan_record
                .contains("pub entries: Vec<SourcePackLibraryScheduleIndexEntry>"),
        "inline schedule entries must be isolated to the in-memory schedule plan"
    );
    assert!(
        !compiler.contains("ready_shard_indices.push"),
        "filesystem source-pack progress summaries must not accumulate every ready shard"
    );
    assert!(
        !compiler.contains("claimed_shard_indices.push"),
        "filesystem source-pack progress summaries must not accumulate every claimed shard"
    );
    let progress_summary_record = source_between(
        &compiler,
        "pub struct SourcePackBuildProgressSummary",
        "impl SourcePackBuildProgressSummary",
    );
    assert!(
        !progress_summary_record.contains("ready_shard_indices")
            && !progress_summary_record.contains("claimed_shard_indices")
            && progress_summary_record.contains("pub ready_batch_count: usize")
            && progress_summary_record.contains("pub first_ready_batch_index: Option<usize>")
            && progress_summary_record.contains("pub claimed_batch_count: usize"),
        "filesystem source-pack progress summaries must persist compact counts and first-frontier records, not shard-frontier arrays"
    );
    assert!(
        !compiler.contains("ready_page_indices.push"),
        "filesystem source-pack work-queue progress must not accumulate every ready page"
    );
    assert!(
        !compiler.contains("claimed_page_indices.push"),
        "filesystem source-pack work-queue progress must not accumulate every claimed page"
    );
    assert!(
        !compiler.contains("ready_shard_indices: summary.ready_shard_indices")
            && !compiler.contains("claimed_shard_indices: summary.claimed_shard_indices"),
        "filesystem source-pack progress snapshots must not expose unbounded shard-frontier arrays"
    );
    let artifact_progress_snapshot = source_between(
        &compiler,
        "pub struct SourcePackFilesystemArtifactProgressSnapshot",
        "pub struct SourcePackFilesystemArtifactProgressPage",
    );
    assert!(
        !artifact_progress_snapshot.contains("ready_shard_indices")
            && !artifact_progress_snapshot.contains("claimed_shard_indices"),
        "filesystem source-pack progress snapshots must expose shard frontier counts and first indices, not shard-frontier arrays"
    );
    assert!(
        !compiler.contains("ready_page_indices: index.ready_page_indices.clone()")
            && !compiler.contains("claimed_page_indices: index.claimed_page_indices.clone()"),
        "filesystem source-pack work-queue snapshots must not expose unbounded page-frontier arrays"
    );
    let work_queue_progress_index = source_between(
        &source_pack_records,
        "pub struct SourcePackWorkQueueProgressIndex",
        "#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]\npub struct SourcePackWorkQueueProgressPage",
    );
    assert!(
        !work_queue_progress_index.contains("ready_page_indices")
            && !work_queue_progress_index.contains("claimed_page_indices")
            && !work_queue_progress_index.contains("pub pages: Vec<")
            && work_queue_progress_index.contains("pub ready_item_count: usize")
            && work_queue_progress_index.contains("pub first_ready_item_index: Option<usize>")
            && work_queue_progress_index.contains("pub claimed_item_count: usize"),
        "filesystem source-pack work-queue progress indexes must persist compact counts and first-frontier records, not page-frontier arrays or page-summary arrays"
    );
    let work_queue_progress_snapshot = source_between(
        &compiler,
        "pub struct SourcePackFilesystemWorkQueueProgressSnapshot",
        "pub struct SourcePackFilesystemWorkQueueItemClaimResult",
    );
    assert!(
        !work_queue_progress_snapshot.contains("ready_page_indices")
            && !work_queue_progress_snapshot.contains("claimed_page_indices"),
        "filesystem source-pack work-queue snapshots must expose page frontier counts and first indices, not page-frontier arrays"
    );
    let hierarchical_link_plan_index = source_between(
        &source_pack_records,
        "pub struct SourcePackHierarchicalLinkPlanIndex",
        "#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]\npub struct SourcePackHierarchicalLinkGroupPage",
    );
    assert!(
        hierarchical_link_plan_index.contains("pub link_group_count: usize")
            && hierarchical_link_plan_index.contains("pub final_link_group_index: usize")
            && !hierarchical_link_plan_index.contains("pub groups: Vec<"),
        "filesystem source-pack hierarchical link plan indexes must persist compact counts and final pointers, not per-group summaries"
    );
    let hierarchical_link_group_store = source_between(
        &compiler,
        "pub fn store_hierarchical_link_group_page(",
        "pub fn load_hierarchical_link_group_page_for_target",
    );
    assert!(
        hierarchical_link_group_store.contains("stored_group.input_frontend_job_indices.clear();")
            && hierarchical_link_group_store
                .contains("stored_group.input_partition_indices.clear();")
            && hierarchical_link_group_store
                .contains("source_pack_hierarchical_link_group_input_frontend_job_count(group)")
            && hierarchical_link_group_store
                .contains("source_pack_hierarchical_link_group_input_partition_count(group)"),
        "filesystem source-pack hierarchical link group pages must persist compact counts for unbounded frontend and reduce-partition inputs"
    );
    let hierarchical_link_group_validation = source_between(
        &compiler,
        "fn validate_source_pack_hierarchical_link_group_page",
        "fn validate_source_pack_hierarchical_link_execution_index",
    );
    assert!(
        hierarchical_link_group_validation
            .contains("SOURCE_PACK_HIERARCHICAL_LINK_GROUP_INPUT_DEFAULT_PAGE_SIZE")
            && hierarchical_link_group_validation.contains("group.input_partition_indices.len()")
            && hierarchical_link_group_validation
                .contains("group.input_frontend_job_indices.len()")
            && hierarchical_link_group_validation.contains("group.input_codegen_job_indices.len()")
            && hierarchical_link_group_validation.contains("group.input_link_group_indices.len()"),
        "filesystem source-pack hierarchical link group pages must cap retained input vectors before record scans"
    );
    let hierarchical_link_execution_index = source_between(
        &source_pack_records,
        "pub struct SourcePackHierarchicalLinkExecutionIndex",
        "#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]\npub struct SourcePackHierarchicalLinkExecutionPage",
    );
    assert!(
        hierarchical_link_execution_index.contains("pub link_group_count: usize")
            && hierarchical_link_execution_index.contains("pub final_output_key: String")
            && !hierarchical_link_execution_index.contains("pub groups: Vec<"),
        "filesystem source-pack hierarchical link execution indexes must persist compact counts and final output keys, not per-group summaries"
    );
    let hierarchical_link_execution_validation = source_between(
        &compiler,
        "fn validate_source_pack_hierarchical_link_execution_page",
        "fn validate_source_pack_hierarchical_link_execution_artifact_refs",
    );
    assert!(
        hierarchical_link_execution_validation
            .contains("SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE")
            && hierarchical_link_execution_validation
                .contains("SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE")
            && hierarchical_link_execution_validation
                .contains("SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE")
            && hierarchical_link_execution_validation.contains("page.input_interface_ranges.len()")
            && hierarchical_link_execution_validation.contains("page.input_interfaces.len()")
            && hierarchical_link_execution_validation.contains("page.input_objects.len()")
            && hierarchical_link_execution_validation.contains("page.input_group_indices.len()")
            && hierarchical_link_execution_validation
                .contains("page.input_group_output_keys.len()"),
        "filesystem source-pack hierarchical link execution pages must cap retained inline input vectors before record scans"
    );
    let artifact_shard_index_record = source_between(
        &unit,
        "pub struct SourcePackBuildArtifactShardIndex",
        "impl SourcePackBuildArtifactShardIndex",
    );
    let artifact_shard_record = source_between(
        &unit,
        "impl SourcePackBuildArtifactShard",
        "#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]\npub struct SourcePackBuildArtifactShardIndex",
    );
    assert!(
        artifact_shard_record.contains("pub fn artifact_record_count(&self)")
            && artifact_shard_record.contains("self.input_artifact_ranges.len()")
            && artifact_shard_record.contains("source_pack_artifact_index_range_count("),
        "source-pack artifact shards must distinguish retained artifact records from expanded artifact-range fan-in"
    );
    assert!(
        artifact_shard_index_record.contains("pub shard_count: usize")
            && artifact_shard_index_record.contains("pub job_batch_count: usize")
            && artifact_shard_index_record.contains("pub link_interface_batch_count: usize")
            && artifact_shard_index_record.contains("pub link_object_batch_count: usize")
            && !artifact_shard_index_record.contains("pub shards: Vec<"),
        "source-pack artifact shard indexes must persist compact counts, not inline shard records"
    );
    let artifact_shard_plan_record = source_between(
        &unit,
        "pub struct SourcePackBuildArtifactShardPlan",
        "impl SourcePackBuildArtifactShardPlan",
    );
    assert!(
        artifact_shard_plan_record.contains("pub index: SourcePackBuildArtifactShardIndex")
            && artifact_shard_plan_record.contains("pub shards: Vec<SourcePackBuildArtifactShard>"),
        "inline artifact shard records must be isolated to the in-memory shard plan"
    );
    let artifact_shard_index_builder = source_between(
        &unit,
        "    pub fn build_artifact_shard_index(",
        "    pub fn build_artifact_shard_plan(",
    );
    assert!(
        artifact_shard_index_builder.contains("count_source_pack_build_shards(")
            && artifact_shard_index_builder.contains("self.job_batches")
            && artifact_shard_index_builder.contains("self.link_interface_batches")
            && artifact_shard_index_builder.contains("self.link_object_batches")
            && !artifact_shard_index_builder.contains("build_artifact_shard_plan(")
            && !artifact_shard_index_builder.contains("let mut shards = Vec::new()"),
        "source-pack artifact shard indexes must count directly from batch records without materializing the full shard plan"
    );
    let artifact_shard_counter = source_between(
        &unit,
        "fn count_source_pack_build_shards",
        "fn source_pack_link_interface_batch_shard_builder",
    );
    assert!(
        artifact_shard_counter.contains("SourcePackBuildArtifactShardBuilder::new(kind)")
            && artifact_shard_counter.contains("current.would_exceed(&item, limits)")
            && artifact_shard_counter.contains("current.absorb(item)")
            && !artifact_shard_counter.contains("SourcePackBuildArtifactShardPlan")
            && !artifact_shard_counter.contains("Vec<SourcePackBuildArtifactShard>"),
        "source-pack artifact shard counters must reuse shard-builder coalescing over records without allocating shard records"
    );
    let artifact_shard_record_counter = source_between(
        &unit,
        "fn source_pack_build_shard_artifact_union_count",
        "impl SourcePackBuildPlan",
    );
    assert!(
        artifact_shard_record_counter.contains("input_artifact_ranges.len()")
            && artifact_shard_record_counter.contains("source_pack_compact_artifact_index_ranges(")
            && !artifact_shard_record_counter.contains("source_pack_artifact_index_range_count("),
        "source-pack shard coalescing must count compact range records, not expanded artifact-range fan-in"
    );
    let artifact_shard_streamer = source_between(
        &unit,
        "    pub fn try_for_each_build_artifact_shard",
        "    pub fn build_artifact_shard_plan",
    );
    assert!(
        artifact_shard_streamer.contains("try_emit_source_pack_build_shards(")
            && artifact_shard_streamer.contains("self.job_batches")
            && artifact_shard_streamer.contains("self.link_interface_batches")
            && artifact_shard_streamer.contains("self.link_object_batches")
            && !artifact_shard_streamer.contains("let mut shards = Vec::new()")
            && !artifact_shard_streamer.contains("SourcePackBuildArtifactShardPlan"),
        "source-pack artifact shard streaming must consume batch records directly without allocating the full shard plan"
    );
    let artifact_shard_limits = source_between(
        &unit,
        "impl SourcePackBuildShardLimits",
        "#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]\npub enum SourcePackBuildArtifactShardKind",
    );
    assert!(
        artifact_shard_limits.contains("let record_caps = Self::default()")
            && artifact_shard_limits.contains(".min(record_caps.max_batches_per_shard)")
            && artifact_shard_limits.contains(".min(record_caps.max_jobs_per_shard)")
            && artifact_shard_limits.contains(".min(record_caps.max_artifacts_per_shard)"),
        "source-pack artifact-shard limits must normalize caller limits down to bounded record caps"
    );
    let artifact_shard_validation = source_between(
        &compiler,
        "fn validate_source_pack_build_artifact_shard",
        "fn source_pack_for_each_build_artifact_shard_from_index",
    );
    assert!(
        artifact_shard_validation.contains("shard.limits.normalized()")
            && artifact_shard_validation.contains("shard.batch_indices.len()")
            && artifact_shard_validation.contains("limits.max_batches_per_shard")
            && artifact_shard_validation.contains("shard.job_indices.len()")
            && artifact_shard_validation.contains("limits.max_jobs_per_shard")
            && artifact_shard_validation.contains("artifact_ref_count")
            && artifact_shard_validation.contains("limits.max_artifacts_per_shard"),
        "source-pack artifact shards must reject unbounded persisted batch/job/artifact arrays before record scans"
    );
    let link_input_shard_index = source_between(
        &compiler,
        "pub struct SourcePackBuildLinkInputShardIndex",
        "pub struct SourcePackJobBatchDependents",
    );
    assert!(
        link_input_shard_index
            .contains("pub link_interface_shard_range: Option<SourcePackLinkInputShardRange>")
            && link_input_shard_index
                .contains("pub link_object_shard_range: Option<SourcePackLinkInputShardRange>")
            && !link_input_shard_index.contains("link_interface_shard_indices")
            && !link_input_shard_index.contains("link_object_shard_indices"),
        "filesystem source-pack link-input indexes must persist bounded shard ranges, not shard-index arrays"
    );
    let filesystem_store_results = source_between(
        &compiler,
        "pub struct SourcePackFilesystemLibraryPartitionStoreResult",
        "pub struct SourcePackFilesystemArtifactLinkInputReleaseResult",
    );
    assert!(
        !filesystem_store_results.contains("Vec<PathBuf>"),
        "aggregate filesystem store results must not expose unbounded per-page or per-shard path arrays"
    );
    let partition_store = source_between(
        &compiler,
        "pub fn store_library_partition_index",
        "pub fn store_library_partition_page",
    );
    assert!(
        !partition_store.contains("partition_paths.push"),
        "library partition store results must report counts without retaining every partition path"
    );
    let partition_validation = source_between(
        &compiler,
        "fn validate_source_pack_library_partition(",
        "fn validate_source_pack_library_dependency_page",
    );
    assert!(
        partition_validation.contains("SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE")
            && partition_validation.contains("partition.dependency_library_ids.len()"),
        "library partition validation must reject unbounded inline dependency arrays before record scans"
    );
    let source_file_page_store = source_between(
        &compiler,
        "pub fn store_library_source_file_pages",
        "pub fn store_library_source_file_page",
    );
    assert!(
        !source_file_page_store.contains("paths.push"),
        "library source-file page store results must report counts without retaining every page path"
    );
    let source_file_page_store_boundary = source_between(
        &compiler,
        "pub fn store_library_source_file_page",
        "pub fn load_library_source_file_page_for_target",
    );
    assert!(
        source_file_page_store_boundary.contains("store_library_source_file_record_page(")
            && source_file_page_store_boundary.contains("stored_page.source_files.clear();"),
        "stored source-file pages must spill inline source-file records to per-source pages before persistence"
    );
    let source_file_page_validation = source_between(
        &compiler,
        "fn validate_source_pack_library_source_file_page",
        "fn validate_source_pack_library_source_file_record_page",
    );
    assert!(
        source_file_page_validation
            .contains("SOURCE_PACK_LIBRARY_SOURCE_FILE_INLINE_DEFAULT_RECORD_CAP")
            && source_file_page_validation.contains("page.source_files.len()"),
        "source-file page validation must reject unbounded inline source-file arrays before record scans"
    );
    let build_unit_page_validation = source_between(
        &compiler,
        "fn validate_source_pack_library_build_unit_page",
        "fn validate_source_pack_library_frontend_unit_shape",
    );
    assert!(
        build_unit_page_validation
            .contains("SOURCE_PACK_LIBRARY_BUILD_UNIT_INLINE_DEFAULT_RECORD_CAP")
            && build_unit_page_validation.contains("page.frontend_units.len()")
            && build_unit_page_validation.contains("page.codegen_units.len()")
            && build_unit_page_validation
                .contains("SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE")
            && build_unit_page_validation.contains("page.dependency_library_ids.len()"),
        "build-unit page validation must reject unbounded inline dependency and unit arrays before record scans"
    );
    let build_unit_page_store = source_between(
        &compiler,
        "pub fn store_library_build_unit_pages",
        "pub fn store_library_build_unit_page",
    );
    assert!(
        !build_unit_page_store.contains("paths.push"),
        "library build-unit page store results must report counts without retaining every page path"
    );
    let build_unit_page_store_boundary = source_between(
        &compiler,
        "pub fn store_library_build_unit_page",
        "pub fn load_library_build_unit_page_for_target",
    );
    for required in [
        "store_library_frontend_unit_pages_from_units(page)?",
        "store_library_codegen_unit_pages_from_units(page)?",
        "stored_page.dependency_library_ids.clear();",
        "stored_page.frontend_units.clear();",
        "stored_page.codegen_units.clear();",
    ] {
        assert!(
            build_unit_page_store_boundary.contains(required),
            "stored build-unit pages must spill inline unit records and compact dependency/unit vectors before persistence"
        );
    }
    let schedule_page_store = source_between(
        &compiler,
        "pub fn store_library_schedule_pages",
        "pub fn store_library_schedule_page",
    );
    assert!(
        !schedule_page_store.contains("paths.push"),
        "library schedule page store results must report counts without retaining every page path"
    );
    let schedule_page_store_boundary = source_between(
        &compiler,
        "pub fn store_library_schedule_page",
        "pub fn load_library_schedule_page_for_target",
    );
    for required in [
        "if !page.frontend_jobs.is_empty() || !page.codegen_jobs.is_empty()",
        "store_library_frontend_job_locator_page(",
        "store_schedule_page_job_record(",
        "stored_page.dependency_library_ids.clear();",
        "stored_page.frontend_job.dependency_job_indices.clear();",
        "stored_page.frontend_jobs.clear();",
        "stored_page.codegen_jobs.clear();",
    ] {
        assert!(
            schedule_page_store_boundary.contains(required),
            "stored schedule pages must spill inline job records before compacting job/dependency vectors for persistence"
        );
    }
    let schedule_page_validation = source_between(
        &compiler,
        "fn validate_source_pack_library_schedule_page",
        "fn validate_source_pack_library_schedule_job_locator_index",
    );
    assert!(
        schedule_page_validation
            .contains("SOURCE_PACK_LIBRARY_SCHEDULE_INLINE_JOB_DEFAULT_RECORD_CAP")
            && schedule_page_validation.contains("page.frontend_jobs.len()")
            && schedule_page_validation.contains("page.codegen_jobs.len()")
            && schedule_page_validation
                .contains("SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE")
            && schedule_page_validation.contains("page.dependency_library_ids.len()")
            && schedule_page_validation
                .contains("validate_source_pack_library_schedule_job_inline_dependency_count(")
            && schedule_page_validation.contains("validate_source_pack_job_shape(")
            && schedule_page_validation.contains("&page.frontend_job")
            && schedule_page_validation.contains("page.frontend_jobs.iter().enumerate()")
            && schedule_page_validation.contains("page.codegen_jobs.iter().enumerate()"),
        "schedule page validation must reject unbounded inline dependency/job arrays and invalid job payload shapes before record scans"
    );
    let schedule_dependency_writer = source_between(
        &compiler,
        "impl<'a> SourcePackScheduleJobDependencyPageWriter<'a>",
        "fn store_source_pack_library_schedule_job_page_with_dependency_writer",
    );
    assert!(
        schedule_dependency_writer.contains("source_pack_try_push_dependency_job_range(")
            && schedule_dependency_writer
                .contains("for dependency_job_index in first_job_index..end_job_index")
            && schedule_dependency_writer.contains("self.push(dependency_job_index)?"),
        "schedule dependency range writing must preserve bounded range records before falling back to paged explicit dependency records"
    );
    let schedule_dependency_range_push = source_between(
        &compiler,
        "fn source_pack_try_push_dependency_job_range",
        "fn store_source_pack_library_schedule_job_page_with_dependency_writer",
    );
    assert!(
        schedule_dependency_range_push
            .contains("SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE")
            && schedule_dependency_range_push.contains("*dependency_job_ranges = compact_ranges"),
        "schedule dependency range records must remain capped before they are retained on job pages"
    );
    let schedule_job_page_validation = source_between(
        &compiler,
        "fn validate_source_pack_library_schedule_job_page",
        "fn validate_source_pack_library_schedule_job_dependency_page",
    );
    assert!(
        schedule_job_page_validation.contains("validate_source_pack_job_shape("),
        "schedule job page validation must validate bounded job payload shape before dependency scans"
    );
    assert!(
        schedule_job_page_validation
            .contains("SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE")
            && schedule_job_page_validation.contains("page.job.dependency_job_indices.len()")
            && schedule_job_page_validation.contains("page.dependency_job_ranges.len()"),
        "schedule job page validation must reject unbounded inline dependency and range arrays before record scans"
    );
    let shard_store = source_between(
        &compiler,
        "pub fn store_build_artifact_shard_plan",
        "pub fn store_build_artifact_execution_shards",
    );
    assert!(
        !shard_store.contains("shard_paths.push"),
        "artifact shard store results must report counts without retaining every shard path"
    );
    assert!(
        !shard_store.contains("batch_shard_locator_paths.push"),
        "artifact shard store results must report locator counts without retaining every locator path"
    );
    let execution_shard_store = source_between(
        &compiler,
        "pub fn store_build_artifact_execution_shards",
        "pub fn store_build_artifact_execution_shard_records",
    );
    assert!(
        !execution_shard_store.contains("paths.push"),
        "execution-shard store results must not retain every execution shard path"
    );
    assert!(
        execution_shard_store.contains("Some(manifest.artifacts.job_batch_count)"),
        "execution-shard storage from manifests must use the authoritative batch count instead of inferring it from transient edge vectors"
    );
    let page_metadata_shard_chunk_store = source_between(
        &compiler,
        "fn store_source_pack_build_artifact_shards_from_page_metadata_chunk",
        "fn source_pack_store_artifact_shard_prepare_progress",
    );
    assert!(
        page_metadata_shard_chunk_store.contains("SourcePackBuildArtifactShardPrepareProgress")
            && page_metadata_shard_chunk_store
                .contains("artifact_shard_prepare_progress_path_for_target")
            && page_metadata_shard_chunk_store.contains("max_new_batches")
            && page_metadata_shard_chunk_store.contains("progress.next_batch_index")
            && page_metadata_shard_chunk_store
                .contains("source_pack_build_artifact_shard_builder_for_stored_phase_batch(")
            && page_metadata_shard_chunk_store
                .contains("source_pack_store_pending_artifact_shard_prepare_builder(")
            && page_metadata_shard_chunk_store
                .contains("SourcePackBuildArtifactShardPreparePhase::BuildProgressDirectoryPages")
            && page_metadata_shard_chunk_store
                .contains("SourcePackBuildArtifactShardPreparePhase::BuildProgressDirectoryIndexPages")
            && page_metadata_shard_chunk_store
                .contains("source_pack_store_build_progress_directory_page_from_artifact_shard_prepare_progress(")
            && page_metadata_shard_chunk_store
                .contains("source_pack_store_build_progress_directory_index_page_from_artifact_shard_prepare_progress(")
            && page_metadata_shard_chunk_store.contains("new_prepare_unit_count")
            && page_metadata_shard_chunk_store
                .contains("store_source_pack_build_artifact_shard_compact_indexes("),
        "artifact-shard chunk prepare must resume with persisted shard-builder state, bounded progress-directory phases, and final compact indexes"
    );
    let page_metadata_execution_shard_store = source_between(
        &compiler,
        "fn source_pack_store_build_artifact_shard_from_page_metadata",
        "fn source_pack_store_pending_artifact_shard_prepare_builder",
    );
    assert!(
        page_metadata_execution_shard_store.contains("Some(job_batch_page_index.batch_count)"),
        "execution-shard storage from page metadata must use the stored job-batch index count instead of inferring it from transient edge vectors"
    );
    assert!(
        !page_metadata_shard_chunk_store.contains("0..job_batch_page_index.batch_count")
            && !page_metadata_shard_chunk_store
                .contains("0..link_batch_page_index.link_interface_batch_count")
            && !page_metadata_shard_chunk_store
                .contains("0..link_batch_page_index.link_object_batch_count")
            && !page_metadata_shard_chunk_store
                .contains("store_build_progress_directory_pages_for_summary")
            && !page_metadata_shard_chunk_store
                .contains("for directory_page_index in 0..progress_directory_page_count")
            && !page_metadata_shard_chunk_store.contains(
                "for directory_index_page_index in 0..progress_directory_index_page_count"
            ),
        "artifact-shard chunk prepare must not re-scan every stored batch or final progress directory"
    );
    let page_metadata_progress_directory_store = source_between(
        &compiler,
        "fn source_pack_store_build_progress_directory_page_from_artifact_shard_prepare_progress",
        "fn store_source_pack_build_artifact_shards_from_page_metadata_chunk",
    );
    assert!(
        page_metadata_progress_directory_store
            .contains("source_pack_build_progress_directory_page_from_summaries(")
            && page_metadata_progress_directory_store
                .contains("store_build_progress_directory_page_for_target(")
            && page_metadata_progress_directory_store
                .contains("source_pack_build_progress_directory_index_page_from_directory_pages(")
            && page_metadata_progress_directory_store
                .contains("store_build_progress_directory_index_page_for_target("),
        "artifact-shard chunk prepare must derive bounded build-progress directory pages from stored progress-shard summaries"
    );
    let page_metadata_shard_phase_builder = source_between(
        &compiler,
        "fn source_pack_build_artifact_shard_builder_for_stored_phase_batch",
        "fn source_pack_store_build_artifact_shard_from_page_metadata",
    );
    assert!(
        page_metadata_shard_phase_builder
            .contains("load_build_job_batch_page_for_target(target, batch_index)")
            && page_metadata_shard_phase_builder
                .contains("load_build_link_interface_batch_page_for_target(target, batch_index)")
            && page_metadata_shard_phase_builder
                .contains("load_build_link_object_batch_page_for_target(target, batch_index)")
            && page_metadata_shard_phase_builder
                .contains("source_pack_job_batch_shard_builder_from_stored_schedule_page("),
        "artifact-shard chunk prepare must build one shard-builder input from one persisted batch page"
    );
    let page_metadata_shard_chunk_emit = source_between(
        &compiler,
        "fn source_pack_store_build_artifact_shard_from_page_metadata",
        "fn source_pack_store_pending_artifact_shard_prepare_builder",
    );
    assert!(
        page_metadata_shard_chunk_emit.contains("store_source_pack_build_artifact_shard_page(")
            && page_metadata_shard_chunk_emit
                .contains("store_source_pack_build_batch_shard_locators(")
            && page_metadata_shard_chunk_emit
                .contains("source_pack_build_artifact_execution_shard_from_stored_pages(")
            && page_metadata_shard_chunk_emit
                .contains("store_build_artifact_execution_shard_with_batch_count(")
            && page_metadata_shard_chunk_emit
                .contains("source_pack_initial_build_progress_shard_from_execution_shard("),
        "artifact-shard chunk prepare must persist each emitted shard, execution shard, locator, and initial progress shard"
    );
    let execution_shard_record_store = source_between(
        &compiler,
        "fn store_build_artifact_execution_shard_with_batch_count(",
        "pub fn load_build_artifact_shard_index",
    );
    for required in [
        "store_source_pack_build_job_batch_dependency_pages(",
        "store_source_pack_build_job_batch_dependency_range_pages(",
        "store_build_job_batch_dependents_page(",
        "store_job_artifact_input_interface_pages_from_refs(",
        "dependency.dependency_batch_indices.clear();",
        "dependency.dependency_batch_ranges.clear();",
        "dependents.dependent_batch_indices.clear();",
        "job_manifest.input_interfaces.clear();",
        "job_manifest.input_objects.clear();",
    ] {
        assert!(
            execution_shard_record_store.contains(required),
            "execution-shard records must spill batch and job-artifact fan-in before persistence"
        );
    }
    assert!(
        execution_shard_record_store
            .contains("validate_source_pack_build_artifact_execution_shard_store_input("),
        "execution-shard records must validate transient spill inputs separately from persisted compact pages"
    );
    assert!(
        execution_shard_record_store.contains("let mut dependent_batch_count = batch_count;")
            && execution_shard_record_store
                .contains("source_pack_execution_shard_inferred_batch_count("),
        "execution-shard storage must lazily infer batch counts only for legacy direct record stores without a known count"
    );
    let execution_shard_validation = source_between(
        &compiler,
        "fn validate_source_pack_build_artifact_execution_shard",
        "fn validate_source_pack_build_batch_shard_locator",
    );
    assert!(
        compiler.contains("fn validate_source_pack_job_shape")
            && compiler.contains("job.oversized_source_file && job.source_file_count != 1")
            && compiler.contains("has non-link job payload"),
        "shared source-pack job validation must keep oversized source-file jobs to one file and link jobs payload-free"
    );
    assert!(
        execution_shard_validation
            .contains("SOURCE_PACK_EXECUTION_SHARD_SOURCE_FILE_DEFAULT_RECORD_CAP")
            && execution_shard_validation.contains("execution_shard.source_files.len()")
            && execution_shard_validation.contains("execution_shard.job_batches.len()")
            && execution_shard_validation.contains("execution_shard.batch_dependencies.len()")
            && execution_shard_validation.contains("execution_shard.batch_dependents.len()")
            && execution_shard_validation.contains("execution_shard.jobs.len()")
            && execution_shard_validation.contains("execution_shard.job_artifacts.len()")
            && execution_shard_validation.contains("execution_shard.artifact_refs.len()")
            && execution_shard_validation.contains("execution_shard.link_interface_batches.len()")
            && execution_shard_validation.contains("execution_shard.link_object_batches.len()"),
        "execution-shard validation must reject unbounded persisted side arrays before record scans"
    );
    assert!(
        execution_shard_validation
            .contains("SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE")
            && execution_shard_validation
                .contains("SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE")
            && execution_shard_validation
                .contains("SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE")
            && execution_shard_validation.contains("dependency.dependency_batch_indices.len()")
            && execution_shard_validation.contains("dependency.dependency_batch_ranges.len()")
            && execution_shard_validation.contains("dependents.dependent_batch_indices.len()"),
        "execution-shard validation must cap retained nested batch edge records"
    );
    assert!(
        source_before(
            execution_shard_validation,
            "\"batch dependency\",\n            dependency.dependency_batch_indices.len()",
            "source_pack_manifest_unique_usize_set(\n            &dependency.dependency_batch_indices",
        ) && source_before(
            execution_shard_validation,
            "\"batch dependency range\",\n            dependency.dependency_batch_ranges.len()",
            "source_pack_validate_job_batch_dependency_ranges(",
        ) && source_before(
            execution_shard_validation,
            "\"batch dependent\",\n            dependents.dependent_batch_indices.len()",
            "source_pack_manifest_unique_usize_set(\n            &dependents.dependent_batch_indices",
        ),
        "execution-shard validation must reject oversized retained nested edges before record scans"
    );
    assert!(
        execution_shard_validation.contains("SourcePackBuildArtifactShardKind::JobBatches")
            && execution_shard_validation
                .contains("job-batch record arrays do not match shard batch records")
            && execution_shard_validation
                .contains("link-interface record arrays do not match shard batch records")
            && execution_shard_validation
                .contains("link-object record arrays do not match shard batch records")
            && execution_shard_validation
                .contains("job record arrays do not match shard job records")
            && execution_shard_validation.contains("validate_source_pack_job_shape("),
        "execution-shard validation must prove persisted arrays match the shard-kind record contract"
    );
    let manifest_batch_dependency_validation = source_between(
        &compiler,
        "fn validate_source_pack_manifest_batch_dependencies",
        "fn validate_source_pack_manifest_job_artifacts",
    );
    assert!(
        manifest_batch_dependency_validation.contains("SourcePackJobPhase::Link")
            && manifest_batch_dependency_validation.contains("dependency_job_indices.is_empty()")
            && manifest_batch_dependency_validation.contains("SourcePackJobPhase::Codegen")
            && manifest_batch_dependency_validation
                .contains("expected.insert(dependency_batch_index)"),
        "artifact manifest dependency validation must derive implicit link-job dependencies from codegen job records"
    );
    let batch_locator_store = source_between(
        &compiler,
        "fn store_source_pack_build_batch_shard_locators",
        "fn store_source_pack_build_artifact_shard_compact_indexes",
    );
    assert!(
        !batch_locator_store.contains("paths.push"),
        "batch-shard locator helper must report counts without retaining every locator path"
    );
    let progress_shard_store = source_between(
        &compiler,
        "pub fn store_initial_build_progress_shards",
        "fn build_progress_summary_available_for_target",
    );
    assert!(
        !progress_shard_store.contains("paths.push"),
        "initial progress-shard store results must report counts without retaining every progress shard path"
    );
    let path_build_manifest_store = source_between(
        &compiler,
        "pub fn store_path_build_manifest(",
        "pub fn store_path_build_manifest_with_shard_limits(",
    );
    assert!(
        path_build_manifest_store.contains("store_path_build_manifest_with_shard_limits("),
        "default path-build manifest store must delegate to the shard-limited store path"
    );
    assert!(
        path_build_manifest_store.contains("SourcePackBuildShardLimits::default()"),
        "default path-build manifest store must set only default shard limits"
    );
    let path_build_manifest_store_with_shards = source_between(
        &compiler,
        "pub fn store_path_build_manifest_with_shard_limits(",
        "pub fn store_compact_path_build_manifest(",
    );
    assert!(
        path_build_manifest_store_with_shards.contains(".try_for_each_build_artifact_shard(")
            && path_build_manifest_store_with_shards.contains("shard_limits")
            && path_build_manifest_store_with_shards
                .contains("store_source_pack_build_artifact_shard_page(")
            && path_build_manifest_store_with_shards
                .contains("store_build_artifact_execution_shard_with_batch_count("),
        "shard-limited path-build manifest store must stream artifact shards into persisted shard and execution records"
    );
    let compact_path_build_manifest_store = source_between(
        &compiler,
        "pub fn store_compact_path_build_manifest(",
        "pub fn load_path_build_manifest",
    );
    assert!(
        compact_path_build_manifest_store.contains("source_files: Vec::new()")
            && compact_path_build_manifest_store.contains("library_dependencies: Vec::new()"),
        "compact path-build manifest store must not persist source-file or library-dependency arrays"
    );
    assert!(
        !path_build_manifest_store_with_shards.contains("SourcePackBuildShardLimits::default()"),
        "shard-limited path-build manifest store must not override caller shard limits"
    );
    assert!(
        !path_build_manifest_store_with_shards.contains(".build_artifact_shard_plan(")
            && !path_build_manifest_store_with_shards.contains("store_build_artifact_shard_plan("),
        "shard-limited path-build manifest store must not materialize the full artifact shard plan"
    );
    assert!(
        !compiler.contains("source_pack_job_batch_artifact_shards_for_index"),
        "filesystem source-pack progress paths must stream job-batch shard records instead of materializing all shards"
    );
    assert!(
        !compiler.contains("index.pages[page.page_index]"),
        "filesystem source-pack work-queue progress must update compact page summaries through page loads"
    );
    assert!(
        !compiler.contains("index.pages.get(") && !compiler.contains("index.pages.get_mut("),
        "filesystem source-pack work-queue progress must read page summaries from bounded sidecar records, not the root index"
    );
    let work_queue_progress_store = source_between(
        &compiler,
        "pub fn store_work_queue_progress(",
        "fn store_work_queue_progress_directory_pages_for_index",
    );
    assert!(
        work_queue_progress_store.contains("source_pack_work_queue_progress_page_summary(page)")
            && work_queue_progress_store.contains("do not match compact index"),
        "filesystem source-pack legacy progress storage must prove compact root counts from supplied page records without storing page-summary arrays"
    );
    assert!(
        !compiler.contains("let mut page_summaries = Vec::with_capacity(page_count);"),
        "filesystem source-pack work-queue progress initialization must not accumulate every page summary"
    );
    assert!(
        !compiler.contains("source_pack_initial_ready_batch_indices_from_stored_job_batch_pages"),
        "filesystem source-pack prepare must not return every initially ready batch"
    );
    let artifact_prepare_result = source_between(
        &compiler,
        "pub struct SourcePackFilesystemArtifactPrepareResult",
        "pub struct SourcePackFilesystemPreparedArtifactBuildSummary",
    );
    assert!(
        !artifact_prepare_result.contains("initial_ready_batch_indices")
            && !artifact_prepare_result.contains("initial_ready_work_item_indices"),
        "filesystem source-pack prepare result must expose compact ready counts and first indices, not all ready frontier arrays"
    );
    assert!(
        !compiler.contains("let mut initial_ready_item_indices = Vec::new()"),
        "filesystem source-pack prepare must not accumulate every initially ready work item"
    );
    assert!(
        !compiler.contains("\"source-pack-build\",\n        usize::MAX"),
        "filesystem source-pack full build must not retain every executed batch index"
    );
    assert!(
        !compiler.contains("completed_batch_indices.extend(progress.completed_batch_indices)"),
        "filesystem source-pack build-state loading must not rebuild every completed batch from progress shards"
    );
    assert!(
        !compiler.contains(
            "source_pack_build_state_ready_unclaimed_batch_indices_from_execution_shards"
        ),
        "filesystem source-pack ready queries must not rebuild ready batches from caller-provided whole-build state"
    );
    assert!(
        !compiler.contains("completed_batch_indices.to_vec()"),
        "filesystem source-pack ready queries must not persist caller-provided completed-batch arrays"
    );
    let build_state_record = source_between(
        &compiler,
        "pub struct SourcePackBuildState",
        "impl Default for SourcePackBuildState",
    );
    assert!(
        build_state_record.contains("pub completed_batch_count: usize")
            && build_state_record.contains("pub claimed_batch_count: usize")
            && !build_state_record.contains("completed_batch_indices")
            && !build_state_record.contains("claimed_batches"),
        "filesystem source-pack build state markers must persist compact counts and output key, not completed or claimed batch arrays"
    );
    let ready_batches_query = source_between(
        &compiler,
        "pub fn source_pack_filesystem_artifact_manifest_ready_batches_for_target",
        "pub fn source_pack_filesystem_artifact_manifest_build_state",
    );
    assert!(
        ready_batches_query.contains(
            "source_pack_filesystem_artifact_manifest_ready_state_batches_limited_for_target("
        ),
        "filesystem source-pack ready-batch compatibility query must delegate to bounded ready-state query"
    );
    let ready_state_batches_query = source_between(
        &compiler,
        "pub fn source_pack_filesystem_artifact_manifest_ready_state_batches",
        "#[cfg(test)]\nfn source_pack_path_build_manifest",
    );
    assert!(
        ready_state_batches_query.contains(
            "source_pack_filesystem_artifact_manifest_ready_state_batches_limited_for_target("
        ),
        "filesystem source-pack ready-state query must expose a bounded variant"
    );
    assert!(
        ready_state_batches_query.contains("Some(max_batches)"),
        "filesystem source-pack ready-state query must cap ready batch materialization with a normalized caller limit"
    );
    assert!(
        ready_state_batches_query
            .contains("let max_batches = source_pack_limit_ready_state_batches(max_batches)"),
        "filesystem source-pack ready-state query must cap oversized public ready-batch limits"
    );
    let path_manifest_ready_queries = source_between(
        &compiler,
        "impl SourcePackPathBuildManifest",
        "fn validate_source_pack_path_build_manifest_versions",
    );
    assert!(
        path_manifest_ready_queries.contains("pub fn ready_batch_indices_limited(")
            && path_manifest_ready_queries
                .contains("pub fn ready_unclaimed_batch_indices_from_state_limited(")
            && path_manifest_ready_queries.contains("max_batches: Option<usize>")
            && path_manifest_ready_queries.contains("state.claimed_batch_count"),
        "path-build manifest ready queries must expose capped variants and reject compact states with claimed batches instead of materializing claimed-batch arrays"
    );
    assert!(
        path_manifest_ready_queries
            .contains("ensure_inline_batch_dependency_records_for_ready_query")
            && path_manifest_ready_queries.contains("batch_dependencies.batches.len()")
            && path_manifest_ready_queries.contains("persisted progress state"),
        "path-build manifest ready queries must consume inline dependency records only when present and reject compact manifests in favor of persisted progress state"
    );
    assert!(
        !path_manifest_ready_queries.contains("pub fn ready_batch_indices(")
            && !path_manifest_ready_queries.contains("pub fn ready_batch_indices_from_state(")
            && !path_manifest_ready_queries
                .contains("pub fn ready_unclaimed_batch_indices_from_state("),
        "path-build manifests must not expose unbounded all-ready-batch compatibility queries"
    );
    let ready_unclaimed_manifest_query = source_between(
        &path_manifest_ready_queries,
        "pub fn ready_unclaimed_batch_indices_from_state_limited",
        "    pub fn is_state_complete",
    );
    assert!(
        !ready_unclaimed_manifest_query.contains("claimed_batch_indices(")
            && !ready_unclaimed_manifest_query.contains("ready_batch_indices_from_state(state)?"),
        "limited path-build manifest ready-unclaimed query must not materialize all claimed or ready batches before applying the cap"
    );
    assert!(
        !compiler.contains("max_batches.max(1)") && !compiler.contains("max_items.max(1)"),
        "filesystem source-pack worker runs must preserve zero-work chunks when normalizing caller limits"
    );
    assert!(
        !ready_state_batches_query.contains("None,\n        )?"),
        "filesystem source-pack ready-state query must not request every ready batch"
    );
    assert!(
        !compiler.contains("let mut executed_item_indices = Vec::new()"),
        "filesystem source-pack work-queue worker run must not retain every executed work item"
    );
    assert!(
        !compiler.contains("let mut executed_artifact_batch_indices = Vec::new()"),
        "filesystem source-pack work-queue worker run must not retain every executed artifact batch"
    );
    assert!(
        !compiler.contains("let mut executed_link_group_indices = Vec::new()"),
        "filesystem source-pack work-queue worker run must not retain every executed link group"
    );
    let work_queue_worker_run_result = source_between(
        &compiler,
        "pub struct SourcePackFilesystemWorkQueueWorkerRunExecutionResult",
        "pub const SOURCE_PACK_PATH_BUILD_MANIFEST_VERSION",
    );
    assert!(
        !work_queue_worker_run_result.contains("executed_item_indices")
            && !work_queue_worker_run_result.contains("executed_artifact_batch_indices")
            && !work_queue_worker_run_result.contains("executed_link_group_indices"),
        "filesystem source-pack work-queue worker-run results must expose execution counts and persisted progress, not unbounded executed-index arrays"
    );
    assert!(
        !compiler.contains("let mut newly_ready_item_indices = Vec::new()"),
        "filesystem source-pack work-queue item completion must not retain every newly ready dependent item"
    );
    assert!(
        !compiler.contains("BTreeMap::<usize, SourcePackWorkQueueProgressPage>::new()"),
        "filesystem source-pack work-queue completion must not cache every changed progress page"
    );
    assert!(
        !compiler.contains("progress_pages.into_values().collect::<Vec<_>>()"),
        "filesystem source-pack work-queue completion must flush changed progress pages incrementally"
    );
    assert!(
        compiler.contains("work_queue_progress_page_summary_path_for_target"),
        "filesystem source-pack work-queue progress must persist compact per-page summary records"
    );
    assert!(
        source_pack_surface
            .contains("source_pack_work_queue_progress_page_ready_items_are_claimed("),
        "filesystem source-pack ready scans must use page summaries to skip fully claimed ready pages"
    );
    assert!(
        !compiler.contains("newly_ready_item_indices.push"),
        "filesystem source-pack work-queue item completion must report newly ready dependents through counts"
    );
    let work_queue_completion_result = source_between(
        &compiler,
        "pub struct SourcePackFilesystemWorkQueueItemCompletionResult",
        "pub struct SourcePackFilesystemWorkQueueArtifactItemExecutionResult",
    );
    assert!(
        !work_queue_completion_result.contains("newly_ready_item_indices"),
        "filesystem source-pack work-queue completion results must expose newly-ready counts and bounded progress, not unbounded dependent arrays"
    );
    assert!(
        !compiler.contains("let mut executed_batch_indices = Vec::new()"),
        "filesystem source-pack artifact worker runs must not retain every executed batch"
    );
    assert!(
        !compiler.contains("executed_batch_indices.push"),
        "filesystem source-pack artifact worker runs must report executed batches through counts"
    );
    let artifact_store_batch_result = source_between(
        &compiler,
        "pub struct SourcePackArtifactStoreBatchExecutionResult",
        "pub const SOURCE_PACK_BUILD_STATE_VERSION",
    );
    assert!(
        artifact_store_batch_result.contains("pub job_count: usize")
            && !artifact_store_batch_result.contains("job_indices"),
        "source-pack artifact-store batch execution results must expose bounded job counts, not batch job-index arrays"
    );
    let artifact_batch_result = source_between(
        &compiler,
        "pub struct SourcePackFilesystemArtifactBatchExecutionResult",
        "pub struct SourcePackFilesystemArtifactBatchClaimResult",
    );
    assert!(
        artifact_batch_result.contains("pub job_count: usize")
            && !artifact_batch_result.contains("job_indices"),
        "filesystem source-pack artifact batch execution results must expose bounded job counts, not batch job-index arrays"
    );
    let artifact_worker_run_results = source_between(
        &compiler,
        "pub struct SourcePackFilesystemArtifactWorkerRunProgressExecutionResult",
        "pub struct SourcePackFilesystemWorkQueueProgressSnapshot",
    );
    assert!(
        !artifact_worker_run_results.contains("executed_batch_indices")
            && !artifact_worker_run_results.contains("completed_batch_indices")
            && !artifact_worker_run_results.contains("ready_batch_indices"),
        "filesystem source-pack artifact worker-run results must expose execution counts and persisted progress, not unbounded batch-index arrays"
    );
    let artifact_claim_result = source_between(
        &compiler,
        "pub struct SourcePackFilesystemArtifactBatchClaimResult",
        "pub struct SourcePackFilesystemArtifactProgressSnapshot",
    );
    assert!(
        !artifact_claim_result.contains("completed_batch_indices")
            && !artifact_claim_result.contains("claimed_batch_indices"),
        "filesystem source-pack artifact claim results must expose claim/completion counts, not unbounded batch-index arrays"
    );
    assert!(
        !compiler.contains("library_dependencies: library_dependencies.to_vec()"),
        "filesystem source-pack compact path manifests must not persist every library dependency edge"
    );
    assert!(
        !compiler.contains("dependency_page.dependent_item_indices.push(page.item_index)"),
        "filesystem source-pack work-queue prepare must not append all reverse dependents into item pages"
    );
    assert!(
        compiler
            .contains("source_pack_work_queue_record_work_item_dependents_dependency_completed(")
            && compiler.contains("load_work_queue_dependents_page_for_target(")
            && compiler
                .contains("source_pack_work_queue_record_dependent_range_dependency_completed("),
        "filesystem source-pack work-queue completion must iterate reverse dependents through bounded pages and ranged progress updates"
    );

    let ready_frontier_update = source_between(
        &compiler,
        "fn source_pack_update_ready_frontier_after_batch_completion_bounded",
        "fn store_source_pack_build_state_progress_shards",
    );
    assert!(
        ready_frontier_update.contains("source_pack_for_each_job_batch_dependent_index("),
        "filesystem source-pack completion must consume paged reverse batch dependents"
    );
    assert!(
        ready_frontier_update.contains("load_build_progress_summary_for_target(target)"),
        "filesystem source-pack completion must use compact progress counts for sparse reverse-dependent pages"
    );
    assert!(
        !ready_frontier_update.contains("load_build_artifact_shard_index"),
        "filesystem source-pack completion must not reload the global shard index to find reverse dependents"
    );

    let load_build_state = source_between(
        &compiler,
        "pub fn load_build_state_for_target",
        "pub fn load_or_init_build_state",
    );
    assert!(
        load_build_state.contains("load_source_pack_build_state_from_progress_summary("),
        "filesystem source-pack state loading must consume compact progress summaries"
    );
    assert!(
        !load_build_state.contains("load_build_artifact_shard_index"),
        "filesystem source-pack state loading must not scan the global shard index"
    );

    let claim_ready_batch = source_between(
        &compiler,
        "pub fn source_pack_filesystem_artifact_manifest_claim_ready_batch_for_target_at",
        "pub fn source_pack_filesystem_artifact_manifest_claim_ready_batch_progress",
    );
    assert!(
        claim_ready_batch
            .contains("source_pack_build_progress_first_ready_unclaimed_batch_index_from_summary("),
        "filesystem source-pack batch claiming must consume the compact progress summary frontier"
    );
    assert!(
        !claim_ready_batch.contains("load_build_artifact_shard_index"),
        "filesystem source-pack batch claiming must not scan the global shard index"
    );

    let ready_batch_runner = source_between(
        &compiler,
        "pub fn execute_source_pack_filesystem_artifact_manifest_ready_batches_for_target",
        "pub fn source_pack_filesystem_artifact_manifest_ready_batches",
    );
    assert!(
        ready_batch_runner.contains(
            "source_pack_build_progress_ready_unclaimed_batch_indices_from_summary_limited("
        ),
        "filesystem source-pack ready runner must page from the summary frontier"
    );
    assert!(
        ready_batch_runner
            .contains("execute_source_pack_filesystem_artifact_execution_shard_batch_for_target("),
        "filesystem source-pack ready runner must execute through the bounded execution-shard helper"
    );
    assert!(
        !ready_batch_runner.contains("load_build_artifact_shard_index"),
        "filesystem source-pack ready runner must not scan the global shard index"
    );
    let manifest_full_build = source_between(
        &compiler,
        "pub fn execute_source_pack_filesystem_artifact_manifest_build_for_target",
        "pub fn execute_source_pack_filesystem_artifact_manifest_batch",
    );
    assert!(
        manifest_full_build.contains(
            "let step_limit = source_pack_limit_artifact_manifest_full_build_batches(usize::MAX)"
        ) && manifest_full_build.contains("for _ in 0..step_limit")
            && !manifest_full_build.contains("while !progress.complete"),
        "filesystem source-pack full manifest build convenience API must be hard-bounded"
    );
    assert!(
        manifest_full_build.contains(
            "execute_source_pack_filesystem_artifact_manifest_worker_step_progress_for_target_at("
        ) && manifest_full_build
            .contains("execute_source_pack_filesystem_artifact_manifest_worker_run_for_target")
            && manifest_full_build.contains(
                "execute_source_pack_filesystem_artifact_manifest_ready_batches_for_target"
            ),
        "filesystem source-pack full manifest build must advance by persisted worker steps and direct large builds to resumable APIs"
    );

    let manifest_batch_runner = source_between(
        &compiler,
        "fn execute_source_pack_filesystem_artifact_execution_shard_batch_for_target",
        "pub fn source_pack_filesystem_artifact_manifest_claim_ready_batch",
    );
    assert!(
        manifest_batch_runner
            .contains("execute_source_pack_build_artifact_execution_shard_batch_paged("),
        "filesystem source-pack manifest batch execution must use the paged artifact executor path"
    );
    assert!(
        !manifest_batch_runner
            .contains("execute_source_pack_build_artifact_execution_shard_batch("),
        "filesystem source-pack manifest batch execution must not use the legacy whole-input executor path"
    );

    let manifest_claimed_batch = source_between(
        &compiler,
        "pub fn execute_source_pack_filesystem_artifact_manifest_claimed_batch_for_target_at",
        "pub fn execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_for_target_at",
    );
    assert!(
        manifest_claimed_batch.contains(
            "execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_for_target_at("
        ),
        "filesystem source-pack claimed-batch API must use the paged claimed execution path by default"
    );
    assert!(
        !manifest_claimed_batch.contains(
            "execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_for_target_at("
        ),
        "filesystem source-pack claimed-batch API must not use the legacy whole-input claimed execution path"
    );

    let manifest_worker_step = source_between(
        &compiler,
        "pub fn execute_source_pack_filesystem_artifact_manifest_worker_step_for_target_at",
        "pub fn execute_source_pack_filesystem_artifact_manifest_worker_step_progress",
    );
    assert!(
        manifest_worker_step.contains(
            "execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_for_target_at("
        ),
        "filesystem source-pack manifest worker steps must execute claimed batches through the paged path"
    );
    assert!(
        !manifest_worker_step.contains(
            "execute_source_pack_filesystem_artifact_manifest_claimed_batch_for_target_at("
        ),
        "filesystem source-pack manifest worker steps must not use the legacy claimed-batch executor"
    );
    let manifest_worker_run = source_between(
        &compiler,
        "pub fn execute_source_pack_filesystem_artifact_manifest_worker_run_for_target_at",
        "pub fn execute_source_pack_filesystem_artifact_manifest_worker_run_with_path_artifacts",
    );
    assert!(
        manifest_worker_run.contains(
            "let step_limit = source_pack_limit_artifact_worker_run_batches(max_batches)"
        ) && manifest_worker_run.contains("for _ in 0..step_limit"),
        "filesystem source-pack manifest worker runs must cap max_batches before looping"
    );

    let ready_batches_compat = source_between(
        &compiler,
        "pub fn source_pack_filesystem_artifact_manifest_ready_batches_for_target",
        "pub fn source_pack_filesystem_artifact_manifest_build_state",
    );
    assert!(
        ready_batches_compat.contains(
            "source_pack_filesystem_artifact_manifest_ready_state_batches_limited_for_target("
        ),
        "filesystem source-pack ready-batches compatibility API must delegate to bounded persisted progress state"
    );
    assert!(
        !ready_batches_compat.contains("load_build_artifact_shard_index"),
        "filesystem source-pack ready-batches compatibility API must not scan the global shard index"
    );

    let progress_summary_api = source_between(
        &compiler,
        "pub fn source_pack_filesystem_artifact_manifest_progress_summary_for_target",
        "pub fn source_pack_filesystem_artifact_manifest_progress_snapshot",
    );
    assert!(
        progress_summary_api.contains("store.load_build_progress_summary_for_target(target)"),
        "filesystem source-pack progress summary API must read the compact summary record"
    );
    assert!(
        !progress_summary_api.contains("load_build_artifact_shard_index"),
        "filesystem source-pack progress summary API must not reconstruct from shard pages"
    );

    let progress_page_api = source_between(
        &compiler,
        "pub fn source_pack_filesystem_artifact_manifest_progress_page_for_target_at",
        "pub fn source_pack_filesystem_work_queue_progress_snapshot",
    );
    assert!(
        progress_page_api.contains("load_build_artifact_shard_for_target(target, shard_index)"),
        "filesystem source-pack progress page API must load only the requested shard page"
    );
    assert!(
        !progress_page_api.contains("load_build_artifact_shard_index"),
        "filesystem source-pack progress page API must not scan the global shard index"
    );
    let artifact_progress_snapshot_api = source_between(
        &compiler,
        "pub fn source_pack_filesystem_artifact_manifest_progress_snapshot_for_target_at",
        "pub fn source_pack_filesystem_artifact_manifest_progress_page",
    );
    assert!(
        artifact_progress_snapshot_api
            .contains("source_pack_limit_ready_state_batches(max_ready_batches)"),
        "filesystem source-pack artifact progress snapshots must cap public ready-batch materialization"
    );
    let work_queue_progress_snapshot_api = source_between(
        &compiler,
        "fn source_pack_filesystem_work_queue_progress_snapshot_from_index",
        "fn source_pack_work_queue_singleton_artifact_batch_index_for_item",
    );
    assert!(
        work_queue_progress_snapshot_api
            .contains("source_pack_limit_ready_state_items(max_ready_items)"),
        "filesystem source-pack work-queue progress snapshots must cap public ready-item materialization"
    );

    let ready_state_batches = source_between(
        &compiler,
        "pub fn source_pack_filesystem_artifact_manifest_ready_state_batches_for_target",
        "fn source_pack_path_build_manifest",
    );
    assert!(
        ready_state_batches.contains(
            "source_pack_build_progress_ready_unclaimed_batch_indices_from_summary_limited("
        ),
        "filesystem source-pack ready-state query must consume the compact progress summary frontier"
    );
    assert!(
        !ready_state_batches.contains("load_build_artifact_shard_index"),
        "filesystem source-pack ready-state query must not scan the global shard index"
    );
    let ready_batch_query = source_between(
        &build_progress,
        "fn source_pack_build_progress_ready_unclaimed_batch_indices_from_summary_limited",
        "fn source_pack_build_progress_first_ready_unclaimed_batch_index_from_summary",
    );
    assert!(
        ready_batch_query.contains("summary.job_batch_shard_count != 0"),
        "filesystem source-pack ready-state query must use compact job-batch shard counts when present"
    );
    assert!(
        ready_batch_query.contains("load_build_progress_shard_for_target("),
        "filesystem source-pack ready-state query must scan bounded progress shards instead of every batch gap"
    );
    assert!(
        ready_batch_query.contains("source_pack_build_progress_shard_ready_batches_are_claimed("),
        "filesystem source-pack ready-state query must skip fully claimed shards through compact shard summaries"
    );
    assert!(
        ready_batch_query
            .contains("source_pack_build_progress_directory_page_from_store_or_summaries("),
        "filesystem source-pack ready-state query must skip empty progress-shard groups through directory pages"
    );
    assert!(
        ready_batch_query.contains(
            "source_pack_build_progress_directory_index_page_from_store_or_directory_pages("
        ) && ready_batch_query.contains("directory_index_page.ready_directory_page_count"),
        "filesystem source-pack ready-state query must skip empty directory-page groups through directory-index pages"
    );
    assert!(
        ready_batch_query
            .contains("source_pack_build_progress_directory_ready_shards_are_claimed("),
        "filesystem source-pack ready-state query must skip fully claimed progress-shard groups through directory pages"
    );
    assert!(
        ready_batch_query
            .contains("source_pack_build_progress_directory_index_ready_pages_are_claimed("),
        "filesystem source-pack ready-state query must skip fully claimed directory-page groups through directory-index pages"
    );
    assert!(
        ready_batch_query.contains("source_pack_build_progress_summary_ready_batches_are_claimed("),
        "filesystem source-pack ready-state query must skip fully claimed frontiers through compact progress summaries"
    );
    let first_ready_query = source_between(
        &build_progress,
        "fn source_pack_build_progress_first_ready_batch_index_from_summary_pages_bounded",
        "fn source_pack_build_progress_ready_unclaimed_batch_indices_from_summary_limited",
    );
    assert!(
        first_ready_query.contains("summary.job_batch_shard_count != 0"),
        "filesystem source-pack first-ready refresh must use compact job-batch shard counts when present"
    );
    assert!(
        first_ready_query.contains("load_build_progress_shard_for_target("),
        "filesystem source-pack first-ready refresh must scan bounded progress shards instead of every batch gap"
    );
    assert!(
        first_ready_query.contains("source_pack_build_progress_shard_summary_from_store("),
        "filesystem source-pack first-ready refresh must use compact progress-shard summaries before loading full shards"
    );
    assert!(
        first_ready_query
            .contains("source_pack_build_progress_directory_page_from_store_or_summaries("),
        "filesystem source-pack first-ready refresh must skip empty progress-shard groups through directory pages"
    );
    assert!(
        first_ready_query.contains(
            "source_pack_build_progress_directory_index_page_from_store_or_directory_pages("
        ) && first_ready_query.contains("directory_index_page.ready_directory_page_count"),
        "filesystem source-pack first-ready refresh must skip empty directory-page groups through directory-index pages"
    );
    let first_ready_unclaimed_query = source_after(
        &build_progress,
        "fn source_pack_build_progress_first_ready_unclaimed_batch_index_from_summary",
    );
    assert!(
        first_ready_unclaimed_query
            .contains("source_pack_build_progress_summary_ready_batches_are_claimed("),
        "filesystem source-pack first-ready claim query must skip fully claimed frontiers through compact progress summaries"
    );
    let progress_shard_validation = source_between(
        &build_progress,
        "fn validate_source_pack_build_progress_shard",
        "fn validate_source_pack_build_progress_shard_summary",
    );
    assert!(
        progress_shard_validation.contains("DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES")
            && progress_shard_validation.contains("shard.batch_indices.len()")
            && progress_shard_validation.contains("shard.completed_batch_indices.len()")
            && progress_shard_validation.contains("shard.ready_batch_indices.len()")
            && progress_shard_validation.contains("shard.claimed_batches.len()"),
        "filesystem source-pack progress shards must reject unbounded persisted batch arrays before record scans"
    );
    let progress_shard_summary_validation = source_between(
        &build_progress,
        "fn validate_source_pack_build_progress_shard_summary",
        "fn validate_source_pack_build_progress_summary",
    );
    assert!(
        progress_shard_summary_validation.contains("DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES")
            && progress_shard_summary_validation.contains("summary.batch_count"),
        "filesystem source-pack progress shard summaries must preserve bounded per-shard batch counts"
    );
    let progress_shard_store = source_between(
        &compiler,
        "fn write_build_progress_shard_file",
        "pub fn store_build_progress_summary",
    );
    assert!(
        progress_shard_store.contains("store_build_progress_shard_summary_for_target("),
        "filesystem source-pack progress shard stores must write compact shard summary sidecars"
    );
    let progress_summary_store = source_between(
        &compiler,
        "pub fn store_build_progress_summary",
        "pub fn load_build_progress_summary_for_target",
    );
    assert!(
        !progress_summary_store.contains("ready_shard_indices")
            && !progress_summary_store.contains("claimed_shard_indices")
            && progress_summary_store.contains("let compact_summary = summary.clone()"),
        "filesystem source-pack progress summary stores must write compact count/frontier summaries without shard-frontier arrays"
    );
    let progress_shard_update = source_between(
        &compiler,
        "pub fn store_build_progress_shard(",
        "fn write_build_progress_shard_file",
    );
    assert!(
        progress_shard_update.contains("store_build_progress_directory_page_for_shard("),
        "filesystem source-pack progress shard updates must refresh compact directory pages"
    );
    assert!(
        progress_shard_update.contains("store_build_progress_directory_page_for_shard(")
            && source_between(
                &compiler,
                "fn store_build_progress_directory_page_for_shard",
                "fn store_build_progress_directory_pages_for_summary",
            )
            .contains("store_build_progress_directory_index_page_for_target("),
        "filesystem source-pack progress shard updates must refresh compact directory-index pages"
    );
    let progress_lease_recompute = source_between(
        &build_progress,
        "fn source_pack_build_progress_earliest_claim_lease_from_summary_shards_bounded",
        "fn source_pack_build_progress_summary_for_frontier_bounded",
    );
    assert!(
        progress_lease_recompute.contains(
            "source_pack_build_progress_directory_index_page_from_store_or_directory_pages("
        ),
        "filesystem source-pack claim-lease recompute must consume compact directory-index pages"
    );
    assert!(
        !progress_lease_recompute.contains("for shard_index in 0..summary.job_batch_shard_count"),
        "filesystem source-pack claim-lease recompute must not scan every progress shard summary"
    );
    let ready_dependency_artifacts = source_between(
        &compiler,
        "fn validate_source_pack_ready_batch_dependency_artifacts_from_execution_shards",
        "fn validate_source_pack_ready_batch_dependency_artifact_from_execution_shards",
    );
    assert!(
        ready_dependency_artifacts
            .contains("source_pack_for_each_stored_job_batch_dependency_index("),
        "filesystem source-pack ready dependency validation must stream stored dependency pages"
    );
    assert!(
        ready_dependency_artifacts.contains(
            "validate_source_pack_ready_batch_dependency_artifact_from_execution_shards("
        ),
        "filesystem source-pack ready dependency validation must validate each dependency as it is streamed"
    );
    assert!(
        !ready_dependency_artifacts.contains("let mut dependency_batch_indices"),
        "filesystem source-pack ready dependency validation must not accumulate all dependency batches"
    );

    let stored_artifact_ref_prepare = source_between(
        &compiler,
        "fn store_source_pack_build_artifact_ref_pages_from_stored_schedule_pages",
        "fn source_pack_build_artifact_ref_page",
    );
    assert!(
        stored_artifact_ref_prepare.contains("source_pack_for_each_stored_schedule_codegen_job("),
        "filesystem source-pack artifact-ref prepare must consume stored schedule job pages"
    );
    assert!(
        stored_artifact_ref_prepare.contains(
            "store_source_pack_build_artifact_ref_pages_from_stored_schedule_pages_chunk("
        ) && stored_artifact_ref_prepare.contains("SourcePackBuildArtifactRefPrepareProgress")
            && stored_artifact_ref_prepare.contains("progress.next_partition_index")
            && stored_artifact_ref_prepare
                .contains("load_build_artifact_ref_prepare_progress_for_target(")
            && stored_artifact_ref_prepare.contains("store_build_artifact_ref_prepare_progress(")
            && stored_artifact_ref_prepare.contains("max_new_libraries")
            && stored_artifact_ref_prepare.contains("new_library_count")
            && stored_artifact_ref_prepare.contains("artifact_ref_index_path: None")
            && stored_artifact_ref_prepare
                .contains("store.store_build_artifact_ref_index(&index)?"),
        "filesystem source-pack artifact-ref prepare must expose bounded progress-backed chunks and defer the compact artifact-ref index until all library artifact refs are present"
    );
    assert!(
        !stored_artifact_ref_prepare
            .contains("source_pack_schedule_partition_artifact_ref_pages_are_complete("),
        "filesystem source-pack artifact-ref chunks must not rediscover prior partitions by probing every artifact-ref page"
    );
    assert!(
        !stored_artifact_ref_prepare.contains("for job in &page.codegen_jobs"),
        "filesystem source-pack artifact-ref prepare must not consume inline schedule-page codegen jobs"
    );
    assert!(
        stored_artifact_ref_prepare.contains("total_source_line_count")
            && stored_artifact_ref_prepare.contains("frontend_job.source_lines")
            && stored_artifact_ref_prepare.contains("job.source_lines"),
        "filesystem source-pack artifact-ref prepare must preserve source-line totals from stored job records"
    );
    let stored_interface_link_batch_prepare = source_between(
        &compiler,
        "fn store_source_pack_build_link_interface_batch_pages_from_stored_artifact_ref_pages",
        "fn store_source_pack_build_link_object_batch_pages_from_stored_artifact_ref_pages",
    );
    let stored_object_link_batch_prepare = source_between(
        &compiler,
        "fn store_source_pack_build_link_object_batch_pages_from_stored_artifact_ref_pages",
        "fn store_source_pack_job_batch_dependents_pages_from_stored_job_batch_pages",
    );
    let stored_link_batch_validation = source_between(
        &compiler,
        "fn validate_source_pack_build_link_interface_batch_page",
        "fn validate_source_pack_build_link_input_shard_index",
    );
    assert!(
        stored_interface_link_batch_prepare
            .contains("source_pack_link_batch_input_limit(batch_limits)")
            && stored_object_link_batch_prepare
                .contains("source_pack_link_batch_input_limit(batch_limits)")
            && stored_link_batch_validation
                .contains("SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE"),
        "filesystem source-pack link-batch pages must consume artifact-ref pages and cap inline input records"
    );
    let stored_link_batch_chunk_prepare = source_between(
        &compiler,
        "fn store_source_pack_build_link_batch_pages_from_stored_artifact_ref_pages_chunk",
        "fn store_source_pack_build_link_interface_batch_pages_from_stored_artifact_ref_pages",
    );
    assert!(
        stored_link_batch_chunk_prepare.contains("SourcePackBuildLinkBatchPrepareProgress")
            && stored_link_batch_chunk_prepare
                .contains("build_link_batch_prepare_progress_path_for_target")
            && stored_link_batch_chunk_prepare.contains("next_interface_artifact_index")
            && stored_link_batch_chunk_prepare.contains("next_object_artifact_index")
            && stored_link_batch_chunk_prepare.contains("max_new_batches")
            && stored_link_batch_chunk_prepare.contains("link_batch_index_path: None")
            && stored_link_batch_chunk_prepare
                .contains("store.store_build_link_batch_page_index(&index)?"),
        "filesystem source-pack link-batch pages must expose persisted resumable chunks and defer the compact link-batch index until interface and object artifact ranges are fully batched"
    );

    let stored_job_batch_prepare = source_between(
        &compiler,
        "fn store_source_pack_build_job_batch_pages_from_stored_schedule_pages",
        "struct SourcePackStoredJobBatchBuilder",
    );
    assert!(
        stored_job_batch_prepare.contains("source_pack_stored_schedule_job_metadata("),
        "stored job-batch prepare must load schedule job metadata without hydrating every dependency"
    );
    assert!(
        stored_job_batch_prepare
            .contains("store_source_pack_build_job_batch_pages_from_stored_schedule_pages_chunk(")
            && stored_job_batch_prepare.contains("SourcePackBuildJobBatchPrepareProgress")
            && stored_job_batch_prepare
                .contains("build_job_batch_prepare_progress_path_for_target")
            && stored_job_batch_prepare.contains("progress.next_job_index")
            && stored_job_batch_prepare.contains("max_new_batches")
            && stored_job_batch_prepare.contains("job_batch_index_path: None")
            && stored_job_batch_prepare.contains("store.store_build_job_batch_page_index(&index)?"),
        "stored job-batch prepare must expose persisted resumable chunks and defer the compact batch index until every scheduled job is batched"
    );
    assert!(
        !stored_job_batch_prepare.contains("source_pack_stored_schedule_job("),
        "stored job-batch prepare must not materialize schedule job dependency vectors before batching"
    );
    assert!(
        stored_job_batch_prepare.contains("source_lines"),
        "stored job-batch prepare must pass bounded source-line totals into batch pages"
    );
    assert!(
        !compiler
            .contains("fn source_pack_initial_ready_batch_summary_from_stored_job_batch_pages"),
        "stored job-batch prepare must not reread every stored batch page to recover the initial ready frontier"
    );
    let stored_job_batch_dependency = source_between(
        &compiler,
        "fn source_pack_stored_job_batch_dependency",
        "fn source_pack_insert_dependency_batch_range_for_jobs",
    );
    assert!(
        stored_job_batch_dependency.contains(".dependency_job_ranges")
            && stored_job_batch_dependency
                .contains("source_pack_for_each_schedule_job_explicit_dependency_index(")
            && stored_job_batch_dependency
                .contains("source_pack_insert_dependency_batch_range_for_jobs("),
        "stored job-batch dependency construction must consume explicit dependency pages and compact dependency ranges"
    );
    assert!(
        stored_job_batch_dependency.contains("SourcePackBuildJobBatchDependencyPageWriter::new("),
        "stored job-batch dependency construction must write dependency pages directly"
    );
    assert!(
        stored_job_batch_dependency.contains("source_pack_write_dependency_batch_for_job("),
        "stored job-batch dependency construction must route each dependency through the bounded writer"
    );
    assert!(
        !stored_job_batch_dependency.contains("let mut dependency_batch_indices"),
        "stored job-batch dependency construction must not accumulate all dependency batches before paging"
    );
    assert!(
        !stored_job_batch_dependency
            .contains("for &dependency_job_index in &job.dependency_job_indices"),
        "stored job-batch dependency construction must not read whole dependency vectors from jobs"
    );
    let job_batch_dependency_writer = source_between(
        &compiler,
        "impl<'a> SourcePackBuildJobBatchDependencyPageWriter<'a>",
        "fn source_pack_for_each_stored_job_batch_dependency_index",
    );
    assert!(
        job_batch_dependency_writer.contains("seen_dependency_batch_indices: BTreeSet::new()")
            && job_batch_dependency_writer.contains(".seen_dependency_batch_indices"),
        "stored job-batch dependency writer must preserve per-batch set semantics without rereading flushed pages"
    );
    assert!(
        !job_batch_dependency_writer.contains("load_build_job_batch_dependency_page_for_target("),
        "stored job-batch dependency writer must not reread flushed dependency pages for duplicate checks"
    );
    let job_batch_page_store = source_between(
        &compiler,
        "pub fn store_build_job_batch_page",
        "pub fn load_build_job_batch_page_for_target",
    );
    assert!(
        job_batch_page_store.contains("store_source_pack_build_job_batch_dependency_pages("),
        "stored job-batch pages must spill forward dependency ids into bounded dependency pages"
    );
    assert!(
        job_batch_page_store.contains("store_source_pack_build_job_batch_dependency_range_pages("),
        "stored job-batch pages must spill dependency ranges into bounded dependency range pages"
    );
    assert!(
        job_batch_page_store.contains("stored_page.dependency.dependency_batch_indices.clear()"),
        "stored job-batch pages must not retain spilled forward dependency ids inline"
    );
    assert!(
        job_batch_page_store.contains("stored_page.dependency.dependency_batch_ranges.clear()"),
        "stored job-batch pages must not retain spilled dependency ranges inline"
    );
    assert!(
        job_batch_page_store.contains("validate_source_pack_build_job_batch_page_store_input("),
        "stored job-batch pages must validate transient spill inputs separately from persisted compact pages"
    );
    let job_batch_page_validation = source_between(
        &compiler,
        "fn validate_source_pack_build_job_batch_page",
        "fn validate_source_pack_build_job_batch_dependency_page",
    );
    assert!(
        job_batch_page_validation
            .contains("SOURCE_PACK_BUILD_JOB_BATCH_INLINE_JOB_DEFAULT_RECORD_CAP")
            && job_batch_page_validation.contains("page.batch.job_indices.len()"),
        "stored job-batch page validation must cap retained inline job records"
    );
    assert!(
        source_before(
            job_batch_page_validation,
            "page.batch.job_indices.len() > SOURCE_PACK_BUILD_JOB_BATCH_INLINE_JOB_DEFAULT_RECORD_CAP",
            "source_pack_manifest_unique_usize_set(\n        &page.batch.job_indices",
        ),
        "stored job-batch page validation must reject oversized inline jobs before uniqueness scans"
    );
    assert!(
        job_batch_page_validation
            .contains("SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE")
            && job_batch_page_validation.contains("page.dependency.dependency_batch_indices.len()")
            && job_batch_page_validation
                .contains("SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE")
            && job_batch_page_validation.contains("page.dependency.dependency_batch_ranges.len()"),
        "stored job-batch page validation must cap retained inline dependency records"
    );
    assert!(
        source_before(
            job_batch_page_validation,
            "\"dependency\",\n        page.dependency.dependency_batch_indices.len()",
            "source_pack_manifest_unique_usize_set(\n        &page.dependency.dependency_batch_indices",
        ) && source_before(
            job_batch_page_validation,
            "\"dependency range\",\n        page.dependency.dependency_batch_ranges.len()",
            "source_pack_validate_job_batch_dependency_ranges(",
        ),
        "stored job-batch page validation must reject oversized retained dependencies before record scans"
    );
    let stored_job_batch_dependency_iter = source_between(
        &compiler,
        "fn source_pack_for_each_stored_job_batch_dependency_index",
        "fn validate_source_pack_build_state_version",
    );
    assert!(
        stored_job_batch_dependency_iter
            .contains("load_build_job_batch_dependency_page_for_target("),
        "stored job-batch dependency iteration must stream bounded dependency pages"
    );
    assert!(
        stored_job_batch_dependency_iter
            .contains("load_build_job_batch_dependency_range_page_for_target("),
        "stored job-batch dependency iteration must stream bounded dependency range pages"
    );
    assert!(
        !stored_job_batch_dependency_iter.contains("let mut dependency_batch_indices"),
        "stored job-batch dependency iteration must not hydrate all dependency pages into a Vec"
    );
    let stored_job_batch_dependents_prepare = source_between(
        &compiler,
        "fn store_source_pack_job_batch_dependents_pages_from_stored_job_batch_pages",
        "fn store_source_pack_job_batch_dependents_pages_from_manifest_dependencies",
    );
    assert!(
        stored_job_batch_dependents_prepare
            .contains("source_pack_for_each_stored_job_batch_dependency_index("),
        "stored reverse batch-dependent pages must consume forward dependencies from stored pages"
    );
    assert!(
        !stored_job_batch_dependents_prepare
            .contains("source_pack_for_each_job_batch_dependency_index("),
        "stored reverse batch-dependent pages must not require inline forward dependency vectors"
    );
    assert!(
        !compiler.contains("fn store_source_pack_empty_job_batch_dependents_pages"),
        "reverse batch-dependent setup must not pre-create empty dependents pages for every batch"
    );
    let stored_job_batch_dependents_chunk_prepare = source_between(
        &compiler,
        "fn store_source_pack_job_batch_dependents_pages_from_stored_job_batch_pages_chunk",
        "fn source_pack_store_job_batch_dependents_prepare_progress",
    );
    assert!(
        stored_job_batch_dependents_chunk_prepare
            .contains("SourcePackJobBatchDependentsPrepareProgress")
            && stored_job_batch_dependents_chunk_prepare
                .contains("build_job_batch_dependents_prepare_progress_path_for_target")
            && stored_job_batch_dependents_chunk_prepare.contains("max_new_batches")
            && stored_job_batch_dependents_chunk_prepare.contains("progress.next_batch_index")
            && stored_job_batch_dependents_chunk_prepare
                .contains("source_pack_for_each_stored_job_batch_dependency_index(")
            && stored_job_batch_dependents_chunk_prepare
                .contains("source_pack_append_job_batch_dependent_page("),
        "stored reverse batch-dependent chunk prepare must resume from progress and consume stored forward dependency pages"
    );
    assert!(
        !stored_job_batch_dependents_chunk_prepare
            .contains("for batch_index in 0..index.batch_count")
            && !stored_job_batch_dependents_chunk_prepare
                .contains("source_pack_for_each_job_batch_dependency_index("),
        "stored reverse batch-dependent chunk prepare must not re-scan all batches or require inline dependency vectors"
    );
    let job_batch_dependents_loader = source_between(
        &compiler,
        "pub fn load_build_job_batch_dependents_page_for_target",
        "pub fn store_build_job_batch_dependent_batch_page",
    );
    let job_batch_dependents_store = source_between(
        &compiler,
        "pub fn store_build_job_batch_dependents_page",
        "pub fn load_build_job_batch_dependents_page_for_target",
    );
    assert!(
        job_batch_dependents_store.contains("store_build_job_batch_dependent_pages_from_indices(")
            && job_batch_dependents_store
                .contains("stored_page.dependents.dependent_batch_indices.clear();")
            && job_batch_dependents_store.contains("stored_page.dependent_batch_count")
            && job_batch_dependents_store.contains("stored_page.dependent_page_count"),
        "reverse batch-dependent count pages must spill inline dependent vectors into bounded dependent-batch pages"
    );
    assert!(
        job_batch_dependents_store
            .contains("validate_source_pack_build_job_batch_dependents_page_store_input("),
        "reverse batch-dependent count pages must validate transient spill inputs separately from persisted compact pages"
    );
    assert!(
        job_batch_dependents_store.contains("let mut seen = BTreeSet::new();")
            && job_batch_dependents_store.contains("duplicate dependent batch"),
        "reverse batch-dependent stores must preserve uniqueness while streaming inline dependents into pages"
    );
    let job_batch_dependents_validation = source_between(
        &compiler,
        "fn validate_source_pack_build_job_batch_dependents_page",
        "fn validate_source_pack_build_job_batch_dependent_batch_page",
    );
    assert!(
        job_batch_dependents_validation
            .contains("SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE")
            && job_batch_dependents_validation
                .contains("page.dependents.dependent_batch_indices.len()"),
        "reverse batch-dependent validation must cap retained inline dependent records"
    );
    assert!(
        source_before(
            job_batch_dependents_validation,
            "\"dependent\",\n        page.dependents.dependent_batch_indices.len()",
            "source_pack_manifest_unique_usize_set(\n        &page.dependents.dependent_batch_indices",
        ),
        "reverse batch-dependent validation must reject oversized retained dependents before uniqueness scans"
    );
    assert!(
        job_batch_dependents_loader.contains("source_pack_empty_build_job_batch_dependents_page("),
        "reverse batch-dependent loaders must treat missing sparse pages as validated empty records"
    );
    assert!(
        job_batch_dependents_loader.contains("load_build_job_batch_page_index_for_target(target)"),
        "embedded-count reverse dependent lookup must recover sparse empty page counts from the batch index"
    );
    let stored_artifact_shard_builder = source_between(
        &compiler,
        "fn source_pack_job_batch_shard_builder_from_stored_schedule_page",
        "fn source_pack_link_interface_batch_shard_builder_from_page",
    );
    assert!(
        stored_artifact_shard_builder.contains("source_pack_stored_schedule_job_metadata("),
        "stored artifact-shard planning must load schedule job metadata without hydrating dependencies"
    );
    assert!(
        !stored_artifact_shard_builder
            .contains("source_pack_for_each_stored_schedule_job_dependency_index("),
        "stored artifact-shard planning must not duplicate per-job dependency artifact refs into shard inputs"
    );
    assert!(
        !stored_artifact_shard_builder
            .contains("builder.input_artifact_indices.insert(dependency_job_index)"),
        "stored job-batch shards must rely on paged job input-interface refs instead of embedding dependency artifacts"
    );
    assert!(
        !stored_artifact_shard_builder.contains("source_pack_stored_schedule_job("),
        "stored artifact-shard planning must not materialize schedule job dependency vectors"
    );
    assert!(
        !stored_artifact_shard_builder.contains(".extend(job.dependency_job_indices"),
        "stored artifact-shard planning must not copy hydrated job dependency vectors"
    );
    assert!(
        stored_artifact_shard_builder.contains("builder.source_lines = batch.source_lines"),
        "stored artifact-shard planning must preserve source-line totals from batch records"
    );

    let stored_link_leaf_prepare = source_between(
        &compiler,
        "fn store_source_pack_hierarchical_link_leaf_groups_from_stored_schedule_pages_chunk",
        "fn store_source_pack_hierarchical_link_reduce_groups_from_stored_leaf_groups_chunk",
    );
    assert!(
        stored_link_leaf_prepare.contains("source_pack_for_each_stored_schedule_codegen_job(")
            && stored_link_leaf_prepare.contains("max_new_partitions")
            && stored_link_leaf_prepare.contains("progress.next_partition_index"),
        "filesystem source-pack link leaf planning must consume stored schedule job pages in bounded chunks"
    );
    assert!(
        stored_link_leaf_prepare.contains("source_pack_stored_leaf_link_group("),
        "filesystem source-pack link planning must build leaf groups through the stored schedule dependency path"
    );
    assert!(
        stored_link_leaf_prepare.contains("source_pack_stored_codegen_job_dependency_count("),
        "filesystem source-pack link planning must read frontend dependency fan-in from bounded codegen schedule job pages"
    );
    assert!(
        !stored_link_leaf_prepare.contains("for job in &page.codegen_jobs"),
        "filesystem source-pack link planning must not consume inline schedule-page codegen jobs"
    );
    let stored_link_reduce_prepare = source_between(
        &compiler,
        "fn store_source_pack_hierarchical_link_reduce_groups_from_stored_leaf_groups_chunk",
        "fn store_source_pack_hierarchical_link_execution_from_stored_schedule_pages_chunk",
    );
    assert!(
        stored_link_reduce_prepare.contains("current_level_first_group_index"),
        "filesystem source-pack link planning must track stored group levels as compact ranges"
    );
    assert!(
        !stored_link_reduce_prepare.contains("let mut current_level_group_indices = Vec::new()"),
        "filesystem source-pack link planning must not accumulate every group index in a level"
    );
    assert!(
        !stored_link_reduce_prepare.contains("let mut next_level_group_indices = Vec::new()"),
        "filesystem source-pack link planning must not accumulate every next-level group index"
    );
    assert!(
        stored_link_reduce_prepare.contains("input_partition_count"),
        "filesystem source-pack link planning must retain partition totals as counts"
    );
    assert!(
        stored_link_leaf_prepare.contains("current_source_line_count")
            && stored_link_leaf_prepare.contains("job.source_lines")
            && stored_link_reduce_prepare.contains("input_group.source_line_count"),
        "filesystem source-pack link planning must propagate bounded source-line totals through leaf and reduce groups"
    );
    assert!(
        stored_link_reduce_prepare.contains("input_partition_indices: Vec::new()"),
        "filesystem source-pack reduce groups must not persist all transitive partition indices"
    );
    assert!(
        !stored_link_reduce_prepare.contains("input_partition_indices.extend"),
        "filesystem source-pack link planning must not accumulate transitive partition-index sets"
    );
    let stored_link_leaf_chunk_prepare = source_between(
        &compiler,
        "fn store_source_pack_hierarchical_link_leaf_groups_from_stored_schedule_pages_chunk",
        "fn store_source_pack_hierarchical_link_leaf_groups_for_schedule_page",
    );
    assert!(
        stored_link_leaf_chunk_prepare.contains("SourcePackHierarchicalLinkPlanPrepareProgress")
            && stored_link_leaf_chunk_prepare
                .contains("hierarchical_link_plan_prepare_progress_path_for_target")
            && stored_link_leaf_chunk_prepare.contains("max_new_partitions")
            && stored_link_leaf_chunk_prepare.contains("progress.next_partition_index")
            && stored_link_leaf_chunk_prepare.contains("progress.next_group_index"),
        "filesystem source-pack leaf link planning must expose bounded resumable chunks over persisted schedule partitions"
    );
    assert!(
        !stored_link_leaf_chunk_prepare
            .contains("store_source_pack_hierarchical_link_plan_compact_index("),
        "leaf link planning chunks must defer compact link-plan index publication"
    );
    let stored_link_leaf_page_prepare = source_between(
        &compiler,
        "fn store_source_pack_hierarchical_link_leaf_groups_for_schedule_page",
        "fn source_pack_store_hierarchical_link_plan_prepare_progress",
    );
    assert!(
        stored_link_leaf_page_prepare.contains("source_pack_for_each_stored_schedule_codegen_job(")
            && stored_link_leaf_page_prepare.contains("source_pack_stored_leaf_link_group(")
            && stored_link_leaf_page_prepare
                .contains("source_pack_stored_codegen_job_dependency_count(")
            && stored_link_leaf_page_prepare
                .contains("store.store_hierarchical_link_group_page(&group)?"),
        "filesystem source-pack leaf link planning chunks must consume stored codegen job pages and persist leaf group pages"
    );
    assert!(
        !stored_link_leaf_page_prepare.contains("for job in &page.codegen_jobs"),
        "leaf link planning chunks must not consume inline schedule-page codegen jobs"
    );
    let stored_link_reduce_chunk_prepare = source_between(
        &compiler,
        "fn store_source_pack_hierarchical_link_reduce_groups_from_stored_leaf_groups_chunk",
        "fn source_pack_advance_completed_hierarchical_link_reduce_levels",
    );
    assert!(
        stored_link_reduce_chunk_prepare
            .contains("SourcePackFilesystemHierarchicalLinkPlanPrepareStepResult")
            && stored_link_reduce_chunk_prepare
                .contains("source_pack_load_hierarchical_link_plan_prepare_progress(")
            && stored_link_reduce_chunk_prepare.contains("max_new_reduce_groups")
            && stored_link_reduce_chunk_prepare
                .contains("progress.current_level_first_group_index")
            && stored_link_reduce_chunk_prepare.contains("progress.current_level_group_count")
            && stored_link_reduce_chunk_prepare.contains("progress.next_input_group_index")
            && stored_link_reduce_chunk_prepare.contains("progress.next_group_index")
            && stored_link_reduce_chunk_prepare.contains("source_pack_stored_reduce_link_group(")
            && stored_link_reduce_chunk_prepare
                .contains("store.store_hierarchical_link_group_page(&group)?")
            && stored_link_reduce_chunk_prepare
                .contains("store_source_pack_hierarchical_link_plan_compact_index(store, &index)?"),
        "filesystem source-pack reduce link planning must expose bounded resumable chunks and publish the compact plan index only after the final reduce group exists"
    );
    assert!(
        !stored_link_reduce_chunk_prepare.contains("current_level_group_indices")
            && !stored_link_reduce_chunk_prepare.contains("next_level_group_indices"),
        "filesystem source-pack reduce link planning chunks must track levels as compact ranges, not per-level group vectors"
    );
    let stored_reduce_link_group = source_between(
        &compiler,
        "fn source_pack_stored_reduce_link_group",
        "fn source_pack_store_hierarchical_link_plan_prepare_progress",
    );
    assert!(
        stored_reduce_link_group.contains("load_hierarchical_link_group_page_for_target(")
            && stored_reduce_link_group
                .contains("source_pack_hierarchical_link_group_input_partition_count(")
            && stored_reduce_link_group.contains("input_partition_indices: Vec::new()")
            && stored_reduce_link_group.contains("input_link_group_indices"),
        "stored reduce link groups must consume bounded input group pages and retain compact partition counts"
    );
    assert!(
        !stored_reduce_link_group.contains("input_partition_indices.extend"),
        "stored reduce link groups must not accumulate transitive partition-index arrays"
    );
    let stored_leaf_link_group = source_between(
        &compiler,
        "fn source_pack_stored_leaf_link_group",
        "fn source_pack_stored_codegen_job_dependency_count",
    );
    assert!(
        stored_leaf_link_group.contains("input_frontend_job_count"),
        "stored leaf link groups must consume bounded frontend fan-in as persisted job-page metadata"
    );
    assert!(
        !stored_leaf_link_group.contains("frontend_job.dependency_job_indices"),
        "stored leaf link groups must not read hydrated frontend dependency vectors"
    );
    assert!(
        !stored_leaf_link_group
            .contains("source_pack_for_each_stored_schedule_job_dependency_index("),
        "stored leaf link groups must not scan dependency pages just to count frontend fan-in"
    );
    assert!(
        stored_leaf_link_group.contains("input_frontend_job_count"),
        "stored leaf link groups must retain frontend fan-in as a count instead of inline job ids"
    );
    assert!(
        stored_leaf_link_group.contains("input_frontend_job_count > limits.max_jobs_per_batch"),
        "stored leaf link groups must classify excessive frontend/interface fan-in as oversized"
    );
    assert!(
        stored_leaf_link_group.contains("source_line_count"),
        "stored leaf link groups must retain bounded source-line totals in the group page"
    );
    assert!(
        !stored_leaf_link_group.contains("input_frontend_job_indices.push"),
        "stored leaf link groups must not accumulate frontend dependency jobs into the group page"
    );

    let stored_hierarchical_execution = source_between(
        &compiler,
        "fn source_pack_hierarchical_link_execution_page_from_stored_artifact_refs",
        "fn source_pack_hierarchical_link_execution_output_key_for_group",
    );
    assert!(
        stored_hierarchical_execution.contains(
            "store_source_pack_hierarchical_link_execution_interface_pages_from_stored_leaf_group("
        ),
        "stored hierarchical link execution must page leaf interface inputs"
    );
    assert!(
        stored_hierarchical_execution.contains(
            "store_source_pack_hierarchical_link_execution_object_pages_from_stored_leaf_group("
        ),
        "stored hierarchical link execution must page leaf object inputs"
    );
    assert!(
        stored_hierarchical_execution.contains(
            "store_source_pack_hierarchical_link_execution_partial_pages_from_stored_reduce_group("
        ),
        "stored hierarchical link execution must page reduce partial-link inputs"
    );
    assert!(
        !stored_hierarchical_execution.contains("&group.input_frontend_job_indices"),
        "stored hierarchical link execution must not hydrate all leaf frontend inputs from group pages"
    );
    assert!(
        !stored_hierarchical_execution.contains(
            "source_pack_hierarchical_link_execution_output_refs_from_stored_artifact_refs("
        ),
        "stored hierarchical link execution must not hydrate all leaf object refs into the execution page"
    );
    assert!(
        stored_hierarchical_execution.contains("source_line_count: group.source_line_count"),
        "stored hierarchical link execution must preserve source-line totals from link-group records"
    );
    let stored_hierarchical_execution_chunk = source_between(
        &compiler,
        "fn store_source_pack_hierarchical_link_execution_from_stored_schedule_pages_chunk",
        "fn source_pack_store_hierarchical_link_execution_prepare_progress",
    );
    assert!(
        stored_hierarchical_execution_chunk
            .contains("SourcePackHierarchicalLinkExecutionPrepareProgress")
            && stored_hierarchical_execution_chunk
                .contains("hierarchical_link_execution_prepare_progress_path_for_target")
            && stored_hierarchical_execution_chunk.contains("max_new_groups")
            && stored_hierarchical_execution_chunk.contains("progress.next_group_index")
            && stored_hierarchical_execution_chunk
                .contains("load_hierarchical_link_group_page_for_target(")
            && stored_hierarchical_execution_chunk.contains(
                "source_pack_hierarchical_link_execution_page_from_stored_artifact_refs("
            )
            && stored_hierarchical_execution_chunk
                .contains("store.store_hierarchical_link_execution_page(&page)?")
            && stored_hierarchical_execution_chunk.contains(
                "store_source_pack_hierarchical_link_execution_compact_index(store, &index)?"
            ),
        "stored hierarchical link execution must expose bounded resumable chunks and defer the compact execution index until every group page is stored"
    );
    assert!(
        !stored_hierarchical_execution_chunk
            .contains("for group_index in 0..link_plan_index.link_group_count"),
        "stored hierarchical link execution chunks must not loop the full link plan in one step"
    );
    let stored_hierarchical_interface_inputs = source_between(
        &compiler,
        "fn store_source_pack_hierarchical_link_execution_interface_pages_from_stored_leaf_group",
        "struct SourcePackHierarchicalLinkExecutionObjectPageWriter",
    );
    assert!(
        stored_hierarchical_interface_inputs
            .contains("source_pack_for_each_schedule_job_explicit_dependency_index(")
            && stored_hierarchical_interface_inputs.contains(".dependency_job_ranges")
            && stored_hierarchical_interface_inputs
                .contains("source_pack_job_index_range_dependency_count("),
        "stored hierarchical link execution must page explicit interface inputs and retain compact ranged interface inputs"
    );
    assert!(
        !stored_hierarchical_interface_inputs
            .contains("source_pack_for_each_stored_schedule_job_dependency_index("),
        "stored hierarchical link execution must not expand ranged frontend dependencies into execution input pages"
    );
    let direct_hierarchical_execution_store = source_between(
        &compiler,
        "pub fn store_hierarchical_link_execution_page(",
        "pub fn store_hierarchical_link_execution_interface_page(",
    );
    assert!(
        direct_hierarchical_execution_store
            .contains("validate_source_pack_hierarchical_link_execution_page_store_input("),
        "direct hierarchical link execution storage must validate store-input pages before spilling inline records"
    );
    assert!(
        direct_hierarchical_execution_store
            .contains("store_hierarchical_link_execution_interface_pages_from_refs("),
        "direct hierarchical link execution storage must page inline interface inputs"
    );
    assert!(
        direct_hierarchical_execution_store
            .contains("store_hierarchical_link_execution_object_pages_from_refs("),
        "direct hierarchical link execution storage must page inline object inputs"
    );
    assert!(
        direct_hierarchical_execution_store
            .contains("store_hierarchical_link_execution_partial_pages_from_inputs("),
        "direct hierarchical link execution storage must page inline partial-link inputs"
    );
    assert!(
        direct_hierarchical_execution_store.contains("stored_page.input_interfaces.clear();")
            && direct_hierarchical_execution_store.contains("stored_page.input_objects.clear();")
            && direct_hierarchical_execution_store
                .contains("stored_page.input_group_indices.clear();")
            && direct_hierarchical_execution_store
                .contains("stored_page.input_group_output_keys.clear();"),
        "direct hierarchical link execution storage must persist only compact counts plus input pages"
    );
    let hierarchical_execution_validation = source_between(
        &compiler,
        "fn validate_source_pack_hierarchical_link_execution_page_with_mode",
        "fn validate_source_pack_hierarchical_link_execution_artifact_refs",
    );
    assert!(
        hierarchical_execution_validation
            .contains("SourcePackHierarchicalLinkExecutionPageValidationMode::Persisted")
            && hierarchical_execution_validation.contains("page.input_interfaces.len()")
            && hierarchical_execution_validation.contains("page.input_objects.len()")
            && hierarchical_execution_validation.contains("page.input_group_indices.len()")
            && hierarchical_execution_validation.contains("page.input_group_output_keys.len()"),
        "hierarchical link execution validation must cap retained persisted side arrays while allowing store inputs to spill"
    );

    let hierarchical_execution_runner = source_between(
        &compiler,
        "fn execute_source_pack_hierarchical_link_execution_page",
        "async fn execute_source_pack_hierarchical_link_execution_page_async",
    );
    assert!(
        hierarchical_execution_runner.contains("page.input_interface_page_count"),
        "hierarchical link execution must stream paged interface inputs"
    );
    assert!(
        hierarchical_execution_runner.contains("load_hierarchical_link_execution_interface_page("),
        "hierarchical link execution must load bounded interface input pages"
    );
    assert!(
        hierarchical_execution_runner.contains("page.input_interface_ranges")
            && hierarchical_execution_runner.contains("load_build_artifact_ref_page("),
        "hierarchical link execution must stream compact ranged interface inputs through bounded artifact-ref batches"
    );
    assert!(
        hierarchical_execution_runner.contains("load_hierarchical_link_execution_object_page("),
        "hierarchical link execution must load bounded object input pages"
    );
    assert!(
        hierarchical_execution_runner.contains("streamed_object_count")
            && hierarchical_execution_runner.contains("streamed {} object refs but expected {}"),
        "hierarchical link execution must verify object-page streams against the execution page object count"
    );
    assert!(
        hierarchical_execution_runner.contains("load_hierarchical_link_execution_partial_page("),
        "hierarchical link execution must load bounded partial-link input pages"
    );
    assert!(
        hierarchical_execution_runner.contains("streamed_partial_count")
            && hierarchical_execution_runner
                .contains("streamed {} partial-link refs but expected {}"),
        "hierarchical link execution must verify partial-link page streams against the execution page group count"
    );
    assert!(
        !hierarchical_execution_runner.contains("LibraryInterfaceArtifact = Vec<u8>"),
        "hierarchical link execution must not be specialized to byte-vector interface artifacts"
    );
    assert!(
        !hierarchical_execution_runner.contains("PartialLinkArtifact = Vec<u8>"),
        "hierarchical link execution must not be specialized to byte-vector partial link artifacts"
    );

    let stored_work_queue_chunk_prepare = source_between(
        &compiler,
        "fn store_source_pack_work_queue_pages_from_stored_schedule_pages_chunk",
        "fn source_pack_store_work_queue_page_for_stored_item_index",
    );
    assert!(
        stored_work_queue_chunk_prepare.contains("SourcePackWorkQueuePrepareProgress")
            && stored_work_queue_chunk_prepare
                .contains("work_queue_prepare_progress_path_for_target")
            && stored_work_queue_chunk_prepare.contains("max_new_items")
            && stored_work_queue_chunk_prepare.contains("progress.next_item_index")
            && stored_work_queue_chunk_prepare
                .contains("source_pack_store_work_queue_page_for_stored_item_index")
            && stored_work_queue_chunk_prepare
                .contains("store_source_pack_work_queue_compact_index"),
        "filesystem source-pack work-queue chunk prepare must resume from bounded progress and finalize a compact index"
    );
    assert!(
        !stored_work_queue_chunk_prepare
            .contains("for partition_index in 0..schedule_index.partition_count")
            && !stored_work_queue_chunk_prepare
                .contains("for group_index in 0..link_plan_index.link_group_count"),
        "filesystem source-pack work-queue chunk prepare must not re-walk all schedule partitions or link groups"
    );
    let stored_work_queue_item_prepare = source_between(
        &compiler,
        "fn source_pack_store_work_queue_page_for_stored_item_index",
        "fn source_pack_store_work_queue_prepare_progress",
    );
    assert!(
        stored_work_queue_item_prepare.contains("source_pack_stored_schedule_job_metadata(")
            && stored_work_queue_item_prepare
                .contains("load_library_schedule_job_locator_page_for_target(")
            && stored_work_queue_item_prepare
                .contains("load_hierarchical_link_group_page_for_target(")
            && stored_work_queue_item_prepare
                .contains("store_source_pack_work_queue_page_with_dependency_writer(")
            && stored_work_queue_item_prepare
                .contains("source_pack_write_work_queue_dependencies_from_stored_schedule_job(")
            && stored_work_queue_item_prepare.contains("writer.push(codegen_job_index)?")
            && stored_work_queue_item_prepare.contains("writer.push(input_item_index)?"),
        "filesystem source-pack work-queue item prepare must load one stored schedule or link page and stream dependencies"
    );
    assert!(
        !stored_work_queue_item_prepare
            .contains("for partition_index in 0..schedule_index.partition_count")
            && !stored_work_queue_item_prepare
                .contains("for group_index in 0..link_plan_index.link_group_count"),
        "filesystem source-pack work-queue item prepare must stay addressable by item index"
    );
    let work_queue_page_record = source_between(
        &source_pack_records,
        "pub struct SourcePackWorkQueuePage",
        "pub struct SourcePackWorkQueueDependenciesPage",
    );
    assert!(
        work_queue_page_record.contains("pub dependency_item_ranges: Vec<SourcePackJobIndexRange>"),
        "filesystem source-pack work-queue pages must retain compact dependency ranges alongside bounded dependency pages"
    );
    assert!(
        work_queue_page_record.contains("pub dependent_item_ranges: Vec<SourcePackJobIndexRange>"),
        "filesystem source-pack work-queue pages must retain compact reverse-dependent ranges alongside bounded dependent pages"
    );
    assert!(
        compiler.contains("store_work_queue_dependencies_page("),
        "filesystem source-pack work-queue prepare must store forward dependency records in pages"
    );
    let stored_work_queue_page = source_between(
        &compiler,
        "pub fn store_work_queue_page(",
        "pub fn load_work_queue_page_for_target",
    );
    assert!(
        stored_work_queue_page.contains("store_work_queue_dependency_pages_from_indices(")
            && stored_work_queue_page.contains("store_work_queue_dependent_pages_from_indices(")
            && stored_work_queue_page.contains("store_work_queue_dependencies_page(")
            && stored_work_queue_page.contains("store_work_queue_dependents_page("),
        "filesystem source-pack work-queue page store must spill inline edge lists into bounded edge pages"
    );
    assert!(
        stored_work_queue_page.contains("stored_page.dependency_item_indices.clear();")
            && stored_work_queue_page.contains("stored_page.dependent_item_indices.clear();")
            && stored_work_queue_page.contains("stored_page.dependency_item_count")
            && stored_work_queue_page.contains("stored_page.dependent_item_count"),
        "filesystem source-pack work-queue page store must persist compact edge counts, not inline edge lists"
    );
    assert!(
        stored_work_queue_page.contains("stored_page.input_frontend_job_indices.clear();")
            && stored_work_queue_page.contains("stored_page.partition_indices.clear();")
            && stored_work_queue_page.contains("SourcePackWorkQueueItemKind::LinkReduce"),
        "filesystem source-pack work-queue page store must compact count-addressable link metadata instead of persisting transitive vectors"
    );
    assert!(
        stored_work_queue_page.contains("validate_source_pack_work_queue_page_store_input("),
        "filesystem source-pack work-queue page store must validate transient inputs separately from persisted compact pages"
    );
    assert!(
        stored_work_queue_page.contains("let mut seen = BTreeSet::new();")
            && stored_work_queue_page.contains("duplicate dependency item")
            && stored_work_queue_page.contains("duplicate dependent item"),
        "filesystem source-pack work-queue page store must preserve edge uniqueness while streaming inline edges into pages"
    );
    let work_queue_page_validation = source_between(
        &compiler,
        "fn validate_source_pack_work_queue_page",
        "fn validate_source_pack_work_queue_dependencies_page",
    );
    assert!(
        work_queue_page_validation.contains("SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE")
            && work_queue_page_validation
                .contains("SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE")
            && work_queue_page_validation
                .contains("SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE")
            && work_queue_page_validation.contains("page.dependency_item_indices.len()")
            && work_queue_page_validation.contains("page.dependency_item_ranges.len()")
            && work_queue_page_validation.contains("page.dependent_item_indices.len()")
            && work_queue_page_validation.contains("page.dependent_item_ranges.len()")
            && work_queue_page_validation.contains("page.partition_indices.len()")
            && work_queue_page_validation.contains("page.input_frontend_job_indices.len()")
            && work_queue_page_validation.contains("page.input_codegen_job_indices.len()")
            && work_queue_page_validation.contains("page.input_link_group_indices.len()"),
        "filesystem source-pack work-queue pages must cap retained input vectors"
    );
    assert!(
        source_before(
            work_queue_page_validation,
            "\"dependency\",\n        page.dependency_item_indices.len()",
            "source_pack_manifest_unique_usize_set(\n            &page.dependency_item_indices",
        ) && source_before(
            work_queue_page_validation,
            "\"dependent\",\n        page.dependent_item_indices.len()",
            "source_pack_manifest_unique_usize_set(\n            &page.dependent_item_indices",
        ) && source_before(
            work_queue_page_validation,
            "\"partition\",\n        page.partition_indices.len()",
            "source_pack_manifest_unique_usize_set(\n            &page.partition_indices",
        ) && source_before(
            work_queue_page_validation,
            "\"frontend input\",\n        page.input_frontend_job_indices.len()",
            "source_pack_manifest_unique_usize_set(\n            &page.input_frontend_job_indices",
        ) && source_before(
            work_queue_page_validation,
            "\"codegen input\",\n        page.input_codegen_job_indices.len()",
            "source_pack_manifest_unique_usize_set(\n        &page.input_codegen_job_indices",
        ) && source_before(
            work_queue_page_validation,
            "\"link-group input\",\n        page.input_link_group_indices.len()",
            "source_pack_manifest_unique_usize_set(\n        &page.input_link_group_indices",
        ),
        "filesystem source-pack work-queue pages must reject oversized retained inputs before record scans"
    );
    assert!(
        work_queue_page_validation.contains("source_pack_validate_job_dependency_ranges("),
        "filesystem source-pack work-queue validation must validate retained dependency range records against explicit dependency records"
    );
    assert!(
        work_queue_page_validation.contains("source_pack_validate_job_dependent_ranges("),
        "filesystem source-pack work-queue validation must validate retained reverse-dependent range records against explicit dependent records"
    );
    assert!(
        compiler.contains("load_work_queue_dependencies_page_for_target("),
        "filesystem source-pack work-queue execution must load forward dependency records from pages"
    );
    assert!(
        !stored_work_queue_item_prepare.contains("for job in &schedule_page.codegen_jobs"),
        "filesystem source-pack work-queue prepare must not consume inline schedule-page codegen jobs"
    );
    assert!(
        stored_work_queue_item_prepare
            .contains("store_source_pack_work_queue_page_with_dependency_writer("),
        "filesystem source-pack work-queue prepare must stream dependencies through a bounded page writer"
    );
    assert!(
        stored_work_queue_item_prepare
            .contains("source_pack_write_work_queue_dependencies_from_stored_schedule_job("),
        "filesystem source-pack work-queue prepare must write stored schedule dependencies through the compact dependency-range path"
    );
    assert!(
        !stored_work_queue_item_prepare
            .contains("source_pack_for_each_stored_schedule_job_dependency_index("),
        "filesystem source-pack work-queue prepare must not expand compact schedule dependency ranges into explicit dependency records"
    );
    let work_queue_schedule_dependency_writer = source_between(
        &compiler,
        "fn source_pack_write_work_queue_dependencies_from_stored_schedule_job",
        "fn source_pack_singleton_artifact_batch_index_for_job_from_stored_locator",
    );
    assert!(
        work_queue_schedule_dependency_writer
            .contains("source_pack_for_each_schedule_job_explicit_dependency_index(")
            && work_queue_schedule_dependency_writer.contains("writer.push(dependency_job_index)")
            && work_queue_schedule_dependency_writer
                .contains("writer.push_range(range.first_job_index, range.job_count)?"),
        "filesystem source-pack work-queue dependency writing must consume explicit dependency pages and compact schedule dependency ranges separately"
    );
    let stored_work_queue_dependency_writer = source_between(
        &compiler,
        "impl<'a> SourcePackWorkQueueDependencyPageWriter<'a>",
        "fn store_source_pack_work_queue_page_with_dependency_writer",
    );
    assert!(
        stored_work_queue_dependency_writer
            .contains("seen_dependency_item_indices: BTreeSet::new()")
            && stored_work_queue_dependency_writer.contains(".seen_dependency_item_indices")
            && stored_work_queue_dependency_writer.contains("duplicate dependency item"),
        "filesystem source-pack work-queue dependency writer must preserve uniqueness across flushed dependency pages"
    );
    assert!(
        stored_work_queue_dependency_writer.contains("fn push_range(")
            && stored_work_queue_dependency_writer
                .contains("source_pack_try_push_dependency_item_range(")
            && stored_work_queue_dependency_writer
                .contains("source_pack_append_work_queue_dependent_range_to_dependency_range(")
            && stored_work_queue_dependency_writer
                .contains("source_pack_work_queue_append_dependent_page("),
        "filesystem source-pack work-queue dependency writer must retain compact dependency ranges while preserving reverse-dependent records"
    );
    let work_queue_dependency_range_push = source_between(
        &compiler,
        "fn source_pack_try_push_dependency_item_range",
        "fn store_source_pack_work_queue_page_with_dependency_writer",
    );
    assert!(
        work_queue_dependency_range_push
            .contains("SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE")
            && work_queue_dependency_range_push
                .contains("*dependency_item_ranges = compact_ranges"),
        "filesystem source-pack work-queue dependency ranges must stay capped before being retained on item pages"
    );
    let work_queue_dependent_range_push = source_between(
        &compiler,
        "fn source_pack_try_push_dependent_item_range",
        "fn store_source_pack_work_queue_page_with_dependency_writer",
    );
    assert!(
        work_queue_dependent_range_push
            .contains("SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE")
            && work_queue_dependent_range_push.contains("*dependent_item_ranges = compact_ranges"),
        "filesystem source-pack work-queue reverse-dependent ranges must stay capped before being retained on item pages"
    );
    assert!(
        compiler.contains("fn store_initial_work_queue_progress_from_stored_work_queue_pages")
            && compiler.contains("store.load_work_queue_page_for_target(target, item_index)?")
            && compiler.contains("progress_writer.record_item(&item)?"),
        "filesystem source-pack work-queue prepare must seed progress counters from finalized persisted item pages one at a time"
    );
    let stored_work_queue_progress_chunk_prepare = source_between(
        &compiler,
        "fn store_initial_work_queue_progress_from_stored_work_queue_pages_chunk",
        "fn source_pack_store_initial_work_queue_progress_prepare_progress",
    );
    assert!(
        stored_work_queue_progress_chunk_prepare
            .contains("SourcePackInitialWorkQueueProgressPrepareProgress")
            && stored_work_queue_progress_chunk_prepare
                .contains("work_queue_progress_prepare_progress_path_for_target")
            && stored_work_queue_progress_chunk_prepare.contains("max_new_pages")
            && stored_work_queue_progress_chunk_prepare.contains("progress.next_page_index")
            && stored_work_queue_progress_chunk_prepare
                .contains("store.store_work_queue_progress_page(&progress_page)?")
            && stored_work_queue_progress_chunk_prepare
                .contains("store.store_work_queue_progress_index(&index)?"),
        "filesystem source-pack work-queue progress chunk prepare must resume by progress page and write the compact index only at completion"
    );
    assert!(
        !stored_work_queue_progress_chunk_prepare.contains("for item_index in 0..work_item_count")
            && !stored_work_queue_progress_chunk_prepare
                .contains("for item_index in 0..queue.work_item_count"),
        "filesystem source-pack work-queue progress chunk prepare must not re-walk the full work queue"
    );
    let stored_work_queue_progress_page_prepare = source_between(
        &compiler,
        "fn source_pack_initial_work_queue_progress_page_from_stored_work_queue_pages",
        "fn source_pack_store_initial_work_queue_progress_directory_pages_after_progress_page",
    );
    assert!(
        stored_work_queue_progress_page_prepare
            .contains("store.load_work_queue_page_for_target(target, item_index)?")
            && stored_work_queue_progress_page_prepare
                .contains("source_pack_work_queue_page_dependency_count(&item)")
            && stored_work_queue_progress_page_prepare
                .contains("source_pack_work_queue_page_dependent_count(&item)")
            && stored_work_queue_progress_page_prepare.contains("SourcePackWorkQueueProgressPage"),
        "filesystem source-pack work-queue progress page prepare must derive each bounded progress page from persisted work item pages"
    );
    assert!(
        stored_work_queue_progress_page_prepare
            .contains("for item_index in first_item_index..item_end")
            && !stored_work_queue_progress_page_prepare
                .contains("for item_index in 0..work_item_count"),
        "filesystem source-pack work-queue progress page prepare must only scan the requested progress page range"
    );
    let stored_work_queue_progress_directory_prepare = source_between(
        &compiler,
        "fn source_pack_store_initial_work_queue_progress_directory_pages_after_progress_page",
        "fn store_initial_work_queue_progress_from_stored_work_queue_pages_chunk",
    );
    assert!(
        stored_work_queue_progress_directory_prepare
            .contains("source_pack_work_queue_progress_directory_page_from_summaries(")
            && stored_work_queue_progress_directory_prepare.contains(
                "source_pack_work_queue_progress_directory_index_page_from_directory_pages("
            )
            && stored_work_queue_progress_directory_prepare
                .contains("store_work_queue_progress_directory_page_for_target(")
            && stored_work_queue_progress_directory_prepare
                .contains("store_work_queue_progress_directory_index_page_for_target("),
        "filesystem source-pack work-queue progress chunk prepare must store bounded directory pages as their input ranges complete"
    );
    assert!(
        !stored_work_queue_item_prepare
            .contains("let mut dependencies = group.input_frontend_job_indices.clone()"),
        "filesystem source-pack link work-queue pages must not materialize all leaf frontend dependencies"
    );
    assert!(
        !stored_work_queue_item_prepare
            .contains("dependency_item_indices: frontend_job.dependency_job_indices.clone()"),
        "filesystem source-pack work-queue frontend pages must not clone hydrated job dependencies"
    );
    assert!(
        !stored_work_queue_item_prepare
            .contains("dependency_item_indices: job.dependency_job_indices.clone()"),
        "filesystem source-pack work-queue codegen pages must not clone hydrated job dependencies"
    );
    assert!(
        !stored_work_queue_item_prepare
            .contains("partition_indices: group.input_partition_indices.clone()"),
        "filesystem source-pack work-queue reduce pages must not copy transitive partition-index sets"
    );
    let stored_schedule_codegen_iter = source_between(
        &compiler,
        "fn source_pack_for_each_stored_schedule_codegen_job",
        "fn source_pack_execution_shard_job_batch",
    );
    assert!(
        stored_schedule_codegen_iter.contains("load_library_schedule_job_page_for_target(")
            && stored_schedule_codegen_iter
                .contains("load_library_schedule_job_locator_page_for_target("),
        "stored schedule codegen iteration must load job metadata records without hydrating dependency vectors"
    );
    assert!(
        stored_schedule_codegen_iter.contains("source_pack_schedule_job_first_dependency_index("),
        "stored schedule codegen iteration must validate the owning frontend from the first persisted dependency record"
    );
    assert!(
        !stored_schedule_codegen_iter
            .contains("source_pack_for_each_stored_schedule_job_dependency_index("),
        "stored schedule codegen iteration must not scan full dependency pages during metadata iteration"
    );
    assert!(
        !stored_schedule_codegen_iter.contains("source_pack_stored_schedule_job("),
        "stored schedule codegen iteration must not materialize dependency vectors"
    );
    assert!(
        !stored_schedule_codegen_iter.contains("&job.dependency_job_indices"),
        "stored schedule codegen iteration must not inspect hydrated dependency vectors"
    );

    let path_artifact_store = source_between(
        &compiler,
        "impl SourcePackPathArtifactStore for SourcePackFilesystemArtifactPathStore",
        "impl SourcePackPathHierarchicalLinkArtifactStore for SourcePackFilesystemArtifactPathStore",
    );
    assert!(
        path_artifact_store.contains("source_pack_filesystem_artifact_path_handle("),
        "filesystem path-artifact store must load dependency artifacts as path handles"
    );
    assert!(
        path_artifact_store.contains("copy_source_pack_filesystem_artifact_file_atomically("),
        "filesystem path-artifact store must persist produced artifacts by path-copying"
    );
    assert!(
        !path_artifact_store.contains("read_source_pack_filesystem_artifact("),
        "filesystem path-artifact store must not hydrate dependency artifacts as byte vectors"
    );
    assert!(
        !path_artifact_store.contains("write_source_pack_filesystem_artifact("),
        "filesystem path-artifact store must not require produced artifacts as byte vectors"
    );
    let path_artifact_claimed_batch = source_between(
        &compiler,
        "pub fn execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_with_path_artifacts_for_target_at",
        "pub async fn execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_async_for_target_at",
    );
    assert!(
        path_artifact_claimed_batch.contains("SourcePackFilesystemArtifactPathStore::new("),
        "path-artifact claimed-batch execution must use the path-artifact filesystem store"
    );
    assert!(
        path_artifact_claimed_batch.contains(
            "execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_with_store_for_target_at("
        ),
        "path-artifact claimed-batch execution must reuse the generic paged batch executor"
    );
    assert!(
        !path_artifact_claimed_batch.contains("SourcePackFilesystemArtifactStore::new("),
        "path-artifact claimed-batch execution must not instantiate the byte-vector filesystem store"
    );
    let async_paged_executor_trait = source_between(
        &compiler,
        "pub trait SourcePackPathAsyncPagedArtifactBuildExecutor",
        "pub trait SourcePackPathHierarchicalLinkExecutor",
    );
    assert!(
        async_paged_executor_trait.contains("SourcePackBoxFuture"),
        "async paged artifact executor must expose awaitable GPU work units"
    );
    assert!(
        async_paged_executor_trait.contains("add_library_interface_dependency_batch"),
        "async paged artifact executor must receive frontend dependency interfaces in batches"
    );
    assert!(
        async_paged_executor_trait.contains("add_codegen_object_dependency_batch"),
        "async paged artifact executor must receive codegen dependency interfaces in batches"
    );
    let async_paged_job = source_between(
        &compiler,
        "async fn execute_source_pack_build_artifact_execution_shard_job_paged_async",
        "async fn source_pack_add_library_interface_dependency_batches_async",
    );
    assert!(
        async_paged_job.contains("begin_library_interface(job, &source_files).await"),
        "async paged job execution must await bounded library frontend work"
    );
    assert!(
        async_paged_job.contains("source_pack_add_library_interface_dependency_batches_async("),
        "async paged job execution must stream frontend dependency interface pages"
    );
    assert!(
        async_paged_job.contains("begin_codegen_object(job, &source_files, &library_interface)"),
        "async paged job execution must await bounded codegen work from the owning interface"
    );
    assert!(
        async_paged_job.contains("source_pack_add_codegen_object_dependency_batches_async("),
        "async paged job execution must stream codegen dependency interface pages"
    );
    assert!(
        !async_paged_job.contains("source_pack_execution_shard_job_input_interface_refs("),
        "async paged job execution must not collect all dependency interface refs before execution"
    );
    let async_path_artifact_claimed_batch = source_between(
        &compiler,
        "pub async fn execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_async_with_path_artifacts_for_target_at",
        "async fn execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_async_with_store_for_target_at",
    );
    assert!(
        async_path_artifact_claimed_batch.contains("SourcePackFilesystemArtifactPathStore::new("),
        "async path-artifact claimed-batch execution must use the path-artifact filesystem store"
    );
    assert!(
        async_path_artifact_claimed_batch.contains(
            "execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_async_with_store_for_target_at("
        ),
        "async path-artifact claimed-batch execution must reuse the generic async paged batch executor"
    );
    assert!(
        !async_path_artifact_claimed_batch.contains("SourcePackFilesystemArtifactStore::new("),
        "async path-artifact claimed-batch execution must not instantiate the byte-vector filesystem store"
    );
    let async_claimed_batch_with_store = source_between(
        &compiler,
        "async fn execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_async_with_store_for_target_at",
        "fn execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_with_store_for_target_at",
    );
    assert!(
        async_claimed_batch_with_store
            .contains("execute_source_pack_build_artifact_execution_shard_batch_paged_async("),
        "async claimed-batch execution must execute through the async paged execution-shard batch path"
    );
    assert!(
        !async_claimed_batch_with_store
            .contains("execute_source_pack_build_artifact_execution_shard_batch_paged("),
        "async claimed-batch execution must not fall back to the synchronous paged executor"
    );
    let async_path_artifact_worker_step = source_between(
        &compiler,
        "pub async fn execute_source_pack_filesystem_artifact_manifest_worker_step_async_with_path_artifacts_for_target_at",
        "pub fn execute_source_pack_filesystem_artifact_manifest_worker_step_progress",
    );
    assert!(
        async_path_artifact_worker_step
            .contains("source_pack_filesystem_artifact_manifest_claim_ready_batch_for_target_at("),
        "async path-artifact worker steps must claim a persisted ready batch before execution"
    );
    assert!(
        async_path_artifact_worker_step.contains(
            "execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_async_with_path_artifacts_for_target_at("
        ),
        "async path-artifact worker steps must execute through the async paged path-artifact claimed-batch API"
    );
    assert!(
        !async_path_artifact_worker_step.contains(
            "execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_with_path_artifacts_for_target_at("
        ),
        "async path-artifact worker steps must not fall back to the synchronous claimed-batch API"
    );
    assert!(
        !async_path_artifact_worker_step
            .contains("execute_source_pack_filesystem_artifact_manifest_build_for_target("),
        "async path-artifact worker steps must not run the whole persisted manifest"
    );
    let async_path_artifact_worker_run = source_between(
        &compiler,
        "pub async fn execute_source_pack_filesystem_artifact_manifest_worker_run_async_with_path_artifacts_for_target_at",
        "pub fn execute_source_pack_filesystem_artifact_manifest_ready_batches",
    );
    assert!(
        async_path_artifact_worker_run.contains(
            "let step_limit = source_pack_limit_artifact_worker_run_batches(max_batches)"
        ),
        "async path-artifact worker runs must cap the caller max_batches value before looping"
    );
    assert!(
        async_path_artifact_worker_run.contains(
            "execute_source_pack_filesystem_artifact_manifest_worker_step_async_with_path_artifacts_for_target_at("
        ),
        "async path-artifact worker runs must advance by bounded async worker steps"
    );
    assert!(
        !async_path_artifact_worker_run.contains("executed_batch_indices"),
        "async path-artifact worker runs must report executed batches by count instead of retaining every batch index"
    );
    assert!(
        !async_path_artifact_worker_run.contains("executed_batch_indices.push"),
        "async path-artifact worker runs must not accumulate executed batch indices"
    );
    assert!(
        !async_path_artifact_worker_run
            .contains("execute_source_pack_filesystem_artifact_manifest_build_for_target("),
        "async path-artifact worker runs must not execute the whole persisted manifest"
    );
    let async_path_artifact_worker_run_wrapper = source_between(
        &compiler,
        "pub async fn execute_source_pack_filesystem_artifact_manifest_worker_run_async_with_path_artifacts_for_target<\n    E,",
        "pub fn execute_source_pack_filesystem_artifact_manifest_ready_batches",
    );
    assert!(
        async_path_artifact_worker_run_wrapper.contains(
            "execute_source_pack_filesystem_artifact_manifest_worker_run_async_with_path_artifacts_for_target_at("
        ),
        "current-time async path-artifact worker-run wrapper must delegate to the deterministic-at API"
    );
    assert!(
        async_path_artifact_worker_run_wrapper
            .contains("Some(source_pack_build_now_unix_nanos()?)"),
        "current-time async path-artifact worker-run wrapper must use the build clock for claims"
    );
    let async_link_job = source_between(
        &compiler,
        "async fn execute_source_pack_build_artifact_execution_shard_link_job_async",
        "fn source_pack_execution_shard_job_input_interface_refs",
    );
    assert!(
        async_link_job.contains("execute_source_pack_link_input_interface_shards_async("),
        "async link execution must stream interface link-input shards through a bounded helper"
    );
    assert!(
        async_link_job.contains("execute_source_pack_link_input_object_shards_async("),
        "async link execution must stream object link-input shards through a bounded helper"
    );
    assert!(
        !async_link_job.contains("let mut interface_shard_indices = Vec::new()"),
        "async link execution must not collect every interface link shard before processing"
    );
    assert!(
        !async_link_job.contains("let mut object_shard_indices = Vec::new()"),
        "async link execution must not collect every object link shard before processing"
    );
    let async_link_stream_helpers = source_between(
        &compiler,
        "async fn execute_source_pack_link_input_interface_shards_async",
        "fn source_pack_execution_shard_job_input_interface_refs",
    );
    assert!(
        async_link_stream_helpers.contains("link_interface_shard_range.as_ref()"),
        "async interface link input streaming must consume persisted shard ranges directly"
    );
    assert!(
        async_link_stream_helpers.contains("link_object_shard_range.as_ref()"),
        "async object link input streaming must consume persisted shard ranges directly"
    );
    assert!(
        async_link_stream_helpers.contains("execute_source_pack_link_input_interface_shard_async("),
        "async interface link input streaming must process one shard at a time"
    );
    assert!(
        async_link_stream_helpers.contains("execute_source_pack_link_input_object_shard_async("),
        "async object link input streaming must process one shard at a time"
    );
    let gpu_source_pack_artifact_contract = artifact_descriptor.as_str();
    assert!(
        gpu_source_pack_artifact_contract.contains("semantic_interface_records"),
        "GPU source-pack library-interface artifacts must declare semantic interface record arrays"
    );
    assert!(
        gpu_source_pack_artifact_contract.contains("pub input_record_arrays:")
            && gpu_source_pack_artifact_contract.contains("pub output_record_arrays:")
            && gpu_source_pack_artifact_contract.contains("fn combined_record_arrays("),
        "GPU source-pack descriptors must separate consumed record arrays from produced record arrays while retaining a combined compatibility view"
    );
    assert!(
        gpu_source_pack_artifact_contract.contains("pub fn bounded(")
            && gpu_source_pack_artifact_contract
                .contains("GpuSourcePackRecordArrayDescriptor::bounded(")
            && gpu_source_pack_artifact_contract.contains("\"source_file_records\"")
            && gpu_source_pack_artifact_contract.contains("job.source_file_count")
            && gpu_source_pack_artifact_contract.contains("job.source_bytes")
            && gpu_source_pack_artifact_contract.contains("source_lines: job.source_lines")
            && gpu_source_pack_artifact_contract.contains("source_lines: page.source_line_count"),
        "GPU source-pack descriptors must bound source-file record arrays and line totals from job or link-page records"
    );
    assert!(
        gpu_source_pack_artifact_contract.contains("dependency_interface_batch_count"),
        "GPU source-pack artifacts must record dependency batch counts without embedding every dependency key"
    );
    assert!(
        gpu_source_pack_artifact_contract.contains("GpuSourcePackDependencyInterfaceSummary"),
        "GPU source-pack artifact descriptors must use a bounded dependency-interface summary"
    );
    assert!(
        !gpu_source_pack_artifact_contract.contains("inline_keys")
            && !gpu_source_pack_artifact_contract.contains("dependency_interface_keys")
            && !gpu_source_pack_artifact_contract.contains("from_inline_keys("),
        "GPU source-pack artifact descriptors must not retain dependency interface keys inline"
    );
    assert!(
        gpu_source_pack_artifact_contract.contains("virtual_instruction_records"),
        "GPU source-pack codegen object artifacts must declare virtual instruction record arrays"
    );
    let codegen_descriptor_contract = source_between(
        &artifact_descriptor,
        "pub fn codegen_object_contract_for_job",
        "pub fn linked_output_contract_for_job",
    );
    assert!(
        codegen_descriptor_contract.contains("let input_record_arrays = vec![")
            && codegen_descriptor_contract.contains("\"attributed_hir_records\"")
            && codegen_descriptor_contract.contains("\"resolver_records\"")
            && codegen_descriptor_contract.contains("\"type_instance_records\"")
            && codegen_descriptor_contract.contains("\"literal_records\"")
            && codegen_descriptor_contract.contains("\"dependency_semantic_interface_records\"")
            && codegen_descriptor_contract.contains("let output_record_arrays = vec![")
            && codegen_descriptor_contract.contains("\"node_instruction_count_records\"")
            && codegen_descriptor_contract.contains("\"instruction_location_records\"")
            && codegen_descriptor_contract.contains("\"virtual_instruction_records\"")
            && codegen_descriptor_contract.contains("\"virtual_register_records\""),
        "GPU source-pack codegen descriptors must declare HIR/semantic input arrays separately from virtual-instruction output arrays"
    );
    assert!(
        !codegen_descriptor_contract.contains("\"source_file_records\"")
            && !codegen_descriptor_contract.contains("\"token_records\""),
        "GPU source-pack codegen descriptors must not consume source-file or token record arrays"
    );
    assert!(
        gpu_source_pack_artifact_contract.contains("PartialLink")
            && gpu_source_pack_artifact_contract.contains("partial_link_relocation_records"),
        "GPU source-pack partial-link artifacts must declare intermediate link record arrays"
    );
    let linked_output_descriptor_contract = source_between(
        &artifact_descriptor,
        "pub fn linked_output_contract_for_job",
        "pub fn partial_link_contract_for_page",
    );
    assert!(
        linked_output_descriptor_contract.contains("let input_record_arrays = vec![")
            && linked_output_descriptor_contract.contains("\"allocated_instruction_records\"")
            && linked_output_descriptor_contract.contains("\"function_offset_records\"")
            && linked_output_descriptor_contract.contains("\"link_relocation_records\"")
            && linked_output_descriptor_contract.contains("let output_record_arrays")
            && linked_output_descriptor_contract.contains("\"emitted_byte_records\""),
        "GPU source-pack linked-output descriptors must declare allocated-instruction inputs separately from emitted-byte outputs"
    );
    assert!(
        gpu_source_pack_artifact_contract.contains("allocated_instruction_records"),
        "GPU source-pack linked-output artifacts must declare allocated instruction record arrays"
    );
    assert!(
        gpu_source_pack_artifact_contract.contains("dependency_codegen_object_count")
            && gpu_source_pack_artifact_contract.contains("dependency_partial_link_count"),
        "GPU source-pack link descriptors must count streamed object and partial-link inputs"
    );
    let gpu_source_pack_artifact_executor = source_between(
        &compiler,
        "pub struct GpuSourcePackArtifactExecutor",
        "struct OwnedX86ParserBuffers",
    );
    assert!(
        gpu_source_pack_artifact_executor.contains("type_check_source_pack(&sources).await"),
        "GPU source-pack artifact executor must run bounded frontend work through the GPU typechecker"
    );
    assert!(
        gpu_source_pack_artifact_executor.contains(
            ".dependency_interfaces\n                .add_batch(dependency_interfaces.len())"
        ) || gpu_source_pack_artifact_executor
            .contains(".dependency_interfaces.add_batch(dependency_interfaces.len())"),
        "GPU source-pack artifact executor must count streamed dependency batches instead of storing every dependency path"
    );
    assert!(
        gpu_source_pack_artifact_executor.contains("validate_existing_path_artifact_batch("),
        "GPU source-pack artifact executor must validate streamed dependency path artifacts while counting them"
    );
    assert!(
        !gpu_source_pack_artifact_executor
            .contains("dependency_interface_artifacts: Vec<SourcePackFilesystemArtifactPath>"),
        "GPU source-pack artifact handles must not accumulate every dependency artifact path"
    );
    assert!(
        !gpu_source_pack_artifact_executor
            .contains(".extend(dependency_interfaces.iter().cloned())"),
        "GPU source-pack artifact executor must not clone streamed dependency artifact batches into a whole-job vector"
    );
    assert!(
        gpu_source_pack_artifact_executor.contains("finish_codegen_object_artifact(")
            && gpu_source_pack_artifact_executor
                .contains("GpuSourcePackArtifactDescriptor::codegen_object_contract_for_job("),
        "GPU source-pack artifact executor must emit path-backed codegen descriptor artifacts from bounded job records"
    );
    assert!(
        gpu_source_pack_artifact_executor.contains("validate_job_source_file_records(")
            && gpu_source_pack_artifact_executor
                .contains("handle.library_interface_artifact.path.is_file()"),
        "GPU source-pack codegen descriptor emission must validate bounded source-file records and owning interface artifact paths"
    );
    assert!(
        gpu_source_pack_artifact_executor
            .contains("self.validate_job_source_file_records(\n            \"library-interface\"")
            && gpu_source_pack_artifact_executor
                .contains("self.validate_job_source_file_records(\"codegen\""),
        "GPU source-pack frontend/codegen descriptor emission must validate bounded source-file record counts"
    );
    assert!(
        gpu_source_pack_artifact_executor.contains("job.first_source_index")
            && gpu_source_pack_artifact_executor.contains("checked_add(job.source_file_count)")
            && gpu_source_pack_artifact_executor.contains("file.library_id != job.library_id")
            && gpu_source_pack_artifact_executor.contains("checked_add(file.byte_len)")
            && gpu_source_pack_artifact_executor.contains("source_bytes != job.source_bytes")
            && gpu_source_pack_artifact_executor.contains("source_lines != job.source_lines"),
        "GPU source-pack descriptor emission must validate source-file records against the bounded job range and totals"
    );
    assert!(
        !gpu_source_pack_artifact_executor.contains("compile_source_pack_to_wasm("),
        "GPU source-pack artifact executor must not produce codegen objects by invoking whole-pack WASM compilation"
    );
    assert!(
        !gpu_source_pack_artifact_executor.contains("compile_source_pack_to_x86_64("),
        "GPU source-pack artifact executor must not produce codegen objects by invoking whole-pack x86 compilation"
    );
    assert!(
        gpu_source_pack_artifact_executor.contains("finish_linked_output_artifact(")
            && gpu_source_pack_artifact_executor
                .contains("GpuSourcePackArtifactDescriptor::linked_output_contract_for_job("),
        "GPU source-pack artifact executor must emit path-backed linked-output descriptor artifacts from streamed link records"
    );
    assert!(
        gpu_source_pack_artifact_executor
            .contains("impl<'compiler, 'gpu> SourcePackPathAsyncHierarchicalLinkExecutor"),
        "GPU source-pack artifact executor must implement async hierarchical linking so async work-queue APIs are concrete GPU entrypoints"
    );
    assert!(
        gpu_source_pack_artifact_executor
            .contains("type PartialLinkArtifact = SourcePackFilesystemArtifactPath"),
        "GPU source-pack hierarchical linking must preserve partial links as path artifacts"
    );
    assert!(
        gpu_source_pack_artifact_executor.contains("partial_link_count")
            && gpu_source_pack_artifact_executor.contains("partial_links.len()"),
        "GPU source-pack hierarchical linking must count streamed partial-link batches without retaining paths"
    );
    assert!(
        gpu_source_pack_artifact_executor.contains("finish_hierarchical_partial_link_artifact(")
            && gpu_source_pack_artifact_executor
                .contains("GpuSourcePackArtifactDescriptor::partial_link_contract_for_page("),
        "GPU source-pack hierarchical linking must emit path-backed partial-link descriptor artifacts"
    );
    assert!(
        !gpu_source_pack_artifact_executor
            .contains("refusing to concatenate or rewrite link artifacts on the CPU"),
        "GPU source-pack hierarchical linking should not abort before producing descriptor artifacts"
    );
    let path_artifact_work_queue_item = source_between(
        &compiler,
        "pub fn execute_source_pack_filesystem_work_queue_claimed_item_with_path_artifacts_for_target_at",
        "pub fn execute_source_pack_filesystem_work_queue_claimed_link_item",
    );
    assert!(
        path_artifact_work_queue_item.contains(
            "execute_source_pack_filesystem_work_queue_claimed_artifact_item_with_path_artifacts_for_target_at("
        ),
        "path-artifact work-queue item execution must use path-backed artifact batch execution"
    );
    assert!(
        path_artifact_work_queue_item.contains(
            "execute_source_pack_filesystem_work_queue_claimed_link_item_with_path_artifacts_for_target_at("
        ),
        "path-artifact work-queue item execution must use path-backed hierarchical link execution"
    );
    assert!(
        !path_artifact_work_queue_item.contains(
            "execute_source_pack_filesystem_work_queue_claimed_artifact_item_paged_for_target_at("
        ),
        "path-artifact work-queue item execution must not fall back to byte-vector artifact batches"
    );
    let path_artifact_link_item = source_between(
        &compiler,
        "pub fn execute_source_pack_filesystem_work_queue_claimed_link_item_with_path_artifacts_for_target_at",
        "fn execute_source_pack_filesystem_work_queue_claimed_link_item_with_store_for_target_at",
    );
    assert!(
        path_artifact_link_item.contains("SourcePackFilesystemArtifactPathStore::new("),
        "path-artifact link item execution must instantiate the path-artifact store"
    );
    assert!(
        !path_artifact_link_item.contains("SourcePackFilesystemArtifactStore::new("),
        "path-artifact link item execution must not instantiate the byte-vector filesystem store"
    );
    let byte_artifact_work_queue_run = source_between(
        &compiler,
        "pub fn execute_source_pack_filesystem_work_queue_worker_run_for_target_at",
        "pub fn execute_source_pack_filesystem_work_queue_worker_run_with_path_artifacts",
    );
    assert!(
        byte_artifact_work_queue_run
            .contains("source_pack_filesystem_work_queue_progress_snapshot_for_target_at("),
        "byte-artifact work-queue worker runs must start from a persisted progress snapshot"
    );
    assert!(
        byte_artifact_work_queue_run
            .contains("let step_limit = source_pack_limit_work_queue_worker_run_items(max_items)")
            && byte_artifact_work_queue_run.contains("for _ in 0..step_limit"),
        "byte-artifact work-queue worker runs must cap max_items before looping"
    );
    assert!(
        byte_artifact_work_queue_run
            .contains("execute_source_pack_filesystem_work_queue_worker_step_for_target_at("),
        "byte-artifact work-queue worker runs must advance by bounded worker steps"
    );
    assert!(
        !byte_artifact_work_queue_run.contains("while ")
            && !byte_artifact_work_queue_run.contains("max_items.max(1)")
            && !byte_artifact_work_queue_run.contains("executed_item_indices")
            && !byte_artifact_work_queue_run
                .contains("execute_source_pack_filesystem_artifact_manifest_build_for_target(")
            && !byte_artifact_work_queue_run
                .contains("execute_source_pack_filesystem_artifact_manifest_worker_run"),
        "byte-artifact work-queue worker runs must stay count-reporting, queue-backed, and hard bounded"
    );
    let path_artifact_work_queue_run = source_between(
        &compiler,
        "pub fn execute_source_pack_filesystem_work_queue_worker_run_with_path_artifacts_for_target_at",
        "pub async fn execute_source_pack_filesystem_work_queue_claimed_artifact_item_async_with_path_artifacts_for_target_at",
    );
    assert!(
        path_artifact_work_queue_run
            .contains("source_pack_filesystem_work_queue_progress_snapshot_for_target_at("),
        "path-artifact work-queue worker runs must start from a persisted progress snapshot"
    );
    assert!(
        path_artifact_work_queue_run
            .contains("let step_limit = source_pack_limit_work_queue_worker_run_items(max_items)")
            && path_artifact_work_queue_run.contains("for _ in 0..step_limit"),
        "path-artifact work-queue worker runs must cap max_items before looping"
    );
    assert!(
        path_artifact_work_queue_run.contains(
            "execute_source_pack_filesystem_work_queue_worker_step_with_path_artifacts_for_target_at("
        ),
        "path-artifact work-queue worker run must execute path-backed worker steps"
    );
    assert!(
        !path_artifact_work_queue_run
            .contains("execute_source_pack_filesystem_work_queue_worker_step_for_target_at("),
        "path-artifact work-queue worker run must not fall back to byte-vector worker steps"
    );
    assert!(
        !path_artifact_work_queue_run.contains("while ")
            && !path_artifact_work_queue_run.contains("max_items.max(1)")
            && !path_artifact_work_queue_run.contains("executed_item_indices")
            && !path_artifact_work_queue_run
                .contains("execute_source_pack_filesystem_artifact_manifest_build_for_target(")
            && !path_artifact_work_queue_run
                .contains("execute_source_pack_filesystem_artifact_manifest_worker_run"),
        "path-artifact work-queue worker runs must stay count-reporting, queue-backed, and hard bounded"
    );
    let async_hierarchical_link_executor_trait = source_between(
        &compiler,
        "pub trait SourcePackPathAsyncHierarchicalLinkExecutor",
        "pub trait SourcePackPathAsyncPagedHierarchicalLinkExecutor",
    );
    assert!(
        async_hierarchical_link_executor_trait.contains("begin_hierarchical_link_group"),
        "async hierarchical link executor must expose a bounded group-start work unit"
    );
    assert!(
        async_hierarchical_link_executor_trait.contains("link_hierarchical_library_interfaces"),
        "async hierarchical link executor must stream library-interface input pages"
    );
    assert!(
        async_hierarchical_link_executor_trait.contains("link_hierarchical_codegen_objects"),
        "async hierarchical link executor must stream codegen-object input pages"
    );
    assert!(
        async_hierarchical_link_executor_trait.contains("link_hierarchical_partial_links"),
        "async hierarchical link executor must stream partial-link inputs for reduce groups"
    );
    let async_hierarchical_link_page = source_between(
        &compiler,
        "async fn execute_source_pack_hierarchical_link_execution_page_async",
        "fn source_pack_schedule_error",
    );
    assert!(
        async_hierarchical_link_page.contains("executor.begin_hierarchical_link_group(page).await"),
        "async hierarchical link page execution must await the group-start work unit"
    );
    assert!(
        async_hierarchical_link_page
            .contains("store.load_hierarchical_link_execution_interface_page("),
        "async hierarchical leaf linking must stream persisted interface pages"
    );
    assert!(
        async_hierarchical_link_page.contains("page.input_interface_ranges")
            && async_hierarchical_link_page.contains("store.load_build_artifact_ref_page("),
        "async hierarchical leaf linking must stream compact ranged interface inputs through bounded artifact-ref batches"
    );
    assert!(
        async_hierarchical_link_page
            .contains("store.load_hierarchical_link_execution_object_page("),
        "async hierarchical leaf linking must stream persisted object pages"
    );
    assert!(
        async_hierarchical_link_page.contains("streamed_object_count")
            && async_hierarchical_link_page.contains("streamed {} object refs but expected {}"),
        "async hierarchical leaf linking must verify object-page streams against the execution page object count"
    );
    assert!(
        async_hierarchical_link_page
            .contains("store.load_hierarchical_link_execution_partial_page("),
        "async hierarchical reduce linking must stream persisted partial-link pages"
    );
    assert!(
        async_hierarchical_link_page.contains("streamed_partial_count")
            && async_hierarchical_link_page
                .contains("streamed {} partial-link refs but expected {}"),
        "async hierarchical reduce linking must verify partial-link page streams against the execution page group count"
    );
    assert!(
        async_hierarchical_link_page
            .contains(".link_hierarchical_library_interfaces(page, &mut link_handle, &interfaces)"),
        "async hierarchical leaf linking must pass loaded interface records to the executor"
    );
    assert!(
        async_hierarchical_link_page
            .contains(".link_hierarchical_partial_links(page, &mut link_handle, &partial_links)"),
        "async hierarchical reduce linking must pass persisted partial-link records to the executor"
    );
    assert!(
        async_hierarchical_link_page
            .contains(".finish_hierarchical_partial_link_group(page, link_handle)"),
        "async hierarchical non-final groups must persist partial-link artifacts"
    );
    let async_path_artifact_link_item = source_between(
        &compiler,
        "pub async fn execute_source_pack_filesystem_work_queue_claimed_link_item_async_with_path_artifacts_for_target_at",
        "pub async fn execute_source_pack_filesystem_work_queue_claimed_item_async_with_path_artifacts_for_target_at",
    );
    assert!(
        async_path_artifact_link_item.contains("SourcePackFilesystemArtifactPathStore::new("),
        "async path-artifact link item execution must instantiate the path-artifact store"
    );
    assert!(
        async_path_artifact_link_item.contains(
            "execute_source_pack_hierarchical_link_execution_page_async(&page, executor, &mut store)"
        ),
        "async path-artifact link item execution must use async hierarchical link page execution"
    );
    assert!(
        !async_path_artifact_link_item
            .contains("execute_source_pack_hierarchical_link_execution_page(&page"),
        "async path-artifact link item execution must not fall back to sync hierarchical linking"
    );
    let async_path_artifact_work_queue_item = source_between(
        &compiler,
        "pub async fn execute_source_pack_filesystem_work_queue_claimed_item_async_with_path_artifacts_for_target_at",
        "pub async fn execute_source_pack_filesystem_work_queue_worker_step_async_with_path_artifacts_for_target_at",
    );
    assert!(
        async_path_artifact_work_queue_item.contains(
            "execute_source_pack_filesystem_work_queue_claimed_artifact_item_async_with_path_artifacts_for_target_at("
        ),
        "async path-artifact work-queue item execution must use async path-backed artifact batch execution"
    );
    assert!(
        async_path_artifact_work_queue_item.contains(
            "execute_source_pack_filesystem_work_queue_claimed_link_item_async_with_path_artifacts_for_target_at("
        ),
        "async path-artifact work-queue item execution must use async path-backed hierarchical link execution"
    );
    assert!(
        !async_path_artifact_work_queue_item.contains(
            "execute_source_pack_filesystem_work_queue_claimed_artifact_item_with_path_artifacts_for_target_at("
        ),
        "async path-artifact work-queue item execution must not fall back to sync path-artifact batches"
    );
    let async_path_artifact_work_queue_step = source_between(
        &compiler,
        "pub async fn execute_source_pack_filesystem_work_queue_worker_step_async_with_path_artifacts_for_target_at",
        "pub async fn execute_source_pack_filesystem_work_queue_worker_run_async_with_path_artifacts_for_target_at",
    );
    assert!(
        async_path_artifact_work_queue_step
            .contains("source_pack_filesystem_work_queue_claim_ready_item_for_target_at("),
        "async path-artifact work-queue worker steps must claim one persisted ready item"
    );
    assert!(
        async_path_artifact_work_queue_step.contains(
            "execute_source_pack_filesystem_work_queue_claimed_item_async_with_path_artifacts_for_target_at("
        ),
        "async path-artifact work-queue worker steps must execute the claimed item through async path-artifact execution"
    );
    assert!(
        !async_path_artifact_work_queue_step.contains(
            "execute_source_pack_filesystem_work_queue_claimed_item_with_path_artifacts_for_target_at("
        ),
        "async path-artifact work-queue worker steps must not call the sync path-artifact item executor"
    );
    let async_path_artifact_work_queue_run = source_between(
        &compiler,
        "pub async fn execute_source_pack_filesystem_work_queue_worker_run_async_with_path_artifacts_for_target_at",
        "pub async fn execute_source_pack_filesystem_work_queue_worker_run_async_with_path_artifacts_for_target<\n    E,",
    );
    assert!(
        async_path_artifact_work_queue_run
            .contains("let step_limit = source_pack_limit_work_queue_worker_run_items(max_items)"),
        "async path-artifact work-queue worker runs must cap max_items before looping"
    );
    assert!(
        async_path_artifact_work_queue_run.contains(
            "execute_source_pack_filesystem_work_queue_worker_step_async_with_path_artifacts_for_target_at("
        ),
        "async path-artifact work-queue worker runs must advance by bounded async worker steps"
    );
    assert!(
        !async_path_artifact_work_queue_run.contains("executed_item_indices"),
        "async path-artifact work-queue worker runs must report executed items by count, not by retained item indices"
    );
    assert!(
        async_path_artifact_work_queue_run
            .contains("source_pack_filesystem_work_queue_final_linked_output_for_progress("),
        "async path-artifact work-queue worker runs must resolve final output handles from persisted link records"
    );
    assert!(
        !async_path_artifact_work_queue_run.contains("executed_item_indices.push"),
        "async path-artifact work-queue worker runs must not retain every executed item index"
    );
    let work_queue_final_output = source_between(
        &compiler,
        "fn source_pack_filesystem_work_queue_final_linked_output_for_progress",
        "fn validate_source_pack_library_partition",
    );
    assert!(
        work_queue_final_output
            .contains("store.load_hierarchical_link_execution_index_for_target(target)?"),
        "work-queue final output lookup must use persisted hierarchical-link execution records"
    );
    assert!(
        work_queue_final_output.contains("if !progress.complete"),
        "work-queue final output lookup must only produce a final handle after completion"
    );
    assert!(
        !work_queue_final_output.contains("load_path_build_manifest")
            && !work_queue_final_output.contains("load_build_artifact_manifest"),
        "work-queue final output lookup must not load whole build manifests"
    );

    let ordered_execute = source_between(
        &compiler,
        "pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_for_target",
        "pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits_for_target",
    );
    assert!(
        ordered_execute.contains(
            "execute_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "ordered filesystem source-pack build entrypoint must delegate to the shard-limited execution path"
    );
    assert!(
        ordered_execute.contains("SourcePackBuildShardLimits::default()"),
        "default ordered filesystem source-pack build entrypoint must set only default shard limits"
    );
    let ordered_execute_with_shards = source_between(
        &compiler,
        "pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits_for_target",
        "pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_worker_run_for_target",
    );
    assert!(
        ordered_execute_with_shards.contains(
            "prepare_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "shard-limited ordered filesystem source-pack build entrypoint must pass caller shard limits into prepare"
    );
    assert!(
        !ordered_execute_with_shards.contains("SourcePackBuildShardLimits::default()"),
        "shard-limited ordered filesystem source-pack build entrypoint must not override caller shard limits"
    );
    assert!(
        ordered_execute_with_shards
            .contains("execute_source_pack_filesystem_artifact_manifest_build_for_target("),
        "shard-limited ordered filesystem source-pack build entrypoint must execute from persisted artifact records"
    );
    assert!(
        !ordered_execute_with_shards
            .contains("source_pack_prepare_library_schedule_pages_from_explicit_source_libraries("),
        "ordered filesystem source-pack build entrypoint must not use the whole-Vec topological planner"
    );
    let ordered_worker_run = source_between(
        &compiler,
        "pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_worker_run_for_target",
        "pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_worker_run_with_shard_limits_for_target",
    );
    assert!(
        ordered_worker_run.contains(
            "execute_ordered_explicit_source_libraries_filesystem_artifact_build_worker_run_with_shard_limits_for_target("
        ),
        "bounded ordered filesystem source-pack worker run must delegate to the shard-limited worker-run path"
    );
    assert!(
        ordered_worker_run.contains("SourcePackBuildShardLimits::default()"),
        "default bounded ordered filesystem source-pack worker run must set only default shard limits"
    );
    let ordered_worker_run_with_shards = source_between(
        &compiler,
        "pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_worker_run_with_shard_limits_for_target",
        "pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_worker_run_with_path_artifacts_for_target",
    );
    assert!(
        ordered_worker_run_with_shards.contains("ExplicitSourceLibraryPathStream")
            && ordered_worker_run_with_shards.contains("source_file_count: library.paths.len()")
            && ordered_worker_run_with_shards.contains(
                "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_for_target("
            ),
        "bounded ordered filesystem source-pack worker run must lower owned libraries into bounded path streams"
    );
    assert!(
        !ordered_worker_run_with_shards.contains(
            "prepare_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits_for_target("
        ) && !ordered_worker_run_with_shards
            .contains("execute_source_pack_filesystem_artifact_manifest_worker_run_for_target("),
        "bounded ordered filesystem source-pack worker run must not hide whole owned-library preparation or direct manifest execution"
    );
    assert!(
        !ordered_worker_run_with_shards
            .contains("execute_source_pack_filesystem_artifact_manifest_build_for_target("),
        "bounded ordered filesystem source-pack worker run must not execute the whole manifest in one call"
    );
    assert!(
        !ordered_worker_run_with_shards.contains("SourcePackBuildShardLimits::default()"),
        "shard-limited bounded ordered filesystem source-pack worker run must not override caller shard limits"
    );
    let ordered_path_artifact_worker_run = source_between(
        &compiler,
        "pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_worker_run_with_path_artifacts_for_target",
        "pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target",
    );
    assert!(
        ordered_path_artifact_worker_run.contains(
            "execute_ordered_explicit_source_libraries_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target("
        ),
        "bounded ordered filesystem source-pack path-artifact worker run must delegate to the shard-limited path-artifact worker-run path"
    );
    assert!(
        ordered_path_artifact_worker_run.contains("SourcePackBuildShardLimits::default()"),
        "default bounded ordered filesystem source-pack path-artifact worker run must set only default shard limits"
    );
    let ordered_path_artifact_worker_run_with_shards = source_between(
        &compiler,
        "pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target",
        "pub async fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_run_async_with_path_artifacts_for_target",
    );
    assert!(
        ordered_path_artifact_worker_run_with_shards.contains("ExplicitSourceLibraryPathStream")
            && ordered_path_artifact_worker_run_with_shards
                .contains("source_file_count: library.paths.len()")
            && ordered_path_artifact_worker_run_with_shards.contains(
                "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target("
            ),
        "bounded ordered filesystem source-pack path-artifact worker run must lower owned libraries into bounded path streams"
    );
    assert!(
        !ordered_path_artifact_worker_run_with_shards.contains(
            "prepare_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "bounded ordered filesystem source-pack path-artifact worker run must not hide whole owned-library preparation"
    );
    assert!(
        !ordered_path_artifact_worker_run_with_shards
            .contains("execute_source_pack_filesystem_artifact_manifest_worker_run_for_target("),
        "bounded ordered filesystem source-pack path-artifact worker run must not fall back to byte-vector artifacts"
    );
    assert!(
        !ordered_path_artifact_worker_run_with_shards
            .contains("SourcePackBuildShardLimits::default()"),
        "shard-limited bounded ordered filesystem source-pack path-artifact worker run must not override caller shard limits"
    );
    let ordered_async_work_queue_worker_run = source_between(
        &compiler,
        "pub async fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_run_async_with_path_artifacts_for_target",
        "pub async fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target",
    );
    assert!(
        ordered_async_work_queue_worker_run.contains(
            "execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target("
        ),
        "default async ordered filesystem work-queue worker run must delegate to the shard-limited async work-queue path"
    );
    assert!(
        ordered_async_work_queue_worker_run.contains("SourcePackBuildShardLimits::default()"),
        "default async ordered filesystem work-queue worker run must set only default shard limits"
    );
    let ordered_async_work_queue_worker_run_with_shards = source_between(
        &compiler,
        "pub async fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target",
        "pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build",
    );
    assert!(
        ordered_async_work_queue_worker_run_with_shards.contains("ExplicitSourceLibraryPathStream"),
        "async ordered filesystem work-queue worker run must lower library inputs into path streams"
    );
    assert!(
        ordered_async_work_queue_worker_run_with_shards.contains(
            "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target("
        ),
        "async ordered filesystem work-queue worker run must reuse the ordered path-stream async work-queue path"
    );
    assert!(
        !ordered_async_work_queue_worker_run_with_shards.contains(
            "prepare_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "async ordered filesystem work-queue worker run must not duplicate ordered-library prepare logic"
    );
    assert!(
        !ordered_async_work_queue_worker_run_with_shards.contains(
            "execute_source_pack_filesystem_artifact_manifest_worker_run_with_path_artifacts_for_target("
        ),
        "async ordered filesystem work-queue worker run must not bypass the work queue through artifact-manifest execution"
    );
    assert!(
        !ordered_async_work_queue_worker_run_with_shards
            .contains("SourcePackBuildShardLimits::default()"),
        "shard-limited async ordered filesystem work-queue worker run must not override caller shard limits"
    );
    let ordered_path_stream_execute = source_between(
        &compiler,
        "pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_for_target",
        "pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits_for_target",
    );
    assert!(
        ordered_path_stream_execute.contains(
            "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "ordered path-stream filesystem source-pack build entrypoint must delegate to the shard-limited execution path"
    );
    assert!(
        ordered_path_stream_execute.contains("SourcePackBuildShardLimits::default()"),
        "default ordered path-stream filesystem source-pack build entrypoint must set only default shard limits"
    );
    let ordered_path_stream_execute_with_shards = source_between(
        &compiler,
        "pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits_for_target",
        "pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_worker_run_for_target",
    );
    assert!(
        ordered_path_stream_execute_with_shards.contains(
            "prepare_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "shard-limited ordered path-stream filesystem source-pack build entrypoint must pass caller shard limits into prepare"
    );
    assert!(
        !ordered_path_stream_execute_with_shards.contains("SourcePackBuildShardLimits::default()"),
        "shard-limited ordered path-stream filesystem source-pack build entrypoint must not override caller shard limits"
    );
    assert!(
        ordered_path_stream_execute_with_shards
            .contains("execute_source_pack_filesystem_artifact_manifest_build_for_target("),
        "shard-limited ordered path-stream filesystem source-pack build entrypoint must execute from persisted artifact records"
    );
    let ordered_path_stream_worker_run = source_between(
        &compiler,
        "pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_worker_run_for_target",
        "pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_for_target",
    );
    assert!(
        ordered_path_stream_worker_run.contains(
            "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_for_target("
        ),
        "bounded ordered path-stream filesystem source-pack worker run must delegate to the shard-limited worker-run path"
    );
    assert!(
        ordered_path_stream_worker_run.contains("SourcePackBuildShardLimits::default()"),
        "default bounded ordered path-stream filesystem source-pack worker run must set only default shard limits"
    );
    let ordered_path_stream_worker_run_with_shards = source_between(
        &compiler,
        "pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_for_target",
        "pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_worker_run_with_path_artifacts_for_target",
    );
    assert!(
        ordered_path_stream_worker_run_with_shards
            .contains("ExplicitSourceLibraryPathDependencyStream")
            && ordered_path_stream_worker_run_with_shards
                .contains("dependency_library_ids.sort_unstable()")
            && ordered_path_stream_worker_run_with_shards.contains(
                "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_work_queue_chunk_with_shard_limits_for_target("
            )
            && ordered_path_stream_worker_run_with_shards
                .contains("source_pack_limit_artifact_worker_run_batches(max_batches).max(1)")
            && ordered_path_stream_worker_run_with_shards
                .contains("source_pack_work_queue_not_prepared_after_bounded_chunk_error(")
            && !ordered_path_stream_worker_run_with_shards.contains(
                "prepare_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits_for_target("
            ),
        "bounded ordered path-stream filesystem source-pack worker run must lower to dependency streams and stop after one bounded preparation chunk"
    );
    assert!(
        ordered_path_stream_worker_run_with_shards
            .contains("execute_source_pack_filesystem_artifact_manifest_worker_run_for_target("),
        "bounded ordered path-stream filesystem source-pack worker run must execute through the resumable worker-run API"
    );
    assert!(
        !ordered_path_stream_worker_run_with_shards
            .contains("execute_source_pack_filesystem_artifact_manifest_build_for_target("),
        "bounded ordered path-stream filesystem source-pack worker run must not execute the whole manifest in one call"
    );
    assert!(
        !ordered_path_stream_worker_run_with_shards
            .contains("SourcePackBuildShardLimits::default()"),
        "shard-limited bounded ordered path-stream filesystem source-pack worker run must not override caller shard limits"
    );
    let ordered_path_stream_path_artifact_worker_run = source_between(
        &compiler,
        "pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_worker_run_with_path_artifacts_for_target",
        "pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target",
    );
    assert!(
        ordered_path_stream_path_artifact_worker_run.contains(
            "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target("
        ),
        "default ordered path-stream path-artifact worker run must delegate to the shard-limited path-artifact worker-run path"
    );
    assert!(
        ordered_path_stream_path_artifact_worker_run
            .contains("SourcePackBuildShardLimits::default()"),
        "default ordered path-stream path-artifact worker run must set only default shard limits"
    );
    let ordered_path_stream_path_artifact_worker_run_with_shards = source_between(
        &compiler,
        "pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target",
        "pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_path_artifacts_for_target",
    );
    assert!(
        ordered_path_stream_path_artifact_worker_run_with_shards
            .contains("ExplicitSourceLibraryPathDependencyStream")
            && ordered_path_stream_path_artifact_worker_run_with_shards
                .contains("dependency_library_ids.sort_unstable()")
            && ordered_path_stream_path_artifact_worker_run_with_shards.contains(
                "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_work_queue_chunk_with_shard_limits_for_target("
            )
            && ordered_path_stream_path_artifact_worker_run_with_shards
                .contains("source_pack_limit_artifact_worker_run_batches(max_batches).max(1)")
            && ordered_path_stream_path_artifact_worker_run_with_shards
                .contains("source_pack_work_queue_not_prepared_after_bounded_chunk_error(")
            && !ordered_path_stream_path_artifact_worker_run_with_shards.contains(
                "prepare_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits_for_target("
            ),
        "ordered path-stream path-artifact worker run must lower to dependency streams and stop after one bounded preparation chunk"
    );
    assert!(
        ordered_path_stream_path_artifact_worker_run_with_shards.contains(
            "execute_source_pack_filesystem_artifact_manifest_worker_run_with_path_artifacts_for_target("
        ),
        "ordered path-stream path-artifact worker run must execute through the path-preserving resumable worker-run API"
    );
    assert!(
        !ordered_path_stream_path_artifact_worker_run_with_shards
            .contains("execute_source_pack_filesystem_artifact_manifest_worker_run_for_target("),
        "ordered path-stream path-artifact worker run must not execute through the byte-artifact worker-run API"
    );
    assert!(
        !ordered_path_stream_path_artifact_worker_run_with_shards
            .contains("execute_source_pack_filesystem_artifact_manifest_build_for_target("),
        "ordered path-stream path-artifact worker run must not execute the whole manifest in one call"
    );
    assert!(
        !ordered_path_stream_path_artifact_worker_run_with_shards
            .contains("SourcePackBuildShardLimits::default()"),
        "shard-limited ordered path-stream path-artifact worker run must not override caller shard limits"
    );
    let ordered_path_stream_async_work_queue_worker_run = source_between(
        &compiler,
        "pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_path_artifacts_for_target",
        "pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target",
    );
    assert!(
        ordered_path_stream_async_work_queue_worker_run.contains(
            "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target("
        ),
        "default async ordered path-stream work-queue worker run must delegate to the shard-limited async work-queue path"
    );
    assert!(
        ordered_path_stream_async_work_queue_worker_run
            .contains("SourcePackBuildShardLimits::default()"),
        "default async ordered path-stream work-queue worker run must set only default shard limits"
    );
    let ordered_path_stream_async_work_queue_worker_run_with_shards = source_between(
        &compiler,
        "pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target",
        "pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build",
    );
    assert!(
        ordered_path_stream_async_work_queue_worker_run_with_shards
            .contains("ExplicitSourceLibraryPathDependencyStream")
            && ordered_path_stream_async_work_queue_worker_run_with_shards
                .contains("dependency_library_ids.sort_unstable()")
            && ordered_path_stream_async_work_queue_worker_run_with_shards.contains(
                "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_work_queue_chunk_with_shard_limits_for_target("
            )
            && ordered_path_stream_async_work_queue_worker_run_with_shards
                .contains("source_pack_limit_work_queue_worker_run_items(max_items).max(1)")
            && ordered_path_stream_async_work_queue_worker_run_with_shards
                .contains("source_pack_work_queue_not_prepared_after_bounded_chunk_error(")
            && !ordered_path_stream_async_work_queue_worker_run_with_shards.contains(
                "prepare_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits_for_target("
            ),
        "async ordered path-stream work-queue worker run must lower to dependency streams and stop after one bounded preparation chunk"
    );
    assert!(
        ordered_path_stream_async_work_queue_worker_run_with_shards.contains(
            "execute_source_pack_filesystem_work_queue_worker_run_async_with_path_artifacts_for_target("
        ),
        "async ordered path-stream work-queue worker run must execute through the async path-artifact work-queue API"
    );
    assert!(
        ordered_path_stream_async_work_queue_worker_run_with_shards.contains(".await"),
        "async ordered path-stream work-queue worker run must await bounded async queue execution"
    );
    assert!(
        !ordered_path_stream_async_work_queue_worker_run_with_shards.contains(
            "execute_source_pack_filesystem_artifact_manifest_worker_run_with_path_artifacts_for_target("
        ),
        "async ordered path-stream work-queue worker run must not bypass the work queue through artifact-manifest execution"
    );
    assert!(
        !ordered_path_stream_async_work_queue_worker_run_with_shards
            .contains("execute_source_pack_filesystem_artifact_manifest_build_for_target("),
        "async ordered path-stream work-queue worker run must not execute the whole manifest in one call"
    );
    assert!(
        !ordered_path_stream_async_work_queue_worker_run_with_shards
            .contains("SourcePackBuildShardLimits::default()"),
        "shard-limited async ordered path-stream work-queue worker run must not override caller shard limits"
    );
    let ordered_path_dependency_stream_execute = source_between(
        &compiler,
        "pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_for_target",
        "pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target",
    );
    assert!(
        ordered_path_dependency_stream_execute.contains(
            "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "ordered path+dependency-stream filesystem source-pack build entrypoint must delegate to the shard-limited execution path"
    );
    assert!(
        ordered_path_dependency_stream_execute.contains("SourcePackBuildShardLimits::default()"),
        "default ordered path+dependency-stream filesystem source-pack build entrypoint must set only default shard limits"
    );
    let ordered_path_dependency_stream_execute_with_shards = source_between(
        &compiler,
        "pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target",
        "pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_worker_run_for_target",
    );
    assert!(
        ordered_path_dependency_stream_execute_with_shards.contains(
            "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "shard-limited ordered path+dependency-stream filesystem source-pack build entrypoint must pass caller shard limits into prepare"
    );
    assert!(
        !ordered_path_dependency_stream_execute_with_shards
            .contains("SourcePackBuildShardLimits::default()"),
        "shard-limited ordered path+dependency-stream filesystem source-pack build entrypoint must not override caller shard limits"
    );
    assert!(
        ordered_path_dependency_stream_execute_with_shards
            .contains("execute_source_pack_filesystem_artifact_manifest_build_for_target("),
        "shard-limited ordered path+dependency-stream filesystem source-pack build entrypoint must execute from persisted artifact records"
    );
    let ordered_path_dependency_stream_worker_run = source_between(
        &compiler,
        "pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_worker_run_for_target",
        "pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_worker_run_with_shard_limits_for_target",
    );
    assert!(
        ordered_path_dependency_stream_worker_run.contains(
            "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_worker_run_with_shard_limits_for_target("
        ),
        "bounded ordered path+dependency-stream filesystem source-pack worker run must delegate to the shard-limited worker-run path"
    );
    assert!(
        ordered_path_dependency_stream_worker_run.contains("SourcePackBuildShardLimits::default()"),
        "default bounded ordered path+dependency-stream filesystem source-pack worker run must set only default shard limits"
    );
    let ordered_path_dependency_stream_worker_run_with_shards = source_between(
        &compiler,
        "pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_worker_run_with_shard_limits_for_target",
        "pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_worker_run_with_path_artifacts_for_target",
    );
    assert!(
        ordered_path_dependency_stream_worker_run_with_shards.contains(
            "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_work_queue_chunk_with_shard_limits_for_target("
        ) && ordered_path_dependency_stream_worker_run_with_shards
            .contains("source_pack_limit_artifact_worker_run_batches(max_batches).max(1)")
            && ordered_path_dependency_stream_worker_run_with_shards
                .contains("source_pack_work_queue_not_prepared_after_bounded_chunk_error(")
            && !ordered_path_dependency_stream_worker_run_with_shards.contains(
                "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target("
            ),
        "bounded ordered path+dependency-stream filesystem source-pack worker run must stop after one bounded preparation chunk instead of hiding full artifact preparation"
    );
    assert!(
        ordered_path_dependency_stream_worker_run_with_shards
            .contains("execute_source_pack_filesystem_artifact_manifest_worker_run_for_target("),
        "bounded ordered path+dependency-stream filesystem source-pack worker run must execute through the resumable worker-run API"
    );
    assert!(
        !ordered_path_dependency_stream_worker_run_with_shards
            .contains("execute_source_pack_filesystem_artifact_manifest_build_for_target("),
        "bounded ordered path+dependency-stream filesystem source-pack worker run must not execute the whole manifest in one call"
    );
    assert!(
        !ordered_path_dependency_stream_worker_run_with_shards
            .contains("SourcePackBuildShardLimits::default()"),
        "shard-limited bounded ordered path+dependency-stream filesystem source-pack worker run must not override caller shard limits"
    );
    let ordered_path_dependency_stream_path_artifact_worker_run = source_between(
        &compiler,
        "pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_worker_run_with_path_artifacts_for_target",
        "pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target",
    );
    assert!(
        ordered_path_dependency_stream_path_artifact_worker_run.contains(
            "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target("
        ),
        "default ordered path+dependency-stream path-artifact worker run must delegate to the shard-limited path-artifact worker-run path"
    );
    assert!(
        ordered_path_dependency_stream_path_artifact_worker_run
            .contains("SourcePackBuildShardLimits::default()"),
        "default ordered path+dependency-stream path-artifact worker run must set only default shard limits"
    );
    let ordered_path_dependency_stream_path_artifact_worker_run_with_shards = source_between(
        &compiler,
        "pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target",
        "pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_async_with_path_artifacts_for_target",
    );
    assert!(
        ordered_path_dependency_stream_path_artifact_worker_run_with_shards.contains(
            "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_work_queue_chunk_with_shard_limits_for_target("
        ) && ordered_path_dependency_stream_path_artifact_worker_run_with_shards
            .contains("source_pack_limit_artifact_worker_run_batches(max_batches).max(1)")
            && ordered_path_dependency_stream_path_artifact_worker_run_with_shards
                .contains("source_pack_work_queue_not_prepared_after_bounded_chunk_error(")
            && !ordered_path_dependency_stream_path_artifact_worker_run_with_shards.contains(
                "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target("
            ),
        "ordered path+dependency-stream path-artifact worker run must stop after one bounded preparation chunk instead of hiding full artifact preparation"
    );
    assert!(
        ordered_path_dependency_stream_path_artifact_worker_run_with_shards.contains(
            "execute_source_pack_filesystem_artifact_manifest_worker_run_with_path_artifacts_for_target("
        ),
        "ordered path+dependency-stream path-artifact worker run must execute through the path-preserving resumable worker-run API"
    );
    assert!(
        !ordered_path_dependency_stream_path_artifact_worker_run_with_shards
            .contains("execute_source_pack_filesystem_artifact_manifest_worker_run_for_target("),
        "ordered path+dependency-stream path-artifact worker run must not execute through the byte-artifact worker-run API"
    );
    assert!(
        !ordered_path_dependency_stream_path_artifact_worker_run_with_shards
            .contains("execute_source_pack_filesystem_artifact_manifest_build_for_target("),
        "ordered path+dependency-stream path-artifact worker run must not execute the whole manifest in one call"
    );
    assert!(
        !ordered_path_dependency_stream_path_artifact_worker_run_with_shards
            .contains("SourcePackBuildShardLimits::default()"),
        "shard-limited ordered path+dependency-stream path-artifact worker run must not override caller shard limits"
    );
    let ordered_path_dependency_stream_async_work_queue_worker_run = source_between(
        &compiler,
        "pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_async_with_path_artifacts_for_target",
        "pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target",
    );
    assert!(
        ordered_path_dependency_stream_async_work_queue_worker_run.contains(
            "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target("
        ),
        "default async ordered path+dependency-stream work-queue worker run must delegate to the shard-limited async work-queue path"
    );
    assert!(
        ordered_path_dependency_stream_async_work_queue_worker_run
            .contains("SourcePackBuildShardLimits::default()"),
        "default async ordered path+dependency-stream work-queue worker run must set only default shard limits"
    );
    let ordered_path_dependency_stream_async_work_queue_worker_run_with_shards = source_between(
        &compiler,
        "pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target",
        "pub fn execute_explicit_source_libraries_filesystem_artifact_build_for_target",
    );
    assert!(
        ordered_path_dependency_stream_async_work_queue_worker_run_with_shards.contains(
            "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_work_queue_chunk_with_shard_limits_for_target("
        ) && ordered_path_dependency_stream_async_work_queue_worker_run_with_shards
            .contains("source_pack_limit_work_queue_worker_run_items(max_items).max(1)")
            && ordered_path_dependency_stream_async_work_queue_worker_run_with_shards
                .contains("source_pack_work_queue_not_prepared_after_bounded_chunk_error(")
            && !ordered_path_dependency_stream_async_work_queue_worker_run_with_shards.contains(
                "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target("
            ),
        "async ordered path+dependency-stream work-queue worker run must stop after one bounded preparation chunk instead of hiding full artifact preparation"
    );
    assert!(
        ordered_path_dependency_stream_async_work_queue_worker_run_with_shards.contains(
            "execute_source_pack_filesystem_work_queue_worker_run_async_with_path_artifacts_for_target("
        ),
        "async ordered path+dependency-stream work-queue worker run must execute through the async path-artifact work-queue API"
    );
    assert!(
        ordered_path_dependency_stream_async_work_queue_worker_run_with_shards.contains(".await"),
        "async ordered path+dependency-stream work-queue worker run must await bounded async queue execution"
    );
    assert!(
        !ordered_path_dependency_stream_async_work_queue_worker_run_with_shards.contains(
            "execute_source_pack_filesystem_artifact_manifest_worker_run_with_path_artifacts_for_target("
        ),
        "async ordered path+dependency-stream work-queue worker run must not bypass the work queue through artifact-manifest execution"
    );
    assert!(
        !ordered_path_dependency_stream_async_work_queue_worker_run_with_shards
            .contains("execute_source_pack_filesystem_artifact_manifest_build_for_target("),
        "async ordered path+dependency-stream work-queue worker run must not execute the whole manifest in one call"
    );
    assert!(
        !ordered_path_dependency_stream_async_work_queue_worker_run_with_shards
            .contains("SourcePackBuildShardLimits::default()"),
        "shard-limited async ordered path+dependency-stream work-queue worker run must not override caller shard limits"
    );
    let pack_path_streams_prepare = source_between(
        &compiler,
        "pub fn prepare_explicit_source_pack_path_streams_filesystem_artifact_build_for_target",
        "pub fn prepare_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target",
    );
    assert!(
        pack_path_streams_prepare.contains(
            "prepare_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "stdlib/user path-stream filesystem source-pack prepare must delegate to the shard-limited prepare path"
    );
    assert!(
        pack_path_streams_prepare.contains("SourcePackBuildShardLimits::default()"),
        "default stdlib/user path-stream filesystem source-pack prepare must set only default shard limits"
    );
    let pack_path_streams_prepare_with_shards = source_between(
        &compiler,
        "pub fn prepare_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target",
        "pub fn prepare_explicit_source_pack_paths_filesystem_artifact_build",
    );
    assert!(
        pack_path_streams_prepare_with_shards.contains("ExplicitSourceLibraryPathDependencyStream"),
        "stdlib/user path-stream filesystem source-pack prepare must route through path+dependency streams"
    );
    assert!(
        pack_path_streams_prepare_with_shards.contains(
            "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "stdlib/user path-stream filesystem source-pack prepare must use the ordered streaming prepare stage with caller shard limits"
    );
    assert!(
        !pack_path_streams_prepare_with_shards.contains("SourcePackBuildShardLimits::default()"),
        "shard-limited stdlib/user path-stream filesystem source-pack prepare must not override caller shard limits"
    );
    assert!(
        !pack_path_streams_prepare_with_shards.contains(".to_path_buf()"),
        "stdlib/user path-stream filesystem source-pack prepare must not clone every input path before streaming"
    );
    assert!(
        !pack_path_streams_prepare_with_shards.contains(".collect()"),
        "stdlib/user path-stream filesystem source-pack prepare must not collect input paths into Vec libraries"
    );
    let pack_paths_prepare = source_between(
        &compiler,
        "pub fn prepare_explicit_source_pack_paths_filesystem_artifact_build_for_target",
        "pub fn execute_explicit_source_pack_paths_filesystem_artifact_build",
    );
    assert!(
        pack_paths_prepare.contains(
            "prepare_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "stdlib/user slice filesystem source-pack prepare must delegate to the path-stream prepare path"
    );
    assert!(
        pack_paths_prepare.contains(
            "prepare_explicit_source_pack_paths_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "stdlib/user filesystem source-pack prepare must delegate through the shard-limited prepare path"
    );
    assert!(
        !pack_paths_prepare.contains("ExplicitSourceLibraryPathDependencyStream"),
        "stdlib/user slice filesystem source-pack prepare must not duplicate stream lowering"
    );
    assert!(
        !pack_paths_prepare.contains(".to_path_buf()"),
        "stdlib/user filesystem source-pack prepare must not clone every input path before streaming"
    );
    assert!(
        !pack_paths_prepare.contains(".collect()"),
        "stdlib/user filesystem source-pack prepare must not collect input path slices into Vec libraries"
    );
    assert!(
        !pack_paths_prepare
            .contains("prepare_explicit_source_libraries_filesystem_artifact_build_for_target("),
        "stdlib/user filesystem source-pack prepare must not re-enter the whole-Vec library planner"
    );
    let pack_path_streams_execute = source_between(
        &compiler,
        "pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_for_target",
        "pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_worker_run_for_target",
    );
    assert!(
        pack_path_streams_execute.contains(
            "execute_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "stdlib/user path-stream filesystem source-pack execute must delegate to the shard-limited execute path"
    );
    assert!(
        pack_path_streams_execute.contains("SourcePackBuildShardLimits::default()"),
        "default stdlib/user path-stream filesystem source-pack execute must set only default shard limits"
    );
    let pack_path_streams_execute_with_shards = source_between(
        &compiler,
        "pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target",
        "pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_for_target",
    );
    assert!(
        pack_path_streams_execute_with_shards.contains(
            "prepare_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "shard-limited stdlib/user path-stream filesystem source-pack execute must pass caller shard limits into prepare"
    );
    assert!(
        !pack_path_streams_execute_with_shards.contains("SourcePackBuildShardLimits::default()"),
        "shard-limited stdlib/user path-stream filesystem source-pack execute must not override caller shard limits"
    );
    assert!(
        pack_path_streams_execute_with_shards
            .contains("execute_source_pack_filesystem_artifact_manifest_build_for_target("),
        "shard-limited stdlib/user path-stream filesystem source-pack execute must execute from persisted artifact records"
    );
    let pack_path_streams_worker_run = source_between(
        &compiler,
        "pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_worker_run_for_target",
        "pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target",
    );
    assert!(
        pack_path_streams_worker_run.contains(
            "execute_explicit_source_pack_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_for_target("
        ),
        "bounded stdlib/user path-stream filesystem source-pack worker run must delegate to the shard-limited worker-run path"
    );
    assert!(
        pack_path_streams_worker_run.contains("SourcePackBuildShardLimits::default()"),
        "default bounded stdlib/user path-stream filesystem source-pack worker run must set only default shard limits"
    );
    let pack_path_streams_worker_run_with_shards = source_between(
        &compiler,
        "pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_for_target",
        "pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_worker_run_with_path_artifacts_for_target",
    );
    assert!(
        pack_path_streams_worker_run_with_shards.contains(
            "prepare_explicit_source_pack_path_streams_filesystem_work_queue_chunk_with_shard_limits_for_target("
        ) && pack_path_streams_worker_run_with_shards
            .contains("source_pack_limit_artifact_worker_run_batches(max_batches).max(1)")
            && pack_path_streams_worker_run_with_shards
                .contains("source_pack_work_queue_not_prepared_after_bounded_chunk_error(")
            && !pack_path_streams_worker_run_with_shards.contains(
                "prepare_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target("
            ),
        "bounded stdlib/user path-stream filesystem source-pack worker run must stop after one bounded preparation chunk instead of hiding full artifact preparation"
    );
    assert!(
        pack_path_streams_worker_run_with_shards
            .contains("execute_source_pack_filesystem_artifact_manifest_worker_run_for_target("),
        "bounded stdlib/user path-stream filesystem source-pack worker run must execute through the resumable worker-run API"
    );
    assert!(
        !pack_path_streams_worker_run_with_shards
            .contains("execute_source_pack_filesystem_artifact_manifest_build_for_target("),
        "bounded stdlib/user path-stream filesystem source-pack worker run must not execute the whole manifest in one call"
    );
    assert!(
        !pack_path_streams_worker_run_with_shards.contains("SourcePackBuildShardLimits::default()"),
        "shard-limited bounded stdlib/user path-stream filesystem source-pack worker run must not override caller shard limits"
    );
    let pack_path_streams_path_artifact_worker_run = source_between(
        &compiler,
        "pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_worker_run_with_path_artifacts_for_target",
        "pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target",
    );
    assert!(
        pack_path_streams_path_artifact_worker_run.contains(
            "execute_explicit_source_pack_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target("
        ),
        "default stdlib/user path-stream path-artifact worker run must delegate to the shard-limited path-artifact worker-run path"
    );
    assert!(
        pack_path_streams_path_artifact_worker_run
            .contains("SourcePackBuildShardLimits::default()"),
        "default stdlib/user path-stream path-artifact worker run must set only default shard limits"
    );
    let pack_path_streams_path_artifact_worker_run_with_shards = source_between(
        &compiler,
        "pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target",
        "pub async fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_path_artifacts_for_target",
    );
    assert!(
        pack_path_streams_path_artifact_worker_run_with_shards.contains(
            "prepare_explicit_source_pack_path_streams_filesystem_work_queue_chunk_with_shard_limits_for_target("
        ) && pack_path_streams_path_artifact_worker_run_with_shards
            .contains("source_pack_limit_artifact_worker_run_batches(max_batches).max(1)")
            && pack_path_streams_path_artifact_worker_run_with_shards
                .contains("source_pack_work_queue_not_prepared_after_bounded_chunk_error(")
            && !pack_path_streams_path_artifact_worker_run_with_shards.contains(
                "prepare_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target("
            ),
        "stdlib/user path-stream path-artifact worker run must stop after one bounded preparation chunk instead of hiding full artifact preparation"
    );
    assert!(
        pack_path_streams_path_artifact_worker_run_with_shards.contains(
            "execute_source_pack_filesystem_artifact_manifest_worker_run_with_path_artifacts_for_target("
        ),
        "stdlib/user path-stream path-artifact worker run must execute through the path-preserving resumable worker-run API"
    );
    assert!(
        !pack_path_streams_path_artifact_worker_run_with_shards
            .contains("execute_source_pack_filesystem_artifact_manifest_worker_run_for_target("),
        "stdlib/user path-stream path-artifact worker run must not execute through the byte-artifact worker-run API"
    );
    assert!(
        !pack_path_streams_path_artifact_worker_run_with_shards
            .contains("execute_source_pack_filesystem_artifact_manifest_build_for_target("),
        "stdlib/user path-stream path-artifact worker run must not execute the whole manifest in one call"
    );
    assert!(
        !pack_path_streams_path_artifact_worker_run_with_shards
            .contains("SourcePackBuildShardLimits::default()"),
        "shard-limited stdlib/user path-stream path-artifact worker run must not override caller shard limits"
    );
    let pack_path_streams_async_work_queue_worker_run = source_between(
        &compiler,
        "pub async fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_path_artifacts_for_target",
        "pub async fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target",
    );
    assert!(
        pack_path_streams_async_work_queue_worker_run.contains(
            "execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target("
        ),
        "default async stdlib/user path-stream work-queue worker run must delegate to the shard-limited async work-queue path"
    );
    assert!(
        pack_path_streams_async_work_queue_worker_run
            .contains("SourcePackBuildShardLimits::default()"),
        "default async stdlib/user path-stream work-queue worker run must set only default shard limits"
    );
    let pack_path_streams_async_work_queue_worker_run_with_shards = source_between(
        &compiler,
        "pub async fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target",
        "pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_async_with_path_artifacts_for_target",
    );
    assert!(
        pack_path_streams_async_work_queue_worker_run_with_shards.contains(
            "prepare_explicit_source_pack_path_streams_filesystem_work_queue_chunk_with_shard_limits_for_target("
        ) && pack_path_streams_async_work_queue_worker_run_with_shards
            .contains("source_pack_limit_work_queue_worker_run_items(max_items).max(1)")
            && pack_path_streams_async_work_queue_worker_run_with_shards
                .contains("source_pack_work_queue_not_prepared_after_bounded_chunk_error(")
            && !pack_path_streams_async_work_queue_worker_run_with_shards.contains(
                "prepare_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target("
            ),
        "async stdlib/user path-stream work-queue worker run must stop after one bounded preparation chunk instead of hiding full artifact preparation"
    );
    assert!(
        pack_path_streams_async_work_queue_worker_run_with_shards.contains(
            "execute_source_pack_filesystem_work_queue_worker_run_async_with_path_artifacts_for_target("
        ),
        "async stdlib/user path-stream work-queue worker run must execute through the async path-artifact work-queue API"
    );
    assert!(
        pack_path_streams_async_work_queue_worker_run_with_shards.contains(".await"),
        "async stdlib/user path-stream work-queue worker run must await bounded async queue execution"
    );
    assert!(
        !pack_path_streams_async_work_queue_worker_run_with_shards.contains(
            "execute_source_pack_filesystem_artifact_manifest_worker_run_with_path_artifacts_for_target("
        ),
        "async stdlib/user path-stream work-queue worker run must not bypass the work queue through artifact-manifest execution"
    );
    assert!(
        !pack_path_streams_async_work_queue_worker_run_with_shards
            .contains("execute_source_pack_filesystem_artifact_manifest_build_for_target("),
        "async stdlib/user path-stream work-queue worker run must not execute the whole manifest in one call"
    );
    assert!(
        !pack_path_streams_async_work_queue_worker_run_with_shards
            .contains("SourcePackBuildShardLimits::default()"),
        "shard-limited async stdlib/user path-stream work-queue worker run must not override caller shard limits"
    );
    let pack_paths_execute = source_between(
        &compiler,
        "pub fn execute_explicit_source_pack_paths_filesystem_artifact_build_for_target",
        "pub fn execute_explicit_source_libraries_artifact_store_build",
    );
    assert!(
        pack_paths_execute.contains(
            "execute_explicit_source_pack_paths_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "stdlib/user filesystem source-pack execute must delegate through the shard-limited execute path"
    );
    assert!(
        pack_paths_execute.contains(
            "prepare_explicit_source_pack_paths_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "stdlib/user filesystem source-pack execute must pass caller shard limits into prepare"
    );
    assert!(
        pack_paths_execute
            .contains("execute_source_pack_filesystem_artifact_manifest_build_for_target("),
        "stdlib/user filesystem source-pack execute must execute from persisted artifact records"
    );
    let pack_paths_async_work_queue_worker_run = source_between(
        &compiler,
        "pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_async_with_path_artifacts_for_target",
        "pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target",
    );
    assert!(
        pack_paths_async_work_queue_worker_run.contains(
            "execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target("
        ),
        "default async stdlib/user path-slice work-queue worker run must delegate to the shard-limited async work-queue path"
    );
    assert!(
        pack_paths_async_work_queue_worker_run.contains("SourcePackBuildShardLimits::default()"),
        "default async stdlib/user path-slice work-queue worker run must set only default shard limits"
    );
    let pack_paths_async_work_queue_worker_run_with_shards = source_between(
        &compiler,
        "pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target",
        "pub fn execute_explicit_source_pack_paths_filesystem_artifact_build_with_shard_limits<",
    );
    assert!(
        pack_paths_async_work_queue_worker_run_with_shards.contains(
            "execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target("
        ),
        "async stdlib/user path-slice work-queue worker run must reuse the path-stream async work-queue path"
    );
    assert!(
        pack_paths_async_work_queue_worker_run_with_shards
            .contains("stdlib_paths.iter().map(|path| path.as_ref())"),
        "async stdlib/user path-slice work-queue worker run must stream stdlib paths without cloning"
    );
    assert!(
        pack_paths_async_work_queue_worker_run_with_shards
            .contains("user_paths.iter().map(|path| path.as_ref())"),
        "async stdlib/user path-slice work-queue worker run must stream user paths without cloning"
    );
    assert!(
        !pack_paths_async_work_queue_worker_run_with_shards.contains(".to_path_buf()"),
        "async stdlib/user path-slice work-queue worker run must not clone every input path"
    );
    assert!(
        !pack_paths_async_work_queue_worker_run_with_shards.contains(".collect()"),
        "async stdlib/user path-slice work-queue worker run must not collect input paths into Vec libraries"
    );
    assert!(
        !pack_paths_async_work_queue_worker_run_with_shards.contains(
            "execute_source_pack_filesystem_artifact_manifest_worker_run_with_path_artifacts_for_target("
        ),
        "async stdlib/user path-slice work-queue worker run must not bypass the work queue through artifact-manifest execution"
    );
    assert!(
        !pack_paths_async_work_queue_worker_run_with_shards
            .contains("SourcePackBuildShardLimits::default()"),
        "shard-limited async stdlib/user path-slice work-queue worker run must not override caller shard limits"
    );
    let gpu_compiler_prepared_descriptor_worker = source_between(
        &compiler,
        "pub async fn execute_prepared_source_pack_filesystem_work_queue_worker_run_with_gpu_descriptors_for_target",
        "pub async fn execute_prepared_source_pack_filesystem_work_queue_worker_run_to_wasm_with_gpu_descriptors",
    );
    assert!(
        gpu_compiler_prepared_descriptor_worker
            .contains("GpuSourcePackArtifactExecutor::new(self, artifact_root.clone(), target)"),
        "GPU compiler prepared descriptor worker must execute through the GPU source-pack path-artifact executor"
    );
    assert!(
        gpu_compiler_prepared_descriptor_worker.contains(
            "execute_source_pack_filesystem_work_queue_worker_run_async_with_path_artifacts_for_target("
        ),
        "GPU compiler prepared descriptor worker must run the existing persisted async path-artifact work queue"
    );
    assert!(
        !gpu_compiler_prepared_descriptor_worker
            .contains("prepare_explicit_source_pack_paths_filesystem_artifact_build"),
        "GPU compiler prepared descriptor worker must not reprepare path inputs"
    );
    assert!(
        !gpu_compiler_prepared_descriptor_worker
            .contains("load_explicit_source_pack_manifest_from_paths("),
        "GPU compiler prepared descriptor worker must not load source paths into a whole source-pack manifest"
    );
    let gpu_compiler_prepared_descriptor_step = source_between(
        &compiler,
        "pub async fn execute_prepared_source_pack_filesystem_work_queue_worker_step_with_gpu_descriptors_for_target",
        "pub async fn execute_prepared_source_pack_filesystem_work_queue_worker_run_to_wasm_with_gpu_descriptors",
    );
    assert!(
        gpu_compiler_prepared_descriptor_step
            .contains("GpuSourcePackArtifactExecutor::new(self, artifact_root.clone(), target)"),
        "GPU compiler prepared descriptor step must execute through the GPU source-pack path-artifact executor"
    );
    assert!(
        gpu_compiler_prepared_descriptor_step.contains(
            "execute_source_pack_filesystem_work_queue_worker_step_async_with_path_artifacts_for_target_at("
        ),
        "GPU compiler prepared descriptor step must submit exactly one persisted async path-artifact work item"
    );
    assert!(
        !gpu_compiler_prepared_descriptor_step.contains(
            "execute_source_pack_filesystem_work_queue_worker_run_async_with_path_artifacts_for_target("
        ),
        "GPU compiler prepared descriptor step must not call the chunk worker-run loop"
    );
    let prepared_build_submission_helpers = source_between(
        &compiler,
        "impl SourcePackFilesystemPreparedArtifactBuild",
        "impl SourcePackFilesystemArtifactPrepareResult",
    );
    assert!(
        prepared_build_submission_helpers.contains("submit_path_artifact_work_queue_step<E>(")
            && prepared_build_submission_helpers.contains(
                "execute_source_pack_filesystem_work_queue_worker_step_with_path_artifacts_for_target_at("
            ),
        "prepared source-pack handles must expose a one-item path-artifact submit step"
    );
    assert!(
        prepared_build_submission_helpers
            .contains("submit_path_artifact_work_queue_step_async<E>(")
            && prepared_build_submission_helpers.contains(
                "execute_source_pack_filesystem_work_queue_worker_step_async_with_path_artifacts_for_target_at("
            ),
        "prepared source-pack handles must expose a one-item async path-artifact submit step"
    );
    assert!(
        prepared_build_submission_helpers.contains("submit_gpu_descriptor_work_queue_step_using(")
            && prepared_build_submission_helpers.contains(
                "execute_prepared_source_pack_filesystem_work_queue_worker_step_with_gpu_descriptors_for_target("
            ),
        "prepared source-pack handles must expose a one-item GPU descriptor submit step"
    );
    let gpu_compiler_prepared_wasm_descriptor_worker = source_between(
        &compiler,
        "pub async fn execute_prepared_source_pack_filesystem_work_queue_worker_run_to_wasm_with_gpu_descriptors",
        "pub async fn execute_prepared_source_pack_filesystem_work_queue_worker_run_to_x86_64_with_gpu_descriptors",
    );
    assert!(
        gpu_compiler_prepared_wasm_descriptor_worker.contains("SourcePackArtifactTarget::Wasm"),
        "GPU compiler prepared WASM descriptor worker must select the WASM target for existing artifact records"
    );
    let gpu_compiler_prepared_x86_descriptor_worker = source_between(
        &compiler,
        "pub async fn execute_prepared_source_pack_filesystem_work_queue_worker_run_to_x86_64_with_gpu_descriptors",
        "pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_with_gpu_descriptors_for_target",
    );
    assert!(
        gpu_compiler_prepared_x86_descriptor_worker.contains("SourcePackArtifactTarget::X86_64"),
        "GPU compiler prepared x86 descriptor worker must select the x86 target for existing artifact records"
    );
    let gpu_compiler_owned_library_descriptor_step = source_between(
        &compiler,
        "pub async fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_with_gpu_descriptors_for_target",
        "pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_with_gpu_descriptors_for_target",
    );
    assert!(
        gpu_compiler_owned_library_descriptor_step.contains("ExplicitSourceLibraryPathStream")
            && gpu_compiler_owned_library_descriptor_step
                .contains("source_file_count: library.paths.len()")
            && gpu_compiler_owned_library_descriptor_step.contains("paths: library.paths")
            && gpu_compiler_owned_library_descriptor_step
                .contains("dependency_library_ids: library.dependency_library_ids"),
        "GPU compiler owned-library descriptor step must lower owned path lists into bounded path streams"
    );
    assert!(
        gpu_compiler_owned_library_descriptor_step.contains(
            "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_with_gpu_descriptors_for_target("
        ),
        "GPU compiler owned-library descriptor step must delegate to the ordered path-stream one-item descriptor step"
    );
    assert!(
        !gpu_compiler_owned_library_descriptor_step.contains(
            "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_with_gpu_descriptors_for_target("
        ) && !gpu_compiler_owned_library_descriptor_step
            .contains("load_explicit_source_libraries_from_paths(")
            && !gpu_compiler_owned_library_descriptor_step
                .contains("load_explicit_source_pack_manifest_from_paths("),
        "GPU compiler owned-library descriptor step must not enter a run loop or load whole source-pack manifests"
    );
    let gpu_compiler_library_path_stream_descriptor_worker = source_between(
        &compiler,
        "pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_with_gpu_descriptors_for_target",
        "pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors",
    );
    assert!(
        gpu_compiler_library_path_stream_descriptor_worker
            .contains("GpuSourcePackArtifactExecutor::new(self, artifact_root.clone(), target)"),
        "GPU compiler ordered library path-stream descriptor worker must execute through the GPU source-pack path-artifact executor"
    );
    assert!(
        gpu_compiler_library_path_stream_descriptor_worker.contains(
            "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target("
        ),
        "GPU compiler ordered library path-stream descriptor worker must use the ordered path-stream work queue"
    );
    assert!(
        !gpu_compiler_library_path_stream_descriptor_worker
            .contains("load_explicit_source_libraries_from_paths(")
            && !gpu_compiler_library_path_stream_descriptor_worker
                .contains("load_explicit_source_pack_manifest_from_paths("),
        "GPU compiler ordered library path-stream descriptor worker must not load paths into whole source-pack manifests"
    );
    assert!(
        !gpu_compiler_library_path_stream_descriptor_worker.contains(".collect()")
            && !gpu_compiler_library_path_stream_descriptor_worker
                .contains("Vec<ExplicitSourceLibraryPaths"),
        "GPU compiler ordered library path-stream descriptor worker must not collect streamed library inputs"
    );
    let gpu_compiler_library_path_stream_descriptor_step = source_between(
        &compiler,
        "pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_with_gpu_descriptors_for_target",
        "pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors",
    );
    assert!(
        gpu_compiler_library_path_stream_descriptor_step
            .contains("ExplicitSourceLibraryPathDependencyStream")
            && gpu_compiler_library_path_stream_descriptor_step
                .contains("dependency_library_ids.sort_unstable()")
            && gpu_compiler_library_path_stream_descriptor_step.contains(
                "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_work_queue_chunk_with_shard_limits_for_target("
            )
            && gpu_compiler_library_path_stream_descriptor_step
                .contains("SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT")
            && gpu_compiler_library_path_stream_descriptor_step
                .contains("source_pack_work_queue_not_prepared_after_bounded_chunk_error("),
        "GPU compiler ordered library path-stream descriptor step must lower to dependency streams and stop after one bounded preparation chunk"
    );
    assert!(
        gpu_compiler_library_path_stream_descriptor_step
            .contains("SourcePackFilesystemPreparedArtifactBuild::new(&artifact_root, target)")
            && gpu_compiler_library_path_stream_descriptor_step
                .contains("submit_gpu_descriptor_work_queue_step_using("),
        "GPU compiler ordered library path-stream descriptor step must advance exactly one item from a reopened persisted queue"
    );
    assert!(
        !gpu_compiler_library_path_stream_descriptor_step.contains(
            "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target("
        ) && !gpu_compiler_library_path_stream_descriptor_step.contains(
            "execute_source_pack_filesystem_work_queue_worker_run_async_with_path_artifacts_for_target("
        ) && !gpu_compiler_library_path_stream_descriptor_step.contains(
            "prepare_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "GPU compiler ordered library path-stream descriptor step must not enter a max-items worker run loop or hide full artifact preparation"
    );
    assert!(
        !gpu_compiler_library_path_stream_descriptor_step
            .contains("load_explicit_source_libraries_from_paths(")
            && !gpu_compiler_library_path_stream_descriptor_step
                .contains("load_explicit_source_pack_manifest_from_paths("),
        "GPU compiler ordered library path-stream descriptor step must not load paths into whole source-pack manifests"
    );
    let gpu_compiler_library_path_stream_wasm_descriptor_worker = source_between(
        &compiler,
        "pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors",
        "pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_to_x86_64_with_gpu_descriptors",
    );
    assert!(
        gpu_compiler_library_path_stream_wasm_descriptor_worker
            .contains("SourcePackArtifactTarget::Wasm"),
        "GPU compiler ordered library path-stream WASM descriptor worker must select the WASM target"
    );
    let gpu_compiler_library_path_stream_x86_descriptor_worker = source_between(
        &compiler,
        "pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_to_x86_64_with_gpu_descriptors",
        "pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_with_gpu_descriptors_for_target",
    );
    assert!(
        gpu_compiler_library_path_stream_x86_descriptor_worker
            .contains("SourcePackArtifactTarget::X86_64"),
        "GPU compiler ordered library path-stream x86 descriptor worker must select the x86 target"
    );
    let gpu_compiler_library_dependency_descriptor_worker = source_between(
        &compiler,
        "pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_with_gpu_descriptors_for_target",
        "pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors",
    );
    assert!(
        gpu_compiler_library_dependency_descriptor_worker.contains(
            "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_work_queue_chunk_with_shard_limits_for_target("
        ) && gpu_compiler_library_dependency_descriptor_worker.contains(
            "source_pack_limit_work_queue_worker_run_items(max_items).max(1)"
        ),
        "GPU compiler many-library descriptor worker must advance only one bounded persisted preparation chunk before queue execution"
    );
    assert!(
        gpu_compiler_library_dependency_descriptor_worker.contains(
            "execute_prepared_source_pack_filesystem_work_queue_worker_run_with_gpu_descriptors_for_target("
        ),
        "GPU compiler many-library descriptor worker must submit only from an already prepared persisted work queue"
    );
    assert!(
        gpu_compiler_library_dependency_descriptor_worker
            .contains("source_pack_work_queue_not_prepared_after_bounded_chunk_error("),
        "GPU compiler many-library descriptor worker must stop after a bounded preparation chunk when the queue is not ready"
    );
    assert!(
        !gpu_compiler_library_dependency_descriptor_worker
            .contains("load_explicit_source_libraries_from_paths(")
            && !gpu_compiler_library_dependency_descriptor_worker
                .contains("load_explicit_source_pack_manifest_from_paths("),
        "GPU compiler many-library descriptor worker must not load paths into whole source-pack manifests"
    );
    assert!(
        !gpu_compiler_library_dependency_descriptor_worker.contains(".collect()")
            && !gpu_compiler_library_dependency_descriptor_worker
                .contains("Vec<ExplicitSourceLibraryPaths")
            && !gpu_compiler_library_dependency_descriptor_worker.contains(
                "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target("
            )
            && !gpu_compiler_library_dependency_descriptor_worker.contains(
                "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target("
            ),
        "GPU compiler many-library descriptor worker must not collect streamed library inputs or hide whole artifact preparation behind the worker run"
    );
    let gpu_compiler_library_dependency_descriptor_step = source_between(
        &compiler,
        "pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_with_gpu_descriptors_for_target",
        "pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors",
    );
    assert!(
        gpu_compiler_library_dependency_descriptor_step.contains(
            "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_work_queue_chunk_with_shard_limits_for_target("
        ),
        "GPU compiler many-library descriptor step must advance bounded persisted preparation before queue execution"
    );
    assert!(
        gpu_compiler_library_dependency_descriptor_step
            .contains("SourcePackFilesystemPreparedArtifactBuild::new(&artifact_root, target)")
            && gpu_compiler_library_dependency_descriptor_step
                .contains("submit_gpu_descriptor_work_queue_step_using("),
        "GPU compiler many-library descriptor step must advance exactly one item from a prepared persisted queue"
    );
    assert!(
        gpu_compiler_library_dependency_descriptor_step
            .contains("source_pack_work_queue_not_prepared_after_bounded_chunk_error("),
        "GPU compiler many-library descriptor step must stop after a bounded preparation chunk when the queue is not ready"
    );
    assert!(
        !gpu_compiler_library_dependency_descriptor_step.contains(
            "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target("
        ) && !gpu_compiler_library_dependency_descriptor_step.contains(
            "execute_source_pack_filesystem_work_queue_worker_run_async_with_path_artifacts_for_target("
        ) && !gpu_compiler_library_dependency_descriptor_step.contains(
            "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "GPU compiler many-library descriptor step must not enter a max-items worker run loop or full artifact preparation"
    );
    assert!(
        !gpu_compiler_library_dependency_descriptor_step
            .contains("load_explicit_source_libraries_from_paths(")
            && !gpu_compiler_library_dependency_descriptor_step
                .contains("load_explicit_source_pack_manifest_from_paths("),
        "GPU compiler many-library descriptor step must not load paths into whole source-pack manifests"
    );
    let gpu_compiler_library_dependency_prepare_chunk = source_between(
        &compiler,
        "fn prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_work_queue_chunk_with_shard_limits_for_target",
        "pub fn execute_explicit_source_libraries_filesystem_artifact_build",
    );
    assert!(
        gpu_compiler_library_dependency_prepare_chunk.contains(
            "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_for_target("
        ) && gpu_compiler_library_dependency_prepare_chunk.contains(
            "prepare_source_pack_filesystem_artifact_build_from_metadata_chunk_with_shard_limits_for_target("
        ) && gpu_compiler_library_dependency_prepare_chunk.contains(
            "SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT"
        ),
        "GPU compiler many-library descriptor preparation must route through bounded metadata/build chunk APIs"
    );
    assert!(
        !gpu_compiler_library_dependency_prepare_chunk.contains(
            "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target("
        ) && !gpu_compiler_library_dependency_prepare_chunk.contains(
            "source_pack_prepare_ordered_library_schedule_pages_from_explicit_source_library_path_dependency_streams("
        ),
        "GPU compiler many-library descriptor preparation chunk must not call whole schedule/artifact preparation"
    );
    let gpu_compiler_library_dependency_wasm_descriptor_worker = source_between(
        &compiler,
        "pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors",
        "pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_to_x86_64_with_gpu_descriptors",
    );
    assert!(
        gpu_compiler_library_dependency_wasm_descriptor_worker
            .contains("SourcePackArtifactTarget::Wasm"),
        "GPU compiler many-library WASM descriptor worker must select the WASM target"
    );
    let gpu_compiler_library_dependency_x86_descriptor_worker = source_between(
        &compiler,
        "pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_to_x86_64_with_gpu_descriptors",
        "pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_with_gpu_descriptors_for_target",
    );
    assert!(
        gpu_compiler_library_dependency_x86_descriptor_worker
            .contains("SourcePackArtifactTarget::X86_64"),
        "GPU compiler many-library x86 descriptor worker must select the x86 target"
    );
    let gpu_compiler_descriptor_worker = source_between(
        &compiler,
        "pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_with_gpu_descriptors_for_target",
        "pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors",
    );
    assert!(
        gpu_compiler_descriptor_worker.contains(
            "reject_raw_source_pack_paths_for_gpu_descriptor_worker(stdlib_paths, user_paths)?"
        ),
        "raw-path GPU compiler descriptor worker must reject direct source path inputs before descriptor execution"
    );
    assert!(
        gpu_compiler_descriptor_worker.contains(
            "execute_prepared_source_pack_filesystem_work_queue_worker_run_with_gpu_descriptors_for_target("
        ),
        "raw-path GPU compiler descriptor worker must execute only from already prepared artifact records"
    );
    assert!(
        !gpu_compiler_descriptor_worker
            .contains("GpuSourcePackArtifactExecutor::new(self, artifact_root.clone(), target)")
            && !gpu_compiler_descriptor_worker.contains(
                "execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target("
            ) && !gpu_compiler_descriptor_worker.contains(
                "prepare_explicit_source_pack_paths_filesystem_artifact_build"
            ),
        "raw-path GPU compiler descriptor worker must not prepare or execute raw path inputs inline"
    );
    assert!(
        !gpu_compiler_descriptor_worker.contains("load_explicit_source_pack_manifest_from_paths("),
        "GPU compiler descriptor worker must not load the whole source pack into memory"
    );
    assert!(
        !gpu_compiler_descriptor_worker.contains("compile_source_pack_manifest_to_wasm(")
            && !gpu_compiler_descriptor_worker.contains("compile_source_pack_manifest_to_x86_64("),
        "GPU compiler descriptor worker must not fall back to whole-pack compile helpers"
    );
    let gpu_compiler_descriptor_step = source_between(
        &compiler,
        "pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_with_gpu_descriptors_for_target",
        "pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors",
    );
    assert!(
        gpu_compiler_descriptor_step.contains(
            "reject_raw_source_pack_paths_for_gpu_descriptor_worker(stdlib_paths, user_paths)?"
        ),
        "raw-path GPU compiler descriptor step must reject direct source path inputs before descriptor execution"
    );
    assert!(
        gpu_compiler_descriptor_step.contains(
            "execute_prepared_source_pack_filesystem_work_queue_worker_step_with_gpu_descriptors_for_target("
        ),
        "raw-path GPU compiler descriptor step must advance exactly one already prepared queue item"
    );
    assert!(
        !gpu_compiler_descriptor_step.contains(
            "prepare_explicit_source_pack_paths_filesystem_artifact_build"
        ) && !gpu_compiler_descriptor_step.contains("submit_gpu_descriptor_work_queue_step_using(")
            && !gpu_compiler_descriptor_step.contains(
                "execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target("
            ) && !gpu_compiler_descriptor_step.contains(
                "execute_source_pack_filesystem_work_queue_worker_run_async_with_path_artifacts_for_target("
            ),
        "raw-path GPU compiler descriptor step must not prepare raw paths inline or enter a max-items worker run loop"
    );
    assert!(
        !gpu_compiler_descriptor_step.contains("load_explicit_source_pack_manifest_from_paths(")
            && !gpu_compiler_descriptor_step.contains("compile_source_pack_manifest_to_wasm(")
            && !gpu_compiler_descriptor_step.contains("compile_source_pack_manifest_to_x86_64("),
        "GPU compiler descriptor step must not fall back to whole-pack manifest loading or compile helpers"
    );
    let gpu_compiler_wasm_descriptor_worker = source_between(
        &compiler,
        "pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors",
        "pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_to_x86_64_with_gpu_descriptors",
    );
    assert!(
        gpu_compiler_wasm_descriptor_worker.contains("SourcePackArtifactTarget::Wasm"),
        "GPU compiler WASM descriptor worker must select the WASM target for persisted artifact records"
    );
    let gpu_compiler_x86_descriptor_worker = source_between(
        &compiler,
        "pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_to_x86_64_with_gpu_descriptors",
        "async fn compile_expanded_source_to_wasm",
    );
    assert!(
        gpu_compiler_x86_descriptor_worker.contains("SourcePackArtifactTarget::X86_64"),
        "GPU compiler x86 descriptor worker must select the x86 target for persisted artifact records"
    );
    let public_gpu_descriptor_workers = source_between_last(
        &compiler,
        "pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors<",
        "pub async fn compile_source_to_x86_64_with_gpu_codegen_using_path",
    );
    assert!(
        public_gpu_descriptor_workers.contains("global_wasm_gpu_compiler()?")
            && public_gpu_descriptor_workers.contains("global_x86_gpu_compiler()?"),
        "public GPU descriptor workers must expose target-specific global compiler entrypoints"
    );
    assert!(
        public_gpu_descriptor_workers.contains("_to_wasm_with_gpu_descriptors_using")
            && public_gpu_descriptor_workers.contains("_to_x86_64_with_gpu_descriptors_using"),
        "public GPU descriptor workers must also allow caller-owned compiler instances"
    );
    assert!(
        public_gpu_descriptor_workers
            .matches(
                "reject_raw_source_pack_paths_for_gpu_descriptor_worker(stdlib_paths, user_paths)?"
            )
            .count()
            >= 8
            && source_before(
                public_gpu_descriptor_workers,
                "reject_raw_source_pack_paths_for_gpu_descriptor_worker(stdlib_paths, user_paths)?",
                "global_wasm_gpu_compiler()?"
            )
            && source_before(
                public_gpu_descriptor_workers,
                "reject_raw_source_pack_paths_for_gpu_descriptor_worker(stdlib_paths, user_paths)?",
                "global_x86_gpu_compiler()?"
            ),
        "public raw-path GPU descriptor workers must reject raw path inputs before initializing target-specific GPU compilers or delegating to caller-owned compilers"
    );
    assert!(
        !public_gpu_descriptor_workers.contains("load_explicit_source_pack_manifest_from_paths("),
        "public GPU descriptor workers must not load path inputs into a whole source-pack manifest"
    );
    let public_prepared_gpu_descriptor_workers = source_between_last(
        &compiler,
        "pub async fn execute_prepared_source_pack_filesystem_work_queue_worker_run_to_wasm_with_gpu_descriptors(\n    artifact_root",
        "pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors<",
    );
    assert!(
        public_prepared_gpu_descriptor_workers.contains("global_wasm_gpu_compiler()?")
            && public_prepared_gpu_descriptor_workers.contains("global_x86_gpu_compiler()?"),
        "public prepared GPU descriptor workers must expose target-specific global compiler entrypoints"
    );
    assert!(
        public_prepared_gpu_descriptor_workers.contains("_to_wasm_with_gpu_descriptors_using")
            && public_prepared_gpu_descriptor_workers
                .contains("_to_x86_64_with_gpu_descriptors_using"),
        "public prepared GPU descriptor workers must also allow caller-owned compiler instances"
    );
    assert!(
        !public_prepared_gpu_descriptor_workers
            .contains("load_explicit_source_pack_manifest_from_paths(")
            && !public_prepared_gpu_descriptor_workers
                .contains("prepare_explicit_source_pack_paths_filesystem_artifact_build"),
        "public prepared GPU descriptor workers must not reprepare or load path inputs"
    );
    let public_library_path_stream_gpu_descriptor_workers = source_between_last(
        &compiler,
        "pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors<",
        "pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors<",
    );
    assert!(
        public_library_path_stream_gpu_descriptor_workers.contains("global_wasm_gpu_compiler()?")
            && public_library_path_stream_gpu_descriptor_workers
                .contains("global_x86_gpu_compiler()?"),
        "public ordered library path-stream GPU descriptor workers must expose target-specific global compiler entrypoints"
    );
    assert!(
        public_library_path_stream_gpu_descriptor_workers
            .contains("_to_wasm_with_gpu_descriptors_using")
            && public_library_path_stream_gpu_descriptor_workers
                .contains("_to_x86_64_with_gpu_descriptors_using"),
        "public ordered library path-stream GPU descriptor workers must also allow caller-owned compiler instances"
    );
    assert!(
        !public_library_path_stream_gpu_descriptor_workers
            .contains("load_explicit_source_libraries_from_paths(")
            && !public_library_path_stream_gpu_descriptor_workers
                .contains("load_explicit_source_pack_manifest_from_paths(")
            && !public_library_path_stream_gpu_descriptor_workers.contains(".collect()"),
        "public ordered library path-stream GPU descriptor workers must not whole-load or collect streamed library inputs"
    );
    let public_library_dependency_gpu_descriptor_workers = source_between_last(
        &compiler,
        "pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors<",
        "pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors<",
    );
    assert!(
        public_library_dependency_gpu_descriptor_workers.contains("global_wasm_gpu_compiler()?")
            && public_library_dependency_gpu_descriptor_workers
                .contains("global_x86_gpu_compiler()?"),
        "public many-library GPU descriptor workers must expose target-specific global compiler entrypoints"
    );
    assert!(
        public_library_dependency_gpu_descriptor_workers
            .contains("_to_wasm_with_gpu_descriptors_using")
            && public_library_dependency_gpu_descriptor_workers
                .contains("_to_x86_64_with_gpu_descriptors_using"),
        "public many-library GPU descriptor workers must also allow caller-owned compiler instances"
    );
    assert!(
        !public_library_dependency_gpu_descriptor_workers
            .contains("load_explicit_source_libraries_from_paths(")
            && !public_library_dependency_gpu_descriptor_workers
                .contains("load_explicit_source_pack_manifest_from_paths(")
            && !public_library_dependency_gpu_descriptor_workers.contains(".collect()"),
        "public many-library GPU descriptor workers must not whole-load or collect streamed library inputs"
    );
    let pack_path_streams_metadata_prepare = source_between(
        &compiler,
        "pub fn prepare_explicit_source_pack_path_streams_filesystem_metadata_for_target",
        "pub fn prepare_explicit_source_pack_paths_filesystem_metadata_for_target",
    );
    assert!(
        pack_path_streams_metadata_prepare.contains("ExplicitSourceLibraryPathDependencyStream"),
        "stdlib/user path-stream filesystem metadata prepare must route through path+dependency streams"
    );
    assert!(
        pack_path_streams_metadata_prepare.contains(
            "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_for_target("
        ),
        "stdlib/user path-stream filesystem metadata prepare must use the ordered streaming metadata stage"
    );
    assert!(
        !pack_path_streams_metadata_prepare.contains(".to_path_buf()"),
        "stdlib/user path-stream filesystem metadata prepare must not clone every input path before streaming"
    );
    assert!(
        !pack_path_streams_metadata_prepare.contains(".collect()"),
        "stdlib/user path-stream filesystem metadata prepare must not collect input paths into Vec libraries"
    );
    assert!(
        !pack_path_streams_metadata_prepare
            .contains("prepare_explicit_source_libraries_filesystem_metadata_for_target("),
        "stdlib/user path-stream filesystem metadata prepare must not re-enter the whole-Vec metadata planner"
    );
    let pack_paths_metadata_prepare = source_between(
        &compiler,
        "pub fn prepare_explicit_source_pack_paths_filesystem_metadata_for_target",
        "pub fn prepare_ordered_explicit_source_libraries_filesystem_metadata",
    );
    assert!(
        pack_paths_metadata_prepare
            .contains("prepare_explicit_source_pack_path_streams_filesystem_metadata_for_target("),
        "stdlib/user filesystem metadata prepare must delegate to the path-stream metadata prepare path"
    );
    assert!(
        !pack_paths_metadata_prepare.contains("ExplicitSourceLibraryPathDependencyStream"),
        "stdlib/user slice filesystem metadata prepare must not duplicate stream lowering"
    );
    assert!(
        !pack_paths_metadata_prepare.contains(".to_path_buf()"),
        "stdlib/user filesystem metadata prepare must not clone every input path before streaming"
    );
    assert!(
        !pack_paths_metadata_prepare.contains(".collect()"),
        "stdlib/user filesystem metadata prepare must not collect input path slices into Vec libraries"
    );
    assert!(
        !pack_paths_metadata_prepare
            .contains("prepare_explicit_source_libraries_filesystem_metadata_for_target("),
        "stdlib/user filesystem metadata prepare must not re-enter the whole-Vec metadata planner"
    );

    let ordered_metadata_entrypoint = source_between(
        &compiler,
        "pub fn prepare_ordered_explicit_source_libraries_filesystem_metadata_for_target",
        "pub fn prepare_explicit_source_libraries_filesystem_metadata",
    );
    assert!(
        ordered_metadata_entrypoint.contains(
            "source_pack_prepare_ordered_library_metadata_pages_from_explicit_source_libraries("
        ),
        "ordered filesystem metadata entrypoint must use the streaming ordered metadata prepare stage"
    );
    assert!(
        !ordered_metadata_entrypoint.contains("validate_explicit_source_library_entries("),
        "ordered filesystem metadata entrypoint must not use the whole-Vec topological planner"
    );
    let ordered_path_dependency_stream_metadata_entrypoint = source_between(
        &compiler,
        "pub fn prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_for_target",
        "pub fn prepare_explicit_source_libraries_filesystem_metadata",
    );
    assert!(
        ordered_path_dependency_stream_metadata_entrypoint.contains(
            "source_pack_prepare_ordered_library_metadata_pages_from_explicit_source_library_path_dependency_streams("
        ),
        "ordered path+dependency-stream filesystem metadata entrypoint must prepare directly from streams"
    );
    assert!(
        !ordered_path_dependency_stream_metadata_entrypoint.contains(
            "source_pack_prepare_ordered_library_metadata_pages_from_explicit_source_libraries("
        ),
        "ordered path+dependency-stream filesystem metadata entrypoint must not round-trip through Vec library wrappers"
    );

    let work_queue_completion = source_between(
        &compiler,
        "pub fn source_pack_filesystem_work_queue_record_claimed_item_complete_for_target_at",
        "pub fn execute_source_pack_filesystem_work_queue_claimed_artifact_item",
    );
    assert!(
        work_queue_completion
            .contains("source_pack_work_queue_record_work_item_dependents_dependency_completed("),
        "filesystem source-pack work-queue completion must delegate dependent progress updates"
    );
    assert!(
        !work_queue_completion.contains("source_pack_for_each_work_queue_dependent_item("),
        "filesystem source-pack work-queue completion must not expand ranged dependent records"
    );
    let work_queue_dependent_progress_update = source_between(
        &compiler,
        "fn source_pack_work_queue_record_work_item_dependents_dependency_completed",
        "fn source_pack_work_queue_record_dependent_completed_for_release_candidate",
    );
    assert!(
        work_queue_dependent_progress_update
            .contains("load_work_queue_dependents_page_for_target(")
            && work_queue_dependent_progress_update
                .contains("source_pack_work_queue_record_dependent_dependency_completed(")
            && work_queue_dependent_progress_update
                .contains("source_pack_work_queue_record_dependent_range_dependency_completed("),
        "filesystem source-pack work-queue completion must consume paged and ranged dependent records through persisted progress counters"
    );
    assert!(
        !work_queue_dependent_progress_update
            .contains("source_pack_for_each_work_queue_dependent_item("),
        "filesystem source-pack dependent progress updates must not expand ranged dependent records through the generic iterator"
    );
    assert!(
        work_queue_dependent_progress_update
            .contains("source_pack_work_queue_record_dependent_dependency_completed("),
        "filesystem source-pack work-queue completion must check readiness through persisted dependency progress"
    );
    let stored_work_queue_prepare = source_between(
        &compiler,
        "fn store_source_pack_work_queue_pages_from_stored_schedule_pages_chunk",
        "fn source_pack_store_work_queue_prepare_progress",
    );
    assert!(
        stored_work_queue_prepare.contains("SourcePackWorkQueuePrepareProgress")
            && stored_work_queue_prepare.contains("progress.next_item_index")
            && stored_work_queue_prepare.contains("max_new_items")
            && stored_work_queue_prepare
                .contains("source_pack_store_work_queue_page_for_stored_item_index(")
            && stored_work_queue_prepare.contains("let mut work_queue_index_path = None"),
        "stored work-queue preparation must advance through persisted work items in bounded chunks"
    );
    assert!(
        !work_queue_completion.contains("source_pack_work_queue_item_dependencies_completed("),
        "filesystem source-pack work-queue completion must not rescan dependent dependency records directly"
    );
    assert!(
        work_queue_completion.contains("store.store_work_queue_progress_page(&changed_pages[0])?"),
        "filesystem source-pack work-queue completion must flush each changed progress page"
    );
    assert!(
        !work_queue_completion.contains("progress_pages"),
        "filesystem source-pack work-queue completion must not retain an unbounded changed-page cache"
    );
    let batch_ready_frontier_update = source_between(
        &compiler,
        "fn source_pack_update_ready_frontier_after_batch_completion_bounded",
        "fn store_source_pack_build_state_progress_shards",
    );
    assert!(
        batch_ready_frontier_update
            .contains("source_pack_for_each_stored_job_batch_dependency_index("),
        "filesystem source-pack ready frontier updates must consume stored forward dependency pages"
    );
    let build_state_progress_store = source_between(
        &compiler,
        "fn store_source_pack_build_state_progress_shards",
        "fn validate_source_pack_completed_batch_artifacts_from_execution_shard",
    );
    assert!(
        build_state_progress_store.contains("load_build_progress_summary_for_target(target)")
            && build_state_progress_store.contains("state.completed_batch_count")
            && build_state_progress_store.contains("state.claimed_batch_count"),
        "filesystem source-pack build-state storage must validate compact counts against persisted progress summaries"
    );
    assert!(
        !build_state_progress_store.contains("source_pack_execution_shard_for_batch_locator(")
            && !build_state_progress_store
                .contains("source_pack_update_ready_frontier_after_batch_completion_bounded("),
        "filesystem source-pack build-state storage must not replay caller-provided batch arrays into progress shards"
    );
    assert!(
        !build_state_progress_store
            .contains("source_pack_for_each_job_batch_artifact_shard_from_index("),
        "filesystem source-pack legacy build-state replay must not scan every artifact shard"
    );
    let build_state_store = source_between(
        &compiler,
        "pub fn store_build_state_for_target",
        "fn store_build_state_marker_for_target",
    );
    assert!(
        !build_state_store.contains("load_build_artifact_shard_index_for_target("),
        "filesystem source-pack build-state store must not load the global artifact shard index"
    );

    let ordered_prepare = source_between(
        &compiler,
        "fn source_pack_prepare_ordered_library_schedule_pages_from_explicit_source_libraries",
        "fn source_pack_prepare_library_schedule_pages_from_stored_metadata_chunk",
    );
    assert!(
        ordered_prepare.contains("store_source_pack_library_source_file_record_pages_from_paths("),
        "ordered filesystem source-pack prepare must stream source metadata directly into per-file pages"
    );
    assert!(
        ordered_prepare.contains("source_pack_compact_library_source_file_page_from_partition("),
        "ordered filesystem source-pack prepare must write compact source-file pages from partition metadata"
    );
    assert!(
        ordered_prepare.contains(
            "store_source_pack_library_frontend_unit_pages_from_stored_source_file_records("
        ),
        "ordered filesystem source-pack prepare must stream stored source-file records into per-frontend-unit pages"
    );
    assert!(
        ordered_prepare.contains(
            "store_source_pack_library_codegen_unit_pages_from_stored_source_file_records("
        ),
        "ordered filesystem source-pack prepare must stream stored source-file records into per-codegen-unit pages"
    );
    assert!(
        ordered_prepare.contains(
            "source_pack_compact_library_build_unit_page_from_stored_source_file_records("
        ),
        "ordered filesystem source-pack prepare must build compact build-unit pages without retaining per-library codegen-unit vectors"
    );
    assert!(
        !ordered_prepare.contains("let mut source_files = Vec::with_capacity(library.paths.len())"),
        "ordered filesystem source-pack prepare must not retain every source-file metadata record for a library"
    );
    assert!(
        !ordered_prepare.contains("SourcePackLibrarySourceFilePage {\n            version: SOURCE_PACK_LIBRARY_SOURCE_FILE_PAGE_VERSION"),
        "ordered filesystem source-pack prepare must not build inline source-file pages"
    );
    assert!(
        !ordered_prepare.contains("source_pack_library_build_unit_page("),
        "ordered filesystem source-pack prepare must not build whole-library inline codegen-unit pages"
    );
    assert!(
        ordered_prepare.contains(
            "source_pack_library_schedule_page_with_stored_codegen_units_from_partition_dependencies("
        ),
        "ordered filesystem source-pack prepare must stream dependency records while building schedule pages from stored codegen-unit pages"
    );
    assert!(
        ordered_prepare.contains("let library_schedule_index = SourcePackLibraryScheduleIndex")
            && !ordered_prepare.contains("entries:")
            && ordered_prepare
                .contains("store.store_library_schedule_index(&library_schedule_index)"),
        "ordered filesystem source-pack prepare must persist a compact schedule index instead of retaining schedule entries"
    );
    assert!(
        !ordered_prepare.contains("source_pack_load_library_dependency_ids("),
        "ordered filesystem source-pack prepare must not materialize every library dependency id"
    );
    assert!(
        !ordered_prepare.contains("source_pack_library_frontend_job_indices_from_stored_locators("),
        "ordered filesystem source-pack prepare must not materialize every dependency frontend job"
    );
    assert!(
        !ordered_prepare.contains("source_pack_library_schedule_page_with_dependency_jobs("),
        "ordered filesystem source-pack prepare must not materialize every codegen job in one schedule page"
    );
    assert!(
        !ordered_prepare.contains("frontend_job_index_by_library_id"),
        "ordered filesystem source-pack prepare must not keep a global library-id frontend-job map"
    );
    assert!(
        !ordered_prepare.contains("seen_library_ids"),
        "ordered filesystem source-pack prepare must validate prior libraries through stored locator pages"
    );
    let unordered_prepare_entrypoint = source_between(
        &compiler,
        "pub fn prepare_explicit_source_libraries_filesystem_artifact_build_for_target",
        "pub fn prepare_ordered_explicit_source_libraries_filesystem_artifact_build",
    );
    assert!(
        unordered_prepare_entrypoint.contains(
            "source_pack_ordered_library_path_dependency_streams_from_explicit_source_libraries("
        ) && unordered_prepare_entrypoint.contains(
                "source_pack_prepare_ordered_library_schedule_pages_from_explicit_source_library_path_dependency_streams("
            ),
        "unordered filesystem source-pack prepare must topologically order metadata, then enter the bounded path+dependency-stream scheduler"
    );
    assert!(
        !unordered_prepare_entrypoint
            .contains("source_pack_prepare_library_schedule_pages_from_explicit_source_libraries("),
        "unordered filesystem source-pack prepare must not use the duplicate whole-Vec schedule-page planner"
    );

    let unordered_path_dependency_streams = source_between(
        &compiler,
        "fn source_pack_ordered_library_path_dependency_streams_from_explicit_source_libraries",
        "fn source_pack_prepare_ordered_library_metadata_pages_from_explicit_source_libraries",
    );
    assert!(
        unordered_path_dependency_streams.contains("validate_explicit_source_library_entries(")
            && unordered_path_dependency_streams
                .contains("ExplicitSourceLibraryPathDependencyStream")
            && unordered_path_dependency_streams
                .contains("dependency_library_count: dependency_library_ids.len()"),
        "unordered filesystem source-pack helper must validate metadata and emit bounded path+dependency stream records"
    );
    assert!(
        unordered_path_dependency_streams.contains("paths: library.paths")
            && unordered_path_dependency_streams.contains("dependency_library_ids"),
        "unordered filesystem source-pack prepare must convert library metadata into path and dependency streams without reading source files"
    );

    let inline_build_unit = source_between(
        &compiler,
        "fn source_pack_library_build_unit_page",
        "fn source_pack_source_file_unit_input_from_record",
    );
    assert!(
        inline_build_unit.contains("SourcePackJobPlan::from_file_stream_with_dependencies("),
        "inline build-unit pages must consume source-file page records through the one-pass job planner"
    );
    assert!(
        inline_build_unit.contains("SourceFileUnitInput {"),
        "inline build-unit pages must convert source-file records into SourceFileUnitInput records"
    );
    assert!(
        !inline_build_unit.contains("let source_file_inputs ="),
        "inline build-unit pages must not collect every SourceFileUnitInput before planning"
    );
    assert!(
        !inline_build_unit.contains("LibraryUnitPlan::from_files(&source_file_inputs)"),
        "inline build-unit pages must not plan frontend units from a collected input vector"
    );
    assert!(
        !inline_build_unit.contains("CodegenUnitPlan::from_files(&source_file_inputs"),
        "inline build-unit pages must not plan codegen units from a collected input vector"
    );

    let compact_build_unit = source_between(
        &compiler,
        "fn source_pack_compact_library_build_unit_page_from_stored_source_file_records",
        "fn source_pack_library_build_unit_page_codegen_unit_count",
    );
    assert!(
        compact_build_unit
            .contains("source_pack_summarize_library_build_units_from_stored_source_file_records("),
        "compact build-unit pages must summarize frontend metadata and codegen-unit count from one stored-record stream"
    );
    let stored_build_unit_summary = source_between(
        &compiler,
        "fn source_pack_summarize_library_build_units_from_stored_source_file_records",
        "fn source_pack_compact_library_build_unit_page_from_stored_source_file_records",
    );
    assert!(
        stored_build_unit_summary.contains("CodegenUnitPlan::try_for_each_from_fallible_files("),
        "stored build-unit summaries must consume source-file record pages through the bounded codegen-unit iterator"
    );
    assert!(
        stored_build_unit_summary.contains("FrontendUnitPlan::try_for_each_from_fallible_files("),
        "stored build-unit summaries must consume source-file record pages through the bounded frontend-unit iterator"
    );
    assert!(
        stored_build_unit_summary.contains("summary_builder.record_codegen_unit(&unit)"),
        "stored build-unit summaries must derive library metadata from emitted codegen-unit records"
    );
    let stored_frontend_unit_pages = source_between(
        &compiler,
        "fn store_source_pack_library_frontend_unit_pages_from_stored_source_file_records",
        "fn store_source_pack_library_codegen_unit_pages_from_stored_source_file_records",
    );
    assert!(
        stored_frontend_unit_pages.contains("FrontendUnitPlan::try_for_each_from_fallible_files("),
        "stored frontend-unit page construction must consume source-file record pages through the bounded frontend-unit iterator"
    );
    assert!(
        stored_frontend_unit_pages.contains("store.store_library_frontend_unit_page(&page)?"),
        "stored frontend-unit page construction must persist each bounded frontend-unit page"
    );
    assert!(
        !compiler.contains("fn source_pack_library_frontend_unit_from_stored_source_file_records"),
        "compact build-unit page construction must not reread stored source-file records only to build frontend metadata"
    );
    assert!(
        !compiler
            .contains("fn source_pack_count_library_codegen_units_from_stored_source_file_records"),
        "compact build-unit page construction must not keep a separate stored-record count pass"
    );

    let stored_codegen_schedule = source_between(
        &compiler,
        "fn source_pack_library_schedule_page_with_stored_codegen_units",
        "fn source_pack_frontend_job_from_unit",
    );
    assert!(
        stored_codegen_schedule.contains("load_library_codegen_unit_page_for_target("),
        "stored schedule-page construction must consume per-codegen-unit pages"
    );
    assert!(
        stored_codegen_schedule.contains("load_library_frontend_unit_page_for_target("),
        "stored schedule-page construction must consume per-frontend-unit pages"
    );
    assert!(
        stored_codegen_schedule.contains("frontend_job_count"),
        "stored schedule-page construction must schedule all bounded frontend-unit jobs"
    );
    assert!(
        stored_codegen_schedule.contains("owning_frontend_job_index"),
        "stored codegen jobs must depend on the owning bounded frontend-unit job"
    );
    assert!(
        compiler.contains("source_pack_write_library_dependency_frontend_job_ranges("),
        "stored schedule-page construction must stream partition dependency pages into compact schedule dependency ranges"
    );
    assert!(
        stored_codegen_schedule.contains("store_source_pack_library_schedule_codegen_job_locator("),
        "stored schedule-page construction must emit per-job schedule locators from codegen-unit pages"
    );
    assert!(
        stored_codegen_schedule
            .contains("store_source_pack_library_schedule_job_page_with_dependency_writer("),
        "stored schedule-page construction must stream schedule dependency pages without materializing full dependency vectors"
    );
    assert!(
        compiler.contains("store_source_pack_library_dependency_pages("),
        "stored partition pages must store library dependency records in bounded pages"
    );
    assert!(
        compiler.contains("load_library_dependency_page_for_target("),
        "stored partition dependency lookup must load bounded dependency pages"
    );
    assert!(
        compiler.contains("stored_page.dependency_library_ids.clear()"),
        "stored build/schedule pages must not duplicate partition dependency libraries"
    );
    assert!(
        compiler.contains("store_source_pack_library_schedule_job_dependency_pages("),
        "stored schedule-job pages must store dependency job records in bounded pages"
    );
    assert!(
        compiler.contains("source_pack_load_schedule_job_dependencies("),
        "stored schedule-job lookup must hydrate dependencies from dependency pages"
    );
    assert!(
        compiler.contains("source_pack_for_each_stored_schedule_frontend_job("),
        "stored schedule-page consumers must load bounded frontend metadata from per-job pages"
    );
    assert!(
        stored_codegen_schedule.contains("page.frontend_job.dependency_job_indices.clear()"),
        "stored schedule pages must not embed unbounded frontend dependency jobs"
    );
    assert!(
        !stored_codegen_schedule.contains(".codegen_units.iter()"),
        "stored schedule-page construction must not iterate inline build-unit codegen vectors"
    );

    let stored_execution_shard = source_between(
        &compiler,
        "fn source_pack_build_artifact_execution_shard_from_stored_pages",
        "fn source_pack_stored_source_file_for_index",
    );
    assert!(
        stored_execution_shard.contains("source_files: Vec::new()"),
        "stored execution shards must not duplicate source-file records from source-file pages"
    );
    assert!(
        stored_execution_shard.contains("source_pack_stored_schedule_job_metadata("),
        "stored execution shards must load schedule job metadata without hydrating dependency vectors"
    );
    assert!(
        !stored_execution_shard.contains("source_pack_stored_schedule_job("),
        "stored execution shards must not materialize schedule job dependency vectors"
    );
    assert!(
        !stored_execution_shard.contains("source_file_page_cache"),
        "stored execution shard construction must not cache source-file pages to clone them into shards"
    );
    assert!(
        !stored_execution_shard.contains("source_file_indices"),
        "stored execution shard construction must not accumulate every source-file index in the shard"
    );
    let stored_job_artifacts = source_between(
        &compiler,
        "fn source_pack_job_artifact_manifest_from_stored_artifact_refs",
        "struct SourcePackJobArtifactInputInterfacePageWriter",
    );
    assert!(
        stored_job_artifacts.contains(
            "store_source_pack_job_artifact_input_interface_pages_from_stored_schedule_dependencies("
        ),
        "stored job artifact manifests must page input interface refs from streamed schedule dependencies"
    );
    assert!(
        !stored_job_artifacts.contains("&job.dependency_job_indices"),
        "stored job artifact manifests must not read hydrated job dependency vectors"
    );
    assert!(
        !stored_job_artifacts
            .contains("source_pack_interface_output_refs_for_stored_schedule_job_dependencies("),
        "stored job artifact manifests must not embed all dependency interface refs"
    );
    let stored_dependency_artifact_ref_pages = source_between(
        &compiler,
        "fn store_source_pack_job_artifact_input_interface_pages_from_stored_schedule_dependencies",
        "fn source_pack_compact_path_build_manifest_from_stored_indexes",
    );
    assert!(
        stored_dependency_artifact_ref_pages
            .contains("source_pack_for_each_schedule_job_explicit_dependency_index(")
            && stored_dependency_artifact_ref_pages.contains(".dependency_job_ranges"),
        "stored dependency artifact-ref pages must stream explicit schedule dependency pages and retain compact dependency ranges"
    );
    let compact_path_manifest = source_between(
        &compiler,
        "fn source_pack_compact_path_build_manifest_from_stored_indexes",
        "fn source_pack_work_queue_artifact_item_count_from_pages",
    );
    assert!(
        compact_path_manifest.contains("source_line_count: usize")
            && compact_path_manifest.contains("source_line_count,")
            && compact_path_manifest.contains("source_files: Vec::new()")
            && compact_path_manifest.contains("library_dependencies: Vec::new()"),
        "compact path build manifests must preserve source-line totals while leaving source-file and dependency records paged"
    );
    let execution_job_runner = source_between(
        &compiler,
        "fn execute_source_pack_build_artifact_execution_shard_job",
        "fn execute_source_pack_build_artifact_execution_shard_link_job",
    );
    assert!(
        execution_job_runner.contains("source_pack_execution_shard_job_input_interface_refs("),
        "legacy stored execution must load only bounded inline job interface inputs through the legacy helper"
    );
    let legacy_input_loader = source_between(
        &compiler,
        "fn source_pack_execution_shard_job_input_interface_refs",
        "\nfn source_pack_execution_shard_job_input_interface_ref<S>",
    );
    assert!(
        legacy_input_loader.contains("paged or ranged interface inputs must use paged execution")
            && !legacy_input_loader.contains("load_job_artifact_input_interface_page(")
            && !legacy_input_loader.contains("source_pack_manifest_artifact_index_range_set(")
            && !legacy_input_loader
                .contains("Vec::with_capacity(job_manifest.input_interface_count)"),
        "legacy source-pack execution must reject paged dependency refs instead of rehydrating all inputs"
    );
    let paged_execution_job_runner = source_between(
        &compiler,
        "fn execute_source_pack_build_artifact_execution_shard_job_paged",
        "fn source_pack_execution_shard_job_input_interface_refs",
    );
    assert!(
        paged_execution_job_runner
            .contains("source_pack_for_each_execution_shard_job_input_interface_batch("),
        "paged source-pack execution must stream dependency interface batches"
    );
    assert!(
        !paged_execution_job_runner
            .contains("source_pack_execution_shard_job_input_interface_refs("),
        "paged source-pack execution must not hydrate every dependency interface ref"
    );
    assert!(
        !paged_execution_job_runner
            .contains("load_library_interface_artifacts(store, &dependency_interface_refs)"),
        "paged source-pack execution must not load all dependency interfaces into one Vec"
    );
    let paged_dependency_batch_loader = source_between(
        &compiler,
        "fn source_pack_for_each_execution_shard_job_input_interface_batch",
        "fn execute_source_pack_build_artifact_execution_shard_link_job",
    );
    assert!(
        !paged_dependency_batch_loader.contains(".cloned()\n                .collect::<Vec<_>>()"),
        "paged source-pack dependency batches must not clone artifact refs into temporary vectors"
    );
    let execution_link_job = source_between(
        &compiler,
        "fn execute_source_pack_build_artifact_execution_shard_link_job",
        "fn execute_source_pack_hierarchical_link_execution_page",
    );
    assert!(
        !execution_link_job
            .contains("let artifact_refs = source_pack_execution_shard_artifact_refs_for_indices("),
        "paged source-pack link execution must not build temporary artifact-ref vectors from shard indices"
    );
    let work_queue_claimed_item = source_between(
        &compiler,
        "pub fn execute_source_pack_filesystem_work_queue_claimed_item_for_target_at",
        "pub fn execute_source_pack_filesystem_work_queue_claimed_link_item",
    );
    assert!(
        work_queue_claimed_item.contains(
            "execute_source_pack_filesystem_work_queue_claimed_artifact_item_paged_for_target_at("
        ),
        "work-queue artifact items must use the paged artifact execution path"
    );
    assert!(
        !work_queue_claimed_item.contains(
            "execute_source_pack_filesystem_work_queue_claimed_artifact_item_for_target_at("
        ),
        "work-queue artifact items must not use the legacy whole-input artifact execution path"
    );
    let work_queue_claimed_artifact_item = source_between(
        &compiler,
        "pub fn execute_source_pack_filesystem_work_queue_claimed_artifact_item_for_target_at",
        "pub fn execute_source_pack_filesystem_work_queue_claimed_artifact_item_paged",
    );
    assert!(
        work_queue_claimed_artifact_item.contains(
            "execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_for_target_at("
        ),
        "direct work-queue artifact item execution must use the paged claimed-batch path"
    );
    assert!(
        !work_queue_claimed_artifact_item.contains(
            "execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_for_target_at("
        ),
        "direct work-queue artifact item execution must not use the legacy whole-input claimed-batch path"
    );
    let execution_source_files = source_between(
        &compiler,
        "fn source_pack_execution_shard_source_files_for_job",
        "fn source_pack_for_each_execution_shard_artifact_ref_for_indices",
    );
    assert!(
        execution_source_files.contains("store.load_source_files_for_range("),
        "compact execution shards must load job source files from persisted source-file records"
    );
    let stored_source_file_lookup = source_between(
        &compiler,
        "fn source_pack_stored_source_file_for_index",
        "fn source_pack_library_partition_for_source_index_from_stored_pages",
    );
    assert!(
        stored_source_file_lookup.contains("load_library_source_file_record_page_for_target("),
        "source-file lookup must read per-file records when source-file pages are compact"
    );
    assert!(
        stored_source_file_lookup.contains("page.source_files.is_empty()"),
        "source-file lookup must distinguish compact source-file pages from legacy inline pages"
    );

    let source_file_record_store = source_between(
        &compiler,
        "fn store_source_pack_library_source_file_record_pages_from_paths",
        "fn source_pack_compact_library_source_file_page_from_partition",
    );
    assert!(
        source_file_record_store.contains("SourcePackStoredSourceFileRecordTotals")
            && source_file_record_store.contains("source_line_count")
            && source_file_record_store.contains("file.line_count.unwrap_or(0)"),
        "filesystem source-file record storage must return bounded byte and source-line totals from per-file metadata"
    );

    let ordered_metadata_prepare = source_between(
        &compiler,
        "fn source_pack_prepare_ordered_library_metadata_pages_from_explicit_source_libraries",
        "fn source_pack_prepare_ordered_library_schedule_pages_from_explicit_source_libraries",
    );
    assert!(
        ordered_metadata_prepare
            .contains("store_source_pack_library_source_file_record_pages_from_paths("),
        "ordered filesystem metadata prepare must stream source metadata directly into per-file pages"
    );
    assert!(
        ordered_metadata_prepare
            .contains("source_pack_compact_library_source_file_page_from_partition("),
        "ordered filesystem metadata prepare must write compact source-file pages from partition metadata"
    );
    assert!(
        ordered_metadata_prepare.contains("source_line_count")
            && ordered_metadata_prepare.contains("partition_source_totals.source_line_count"),
        "ordered filesystem metadata prepare must preserve source-line totals in partition metadata"
    );
    assert!(
        !ordered_metadata_prepare
            .contains("let mut source_files = Vec::with_capacity(library.paths.len())"),
        "ordered filesystem metadata prepare must not retain every source-file metadata record for a library"
    );
    assert!(
        !ordered_metadata_prepare.contains("SourcePackLibrarySourceFilePage {\n            version: SOURCE_PACK_LIBRARY_SOURCE_FILE_PAGE_VERSION"),
        "ordered filesystem metadata prepare must not build inline source-file pages"
    );
    assert!(
        ordered_metadata_prepare.contains("store_source_pack_library_dependency_pages_from_ids("),
        "ordered filesystem metadata prepare must stream dependency ids into dependency pages"
    );
    assert!(
        ordered_metadata_prepare.contains("store.store_library_partition_locator_page("),
        "ordered filesystem metadata prepare must publish a bounded partition locator for each library"
    );
    let unordered_metadata_prepare = source_between(
        &compiler,
        "pub fn prepare_explicit_source_libraries_filesystem_metadata_for_target",
        "pub fn execute_explicit_source_libraries_filesystem_artifact_build",
    );
    assert!(
        unordered_metadata_prepare.contains(
            "source_pack_ordered_library_path_dependency_streams_from_explicit_source_libraries("
        ) && unordered_metadata_prepare.contains(
                "source_pack_prepare_ordered_library_metadata_pages_from_explicit_source_library_path_dependency_streams("
            ),
        "filesystem metadata prepare must route unordered libraries through the bounded path+dependency-stream metadata scheduler"
    );
    assert!(
        !unordered_metadata_prepare
            .contains("let mut source_files = Vec::with_capacity(library.paths.len())"),
        "filesystem metadata prepare must not retain every source-file metadata record for a library"
    );
    assert!(
        !unordered_metadata_prepare.contains("SourcePackLibrarySourceFilePage {\n            version: SOURCE_PACK_LIBRARY_SOURCE_FILE_PAGE_VERSION"),
        "filesystem metadata prepare must not build inline source-file pages"
    );
    assert!(
        !unordered_metadata_prepare.contains("dependency_library_ids: dependencies_by_library"),
        "filesystem metadata prepare must not inline dependency ids into partition metadata"
    );
    assert!(
        !ordered_metadata_prepare.contains("topological_library_ids"),
        "ordered filesystem metadata prepare must not require a complete topological library id vector"
    );
    assert!(
        !ordered_metadata_prepare.contains("remaining_libraries"),
        "ordered filesystem metadata prepare must not retain the whole library list for reordering"
    );
    assert!(
        !ordered_metadata_prepare.contains("seen_library_ids"),
        "ordered filesystem metadata prepare must validate duplicates through persisted locator pages"
    );
    let ordered_metadata_dependency_stream_prepare = source_between(
        &compiler,
        "fn source_pack_prepare_ordered_library_metadata_pages_from_explicit_source_library_path_dependency_streams",
        "fn source_pack_prepare_ordered_library_schedule_pages_from_explicit_source_libraries",
    );
    assert!(
        ordered_metadata_dependency_stream_prepare
            .contains("store_source_pack_library_source_file_record_pages_from_paths("),
        "ordered metadata path+dependency-stream prepare must stream source path metadata directly into per-file pages"
    );
    assert!(
        ordered_metadata_dependency_stream_prepare
            .contains("store_source_pack_library_dependency_pages_from_ids("),
        "ordered metadata path+dependency-stream prepare must write dependency pages directly from dependency streams"
    );
    assert!(
        ordered_metadata_dependency_stream_prepare.contains("dependency_library_ids: Vec::new()"),
        "ordered metadata path+dependency-stream prepare must keep partition dependency ids paged"
    );
    assert!(
        ordered_metadata_dependency_stream_prepare
            .contains("source_file_count: partition_source_file_count"),
        "ordered metadata path+dependency-stream prepare must use caller-provided source-file counts"
    );
    assert!(
        ordered_metadata_dependency_stream_prepare
            .contains("SOURCE_PACK_LIBRARY_METADATA_PREPARE_DEFAULT_SOURCE_FILE_LIMIT",)
            && ordered_metadata_dependency_stream_prepare
                .contains("SOURCE_PACK_LIBRARY_METADATA_PREPARE_DEFAULT_DEPENDENCY_LIMIT",)
            && ordered_metadata_dependency_stream_prepare
                .matches("source_pack_validate_metadata_chunk_new_library_counts(")
                .count()
                >= 3
            && source_before(
                ordered_metadata_dependency_stream_prepare,
                "source_pack_validate_metadata_chunk_new_library_counts(",
                "store_source_pack_library_dependency_pages_from_ids("
            ),
        "chunked ordered metadata prepare must reject oversized single-library source-file/dependency counts before writing dependency or source-file pages"
    );
    assert!(
        ordered_metadata_dependency_stream_prepare
            .contains("library_partition_index_path_for_target(target)")
            && ordered_metadata_dependency_stream_prepare
                .contains("load_library_partition_index_for_target(target)")
            && ordered_metadata_dependency_stream_prepare
                .contains("load_library_partition_locator_page_for_target(target, library_id)")
            && ordered_metadata_dependency_stream_prepare
                .contains("load_library_partition_for_target(target, locator.partition_index)")
            && ordered_metadata_dependency_stream_prepare
                .contains("source_pack_verify_stored_library_dependency_pages_match_ids(")
            && ordered_metadata_dependency_stream_prepare.contains("continue;"),
        "ordered metadata path+dependency-stream prepare must resume completed library-prefix metadata records before reading remaining source paths"
    );
    assert!(
        ordered_metadata_dependency_stream_prepare.contains("max_new_libraries")
            && ordered_metadata_dependency_stream_prepare.contains("new_library_count >= limit")
            && ordered_metadata_dependency_stream_prepare.contains("complete = false")
            && ordered_metadata_dependency_stream_prepare
                .contains("library_partition_index_path: None")
            && source_before(
                ordered_metadata_dependency_stream_prepare,
                "library_partition_index_path: None",
                "store.store_library_partition_compact_index"
            ),
        "ordered metadata path+dependency-stream prepare must be resumable in bounded chunks and must not write the compact partition index until all libraries are stored"
    );
    assert!(
        ordered_metadata_dependency_stream_prepare.contains(
            "Some(SOURCE_PACK_LIBRARY_METADATA_FULL_PREPARE_DEFAULT_LIBRARY_LIMIT)",
        ) && ordered_metadata_dependency_stream_prepare.contains("if !step.complete")
            && ordered_metadata_dependency_stream_prepare.contains(
                "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_for_target"
            ),
        "full ordered metadata convenience prepare must stop after a bounded library window and direct large inputs to chunked metadata APIs"
    );
    assert!(
        ordered_metadata_dependency_stream_prepare.contains("source_line_count")
            && ordered_metadata_dependency_stream_prepare
                .contains("partition_source_totals.source_line_count"),
        "ordered metadata path+dependency-stream prepare must preserve source-line totals in partition metadata"
    );
    assert!(
        !ordered_metadata_dependency_stream_prepare.contains("BTreeSet"),
        "ordered metadata path+dependency-stream prepare must not retain every dependency id in a set"
    );
    assert!(
        !ordered_metadata_dependency_stream_prepare.contains(".collect()"),
        "ordered metadata path+dependency-stream prepare must not collect dependency ids into a Vec"
    );
    assert!(
        !ordered_metadata_dependency_stream_prepare.contains("paths.len()"),
        "ordered metadata path+dependency-stream prepare must not require a collected path vector"
    );
    assert!(
        !ordered_metadata_dependency_stream_prepare.contains("topological_library_ids"),
        "ordered metadata path+dependency-stream prepare must not require a complete topological library id vector"
    );
    assert!(
        !ordered_metadata_dependency_stream_prepare.contains("remaining_libraries"),
        "ordered metadata path+dependency-stream prepare must not retain the whole library list for reordering"
    );
    let ordered_artifact_prepare = source_between(
        &compiler,
        "pub fn prepare_ordered_explicit_source_libraries_filesystem_artifact_build_for_target",
        "pub fn prepare_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits_for_target",
    );
    assert!(
        ordered_artifact_prepare.contains(
            "prepare_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "default ordered artifact prepare must delegate to the shard-limited prepare path"
    );
    assert!(
        ordered_artifact_prepare.contains("SourcePackBuildShardLimits::default()"),
        "default ordered artifact prepare must set only the default shard limits"
    );
    let ordered_artifact_prepare_with_shards = source_between(
        &compiler,
        "pub fn prepare_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits_for_target",
        "pub fn prepare_ordered_explicit_source_library_path_streams_filesystem_artifact_build",
    );
    assert!(
        ordered_artifact_prepare_with_shards.contains(
            "prepare_explicit_source_prepared_library_pages_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "shard-limited ordered artifact prepare must pass caller shard limits into persisted artifact preparation"
    );
    assert!(
        !ordered_artifact_prepare_with_shards.contains("SourcePackBuildShardLimits::default()"),
        "shard-limited ordered artifact prepare must not override caller shard limits"
    );
    let ordered_path_stream_prepare = source_between(
        &compiler,
        "fn source_pack_prepare_ordered_library_schedule_pages_from_explicit_source_library_path_streams",
        "fn store_source_pack_library_schedule_codegen_job_locator",
    );
    assert!(
        ordered_path_stream_prepare
            .contains("store_source_pack_library_source_file_record_pages_from_paths("),
        "ordered path-stream prepare must stream source path metadata directly into per-file pages"
    );
    assert!(
        ordered_path_stream_prepare.contains("source_file_count: partition_source_file_count"),
        "ordered path-stream prepare must use caller-provided source-file counts"
    );
    assert!(
        ordered_path_stream_prepare.contains("source_line_count")
            && ordered_path_stream_prepare.contains("partition_source_totals.source_line_count"),
        "ordered path-stream prepare must preserve source-line totals in partition metadata"
    );
    assert!(
        !ordered_path_stream_prepare.contains("paths.len()"),
        "ordered path-stream prepare must not require a collected path vector"
    );
    assert!(
        !ordered_path_stream_prepare.contains("topological_library_ids"),
        "ordered path-stream prepare must not require a complete topological library id vector"
    );
    assert!(
        !ordered_path_stream_prepare.contains("remaining_libraries"),
        "ordered path-stream prepare must not retain the whole library list for reordering"
    );
    let ordered_path_stream_artifact_prepare = source_between(
        &compiler,
        "pub fn prepare_ordered_explicit_source_library_path_streams_filesystem_artifact_build_for_target",
        "pub fn prepare_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits_for_target",
    );
    assert!(
        ordered_path_stream_artifact_prepare.contains(
            "prepare_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "default ordered path-stream artifact prepare must delegate to the shard-limited prepare path"
    );
    assert!(
        ordered_path_stream_artifact_prepare.contains("SourcePackBuildShardLimits::default()"),
        "default ordered path-stream artifact prepare must set only the default shard limits"
    );
    let ordered_path_stream_artifact_prepare_with_shards = source_between(
        &compiler,
        "pub fn prepare_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits_for_target",
        "pub fn prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build",
    );
    assert!(
        ordered_path_stream_artifact_prepare_with_shards.contains(
            "prepare_explicit_source_prepared_library_pages_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "shard-limited ordered path-stream artifact prepare must pass caller shard limits into persisted artifact preparation"
    );
    assert!(
        !ordered_path_stream_artifact_prepare_with_shards
            .contains("SourcePackBuildShardLimits::default()"),
        "shard-limited ordered path-stream artifact prepare must not override caller shard limits"
    );
    let ordered_path_dependency_stream_prepare = source_between(
        &compiler,
        "fn source_pack_prepare_ordered_library_schedule_pages_from_explicit_source_library_path_dependency_streams",
        "fn store_source_pack_library_schedule_codegen_job_locator",
    );
    assert!(
        ordered_path_dependency_stream_prepare
            .contains("store_source_pack_library_dependency_pages_from_ids("),
        "ordered path+dependency-stream prepare must write dependency pages directly from dependency streams"
    );
    assert!(
        ordered_path_dependency_stream_prepare.contains("dependency_library_ids: Vec::new()"),
        "ordered path+dependency-stream prepare must keep partition dependency ids paged"
    );
    assert!(
        !ordered_path_dependency_stream_prepare.contains("BTreeSet"),
        "ordered path+dependency-stream prepare must not retain every dependency id in a set"
    );
    assert!(
        !ordered_path_dependency_stream_prepare.contains(".collect()"),
        "ordered path+dependency-stream prepare must not collect dependency ids into a Vec"
    );
    let ordered_path_dependency_artifact_prepare = source_between(
        &compiler,
        "pub fn prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_for_target",
        "pub fn prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target",
    );
    assert!(
        ordered_path_dependency_artifact_prepare.contains(
            "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "default ordered path+dependency-stream artifact prepare must delegate to the shard-limited prepare path"
    );
    assert!(
        ordered_path_dependency_artifact_prepare.contains("SourcePackBuildShardLimits::default()"),
        "default ordered path+dependency-stream artifact prepare must set only the default shard limits"
    );
    let ordered_path_dependency_artifact_prepare_with_shards = source_between(
        &compiler,
        "pub fn prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target",
        "pub fn prepare_explicit_source_pack_paths_filesystem_metadata",
    );
    assert!(
        ordered_path_dependency_artifact_prepare_with_shards.contains(
            "prepare_explicit_source_prepared_library_pages_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "shard-limited ordered path+dependency-stream artifact prepare must pass caller shard limits into persisted artifact preparation"
    );
    assert!(
        !ordered_path_dependency_artifact_prepare_with_shards
            .contains("SourcePackBuildShardLimits::default()"),
        "shard-limited ordered path+dependency-stream artifact prepare must not override caller shard limits"
    );
    let prepared_pages_artifact_prepare_with_shards = source_between(
        &compiler,
        "fn prepare_explicit_source_prepared_library_pages_filesystem_artifact_build_with_shard_limits_for_target",
        "pub fn execute_source_pack_filesystem_artifact_manifest_build",
    );
    assert!(
        prepared_pages_artifact_prepare_with_shards
            .contains("validate_source_pack_library_partition_index(")
            && prepared_pages_artifact_prepare_with_shards
                .contains("validate_source_pack_library_schedule_index("),
        "prepared library pages must validate the persisted partition and schedule indexes before artifact preparation"
    );
    assert!(
        prepared_pages_artifact_prepare_with_shards.contains(
            "for _ in 0..SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_FULL_PREPARE_DEFAULT_STEP_LIMIT"
        ) && prepared_pages_artifact_prepare_with_shards.contains(
            "prepare_source_pack_filesystem_artifact_build_from_metadata_chunk_with_shard_limits_for_target("
        ) && prepared_pages_artifact_prepare_with_shards.contains(
            "SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT"
        ),
        "prepared library pages must finish artifact preparation through bounded persisted chunk steps"
    );
    for forbidden in [
        "store_source_pack_build_artifact_ref_pages_from_stored_schedule_pages(",
        "store_source_pack_build_job_batch_pages_from_stored_schedule_pages(",
        "store_source_pack_build_link_batch_pages_from_stored_artifact_ref_pages(",
        "store_source_pack_hierarchical_link_plan_from_stored_schedule_pages(",
        "store_source_pack_hierarchical_link_execution_from_stored_schedule_pages(",
        "store_source_pack_work_queue_from_stored_schedule_pages(",
        "store_source_pack_build_artifact_shards_from_page_metadata(",
        "source_pack_compact_path_build_manifest_from_stored_indexes(",
        "source_pack_library_schedule_plan(",
        "source_pack_hierarchical_link_plan(",
        "source_pack_hierarchical_link_execution_plan(",
        "source_pack_work_queue(",
        "SourcePackBuildPlan::",
        "SourcePackArtifactPlan::",
        "load_explicit_source_pack_manifest_from_paths(",
        "load_build_artifact_manifest",
        "load_work_queue_index_for_target",
    ] {
        assert!(
            !prepared_pages_artifact_prepare_with_shards.contains(forbidden),
            "prepared library pages must not hydrate whole source-pack plans or manifests via {forbidden:?}"
        );
    }
    assert!(
        prepared_pages_artifact_prepare_with_shards.contains("shard_limits"),
        "prepared library pages must pass caller-provided shard limits into persisted chunk preparation"
    );
    let schedule_from_stored_metadata = source_between(
        &compiler,
        "fn source_pack_prepare_library_schedule_pages_from_stored_metadata",
        "fn store_source_pack_library_schedule_codegen_job_locator",
    );
    assert!(
        schedule_from_stored_metadata
            .contains("store.load_library_partition_index_for_target(target)?")
            && schedule_from_stored_metadata
                .contains("store.load_library_partition_for_target(target, partition_index)?")
            && schedule_from_stored_metadata
                .contains("store.load_library_source_file_page_for_target(target, partition_index)?")
            && schedule_from_stored_metadata
                .contains("source_pack_validate_source_file_page_matches_partition(")
            && schedule_from_stored_metadata.contains(
                "source_pack_compact_library_build_unit_page_from_stored_source_file_records("
            )
            && schedule_from_stored_metadata.contains(
                "source_pack_library_schedule_page_with_stored_codegen_units_from_partition_dependencies("
            )
            && schedule_from_stored_metadata.contains("store.store_library_schedule_page(&page)?"),
        "stored-metadata schedule prepare must consume persisted partition/source-file/dependency pages"
    );
    assert!(
        !schedule_from_stored_metadata.contains("read_explicit_source_path_metadata")
            && !schedule_from_stored_metadata
                .contains("store_source_pack_library_source_file_record_pages_from_paths(")
            && !schedule_from_stored_metadata.contains("ExplicitSourceLibraryPath"),
        "stored-metadata schedule prepare must not re-read path metadata or require source path streams"
    );
    let schedule_from_stored_metadata_chunk = source_between(
        &compiler,
        "fn source_pack_prepare_library_schedule_pages_from_stored_metadata_chunk",
        "fn source_pack_validate_build_unit_page_matches_partition",
    );
    assert!(
        schedule_from_stored_metadata_chunk
            .contains("library_build_unit_page_path_for_target(target, partition_index)")
            && schedule_from_stored_metadata_chunk.contains("new_library_build_unit_page_count")
            && schedule_from_stored_metadata_chunk.contains("new_library_schedule_page_count")
            && schedule_from_stored_metadata_chunk.contains("max_new_libraries")
            && schedule_from_stored_metadata_chunk
                .contains("load_library_schedule_prepare_progress_for_target(")
            && schedule_from_stored_metadata_chunk
                .contains("store_library_schedule_prepare_progress(")
            && schedule_from_stored_metadata_chunk
                .contains("SourcePackFilesystemLibrarySchedulePreparePhase::BuildUnitPages")
            && schedule_from_stored_metadata_chunk
                .contains("SourcePackFilesystemLibrarySchedulePreparePhase::SchedulePages")
            && schedule_from_stored_metadata_chunk.contains("library_schedule_index_path: None")
            && schedule_from_stored_metadata_chunk.contains(
                "source_pack_compact_library_build_unit_page_from_stored_source_file_records("
            )
            && schedule_from_stored_metadata_chunk.contains(
                "source_pack_library_schedule_page_with_stored_codegen_units_from_partition_dependencies("
            ),
        "stored-metadata schedule chunks must resume from persisted schedule progress/build-unit/schedule pages and cap newly prepared libraries"
    );
    assert!(
        !schedule_from_stored_metadata_chunk.contains("read_explicit_source_path_metadata")
            && !schedule_from_stored_metadata_chunk
                .contains("store_source_pack_library_source_file_record_pages_from_paths(")
            && !schedule_from_stored_metadata_chunk.contains("ExplicitSourceLibraryPath"),
        "stored-metadata schedule chunks must not re-read source paths"
    );
    assert!(
        source_before(
            schedule_from_stored_metadata_chunk,
            "library_schedule_index_path: None",
            "store.store_library_schedule_index(&library_schedule_index)"
        ),
        "stored-metadata schedule chunks must not write the schedule index until every build-unit page is prepared"
    );
    let public_metadata_chunk_apis = source_between(
        &compiler,
        "pub fn prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_for_target",
        "pub fn prepare_explicit_source_libraries_filesystem_metadata",
    );
    assert!(
        public_metadata_chunk_apis
            .matches(
                "max_new_libraries.min(SOURCE_PACK_LIBRARY_METADATA_PREPARE_DEFAULT_CHUNK_LIMIT)",
            )
            .count()
            >= 2
            && public_metadata_chunk_apis.contains(
                "source_pack_prepare_ordered_library_metadata_pages_from_explicit_source_library_path_dependency_streams_with_max_new_libraries(",
            )
            && public_metadata_chunk_apis.contains(
                "source_pack_prepare_ordered_library_metadata_pages_from_explicit_source_library_path_dependency_streams_from_progress_with_max_new_libraries(",
            ),
        "public metadata chunk APIs must cap caller limits before preparing source-path metadata records"
    );
    let public_artifact_stage_chunk_apis = source_between(
        &compiler,
        "pub fn prepare_source_pack_filesystem_library_schedule_from_metadata_chunk_for_target",
        "fn source_pack_filesystem_artifact_prepare_result_from_stored_indexes",
    );
    assert!(
        public_artifact_stage_chunk_apis
            .matches("SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT")
            .count()
            >= 11
            && public_artifact_stage_chunk_apis.contains(
                "max_new_libraries.min(SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT)",
            )
            && public_artifact_stage_chunk_apis.contains(
                "max_new_batches.min(SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT)",
            )
            && public_artifact_stage_chunk_apis.contains(
                "max_new_partitions.min(SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT)",
            )
            && public_artifact_stage_chunk_apis
                .contains("let max_new_reduce_groups = max_new_reduce_groups")
            && public_artifact_stage_chunk_apis.contains(
                "max_new_groups.min(SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT)",
            )
            && public_artifact_stage_chunk_apis.contains(
                "max_new_items.min(SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT)",
            )
            && public_artifact_stage_chunk_apis.contains(
                "max_new_pages.min(SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT)",
            ),
        "public artifact-stage chunk APIs must cap caller limits before preparing persisted stage records"
    );
    let artifact_prepare_from_metadata = source_between(
        &compiler,
        "pub fn prepare_source_pack_filesystem_artifact_build_from_metadata",
        "pub fn execute_explicit_source_libraries_filesystem_artifact_build",
    );
    assert!(
        artifact_prepare_from_metadata.contains(
            "prepare_source_pack_filesystem_artifact_build_from_metadata_with_shard_limits_for_target("
        ) && artifact_prepare_from_metadata.contains(
            "prepare_source_pack_filesystem_artifact_build_from_metadata_chunk_with_shard_limits_for_target("
        ) && artifact_prepare_from_metadata.contains(
            "max_new_items.min(SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT)"
        ) && artifact_prepare_from_metadata.contains(
            "SourcePackFilesystemArtifactBuildPrepareStage::LibrarySchedule"
        ) && artifact_prepare_from_metadata.contains(
            "SourcePackFilesystemArtifactBuildPrepareStage::BuildManifests"
        ),
        "public artifact prepare from metadata must route persisted metadata through the resumable shard-limited top-level chunk orchestrator and cap caller chunk sizes"
    );
    assert!(
        artifact_prepare_from_metadata.contains("store.try_lock_build_state_for_target(target)?"),
        "public artifact prepare from metadata must take the persisted build-state lock"
    );
    assert!(
        artifact_prepare_from_metadata
            .contains("source_pack_store_compact_build_manifests_from_stored_indexes(")
            && artifact_prepare_from_metadata
                .contains("source_pack_filesystem_artifact_prepare_result_from_stored_indexes(")
            && artifact_prepare_from_metadata
                .contains("SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT")
            && artifact_prepare_from_metadata
                .contains("SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_FULL_PREPARE_DEFAULT_STEP_LIMIT",),
        "public artifact prepare from metadata must finalize compact manifests/results from persisted indexes without hydrating the source pack"
    );
    assert!(
        artifact_prepare_from_metadata.contains(
            "for _ in 0..SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_FULL_PREPARE_DEFAULT_STEP_LIMIT",
        ) && !artifact_prepare_from_metadata.contains("loop {"),
        "full artifact prepare convenience wrapper must be hard-bounded and leave arbitrary-size builds to repeated chunk calls"
    );
    assert!(
        !artifact_prepare_from_metadata.contains("read_explicit_source_path_metadata")
            && !artifact_prepare_from_metadata
                .contains("load_explicit_source_pack_manifest_from_paths(")
            && !artifact_prepare_from_metadata
                .contains("load_explicit_source_libraries_from_paths(")
            && !artifact_prepare_from_metadata
                .contains("store_source_pack_library_source_file_record_pages_from_paths(")
            && !artifact_prepare_from_metadata.contains(
                "prepare_explicit_source_prepared_library_pages_filesystem_artifact_build_with_shard_limits_for_target("
            )
            && !artifact_prepare_from_metadata
                .contains("store_source_pack_build_artifact_shards_from_page_metadata(")
            && !artifact_prepare_from_metadata
                .contains("source_pack_prepare_library_schedule_pages_from_stored_metadata("),
        "public artifact prepare from metadata must not re-read paths or call legacy whole-stage preparation"
    );
    let dependency_page_stream_writer = source_between(
        &compiler,
        "fn store_source_pack_library_dependency_pages_from_ids",
        "fn first_seen_library_ids",
    );
    assert!(
        dependency_page_stream_writer
            .contains("store_source_pack_library_dependency_page_from_ids("),
        "dependency stream writer must flush bounded dependency pages"
    );
    assert!(
        !dependency_page_stream_writer.contains("BTreeSet"),
        "dependency stream writer must validate sorted dependencies without retaining all ids"
    );
    assert!(
        dependency_page_stream_writer
            .contains("dependency_library_count >= expected_dependency_library_count")
            && dependency_page_stream_writer
                .contains("dependency_library_count != expected_dependency_library_count"),
        "dependency stream writer must enforce caller-declared dependency counts while streaming"
    );
    assert!(
        dependency_page_stream_writer.contains("previous_dependency_library_id")
            && dependency_page_stream_writer
                .contains("dependency_library_id <= previous_dependency_library_id"),
        "dependency stream writer must reject unsorted or duplicate dependency ids without retaining all ids"
    );
    assert!(
        dependency_page_stream_writer.contains("load_library_partition_locator_page_for_target("),
        "dependency stream writer must validate metadata dependencies through persisted partition locators"
    );
    assert!(
        dependency_page_stream_writer
            .contains("load_library_frontend_job_locator_page_for_target("),
        "dependency stream writer must validate artifact-build dependencies through persisted frontend job locators"
    );
}

#[test]
fn source_pack_work_queue_completion_uses_persisted_dependency_counters() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let compiler_path = root.join("src/compiler.rs");
    let compiler = fs::read_to_string(&compiler_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", compiler_path.display()));
    let source_pack_records_path = root.join("src/compiler/source_pack_records.rs");
    let source_pack_records = fs::read_to_string(&source_pack_records_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", source_pack_records_path.display()));
    let work_queue_progress_path = root.join("src/compiler/work_queue_progress.rs");
    let work_queue_progress = fs::read_to_string(&work_queue_progress_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", work_queue_progress_path.display()));

    let work_queue_index_record = source_between(
        &source_pack_records,
        "pub struct SourcePackWorkQueueIndex",
        "pub struct SourcePackWorkQueuePage",
    );
    assert!(
        work_queue_index_record.contains("pub artifact_item_count: usize")
            && work_queue_index_record.contains("pub work_item_count: usize")
            && !work_queue_index_record.contains("pub items: Vec<"),
        "work-queue index must persist compact counts, not one summary per work item"
    );

    let progress_records = source_between(
        &source_pack_records,
        "pub struct SourcePackWorkQueueProgressPageSummary",
        "struct ExplicitSourceLibraryManifestEntry",
    );
    assert!(
        progress_records.contains("pub blocked_item_count: usize")
            && progress_records.contains("pub struct SourcePackWorkQueueRemainingDependencyCount")
            && progress_records.contains("pub remaining_dependency_counts: Vec<")
            && progress_records.contains("pub pending_dependent_item_count: usize")
            && progress_records.contains("pub struct SourcePackWorkQueueRemainingDependentCount")
            && progress_records.contains("pub remaining_dependent_counts: Vec<"),
        "work-queue progress pages must persist per-item dependency and dependent counters"
    );
    assert!(
        progress_records.contains("pub artifact_item_count: usize")
            && progress_records.contains("pub ready_artifact_item_count: usize")
            && progress_records.contains("pub first_ready_item_index: Option<usize>")
            && progress_records.contains("pub first_ready_artifact_item_index: Option<usize>")
            && progress_records.contains("pub ready_artifact_claimed_item_count: usize")
            && progress_records.contains("pub artifact_item_indices: Vec<usize>")
            && progress_records.contains("pub ready_artifact_item_indices: Vec<usize>")
            && progress_records.contains("pub struct SourcePackWorkQueueProgressDirectoryPage")
            && progress_records
                .contains("pub struct SourcePackWorkQueueProgressDirectoryIndexPage")
            && progress_records.contains("pub fully_claimed_ready_directory_page_count: usize")
            && progress_records.contains("pub first_ready_page_index: Option<usize>")
            && progress_records.contains("pub first_ready_artifact_page_index: Option<usize>"),
        "work-queue progress pages must persist first-ready and artifact-ready subsets so workers can skip link-only ready work"
    );
    let progress_index_validation = source_between(
        &work_queue_progress,
        "fn validate_source_pack_work_queue_progress_index",
        "fn validate_source_pack_work_queue_progress_page_record_count",
    );
    assert!(
        progress_index_validation.contains("SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE")
            && progress_index_validation.contains("index.page_size"),
        "work-queue progress indexes must reject page sizes above the bounded progress-page record cap"
    );
    let progress_page_validation = source_between(
        &work_queue_progress,
        "fn validate_source_pack_work_queue_progress_page",
        "fn validate_source_pack_work_queue_progress_page_summary",
    );
    assert!(
        progress_page_validation.contains("SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE")
            && progress_page_validation.contains("page.artifact_item_indices.len()")
            && progress_page_validation.contains("page.remaining_dependency_counts.len()")
            && progress_page_validation.contains("page.remaining_dependent_counts.len()")
            && progress_page_validation.contains("page.completed_item_indices.len()")
            && progress_page_validation.contains("page.ready_item_indices.len()")
            && progress_page_validation.contains("page.ready_artifact_item_indices.len()")
            && progress_page_validation.contains("page.claimed_items.len()"),
        "work-queue progress pages must reject unbounded persisted item arrays before record scans"
    );
    let progress_page_summary_validation = source_between(
        &work_queue_progress,
        "fn validate_source_pack_work_queue_progress_page_summary",
        "fn source_pack_work_queue_progress_page_contains_item",
    );
    assert!(
        progress_page_summary_validation
            .contains("SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE")
            && progress_page_summary_validation.contains("summary.item_count"),
        "work-queue progress summary sidecars must preserve bounded per-page item counts"
    );
    let progress_summary_store = source_between(
        &compiler,
        "pub fn store_work_queue_progress_page_summary_for_target",
        "pub fn try_load_work_queue_progress_page_summary_for_target",
    );
    let progress_summary_load = source_between(
        &compiler,
        "pub fn try_load_work_queue_progress_page_summary_for_target",
        "pub fn store_work_queue_progress_directory_page_for_target",
    );
    assert!(
        progress_summary_store
            .contains("validate_source_pack_work_queue_progress_page_summary(summary)")
            && progress_summary_load
                .contains("validate_source_pack_work_queue_progress_page_summary(&summary)"),
        "work-queue progress summary sidecars must be validated at store/load boundaries"
    );

    let initial_progress_writer = source_between(
        &compiler,
        "struct SourcePackInitialWorkQueueProgressPageWriter",
        "fn store_source_pack_work_queue_compact_index",
    );
    assert!(
        initial_progress_writer.contains("current_remaining_dependency_counts")
            && initial_progress_writer.contains("remaining_dependency_count: dependency_count")
            && initial_progress_writer.contains("current_remaining_dependent_counts")
            && initial_progress_writer.contains("remaining_dependent_count: dependent_count")
            && initial_progress_writer.contains("current_artifact_item_indices")
            && initial_progress_writer.contains("current_ready_artifact_item_indices")
            && initial_progress_writer
                .contains("source_pack_work_queue_item_kind_is_artifact_backed(item.kind)"),
        "initial work-queue progress must seed blocked, pending-dependent, and artifact-ready counters from stored work-item pages"
    );
    assert!(
        initial_progress_writer.contains("store_work_queue_progress_directory_pages_for_index("),
        "streaming initial work-queue progress must persist compact directory and directory-index records without materializing every progress page"
    );

    let ready_frontier = source_between(
        &work_queue_progress,
        "fn source_pack_work_queue_progress_first_ready_item_index_from_index",
        "fn source_pack_work_queue_progress_refresh_index_from_pages",
    );
    assert!(
        ready_frontier.contains("summary.first_ready_item_index")
            && ready_frontier.contains("summary.first_ready_artifact_item_index")
            && ready_frontier.contains(
                "source_pack_work_queue_progress_directory_index_page_from_changes_or_store("
            )
            && ready_frontier.contains("load_work_queue_progress_page_for_target("),
        "work-queue ready-frontier recomputation must consume summary and directory-index frontier records before falling back to progress-page bodies"
    );

    let ready_query = source_between(
        &work_queue_progress,
        "fn source_pack_work_queue_progress_ready_unclaimed_item_indices_from_index_limited",
        "fn source_pack_work_queue_progress_first_ready_unclaimed_item_index",
    );
    assert!(
        ready_query
            .contains("source_pack_work_queue_progress_directory_page_from_changes_or_store(")
            && ready_query.contains("directory_page.ready_page_count")
            && ready_query
                .contains("source_pack_work_queue_progress_directory_ready_pages_are_claimed(")
            && ready_query.contains(
                "source_pack_work_queue_progress_directory_index_page_from_changes_or_store("
            )
            && ready_query.contains(
                "source_pack_work_queue_progress_directory_index_ready_pages_are_claimed("
            )
            && ready_query.contains("directory_page_end"),
        "work-queue ready queries must skip empty and fully claimed progress-page groups through compact directory and directory-index records"
    );

    let artifact_claim = source_between(
        &compiler,
        "fn source_pack_work_queue_first_ready_unclaimed_artifact_item",
        "fn source_pack_work_queue_record_artifact_batch_claim",
    );
    assert!(
        artifact_claim.contains("validate_source_pack_work_queue_progress_index(index, target)?")
            && artifact_claim.contains("index.ready_artifact_item_count")
            && artifact_claim.contains("index.first_ready_artifact_item_index")
            && artifact_claim.contains("summary.ready_artifact_item_count")
            && artifact_claim.contains("page.ready_artifact_item_indices")
            && artifact_claim.contains("directory_page.ready_artifact_page_count")
            && artifact_claim.contains(
                "source_pack_work_queue_progress_directory_ready_artifact_pages_are_claimed("
            )
            && artifact_claim.contains(
                "source_pack_work_queue_progress_directory_index_ready_artifact_pages_are_claimed("
            )
            && artifact_claim
                .contains("source_pack_work_queue_progress_page_ready_artifact_items_are_claimed("),
        "artifact work claims must consume persisted ready-artifact counters before loading work-item or execution-shard records"
    );
    assert!(
        !artifact_claim.contains("load_work_queue_index_for_target("),
        "artifact work claims must not load the compact monolithic work-queue index"
    );
    assert!(
        !compiler
            .contains("source_pack_work_queue_first_ready_unclaimed_artifact_item_legacy_scan"),
        "artifact work claims must not scan general ready items as a compatibility fallback"
    );

    let dependent_update = source_between(
        &compiler,
        "fn source_pack_work_queue_record_dependent_dependency_completed",
        "fn source_pack_work_queue_record_dependent_completed_for_release_candidate",
    );
    assert!(
        dependent_update
            .contains("source_pack_work_queue_progress_page_record_dependency_completed(")
            && !dependent_update.contains("source_pack_work_queue_item_dependencies_completed(")
            && !dependent_update.contains("source_pack_for_each_work_queue_dependency_item("),
        "dependent readiness updates must use persisted counters and must not rescan dependency lists as a fallback"
    );

    let changed_page_batch = source_between(
        &compiler,
        "struct SourcePackWorkQueueProgressChangedPageBatch",
        "fn source_pack_work_queue_item_has_no_remaining_dependents",
    );
    assert!(
        changed_page_batch.contains("page_limit")
            && changed_page_batch.contains("fn page_for_item_mut(")
            && changed_page_batch.contains("fn page_for_index_mut(")
            && changed_page_batch.contains("fn flush(")
            && changed_page_batch
                .contains("source_pack_work_queue_progress_refresh_index_from_pages("),
        "work-queue progress updates must batch changed progress pages behind a bounded flush helper"
    );

    let dependent_range_progress_update = source_between(
        &compiler,
        "fn source_pack_work_queue_record_dependent_range_dependency_completed",
        "fn source_pack_work_queue_record_work_item_dependents_dependency_completed",
    );
    assert!(
        dependent_range_progress_update.contains("page_for_index_mut(")
            && dependent_range_progress_update.contains(
                "source_pack_work_queue_progress_page_record_dependency_range_completed("
            ),
        "work-queue ranged dependent updates must operate through bounded progress pages"
    );

    let dependent_progress_update = source_between(
        &compiler,
        "fn source_pack_work_queue_record_work_item_dependents_dependency_completed",
        "fn source_pack_work_queue_record_dependent_completed_for_release_candidate",
    );
    assert!(
        dependent_progress_update.contains("load_work_queue_dependents_page_for_target(")
            && dependent_progress_update
                .contains("source_pack_work_queue_record_dependent_dependency_completed(")
            && dependent_progress_update
                .contains("source_pack_work_queue_record_dependent_range_dependency_completed(")
            && !dependent_progress_update
                .contains("source_pack_for_each_work_queue_dependent_item("),
        "work-queue dependent updates must consume explicit dependent pages and ranged dependent records without expanding ranges"
    );

    let release_update = source_between(
        &compiler,
        "fn source_pack_work_queue_record_dependent_completed_for_release_candidate",
        "fn release_source_pack_work_queue_item_output",
    );
    assert!(
        release_update.contains("source_pack_work_queue_progress_page_record_dependent_completed(")
            && release_update
                .contains("source_pack_work_queue_progress_page_record_dependent_range_completed(")
            && release_update.contains("page_for_index_mut(")
            && !release_update.contains("source_pack_work_queue_item_has_no_remaining_dependents(")
            && !release_update.contains("source_pack_for_each_work_queue_dependent_item("),
        "output-release updates must use persisted dependent counters and ranged progress pages, and must not rescan dependent lists as a fallback"
    );

    let release_driver = source_between(
        &compiler,
        "fn release_source_pack_work_queue_consumed_outputs_after_item_completion",
        "fn source_pack_work_queue_first_ready_unclaimed_artifact_item",
    );
    assert!(
        release_driver
            .contains("release_source_pack_work_queue_dependency_item_after_item_completion(")
            && release_driver
                .contains("release_source_pack_work_queue_dependency_range_after_item_completion(")
            && release_driver.contains("load_work_queue_dependencies_page_for_target(")
            && release_driver.contains("source_pack_work_queue_item_has_no_remaining_dependents(")
            && release_driver.contains("SourcePackWorkQueueProgressChangedPageBatch::new(")
            && release_driver.contains("changed_page_batch.flush("),
        "output cleanup must update release counters from the completed item's explicit and ranged dependency records"
    );
    assert!(
        !release_driver.contains("source_pack_work_queue_item_dependents_completed(")
            && !release_driver.contains("source_pack_for_each_work_queue_dependent_item(")
            && !release_driver.contains("source_pack_for_each_work_queue_dependency_item("),
        "output cleanup must not scan reverse dependent records or expand dependency ranges directly"
    );

    let completion_api = source_between(
        &compiler,
        "pub fn source_pack_filesystem_work_queue_record_claimed_item_complete_for_target_at",
        "pub fn execute_source_pack_filesystem_work_queue_claimed_artifact_item",
    );
    assert!(
        completion_api
            .contains("source_pack_work_queue_record_work_item_dependents_dependency_completed("),
        "work-queue completion must delegate dependent readiness to the counter-backed progress update"
    );
    assert!(
        completion_api.contains("SourcePackWorkQueueProgressChangedPageBatch::new(")
            && completion_api.contains("changed_page_batch.flush("),
        "work-queue completion must batch dependent progress-page updates before refreshing the compact index"
    );
    assert!(
        !completion_api.contains("source_pack_work_queue_item_dependencies_completed(")
            && !completion_api.contains("source_pack_for_each_work_queue_dependency_item(")
            && !completion_api.contains("source_pack_for_each_work_queue_dependent_item("),
        "work-queue completion must not rescan dependent dependency lists directly"
    );
}

#[test]
fn source_pack_sync_path_artifact_work_queue_entrypoints_use_persisted_queue() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let compiler_path = root.join("src/compiler.rs");
    let compiler = fs::read_to_string(&compiler_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", compiler_path.display()));

    let prepare_result = source_between(
        &compiler,
        "pub struct SourcePackFilesystemArtifactPrepareResult",
        "pub struct SourcePackFilesystemWorkQueueProgressSnapshot",
    );
    assert!(
        prepare_result.contains("pub artifact_root: PathBuf"),
        "filesystem source-pack prepare result must carry the persisted artifact root for repeated chunk submits"
    );
    assert!(
        prepare_result.contains("pub struct SourcePackFilesystemPreparedArtifactBuild")
            && prepare_result.contains("pub fn new(")
            && prepare_result.contains("pub fn artifact_root(&self) -> &Path")
            && prepare_result.contains("pub fn target(&self) -> SourcePackArtifactTarget"),
        "filesystem source-pack prepared build handle must be reopenable from artifact root and target"
    );
    assert!(
        prepare_result.contains("pub struct SourcePackFilesystemPreparedArtifactBuildSummary")
            && prepare_result.contains("pub fn bounded_summary("),
        "filesystem source-pack prepared build handle must expose bounded persisted-state summaries"
    );
    for required_loader in [
        "load_library_partition_index_for_target(self.target)",
        "load_library_schedule_index_for_target(self.target)",
        "load_build_job_batch_page_index_for_target(self.target)",
        "load_build_artifact_ref_index_for_target(self.target)",
        "load_build_artifact_shard_index_for_target(self.target)",
        "load_hierarchical_link_execution_index_for_target(self.target)",
        "load_work_queue_progress_index_for_target(self.target)",
    ] {
        assert!(
            prepare_result.contains(required_loader),
            "prepared build summary must consume persisted index record {required_loader:?}"
        );
    }
    assert!(
        prepare_result.contains("pub fn prepared_build(&self)")
            && prepare_result.contains(
                "SourcePackFilesystemPreparedArtifactBuild::new(&self.artifact_root, self.target)"
            ),
        "filesystem source-pack prepare result must expose a persisted-state handle without retaining path inputs"
    );
    assert!(
        prepare_result.contains("pub fn submit_path_artifact_work_queue_chunk")
            && prepare_result.contains(
                "execute_source_pack_filesystem_work_queue_worker_run_with_path_artifacts_for_target("
            ),
        "prepared source-pack result must expose a path-artifact chunk submit API over the persisted work queue"
    );
    assert!(
        prepare_result.contains("pub fn submit_path_artifact_work_queue_step")
            && prepare_result.contains(
                "execute_source_pack_filesystem_work_queue_worker_step_with_path_artifacts_for_target_at("
            ),
        "prepared source-pack result must expose a one-item path-artifact submit API over the persisted work queue"
    );
    assert!(
        prepare_result.contains("pub async fn submit_path_artifact_work_queue_step_async")
            && prepare_result.contains(
                "execute_source_pack_filesystem_work_queue_worker_step_async_with_path_artifacts_for_target_at("
            ),
        "prepared source-pack result must expose a one-item async path-artifact submit API over the persisted work queue"
    );
    assert!(
        prepare_result.contains("pub fn work_queue_progress_snapshot")
            && prepare_result
                .contains("source_pack_filesystem_work_queue_progress_snapshot_for_target("),
        "prepared source-pack result must expose bounded progress snapshots from persisted queue records"
    );
    assert!(
        prepare_result.contains("pub async fn submit_gpu_descriptor_work_queue_chunk_using")
            && prepare_result.contains(
                "execute_prepared_source_pack_filesystem_work_queue_worker_run_with_gpu_descriptors_for_target("
            ),
        "prepared source-pack result must expose a GPU descriptor chunk submit API over the persisted work queue"
    );
    assert!(
        !prepare_result.contains("prepare_explicit_source_pack_paths_filesystem_artifact_build")
            && !prepare_result.contains("load_explicit_source_pack_manifest_from_paths(")
            && !prepare_result.contains("load_path_build_manifest")
            && !prepare_result.contains("load_build_artifact_manifest")
            && !prepare_result.contains("load_work_queue_index_for_target")
            && !prepare_result
                .contains("execute_source_pack_filesystem_artifact_manifest_worker_run"),
        "prepared source-pack result must not reprepare inputs, load compact whole manifests, or bypass the persisted work queue"
    );

    for (start, end, delegate) in [
        (
            "pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_run_with_path_artifacts_for_target<",
            "pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target<",
            "execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target(",
        ),
        (
            "pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_with_path_artifacts_for_target<",
            "pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target<",
            "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target(",
        ),
        (
            "pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_with_path_artifacts_for_target<",
            "pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target<",
            "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target(",
        ),
        (
            "pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_with_path_artifacts_for_target<",
            "pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target<",
            "execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target(",
        ),
        (
            "pub fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_with_path_artifacts_for_target<",
            "pub fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target<",
            "execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target(",
        ),
    ] {
        let section = source_between(&compiler, start, end);
        assert!(
            section.contains(delegate),
            "default sync path-artifact work-queue entrypoint must delegate to its shard-limited variant"
        );
        assert!(
            section.contains("SourcePackBuildShardLimits::default()"),
            "default sync path-artifact work-queue entrypoint must only provide default shard limits"
        );
        assert!(
            !section.contains("execute_source_pack_filesystem_artifact_manifest_worker_run")
                && !section.contains("execute_source_pack_filesystem_artifact_manifest_build"),
            "default sync path-artifact work-queue entrypoint must not bypass the persisted work queue"
        );
    }

    let ordered_libraries = source_between(
        &compiler,
        "pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target<",
        "pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_with_path_artifacts_for_target<",
    );
    assert!(
        ordered_libraries.contains("ExplicitSourceLibraryPathStream")
            && ordered_libraries.contains("source_file_count: library.paths.len()")
            && ordered_libraries.contains(
                "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target("
            ),
        "sync ordered-library work-queue entrypoint must lower owned libraries into bounded path streams"
    );
    assert!(
        !ordered_libraries.contains(
            "prepare_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits_for_target("
        ) && !ordered_libraries.contains("execute_source_pack_filesystem_artifact_manifest_worker_run")
            && !ordered_libraries.contains("execute_source_pack_filesystem_artifact_manifest_build")
            && !ordered_libraries.contains("execute_source_pack_filesystem_work_queue_worker_run_async"),
        "sync ordered-library work-queue entrypoint must reuse path-stream queue execution without manifest or async fallback"
    );
    assert!(
        !ordered_libraries.contains("SourcePackBuildShardLimits::default()"),
        "shard-limited sync ordered-library work-queue entrypoint must not override caller shard limits"
    );

    for (start, end, prepare) in [
        (
            "pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target<",
            "pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_with_path_artifacts_for_target<",
            "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_work_queue_chunk_with_shard_limits_for_target(",
        ),
        (
            "pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target<",
            "pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_with_path_artifacts_for_target<",
            "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_work_queue_chunk_with_shard_limits_for_target(",
        ),
        (
            "pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target<",
            "pub fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_with_path_artifacts_for_target<",
            "prepare_explicit_source_pack_path_streams_filesystem_work_queue_chunk_with_shard_limits_for_target(",
        ),
    ] {
        let section = source_between(&compiler, start, end);
        assert!(
            section.contains(prepare),
            "sync path-artifact work-queue entrypoint must prepare persisted artifact and queue records with caller shard limits"
        );
        assert!(
            section.contains(
                "execute_source_pack_filesystem_work_queue_worker_run_with_path_artifacts_for_target("
            ),
            "sync path-artifact work-queue entrypoint must execute the persisted path-artifact queue"
        );
        assert!(
            !section.contains("execute_source_pack_filesystem_artifact_manifest_worker_run")
                && !section.contains("execute_source_pack_filesystem_artifact_manifest_build")
                && !section.contains("execute_source_pack_filesystem_work_queue_worker_run_async")
                && !section.contains(".await"),
            "sync path-artifact work-queue entrypoint must not route through manifest execution or async-only paths"
        );
        assert!(
            !section.contains("SourcePackBuildShardLimits::default()"),
            "shard-limited sync path-artifact work-queue entrypoint must not override caller shard limits"
        );
    }

    let ordered_path_dependency_run = source_between(
        &compiler,
        "pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target<",
        "pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_with_path_artifacts_for_target<",
    );
    assert!(
        ordered_path_dependency_run
            .contains("source_pack_limit_work_queue_worker_run_items(max_items).max(1)")
            && ordered_path_dependency_run
                .contains("source_pack_work_queue_not_prepared_after_bounded_chunk_error(")
            && !ordered_path_dependency_run.contains(
                "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target("
            ),
        "sync ordered path+dependency-stream work-queue run must stop after one bounded preparation chunk instead of hiding full artifact preparation"
    );
    let ordered_path_stream_run = source_between(
        &compiler,
        "pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target<",
        "pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_with_path_artifacts_for_target<",
    );
    assert!(
        ordered_path_stream_run.contains("ExplicitSourceLibraryPathDependencyStream")
            && ordered_path_stream_run.contains("dependency_library_ids.sort_unstable()")
            && ordered_path_stream_run
                .contains("source_pack_limit_work_queue_worker_run_items(max_items).max(1)")
            && ordered_path_stream_run
                .contains("source_pack_work_queue_not_prepared_after_bounded_chunk_error(")
            && !ordered_path_stream_run.contains(
                "prepare_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "sync ordered path-stream work-queue run must lower to dependency streams and stop after one bounded preparation chunk"
    );
    let source_pack_path_stream_run = source_between(
        &compiler,
        "pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target<",
        "pub fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_with_path_artifacts_for_target<",
    );
    assert!(
        source_pack_path_stream_run.contains("source_pack_limit_work_queue_worker_run_items(max_items).max(1)")
            && source_pack_path_stream_run
                .contains("source_pack_work_queue_not_prepared_after_bounded_chunk_error(")
            && !source_pack_path_stream_run.contains(
                "prepare_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target("
            ),
        "sync stdlib/user path-stream work-queue run must stop after one bounded preparation chunk instead of hiding full artifact preparation"
    );

    let path_slices = source_between(
        &compiler,
        "pub fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target<",
        "pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_with_path_artifacts_for_target<",
    );
    assert!(
        path_slices.contains(
            "execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target("
        ),
        "sync stdlib/user path-slice work-queue entrypoint must reuse the path-stream queue path"
    );
    assert!(
        path_slices.contains("stdlib_paths.iter().map(|path| path.as_ref())")
            && path_slices.contains("user_paths.iter().map(|path| path.as_ref())"),
        "sync stdlib/user path-slice work-queue entrypoint must stream path slices without cloning"
    );
    assert!(
        !path_slices.contains(".to_path_buf()")
            && !path_slices.contains(".collect()")
            && !path_slices.contains("execute_source_pack_filesystem_artifact_manifest_worker_run")
            && !path_slices.contains("execute_source_pack_filesystem_artifact_manifest_build")
            && !path_slices.contains("execute_source_pack_filesystem_work_queue_worker_run_async")
            && !path_slices.contains("SourcePackBuildShardLimits::default()"),
        "shard-limited sync stdlib/user path-slice work-queue entrypoint must stay streaming and queue-backed"
    );

    for (start, end, delegate) in [
        (
            "pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_with_path_artifacts_for_target<",
            "pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target<",
            "execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target(",
        ),
        (
            "pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_with_path_artifacts_for_target<",
            "pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target<",
            "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target(",
        ),
        (
            "pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_with_path_artifacts_for_target<",
            "pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target<",
            "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target(",
        ),
        (
            "pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_with_path_artifacts_for_target<",
            "pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target<",
            "execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target(",
        ),
        (
            "pub fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_with_path_artifacts_for_target<",
            "pub fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target<",
            "execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target(",
        ),
    ] {
        let section = source_between(&compiler, start, end);
        assert!(
            section.contains(delegate),
            "default sync path-artifact work-queue step entrypoint must delegate to its shard-limited variant"
        );
        assert!(
            section.contains("SourcePackBuildShardLimits::default()"),
            "default sync path-artifact work-queue step entrypoint must only provide default shard limits"
        );
        assert!(
            !section.contains("execute_source_pack_filesystem_artifact_manifest_worker_run")
                && !section.contains("execute_source_pack_filesystem_artifact_manifest_build")
                && !section.contains("execute_source_pack_filesystem_work_queue_worker_run")
                && !section.contains("execute_source_pack_filesystem_work_queue_worker_run_async")
                && !section.contains(".await"),
            "default sync path-artifact work-queue step entrypoint must not route through manifest execution, run loops, or async paths"
        );
    }

    let ordered_libraries_step = source_between(
        &compiler,
        "pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target<",
        "pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_with_path_artifacts_for_target<",
    );
    assert!(
        ordered_libraries_step.contains("ExplicitSourceLibraryPathStream")
            && ordered_libraries_step.contains("source_file_count: library.paths.len()")
            && ordered_libraries_step.contains(
                "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target("
            ),
        "sync ordered-library work-queue step entrypoint must lower owned libraries into bounded path streams"
    );
    assert!(
        !ordered_libraries_step.contains(
            "prepare_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits_for_target("
        ) && !ordered_libraries_step.contains("execute_source_pack_filesystem_artifact_manifest_worker_run")
            && !ordered_libraries_step.contains("execute_source_pack_filesystem_artifact_manifest_build")
            && !ordered_libraries_step.contains("execute_source_pack_filesystem_work_queue_worker_run")
            && !ordered_libraries_step.contains("execute_source_pack_filesystem_work_queue_worker_run_async"),
        "sync ordered-library work-queue step entrypoint must reuse path-stream queue execution without manifest, run-loop, or async fallback"
    );
    assert!(
        !ordered_libraries_step.contains("SourcePackBuildShardLimits::default()"),
        "shard-limited sync ordered-library work-queue step entrypoint must not override caller shard limits"
    );

    for (start, end, prepare) in [
        (
            "pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target<",
            "pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_with_path_artifacts_for_target<",
            "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_work_queue_chunk_with_shard_limits_for_target(",
        ),
        (
            "pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target<",
            "pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_with_path_artifacts_for_target<",
            "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_work_queue_chunk_with_shard_limits_for_target(",
        ),
        (
            "pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target<",
            "pub fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_with_path_artifacts_for_target<",
            "prepare_explicit_source_pack_path_streams_filesystem_work_queue_chunk_with_shard_limits_for_target(",
        ),
    ] {
        let section = source_between(&compiler, start, end);
        assert!(
            section.contains(prepare),
            "sync path-artifact work-queue step entrypoint must prepare persisted artifact and queue records with caller shard limits"
        );
        assert!(
            section.contains("prepared.submit_path_artifact_work_queue_step("),
            "sync path-artifact work-queue step entrypoint must execute one persisted queue item"
        );
        assert!(
            !section.contains("execute_source_pack_filesystem_artifact_manifest_worker_run")
                && !section.contains("execute_source_pack_filesystem_artifact_manifest_build")
                && !section.contains("execute_source_pack_filesystem_work_queue_worker_run")
                && !section.contains("execute_source_pack_filesystem_work_queue_worker_run_async")
                && !section.contains(".await"),
            "sync path-artifact work-queue step entrypoint must not route through manifest execution, run loops, or async paths"
        );
        assert!(
            !section.contains("SourcePackBuildShardLimits::default()"),
            "shard-limited sync path-artifact work-queue step entrypoint must not override caller shard limits"
        );
    }

    let ordered_path_stream_step = source_between(
        &compiler,
        "pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target<",
        "pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_with_path_artifacts_for_target<",
    );
    assert!(
        ordered_path_stream_step.contains("ExplicitSourceLibraryPathDependencyStream")
            && ordered_path_stream_step.contains("dependency_library_ids.sort_unstable()")
            && ordered_path_stream_step
                .contains("SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT")
            && ordered_path_stream_step
                .contains("source_pack_work_queue_not_prepared_after_bounded_chunk_error(")
            && !ordered_path_stream_step.contains(
                "prepare_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits_for_target("
            ),
        "sync ordered path-stream work-queue step must lower to dependency streams and stop after one bounded preparation chunk"
    );

    let ordered_path_dependency_step = source_between(
        &compiler,
        "pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target<",
        "pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_with_path_artifacts_for_target<",
    );
    assert!(
        ordered_path_dependency_step
            .contains("SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT")
            && ordered_path_dependency_step
                .contains("source_pack_work_queue_not_prepared_after_bounded_chunk_error(")
            && !ordered_path_dependency_step.contains(
                "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "sync ordered path+dependency-stream work-queue step must stop after one bounded preparation chunk instead of hiding full artifact preparation"
    );

    let source_pack_path_stream_step = source_between(
        &compiler,
        "pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target<",
        "pub fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_with_path_artifacts_for_target<",
    );
    assert!(
        source_pack_path_stream_step
            .contains("SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT")
            && source_pack_path_stream_step
                .contains("source_pack_work_queue_not_prepared_after_bounded_chunk_error(")
            && !source_pack_path_stream_step.contains(
                "prepare_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target("
            ),
        "sync stdlib/user path-stream work-queue step must stop after one bounded preparation chunk instead of hiding full artifact preparation"
    );

    let path_slices_step = source_between(
        &compiler,
        "pub fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target<",
        "pub async fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_async_with_path_artifacts_for_target<",
    );
    assert!(
        path_slices_step.contains(
            "execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target("
        ),
        "sync stdlib/user path-slice work-queue step entrypoint must reuse the path-stream queue step path"
    );
    assert!(
        path_slices_step.contains("stdlib_paths.iter().map(|path| path.as_ref())")
            && path_slices_step.contains("user_paths.iter().map(|path| path.as_ref())"),
        "sync stdlib/user path-slice work-queue step entrypoint must stream path slices without cloning"
    );
    assert!(
        !path_slices_step.contains(".to_path_buf()")
            && !path_slices_step.contains(".collect()")
            && !path_slices_step
                .contains("execute_source_pack_filesystem_artifact_manifest_worker_run")
            && !path_slices_step.contains("execute_source_pack_filesystem_artifact_manifest_build")
            && !path_slices_step.contains("execute_source_pack_filesystem_work_queue_worker_run")
            && !path_slices_step
                .contains("execute_source_pack_filesystem_work_queue_worker_run_async")
            && !path_slices_step.contains("SourcePackBuildShardLimits::default()"),
        "shard-limited sync stdlib/user path-slice work-queue step entrypoint must stay streaming and queue-backed"
    );
}

#[test]
fn source_pack_async_path_artifact_work_queue_step_entrypoints_use_persisted_queue() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let compiler_path = root.join("src/compiler.rs");
    let compiler = fs::read_to_string(&compiler_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", compiler_path.display()));

    for (start, end, delegate) in [
        (
            "pub async fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_async_with_path_artifacts_for_target<",
            "pub async fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target<",
            "execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target(",
        ),
        (
            "pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_path_artifacts_for_target<",
            "pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target<",
            "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target(",
        ),
        (
            "pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_async_with_path_artifacts_for_target<",
            "pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target<",
            "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target(",
        ),
        (
            "pub async fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_path_artifacts_for_target<",
            "pub async fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target<",
            "execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target(",
        ),
    ] {
        let section = source_between(&compiler, start, end);
        assert!(
            section.contains(delegate),
            "default async path-artifact work-queue step entrypoint must delegate to its shard-limited variant"
        );
        assert!(
            section.contains("SourcePackBuildShardLimits::default()"),
            "default async path-artifact work-queue step entrypoint must only provide default shard limits"
        );
        assert!(
            section.contains(".await"),
            "default async path-artifact work-queue step entrypoint must await one-step execution"
        );
        assert!(
            !section.contains("execute_source_pack_filesystem_artifact_manifest_worker_run")
                && !section.contains("execute_source_pack_filesystem_artifact_manifest_build")
                && !section.contains("execute_source_pack_filesystem_work_queue_worker_run")
                && !section.contains("execute_source_pack_filesystem_work_queue_worker_run_async"),
            "default async path-artifact work-queue step entrypoint must not route through manifest execution or run loops"
        );
    }

    let ordered_libraries_step = source_between(
        &compiler,
        "pub async fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target<",
        "pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_path_artifacts_for_target<",
    );
    assert!(
        ordered_libraries_step.contains("ExplicitSourceLibraryPathStream")
            && ordered_libraries_step.contains("source_file_count: library.paths.len()")
            && ordered_libraries_step.contains(
                "execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target("
            ),
        "async ordered-library work-queue step entrypoint must lower owned libraries into bounded path streams"
    );
    assert!(
        ordered_libraries_step.contains(".await"),
        "async ordered-library work-queue step entrypoint must await the path-stream one-step path"
    );
    assert!(
        !ordered_libraries_step.contains(
            "prepare_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits_for_target("
        ) && !ordered_libraries_step.contains("execute_source_pack_filesystem_artifact_manifest_worker_run")
            && !ordered_libraries_step.contains("execute_source_pack_filesystem_artifact_manifest_build")
            && !ordered_libraries_step.contains("execute_source_pack_filesystem_work_queue_worker_run")
            && !ordered_libraries_step.contains("execute_source_pack_filesystem_work_queue_worker_run_async"),
        "async ordered-library work-queue step entrypoint must reuse path-stream queue execution without manifest or run-loop fallback"
    );
    assert!(
        !ordered_libraries_step.contains("SourcePackBuildShardLimits::default()"),
        "shard-limited async ordered-library work-queue step entrypoint must not override caller shard limits"
    );

    for (start, end, prepare) in [
        (
            "pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target<",
            "pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_async_with_path_artifacts_for_target<",
            "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_work_queue_chunk_with_shard_limits_for_target(",
        ),
        (
            "pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target<",
            "pub async fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_path_artifacts_for_target<",
            "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_work_queue_chunk_with_shard_limits_for_target(",
        ),
        (
            "pub async fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target<",
            "pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_async_with_path_artifacts_for_target<",
            "prepare_explicit_source_pack_path_streams_filesystem_work_queue_chunk_with_shard_limits_for_target(",
        ),
    ] {
        let section = source_between(&compiler, start, end);
        assert!(
            section.contains(prepare),
            "async path-artifact work-queue step entrypoint must prepare persisted artifact and queue records with caller shard limits"
        );
        assert!(
            section.contains(".submit_path_artifact_work_queue_step_async("),
            "async path-artifact work-queue step entrypoint must execute one persisted queue item"
        );
        assert!(
            section.contains(".await"),
            "async path-artifact work-queue step entrypoint must await the one-step submit"
        );
        assert!(
            !section.contains("execute_source_pack_filesystem_artifact_manifest_worker_run")
                && !section.contains("execute_source_pack_filesystem_artifact_manifest_build")
                && !section.contains("execute_source_pack_filesystem_work_queue_worker_run")
                && !section.contains("execute_source_pack_filesystem_work_queue_worker_run_async"),
            "async path-artifact work-queue step entrypoint must not route through manifest execution or run loops"
        );
        assert!(
            !section.contains("SourcePackBuildShardLimits::default()"),
            "shard-limited async path-artifact work-queue step entrypoint must not override caller shard limits"
        );
    }

    let ordered_path_stream_step = source_between(
        &compiler,
        "pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target<",
        "pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_async_with_path_artifacts_for_target<",
    );
    assert!(
        ordered_path_stream_step.contains("ExplicitSourceLibraryPathDependencyStream")
            && ordered_path_stream_step.contains("dependency_library_ids.sort_unstable()")
            && ordered_path_stream_step
                .contains("SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT")
            && ordered_path_stream_step
                .contains("source_pack_work_queue_not_prepared_after_bounded_chunk_error(")
            && !ordered_path_stream_step.contains(
                "prepare_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits_for_target("
            ),
        "async ordered path-stream work-queue step must lower to dependency streams and stop after one bounded preparation chunk"
    );

    let ordered_path_dependency_step = source_between(
        &compiler,
        "pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target<",
        "pub async fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_path_artifacts_for_target<",
    );
    assert!(
        ordered_path_dependency_step
            .contains("SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT")
            && ordered_path_dependency_step
                .contains("source_pack_work_queue_not_prepared_after_bounded_chunk_error(")
            && !ordered_path_dependency_step.contains(
                "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target("
            ),
        "async ordered path+dependency-stream work-queue step must stop after one bounded preparation chunk instead of hiding full artifact preparation"
    );

    let source_pack_path_stream_step = source_between(
        &compiler,
        "pub async fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target<",
        "pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_async_with_path_artifacts_for_target<",
    );
    assert!(
        source_pack_path_stream_step
            .contains("SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT")
            && source_pack_path_stream_step
                .contains("source_pack_work_queue_not_prepared_after_bounded_chunk_error(")
            && !source_pack_path_stream_step.contains(
                "prepare_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target("
            ),
        "async stdlib/user path-stream work-queue step must stop after one bounded preparation chunk instead of hiding full artifact preparation"
    );

    let path_slices_step = source_between(
        &compiler,
        "pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_async_with_path_artifacts_for_target<",
        "#[cfg(test)]\nmod tests",
    );
    assert!(
        path_slices_step.contains(
            "execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target("
        ),
        "async stdlib/user path-slice work-queue step entrypoint must reuse the path-stream queue step path"
    );
    assert!(
        path_slices_step.contains("stdlib_paths.iter().map(|path| path.as_ref())")
            && path_slices_step.contains("user_paths.iter().map(|path| path.as_ref())"),
        "async stdlib/user path-slice work-queue step entrypoint must stream path slices without cloning"
    );
    assert!(
        path_slices_step.contains(".await"),
        "async stdlib/user path-slice work-queue step entrypoint must await the path-stream one-step path"
    );
    assert!(
        path_slices_step.contains("SourcePackBuildShardLimits::default()"),
        "async stdlib/user path-slice work-queue step entrypoint must provide default shard limits directly"
    );
    assert!(
        !path_slices_step.contains(".to_path_buf()")
            && !path_slices_step.contains(".collect()")
            && !path_slices_step
                .contains("execute_source_pack_filesystem_artifact_manifest_worker_run")
            && !path_slices_step.contains("execute_source_pack_filesystem_artifact_manifest_build")
            && !path_slices_step.contains("execute_source_pack_filesystem_work_queue_worker_run")
            && !path_slices_step
                .contains("execute_source_pack_filesystem_work_queue_worker_run_async"),
        "async stdlib/user path-slice work-queue step entrypoint must stay streaming and queue-backed"
    );
}

#[test]
fn in_memory_source_pack_public_helpers_are_bounded_codegen_units() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let compiler_path = root.join("src/compiler.rs");
    let compiler = fs::read_to_string(&compiler_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", compiler_path.display()));

    let validator = source_between(
        &compiler,
        "fn validate_in_memory_source_pack_fits_default_codegen_unit",
        "pub async fn compile_source_to_wasm_with_gpu_codegen",
    );
    assert!(
        validator.contains("CodegenUnitLimits::default().normalized()")
            && validator.contains("sources.len() > limits.max_source_files")
            && validator.contains("source_bytes > limits.max_source_bytes")
            && validator.contains("total_source_bytes > limits.max_source_bytes")
            && validator.contains("persisted source-pack descriptor work queues"),
        "in-memory source-pack validator must cap public whole-pack helpers by default codegen-unit limits and route larger codebases to descriptor queues"
    );

    for (start, end, operation) in [
        (
            "pub async fn type_check_source_pack<S: AsRef<str>>",
            "pub async fn type_check_source_pack_manifest",
            "type check source pack",
        ),
        (
            "pub async fn compile_source_pack_to_wasm<S: AsRef<str>>",
            "pub async fn compile_source_pack_manifest_to_wasm",
            "compile source pack to WASM",
        ),
        (
            "pub async fn compile_source_pack_to_x86_64<S: AsRef<str>>",
            "pub async fn compile_source_pack_manifest_to_x86_64",
            "compile source pack to x86_64",
        ),
    ] {
        let helper = source_between(&compiler, start, end);
        assert!(
            helper.contains("validate_in_memory_source_pack_fits_default_codegen_unit(")
                && helper.contains(operation),
            "public in-memory source-pack helper {start:?} must validate default codegen-unit bounds"
        );
        let first_pipeline_marker = helper
            .find("with_recorded_resident_source_pack_tokens_after_count")
            .or_else(|| helper.find("type_check_explicit_source_pack("))
            .unwrap_or_else(|| panic!("missing source-pack pipeline marker in {start:?}"));
        let validation_marker = helper
            .find("validate_in_memory_source_pack_fits_default_codegen_unit(")
            .unwrap_or_else(|| panic!("missing validation marker in {start:?}"));
        assert!(
            validation_marker < first_pipeline_marker,
            "public in-memory source-pack helper {start:?} must validate before recording resident source-pack buffers"
        );
    }

    let typecheck_manifest = source_between(
        &compiler,
        "pub async fn type_check_source_pack_manifest",
        "async fn type_check_expanded_source",
    );
    assert!(
        typecheck_manifest.contains("self.type_check_source_pack(&source_pack.sources).await")
            && !typecheck_manifest.contains("type_check_explicit_source_pack("),
        "in-memory source-pack manifest typecheck must reuse the bounded public source-pack helper"
    );

    let public_typecheck_helpers = source_between(
        &compiler,
        "pub async fn type_check_source_pack_with_gpu<S: AsRef<str>>",
        "pub async fn compile_source_pack_to_wasm_with_gpu_codegen<S: AsRef<str>>",
    );
    assert!(
        public_typecheck_helpers.contains(".type_check_source_pack(sources)")
            && public_typecheck_helpers.contains("compiler.type_check_source_pack(sources).await")
            && !public_typecheck_helpers.contains("type_check_explicit_source_pack("),
        "global in-memory source-pack typecheck helpers must call the bounded public source-pack helper"
    );
}

#[test]
fn source_pack_path_compile_helpers_are_explicit_legacy_in_memory() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let compiler_path = root.join("src/compiler.rs");
    let compiler = fs::read_to_string(&compiler_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", compiler_path.display()));

    for (legacy_start, legacy_end, loader) in [
        (
            "pub async fn compile_explicit_source_pack_paths_legacy_in_memory_to_wasm<",
            "note = \"compile_explicit_source_pack_paths_to_wasm whole-loads source files",
            "load_explicit_source_pack_manifest_from_paths(",
        ),
        (
            "pub async fn compile_explicit_source_libraries_legacy_in_memory_to_wasm<",
            "note = \"compile_explicit_source_libraries_to_wasm whole-loads source files",
            "load_explicit_source_libraries_from_paths(",
        ),
        (
            "pub async fn compile_explicit_source_pack_paths_legacy_in_memory_to_x86_64<",
            "note = \"compile_explicit_source_pack_paths_to_x86_64 whole-loads source files",
            "load_explicit_source_pack_manifest_from_paths(",
        ),
        (
            "pub async fn compile_explicit_source_libraries_legacy_in_memory_to_x86_64<",
            "note = \"compile_explicit_source_libraries_to_x86_64 whole-loads source files",
            "load_explicit_source_libraries_from_paths(",
        ),
        (
            "pub async fn compile_explicit_source_pack_paths_legacy_in_memory_to_wasm_with_gpu_codegen<",
            "note = \"compile_explicit_source_pack_paths_to_wasm_with_gpu_codegen whole-loads source files",
            "load_explicit_source_pack_manifest_from_paths(",
        ),
        (
            "pub async fn compile_explicit_source_libraries_legacy_in_memory_to_wasm_with_gpu_codegen<",
            "note = \"compile_explicit_source_libraries_to_wasm_with_gpu_codegen whole-loads source files",
            "load_explicit_source_libraries_from_paths(",
        ),
        (
            "pub async fn compile_explicit_source_pack_paths_legacy_in_memory_to_x86_64_with_gpu_codegen<",
            "note = \"compile_explicit_source_pack_paths_to_x86_64_with_gpu_codegen whole-loads source files",
            "load_explicit_source_pack_manifest_from_paths(",
        ),
        (
            "pub async fn compile_explicit_source_libraries_legacy_in_memory_to_x86_64_with_gpu_codegen<",
            "note = \"compile_explicit_source_libraries_to_x86_64_with_gpu_codegen whole-loads source files",
            "load_explicit_source_libraries_from_paths(",
        ),
    ] {
        let legacy = source_between(&compiler, legacy_start, legacy_end);
        assert!(
            legacy.contains(loader),
            "legacy in-memory compile helper {legacy_start:?} must be the only helper in its pair that whole-loads path inputs"
        );
    }

    for (wrapper_start, wrapper_end, legacy_call, forbidden_loader) in [
        (
            "note = \"compile_explicit_source_pack_paths_to_wasm whole-loads source files",
            "pub async fn compile_explicit_source_libraries_legacy_in_memory_to_wasm<",
            "compile_explicit_source_pack_paths_legacy_in_memory_to_wasm(",
            "load_explicit_source_pack_manifest_from_paths(",
        ),
        (
            "note = \"compile_explicit_source_libraries_to_wasm whole-loads source files",
            "#[allow(clippy::too_many_arguments)]",
            "compile_explicit_source_libraries_legacy_in_memory_to_wasm(",
            "load_explicit_source_libraries_from_paths(",
        ),
        (
            "note = \"compile_explicit_source_pack_paths_to_x86_64 whole-loads source files",
            "pub async fn compile_explicit_source_libraries_legacy_in_memory_to_x86_64<",
            "compile_explicit_source_pack_paths_legacy_in_memory_to_x86_64(",
            "load_explicit_source_pack_manifest_from_paths(",
        ),
        (
            "note = \"compile_explicit_source_libraries_to_x86_64 whole-loads source files",
            "#[allow(clippy::too_many_arguments)]\n    fn record_typecheck_from_parse_buffers",
            "compile_explicit_source_libraries_legacy_in_memory_to_x86_64(",
            "load_explicit_source_libraries_from_paths(",
        ),
        (
            "note = \"compile_explicit_source_pack_paths_to_wasm_with_gpu_codegen whole-loads source files",
            "pub async fn compile_explicit_source_libraries_legacy_in_memory_to_wasm_with_gpu_codegen<",
            "compile_explicit_source_pack_paths_legacy_in_memory_to_wasm_with_gpu_codegen(",
            "load_explicit_source_pack_manifest_from_paths(",
        ),
        (
            "note = \"compile_explicit_source_libraries_to_wasm_with_gpu_codegen whole-loads source files",
            "pub async fn compile_explicit_source_pack_paths_legacy_in_memory_to_wasm_with_gpu_codegen_using<",
            "compile_explicit_source_libraries_legacy_in_memory_to_wasm_with_gpu_codegen(",
            "load_explicit_source_libraries_from_paths(",
        ),
        (
            "note = \"compile_explicit_source_pack_paths_to_x86_64_with_gpu_codegen whole-loads source files",
            "pub async fn compile_explicit_source_libraries_legacy_in_memory_to_x86_64_with_gpu_codegen<",
            "compile_explicit_source_pack_paths_legacy_in_memory_to_x86_64_with_gpu_codegen(",
            "load_explicit_source_pack_manifest_from_paths(",
        ),
        (
            "note = \"compile_explicit_source_libraries_to_x86_64_with_gpu_codegen whole-loads source files",
            "pub async fn compile_explicit_source_pack_paths_legacy_in_memory_to_x86_64_with_gpu_codegen_using<",
            "compile_explicit_source_libraries_legacy_in_memory_to_x86_64_with_gpu_codegen(",
            "load_explicit_source_libraries_from_paths(",
        ),
    ] {
        let wrapper = source_between(&compiler, wrapper_start, wrapper_end);
        assert!(
            wrapper.contains("whole-loads source files") && wrapper.contains(legacy_call),
            "old path compile helper {wrapper_start:?} must be deprecated and delegate to its explicit legacy in-memory helper"
        );
        assert!(
            !wrapper.contains(forbidden_loader),
            "deprecated path compile wrapper {wrapper_start:?} must not whole-load sources itself"
        );
    }
}

#[test]
fn main_cli_source_pack_uses_descriptor_work_queue_by_default() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let main_path = root.join("src/main.rs");
    let main = fs::read_to_string(&main_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", main_path.display()));
    let compiler_path = root.join("src/compiler.rs");
    let compiler = fs::read_to_string(&compiler_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", compiler_path.display()));

    let cli_defaults = source_between(&main, "const DEFAULT_SOURCE_PACK_MAX_ITEMS", "fn main()");
    assert!(
        cli_defaults.contains("const DEFAULT_SOURCE_PACK_MAX_ITEMS: usize = 64;")
            && cli_defaults.contains("const DEFAULT_SOURCE_PACK_MAX_READY_ITEMS: usize = 64;")
            && cli_defaults
                .contains("const DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES: usize = 64;")
            && cli_defaults.contains("const DEFAULT_SOURCE_PACK_METADATA_MAX_SOURCE_FILES: usize")
            && cli_defaults.contains("DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES")
            && !cli_defaults.contains("usize::MAX"),
        "main CLI descriptor mode must use bounded default metadata library/source-file, work-item, and ready-frontier limits"
    );

    let argument_parser = source_between(&main, "fn run() -> Result<(), String>", "let emitted =");
    assert!(
        argument_parser.contains("--source-pack-descriptors")
            && argument_parser.contains("--source-pack-manifest")
            && argument_parser.contains("--source-pack-library-manifest")
            && argument_parser.contains("--source-pack-metadata-only")
            && argument_parser.contains("--source-pack-prepare-only")
            && argument_parser.contains("--source-pack-metadata-max-libraries")
            && argument_parser.contains("--source-pack-metadata-max-source-files")
            && argument_parser.contains("--source-pack-build-from-metadata")
            && argument_parser.contains("--source-pack-artifact-root")
            && argument_parser.contains("--source-pack-max-items")
            && argument_parser.contains("--source-pack-max-ready-items")
            && argument_parser.contains("--source-pack-legacy-in-memory"),
        "main CLI must expose persisted source-pack descriptor controls and require an explicit legacy flag for the whole-pack path"
    );
    assert!(
        argument_parser.contains(
            "--source-pack-descriptors and --source-pack-legacy-in-memory are mutually exclusive"
        ),
        "main CLI must prevent ambiguous descriptor and legacy source-pack modes"
    );
    assert!(
        argument_parser.contains("--source-pack-manifest requires descriptor mode")
            && argument_parser.contains("--source-pack-library-manifest requires descriptor mode")
            && argument_parser.contains(
                "--source-pack-manifest and --source-pack-library-manifest are mutually exclusive"
            )
            && argument_parser.contains(
                "--source-pack-metadata-only and --source-pack-build-from-metadata are mutually exclusive"
            )
            && argument_parser.contains(
                "--source-pack-prepare-only and --source-pack-metadata-only are mutually exclusive"
            )
            && argument_parser.contains(
                "--source-pack-prepare-only prepares from source-pack inputs"
            )
            && argument_parser.contains(
                "--source-pack-build-from-metadata reads persisted metadata from --source-pack-artifact-root"
            )
            && argument_parser.contains(
                "--source-pack-metadata-max-libraries only applies with --source-pack-metadata-only or --source-pack-prepare-only"
            )
            && argument_parser.contains(
                "--source-pack-metadata-max-source-files only applies with --source-pack-metadata-only or --source-pack-prepare-only"
            )
            && argument_parser
                .contains("--source-pack-metadata-max-libraries must be greater than zero")
            && argument_parser
                .contains("--source-pack-metadata-max-source-files must be greater than zero")
            && argument_parser
                .contains("--source-pack-library-manifest describe all source-pack libraries")
            && argument_parser.contains("source_pack.manifest.is_some()"),
        "main CLI manifest modes must be descriptor-only, mutually exclusive, and must not collapse manifest libraries into stdlib/user positional inputs"
    );

    let metadata_dispatch = source_between(
        &main,
        "if source_pack.metadata_only",
        "let emitted = if source_pack.build_from_metadata",
    );
    assert!(
        metadata_dispatch.contains("prepare_source_pack_metadata_only(")
            && metadata_dispatch.contains("prepare_source_pack_inputs_chunk_only(")
            && metadata_dispatch.contains("prepare_source_pack_build_from_metadata_chunk_only(")
            && metadata_dispatch.contains("return Ok(())"),
        "main CLI metadata-only and prepare-only modes must stop after persisted source-pack preparation chunks"
    );
    let metadata_limit_helpers = source_between(
        &main,
        "fn source_pack_metadata_max_libraries",
        "fn prepare_source_pack_metadata_only",
    );
    assert!(
        metadata_limit_helpers.contains(".unwrap_or(DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES)")
            && metadata_limit_helpers.contains(".min(DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES)")
            && metadata_limit_helpers
                .contains(".unwrap_or(DEFAULT_SOURCE_PACK_METADATA_MAX_SOURCE_FILES)")
            && metadata_limit_helpers
                .contains(".min(DEFAULT_SOURCE_PACK_METADATA_MAX_SOURCE_FILES)")
            && metadata_limit_helpers.contains(".min(DEFAULT_SOURCE_PACK_BUILD_MAX_ITEMS)")
            && metadata_limit_helpers.contains(".min(DEFAULT_SOURCE_PACK_MAX_ITEMS)")
            && metadata_limit_helpers.contains(".min(DEFAULT_SOURCE_PACK_MAX_READY_ITEMS)")
            && metadata_limit_helpers.contains(".max(1)"),
        "main CLI source-pack chunk/execution limits must cap oversized caller values to bounded default record windows"
    );
    let metadata_only_prepare = source_between(
        &main,
        "fn prepare_source_pack_metadata_only",
        "fn compile_source_pack_from_metadata_with_descriptor_queue",
    );
    assert!(
        metadata_only_prepare.contains("prepare_source_pack_metadata_chunk(")
            && metadata_only_prepare.contains("metadata_max_libraries")
            && metadata_only_prepare.contains("metadata_max_source_files")
            && metadata_only_prepare
                .contains("source_pack.metadata_max_source_files.is_some()")
            && metadata_only_prepare.contains("source_pack_metadata_max_libraries(source_pack)")
            && metadata_only_prepare.contains("source_pack_metadata_max_source_files(source_pack)")
            && metadata_only_prepare
                .contains("complete={} libraries={} new_libraries={}")
            && metadata_only_prepare.contains(
                "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_from_progress_for_target("
            )
            && metadata_only_prepare.contains(
                "--source-pack-metadata-only with --source-pack-manifest would require reading the whole JSON manifest"
            )
            && !metadata_only_prepare.contains("fs::read(manifest_path)")
            && !metadata_only_prepare
                .contains("serde_json::from_slice::<ExplicitSourcePackPathManifest>")
            && !metadata_only_prepare
                .contains("source_pack_manifest_ordered_path_dependency_streams(manifest)"),
        "main CLI metadata-only mode must default JSONL library manifests to bounded metadata chunks and reject whole JSON manifests before reading them"
    );

    let source_pack_dispatch = source_between(
        &main,
        "let emitted = if source_pack.build_from_metadata",
        "} else if let Some(input) = inputs.first()",
    );
    assert!(
        source_pack_dispatch.contains("compile_source_pack_from_metadata_with_descriptor_queue(")
            && source_pack_dispatch
                .contains("compile_source_pack_library_manifest_with_descriptor_queue(")
            && source_pack_dispatch.contains("compile_source_pack_manifest_with_descriptor_queue(")
            && source_pack_dispatch.contains("if source_pack.legacy_in_memory")
            && source_pack_dispatch.contains("compile_source_pack_legacy_in_memory(")
            && source_pack_dispatch.contains("compile_source_pack_with_descriptor_queue("),
        "main CLI source-pack dispatch must split metadata-build mode, streaming library-manifest mode, manifest descriptor mode, explicit legacy mode, and the default descriptor work queue"
    );
    assert!(
        source_before(
            source_pack_dispatch,
            "compile_source_pack_from_metadata_with_descriptor_queue(",
            "compile_source_pack_library_manifest_with_descriptor_queue("
        ),
        "main CLI must dispatch persisted metadata builds before parsing source-pack inputs"
    );
    assert!(
        source_before(
            source_pack_dispatch,
            "compile_source_pack_library_manifest_with_descriptor_queue(",
            "compile_source_pack_manifest_with_descriptor_queue("
        ),
        "main CLI must dispatch streaming library manifests before full JSON path manifests"
    );
    assert!(
        source_before(
            source_pack_dispatch,
            "compile_source_pack_library_manifest_with_descriptor_queue(",
            "if source_pack.legacy_in_memory"
        ),
        "main CLI must dispatch streaming library-manifest source packs before stdlib/user source-pack modes"
    );
    assert!(
        source_before(
            source_pack_dispatch,
            "compile_source_pack_manifest_with_descriptor_queue(",
            "if source_pack.legacy_in_memory"
        ),
        "main CLI must dispatch manifest source packs before stdlib/user source-pack modes"
    );
    assert!(
        source_before(
            source_pack_dispatch,
            "if source_pack.legacy_in_memory",
            "compile_source_pack_with_descriptor_queue("
        ),
        "main CLI must check the explicit legacy flag before running the descriptor default"
    );
    assert!(
        !source_pack_dispatch.contains("compile_explicit_source_pack_paths_legacy_in_memory"),
        "main CLI source-pack dispatch must not directly call legacy whole-pack helpers"
    );

    let descriptor_queue = source_between(
        &main,
        "fn compile_source_pack_with_descriptor_queue",
        "fn compile_source_pack_manifest_with_descriptor_queue",
    );
    assert!(
        descriptor_queue.contains("require_source_pack_artifact_root(")
            && descriptor_queue.contains("source_pack_artifact_root_has_prepared_build(")
            && descriptor_queue.contains("source_pack_artifact_root_has_prepared_metadata(")
            && descriptor_queue
                .contains("require_source_pack_prepared_metadata_for_direct_compile(")
            && descriptor_queue.contains("compile_prepared_source_pack_descriptor_queue(")
            && descriptor_queue
                .contains("compile_source_pack_from_metadata_artifact_root_with_descriptor_queue("),
        "main CLI descriptor mode must require an explicit artifact root and resume prepared metadata/queues"
    );
    assert!(
        source_before(
            descriptor_queue,
            "require_source_pack_artifact_root(",
            "source_pack_artifact_root_has_prepared_build("
        ) && source_before(
            descriptor_queue,
            "source_pack_artifact_root_has_prepared_build(",
            "source_pack_artifact_root_has_prepared_metadata("
        ) && source_before(
            descriptor_queue,
            "source_pack_artifact_root_has_prepared_metadata(",
            "require_source_pack_prepared_metadata_for_direct_compile("
        ),
        "main CLI stdlib/user descriptor mode must require an artifact root, then resume existing prepared metadata or queues before failing"
    );
    assert!(
        !descriptor_queue.contains(
            "execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors("
        ) && !descriptor_queue.contains(
            "execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_to_x86_64_with_gpu_descriptors("
        ),
        "main CLI descriptor mode must not prepare and submit raw source-pack paths in one compile invocation"
    );
    assert!(
        !descriptor_queue.contains("compile_explicit_source_pack_paths_legacy_in_memory"),
        "main CLI descriptor mode must not fall back to the legacy whole-pack compiler"
    );

    let metadata_only = source_between(
        &main,
        "fn prepare_source_pack_metadata_only",
        "fn compile_source_pack_legacy_in_memory",
    );
    assert!(
        metadata_only.contains("require_source_pack_artifact_root(")
            && metadata_only.contains("source_pack_artifact_root_has_prepared_metadata(")
            && metadata_only.contains(
                "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_from_progress_for_target("
            )
            && metadata_only.contains(
                "prepare_source_pack_filesystem_artifact_build_from_metadata_chunk_with_shard_limits_for_target("
            )
            && metadata_only.contains("require_source_pack_prepared_build_for_descriptor_compile(")
            && metadata_only.contains("compile_prepared_source_pack_descriptor_queue(")
            && metadata_only.contains("--source-pack-metadata-only with raw --stdlib or positional source paths would prepare a whole path list")
            && !metadata_only
                .contains("prepare_explicit_source_pack_paths_filesystem_metadata_for_target("),
        "main CLI metadata phases must expose bounded metadata-only preparation, chunked build-from-metadata preparation, and prepared descriptor execution without raw path-list preparation"
    );
    assert!(
        main.contains("--source-pack-build-prepare-only")
            && main.contains("--source-pack-prepare-only")
            && main.contains("--source-pack-build-max-items")
            && metadata_only.contains("fn prepare_source_pack_build_from_metadata_chunk_only")
            && metadata_only.contains("source_pack_build_max_items(source_pack)")
            && metadata_only.contains("stage={:?} next_stage={:?} new_items={}")
            && metadata_only.contains("return Ok(());"),
        "main CLI must expose a one-chunk build-from-metadata preparation mode with a bounded item count"
    );
    let direct_prepare_only = source_between(
        &main,
        "fn prepare_source_pack_inputs_chunk_only",
        "fn compile_source_pack_from_metadata_with_descriptor_queue",
    );
    assert!(
        direct_prepare_only
            .contains("--source-pack-prepare-only requires --source-pack-artifact-root")
            && direct_prepare_only.contains("source_pack_artifact_root_has_prepared_metadata(")
            && direct_prepare_only.contains("source_pack_metadata_max_libraries(source_pack)")
            && direct_prepare_only.contains("source_pack_metadata_max_source_files(source_pack)")
            && direct_prepare_only.contains("prepare_source_pack_metadata_chunk(")
            && direct_prepare_only.contains("prepare_source_pack_build_from_metadata_chunk_only(")
            && direct_prepare_only.contains("--source-pack-prepare-only with raw --stdlib or positional source paths would prepare a whole path list")
            && !direct_prepare_only.contains("prepare_source_pack_metadata_only("),
        "main CLI source-pack prepare-only mode must advance bounded JSONL source metadata chunks before build-preparation chunks and reject raw path-list preparation"
    );
    assert!(
        source_before(
            direct_prepare_only,
            "source_pack_artifact_root_has_prepared_metadata(",
            "prepare_source_pack_metadata_chunk("
        ) && source_before(
            direct_prepare_only,
            "prepare_source_pack_metadata_chunk(",
            "prepare_source_pack_build_from_metadata_chunk_only("
        ),
        "main CLI source-pack prepare-only mode must finish persisted metadata before preparing build records"
    );
    let metadata_chunk = source_between(
        &main,
        "fn prepare_source_pack_metadata_chunk",
        "fn prepare_source_pack_build_from_metadata_chunk_only",
    );
    assert!(
        metadata_chunk
            .contains("source_pack_artifact_root_persisted_library_partition_prefix_count(")
            && metadata_chunk
                .contains("load_source_pack_library_manifest_read_progress_or_default(")
            && metadata_chunk
                .contains("load_source_pack_library_manifest_entries_chunk_from_offset(")
            && metadata_chunk.contains("max_new_source_files")
            && metadata_chunk.contains("progress.next_byte_offset")
            && metadata_chunk.contains("store_source_pack_library_manifest_read_progress(")
            && metadata_chunk
                .contains("source_pack_library_manifest_prefix_path_dependency_streams(")
            && metadata_chunk.contains("manifest_complete_after_input")
            && metadata_chunk.contains(
                "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_from_progress_for_target("
            )
            && metadata_chunk.contains("use --source-pack-library-manifest")
            && !metadata_chunk.contains("fs::read(manifest_path)")
            && !metadata_chunk.contains("load_source_pack_library_manifest_entries_prefix(")
            && !metadata_chunk.contains("load_source_pack_library_manifest_entries("),
        "main CLI source-pack metadata chunks must seek to the persisted JSONL byte offset and read only the bounded new-library/source-file window"
    );
    let metadata_progress = source_between(
        &compiler,
        "pub struct SourcePackFilesystemLibraryMetadataPrepareProgress",
        "pub struct SourcePackFilesystemLibrarySchedulePrepareStepResult",
    );
    let metadata_progress_store = source_between(
        &compiler,
        "pub fn store_library_metadata_prepare_progress",
        "pub fn load_library_partition_for_target",
    );
    assert!(
        metadata_progress.contains("library_partition_count")
            && metadata_progress.contains("source_file_count")
            && metadata_progress.contains("source_byte_count")
            && metadata_progress_store.contains("store_library_metadata_prepare_progress(")
            && metadata_progress_store
                .contains("load_library_metadata_prepare_progress_for_target(")
            && metadata_progress_store.contains("source-pack library metadata prepare progress"),
        "compiler must persist source-pack metadata chunk progress so resumed chunks do not replay all previous library partitions"
    );
    assert!(
        !direct_prepare_only.contains("compile_prepared_source_pack_descriptor_queue(")
            && !direct_prepare_only.contains(
                "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors("
            )
            && !direct_prepare_only.contains(
                "execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors("
            ),
        "main CLI source-pack prepare-only mode must not submit descriptor work"
    );
    assert!(
        source_before(
            metadata_only,
            "source_pack_artifact_root_has_prepared_metadata(",
            "prepare_source_pack_metadata_chunk("
        ) && metadata_only.contains("source_pack_metadata_max_libraries(source_pack)")
            && metadata_only.contains("source_pack_metadata_max_source_files(source_pack)")
            && !metadata_only
                .contains("load_source_pack_library_manifest_entries(library_manifest_path)"),
        "main CLI metadata-only mode must accept completed persisted metadata before reading inputs and must chunk JSONL library manifests by default"
    );
    let compile_from_metadata = source_between(
        &main,
        "fn compile_source_pack_from_metadata_with_descriptor_queue",
        "fn require_source_pack_artifact_root",
    );
    assert!(
        compile_from_metadata.contains("require_source_pack_prepared_build_for_descriptor_compile(")
            && compile_from_metadata.contains("compile_prepared_source_pack_descriptor_queue(")
            && !compile_from_metadata.contains(
                "prepare_source_pack_filesystem_artifact_build_from_metadata_with_shard_limits_for_target("
            )
            &&
        source_before(
            compile_from_metadata,
            "require_source_pack_prepared_build_for_descriptor_compile(",
            "compile_prepared_source_pack_descriptor_queue("
        ),
        "main CLI build-from-metadata mode must submit descriptor work only after a persisted build queue exists"
    );
    let prepared_build_requirement = source_between(
        &main,
        "fn require_source_pack_prepared_build_for_descriptor_compile",
        "fn source_pack_artifact_target",
    );
    assert!(
        prepared_build_requirement.contains("source_pack_artifact_root_has_prepared_build(")
            && prepared_build_requirement
                .contains("--source-pack-build-from-metadata --source-pack-build-prepare-only")
            && !prepared_build_requirement.contains(
                "prepare_source_pack_filesystem_artifact_build_from_metadata_with_shard_limits_for_target("
            ),
        "main CLI build-from-metadata mode must require an already prepared work queue instead of preparing all metadata-derived records in the compile path"
    );
    assert!(
        !metadata_only.contains("compile_explicit_source_pack_paths_legacy_in_memory")
            && !metadata_only.contains("compile_source_pack_legacy_in_memory(")
            && !metadata_only.contains(
                "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors("
            )
            && !source_between(
                metadata_only,
                "fn prepare_source_pack_build_from_metadata_chunk_only",
                "fn compile_source_pack_from_metadata_with_descriptor_queue"
            )
            .contains("compile_prepared_source_pack_descriptor_queue("),
        "main CLI metadata-only/build-from-metadata helpers must not fall back to legacy whole-pack compilation or submit descriptor work from prepare-only mode"
    );

    let library_manifest_descriptor_queue = source_between(
        &main,
        "fn compile_source_pack_library_manifest_with_descriptor_queue",
        "fn compile_source_pack_manifest_with_descriptor_queue",
    );
    assert!(
        library_manifest_descriptor_queue
            .contains("require_source_pack_prepared_metadata_for_manifest_compile(")
            && library_manifest_descriptor_queue
                .contains("compile_source_pack_from_metadata_artifact_root_with_descriptor_queue(")
            && !library_manifest_descriptor_queue
                .contains("load_source_pack_library_manifest_entries(")
            && !library_manifest_descriptor_queue.contains(
                "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors("
            )
            && !library_manifest_descriptor_queue.contains(
                "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_to_x86_64_with_gpu_descriptors("
            ),
        "main CLI streaming library-manifest compile mode must resume persisted metadata/build queues instead of parsing the whole manifest during compile"
    );
    assert!(
        source_before(
            library_manifest_descriptor_queue,
            "source_pack_artifact_root_has_prepared_build(",
            "source_pack_artifact_root_has_prepared_metadata("
        ) && source_before(
            library_manifest_descriptor_queue,
            "source_pack_artifact_root_has_prepared_metadata(",
            "require_source_pack_prepared_metadata_for_manifest_compile("
        ),
        "main CLI streaming library-manifest mode must resume from persisted records and require explicit prepare-only metadata before descriptor execution"
    );
    assert!(
        !library_manifest_descriptor_queue
            .contains("compile_explicit_source_pack_paths_legacy_in_memory")
            && !library_manifest_descriptor_queue.contains("compile_source_pack_legacy_in_memory("),
        "main CLI streaming library-manifest descriptor mode must not fall back to legacy whole-pack compilation"
    );

    let manifest_descriptor_queue = source_between(
        &main,
        "fn compile_source_pack_manifest_with_descriptor_queue",
        "fn compile_prepared_source_pack_descriptor_queue",
    );
    assert!(
        manifest_descriptor_queue
            .contains("require_source_pack_prepared_metadata_for_manifest_compile(")
            && manifest_descriptor_queue
                .contains("compile_source_pack_from_metadata_artifact_root_with_descriptor_queue(")
            && !manifest_descriptor_queue
                .contains("serde_json::from_slice::<ExplicitSourcePackPathManifest>")
            && !manifest_descriptor_queue
                .contains("source_pack_manifest_ordered_path_dependency_streams(manifest)")
            && !manifest_descriptor_queue.contains(
                "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors("
            )
            && !manifest_descriptor_queue.contains(
                "execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_to_x86_64_with_gpu_descriptors("
            ),
        "main CLI manifest compile mode must resume persisted metadata/build queues instead of parsing the whole JSON manifest during compile"
    );
    assert!(
        manifest_descriptor_queue.contains("source_pack_artifact_root_has_prepared_build(")
            && manifest_descriptor_queue
                .contains("source_pack_artifact_root_has_prepared_metadata(")
            && manifest_descriptor_queue.contains("compile_prepared_source_pack_descriptor_queue("),
        "main CLI manifest descriptor mode must resume existing prepared metadata or queues from the artifact root"
    );
    assert!(
        source_before(
            manifest_descriptor_queue,
            "source_pack_artifact_root_has_prepared_build(",
            "source_pack_artifact_root_has_prepared_metadata("
        ) && source_before(
            manifest_descriptor_queue,
            "source_pack_artifact_root_has_prepared_metadata(",
            "require_source_pack_prepared_metadata_for_manifest_compile("
        ),
        "main CLI manifest descriptor mode must resume from persisted records and require explicit prepare-only metadata before descriptor execution"
    );
    assert!(
        !manifest_descriptor_queue.contains("ExplicitSourceLibraryPathDependencyStream")
            && !manifest_descriptor_queue.contains("visit_source_pack_manifest_library("),
        "main CLI manifest compile mode must not rebuild library dependency streams after metadata has been prepared"
    );
    assert!(
        !manifest_descriptor_queue.contains("compile_explicit_source_pack_paths_legacy_in_memory")
            && !manifest_descriptor_queue.contains("compile_source_pack_legacy_in_memory("),
        "main CLI manifest descriptor mode must not fall back to legacy whole-pack compilation"
    );

    let prepared_descriptor_queue = source_between(
        &main,
        "fn compile_prepared_source_pack_descriptor_queue",
        "fn load_source_pack_library_manifest_entries",
    );
    assert!(
        prepared_descriptor_queue.contains(
            "execute_prepared_source_pack_filesystem_work_queue_worker_run_to_wasm_with_gpu_descriptors("
        ) && prepared_descriptor_queue.contains(
            "execute_prepared_source_pack_filesystem_work_queue_worker_run_to_x86_64_with_gpu_descriptors("
        ) && prepared_descriptor_queue.contains("let max_items = source_pack_max_items(source_pack)")
            && prepared_descriptor_queue
                .contains("let max_ready_items = source_pack_max_ready_items(source_pack)")
            && !prepared_descriptor_queue.contains("source_pack.max_items")
            && !prepared_descriptor_queue.contains("source_pack.max_ready_items")
            && prepared_descriptor_queue.contains("complete_source_pack_output_path(artifact_root, run)"),
        "main CLI prepared descriptor mode must submit additional work directly from persisted queue state and return the completed linked-output path"
    );
    assert!(
        prepared_descriptor_queue.contains("SourcePackFilesystemArtifactStore::new(artifact_root)")
            && prepared_descriptor_queue
                .contains("build_state_path_for_target(source_pack_artifact_target(emit))")
            && prepared_descriptor_queue.contains("SourcePackArtifactTarget::Wasm")
            && prepared_descriptor_queue.contains("SourcePackArtifactTarget::X86_64"),
        "main CLI resume detection must be target-specific and based on persisted build-state records"
    );
    assert!(
        prepared_descriptor_queue.contains("source_pack_artifact_root_has_prepared_metadata(")
            && prepared_descriptor_queue.contains(
                "library_partition_index_path_for_target(source_pack_artifact_target(emit))"
            ),
        "main CLI metadata resume detection must be target-specific and based on persisted library partition index records"
    );

    let library_manifest_streaming = source_between(
        &main,
        "fn load_source_pack_library_manifest_entries_chunk_from_offset",
        "fn source_pack_manifest_ordered_path_dependency_streams",
    );
    assert!(
        library_manifest_streaming
            .contains("serde_json::from_str::<SourcePackLibraryPathManifestEntry>")
            && library_manifest_streaming.contains("file.seek(SeekFrom::Start(start_byte_offset))")
            && library_manifest_streaming.contains("read_source_pack_library_manifest_line(")
            && library_manifest_streaming
                .contains("SourcePackPathListFile::deferred(entry.path_list)")
            && library_manifest_streaming.contains("max_source_files")
            && library_manifest_streaming.contains("new_source_file_count")
            && library_manifest_streaming.contains("next_source_file_count > max_source_files")
            && library_manifest_streaming.contains("next_byte_offset: line_start")
            && library_manifest_streaming.contains("dependency_library_count"),
        "main CLI streaming library-manifest mode must parse bounded top-level library/source-file records from a byte offset and stream per-library path lists into dependency streams"
    );
    assert!(
        !library_manifest_streaming.contains("ExplicitSourcePackPathManifest")
            && !library_manifest_streaming.contains("validate_source_pack_path_list_file(")
            && !library_manifest_streaming.contains("SourcePackPathListFile::new(")
            && !library_manifest_streaming.contains("reader.read_line(&mut line)")
            && !library_manifest_streaming.contains("BufReader::new(file).lines()")
            && !library_manifest_streaming.contains("Vec<PathBuf>>::new()"),
        "main CLI streaming library-manifest mode must not materialize a whole source-pack path manifest, pre-scan every path-list file, or flatten path lists"
    );
    let library_manifest_line_reader = source_between(
        &main,
        "fn source_pack_library_manifest_offset_after_entry_count",
        "fn source_pack_library_manifest_prefix_path_dependency_streams",
    );
    assert!(
        main.contains("const SOURCE_PACK_LIBRARY_MANIFEST_MAX_LINE_BYTES")
            && main.contains("const SOURCE_PACK_LIBRARY_MANIFEST_MAX_BLANK_LINES_PER_CHUNK")
            && library_manifest_line_reader.contains("read_source_pack_library_manifest_line(")
            && library_manifest_line_reader.contains(".fill_buf()")
            && library_manifest_line_reader.contains(".consume(take_len)")
            && library_manifest_line_reader.contains("exceeds line byte limit")
            && library_manifest_line_reader.contains("blank_line_count")
            && library_manifest_line_reader.contains("trailing_blank_line_count")
            && !library_manifest_line_reader.contains("reader.read_line(&mut line)"),
        "main CLI library-manifest replay/chunk readers must bound each manifest record line and blank-line run before parsing JSON"
    );
    let library_manifest_path_list =
        source_between(&main, "impl SourcePackPathListFile", "fn main()");
    assert!(
        library_manifest_path_list.contains("fn deferred(path: PathBuf) -> Self")
            && library_manifest_path_list.contains("fn into_iter(self) -> Self::IntoIter")
            && library_manifest_path_list.contains("BufReader::new(fs::File::open(&self.path)")
            && library_manifest_path_list.contains("read_source_pack_path_list_line(")
            && library_manifest_path_list.contains("SOURCE_PACK_PATH_LIST_MAX_LINE_BYTES")
            && library_manifest_path_list
                .contains("SOURCE_PACK_PATH_LIST_MAX_BLANK_LINES_PER_ITEM")
            && library_manifest_path_list.contains("blank_line_count")
            && library_manifest_path_list
                .contains("panic!(\"open source-pack path list {}: {err}\", self.path.display())",),
        "main CLI path-list wrapper must defer opening each path-list file until descriptor metadata preparation consumes that library and bound each path-list record"
    );
    assert!(
        !library_manifest_path_list.contains(".lines()")
            && !library_manifest_path_list.contains("reader.read_line("),
        "main CLI path-list wrapper must not use unbounded line readers"
    );
    let source_file_record_writer = source_between(
        &compiler,
        "fn store_source_pack_library_source_file_record_pages_from_paths",
        "fn source_pack_compact_library_source_file_page_from_partition",
    );
    assert!(
        source_file_record_writer.contains("if path_index >= source_file_count")
            && source_file_record_writer.contains("yielded more than {source_file_count} source files")
            && source_file_record_writer.contains("stored {stored_source_file_count} source-file records but expected {source_file_count}")
            && source_file_record_writer.contains("store.store_library_source_file_record_page(&record)"),
        "persisted source-file record writer must enforce declared path counts while streaming source-file records"
    );

    let linked_output = source_between(
        &main,
        "fn complete_source_pack_output_path",
        "fn print_help",
    );
    assert!(
        linked_output.contains("run.progress.complete")
            && linked_output.contains("run.linked_output_path")
            && linked_output.contains("linked_output_path.is_file()")
            && !linked_output.contains("fs::read("),
        "main CLI descriptor mode must return a completed persisted linked-output artifact path without materializing final bytes"
    );
    let cli_emission = source_between(
        &main,
        "fn write_cli_emission",
        "fn prepare_source_pack_inputs_chunk_only",
    );
    assert!(
        cli_emission.contains("CliEmission::File(path)")
            && cli_emission.contains("fs::copy(&path, &output)")
            && cli_emission.contains("std::io::copy(&mut file, &mut std::io::stdout())")
            && !cli_emission.contains("fs::read("),
        "main CLI must copy or stream descriptor linked-output files instead of reading them into memory"
    );
}

#[test]
fn gpu_bench_source_pack_descriptor_mode_uses_prepared_step_queue() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let bench_path = root.join("src/bin/gpu_compile_bench.rs");
    let bench = fs::read_to_string(&bench_path)
        .unwrap_or_else(|err| panic!("read {}: {err}", bench_path.display()));

    let descriptor_phase = source_between(
        &bench,
        "async fn run_source_pack_descriptor_phase",
        "fn source_pack_artifact_target_for_phase",
    );
    assert!(
        descriptor_phase.contains(
            "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_from_progress_for_target("
        ) && descriptor_phase.contains(
            "prepare_source_pack_filesystem_artifact_build_from_metadata_chunk_with_shard_limits_for_target("
        ) && descriptor_phase.contains("SourcePackFilesystemPreparedArtifactBuild::new(")
            && descriptor_phase.contains("bounded_max_items()")
            && descriptor_phase.contains("bounded_max_ready_items()"),
        "module-pack descriptor benchmark mode must advance persisted metadata/build preparation in bounded chunks before opening the work queue"
    );
    assert!(
        !descriptor_phase.contains(
            "prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target("
        ),
        "module-pack descriptor benchmark mode must not run the full artifact-build convenience prepare path"
    );
    assert!(
        descriptor_phase.contains("submit_gpu_descriptor_work_queue_step_using("),
        "module-pack descriptor benchmark mode must advance the persisted queue one work item at a time"
    );
    assert!(
        !descriptor_phase.contains("compile_source_pack_to_wasm")
            && !descriptor_phase.contains("compile_source_pack_to_x86_64")
            && !descriptor_phase.contains("type_check_source_pack("),
        "module-pack descriptor benchmark mode must not fall back to whole-pack in-memory compile/typecheck calls"
    );

    let source_pack_dispatch = source_between(
        &bench,
        "async fn run_phase",
        "async fn run_source_pack_phase",
    );
    assert!(
        source_pack_dispatch.contains("if let Some(config) = source_pack_descriptor_config")
            && source_pack_dispatch.contains("if !source_pack_legacy_in_memory")
            && source_pack_dispatch.contains("source_pack_execution_mode_required_error("),
        "module-pack benchmark dispatch must require an explicit legacy flag before using whole-pack in-memory compilation"
    );
    assert!(
        source_before(
            source_pack_dispatch,
            "if !source_pack_legacy_in_memory",
            "return run_source_pack_phase("
        ),
        "module-pack benchmark dispatch must reject the implicit legacy path before calling run_source_pack_phase"
    );
    let mode_error = source_between(
        &bench,
        "fn source_pack_execution_mode_required_error",
        "fn source_pack_descriptor_artifact_root",
    );
    assert!(
        mode_error.contains("--source-pack-descriptors")
            && mode_error.contains("--source-pack-legacy-in-memory"),
        "module-pack benchmark missing-mode error must name the bounded and explicit legacy modes"
    );

    let descriptor_limits =
        source_between(&bench, "impl SourcePackDescriptorRunConfig", "fn main()");
    assert!(
        bench.contains("const SOURCE_PACK_DESCRIPTOR_MAX_CHUNK_ITEMS: usize = 64;")
            && descriptor_limits.contains("fn bounded_max_items")
            && descriptor_limits.contains(".max(1)")
            && descriptor_limits.contains(".min(SOURCE_PACK_DESCRIPTOR_MAX_CHUNK_ITEMS)")
            && descriptor_limits.contains("fn bounded_max_ready_items")
            && descriptor_limits.contains(".min(DEFAULT_SOURCE_PACK_DESCRIPTOR_MAX_READY_ITEMS)"),
        "module-pack descriptor benchmark mode must cap oversized prepare/submit windows to bounded defaults"
    );

    let materialize_paths = source_between(
        &bench,
        "fn materialize_generated_source_pack_paths",
        "impl SourceMode",
    );
    assert!(
        materialize_paths.contains("ExplicitSourceLibraryPathDependencyStream"),
        "module-pack descriptor benchmark inputs must stay grouped as explicit library path dependency streams"
    );
    assert!(
        materialize_paths.contains("source_file_count: paths.len()")
            && materialize_paths.contains("dependency_library_count: dependency_library_ids.len()"),
        "module-pack descriptor benchmark path streams must carry per-library source and dependency counts"
    );
}

fn source_between<'a>(source: &'a str, start: &str, end: &str) -> &'a str {
    let start_index = source
        .find(start)
        .unwrap_or_else(|| panic!("missing source marker {start:?}"));
    let rest = &source[start_index..];
    let end_index = rest
        .find(end)
        .unwrap_or_else(|| panic!("missing source marker {end:?} after {start:?}"));
    &rest[..end_index]
}

fn source_between_last<'a>(source: &'a str, start: &str, end: &str) -> &'a str {
    let start_index = source
        .rfind(start)
        .unwrap_or_else(|| panic!("missing source marker {start:?}"));
    let rest = &source[start_index..];
    let end_index = rest
        .find(end)
        .unwrap_or_else(|| panic!("missing source marker {end:?} after last {start:?}"));
    &rest[..end_index]
}

fn source_after<'a>(source: &'a str, start: &str) -> &'a str {
    let start_index = source
        .find(start)
        .unwrap_or_else(|| panic!("missing source marker {start:?}"));
    &source[start_index..]
}

fn source_before(source: &str, earlier: &str, later: &str) -> bool {
    let earlier_index = source
        .find(earlier)
        .unwrap_or_else(|| panic!("missing source marker {earlier:?}"));
    let later_index = source
        .find(later)
        .unwrap_or_else(|| panic!("missing source marker {later:?}"));
    earlier_index < later_index
}

fn collect_files(dir: &Path, files: &mut Vec<PathBuf>) {
    for entry in fs::read_dir(dir).unwrap_or_else(|err| panic!("read {}: {err}", dir.display())) {
        let path = entry.expect("read directory entry").path();
        if path.is_dir() {
            collect_files(&path, files);
        } else if matches!(
            path.extension().and_then(|ext| ext.to_str()),
            Some("rs" | "slang")
        ) {
            files.push(path);
        }
    }
}
