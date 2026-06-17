use super::*;

mod artifact_io;
pub(in crate::compiler) use artifact_io::*;
mod artifact_refs;
mod build_progress;
pub(in crate::compiler) use build_progress::update_ready_frontier_after_batch_completion;
mod build_state;
mod execution_loader;
mod job_batches;
mod library;
mod link;
mod link_batches;
mod manifests;
mod paths;
mod schedule;
mod work_queue;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FilesystemArtifactStore {
    pub(in crate::compiler) root: PathBuf,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ArtifactPath {
    pub key: String,
    pub path: PathBuf,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ArtifactPathStore {
    pub(in crate::compiler) inner: FilesystemArtifactStore,
}

impl FilesystemArtifactStore {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn path_for_key(&self, key: &str) -> Result<PathBuf, CompileError> {
        artifact_path(&self.root, key)
    }

    pub fn artifact_exists(&self, artifact: &SourcePackArtifactRef) -> Result<bool, CompileError> {
        Ok(self.path_for_key(&artifact.key)?.is_file())
    }

    pub(in crate::compiler) fn require_artifact_key_file(
        &self,
        key: &str,
        artifact_label: &str,
    ) -> Result<PathBuf, CompileError> {
        let path = self.path_for_key(key)?;
        if !path.is_file() {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack {artifact_label} artifact {key:?} is missing at {}",
                path.display()
            )));
        }
        Ok(path)
    }
}

impl AsRef<FilesystemArtifactStore> for FilesystemArtifactStore {
    fn as_ref(&self) -> &FilesystemArtifactStore {
        self
    }
}

impl ArtifactPathStore {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self {
            inner: FilesystemArtifactStore::new(root),
        }
    }

    pub fn root(&self) -> &Path {
        self.inner.root()
    }

    pub fn path_for_key(&self, key: &str) -> Result<PathBuf, CompileError> {
        self.inner.path_for_key(key)
    }
}

impl AsRef<FilesystemArtifactStore> for ArtifactPathStore {
    fn as_ref(&self) -> &FilesystemArtifactStore {
        &self.inner
    }
}
