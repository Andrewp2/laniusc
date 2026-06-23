use super::*;

/// File-backed advisory lock for source-pack build-state updates.
///
/// The lock is represented by a marker file and removed on drop. It is used to
/// avoid concurrent writers racing while compact build state and progress
/// summaries are being reconciled.
#[derive(Debug)]
pub(in crate::compiler) struct BuildStateLock {
    /// Path of the marker file removed when the lock is dropped.
    pub(in crate::compiler) path: PathBuf,
}

impl Drop for BuildStateLock {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

fn validate_build_state_version_for_store(
    state: &SourcePackBuildState,
) -> Result<(), CompileError> {
    if state.version != SOURCE_PACK_BUILD_STATE_VERSION {
        return Err(source_pack_store_metadata_error(format!(
            "unsupported source-pack build state version {}; expected {}",
            state.version, SOURCE_PACK_BUILD_STATE_VERSION
        )));
    }
    Ok(())
}

/// Checks that compact build state agrees with the persisted progress summary.
///
/// When a progress summary exists, it is the authoritative state for completed
/// and claimed batch counts. Compact build state may mirror that summary, but it
/// cannot introduce a linked output key without the corresponding progress shard.
pub(in crate::compiler) fn validate_build_state_progress_summary(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    state: &SourcePackBuildState,
) -> Result<(), CompileError> {
    validate_build_state_version_for_store(state)?;
    let summary = store.load_build_progress_summary_for_target(target)?;
    if state.completed_batch_count != summary.completed_batch_count {
        return Err(source_pack_progress_state_error(format!(
            "compact source-pack build state records {} completed batches, but persisted progress summary records {}",
            state.completed_batch_count, summary.completed_batch_count
        )));
    }
    if state.claimed_batch_count != summary.claimed_batch_count {
        return Err(source_pack_progress_state_error(format!(
            "compact source-pack build state records {} claimed batches, but persisted progress summary records {}",
            state.claimed_batch_count, summary.claimed_batch_count
        )));
    }
    if let Some(linked_output_key) = &state.linked_output_key {
        if summary
            .linked_output_key
            .as_ref()
            .is_some_and(|existing| existing != linked_output_key)
        {
            return Err(source_pack_progress_state_error(format!(
                "source-pack progress summary already recorded linked output {:?}, cannot replace with {:?}",
                summary.linked_output_key.as_deref(),
                linked_output_key
            )));
        }
        if summary.linked_output_key.is_none() {
            return Err(source_pack_progress_state_error(
                "compact source-pack build state cannot introduce a linked output key; write the producing progress shard instead",
            ));
        }
    }
    Ok(())
}

impl FilesystemArtifactStore {
    /// Attempts to acquire the per-target build-state writer lock.
    ///
    /// The lock creation uses `create_new` so an existing marker is treated as
    /// an active writer rather than being overwritten.
    pub(in crate::compiler) fn try_lock_build_state_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<BuildStateLock, CompileError> {
        let path = self.build_state_lock_path_for_target(target);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|err| {
                source_pack_store_metadata_error(format!(
                    "create source-pack build state lock directory {}: {err}",
                    parent.display()
                ))
            })?;
        }
        match fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&path)
        {
            Ok(_) => Ok(BuildStateLock { path }),
            Err(err) if err.kind() == std::io::ErrorKind::AlreadyExists => {
                Err(source_pack_store_metadata_error(format!(
                    "source-pack build state lock is already held at {}",
                    path.display()
                )))
            }
            Err(err) => Err(source_pack_store_metadata_error(format!(
                "create source-pack build state lock {}: {err}",
                path.display()
            ))),
        }
    }

    /// Returns whether the target has the newer progress-summary state file.
    ///
    /// Callers use this to decide whether compact build state should be loaded
    /// directly or reconstructed from progress-summary records.
    pub(in crate::compiler) fn progress_summary_available_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> bool {
        self.build_progress_summary_path_for_target(target)
            .is_file()
    }

    /// Stores compact build state for a target after reconciling progress summary state.
    ///
    /// If a progress summary has already been written, the compact state must
    /// match it before the root build-state marker is persisted.
    pub fn store_build_state_for_target(
        &self,
        target: SourcePackArtifactTarget,
        state: &SourcePackBuildState,
    ) -> Result<PathBuf, CompileError> {
        validate_build_state_version_for_store(state)?;
        if self.progress_summary_available_for_target(target) {
            validate_build_state_progress_summary(self, target, state)?;
        }
        let stored_state = root_build_state_marker(state);
        self.store_build_state_file_for_target(target, &stored_state)
    }

    /// Stores only the root build-state marker for a target.
    ///
    /// This helper skips progress-summary reconciliation and is used by internal
    /// paths that have already established the marker state they need to write.
    pub(in crate::compiler) fn store_build_state_marker_for_target(
        &self,
        target: SourcePackArtifactTarget,
        state: &SourcePackBuildState,
    ) -> Result<PathBuf, CompileError> {
        validate_build_state_version_for_store(state)?;
        self.store_build_state_file_for_target(target, &root_build_state_marker(state))
    }

    /// Writes the build-state JSON file atomically for a target.
    ///
    /// The state is version-checked before serialization so invalid records do
    /// not reach the source-pack store.
    pub(in crate::compiler) fn store_build_state_file_for_target(
        &self,
        target: SourcePackArtifactTarget,
        state: &SourcePackBuildState,
    ) -> Result<PathBuf, CompileError> {
        validate_build_state_version_for_store(state)?;
        let path = self.build_state_path_for_target(target);
        let bytes = serialize_store_json(state, "source-pack build state")?;
        write_store_file_atomic(&path, &bytes, "source-pack build state")?;
        Ok(path)
    }

    #[cfg(test)]
    /// Loads persisted build state for tests.
    ///
    /// Tests exercise both storage forms: direct compact state when no summary
    /// exists, and summary-derived state once progress summaries have been
    /// introduced.
    pub(in crate::compiler) fn load_build_state_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildState, CompileError> {
        if self.progress_summary_available_for_target(target) {
            return load_build_state_from_progress_summary(self, target);
        }
        let path = self.build_state_path_for_target(target);
        let bytes = read_store_file(&path, "source-pack build state")?;
        let state =
            parse_store_json::<SourcePackBuildState>(&bytes, &path, "source-pack build state")?;
        validate_build_state_version_for_store(&state)?;
        Ok(state)
    }

    /// Loads the target build state or returns a fresh empty state.
    ///
    /// Progress summaries take precedence over compact state because they carry
    /// the current execution progress. A missing compact state file means no
    /// work has been persisted yet.
    pub fn load_or_init_build_state_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildState, CompileError> {
        if self.progress_summary_available_for_target(target) {
            return load_build_state_from_progress_summary(self, target);
        }
        let path = self.build_state_path_for_target(target);
        let Some(bytes) = try_read_store_file(&path, "source-pack build state")? else {
            return Ok(SourcePackBuildState::new());
        };
        let state =
            parse_store_json::<SourcePackBuildState>(&bytes, &path, "source-pack build state")?;
        validate_build_state_version_for_store(&state)?;
        Ok(state)
    }
}
