use super::*;

/// Version for persisted source-pack path build manifests.
pub const SOURCE_PACK_PATH_BUILD_MANIFEST_VERSION: u32 = 1;

/// Persisted build manifest for path-backed source-pack compilation.
///
/// A compact manifest may omit inline source files and rely on source-file pages,
/// but it still records source totals and the artifact manifest needed to replay
/// execution.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackPathBuildManifest {
    pub version: u32,
    pub source_file_count: usize,
    pub source_byte_count: usize,
    #[serde(default)]
    pub source_line_count: usize,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub source_files: Vec<ExplicitSourcePathFile>,
    pub library_dependencies: Vec<SourcePackLibraryDependency>,
    pub limits: CodegenUnitLimits,
    pub batch_limits: SourcePackJobBatchLimits,
    pub artifacts: SourcePackBuildArtifactManifest,
}

impl SourcePackPathBuildManifest {
    /// Validates this manifest against the source-pack path manifest contract.
    pub fn validate_contract(&self) -> Result<(), CompileError> {
        validate_path_manifest(self)
    }

    /// Returns the inline path manifest represented by this build manifest.
    pub fn path_manifest(&self) -> Result<ExplicitSourcePackPathManifest, CompileError> {
        validate_path_manifest(self)?;
        if self.source_files.is_empty() {
            return Err(manifest_contract_error(
                "compact path build manifest leaves source files in source-file pages",
            ));
        }
        Ok(ExplicitSourcePackPathManifest {
            files: self.source_files.clone(),
            library_dependencies: self.library_dependencies.clone(),
        })
    }

    /// Executes all artifact-manifest batches against an artifact store.
    pub fn execute_with_artifact_store<E, S>(
        &self,
        executor: &mut E,
        store: &mut S,
    ) -> Result<ArtifactStoreBuildExecutionResult, CompileError>
    where
        E: ArtifactBuildExecutor<
                LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
                CodegenObjectArtifact = S::CodegenObjectArtifact,
                LinkedOutputArtifact = S::LinkedOutputArtifact,
            >,
        S: ArtifactStore,
    {
        let source_pack = self.path_manifest()?;
        execute_artifact_manifest_build(&source_pack, &self.artifacts, executor, store)
    }

    /// Executes one artifact-manifest batch against an artifact store.
    pub fn execute_batch_with_artifact_store<E, S>(
        &self,
        batch_index: usize,
        executor: &mut E,
        store: &mut S,
    ) -> Result<ArtifactStoreBatchExecutionResult, CompileError>
    where
        E: ArtifactBuildExecutor<
                LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
                CodegenObjectArtifact = S::CodegenObjectArtifact,
                LinkedOutputArtifact = S::LinkedOutputArtifact,
            >,
        S: ArtifactStore,
    {
        let source_pack = self.path_manifest()?;
        execute_artifact_manifest_batch(&source_pack, &self.artifacts, batch_index, executor, store)
    }

    /// Returns ready batch indices using inline dependency records.
    pub fn ready_batch_indices_limited(
        &self,
        completed_batch_indices: &[usize],
        max_batches: Option<usize>,
    ) -> Result<Vec<usize>, CompileError> {
        validate_path_manifest(self)?;
        self.ensure_inline_batch_dependency_records_for_ready_query()?;
        Ok(self
            .artifacts
            .batch_dependencies
            .ready_batch_indices_limited(completed_batch_indices, max_batches))
    }

    /// Returns ready batch indices for a compact build state when possible.
    pub fn ready_batch_indices_from_state_limited(
        &self,
        state: &SourcePackBuildState,
        max_batches: Option<usize>,
    ) -> Result<Vec<usize>, CompileError> {
        validate_build_state_version(state)?;
        if state.completed_batch_count == 0 {
            return self.ready_batch_indices_limited(&[], max_batches);
        }
        if self.is_state_complete(state)? {
            return Ok(Vec::new());
        }
        Err(CompileError::GpuFrontend(
            "source-pack ready-batch queries must use persisted progress state; compact build state does not record completed-batch identities".into(),
        ))
    }

    /// Returns ready and unclaimed batch indices for a compact build state.
    pub fn ready_unclaimed_batch_indices_from_state_limited(
        &self,
        state: &SourcePackBuildState,
        _now_unix_nanos: Option<u128>,
        max_batches: Option<usize>,
    ) -> Result<Vec<usize>, CompileError> {
        validate_path_manifest(self)?;
        validate_build_state_version(state)?;
        if max_batches == Some(0) {
            return Ok(Vec::new());
        }
        if state.claimed_batch_count != 0 {
            return Err(CompileError::GpuFrontend(
                "source-pack ready-unclaimed queries must use persisted progress state; compact build state does not record claimed-batch identities".into(),
            ));
        }
        if state.completed_batch_count == 0 {
            return self.ready_batch_indices_limited(&[], max_batches);
        }
        if self.is_state_complete(state)? {
            return Ok(Vec::new());
        }
        Err(CompileError::GpuFrontend(
            "source-pack ready-unclaimed queries must use persisted progress state; compact build state does not record completed-batch identities".into(),
        ))
    }

    /// Returns whether a compact build state has completed every job batch.
    pub fn is_state_complete(&self, state: &SourcePackBuildState) -> Result<bool, CompileError> {
        validate_path_manifest(self)?;
        validate_build_state_version(state)?;
        Ok(state.completed_batch_count() == self.artifacts.job_batch_count)
    }

    /// Ensures ready-batch queries can use inline batch-dependency records.
    pub(in crate::compiler) fn ensure_inline_batch_dependency_records_for_ready_query(
        &self,
    ) -> Result<(), CompileError> {
        let dependency_record_count = self.artifacts.batch_dependencies.batches.len();
        if dependency_record_count != self.artifacts.batch_dependency_count {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack path-build manifest ready-batch queries require inline batch-dependency records; compact manifest records {} dependency counts but {} inline records and must use persisted progress state",
                self.artifacts.batch_dependency_count, dependency_record_count
            )));
        }
        Ok(())
    }
}

/// Validates a path build manifest and its embedded artifact manifest.
pub(in crate::compiler) fn validate_path_manifest(
    manifest: &SourcePackPathBuildManifest,
) -> Result<(), CompileError> {
    if manifest.version != SOURCE_PACK_PATH_BUILD_MANIFEST_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack path build manifest version {}; expected {}",
            manifest.version, SOURCE_PACK_PATH_BUILD_MANIFEST_VERSION
        )));
    }
    validate_artifact_manifest(&manifest.artifacts)?;
    validate_path_manifest_source_ranges(manifest)?;
    Ok(())
}

/// Validates source-file totals and job/artifact source ranges.
pub(in crate::compiler) fn validate_path_manifest_source_ranges(
    manifest: &SourcePackPathBuildManifest,
) -> Result<(), CompileError> {
    let source_file_count = manifest.source_file_count;
    if source_file_count == 0 {
        return Err(manifest_contract_error(
            "path build manifest has no source files",
        ));
    }
    if manifest.source_byte_count == 0 {
        return Err(manifest_contract_error(format!(
            "path build manifest has empty source-byte summary for {source_file_count} source files; compact replay manifests must carry concrete source-byte evidence"
        )));
    }
    if manifest.source_byte_count < source_file_count {
        return Err(manifest_contract_error(format!(
            "path build manifest source-byte summary {} is smaller than source-file count {source_file_count}; compact replay manifests must not treat empty source metadata as package input",
            manifest.source_byte_count
        )));
    }
    if !manifest.source_files.is_empty() && manifest.source_files.len() != source_file_count {
        return Err(manifest_contract_error(format!(
            "path build manifest has {} source-file records but source_file_count {}",
            manifest.source_files.len(),
            source_file_count
        )));
    }
    if !manifest.source_files.is_empty() {
        let source_byte_count = manifest
            .source_files
            .iter()
            .map(|file| file.byte_len)
            .sum::<usize>();
        let source_line_count = manifest
            .source_files
            .iter()
            .map(|file| file.line_count.unwrap_or(0))
            .sum::<usize>();
        if source_byte_count != manifest.source_byte_count {
            return Err(manifest_contract_error(format!(
                "path build manifest source byte total {} does not match source_byte_count {}",
                source_byte_count, manifest.source_byte_count
            )));
        }
        if source_line_count != manifest.source_line_count {
            return Err(manifest_contract_error(format!(
                "path build manifest source line total {} does not match source_line_count {}",
                source_line_count, manifest.source_line_count
            )));
        }
    }
    for job in &manifest.artifacts.job_schedule.jobs {
        let source_end = job.first_source_index.saturating_add(job.source_file_count);
        if source_end > source_file_count {
            return Err(manifest_contract_error(format!(
                "job {} source range {}..{} exceeds path manifest source file count {}",
                job.job_index, job.first_source_index, source_end, source_file_count
            )));
        }
    }
    for artifact in &manifest.artifacts.artifacts.artifacts {
        let source_end = artifact
            .first_source_index
            .saturating_add(artifact.source_file_count);
        if source_end > source_file_count {
            return Err(manifest_contract_error(format!(
                "artifact {} source range {}..{} exceeds path manifest source file count {}",
                artifact.artifact_index, artifact.first_source_index, source_end, source_file_count
            )));
        }
    }
    validate_path_manifest_job_source_libraries(manifest)?;
    validate_path_manifest_frontend_source_coverage(manifest, source_file_count)?;
    Ok(())
}

fn validate_path_manifest_job_source_libraries(
    manifest: &SourcePackPathBuildManifest,
) -> Result<(), CompileError> {
    if manifest.source_files.is_empty() {
        return Ok(());
    }

    for job in &manifest.artifacts.job_schedule.jobs {
        if job.phase == SourcePackJobPhase::Link {
            continue;
        }
        let source_end = job.first_source_index.saturating_add(job.source_file_count);
        let source_files = &manifest.source_files[job.first_source_index..source_end];
        for (source_offset, source_file) in source_files.iter().enumerate() {
            if source_file.library_id != job.library_id {
                let source_index = job.first_source_index.saturating_add(source_offset);
                return Err(manifest_contract_error(format!(
                    "job {} {:?} source range claims library {} but source-file record {} belongs to library {}; path-build replay must not reinterpret source-root path identity through job metadata",
                    job.job_index, job.phase, job.library_id, source_index, source_file.library_id
                )));
            }
        }
    }

    Ok(())
}

fn validate_path_manifest_frontend_source_coverage(
    manifest: &SourcePackPathBuildManifest,
    source_file_count: usize,
) -> Result<(), CompileError> {
    if manifest.artifacts.job_schedule.jobs.is_empty() {
        return Ok(());
    }

    let mut ranges = manifest
        .artifacts
        .job_schedule
        .jobs
        .iter()
        .filter(|job| job.phase == SourcePackJobPhase::LibraryFrontend)
        .map(|job| {
            (
                job.first_source_index,
                job.first_source_index.saturating_add(job.source_file_count),
                job.job_index,
            )
        })
        .collect::<Vec<_>>();
    ranges.sort_unstable();

    if ranges.is_empty() {
        return Err(manifest_contract_error(
            "path build manifest has inline jobs but no library frontend source ranges",
        ));
    }

    let mut next_source_index = 0usize;
    for (first_source_index, source_end, job_index) in ranges {
        if first_source_index < next_source_index {
            return Err(manifest_contract_error(format!(
                "library frontend job source ranges overlap at source file {first_source_index}; job {job_index} starts before expected source file {next_source_index}"
            )));
        }
        if first_source_index > next_source_index {
            return Err(manifest_contract_error(format!(
                "library frontend job source ranges leave path manifest source files {}..{} uncovered",
                next_source_index, first_source_index
            )));
        }
        next_source_index = source_end;
    }

    if next_source_index != source_file_count {
        return Err(manifest_contract_error(format!(
            "library frontend job source ranges cover path manifest source files 0..{} but source_file_count is {}",
            next_source_index, source_file_count
        )));
    }

    Ok(())
}
