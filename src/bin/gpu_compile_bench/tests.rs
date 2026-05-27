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
