use laniusc::codegen::unit::{SourcePackJobPlan, SourcePackJobSchedule};

use super::*;

fn assert_generated_artifact_is_well_formed(
    mode: SourceMode,
    lines: usize,
    seed: u64,
) -> SourceArtifact {
    let first = make_source_artifact(mode, lines, None, seed);
    let second = make_source_artifact(mode, lines, None, seed);

    assert_eq!(
        first.source, second.source,
        "{mode:?} source generation should be deterministic"
    );
    assert_eq!(
        first.sources, second.sources,
        "{mode:?} source-pack generation should be deterministic"
    );
    assert_eq!(
        first.library_ids, second.library_ids,
        "{mode:?} library ids should be deterministic"
    );
    assert_eq!(
        first.library_dependencies, second.library_dependencies,
        "{mode:?} library dependencies should be deterministic"
    );
    assert_eq!(
        first.expected_stdout, second.expected_stdout,
        "{mode:?} stdout oracle should be deterministic"
    );

    assert!(
        !first.source.trim().is_empty(),
        "{mode:?} should emit nonempty source"
    );
    assert_eq!(
        first.sources.join(""),
        first.source,
        "{mode:?} aggregate source should match source-pack fragments"
    );
    assert_eq!(
        first.sources.len(),
        first.library_ids.len(),
        "{mode:?} should attach one library id per source"
    );
    assert!(
        first.expected_stdout.is_some(),
        "{mode:?} should provide a stdout oracle for compile benchmarks"
    );
    if let Some(stdout) = &first.expected_stdout {
        assert!(
            stdout.is_empty() || stdout.ends_with('\n'),
            "{mode:?} stdout oracle should be line-oriented"
        );
    }

    if mode == SourceMode::ModulePack {
        assert!(
            first.sources.len() > 1,
            "module-pack mode should exercise source-pack compilation"
        );
        assert!(
            !first.library_dependencies.is_empty(),
            "module-pack mode should include library dependencies"
        );
    } else {
        assert_eq!(
            first.sources.len(),
            1,
            "{mode:?} should be a single-source benchmark mode"
        );
        assert_eq!(
            first.library_ids,
            vec![0],
            "{mode:?} should use the default single-source library id"
        );
        assert!(
            first.library_dependencies.is_empty(),
            "{mode:?} should not fabricate source-pack dependencies"
        );
    }

    first
}

fn assert_schedule_orders_dependencies(schedule: &SourcePackJobSchedule) {
    let waves = schedule
        .try_execution_waves()
        .expect("generated source-pack schedule should be acyclic");
    let mut wave_by_job = vec![None; schedule.jobs.len()];

    for wave in &waves.waves {
        assert!(
            !wave.job_indices.is_empty(),
            "execution waves should not be empty"
        );
        for &job_index in &wave.job_indices {
            assert!(
                job_index < schedule.jobs.len(),
                "wave references unknown job {job_index}"
            );
            assert!(
                wave_by_job[job_index].replace(wave.wave_index).is_none(),
                "job {job_index} appears in more than one execution wave"
            );
        }
    }

    assert!(
        wave_by_job.iter().all(Option::is_some),
        "every scheduled job should appear in an execution wave"
    );

    for job in &schedule.jobs {
        let job_wave = wave_by_job[job.job_index].expect("job should be scheduled");
        for &dependency_job_index in &job.dependency_job_indices {
            assert!(
                wave_by_job[dependency_job_index].expect("dependency should be scheduled")
                    < job_wave,
                "job {} ran before dependency {}",
                job.job_index,
                dependency_job_index
            );
        }
        for dependency_range in schedule.dependency_job_ranges(job.job_index) {
            for dependency_job_index in dependency_range.first_job_index
                ..dependency_range.first_job_index + dependency_range.job_count
            {
                assert!(
                    wave_by_job[dependency_job_index].expect("dependency should be scheduled")
                        < job_wave,
                    "job {} ran before ranged dependency {}",
                    job.job_index,
                    dependency_job_index
                );
            }
        }
    }
}

#[test]
fn generated_compile_modes_are_deterministic_and_well_formed() {
    for mode in GENERATED_COMPILE_SOURCE_MODES {
        assert_generated_artifact_is_well_formed(mode, 96, 12345);
    }
}

#[test]
fn generated_single_source_modes_honor_target_bytes() {
    for mode in GENERATED_SINGLE_SOURCE_MODES {
        let generated = make_source_artifact(mode, 0, Some(2_048), 67890);
        assert!(
            generated.source.len() >= 2_048,
            "{mode:?} should generate at least the requested target bytes"
        );
    }
}

#[test]
fn cli_source_mode_selection_is_explicit() {
    assert_eq!(
        parse_source_mode(Some("all".to_string())).unwrap(),
        SourceMode::All
    );
    assert!(
        !GENERATED_SINGLE_SOURCE_MODES.contains(&SourceMode::ModulePack),
        "parse/lex benchmark suites should stay single-source"
    );
    assert!(
        GENERATED_COMPILE_SOURCE_MODES.contains(&SourceMode::ModulePack),
        "compile benchmark suites should include source-pack coverage"
    );
    assert!(
        !GENERATED_COMPILE_SOURCE_MODES.contains(&SourceMode::All),
        "suite expansion should not recursively include all"
    );
    assert_eq!(
        generated_source_modes_for_phase(Phase::Parse),
        &GENERATED_SINGLE_SOURCE_MODES
    );
    assert_eq!(
        generated_source_modes_for_phase(Phase::X86),
        &GENERATED_COMPILE_SOURCE_MODES
    );

    for mode in GENERATED_COMPILE_SOURCE_MODES {
        assert_eq!(
            parse_source_mode(Some(mode.name().to_string())).unwrap(),
            mode,
            "{mode:?} should parse from its CLI name"
        );
    }
}

#[test]
fn phase_backend_selection_follows_compilation_boundary() {
    assert_eq!(
        parse_emit_phase(Some("x86_64-elf".to_string())).unwrap(),
        Phase::X86
    );
    assert_eq!(
        parse_phase(Some("x86".to_string()), Phase::Wasm).unwrap(),
        Phase::X86
    );
    assert_eq!(
        parse_phase(Some("compile".to_string()), Phase::X86).unwrap(),
        Phase::X86
    );

    assert_eq!(
        compiler_backends_for_phase(Phase::X86),
        GpuCompilerBackends::x86_only()
    );
    assert_eq!(
        compiler_backends_for_phase(Phase::Wasm),
        GpuCompilerBackends::wasm_only()
    );
    assert_eq!(
        compiler_backends_for_phase(Phase::Lex),
        GpuCompilerBackends::frontend_only()
    );
    assert_eq!(
        compiler_backends_for_phase(Phase::Parse),
        GpuCompilerBackends::frontend_only()
    );
    assert_eq!(
        compiler_backends_for_phase(Phase::TypeCheck),
        GpuCompilerBackends::frontend_only()
    );
}

#[test]
fn capacity_estimates_publish_paper_ordered_parallel_pass_contracts() {
    let contracts = super::capacity::parallel_pass_contracts();
    let groups = contracts
        .iter()
        .map(|contract| contract.pass_group)
        .collect::<Vec<_>>();

    assert_eq!(
        groups,
        vec![
            "frontend_token_stream",
            "parser_tree_records",
            "semantic_record_joins",
            "x86_value_location_allocation",
            "optimization_record_boundary_gap",
            "x86_location_and_byte_emission",
        ],
        "capacity and measurement estimates should keep the paper pipeline order"
    );
    assert_eq!(
        super::capacity::PARALLEL_PASS_CONTRACT_EXECUTION_ORDER,
        groups.join(","),
        "execution-order field should be the same ordered pass-group list"
    );
    assert_eq!(
        super::capacity::PARALLEL_PASS_CONTRACT_SCHEMA,
        "lanius.parallel-pass-contracts.v1"
    );
    assert_eq!(
        super::capacity::PARALLEL_PASS_CONTRACT_POLICY,
        "scale-claims-require-map-scan-scatter-join-contracts"
    );
    assert_eq!(
        super::capacity::PARALLEL_PASS_CONTRACT_ORDER_POLICY,
        "paper-pass-order-record-boundary-sequence"
    );
    assert_eq!(
        super::capacity::PARALLEL_PASS_CONTRACT_STATUS_SCHEMA,
        "lanius.parallel-pass-contract-status.v1"
    );
    assert_eq!(
        super::capacity::PARALLEL_PASS_CONTRACT_LOOP_POLICY,
        "scale-claims-require-unbounded-pass-loops"
    );
    assert_eq!(
        super::capacity::PARALLEL_PASS_CONTRACT_LOOP_STATUS,
        "bounded"
    );
    assert_eq!(
        super::capacity::PARALLEL_PASS_CONTRACT_FALLBACK_STATUS,
        "fail-closed"
    );
    assert_eq!(
        super::capacity::PARALLEL_PASS_CONTRACT_CLAIM_STATUS,
        "blocked"
    );
    assert_eq!(
        super::capacity::PARALLEL_PASS_CONTRACT_CLAIM_BLOCKERS,
        "bounded_pass_loops,fail_closed_passes"
    );
    assert_eq!(
        super::capacity::PARALLEL_PASS_CONTRACT_READINESS_STATUS,
        "blocked"
    );

    let semantic = contracts
        .iter()
        .find(|contract| contract.pass_group == "semantic_record_joins")
        .expect("semantic join contract");
    assert_eq!(semantic.record_boundary, "typed_identity_records");
    assert_eq!(semantic.parallel_primitives, "sort,join,scatter");
    assert_eq!(semantic.claim_boundary, "no-host-semantic-fallback");

    let optimization_gap = contracts
        .iter()
        .find(|contract| contract.pass_group == "optimization_record_boundary_gap")
        .expect("optimization gap contract");
    assert_eq!(
        optimization_gap.record_boundary,
        "missing_optimization_records"
    );
    assert_eq!(optimization_gap.parallel_primitives, "planned-gap");
    assert_eq!(
        optimization_gap.claim_boundary,
        "optimization-contract-absent"
    );

    let x86_emit = contracts
        .iter()
        .find(|contract| contract.pass_group == "x86_location_and_byte_emission")
        .expect("x86 emission contract");
    assert_eq!(
        x86_emit.record_boundary,
        "instruction_location_and_byte_records"
    );
    assert_eq!(x86_emit.parallel_primitives, "map,scan,scatter");
    assert_eq!(x86_emit.claim_boundary, "no-host-byte-patching");
}

#[test]
fn module_pack_schedule_is_acyclic_and_covers_generated_libraries() {
    let generated = assert_generated_artifact_is_well_formed(SourceMode::ModulePack, 120, 975);
    let job_plan = SourcePackJobPlan::from_source_pack_with_libraries_and_dependencies(
        &generated.sources,
        &generated.library_ids,
        &generated.library_dependencies,
        CodegenUnitLimits::default(),
    );
    let schedule = job_plan.job_schedule();

    assert_eq!(job_plan.libraries.library_count(), generated.sources.len());
    assert_eq!(schedule.frontend_job_count(), generated.sources.len());
    assert_eq!(schedule.codegen_job_count(), generated.sources.len());
    assert_eq!(schedule.link_job_count(), 1);
    assert!(
        schedule.dependency_edge_count() >= generated.library_dependencies.len(),
        "schedule should preserve at least the declared library dependency edges"
    );
    assert_schedule_orders_dependencies(&schedule);

    let build_plan = job_plan.build_plan();
    assert_eq!(
        build_plan.interface_artifact_count(),
        generated.sources.len()
    );
    assert_eq!(build_plan.object_artifact_count(), generated.sources.len());
    assert_eq!(build_plan.linked_output_artifact_count(), 1);
    assert_eq!(
        build_plan
            .artifact_last_use_index()
            .artifacts_without_consumers(),
        1,
        "only the final linked output should be unconsumed"
    );
}

#[test]
fn module_pack_descriptor_paths_preserve_library_dependencies() {
    let generated = assert_generated_artifact_is_well_formed(SourceMode::ModulePack, 120, 975);
    let root = std::env::temp_dir().join(format!(
        "laniusc-bench-source-pack-paths-test-{}",
        std::process::id()
    ));
    let _ = fs::remove_dir_all(&root);

    let libraries =
        materialize_generated_source_pack_paths(&generated, &root).expect("materialize paths");

    assert_eq!(libraries.len(), generated.sources.len());
    for (index, library) in libraries.iter().enumerate() {
        assert_eq!(library.library_id, generated.library_ids[index]);
        assert_eq!(library.paths.len(), library.source_file_count);
        assert_eq!(
            library.dependency_library_ids,
            generated
                .library_dependencies
                .iter()
                .filter(|dependency| dependency.library_id == library.library_id)
                .map(|dependency| dependency.depends_on_library_id)
                .collect::<Vec<_>>()
        );
        for path in &library.paths {
            assert!(path.is_file(), "materialized source {}", path.display());
        }
    }

    let _ = fs::remove_dir_all(&root);
}

#[test]
fn interactive_guard_allows_synthetic_x86_source_by_token_count() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../../../tables/parse_tables.bin"))
            .expect("parse tables");
    let generated = make_source_artifact(SourceMode::ExprDense, 10_000, None, 975);
    let source_lines = generated.source.lines().count();

    reject_large_interactive_run(
        Phase::Parse,
        source_lines,
        &generated.source,
        generated.sources.len(),
        false,
        Some(&tables),
    )
    .expect("10k parse benchmark should not be rejected by allocation estimates");

    reject_large_interactive_run(
        Phase::X86,
        source_lines,
        &generated.source,
        generated.sources.len(),
        false,
        Some(&tables),
    )
    .expect("10k x86 benchmark should use token count instead of source-byte capacity");
}

#[test]
fn interactive_guard_rejects_above_20k_lines_without_opt_in() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../../../tables/parse_tables.bin"))
            .expect("parse tables");
    let source = "\n".repeat(20_001);
    let err = reject_large_interactive_run(
        Phase::Parse,
        source.lines().count(),
        &source,
        1,
        false,
        Some(&tables),
    )
    .expect_err("interactive generated runs above 20k lines should require --allow-large");

    assert!(
        err.contains("lines=20001") && err.contains("pass --allow-large"),
        "rejection should identify the line checkpoint and opt-in path: {err}"
    );

    reject_large_interactive_run(
        Phase::Parse,
        source.lines().count(),
        &source,
        1,
        true,
        Some(&tables),
    )
    .expect("--allow-large should be an explicit opt-in for above-20k generated runs");
}

#[test]
fn generated_capacity_snapshots_scale_monotonically_without_gpu_work() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../../../tables/parse_tables.bin"))
            .expect("parse tables");
    let modes = [
        SourceMode::ExprDense,
        SourceMode::LongFunction,
        SourceMode::ModulePack,
    ];

    for mode in modes {
        let mut previous: Option<super::capacity::CompileCapacitySnapshot> = None;
        for lines in [64usize, 128, 256] {
            let generated = assert_generated_artifact_is_well_formed(mode, lines, 0x5ca1e_u64);
            let snapshot = super::capacity::compile_capacity_snapshot_for_source(
                &generated.source,
                generated.sources.len(),
                Some(&tables),
            );

            assert!(
                snapshot.source_bytes < 512 * 1024,
                "{mode:?} lines={lines} should stay a small CPU-only scaling fixture"
            );
            assert_eq!(
                snapshot.parser_token_capacity,
                snapshot.lexer_token_capacity.saturating_add(2),
                "{mode:?} lines={lines} parser capacity should include sentinel tokens"
            );
            assert!(
                snapshot.parser_tree_capacity >= snapshot.parser_token_capacity,
                "{mode:?} lines={lines} projected parser tree capacity should cover tokens"
            );
            assert!(
                snapshot.frontend_floor_bytes >= snapshot.parser_floor_bytes,
                "{mode:?} lines={lines} frontend floor should include parser allocations"
            );
            assert!(
                snapshot.compile_floor_bytes
                    >= snapshot
                        .frontend_floor_bytes
                        .saturating_add(snapshot.x86_floor_bytes),
                "{mode:?} lines={lines} compile floor should include frontend plus x86"
            );
            assert!(
                snapshot.x86_inst_capacity >= 256,
                "{mode:?} lines={lines} x86 instruction capacity should keep the minimum planning floor"
            );

            if let Some(previous) = previous {
                assert!(
                    snapshot.source_bytes >= previous.source_bytes,
                    "{mode:?} source bytes shrank between generated checkpoints"
                );
                assert!(
                    snapshot.lexer_token_capacity >= previous.lexer_token_capacity,
                    "{mode:?} token capacity shrank between generated checkpoints"
                );
                assert!(
                    snapshot.parser_tree_capacity >= previous.parser_tree_capacity,
                    "{mode:?} parser tree capacity shrank between generated checkpoints"
                );
                assert!(
                    snapshot.x86_inst_capacity >= previous.x86_inst_capacity,
                    "{mode:?} x86 instruction capacity shrank between generated checkpoints"
                );
                assert!(
                    snapshot.compile_floor_bytes >= previous.compile_floor_bytes,
                    "{mode:?} compile allocation floor shrank between generated checkpoints"
                );
            }

            previous = Some(snapshot);
        }
    }
}
