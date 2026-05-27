use super::*;

pub(in crate::compiler) fn manifest_artifact_entry<'a>(
    manifest: &'a SourcePackArtifactManifest,
    artifact_index: usize,
    label: &str,
) -> Result<&'a SourcePackArtifactManifestEntry, CompileError> {
    let artifact = manifest.get(artifact_index).ok_or_else(|| {
        manifest_contract_error(format!(
            "{label} references missing artifact {artifact_index}"
        ))
    })?;
    if artifact.artifact_index != artifact_index {
        return Err(manifest_contract_error(format!(
            "{label} references artifact {} but entry records artifact_index {}",
            artifact_index, artifact.artifact_index
        )));
    }
    Ok(artifact)
}

pub(in crate::compiler) fn library_interface_artifact_for_job<'a>(
    manifest: &'a SourcePackArtifactManifest,
    producing_job_index: usize,
    label: &str,
) -> Result<&'a SourcePackArtifactManifestEntry, CompileError> {
    if let Some(artifact) = manifest.get(producing_job_index) {
        if artifact.producing_job_index == producing_job_index
            && artifact.kind == SourcePackArtifactKind::LibraryInterface
        {
            return Ok(artifact);
        }
    }

    let mut matches = manifest.artifacts.iter().filter(|artifact| {
        artifact.producing_job_index == producing_job_index
            && artifact.kind == SourcePackArtifactKind::LibraryInterface
    });
    let artifact = matches.next().ok_or_else(|| {
        manifest_contract_error(format!(
            "{label} references missing library-interface artifact from job {producing_job_index}"
        ))
    })?;
    if matches.next().is_some() {
        return Err(manifest_contract_error(format!(
            "{label} references producer job {producing_job_index} with multiple library-interface artifacts"
        )));
    }
    Ok(artifact)
}

pub(in crate::compiler) fn artifact_ref_from_manifest_entry(
    artifact: &SourcePackArtifactManifestEntry,
) -> SourcePackArtifactRef {
    SourcePackArtifactRef {
        artifact_index: artifact.artifact_index,
        key: artifact.key.clone(),
        producing_job_index: artifact.producing_job_index,
        kind: artifact.kind,
    }
}

pub(in crate::compiler) fn insert_interface_job_range_indices(
    manifest: &SourcePackArtifactManifest,
    job_ranges: &[SourcePackJobIndexRange],
    values: &mut BTreeSet<usize>,
    label: &str,
) -> Result<(), CompileError> {
    for range in job_ranges {
        let Some(job_indices) = range.iter() else {
            return Err(manifest_contract_error(format!(
                "{label} contains overflowing job range starting at {} with {} jobs",
                range.first_job_index, range.job_count
            )));
        };
        for producing_job_index in job_indices {
            let artifact =
                library_interface_artifact_for_job(manifest, producing_job_index, label)?;
            if !values.insert(artifact.artifact_index) {
                return Err(manifest_contract_error(format!(
                    "{label} contains duplicate ranged interface artifact {}",
                    artifact.artifact_index
                )));
            }
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_artifact_ref_matches_entry(
    manifest: &SourcePackArtifactManifest,
    artifact_ref: &SourcePackArtifactRef,
    label: &str,
) -> Result<(), CompileError> {
    let artifact = manifest_artifact_entry(manifest, artifact_ref.artifact_index, label)?;
    if artifact_ref.key != artifact.key
        || artifact_ref.producing_job_index != artifact.producing_job_index
        || artifact_ref.kind != artifact.kind
    {
        return Err(manifest_contract_error(format!(
            "{label} artifact ref {} does not match artifact entry: ref(key={:?}, producer={}, kind={:?}) entry(key={:?}, producer={}, kind={:?})",
            artifact_ref.artifact_index,
            artifact_ref.key,
            artifact_ref.producing_job_index,
            artifact_ref.kind,
            artifact.key,
            artifact.producing_job_index,
            artifact.kind
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn artifact_ref_index_set(
    artifact_refs: &[SourcePackArtifactRef],
    label: &str,
) -> Result<BTreeSet<usize>, CompileError> {
    let mut values = BTreeSet::new();
    for artifact_ref in artifact_refs {
        if !values.insert(artifact_ref.artifact_index) {
            return Err(manifest_contract_error(format!(
                "{label} contains duplicate artifact {}",
                artifact_ref.artifact_index
            )));
        }
    }
    Ok(values)
}

pub(in crate::compiler) fn artifact_ref_and_range_index_set(
    artifact_refs: &[SourcePackArtifactRef],
    artifact_ranges: &[SourcePackArtifactIndexRange],
    label: &str,
) -> Result<BTreeSet<usize>, CompileError> {
    let mut values = artifact_ref_index_set(artifact_refs, label)?;
    for value in artifact_index_range_set(artifact_ranges, label)? {
        if !values.insert(value) {
            return Err(manifest_contract_error(format!(
                "{label} contains duplicate artifact {value}"
            )));
        }
    }
    Ok(values)
}

pub(in crate::compiler) fn unique_usize_set(
    values: &[usize],
    label: &str,
) -> Result<BTreeSet<usize>, CompileError> {
    let mut unique_values = BTreeSet::new();
    for &value in values {
        if !unique_values.insert(value) {
            return Err(manifest_contract_error(format!(
                "{label} contains duplicate index {value}"
            )));
        }
    }
    Ok(unique_values)
}

pub(in crate::compiler) fn unique_usize_and_artifact_range_set(
    values: &[usize],
    artifact_ranges: &[SourcePackArtifactIndexRange],
    label: &str,
) -> Result<BTreeSet<usize>, CompileError> {
    let mut unique_values = unique_usize_set(values, label)?;
    for value in artifact_index_range_set(artifact_ranges, label)? {
        if !unique_values.insert(value) {
            return Err(manifest_contract_error(format!(
                "{label} contains duplicate index {value}"
            )));
        }
    }
    Ok(unique_values)
}

pub(in crate::compiler) fn artifact_index_range_set(
    artifact_ranges: &[SourcePackArtifactIndexRange],
    label: &str,
) -> Result<BTreeSet<usize>, CompileError> {
    let mut unique_values = BTreeSet::new();
    for range in artifact_ranges {
        let Some(indices) = range.iter() else {
            return Err(manifest_contract_error(format!(
                "{label} contains overflowing artifact range starting at {} with {} artifacts",
                range.first_artifact_index, range.artifact_count
            )));
        };
        for value in indices {
            if !unique_values.insert(value) {
                return Err(manifest_contract_error(format!(
                    "{label} contains duplicate ranged artifact {value}"
                )));
            }
        }
    }
    Ok(unique_values)
}

pub(in crate::compiler) fn artifact_index_range_count(
    ranges: &[SourcePackArtifactIndexRange],
) -> usize {
    ranges.iter().fold(0usize, |count, range| {
        count.saturating_add(range.artifact_count)
    })
}

pub(in crate::compiler) fn artifact_index_covered_by_ranges(
    artifact_index: usize,
    ranges: &[SourcePackArtifactIndexRange],
) -> bool {
    ranges.iter().any(|range| range.contains(artifact_index))
}

pub(in crate::compiler) fn compact_artifact_index_ranges(
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

pub(in crate::compiler) fn validate_artifact_index_ranges<F>(
    artifact_ranges: &[SourcePackArtifactIndexRange],
    explicit_artifact_indices: &BTreeSet<usize>,
    context: &str,
    make_error: F,
) -> Result<(), CompileError>
where
    F: Fn(String) -> CompileError,
{
    let mut ranges = Vec::<(usize, usize)>::new();
    for (range_position, range) in artifact_ranges.iter().enumerate() {
        if range.artifact_count == 0 {
            return Err(make_error(format!(
                "{context} range {range_position} is empty"
            )));
        }
        let Some(end_artifact_index) = range.end_artifact_index() else {
            return Err(make_error(format!(
                "{context} range {range_position} overflows usize"
            )));
        };
        if let Some(duplicate) = explicit_artifact_indices
            .iter()
            .copied()
            .find(|&artifact_index| range.contains(artifact_index))
        {
            return Err(make_error(format!(
                "{context} range {}..{} duplicates explicit artifact {}",
                range.first_artifact_index, end_artifact_index, duplicate
            )));
        }
        if let Some(&(overlap_start, overlap_end)) = ranges
            .iter()
            .find(|&&(start, end)| range.first_artifact_index < end && start < end_artifact_index)
        {
            return Err(make_error(format!(
                "{context} range {}..{} overlaps range {}..{}",
                range.first_artifact_index, end_artifact_index, overlap_start, overlap_end
            )));
        }
        ranges.push((range.first_artifact_index, end_artifact_index));
    }
    Ok(())
}

pub(in crate::compiler) fn unique_u32_set(
    values: &[u32],
    label: &str,
) -> Result<BTreeSet<u32>, CompileError> {
    let mut unique_values = BTreeSet::new();
    for &value in values {
        if !unique_values.insert(value) {
            return Err(manifest_contract_error(format!(
                "{label} contains duplicate id {value}"
            )));
        }
    }
    Ok(unique_values)
}

pub(in crate::compiler) fn validate_manifest_artifact_key(
    target: SourcePackArtifactTarget,
    key: &str,
    label: &str,
) -> Result<(), CompileError> {
    artifact_path(Path::new(""), key).map_err(|err| {
        manifest_contract_error(format!("{label} has invalid key {key:?}: {err}"))
    })?;
    if let Some(prefix) = target.key_prefix() {
        let target_prefix = format!("{prefix}/");
        if !key.starts_with(&target_prefix) {
            return Err(manifest_contract_error(format!(
                "{label} key {key:?} does not start with target prefix {target_prefix:?}"
            )));
        }
    }
    Ok(())
}
