use super::*;

impl ArtifactStore for FilesystemArtifactStore {
    type LibraryInterfaceArtifact = Vec<u8>;
    type CodegenObjectArtifact = Vec<u8>;
    type LinkedOutputArtifact = Vec<u8>;

    fn load_library_interface(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<Self::LibraryInterfaceArtifact, CompileError> {
        read_artifact(&self.root, &artifact.key, "library interface")
    }

    fn store_library_interface(
        &mut self,
        artifact: &SourcePackArtifactRef,
        interface: Self::LibraryInterfaceArtifact,
    ) -> Result<(), CompileError> {
        write_artifact(&self.root, &artifact.key, "library interface", interface)
    }

    fn release_library_interface(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<(), CompileError> {
        remove_artifact(&self.root, &artifact.key, "library interface")
    }

    fn load_codegen_object(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<Self::CodegenObjectArtifact, CompileError> {
        read_artifact(&self.root, &artifact.key, "codegen object")
    }

    fn store_codegen_object(
        &mut self,
        artifact: &SourcePackArtifactRef,
        object: Self::CodegenObjectArtifact,
    ) -> Result<(), CompileError> {
        write_artifact(&self.root, &artifact.key, "codegen object", object)
    }

    fn release_codegen_object(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<(), CompileError> {
        remove_artifact(&self.root, &artifact.key, "codegen object")
    }

    fn store_linked_output(
        &mut self,
        artifact: &SourcePackArtifactRef,
        output: Self::LinkedOutputArtifact,
    ) -> Result<(), CompileError> {
        write_artifact(&self.root, &artifact.key, "linked output", output)
    }
}

impl HierarchicalLinkArtifactStore for FilesystemArtifactStore {
    type PartialLinkArtifact = Vec<u8>;

    fn load_partial_link_output(
        &mut self,
        key: &str,
    ) -> Result<Self::PartialLinkArtifact, CompileError> {
        read_artifact(&self.root, key, "partial link output")
    }

    fn store_partial_link_output(
        &mut self,
        key: &str,
        output: Self::PartialLinkArtifact,
    ) -> Result<(), CompileError> {
        write_artifact(&self.root, key, "partial link output", output)
    }

    fn store_hierarchical_linked_output(
        &mut self,
        key: &str,
        output: Self::LinkedOutputArtifact,
    ) -> Result<(), CompileError> {
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
        artifact_path_handle(self.root(), &artifact.key, "library interface")
    }

    fn store_library_interface(
        &mut self,
        artifact: &SourcePackArtifactRef,
        interface: Self::LibraryInterfaceArtifact,
    ) -> Result<(), CompileError> {
        copy_artifact_file_atomic(self.root(), &artifact.key, "library interface", interface)
    }

    fn release_library_interface(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<(), CompileError> {
        remove_artifact(self.root(), &artifact.key, "library interface")
    }

    fn load_codegen_object(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<Self::CodegenObjectArtifact, CompileError> {
        artifact_path_handle(self.root(), &artifact.key, "codegen object")
    }

    fn store_codegen_object(
        &mut self,
        artifact: &SourcePackArtifactRef,
        object: Self::CodegenObjectArtifact,
    ) -> Result<(), CompileError> {
        copy_artifact_file_atomic(self.root(), &artifact.key, "codegen object", object)
    }

    fn release_codegen_object(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<(), CompileError> {
        remove_artifact(self.root(), &artifact.key, "codegen object")
    }

    fn store_linked_output(
        &mut self,
        artifact: &SourcePackArtifactRef,
        output: Self::LinkedOutputArtifact,
    ) -> Result<(), CompileError> {
        copy_artifact_file_atomic(self.root(), &artifact.key, "linked output", output)
    }
}

impl HierarchicalLinkArtifactStore for ArtifactPathStore {
    type PartialLinkArtifact = ArtifactPath;

    fn load_partial_link_output(
        &mut self,
        key: &str,
    ) -> Result<Self::PartialLinkArtifact, CompileError> {
        artifact_path_handle(self.root(), key, "partial link output")
    }

    fn store_partial_link_output(
        &mut self,
        key: &str,
        output: Self::PartialLinkArtifact,
    ) -> Result<(), CompileError> {
        copy_artifact_file_atomic(self.root(), key, "partial link output", output)
    }

    fn store_hierarchical_linked_output(
        &mut self,
        key: &str,
        output: Self::LinkedOutputArtifact,
    ) -> Result<(), CompileError> {
        copy_artifact_file_atomic(self.root(), key, "linked output", output)
    }
}

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
