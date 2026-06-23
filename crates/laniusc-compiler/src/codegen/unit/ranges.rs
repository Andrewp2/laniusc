use super::*;

/// Returns whether `outer` fully covers `inner`.
pub(in crate::codegen::unit) fn range_contains_range(
    outer: Range<usize>,
    inner: Range<usize>,
) -> bool {
    outer.start <= inner.start && inner.end <= outer.end
}

/// Returns the effective artifact count from explicit indices and compact ranges.
pub(in crate::codegen::unit) fn artifact_index_count(
    recorded_count: usize,
    explicit_indices: &[usize],
    ranges: &[SourcePackArtifactIndexRange],
) -> usize {
    recorded_count.max(
        explicit_indices
            .len()
            .saturating_add(artifact_index_range_count(ranges)),
    )
}

/// Counts artifact indices represented by compact artifact ranges.
pub(in crate::codegen::unit) fn artifact_index_range_count(
    ranges: &[SourcePackArtifactIndexRange],
) -> usize {
    ranges.iter().fold(0usize, |count, range| {
        count.saturating_add(range.artifact_count)
    })
}

/// Returns whether an artifact index is covered by any compact artifact range.
pub(in crate::codegen::unit) fn artifact_index_covered_by_ranges(
    artifact_index: usize,
    ranges: &[SourcePackArtifactIndexRange],
) -> bool {
    ranges.iter().any(|range| range.contains(artifact_index))
}

/// Sorts and merges overlapping or adjacent artifact index ranges.
pub(in crate::codegen::unit) fn compact_artifact_index_ranges(
    ranges: Vec<SourcePackArtifactIndexRange>,
) -> Vec<SourcePackArtifactIndexRange> {
    let mut ranges = ranges
        .into_iter()
        .filter(|range| range.artifact_count != 0)
        .collect::<Vec<_>>();
    ranges.sort_by_key(|range| range.first_artifact_index);
    let mut compact_ranges = Vec::<SourcePackArtifactIndexRange>::with_capacity(ranges.len());
    for range in ranges {
        let Some(range_end) = range.end_artifact_index() else {
            compact_ranges.push(range);
            continue;
        };
        if let Some(last) = compact_ranges.last_mut() {
            if let Some(last_end) = last.end_artifact_index() {
                if range.first_artifact_index <= last_end {
                    let compact_end = last_end.max(range_end);
                    last.artifact_count = compact_end - last.first_artifact_index;
                    continue;
                }
            }
        }
        compact_ranges.push(range);
    }
    compact_ranges
}

/// Counts job indices represented by compact job dependency ranges.
pub(in crate::codegen::unit) fn job_index_range_dependency_count(
    ranges: &[SourcePackJobIndexRange],
) -> usize {
    ranges
        .iter()
        .fold(0usize, |count, range| count.saturating_add(range.job_count))
}

/// Sorts and merges overlapping or adjacent job dependency ranges.
pub(in crate::codegen::unit) fn compact_job_index_ranges(
    ranges: Vec<SourcePackJobIndexRange>,
) -> Vec<SourcePackJobIndexRange> {
    let mut ranges = ranges
        .into_iter()
        .filter(|range| !range.is_empty())
        .collect::<Vec<_>>();
    ranges.sort_by_key(|range| range.first_job_index);
    let mut compact_ranges = Vec::<SourcePackJobIndexRange>::with_capacity(ranges.len());
    for range in ranges {
        let Some(range_end) = range.end_job_index() else {
            compact_ranges.push(range);
            continue;
        };
        if let Some(last) = compact_ranges.last_mut() {
            if let Some(last_end) = last.end_job_index() {
                if range.first_job_index <= last_end {
                    let compact_end = last_end.max(range_end);
                    last.job_count = compact_end - last.first_job_index;
                    continue;
                }
            }
        }
        compact_ranges.push(range);
    }
    compact_ranges
}

/// Returns whether completed job ranges fully cover one dependency range.
pub(in crate::codegen::unit) fn job_range_covered_by_ranges(
    dependency_range: &SourcePackJobIndexRange,
    completed_ranges: &[SourcePackJobIndexRange],
) -> bool {
    if dependency_range.is_empty() {
        return true;
    }

    let Some(required_end) = dependency_range.end_job_index() else {
        return false;
    };
    let mut covered_until = dependency_range.first_job_index;
    while covered_until < required_end {
        let mut next_covered_until = covered_until;
        for completed_range in completed_ranges {
            let Some(completed_end) = completed_range.end_job_index() else {
                continue;
            };
            if completed_range.first_job_index <= covered_until && covered_until < completed_end {
                next_covered_until = next_covered_until.max(completed_end.min(required_end));
            }
        }
        if next_covered_until == covered_until {
            return false;
        }
        covered_until = next_covered_until;
    }

    true
}

/// Appends one completed job index, extending the last range when contiguous.
pub(in crate::codegen::unit) fn push_completed_job_range(
    completed_ranges: &mut Vec<SourcePackJobIndexRange>,
    job_index: usize,
) {
    if let Some(last) = completed_ranges.last_mut() {
        if last.end_job_index() == Some(job_index) {
            last.job_count = last.job_count.saturating_add(1);
            return;
        }
    }
    completed_ranges.push(SourcePackJobIndexRange {
        first_job_index: job_index,
        job_count: 1,
    });
}

/// Returns whether all explicit and ranged dependencies for a job are complete.
pub(in crate::codegen::unit) fn job_dependencies_satisfied(
    job: &SourcePackJob,
    dependency_job_ranges: &[SourcePackJobIndexRange],
    job_position_by_index: &[Option<usize>],
    emitted_by_position: &[bool],
    completed_job_ranges: &[SourcePackJobIndexRange],
    emitted_codegen_count: usize,
    codegen_job_count: usize,
) -> bool {
    let has_explicit_dependencies = !job.dependency_job_indices.is_empty();
    let has_ranged_dependencies = !dependency_job_ranges.is_empty();
    if job.phase == SourcePackJobPhase::Link
        && !has_explicit_dependencies
        && !has_ranged_dependencies
    {
        return emitted_codegen_count == codegen_job_count;
    }

    job.dependency_job_indices
        .iter()
        .all(|&dependency_job_index| {
            job_position_by_index
                .get(dependency_job_index)
                .and_then(|position| *position)
                .and_then(|position| emitted_by_position.get(position).copied())
                .unwrap_or(false)
        })
        && dependency_job_ranges
            .iter()
            .all(|range| job_range_covered_by_ranges(range, completed_job_ranges))
}

/// Converts an optional first/count artifact pair into a compact range list.
pub(in crate::codegen::unit) fn artifact_index_ranges_from_first_count(
    first_artifact_index: Option<usize>,
    artifact_count: usize,
) -> Vec<SourcePackArtifactIndexRange> {
    match (first_artifact_index, artifact_count) {
        (Some(first_artifact_index), artifact_count) if artifact_count != 0 => {
            vec![SourcePackArtifactIndexRange {
                first_artifact_index,
                artifact_count,
            }]
        }
        _ => Vec::new(),
    }
}

/// Visits explicit artifact indices and expanded artifact ranges in order.
pub(in crate::codegen::unit) fn try_for_each_artifact_index<F, E>(
    explicit_indices: &[usize],
    ranges: &[SourcePackArtifactIndexRange],
    mut visit: F,
) -> Result<usize, E>
where
    F: FnMut(usize) -> Result<(), E>,
{
    let mut count = 0usize;
    for &artifact_index in explicit_indices {
        visit(artifact_index)?;
        count = count.saturating_add(1);
    }
    for range in ranges {
        if let Some(indices) = range.iter() {
            for artifact_index in indices {
                visit(artifact_index)?;
                count = count.saturating_add(1);
            }
        }
    }
    Ok(count)
}

/// Pushes a value only when it is not already present.
pub(in crate::codegen::unit) fn push_unique(values: &mut Vec<usize>, value: usize) {
    if !values.contains(&value) {
        values.push(value);
    }
}

/// Sorts dependency indices into the canonical persisted order.
pub(in crate::codegen::unit) fn normalize_dependency_indices(values: &mut Vec<usize>) {
    values.sort_unstable();
    values.dedup();
}

/// Appends dependency batch indices as compact contiguous ranges.
pub(in crate::codegen::unit) fn push_dependency_batch_indices_as_ranges<I>(
    dependency_batch_ranges: &mut Vec<SourcePackJobBatchDependencyRange>,
    dependency_batch_indices: I,
) where
    I: IntoIterator<Item = usize>,
{
    for dependency_batch_index in dependency_batch_indices {
        if let Some(last) = dependency_batch_ranges.last_mut() {
            if last.end_batch_index() == Some(dependency_batch_index) {
                last.batch_count = last.batch_count.saturating_add(1);
                continue;
            }
        }
        dependency_batch_ranges.push(SourcePackJobBatchDependencyRange {
            first_batch_index: dependency_batch_index,
            batch_count: 1,
        });
    }
}

/// Appends dependency batch ranges while removing one excluded batch.
pub(in crate::codegen::unit) fn push_dependency_batch_ranges_excluding_batch(
    dependency_batch_ranges: &mut Vec<SourcePackJobBatchDependencyRange>,
    ranges: &[SourcePackJobBatchDependencyRange],
    excluded_batch_index: usize,
) {
    for range in ranges {
        let Some(range_end) = range.end_batch_index() else {
            continue;
        };
        if !range.contains(excluded_batch_index) {
            dependency_batch_ranges.push(range.clone());
            continue;
        }
        if range.first_batch_index < excluded_batch_index {
            dependency_batch_ranges.push(SourcePackJobBatchDependencyRange {
                first_batch_index: range.first_batch_index,
                batch_count: excluded_batch_index - range.first_batch_index,
            });
        }
        let after_excluded = excluded_batch_index.saturating_add(1);
        if after_excluded < range_end {
            dependency_batch_ranges.push(SourcePackJobBatchDependencyRange {
                first_batch_index: after_excluded,
                batch_count: range_end - after_excluded,
            });
        }
    }
}

/// Appends one dependency batch range while removing multiple excluded batches.
pub(in crate::codegen::unit) fn push_dependency_batch_range_excluding_batches(
    dependency_batch_ranges: &mut Vec<SourcePackJobBatchDependencyRange>,
    first_batch_index: usize,
    batch_count: usize,
    excluded_batch_indices: &BTreeSet<usize>,
) {
    if batch_count == 0 {
        return;
    }
    let Some(end_batch_index) = first_batch_index.checked_add(batch_count) else {
        return;
    };
    let mut range_start = first_batch_index;
    for &excluded_batch_index in excluded_batch_indices.range(first_batch_index..end_batch_index) {
        if range_start < excluded_batch_index {
            dependency_batch_ranges.push(SourcePackJobBatchDependencyRange {
                first_batch_index: range_start,
                batch_count: excluded_batch_index - range_start,
            });
        }
        range_start = excluded_batch_index.saturating_add(1);
    }
    if range_start < end_batch_index {
        dependency_batch_ranges.push(SourcePackJobBatchDependencyRange {
            first_batch_index: range_start,
            batch_count: end_batch_index - range_start,
        });
    }
}

/// Maps a dependency job range to dependency batch ranges for one current batch.
pub(in crate::codegen::unit) fn push_dependency_batch_range_for_job_range(
    dependency_batch_ranges: &mut Vec<SourcePackJobBatchDependencyRange>,
    dependency_batch_indices: &BTreeSet<usize>,
    batch_index_by_job_index: &[Option<usize>],
    dependency_job_range: &SourcePackJobIndexRange,
    current_batch_index: usize,
) -> Result<(), SourcePackScheduleError> {
    if dependency_job_range.job_count == 0 {
        return Ok(());
    }
    let Some(end_job_index) = dependency_job_range.end_job_index() else {
        return Err(SourcePackScheduleError {
            unscheduled_job_indices: vec![dependency_job_range.first_job_index],
        });
    };
    let first_dependency_batch_index = batch_index_by_job_index
        .get(dependency_job_range.first_job_index)
        .and_then(|batch_index| *batch_index)
        .ok_or_else(|| SourcePackScheduleError {
            unscheduled_job_indices: vec![dependency_job_range.first_job_index],
        })?;
    let last_dependency_job_index = end_job_index - 1;
    let last_dependency_batch_index = batch_index_by_job_index
        .get(last_dependency_job_index)
        .and_then(|batch_index| *batch_index)
        .ok_or_else(|| SourcePackScheduleError {
            unscheduled_job_indices: vec![last_dependency_job_index],
        })?;
    let first_batch_index = first_dependency_batch_index.min(last_dependency_batch_index);
    let last_batch_index = first_dependency_batch_index.max(last_dependency_batch_index);
    let batch_count = last_batch_index
        .checked_sub(first_batch_index)
        .and_then(|count| count.checked_add(1))
        .ok_or_else(|| SourcePackScheduleError {
            unscheduled_job_indices: vec![dependency_job_range.first_job_index],
        })?;
    let mut excluded_batch_indices = dependency_batch_indices.clone();
    excluded_batch_indices.insert(current_batch_index);
    push_dependency_batch_range_excluding_batches(
        dependency_batch_ranges,
        first_batch_index,
        batch_count,
        &excluded_batch_indices,
    );
    Ok(())
}

/// Returns whether a batch index is covered by any dependency batch range.
pub(in crate::codegen::unit) fn job_batch_index_covered_by_ranges(
    batch_index: usize,
    ranges: &[SourcePackJobBatchDependencyRange],
) -> bool {
    ranges.iter().any(|range| range.contains(batch_index))
}

/// Returns whether completed batch ranges fully cover one dependency batch range.
pub(in crate::codegen::unit) fn job_batch_range_covered_by_ranges(
    dependency_range: &SourcePackJobBatchDependencyRange,
    completed_ranges: &[SourcePackJobBatchDependencyRange],
) -> bool {
    if dependency_range.is_empty() {
        return true;
    }

    let Some(required_end) = dependency_range.end_batch_index() else {
        return false;
    };
    let mut covered_until = dependency_range.first_batch_index;
    while covered_until < required_end {
        let mut next_covered_until = covered_until;
        for completed_range in completed_ranges {
            let Some(completed_end) = completed_range.end_batch_index() else {
                continue;
            };
            if completed_range.first_batch_index <= covered_until && covered_until < completed_end {
                next_covered_until = next_covered_until.max(completed_end.min(required_end));
            }
        }
        if next_covered_until == covered_until {
            return false;
        }
        covered_until = next_covered_until;
    }

    true
}
