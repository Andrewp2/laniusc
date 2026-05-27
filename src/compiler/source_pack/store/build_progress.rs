use super::*;

impl FilesystemArtifactStore {
    pub fn store_build_progress_shard(
        &self,
        shard: &SourcePackBuildProgressShard,
    ) -> Result<PathBuf, CompileError> {
        validate_build_progress_shard(shard)?;
        let old_shard_path =
            self.build_progress_shard_path_for_target(shard.target, shard.shard_index);
        let old_shard = if old_shard_path.is_file() {
            Some(self.load_build_progress_shard_for_target(shard.target, shard.shard_index)?)
        } else {
            None
        };
        let path = self.write_build_progress_shard_file(shard)?;
        let summary = self.update_summary_after_shard_store(old_shard.as_ref(), shard)?;
        self.store_progress_directory_page_for_shard(&summary, shard.shard_index)?;
        Ok(path)
    }

    pub(in crate::compiler) fn write_build_progress_shard_file(
        &self,
        shard: &SourcePackBuildProgressShard,
    ) -> Result<PathBuf, CompileError> {
        validate_build_progress_shard(shard)?;
        let path = self.build_progress_shard_path_for_target(shard.target, shard.shard_index);
        let bytes = serde_json::to_vec_pretty(shard).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack build progress shard {}: {err}",
                shard.shard_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack build progress shard")?;
        self.store_build_progress_shard_summary_for_target(
            shard.target,
            &build_progress_shard_summary(shard)?,
        )?;
        Ok(path)
    }

    pub fn store_build_progress_shard_summary_for_target(
        &self,
        target: SourcePackArtifactTarget,
        summary: &SourcePackBuildProgressShardSummary,
    ) -> Result<PathBuf, CompileError> {
        validate_build_progress_shard_summary(summary)?;
        if summary.target != target {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack progress shard summary target {:?} does not match requested target {:?}",
                summary.target, target
            )));
        }
        let path = self.build_progress_shard_summary_path_for_target(target, summary.shard_index);
        let bytes = serde_json::to_vec_pretty(summary).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack build progress shard summary {}: {err}",
                summary.shard_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack build progress shard summary")?;
        Ok(path)
    }

    pub fn store_build_progress_directory_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        directory_page: &SourcePackBuildProgressDirectoryPage,
        summary: &SourcePackBuildProgressSummary,
    ) -> Result<PathBuf, CompileError> {
        validate_build_progress_directory_page(directory_page, target, summary)?;
        let path = self.build_progress_directory_page_path_for_target(
            target,
            directory_page.directory_page_index,
        );
        let bytes = serde_json::to_vec_pretty(directory_page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack build progress directory page {}: {err}",
                directory_page.directory_page_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack build progress directory page")?;
        Ok(path)
    }

    pub fn try_load_build_progress_directory_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        directory_page_index: usize,
    ) -> Result<Option<SourcePackBuildProgressDirectoryPage>, CompileError> {
        let path = self.build_progress_directory_page_path_for_target(target, directory_page_index);
        let bytes = match fs::read(&path) {
            Ok(bytes) => bytes,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(err) => {
                return Err(CompileError::GpuFrontend(format!(
                    "read source-pack build progress directory page {}: {err}",
                    path.display()
                )));
            }
        };
        let directory_page = serde_json::from_slice::<SourcePackBuildProgressDirectoryPage>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack build progress directory page {}: {err}",
                    path.display()
                ))
            })?;
        if directory_page.version != SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_PAGE_VERSION {
            return Err(CompileError::GpuFrontend(format!(
                "unsupported source-pack build progress directory page version {}; expected {}",
                directory_page.version, SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_PAGE_VERSION
            )));
        }
        if directory_page.target != target
            || directory_page.directory_page_index != directory_page_index
        {
            return Err(CompileError::GpuFrontend(format!(
                "loaded source-pack build progress directory page target {:?} index {} from {} but requested target {:?} index {}",
                directory_page.target,
                directory_page.directory_page_index,
                path.display(),
                target,
                directory_page_index
            )));
        }
        Ok(Some(directory_page))
    }

    pub fn store_build_progress_directory_index_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        directory_index_page: &SourcePackBuildProgressDirectoryIndexPage,
        summary: &SourcePackBuildProgressSummary,
    ) -> Result<PathBuf, CompileError> {
        validate_directory_index_page(directory_index_page, target, summary)?;
        let path = self.build_progress_directory_index_page_path_for_target(
            target,
            directory_index_page.directory_index_page_index,
        );
        let bytes = serde_json::to_vec_pretty(directory_index_page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack build progress directory-index page {}: {err}",
                directory_index_page.directory_index_page_index
            ))
        })?;
        write_file_atomic(
            &path,
            &bytes,
            "source-pack build progress directory-index page",
        )?;
        Ok(path)
    }

    pub fn try_load_build_progress_directory_index_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        directory_index_page_index: usize,
    ) -> Result<Option<SourcePackBuildProgressDirectoryIndexPage>, CompileError> {
        let path = self.build_progress_directory_index_page_path_for_target(
            target,
            directory_index_page_index,
        );
        let bytes = match fs::read(&path) {
            Ok(bytes) => bytes,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(err) => {
                return Err(CompileError::GpuFrontend(format!(
                    "read source-pack build progress directory-index page {}: {err}",
                    path.display()
                )));
            }
        };
        let directory_index_page = serde_json::from_slice::<
            SourcePackBuildProgressDirectoryIndexPage,
        >(&bytes)
        .map_err(|err| {
            CompileError::GpuFrontend(format!(
                "parse source-pack build progress directory-index page {}: {err}",
                path.display()
            ))
        })?;
        if directory_index_page.version != SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_INDEX_PAGE_VERSION {
            return Err(CompileError::GpuFrontend(format!(
                "unsupported source-pack build progress directory-index page version {}; expected {}",
                directory_index_page.version,
                SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_INDEX_PAGE_VERSION
            )));
        }
        if directory_index_page.target != target
            || directory_index_page.directory_index_page_index != directory_index_page_index
        {
            return Err(CompileError::GpuFrontend(format!(
                "loaded source-pack build progress directory-index page target {:?} index {} from {} but requested target {:?} index {}",
                directory_index_page.target,
                directory_index_page.directory_index_page_index,
                path.display(),
                target,
                directory_index_page_index
            )));
        }
        Ok(Some(directory_index_page))
    }

    pub(in crate::compiler) fn store_progress_directory_page_for_shard(
        &self,
        summary: &SourcePackBuildProgressSummary,
        shard_index: usize,
    ) -> Result<PathBuf, CompileError> {
        validate_build_progress_summary(summary)?;
        if shard_index >= summary.job_batch_shard_count {
            return Err(artifact_shard_contract_error(format!(
                "source-pack build progress directory cannot refresh shard {shard_index}; summary has {} shards",
                summary.job_batch_shard_count
            )));
        }
        let directory_page_index = directory_page_index_for_shard(shard_index);
        let directory_page =
            directory_page_from_summaries(self, summary.target, summary, directory_page_index)?;
        let path = self.store_build_progress_directory_page_for_target(
            summary.target,
            &directory_page,
            summary,
        )?;
        let directory_index_page_index = directory_index_page_index_for_page(directory_page_index);
        let directory_index_page = directory_index_page_from_pages(
            self,
            summary.target,
            summary,
            Some(&directory_page),
            directory_index_page_index,
        )?;
        self.store_build_progress_directory_index_page_for_target(
            summary.target,
            &directory_index_page,
            summary,
        )?;
        Ok(path)
    }

    pub(in crate::compiler) fn store_progress_directory_pages_for_summary(
        &self,
        summary: &SourcePackBuildProgressSummary,
    ) -> Result<(), CompileError> {
        let directory_page_count = directory_page_count(summary)?;
        for directory_page_index in 0..directory_page_count {
            let directory_page =
                directory_page_from_summaries(self, summary.target, summary, directory_page_index)?;
            self.store_build_progress_directory_page_for_target(
                summary.target,
                &directory_page,
                summary,
            )?;
        }
        let directory_index_page_count = directory_index_page_count(summary)?;
        for directory_index_page_index in 0..directory_index_page_count {
            let directory_index_page = directory_index_page_from_pages(
                self,
                summary.target,
                summary,
                None,
                directory_index_page_index,
            )?;
            self.store_build_progress_directory_index_page_for_target(
                summary.target,
                &directory_index_page,
                summary,
            )?;
        }
        Ok(())
    }

    pub fn store_build_progress_summary(
        &self,
        summary: &SourcePackBuildProgressSummary,
    ) -> Result<PathBuf, CompileError> {
        validate_build_progress_summary(summary)?;
        let path = self.build_progress_summary_path_for_target(summary.target);
        let compact_summary = summary.clone();
        validate_build_progress_summary(&compact_summary)?;
        let bytes = serde_json::to_vec_pretty(&compact_summary).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack build progress summary: {err}"
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack build progress summary")?;
        Ok(path)
    }

    pub fn load_build_progress_summary_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildProgressSummary, CompileError> {
        let path = self.build_progress_summary_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack build progress summary {}: {err}",
                path.display()
            ))
        })?;
        let summary =
            serde_json::from_slice::<SourcePackBuildProgressSummary>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack build progress summary {}: {err}",
                    path.display()
                ))
            })?;
        validate_build_progress_summary(&summary)?;
        if summary.target != target {
            return Err(CompileError::GpuFrontend(format!(
                "loaded source-pack progress summary target {:?} from {} but requested target {:?}",
                summary.target,
                path.display(),
                target
            )));
        }
        Ok(summary)
    }

    pub fn try_load_build_progress_shard_summary_for_target(
        &self,
        target: SourcePackArtifactTarget,
        shard_index: usize,
    ) -> Result<Option<SourcePackBuildProgressShardSummary>, CompileError> {
        let path = self.build_progress_shard_summary_path_for_target(target, shard_index);
        let bytes = match fs::read(&path) {
            Ok(bytes) => bytes,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(err) => {
                return Err(CompileError::GpuFrontend(format!(
                    "read source-pack build progress shard summary {}: {err}",
                    path.display()
                )));
            }
        };
        let summary = serde_json::from_slice::<SourcePackBuildProgressShardSummary>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack build progress shard summary {}: {err}",
                    path.display()
                ))
            })?;
        validate_build_progress_shard_summary(&summary)?;
        if summary.target != target || summary.shard_index != shard_index {
            return Err(CompileError::GpuFrontend(format!(
                "loaded source-pack progress shard summary target {:?} index {} from {} but requested target {:?} index {}",
                summary.target,
                summary.shard_index,
                path.display(),
                target,
                shard_index
            )));
        }
        Ok(Some(summary))
    }

    pub(in crate::compiler) fn update_summary_after_shard_store(
        &self,
        old_shard: Option<&SourcePackBuildProgressShard>,
        new_shard: &SourcePackBuildProgressShard,
    ) -> Result<SourcePackBuildProgressSummary, CompileError> {
        validate_build_progress_shard(new_shard)?;
        if let Some(old_shard) = old_shard {
            validate_build_progress_shard(old_shard)?;
            if old_shard.target != new_shard.target
                || old_shard.shard_index != new_shard.shard_index
                || old_shard.batch_indices != new_shard.batch_indices
            {
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack progress shard update changed identity from target {:?} index {} batches {:?} to target {:?} index {} batches {:?}",
                    old_shard.target,
                    old_shard.shard_index,
                    old_shard.batch_indices,
                    new_shard.target,
                    new_shard.shard_index,
                    new_shard.batch_indices
                )));
            }
        }
        let old_shard_summary = old_shard.map(build_progress_shard_summary).transpose()?;
        let new_shard_summary = build_progress_shard_summary(new_shard)?;

        let old_completed_count = old_shard
            .map(|shard| shard.completed_batch_indices.len())
            .unwrap_or(0);
        let new_completed_count = new_shard.completed_batch_indices.len();
        let old_ready_count = old_shard
            .map(|shard| shard.ready_batch_indices.len())
            .unwrap_or(0);
        let new_ready_count = new_shard.ready_batch_indices.len();
        let old_claimed_count = old_shard
            .map(|shard| shard.claimed_batches.len())
            .unwrap_or(0);
        let new_claimed_count = new_shard.claimed_batches.len();
        let old_ready_claimed_count = old_shard_summary
            .as_ref()
            .map(|summary| summary.ready_claimed_batch_count)
            .unwrap_or(0);
        let new_ready_claimed_count = new_shard_summary.ready_claimed_batch_count;
        let old_earliest_claim_lease = old_shard_summary
            .as_ref()
            .and_then(|summary| summary.earliest_claim_lease_expires_unix_nanos);
        let new_earliest_claim_lease = new_shard_summary.earliest_claim_lease_expires_unix_nanos;
        let old_first_ready =
            old_shard.and_then(|shard| shard.ready_batch_indices.iter().copied().min());
        let new_first_ready = new_shard.ready_batch_indices.iter().copied().min();
        let old_job_batch_count = old_shard
            .map(|shard| shard.batch_indices.len())
            .unwrap_or(0);
        let new_job_batch_count = new_shard.batch_indices.len();
        let summary_path = self.build_progress_summary_path_for_target(new_shard.target);
        let mut summary = if summary_path.is_file() {
            self.load_build_progress_summary_for_target(new_shard.target)?
        } else {
            SourcePackBuildProgressSummary::new(new_shard.target, 0)
        };
        summary.job_batch_count = summary
            .job_batch_count
            .saturating_add(new_job_batch_count)
            .checked_sub(old_job_batch_count)
            .ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack progress summary underflow updating shard {}",
                    new_shard.shard_index
                ))
            })?;
        summary.job_batch_shard_count = summary
            .job_batch_shard_count
            .max(new_shard.shard_index.saturating_add(1));
        summary.completed_batch_count = summary
            .completed_batch_count
            .saturating_add(new_completed_count)
            .checked_sub(old_completed_count)
            .ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack progress summary completed-count underflow updating shard {}",
                    new_shard.shard_index
                ))
            })?;
        summary.ready_batch_count = summary
            .ready_batch_count
            .saturating_add(new_ready_count)
            .checked_sub(old_ready_count)
            .ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack progress summary ready-count underflow updating shard {}",
                    new_shard.shard_index
                ))
            })?;
        summary.claimed_batch_count = summary
            .claimed_batch_count
            .saturating_add(new_claimed_count)
            .checked_sub(old_claimed_count)
            .ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack progress summary claimed-count underflow updating shard {}",
                    new_shard.shard_index
                ))
            })?;
        let previous_earliest_claim_lease = summary.earliest_claim_lease_expires_unix_nanos;
        summary.ready_claimed_batch_count = summary
            .ready_claimed_batch_count
            .saturating_add(new_ready_claimed_count)
            .checked_sub(old_ready_claimed_count)
            .ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack progress summary ready-claimed-count underflow updating shard {}",
                    new_shard.shard_index
                ))
            })?;
        summary.earliest_claim_lease_expires_unix_nanos = if summary.ready_claimed_batch_count == 0
        {
            None
        } else if previous_earliest_claim_lease == old_earliest_claim_lease
            && old_earliest_claim_lease.is_some()
            && new_earliest_claim_lease.map_or(true, |new_earliest| {
                Some(new_earliest) > old_earliest_claim_lease
            })
        {
            earliest_claim_lease_bounded(
                self,
                new_shard.target,
                &summary,
                Some(new_shard.shard_index),
            )?
        } else {
            earliest_lease_expiry(previous_earliest_claim_lease, new_earliest_claim_lease)
        };
        summary.first_ready_batch_index = if summary.ready_batch_count == 0 {
            None
        } else {
            match (
                summary.first_ready_batch_index,
                old_first_ready,
                new_first_ready,
            ) {
                (Some(summary_first), Some(old_first), new_first)
                    if summary_first == old_first
                        && new_first.map_or(true, |new_first| new_first > old_first) =>
                {
                    first_ready_batch_from_summary_pages(self, new_shard.target, &summary)?
                }
                (summary_first, _, Some(new_first)) => match summary_first {
                    Some(summary_first) => Some(summary_first.min(new_first)),
                    None => Some(new_first),
                },
                (Some(summary_first), _, None) => Some(summary_first),
                (None, _, None) => {
                    first_ready_batch_from_summary_pages(self, new_shard.target, &summary)?
                }
            }
        };
        if let Some(linked_output_key) = &new_shard.linked_output_key {
            if summary
                .linked_output_key
                .as_ref()
                .is_some_and(|existing| existing != linked_output_key)
            {
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack progress summary already recorded linked output {:?}, cannot replace with {:?}",
                    summary.linked_output_key.as_deref(),
                    linked_output_key
                )));
            }
            summary.linked_output_key = Some(linked_output_key.clone());
        }
        self.store_build_progress_summary(&summary)?;
        Ok(summary)
    }

    pub fn load_build_progress_shard_for_target(
        &self,
        target: SourcePackArtifactTarget,
        shard_index: usize,
    ) -> Result<SourcePackBuildProgressShard, CompileError> {
        let path = self.build_progress_shard_path_for_target(target, shard_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack build progress shard {}: {err}",
                path.display()
            ))
        })?;
        let shard =
            serde_json::from_slice::<SourcePackBuildProgressShard>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack build progress shard {}: {err}",
                    path.display()
                ))
            })?;
        validate_build_progress_shard(&shard)?;
        if shard.target != target || shard.shard_index != shard_index {
            return Err(CompileError::GpuFrontend(format!(
                "loaded source-pack progress shard target {:?} index {} from {} but requested target {:?} index {}",
                shard.target,
                shard.shard_index,
                path.display(),
                target,
                shard_index
            )));
        }
        Ok(shard)
    }

    pub(in crate::compiler) fn load_or_init_build_progress_shard_for_target(
        &self,
        target: SourcePackArtifactTarget,
        artifact_shard: &SourcePackBuildArtifactShard,
    ) -> Result<SourcePackBuildProgressShard, CompileError> {
        let path = self.build_progress_shard_path_for_target(target, artifact_shard.shard_index);
        if !path.is_file() {
            return Ok(SourcePackBuildProgressShard::new(target, artifact_shard));
        }
        let shard =
            self.load_build_progress_shard_for_target(target, artifact_shard.shard_index)?;
        validate_progress_shard_matches_artifact_shard(&shard, artifact_shard)?;
        Ok(shard)
    }

    pub fn store_initial_build_progress_shards(
        &self,
        index: &SourcePackBuildArtifactShardIndex,
    ) -> Result<FilesystemBuildProgressShardStoreResult, CompileError> {
        validate_artifact_shard_index(index)?;
        let mut build_progress_shard_count = 0usize;
        let mut ready_batch_count = 0usize;
        let mut first_ready_batch_index = None;
        for_each_job_batch_artifact_shard(self, index.target, index, |shard| {
            let mut progress = SourcePackBuildProgressShard::new(index.target, shard);
            let execution_shard = self
                .load_build_artifact_execution_shard_for_target(index.target, shard.shard_index)?;
            for dependency in &execution_shard.batch_dependencies {
                if !dependency.has_dependencies() {
                    progress.record_batch_ready(dependency.batch_index)?;
                }
            }
            ready_batch_count =
                ready_batch_count.saturating_add(progress.ready_batch_indices.len());
            if let Some(shard_first_ready) = progress.ready_batch_indices.iter().copied().min() {
                if first_ready_batch_index.map_or(true, |first| shard_first_ready < first) {
                    first_ready_batch_index = Some(shard_first_ready);
                }
            }
            self.write_build_progress_shard_file(&progress)?;
            build_progress_shard_count += 1;
            Ok(())
        })?;
        let summary = SourcePackBuildProgressSummary {
            version: SOURCE_PACK_BUILD_PROGRESS_SUMMARY_VERSION,
            target: index.target,
            job_batch_count: index.job_batch_count,
            job_batch_shard_count: build_progress_shard_count,
            completed_batch_count: 0,
            ready_batch_count,
            first_ready_batch_index,
            claimed_batch_count: 0,
            ready_claimed_batch_count: 0,
            earliest_claim_lease_expires_unix_nanos: None,
            linked_output_key: None,
        };
        self.store_build_progress_summary(&summary)?;
        self.store_progress_directory_pages_for_summary(&summary)?;
        Ok(FilesystemBuildProgressShardStoreResult {
            build_progress_shard_count,
        })
    }
}

pub(in crate::compiler) fn update_ready_frontier_after_batch_completion(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    completed_batch_index: usize,
    now_unix_nanos: Option<u128>,
) -> Result<(), CompileError> {
    let summary = store.load_build_progress_summary_for_target(target)?;
    for_each_job_batch_dependent_index(
        store,
        target,
        completed_batch_index,
        summary.job_batch_count,
        |dependent_batch_index| {
            let locator =
                store.load_build_batch_shard_locator_for_target(target, dependent_batch_index)?;
            let dependent_execution_shard = store
                .load_build_artifact_execution_shard_for_target(target, locator.shard_index)?;
            if dependent_execution_shard.shard.kind != SourcePackBuildArtifactShardKind::JobBatches
            {
                return Err(artifact_shard_contract_error(format!(
                    "reverse dependency points to non-job shard {:?}",
                    dependent_execution_shard.shard.kind
                )));
            }
            let mut progress =
                store.load_build_progress_shard_for_target(target, locator.shard_index)?;
            let mut progress_changed = progress.prune_inactive_batch_claims(now_unix_nanos)?;
            if !dependent_execution_shard
                .shard
                .batch_indices
                .contains(&dependent_batch_index)
            {
                return Err(artifact_shard_contract_error(format!(
                    "dependent batch {dependent_batch_index} is not in execution shard {}",
                    locator.shard_index
                )));
            }
            if progress.is_batch_completed(dependent_batch_index) {
                if progress_changed {
                    store.store_build_progress_shard(&progress)?;
                }
                return Ok(());
            }
            let dependency = execution_shard_batch_dependency(
                &dependent_execution_shard,
                dependent_batch_index,
            )?;
            let mut dependencies_complete = true;
            for_each_stored_job_batch_dependency_index(
                store,
                target,
                dependency,
                |dependency_batch_index| {
                    if !batch_completed_from_locator(store, target, dependency_batch_index)? {
                        dependencies_complete = false;
                    }
                    Ok(())
                },
            )?;
            if dependencies_complete {
                let was_ready = progress.is_batch_ready(dependent_batch_index);
                progress.record_batch_ready(dependent_batch_index)?;
                progress_changed = progress_changed || !was_ready;
            } else if progress.remove_ready_batch(dependent_batch_index)? {
                progress_changed = true;
            }
            if progress_changed {
                store.store_build_progress_shard(&progress)?;
            }
            Ok(())
        },
    )?;
    Ok(())
}
