use super::*;

/// Converts a schedule-topology failure into a compiler error.
///
/// The scheduling algorithm reports unscheduled jobs when dependency waves
/// cannot make progress. This helper formats that state for the source-pack
/// execution path.
pub(in crate::compiler) fn schedule_error(err: SourcePackScheduleError) -> CompileError {
    CompileError::GpuFrontend(format!(
        "source-pack job schedule has no dependency-ready wave for jobs {:?}",
        err.unscheduled_job_indices
    ))
}

/// Finds a job by global job index in an in-memory schedule.
///
/// Fast-path lookup uses the index as a vector position, then falls back to a
/// scan for schedules whose jobs are not stored at their global index.
pub(in crate::compiler) fn schedule_job(
    schedule: &SourcePackJobSchedule,
    job_index: usize,
) -> Result<&SourcePackJob, CompileError> {
    if let Some(job) = schedule.jobs.get(job_index) {
        if job.job_index == job_index {
            return Ok(job);
        }
    }
    schedule
        .jobs
        .iter()
        .find(|job| job.job_index == job_index)
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack job schedule references missing job {job_index}"
            ))
        })
}

/// Streams explicit dependency job indices for a stored schedule job page.
///
/// Inline dependencies are visited directly. Paged dependencies are validated
/// for contiguous positions and expected page sizes while they are streamed.
pub(in crate::compiler) fn for_each_schedule_job_explicit_dependency_index<F>(
    store: &FilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    page: &SourcePackLibraryScheduleJobPage,
    mut visit: F,
) -> Result<usize, CompileError>
where
    F: FnMut(usize) -> Result<(), CompileError>,
{
    validate_schedule_job_page(
        page,
        schedule_index.target,
        schedule_index.job_count,
        Some(page.job_index),
    )?;
    if !page.job.dependency_job_indices.is_empty() {
        for &dependency_job_index in &page.job.dependency_job_indices {
            if dependency_job_index >= page.job_index {
                return Err(library_partition_contract_error(format!(
                    "schedule job page {} depends on non-prior inline job {}",
                    page.job_index, dependency_job_index
                )));
            }
            visit(dependency_job_index)?;
        }
        return Ok(page.job.dependency_job_indices.len());
    }

    let mut dependency_count = 0usize;
    let explicit_dependency_job_count = schedule_job_explicit_dependency_count(page);
    for page_index in 0..page.dependency_page_count {
        let dependency_page = store.load_library_schedule_job_dependency_page_for_target(
            schedule_index.target,
            page.job_index,
            page_index,
            schedule_index.job_count,
        )?;
        if dependency_page.first_dependency_position != dependency_count {
            return Err(library_partition_contract_error(format!(
                "schedule job page {} dependency page {} starts at {} but streamed {} dependencies",
                page.job_index,
                page_index,
                dependency_page.first_dependency_position,
                dependency_count
            )));
        }
        let remaining_dependency_count = page
            .dependency_job_count
            .checked_sub(dependency_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "schedule job page {} streamed too many dependencies before page {}",
                    page.job_index, page_index
                ))
            })?;
        let expected_page_dependency_count = remaining_dependency_count
            .min(SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE);
        if dependency_page.dependency_count != expected_page_dependency_count {
            return Err(library_partition_contract_error(format!(
                "schedule job page {} dependency page {} has {} dependencies but expected {}",
                page.job_index,
                page_index,
                dependency_page.dependency_count,
                expected_page_dependency_count
            )));
        }
        for dependency_job_index in dependency_page.dependency_job_indices {
            if dependency_job_index >= page.job_index {
                return Err(library_partition_contract_error(format!(
                    "schedule job page {} depends on non-prior paged job {}",
                    page.job_index, dependency_job_index
                )));
            }
            visit(dependency_job_index)?;
            dependency_count += 1;
        }
    }
    if dependency_count != explicit_dependency_job_count {
        return Err(library_partition_contract_error(format!(
            "schedule job page {} streamed {} explicit dependencies but expected {}",
            page.job_index, dependency_count, explicit_dependency_job_count
        )));
    }
    Ok(dependency_count)
}

/// Returns the first dependency index for a stored schedule job, if one exists.
///
/// The lookup handles inline dependencies, ranged dependencies, and paged
/// dependencies. It also checks that every discovered dependency refers to an
/// earlier job, preserving the schedule's acyclic ordering contract.
pub(in crate::compiler) fn schedule_job_first_dependency_index(
    store: &FilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    page: &SourcePackLibraryScheduleJobPage,
) -> Result<Option<usize>, CompileError> {
    validate_schedule_job_page(
        page,
        schedule_index.target,
        schedule_index.job_count,
        Some(page.job_index),
    )?;
    if let Some(&dependency_job_index) = page.job.dependency_job_indices.first() {
        if dependency_job_index >= page.job_index {
            return Err(library_partition_contract_error(format!(
                "schedule job page {} depends on non-prior inline job {}",
                page.job_index, dependency_job_index
            )));
        }
        return Ok(Some(dependency_job_index));
    }
    if schedule_job_explicit_dependency_count(page) == 0 {
        if let Some(range) = page.dependency_job_ranges.first() {
            if range.job_count == 0 {
                return Err(library_partition_contract_error(format!(
                    "schedule job page {} has empty first dependency range",
                    page.job_index
                )));
            }
            if range.first_job_index >= page.job_index {
                return Err(library_partition_contract_error(format!(
                    "schedule job page {} depends on non-prior ranged job {}",
                    page.job_index, range.first_job_index
                )));
            }
            return Ok(Some(range.first_job_index));
        }
        return Ok(None);
    }
    let dependency_page = store.load_library_schedule_job_dependency_page_for_target(
        schedule_index.target,
        page.job_index,
        0,
        schedule_index.job_count,
    )?;
    let Some(&dependency_job_index) = dependency_page.dependency_job_indices.first() else {
        return Err(library_partition_contract_error(format!(
            "schedule job page {} records {} dependencies but first dependency page is empty",
            page.job_index, page.dependency_job_count
        )));
    };
    if dependency_job_index >= page.job_index {
        return Err(library_partition_contract_error(format!(
            "schedule job page {} depends on non-prior paged job {}",
            page.job_index, dependency_job_index
        )));
    }
    Ok(Some(dependency_job_index))
}

/// Loads schedule job metadata without its expanded dependency payload.
///
/// The job page and locator are loaded together, cross-checked, and returned
/// with inline dependency indices cleared so callers receive compact metadata.
pub(in crate::compiler) fn stored_schedule_job_metadata(
    store: &FilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    job_index: usize,
) -> Result<SourcePackJob, CompileError> {
    validate_library_schedule_index(schedule_index, schedule_index.target)?;
    let locator = store.load_library_schedule_job_locator_page_for_target(
        schedule_index.target,
        job_index,
        schedule_index.job_count,
    )?;
    let job_page = store.load_library_schedule_job_page_for_target(
        schedule_index.target,
        job_index,
        schedule_index.job_count,
    )?;
    let mut job = job_page.job;
    job.dependency_job_indices.clear();
    validate_stored_schedule_job_metadata(schedule_index, job_index, &locator, &job)?;
    Ok(job)
}

/// Validates consistency between a job locator and its schedule job metadata.
///
/// The locator determines the expected phase and partition position. The job
/// page must agree with that phase-specific location and remain inside the
/// frontend, codegen, or link range recorded by the schedule index.
pub(in crate::compiler) fn validate_stored_schedule_job_metadata(
    schedule_index: &SourcePackLibraryScheduleIndex,
    job_index: usize,
    locator: &SourcePackLibraryScheduleJobLocatorPage,
    job: &SourcePackJob,
) -> Result<(), CompileError> {
    if job.phase != locator.phase {
        return Err(library_partition_contract_error(format!(
            "schedule job page {} has phase {:?} but locator has {:?}",
            job_index, job.phase, locator.phase
        )));
    }
    match locator.phase {
        SourcePackJobPhase::LibraryFrontend => {
            let partition_index = locator.partition_index.ok_or_else(|| {
                library_partition_contract_error(format!(
                    "frontend job locator {} has no partition",
                    locator.job_index
                ))
            })?;
            if job.job_index != job_index {
                return Err(library_partition_contract_error(format!(
                    "schedule locator for frontend job {job_index} points to partition {} but job page has job {}",
                    partition_index, job.job_index
                )));
            }
            Ok(())
        }
        SourcePackJobPhase::Codegen => {
            let partition_index = locator.partition_index.ok_or_else(|| {
                library_partition_contract_error(format!(
                    "codegen job locator {} has no partition",
                    locator.job_index
                ))
            })?;
            let codegen_job_offset = locator.codegen_job_offset.ok_or_else(|| {
                library_partition_contract_error(format!(
                    "codegen job locator {} has no codegen offset",
                    locator.job_index
                ))
            })?;
            if job.job_index != job_index {
                return Err(library_partition_contract_error(format!(
                    "schedule locator for codegen job {job_index} points to job {}",
                    job.job_index
                )));
            }
            let frontend_job_count = library_schedule_index_frontend_job_count(schedule_index);
            let Some(frontend_job_index) = job.library_job_index else {
                return Err(library_partition_contract_error(format!(
                    "schedule locator for codegen job {job_index} has no owning frontend job"
                )));
            };
            if frontend_job_index >= frontend_job_count {
                return Err(library_partition_contract_error(format!(
                    "schedule locator for codegen job {job_index} points to partition {partition_index} but job page owner {} is outside frontend job range 0..{}",
                    frontend_job_index, frontend_job_count
                )));
            }
            let expected_job_index_floor = frontend_job_count;
            if job.job_index < expected_job_index_floor
                || job.job_index >= schedule_index.link_job_index
            {
                return Err(library_partition_contract_error(format!(
                    "schedule locator for codegen job {job_index} offset {codegen_job_offset} points outside codegen job range {}..{}",
                    expected_job_index_floor, schedule_index.link_job_index
                )));
            }
            Ok(())
        }
        SourcePackJobPhase::Link => {
            if job_index != schedule_index.link_job_index {
                return Err(library_partition_contract_error(format!(
                    "link job locator {} does not match schedule link job {}",
                    job_index, schedule_index.link_job_index
                )));
            }
            Ok(())
        }
    }
}

/// Returns the total dependency count recorded by a schedule job page.
///
/// The total combines explicit dependency records with compact contiguous job
/// ranges so callers can compare summary counts without expanding every range.
pub(in crate::compiler) fn schedule_job_page_dependency_count(
    page: &SourcePackLibraryScheduleJobPage,
) -> usize {
    schedule_job_explicit_dependency_count(page).saturating_add(job_index_range_dependency_count(
        &page.dependency_job_ranges,
    ))
}

/// Visits all frontend jobs represented by a stored schedule page.
///
/// Compact pages may store jobs inline or only by locator/job pages. This
/// iterator normalizes both forms, validates each job against the page range,
/// and reports the dependency count with each visited job.
pub(in crate::compiler) fn for_each_stored_schedule_frontend_job<F>(
    store: &FilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    page: &SourcePackLibrarySchedulePage,
    mut visit: F,
) -> Result<(), CompileError>
where
    F: FnMut(usize, SourcePackJob, usize) -> Result<(), CompileError>,
{
    validate_library_schedule_page_for_index(page, schedule_index)?;
    if !page.frontend_jobs.is_empty() {
        for (offset, job) in page.frontend_jobs.iter().cloned().enumerate() {
            let dependency_job_count = job.dependency_job_indices.len();
            visit(offset, job, dependency_job_count)?;
        }
        return Ok(());
    }

    for offset in 0..library_schedule_page_frontend_job_count(page) {
        let job_index = page.frontend_job_index.checked_add(offset).ok_or_else(|| {
            library_partition_contract_error(format!(
                "schedule page {} frontend job offset {} overflows",
                page.partition_index, offset
            ))
        })?;
        let locator = store.load_library_schedule_job_locator_page_for_target(
            schedule_index.target,
            job_index,
            schedule_index.job_count,
        )?;
        let job_page = store.load_library_schedule_job_page_for_target(
            schedule_index.target,
            job_index,
            schedule_index.job_count,
        )?;
        let dependency_job_count = schedule_job_page_dependency_count(&job_page);
        let mut job = job_page.job;
        job.dependency_job_indices.clear();
        validate_stored_schedule_job_metadata(schedule_index, job_index, &locator, &job)?;
        if job.phase != SourcePackJobPhase::LibraryFrontend
            || job.phase_unit_index
                != library_schedule_page_first_frontend_unit_index(page) + offset
            || job.library_job_index.is_some()
            || job.library_id != page.library_id
        {
            return Err(library_partition_contract_error(format!(
                "stored frontend job {} does not match compact schedule page {} offset {}",
                job_index, page.partition_index, offset
            )));
        }
        visit(offset, job, dependency_job_count)?;
    }
    Ok(())
}

/// Visits all codegen jobs represented by a stored schedule page.
///
/// The iterator supports inline and locator-backed jobs. For locator-backed
/// jobs it also checks the first dependency and owning frontend job to confirm
/// the codegen job belongs to the schedule page being streamed.
pub(in crate::compiler) fn for_each_stored_schedule_codegen_job<F>(
    store: &FilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    page: &SourcePackLibrarySchedulePage,
    mut visit: F,
) -> Result<(), CompileError>
where
    F: FnMut(usize, SourcePackJob) -> Result<(), CompileError>,
{
    validate_library_schedule_page_for_index(page, schedule_index)?;
    if !page.codegen_jobs.is_empty() {
        for (offset, job) in page.codegen_jobs.iter().cloned().enumerate() {
            visit(offset, job)?;
        }
        return Ok(());
    }

    for offset in 0..page.codegen_job_count {
        let job_index = page
            .first_codegen_job_index
            .checked_add(offset)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "schedule page {} codegen job offset {} overflows",
                    page.partition_index, offset
                ))
            })?;
        let locator = store.load_library_schedule_job_locator_page_for_target(
            schedule_index.target,
            job_index,
            schedule_index.job_count,
        )?;
        let job_page = store.load_library_schedule_job_page_for_target(
            schedule_index.target,
            job_index,
            schedule_index.job_count,
        )?;
        let first_dependency_job_index =
            schedule_job_first_dependency_index(store, schedule_index, &job_page)?;
        let mut job = job_page.job;
        job.dependency_job_indices.clear();
        validate_stored_schedule_job_metadata(schedule_index, job_index, &locator, &job)?;
        if job.phase != SourcePackJobPhase::Codegen
            || job.phase_unit_index != page.first_codegen_unit_index.saturating_add(offset)
            || !job.library_job_index.is_some_and(|frontend_job_index| {
                library_schedule_page_contains_frontend_job(page, frontend_job_index)
                    .unwrap_or(false)
            })
            || job.library_id != page.library_id
        {
            return Err(library_partition_contract_error(format!(
                "stored schedule job {} does not match compact schedule page {} offset {}",
                job_index, page.partition_index, offset
            )));
        }
        let owning_frontend_job_index = job
            .library_job_index
            .expect("codegen job owner checked above");
        if first_dependency_job_index != Some(owning_frontend_job_index) {
            return Err(library_partition_contract_error(format!(
                "stored schedule job {} first dependency {:?} is not owning frontend job {}",
                job.job_index, first_dependency_job_index, owning_frontend_job_index
            )));
        }
        visit(offset, job)?;
    }
    Ok(())
}
