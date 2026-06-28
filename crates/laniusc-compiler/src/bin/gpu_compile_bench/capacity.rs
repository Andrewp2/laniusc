use laniusc_compiler::{
    codegen::{
        unit::{
            CodegenUnitLimits,
            SourcePackArtifactTarget,
            SourcePackJobBatchLimits,
            SourcePackJobPlan,
            SourcePackLibraryDependency,
        },
        x86::{
            X86CapacityEstimate,
            x86_call_type_record_words,
            x86_capacity_estimate_for_hir_and_tokens,
            x86_capacity_estimate_for_hir_tokens_and_inst_basis,
            x86_function_slot_capacity,
            x86_node_inst_count_record_words,
            x86_node_inst_gen_node_record_words,
            x86_node_inst_order_record_words,
        },
    },
    compiler::GpuLiveCapacityEstimateResult,
    lexer::test_cpu::lex_on_test_cpu,
    parser::tables::PrecomputedParseTables,
};

use super::Phase;

pub(super) const RESIDENT_TREE_PRODUCTION_CAPACITY_PER_TOKEN: usize = 10;
pub(super) const TYPECHECK_TYPE_INSTANCE_ARG_REF_STRIDE: usize = 4;
pub(super) const TYPECHECK_CALL_ARG_SLOT_STRIDE: usize = 4;
pub(super) const TYPECHECK_NAME_RADIX_BUCKETS: usize = 257;
pub(super) const TYPECHECK_LANGUAGE_SYMBOL_COUNT: usize = 20;
pub(super) const TYPECHECK_HIR_VISIBLE_DECL_ROW_BLOCK_SIZE: usize = 64;

pub(super) const PARALLEL_PASS_CONTRACT_SCHEMA: &str = "lanius.parallel-pass-contracts.v1";
pub(super) const PARALLEL_PASS_CONTRACT_POLICY: &str =
    "scale-claims-require-map-scan-scatter-join-contracts";
pub(super) const PARALLEL_PASS_CONTRACT_ORDER_POLICY: &str =
    "paper-pass-order-record-boundary-sequence";
pub(super) const PARALLEL_PASS_CONTRACT_EXECUTION_ORDER: &str = concat!(
    "frontend_token_stream,",
    "parser_tree_records,",
    "semantic_record_joins,",
    "x86_value_location_allocation,",
    "optimization_record_boundary_gap,",
    "x86_location_and_byte_emission"
);
pub(super) const PARALLEL_PASS_CONTRACT_STATUS_SCHEMA: &str =
    "lanius.parallel-pass-contract-status.v1";
pub(super) const PARALLEL_PASS_CONTRACT_LOOP_POLICY: &str =
    "scale-claims-require-unbounded-pass-loops";
pub(super) const PARALLEL_PASS_CONTRACT_LOOP_STATUS: &str = "bounded";
pub(super) const PARALLEL_PASS_CONTRACT_FALLBACK_STATUS: &str = "fail-closed";
pub(super) const PARALLEL_PASS_CONTRACT_CLAIM_STATUS: &str = "blocked";
pub(super) const PARALLEL_PASS_CONTRACT_CLAIM_BLOCKERS: &str =
    "bounded_pass_loops,fail_closed_passes";
pub(super) const PARALLEL_PASS_CONTRACT_READINESS_STATUS: &str = "blocked";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) struct ParallelPassContract {
    pub(super) pass_group: &'static str,
    pub(super) record_boundary: &'static str,
    pub(super) parallel_primitives: &'static str,
    pub(super) evidence_shape: &'static str,
    pub(super) claim_boundary: &'static str,
}

const PARALLEL_PASS_CONTRACTS: &[ParallelPassContract] = &[
    ParallelPassContract {
        pass_group: "frontend_token_stream",
        record_boundary: "ordered_token_records",
        parallel_primitives: "map,scan",
        evidence_shape: "record-invariant",
        claim_boundary: "no-host-semantic-fallback",
    },
    ParallelPassContract {
        pass_group: "parser_tree_records",
        record_boundary: "tree_and_span_records",
        parallel_primitives: "map,scan,scatter",
        evidence_shape: "record-invariant",
        claim_boundary: "no-host-semantic-fallback",
    },
    ParallelPassContract {
        pass_group: "semantic_record_joins",
        record_boundary: "typed_identity_records",
        parallel_primitives: "sort,join,scatter",
        evidence_shape: "semantic-contract",
        claim_boundary: "no-host-semantic-fallback",
    },
    ParallelPassContract {
        pass_group: "x86_value_location_allocation",
        record_boundary: "virtual_value_live_interval_and_location_records",
        parallel_primitives: "map,scan,sort,join,scatter",
        evidence_shape: "execution-contract",
        claim_boundary: "no-serial-regalloc-replay",
    },
    ParallelPassContract {
        pass_group: "optimization_record_boundary_gap",
        record_boundary: "missing_optimization_records",
        parallel_primitives: "planned-gap",
        evidence_shape: "measurement-scaffold",
        claim_boundary: "optimization-contract-absent",
    },
    ParallelPassContract {
        pass_group: "x86_location_and_byte_emission",
        record_boundary: "instruction_location_and_byte_records",
        parallel_primitives: "map,scan,scatter",
        evidence_shape: "execution-contract",
        claim_boundary: "no-host-byte-patching",
    },
];

pub(super) fn parallel_pass_contracts() -> &'static [ParallelPassContract] {
    PARALLEL_PASS_CONTRACTS
}

pub(super) fn print_parallel_pass_contract_estimate() {
    println!(
        "estimate parallel_pass_contract_schema={} policy={} order_policy={} execution_order={}",
        PARALLEL_PASS_CONTRACT_SCHEMA,
        PARALLEL_PASS_CONTRACT_POLICY,
        PARALLEL_PASS_CONTRACT_ORDER_POLICY,
        PARALLEL_PASS_CONTRACT_EXECUTION_ORDER,
    );
    println!(
        "estimate parallel_pass_contract_status_schema={} loop_policy={} loop_status={} fallback_status={} claim_status={} claim_blockers={} readiness_status={}",
        PARALLEL_PASS_CONTRACT_STATUS_SCHEMA,
        PARALLEL_PASS_CONTRACT_LOOP_POLICY,
        PARALLEL_PASS_CONTRACT_LOOP_STATUS,
        PARALLEL_PASS_CONTRACT_FALLBACK_STATUS,
        PARALLEL_PASS_CONTRACT_CLAIM_STATUS,
        PARALLEL_PASS_CONTRACT_CLAIM_BLOCKERS,
        PARALLEL_PASS_CONTRACT_READINESS_STATUS,
    );
    for contract in parallel_pass_contracts() {
        println!(
            "estimate parallel_pass_contract pass_group={} record_boundary={} parallel_primitives={} evidence_shape={} loop_status={} fallback_status={} claim_boundary={}",
            contract.pass_group,
            contract.record_boundary,
            contract.parallel_primitives,
            contract.evidence_shape,
            PARALLEL_PASS_CONTRACT_LOOP_STATUS,
            PARALLEL_PASS_CONTRACT_FALLBACK_STATUS,
            contract.claim_boundary,
        );
    }
}

pub(super) fn reject_large_interactive_run(
    phase: Phase,
    source_lines: usize,
    src: &str,
    source_file_capacity: usize,
    allow_large: bool,
    tables: Option<&PrecomputedParseTables>,
) -> Result<(), String> {
    const MAX_INTERACTIVE_LINES: usize = 20_000;
    const MAX_INTERACTIVE_BYTES: usize = 2_000_000;
    const MAX_INTERACTIVE_PARSER_TREE_FLOOR_BYTES: usize = 2 * 1024 * 1024 * 1024;
    const MAX_INTERACTIVE_FRONTEND_FLOOR_BYTES: usize = 2 * 1024 * 1024 * 1024;
    const MAX_INTERACTIVE_COMPILE_FLOOR_BYTES: usize = 3 * 1024 * 1024 * 1024;
    if allow_large {
        return Ok(());
    }

    let source_bytes = src.len();
    let token_capacity = token_capacity_estimate_for_source(src);
    let estimate =
        parser_capacity_estimate_for_token_capacity(token_capacity.parser_token_capacity, tables);
    let floor_bytes = parser_tree_floor_bytes(estimate.tree_capacity);
    let parser_floor = parser_allocation_floor_bytes(&estimate);
    let typecheck_floor = typecheck_allocation_floor_bytes(
        token_capacity.lexer_token_capacity,
        estimate.tree_capacity,
        true,
        source_file_capacity,
    );
    let frontend_floor = parser_floor.total.saturating_add(typecheck_floor.total);
    if phase == Phase::X86 {
        let x86_capacity = x86_capacity_estimate_for_hir_and_tokens(
            estimate.tree_capacity,
            token_capacity.lexer_token_capacity,
        );
        let x86_floor =
            x86_allocation_floor_bytes(token_capacity.lexer_token_capacity, &x86_capacity);
        let compile_floor = frontend_floor.saturating_add(x86_floor.total);
        if compile_floor > MAX_INTERACTIVE_COMPILE_FLOOR_BYTES {
            return Err(format!(
                "refusing large interactive GPU benchmark: lines={source_lines} bytes={source_bytes}; estimated compile allocation floor={} (parser={} typecheck={} x86={}) via {} token_capacity_basis={}; pass --allow-large to run it intentionally",
                human_bytes(compile_floor),
                human_bytes(parser_floor.total),
                human_bytes(typecheck_floor.total),
                human_bytes(x86_floor.total),
                estimate.path,
                token_capacity.basis
            ));
        }
    }
    if matches!(phase, Phase::TypeCheck | Phase::Wasm | Phase::X86)
        && frontend_floor > MAX_INTERACTIVE_FRONTEND_FLOOR_BYTES
    {
        return Err(format!(
            "refusing large interactive GPU benchmark: lines={source_lines} bytes={source_bytes}; estimated frontend allocation floor={} (parser={} typecheck={}) via {} token_capacity_basis={}; pass --allow-large to run it intentionally",
            human_bytes(frontend_floor),
            human_bytes(parser_floor.total),
            human_bytes(typecheck_floor.total),
            estimate.path,
            token_capacity.basis
        ));
    }

    if matches!(
        phase,
        Phase::Parse | Phase::TypeCheck | Phase::Wasm | Phase::X86
    ) && floor_bytes > MAX_INTERACTIVE_PARSER_TREE_FLOOR_BYTES
    {
        return Err(format!(
            "refusing large interactive GPU benchmark: lines={source_lines} bytes={source_bytes}; estimated parser tree floor={} via {} token_capacity_basis={}; pass --allow-large to run it intentionally",
            human_bytes(floor_bytes),
            estimate.path,
            token_capacity.basis
        ));
    }

    if source_lines <= MAX_INTERACTIVE_LINES && source_bytes <= MAX_INTERACTIVE_BYTES {
        return Ok(());
    }

    Err(format!(
        "refusing large interactive GPU benchmark: lines={source_lines} bytes={source_bytes}; estimated parser tree floor={} via {} token_capacity_basis={}; pass --allow-large to run it intentionally",
        human_bytes(floor_bytes),
        estimate.path,
        token_capacity.basis
    ))
}

pub(super) fn print_capacity_estimate(
    source_lines: usize,
    src: &str,
    sources: &[String],
    library_ids: &[u32],
    library_dependencies: &[SourcePackLibraryDependency],
    tables: Option<&PrecomputedParseTables>,
) {
    let source_bytes = src.len();
    let source_file_capacity = sources.len().max(1);
    let token_capacity = token_capacity_estimate_for_source(src);
    let parse_capacity =
        parser_capacity_estimate_for_token_capacity(token_capacity.parser_token_capacity, tables);
    println!(
        "estimate lines={source_lines} source_bytes={source_bytes} source_file_capacity={} lexer_byte_capacity={} lexer_token_capacity={} parser_token_capacity={} token_capacity_basis={}",
        source_file_capacity.max(1),
        token_capacity.lexer_byte_capacity,
        token_capacity.lexer_token_capacity,
        token_capacity.parser_token_capacity,
        token_capacity.basis,
    );
    print_capacity_floors(
        token_capacity.lexer_token_capacity,
        &parse_capacity,
        None,
        source_file_capacity,
    );
    print_codegen_unit_estimate(sources, library_ids, library_dependencies);
    print_parallel_pass_contract_estimate();
    println!("estimate ll1_seed_path=inactive note=capacity-derived; no GPU work was submitted");
}

pub(super) fn print_codegen_unit_estimate(
    sources: &[String],
    library_ids: &[u32],
    library_dependencies: &[SourcePackLibraryDependency],
) {
    let limits = CodegenUnitLimits::default();
    let plan = SourcePackJobPlan::from_source_pack_with_libraries_and_dependencies(
        sources,
        library_ids,
        library_dependencies,
        limits,
    );
    let codegen_units = &plan.codegen_units;
    println!(
        "estimate codegen_units unit_count={} max_unit_source_bytes={} max_unit_source_files={} oversized_units={} unit_max_source_bytes_limit={} unit_max_source_files_limit={} split_policy=file-and-library-boundaries",
        codegen_units.unit_count(),
        codegen_units.max_unit_source_bytes(),
        codegen_units.max_unit_source_files(),
        codegen_units.oversized_unit_count(),
        limits.max_source_bytes,
        limits.max_source_files,
    );
    println!(
        "estimate library_units unit_count={} max_library_source_bytes={} max_library_source_files={} split_policy=contiguous-library-boundaries",
        plan.libraries.library_count(),
        plan.libraries.max_library_source_bytes(),
        plan.libraries.max_library_source_files(),
    );
    let schedule = plan.bounded_frontend_job_schedule();
    println!(
        "estimate scheduled_jobs total={} frontend_jobs={} codegen_jobs={} link_jobs={} max_job_source_bytes={} max_job_source_files={} order=dependency-topological-jobs",
        schedule.jobs.len(),
        schedule.frontend_job_count(),
        schedule.codegen_job_count(),
        schedule.link_job_count(),
        schedule.max_job_source_bytes(),
        schedule.max_job_source_files(),
    );
    let waves = schedule
        .try_execution_wave_summary()
        .expect("generated source-pack schedule should be acyclic");
    println!(
        "estimate schedule_waves wave_count={} max_ready_jobs={} max_wave_source_bytes={} max_wave_source_files={} policy=dependency-ready-waves",
        waves.wave_count(),
        waves.max_wave_job_count(),
        waves.max_wave_source_bytes(),
        waves.max_wave_source_files(),
    );
    let batch_limits = SourcePackJobBatchLimits::from_codegen_unit_limits(limits);
    let batches = schedule
        .try_execution_batch_summary(batch_limits)
        .expect("generated source-pack schedule should produce bounded batches");
    println!(
        "estimate schedule_batches batch_count={} max_batch_jobs={} max_batch_source_bytes={} max_batch_source_files={} batch_max_source_bytes_limit={} batch_max_source_files_limit={} policy=bounded-ready-wave-batches",
        batches.batch_count(),
        batches.max_batch_job_count(),
        batches.max_batch_source_bytes(),
        batches.max_batch_source_files(),
        batch_limits.max_source_bytes_per_batch,
        batch_limits.max_source_files_per_batch,
    );
    let batch_dependencies = schedule
        .try_execution_batch_dependency_summary(batch_limits)
        .expect("generated source-pack batches should have dependency records");
    println!(
        "estimate batch_dependencies batch_count={} dependency_edges={} max_dependencies={} initial_ready_batches={} policy=persisted-batch-dag",
        batch_dependencies.batch_count(),
        batch_dependencies.dependency_edge_count(),
        batch_dependencies.max_dependency_count(),
        batch_dependencies.initial_ready_batch_count(),
    );
    let artifact_estimate = plan.build_artifact_estimate_summary_for_schedule(
        &schedule,
        batch_limits,
        SourcePackArtifactTarget::Generic,
    );
    let artifact_manifest = artifact_estimate.artifact_manifest;
    let artifact_lifetimes = artifact_estimate.artifact_lifetimes;
    let job_artifacts = artifact_estimate.job_artifacts;
    let job_artifact_manifest = artifact_estimate.job_artifact_manifest;
    let link_interface_batches = artifact_estimate.link_interface_batches;
    let link_object_batches = artifact_estimate.link_object_batches;
    println!(
        "estimate job_dependencies library_edges={} scheduled_edges={} max_job_dependencies={}",
        library_dependencies.len(),
        schedule.dependency_edge_count(),
        schedule.max_job_dependency_count(),
    );
    println!(
        "estimate job_artifact_io max_input_interfaces={} max_input_objects={} max_input_artifacts={} max_output_artifacts={} policy=explicit-artifact-graph",
        job_artifacts.max_input_interface_count(),
        job_artifacts.max_input_object_count(),
        job_artifacts.max_input_artifact_count(),
        job_artifacts.max_output_artifact_count(),
    );
    println!(
        "estimate artifact_manifest artifacts={} max_key_len={} max_manifest_job_inputs={} key_policy=stable-kind-library-job-source-range",
        artifact_manifest.artifact_count(),
        artifact_manifest.max_key_len(),
        job_artifact_manifest.max_input_artifact_count(),
    );
    println!(
        "estimate artifact_lifetimes artifacts={} artifacts_without_consumers={} release_policy=dense-last-consumer-index",
        artifact_estimate.artifact_use_count,
        artifact_lifetimes.artifacts_without_consumers(),
    );
    println!(
        "estimate link_interface_batches batch_count={} max_batch_interfaces={} max_batch_source_bytes={} max_batch_source_files={} policy=bounded-interface-inputs",
        link_interface_batches.batch_count(),
        link_interface_batches.max_batch_interface_count(),
        link_interface_batches.max_batch_source_bytes(),
        link_interface_batches.max_batch_source_files(),
    );
    println!(
        "estimate link_object_batches batch_count={} max_batch_objects={} max_batch_source_bytes={} max_batch_source_files={} policy=bounded-object-inputs",
        link_object_batches.batch_count(),
        link_object_batches.max_batch_object_count(),
        link_object_batches.max_batch_source_bytes(),
        link_object_batches.max_batch_source_files(),
    );
    println!(
        "estimate planned_artifacts total={} library_interfaces={} codegen_objects={} linked_outputs={} link_object_inputs={} link_interface_inputs={}",
        artifact_estimate.total_artifacts,
        artifact_estimate.interface_artifacts,
        artifact_estimate.object_artifacts,
        artifact_estimate.linked_output_artifacts,
        artifact_estimate.link_object_inputs,
        artifact_estimate.link_interface_inputs,
    );
}

#[cfg(test)]
#[derive(Clone, Copy, Debug)]
pub(super) struct CompileCapacitySnapshot {
    pub(super) source_bytes: usize,
    pub(super) lexer_token_capacity: usize,
    pub(super) parser_token_capacity: usize,
    pub(super) parser_tree_capacity: usize,
    pub(super) parser_floor_bytes: usize,
    pub(super) frontend_floor_bytes: usize,
    pub(super) x86_inst_capacity: usize,
    pub(super) x86_floor_bytes: usize,
    pub(super) compile_floor_bytes: usize,
}

#[cfg(test)]
pub(super) fn compile_capacity_snapshot_for_source(
    src: &str,
    source_file_capacity: usize,
    tables: Option<&PrecomputedParseTables>,
) -> CompileCapacitySnapshot {
    let token_capacity = token_capacity_estimate_for_source(src);
    let parse_capacity =
        parser_capacity_estimate_for_token_capacity(token_capacity.parser_token_capacity, tables);
    let parser_floor = parser_allocation_floor_bytes(&parse_capacity);
    let typecheck_floor = typecheck_allocation_floor_bytes(
        token_capacity.lexer_token_capacity,
        parse_capacity.tree_capacity,
        true,
        source_file_capacity,
    );
    let x86_capacity = x86_capacity_estimate_for_hir_and_tokens(
        parse_capacity.tree_capacity,
        token_capacity.lexer_token_capacity,
    );
    let x86_floor = x86_allocation_floor_bytes(token_capacity.lexer_token_capacity, &x86_capacity);
    let frontend_floor_bytes = parser_floor.total.saturating_add(typecheck_floor.total);
    let compile_floor_bytes = frontend_floor_bytes.saturating_add(x86_floor.total);

    CompileCapacitySnapshot {
        source_bytes: src.len(),
        lexer_token_capacity: token_capacity.lexer_token_capacity,
        parser_token_capacity: token_capacity.parser_token_capacity,
        parser_tree_capacity: parse_capacity.tree_capacity,
        parser_floor_bytes: parser_floor.total,
        frontend_floor_bytes,
        x86_inst_capacity: x86_capacity.inst_capacity,
        x86_floor_bytes: x86_floor.total,
        compile_floor_bytes,
    }
}

pub(super) fn print_live_capacity_estimate(
    source_lines: usize,
    source_bytes: usize,
    live: GpuLiveCapacityEstimateResult,
    tables: Option<&PrecomputedParseTables>,
) {
    let token_capacity = (live.token_count as usize).max(1);
    let parse_capacity = parser_capacity_estimate_for_live_token_count(
        token_capacity,
        live.parser_tree_capacity as usize,
        tables,
    );
    println!(
        "estimate_live lines={source_lines} source_bytes={source_bytes} gpu_token_count={} token_capacity={token_capacity} parser_emit_len={} semantic_hir_count={}",
        live.token_count, live.parser_emit_len, live.semantic_hir_count
    );
    let x86_hir_words = (live.parser_emit_len as usize).max(1);
    let semantic_hir_words = (live.semantic_hir_count as usize).max(1);
    print_capacity_floors(
        token_capacity,
        &parse_capacity,
        Some((x86_hir_words, semantic_hir_words)),
        1,
    );
    print_parallel_pass_contract_estimate();
    if x86_hir_words < parse_capacity.tree_capacity {
        let projected_x86_capacity = x86_capacity_estimate_for_hir_tokens_and_inst_basis(
            parse_capacity.tree_capacity,
            token_capacity,
            semantic_hir_words,
        );
        let current_x86_capacity = x86_capacity_estimate_for_hir_tokens_and_inst_basis(
            x86_hir_words,
            token_capacity,
            semantic_hir_words,
        );
        let projected_x86_floor =
            x86_allocation_floor_bytes(token_capacity, &projected_x86_capacity);
        let current_x86_floor = x86_allocation_floor_bytes(token_capacity, &current_x86_capacity);
        let saved = projected_x86_floor
            .hir_scaled
            .saturating_sub(current_x86_floor.hir_scaled);
        println!(
            "estimate_live x86_parser_emit_capacity current_hir_words={x86_hir_words} projected_tree_hir_words={} projected_x86_hir_scaled={} current_x86_hir_scaled={} hir_scaled_savings={}",
            projected_x86_capacity.hir_words,
            human_bytes(projected_x86_floor.hir_scaled),
            human_bytes(current_x86_floor.hir_scaled),
            human_bytes(saved)
        );
    }
    if semantic_hir_words < x86_hir_words {
        let current_x86_capacity = x86_capacity_estimate_for_hir_tokens_and_inst_basis(
            x86_hir_words,
            token_capacity,
            semantic_hir_words,
        );
        let dense_x86_capacity = x86_capacity_estimate_for_hir_tokens_and_inst_basis(
            semantic_hir_words,
            token_capacity,
            semantic_hir_words,
        );
        let current_x86_floor = x86_allocation_floor_bytes(token_capacity, &current_x86_capacity);
        let dense_x86_floor = x86_allocation_floor_bytes(token_capacity, &dense_x86_capacity);
        let saved = current_x86_floor
            .hir_scaled
            .saturating_sub(dense_x86_floor.hir_scaled);
        println!(
            "estimate_live x86_semantic_dense_hypothesis semantic_hir_words={semantic_hir_words} current_hir_words={x86_hir_words} current_x86_hir_scaled={} dense_x86_hir_scaled={} possible_hir_scaled_savings={} note=diagnostic-only-HIR-records-are-still-original-node-keyed",
            human_bytes(current_x86_floor.hir_scaled),
            human_bytes(dense_x86_floor.hir_scaled),
            human_bytes(saved)
        );
    }
    println!(
        "estimate_live ll1_seed_path=inactive note=live GPU lex, parser, and semantic-HIR count"
    );
}

pub(super) fn print_capacity_floors(
    token_capacity: usize,
    parse_capacity: &ParserCapacityEstimate,
    x86_words_override: Option<(usize, usize)>,
    source_file_capacity: usize,
) {
    let allocation_floor = parser_allocation_floor_bytes(parse_capacity);
    let typecheck_floor = typecheck_allocation_floor_bytes(
        token_capacity,
        parse_capacity.tree_capacity,
        true,
        source_file_capacity,
    );

    println!(
        "estimate parser_path={} parser_tree_capacity={} one_tree_u32_buffer={} parser_tree_buffer_floor={}",
        parse_capacity.path,
        parse_capacity.tree_capacity,
        human_bytes(parse_capacity.tree_capacity.saturating_mul(4)),
        human_bytes(allocation_floor.tree_hir)
    );
    println!(
        "estimate parser_allocation_floor total={} tree_hir={} brackets={} pack_streams={}",
        human_bytes(allocation_floor.total),
        human_bytes(allocation_floor.tree_hir),
        human_bytes(allocation_floor.brackets),
        human_bytes(allocation_floor.pack_streams)
    );
    println!(
        "estimate typecheck_u32_buffer_floor total={} names_radix={} module_paths={} visible_hir_decls={} calls={} type_metadata={} methods={} control={} core={} empty_hir={}",
        human_bytes(typecheck_floor.total),
        human_bytes(typecheck_floor.names_radix),
        human_bytes(typecheck_floor.module_paths),
        human_bytes(typecheck_floor.visible_hir_decls),
        human_bytes(typecheck_floor.calls),
        human_bytes(typecheck_floor.type_metadata),
        human_bytes(typecheck_floor.methods),
        human_bytes(typecheck_floor.control),
        human_bytes(typecheck_floor.core),
        human_bytes(typecheck_floor.empty_hir),
    );
    println!(
        "estimate frontend_allocation_floor parser_plus_typecheck={}",
        human_bytes(allocation_floor.total.saturating_add(typecheck_floor.total))
    );
    let (x86_hir_words, x86_inst_basis_words) =
        x86_words_override.unwrap_or((parse_capacity.tree_capacity, parse_capacity.tree_capacity));
    let x86_hir_words = x86_hir_words.max(1);
    let x86_inst_basis_words = x86_inst_basis_words.max(1);
    let x86_hir_basis = match x86_words_override {
        Some(_) if x86_inst_basis_words < x86_hir_words => "parser_emit_len+semantic_hir_count",
        Some(_) => "parser_emit_len",
        None => "parser_tree_capacity",
    };
    let x86_capacity = x86_capacity_estimate_for_hir_tokens_and_inst_basis(
        x86_hir_words,
        token_capacity,
        x86_inst_basis_words,
    );
    let x86_dynamic = x86_dynamic_buffer_estimate_bytes(&x86_capacity);
    let x86_floor = x86_allocation_floor_bytes(token_capacity, &x86_capacity);
    println!(
        "estimate x86_dynamic_caps hir_basis={x86_hir_basis} hir_words={} inst_basis_words={} requested_inst_capacity={} inst_capacity={} inst_capacity_capped={} output_capacity={}",
        x86_capacity.hir_words,
        x86_capacity.inst_basis_words,
        x86_capacity.requested_inst_capacity,
        x86_capacity.inst_capacity,
        x86_capacity.inst_capacity_capped,
        human_bytes(x86_capacity.output_capacity)
    );
    println!(
        "estimate x86_dynamic_buffer_estimate total={} virtual_inst_records={} live_ranges={} selected_text={}",
        human_bytes(x86_dynamic.total),
        human_bytes(x86_dynamic.virtual_inst_records),
        human_bytes(x86_dynamic.live_ranges),
        human_bytes(x86_dynamic.selected_text)
    );
    println!(
        "estimate x86_allocation_floor total={} hir_scaled={} token_scaled={} inst_scaled={} scans={} output_and_readback={} small={}",
        human_bytes(x86_floor.total),
        human_bytes(x86_floor.hir_scaled),
        human_bytes(x86_floor.token_scaled),
        human_bytes(x86_floor.inst_scaled),
        human_bytes(x86_floor.scans),
        human_bytes(x86_floor.output_and_readback),
        human_bytes(x86_floor.small),
    );
    let compile_floor_bytes = allocation_floor
        .total
        .saturating_add(typecheck_floor.total)
        .saturating_add(x86_floor.total);
    println!(
        "estimate compile_allocation_floor parser_plus_typecheck_plus_x86={} compile_floor_bytes={compile_floor_bytes}",
        human_bytes(compile_floor_bytes)
    );
    if parse_capacity.path.starts_with("llp-") {
        println!(
            "estimate llp_pair_projection max_sc_len={} max_emit_len={} total_sc={} total_emit={}",
            parse_capacity.max_sc_len,
            parse_capacity.max_emit_len,
            parse_capacity.total_sc,
            parse_capacity.total_emit
        );
    }
}

pub(super) struct X86DynamicBufferEstimate {
    total: usize,
    virtual_inst_records: usize,
    live_ranges: usize,
    selected_text: usize,
}

pub(super) struct X86AllocationFloor {
    total: usize,
    hir_scaled: usize,
    token_scaled: usize,
    inst_scaled: usize,
    scans: usize,
    output_and_readback: usize,
    small: usize,
}

pub(super) fn x86_dynamic_buffer_estimate_bytes(
    capacity: &X86CapacityEstimate,
) -> X86DynamicBufferEstimate {
    let inst = capacity.inst_capacity;
    let virtual_inst_records = inst
        .saturating_mul(16)
        .saturating_add(inst.saturating_mul(16))
        .saturating_add(inst.saturating_mul(4));
    let live_ranges = inst.saturating_mul(4).saturating_mul(4);
    let selected_text = inst.saturating_mul(4).saturating_mul(3);
    X86DynamicBufferEstimate {
        total: virtual_inst_records
            .saturating_add(live_ranges)
            .saturating_add(selected_text),
        virtual_inst_records,
        live_ranges,
        selected_text,
    }
}

pub(super) fn x86_allocation_floor_bytes(
    token_capacity: usize,
    capacity: &X86CapacityEstimate,
) -> X86AllocationFloor {
    const X86_NODE_LOCAL_INSTS: usize = 4;
    const STATUS_WORDS: usize = 4;
    const FUNC_META_WORDS: usize = 8;
    const ELF_LAYOUT_WORDS: usize = 8;
    const TRACE_STATUS_WORDS: usize = 110;

    let token_words = token_capacity.max(1);
    let hir_words = capacity.hir_words.max(1);
    let inst = capacity.inst_capacity.max(1);
    let output_words = capacity.output_capacity.div_ceil(4).max(1);
    let func_owner_scan_blocks = hir_words.div_ceil(256).max(1);
    let node_inst_scan_words = hir_words.saturating_add(1);
    let text_scan_blocks = inst.div_ceil(256).max(1);

    let hir_scaled_words_per_node = (
        // Keep this in sync with `record_elf_from_hir` HIR-sized buffers.
        4 + 1
            + 1
            + 1
            + 1
            + 4
            + 4
            + 1
            + 1
            + 1
            + 1
            + 1
            + 1
            + 1
            + 1
            + 4
            + 4
            + 4
            + 4
            + 4
            + 4
            + 1
            + 4
            + 1
            + 4
            + 1
            + 4
            + 1
            + 4
            + 1
            + 4
            + 4
            + 4
            + 4
            + 4
            + 4
            + 4
            + 1
            + 1
            + 4
            + 4
            + X86_NODE_LOCAL_INSTS
            + 4
            + 1
            + 1
            + 1
        // Write-only call-argument eval, call-argument ABI, node-value,
        // terminal-if projection, dead return-projection records, and the
        // dead function-discovery record were removed from the retained x86
        // backend surface. The call-argument lookup record is packed to one
        // word per call/ordinal slot, and the call ABI record stores only the
        // target plus packed argument count/return width. One resolved-expression
        // table was added so backend shaders do not each walk HIR_EXPR_FORWARD
        // chains locally. Node instruction ranges reuse dead parser HIR
        // workspaces as separate start/info words. Enum value records retain only packed
        // kind/payload-count data plus ordinal. Struct/array access rows and
        // declaration layout rows pack their small kind fields into three-word
        // flat records. Node instruction order rows use a compact three-word
        // phase-reused buffer.
        // Enclosing loop owners, virtual parameter masks, node instruction
        // counts, instruction-order rows, subtree slot bounds, node
        // instruction locations, and virtual row bounds reuse existing backend
        // scratch instead of adding HIR-sized buffers. Call type and node
        // instruction count records share one compact row table sized to also
        // carry the later subtree-bounds worklist tail.
        // Match-result owner pointer-jump rows reuse the later match-pattern
        // owner scratch and same-end link scratch.
        // Function-owner pointer-jump output reuses match-pattern first-use
        // scratch, copying odd-step results back to the stable owner table.
        // Enclosing-let pointer-jump output reuses the later call-callee-root
        // marker table after copyback to the stable owner table.
        // Intrinsic call projection reuses the dead match-pattern owner table.
        // Intrinsic call projection packs the call lookup base and small
        // intrinsic tag into one HIR-keyed word. Call ABI and declaration
        // layouts are token/declaration-token indexed instead of retaining
        // HIR-sized side tables.
        // x86 calls resolve function targets through the token-indexed
        // declaration table rather than a second open-address function table,
        // and const values are token-row sized.
        // Register allocation keeps active-end register state in compact
        // function slots and uses a compact function-slot list for active
        // dispatch.
        // Backend tree projection keeps parent/subtree_end only; first-child
        // and next-sibling links are derived from preorder spans in x86
        // shaders. Expression semantic compare type and links are packed into the
        // existing same-end link scratch instead of retaining two HIR-sized
        // type ping-pong buffers.
        // Parameter-node decl lookup is carried in existing HIR metadata and
        // per-node location metadata instead of a HIR-sized param-reg tail.
    )
    .saturating_sub(96usize);
    let hir_scaled_words = hir_words.saturating_mul(hir_scaled_words_per_node);
    let token_scaled_words_per_token = {
        // Token-sized metadata and the token half of compact backend lookup
        // buffers. Virtual function last-row bounds reuse dead call ABI
        // storage, and register-allocation active ends reuse dead node-order
        // scratch when that scratch is large enough.
        let enum_type_record = 1usize;
        let struct_type_record = 1usize;
        let decl_layout_record = 4usize;
        let decl_node_by_token = 1usize;
        let const_value_record = 2usize;
        let param_reg_record = 6usize;
        let local_literal_record = 3usize;
        let call_abi_record = 2usize;
        enum_type_record
            + struct_type_record
            + decl_layout_record
            + decl_node_by_token
            + const_value_record
            + param_reg_record
            + local_literal_record
            + call_abi_record
    };
    let function_slot_words =
        x86_function_slot_capacity(capacity.inst_basis_words, hir_words, token_words);
    let virtual_func_first_row_words = function_slot_words;
    let virtual_regalloc_active_end_words = function_slot_words.saturating_mul(14);
    let prior_node_inst_order_reuse_words = node_inst_scan_words.saturating_mul(3);
    let node_inst_order_reuse_words =
        x86_node_inst_order_record_words(hir_words, inst, function_slot_words);
    let prior_node_inst_subtree_bounds_words = hir_words.saturating_add(1).saturating_mul(4);
    let call_type_record_words = x86_call_type_record_words(hir_words, true);
    let node_inst_count_words = x86_node_inst_count_record_words(hir_words);
    let node_inst_subtree_bounds_words = hir_words.saturating_mul(2);
    let node_inst_gen_node_record_words = x86_node_inst_gen_node_record_words(hir_words, inst);
    let split_node_inst_planning_words = call_type_record_words
        .saturating_add(node_inst_count_words)
        .saturating_add(node_inst_subtree_bounds_words)
        .saturating_add(node_inst_gen_node_record_words);
    let hir_scaled_words = hir_scaled_words
        .saturating_sub(
            prior_node_inst_order_reuse_words.saturating_sub(node_inst_order_reuse_words),
        )
        .saturating_sub(prior_node_inst_subtree_bounds_words)
        .saturating_add(split_node_inst_planning_words)
        .saturating_add(virtual_func_first_row_words)
        .saturating_add(function_slot_words);
    let active_end_extra_words =
        virtual_regalloc_active_end_words.saturating_sub(node_inst_order_reuse_words);
    let token_scaled_words = token_words
        .saturating_mul(token_scaled_words_per_token)
        .saturating_add(active_end_extra_words);
    let inst_scaled_words = inst.saturating_mul(
        // Virtual instruction records plus the inst-sized scratch that remains
        // live after lifetime reuse. Fixed-barrier spans reuse the future
        // call-live-mask table before register allocation writes the final
        // masks. Selected instruction fields and instruction sizes reuse dead
        // backend scratch records; byte offsets and text-scan local prefixes
        // are retained as compact inst-sized rows after virtual use-edge
        // materialization was removed.
        4 + 4 + 1 + 1 + 1 + 1 + 1 + 1 + 1,
    );
    let scan_words = func_owner_scan_blocks
        .saturating_mul(3)
        .saturating_add(node_inst_scan_words.saturating_mul(5))
        .saturating_add(text_scan_blocks.saturating_mul(3));
    let output_words_total = output_words.saturating_mul(2).saturating_add(4);
    let small_words = FUNC_META_WORDS
        .saturating_mul(2)
        .saturating_add(ELF_LAYOUT_WORDS)
        .saturating_add(STATUS_WORDS.saturating_mul(37))
        .saturating_add(TRACE_STATUS_WORDS);

    X86AllocationFloor {
        hir_scaled: u32_words_to_bytes(hir_scaled_words),
        token_scaled: u32_words_to_bytes(token_scaled_words),
        inst_scaled: u32_words_to_bytes(inst_scaled_words),
        scans: u32_words_to_bytes(scan_words),
        output_and_readback: u32_words_to_bytes(output_words_total),
        small: u32_words_to_bytes(small_words),
        total: u32_words_to_bytes(
            hir_scaled_words
                .saturating_add(token_scaled_words)
                .saturating_add(inst_scaled_words)
                .saturating_add(scan_words)
                .saturating_add(output_words_total)
                .saturating_add(small_words),
        ),
    }
}

pub(super) struct TypecheckAllocationFloor {
    total: usize,
    names_radix: usize,
    module_paths: usize,
    visible_hir_decls: usize,
    calls: usize,
    type_metadata: usize,
    methods: usize,
    control: usize,
    core: usize,
    empty_hir: usize,
}

pub(super) fn typecheck_allocation_floor_bytes(
    token_capacity: usize,
    hir_node_capacity: usize,
    uses_hir_items: bool,
    source_file_capacity: usize,
) -> TypecheckAllocationFloor {
    let token_capacity = token_capacity.max(1);
    let hir_node_capacity = hir_node_capacity.max(1);
    let token_blocks = token_capacity.div_ceil(256).max(1);
    let name_capacity = token_capacity
        .saturating_add(TYPECHECK_LANGUAGE_SYMBOL_COUNT)
        .max(1);
    let name_blocks = name_capacity.div_ceil(256).max(1);
    let name_radix_histogram_len = name_blocks.saturating_mul(TYPECHECK_NAME_RADIX_BUCKETS);
    let hir_blocks = hir_node_capacity.div_ceil(256).max(1);
    let record_radix_histogram_len = token_blocks.saturating_mul(TYPECHECK_NAME_RADIX_BUCKETS);
    let source_file_capacity = source_file_capacity.max(1);
    let module_capacity = source_file_capacity;
    let import_visible_capacity = if source_file_capacity <= 1 {
        1
    } else {
        token_capacity
    };
    let import_record_capacity =
        typecheck_import_record_capacity(token_capacity, source_file_capacity);
    let module_blocks = module_capacity.div_ceil(256).max(1);
    let import_visible_blocks = import_visible_capacity.div_ceil(256).max(1);
    let module_radix_histogram_len = module_blocks.saturating_mul(TYPECHECK_NAME_RADIX_BUCKETS);
    let import_visible_radix_histogram_len =
        import_visible_blocks.saturating_mul(TYPECHECK_NAME_RADIX_BUCKETS);
    let module_path_key_radix_histogram_len = record_radix_histogram_len
        .max(module_radix_histogram_len)
        .max(import_visible_radix_histogram_len);
    let hir_visible_decl_tree_leaf_count = token_capacity
        .div_ceil(TYPECHECK_HIR_VISIBLE_DECL_ROW_BLOCK_SIZE)
        .max(1);
    let hir_visible_decl_tree_leaf_base = hir_visible_decl_tree_leaf_count.next_power_of_two();
    let hir_visible_decl_radix_histogram_len =
        token_blocks.saturating_mul(TYPECHECK_NAME_RADIX_BUCKETS);

    let core_u32 = 12usize
        .saturating_mul(token_capacity)
        .saturating_add(TYPECHECK_LANGUAGE_SYMBOL_COUNT);
    let names_radix_u32 = 4usize
        .saturating_mul(token_capacity)
        .saturating_add(3usize.saturating_mul(token_blocks))
        .saturating_add(2)
        .saturating_add(11usize.saturating_mul(name_capacity))
        .saturating_add(token_capacity)
        .saturating_add(2usize.saturating_mul(name_radix_histogram_len))
        .saturating_add(2usize.saturating_mul(TYPECHECK_NAME_RADIX_BUCKETS))
        .saturating_add(3)
        .saturating_add(1);
    let control_u32 = 9usize
        .saturating_mul(token_capacity)
        .saturating_add(8usize.saturating_mul(token_blocks))
        .saturating_add(4);
    let call_param_cache_u32 = 0usize;
    let call_param_count_u32 = if hir_node_capacity >= token_capacity {
        0
    } else {
        token_capacity
    };
    let function_lookup_u32 = if hir_node_capacity >= 2usize.saturating_mul(token_capacity) {
        0
    } else {
        4usize.saturating_mul(token_capacity)
    };
    let call_arg_record_u32 = if hir_node_capacity >= 4usize.saturating_mul(token_capacity) {
        0
    } else {
        4usize.saturating_mul(token_capacity)
    };
    let call_arg_node_u32 = typecheck_call_arg_node_words(hir_node_capacity);
    let compact_call_arg_row_u32 = typecheck_compact_call_arg_row_words(hir_node_capacity);
    let calls_u32 = 4usize
        .saturating_mul(token_capacity)
        .saturating_add(call_param_count_u32)
        .saturating_add(function_lookup_u32)
        .saturating_add(call_param_cache_u32)
        .saturating_add(call_arg_record_u32)
        .saturating_add(call_arg_node_u32)
        .saturating_add(compact_call_arg_row_u32);
    let method_key_radix_scratch_u32 = if hir_node_capacity >= name_radix_histogram_len {
        0
    } else {
        2usize.saturating_mul(name_radix_histogram_len)
    };
    let methods_u32 = 2usize
        .saturating_mul(token_capacity)
        .saturating_add(source_file_capacity)
        .saturating_add(method_key_radix_scratch_u32)
        .saturating_add(2usize.saturating_mul(TYPECHECK_NAME_RADIX_BUCKETS))
        .saturating_add(1);
    let type_metadata_u32 = 2usize
        .saturating_mul(TYPECHECK_TYPE_INSTANCE_ARG_REF_STRIDE)
        .saturating_mul(token_capacity);
    let empty_hir_u32 = if uses_hir_items {
        4
    } else {
        4usize.saturating_mul(hir_node_capacity)
    };
    let module_path_radix_scratch_u32 = if hir_node_capacity >= module_path_key_radix_histogram_len
    {
        0
    } else {
        2usize.saturating_mul(module_path_key_radix_histogram_len)
    };
    let module_path_decl_tree_scratch_u32 = if hir_node_capacity >= token_capacity {
        0
    } else {
        2usize.saturating_mul(token_capacity)
    };
    let module_paths_u32 = 48usize
        .saturating_mul(token_capacity)
        .saturating_add(7usize.saturating_mul(import_record_capacity))
        .saturating_add(source_file_capacity)
        .saturating_add(16usize.saturating_mul(module_capacity))
        .saturating_add(20usize.saturating_mul(import_visible_capacity))
        .saturating_add(2usize.saturating_mul(token_capacity))
        // HIR-indexed module/path scratch: shared record prefix/local scan and
        // owner map. Family bits/flags reuse later typecheck/codegen records;
        // path prefixes reuse the shared prefix and are retained through
        // path_id_by_owner_hir. Module-key radix scratch and ten declaration
        // record tables borrow dead parser workspaces when those workspaces
        // are large enough. The five x86-retained declaration metadata tables
        // borrow typecheck name-radix scratch after the name pipeline records.
        .saturating_add(3usize.saturating_mul(hir_node_capacity))
        .saturating_add(3usize.saturating_mul(hir_blocks))
        .saturating_add(module_path_radix_scratch_u32)
        .saturating_add(module_path_decl_tree_scratch_u32)
        .saturating_add(2usize.saturating_mul(TYPECHECK_NAME_RADIX_BUCKETS))
        .saturating_add(33);
    let visible_hir_decl_scan_scratch_u32 = if uses_hir_items {
        0
    } else {
        3usize
            .saturating_mul(hir_node_capacity)
            .saturating_add(3usize.saturating_mul(hir_blocks))
    };
    let visible_hir_decls_u32 = visible_hir_decl_scan_scratch_u32
        .saturating_add(1)
        .saturating_add(3)
        .saturating_add(6usize.saturating_mul(token_capacity))
        .saturating_add(2usize.saturating_mul(hir_visible_decl_radix_histogram_len))
        .saturating_add(2usize.saturating_mul(TYPECHECK_NAME_RADIX_BUCKETS))
        .saturating_add(hir_visible_decl_tree_leaf_base.saturating_mul(2));

    TypecheckAllocationFloor {
        total: u32_words_to_bytes(
            core_u32
                .saturating_add(names_radix_u32)
                .saturating_add(module_paths_u32)
                .saturating_add(visible_hir_decls_u32)
                .saturating_add(calls_u32)
                .saturating_add(type_metadata_u32)
                .saturating_add(methods_u32)
                .saturating_add(control_u32)
                .saturating_add(empty_hir_u32),
        ),
        names_radix: u32_words_to_bytes(names_radix_u32),
        module_paths: u32_words_to_bytes(module_paths_u32),
        visible_hir_decls: u32_words_to_bytes(visible_hir_decls_u32),
        calls: u32_words_to_bytes(calls_u32),
        type_metadata: u32_words_to_bytes(type_metadata_u32),
        methods: u32_words_to_bytes(methods_u32),
        control: u32_words_to_bytes(control_u32),
        core: u32_words_to_bytes(core_u32),
        empty_hir: u32_words_to_bytes(empty_hir_u32),
    }
}

pub(super) fn typecheck_call_arg_node_words(hir_node_capacity: usize) -> usize {
    hir_node_capacity
        .max(1)
        .saturating_mul(TYPECHECK_CALL_ARG_SLOT_STRIDE)
}

pub(super) fn typecheck_compact_call_arg_row_words(hir_node_capacity: usize) -> usize {
    let row_capacity = hir_node_capacity.max(1);
    let scan_blocks = row_capacity.div_ceil(256).max(1);
    1usize
        .saturating_add(8usize.saturating_mul(row_capacity))
        .saturating_add(3usize.saturating_mul(scan_blocks))
}

pub(super) fn typecheck_import_record_capacity(
    token_capacity: usize,
    source_file_capacity: usize,
) -> usize {
    if source_file_capacity <= 1 {
        1
    } else {
        token_capacity.max(1)
    }
}

pub(super) fn u32_words_to_bytes(words: usize) -> usize {
    words.saturating_mul(4)
}

pub(super) struct ParserAllocationFloor {
    total: usize,
    tree_hir: usize,
    brackets: usize,
    pack_streams: usize,
}

pub(super) fn parser_allocation_floor_bytes(
    estimate: &ParserCapacityEstimate,
) -> ParserAllocationFloor {
    let tree_hir = parser_tree_floor_bytes(estimate.tree_capacity);
    let brackets = parser_bracket_floor_bytes(estimate.total_sc);
    let pack_streams = parser_pack_stream_floor_bytes(estimate);
    ParserAllocationFloor {
        total: tree_hir
            .saturating_add(brackets)
            .saturating_add(pack_streams),
        tree_hir,
        brackets,
        pack_streams,
    }
}

pub(super) fn parser_tree_floor_bytes(tree_capacity: usize) -> usize {
    // Resident parser/HIR tree-capacity allocations after shared pointer-jump
    // list scratch. This counts actual allocations, not alias views.
    const PARSER_TREE_SCALAR_U32_BUFFERS: usize = 78;
    const PARSER_TREE_U32X4_RECORD_BUFFERS: usize = 3;
    let parser_tree_scalar_floor_bytes = PARSER_TREE_SCALAR_U32_BUFFERS
        .saturating_mul(tree_capacity)
        .saturating_mul(4);
    let parser_tree_wide_floor_bytes = PARSER_TREE_U32X4_RECORD_BUFFERS
        .saturating_mul(tree_capacity)
        .saturating_mul(16);
    parser_tree_scalar_floor_bytes.saturating_add(parser_tree_wide_floor_bytes)
}

pub(super) fn parser_bracket_floor_bytes(total_sc: usize) -> usize {
    const U32_SIZE: usize = 4;
    let _ = total_sc;
    // `gpu_compile_bench` uses the resident LLP path, so the bracket scratch
    // estimate only reserves the fixed placeholder buffers still allocated there.
    const RESIDENT_BRACKET_PLACEHOLDER_U32S: usize = 7 + 7 + 6 + 3;
    RESIDENT_BRACKET_PLACEHOLDER_U32S.saturating_mul(U32_SIZE)
}

pub(super) fn parser_pack_stream_floor_bytes(estimate: &ParserCapacityEstimate) -> usize {
    const U32_SIZE: usize = 4;
    // Resident parsing consumes the production stream for tree/HIR recovery.
    1usize
        .saturating_add(estimate.tree_capacity.saturating_mul(2))
        .saturating_mul(U32_SIZE)
}

pub(super) struct TokenCapacityEstimate {
    lexer_byte_capacity: usize,
    lexer_token_capacity: usize,
    parser_token_capacity: usize,
    basis: &'static str,
}

pub(super) fn token_capacity_estimate_for_source(src: &str) -> TokenCapacityEstimate {
    let lexer_byte_capacity = src.len().div_ceil(4).saturating_mul(4).max(1);
    let (lexer_token_capacity, basis) = match lex_on_test_cpu(src) {
        Ok(tokens) => (tokens.len().max(1), "test_cpu_token_count"),
        Err(_) => (lexer_byte_capacity, "source_byte_capacity_fallback"),
    };
    TokenCapacityEstimate {
        lexer_byte_capacity,
        lexer_token_capacity,
        parser_token_capacity: lexer_token_capacity.saturating_add(2),
        basis,
    }
}

pub(super) fn parser_capacity_estimate_for_token_capacity(
    parser_token_capacity: usize,
    tables: Option<&PrecomputedParseTables>,
) -> ParserCapacityEstimate {
    let parser_token_capacity = parser_token_capacity.max(1);
    let parser_pair_capacity = parser_token_capacity.saturating_sub(1);
    tables
        .map(|tables| {
            projected_parser_capacity(tables, parser_token_capacity, parser_pair_capacity)
        })
        .unwrap_or_else(|| ParserCapacityEstimate {
            path: "llp-unavailable",
            tree_capacity: parser_token_capacity.max(1),
            total_sc: 0,
            total_emit: parser_token_capacity.max(1),
            max_sc_len: 0,
            max_emit_len: 0,
        })
}

pub(super) fn parser_capacity_estimate_for_live_token_count(
    token_capacity: usize,
    parser_tree_capacity: usize,
    tables: Option<&PrecomputedParseTables>,
) -> ParserCapacityEstimate {
    let token_capacity = token_capacity.max(1);
    let parser_pair_capacity = token_capacity.saturating_sub(1);
    tables
        .map(|tables| {
            let max_sc_len = tables.sc_len.iter().copied().max().unwrap_or(0) as usize;
            let max_emit_len = tables.pp_len.iter().copied().max().unwrap_or(0) as usize;
            ParserCapacityEstimate {
                path: "llp-live-gpu-count",
                tree_capacity: parser_tree_capacity.max(1),
                total_sc: parser_pair_capacity.saturating_mul(max_sc_len),
                total_emit: parser_pair_capacity.saturating_mul(max_emit_len),
                max_sc_len,
                max_emit_len,
            }
        })
        .unwrap_or_else(|| ParserCapacityEstimate {
            path: "llp-live-gpu-count-no-tables",
            tree_capacity: parser_tree_capacity.max(1),
            total_sc: 0,
            total_emit: parser_tree_capacity.max(1),
            max_sc_len: 0,
            max_emit_len: 0,
        })
}

pub(super) struct ParserCapacityEstimate {
    path: &'static str,
    tree_capacity: usize,
    total_sc: usize,
    total_emit: usize,
    max_sc_len: usize,
    max_emit_len: usize,
}

pub(super) fn projected_parser_capacity(
    tables: &PrecomputedParseTables,
    parser_token_capacity: usize,
    parser_pair_capacity: usize,
) -> ParserCapacityEstimate {
    let max_sc_len = tables.sc_len.iter().copied().max().unwrap_or(0) as usize;
    let max_emit_len = tables.pp_len.iter().copied().max().unwrap_or(0) as usize;
    let total_sc = parser_pair_capacity.saturating_mul(max_sc_len);
    let total_emit = parser_pair_capacity.saturating_mul(max_emit_len);
    ParserCapacityEstimate {
        path: "llp-projected",
        tree_capacity: resident_projected_tree_capacity(parser_token_capacity, total_emit),
        total_sc,
        total_emit,
        max_sc_len,
        max_emit_len,
    }
}

pub(super) fn resident_projected_tree_capacity(
    parser_token_capacity: usize,
    total_emit: usize,
) -> usize {
    parser_token_capacity
        .saturating_mul(RESIDENT_TREE_PRODUCTION_CAPACITY_PER_TOKEN)
        .max(1)
        .min(total_emit.max(1))
}

pub(super) fn human_bytes(bytes: usize) -> String {
    const KIB: f64 = 1024.0;
    const MIB: f64 = KIB * 1024.0;
    const GIB: f64 = MIB * 1024.0;
    let bytes_f = bytes as f64;
    if bytes_f >= GIB {
        format!("{:.2} GiB", bytes_f / GIB)
    } else if bytes_f >= MIB {
        format!("{:.1} MiB", bytes_f / MIB)
    } else if bytes_f >= KIB {
        format!("{:.1} KiB", bytes_f / KIB)
    } else {
        format!("{bytes} B")
    }
}
