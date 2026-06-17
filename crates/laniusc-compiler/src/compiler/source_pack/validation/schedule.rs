use super::*;

pub(in crate::compiler) fn validate_library_schedule_index(
    index: &SourcePackLibraryScheduleIndex,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if index.version != SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library schedule index version {}; expected {}",
            index.version, SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION
        )));
    }
    if index.target != target {
        return Err(library_partition_contract_error(format!(
            "schedule index target {:?} does not match requested target {:?}",
            index.target, target
        )));
    }
    if index.partition_count == 0 {
        return Err(library_partition_contract_error(
            "schedule index has no partitions",
        ));
    }
    if index.codegen_job_count == 0 {
        return Err(library_partition_contract_error(
            "schedule index has no codegen jobs",
        ));
    }
    let frontend_job_count = library_schedule_index_frontend_job_count(index);
    if frontend_job_count == 0 {
        return Err(library_partition_contract_error(
            "schedule index has no frontend jobs",
        ));
    }
    let expected_link_job_index = frontend_job_count
        .checked_add(index.codegen_job_count)
        .ok_or_else(|| {
            library_partition_contract_error("schedule index frontend/codegen job counts overflow")
        })?;
    if index.link_job_index != expected_link_job_index {
        return Err(library_partition_contract_error(format!(
            "schedule index link job {}, expected {}",
            index.link_job_index, expected_link_job_index
        )));
    }
    let expected_job_count = index
        .link_job_index
        .checked_add(1)
        .ok_or_else(|| library_partition_contract_error("schedule index job count overflows"))?;
    if index.job_count != expected_job_count {
        return Err(library_partition_contract_error(format!(
            "schedule index job_count {} does not match link job {}",
            index.job_count, index.link_job_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_library_schedule_prepare_progress(
    progress: &FilesystemLibrarySchedulePrepareProgress,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if progress.version != SOURCE_PACK_LIBRARY_SCHEDULE_PREPARE_PROGRESS_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library schedule prepare progress version {}; expected {}",
            progress.version, SOURCE_PACK_LIBRARY_SCHEDULE_PREPARE_PROGRESS_VERSION
        )));
    }
    if progress.target != target {
        return Err(library_partition_contract_error(format!(
            "library schedule prepare progress target {:?} does not match requested target {:?}",
            progress.target, target
        )));
    }
    if progress.library_count != progress.library_partition_count
        || progress.library_source_file_page_count != progress.library_partition_count
    {
        return Err(library_partition_contract_error(format!(
            "library schedule prepare progress has inconsistent library counts: libraries={} partitions={} source_file_pages={}",
            progress.library_count,
            progress.library_partition_count,
            progress.library_source_file_page_count
        )));
    }
    if progress.next_partition_index > progress.library_partition_count {
        return Err(library_partition_contract_error(format!(
            "library schedule prepare progress next partition {} exceeds partition count {}",
            progress.next_partition_index, progress.library_partition_count
        )));
    }
    if progress.library_build_unit_page_count > progress.library_partition_count
        || progress.library_schedule_page_count > progress.library_partition_count
    {
        return Err(library_partition_contract_error(format!(
            "library schedule prepare progress has too many prepared pages: build_units={} schedule_pages={} partitions={}",
            progress.library_build_unit_page_count,
            progress.library_schedule_page_count,
            progress.library_partition_count
        )));
    }
    match progress.phase {
        FilesystemLibrarySchedulePreparePhase::BuildUnitPages => {
            if progress.library_schedule_page_count != 0 {
                return Err(library_partition_contract_error(
                    "build-unit schedule progress has prepared schedule pages",
                ));
            }
            if progress.next_partition_index != progress.library_build_unit_page_count {
                return Err(library_partition_contract_error(format!(
                    "build-unit schedule progress next partition {} does not match build-unit page count {}",
                    progress.next_partition_index, progress.library_build_unit_page_count
                )));
            }
        }
        FilesystemLibrarySchedulePreparePhase::SchedulePages => {
            if progress.library_build_unit_page_count != progress.library_partition_count {
                return Err(library_partition_contract_error(
                    "schedule-page progress requires all build-unit pages",
                ));
            }
            if progress.next_partition_index != progress.library_schedule_page_count {
                return Err(library_partition_contract_error(format!(
                    "schedule-page progress next partition {} does not match schedule page count {}",
                    progress.next_partition_index, progress.library_schedule_page_count
                )));
            }
            let frontend_job_count = progress
                .frontend_job_count
                .min(progress.next_frontend_job_index);
            if frontend_job_count != progress.next_frontend_job_index {
                return Err(library_partition_contract_error(
                    "schedule-page progress next frontend job exceeds total frontend jobs",
                ));
            }
            let first_codegen_job_index = progress.frontend_job_count;
            if progress.next_codegen_job_index < first_codegen_job_index {
                return Err(library_partition_contract_error(
                    "schedule-page progress next codegen job precedes frontend jobs",
                ));
            }
        }
        FilesystemLibrarySchedulePreparePhase::Complete => {
            if progress.next_partition_index != progress.library_partition_count
                || progress.library_build_unit_page_count != progress.library_partition_count
                || progress.library_schedule_page_count != progress.library_partition_count
            {
                return Err(library_partition_contract_error(
                    "complete schedule progress does not cover every partition",
                ));
            }
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_schedule_job_inline_dependency_count(
    job: &SourcePackJob,
    context: &str,
) -> Result<(), CompileError> {
    if job.dependency_job_indices.len()
        > SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE
    {
        return Err(library_partition_contract_error(format!(
            "{context} stores {} inline dependency records, exceeding record cap {}",
            job.dependency_job_indices.len(),
            SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_library_schedule_page(
    page: &SourcePackLibrarySchedulePage,
    target: SourcePackArtifactTarget,
    expected_partition_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_LIBRARY_SCHEDULE_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library schedule page version {}; expected {}",
            page.version, SOURCE_PACK_LIBRARY_SCHEDULE_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(library_partition_contract_error(format!(
            "schedule page {} target {:?} does not match requested target {:?}",
            page.partition_index, page.target, target
        )));
    }
    if let Some(expected_partition_index) = expected_partition_index {
        if page.partition_index != expected_partition_index {
            return Err(library_partition_contract_error(format!(
                "loaded schedule page {} but expected {}",
                page.partition_index, expected_partition_index
            )));
        }
    }
    if page.dependency_library_ids.len() > SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE {
        return Err(library_partition_contract_error(format!(
            "schedule page {} stores {} inline dependency library records, exceeding record cap {}",
            page.partition_index,
            page.dependency_library_ids.len(),
            SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE
        )));
    }
    if page.frontend_jobs.len() > SOURCE_PACK_LIBRARY_SCHEDULE_INLINE_JOB_DEFAULT_RECORD_CAP {
        return Err(library_partition_contract_error(format!(
            "schedule page {} stores {} inline frontend-job records, exceeding record cap {}",
            page.partition_index,
            page.frontend_jobs.len(),
            SOURCE_PACK_LIBRARY_SCHEDULE_INLINE_JOB_DEFAULT_RECORD_CAP
        )));
    }
    if page.codegen_jobs.len() > SOURCE_PACK_LIBRARY_SCHEDULE_INLINE_JOB_DEFAULT_RECORD_CAP {
        return Err(library_partition_contract_error(format!(
            "schedule page {} stores {} inline codegen-job records, exceeding record cap {}",
            page.partition_index,
            page.codegen_jobs.len(),
            SOURCE_PACK_LIBRARY_SCHEDULE_INLINE_JOB_DEFAULT_RECORD_CAP
        )));
    }
    validate_job_shape(
        &page.frontend_job,
        &format!("schedule page {} first frontend job", page.partition_index),
        |message| library_partition_contract_error(message),
    )?;
    validate_schedule_job_inline_dependency_count(
        &page.frontend_job,
        &format!(
            "schedule page {} first frontend dependencies",
            page.partition_index
        ),
    )?;
    if page.codegen_jobs.len() != page.codegen_job_count {
        if !page.codegen_jobs.is_empty() {
            return Err(library_partition_contract_error(format!(
                "schedule page {} has {} codegen jobs but codegen_job_count {}",
                page.partition_index,
                page.codegen_jobs.len(),
                page.codegen_job_count
            )));
        }
    }
    if page.codegen_job_count == 0 {
        return Err(library_partition_contract_error(format!(
            "schedule page {} has no codegen jobs",
            page.partition_index
        )));
    }
    let frontend_job_count = library_schedule_page_frontend_job_count(page);
    if frontend_job_count == 0 {
        return Err(library_partition_contract_error(format!(
            "schedule page {} has no frontend jobs",
            page.partition_index
        )));
    }
    if !page.frontend_jobs.is_empty() && page.frontend_jobs.len() != frontend_job_count {
        return Err(library_partition_contract_error(format!(
            "schedule page {} has {} inline frontend jobs but frontend_job_count {}",
            page.partition_index,
            page.frontend_jobs.len(),
            frontend_job_count
        )));
    }

    if page.frontend_job.job_index != page.frontend_job_index
        || page.frontend_job.phase != SourcePackJobPhase::LibraryFrontend
        || page.frontend_job.phase_unit_index
            != library_schedule_page_first_frontend_unit_index(page)
        || page.frontend_job.library_job_index.is_some()
        || page.frontend_job.library_id != page.library_id
    {
        return Err(library_partition_contract_error(format!(
            "schedule page {} frontend job does not match page metadata",
            page.partition_index
        )));
    }

    let mut dependency_ids = BTreeSet::new();
    let mut previous_dependency_library_id = None;
    for dependency_library_id in &page.dependency_library_ids {
        if *dependency_library_id == page.library_id {
            return Err(library_partition_contract_error(format!(
                "schedule page {} library {} depends on itself",
                page.partition_index, page.library_id
            )));
        }
        if let Some(previous_dependency_library_id) = previous_dependency_library_id
            && *dependency_library_id <= previous_dependency_library_id
        {
            return Err(library_partition_contract_error(format!(
                "schedule page {} dependency library ids must be strictly ascending; id {} follows {}",
                page.partition_index, dependency_library_id, previous_dependency_library_id
            )));
        }
        previous_dependency_library_id = Some(*dependency_library_id);
        if !dependency_ids.insert(*dependency_library_id) {
            return Err(library_partition_contract_error(format!(
                "schedule page {} contains duplicate dependency library {}",
                page.partition_index, dependency_library_id
            )));
        }
    }
    unique_usize_set(
        &page.frontend_job.dependency_job_indices,
        &format!(
            "schedule page {} first frontend dependencies",
            page.partition_index
        ),
    )?;

    for (offset, job) in page.frontend_jobs.iter().enumerate() {
        let expected_job_index = page.frontend_job_index + offset;
        validate_job_shape(
            job,
            &format!(
                "schedule page {} frontend job {}",
                page.partition_index, job.job_index
            ),
            |message| library_partition_contract_error(message),
        )?;
        validate_schedule_job_inline_dependency_count(
            job,
            &format!(
                "schedule page {} frontend job {} dependencies",
                page.partition_index, job.job_index
            ),
        )?;
        if job.job_index != expected_job_index
            || job.phase != SourcePackJobPhase::LibraryFrontend
            || job.phase_unit_index
                != library_schedule_page_first_frontend_unit_index(page) + offset
            || job.library_job_index.is_some()
            || job.library_id != page.library_id
        {
            return Err(library_partition_contract_error(format!(
                "schedule page {} frontend job entry {} does not match page metadata",
                page.partition_index, offset
            )));
        }
        unique_usize_set(
            &job.dependency_job_indices,
            &format!(
                "schedule page {} frontend job {} dependencies",
                page.partition_index, job.job_index
            ),
        )?;
    }

    for (offset, job) in page.codegen_jobs.iter().enumerate() {
        let expected_job_index = page.first_codegen_job_index + offset;
        validate_job_shape(
            job,
            &format!(
                "schedule page {} codegen job {}",
                page.partition_index, job.job_index
            ),
            |message| library_partition_contract_error(message),
        )?;
        validate_schedule_job_inline_dependency_count(
            job,
            &format!(
                "schedule page {} codegen job {} dependencies",
                page.partition_index, job.job_index
            ),
        )?;
        if job.job_index != expected_job_index
            || job.phase != SourcePackJobPhase::Codegen
            || job.phase_unit_index != page.first_codegen_unit_index + offset
            || !job.library_job_index.is_some_and(|frontend_job_index| {
                library_schedule_page_contains_frontend_job(page, frontend_job_index)
                    .unwrap_or(false)
            })
            || job.library_id != page.library_id
        {
            return Err(library_partition_contract_error(format!(
                "schedule page {} codegen job entry {} does not match page metadata",
                page.partition_index, offset
            )));
        }
        unique_usize_set(
            &job.dependency_job_indices,
            &format!(
                "schedule page {} codegen job {} dependencies",
                page.partition_index, job.job_index
            ),
        )?;
        if !job
            .dependency_job_indices
            .contains(&job.library_job_index.expect("checked above"))
        {
            return Err(library_partition_contract_error(format!(
                "schedule page {} codegen job {} does not depend on owning frontend job {:?}",
                page.partition_index, job.job_index, job.library_job_index
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_library_schedule_page_for_index(
    page: &SourcePackLibrarySchedulePage,
    index: &SourcePackLibraryScheduleIndex,
) -> Result<(), CompileError> {
    validate_library_schedule_index(index, index.target)?;
    validate_library_schedule_page(page, index.target, Some(page.partition_index))?;
    if page.partition_index >= index.partition_count {
        return Err(library_partition_contract_error(format!(
            "schedule page {} is outside schedule index partition count {}",
            page.partition_index, index.partition_count
        )));
    }
    if page.link_job_index != index.link_job_index {
        return Err(library_partition_contract_error(format!(
            "schedule page {} link job {} does not match schedule index link job {}",
            page.partition_index, page.link_job_index, index.link_job_index
        )));
    }

    let index_frontend_job_count = library_schedule_index_frontend_job_count(index);
    let page_frontend_job_count = library_schedule_page_frontend_job_count(page);
    let page_frontend_job_end = page
        .frontend_job_index
        .checked_add(page_frontend_job_count)
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "schedule page {} frontend job range overflows",
                page.partition_index
            ))
        })?;
    if page_frontend_job_end > index_frontend_job_count {
        return Err(library_partition_contract_error(format!(
            "schedule page {} frontend job range {}..{} exceeds schedule index frontend range 0..{}",
            page.partition_index,
            page.frontend_job_index,
            page_frontend_job_end,
            index_frontend_job_count
        )));
    }

    if page.first_codegen_job_index < index_frontend_job_count {
        return Err(library_partition_contract_error(format!(
            "schedule page {} codegen job range starts at {}, before schedule index codegen range {}..{}",
            page.partition_index,
            page.first_codegen_job_index,
            index_frontend_job_count,
            index.link_job_index
        )));
    }
    let page_codegen_job_end = page
        .first_codegen_job_index
        .checked_add(page.codegen_job_count)
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "schedule page {} codegen job range overflows",
                page.partition_index
            ))
        })?;
    if page_codegen_job_end > index.link_job_index {
        return Err(library_partition_contract_error(format!(
            "schedule page {} codegen job range {}..{} exceeds schedule index codegen range {}..{}",
            page.partition_index,
            page.first_codegen_job_index,
            page_codegen_job_end,
            index_frontend_job_count,
            index.link_job_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_schedule_job_locator_index(
    index: &SourcePackLibraryScheduleJobLocatorIndex,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if index.version != SOURCE_PACK_LIBRARY_SCHEDULE_JOB_LOCATOR_INDEX_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library schedule job-locator index version {}; expected {}",
            index.version, SOURCE_PACK_LIBRARY_SCHEDULE_JOB_LOCATOR_INDEX_VERSION
        )));
    }
    if index.target != target {
        return Err(library_partition_contract_error(format!(
            "schedule job-locator index target {:?} does not match requested target {:?}",
            index.target, target
        )));
    }
    if index.job_count == 0 {
        return Err(library_partition_contract_error(
            "schedule job-locator index has no jobs",
        ));
    }
    if index.locator_count != index.job_count {
        return Err(library_partition_contract_error(format!(
            "schedule job-locator index has {} locators but {} jobs",
            index.locator_count, index.job_count
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_frontend_job_locator_page(
    page: &SourcePackLibraryFrontendJobLocatorPage,
    target: SourcePackArtifactTarget,
    expected_library_id: Option<u32>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_LIBRARY_FRONTEND_JOB_LOCATOR_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library frontend-job locator page version {}; expected {}",
            page.version, SOURCE_PACK_LIBRARY_FRONTEND_JOB_LOCATOR_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(library_partition_contract_error(format!(
            "library frontend-job locator for library {} target {:?} does not match requested target {:?}",
            page.library_id, page.target, target
        )));
    }
    if let Some(expected_library_id) = expected_library_id {
        if page.library_id != expected_library_id {
            return Err(library_partition_contract_error(format!(
                "loaded frontend-job locator for library {} but expected {}",
                page.library_id, expected_library_id
            )));
        }
    }
    if library_frontend_job_locator_count(page) == 0 {
        return Err(library_partition_contract_error(format!(
            "library frontend-job locator for library {} has no frontend jobs",
            page.library_id
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_schedule_job_locator_page(
    page: &SourcePackLibraryScheduleJobLocatorPage,
    target: SourcePackArtifactTarget,
    job_count: usize,
    expected_job_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_LIBRARY_SCHEDULE_JOB_LOCATOR_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library schedule job-locator page version {}; expected {}",
            page.version, SOURCE_PACK_LIBRARY_SCHEDULE_JOB_LOCATOR_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(library_partition_contract_error(format!(
            "schedule job-locator page target {:?} does not match requested target {:?}",
            page.target, target
        )));
    }
    if let Some(expected_job_index) = expected_job_index {
        if page.job_index != expected_job_index {
            return Err(library_partition_contract_error(format!(
                "loaded schedule job-locator page {} but expected {}",
                page.job_index, expected_job_index
            )));
        }
    }
    if page.job_index >= job_count {
        return Err(library_partition_contract_error(format!(
            "schedule job-locator page {} exceeds job count {}",
            page.job_index, job_count
        )));
    }
    match page.phase {
        SourcePackJobPhase::LibraryFrontend => {
            if page.partition_index.is_none() || page.codegen_job_offset.is_some() {
                return Err(library_partition_contract_error(format!(
                    "frontend job-locator page {} has partition {:?} and codegen offset {:?}",
                    page.job_index, page.partition_index, page.codegen_job_offset
                )));
            }
        }
        SourcePackJobPhase::Codegen => {
            if page.partition_index.is_none() || page.codegen_job_offset.is_none() {
                return Err(library_partition_contract_error(format!(
                    "codegen job-locator page {} is missing partition or codegen offset",
                    page.job_index
                )));
            }
        }
        SourcePackJobPhase::Link => {
            if page.partition_index.is_some() || page.codegen_job_offset.is_some() {
                return Err(library_partition_contract_error(format!(
                    "link job-locator page {} has partition {:?} and codegen offset {:?}",
                    page.job_index, page.partition_index, page.codegen_job_offset
                )));
            }
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_schedule_job_page(
    page: &SourcePackLibraryScheduleJobPage,
    target: SourcePackArtifactTarget,
    job_count: usize,
    expected_job_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_LIBRARY_SCHEDULE_JOB_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library schedule job page version {}; expected {}",
            page.version, SOURCE_PACK_LIBRARY_SCHEDULE_JOB_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(library_partition_contract_error(format!(
            "schedule job page target {:?} does not match requested target {:?}",
            page.target, target
        )));
    }
    if let Some(expected_job_index) = expected_job_index {
        if page.job_index != expected_job_index {
            return Err(library_partition_contract_error(format!(
                "loaded schedule job page {} but requested job {}",
                page.job_index, expected_job_index
            )));
        }
    }
    if page.job_index >= job_count {
        return Err(library_partition_contract_error(format!(
            "schedule job page {} exceeds job_count {}",
            page.job_index, job_count
        )));
    }
    if page.job.job_index != page.job_index {
        return Err(library_partition_contract_error(format!(
            "schedule job page {} contains job {}",
            page.job_index, page.job.job_index
        )));
    }
    validate_job_shape(
        &page.job,
        &format!("schedule job page {}", page.job_index),
        |message| library_partition_contract_error(message),
    )?;
    let explicit_dependency_job_count = schedule_job_explicit_dependency_count(page);
    if !page.job.dependency_job_indices.is_empty() && page.dependency_job_count != 0 {
        return Err(library_partition_contract_error(format!(
            "schedule job page {} records both inline and paged dependencies",
            page.job_index
        )));
    }
    if page.job.dependency_job_indices.len()
        > SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE
    {
        return Err(library_partition_contract_error(format!(
            "schedule job page {} stores {} inline dependency records, exceeding record cap {}",
            page.job_index,
            page.job.dependency_job_indices.len(),
            SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE
        )));
    }
    if page.dependency_job_ranges.len()
        > SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE
    {
        return Err(library_partition_contract_error(format!(
            "schedule job page {} stores {} inline dependency range records, exceeding record cap {}",
            page.job_index,
            page.dependency_job_ranges.len(),
            SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE
        )));
    }
    if page.dependency_job_count == 0 {
        if page.dependency_page_count != 0 {
            return Err(library_partition_contract_error(format!(
                "schedule job page {} has dependency page count {} without dependencies",
                page.job_index, page.dependency_page_count
            )));
        }
    } else {
        let expected_page_count = page
            .dependency_job_count
            .div_ceil(SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE);
        if page.dependency_page_count != expected_page_count {
            return Err(library_partition_contract_error(format!(
                "schedule job page {} has dependency page count {} but expected {} for {} dependencies",
                page.job_index,
                page.dependency_page_count,
                expected_page_count,
                page.dependency_job_count
            )));
        }
    }
    let explicit_dependencies = unique_usize_set(
        &page.job.dependency_job_indices,
        &format!("schedule job page {} dependencies", page.job_index),
    )?;
    validate_usize_values_strictly_ascending(
        &page.job.dependency_job_indices,
        &format!("schedule job page {} dependencies", page.job_index),
        |message| library_partition_contract_error(message),
    )?;
    validate_job_dependency_ranges(
        &page.dependency_job_ranges,
        &explicit_dependencies,
        &format!("schedule job page {}", page.job_index),
        page.job_index,
        |message| library_partition_contract_error(message),
    )?;
    for &dependency_job_index in &page.job.dependency_job_indices {
        if dependency_job_index >= page.job_index {
            return Err(library_partition_contract_error(format!(
                "schedule job page {} depends on non-prior job {}",
                page.job_index, dependency_job_index
            )));
        }
    }
    let dependency_job_count = explicit_dependency_job_count.saturating_add(
        page.dependency_job_ranges
            .iter()
            .map(|range| range.job_count)
            .sum::<usize>(),
    );
    if dependency_job_count > page.job_index {
        return Err(library_partition_contract_error(format!(
            "schedule job page {} dependency count {} exceeds prior job count {}",
            page.job_index, dependency_job_count, page.job_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_schedule_job_dependency_page(
    page: &SourcePackLibraryScheduleJobDependencyPage,
    target: SourcePackArtifactTarget,
    job_count: usize,
    expected_job_index: usize,
    expected_page_index: usize,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library schedule job dependency page version {}; expected {}",
            page.version, SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(library_partition_contract_error(format!(
            "schedule job dependency page {} target {:?} does not match requested target {:?}",
            page.job_index, page.target, target
        )));
    }
    if page.job_index != expected_job_index {
        return Err(library_partition_contract_error(format!(
            "loaded schedule job dependency page for job {} but expected {}",
            page.job_index, expected_job_index
        )));
    }
    if page.page_index != expected_page_index {
        return Err(library_partition_contract_error(format!(
            "loaded schedule job dependency page {} for job {} but expected page {}",
            page.page_index, page.job_index, expected_page_index
        )));
    }
    let expected_first_position = expected_page_index
        .saturating_mul(SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE);
    if page.first_dependency_position != expected_first_position {
        return Err(library_partition_contract_error(format!(
            "schedule job dependency page {} for job {} starts at {} but expected {}",
            page.page_index,
            page.job_index,
            page.first_dependency_position,
            expected_first_position
        )));
    }
    if page.dependency_count != page.dependency_job_indices.len() {
        return Err(library_partition_contract_error(format!(
            "schedule job dependency page {} for job {} records {} dependencies but stores {}",
            page.page_index,
            page.job_index,
            page.dependency_count,
            page.dependency_job_indices.len()
        )));
    }
    if page.dependency_count > SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE {
        return Err(library_partition_contract_error(format!(
            "schedule job dependency page {} for job {} exceeds page size {}",
            page.page_index,
            page.job_index,
            SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE
        )));
    }
    unique_usize_set(
        &page.dependency_job_indices,
        &format!(
            "schedule job dependency page {} for job {} dependencies",
            page.page_index, page.job_index
        ),
    )?;
    validate_usize_values_strictly_ascending(
        &page.dependency_job_indices,
        &format!(
            "schedule job dependency page {} for job {} dependencies",
            page.page_index, page.job_index
        ),
        |message| library_partition_contract_error(message),
    )?;
    for &dependency_job_index in &page.dependency_job_indices {
        if dependency_job_index >= page.job_index || dependency_job_index >= job_count {
            return Err(library_partition_contract_error(format!(
                "schedule job dependency page {} for job {} has invalid dependency job {}",
                page.page_index, page.job_index, dependency_job_index
            )));
        }
    }
    Ok(())
}
