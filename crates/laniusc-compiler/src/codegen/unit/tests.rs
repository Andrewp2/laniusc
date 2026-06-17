use super::*;

fn limits(max_source_bytes: usize, max_source_files: usize) -> CodegenUnitLimits {
    CodegenUnitLimits {
        max_source_bytes,
        max_source_files,
    }
}

fn test_job(job_index: usize, dependency_job_indices: Vec<usize>) -> SourcePackJob {
    SourcePackJob {
        job_index,
        phase: SourcePackJobPhase::Codegen,
        phase_unit_index: job_index,
        library_job_index: None,
        library_id: 0,
        first_source_index: job_index,
        source_file_count: 1,
        source_bytes: 1,
        source_lines: 0,
        oversized_source_file: false,
        dependency_job_indices,
    }
}

fn assert_schedule_orders_dependencies(schedule: &SourcePackJobSchedule) {
    let waves = schedule
        .try_execution_waves()
        .expect("schedule should be acyclic");
    let modeled_waves = model_execution_waves(schedule).expect("model schedule should be acyclic");

    assert_eq!(
        waves
            .waves
            .iter()
            .map(|wave| wave.job_indices.clone())
            .collect::<Vec<_>>(),
        modeled_waves,
        "execution waves should match the ready-set reference model"
    );
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
        "every job should be scheduled exactly once"
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
        if job.phase == SourcePackJobPhase::Link
            && job.dependency_job_indices.is_empty()
            && schedule.dependency_job_ranges(job.job_index).is_empty()
        {
            for codegen_job in schedule
                .jobs
                .iter()
                .filter(|candidate| candidate.phase == SourcePackJobPhase::Codegen)
            {
                assert!(
                    wave_by_job[codegen_job.job_index].expect("codegen job should be scheduled")
                        < job_wave,
                    "link job {} ran before codegen job {}",
                    job.job_index,
                    codegen_job.job_index
                );
            }
        }
    }
}

fn model_execution_waves(schedule: &SourcePackJobSchedule) -> Result<Vec<Vec<usize>>, Vec<usize>> {
    let max_job_index = schedule
        .jobs
        .iter()
        .map(|job| job.job_index)
        .max()
        .unwrap_or(0);
    let mut job_position_by_index = vec![None; max_job_index.saturating_add(1)];
    for (position, job) in schedule.jobs.iter().enumerate() {
        if let Some(slot) = job_position_by_index.get_mut(job.job_index) {
            *slot = Some(position);
        }
    }

    let mut emitted = vec![false; schedule.jobs.len()];
    let mut waves = Vec::new();

    while emitted.iter().any(|done| !*done) {
        let wave = schedule
            .jobs
            .iter()
            .enumerate()
            .filter_map(|(position, job)| {
                (!emitted[position]
                    && model_job_dependencies_satisfied(
                        schedule,
                        job,
                        &job_position_by_index,
                        &emitted,
                    ))
                .then_some(job.job_index)
            })
            .collect::<Vec<_>>();

        if wave.is_empty() {
            return Err(schedule
                .jobs
                .iter()
                .zip(emitted.iter().copied())
                .filter_map(|(job, done)| (!done).then_some(job.job_index))
                .collect());
        }

        for &job_index in &wave {
            let position = job_position_by_index
                .get(job_index)
                .and_then(|position| *position)
                .expect("modeled wave should reference a known job");
            emitted[position] = true;
        }
        waves.push(wave);
    }

    Ok(waves)
}

fn model_job_dependencies_satisfied(
    schedule: &SourcePackJobSchedule,
    job: &SourcePackJob,
    job_position_by_index: &[Option<usize>],
    emitted: &[bool],
) -> bool {
    if job.phase == SourcePackJobPhase::Link
        && job.dependency_job_indices.is_empty()
        && schedule.dependency_job_ranges(job.job_index).is_empty()
    {
        return schedule
            .jobs
            .iter()
            .filter(|candidate| candidate.phase == SourcePackJobPhase::Codegen)
            .all(|candidate| {
                job_position_by_index
                    .get(candidate.job_index)
                    .and_then(|position| *position)
                    .is_some_and(|position| emitted[position])
            });
    }

    job.dependency_job_indices
        .iter()
        .copied()
        .chain(
            schedule
                .dependency_job_ranges(job.job_index)
                .iter()
                .flat_map(|range| range.iter().into_iter().flatten()),
        )
        .all(|dependency_job_index| {
            job_position_by_index
                .get(dependency_job_index)
                .and_then(|position| *position)
                .is_some_and(|position| emitted[position])
        })
}

fn assert_indices_cover_exactly_once(mut actual: Vec<usize>, mut expected: Vec<usize>) {
    actual.sort_unstable();
    expected.sort_unstable();
    assert_eq!(actual, expected);
}

fn assert_shards_cover_batches_once(
    plan: &SourcePackBuildArtifactShardPlan,
    kind: SourcePackBuildArtifactShardKind,
    batch_count: usize,
) {
    assert_indices_cover_exactly_once(
        plan.shards
            .iter()
            .filter(|shard| shard.kind == kind)
            .flat_map(|shard| shard.batch_indices.iter().copied())
            .collect(),
        (0..batch_count).collect(),
    );
}

fn assert_batches_cover_jobs_once(batches: &SourcePackJobBatchSchedule, job_count: usize) {
    assert_indices_cover_exactly_once(
        batches
            .batches
            .iter()
            .flat_map(|batch| batch.job_indices.iter().copied())
            .collect(),
        (0..job_count).collect(),
    );
}

fn assert_batches_respect_limits(
    batches: &SourcePackJobBatchSchedule,
    limits: SourcePackJobBatchLimits,
) {
    let limits = limits.normalized();
    for batch in &batches.batches {
        if batch.oversized {
            assert_eq!(
                batch.job_count(),
                1,
                "oversized execution batch should contain exactly one job"
            );
        } else {
            assert!(
                batch.job_count() <= limits.max_jobs_per_batch,
                "execution batch should respect job limit"
            );
            assert!(
                batch.source_bytes <= limits.max_source_bytes_per_batch,
                "execution batch should respect source-byte limit"
            );
            assert!(
                batch.source_file_count <= limits.max_source_files_per_batch,
                "execution batch should respect source-file limit"
            );
        }
    }
}

fn oversized_job_indices(
    schedule: &SourcePackJobSchedule,
    limits: SourcePackJobBatchLimits,
) -> Vec<usize> {
    let limits = limits.normalized();
    schedule
        .jobs
        .iter()
        .filter(|job| {
            job.source_bytes > limits.max_source_bytes_per_batch
                || job.source_file_count > limits.max_source_files_per_batch
        })
        .map(|job| job.job_index)
        .collect()
}

fn oversized_batch_job_indices(batches: &SourcePackJobBatchSchedule) -> Vec<usize> {
    batches
        .batches
        .iter()
        .filter(|batch| batch.oversized)
        .flat_map(|batch| batch.job_indices.iter().copied())
        .collect()
}

fn expected_link_batch_count(input_count: usize, limits: SourcePackJobBatchLimits) -> usize {
    let limit = link_batch_input_limit(limits);
    input_count.div_ceil(limit)
}

fn assert_link_object_batches_cover_inputs_once(
    batches: &SourcePackLinkObjectBatchPlan,
    expected_inputs: Vec<usize>,
) {
    assert_indices_cover_exactly_once(
        batches
            .batches
            .iter()
            .flat_map(|batch| batch.input_object_artifact_indices.iter().copied())
            .collect(),
        expected_inputs,
    );
}

fn assert_link_interface_batches_cover_inputs_once(
    batches: &SourcePackLinkInterfaceBatchPlan,
    expected_inputs: Vec<usize>,
) {
    assert_indices_cover_exactly_once(
        batches
            .batches
            .iter()
            .flat_map(|batch| batch.input_interface_artifact_indices.iter().copied())
            .collect(),
        expected_inputs,
    );
}

fn assert_link_object_batches_respect_limits(
    batches: &SourcePackLinkObjectBatchPlan,
    limits: SourcePackJobBatchLimits,
) {
    let limits = limits.normalized();
    let input_limit = link_batch_input_limit(limits);
    for batch in &batches.batches {
        assert!(
            batch.object_count() <= input_limit,
            "link object batch should respect input-artifact limit"
        );
        assert!(
            batch.object_count() == 1 || batch.source_bytes <= limits.max_source_bytes_per_batch,
            "multi-input link object batch should respect source-byte limit"
        );
        assert!(
            batch.object_count() == 1
                || batch.source_file_count <= limits.max_source_files_per_batch,
            "multi-input link object batch should respect source-file limit"
        );
    }
}

fn assert_link_interface_batches_respect_limits(
    batches: &SourcePackLinkInterfaceBatchPlan,
    limits: SourcePackJobBatchLimits,
) {
    let limits = limits.normalized();
    let input_limit = link_batch_input_limit(limits);
    for batch in &batches.batches {
        assert!(
            batch.interface_count() <= input_limit,
            "link interface batch should respect input-artifact limit"
        );
        assert!(
            batch.interface_count() == 1 || batch.source_bytes <= limits.max_source_bytes_per_batch,
            "multi-input link interface batch should respect source-byte limit"
        );
        assert!(
            batch.interface_count() == 1
                || batch.source_file_count <= limits.max_source_files_per_batch,
            "multi-input link interface batch should respect source-file limit"
        );
    }
}

fn assert_codegen_units_cover_sources_once(plan: &CodegenUnitPlan, source_file_count: usize) {
    let mut coverage = vec![0usize; source_file_count];
    for unit in &plan.units {
        assert!(
            unit.source_range().end <= source_file_count,
            "codegen unit {} source range {:?} exceeds source file count {source_file_count}",
            unit.unit_index,
            unit.source_range()
        );
        for source_index in unit.source_range() {
            coverage[source_index] += 1;
        }
    }
    assert!(
        coverage.iter().all(|&count| count == 1),
        "codegen units should cover every source exactly once: {coverage:?}"
    );
}

fn assert_frontend_units_cover_sources_once(plan: &FrontendUnitPlan, source_file_count: usize) {
    let mut coverage = vec![0usize; source_file_count];
    for unit in &plan.units {
        assert!(
            unit.source_range().end <= source_file_count,
            "frontend unit {} source range {:?} exceeds source file count {source_file_count}",
            unit.unit_index,
            unit.source_range()
        );
        for source_index in unit.source_range() {
            coverage[source_index] += 1;
        }
    }
    assert!(
        coverage.iter().all(|&count| count == 1),
        "frontend units should cover every source exactly once: {coverage:?}"
    );
}

fn assert_library_units_cover_sources_once(plan: &LibraryUnitPlan, source_file_count: usize) {
    let mut coverage = vec![0usize; source_file_count];
    for library in &plan.libraries {
        assert!(
            library.source_range().end <= source_file_count,
            "library unit {} source range {:?} exceeds source file count {source_file_count}",
            library.library_index,
            library.source_range()
        );
        for source_index in library.source_range() {
            coverage[source_index] += 1;
        }
    }
    assert!(
        coverage.iter().all(|&count| count == 1),
        "library units should cover every source exactly once: {coverage:?}"
    );
}

fn assert_codegen_units_respect_limits(plan: &CodegenUnitPlan, limits: CodegenUnitLimits) {
    let limits = limits.normalized();
    for unit in &plan.units {
        if unit.oversized_source_file {
            assert_eq!(
                unit.source_file_count, 1,
                "oversized codegen unit should contain exactly one source file"
            );
            assert!(
                unit.source_bytes > limits.max_source_bytes,
                "oversized codegen unit should exceed byte limit"
            );
        } else {
            assert!(
                unit.source_file_count <= limits.max_source_files,
                "codegen unit should respect file limit"
            );
            assert!(
                unit.source_bytes <= limits.max_source_bytes,
                "codegen unit should respect byte limit"
            );
        }
    }
}

fn assert_frontend_units_respect_limits(plan: &FrontendUnitPlan, limits: CodegenUnitLimits) {
    let limits = limits.normalized();
    for unit in &plan.units {
        if unit.oversized_source_file {
            assert_eq!(
                unit.source_file_count, 1,
                "oversized frontend unit should contain exactly one source file"
            );
            assert!(
                unit.source_bytes > limits.max_source_bytes,
                "oversized frontend unit should exceed byte limit"
            );
        } else {
            assert!(
                unit.source_file_count <= limits.max_source_files,
                "frontend unit should respect file limit"
            );
            assert!(
                unit.source_bytes <= limits.max_source_bytes,
                "frontend unit should respect byte limit"
            );
        }
    }
}

fn contiguous_library_spans(library_ids: &[u32]) -> Vec<(u32, std::ops::Range<usize>)> {
    let mut spans = Vec::new();
    let mut start = 0usize;
    while start < library_ids.len() {
        let library_id = library_ids[start];
        let mut end = start + 1;
        while end < library_ids.len() && library_ids[end] == library_id {
            end += 1;
        }
        spans.push((library_id, start..end));
        start = end;
    }
    spans
}

fn assert_codegen_units_stay_within_library_spans(plan: &CodegenUnitPlan, library_ids: &[u32]) {
    let spans = contiguous_library_spans(library_ids);
    for unit in &plan.units {
        let unit_range = unit.source_range();
        assert!(
            spans.iter().any(|(library_id, span)| {
                *library_id == unit.library_id
                    && span.start <= unit_range.start
                    && unit_range.end <= span.end
            }),
            "codegen unit {} range {:?} crosses library spans {:?}",
            unit.unit_index,
            unit_range,
            spans
        );
    }
}

fn assert_oversized_codegen_units_match_source_sizes<S: AsRef<str>>(
    plan: &CodegenUnitPlan,
    sources: &[S],
    limits: CodegenUnitLimits,
) {
    let expected_oversized_sources = sources
        .iter()
        .enumerate()
        .filter_map(|(source_index, source)| {
            (source.as_ref().len() > limits.normalized().max_source_bytes).then_some(source_index)
        })
        .collect::<Vec<_>>();
    let actual_oversized_sources = plan
        .units
        .iter()
        .filter(|unit| unit.oversized_source_file)
        .map(|unit| unit.first_source_index)
        .collect::<Vec<_>>();
    assert_eq!(actual_oversized_sources, expected_oversized_sources);
}

fn job_depends_on_job(
    schedule: &SourcePackJobSchedule,
    job: &SourcePackJob,
    dependency_job_index: usize,
) -> bool {
    job.dependency_job_indices.contains(&dependency_job_index)
        || schedule
            .dependency_job_ranges(job.job_index)
            .iter()
            .any(|range| range.contains(dependency_job_index))
}

fn frontend_jobs_for_library(
    schedule: &SourcePackJobSchedule,
    library_id: u32,
) -> Vec<&SourcePackJob> {
    schedule
        .jobs
        .iter()
        .filter(|job| job.phase == SourcePackJobPhase::LibraryFrontend)
        .filter(|job| job.library_id == library_id)
        .collect()
}

fn assert_phase_covers_sources_exactly_once(
    schedule: &SourcePackJobSchedule,
    phase: SourcePackJobPhase,
    source_file_count: usize,
) {
    let mut coverage = vec![0usize; source_file_count];
    for job in schedule.jobs.iter().filter(|job| job.phase == phase) {
        assert!(
            job.source_range().end <= source_file_count,
            "{phase:?} job {} source range {:?} exceeds source file count {source_file_count}",
            job.job_index,
            job.source_range()
        );
        for source_index in job.source_range() {
            coverage[source_index] += 1;
        }
    }
    assert!(
        coverage.iter().all(|&count| count == 1),
        "{phase:?} jobs should cover every source exactly once: {coverage:?}"
    );
}

fn assert_declared_library_dependencies_reach_frontend_jobs(
    schedule: &SourcePackJobSchedule,
    dependencies: &[SourcePackLibraryDependency],
) {
    for dependency in dependencies {
        let dependent_jobs = frontend_jobs_for_library(schedule, dependency.library_id);
        let dependency_jobs = frontend_jobs_for_library(schedule, dependency.depends_on_library_id);
        assert!(
            !dependent_jobs.is_empty(),
            "library {} should have frontend jobs",
            dependency.library_id
        );
        assert!(
            !dependency_jobs.is_empty(),
            "dependency library {} should have frontend jobs",
            dependency.depends_on_library_id
        );

        for dependent_job in dependent_jobs {
            for dependency_job in &dependency_jobs {
                assert!(
                    job_depends_on_job(schedule, dependent_job, dependency_job.job_index),
                    "library {} frontend job {} should depend on library {} frontend job {}",
                    dependency.library_id,
                    dependent_job.job_index,
                    dependency.depends_on_library_id,
                    dependency_job.job_index
                );
            }
        }
    }
}

fn assert_codegen_jobs_wait_for_frontend_inputs(
    schedule: &SourcePackJobSchedule,
    dependencies: &[SourcePackLibraryDependency],
) {
    for codegen_job in schedule
        .jobs
        .iter()
        .filter(|job| job.phase == SourcePackJobPhase::Codegen)
    {
        for frontend_job in frontend_jobs_for_library(schedule, codegen_job.library_id) {
            assert!(
                job_depends_on_job(schedule, codegen_job, frontend_job.job_index),
                "codegen job {} should wait for library {} frontend job {}",
                codegen_job.job_index,
                codegen_job.library_id,
                frontend_job.job_index
            );
        }
        for dependency in dependencies
            .iter()
            .filter(|dependency| dependency.library_id == codegen_job.library_id)
        {
            for frontend_job in
                frontend_jobs_for_library(schedule, dependency.depends_on_library_id)
            {
                assert!(
                    job_depends_on_job(schedule, codegen_job, frontend_job.job_index),
                    "codegen job {} should wait for dependency library {} frontend job {}",
                    codegen_job.job_index,
                    dependency.depends_on_library_id,
                    frontend_job.job_index
                );
            }
        }
    }
}

fn assert_retained_manifest_counts_match_records(manifest: &SourcePackBuildArtifactManifest) {
    assert_eq!(manifest.job_count, manifest.job_schedule.jobs.len());
    assert_eq!(manifest.job_batch_count, manifest.job_batches.batches.len());
    assert_eq!(
        manifest.batch_dependency_count,
        manifest.batch_dependencies.batches.len()
    );
    assert_eq!(manifest.artifact_count, manifest.artifacts.artifacts.len());
    assert_eq!(
        manifest.job_artifact_count,
        manifest.job_artifacts.jobs.len()
    );
    assert_eq!(
        manifest.job_artifact_io_count,
        manifest.job_artifact_io.jobs.len()
    );
    assert_eq!(
        manifest.artifact_use_count,
        manifest.artifact_uses.uses.len()
    );
    assert_eq!(
        manifest.link_interface_batch_count,
        manifest.link_interface_batches.batches.len()
    );
    assert_eq!(
        manifest.link_object_batch_count,
        manifest.link_object_batches.batches.len()
    );
}

#[test]
fn batch_and_shard_limits_are_bounded_by_record_caps() {
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: usize::MAX,
        max_source_bytes_per_batch: usize::MAX,
        max_source_files_per_batch: usize::MAX,
    }
    .normalized();
    assert_eq!(batch_limits, SourcePackJobBatchLimits::default());
    assert!(batch_limits.max_jobs_per_batch < usize::MAX);
    assert!(batch_limits.max_source_bytes_per_batch < usize::MAX);
    assert!(batch_limits.max_source_files_per_batch < usize::MAX);

    let shard_limits = SourcePackBuildShardLimits {
        max_batches_per_shard: usize::MAX,
        max_jobs_per_shard: usize::MAX,
        max_artifacts_per_shard: usize::MAX,
    }
    .normalized();
    assert_eq!(shard_limits, SourcePackBuildShardLimits::default());
    assert!(shard_limits.max_batches_per_shard < usize::MAX);
    assert!(shard_limits.max_jobs_per_shard < usize::MAX);
    assert!(shard_limits.max_artifacts_per_shard < usize::MAX);
}

#[test]
fn codegen_units_respect_file_byte_and_library_boundaries() {
    let sources = ["aaaaaaaaaa", "bbbbbbbbbb", "cccccccccc"];
    let unit_limits = limits(20, 8);
    let plan = CodegenUnitPlan::from_source_pack(&sources, unit_limits);
    assert_codegen_units_cover_sources_once(&plan, sources.len());
    assert_codegen_units_respect_limits(&plan, unit_limits);
    assert!(
        plan.units.len() < sources.len(),
        "codegen should pack adjacent files while respecting byte limits"
    );
    assert_eq!(plan.max_unit_source_bytes(), unit_limits.max_source_bytes);

    let sources = ["a", "b", "c", "d"];
    let libraries = [0u32, 0, 1, 1];
    let unit_limits = limits(64, 8);
    let plan = CodegenUnitPlan::from_source_pack_with_libraries(&sources, &libraries, unit_limits);
    assert_codegen_units_cover_sources_once(&plan, sources.len());
    assert_codegen_units_respect_limits(&plan, unit_limits);
    assert_codegen_units_stay_within_library_spans(&plan, &libraries);
    assert_eq!(
        plan.unit_count(),
        contiguous_library_spans(&libraries).len()
    );

    let sources = ["a", "b", "c", "d", "e"];
    let unit_limits = limits(64, 2);
    let plan = CodegenUnitPlan::from_source_pack(&sources, unit_limits);
    assert_codegen_units_cover_sources_once(&plan, sources.len());
    assert_codegen_units_respect_limits(&plan, unit_limits);
    assert_eq!(plan.max_unit_source_files(), unit_limits.max_source_files);

    let sources = ["small", "this file is too large", "tiny"];
    let unit_limits = limits(8, 8);
    let plan = CodegenUnitPlan::from_source_pack(&sources, unit_limits);
    assert_codegen_units_cover_sources_once(&plan, sources.len());
    assert_codegen_units_respect_limits(&plan, unit_limits);
    assert_oversized_codegen_units_match_source_sizes(&plan, &sources, unit_limits);
}

#[test]
fn frontend_and_library_units_keep_contiguous_library_spans() {
    let sources = ["aaaa", "bbbb", "cccc"];
    let libraries = [5u32, 5, 5];
    let unit_limits = limits(4, 8);
    let plan = FrontendUnitPlan::from_source_pack_with_libraries(&sources, &libraries, unit_limits);
    assert_frontend_units_cover_sources_once(&plan, sources.len());
    assert_frontend_units_respect_limits(&plan, unit_limits);
    assert_eq!(plan.unit_count(), sources.len());
    assert_eq!(plan.max_unit_source_files(), 1);
    assert_eq!(plan.max_unit_source_bytes(), unit_limits.max_source_bytes);

    let sources = ["a", "b", "c", "d", "e"];
    let libraries = [0u32, 0, 1, 1, 0];
    let plan = LibraryUnitPlan::from_source_pack_with_libraries(&sources, &libraries);
    let expected_spans = contiguous_library_spans(&libraries);
    assert_library_units_cover_sources_once(&plan, sources.len());
    assert_eq!(plan.library_count(), expected_spans.len());
    assert_eq!(
        plan.libraries
            .iter()
            .map(|library| (library.library_id, library.source_range()))
            .collect::<Vec<_>>(),
        expected_spans
    );
    assert_eq!(
        plan.max_library_source_files(),
        contiguous_library_spans(&libraries)
            .iter()
            .map(|(_, span)| span.len())
            .max()
            .unwrap_or(0)
    );
}

#[test]
fn source_pack_schedules_preserve_dependency_and_source_coverage_invariants() {
    struct Case {
        name: &'static str,
        sources: Vec<&'static str>,
        libraries: Vec<u32>,
        dependencies: Vec<SourcePackLibraryDependency>,
        limits: CodegenUnitLimits,
    }

    let cases = [
        Case {
            name: "independent libraries",
            sources: vec!["core", "math", "app"],
            libraries: vec![1, 2, 3],
            dependencies: Vec::new(),
            limits: limits(64, 8),
        },
        Case {
            name: "dependency chain",
            sources: vec!["core", "math", "app"],
            libraries: vec![1, 2, 3],
            dependencies: vec![
                SourcePackLibraryDependency {
                    library_id: 2,
                    depends_on_library_id: 1,
                },
                SourcePackLibraryDependency {
                    library_id: 3,
                    depends_on_library_id: 2,
                },
            ],
            limits: limits(64, 8),
        },
        Case {
            name: "dependency diamond",
            sources: vec!["core", "left", "right", "app"],
            libraries: vec![1, 2, 3, 4],
            dependencies: vec![
                SourcePackLibraryDependency {
                    library_id: 2,
                    depends_on_library_id: 1,
                },
                SourcePackLibraryDependency {
                    library_id: 3,
                    depends_on_library_id: 1,
                },
                SourcePackLibraryDependency {
                    library_id: 4,
                    depends_on_library_id: 2,
                },
                SourcePackLibraryDependency {
                    library_id: 4,
                    depends_on_library_id: 3,
                },
            ],
            limits: limits(64, 8),
        },
        Case {
            name: "split libraries with dependencies",
            sources: vec!["aa", "bb", "cc", "dd", "ee"],
            libraries: vec![1, 1, 2, 2, 3],
            dependencies: vec![
                SourcePackLibraryDependency {
                    library_id: 2,
                    depends_on_library_id: 1,
                },
                SourcePackLibraryDependency {
                    library_id: 3,
                    depends_on_library_id: 2,
                },
            ],
            limits: limits(2, 1),
        },
    ];

    for case in cases {
        let plan = SourcePackJobPlan::from_source_pack_with_libraries_and_dependencies(
            &case.sources,
            &case.libraries,
            &case.dependencies,
            case.limits,
        );
        for (schedule_name, schedule) in [
            ("coarse", plan.job_schedule()),
            ("bounded", plan.bounded_frontend_job_schedule()),
        ] {
            assert_eq!(
                schedule.link_job_count(),
                1,
                "{} {schedule_name} schedule should contain one link job",
                case.name
            );
            assert_schedule_orders_dependencies(&schedule);
            assert_phase_covers_sources_exactly_once(
                &schedule,
                SourcePackJobPhase::LibraryFrontend,
                case.sources.len(),
            );
            assert_phase_covers_sources_exactly_once(
                &schedule,
                SourcePackJobPhase::Codegen,
                case.sources.len(),
            );
            assert_declared_library_dependencies_reach_frontend_jobs(&schedule, &case.dependencies);
            assert_codegen_jobs_wait_for_frontend_inputs(&schedule, &case.dependencies);
        }

        for (build_name, build) in [
            ("coarse", plan.build_plan()),
            ("bounded", plan.bounded_frontend_build_plan()),
        ] {
            assert_eq!(
                build.interface_artifact_count(),
                build.schedule.frontend_job_count(),
                "{} {build_name} build should emit one interface artifact per frontend job",
                case.name
            );
            assert_eq!(
                build.object_artifact_count(),
                build.schedule.codegen_job_count(),
                "{} {build_name} build should emit one object artifact per codegen job",
                case.name
            );
            assert_eq!(
                build.linked_output_artifact_count(),
                1,
                "{} {build_name} build should emit one linked output artifact",
                case.name
            );
        }
    }
}

#[test]
fn job_schedule_rejects_cycles_and_missing_dependencies() {
    let cycle = SourcePackJobSchedule {
        jobs: vec![test_job(0, vec![1]), test_job(1, vec![0])],
        dependency_job_ranges_by_job_index: Vec::new(),
    };
    let err = cycle
        .try_execution_waves()
        .expect_err("cycle should not produce ready waves");
    assert_eq!(err.unscheduled_job_indices, vec![0, 1]);
    assert_eq!(
        model_execution_waves(&cycle).expect_err("model should reject cycle"),
        err.unscheduled_job_indices
    );

    let missing = SourcePackJobSchedule {
        jobs: vec![test_job(0, vec![99]), test_job(1, vec![0])],
        dependency_job_ranges_by_job_index: Vec::new(),
    };
    let err = missing
        .try_execution_waves()
        .expect_err("missing dependency should not become ready");
    assert_eq!(err.unscheduled_job_indices, vec![0, 1]);
    assert_eq!(
        model_execution_waves(&missing).expect_err("model should reject missing dependency"),
        err.unscheduled_job_indices
    );
}

#[test]
fn execution_batches_apply_resource_limits_and_preserve_oversized_jobs() {
    let schedule = SourcePackJobSchedule {
        jobs: (0..DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES + 1)
            .map(|job_index| test_job(job_index, Vec::new()))
            .collect(),
        dependency_job_ranges_by_job_index: Vec::new(),
    };

    let batches = schedule
        .try_execution_batches(SourcePackJobBatchLimits {
            max_jobs_per_batch: usize::MAX,
            max_source_bytes_per_batch: usize::MAX,
            max_source_files_per_batch: usize::MAX,
        })
        .expect("batch schedule");

    assert_batches_cover_jobs_once(&batches, schedule.jobs.len());
    assert_batches_respect_limits(&batches, SourcePackJobBatchLimits::default());
    assert!(
        batches.batch_count() > 1,
        "normalized default batch cap should split one-over-limit workloads"
    );
    assert!(
        batches.batches.iter().any(
            |batch| batch.job_count() == SourcePackJobBatchLimits::default().max_jobs_per_batch
        ),
        "test workload should exercise the normalized default job cap"
    );

    let schedule = SourcePackJobSchedule {
        jobs: vec![
            test_job(0, Vec::new()),
            SourcePackJob {
                source_bytes: 10,
                source_file_count: 3,
                ..test_job(1, Vec::new())
            },
        ],
        dependency_job_ranges_by_job_index: Vec::new(),
    };
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 8,
        max_source_bytes_per_batch: 4,
        max_source_files_per_batch: 2,
    };
    let batches = schedule
        .try_execution_batches(batch_limits)
        .expect("oversized job should still be schedulable");

    assert_batches_cover_jobs_once(&batches, schedule.jobs.len());
    assert_batches_respect_limits(&batches, batch_limits);
    assert_indices_cover_exactly_once(
        oversized_batch_job_indices(&batches),
        oversized_job_indices(&schedule, batch_limits),
    );
    assert_eq!(
        batches.oversized_batch_count(),
        oversized_job_indices(&schedule, batch_limits).len()
    );
    assert_eq!(
        batches.max_batch_source_bytes(),
        schedule
            .jobs
            .iter()
            .map(|job| job.source_bytes)
            .max()
            .unwrap_or(0)
    );
    assert_eq!(
        batches.max_batch_source_files(),
        schedule
            .jobs
            .iter()
            .map(|job| job.source_file_count)
            .max()
            .unwrap_or(0)
    );
}

#[test]
fn build_manifest_roundtrips_with_durable_counts() {
    let sources = ["core", "math", "app"];
    let libraries = [1u32, 2, 3];
    let dependencies = [
        SourcePackLibraryDependency {
            library_id: 2,
            depends_on_library_id: 1,
        },
        SourcePackLibraryDependency {
            library_id: 3,
            depends_on_library_id: 2,
        },
    ];
    let build = SourcePackJobPlan::from_source_pack_with_libraries_and_dependencies(
        &sources,
        &libraries,
        &dependencies,
        limits(64, 8),
    )
    .build_plan();
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 2,
        max_source_bytes_per_batch: 8,
        max_source_files_per_batch: 2,
    };
    let manifest = build.retained_build_artifact_manifest(batch_limits);
    let json = serde_json::to_string_pretty(&manifest)
        .expect("serialize source-pack build artifact manifest");
    let roundtrip = serde_json::from_str::<SourcePackBuildArtifactManifest>(&json)
        .expect("deserialize source-pack build artifact manifest");

    assert_eq!(roundtrip, manifest);
    assert_eq!(
        roundtrip.version,
        SOURCE_PACK_BUILD_ARTIFACT_MANIFEST_VERSION
    );
    assert_eq!(roundtrip.target, SourcePackArtifactTarget::Generic);
    assert_retained_manifest_counts_match_records(&roundtrip);
    assert_schedule_orders_dependencies(&roundtrip.job_schedule);
    assert_phase_covers_sources_exactly_once(
        &roundtrip.job_schedule,
        SourcePackJobPhase::LibraryFrontend,
        sources.len(),
    );
    assert_phase_covers_sources_exactly_once(
        &roundtrip.job_schedule,
        SourcePackJobPhase::Codegen,
        sources.len(),
    );
    assert_declared_library_dependencies_reach_frontend_jobs(
        &roundtrip.job_schedule,
        &dependencies,
    );
    assert!(
        roundtrip
            .batch_dependencies
            .batches
            .iter()
            .any(SourcePackJobBatchDependency::has_dependencies),
        "retained manifest should preserve nonempty batch dependency records"
    );
}

#[test]
fn compact_manifest_reports_counts_without_materialized_records() {
    let sources = ["core", "math", "app"];
    let libraries = [1u32, 2, 3];
    let dependencies = [
        SourcePackLibraryDependency {
            library_id: 2,
            depends_on_library_id: 1,
        },
        SourcePackLibraryDependency {
            library_id: 3,
            depends_on_library_id: 2,
        },
    ];
    let plan = SourcePackJobPlan::from_source_pack_with_libraries_and_dependencies(
        &sources,
        &libraries,
        &dependencies,
        limits(64, 8),
    );
    let build = plan.build_plan();
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 2,
        max_source_bytes_per_batch: 8,
        max_source_files_per_batch: 2,
    };
    let full = build.retained_build_artifact_manifest(batch_limits);
    let compact = build.compact_build_artifact_manifest(batch_limits);
    let direct_compact = plan
        .try_compact_build_artifact_manifest_for_schedule(
            &build.schedule,
            batch_limits,
            SourcePackArtifactTarget::Generic,
        )
        .expect("direct compact manifest should use acyclic source-pack schedule");

    assert_eq!(compact.version, full.version);
    assert_eq!(compact.target, full.target);
    assert_eq!(compact.job_count, full.job_count);
    assert_eq!(compact.job_batch_count, full.job_batch_count);
    assert_eq!(compact.batch_dependency_count, full.batch_dependency_count);
    assert_eq!(compact.artifact_count, full.artifact_count);
    assert_eq!(compact.job_artifact_count, full.job_artifact_count);
    assert_eq!(compact.job_artifact_io_count, full.job_artifact_io_count);
    assert_eq!(compact.artifact_use_count, full.artifact_use_count);
    assert_eq!(
        compact.link_interface_batch_count,
        full.link_interface_batch_count
    );
    assert_eq!(
        compact.link_object_batch_count,
        full.link_object_batch_count
    );
    assert_eq!(direct_compact.job_count, compact.job_count);
    assert_eq!(direct_compact.artifact_count, compact.artifact_count);
    assert!(compact.job_schedule.jobs.is_empty());
    assert!(compact.job_batches.batches.is_empty());
    assert!(compact.batch_dependencies.batches.is_empty());
    assert!(compact.artifacts.artifacts.is_empty());
    assert!(compact.job_artifacts.jobs.is_empty());
    assert!(compact.job_artifact_io.jobs.is_empty());
    assert!(compact.artifact_uses.uses.is_empty());
    assert!(compact.link_interface_batches.batches.is_empty());
    assert!(compact.link_object_batches.batches.is_empty());
}

#[test]
fn artifact_keys_are_target_qualified() {
    let sources = ["core", "app"];
    let libraries = [1u32, 2];
    let build =
        SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(64, 8))
            .build_plan();
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 8,
        max_source_bytes_per_batch: 64,
        max_source_files_per_batch: 8,
    };
    let generic = build.retained_build_artifact_manifest(batch_limits);
    let wasm = build
        .retained_build_artifact_manifest_for_target(batch_limits, SourcePackArtifactTarget::Wasm);
    let x86 = build.retained_build_artifact_manifest_for_target(
        batch_limits,
        SourcePackArtifactTarget::X86_64,
    );

    assert_eq!(generic.target, SourcePackArtifactTarget::Generic);
    assert_eq!(wasm.target, SourcePackArtifactTarget::Wasm);
    assert_eq!(x86.target, SourcePackArtifactTarget::X86_64);
    assert_eq!(
        generic.artifacts.artifacts.len(),
        wasm.artifacts.artifacts.len()
    );
    assert_eq!(
        generic.artifacts.artifacts.len(),
        x86.artifacts.artifacts.len()
    );
    for ((generic_artifact, wasm_artifact), x86_artifact) in generic
        .artifacts
        .artifacts
        .iter()
        .zip(&wasm.artifacts.artifacts)
        .zip(&x86.artifacts.artifacts)
    {
        assert!(!generic_artifact.key.starts_with("wasm/"));
        assert!(!generic_artifact.key.starts_with("x86_64/"));
        assert_eq!(
            wasm_artifact
                .key
                .strip_prefix("wasm/")
                .expect("wasm artifact key should be target-qualified"),
            generic_artifact.key
        );
        assert_eq!(
            x86_artifact
                .key
                .strip_prefix("x86_64/")
                .expect("x86 artifact key should be target-qualified"),
            generic_artifact.key
        );
    }
}

#[test]
fn build_shards_cover_batches_and_cap_unbounded_limits() {
    let sources = ["aaaa", "bbbb", "cccc", "dddd"];
    let libraries = [7u32, 7, 8, 8];
    let build =
        SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(4, 8))
            .build_plan();
    let manifest = build.retained_build_artifact_manifest(SourcePackJobBatchLimits {
        max_jobs_per_batch: 1,
        max_source_bytes_per_batch: 8,
        max_source_files_per_batch: 2,
    });
    let plan = manifest.build_artifact_shard_plan(SourcePackBuildShardLimits {
        max_batches_per_shard: 2,
        max_jobs_per_shard: 2,
        max_artifacts_per_shard: 3,
    });

    assert_eq!(
        plan.index.version,
        SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION
    );
    assert_eq!(plan.oversized_shard_count(), 0);
    assert!(plan.max_shard_batch_count() <= 2);
    assert!(plan.max_shard_job_count() <= 2);
    assert!(plan.max_shard_artifact_count() <= 3);
    assert_shards_cover_batches_once(
        &plan,
        SourcePackBuildArtifactShardKind::JobBatches,
        manifest.job_batches.batch_count(),
    );
    assert_shards_cover_batches_once(
        &plan,
        SourcePackBuildArtifactShardKind::LinkInterfaceBatches,
        manifest.link_interface_batches.batch_count(),
    );
    assert_shards_cover_batches_once(
        &plan,
        SourcePackBuildArtifactShardKind::LinkObjectBatches,
        manifest.link_object_batches.batch_count(),
    );

    let batch_count = DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES + 1;
    let manifest = SourcePackBuildArtifactManifest {
        version: SOURCE_PACK_BUILD_ARTIFACT_MANIFEST_VERSION,
        target: SourcePackArtifactTarget::Generic,
        job_count: 0,
        job_batch_count: batch_count,
        batch_dependency_count: 0,
        artifact_count: 0,
        job_artifact_count: 0,
        job_artifact_io_count: 0,
        artifact_use_count: 0,
        link_interface_batch_count: 0,
        link_object_batch_count: 0,
        job_schedule: Default::default(),
        job_batches: SourcePackJobBatchSchedule {
            batches: (0..batch_count)
                .map(|batch_index| SourcePackJobBatch {
                    batch_index,
                    wave_index: 0,
                    job_indices: Vec::new(),
                    source_bytes: 0,
                    source_file_count: 0,
                    source_lines: 0,
                    oversized: false,
                })
                .collect(),
        },
        batch_dependencies: Default::default(),
        artifacts: Default::default(),
        job_artifacts: Default::default(),
        job_artifact_io: Default::default(),
        artifact_uses: Default::default(),
        link_interface_batches: Default::default(),
        link_object_batches: Default::default(),
    };
    let plan = manifest.build_artifact_shard_plan(SourcePackBuildShardLimits {
        max_batches_per_shard: usize::MAX,
        max_jobs_per_shard: usize::MAX,
        max_artifacts_per_shard: usize::MAX,
    });

    assert_eq!(plan.index.limits, SourcePackBuildShardLimits::default());
    assert_eq!(
        plan.max_shard_batch_count(),
        DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES
    );
    assert_shards_cover_batches_once(
        &plan,
        SourcePackBuildArtifactShardKind::JobBatches,
        batch_count,
    );
    assert_eq!(
        plan.shards
            .iter()
            .filter(|shard| shard.kind == SourcePackBuildArtifactShardKind::JobBatches)
            .count(),
        batch_count.div_ceil(DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES)
    );
}

#[test]
fn shard_index_roundtrips_without_shard_payloads() {
    let sources = ["core", "math", "app"];
    let libraries = [1u32, 2, 3];
    let build =
        SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(4, 8))
            .build_plan();
    let manifest = build.retained_build_artifact_manifest(SourcePackJobBatchLimits {
        max_jobs_per_batch: 1,
        max_source_bytes_per_batch: 4,
        max_source_files_per_batch: 1,
    });
    let index = manifest.build_artifact_shard_index(SourcePackBuildShardLimits {
        max_batches_per_shard: 1,
        max_jobs_per_shard: 1,
        max_artifacts_per_shard: 2,
    });
    let json = serde_json::to_string_pretty(&index)
        .expect("serialize source-pack build artifact shard index");
    let roundtrip = serde_json::from_str::<SourcePackBuildArtifactShardIndex>(&json)
        .expect("deserialize source-pack build artifact shard index");
    let schema = serde_json::from_str::<serde_json::Value>(&json)
        .expect("deserialize source-pack build artifact shard index as JSON");
    let schema_object = schema
        .as_object()
        .expect("source-pack build artifact shard index should serialize as an object");

    assert_eq!(roundtrip, index);
    assert!(
        !schema_object.contains_key("shards"),
        "shard index must persist shard descriptors without embedding shard payloads"
    );
    assert_eq!(roundtrip.shard_count(), index.shard_count());
}

#[test]
fn link_inputs_are_batched_and_record_capped() {
    let sources = ["aaaa", "bbbb", "cccc"];
    let libraries = [5u32, 5, 9];
    let build =
        SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(4, 8))
            .build_plan();
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 2,
        max_source_bytes_per_batch: 8,
        max_source_files_per_batch: 8,
    };
    let object_batches = build.link_object_batches(batch_limits);
    let mut expected_object_inputs = Vec::new();
    build
        .link
        .try_for_each_input_object_artifact_index(|artifact_index| {
            expected_object_inputs.push(artifact_index);
            Ok::<(), ()>(())
        })
        .expect("collect link object inputs");

    assert_link_object_batches_cover_inputs_once(&object_batches, expected_object_inputs);
    assert_link_object_batches_respect_limits(&object_batches, batch_limits);
    assert!(
        object_batches.batch_count() > 1,
        "three object inputs with two-input/eight-byte limits should exercise batching"
    );
    assert_eq!(
        object_batches.max_batch_object_count(),
        link_batch_input_limit(batch_limits)
    );
    assert_eq!(
        object_batches.max_batch_source_bytes(),
        batch_limits.max_source_bytes_per_batch
    );

    let input_count = SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE + 1;
    let sources = (0..input_count)
        .map(|source_index| format!("source-{source_index}"))
        .collect::<Vec<_>>();
    let libraries = (0..input_count as u32).collect::<Vec<_>>();
    let build =
        SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(64, 1))
            .build_plan();
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: input_count,
        max_source_bytes_per_batch: usize::MAX,
        max_source_files_per_batch: usize::MAX,
    };

    let interface_batches = build.link_interface_batches(batch_limits);
    let object_batches = build.link_object_batches(batch_limits);
    let mut expected_interface_inputs = Vec::new();
    build
        .link
        .try_for_each_input_interface_artifact_index(|artifact_index| {
            expected_interface_inputs.push(artifact_index);
            Ok::<(), ()>(())
        })
        .expect("collect link interface inputs");
    let mut expected_object_inputs = Vec::new();
    build
        .link
        .try_for_each_input_object_artifact_index(|artifact_index| {
            expected_object_inputs.push(artifact_index);
            Ok::<(), ()>(())
        })
        .expect("collect link object inputs");

    assert_eq!(
        interface_batches.batch_count(),
        expected_link_batch_count(expected_interface_inputs.len(), batch_limits)
    );
    assert_eq!(
        object_batches.batch_count(),
        expected_link_batch_count(expected_object_inputs.len(), batch_limits)
    );
    assert_link_interface_batches_respect_limits(&interface_batches, batch_limits);
    assert_link_object_batches_respect_limits(&object_batches, batch_limits);
    assert_eq!(
        interface_batches.max_batch_interface_count(),
        link_batch_input_limit(batch_limits)
    );
    assert_eq!(
        object_batches.max_batch_object_count(),
        link_batch_input_limit(batch_limits)
    );
    assert_link_interface_batches_cover_inputs_once(&interface_batches, expected_interface_inputs);
    assert_link_object_batches_cover_inputs_once(&object_batches, expected_object_inputs);
}
