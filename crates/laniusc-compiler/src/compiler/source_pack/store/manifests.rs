use super::*;

#[cfg(test)]
pub(in crate::compiler) fn build_artifact_execution_shard(
    manifest: &SourcePackPathBuildManifest,
    shard: &SourcePackBuildArtifactShard,
) -> Result<SourcePackBuildArtifactExecutionShard, CompileError> {
    validate_path_manifest(manifest)?;
    validate_artifact_shard(shard, manifest.artifacts.target)?;

    let mut source_file_indices = BTreeSet::new();
    let mut jobs = Vec::new();
    let mut job_artifacts = Vec::new();
    for &job_index in &shard.job_indices {
        let job = schedule_job(&manifest.artifacts.job_schedule, job_index)?.clone();
        for source_index in
            job.first_source_index..job.first_source_index.saturating_add(job.source_file_count)
        {
            source_file_indices.insert(source_index);
        }
        let job_manifest =
            job_artifact_manifest(&manifest.artifacts.job_artifacts, job_index)?.clone();
        jobs.push(job);
        job_artifacts.push(job_manifest);
    }

    let mut job_batches = Vec::new();
    let mut batch_dependencies = Vec::new();
    let mut batch_dependents = Vec::new();
    let mut link_interface_batches = Vec::new();
    let mut link_object_batches = Vec::new();
    match shard.kind {
        SourcePackBuildArtifactShardKind::JobBatches => {
            for &batch_index in &shard.batch_indices {
                job_batches
                    .push(artifact_manifest_batch(&manifest.artifacts, batch_index)?.clone());
                batch_dependencies.push(
                    job_batch_dependency(&manifest.artifacts.batch_dependencies, batch_index)?
                        .clone(),
                );
                batch_dependents.push(SourcePackJobBatchDependents {
                    batch_index,
                    dependent_batch_indices: Vec::new(),
                });
            }
        }
        SourcePackBuildArtifactShardKind::LinkInterfaceBatches => {
            for &batch_index in &shard.batch_indices {
                link_interface_batches.push(
                    link_interface_batch(&manifest.artifacts.link_interface_batches, batch_index)?
                        .clone(),
                );
            }
        }
        SourcePackBuildArtifactShardKind::LinkObjectBatches => {
            for &batch_index in &shard.batch_indices {
                link_object_batches.push(
                    link_object_batch(&manifest.artifacts.link_object_batches, batch_index)?
                        .clone(),
                );
            }
        }
    }

    let source_files = source_file_indices
        .into_iter()
        .map(|source_index| {
            let file = manifest
                .source_files
                .get(source_index)
                .cloned()
                .ok_or_else(|| {
                    artifact_shard_contract_error(format!(
                        "execution shard {} references missing source file {}",
                        shard.shard_index, source_index
                    ))
                })?;
            Ok(SourcePackShardSourceFile { source_index, file })
        })
        .collect::<Result<Vec<_>, CompileError>>()?;

    let artifact_indices = shard
        .input_artifact_indices
        .iter()
        .chain(shard.output_artifact_indices.iter())
        .copied()
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect::<Vec<_>>();
    let mut artifact_refs =
        artifact_refs_for_indices(&manifest.artifacts.artifacts, &artifact_indices)?;
    let mut seen_artifact_refs = artifact_refs
        .iter()
        .map(|artifact| artifact.artifact_index)
        .collect::<BTreeSet<_>>();
    for range in &shard.input_artifact_ranges {
        let Some(indices) = range.iter() else {
            return Err(artifact_shard_contract_error(format!(
                "execution shard {} input artifact range starting at {} overflows",
                shard.shard_index, range.first_artifact_index
            )));
        };
        for artifact_index in indices {
            if !seen_artifact_refs.insert(artifact_index) {
                continue;
            }
            artifact_refs.push(artifact_ref_for_index(
                &manifest.artifacts.artifacts,
                artifact_index,
            )?);
        }
    }

    Ok(SourcePackBuildArtifactExecutionShard {
        version: SOURCE_PACK_BUILD_ARTIFACT_EXECUTION_SHARD_VERSION,
        target: manifest.artifacts.target,
        shard: shard.clone(),
        source_files,
        job_batches,
        batch_dependencies,
        batch_dependents,
        jobs,
        job_artifacts,
        artifact_refs,
        link_interface_batches,
        link_object_batches,
    })
}

impl FilesystemArtifactStore {
    pub fn store_build_artifact_manifest(
        &self,
        manifest: &SourcePackBuildArtifactManifest,
    ) -> Result<PathBuf, CompileError> {
        validate_artifact_manifest(manifest)?;
        let path = self.artifact_manifest_path_for_target(manifest.target);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "create source-pack build artifact manifest directory {}: {err}",
                    parent.display()
                ))
            })?;
        }
        let compact_manifest = compact_artifact_manifest(manifest)?;
        let bytes = serde_json::to_vec_pretty(&compact_manifest).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack build artifact manifest: {err}"
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack build artifact manifest")?;
        Ok(path)
    }

    pub fn load_build_artifact_manifest_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildArtifactManifest, CompileError> {
        let path = self.artifact_manifest_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack build artifact manifest {}: {err}",
                path.display()
            ))
        })?;
        let manifest =
            serde_json::from_slice::<SourcePackBuildArtifactManifest>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack build artifact manifest {}: {err}",
                    path.display()
                ))
            })?;
        validate_artifact_manifest(&manifest)?;
        Ok(manifest)
    }

    pub(in crate::compiler) fn store_build_artifact_execution_shard_with_batch_count(
        &self,
        execution_shard: &SourcePackBuildArtifactExecutionShard,
        batch_count: Option<usize>,
    ) -> Result<PathBuf, CompileError> {
        validate_execution_shard_store_input(execution_shard, execution_shard.target)?;
        let mut stored_execution_shard = execution_shard.clone();
        for dependency in &mut stored_execution_shard.batch_dependencies {
            let (dependency_batch_count, dependency_page_count) =
                store_job_batch_dependency_pages(self, stored_execution_shard.target, dependency)?;
            let (dependency_range_count, dependency_range_page_count, dependency_range_batch_count) =
                store_job_batch_dependency_range_pages(
                    self,
                    stored_execution_shard.target,
                    dependency,
                )?;
            dependency.dependency_batch_indices.clear();
            dependency.dependency_batch_count = dependency_batch_count;
            dependency.dependency_page_count = dependency_page_count;
            dependency.dependency_batch_ranges.clear();
            dependency.dependency_range_count = dependency_range_count;
            dependency.dependency_range_page_count = dependency_range_page_count;
            dependency.dependency_range_batch_count = dependency_range_batch_count;
        }
        let mut dependent_batch_count = batch_count;
        for dependents in &mut stored_execution_shard.batch_dependents {
            if !dependents.dependent_batch_indices.is_empty() {
                if dependent_batch_count.is_none() {
                    dependent_batch_count =
                        Some(Self::infer_execution_shard_batch_count(execution_shard)?);
                }
                let dependent_batch_count =
                    dependent_batch_count.expect("execution-shard dependent batch count");
                let page = SourcePackBuildJobBatchDependentsPage {
                    version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_PAGE_VERSION,
                    target: stored_execution_shard.target,
                    batch_count: dependent_batch_count,
                    batch_index: dependents.batch_index,
                    dependents: dependents.clone(),
                    dependent_batch_count: 0,
                    dependent_page_count: 0,
                };
                self.store_build_job_batch_dependents_page(&page, dependent_batch_count)?;
                dependents.dependent_batch_indices.clear();
            }
        }
        for job_manifest in &mut stored_execution_shard.job_artifacts {
            match job_manifest.phase {
                SourcePackJobPhase::LibraryFrontend | SourcePackJobPhase::Codegen => {
                    let explicit_input_interface_count = job_manifest.input_interfaces.len();
                    if !job_manifest.input_interfaces.is_empty() {
                        let input_interface_page_count = self
                            .store_job_artifact_input_interface_pages_from_refs(
                                stored_execution_shard.target,
                                job_manifest.job_index,
                                &job_manifest.input_interfaces,
                            )?;
                        job_manifest.input_interface_page_count = input_interface_page_count;
                        job_manifest.input_interfaces.clear();
                    }
                    let retained_input_interface_count = explicit_input_interface_count
                        .saturating_add(job_index_range_dependency_count(
                            &job_manifest.input_interface_ranges,
                        ))
                        .saturating_add(artifact_index_range_count(
                            &job_manifest.input_interface_artifact_ranges,
                        ));
                    job_manifest.input_interface_count = job_manifest
                        .input_interface_count
                        .max(retained_input_interface_count);
                }
                SourcePackJobPhase::Link => {
                    job_manifest.input_interface_count = 0;
                    job_manifest.input_interface_page_count = 0;
                    job_manifest.input_interface_ranges.clear();
                    job_manifest.input_interfaces.clear();
                    job_manifest.input_objects.clear();
                }
            }
        }
        prune_persisted_execution_shard_artifact_refs(&mut stored_execution_shard)?;
        validate_execution_shard(&stored_execution_shard, stored_execution_shard.target)?;
        let path = self.artifact_execution_shard_path_for_target(
            stored_execution_shard.target,
            stored_execution_shard.shard.shard_index,
        );
        let bytes = serde_json::to_vec_pretty(&stored_execution_shard).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack build artifact execution shard {}: {err}",
                stored_execution_shard.shard.shard_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack build artifact execution shard")?;
        Ok(path)
    }

    pub(in crate::compiler) fn store_job_artifact_input_interface_pages_from_refs(
        &self,
        target: SourcePackArtifactTarget,
        job_index: usize,
        input_interfaces: &[SourcePackArtifactRef],
    ) -> Result<usize, CompileError> {
        for (page_index, input_interfaces) in input_interfaces
            .chunks(SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE)
            .enumerate()
        {
            let page = SourcePackJobArtifactInputInterfacePage {
                version: SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_PAGE_VERSION,
                target,
                job_index,
                page_index,
                first_input_position: page_index
                    .saturating_mul(SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE),
                input_count: input_interfaces.len(),
                input_interfaces: input_interfaces.to_vec(),
            };
            self.store_job_artifact_input_interface_page(&page)?;
        }
        Ok(input_interfaces
            .len()
            .div_ceil(SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE))
    }

    pub(in crate::compiler) fn infer_execution_shard_batch_count(
        execution_shard: &SourcePackBuildArtifactExecutionShard,
    ) -> Result<usize, CompileError> {
        let mut batch_count = 0usize;
        for batch_index in execution_shard
            .shard
            .batch_indices
            .iter()
            .copied()
            .chain(
                execution_shard
                    .batch_dependencies
                    .iter()
                    .map(|dependency| dependency.batch_index),
            )
            .chain(
                execution_shard
                    .batch_dependencies
                    .iter()
                    .flat_map(|dependency| dependency.dependency_batch_indices.iter().copied()),
            )
            .chain(
                execution_shard
                    .batch_dependents
                    .iter()
                    .map(|dependents| dependents.batch_index),
            )
            .chain(
                execution_shard
                    .batch_dependents
                    .iter()
                    .flat_map(|dependents| dependents.dependent_batch_indices.iter().copied()),
            )
        {
            batch_count = batch_count.max(batch_index.checked_add(1).ok_or_else(|| {
                artifact_shard_contract_error(format!(
                    "execution shard {} batch index overflows inferred batch count",
                    execution_shard.shard.shard_index
                ))
            })?);
        }
        for range in execution_shard
            .batch_dependencies
            .iter()
            .flat_map(|dependency| dependency.dependency_batch_ranges.iter())
        {
            batch_count = batch_count.max(range.end_batch_index().ok_or_else(|| {
                artifact_shard_contract_error(format!(
                    "execution shard {} dependency range overflows inferred batch count",
                    execution_shard.shard.shard_index
                ))
            })?);
        }
        Ok(batch_count)
    }

    pub fn load_build_artifact_shard_index_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildArtifactShardIndex, CompileError> {
        let path = self.artifact_shard_index_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack build artifact shard index {}: {err}",
                path.display()
            ))
        })?;
        let index =
            serde_json::from_slice::<SourcePackBuildArtifactShardIndex>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack build artifact shard index {}: {err}",
                    path.display()
                ))
            })?;
        validate_artifact_shard_index(&index)?;
        if index.target != target {
            return Err(artifact_shard_contract_error(format!(
                "loaded shard index target {:?} does not match requested target {:?}",
                index.target, target
            )));
        }
        Ok(index)
    }

    pub fn load_link_input_shard_index_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildLinkInputShardIndex, CompileError> {
        let path = self.link_input_shard_index_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack link input shard index {}: {err}",
                path.display()
            ))
        })?;
        let index = serde_json::from_slice::<SourcePackBuildLinkInputShardIndex>(&bytes).map_err(
            |err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack link input shard index {}: {err}",
                    path.display()
                ))
            },
        )?;
        validate_link_input_shard_index(&index, target)?;
        Ok(index)
    }

    pub fn load_build_artifact_shard_for_target(
        &self,
        target: SourcePackArtifactTarget,
        shard_index: usize,
    ) -> Result<SourcePackBuildArtifactShard, CompileError> {
        let path = self.artifact_shard_path_for_target(target, shard_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack build artifact shard {}: {err}",
                path.display()
            ))
        })?;
        let shard =
            serde_json::from_slice::<SourcePackBuildArtifactShard>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack build artifact shard {}: {err}",
                    path.display()
                ))
            })?;
        validate_artifact_shard(&shard, target)?;
        if shard.shard_index != shard_index {
            return Err(artifact_shard_contract_error(format!(
                "loaded shard {} from {} but requested shard {}",
                shard.shard_index,
                path.display(),
                shard_index
            )));
        }
        Ok(shard)
    }

    pub fn load_build_artifact_execution_shard_for_target(
        &self,
        target: SourcePackArtifactTarget,
        shard_index: usize,
    ) -> Result<SourcePackBuildArtifactExecutionShard, CompileError> {
        let path = self.artifact_execution_shard_path_for_target(target, shard_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack build artifact execution shard {}: {err}",
                path.display()
            ))
        })?;
        let execution_shard = serde_json::from_slice::<SourcePackBuildArtifactExecutionShard>(
            &bytes,
        )
        .map_err(|err| {
            CompileError::GpuFrontend(format!(
                "parse source-pack build artifact execution shard {}: {err}",
                path.display()
            ))
        })?;
        validate_execution_shard(&execution_shard, target)?;
        if execution_shard.shard.shard_index != shard_index {
            return Err(artifact_shard_contract_error(format!(
                "loaded execution shard {} from {} but requested shard {}",
                execution_shard.shard.shard_index,
                path.display(),
                shard_index
            )));
        }
        Ok(execution_shard)
    }

    pub fn load_build_batch_shard_locator_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
    ) -> Result<SourcePackBuildBatchShardLocator, CompileError> {
        let path = self.batch_shard_locator_path_for_target(target, batch_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack batch shard locator {}: {err}",
                path.display()
            ))
        })?;
        let locator =
            serde_json::from_slice::<SourcePackBuildBatchShardLocator>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack batch shard locator {}: {err}",
                    path.display()
                ))
            })?;
        validate_batch_shard_locator(&locator, target, batch_index)?;
        Ok(locator)
    }

    #[cfg(test)]

    pub(in crate::compiler) fn store_path_build_manifest(
        &self,
        manifest: &SourcePackPathBuildManifest,
    ) -> Result<PathBuf, CompileError> {
        self.store_path_build_manifest_with_shard_limits(
            manifest,
            SourcePackBuildShardLimits::default(),
        )
    }

    #[cfg(test)]

    pub(in crate::compiler) fn store_path_build_manifest_with_shard_limits(
        &self,
        manifest: &SourcePackPathBuildManifest,
        shard_limits: SourcePackBuildShardLimits,
    ) -> Result<PathBuf, CompileError> {
        validate_path_manifest(manifest)?;
        store_job_batch_dependents_from_manifest_dependencies(
            self,
            manifest.artifacts.target,
            &manifest.artifacts.batch_dependencies.batches,
            manifest.artifacts.job_batch_count,
        )?;
        let mut link_interface_shard_range = None;
        let mut link_object_shard_range = None;
        let shard_index = manifest.artifacts.try_for_each_build_artifact_shard(
            shard_limits,
            |shard| -> Result<(), CompileError> {
                store_artifact_shard_page(self, shard)?;
                store_batch_shard_locators(self, shard)?;
                let execution_shard = build_artifact_execution_shard(manifest, shard)?;
                self.store_build_artifact_execution_shard_with_batch_count(
                    &execution_shard,
                    Some(manifest.artifacts.job_batch_count),
                )?;
                match shard.kind {
                    SourcePackBuildArtifactShardKind::LinkInterfaceBatches => {
                        extend_link_input_shard_range(
                            &mut link_interface_shard_range,
                            shard.shard_index,
                            "interface",
                        )?;
                    }
                    SourcePackBuildArtifactShardKind::LinkObjectBatches => {
                        extend_link_input_shard_range(
                            &mut link_object_shard_range,
                            shard.shard_index,
                            "object",
                        )?;
                    }
                    SourcePackBuildArtifactShardKind::JobBatches => {}
                }
                Ok(())
            },
        )?;
        let link_input_index = SourcePackBuildLinkInputShardIndex {
            version: SOURCE_PACK_BUILD_LINK_INPUT_SHARD_INDEX_VERSION,
            target: manifest.artifacts.target,
            link_interface_shard_range,
            link_object_shard_range,
        };
        validate_link_input_shard_index(&link_input_index, manifest.artifacts.target)?;
        store_artifact_shard_compact_indexes(self, &shard_index, &link_input_index)?;
        self.store_initial_build_progress_shards(&shard_index)?;
        self.store_compact_path_build_manifest(manifest)
    }

    pub fn store_compact_path_build_manifest(
        &self,
        manifest: &SourcePackPathBuildManifest,
    ) -> Result<PathBuf, CompileError> {
        validate_path_manifest(manifest)?;
        let path = self.build_manifest_path_for_target(manifest.artifacts.target);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "create source-pack path build manifest directory {}: {err}",
                    parent.display()
                ))
            })?;
        }
        let compact_manifest = SourcePackPathBuildManifest {
            source_files: Vec::new(),
            library_dependencies: Vec::new(),
            artifacts: compact_artifact_manifest(&manifest.artifacts)?,
            ..manifest.clone()
        };
        validate_path_manifest(&compact_manifest)?;
        let bytes = serde_json::to_vec_pretty(&compact_manifest).map_err(|err| {
            CompileError::GpuFrontend(format!("serialize source-pack path build manifest: {err}"))
        })?;
        write_file_atomic(&path, &bytes, "source-pack path build manifest")?;
        Ok(path)
    }

    pub fn load_path_build_manifest_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackPathBuildManifest, CompileError> {
        let path = self.build_manifest_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack path build manifest {}: {err}",
                path.display()
            ))
        })?;
        let manifest =
            serde_json::from_slice::<SourcePackPathBuildManifest>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack path build manifest {}: {err}",
                    path.display()
                ))
            })?;
        validate_path_manifest(&manifest)?;
        Ok(manifest)
    }
}
