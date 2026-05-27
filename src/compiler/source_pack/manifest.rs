use super::*;

pub const SOURCE_PACK_PATH_BUILD_MANIFEST_VERSION: u32 = 1;

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
    pub fn validate_contract(&self) -> Result<(), CompileError> {
        validate_source_pack_path_build_manifest_versions(self)
    }

    pub fn source_pack_path_manifest(
        &self,
    ) -> Result<ExplicitSourcePackPathManifest, CompileError> {
        validate_source_pack_path_build_manifest_versions(self)?;
        if self.source_files.is_empty() {
            return Err(source_pack_manifest_contract_error(
                "compact path build manifest leaves source files in source-file pages",
            ));
        }
        Ok(ExplicitSourcePackPathManifest {
            files: self.source_files.clone(),
            library_dependencies: self.library_dependencies.clone(),
        })
    }

    pub fn execute_with_artifact_store<E, S>(
        &self,
        executor: &mut E,
        store: &mut S,
    ) -> Result<SourcePackArtifactStoreBuildExecutionResult, CompileError>
    where
        E: SourcePackPathArtifactBuildExecutor<
                LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
                CodegenObjectArtifact = S::CodegenObjectArtifact,
                LinkedOutputArtifact = S::LinkedOutputArtifact,
            >,
        S: SourcePackPathArtifactStore,
    {
        let source_pack = self.source_pack_path_manifest()?;
        execute_source_pack_path_artifact_manifest_store_build(
            &source_pack,
            &self.artifacts,
            executor,
            store,
        )
    }

    pub fn execute_batch_with_artifact_store<E, S>(
        &self,
        batch_index: usize,
        executor: &mut E,
        store: &mut S,
    ) -> Result<SourcePackArtifactStoreBatchExecutionResult, CompileError>
    where
        E: SourcePackPathArtifactBuildExecutor<
                LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
                CodegenObjectArtifact = S::CodegenObjectArtifact,
                LinkedOutputArtifact = S::LinkedOutputArtifact,
            >,
        S: SourcePackPathArtifactStore,
    {
        let source_pack = self.source_pack_path_manifest()?;
        execute_source_pack_path_artifact_manifest_store_batch(
            &source_pack,
            &self.artifacts,
            batch_index,
            executor,
            store,
        )
    }

    pub fn ready_batch_indices_limited(
        &self,
        completed_batch_indices: &[usize],
        max_batches: Option<usize>,
    ) -> Result<Vec<usize>, CompileError> {
        validate_source_pack_path_build_manifest_versions(self)?;
        self.ensure_inline_batch_dependency_records_for_ready_query()?;
        Ok(self
            .artifacts
            .batch_dependencies
            .ready_batch_indices_limited(completed_batch_indices, max_batches))
    }

    pub fn ready_batch_indices_from_state_limited(
        &self,
        state: &SourcePackBuildState,
        max_batches: Option<usize>,
    ) -> Result<Vec<usize>, CompileError> {
        validate_source_pack_build_state_version(state)?;
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

    pub fn ready_unclaimed_batch_indices_from_state_limited(
        &self,
        state: &SourcePackBuildState,
        _now_unix_nanos: Option<u128>,
        max_batches: Option<usize>,
    ) -> Result<Vec<usize>, CompileError> {
        validate_source_pack_path_build_manifest_versions(self)?;
        validate_source_pack_build_state_version(state)?;
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

    pub fn is_state_complete(&self, state: &SourcePackBuildState) -> Result<bool, CompileError> {
        validate_source_pack_path_build_manifest_versions(self)?;
        validate_source_pack_build_state_version(state)?;
        Ok(state.completed_batch_count() == self.artifacts.job_batch_count)
    }

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

pub(in crate::compiler) fn validate_source_pack_path_build_manifest_versions(
    manifest: &SourcePackPathBuildManifest,
) -> Result<(), CompileError> {
    if manifest.version != SOURCE_PACK_PATH_BUILD_MANIFEST_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack path build manifest version {}; expected {}",
            manifest.version, SOURCE_PACK_PATH_BUILD_MANIFEST_VERSION
        )));
    }
    validate_source_pack_build_artifact_manifest(&manifest.artifacts)?;
    validate_source_pack_path_build_manifest_source_ranges(manifest)?;
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_path_build_manifest_source_ranges(
    manifest: &SourcePackPathBuildManifest,
) -> Result<(), CompileError> {
    let source_file_count = manifest.source_file_count;
    if source_file_count == 0 {
        return Err(source_pack_manifest_contract_error(
            "path build manifest has no source files",
        ));
    }
    if !manifest.source_files.is_empty() && manifest.source_files.len() != source_file_count {
        return Err(source_pack_manifest_contract_error(format!(
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
            return Err(source_pack_manifest_contract_error(format!(
                "path build manifest source byte total {} does not match source_byte_count {}",
                source_byte_count, manifest.source_byte_count
            )));
        }
        if source_line_count != manifest.source_line_count {
            return Err(source_pack_manifest_contract_error(format!(
                "path build manifest source line total {} does not match source_line_count {}",
                source_line_count, manifest.source_line_count
            )));
        }
    }
    for job in &manifest.artifacts.job_schedule.jobs {
        let source_end = job.first_source_index.saturating_add(job.source_file_count);
        if source_end > source_file_count {
            return Err(source_pack_manifest_contract_error(format!(
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
            return Err(source_pack_manifest_contract_error(format!(
                "artifact {} source range {}..{} exceeds path manifest source file count {}",
                artifact.artifact_index, artifact.first_source_index, source_end, source_file_count
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_build_artifact_manifest(
    manifest: &SourcePackBuildArtifactManifest,
) -> Result<(), CompileError> {
    validate_source_pack_build_artifact_manifest_version(manifest)?;
    validate_source_pack_build_artifact_manifest_contract(manifest)
}

pub(in crate::compiler) fn source_pack_compact_build_artifact_manifest(
    manifest: &SourcePackBuildArtifactManifest,
) -> Result<SourcePackBuildArtifactManifest, CompileError> {
    validate_source_pack_build_artifact_manifest(manifest)?;
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
    validate_source_pack_build_artifact_manifest(&compact)?;
    Ok(compact)
}

pub(in crate::compiler) fn ensure_inline_build_artifact_records_for_manifest_execution(
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

pub(in crate::compiler) fn validate_source_pack_build_artifact_manifest_version(
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

pub(in crate::compiler) fn validate_source_pack_build_artifact_shard_index(
    index: &SourcePackBuildArtifactShardIndex,
) -> Result<(), CompileError> {
    if index.version != SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack artifact shard index version {}; expected {}",
            index.version, SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION
        )));
    }
    if index.shard_count == 0 {
        return Err(source_pack_artifact_shard_contract_error(
            "artifact shard index has no shards",
        ));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_build_artifact_shard_plan(
    plan: &SourcePackBuildArtifactShardPlan,
) -> Result<(), CompileError> {
    validate_source_pack_build_artifact_shard_index(&plan.index)?;
    if plan.shards.len() != plan.index.shard_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact shard plan has {} shard records but shard_count {}",
            plan.shards.len(),
            plan.index.shard_count
        )));
    }
    let limits = plan.index.limits.normalized();
    for (position, shard) in plan.shards.iter().enumerate() {
        if shard.shard_index != position {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "shard entry {position} has shard_index {}",
                shard.shard_index
            )));
        }
        validate_source_pack_build_artifact_shard(shard, plan.index.target)?;
        if shard.limits.normalized() != limits {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "shard {} limits {:?} do not match index limits {:?}",
                shard.shard_index, shard.limits, plan.index.limits
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_build_artifact_shard(
    shard: &SourcePackBuildArtifactShard,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if shard.version != SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack artifact shard version {}; expected {}",
            shard.version, SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION
        )));
    }
    if shard.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "shard {} target {:?} does not match index target {:?}",
            shard.shard_index, shard.target, target
        )));
    }
    if shard.batch_indices.is_empty() {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "shard {} has no batch indices",
            shard.shard_index
        )));
    }
    let limits = shard.limits.normalized();
    if shard.batch_indices.len() > limits.max_batches_per_shard {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "shard {} has {} batch records but the record cap is {}",
            shard.shard_index,
            shard.batch_indices.len(),
            limits.max_batches_per_shard
        )));
    }
    if shard.job_indices.len() > limits.max_jobs_per_shard {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "shard {} has {} job records but the record cap is {}",
            shard.shard_index,
            shard.job_indices.len(),
            limits.max_jobs_per_shard
        )));
    }
    let artifact_ref_count = shard
        .input_artifact_indices
        .len()
        .checked_add(shard.input_artifact_ranges.len())
        .ok_or_else(|| {
            source_pack_artifact_shard_contract_error(format!(
                "shard {} artifact record count overflows",
                shard.shard_index
            ))
        })?
        .checked_add(shard.output_artifact_indices.len())
        .ok_or_else(|| {
            source_pack_artifact_shard_contract_error(format!(
                "shard {} artifact record count overflows",
                shard.shard_index
            ))
        })?;
    if artifact_ref_count > limits.max_artifacts_per_shard {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "shard {} has {} artifact records but the record cap is {}",
            shard.shard_index, artifact_ref_count, limits.max_artifacts_per_shard
        )));
    }
    source_pack_manifest_unique_usize_set(
        &shard.batch_indices,
        &format!("shard {} batches", shard.shard_index),
    )?;
    source_pack_manifest_unique_usize_set(
        &shard.job_indices,
        &format!("shard {} jobs", shard.shard_index),
    )?;
    let explicit_input_artifacts = source_pack_manifest_unique_usize_set(
        &shard.input_artifact_indices,
        &format!("shard {} input artifacts", shard.shard_index),
    )?;
    source_pack_validate_artifact_index_ranges(
        &shard.input_artifact_ranges,
        &explicit_input_artifacts,
        &format!("shard {} input artifact", shard.shard_index),
        |message| source_pack_artifact_shard_contract_error(message),
    )?;
    source_pack_manifest_unique_usize_set(
        &shard.output_artifact_indices,
        &format!("shard {} output artifacts", shard.shard_index),
    )?;
    let structurally_oversized = shard.batch_count() > limits.max_batches_per_shard
        || shard.job_count() > limits.max_jobs_per_shard
        || artifact_ref_count > limits.max_artifacts_per_shard;
    if structurally_oversized && !shard.oversized {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "shard {} exceeds shard limits {:?} but oversized flag is false",
            shard.shard_index, shard.limits
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_for_each_build_artifact_shard_from_index<F>(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackBuildArtifactShardIndex,
    mut visit: F,
) -> Result<(), CompileError>
where
    F: FnMut(&SourcePackBuildArtifactShard) -> Result<(), CompileError>,
{
    validate_source_pack_build_artifact_shard_index(index)?;
    if index.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact shard index target {:?} does not match requested target {:?}",
            index.target, target
        )));
    }
    for shard_index in 0..index.shard_count {
        let shard = store.load_build_artifact_shard_for_target(target, shard_index)?;
        visit(&shard)?;
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_for_each_job_batch_artifact_shard_from_index<F>(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackBuildArtifactShardIndex,
    visit: F,
) -> Result<(), CompileError>
where
    F: FnMut(&SourcePackBuildArtifactShard) -> Result<(), CompileError>,
{
    let mut visit = visit;
    source_pack_for_each_build_artifact_shard_from_index(store, target, index, |shard| {
        if shard.kind == SourcePackBuildArtifactShardKind::JobBatches {
            visit(shard)?;
        }
        Ok(())
    })
}

pub(in crate::compiler) fn validate_source_pack_build_artifact_execution_shard_record_count(
    shard_index: usize,
    label: &str,
    count: usize,
    cap: usize,
) -> Result<(), CompileError> {
    if count > cap {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "execution shard {shard_index} has {count} {label} records but the record cap is {cap}"
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_build_artifact_execution_shard(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    validate_source_pack_build_artifact_execution_shard_with_mode(
        execution_shard,
        target,
        SourcePackBuildArtifactExecutionShardValidationMode::Persisted,
    )
}

pub(in crate::compiler) fn validate_source_pack_build_artifact_execution_shard_store_input(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    validate_source_pack_build_artifact_execution_shard_with_mode(
        execution_shard,
        target,
        SourcePackBuildArtifactExecutionShardValidationMode::StoreInput,
    )
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(in crate::compiler) enum SourcePackBuildArtifactExecutionShardValidationMode {
    Persisted,
    StoreInput,
}

pub(in crate::compiler) fn validate_source_pack_build_artifact_execution_shard_inline_record_count(
    shard_index: usize,
    label: &str,
    count: usize,
    cap: usize,
    mode: SourcePackBuildArtifactExecutionShardValidationMode,
) -> Result<(), CompileError> {
    if mode == SourcePackBuildArtifactExecutionShardValidationMode::Persisted && count > cap {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "execution shard {shard_index} stores {count} inline {label} records, exceeding record cap {cap}"
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_build_artifact_execution_shard_with_mode(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    target: SourcePackArtifactTarget,
    mode: SourcePackBuildArtifactExecutionShardValidationMode,
) -> Result<(), CompileError> {
    if execution_shard.version != SOURCE_PACK_BUILD_ARTIFACT_EXECUTION_SHARD_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack artifact execution shard version {}; expected {}",
            execution_shard.version, SOURCE_PACK_BUILD_ARTIFACT_EXECUTION_SHARD_VERSION
        )));
    }
    if execution_shard.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "execution shard target {:?} does not match requested target {:?}",
            execution_shard.target, target
        )));
    }
    validate_source_pack_build_artifact_shard(&execution_shard.shard, target)?;
    let shard = &execution_shard.shard;
    let shard_batch_count = shard.batch_indices.len();
    let shard_job_count = shard.job_indices.len();
    let shard_artifact_ref_count = match mode {
        SourcePackBuildArtifactExecutionShardValidationMode::Persisted => {
            shard.artifact_record_count()
        }
        SourcePackBuildArtifactExecutionShardValidationMode::StoreInput => shard.artifact_count(),
    };
    validate_source_pack_build_artifact_execution_shard_record_count(
        shard.shard_index,
        "source-file",
        execution_shard.source_files.len(),
        SOURCE_PACK_EXECUTION_SHARD_SOURCE_FILE_DEFAULT_RECORD_CAP,
    )?;
    if !execution_shard.source_files.is_empty()
        && execution_shard.source_files.len() > shard.source_file_count
    {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "execution shard {} has {} source-file records but the shard records {} source files",
            shard.shard_index,
            execution_shard.source_files.len(),
            shard.source_file_count
        )));
    }
    validate_source_pack_build_artifact_execution_shard_record_count(
        shard.shard_index,
        "job-batch",
        execution_shard.job_batches.len(),
        shard_batch_count,
    )?;
    validate_source_pack_build_artifact_execution_shard_record_count(
        shard.shard_index,
        "batch-dependency",
        execution_shard.batch_dependencies.len(),
        shard_batch_count,
    )?;
    validate_source_pack_build_artifact_execution_shard_record_count(
        shard.shard_index,
        "batch-dependent",
        execution_shard.batch_dependents.len(),
        shard_batch_count,
    )?;
    validate_source_pack_build_artifact_execution_shard_record_count(
        shard.shard_index,
        "job",
        execution_shard.jobs.len(),
        shard_job_count,
    )?;
    validate_source_pack_build_artifact_execution_shard_record_count(
        shard.shard_index,
        "job-artifact",
        execution_shard.job_artifacts.len(),
        shard_job_count,
    )?;
    validate_source_pack_build_artifact_execution_shard_record_count(
        shard.shard_index,
        "artifact-ref",
        execution_shard.artifact_refs.len(),
        shard_artifact_ref_count,
    )?;
    validate_source_pack_build_artifact_execution_shard_record_count(
        shard.shard_index,
        "link-interface-batch",
        execution_shard.link_interface_batches.len(),
        shard_batch_count,
    )?;
    validate_source_pack_build_artifact_execution_shard_record_count(
        shard.shard_index,
        "link-object-batch",
        execution_shard.link_object_batches.len(),
        shard_batch_count,
    )?;
    match shard.kind {
        SourcePackBuildArtifactShardKind::JobBatches => {
            if execution_shard.job_batches.len() != shard_batch_count
                || execution_shard.batch_dependencies.len() != shard_batch_count
                || execution_shard.batch_dependents.len() != shard_batch_count
                || !execution_shard.link_interface_batches.is_empty()
                || !execution_shard.link_object_batches.is_empty()
            {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "execution shard {} job-batch record arrays do not match shard batch records",
                    shard.shard_index
                )));
            }
        }
        SourcePackBuildArtifactShardKind::LinkInterfaceBatches => {
            if execution_shard.link_interface_batches.len() != shard_batch_count
                || !execution_shard.job_batches.is_empty()
                || !execution_shard.batch_dependencies.is_empty()
                || !execution_shard.batch_dependents.is_empty()
                || !execution_shard.link_object_batches.is_empty()
            {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "execution shard {} link-interface record arrays do not match shard batch records",
                    shard.shard_index
                )));
            }
        }
        SourcePackBuildArtifactShardKind::LinkObjectBatches => {
            if execution_shard.link_object_batches.len() != shard_batch_count
                || !execution_shard.job_batches.is_empty()
                || !execution_shard.batch_dependencies.is_empty()
                || !execution_shard.batch_dependents.is_empty()
                || !execution_shard.link_interface_batches.is_empty()
            {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "execution shard {} link-object record arrays do not match shard batch records",
                    shard.shard_index
                )));
            }
        }
    }
    if execution_shard.jobs.len() != shard_job_count
        || execution_shard.job_artifacts.len() != shard_job_count
    {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "execution shard {} job record arrays do not match shard job records",
            shard.shard_index
        )));
    }
    source_pack_manifest_unique_usize_set(
        &execution_shard
            .source_files
            .iter()
            .map(|source_file| source_file.source_index)
            .collect::<Vec<_>>(),
        &format!(
            "execution shard {} source files",
            execution_shard.shard.shard_index
        ),
    )?;
    source_pack_manifest_unique_usize_set(
        &execution_shard
            .batch_dependencies
            .iter()
            .map(|batch| batch.batch_index)
            .collect::<Vec<_>>(),
        &format!(
            "execution shard {} batch dependencies",
            execution_shard.shard.shard_index
        ),
    )?;
    source_pack_manifest_unique_usize_set(
        &execution_shard
            .batch_dependents
            .iter()
            .map(|batch| batch.batch_index)
            .collect::<Vec<_>>(),
        &format!(
            "execution shard {} batch dependents",
            execution_shard.shard.shard_index
        ),
    )?;
    let job_batch_indices = execution_shard
        .job_batches
        .iter()
        .map(|batch| batch.batch_index)
        .collect::<BTreeSet<_>>();
    let dependency_batch_indices = execution_shard
        .batch_dependencies
        .iter()
        .map(|batch| batch.batch_index)
        .collect::<BTreeSet<_>>();
    if job_batch_indices != dependency_batch_indices {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "execution shard {} job batches {:?} do not match dependency batches {:?}",
            execution_shard.shard.shard_index, job_batch_indices, dependency_batch_indices
        )));
    }
    for dependency in &execution_shard.batch_dependencies {
        validate_source_pack_build_artifact_execution_shard_inline_record_count(
            shard.shard_index,
            "batch dependency",
            dependency.dependency_batch_indices.len(),
            SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE,
            mode,
        )?;
        validate_source_pack_build_artifact_execution_shard_inline_record_count(
            shard.shard_index,
            "batch dependency range",
            dependency.dependency_batch_ranges.len(),
            SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE,
            mode,
        )?;
        if !dependency.dependency_batch_indices.is_empty() && dependency.dependency_batch_count != 0
        {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "execution shard {} batch {} records both inline and paged dependencies",
                execution_shard.shard.shard_index, dependency.batch_index
            )));
        }
        if dependency.dependency_batch_count == 0 {
            if dependency.dependency_page_count != 0 {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "execution shard {} batch {} has dependency page count {} without dependencies",
                    execution_shard.shard.shard_index,
                    dependency.batch_index,
                    dependency.dependency_page_count
                )));
            }
        } else {
            let expected_page_count = dependency
                .dependency_batch_count
                .div_ceil(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE);
            if dependency.dependency_page_count != expected_page_count {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "execution shard {} batch {} has dependency page count {} but expected {}",
                    execution_shard.shard.shard_index,
                    dependency.batch_index,
                    dependency.dependency_page_count,
                    expected_page_count
                )));
            }
        }
        let explicit_dependencies = source_pack_manifest_unique_usize_set(
            &dependency.dependency_batch_indices,
            &format!(
                "execution shard {} batch {} dependencies",
                execution_shard.shard.shard_index, dependency.batch_index
            ),
        )?;
        source_pack_validate_job_batch_dependency_range_metadata(
            dependency,
            &format!(
                "execution shard {} batch {}",
                execution_shard.shard.shard_index, dependency.batch_index
            ),
            |message| source_pack_artifact_shard_contract_error(message),
        )?;
        source_pack_validate_job_batch_dependency_ranges(
            dependency,
            &explicit_dependencies,
            &format!(
                "execution shard {} batch {}",
                execution_shard.shard.shard_index, dependency.batch_index
            ),
            usize::MAX,
            Some(dependency.batch_index),
            |message| source_pack_artifact_shard_contract_error(message),
        )?;
    }
    let dependent_record_batch_indices = execution_shard
        .batch_dependents
        .iter()
        .map(|batch| batch.batch_index)
        .collect::<BTreeSet<_>>();
    if execution_shard.shard.kind == SourcePackBuildArtifactShardKind::JobBatches {
        if job_batch_indices != dependent_record_batch_indices {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "execution shard {} job batches {:?} do not match dependent-record batches {:?}",
                execution_shard.shard.shard_index,
                job_batch_indices,
                dependent_record_batch_indices
            )));
        }
    } else if !dependent_record_batch_indices.is_empty() {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "execution shard {} has batch dependent records for non-job shard {:?}",
            execution_shard.shard.shard_index, execution_shard.shard.kind
        )));
    }
    for dependents in &execution_shard.batch_dependents {
        validate_source_pack_build_artifact_execution_shard_inline_record_count(
            shard.shard_index,
            "batch dependent",
            dependents.dependent_batch_indices.len(),
            SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE,
            mode,
        )?;
        if !job_batch_indices.contains(&dependents.batch_index) {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "execution shard {} has dependent record for batch {} outside shard job batches {:?}",
                execution_shard.shard.shard_index, dependents.batch_index, job_batch_indices
            )));
        }
        source_pack_manifest_unique_usize_set(
            &dependents.dependent_batch_indices,
            &format!(
                "execution shard {} batch {} dependents",
                execution_shard.shard.shard_index, dependents.batch_index
            ),
        )?;
        if dependents
            .dependent_batch_indices
            .contains(&dependents.batch_index)
        {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "execution shard {} batch {} lists itself as a dependent",
                execution_shard.shard.shard_index, dependents.batch_index
            )));
        }
    }
    source_pack_manifest_unique_usize_set(
        &execution_shard
            .jobs
            .iter()
            .map(|job| job.job_index)
            .collect::<Vec<_>>(),
        &format!("execution shard {} jobs", execution_shard.shard.shard_index),
    )?;
    source_pack_manifest_unique_usize_set(
        &execution_shard
            .job_artifacts
            .iter()
            .map(|job| job.job_index)
            .collect::<Vec<_>>(),
        &format!(
            "execution shard {} job artifacts",
            execution_shard.shard.shard_index
        ),
    )?;
    let execution_artifact_indices = source_pack_manifest_unique_usize_set(
        &execution_shard
            .artifact_refs
            .iter()
            .map(|artifact| artifact.artifact_index)
            .collect::<Vec<_>>(),
        &format!(
            "execution shard {} artifact refs",
            execution_shard.shard.shard_index
        ),
    )?;
    let shard_artifact_indices =
        source_pack_build_artifact_execution_shard_materialized_artifact_indices(
            &execution_shard.shard,
            mode,
        )?;
    if execution_artifact_indices != shard_artifact_indices {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "execution shard {} artifact refs {:?} do not match shard artifact refs {:?}",
            execution_shard.shard.shard_index, execution_artifact_indices, shard_artifact_indices
        )));
    }
    for job in &execution_shard.jobs {
        validate_source_pack_job_shape(
            job,
            &format!("execution shard {}", execution_shard.shard.shard_index),
            |message| source_pack_artifact_shard_contract_error(message),
        )?;
        if !execution_shard.shard.job_indices.contains(&job.job_index) {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "execution shard {} contains job {} outside shard job set {:?}",
                execution_shard.shard.shard_index, job.job_index, execution_shard.shard.job_indices
            )));
        }
    }
    for job_manifest in &execution_shard.job_artifacts {
        if !execution_shard
            .jobs
            .iter()
            .any(|job| job.job_index == job_manifest.job_index)
        {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "execution shard {} contains artifact manifest for missing job {}",
                execution_shard.shard.shard_index, job_manifest.job_index
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_build_artifact_execution_shard_materialized_artifact_indices(
    shard: &SourcePackBuildArtifactShard,
    mode: SourcePackBuildArtifactExecutionShardValidationMode,
) -> Result<BTreeSet<usize>, CompileError> {
    let mut artifact_indices = shard
        .input_artifact_indices
        .iter()
        .chain(shard.output_artifact_indices.iter())
        .copied()
        .collect::<BTreeSet<_>>();
    if mode == SourcePackBuildArtifactExecutionShardValidationMode::StoreInput {
        for range in &shard.input_artifact_ranges {
            let Some(indices) = range.iter() else {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "execution shard {} input artifact range starting at {} overflows",
                    shard.shard_index, range.first_artifact_index
                )));
            };
            artifact_indices.extend(indices);
        }
    }
    Ok(artifact_indices)
}

pub(in crate::compiler) fn source_pack_prune_persisted_execution_shard_artifact_refs(
    execution_shard: &mut SourcePackBuildArtifactExecutionShard,
) -> Result<(), CompileError> {
    let retained_artifact_indices =
        source_pack_build_artifact_execution_shard_materialized_artifact_indices(
            &execution_shard.shard,
            SourcePackBuildArtifactExecutionShardValidationMode::Persisted,
        )?;
    execution_shard
        .artifact_refs
        .retain(|artifact| retained_artifact_indices.contains(&artifact.artifact_index));
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_build_batch_shard_locator(
    locator: &SourcePackBuildBatchShardLocator,
    target: SourcePackArtifactTarget,
    batch_index: usize,
) -> Result<(), CompileError> {
    if locator.version != SOURCE_PACK_BUILD_BATCH_SHARD_LOCATOR_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack batch shard locator version {}; expected {}",
            locator.version, SOURCE_PACK_BUILD_BATCH_SHARD_LOCATOR_VERSION
        )));
    }
    if locator.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "batch shard locator target {:?} does not match requested target {:?}",
            locator.target, target
        )));
    }
    if locator.batch_index != batch_index {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "loaded batch shard locator for batch {} but requested batch {}",
            locator.batch_index, batch_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_build_job_batch_page_index(
    index: &SourcePackBuildJobBatchPageIndex,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if index.version != SOURCE_PACK_BUILD_JOB_BATCH_PAGE_INDEX_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack job-batch page index version {}; expected {}",
            index.version, SOURCE_PACK_BUILD_JOB_BATCH_PAGE_INDEX_VERSION
        )));
    }
    if index.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch page index target {:?} does not match requested target {:?}",
            index.target, target
        )));
    }
    if index.batch_count == 0 {
        return Err(source_pack_artifact_shard_contract_error(
            "job-batch page index has no batches",
        ));
    }
    if index.scheduled_job_count == 0 {
        return Err(source_pack_artifact_shard_contract_error(
            "job-batch page index has no scheduled jobs",
        ));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_build_job_batch_page(
    page: &SourcePackBuildJobBatchPage,
    target: SourcePackArtifactTarget,
    batch_index: Option<usize>,
) -> Result<(), CompileError> {
    validate_source_pack_build_job_batch_page_with_mode(
        page,
        target,
        batch_index,
        SourcePackBuildJobBatchPageValidationMode::Persisted,
    )
}

pub(in crate::compiler) fn validate_source_pack_build_job_batch_page_store_input(
    page: &SourcePackBuildJobBatchPage,
    target: SourcePackArtifactTarget,
    batch_index: Option<usize>,
) -> Result<(), CompileError> {
    validate_source_pack_build_job_batch_page_with_mode(
        page,
        target,
        batch_index,
        SourcePackBuildJobBatchPageValidationMode::StoreInput,
    )
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(in crate::compiler) enum SourcePackBuildJobBatchPageValidationMode {
    Persisted,
    StoreInput,
}

pub(in crate::compiler) fn validate_source_pack_build_job_batch_inline_record_count(
    page: &SourcePackBuildJobBatchPage,
    label: &str,
    count: usize,
    cap: usize,
    mode: SourcePackBuildJobBatchPageValidationMode,
) -> Result<(), CompileError> {
    if mode == SourcePackBuildJobBatchPageValidationMode::Persisted && count > cap {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch page {} stores {} inline {} records, exceeding record cap {}",
            page.batch_index, count, label, cap
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_build_job_batch_page_with_mode(
    page: &SourcePackBuildJobBatchPage,
    target: SourcePackArtifactTarget,
    batch_index: Option<usize>,
    mode: SourcePackBuildJobBatchPageValidationMode,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_BUILD_JOB_BATCH_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack job-batch page version {}; expected {}",
            page.version, SOURCE_PACK_BUILD_JOB_BATCH_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch page target {:?} does not match requested target {:?}",
            page.target, target
        )));
    }
    if let Some(batch_index) = batch_index {
        if page.batch_index != batch_index {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "loaded job-batch page {} but requested batch {}",
                page.batch_index, batch_index
            )));
        }
    }
    if page.batch.batch_index != page.batch_index {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch page {} contains batch record {}",
            page.batch_index, page.batch.batch_index
        )));
    }
    if page.dependency.batch_index != page.batch_index {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch page {} contains dependency record {}",
            page.batch_index, page.dependency.batch_index
        )));
    }
    if page.batch.job_indices.is_empty() {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch page {} has no jobs",
            page.batch_index
        )));
    }
    if page.batch.job_indices.len() > SOURCE_PACK_BUILD_JOB_BATCH_INLINE_JOB_DEFAULT_RECORD_CAP {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch page {} stores {} inline job records, exceeding record cap {}",
            page.batch_index,
            page.batch.job_indices.len(),
            SOURCE_PACK_BUILD_JOB_BATCH_INLINE_JOB_DEFAULT_RECORD_CAP
        )));
    }
    source_pack_manifest_unique_usize_set(
        &page.batch.job_indices,
        &format!("job-batch page {} jobs", page.batch_index),
    )?;
    validate_source_pack_build_job_batch_inline_record_count(
        page,
        "dependency",
        page.dependency.dependency_batch_indices.len(),
        SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE,
        mode,
    )?;
    validate_source_pack_build_job_batch_inline_record_count(
        page,
        "dependency range",
        page.dependency.dependency_batch_ranges.len(),
        SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE,
        mode,
    )?;
    let explicit_dependency_count = page.dependency.explicit_dependency_count();
    if !page.dependency.dependency_batch_indices.is_empty()
        && page.dependency.dependency_batch_count != 0
    {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch page {} records both inline and paged dependencies",
            page.batch_index
        )));
    }
    if page.dependency.dependency_batch_count == 0 {
        if page.dependency.dependency_page_count != 0 {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "job-batch page {} has dependency page count {} without dependencies",
                page.batch_index, page.dependency.dependency_page_count
            )));
        }
    } else {
        let expected_page_count = page
            .dependency
            .dependency_batch_count
            .div_ceil(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE);
        if page.dependency.dependency_page_count != expected_page_count {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "job-batch page {} has dependency page count {} but expected {} for {} dependencies",
                page.batch_index,
                page.dependency.dependency_page_count,
                expected_page_count,
                page.dependency.dependency_batch_count
            )));
        }
    }
    source_pack_validate_job_batch_dependency_range_metadata(
        &page.dependency,
        &format!("job-batch page {}", page.batch_index),
        |message| source_pack_artifact_shard_contract_error(message),
    )?;
    if !page.dependency.dependency_batch_indices.is_empty()
        && explicit_dependency_count > page.batch_index
    {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch page {} dependency count {} exceeds prior batch count {}",
            page.batch_index, explicit_dependency_count, page.batch_index
        )));
    }
    let explicit_dependencies = source_pack_manifest_unique_usize_set(
        &page.dependency.dependency_batch_indices,
        &format!("job-batch page {} dependencies", page.batch_index),
    )?;
    for &dependency_batch_index in &page.dependency.dependency_batch_indices {
        if dependency_batch_index >= page.batch_index {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "job-batch page {} depends on non-earlier batch {}",
                page.batch_index, dependency_batch_index
            )));
        }
    }
    source_pack_validate_job_batch_dependency_ranges(
        &page.dependency,
        &explicit_dependencies,
        &format!("job-batch page {}", page.batch_index),
        page.batch_index,
        None,
        |message| source_pack_artifact_shard_contract_error(message),
    )?;
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_build_job_batch_dependency_page(
    page: &SourcePackBuildJobBatchDependencyPage,
    target: SourcePackArtifactTarget,
    expected_batch_index: usize,
    expected_page_index: usize,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack job-batch dependency page version {}; expected {}",
            page.version, SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependency page target {:?} does not match requested target {:?}",
            page.target, target
        )));
    }
    if page.batch_index != expected_batch_index {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "loaded job-batch dependency page for batch {} but requested batch {}",
            page.batch_index, expected_batch_index
        )));
    }
    if page.page_index != expected_page_index {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "loaded job-batch dependency page {} for batch {} but expected page {}",
            page.page_index, page.batch_index, expected_page_index
        )));
    }
    let expected_first_position = expected_page_index
        .saturating_mul(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE);
    if page.first_dependency_position != expected_first_position {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependency page {} for batch {} starts at {} but expected {}",
            page.page_index,
            page.batch_index,
            page.first_dependency_position,
            expected_first_position
        )));
    }
    if page.dependency_count != page.dependency_batch_indices.len() {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependency page {} for batch {} records {} dependencies but stores {}",
            page.page_index,
            page.batch_index,
            page.dependency_count,
            page.dependency_batch_indices.len()
        )));
    }
    if page.dependency_count > SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependency page {} for batch {} exceeds page size {}",
            page.page_index,
            page.batch_index,
            SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE
        )));
    }
    source_pack_manifest_unique_usize_set(
        &page.dependency_batch_indices,
        &format!(
            "job-batch dependency page {} for batch {} dependencies",
            page.page_index, page.batch_index
        ),
    )?;
    for &dependency_batch_index in &page.dependency_batch_indices {
        if dependency_batch_index >= page.batch_index {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "job-batch dependency page {} for batch {} has invalid dependency batch {}",
                page.page_index, page.batch_index, dependency_batch_index
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_build_job_batch_dependency_range_page(
    page: &SourcePackBuildJobBatchDependencyRangePage,
    target: SourcePackArtifactTarget,
    expected_batch_index: usize,
    expected_page_index: usize,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack job-batch dependency range page version {}; expected {}",
            page.version, SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependency range page target {:?} does not match requested target {:?}",
            page.target, target
        )));
    }
    if page.batch_index != expected_batch_index {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "loaded job-batch dependency range page for batch {} but requested batch {}",
            page.batch_index, expected_batch_index
        )));
    }
    if page.page_index != expected_page_index {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "loaded job-batch dependency range page {} for batch {} but expected page {}",
            page.page_index, page.batch_index, expected_page_index
        )));
    }
    let expected_first_position = expected_page_index
        .saturating_mul(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE);
    if page.first_range_position != expected_first_position {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependency range page {} for batch {} starts at {} but expected {}",
            page.page_index, page.batch_index, page.first_range_position, expected_first_position
        )));
    }
    if page.range_count != page.dependency_batch_ranges.len() {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependency range page {} for batch {} records {} ranges but stores {}",
            page.page_index,
            page.batch_index,
            page.range_count,
            page.dependency_batch_ranges.len()
        )));
    }
    if page.range_count > SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependency range page {} for batch {} exceeds page size {}",
            page.page_index,
            page.batch_index,
            SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE
        )));
    }
    let dependency_batch_count = page
        .dependency_batch_ranges
        .iter()
        .fold(0usize, |count, range| {
            count.saturating_add(range.batch_count)
        });
    if page.dependency_batch_count != dependency_batch_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependency range page {} for batch {} records {} dependency batches but ranges sum to {}",
            page.page_index, page.batch_index, page.dependency_batch_count, dependency_batch_count
        )));
    }
    let dependency = SourcePackJobBatchDependency {
        batch_index: page.batch_index,
        dependency_batch_count: 0,
        dependency_page_count: 0,
        dependency_range_count: 0,
        dependency_range_page_count: 0,
        dependency_range_batch_count: 0,
        dependency_batch_indices: Vec::new(),
        dependency_batch_ranges: page.dependency_batch_ranges.clone(),
    };
    source_pack_validate_job_batch_dependency_ranges(
        &dependency,
        &BTreeSet::new(),
        &format!(
            "job-batch dependency range page {} for batch {}",
            page.page_index, page.batch_index
        ),
        page.batch_index,
        None,
        |message| source_pack_artifact_shard_contract_error(message),
    )?;
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_build_job_batch_job_locator_page(
    page: &SourcePackBuildJobBatchJobLocatorPage,
    target: SourcePackArtifactTarget,
    scheduled_job_count: usize,
    expected_job_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_BUILD_JOB_BATCH_JOB_LOCATOR_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack job-batch job-locator page version {}; expected {}",
            page.version, SOURCE_PACK_BUILD_JOB_BATCH_JOB_LOCATOR_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch job-locator page target {:?} does not match requested target {:?}",
            page.target, target
        )));
    }
    if let Some(expected_job_index) = expected_job_index {
        if page.job_index != expected_job_index {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "loaded job-batch job-locator page {} but requested job {}",
                page.job_index, expected_job_index
            )));
        }
    }
    if page.job_index >= scheduled_job_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch job-locator page {} exceeds scheduled job count {}",
            page.job_index, scheduled_job_count
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_build_job_batch_dependents_page(
    page: &SourcePackBuildJobBatchDependentsPage,
    target: SourcePackArtifactTarget,
    batch_count: usize,
    expected_batch_index: Option<usize>,
) -> Result<(), CompileError> {
    validate_source_pack_build_job_batch_dependents_page_with_mode(
        page,
        target,
        batch_count,
        expected_batch_index,
        SourcePackBuildJobBatchDependentsPageValidationMode::Persisted,
    )
}

pub(in crate::compiler) fn validate_source_pack_build_job_batch_dependents_page_store_input(
    page: &SourcePackBuildJobBatchDependentsPage,
    target: SourcePackArtifactTarget,
    batch_count: usize,
    expected_batch_index: Option<usize>,
) -> Result<(), CompileError> {
    validate_source_pack_build_job_batch_dependents_page_with_mode(
        page,
        target,
        batch_count,
        expected_batch_index,
        SourcePackBuildJobBatchDependentsPageValidationMode::StoreInput,
    )
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(in crate::compiler) enum SourcePackBuildJobBatchDependentsPageValidationMode {
    Persisted,
    StoreInput,
}

pub(in crate::compiler) fn validate_source_pack_build_job_batch_dependents_inline_record_count(
    page: &SourcePackBuildJobBatchDependentsPage,
    label: &str,
    count: usize,
    cap: usize,
    mode: SourcePackBuildJobBatchDependentsPageValidationMode,
) -> Result<(), CompileError> {
    if mode == SourcePackBuildJobBatchDependentsPageValidationMode::Persisted && count > cap {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependents page {} stores {} inline {} records, exceeding record cap {}",
            page.batch_index, count, label, cap
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_build_job_batch_dependents_page_with_mode(
    page: &SourcePackBuildJobBatchDependentsPage,
    target: SourcePackArtifactTarget,
    batch_count: usize,
    expected_batch_index: Option<usize>,
    mode: SourcePackBuildJobBatchDependentsPageValidationMode,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack job-batch dependents page version {}; expected {}",
            page.version, SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependents page target {:?} does not match requested target {:?}",
            page.target, target
        )));
    }
    if page.batch_count != batch_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependents page {} has batch count {} but expected {}",
            page.batch_index, page.batch_count, batch_count
        )));
    }
    if let Some(expected_batch_index) = expected_batch_index {
        if page.batch_index != expected_batch_index {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "loaded job-batch dependents page {} but requested batch {}",
                page.batch_index, expected_batch_index
            )));
        }
    }
    if page.batch_index >= batch_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependents page {} exceeds batch count {}",
            page.batch_index, batch_count
        )));
    }
    if page.dependents.batch_index != page.batch_index {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependents page {} contains dependent record {}",
            page.batch_index, page.dependents.batch_index
        )));
    }
    validate_source_pack_build_job_batch_dependents_inline_record_count(
        page,
        "dependent",
        page.dependents.dependent_batch_indices.len(),
        SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE,
        mode,
    )?;
    source_pack_manifest_unique_usize_set(
        &page.dependents.dependent_batch_indices,
        &format!("job-batch dependents page {} dependents", page.batch_index),
    )?;
    for &dependent_batch_index in &page.dependents.dependent_batch_indices {
        if dependent_batch_index >= batch_count {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "job-batch dependents page {} references missing dependent batch {}",
                page.batch_index, dependent_batch_index
            )));
        }
        if dependent_batch_index == page.batch_index {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "job-batch dependents page {} lists itself as a dependent",
                page.batch_index
            )));
        }
    }
    if !page.dependents.dependent_batch_indices.is_empty() && page.dependent_batch_count != 0 {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependents page {} records both inline and paged dependents",
            page.batch_index
        )));
    }
    if page.dependent_batch_count == 0 {
        if page.dependent_page_count != 0 {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "job-batch dependents page {} has dependent page count {} without dependents",
                page.batch_index, page.dependent_page_count
            )));
        }
    } else {
        let expected_page_count = page
            .dependent_batch_count
            .div_ceil(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE);
        if page.dependent_page_count != expected_page_count {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "job-batch dependents page {} has dependent page count {} but expected {} for {} dependents",
                page.batch_index,
                page.dependent_page_count,
                expected_page_count,
                page.dependent_batch_count
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_build_job_batch_dependent_batch_page(
    page: &SourcePackBuildJobBatchDependentBatchPage,
    target: SourcePackArtifactTarget,
    batch_count: usize,
    expected_batch_index: usize,
    expected_page_index: usize,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENT_BATCH_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack job-batch dependent-batch page version {}; expected {}",
            page.version, SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENT_BATCH_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependent-batch page target {:?} does not match requested target {:?}",
            page.target, target
        )));
    }
    if page.batch_count != batch_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependent-batch page {} for batch {} has batch count {} but expected {}",
            page.page_index, page.batch_index, page.batch_count, batch_count
        )));
    }
    if page.batch_index != expected_batch_index {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "loaded job-batch dependent-batch page for batch {} but requested batch {}",
            page.batch_index, expected_batch_index
        )));
    }
    if page.batch_index >= batch_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependent-batch page {} exceeds batch count {}",
            page.batch_index, batch_count
        )));
    }
    if page.page_index != expected_page_index {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "loaded job-batch dependent-batch page {} for batch {} but expected page {}",
            page.page_index, page.batch_index, expected_page_index
        )));
    }
    let expected_first_position = expected_page_index
        .saturating_mul(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE);
    if page.first_dependent_position != expected_first_position {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependent-batch page {} for batch {} starts at {} but expected {}",
            page.page_index,
            page.batch_index,
            page.first_dependent_position,
            expected_first_position
        )));
    }
    if page.dependent_count != page.dependent_batch_indices.len() {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependent-batch page {} for batch {} records {} dependents but stores {}",
            page.page_index,
            page.batch_index,
            page.dependent_count,
            page.dependent_batch_indices.len()
        )));
    }
    if page.dependent_count > SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependent-batch page {} for batch {} exceeds page size {}",
            page.page_index,
            page.batch_index,
            SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE
        )));
    }
    source_pack_manifest_unique_usize_set(
        &page.dependent_batch_indices,
        &format!(
            "job-batch dependent-batch page {} for batch {} dependents",
            page.page_index, page.batch_index
        ),
    )?;
    for &dependent_batch_index in &page.dependent_batch_indices {
        if dependent_batch_index >= batch_count {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "job-batch dependent-batch page {} for batch {} references missing dependent batch {}",
                page.page_index, page.batch_index, dependent_batch_index
            )));
        }
        if dependent_batch_index == page.batch_index {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "job-batch dependent-batch page {} for batch {} lists itself as a dependent",
                page.page_index, page.batch_index
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_build_artifact_ref_index(
    index: &SourcePackBuildArtifactRefIndex,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if index.version != SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack artifact-ref index version {}; expected {}",
            index.version, SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION
        )));
    }
    if index.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-ref index target {:?} does not match requested target {:?}",
            index.target, target
        )));
    }
    if index.artifact_count == 0 {
        return Err(source_pack_artifact_shard_contract_error(
            "artifact-ref index has no artifacts",
        ));
    }
    let expected_artifact_count = index
        .interface_artifact_count
        .saturating_add(index.object_artifact_count)
        .saturating_add(1);
    if index.artifact_count != expected_artifact_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-ref index artifact_count {} does not match interface {} + object {} + final output",
            index.artifact_count, index.interface_artifact_count, index.object_artifact_count
        )));
    }
    if index.final_output_artifact_index >= index.artifact_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-ref index final output artifact {} exceeds artifact_count {}",
            index.final_output_artifact_index, index.artifact_count
        )));
    }
    if index.final_output_artifact_index != index.artifact_count - 1 {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-ref index final output artifact {} is not the dense final artifact {}",
            index.final_output_artifact_index,
            index.artifact_count - 1
        )));
    }
    if index.final_output_key.is_empty() {
        return Err(source_pack_artifact_shard_contract_error(
            "artifact-ref index final output key is empty",
        ));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_build_artifact_ref_page(
    page: &SourcePackBuildArtifactRefPage,
    target: SourcePackArtifactTarget,
    artifact_count: usize,
    expected_artifact_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_BUILD_ARTIFACT_REF_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack artifact-ref page version {}; expected {}",
            page.version, SOURCE_PACK_BUILD_ARTIFACT_REF_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-ref page target {:?} does not match requested target {:?}",
            page.target, target
        )));
    }
    if let Some(expected_artifact_index) = expected_artifact_index {
        if page.artifact_index != expected_artifact_index {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "loaded artifact-ref page {} but requested artifact {}",
                page.artifact_index, expected_artifact_index
            )));
        }
    }
    if page.artifact_index >= artifact_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-ref page {} exceeds artifact_count {}",
            page.artifact_index, artifact_count
        )));
    }
    if page.artifact_ref.artifact_index != page.artifact_index {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-ref page {} contains artifact ref {}",
            page.artifact_index, page.artifact_ref.artifact_index
        )));
    }
    if page.artifact_ref.producing_job_index != page.artifact_index {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-ref page {} is produced by job {}",
            page.artifact_index, page.artifact_ref.producing_job_index
        )));
    }
    if page.artifact_ref.key.is_empty() {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-ref page {} has an empty artifact key",
            page.artifact_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_job_artifact_input_interface_page(
    page: &SourcePackJobArtifactInputInterfacePage,
    target: SourcePackArtifactTarget,
    expected_job_index: usize,
    expected_page_index: usize,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack job artifact input interface page version {}; expected {}",
            page.version, SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job artifact input interface page {}:{} target {:?} does not match requested target {:?}",
            page.job_index, page.page_index, page.target, target
        )));
    }
    if page.job_index != expected_job_index || page.page_index != expected_page_index {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "loaded job artifact input interface page {}:{} but expected {}:{}",
            page.job_index, page.page_index, expected_job_index, expected_page_index
        )));
    }
    let expected_first_input_position = expected_page_index
        .saturating_mul(SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE);
    if page.first_input_position != expected_first_input_position {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job artifact input interface page {}:{} starts at {} but expected {}",
            page.job_index,
            page.page_index,
            page.first_input_position,
            expected_first_input_position
        )));
    }
    if page.input_count != page.input_interfaces.len() {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job artifact input interface page {}:{} count {} does not match {} refs",
            page.job_index,
            page.page_index,
            page.input_count,
            page.input_interfaces.len()
        )));
    }
    if page.input_count == 0
        || page.input_count > SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE
    {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job artifact input interface page {}:{} has invalid input count {}",
            page.job_index, page.page_index, page.input_count
        )));
    }
    validate_source_pack_hierarchical_link_execution_artifact_refs(
        &page.input_interfaces,
        SourcePackArtifactKind::LibraryInterface,
        target,
        page.job_index,
        &format!(
            "job artifact input interface page {}:{} inputs",
            page.job_index, page.page_index
        ),
    )?;
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_build_link_batch_page_index(
    index: &SourcePackBuildLinkBatchPageIndex,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if index.version != SOURCE_PACK_BUILD_LINK_BATCH_PAGE_INDEX_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack link-batch page index version {}; expected {}",
            index.version, SOURCE_PACK_BUILD_LINK_BATCH_PAGE_INDEX_VERSION
        )));
    }
    if index.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "link-batch page index target {:?} does not match requested target {:?}",
            index.target, target
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_build_link_interface_batch_page(
    page: &SourcePackBuildLinkInterfaceBatchPage,
    target: SourcePackArtifactTarget,
    batch_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_BUILD_LINK_INTERFACE_BATCH_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack link-interface batch page version {}; expected {}",
            page.version, SOURCE_PACK_BUILD_LINK_INTERFACE_BATCH_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "link-interface batch page target {:?} does not match requested target {:?}",
            page.target, target
        )));
    }
    if let Some(batch_index) = batch_index {
        if page.batch_index != batch_index {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "loaded link-interface batch page {} but requested batch {}",
                page.batch_index, batch_index
            )));
        }
    }
    if page.batch.batch_index != page.batch_index {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "link-interface batch page {} contains batch record {}",
            page.batch_index, page.batch.batch_index
        )));
    }
    if page.batch.input_interface_artifact_indices.is_empty() {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "link-interface batch page {} has no input artifacts",
            page.batch_index
        )));
    }
    if page.batch.input_interface_artifact_indices.len()
        > SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE
    {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "link-interface batch page {} has {} input artifacts but the page limit is {}",
            page.batch_index,
            page.batch.input_interface_artifact_indices.len(),
            SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE
        )));
    }
    source_pack_manifest_unique_usize_set(
        &page.batch.input_interface_artifact_indices,
        &format!("link-interface batch page {} inputs", page.batch_index),
    )?;
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_build_link_object_batch_page(
    page: &SourcePackBuildLinkObjectBatchPage,
    target: SourcePackArtifactTarget,
    batch_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_BUILD_LINK_OBJECT_BATCH_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack link-object batch page version {}; expected {}",
            page.version, SOURCE_PACK_BUILD_LINK_OBJECT_BATCH_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "link-object batch page target {:?} does not match requested target {:?}",
            page.target, target
        )));
    }
    if let Some(batch_index) = batch_index {
        if page.batch_index != batch_index {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "loaded link-object batch page {} but requested batch {}",
                page.batch_index, batch_index
            )));
        }
    }
    if page.batch.batch_index != page.batch_index {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "link-object batch page {} contains batch record {}",
            page.batch_index, page.batch.batch_index
        )));
    }
    if page.batch.input_object_artifact_indices.is_empty() {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "link-object batch page {} has no input artifacts",
            page.batch_index
        )));
    }
    if page.batch.input_object_artifact_indices.len()
        > SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE
    {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "link-object batch page {} has {} input artifacts but the page limit is {}",
            page.batch_index,
            page.batch.input_object_artifact_indices.len(),
            SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE
        )));
    }
    source_pack_manifest_unique_usize_set(
        &page.batch.input_object_artifact_indices,
        &format!("link-object batch page {} inputs", page.batch_index),
    )?;
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_build_link_input_shard_index(
    index: &SourcePackBuildLinkInputShardIndex,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if index.version != SOURCE_PACK_BUILD_LINK_INPUT_SHARD_INDEX_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack link input shard index version {}; expected {}",
            index.version, SOURCE_PACK_BUILD_LINK_INPUT_SHARD_INDEX_VERSION
        )));
    }
    if index.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "link input shard index target {:?} does not match requested target {:?}",
            index.target, target
        )));
    }
    source_pack_validate_link_input_shard_range(
        index.link_interface_shard_range.as_ref(),
        "interface",
    )?;
    source_pack_validate_link_input_shard_range(index.link_object_shard_range.as_ref(), "object")?;
    if let (Some(interface_range), Some(object_range)) = (
        &index.link_interface_shard_range,
        &index.link_object_shard_range,
    ) {
        let interface_end = interface_range.end_shard_index().ok_or_else(|| {
            source_pack_artifact_shard_contract_error("interface link input shard range overflows")
        })?;
        let object_end = object_range.end_shard_index().ok_or_else(|| {
            source_pack_artifact_shard_contract_error("object link input shard range overflows")
        })?;
        if interface_range.first_shard_index < object_end
            && object_range.first_shard_index < interface_end
        {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "link input shard interface range {}..{} overlaps object range {}..{}",
                interface_range.first_shard_index,
                interface_end,
                object_range.first_shard_index,
                object_end
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_validate_link_input_shard_range(
    range: Option<&SourcePackLinkInputShardRange>,
    label: &str,
) -> Result<(), CompileError> {
    let Some(range) = range else {
        return Ok(());
    };
    if range.shard_count == 0 {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "{label} link input shard range is empty"
        )));
    }
    if range.end_shard_index().is_none() {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "{label} link input shard range overflows"
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_for_each_link_input_shard_index<F>(
    index: &SourcePackBuildLinkInputShardIndex,
    kind: SourcePackBuildArtifactShardKind,
    mut visit: F,
) -> Result<(), CompileError>
where
    F: FnMut(usize) -> Result<(), CompileError>,
{
    let (range, label) = match kind {
        SourcePackBuildArtifactShardKind::LinkInterfaceBatches => {
            (index.link_interface_shard_range.as_ref(), "interface")
        }
        SourcePackBuildArtifactShardKind::LinkObjectBatches => {
            (index.link_object_shard_range.as_ref(), "object")
        }
        SourcePackBuildArtifactShardKind::JobBatches => {
            return Err(source_pack_artifact_shard_contract_error(
                "job-batch shards are not link-input shards",
            ));
        }
    };
    if let Some(range) = range {
        let Some(indices) = range.iter() else {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "{label} link input shard range overflows"
            )));
        };
        for shard_index in indices {
            visit(shard_index)?;
        }
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_link_input_shard_index_contains_kind(
    index: &SourcePackBuildLinkInputShardIndex,
    kind: SourcePackBuildArtifactShardKind,
    shard_index: usize,
) -> bool {
    match kind {
        SourcePackBuildArtifactShardKind::LinkInterfaceBatches => index
            .link_interface_shard_range
            .as_ref()
            .is_some_and(|range| range.contains(shard_index)),
        SourcePackBuildArtifactShardKind::LinkObjectBatches => index
            .link_object_shard_range
            .as_ref()
            .is_some_and(|range| range.contains(shard_index)),
        SourcePackBuildArtifactShardKind::JobBatches => false,
    }
}

pub(in crate::compiler) fn validate_source_pack_build_artifact_manifest_contract(
    manifest: &SourcePackBuildArtifactManifest,
) -> Result<(), CompileError> {
    let job_count = manifest.job_count;
    let artifact_count = manifest.artifact_count;
    if job_count == 0 {
        return Err(source_pack_manifest_contract_error(
            "artifact manifest has no jobs",
        ));
    }
    if manifest.job_batch_count == 0 {
        return Err(source_pack_manifest_contract_error(
            "artifact manifest has no job batches",
        ));
    }
    if artifact_count == 0 {
        return Err(source_pack_manifest_contract_error(
            "artifact manifest has no artifacts",
        ));
    }
    if manifest.batch_dependency_count != manifest.job_batch_count {
        return Err(source_pack_manifest_contract_error(format!(
            "artifact manifest records {} batch dependencies but {} job batches",
            manifest.batch_dependency_count, manifest.job_batch_count
        )));
    }
    if manifest.job_artifact_count != job_count {
        return Err(source_pack_manifest_contract_error(format!(
            "artifact manifest records {} job artifact manifests but {} jobs",
            manifest.job_artifact_count, job_count
        )));
    }
    if manifest.job_artifact_io_count != job_count {
        return Err(source_pack_manifest_contract_error(format!(
            "artifact manifest records {} job artifact-io records but {} jobs",
            manifest.job_artifact_io_count, job_count
        )));
    }
    if manifest.artifact_use_count != artifact_count {
        return Err(source_pack_manifest_contract_error(format!(
            "artifact manifest records {} artifact uses but {} artifacts",
            manifest.artifact_use_count, artifact_count
        )));
    }

    let has_record_arrays = !manifest.job_schedule.jobs.is_empty()
        || !manifest.job_batches.batches.is_empty()
        || !manifest.batch_dependencies.batches.is_empty()
        || !manifest.artifacts.artifacts.is_empty()
        || !manifest.job_artifacts.jobs.is_empty()
        || !manifest.job_artifact_io.jobs.is_empty()
        || !manifest.artifact_uses.uses.is_empty()
        || !manifest.link_interface_batches.batches.is_empty()
        || !manifest.link_object_batches.batches.is_empty();
    if !has_record_arrays {
        return Ok(());
    }
    if manifest.job_schedule.jobs.len() != job_count {
        return Err(source_pack_manifest_contract_error(format!(
            "artifact manifest has {} job records but job_count {}",
            manifest.job_schedule.jobs.len(),
            job_count
        )));
    }
    if manifest.job_batches.batches.len() != manifest.job_batch_count {
        return Err(source_pack_manifest_contract_error(format!(
            "artifact manifest has {} job-batch records but job_batch_count {}",
            manifest.job_batches.batches.len(),
            manifest.job_batch_count
        )));
    }
    if manifest.batch_dependencies.batches.len() != manifest.batch_dependency_count {
        return Err(source_pack_manifest_contract_error(format!(
            "artifact manifest has {} batch-dependency records but batch_dependency_count {}",
            manifest.batch_dependencies.batches.len(),
            manifest.batch_dependency_count
        )));
    }
    if manifest.artifacts.artifacts.len() != artifact_count {
        return Err(source_pack_manifest_contract_error(format!(
            "artifact manifest has {} artifact records but artifact_count {}",
            manifest.artifacts.artifacts.len(),
            artifact_count
        )));
    }
    if manifest.job_artifacts.jobs.len() != manifest.job_artifact_count {
        return Err(source_pack_manifest_contract_error(format!(
            "artifact manifest has {} job-artifact records but job_artifact_count {}",
            manifest.job_artifacts.jobs.len(),
            manifest.job_artifact_count
        )));
    }
    if manifest.job_artifact_io.jobs.len() != manifest.job_artifact_io_count {
        return Err(source_pack_manifest_contract_error(format!(
            "artifact manifest has {} job-artifact-io records but job_artifact_io_count {}",
            manifest.job_artifact_io.jobs.len(),
            manifest.job_artifact_io_count
        )));
    }
    if manifest.artifact_uses.uses.len() != manifest.artifact_use_count {
        return Err(source_pack_manifest_contract_error(format!(
            "artifact manifest has {} artifact-use records but artifact_use_count {}",
            manifest.artifact_uses.uses.len(),
            manifest.artifact_use_count
        )));
    }
    if manifest.link_interface_batches.batches.len() != manifest.link_interface_batch_count {
        return Err(source_pack_manifest_contract_error(format!(
            "artifact manifest has {} link-interface batch records but link_interface_batch_count {}",
            manifest.link_interface_batches.batches.len(),
            manifest.link_interface_batch_count
        )));
    }
    if manifest.link_object_batches.batches.len() != manifest.link_object_batch_count {
        return Err(source_pack_manifest_contract_error(format!(
            "artifact manifest has {} link-object batch records but link_object_batch_count {}",
            manifest.link_object_batches.batches.len(),
            manifest.link_object_batch_count
        )));
    }

    let mut link_job_indices = Vec::new();

    for (job_position, job) in manifest.job_schedule.jobs.iter().enumerate() {
        if job.job_index != job_position {
            return Err(source_pack_manifest_contract_error(format!(
                "job schedule entry {job_position} has job_index {}",
                job.job_index
            )));
        }
        if job.phase == SourcePackJobPhase::Link {
            link_job_indices.push(job.job_index);
        }
        let explicit_dependencies = source_pack_manifest_unique_usize_set(
            &job.dependency_job_indices,
            &format!("job {} dependencies", job.job_index),
        )?;
        source_pack_validate_job_dependency_ranges(
            manifest.job_schedule.dependency_job_ranges_for_job(job),
            &explicit_dependencies,
            &format!("job {}", job.job_index),
            job_count,
            |message| source_pack_manifest_contract_error(message),
        )?;
        for &dependency_job_index in &job.dependency_job_indices {
            if dependency_job_index >= job_count {
                return Err(source_pack_manifest_contract_error(format!(
                    "job {} depends on missing job {}",
                    job.job_index, dependency_job_index
                )));
            }
            if dependency_job_index == job.job_index {
                return Err(source_pack_manifest_contract_error(format!(
                    "job {} depends on itself",
                    job.job_index
                )));
            }
        }
        for dependency_job_range in manifest.job_schedule.dependency_job_ranges_for_job(job) {
            if dependency_job_range.contains(job.job_index) {
                return Err(source_pack_manifest_contract_error(format!(
                    "job {} dependency range contains itself",
                    job.job_index
                )));
            }
        }
    }

    if link_job_indices.len() != 1 {
        return Err(source_pack_manifest_contract_error(format!(
            "expected exactly one link job, found {}",
            link_job_indices.len()
        )));
    }
    let link_job_index = link_job_indices[0];

    let mut output_artifact_indices_by_job = vec![Vec::new(); job_count];
    let mut linked_output_artifact_count = 0usize;
    for (artifact_position, artifact) in manifest.artifacts.artifacts.iter().enumerate() {
        if artifact.artifact_index != artifact_position {
            return Err(source_pack_manifest_contract_error(format!(
                "artifact entry {artifact_position} has artifact_index {}",
                artifact.artifact_index
            )));
        }
        validate_source_pack_manifest_artifact_key(
            manifest.target,
            &artifact.key,
            &format!("artifact {}", artifact.artifact_index),
        )?;
        let Some(producer_job) = manifest.job_schedule.jobs.get(artifact.producing_job_index)
        else {
            return Err(source_pack_manifest_contract_error(format!(
                "artifact {} is produced by missing job {}",
                artifact.artifact_index, artifact.producing_job_index
            )));
        };
        let expected_kind = match producer_job.phase {
            SourcePackJobPhase::LibraryFrontend => SourcePackArtifactKind::LibraryInterface,
            SourcePackJobPhase::Codegen => SourcePackArtifactKind::CodegenObject,
            SourcePackJobPhase::Link => SourcePackArtifactKind::LinkedOutput,
        };
        if artifact.kind != expected_kind {
            return Err(source_pack_manifest_contract_error(format!(
                "artifact {} kind {:?} does not match producer job {} phase {:?}",
                artifact.artifact_index, artifact.kind, producer_job.job_index, producer_job.phase
            )));
        }
        if artifact.kind == SourcePackArtifactKind::LinkedOutput {
            linked_output_artifact_count += 1;
        }
        output_artifact_indices_by_job[artifact.producing_job_index].push(artifact.artifact_index);
    }

    if linked_output_artifact_count != 1 {
        return Err(source_pack_manifest_contract_error(format!(
            "expected exactly one linked output artifact, found {linked_output_artifact_count}"
        )));
    }

    let job_to_batch = validate_source_pack_manifest_job_batches(manifest, job_count)?;
    validate_source_pack_manifest_batch_dependencies(manifest, &job_to_batch)?;

    let mut actual_artifact_consumers = vec![BTreeSet::new(); artifact_count];
    validate_source_pack_manifest_job_artifacts(
        manifest,
        &output_artifact_indices_by_job,
        &mut actual_artifact_consumers,
    )?;
    validate_source_pack_manifest_job_artifact_io(manifest)?;
    validate_source_pack_manifest_artifact_uses(manifest, &actual_artifact_consumers)?;
    validate_source_pack_manifest_link_batches(manifest, link_job_index)?;

    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_manifest_job_batches(
    manifest: &SourcePackBuildArtifactManifest,
    job_count: usize,
) -> Result<Vec<usize>, CompileError> {
    let mut job_to_batch = vec![None; job_count];
    for (batch_position, batch) in manifest.job_batches.batches.iter().enumerate() {
        if batch.batch_index != batch_position {
            return Err(source_pack_manifest_contract_error(format!(
                "job batch entry {batch_position} has batch_index {}",
                batch.batch_index
            )));
        }
        source_pack_manifest_unique_usize_set(
            &batch.job_indices,
            &format!("job batch {} jobs", batch.batch_index),
        )?;
        let mut source_bytes = 0usize;
        let mut source_file_count = 0usize;
        for &job_index in &batch.job_indices {
            let Some(job) = manifest.job_schedule.jobs.get(job_index) else {
                return Err(source_pack_manifest_contract_error(format!(
                    "job batch {} references missing job {}",
                    batch.batch_index, job_index
                )));
            };
            if job_to_batch[job_index].replace(batch.batch_index).is_some() {
                return Err(source_pack_manifest_contract_error(format!(
                    "job {job_index} appears in more than one batch"
                )));
            }
            source_bytes = source_bytes.saturating_add(job.source_bytes);
            source_file_count = source_file_count.saturating_add(job.source_file_count);
        }
        if batch.source_bytes != source_bytes {
            return Err(source_pack_manifest_contract_error(format!(
                "job batch {} records {} source bytes but its jobs sum to {}",
                batch.batch_index, batch.source_bytes, source_bytes
            )));
        }
        if batch.source_file_count != source_file_count {
            return Err(source_pack_manifest_contract_error(format!(
                "job batch {} records {} source files but its jobs sum to {}",
                batch.batch_index, batch.source_file_count, source_file_count
            )));
        }
    }

    let mut dense_job_to_batch = Vec::with_capacity(job_count);
    for (job_index, batch_index) in job_to_batch.into_iter().enumerate() {
        let Some(batch_index) = batch_index else {
            return Err(source_pack_manifest_contract_error(format!(
                "job {job_index} does not appear in any batch"
            )));
        };
        dense_job_to_batch.push(batch_index);
    }
    Ok(dense_job_to_batch)
}

pub(in crate::compiler) fn validate_source_pack_manifest_batch_dependencies(
    manifest: &SourcePackBuildArtifactManifest,
    job_to_batch: &[usize],
) -> Result<(), CompileError> {
    let batch_count = manifest.job_batches.batches.len();
    if manifest.batch_dependencies.batches.len() != batch_count {
        return Err(source_pack_manifest_contract_error(format!(
            "batch dependency plan has {} batches but job batch schedule has {}",
            manifest.batch_dependencies.batches.len(),
            batch_count
        )));
    }

    for (batch_position, dependency) in manifest.batch_dependencies.batches.iter().enumerate() {
        if dependency.batch_index != batch_position {
            return Err(source_pack_manifest_contract_error(format!(
                "batch dependency entry {batch_position} has batch_index {}",
                dependency.batch_index
            )));
        }
        let mut listed = source_pack_manifest_unique_usize_set(
            &dependency.dependency_batch_indices,
            &format!("batch {} dependencies", dependency.batch_index),
        )?;
        for &dependency_batch_index in &dependency.dependency_batch_indices {
            if dependency_batch_index >= batch_count {
                return Err(source_pack_manifest_contract_error(format!(
                    "batch {} depends on missing batch {}",
                    dependency.batch_index, dependency_batch_index
                )));
            }
            if dependency_batch_index == dependency.batch_index {
                return Err(source_pack_manifest_contract_error(format!(
                    "batch {} depends on itself",
                    dependency.batch_index
                )));
            }
        }
        source_pack_validate_job_batch_dependency_ranges(
            dependency,
            &listed,
            &format!("batch {}", dependency.batch_index),
            batch_count,
            Some(dependency.batch_index),
            |message| source_pack_manifest_contract_error(message),
        )?;
        for range in &dependency.dependency_batch_ranges {
            let Some(indices) = range.iter() else {
                return Err(source_pack_manifest_contract_error(format!(
                    "batch {} dependency range starting at {} overflows usize",
                    dependency.batch_index, range.first_batch_index
                )));
            };
            listed.extend(indices);
        }

        let batch = &manifest.job_batches.batches[dependency.batch_index];
        let mut expected = BTreeSet::new();
        for &job_index in &batch.job_indices {
            let job = &manifest.job_schedule.jobs[job_index];
            for &dependency_job_index in &job.dependency_job_indices {
                let dependency_batch_index = job_to_batch[dependency_job_index];
                if dependency_batch_index != dependency.batch_index {
                    expected.insert(dependency_batch_index);
                }
            }
            for dependency_job_range in manifest.job_schedule.dependency_job_ranges_for_job(job) {
                let Some(dependency_job_indices) = dependency_job_range.iter() else {
                    return Err(source_pack_manifest_contract_error(format!(
                        "job {} dependency range starting at {} overflows usize",
                        job.job_index, dependency_job_range.first_job_index
                    )));
                };
                for dependency_job_index in dependency_job_indices {
                    let dependency_batch_index = job_to_batch[dependency_job_index];
                    if dependency_batch_index != dependency.batch_index {
                        expected.insert(dependency_batch_index);
                    }
                }
            }
            if job.phase == SourcePackJobPhase::Link
                && job.dependency_job_indices.is_empty()
                && manifest
                    .job_schedule
                    .dependency_job_ranges_for_job(job)
                    .is_empty()
            {
                for codegen_job in manifest
                    .job_schedule
                    .jobs
                    .iter()
                    .filter(|job| job.phase == SourcePackJobPhase::Codegen)
                {
                    let dependency_batch_index = job_to_batch[codegen_job.job_index];
                    if dependency_batch_index != dependency.batch_index {
                        expected.insert(dependency_batch_index);
                    }
                }
            }
        }
        if listed != expected {
            return Err(source_pack_manifest_contract_error(format!(
                "batch dependency mismatch for batch {}: listed {:?}, expected {:?}",
                dependency.batch_index, listed, expected
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_manifest_job_artifacts(
    manifest: &SourcePackBuildArtifactManifest,
    output_artifact_indices_by_job: &[Vec<usize>],
    actual_artifact_consumers: &mut [BTreeSet<usize>],
) -> Result<(), CompileError> {
    let job_count = manifest.job_schedule.jobs.len();
    if manifest.job_artifacts.jobs.len() != job_count {
        return Err(source_pack_manifest_contract_error(format!(
            "job artifact manifest has {} jobs but schedule has {}",
            manifest.job_artifacts.jobs.len(),
            job_count
        )));
    }

    for (job_position, job_manifest) in manifest.job_artifacts.jobs.iter().enumerate() {
        if job_manifest.job_index != job_position {
            return Err(source_pack_manifest_contract_error(format!(
                "job artifact entry {job_position} has job_index {}",
                job_manifest.job_index
            )));
        }
        let job = &manifest.job_schedule.jobs[job_position];
        if job_manifest.phase != job.phase {
            return Err(source_pack_manifest_contract_error(format!(
                "job artifact manifest for job {} has phase {:?} but schedule has {:?}",
                job_position, job_manifest.phase, job.phase
            )));
        }

        let mut seen_input_interface_artifacts = BTreeSet::new();
        for artifact_ref in &job_manifest.input_interfaces {
            if !seen_input_interface_artifacts.insert(artifact_ref.artifact_index) {
                return Err(source_pack_manifest_contract_error(format!(
                    "job {} input interface artifact {} is listed more than once",
                    job_position, artifact_ref.artifact_index
                )));
            }
            if artifact_ref.kind != SourcePackArtifactKind::LibraryInterface {
                return Err(source_pack_manifest_contract_error(format!(
                    "job {} input interface ref {} has kind {:?}",
                    job_position, artifact_ref.artifact_index, artifact_ref.kind
                )));
            }
            validate_source_pack_artifact_ref_matches_entry(
                &manifest.artifacts,
                artifact_ref,
                &format!("job {} input interface", job_position),
            )?;
            actual_artifact_consumers[artifact_ref.artifact_index].insert(job_position);
        }
        for artifact_index in source_pack_manifest_artifact_index_range_set(
            &job_manifest.input_interface_artifact_ranges,
            &format!("job {} input interface artifact ranges", job_position),
        )? {
            if !seen_input_interface_artifacts.insert(artifact_index) {
                return Err(source_pack_manifest_contract_error(format!(
                    "job {} input interface artifact {} is listed more than once",
                    job_position, artifact_index
                )));
            }
            let artifact = source_pack_manifest_artifact_entry(
                &manifest.artifacts,
                artifact_index,
                &format!("job {} input interface range", job_position),
            )?;
            if artifact.kind != SourcePackArtifactKind::LibraryInterface {
                return Err(source_pack_manifest_contract_error(format!(
                    "job {} input interface range references artifact {} with kind {:?}",
                    job_position, artifact_index, artifact.kind
                )));
            }
            actual_artifact_consumers[artifact_index].insert(job_position);
        }
        for range in &job_manifest.input_interface_ranges {
            let Some(dependency_job_indices) = range.iter() else {
                return Err(source_pack_manifest_contract_error(format!(
                    "job {} input interface job range starting at {} overflows usize",
                    job_position, range.first_job_index
                )));
            };
            for dependency_job_index in dependency_job_indices {
                let artifact = source_pack_manifest_library_interface_artifact_for_producing_job(
                    &manifest.artifacts,
                    dependency_job_index,
                    &format!("job {} input interface job range", job_position),
                )?;
                if !seen_input_interface_artifacts.insert(artifact.artifact_index) {
                    return Err(source_pack_manifest_contract_error(format!(
                        "job {} input interface artifact {} is listed more than once",
                        job_position, artifact.artifact_index
                    )));
                }
                actual_artifact_consumers[artifact.artifact_index].insert(job_position);
            }
        }
        let mut seen_input_object_artifacts = BTreeSet::new();
        for artifact_ref in &job_manifest.input_objects {
            if !seen_input_object_artifacts.insert(artifact_ref.artifact_index) {
                return Err(source_pack_manifest_contract_error(format!(
                    "job {} input object artifact {} is listed more than once",
                    job_position, artifact_ref.artifact_index
                )));
            }
            if artifact_ref.kind != SourcePackArtifactKind::CodegenObject {
                return Err(source_pack_manifest_contract_error(format!(
                    "job {} input object ref {} has kind {:?}",
                    job_position, artifact_ref.artifact_index, artifact_ref.kind
                )));
            }
            validate_source_pack_artifact_ref_matches_entry(
                &manifest.artifacts,
                artifact_ref,
                &format!("job {} input object", job_position),
            )?;
            actual_artifact_consumers[artifact_ref.artifact_index].insert(job_position);
        }
        for artifact_index in source_pack_manifest_artifact_index_range_set(
            &job_manifest.input_object_artifact_ranges,
            &format!("job {} input object artifact ranges", job_position),
        )? {
            if !seen_input_object_artifacts.insert(artifact_index) {
                return Err(source_pack_manifest_contract_error(format!(
                    "job {} input object artifact {} is listed more than once",
                    job_position, artifact_index
                )));
            }
            let artifact = source_pack_manifest_artifact_entry(
                &manifest.artifacts,
                artifact_index,
                &format!("job {} input object range", job_position),
            )?;
            if artifact.kind != SourcePackArtifactKind::CodegenObject {
                return Err(source_pack_manifest_contract_error(format!(
                    "job {} input object range references artifact {} with kind {:?}",
                    job_position, artifact_index, artifact.kind
                )));
            }
            actual_artifact_consumers[artifact_index].insert(job_position);
        }
        for artifact_ref in &job_manifest.outputs {
            validate_source_pack_artifact_ref_matches_entry(
                &manifest.artifacts,
                artifact_ref,
                &format!("job {} output", job_position),
            )?;
            if artifact_ref.producing_job_index != job_position {
                return Err(source_pack_manifest_contract_error(format!(
                    "job {} output artifact ref {} is produced by job {}",
                    job_position, artifact_ref.artifact_index, artifact_ref.producing_job_index
                )));
            }
        }

        let output_indices =
            source_pack_artifact_ref_index_set(&job_manifest.outputs, "job output refs")?;
        let expected_output_indices = source_pack_manifest_unique_usize_set(
            &output_artifact_indices_by_job[job_position],
            &format!("job {} produced artifacts", job_position),
        )?;
        if output_indices != expected_output_indices {
            return Err(source_pack_manifest_contract_error(format!(
                "job artifact output mismatch for job {}: listed {:?}, expected {:?}",
                job_position, output_indices, expected_output_indices
            )));
        }

        validate_source_pack_manifest_job_output_shape(job_manifest)?;
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_manifest_job_output_shape(
    job_manifest: &SourcePackJobArtifactManifest,
) -> Result<(), CompileError> {
    let interface_outputs = job_manifest
        .outputs
        .iter()
        .filter(|artifact| artifact.kind == SourcePackArtifactKind::LibraryInterface)
        .count();
    let object_outputs = job_manifest
        .outputs
        .iter()
        .filter(|artifact| artifact.kind == SourcePackArtifactKind::CodegenObject)
        .count();
    let linked_outputs = job_manifest
        .outputs
        .iter()
        .filter(|artifact| artifact.kind == SourcePackArtifactKind::LinkedOutput)
        .count();

    let valid = match job_manifest.phase {
        SourcePackJobPhase::LibraryFrontend => {
            interface_outputs == 1 && object_outputs == 0 && linked_outputs == 0
        }
        SourcePackJobPhase::Codegen => {
            interface_outputs == 0 && object_outputs == 1 && linked_outputs == 0
        }
        SourcePackJobPhase::Link => {
            interface_outputs == 0 && object_outputs == 0 && linked_outputs == 1
        }
    };
    if !valid {
        return Err(source_pack_manifest_contract_error(format!(
            "job {} phase {:?} has invalid output shape: {} interfaces, {} objects, {} linked outputs",
            job_manifest.job_index,
            job_manifest.phase,
            interface_outputs,
            object_outputs,
            linked_outputs
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_manifest_job_artifact_io(
    manifest: &SourcePackBuildArtifactManifest,
) -> Result<(), CompileError> {
    let job_count = manifest.job_schedule.jobs.len();
    if manifest.job_artifact_io.jobs.len() != job_count {
        return Err(source_pack_manifest_contract_error(format!(
            "job artifact IO plan has {} jobs but schedule has {}",
            manifest.job_artifact_io.jobs.len(),
            job_count
        )));
    }

    for (job_position, io) in manifest.job_artifact_io.jobs.iter().enumerate() {
        if io.job_index != job_position {
            return Err(source_pack_manifest_contract_error(format!(
                "job artifact IO entry {job_position} has job_index {}",
                io.job_index
            )));
        }
        let job = &manifest.job_schedule.jobs[job_position];
        if io.phase != job.phase {
            return Err(source_pack_manifest_contract_error(format!(
                "job artifact IO for job {} has phase {:?} but schedule has {:?}",
                job_position, io.phase, job.phase
            )));
        }

        let job_manifest = &manifest.job_artifacts.jobs[job_position];
        let manifest_input_interfaces = source_pack_artifact_ref_and_range_index_set(
            &job_manifest.input_interfaces,
            &job_manifest.input_interface_artifact_ranges,
            "job manifest input interfaces",
        )?;
        let mut manifest_input_interfaces = manifest_input_interfaces;
        source_pack_insert_manifest_interface_job_range_indices(
            &manifest.artifacts,
            &job_manifest.input_interface_ranges,
            &mut manifest_input_interfaces,
            "job manifest input interface job ranges",
        )?;
        let io_input_interfaces = source_pack_manifest_unique_usize_and_artifact_range_set(
            &io.input_interface_artifact_indices,
            &io.input_interface_artifact_ranges,
            &format!("job {} IO input interfaces", job_position),
        )?;
        if manifest_input_interfaces != io_input_interfaces {
            return Err(source_pack_manifest_contract_error(format!(
                "job {} input interface IO mismatch: refs {:?}, io {:?}",
                job_position, manifest_input_interfaces, io_input_interfaces
            )));
        }

        let manifest_input_objects = source_pack_artifact_ref_and_range_index_set(
            &job_manifest.input_objects,
            &job_manifest.input_object_artifact_ranges,
            "job manifest inputs",
        )?;
        let io_input_objects = source_pack_manifest_unique_usize_and_artifact_range_set(
            &io.input_object_artifact_indices,
            &io.input_object_artifact_ranges,
            &format!("job {} IO input objects", job_position),
        )?;
        if manifest_input_objects != io_input_objects {
            return Err(source_pack_manifest_contract_error(format!(
                "job {} input object IO mismatch: refs {:?}, io {:?}",
                job_position, manifest_input_objects, io_input_objects
            )));
        }

        let manifest_outputs =
            source_pack_artifact_ref_index_set(&job_manifest.outputs, "job manifest outputs")?;
        let io_outputs = source_pack_manifest_unique_usize_set(
            &io.output_artifact_indices,
            &format!("job {} IO outputs", job_position),
        )?;
        if manifest_outputs != io_outputs {
            return Err(source_pack_manifest_contract_error(format!(
                "job {} output IO mismatch: refs {:?}, io {:?}",
                job_position, manifest_outputs, io_outputs
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_manifest_artifact_uses(
    manifest: &SourcePackBuildArtifactManifest,
    actual_artifact_consumers: &[BTreeSet<usize>],
) -> Result<(), CompileError> {
    let artifact_count = manifest.artifacts.artifacts.len();
    let job_count = manifest.job_schedule.jobs.len();
    if manifest.artifact_uses.uses.len() != artifact_count {
        return Err(source_pack_manifest_contract_error(format!(
            "artifact use plan has {} artifacts but artifact manifest has {}",
            manifest.artifact_uses.uses.len(),
            artifact_count
        )));
    }

    for (use_position, artifact_use) in manifest.artifact_uses.uses.iter().enumerate() {
        if artifact_use.artifact_index != use_position {
            return Err(source_pack_manifest_contract_error(format!(
                "artifact use entry {use_position} has artifact_index {}",
                artifact_use.artifact_index
            )));
        }
        let artifact = &manifest.artifacts.artifacts[use_position];
        if artifact_use.producing_job_index != artifact.producing_job_index {
            return Err(source_pack_manifest_contract_error(format!(
                "artifact use {} records producer {} but artifact records {}",
                use_position, artifact_use.producing_job_index, artifact.producing_job_index
            )));
        }
        for &consumer_job_index in &artifact_use.consumer_job_indices {
            if consumer_job_index >= job_count {
                return Err(source_pack_manifest_contract_error(format!(
                    "artifact use {} references missing consumer job {}",
                    use_position, consumer_job_index
                )));
            }
        }
        let listed = source_pack_manifest_unique_usize_set(
            &artifact_use.consumer_job_indices,
            &format!("artifact {} consumers", use_position),
        )?;
        if listed != actual_artifact_consumers[use_position] {
            return Err(source_pack_manifest_contract_error(format!(
                "artifact use consumer mismatch for artifact {}: listed {:?}, expected {:?}",
                use_position, listed, actual_artifact_consumers[use_position]
            )));
        }
        let expected_last_consumer = actual_artifact_consumers[use_position]
            .iter()
            .copied()
            .max();
        if artifact_use.last_consumer_job_index != expected_last_consumer {
            return Err(source_pack_manifest_contract_error(format!(
                "artifact use {} records last consumer {:?}, expected {:?}",
                use_position, artifact_use.last_consumer_job_index, expected_last_consumer
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_manifest_link_batches(
    manifest: &SourcePackBuildArtifactManifest,
    link_job_index: usize,
) -> Result<(), CompileError> {
    let link_job_manifest = &manifest.job_artifacts.jobs[link_job_index];
    let expected_interface_indices = source_pack_artifact_ref_and_range_index_set(
        &link_job_manifest.input_interfaces,
        &link_job_manifest.input_interface_artifact_ranges,
        "link job input interfaces",
    )?;
    let expected_object_indices = source_pack_artifact_ref_and_range_index_set(
        &link_job_manifest.input_objects,
        &link_job_manifest.input_object_artifact_ranges,
        "link job inputs",
    )?;

    let mut batched_interface_indices = BTreeSet::new();
    for (batch_position, batch) in manifest.link_interface_batches.batches.iter().enumerate() {
        if batch.batch_index != batch_position {
            return Err(source_pack_manifest_contract_error(format!(
                "link interface batch entry {batch_position} has batch_index {}",
                batch.batch_index
            )));
        }
        if batch.input_interface_artifact_indices.len()
            > SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE
        {
            return Err(source_pack_manifest_contract_error(format!(
                "link interface batch {} has {} input artifacts but the page limit is {}",
                batch.batch_index,
                batch.input_interface_artifact_indices.len(),
                SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE
            )));
        }
        source_pack_manifest_unique_usize_set(
            &batch.input_interface_artifact_indices,
            &format!("link interface batch {} inputs", batch.batch_index),
        )?;
        let mut source_bytes = 0usize;
        let mut source_file_count = 0usize;
        for &artifact_index in &batch.input_interface_artifact_indices {
            let artifact = source_pack_manifest_artifact_entry(
                &manifest.artifacts,
                artifact_index,
                &format!("link interface batch {}", batch.batch_index),
            )?;
            if artifact.kind != SourcePackArtifactKind::LibraryInterface {
                return Err(source_pack_manifest_contract_error(format!(
                    "link interface batch {} references artifact {} with kind {:?}",
                    batch.batch_index, artifact_index, artifact.kind
                )));
            }
            if !batched_interface_indices.insert(artifact_index) {
                return Err(source_pack_manifest_contract_error(format!(
                    "link interface artifact {} appears in more than one link batch",
                    artifact_index
                )));
            }
            source_bytes = source_bytes.saturating_add(artifact.source_bytes);
            source_file_count = source_file_count.saturating_add(artifact.source_file_count);
        }
        if batch.source_bytes != source_bytes {
            return Err(source_pack_manifest_contract_error(format!(
                "link interface batch {} records {} source bytes but artifacts sum to {}",
                batch.batch_index, batch.source_bytes, source_bytes
            )));
        }
        if batch.source_file_count != source_file_count {
            return Err(source_pack_manifest_contract_error(format!(
                "link interface batch {} records {} source files but artifacts sum to {}",
                batch.batch_index, batch.source_file_count, source_file_count
            )));
        }
    }
    if batched_interface_indices != expected_interface_indices {
        return Err(source_pack_manifest_contract_error(format!(
            "link interface batch inputs {:?} do not match link job inputs {:?}",
            batched_interface_indices, expected_interface_indices
        )));
    }

    let mut batched_object_indices = BTreeSet::new();
    for (batch_position, batch) in manifest.link_object_batches.batches.iter().enumerate() {
        if batch.batch_index != batch_position {
            return Err(source_pack_manifest_contract_error(format!(
                "link object batch entry {batch_position} has batch_index {}",
                batch.batch_index
            )));
        }
        if batch.input_object_artifact_indices.len()
            > SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE
        {
            return Err(source_pack_manifest_contract_error(format!(
                "link object batch {} has {} input artifacts but the page limit is {}",
                batch.batch_index,
                batch.input_object_artifact_indices.len(),
                SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE
            )));
        }
        source_pack_manifest_unique_usize_set(
            &batch.input_object_artifact_indices,
            &format!("link object batch {} inputs", batch.batch_index),
        )?;
        let mut source_bytes = 0usize;
        let mut source_file_count = 0usize;
        for &artifact_index in &batch.input_object_artifact_indices {
            let artifact = source_pack_manifest_artifact_entry(
                &manifest.artifacts,
                artifact_index,
                &format!("link object batch {}", batch.batch_index),
            )?;
            if artifact.kind != SourcePackArtifactKind::CodegenObject {
                return Err(source_pack_manifest_contract_error(format!(
                    "link object batch {} references artifact {} with kind {:?}",
                    batch.batch_index, artifact_index, artifact.kind
                )));
            }
            if !batched_object_indices.insert(artifact_index) {
                return Err(source_pack_manifest_contract_error(format!(
                    "link object artifact {} appears in more than one link batch",
                    artifact_index
                )));
            }
            source_bytes = source_bytes.saturating_add(artifact.source_bytes);
            source_file_count = source_file_count.saturating_add(artifact.source_file_count);
        }
        if batch.source_bytes != source_bytes {
            return Err(source_pack_manifest_contract_error(format!(
                "link object batch {} records {} source bytes but artifacts sum to {}",
                batch.batch_index, batch.source_bytes, source_bytes
            )));
        }
        if batch.source_file_count != source_file_count {
            return Err(source_pack_manifest_contract_error(format!(
                "link object batch {} records {} source files but artifacts sum to {}",
                batch.batch_index, batch.source_file_count, source_file_count
            )));
        }
    }
    if batched_object_indices != expected_object_indices {
        return Err(source_pack_manifest_contract_error(format!(
            "link object batch inputs {:?} do not match link job inputs {:?}",
            batched_object_indices, expected_object_indices
        )));
    }

    Ok(())
}

pub(in crate::compiler) fn source_pack_manifest_artifact_entry<'a>(
    manifest: &'a SourcePackArtifactManifest,
    artifact_index: usize,
    label: &str,
) -> Result<&'a SourcePackArtifactManifestEntry, CompileError> {
    let artifact = manifest.get(artifact_index).ok_or_else(|| {
        source_pack_manifest_contract_error(format!(
            "{label} references missing artifact {artifact_index}"
        ))
    })?;
    if artifact.artifact_index != artifact_index {
        return Err(source_pack_manifest_contract_error(format!(
            "{label} references artifact {} but entry records artifact_index {}",
            artifact_index, artifact.artifact_index
        )));
    }
    Ok(artifact)
}

pub(in crate::compiler) fn source_pack_manifest_library_interface_artifact_for_producing_job<'a>(
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
        source_pack_manifest_contract_error(format!(
            "{label} references missing library-interface artifact from job {producing_job_index}"
        ))
    })?;
    if matches.next().is_some() {
        return Err(source_pack_manifest_contract_error(format!(
            "{label} references producer job {producing_job_index} with multiple library-interface artifacts"
        )));
    }
    Ok(artifact)
}

pub(in crate::compiler) fn source_pack_artifact_ref_from_manifest_entry(
    artifact: &SourcePackArtifactManifestEntry,
) -> SourcePackArtifactRef {
    SourcePackArtifactRef {
        artifact_index: artifact.artifact_index,
        key: artifact.key.clone(),
        producing_job_index: artifact.producing_job_index,
        kind: artifact.kind,
    }
}

pub(in crate::compiler) fn source_pack_insert_manifest_interface_job_range_indices(
    manifest: &SourcePackArtifactManifest,
    job_ranges: &[SourcePackJobIndexRange],
    values: &mut BTreeSet<usize>,
    label: &str,
) -> Result<(), CompileError> {
    for range in job_ranges {
        let Some(job_indices) = range.iter() else {
            return Err(source_pack_manifest_contract_error(format!(
                "{label} contains overflowing job range starting at {} with {} jobs",
                range.first_job_index, range.job_count
            )));
        };
        for producing_job_index in job_indices {
            let artifact = source_pack_manifest_library_interface_artifact_for_producing_job(
                manifest,
                producing_job_index,
                label,
            )?;
            if !values.insert(artifact.artifact_index) {
                return Err(source_pack_manifest_contract_error(format!(
                    "{label} contains duplicate ranged interface artifact {}",
                    artifact.artifact_index
                )));
            }
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_artifact_ref_matches_entry(
    manifest: &SourcePackArtifactManifest,
    artifact_ref: &SourcePackArtifactRef,
    label: &str,
) -> Result<(), CompileError> {
    let artifact =
        source_pack_manifest_artifact_entry(manifest, artifact_ref.artifact_index, label)?;
    if artifact_ref.key != artifact.key
        || artifact_ref.producing_job_index != artifact.producing_job_index
        || artifact_ref.kind != artifact.kind
    {
        return Err(source_pack_manifest_contract_error(format!(
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

pub(in crate::compiler) fn source_pack_artifact_ref_index_set(
    artifact_refs: &[SourcePackArtifactRef],
    label: &str,
) -> Result<BTreeSet<usize>, CompileError> {
    let mut values = BTreeSet::new();
    for artifact_ref in artifact_refs {
        if !values.insert(artifact_ref.artifact_index) {
            return Err(source_pack_manifest_contract_error(format!(
                "{label} contains duplicate artifact {}",
                artifact_ref.artifact_index
            )));
        }
    }
    Ok(values)
}

pub(in crate::compiler) fn source_pack_artifact_ref_and_range_index_set(
    artifact_refs: &[SourcePackArtifactRef],
    artifact_ranges: &[SourcePackArtifactIndexRange],
    label: &str,
) -> Result<BTreeSet<usize>, CompileError> {
    let mut values = source_pack_artifact_ref_index_set(artifact_refs, label)?;
    for value in source_pack_manifest_artifact_index_range_set(artifact_ranges, label)? {
        if !values.insert(value) {
            return Err(source_pack_manifest_contract_error(format!(
                "{label} contains duplicate artifact {value}"
            )));
        }
    }
    Ok(values)
}

pub(in crate::compiler) fn source_pack_manifest_unique_usize_set(
    values: &[usize],
    label: &str,
) -> Result<BTreeSet<usize>, CompileError> {
    let mut unique_values = BTreeSet::new();
    for &value in values {
        if !unique_values.insert(value) {
            return Err(source_pack_manifest_contract_error(format!(
                "{label} contains duplicate index {value}"
            )));
        }
    }
    Ok(unique_values)
}

pub(in crate::compiler) fn source_pack_manifest_unique_usize_and_artifact_range_set(
    values: &[usize],
    artifact_ranges: &[SourcePackArtifactIndexRange],
    label: &str,
) -> Result<BTreeSet<usize>, CompileError> {
    let mut unique_values = source_pack_manifest_unique_usize_set(values, label)?;
    for value in source_pack_manifest_artifact_index_range_set(artifact_ranges, label)? {
        if !unique_values.insert(value) {
            return Err(source_pack_manifest_contract_error(format!(
                "{label} contains duplicate index {value}"
            )));
        }
    }
    Ok(unique_values)
}

pub(in crate::compiler) fn source_pack_manifest_artifact_index_range_set(
    artifact_ranges: &[SourcePackArtifactIndexRange],
    label: &str,
) -> Result<BTreeSet<usize>, CompileError> {
    let mut unique_values = BTreeSet::new();
    for range in artifact_ranges {
        let Some(indices) = range.iter() else {
            return Err(source_pack_manifest_contract_error(format!(
                "{label} contains overflowing artifact range starting at {} with {} artifacts",
                range.first_artifact_index, range.artifact_count
            )));
        };
        for value in indices {
            if !unique_values.insert(value) {
                return Err(source_pack_manifest_contract_error(format!(
                    "{label} contains duplicate ranged artifact {value}"
                )));
            }
        }
    }
    Ok(unique_values)
}

pub(in crate::compiler) fn source_pack_artifact_index_range_count(
    ranges: &[SourcePackArtifactIndexRange],
) -> usize {
    ranges.iter().fold(0usize, |count, range| {
        count.saturating_add(range.artifact_count)
    })
}

pub(in crate::compiler) fn source_pack_artifact_index_covered_by_ranges(
    artifact_index: usize,
    ranges: &[SourcePackArtifactIndexRange],
) -> bool {
    ranges.iter().any(|range| range.contains(artifact_index))
}

pub(in crate::compiler) fn source_pack_compact_artifact_index_ranges(
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

pub(in crate::compiler) fn source_pack_validate_artifact_index_ranges<F>(
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

pub(in crate::compiler) fn source_pack_manifest_unique_u32_set(
    values: &[u32],
    label: &str,
) -> Result<BTreeSet<u32>, CompileError> {
    let mut unique_values = BTreeSet::new();
    for &value in values {
        if !unique_values.insert(value) {
            return Err(source_pack_manifest_contract_error(format!(
                "{label} contains duplicate id {value}"
            )));
        }
    }
    Ok(unique_values)
}

pub(in crate::compiler) fn validate_source_pack_manifest_artifact_key(
    target: SourcePackArtifactTarget,
    key: &str,
    label: &str,
) -> Result<(), CompileError> {
    source_pack_filesystem_artifact_path(Path::new(""), key).map_err(|err| {
        source_pack_manifest_contract_error(format!("{label} has invalid key {key:?}: {err}"))
    })?;
    if let Some(prefix) = target.key_prefix() {
        let target_prefix = format!("{prefix}/");
        if !key.starts_with(&target_prefix) {
            return Err(source_pack_manifest_contract_error(format!(
                "{label} key {key:?} does not start with target prefix {target_prefix:?}"
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_manifest_contract_error(
    message: impl Into<String>,
) -> CompileError {
    CompileError::GpuFrontend(format!(
        "invalid source-pack artifact manifest: {}",
        message.into()
    ))
}

pub(in crate::compiler) fn source_pack_artifact_shard_contract_error(
    message: impl Into<String>,
) -> CompileError {
    CompileError::GpuFrontend(format!(
        "invalid source-pack artifact shard index: {}",
        message.into()
    ))
}

pub(in crate::compiler) fn source_pack_library_partition_contract_error(
    message: impl Into<String>,
) -> CompileError {
    CompileError::GpuFrontend(format!(
        "invalid source-pack library partition index: {}",
        message.into()
    ))
}

pub(in crate::compiler) fn source_pack_validate_job_batch_dependency_ranges<F>(
    dependency: &SourcePackJobBatchDependency,
    explicit_dependencies: &BTreeSet<usize>,
    context: &str,
    max_dependency_batch_index_exclusive: usize,
    rejected_batch_index: Option<usize>,
    make_error: F,
) -> Result<(), CompileError>
where
    F: Fn(String) -> CompileError,
{
    let mut ranges = Vec::<(usize, usize)>::new();
    for (range_position, range) in dependency.dependency_batch_ranges.iter().enumerate() {
        if range.batch_count == 0 {
            return Err(make_error(format!(
                "{context} dependency range {range_position} is empty"
            )));
        }
        let Some(end_batch_index) = range.end_batch_index() else {
            return Err(make_error(format!(
                "{context} dependency range {range_position} overflows usize"
            )));
        };
        if end_batch_index > max_dependency_batch_index_exclusive {
            return Err(make_error(format!(
                "{context} dependency range {}..{} exceeds dependency bound {}",
                range.first_batch_index, end_batch_index, max_dependency_batch_index_exclusive
            )));
        }
        if let Some(rejected_batch_index) = rejected_batch_index {
            if range.contains(rejected_batch_index) {
                return Err(make_error(format!(
                    "{context} dependency range {}..{} includes batch {}",
                    range.first_batch_index, end_batch_index, rejected_batch_index
                )));
            }
        }
        if let Some(duplicate) = explicit_dependencies
            .iter()
            .copied()
            .find(|&dependency_batch_index| range.contains(dependency_batch_index))
        {
            return Err(make_error(format!(
                "{context} dependency range {}..{} duplicates explicit dependency {}",
                range.first_batch_index, end_batch_index, duplicate
            )));
        }
        if let Some(&(overlap_start, overlap_end)) = ranges
            .iter()
            .find(|&&(start, end)| range.first_batch_index < end && start < end_batch_index)
        {
            return Err(make_error(format!(
                "{context} dependency range {}..{} overlaps range {}..{}",
                range.first_batch_index, end_batch_index, overlap_start, overlap_end
            )));
        }
        ranges.push((range.first_batch_index, end_batch_index));
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_validate_job_batch_dependency_range_metadata<F>(
    dependency: &SourcePackJobBatchDependency,
    context: &str,
    make_error: F,
) -> Result<(), CompileError>
where
    F: Fn(String) -> CompileError,
{
    if !dependency.dependency_batch_ranges.is_empty() {
        if dependency.dependency_range_page_count != 0 {
            return Err(make_error(format!(
                "{context} records both inline and paged dependency ranges"
            )));
        }
        if dependency.dependency_range_count != dependency.dependency_batch_ranges.len() {
            return Err(make_error(format!(
                "{context} records {} inline dependency ranges but range count {}",
                dependency.dependency_batch_ranges.len(),
                dependency.dependency_range_count
            )));
        }
        let inline_dependency_range_batch_count = dependency
            .dependency_batch_ranges
            .iter()
            .try_fold(0usize, |count, range| {
                count.checked_add(range.batch_count).ok_or_else(|| {
                    make_error(format!(
                        "{context} inline dependency range batch count overflows"
                    ))
                })
            })?;
        if dependency.dependency_range_batch_count != inline_dependency_range_batch_count {
            return Err(make_error(format!(
                "{context} records {} dependency batches in inline ranges but range batch count {}",
                inline_dependency_range_batch_count, dependency.dependency_range_batch_count
            )));
        }
        return Ok(());
    }

    if dependency.dependency_range_count == 0 {
        if dependency.dependency_range_page_count != 0
            || dependency.dependency_range_batch_count != 0
        {
            return Err(make_error(format!(
                "{context} has dependency range metadata without ranges"
            )));
        }
        return Ok(());
    }

    let expected_page_count = dependency
        .dependency_range_count
        .div_ceil(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE);
    if dependency.dependency_range_page_count != expected_page_count {
        return Err(make_error(format!(
            "{context} has dependency range page count {} but expected {} for {} ranges",
            dependency.dependency_range_page_count,
            expected_page_count,
            dependency.dependency_range_count
        )));
    }
    if dependency.dependency_range_batch_count == 0 {
        return Err(make_error(format!(
            "{context} has dependency ranges without dependency batches"
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_for_each_job_batch_dependency_index<F>(
    dependency: &SourcePackJobBatchDependency,
    mut visit: F,
) -> Result<(), CompileError>
where
    F: FnMut(usize) -> Result<(), CompileError>,
{
    if dependency.dependency_batch_indices.len() != dependency.explicit_dependency_count() {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch {} dependency ids are paged and require the stored dependency iterator",
            dependency.batch_index
        )));
    }
    if dependency.dependency_batch_ranges.is_empty() && dependency.dependency_range_count != 0 {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch {} dependency ranges are paged and require the stored dependency iterator",
            dependency.batch_index
        )));
    }
    for &dependency_batch_index in &dependency.dependency_batch_indices {
        visit(dependency_batch_index)?;
    }
    for range in &dependency.dependency_batch_ranges {
        let Some(indices) = range.iter() else {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "batch {} has overflowing dependency range starting at {}",
                dependency.batch_index, range.first_batch_index
            )));
        };
        for dependency_batch_index in indices {
            visit(dependency_batch_index)?;
        }
    }
    Ok(())
}

pub(in crate::compiler) fn store_source_pack_build_job_batch_dependency_pages(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    dependency: &SourcePackJobBatchDependency,
) -> Result<(usize, usize), CompileError> {
    if dependency.dependency_batch_indices.is_empty() {
        return Ok((
            dependency.dependency_batch_count,
            dependency.dependency_page_count,
        ));
    }
    source_pack_manifest_unique_usize_set(
        &dependency.dependency_batch_indices,
        &format!("job-batch page {} dependencies", dependency.batch_index),
    )?;
    let mut dependency_batch_count = 0usize;
    let mut dependency_page_count = 0usize;
    for dependency_chunk in dependency
        .dependency_batch_indices
        .chunks(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE)
    {
        let page = SourcePackBuildJobBatchDependencyPage {
            version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_PAGE_VERSION,
            target,
            batch_index: dependency.batch_index,
            page_index: dependency_page_count,
            first_dependency_position: dependency_page_count
                .saturating_mul(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE),
            dependency_count: dependency_chunk.len(),
            dependency_batch_indices: dependency_chunk.to_vec(),
        };
        validate_source_pack_build_job_batch_dependency_page(
            &page,
            target,
            dependency.batch_index,
            dependency_page_count,
        )?;
        store.store_build_job_batch_dependency_page(&page)?;
        dependency_batch_count = dependency_batch_count.saturating_add(page.dependency_count);
        dependency_page_count += 1;
    }
    Ok((dependency_batch_count, dependency_page_count))
}

pub(in crate::compiler) fn store_source_pack_build_job_batch_dependency_range_pages(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    dependency: &SourcePackJobBatchDependency,
) -> Result<(usize, usize, usize), CompileError> {
    if dependency.dependency_batch_ranges.is_empty() {
        return Ok((
            dependency.dependency_range_count,
            dependency.dependency_range_page_count,
            dependency.dependency_range_batch_count,
        ));
    }
    let mut dependency_range_count = 0usize;
    let mut dependency_range_page_count = 0usize;
    let mut dependency_range_batch_count = 0usize;
    for range_chunk in dependency
        .dependency_batch_ranges
        .chunks(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE)
    {
        let page_dependency_batch_count = range_chunk.iter().fold(0usize, |count, range| {
            count.saturating_add(range.batch_count)
        });
        let page = SourcePackBuildJobBatchDependencyRangePage {
            version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_PAGE_VERSION,
            target,
            batch_index: dependency.batch_index,
            page_index: dependency_range_page_count,
            first_range_position: dependency_range_count,
            range_count: range_chunk.len(),
            dependency_batch_count: page_dependency_batch_count,
            dependency_batch_ranges: range_chunk.to_vec(),
        };
        validate_source_pack_build_job_batch_dependency_range_page(
            &page,
            target,
            dependency.batch_index,
            dependency_range_page_count,
        )?;
        store.store_build_job_batch_dependency_range_page(&page)?;
        dependency_range_count = dependency_range_count.saturating_add(page.range_count);
        dependency_range_batch_count =
            dependency_range_batch_count.saturating_add(page.dependency_batch_count);
        dependency_range_page_count += 1;
    }
    Ok((
        dependency_range_count,
        dependency_range_page_count,
        dependency_range_batch_count,
    ))
}

pub(in crate::compiler) struct SourcePackBuildJobBatchDependencyPageWriter<'a> {
    pub(in crate::compiler) store: &'a SourcePackFilesystemArtifactStore,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) batch_index: usize,
    pub(in crate::compiler) page_index: usize,
    pub(in crate::compiler) first_dependency_position: usize,
    pub(in crate::compiler) dependency_batch_count: usize,
    pub(in crate::compiler) seen_dependency_batch_indices: BTreeSet<usize>,
    pub(in crate::compiler) current_dependency_batch_indices: Vec<usize>,
}

impl<'a> SourcePackBuildJobBatchDependencyPageWriter<'a> {
    pub(in crate::compiler) fn new(
        store: &'a SourcePackFilesystemArtifactStore,
        target: SourcePackArtifactTarget,
        batch_index: usize,
    ) -> Self {
        Self {
            store,
            target,
            batch_index,
            page_index: 0,
            first_dependency_position: 0,
            dependency_batch_count: 0,
            seen_dependency_batch_indices: BTreeSet::new(),
            current_dependency_batch_indices: Vec::with_capacity(
                SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE,
            ),
        }
    }

    pub(in crate::compiler) fn push(
        &mut self,
        dependency_batch_index: usize,
    ) -> Result<(), CompileError> {
        if dependency_batch_index >= self.batch_index {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "job-batch page {} depends on non-earlier batch {}",
                self.batch_index, dependency_batch_index
            )));
        }
        if !self
            .seen_dependency_batch_indices
            .insert(dependency_batch_index)
        {
            return Ok(());
        }
        self.current_dependency_batch_indices
            .push(dependency_batch_index);
        if self.current_dependency_batch_indices.len()
            == SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE
        {
            self.flush()?;
        }
        Ok(())
    }

    pub(in crate::compiler) fn flush(&mut self) -> Result<(), CompileError> {
        if self.current_dependency_batch_indices.is_empty() {
            return Ok(());
        }
        let dependency_batch_indices = std::mem::take(&mut self.current_dependency_batch_indices);
        let page = SourcePackBuildJobBatchDependencyPage {
            version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_PAGE_VERSION,
            target: self.target,
            batch_index: self.batch_index,
            page_index: self.page_index,
            first_dependency_position: self.first_dependency_position,
            dependency_count: dependency_batch_indices.len(),
            dependency_batch_indices,
        };
        validate_source_pack_build_job_batch_dependency_page(
            &page,
            self.target,
            self.batch_index,
            self.page_index,
        )?;
        self.store.store_build_job_batch_dependency_page(&page)?;
        self.dependency_batch_count = self
            .dependency_batch_count
            .saturating_add(page.dependency_count);
        self.first_dependency_position = self
            .first_dependency_position
            .saturating_add(page.dependency_count);
        self.page_index += 1;
        Ok(())
    }

    pub(in crate::compiler) fn finish(mut self) -> Result<(usize, usize), CompileError> {
        self.flush()?;
        Ok((self.dependency_batch_count, self.page_index))
    }
}

pub(in crate::compiler) fn source_pack_for_each_stored_job_batch_dependency_index<F>(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    dependency: &SourcePackJobBatchDependency,
    mut visit: F,
) -> Result<(), CompileError>
where
    F: FnMut(usize) -> Result<(), CompileError>,
{
    if !dependency.dependency_batch_indices.is_empty() {
        source_pack_for_each_job_batch_dependency_index(dependency, visit)?;
        return Ok(());
    }

    let mut seen_dependency_count = 0usize;
    for page_index in 0..dependency.dependency_page_count {
        let page = store.load_build_job_batch_dependency_page_for_target(
            target,
            dependency.batch_index,
            page_index,
        )?;
        seen_dependency_count = seen_dependency_count.saturating_add(page.dependency_count);
        for &dependency_batch_index in &page.dependency_batch_indices {
            visit(dependency_batch_index)?;
        }
    }
    if seen_dependency_count != dependency.dependency_batch_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch {} iterated {} dependency batches but expected {}",
            dependency.batch_index, seen_dependency_count, dependency.dependency_batch_count
        )));
    }
    if !dependency.dependency_batch_ranges.is_empty() {
        for range in &dependency.dependency_batch_ranges {
            let Some(indices) = range.iter() else {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "batch {} has overflowing dependency range starting at {}",
                    dependency.batch_index, range.first_batch_index
                )));
            };
            for dependency_batch_index in indices {
                visit(dependency_batch_index)?;
            }
        }
    } else {
        let mut seen_range_count = 0usize;
        let mut seen_range_dependency_batch_count = 0usize;
        for page_index in 0..dependency.dependency_range_page_count {
            let page = store.load_build_job_batch_dependency_range_page_for_target(
                target,
                dependency.batch_index,
                page_index,
            )?;
            seen_range_count = seen_range_count.saturating_add(page.range_count);
            seen_range_dependency_batch_count =
                seen_range_dependency_batch_count.saturating_add(page.dependency_batch_count);
            for range in &page.dependency_batch_ranges {
                let Some(indices) = range.iter() else {
                    return Err(source_pack_artifact_shard_contract_error(format!(
                        "batch {} has overflowing dependency range starting at {}",
                        dependency.batch_index, range.first_batch_index
                    )));
                };
                for dependency_batch_index in indices {
                    visit(dependency_batch_index)?;
                }
            }
        }
        if seen_range_count != dependency.dependency_range_count {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "job-batch {} iterated {} dependency ranges but expected {}",
                dependency.batch_index, seen_range_count, dependency.dependency_range_count
            )));
        }
        if seen_range_dependency_batch_count != dependency.dependency_range_batch_count {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "job-batch {} iterated {} range dependency batches but expected {}",
                dependency.batch_index,
                seen_range_dependency_batch_count,
                dependency.dependency_range_batch_count
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_build_state_version(
    state: &SourcePackBuildState,
) -> Result<(), CompileError> {
    if state.version != SOURCE_PACK_BUILD_STATE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack build state version {}; expected {}",
            state.version, SOURCE_PACK_BUILD_STATE_VERSION
        )));
    }
    Ok(())
}
