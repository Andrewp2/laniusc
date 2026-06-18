use super::*;

impl ArtifactStore for FilesystemArtifactStore {
    type LibraryInterfaceArtifact = Vec<u8>;
    type CodegenObjectArtifact = Vec<u8>;
    type LinkedOutputArtifact = Vec<u8>;

    fn load_library_interface(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<Self::LibraryInterfaceArtifact, CompileError> {
        validate_store_artifact_ref(
            artifact,
            SourcePackArtifactKind::LibraryInterface,
            "library interface",
        )?;
        read_artifact(&self.root, &artifact.key, "library interface")
    }

    fn store_library_interface(
        &mut self,
        artifact: &SourcePackArtifactRef,
        interface: Self::LibraryInterfaceArtifact,
    ) -> Result<(), CompileError> {
        validate_store_artifact_ref(
            artifact,
            SourcePackArtifactKind::LibraryInterface,
            "library interface",
        )?;
        write_artifact(&self.root, &artifact.key, "library interface", interface)
    }

    fn release_library_interface(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<(), CompileError> {
        validate_store_artifact_ref(
            artifact,
            SourcePackArtifactKind::LibraryInterface,
            "library interface",
        )?;
        remove_artifact(&self.root, &artifact.key, "library interface")
    }

    fn load_codegen_object(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<Self::CodegenObjectArtifact, CompileError> {
        validate_store_artifact_ref(
            artifact,
            SourcePackArtifactKind::CodegenObject,
            "codegen object",
        )?;
        read_artifact(&self.root, &artifact.key, "codegen object")
    }

    fn store_codegen_object(
        &mut self,
        artifact: &SourcePackArtifactRef,
        object: Self::CodegenObjectArtifact,
    ) -> Result<(), CompileError> {
        validate_store_artifact_ref(
            artifact,
            SourcePackArtifactKind::CodegenObject,
            "codegen object",
        )?;
        write_artifact(&self.root, &artifact.key, "codegen object", object)
    }

    fn release_codegen_object(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<(), CompileError> {
        validate_store_artifact_ref(
            artifact,
            SourcePackArtifactKind::CodegenObject,
            "codegen object",
        )?;
        remove_artifact(&self.root, &artifact.key, "codegen object")
    }

    fn store_linked_output(
        &mut self,
        artifact: &SourcePackArtifactRef,
        output: Self::LinkedOutputArtifact,
    ) -> Result<(), CompileError> {
        validate_store_artifact_ref(
            artifact,
            SourcePackArtifactKind::LinkedOutput,
            "linked output",
        )?;
        write_artifact(&self.root, &artifact.key, "linked output", output)
    }
}

impl HierarchicalLinkArtifactStore for FilesystemArtifactStore {
    type PartialLinkArtifact = Vec<u8>;

    fn load_partial_link_output(
        &mut self,
        key: &str,
    ) -> Result<Self::PartialLinkArtifact, CompileError> {
        validate_store_partial_link_key(key, "partial link output")?;
        read_artifact(&self.root, key, "partial link output")
    }

    fn store_partial_link_output(
        &mut self,
        key: &str,
        output: Self::PartialLinkArtifact,
    ) -> Result<(), CompileError> {
        validate_store_partial_link_key(key, "partial link output")?;
        write_artifact(&self.root, key, "partial link output", output)
    }

    fn store_hierarchical_linked_output(
        &mut self,
        key: &str,
        output: Self::LinkedOutputArtifact,
    ) -> Result<(), CompileError> {
        validate_store_linked_output_key(key, "linked output")?;
        write_artifact(&self.root, key, "linked output", output)
    }
}

impl ArtifactStore for ArtifactPathStore {
    type LibraryInterfaceArtifact = ArtifactPath;
    type CodegenObjectArtifact = ArtifactPath;
    type LinkedOutputArtifact = ArtifactPath;

    fn load_library_interface(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<Self::LibraryInterfaceArtifact, CompileError> {
        validate_store_artifact_ref(
            artifact,
            SourcePackArtifactKind::LibraryInterface,
            "library interface",
        )?;
        artifact_path_handle(self.root(), &artifact.key, "library interface")
    }

    fn store_library_interface(
        &mut self,
        artifact: &SourcePackArtifactRef,
        interface: Self::LibraryInterfaceArtifact,
    ) -> Result<(), CompileError> {
        validate_store_artifact_ref(
            artifact,
            SourcePackArtifactKind::LibraryInterface,
            "library interface",
        )?;
        copy_artifact_file_atomic(self.root(), &artifact.key, "library interface", interface)
    }

    fn release_library_interface(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<(), CompileError> {
        validate_store_artifact_ref(
            artifact,
            SourcePackArtifactKind::LibraryInterface,
            "library interface",
        )?;
        remove_artifact(self.root(), &artifact.key, "library interface")
    }

    fn load_codegen_object(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<Self::CodegenObjectArtifact, CompileError> {
        validate_store_artifact_ref(
            artifact,
            SourcePackArtifactKind::CodegenObject,
            "codegen object",
        )?;
        artifact_path_handle(self.root(), &artifact.key, "codegen object")
    }

    fn store_codegen_object(
        &mut self,
        artifact: &SourcePackArtifactRef,
        object: Self::CodegenObjectArtifact,
    ) -> Result<(), CompileError> {
        validate_store_artifact_ref(
            artifact,
            SourcePackArtifactKind::CodegenObject,
            "codegen object",
        )?;
        copy_artifact_file_atomic(self.root(), &artifact.key, "codegen object", object)
    }

    fn release_codegen_object(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<(), CompileError> {
        validate_store_artifact_ref(
            artifact,
            SourcePackArtifactKind::CodegenObject,
            "codegen object",
        )?;
        remove_artifact(self.root(), &artifact.key, "codegen object")
    }

    fn store_linked_output(
        &mut self,
        artifact: &SourcePackArtifactRef,
        output: Self::LinkedOutputArtifact,
    ) -> Result<(), CompileError> {
        validate_store_artifact_ref(
            artifact,
            SourcePackArtifactKind::LinkedOutput,
            "linked output",
        )?;
        copy_artifact_file_atomic(self.root(), &artifact.key, "linked output", output)
    }
}

impl HierarchicalLinkArtifactStore for ArtifactPathStore {
    type PartialLinkArtifact = ArtifactPath;

    fn load_partial_link_output(
        &mut self,
        key: &str,
    ) -> Result<Self::PartialLinkArtifact, CompileError> {
        validate_store_partial_link_key(key, "partial link output")?;
        artifact_path_handle(self.root(), key, "partial link output")
    }

    fn store_partial_link_output(
        &mut self,
        key: &str,
        output: Self::PartialLinkArtifact,
    ) -> Result<(), CompileError> {
        validate_store_partial_link_key(key, "partial link output")?;
        copy_artifact_file_atomic(self.root(), key, "partial link output", output)
    }

    fn store_hierarchical_linked_output(
        &mut self,
        key: &str,
        output: Self::LinkedOutputArtifact,
    ) -> Result<(), CompileError> {
        validate_store_linked_output_key(key, "linked output")?;
        copy_artifact_file_atomic(self.root(), key, "linked output", output)
    }
}

fn validate_store_artifact_ref(
    artifact: &SourcePackArtifactRef,
    expected_kind: SourcePackArtifactKind,
    artifact_label: &str,
) -> Result<(), CompileError> {
    if artifact.kind != expected_kind {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack {artifact_label} artifact ref {} has kind {:?}; expected {:?}",
            artifact.artifact_index, artifact.kind, expected_kind
        )));
    }
    validate_store_artifact_key_kind(&artifact.key, expected_kind, artifact_label)?;
    let key_producer_job_index =
        store_artifact_key_producer_job_index(&artifact.key, expected_kind, artifact_label)?;
    if key_producer_job_index != artifact.producing_job_index {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack {artifact_label} artifact ref {} key {:?} records producer job {} but artifact ref producer job {}",
            artifact.artifact_index,
            artifact.key,
            key_producer_job_index,
            artifact.producing_job_index
        )));
    }
    if artifact.artifact_index != artifact.producing_job_index {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack {artifact_label} artifact ref {} records producer job {}; artifact refs must use the dense producer job as artifact index",
            artifact.artifact_index, artifact.producing_job_index
        )));
    }
    Ok(())
}

fn validate_store_artifact_key_kind(
    key: &str,
    expected_kind: SourcePackArtifactKind,
    artifact_label: &str,
) -> Result<(), CompileError> {
    validate_store_artifact_key_segment(key, expected_kind.key_segment(), artifact_label, || {
        format!("{expected_kind:?} artifact")
    })
}

fn validate_store_partial_link_key(key: &str, artifact_label: &str) -> Result<(), CompileError> {
    validate_store_artifact_key_segment(key, "partial-link", artifact_label, || {
        "partial-link artifact".into()
    })?;
    let payload = strip_store_target_prefix(key);
    let Some(group_and_job) = payload.strip_prefix("partial-link/group-") else {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack {artifact_label} artifact key {key:?} must include a partial-link group"
        )));
    };
    let Some((group_index, job_index)) = group_and_job.split_once("/job-") else {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack {artifact_label} artifact key {key:?} must include a partial-link producer job"
        )));
    };
    validate_store_partial_link_key_index(key, group_index, artifact_label, "group index")?;
    validate_store_partial_link_key_index(key, job_index, artifact_label, "producer job")?;
    Ok(())
}

fn validate_store_linked_output_key(key: &str, artifact_label: &str) -> Result<(), CompileError> {
    validate_store_artifact_key_kind(key, SourcePackArtifactKind::LinkedOutput, artifact_label)?;
    store_artifact_key_producer_job_index(
        key,
        SourcePackArtifactKind::LinkedOutput,
        artifact_label,
    )?;
    Ok(())
}

fn validate_store_artifact_key_segment(
    key: &str,
    expected_segment: &str,
    artifact_label: &str,
    expected_description: impl FnOnce() -> String,
) -> Result<(), CompileError> {
    artifact_path(Path::new(""), key).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "source-pack {artifact_label} artifact key {key:?} is invalid: {err}"
        ))
    })?;
    let payload = strip_store_target_prefix(key);
    let expected_prefix = format!("{expected_segment}/");
    if payload.starts_with(&expected_prefix) {
        return Ok(());
    }
    Err(CompileError::GpuFrontend(format!(
        "source-pack {artifact_label} artifact key {key:?} does not identify a {}",
        expected_description()
    )))
}

fn strip_store_target_prefix(key: &str) -> &str {
    for target in [
        SourcePackArtifactTarget::Wasm,
        SourcePackArtifactTarget::X86_64,
    ] {
        if let Some(prefix) = target.key_prefix() {
            let target_prefix = format!("{prefix}/");
            if let Some(rest) = key.strip_prefix(&target_prefix) {
                return rest;
            }
        }
    }
    key
}

fn store_artifact_key_producer_job_index(
    key: &str,
    expected_kind: SourcePackArtifactKind,
    artifact_label: &str,
) -> Result<usize, CompileError> {
    let payload = strip_store_target_prefix(key);
    let job_and_source = match expected_kind {
        SourcePackArtifactKind::LibraryInterface | SourcePackArtifactKind::CodegenObject => {
            let expected_prefix = format!("{}/lib-", expected_kind.key_segment());
            let Some(suffix) = payload.strip_prefix(&expected_prefix) else {
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack {artifact_label} artifact key {key:?} does not identify a {:?} artifact",
                    expected_kind
                )));
            };
            let Some((library_id, job_and_source)) = suffix.split_once("/job-") else {
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack {artifact_label} artifact key {key:?} must include a library id and producer job"
                )));
            };
            validate_store_artifact_key_usize(key, library_id, artifact_label, "library id")?;
            job_and_source
        }
        SourcePackArtifactKind::LinkedOutput => {
            let expected_prefix = "linked-output/job-";
            let Some(job_and_source) = payload.strip_prefix(expected_prefix) else {
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack {artifact_label} artifact key {key:?} does not identify a LinkedOutput artifact"
                )));
            };
            job_and_source
        }
    };
    let Some((producer_job_index, source_range)) = job_and_source.split_once("/src-") else {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack {artifact_label} artifact key {key:?} must include a source range"
        )));
    };
    let producer_job_index =
        validate_store_artifact_key_usize(key, producer_job_index, artifact_label, "producer job")?;
    let Some((first_source_index, source_end)) = source_range.split_once('-') else {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack {artifact_label} artifact key {key:?} has invalid source range"
        )));
    };
    let first_source_index =
        validate_store_artifact_key_usize(key, first_source_index, artifact_label, "first source")?;
    let source_end =
        validate_store_artifact_key_usize(key, source_end, artifact_label, "source end")?;
    if source_end <= first_source_index {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack {artifact_label} artifact key {key:?} has empty source range {first_source_index}..{source_end}"
        )));
    }
    Ok(producer_job_index)
}

fn validate_store_artifact_key_usize(
    key: &str,
    value: &str,
    artifact_label: &str,
    field: &str,
) -> Result<usize, CompileError> {
    if value.is_empty() || !value.as_bytes().iter().all(|byte| byte.is_ascii_digit()) {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack {artifact_label} artifact key {key:?} has invalid {field}"
        )));
    }
    if value.len() > 1 && value.starts_with('0') {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack {artifact_label} artifact key {key:?} has non-canonical {field} {value:?}; expected no leading zeroes"
        )));
    }
    value.parse::<usize>().map_err(|err| {
        CompileError::GpuFrontend(format!(
            "source-pack {artifact_label} artifact key {key:?} has invalid {field}: {err}"
        ))
    })
}

fn validate_store_partial_link_key_index(
    key: &str,
    value: &str,
    artifact_label: &str,
    field: &str,
) -> Result<(), CompileError> {
    if value.len() < 8 || !value.as_bytes().iter().all(|byte| byte.is_ascii_digit()) {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack {artifact_label} artifact key {key:?} has invalid partial-link {field}; expected at least eight digits"
        )));
    }
    if value.len() > 8 && value.starts_with('0') {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack {artifact_label} artifact key {key:?} has non-canonical partial-link {field} {value:?}; widened partial-link indices must not carry leading zeroes"
        )));
    }
    value.parse::<usize>().map_err(|err| {
        CompileError::GpuFrontend(format!(
            "source-pack {artifact_label} artifact key {key:?} has invalid partial-link {field}: {err}"
        ))
    })?;
    Ok(())
}

/// Resolves an artifact key to a normal relative path under a store root.
///
/// Empty keys, absolute paths, parent-directory components, and other
/// non-normal components are rejected before any filesystem operation occurs.
pub(in crate::compiler) fn artifact_path(root: &Path, key: &str) -> Result<PathBuf, CompileError> {
    if key.is_empty() {
        return Err(CompileError::GpuFrontend(
            "source-pack artifact key cannot be empty".into(),
        ));
    }

    let mut path = root.to_path_buf();
    for component in Path::new(key).components() {
        match component {
            std::path::Component::Normal(segment) => path.push(segment),
            _ => {
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack artifact key {key:?} is not relative and normal"
                )));
            }
        }
    }
    Ok(path)
}

/// Reads an artifact payload from the filesystem store.
pub(in crate::compiler) fn read_artifact(
    root: &Path,
    key: &str,
    artifact_label: &str,
) -> Result<Vec<u8>, CompileError> {
    let path = artifact_path(root, key)?;
    fs::read(&path).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "read source-pack {artifact_label} artifact {key:?} from {}: {err}",
            path.display()
        ))
    })
}

/// Writes an artifact payload to the filesystem store.
///
/// Parent directories are created before the artifact bytes are written.
pub(in crate::compiler) fn write_artifact(
    root: &Path,
    key: &str,
    artifact_label: &str,
    bytes: Vec<u8>,
) -> Result<(), CompileError> {
    let path = artifact_path(root, key)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "create source-pack {artifact_label} artifact directory {}: {err}",
                parent.display()
            ))
        })?;
    }
    fs::write(&path, bytes).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "write source-pack {artifact_label} artifact {key:?} to {}: {err}",
            path.display()
        ))
    })
}

/// Writes a metadata file by replacing it with a temporary file in the same directory.
///
/// The temporary file name includes the process ID and current time so concurrent
/// attempts do not reuse the same temporary path.
pub(in crate::compiler) fn write_file_atomic(
    path: &Path,
    bytes: &[u8],
    label: &str,
) -> Result<(), CompileError> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "create {label} directory {}: {err}",
                parent.display()
            ))
        })?;
    }
    let file_name = path.file_name().ok_or_else(|| {
        CompileError::GpuFrontend(format!("{label} path {} has no file name", path.display()))
    })?;
    let mut tmp_file_name = file_name.to_os_string();
    tmp_file_name.push(format!(
        ".tmp-{}-{}",
        std::process::id(),
        current_unix_nanos()?
    ));
    let tmp_path = path.with_file_name(tmp_file_name);

    fs::write(&tmp_path, bytes).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "write temporary {label} {}: {err}",
            tmp_path.display()
        ))
    })?;
    fs::rename(&tmp_path, path).map_err(|err| {
        let _ = fs::remove_file(&tmp_path);
        CompileError::GpuFrontend(format!(
            "replace {label} {} with {}: {err}",
            path.display(),
            tmp_path.display()
        ))
    })?;
    Ok(())
}

/// Returns a path handle for an existing artifact file.
///
/// This is used by stores that pass artifact files by path instead of loading
/// their bytes into memory.
pub(in crate::compiler) fn artifact_path_handle(
    root: &Path,
    key: &str,
    artifact_label: &str,
) -> Result<ArtifactPath, CompileError> {
    let path = artifact_path(root, key)?;
    if !path.is_file() {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack {artifact_label} artifact {key:?} is missing at {}",
            path.display()
        )));
    }
    Ok(ArtifactPath {
        key: key.to_string(),
        path,
    })
}

/// Copies an artifact path handle into the filesystem store atomically.
///
/// If the source already points at the destination file, the function verifies
/// the file exists and returns without copying.
pub(in crate::compiler) fn copy_artifact_file_atomic(
    root: &Path,
    key: &str,
    artifact_label: &str,
    artifact: ArtifactPath,
) -> Result<(), CompileError> {
    let path = artifact_path(root, key)?;
    if artifact.path == path {
        if path.is_file() {
            return Ok(());
        }
        return Err(CompileError::GpuFrontend(format!(
            "source-pack {artifact_label} artifact {key:?} was returned at {} but the file is missing",
            path.display()
        )));
    }
    if !artifact.path.is_file() {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack {artifact_label} artifact source {} for key {:?} is missing",
            artifact.path.display(),
            artifact.key
        )));
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "create source-pack {artifact_label} artifact directory {}: {err}",
                parent.display()
            ))
        })?;
    }
    let file_name = path.file_name().ok_or_else(|| {
        CompileError::GpuFrontend(format!(
            "source-pack {artifact_label} artifact path {} has no file name",
            path.display()
        ))
    })?;
    let mut tmp_file_name = file_name.to_os_string();
    tmp_file_name.push(format!(
        ".tmp-{}-{}",
        std::process::id(),
        current_unix_nanos()?
    ));
    let tmp_path = path.with_file_name(tmp_file_name);
    fs::copy(&artifact.path, &tmp_path).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "copy source-pack {artifact_label} artifact {:?} from {} to temporary {}: {err}",
            artifact.key,
            artifact.path.display(),
            tmp_path.display()
        ))
    })?;
    fs::rename(&tmp_path, &path).map_err(|err| {
        let _ = fs::remove_file(&tmp_path);
        CompileError::GpuFrontend(format!(
            "replace source-pack {artifact_label} artifact {key:?} at {} with temporary {}: {err}",
            path.display(),
            tmp_path.display()
        ))
    })
}

/// Removes an artifact file from the filesystem store.
///
/// Missing artifacts are treated as already released.
pub(in crate::compiler) fn remove_artifact(
    root: &Path,
    key: &str,
    artifact_label: &str,
) -> Result<(), CompileError> {
    let path = artifact_path(root, key)?;
    match fs::remove_file(&path) {
        Ok(()) => Ok(()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(err) => Err(CompileError::GpuFrontend(format!(
            "release source-pack {artifact_label} artifact {key:?} at {}: {err}",
            path.display()
        ))),
    }
}
