use super::*;

#[derive(Debug)]
pub(in crate::compiler) struct BuildStateLock {
    pub(in crate::compiler) path: PathBuf,
}

impl Drop for BuildStateLock {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

pub(in crate::compiler) fn validate_build_state_progress_summary(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    state: &SourcePackBuildState,
) -> Result<(), CompileError> {
    validate_build_state_version(state)?;
    let summary = store.load_build_progress_summary_for_target(target)?;
    if state.completed_batch_count != summary.completed_batch_count {
        return Err(CompileError::GpuFrontend(format!(
            "compact source-pack build state records {} completed batches, but persisted progress summary records {}",
            state.completed_batch_count, summary.completed_batch_count
        )));
    }
    if state.claimed_batch_count != summary.claimed_batch_count {
        return Err(CompileError::GpuFrontend(format!(
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
            return Err(CompileError::GpuFrontend(format!(
                "source-pack progress summary already recorded linked output {:?}, cannot replace with {:?}",
                summary.linked_output_key.as_deref(),
                linked_output_key
            )));
        }
        if summary.linked_output_key.is_none() {
            return Err(CompileError::GpuFrontend(
                "compact source-pack build state cannot introduce a linked output key; write the producing progress shard instead".into(),
            ));
        }
    }
    Ok(())
}

impl FilesystemArtifactStore {
    pub(in crate::compiler) fn try_lock_build_state_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<BuildStateLock, CompileError> {
        let path = self.build_state_lock_path_for_target(target);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|err| {
                CompileError::GpuFrontend(format!(
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
                Err(CompileError::GpuFrontend(format!(
                    "source-pack build state lock is already held at {}",
                    path.display()
                )))
            }
            Err(err) => Err(CompileError::GpuFrontend(format!(
                "create source-pack build state lock {}: {err}",
                path.display()
            ))),
        }
    }

    pub(in crate::compiler) fn progress_summary_available_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> bool {
        self.build_progress_summary_path_for_target(target)
            .is_file()
    }

    pub fn store_build_state_for_target(
        &self,
        target: SourcePackArtifactTarget,
        state: &SourcePackBuildState,
    ) -> Result<PathBuf, CompileError> {
        validate_build_state_version(state)?;
        if self.progress_summary_available_for_target(target) {
            validate_build_state_progress_summary(self, target, state)?;
        }
        let stored_state = root_build_state_marker(state);
        self.store_build_state_file_for_target(target, &stored_state)
    }

    pub(in crate::compiler) fn store_build_state_marker_for_target(
        &self,
        target: SourcePackArtifactTarget,
        state: &SourcePackBuildState,
    ) -> Result<PathBuf, CompileError> {
        validate_build_state_version(state)?;
        self.store_build_state_file_for_target(target, &root_build_state_marker(state))
    }

    pub(in crate::compiler) fn store_build_state_file_for_target(
        &self,
        target: SourcePackArtifactTarget,
        state: &SourcePackBuildState,
    ) -> Result<PathBuf, CompileError> {
        validate_build_state_version(state)?;
        let path = self.build_state_path_for_target(target);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "create source-pack build state directory {}: {err}",
                    parent.display()
                ))
            })?;
        }
        let bytes = serde_json::to_vec_pretty(state).map_err(|err| {
            CompileError::GpuFrontend(format!("serialize source-pack build state: {err}"))
        })?;
        write_file_atomic(&path, &bytes, "source-pack build state")?;
        Ok(path)
    }

    #[cfg(test)]
    pub(in crate::compiler) fn load_build_state_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildState, CompileError> {
        if self.progress_summary_available_for_target(target) {
            return load_build_state_from_progress_summary(self, target);
        }
        let path = self.build_state_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack build state {}: {err}",
                path.display()
            ))
        })?;
        let state = serde_json::from_slice::<SourcePackBuildState>(&bytes).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "parse source-pack build state {}: {err}",
                path.display()
            ))
        })?;
        validate_build_state_version(&state)?;
        Ok(state)
    }

    pub fn load_or_init_build_state_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildState, CompileError> {
        if self.progress_summary_available_for_target(target) {
            return load_build_state_from_progress_summary(self, target);
        }
        let path = self.build_state_path_for_target(target);
        match fs::read(&path) {
            Ok(bytes) => {
                let state =
                    serde_json::from_slice::<SourcePackBuildState>(&bytes).map_err(|err| {
                        CompileError::GpuFrontend(format!(
                            "parse source-pack build state {}: {err}",
                            path.display()
                        ))
                    })?;
                validate_build_state_version(&state)?;
                Ok(state)
            }
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
                Ok(SourcePackBuildState::new())
            }
            Err(err) => Err(CompileError::GpuFrontend(format!(
                "read source-pack build state {}: {err}",
                path.display()
            ))),
        }
    }
}
