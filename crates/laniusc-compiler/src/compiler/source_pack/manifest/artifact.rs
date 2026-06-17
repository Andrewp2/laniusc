use super::*;

pub(in crate::compiler) fn validate_artifact_manifest(
    manifest: &SourcePackBuildArtifactManifest,
) -> Result<(), CompileError> {
    validate_artifact_manifest_version(manifest)?;
    validate_artifact_manifest_contract(manifest)
}

pub(in crate::compiler) fn compact_artifact_manifest(
    manifest: &SourcePackBuildArtifactManifest,
) -> Result<SourcePackBuildArtifactManifest, CompileError> {
    validate_artifact_manifest(manifest)?;
    let compact = SourcePackBuildArtifactManifest {
        version: manifest.version,
        target: manifest.target,
        job_count: manifest.job_count,
        job_batch_count: manifest.job_batch_count,
        batch_dependency_count: manifest.batch_dependency_count,
        artifact_count: manifest.artifact_count,
        job_artifact_count: manifest.job_artifact_count,
        job_artifact_io_count: manifest.job_artifact_io_count,
        artifact_use_count: manifest.artifact_use_count,
        link_interface_batch_count: manifest.link_interface_batch_count,
        link_object_batch_count: manifest.link_object_batch_count,
        job_schedule: Default::default(),
        job_batches: Default::default(),
        batch_dependencies: Default::default(),
        artifacts: Default::default(),
        job_artifacts: Default::default(),
        job_artifact_io: Default::default(),
        artifact_uses: Default::default(),
        link_interface_batches: Default::default(),
        link_object_batches: Default::default(),
    };
    validate_artifact_manifest(&compact)?;
    Ok(compact)
}

pub(in crate::compiler) fn ensure_manifest_execution_records(
    manifest: &SourcePackBuildArtifactManifest,
) -> Result<(), CompileError> {
    let required_records = [
        (
            "job schedule",
            manifest.job_schedule.jobs.len(),
            manifest.job_count,
        ),
        (
            "job batches",
            manifest.job_batches.batches.len(),
            manifest.job_batch_count,
        ),
        (
            "batch dependencies",
            manifest.batch_dependencies.batches.len(),
            manifest.batch_dependency_count,
        ),
        (
            "artifact refs",
            manifest.artifacts.artifacts.len(),
            manifest.artifact_count,
        ),
        (
            "job artifact manifests",
            manifest.job_artifacts.jobs.len(),
            manifest.job_artifact_count,
        ),
        (
            "job artifact I/O",
            manifest.job_artifact_io.jobs.len(),
            manifest.job_artifact_io_count,
        ),
        (
            "artifact uses",
            manifest.artifact_uses.uses.len(),
            manifest.artifact_use_count,
        ),
        (
            "link interface batches",
            manifest.link_interface_batches.batches.len(),
            manifest.link_interface_batch_count,
        ),
        (
            "link object batches",
            manifest.link_object_batches.batches.len(),
            manifest.link_object_batch_count,
        ),
    ];
    if let Some((label, actual, expected)) = required_records
        .into_iter()
        .find(|(_, actual, expected)| actual != expected)
    {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack artifact-manifest execution requires inline {label} records; compact manifest records {expected} counts but {actual} inline records and must use persisted execution shards"
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_artifact_manifest_version(
    manifest: &SourcePackBuildArtifactManifest,
) -> Result<(), CompileError> {
    if manifest.version != SOURCE_PACK_BUILD_ARTIFACT_MANIFEST_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack artifact manifest version {}; expected {}",
            manifest.version, SOURCE_PACK_BUILD_ARTIFACT_MANIFEST_VERSION
        )));
    }
    Ok(())
}
