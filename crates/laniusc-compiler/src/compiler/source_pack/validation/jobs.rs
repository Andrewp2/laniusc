use super::*;

/// Validates compact dependency job ranges against explicit dependency indices.
///
/// Ranges must be non-empty, sorted, non-overlapping, within the dependency
/// bound, and disjoint from explicitly listed dependencies.
pub(in crate::compiler) fn validate_job_dependency_ranges<F>(
    dependency_job_ranges: &[SourcePackJobIndexRange],
    explicit_dependencies: &BTreeSet<usize>,
    context: &str,
    max_dependency_job_index_exclusive: usize,
    make_error: F,
) -> Result<(), CompileError>
where
    F: Fn(String) -> CompileError,
{
    let mut previous_range_end = None;
    for (range_position, range) in dependency_job_ranges.iter().enumerate() {
        if range.job_count == 0 {
            return Err(make_error(format!(
                "{context} dependency job range {range_position} is empty"
            )));
        }
        let Some(end_job_index) = range.end_job_index() else {
            return Err(make_error(format!(
                "{context} dependency job range {range_position} overflows usize"
            )));
        };
        if end_job_index > max_dependency_job_index_exclusive {
            return Err(make_error(format!(
                "{context} dependency job range {}..{} exceeds dependency bound {}",
                range.first_job_index, end_job_index, max_dependency_job_index_exclusive
            )));
        }
        if let Some(previous_range_end) = previous_range_end
            && range.first_job_index < previous_range_end
        {
            return Err(make_error(format!(
                "{context} dependency job ranges must be sorted and non-overlapping; range {}..{} follows previous end {}",
                range.first_job_index, end_job_index, previous_range_end
            )));
        }
        if let Some(duplicate) = explicit_dependencies
            .iter()
            .copied()
            .find(|&dependency_job_index| range.contains(dependency_job_index))
        {
            return Err(make_error(format!(
                "{context} dependency job range {}..{} duplicates explicit dependency {}",
                range.first_job_index, end_job_index, duplicate
            )));
        }
        previous_range_end = Some(end_job_index);
    }
    Ok(())
}

/// Validates compact dependent job ranges against explicit dependent indices.
///
/// Ranges must be non-empty, sorted, non-overlapping, strictly after the owning
/// item, and disjoint from explicitly listed dependents.
pub(in crate::compiler) fn validate_job_dependent_ranges<F>(
    dependent_job_ranges: &[SourcePackJobIndexRange],
    explicit_dependents: &BTreeSet<usize>,
    context: &str,
    min_dependent_job_index_exclusive: usize,
    make_error: F,
) -> Result<(), CompileError>
where
    F: Fn(String) -> CompileError,
{
    let mut previous_range_end = None;
    for (range_position, range) in dependent_job_ranges.iter().enumerate() {
        if range.job_count == 0 {
            return Err(make_error(format!(
                "{context} dependent job range {range_position} is empty"
            )));
        }
        let Some(end_job_index) = range.end_job_index() else {
            return Err(make_error(format!(
                "{context} dependent job range {range_position} overflows usize"
            )));
        };
        if range.first_job_index <= min_dependent_job_index_exclusive {
            return Err(make_error(format!(
                "{context} dependent job range {}..{} is not after item {}",
                range.first_job_index, end_job_index, min_dependent_job_index_exclusive
            )));
        }
        if let Some(previous_range_end) = previous_range_end
            && range.first_job_index < previous_range_end
        {
            return Err(make_error(format!(
                "{context} dependent job ranges must be sorted and non-overlapping; range {}..{} follows previous end {}",
                range.first_job_index, end_job_index, previous_range_end
            )));
        }
        if let Some(duplicate) = explicit_dependents
            .iter()
            .copied()
            .find(|&dependent_job_index| range.contains(dependent_job_index))
        {
            return Err(make_error(format!(
                "{context} dependent job range {}..{} duplicates explicit dependent {}",
                range.first_job_index, end_job_index, duplicate
            )));
        }
        previous_range_end = Some(end_job_index);
    }
    Ok(())
}

/// Validates phase-specific job payload shape.
///
/// Frontend and codegen jobs must have source input; link jobs must not carry
/// source, dependency, or library-owner payload.
pub(in crate::compiler) fn validate_job_shape<F>(
    job: &SourcePackJob,
    context: &str,
    make_error: F,
) -> Result<(), CompileError>
where
    F: Fn(String) -> CompileError,
{
    job.first_source_index
        .checked_add(job.source_file_count)
        .ok_or_else(|| {
            make_error(format!(
                "{context} job {} source range overflows",
                job.job_index
            ))
        })?;
    match job.phase {
        SourcePackJobPhase::LibraryFrontend | SourcePackJobPhase::Codegen => {
            if job.source_file_count == 0 {
                return Err(make_error(format!(
                    "{context} job {} has no source files",
                    job.job_index
                )));
            }
            if job.oversized_source_file && job.source_file_count != 1 {
                return Err(make_error(format!(
                    "{context} job {} marks an oversized source file but spans {} files",
                    job.job_index, job.source_file_count
                )));
            }
            if job.phase == SourcePackJobPhase::LibraryFrontend && job.library_job_index.is_some() {
                return Err(make_error(format!(
                    "{context} frontend job {} cannot reference owning library job {:?}",
                    job.job_index, job.library_job_index
                )));
            }
        }
        SourcePackJobPhase::Link => {
            if job.source_file_count != 0
                || job.source_bytes != 0
                || job.source_lines != 0
                || job.oversized_source_file
                || job.library_job_index.is_some()
                || !job.dependency_job_indices.is_empty()
            {
                return Err(make_error(format!(
                    "{context} link job {} has non-link job payload",
                    job.job_index
                )));
            }
        }
    }
    Ok(())
}
