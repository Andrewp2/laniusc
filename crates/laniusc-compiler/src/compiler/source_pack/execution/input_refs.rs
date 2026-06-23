use super::*;

/// Returns inline interface input refs for a shard job.
///
/// Inline execution rejects paged or ranged input forms so callers do not
/// silently ignore dependency interfaces that require the paged execution path.
pub(in crate::compiler) fn execution_shard_job_input_interface_refs<S>(
    _execution_shard: &SourcePackBuildArtifactExecutionShard,
    _store: &S,
    _target: SourcePackArtifactTarget,
    job_manifest: &SourcePackJobArtifactManifest,
) -> Result<Vec<SourcePackArtifactRef>, CompileError>
where
    S: ExecutionShardLoader,
{
    if job_manifest.input_interface_page_count != 0
        || !job_manifest.input_interface_ranges.is_empty()
        || !job_manifest.input_interface_artifact_ranges.is_empty()
    {
        return Err(artifact_shard_contract_error(format!(
            "inline source-pack execution for job {} requires bounded inline interface inputs; paged or ranged interface inputs must use paged execution",
            job_manifest.job_index
        )));
    }
    let input_interfaces = job_manifest.input_interfaces.clone();
    if input_interfaces.len() != job_manifest.input_interface_count {
        return Err(artifact_shard_contract_error(format!(
            "job artifact manifest {} records {} inline interface inputs but expected {}",
            job_manifest.job_index,
            input_interfaces.len(),
            job_manifest.input_interface_count
        )));
    }
    Ok(input_interfaces)
}

/// Finds the interface artifact ref produced by a specific job.
///
/// The lookup checks inline refs, paged input pages, job-index ranges, and
/// artifact-index ranges, loading artifact-ref pages for ranged forms.
pub(in crate::compiler) fn execution_shard_job_input_interface_ref<S>(
    store: &S,
    target: SourcePackArtifactTarget,
    job_manifest: &SourcePackJobArtifactManifest,
    producing_job_index: usize,
) -> Result<SourcePackArtifactRef, CompileError>
where
    S: ExecutionShardLoader,
{
    if let Some(artifact) = job_manifest
        .input_interfaces
        .iter()
        .find(|artifact| artifact.producing_job_index == producing_job_index)
    {
        return Ok(artifact.clone());
    }

    for page_index in 0..job_manifest.input_interface_page_count {
        let page = store.load_job_artifact_input_interface_page(
            target,
            job_manifest.job_index,
            page_index,
        )?;
        if let Some(artifact) = page
            .input_interfaces
            .into_iter()
            .find(|artifact| artifact.producing_job_index == producing_job_index)
        {
            return Ok(artifact);
        }
    }
    if job_manifest
        .input_interface_ranges
        .iter()
        .any(|range| range.contains(producing_job_index))
    {
        let artifact_ref_index = store.load_build_artifact_ref_index(target)?;
        let page = store.load_build_artifact_ref_page(
            target,
            producing_job_index,
            artifact_ref_index.artifact_count,
        )?;
        if page.artifact_ref.kind != SourcePackArtifactKind::LibraryInterface {
            return Err(artifact_shard_contract_error(format!(
                "job artifact manifest {} expected interface artifact from producer {} but found {:?}",
                job_manifest.job_index, producing_job_index, page.artifact_ref.kind
            )));
        }
        return Ok(page.artifact_ref);
    }
    if job_manifest
        .input_interface_artifact_ranges
        .iter()
        .any(|range| range.contains(producing_job_index))
    {
        let artifact_ref_index = store.load_build_artifact_ref_index(target)?;
        let page = store.load_build_artifact_ref_page(
            target,
            producing_job_index,
            artifact_ref_index.artifact_count,
        )?;
        if page.artifact_ref.kind != SourcePackArtifactKind::LibraryInterface {
            return Err(artifact_shard_contract_error(format!(
                "job artifact manifest {} expected interface artifact from ranged producer {} but found {:?}",
                job_manifest.job_index, producing_job_index, page.artifact_ref.kind
            )));
        }
        return Ok(page.artifact_ref);
    }
    Err(artifact_shard_contract_error(format!(
        "source-pack job {} missing paged interface artifact from producer {}",
        job_manifest.job_index, producing_job_index
    )))
}

/// Streams interface dependency artifacts for a shard job in bounded batches.
///
/// Inputs may be inline, paged, or compact ranges. `excluded_artifact_index`
/// lets codegen skip its owning library interface while still streaming ordinary
/// interface dependencies.
pub(in crate::compiler) fn for_each_execution_shard_job_input_interface_batch<S, F>(
    store: &mut S,
    target: SourcePackArtifactTarget,
    job_manifest: &SourcePackJobArtifactManifest,
    excluded_artifact_index: Option<usize>,
    mut visit: F,
) -> Result<usize, CompileError>
where
    S: ArtifactStore + ExecutionShardLoader,
    F: FnMut(&[S::LibraryInterfaceArtifact]) -> Result<(), CompileError>,
{
    let mut loaded_input_count = 0usize;
    let mut seen_input_count = 0usize;
    if job_manifest.input_interface_page_count == 0 {
        for chunk in job_manifest
            .input_interfaces
            .chunks(SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE)
        {
            seen_input_count = seen_input_count.saturating_add(chunk.len());
            let interfaces = load_library_interface_artifact_batch_excluding(
                store,
                chunk,
                excluded_artifact_index,
            )?;
            loaded_input_count = loaded_input_count.saturating_add(interfaces.len());
            if interfaces.is_empty() {
                continue;
            }
            visit(&interfaces)?;
        }
    } else if !job_manifest.input_interfaces.is_empty() {
        return Err(artifact_shard_contract_error(format!(
            "job artifact manifest {} mixes inline and paged interface inputs",
            job_manifest.job_index
        )));
    } else {
        for page_index in 0..job_manifest.input_interface_page_count {
            let page = store.load_job_artifact_input_interface_page(
                target,
                job_manifest.job_index,
                page_index,
            )?;
            if page.first_input_position != seen_input_count {
                return Err(artifact_shard_contract_error(format!(
                    "job artifact manifest {} input page {} starts at {} but streamed {} refs",
                    job_manifest.job_index, page_index, page.first_input_position, seen_input_count
                )));
            }
            seen_input_count = seen_input_count.saturating_add(page.input_count);
            let interfaces = load_library_interface_artifact_batch_excluding(
                store,
                &page.input_interfaces,
                excluded_artifact_index,
            )?;
            loaded_input_count = loaded_input_count.saturating_add(interfaces.len());
            if interfaces.is_empty() {
                continue;
            }
            visit(&interfaces)?;
        }
    }
    if !job_manifest.input_interface_ranges.is_empty() {
        let artifact_ref_index = store.load_build_artifact_ref_index(target)?;
        let mut artifact_refs =
            Vec::with_capacity(SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE);
        for range in &job_manifest.input_interface_ranges {
            let Some(indices) = range.iter() else {
                return Err(artifact_shard_contract_error(format!(
                    "job artifact manifest {} interface range starting at {} overflows",
                    job_manifest.job_index, range.first_job_index
                )));
            };
            for job_index in indices {
                let page = store.load_build_artifact_ref_page(
                    target,
                    job_index,
                    artifact_ref_index.artifact_count,
                )?;
                if page.artifact_ref.kind != SourcePackArtifactKind::LibraryInterface {
                    return Err(artifact_shard_contract_error(format!(
                        "job artifact manifest {} interface range references artifact {} with kind {:?}",
                        job_manifest.job_index, job_index, page.artifact_ref.kind
                    )));
                }
                artifact_refs.push(page.artifact_ref);
                seen_input_count = seen_input_count.saturating_add(1);
                if artifact_refs.len() == SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE
                {
                    let interfaces = load_library_interface_artifact_batch_excluding(
                        store,
                        &artifact_refs,
                        excluded_artifact_index,
                    )?;
                    loaded_input_count = loaded_input_count.saturating_add(interfaces.len());
                    if !interfaces.is_empty() {
                        visit(&interfaces)?;
                    }
                    artifact_refs.clear();
                }
            }
        }
        if !artifact_refs.is_empty() {
            let interfaces = load_library_interface_artifact_batch_excluding(
                store,
                &artifact_refs,
                excluded_artifact_index,
            )?;
            loaded_input_count = loaded_input_count.saturating_add(interfaces.len());
            if !interfaces.is_empty() {
                visit(&interfaces)?;
            }
        }
    }
    if !job_manifest.input_interface_artifact_ranges.is_empty() {
        let artifact_ref_index = store.load_build_artifact_ref_index(target)?;
        let mut artifact_refs =
            Vec::with_capacity(SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE);
        for range in &job_manifest.input_interface_artifact_ranges {
            let Some(indices) = range.iter() else {
                return Err(artifact_shard_contract_error(format!(
                    "job artifact manifest {} interface artifact range starting at {} overflows",
                    job_manifest.job_index, range.first_artifact_index
                )));
            };
            for artifact_index in indices {
                let page = store.load_build_artifact_ref_page(
                    target,
                    artifact_index,
                    artifact_ref_index.artifact_count,
                )?;
                if page.artifact_ref.kind != SourcePackArtifactKind::LibraryInterface {
                    return Err(artifact_shard_contract_error(format!(
                        "job artifact manifest {} interface artifact range references artifact {} with kind {:?}",
                        job_manifest.job_index, artifact_index, page.artifact_ref.kind
                    )));
                }
                artifact_refs.push(page.artifact_ref);
                seen_input_count = seen_input_count.saturating_add(1);
                if artifact_refs.len() == SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE
                {
                    let interfaces = load_library_interface_artifact_batch_excluding(
                        store,
                        &artifact_refs,
                        excluded_artifact_index,
                    )?;
                    loaded_input_count = loaded_input_count.saturating_add(interfaces.len());
                    if !interfaces.is_empty() {
                        visit(&interfaces)?;
                    }
                    artifact_refs.clear();
                }
            }
        }
        if !artifact_refs.is_empty() {
            let interfaces = load_library_interface_artifact_batch_excluding(
                store,
                &artifact_refs,
                excluded_artifact_index,
            )?;
            loaded_input_count = loaded_input_count.saturating_add(interfaces.len());
            if !interfaces.is_empty() {
                visit(&interfaces)?;
            }
        }
    }
    if seen_input_count != job_manifest.input_interface_count {
        return Err(artifact_shard_contract_error(format!(
            "job artifact manifest {} streamed {} interface refs but expected {}",
            job_manifest.job_index, seen_input_count, job_manifest.input_interface_count
        )));
    }
    Ok(loaded_input_count)
}
