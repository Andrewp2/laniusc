use super::*;

pub(in crate::compiler) fn execution_shard_job_batch(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    batch_index: usize,
) -> Result<&SourcePackJobBatch, CompileError> {
    execution_shard
        .job_batches
        .iter()
        .find(|batch| batch.batch_index == batch_index)
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack execution shard {} references missing job batch {batch_index}",
                execution_shard.shard.shard_index
            ))
        })
}

pub(in crate::compiler) fn execution_shard_batch_dependency(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    batch_index: usize,
) -> Result<&SourcePackJobBatchDependency, CompileError> {
    execution_shard
        .batch_dependencies
        .iter()
        .find(|batch| batch.batch_index == batch_index)
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack execution shard {} references missing batch dependency {batch_index}",
                execution_shard.shard.shard_index
            ))
        })
}

pub(in crate::compiler) fn execution_shard_job(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    job_index: usize,
) -> Result<&SourcePackJob, CompileError> {
    execution_shard
        .jobs
        .iter()
        .find(|job| job.job_index == job_index)
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack execution shard {} references missing job {job_index}",
                execution_shard.shard.shard_index
            ))
        })
}

pub(in crate::compiler) fn execution_shard_job_artifact(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    job_index: usize,
) -> Result<&SourcePackJobArtifactManifest, CompileError> {
    execution_shard
        .job_artifacts
        .iter()
        .find(|job| job.job_index == job_index)
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack execution shard {} references missing job artifact manifest {job_index}",
                execution_shard.shard.shard_index
            ))
        })
}

pub(in crate::compiler) fn execution_shard_source_files_for_job<S>(
    store: &S,
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    job: &SourcePackJob,
) -> Result<Vec<ExplicitSourcePathFile>, CompileError>
where
    S: ExecutionShardLoader,
{
    if execution_shard.source_files.is_empty() {
        return store.load_source_files_for_range(
            execution_shard.target,
            job.first_source_index,
            job.source_file_count,
        );
    }
    let mut files = Vec::with_capacity(job.source_file_count);
    for source_index in
        job.first_source_index..job.first_source_index.saturating_add(job.source_file_count)
    {
        let source_file = execution_shard
            .source_files
            .iter()
            .find(|source_file| source_file.source_index == source_index)
            .map(|source_file| source_file.file.clone())
            .ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack execution shard {} missing source file {} for job {}",
                    execution_shard.shard.shard_index, source_index, job.job_index
                ))
            })?;
        files.push(source_file);
    }
    validate_explicit_source_path_files_metadata("source-pack job", &files)?;
    Ok(files)
}

pub(in crate::compiler) fn for_each_execution_shard_artifact_ref_for_indices<F>(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    artifact_indices: &[usize],
    mut visit: F,
) -> Result<usize, CompileError>
where
    F: FnMut(&SourcePackArtifactRef) -> Result<(), CompileError>,
{
    let mut artifact_count = 0usize;
    for &artifact_index in artifact_indices {
        visit(execution_shard_artifact_ref_for_index(
            execution_shard,
            artifact_index,
        )?)?;
        artifact_count += 1;
    }
    Ok(artifact_count)
}

pub(in crate::compiler) fn execution_shard_artifact_ref_for_index(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    artifact_index: usize,
) -> Result<&SourcePackArtifactRef, CompileError> {
    execution_shard
        .artifact_refs
        .iter()
        .find(|artifact| artifact.artifact_index == artifact_index)
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack execution shard {} missing artifact ref {}",
                execution_shard.shard.shard_index, artifact_index
            ))
        })
}

pub(in crate::compiler) fn load_interface_artifacts_from_shards<S>(
    store: &mut S,
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    artifact_indices: &[usize],
) -> Result<Vec<S::LibraryInterfaceArtifact>, CompileError>
where
    S: ArtifactStore,
{
    let mut artifacts = Vec::new();
    for_each_execution_shard_artifact_ref_for_indices(
        execution_shard,
        artifact_indices,
        |artifact| {
            artifacts.push(store.load_library_interface(artifact)?);
            Ok(())
        },
    )?;
    Ok(artifacts)
}

pub(in crate::compiler) fn load_codegen_objects_from_shard<S>(
    store: &mut S,
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    artifact_indices: &[usize],
) -> Result<Vec<S::CodegenObjectArtifact>, CompileError>
where
    S: ArtifactStore,
{
    let mut artifacts = Vec::new();
    for_each_execution_shard_artifact_ref_for_indices(
        execution_shard,
        artifact_indices,
        |artifact| {
            artifacts.push(store.load_codegen_object(artifact)?);
            Ok(())
        },
    )?;
    Ok(artifacts)
}

pub(in crate::compiler) fn artifact_manifest_batch(
    manifest: &SourcePackBuildArtifactManifest,
    batch_index: usize,
) -> Result<&SourcePackJobBatch, CompileError> {
    if let Some(batch) = manifest.job_batches.batches.get(batch_index) {
        if batch.batch_index == batch_index {
            return Ok(batch);
        }
    }
    manifest
        .job_batches
        .batches
        .iter()
        .find(|batch| batch.batch_index == batch_index)
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack artifact manifest references missing job batch {batch_index}"
            ))
        })
}

#[cfg(test)]

pub(in crate::compiler) fn job_batch_dependency(
    plan: &crate::codegen::unit::SourcePackJobBatchDependencyPlan,
    batch_index: usize,
) -> Result<&SourcePackJobBatchDependency, CompileError> {
    if let Some(batch) = plan.batches.get(batch_index) {
        if batch.batch_index == batch_index {
            return Ok(batch);
        }
    }
    plan.batches
        .iter()
        .find(|batch| batch.batch_index == batch_index)
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack artifact manifest references missing batch dependency {batch_index}"
            ))
        })
}

#[cfg(test)]

pub(in crate::compiler) fn link_interface_batch(
    plan: &crate::codegen::unit::SourcePackLinkInterfaceBatchPlan,
    batch_index: usize,
) -> Result<&SourcePackLinkInterfaceBatch, CompileError> {
    if let Some(batch) = plan.batches.get(batch_index) {
        if batch.batch_index == batch_index {
            return Ok(batch);
        }
    }
    plan.batches
        .iter()
        .find(|batch| batch.batch_index == batch_index)
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack artifact manifest references missing link interface batch {batch_index}"
            ))
        })
}

#[cfg(test)]

pub(in crate::compiler) fn link_object_batch(
    plan: &crate::codegen::unit::SourcePackLinkObjectBatchPlan,
    batch_index: usize,
) -> Result<&SourcePackLinkObjectBatch, CompileError> {
    if let Some(batch) = plan.batches.get(batch_index) {
        if batch.batch_index == batch_index {
            return Ok(batch);
        }
    }
    plan.batches
        .iter()
        .find(|batch| batch.batch_index == batch_index)
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack artifact manifest references missing link object batch {batch_index}"
            ))
        })
}

pub(in crate::compiler) fn path_manifest_source_files_for_job<'a>(
    source_pack: &'a ExplicitSourcePackPathManifest,
    job: &SourcePackJob,
) -> Result<&'a [ExplicitSourcePathFile], CompileError> {
    let start = job.first_source_index;
    let end = start.saturating_add(job.source_file_count);
    let source_files = source_pack.files.get(start..end).ok_or_else(|| {
        CompileError::GpuFrontend(format!(
            "source-pack job {} source range {}..{} exceeds manifest source file count {}",
            job.job_index,
            start,
            end,
            source_pack.files.len()
        ))
    })?;
    validate_explicit_source_path_files_metadata("source-pack job", source_files)?;
    Ok(source_files)
}

pub(in crate::compiler) fn job_artifact_manifest(
    manifest: &SourcePackJobArtifactManifestPlan,
    job_index: usize,
) -> Result<&SourcePackJobArtifactManifest, CompileError> {
    if let Some(job) = manifest.jobs.get(job_index) {
        if job.job_index == job_index {
            return Ok(job);
        }
    }
    manifest
        .jobs
        .iter()
        .find(|job| job.job_index == job_index)
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack artifact manifest references missing job {job_index}"
            ))
        })
}

pub(in crate::compiler) fn manifest_job_input_interface_refs(
    manifest: &SourcePackBuildArtifactManifest,
    job_manifest: &SourcePackJobArtifactManifest,
) -> Result<Vec<SourcePackArtifactRef>, CompileError> {
    let mut input_interfaces = job_manifest.input_interfaces.clone();
    for range in &job_manifest.input_interface_ranges {
        let Some(dependency_job_indices) = range.iter() else {
            return Err(manifest_contract_error(format!(
                "job {} input interface job range starting at {} overflows usize",
                job_manifest.job_index, range.first_job_index
            )));
        };
        for dependency_job_index in dependency_job_indices {
            let artifact = library_interface_artifact_for_job(
                &manifest.artifacts,
                dependency_job_index,
                &format!("job {} input interface job range", job_manifest.job_index),
            )?;
            input_interfaces.push(artifact_ref_from_manifest_entry(artifact));
        }
    }
    for artifact_index in artifact_index_range_set(
        &job_manifest.input_interface_artifact_ranges,
        &format!(
            "job {} input interface artifact ranges",
            job_manifest.job_index
        ),
    )? {
        let artifact = manifest_artifact_entry(
            &manifest.artifacts,
            artifact_index,
            &format!(
                "job {} input interface artifact range",
                job_manifest.job_index
            ),
        )?;
        if artifact.kind != SourcePackArtifactKind::LibraryInterface {
            return Err(manifest_contract_error(format!(
                "job {} input interface artifact range references artifact {} with kind {:?}",
                job_manifest.job_index, artifact.artifact_index, artifact.kind
            )));
        }
        input_interfaces.push(SourcePackArtifactRef {
            artifact_index: artifact.artifact_index,
            key: artifact.key.clone(),
            producing_job_index: artifact.producing_job_index,
            kind: artifact.kind,
        });
    }
    if input_interfaces.len() != job_manifest.input_interface_count {
        return Err(manifest_contract_error(format!(
            "job {} has {} input interface refs but records {}",
            job_manifest.job_index,
            input_interfaces.len(),
            job_manifest.input_interface_count
        )));
    }
    Ok(input_interfaces)
}

pub(in crate::compiler) fn single_output_artifact_ref(
    job_manifest: &SourcePackJobArtifactManifest,
    kind: SourcePackArtifactKind,
) -> Result<&SourcePackArtifactRef, CompileError> {
    let mut outputs = job_manifest
        .outputs
        .iter()
        .filter(|artifact| artifact.kind == kind);
    let output = outputs.next().ok_or_else(|| {
        CompileError::GpuFrontend(format!(
            "source-pack job {} has no {:?} output artifact",
            job_manifest.job_index, kind
        ))
    })?;
    if outputs.next().is_some() {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack job {} has more than one {:?} output artifact",
            job_manifest.job_index, kind
        )));
    }
    Ok(output)
}

#[cfg(test)]

pub(in crate::compiler) fn artifact_refs_for_indices(
    manifest: &SourcePackArtifactManifest,
    artifact_indices: &[usize],
) -> Result<Vec<SourcePackArtifactRef>, CompileError> {
    let mut refs = Vec::new();
    for_each_artifact_ref_for_indices(manifest, artifact_indices, |artifact| {
        refs.push(artifact);
        Ok(())
    })?;
    Ok(refs)
}

pub(in crate::compiler) fn for_each_artifact_ref_for_indices<F>(
    manifest: &SourcePackArtifactManifest,
    artifact_indices: &[usize],
    mut visit: F,
) -> Result<usize, CompileError>
where
    F: FnMut(SourcePackArtifactRef) -> Result<(), CompileError>,
{
    let mut artifact_count = 0usize;
    for &artifact_index in artifact_indices {
        visit(artifact_ref_for_index(manifest, artifact_index)?)?;
        artifact_count += 1;
    }
    Ok(artifact_count)
}

pub(in crate::compiler) fn artifact_ref_for_index(
    manifest: &SourcePackArtifactManifest,
    artifact_index: usize,
) -> Result<SourcePackArtifactRef, CompileError> {
    let artifact = manifest.get(artifact_index).ok_or_else(|| {
        CompileError::GpuFrontend(format!(
            "source-pack artifact manifest missing artifact {artifact_index}"
        ))
    })?;
    Ok(SourcePackArtifactRef {
        artifact_index: artifact.artifact_index,
        key: artifact.key.clone(),
        producing_job_index: artifact.producing_job_index,
        kind: artifact.kind,
    })
}

pub(in crate::compiler) fn load_library_interface_artifacts_for_indices<S>(
    store: &mut S,
    manifest: &SourcePackArtifactManifest,
    artifact_indices: &[usize],
) -> Result<Vec<S::LibraryInterfaceArtifact>, CompileError>
where
    S: ArtifactStore,
{
    let mut artifacts = Vec::new();
    for_each_artifact_ref_for_indices(manifest, artifact_indices, |artifact| {
        artifacts.push(store.load_library_interface(&artifact)?);
        Ok(())
    })?;
    Ok(artifacts)
}

pub(in crate::compiler) fn load_codegen_object_artifacts_for_indices<S>(
    store: &mut S,
    manifest: &SourcePackArtifactManifest,
    artifact_indices: &[usize],
) -> Result<Vec<S::CodegenObjectArtifact>, CompileError>
where
    S: ArtifactStore,
{
    let mut artifacts = Vec::new();
    for_each_artifact_ref_for_indices(manifest, artifact_indices, |artifact| {
        artifacts.push(store.load_codegen_object(&artifact)?);
        Ok(())
    })?;
    Ok(artifacts)
}

pub(in crate::compiler) fn load_library_interface_artifacts_excluding<S>(
    store: &mut S,
    artifact_refs: &[SourcePackArtifactRef],
    excluded_artifact_index: usize,
) -> Result<Vec<S::LibraryInterfaceArtifact>, CompileError>
where
    S: ArtifactStore,
{
    load_library_interface_artifact_batch_excluding(
        store,
        artifact_refs,
        Some(excluded_artifact_index),
    )
}

pub(in crate::compiler) fn load_library_interface_artifact_batch_excluding<S>(
    store: &mut S,
    artifact_refs: &[SourcePackArtifactRef],
    excluded_artifact_index: Option<usize>,
) -> Result<Vec<S::LibraryInterfaceArtifact>, CompileError>
where
    S: ArtifactStore,
{
    artifact_refs
        .iter()
        .filter(|artifact| Some(artifact.artifact_index) != excluded_artifact_index)
        .map(|artifact| store.load_library_interface(artifact))
        .collect()
}

pub(in crate::compiler) fn load_library_interface_artifacts<S>(
    store: &mut S,
    artifacts: &[SourcePackArtifactRef],
) -> Result<Vec<S::LibraryInterfaceArtifact>, CompileError>
where
    S: ArtifactStore,
{
    artifacts
        .iter()
        .map(|artifact| store.load_library_interface(artifact))
        .collect()
}

pub(in crate::compiler) fn load_codegen_object_artifacts<S>(
    store: &mut S,
    artifacts: &[SourcePackArtifactRef],
) -> Result<Vec<S::CodegenObjectArtifact>, CompileError>
where
    S: ArtifactStore,
{
    artifacts
        .iter()
        .map(|artifact| store.load_codegen_object(artifact))
        .collect()
}

pub(in crate::compiler) fn load_partial_link_outputs<S>(
    store: &mut S,
    keys: &[String],
) -> Result<Vec<S::PartialLinkArtifact>, CompileError>
where
    S: HierarchicalLinkArtifactStore,
{
    keys.iter()
        .map(|key| store.load_partial_link_output(key))
        .collect()
}

pub(in crate::compiler) fn release_link_input_artifacts<S>(
    artifact_manifest: &SourcePackBuildArtifactManifest,
    store: &mut S,
) -> Result<(), CompileError>
where
    S: ArtifactStore,
{
    let mut released_interfaces = BTreeSet::new();
    for link_batch in &artifact_manifest.link_interface_batches.batches {
        for_each_artifact_ref_for_indices(
            &artifact_manifest.artifacts,
            &link_batch.input_interface_artifact_indices,
            |artifact| {
                if released_interfaces.insert(artifact.artifact_index) {
                    store.release_library_interface(&artifact)?;
                }
                Ok(())
            },
        )?;
    }

    let mut released_objects = BTreeSet::new();
    for link_batch in &artifact_manifest.link_object_batches.batches {
        for_each_artifact_ref_for_indices(
            &artifact_manifest.artifacts,
            &link_batch.input_object_artifact_indices,
            |artifact| {
                if released_objects.insert(artifact.artifact_index) {
                    store.release_codegen_object(&artifact)?;
                }
                Ok(())
            },
        )?;
    }

    Ok(())
}

pub(in crate::compiler) fn execution_shard_batch_result(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    batch_index: usize,
) -> Result<ArtifactStoreBatchExecutionResult, CompileError> {
    let batch = execution_shard_job_batch(execution_shard, batch_index)?;
    let mut linked_output_key = None;
    for &job_index in &batch.job_indices {
        let job = execution_shard_job(execution_shard, job_index)?;
        if job.phase != SourcePackJobPhase::Link {
            continue;
        }
        let job_manifest = execution_shard_job_artifact(execution_shard, job_index)?;
        let output =
            single_output_artifact_ref(job_manifest, SourcePackArtifactKind::LinkedOutput)?;
        if linked_output_key.replace(output.key.clone()).is_some() {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack execution shard batch {} contains more than one linked output",
                batch.batch_index
            )));
        }
    }
    Ok(ArtifactStoreBatchExecutionResult {
        batch_index: batch.batch_index,
        job_count: batch.job_indices.len(),
        linked_output_key,
    })
}

pub(in crate::compiler) fn execution_shard_batch_contains_link_job(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    batch_index: usize,
) -> Result<bool, CompileError> {
    let batch = execution_shard_job_batch(execution_shard, batch_index)?;
    for &job_index in &batch.job_indices {
        if execution_shard_job(execution_shard, job_index)?.phase == SourcePackJobPhase::Link {
            return Ok(true);
        }
    }
    Ok(false)
}
