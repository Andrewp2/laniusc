use std::{
    collections::{BTreeMap, BTreeSet},
    fmt::Write as _,
    fs,
    path::{Path, PathBuf},
};

use serde::{Deserialize, Deserializer, Serialize, Serializer, de::Error as _, ser::Error as _};

use super::{
    package_manifest::{
        PACKAGE_NAME_RULES,
        is_lani_source_path,
        package_source_root_relative_module_path_with_label,
        resolved_paths_overlap,
        valid_package_name,
    },
    write_file_atomic,
};
mod artifacts;
mod import_graph;
mod source_scan;
pub use artifacts::PackageLockfileArtifact;
use artifacts::PackageLockfileArtifacts;
use import_graph::{
    PackageLockfileImportEdge,
    PackageLockfileImportGraph,
    PackageLockfileImportSearchRoot,
    PackageLockfileResolvedImport,
    compare_import_edge_identity,
    import_graph_edge_summary,
    import_graph_reachable_files_from_entry,
    validate_import_graph_module_endpoint,
};
use source_scan::{
    LeadingImportPath,
    leading_import_path_records_for_module,
    leading_import_paths_for_module,
    package_name_module_path,
    required_leading_module_path,
    valid_module_path,
};

use crate::compiler::{
    CompileError,
    Diagnostic,
    EntrySourceRoots,
    ExplicitSourcePack,
    ExplicitSourcePackPathManifest,
    PACKAGE_MANIFEST_MAX_ROOTS,
    ResolvedPackageManifest,
    diagnostic_label_from_source_span,
    load_entry_path_manifest_with_source_roots,
    load_entry_with_source_roots,
};

pub const PACKAGE_LOCKFILE_VERSION: u32 = 1;
pub const PACKAGE_LOCKFILE_LANGUAGE_EDITION: &str = "unstable-alpha";
const PACKAGE_LOCKFILE_COMPILER_VERSION: &str = env!("CARGO_PKG_VERSION");
const PACKAGE_LOCKFILE_DIGEST_ALGORITHM: &str = "lanius-fnv1a64-v1";
const PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID: u32 = 0;
const PACKAGE_LOCKFILE_USER_LIBRARY_ID: u32 = 1;

/// Persisted package loading metadata. Paths are resolved control-plane inputs;
/// recorded module declarations and import endpoints are source identity
/// metadata only. Semantic module identity remains owned by GPU-parsed
/// module/import records.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PackageLockfile {
    pub version: u32,
    pub package: String,
    pub language_edition: String,
    pub compiler_version: String,
    pub roots: Vec<PathBuf>,
    pub stdlib_root: Option<PathBuf>,
    pub entry: PathBuf,
    pub artifacts: Vec<PackageLockfileArtifact>,
    replay_integrity: Option<PackageLockfileReplayIntegrity>,
}

impl<'de> Deserialize<'de> for PackageLockfile {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let document = PackageLockfileDocument::deserialize(deserializer)?;
        document.to_validated_lockfile().map_err(D::Error::custom)
    }
}

impl Serialize for PackageLockfile {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        self.to_document_for_serialization()
            .map_err(S::Error::custom)?
            .serialize(serializer)
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct PackageLockfileInputs {
    digest_algorithm: String,
    files: Vec<PackageLockfileInputFile>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct PackageLockfileInputFile {
    library_id: u32,
    path: PathBuf,
    byte_len: usize,
    digest: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct PackageLockfileSourceIdentities {
    files: Vec<PackageLockfileSourceIdentityFile>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct PackageLockfileSourceIdentityFile {
    library_id: u32,
    path: PathBuf,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    source_root_index: Option<usize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    source_root_relative_path: Option<PathBuf>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    module_path: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct PackageLockfileReplayIntegrity {
    inputs: PackageLockfileInputs,
    source_identities: PackageLockfileSourceIdentities,
    import_graph: PackageLockfileImportGraph,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct PackageLockfileDocument {
    version: u32,
    package: String,
    language_edition: String,
    compiler_version: String,
    roots: Vec<PathBuf>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    stdlib_root: Option<PathBuf>,
    entry: PathBuf,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    inputs: Option<PackageLockfileInputs>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    source_identities: Option<PackageLockfileSourceIdentities>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    import_graph: Option<PackageLockfileImportGraph>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    artifacts: Option<PackageLockfileArtifacts>,
}

impl PackageLockfile {
    pub fn from_resolved_manifest(
        manifest: &ResolvedPackageManifest,
    ) -> Result<Self, CompileError> {
        let lockfile = Self {
            version: PACKAGE_LOCKFILE_VERSION,
            package: manifest.package.clone(),
            language_edition: PACKAGE_LOCKFILE_LANGUAGE_EDITION.to_string(),
            compiler_version: PACKAGE_LOCKFILE_COMPILER_VERSION.to_string(),
            roots: manifest.roots.clone(),
            stdlib_root: manifest.stdlib_root.clone(),
            entry: manifest.entry.clone(),
            artifacts: Vec::new(),
            replay_integrity: None,
        };
        lockfile.validate()?;
        Ok(lockfile)
    }

    pub fn parse_json(source: &str) -> Result<Self, CompileError> {
        Self::parse_document(source)?.to_validated_lockfile()
    }

    pub fn load_json_file(path: impl AsRef<Path>) -> Result<Self, CompileError> {
        let path = path.as_ref();
        let source = fs::read_to_string(path).map_err(|err| {
            CompileError::GpuFrontend(format!("read package lockfile {}: {err}", path.display()))
        })?;
        let document = Self::parse_document(&source)?;
        let lockfile_shape = document.to_lockfile();
        lockfile_shape.validate_shape()?;
        lockfile_shape
            .validate_control_plane_path_is_outside_source_roots("lockfile path", path)?;
        lockfile_shape
            .validate_control_plane_path_is_not_recorded_artifact("lockfile path", path)?;
        document.to_validated_lockfile()
    }

    fn parse_document(source: &str) -> Result<PackageLockfileDocument, CompileError> {
        serde_json::from_str::<PackageLockfileDocument>(source)
            .map_err(|err| CompileError::GpuFrontend(format!("parse package lockfile JSON: {err}")))
    }

    pub fn to_json_pretty(&self) -> Result<String, CompileError> {
        let document = self.to_document_for_serialization()?;
        serde_json::to_string_pretty(&document).map_err(|err| {
            CompileError::GpuFrontend(format!("serialize package lockfile JSON: {err}"))
        })
    }

    pub fn write_json_file(&self, path: impl AsRef<Path>) -> Result<(), CompileError> {
        let path = path.as_ref();
        self.validate_control_plane_path_is_outside_source_roots("lockfile output path", path)?;
        let source = self.to_json_pretty()?;
        self.validate_control_plane_path_is_not_recorded_artifact("lockfile output path", path)?;
        write_file_atomic(path, source.as_bytes(), "package lockfile")
    }

    fn validate_control_plane_path_is_outside_source_roots(
        &self,
        label: &str,
        path: &Path,
    ) -> Result<(), CompileError> {
        let control_plane_paths = lockfile_control_plane_identity_paths(path);
        if control_plane_paths.is_empty() {
            return Ok(());
        }
        for control_plane_path in control_plane_paths {
            if self
                .roots
                .iter()
                .any(|root| control_plane_path.starts_with(root))
            {
                return Err(package_lockfile_error(format!(
                    "{label} {} is inside a package source root; choose a separate lockfile path so package source files and control-plane artifacts stay separate",
                    control_plane_path.display()
                )));
            }
            if self
                .stdlib_root
                .as_ref()
                .is_some_and(|root| control_plane_path.starts_with(root))
            {
                return Err(package_lockfile_error(format!(
                    "{label} {} is inside a stdlib source root; choose a separate lockfile path so stdlib source files and control-plane artifacts stay separate",
                    control_plane_path.display()
                )));
            }
        }
        Ok(())
    }

    fn validate_control_plane_path_is_not_recorded_artifact(
        &self,
        label: &str,
        path: &Path,
    ) -> Result<(), CompileError> {
        let control_plane_paths = lockfile_control_plane_identity_paths(path);
        if control_plane_paths.is_empty() {
            return Ok(());
        }
        for control_plane_path in control_plane_paths {
            if self
                .artifacts
                .iter()
                .any(|artifact| artifact.path.as_path() == control_plane_path.as_path())
            {
                return Err(package_lockfile_error(format!(
                    "{label} {} is also recorded as a produced artifact; package lockfiles are control-plane metadata and must not be replayed as build artifacts",
                    control_plane_path.display()
                )));
            }
        }
        Ok(())
    }

    fn to_document_for_serialization(&self) -> Result<PackageLockfileDocument, CompileError> {
        self.validate_shape_and_existing_source_state()?;
        self.validate_replay_integrity()?;
        self.validate_entry_replay_metadata()?;
        let path_manifest = self.load_path_manifest_without_input_validation()?;
        self.validate_path_manifest_file_set(&path_manifest)?;
        let inputs = Self::input_identity_from_path_manifest(&path_manifest)?;
        let source_identities = self.source_identities_from_path_manifest(&path_manifest)?;
        let import_graph = self.import_graph_from_path_manifest(&path_manifest)?;
        self.validate_artifact_source_collisions(&inputs)?;
        let artifacts = PackageLockfileArtifacts::from_files(self.artifacts.clone())?;
        self.validate_artifacts()?;
        Ok(PackageLockfileDocument::from_lockfile(
            self,
            Some(inputs),
            Some(source_identities),
            Some(import_graph),
            artifacts,
        ))
    }
}

fn lockfile_control_plane_identity_paths(path: &Path) -> Vec<PathBuf> {
    let mut paths = Vec::with_capacity(2);
    if let Some(path) = lockfile_normalized_absolute_path(path) {
        paths.push(path);
    }
    if let Some(path) = lockfile_output_identity_path(path) {
        if !paths.iter().any(|candidate| candidate == &path) {
            paths.push(path);
        }
    }
    paths
}

fn format_resolved_roots(roots: &[PathBuf]) -> String {
    roots
        .iter()
        .map(|root| root.display().to_string())
        .collect::<Vec<_>>()
        .join(", ")
}

fn lockfile_normalized_absolute_path(path: &Path) -> Option<PathBuf> {
    let absolute_path = if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir().ok()?.join(path)
    };
    let mut normalized = PathBuf::new();
    for component in absolute_path.components() {
        match component {
            std::path::Component::Prefix(prefix) => normalized.push(prefix.as_os_str()),
            std::path::Component::RootDir => normalized.push(component.as_os_str()),
            std::path::Component::Normal(segment) => normalized.push(segment),
            std::path::Component::CurDir => {}
            std::path::Component::ParentDir => {
                if !normalized.pop() {
                    return None;
                }
            }
        }
    }
    Some(normalized)
}

fn lockfile_output_identity_path(path: &Path) -> Option<PathBuf> {
    if let Ok(canonical_path) = fs::canonicalize(path) {
        return Some(canonical_path);
    }

    let absolute_path = if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir().ok()?.join(path)
    };
    let mut existing_prefix = absolute_path.as_path();

    loop {
        if let Ok(canonical_prefix) = fs::canonicalize(existing_prefix) {
            let missing_tail = absolute_path.strip_prefix(existing_prefix).ok()?;
            return apply_missing_output_tail(canonical_prefix, missing_tail);
        }
        existing_prefix = existing_prefix.parent()?;
    }
}

fn apply_missing_output_tail(mut base: PathBuf, tail: &Path) -> Option<PathBuf> {
    for component in tail.components() {
        match component {
            std::path::Component::Normal(segment) => base.push(segment),
            std::path::Component::CurDir => {}
            std::path::Component::ParentDir => {
                if !base.pop() {
                    return None;
                }
            }
            std::path::Component::Prefix(_) | std::path::Component::RootDir => return None,
        }
    }
    Some(base)
}

impl PackageLockfile {
    pub fn validate(&self) -> Result<(), CompileError> {
        self.validate_shape_and_existing_source_state()?;
        self.validate_replay_integrity()?;
        self.validate_artifacts()
    }

    fn validate_shape_and_existing_source_state(&self) -> Result<(), CompileError> {
        self.validate_shape()?;
        self.validate_existing_package_source_state()
    }

    fn validate_shape(&self) -> Result<(), CompileError> {
        if self.version != PACKAGE_LOCKFILE_VERSION {
            return Err(package_lockfile_error(format!(
                "unsupported version {}; expected {PACKAGE_LOCKFILE_VERSION}",
                self.version
            )));
        }
        if self.language_edition != PACKAGE_LOCKFILE_LANGUAGE_EDITION {
            return Err(package_lockfile_error(format!(
                "unsupported language edition {:?}; expected {PACKAGE_LOCKFILE_LANGUAGE_EDITION:?}",
                self.language_edition
            )));
        }
        if self.compiler_version.trim().is_empty() {
            return Err(package_lockfile_error("compiler version must not be empty"));
        }
        if !valid_package_name(&self.package) {
            return Err(package_lockfile_error(format!(
                "invalid package name {:?}; {PACKAGE_NAME_RULES}",
                self.package,
            )));
        }
        if self.roots.is_empty() {
            return Err(package_lockfile_error(
                "lockfile must declare at least one resolved source root",
            ));
        }
        if self.roots.len() > PACKAGE_MANIFEST_MAX_ROOTS {
            return Err(package_lockfile_error(format!(
                "lockfile declares {} source roots; maximum is {PACKAGE_MANIFEST_MAX_ROOTS}",
                self.roots.len()
            )));
        }

        let mut seen_roots = BTreeSet::new();
        for root in &self.roots {
            validate_resolved_source_root_path("source root", root)?;
            if !seen_roots.insert(root.clone()) {
                return Err(package_lockfile_error(format!(
                    "duplicate resolved source root {}",
                    root.display()
                )));
            }
        }
        let mut sorted_roots = self.roots.clone();
        sorted_roots.sort();
        if sorted_roots != self.roots {
            return Err(package_lockfile_error(
                "resolved source roots must be sorted in canonical path order; regenerate the package lockfile from the package manifest",
            ));
        }
        for (index, root) in self.roots.iter().enumerate() {
            for other in self.roots.iter().skip(index + 1) {
                if resolved_paths_overlap(root, other) {
                    return Err(package_lockfile_error(format!(
                        "overlapping resolved source roots {} and {}",
                        root.display(),
                        other.display()
                    )));
                }
            }
        }
        if let Some(stdlib_root) = &self.stdlib_root {
            validate_resolved_source_root_path("stdlib root", stdlib_root)?;
            for root in &self.roots {
                if resolved_paths_overlap(root, stdlib_root) {
                    return Err(package_lockfile_error(format!(
                        "stdlib root {} overlaps resolved source root {}",
                        stdlib_root.display(),
                        root.display()
                    )));
                }
            }
        }
        validate_resolved_source_path("entry", &self.entry)?;
        if !self.roots.iter().any(|root| self.entry.starts_with(root)) {
            return Err(package_lockfile_error(format!(
                "entry {} is not under any resolved source root; resolved source roots: {}",
                self.entry.display(),
                format_resolved_roots(&self.roots)
            )));
        }
        let (_, entry_relative_path) =
            self.source_identity_root_metadata(PACKAGE_LOCKFILE_USER_LIBRARY_ID, &self.entry)?;
        source_root_relative_module_path_with_label(
            "entry source-root relative path",
            &entry_relative_path,
        )?;
        if self.compiler_version != PACKAGE_LOCKFILE_COMPILER_VERSION {
            return Err(package_lockfile_error(format!(
                "unsupported compiler version {:?}; expected {:?} for {PACKAGE_LOCKFILE_LANGUAGE_EDITION:?} lockfiles",
                self.compiler_version, PACKAGE_LOCKFILE_COMPILER_VERSION
            )));
        }
        Ok(())
    }

    fn validate_existing_package_source_state(&self) -> Result<(), CompileError> {
        for root in &self.roots {
            validate_existing_resolved_dir("source root", root)?;
        }
        if let Some(stdlib_root) = &self.stdlib_root {
            validate_existing_resolved_dir("stdlib root", stdlib_root)?;
        }
        validate_existing_resolved_file("entry", &self.entry)?;
        Ok(())
    }

    fn validate_artifacts(&self) -> Result<(), CompileError> {
        let Some(artifacts) = PackageLockfileArtifacts::from_files(self.artifacts.clone())? else {
            return Ok(());
        };
        artifacts.validate_shape()?;
        for artifact in &artifacts.files {
            if self.artifact_path_is_inside_source_roots(&artifact.path) {
                return Err(package_lockfile_error(format!(
                    "artifact file {} is inside a package source root; produced artifact identities must not point inside package or stdlib source roots",
                    artifact.path.display()
                )));
            }
            validate_existing_resolved_file("artifact file", &artifact.path)?;
            let bytes = fs::read(&artifact.path).map_err(|err| {
                package_lockfile_error(format!(
                    "read artifact file {}: {err}",
                    artifact.path.display()
                ))
            })?;
            if artifact.byte_len != bytes.len() {
                return Err(package_lockfile_error(format!(
                    "artifact byte length mismatch for {}; expected {}, found {}",
                    artifact.path.display(),
                    artifact.byte_len,
                    bytes.len()
                )));
            }
            let actual_digest = stable_content_digest(&bytes);
            if artifact.digest != actual_digest {
                return Err(package_lockfile_error(format!(
                    "artifact digest mismatch for {}; expected {}, found {}",
                    artifact.path.display(),
                    artifact.digest,
                    actual_digest
                )));
            }
        }
        Ok(())
    }

    fn validate_artifact_source_collisions(
        &self,
        inputs: &PackageLockfileInputs,
    ) -> Result<(), CompileError> {
        let Some(artifacts) = PackageLockfileArtifacts::from_files(self.artifacts.clone())? else {
            return Ok(());
        };
        let input_paths = inputs
            .files
            .iter()
            .map(|file| file.path.clone())
            .collect::<BTreeSet<_>>();
        for artifact in &artifacts.files {
            if input_paths.contains(&artifact.path) {
                return Err(package_lockfile_error(format!(
                    "artifact file {} is also a source input; produced artifact identities must not point at source files",
                    artifact.path.display()
                )));
            }
            if self.artifact_path_is_inside_source_roots(&artifact.path) {
                return Err(package_lockfile_error(format!(
                    "artifact file {} is inside a package source root; produced artifact identities must not point inside package or stdlib source roots",
                    artifact.path.display()
                )));
            }
        }
        Ok(())
    }

    fn validate_replay_integrity(&self) -> Result<(), CompileError> {
        let Some(integrity) = &self.replay_integrity else {
            return Ok(());
        };
        self.validate_persisted_input_identity_bytes(&integrity.inputs)?;
        self.validate_section_consistency(
            &integrity.inputs,
            &integrity.source_identities,
            &integrity.import_graph,
        )?;
        self.validate_import_graph_with_input_staleness(
            &integrity.import_graph,
            &integrity.inputs,
        )?;
        self.validate_entry_input_identity(&integrity.inputs)?;
        self.validate_source_identities(&integrity.source_identities)?;
        self.validate_inputs(&integrity.inputs)?;
        self.validate_artifact_source_collisions(&integrity.inputs)?;
        Ok(())
    }

    fn validate_entry_input_identity(
        &self,
        inputs: &PackageLockfileInputs,
    ) -> Result<(), CompileError> {
        inputs.validate_shape()?;
        let expected_entry = inputs
            .files
            .iter()
            .find(|file| {
                file.library_id == PACKAGE_LOCKFILE_USER_LIBRARY_ID && file.path == self.entry
            })
            .ok_or_else(|| {
                package_lockfile_error(format!(
                    "entry {} in user library {PACKAGE_LOCKFILE_USER_LIBRARY_ID} is missing from input identity; regenerate the package lockfile from the package manifest",
                    self.entry.display()
                ))
            })?;
        let bytes = fs::read(&self.entry).map_err(|err| {
            package_lockfile_error(format!("read entry input {}: {err}", self.entry.display()))
        })?;
        if expected_entry.byte_len != bytes.len() {
            return Err(package_lockfile_error(format!(
                "input byte length mismatch for {}; expected {}, found {}",
                expected_entry.path.display(),
                expected_entry.byte_len,
                bytes.len()
            )));
        }
        let actual_digest = stable_content_digest(&bytes);
        if expected_entry.digest != actual_digest {
            return Err(package_lockfile_error(format!(
                "input digest mismatch for {}; expected {}, found {}",
                expected_entry.path.display(),
                expected_entry.digest,
                actual_digest
            )));
        }
        Ok(())
    }

    fn validate_entry_replay_metadata(&self) -> Result<(), CompileError> {
        let source = fs::read_to_string(&self.entry).map_err(|err| {
            package_lockfile_error(format!(
                "read entry source replay metadata {}: {err}",
                self.entry.display()
            ))
        })?;
        let (_, entry_relative_path) =
            self.source_identity_root_metadata(PACKAGE_LOCKFILE_USER_LIBRARY_ID, &self.entry)?;
        let expected_module_path = source_root_relative_module_path(&entry_relative_path)?;
        let module_path = required_leading_module_path(
            &source,
            &self.entry,
            &entry_relative_path,
            &expected_module_path,
        )?;
        leading_import_paths_for_module(&source, &self.entry, &module_path)?;
        Ok(())
    }

    fn artifact_path_is_inside_source_roots(&self, path: &Path) -> bool {
        self.roots.iter().any(|root| path.starts_with(root))
            || self
                .stdlib_root
                .as_ref()
                .is_some_and(|root| path.starts_with(root))
    }

    fn input_identity(&self) -> Result<PackageLockfileInputs, CompileError> {
        self.validate_shape_and_existing_source_state()?;
        let path_manifest = self.load_path_manifest_without_input_validation()?;
        Self::input_identity_from_path_manifest(&path_manifest)
    }

    fn input_identity_from_path_manifest(
        path_manifest: &ExplicitSourcePackPathManifest,
    ) -> Result<PackageLockfileInputs, CompileError> {
        let mut files = Vec::with_capacity(path_manifest.files.len());
        for file in &path_manifest.files {
            let bytes = fs::read(&file.path).map_err(|err| {
                package_lockfile_error(format!("read input file {}: {err}", file.path.display()))
            })?;
            files.push(PackageLockfileInputFile {
                library_id: file.library_id,
                path: file.path.clone(),
                byte_len: bytes.len(),
                digest: stable_content_digest(&bytes),
            });
        }
        files.sort_by(compare_input_file_identity);
        let inputs = PackageLockfileInputs {
            digest_algorithm: PACKAGE_LOCKFILE_DIGEST_ALGORITHM.to_string(),
            files,
        };
        inputs.validate_shape()?;
        Ok(inputs)
    }

    fn source_identities(&self) -> Result<PackageLockfileSourceIdentities, CompileError> {
        self.validate_shape_and_existing_source_state()?;
        let path_manifest = self.load_path_manifest_without_input_validation()?;
        self.source_identities_from_path_manifest(&path_manifest)
    }

    fn source_identities_from_path_manifest(
        &self,
        path_manifest: &ExplicitSourcePackPathManifest,
    ) -> Result<PackageLockfileSourceIdentities, CompileError> {
        let mut files = Vec::with_capacity(path_manifest.files.len());
        for file in &path_manifest.files {
            let source = fs::read_to_string(&file.path).map_err(|err| {
                package_lockfile_error(format!(
                    "read source identity file {}: {err}",
                    file.path.display()
                ))
            })?;
            let (source_root_index, source_root_relative_path) =
                self.source_identity_root_metadata(file.library_id, &file.path)?;
            let expected_module_path =
                source_root_relative_module_path(&source_root_relative_path)?;
            let module_path = required_leading_module_path(
                &source,
                &file.path,
                &source_root_relative_path,
                &expected_module_path,
            )?;
            files.push(PackageLockfileSourceIdentityFile {
                library_id: file.library_id,
                path: file.path.clone(),
                source_root_index: Some(source_root_index),
                source_root_relative_path: Some(source_root_relative_path),
                module_path: Some(module_path),
            });
        }
        files.sort_by(compare_source_identity_file_identity);
        let identities = PackageLockfileSourceIdentities { files };
        identities.validate_shape()?;
        self.validate_source_identity_ownership(&identities)?;
        Ok(identities)
    }

    fn import_graph(&self) -> Result<PackageLockfileImportGraph, CompileError> {
        self.validate_shape_and_existing_source_state()?;
        let path_manifest = self.load_path_manifest_without_input_validation()?;
        self.import_graph_from_path_manifest(&path_manifest)
    }

    fn import_graph_from_path_manifest(
        &self,
        path_manifest: &ExplicitSourcePackPathManifest,
    ) -> Result<PackageLockfileImportGraph, CompileError> {
        self.validate_path_manifest_file_set(path_manifest)?;
        let search_roots = self.import_search_roots()?;
        let file_library_ids = path_manifest
            .files
            .iter()
            .map(|file| (file.path.clone(), file.library_id))
            .collect::<BTreeMap<_, _>>();
        let source_identity_module_paths = source_identity_module_paths_by_file(
            self.source_identities_from_path_manifest(path_manifest)?,
        )?;
        let mut imports = Vec::new();
        let mut seen_source_imports = BTreeSet::new();

        for file in &path_manifest.files {
            let source = fs::read_to_string(&file.path).map_err(|err| {
                package_lockfile_error(format!(
                    "read import graph source {}: {err}",
                    file.path.display()
                ))
            })?;
            let source_key = (file.library_id, file.path.clone());
            let source_module_path = source_identity_module_paths
                .get(&source_key)
                .cloned()
                .ok_or_else(|| {
                    package_lockfile_error(format!(
                        "import graph source file {} in library {} is missing from source identities",
                        file.path.display(),
                        file.library_id
                    ))
                })?;
            for import in
                leading_import_path_records_for_module(&source, &file.path, &source_module_path)?
            {
                if !seen_source_imports.insert((
                    file.library_id,
                    file.path.clone(),
                    import.path.clone(),
                )) {
                    return Err(package_lockfile_error(format!(
                        "duplicate import declaration {} in library {} {}; package lockfiles require one leading declaration per source/import path so replay metadata cannot silently deduplicate source-level import records",
                        import.path,
                        file.library_id,
                        file.path.display()
                    )));
                }
                let target = resolve_lockfile_import(
                    &import,
                    &search_roots,
                    file.library_id,
                    &file.path,
                    &source,
                )?;
                let target_library_id =
                    file_library_ids
                        .get(&target.path)
                        .copied()
                        .ok_or_else(|| {
                            package_lockfile_error(format!(
                                "import graph resolved {} from {} to {}, but the target is not in the source-pack file set",
                                import.path,
                                file.path.display(),
                                target.path.display()
                            ))
                        })?;
                let target_module_path = source_identity_module_paths
                    .get(&(target_library_id, target.path.clone()))
                    .cloned()
                    .ok_or_else(|| {
                        package_lockfile_error(format!(
                            "import graph target file {} in library {} is missing from source identities",
                            target.path.display(),
                            target_library_id
                        ))
                    })?;
                let edge = PackageLockfileImportEdge {
                    source_library_id: file.library_id,
                    source_path: file.path.clone(),
                    source_module_path: source_module_path.clone(),
                    import_path: import.path,
                    target_library_id,
                    target_path: target.path,
                    target_module_path,
                };
                imports.push(edge);
            }
        }

        let mut library_dependencies = path_manifest.library_dependencies.clone();
        library_dependencies
            .sort_by_key(|dependency| (dependency.library_id, dependency.depends_on_library_id));
        imports.sort_by(compare_import_edge_identity);

        let import_graph = PackageLockfileImportGraph {
            library_dependencies,
            imports,
        };
        import_graph.validate_shape()?;
        Ok(import_graph)
    }

    fn validate_path_manifest_file_set(
        &self,
        path_manifest: &ExplicitSourcePackPathManifest,
    ) -> Result<(), CompileError> {
        let mut seen_files = BTreeMap::new();
        for file in &path_manifest.files {
            validate_existing_resolved_source_file("source-pack file", &file.path)?;
            self.validate_file_library_ownership("source-pack file", file.library_id, &file.path)?;
            if let Some(previous_library_id) = seen_files.insert(file.path.clone(), file.library_id)
            {
                let library_context = if previous_library_id == file.library_id {
                    format!("library {}", file.library_id)
                } else {
                    format!("libraries {previous_library_id} and {}", file.library_id)
                };
                return Err(package_lockfile_error(format!(
                    "source-pack file {} is loaded more than once in package source graph ({})",
                    file.path.display(),
                    library_context
                )));
            }
        }
        Ok(())
    }

    fn import_search_roots(&self) -> Result<Vec<PackageLockfileImportSearchRoot>, CompileError> {
        let mut roots =
            Vec::with_capacity(self.roots.len() + usize::from(self.stdlib_root.is_some()));
        for root in &self.roots {
            roots.push(PackageLockfileImportSearchRoot {
                library_id: PACKAGE_LOCKFILE_USER_LIBRARY_ID,
                label: "source root",
                root: canonicalize_import_root("source root", root)?,
            });
        }
        if let Some(stdlib_root) = &self.stdlib_root {
            roots.push(PackageLockfileImportSearchRoot {
                library_id: PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID,
                label: "stdlib root",
                root: canonicalize_import_root("stdlib root", stdlib_root)?,
            });
        }
        Ok(roots)
    }

    fn validate_inputs(&self, expected: &PackageLockfileInputs) -> Result<(), CompileError> {
        expected.validate_shape()?;
        let actual = self.input_identity()?;
        if actual.digest_algorithm != expected.digest_algorithm {
            return Err(package_lockfile_error(format!(
                "input digest algorithm mismatch; expected {}, found {}",
                expected.digest_algorithm, actual.digest_algorithm
            )));
        }
        if actual.files.len() != expected.files.len() {
            return Err(package_lockfile_error(format!(
                "input file set changed; expected {} files, found {}",
                expected.files.len(),
                actual.files.len()
            )));
        }
        for (index, (expected_file, actual_file)) in
            expected.files.iter().zip(actual.files.iter()).enumerate()
        {
            if expected_file.library_id != actual_file.library_id
                || expected_file.path != actual_file.path
            {
                return Err(package_lockfile_error(format!(
                    "input file set changed at index {index}; expected library {} {}, found library {} {}",
                    expected_file.library_id,
                    expected_file.path.display(),
                    actual_file.library_id,
                    actual_file.path.display()
                )));
            }
            if expected_file.byte_len != actual_file.byte_len {
                return Err(package_lockfile_error(format!(
                    "input byte length mismatch for {}; expected {}, found {}",
                    expected_file.path.display(),
                    expected_file.byte_len,
                    actual_file.byte_len
                )));
            }
            if expected_file.digest != actual_file.digest {
                return Err(package_lockfile_error(format!(
                    "input digest mismatch for {}; expected {}, found {}",
                    expected_file.path.display(),
                    expected_file.digest,
                    actual_file.digest
                )));
            }
        }
        Ok(())
    }

    fn validate_source_identities(
        &self,
        expected: &PackageLockfileSourceIdentities,
    ) -> Result<(), CompileError> {
        expected.validate_shape()?;
        let actual = self.source_identities()?;
        if actual.files.len() != expected.files.len() {
            return Err(package_lockfile_error(format!(
                "source identity set changed; expected {} files, found {}",
                expected.files.len(),
                actual.files.len()
            )));
        }
        for (index, (expected_file, actual_file)) in
            expected.files.iter().zip(actual.files.iter()).enumerate()
        {
            if expected_file != actual_file {
                return Err(package_lockfile_error(format!(
                    "source identity changed at index {index}; expected library {} {} module {:?}, found library {} {} module {:?}",
                    expected_file.library_id,
                    expected_file.path.display(),
                    expected_file.module_path,
                    actual_file.library_id,
                    actual_file.path.display(),
                    actual_file.module_path
                )));
            }
        }
        Ok(())
    }

    fn validate_import_graph_with_input_staleness(
        &self,
        expected: &PackageLockfileImportGraph,
        inputs: &PackageLockfileInputs,
    ) -> Result<(), CompileError> {
        expected.validate_shape()?;
        self.validate_persisted_input_identity_bytes(inputs)?;
        let actual = self.import_graph()?;
        self.validate_import_graph_against_actual(expected, &actual)
    }

    fn validate_persisted_input_identity_bytes(
        &self,
        expected: &PackageLockfileInputs,
    ) -> Result<(), CompileError> {
        if let Some(input_err) = self.first_unavailable_input_identity_error(expected)? {
            return Err(input_err);
        }
        if let Some(input_err) = self.first_stale_input_identity_error(expected)? {
            return Err(input_err);
        }
        Ok(())
    }

    fn validate_import_graph_against_actual(
        &self,
        expected: &PackageLockfileImportGraph,
        actual: &PackageLockfileImportGraph,
    ) -> Result<(), CompileError> {
        validate_live_import_graph_user_root_precedence(expected, actual)?;
        if actual.library_dependencies != expected.library_dependencies {
            return Err(package_lockfile_error(format!(
                "library dependency graph changed; expected {:?}, found {:?}",
                expected.library_dependencies, actual.library_dependencies
            )));
        }
        if let Some((index, expected_import, actual_import)) =
            find_import_graph_source_move(&expected.imports, &actual.imports)
        {
            return Err(import_graph_changed_error(
                index,
                expected_import,
                actual_import,
            ));
        }
        if let Some((index, expected_import, actual_import)) =
            find_import_graph_target_change(&expected.imports, &actual.imports)
        {
            return Err(import_graph_changed_error(
                index,
                expected_import,
                actual_import,
            ));
        }
        if actual.imports.len() != expected.imports.len() {
            return Err(package_lockfile_error(format!(
                "import graph changed; expected {} imports [{}], found {} [{}]",
                expected.imports.len(),
                import_graph_edge_summary(&expected.imports),
                actual.imports.len(),
                import_graph_edge_summary(&actual.imports)
            )));
        }
        for (index, (expected_import, actual_import)) in expected
            .imports
            .iter()
            .zip(actual.imports.iter())
            .enumerate()
        {
            if expected_import != actual_import {
                return Err(import_graph_changed_error(
                    index,
                    expected_import,
                    actual_import,
                ));
            }
        }
        Ok(())
    }

    fn first_unavailable_input_identity_error(
        &self,
        expected: &PackageLockfileInputs,
    ) -> Result<Option<CompileError>, CompileError> {
        expected.validate_shape()?;
        for file in &expected.files {
            self.validate_file_library_ownership("input file", file.library_id, &file.path)?;
            validate_resolved_source_path("input file", &file.path)?;
            let metadata = match fs::metadata(&file.path) {
                Ok(metadata) => metadata,
                Err(err) => {
                    return Ok(Some(package_lockfile_error(format!(
                        "input file {} no longer matches persisted input identity: {err}",
                        file.path.display()
                    ))));
                }
            };
            if !metadata.is_file() {
                return Ok(Some(package_lockfile_error(format!(
                    "input file {} no longer matches persisted input identity: no longer resolves to a file",
                    file.path.display()
                ))));
            }
        }
        Ok(None)
    }

    fn first_stale_input_identity_error(
        &self,
        expected: &PackageLockfileInputs,
    ) -> Result<Option<CompileError>, CompileError> {
        expected.validate_shape()?;
        for file in &expected.files {
            self.validate_file_library_ownership("input file", file.library_id, &file.path)?;
            validate_resolved_source_path("input file", &file.path)?;
            let bytes = match fs::read(&file.path) {
                Ok(bytes) => bytes,
                Err(err) => {
                    return Ok(Some(package_lockfile_error(format!(
                        "input file {} no longer matches persisted input identity: {err}",
                        file.path.display()
                    ))));
                }
            };
            if file.byte_len != bytes.len() {
                return Ok(Some(package_lockfile_error(format!(
                    "input byte length mismatch for {}; expected {}, found {}",
                    file.path.display(),
                    file.byte_len,
                    bytes.len()
                ))));
            }
            let actual_digest = stable_content_digest(&bytes);
            if file.digest != actual_digest {
                return Ok(Some(package_lockfile_error(format!(
                    "input digest mismatch for {}; expected {}, found {}",
                    file.path.display(),
                    file.digest,
                    actual_digest
                ))));
            }
        }
        Ok(None)
    }

    fn validate_section_consistency(
        &self,
        inputs: &PackageLockfileInputs,
        source_identities: &PackageLockfileSourceIdentities,
        import_graph: &PackageLockfileImportGraph,
    ) -> Result<(), CompileError> {
        inputs.validate_shape()?;
        self.validate_source_identity_root_metadata(source_identities)?;
        source_identities.validate_shape()?;
        self.validate_source_identity_ownership(source_identities)?;
        import_graph.validate_shape()?;
        self.validate_input_identity_ownership(inputs)?;
        self.validate_import_graph_ownership(import_graph)?;

        let input_files = inputs
            .files
            .iter()
            .map(|file| (file.library_id, file.path.clone()))
            .collect::<BTreeSet<_>>();
        let source_identity_files = source_identities
            .files
            .iter()
            .map(|file| (file.library_id, file.path.clone()))
            .collect::<BTreeSet<_>>();
        let source_identity_module_paths =
            source_identity_module_paths_by_file(source_identities.clone())?;
        let user_source_identity_modules = source_identities
            .files
            .iter()
            .filter(|file| file.library_id == PACKAGE_LOCKFILE_USER_LIBRARY_ID)
            .filter_map(|file| {
                file.module_path
                    .as_ref()
                    .map(|module_path| (module_path.clone(), file.path.clone()))
            })
            .collect::<BTreeMap<_, _>>();
        let package_module_path = package_name_module_path(&self.package);
        let input_libraries = inputs
            .files
            .iter()
            .map(|file| file.library_id)
            .collect::<BTreeSet<_>>();
        let source_identity_libraries = source_identities
            .files
            .iter()
            .map(|file| file.library_id)
            .collect::<BTreeSet<_>>();
        let entry_key = (PACKAGE_LOCKFILE_USER_LIBRARY_ID, self.entry.clone());

        if !input_files.contains(&entry_key) {
            return Err(package_lockfile_error(format!(
                "entry {} in user library {PACKAGE_LOCKFILE_USER_LIBRARY_ID} is missing from input identity; regenerate the package lockfile from the package manifest",
                self.entry.display()
            )));
        }
        if !source_identity_files.contains(&entry_key) {
            return Err(package_lockfile_error(format!(
                "entry {} in user library {PACKAGE_LOCKFILE_USER_LIBRARY_ID} is missing from source identities; regenerate the package lockfile from the package manifest",
                self.entry.display()
            )));
        }

        for (dependency_index, dependency) in import_graph.library_dependencies.iter().enumerate() {
            if !input_libraries.contains(&dependency.library_id) {
                return Err(package_lockfile_error(format!(
                    "import graph library dependency {dependency_index} source library {} is missing from input identity",
                    dependency.library_id
                )));
            }
            if !input_libraries.contains(&dependency.depends_on_library_id) {
                return Err(package_lockfile_error(format!(
                    "import graph library dependency {dependency_index} depends-on library {} is missing from input identity",
                    dependency.depends_on_library_id
                )));
            }
            if !source_identity_libraries.contains(&dependency.library_id) {
                return Err(package_lockfile_error(format!(
                    "import graph library dependency {dependency_index} source library {} is missing from source identities",
                    dependency.library_id
                )));
            }
            if !source_identity_libraries.contains(&dependency.depends_on_library_id) {
                return Err(package_lockfile_error(format!(
                    "import graph library dependency {dependency_index} depends-on library {} is missing from source identities",
                    dependency.depends_on_library_id
                )));
            }
        }

        for (edge_index, import) in import_graph.imports.iter().enumerate() {
            if !input_files.contains(&(import.source_library_id, import.source_path.clone())) {
                return Err(package_lockfile_error(format!(
                    "import graph edge {edge_index} source file {} in library {} is missing from input identity",
                    import.source_path.display(),
                    import.source_library_id
                )));
            }
            if !input_files.contains(&(import.target_library_id, import.target_path.clone())) {
                return Err(package_lockfile_error(format!(
                    "import graph edge {edge_index} target file {} in library {} is missing from input identity",
                    import.target_path.display(),
                    import.target_library_id
                )));
            }
            if !source_identity_files
                .contains(&(import.source_library_id, import.source_path.clone()))
            {
                return Err(package_lockfile_error(format!(
                    "import graph edge {edge_index} source file {} in library {} is missing from source identities",
                    import.source_path.display(),
                    import.source_library_id
                )));
            }
            if !source_identity_files
                .contains(&(import.target_library_id, import.target_path.clone()))
            {
                return Err(package_lockfile_error(format!(
                    "import graph edge {edge_index} target file {} in library {} is missing from source identities",
                    import.target_path.display(),
                    import.target_library_id
                )));
            }
            validate_import_graph_module_endpoint(
                edge_index,
                "source",
                import.source_library_id,
                &import.source_path,
                &import.source_module_path,
                source_identity_module_paths
                    .get(&(import.source_library_id, import.source_path.clone()))
                    .expect("source identity existence checked above"),
                package_module_path.as_deref(),
                &self.package,
            )?;
            validate_import_graph_module_endpoint(
                edge_index,
                "target",
                import.target_library_id,
                &import.target_path,
                &import.target_module_path,
                source_identity_module_paths
                    .get(&(import.target_library_id, import.target_path.clone()))
                    .expect("target identity existence checked above"),
                package_module_path.as_deref(),
                &self.package,
            )?;
            validate_import_graph_user_root_precedence(
                edge_index,
                import,
                &user_source_identity_modules,
            )?;
        }

        for file in &source_identities.files {
            if !input_files.contains(&(file.library_id, file.path.clone())) {
                return Err(package_lockfile_error(format!(
                    "source identity file {} in library {} is missing from input identity",
                    file.path.display(),
                    file.library_id
                )));
            }
        }
        for file in &inputs.files {
            if !source_identity_files.contains(&(file.library_id, file.path.clone())) {
                return Err(package_lockfile_error(format!(
                    "input file {} in library {} is missing from source identities",
                    file.path.display(),
                    file.library_id
                )));
            }
        }
        let reachable_files = import_graph_reachable_files_from_entry(&entry_key, import_graph);
        for file in &inputs.files {
            let file_key = (file.library_id, file.path.clone());
            if !reachable_files.contains(&file_key) {
                return Err(package_lockfile_error(format!(
                    "input file {} in library {} is not reachable from the package entry through persisted import graph edges",
                    file.path.display(),
                    file.library_id
                )));
            }
        }

        Ok(())
    }

    fn validate_input_identity_ownership(
        &self,
        inputs: &PackageLockfileInputs,
    ) -> Result<(), CompileError> {
        for file in &inputs.files {
            self.validate_file_library_ownership("input file", file.library_id, &file.path)?;
        }
        Ok(())
    }

    fn validate_source_identity_ownership(
        &self,
        source_identities: &PackageLockfileSourceIdentities,
    ) -> Result<(), CompileError> {
        for file in &source_identities.files {
            let expected_relative_path = self.validate_source_identity_root_metadata_file(file)?;
            let expected_module_path = source_root_relative_module_path(&expected_relative_path)?;
            match &file.module_path {
                Some(module_path) if module_path == &expected_module_path => {}
                Some(module_path) => {
                    if package_name_module_path(&self.package)
                        .as_deref()
                        .is_some_and(|package_module_path| package_module_path == module_path)
                    {
                        return Err(package_lockfile_error(format!(
                            "source identity file {} declares module {:?} matching package metadata {:?}, but resolved source-root relative path {} maps to {:?}; package names are control-plane identity and must not replace GPU module declarations",
                            file.path.display(),
                            module_path,
                            self.package,
                            expected_relative_path.display(),
                            expected_module_path
                        )));
                    }
                    return Err(package_lockfile_error(format!(
                        "source identity file {} declares module {:?}, but resolved source-root relative path {} maps to {:?}",
                        file.path.display(),
                        module_path,
                        expected_relative_path.display(),
                        expected_module_path
                    )));
                }
                None => {
                    return Err(package_lockfile_error(format!(
                        "source identity file {} is missing module path metadata; resolved source-root relative path {} maps to {:?}; package lockfiles require leading module declarations",
                        file.path.display(),
                        expected_relative_path.display(),
                        expected_module_path
                    )));
                }
            }
        }
        Ok(())
    }

    fn validate_source_identity_root_metadata(
        &self,
        source_identities: &PackageLockfileSourceIdentities,
    ) -> Result<(), CompileError> {
        for file in &source_identities.files {
            self.validate_source_identity_root_metadata_file(file)?;
        }
        Ok(())
    }

    fn validate_source_identity_root_metadata_file(
        &self,
        file: &PackageLockfileSourceIdentityFile,
    ) -> Result<PathBuf, CompileError> {
        validate_resolved_source_path("source identity file", &file.path)?;
        self.validate_file_library_ownership("source identity file", file.library_id, &file.path)?;
        let (expected_root_index, expected_relative_path) =
            self.source_identity_root_metadata(file.library_id, &file.path)?;
        match file.source_root_index {
            Some(actual_root_index) if actual_root_index == expected_root_index => {}
            Some(actual_root_index) => {
                return Err(package_lockfile_error(format!(
                    "source identity file {} in library {} has source-root index {}; expected {}",
                    file.path.display(),
                    file.library_id,
                    actual_root_index,
                    expected_root_index
                )));
            }
            None => {
                return Err(package_lockfile_error(format!(
                    "source identity file {} in library {} is missing source-root index metadata",
                    file.path.display(),
                    file.library_id
                )));
            }
        }
        match &file.source_root_relative_path {
            Some(actual_relative_path) if actual_relative_path == &expected_relative_path => {}
            Some(actual_relative_path) => {
                return Err(package_lockfile_error(format!(
                    "source identity file {} in library {} has source-root relative path {}; expected {}",
                    file.path.display(),
                    file.library_id,
                    actual_relative_path.display(),
                    expected_relative_path.display()
                )));
            }
            None => {
                return Err(package_lockfile_error(format!(
                    "source identity file {} in library {} is missing source-root relative path metadata",
                    file.path.display(),
                    file.library_id
                )));
            }
        }
        Ok(expected_relative_path)
    }

    fn source_identity_root_metadata(
        &self,
        library_id: u32,
        path: &Path,
    ) -> Result<(usize, PathBuf), CompileError> {
        let (root_index, root) = match library_id {
            PACKAGE_LOCKFILE_USER_LIBRARY_ID => self
                .roots
                .iter()
                .enumerate()
                .find(|(_, root)| path.starts_with(root))
                .ok_or_else(|| {
                    package_lockfile_error(format!(
                        "source identity file {} in user library {PACKAGE_LOCKFILE_USER_LIBRARY_ID} is not under any resolved source root; resolved source roots: {}",
                        path.display(),
                        format_resolved_roots(&self.roots)
                    ))
                })?,
            PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID => {
                let Some(stdlib_root) = &self.stdlib_root else {
                    return Err(package_lockfile_error(format!(
                        "source identity file {} uses stdlib library {PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID}, but the lockfile has no stdlib root",
                        path.display()
                    )));
                };
                if !path.starts_with(stdlib_root) {
                    return Err(package_lockfile_error(format!(
                        "source identity file {} in stdlib library {PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID} is not under resolved stdlib root {}",
                        path.display(),
                        stdlib_root.display()
                    )));
                }
                (0, stdlib_root)
            }
            other => {
                return Err(package_lockfile_error(format!(
                    "source identity file {} uses unsupported library {other}; expected user library {PACKAGE_LOCKFILE_USER_LIBRARY_ID} or stdlib library {PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID}",
                    path.display()
                )));
            }
        };
        let relative_path = path.strip_prefix(root).map_err(|_| {
            package_lockfile_error(format!(
                "source identity file {} is not relative to source root {}",
                path.display(),
                root.display()
            ))
        })?;
        validate_source_root_relative_path("source identity relative path", relative_path)?;
        Ok((root_index, relative_path.to_path_buf()))
    }

    fn validate_import_graph_ownership(
        &self,
        import_graph: &PackageLockfileImportGraph,
    ) -> Result<(), CompileError> {
        for (edge_index, import) in import_graph.imports.iter().enumerate() {
            self.validate_file_library_ownership(
                &format!("import graph edge {edge_index} source file"),
                import.source_library_id,
                &import.source_path,
            )?;
            self.validate_file_library_ownership(
                &format!("import graph edge {edge_index} target file"),
                import.target_library_id,
                &import.target_path,
            )?;
            self.validate_import_graph_endpoint_path_identity(
                edge_index,
                "source",
                import.source_library_id,
                &import.source_path,
                &import.source_module_path,
            )?;
            self.validate_import_graph_endpoint_path_identity(
                edge_index,
                "target",
                import.target_library_id,
                &import.target_path,
                &import.target_module_path,
            )?;
        }
        Ok(())
    }

    fn validate_import_graph_endpoint_path_identity(
        &self,
        edge_index: usize,
        endpoint: &str,
        library_id: u32,
        path: &Path,
        edge_module_path: &str,
    ) -> Result<(), CompileError> {
        let (_, relative_path) = self.source_identity_root_metadata(library_id, path)?;
        let expected_module_path = source_root_relative_module_path(&relative_path)?;
        if edge_module_path == expected_module_path {
            return Ok(());
        }
        if package_name_module_path(&self.package)
            .as_deref()
            .is_some_and(|package_module_path| package_module_path == edge_module_path)
        {
            return Err(package_lockfile_error(format!(
                "import graph edge {edge_index} {endpoint} module path {:?} matches package metadata {:?}, but source identity module from resolved source-root relative path {} maps to {:?}; package names are control-plane identity and must not replace GPU module declarations",
                edge_module_path,
                self.package,
                relative_path.display(),
                expected_module_path
            )));
        }
        Err(package_lockfile_error(format!(
            "import graph edge {edge_index} {endpoint} module path {:?} does not match source identity module from resolved source-root relative path {} mapping {:?}",
            edge_module_path,
            relative_path.display(),
            expected_module_path
        )))
    }

    fn validate_file_library_ownership(
        &self,
        label: &str,
        library_id: u32,
        path: &Path,
    ) -> Result<(), CompileError> {
        match library_id {
            PACKAGE_LOCKFILE_USER_LIBRARY_ID => {
                if self.roots.iter().any(|root| path.starts_with(root)) {
                    Ok(())
                } else {
                    Err(package_lockfile_error(format!(
                        "{label} {} in user library {PACKAGE_LOCKFILE_USER_LIBRARY_ID} is not under any resolved source root; resolved source roots: {}",
                        path.display(),
                        format_resolved_roots(&self.roots)
                    )))
                }
            }
            PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID => {
                let Some(stdlib_root) = &self.stdlib_root else {
                    return Err(package_lockfile_error(format!(
                        "{label} {} uses stdlib library {PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID}, but the lockfile has no stdlib root",
                        path.display()
                    )));
                };
                if path.starts_with(stdlib_root) {
                    Ok(())
                } else {
                    Err(package_lockfile_error(format!(
                        "{label} {} in stdlib library {PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID} is not under resolved stdlib root {}",
                        path.display(),
                        stdlib_root.display()
                    )))
                }
            }
            other => Err(package_lockfile_error(format!(
                "{label} {} uses unsupported library {other}; expected user library {PACKAGE_LOCKFILE_USER_LIBRARY_ID} or stdlib library {PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID}",
                path.display()
            ))),
        }
    }

    pub fn to_entry_source_roots(&self) -> EntrySourceRoots {
        EntrySourceRoots {
            stdlib_root: self.stdlib_root.clone(),
            user_roots: self.roots.clone(),
        }
    }

    pub fn load_source_pack(&self) -> Result<ExplicitSourcePack, CompileError> {
        self.validate_shape_and_existing_source_state()?;
        self.validate_replay_integrity()?;
        self.validate_entry_replay_metadata()?;
        self.validate_artifacts()?;
        self.validate_live_import_graph()?;
        load_entry_with_source_roots(&self.entry, &self.to_entry_source_roots())
    }

    pub fn load_path_manifest(&self) -> Result<ExplicitSourcePackPathManifest, CompileError> {
        self.validate_shape_and_existing_source_state()?;
        self.validate_replay_integrity()?;
        self.validate_entry_replay_metadata()?;
        self.validate_artifacts()?;
        let path_manifest = self.load_path_manifest_without_input_validation()?;
        self.import_graph_from_path_manifest(&path_manifest)?;
        Ok(path_manifest)
    }

    fn load_path_manifest_without_input_validation(
        &self,
    ) -> Result<ExplicitSourcePackPathManifest, CompileError> {
        load_entry_path_manifest_with_source_roots(&self.entry, &self.to_entry_source_roots())
            .map_err(add_package_replay_diagnostic_context)
    }

    fn validate_live_import_graph(&self) -> Result<(), CompileError> {
        let path_manifest = self.load_path_manifest_without_input_validation()?;
        self.import_graph_from_path_manifest(&path_manifest)?;
        Ok(())
    }
}

fn validate_import_graph_user_root_precedence(
    edge_index: usize,
    import: &PackageLockfileImportEdge,
    user_source_identity_modules: &BTreeMap<String, PathBuf>,
) -> Result<(), CompileError> {
    if import.source_library_id != PACKAGE_LOCKFILE_USER_LIBRARY_ID
        || import.target_library_id != PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID
    {
        return Ok(());
    }
    let Some(user_path) = user_source_identity_modules.get(&import.target_module_path) else {
        return Ok(());
    };
    Err(package_lockfile_error(format!(
        "import graph edge {edge_index} from user source {} targets stdlib module {} at {}, but user source identity {} declares the same module; package/user roots take precedence over stdlib fallback so persisted library metadata must not choose semantic module identity",
        import.source_path.display(),
        import.target_module_path,
        import.target_path.display(),
        user_path.display()
    )))
}

fn validate_live_import_graph_user_root_precedence(
    expected: &PackageLockfileImportGraph,
    actual: &PackageLockfileImportGraph,
) -> Result<(), CompileError> {
    for expected_import in &expected.imports {
        if expected_import.source_library_id != PACKAGE_LOCKFILE_USER_LIBRARY_ID
            || expected_import.target_library_id != PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID
        {
            continue;
        }
        let Some(actual_import) = actual.imports.iter().find(|actual_import| {
            actual_import.source_library_id == expected_import.source_library_id
                && actual_import.source_path == expected_import.source_path
                && actual_import.import_path == expected_import.import_path
                && actual_import.target_library_id == PACKAGE_LOCKFILE_USER_LIBRARY_ID
        }) else {
            continue;
        };
        return Err(package_lockfile_error(format!(
            "import graph changed for user source {} import {}; persisted replay targets stdlib module {} at {}, but live source-root replay resolves package/user module at {}; package/user roots take precedence over stdlib fallback so stale lockfile metadata must not choose semantic module identity",
            expected_import.source_path.display(),
            expected_import.import_path,
            expected_import.target_module_path,
            expected_import.target_path.display(),
            actual_import.target_path.display()
        )));
    }
    Ok(())
}

fn add_package_replay_diagnostic_context(err: CompileError) -> CompileError {
    match err {
        CompileError::Diagnostic(diagnostic) if diagnostic.code == "LNC0001" => {
            CompileError::Diagnostic(diagnostic.with_note(
                "package names and lockfile roots are control-plane metadata; provide a source-root .lani file whose leading module declaration matches the import path",
            ))
        }
        other => other,
    }
}

fn find_import_graph_source_move<'a>(
    expected_imports: &'a [PackageLockfileImportEdge],
    actual_imports: &'a [PackageLockfileImportEdge],
) -> Option<(
    usize,
    &'a PackageLockfileImportEdge,
    &'a PackageLockfileImportEdge,
)> {
    let actual_edges = import_graph_full_edge_keys(actual_imports);
    let actual_by_import_target = actual_imports
        .iter()
        .map(|actual| (import_graph_import_target_key(actual), actual))
        .collect::<BTreeMap<_, _>>();
    for (index, expected) in expected_imports.iter().enumerate() {
        if actual_edges.contains(&import_graph_full_edge_key(expected)) {
            continue;
        }
        let key = import_graph_import_target_key(expected);
        if let Some(actual) = actual_by_import_target.get(&key).copied()
            && import_graph_edge_source_changed(expected, actual)
        {
            return Some((index, expected, actual));
        }
    }
    None
}

fn find_import_graph_target_change<'a>(
    expected_imports: &'a [PackageLockfileImportEdge],
    actual_imports: &'a [PackageLockfileImportEdge],
) -> Option<(
    usize,
    &'a PackageLockfileImportEdge,
    &'a PackageLockfileImportEdge,
)> {
    let actual_edges = import_graph_full_edge_keys(actual_imports);
    let actual_by_source_import = actual_imports
        .iter()
        .map(|actual| (import_graph_source_import_key(actual), actual))
        .collect::<BTreeMap<_, _>>();
    for (index, expected) in expected_imports.iter().enumerate() {
        if actual_edges.contains(&import_graph_full_edge_key(expected)) {
            continue;
        }
        let key = import_graph_source_import_key(expected);
        if let Some(actual) = actual_by_source_import.get(&key).copied()
            && import_graph_edge_target_changed(expected, actual)
        {
            return Some((index, expected, actual));
        }
    }
    None
}

type ImportGraphFullEdgeKey = (u32, PathBuf, String, String, u32, PathBuf, String);
type ImportGraphImportTargetKey = (String, u32, PathBuf, String);
type ImportGraphSourceImportKey = (u32, PathBuf, String, String);

fn import_graph_full_edge_keys(
    imports: &[PackageLockfileImportEdge],
) -> BTreeSet<ImportGraphFullEdgeKey> {
    imports.iter().map(import_graph_full_edge_key).collect()
}

fn import_graph_full_edge_key(import: &PackageLockfileImportEdge) -> ImportGraphFullEdgeKey {
    (
        import.source_library_id,
        import.source_path.clone(),
        import.source_module_path.clone(),
        import.import_path.clone(),
        import.target_library_id,
        import.target_path.clone(),
        import.target_module_path.clone(),
    )
}

fn import_graph_import_target_key(
    import: &PackageLockfileImportEdge,
) -> ImportGraphImportTargetKey {
    (
        import.import_path.clone(),
        import.target_library_id,
        import.target_path.clone(),
        import.target_module_path.clone(),
    )
}

fn import_graph_source_import_key(
    import: &PackageLockfileImportEdge,
) -> ImportGraphSourceImportKey {
    (
        import.source_library_id,
        import.source_path.clone(),
        import.source_module_path.clone(),
        import.import_path.clone(),
    )
}

fn import_graph_edge_source_changed(
    expected: &PackageLockfileImportEdge,
    actual: &PackageLockfileImportEdge,
) -> bool {
    expected.source_library_id != actual.source_library_id
        || expected.source_path != actual.source_path
        || expected.source_module_path != actual.source_module_path
}

fn import_graph_edge_target_changed(
    expected: &PackageLockfileImportEdge,
    actual: &PackageLockfileImportEdge,
) -> bool {
    expected.target_library_id != actual.target_library_id
        || expected.target_path != actual.target_path
        || expected.target_module_path != actual.target_module_path
}

fn import_graph_changed_error(
    edge_index: usize,
    expected: &PackageLockfileImportEdge,
    actual: &PackageLockfileImportEdge,
) -> CompileError {
    let reason = if expected.source_library_id == actual.source_library_id
        && expected.source_path == actual.source_path
        && expected.import_path != actual.import_path
    {
        format!(
            "source import path changed from {} to {}",
            expected.import_path, actual.import_path
        )
    } else if expected.source_library_id == actual.source_library_id
        && expected.source_path == actual.source_path
        && expected.import_path == actual.import_path
        && (expected.target_library_id != actual.target_library_id
            || expected.target_path != actual.target_path
            || expected.target_module_path != actual.target_module_path)
    {
        format!(
            "target changed for import {} from library {} {} module {} to library {} {} module {}",
            expected.import_path,
            expected.target_library_id,
            expected.target_path.display(),
            expected.target_module_path,
            actual.target_library_id,
            actual.target_path.display(),
            actual.target_module_path
        )
    } else if expected.import_path == actual.import_path
        && expected.target_library_id == actual.target_library_id
        && expected.target_path == actual.target_path
        && expected.target_module_path == actual.target_module_path
        && (expected.source_library_id != actual.source_library_id
            || expected.source_path != actual.source_path
            || expected.source_module_path != actual.source_module_path)
    {
        format!(
            "source changed for import {} from library {} {} module {} to library {} {} module {}",
            expected.import_path,
            expected.source_library_id,
            expected.source_path.display(),
            expected.source_module_path,
            actual.source_library_id,
            actual.source_path.display(),
            actual.source_module_path
        )
    } else {
        "source or target edge identity changed".to_string()
    };
    package_lockfile_error(format!(
        "import graph changed at edge {edge_index}: {reason}; persisted edge was import {} from library {} {} module {} to library {} {} module {}, live source-root replay found import {} from library {} {} module {} to library {} {} module {}; regenerate the package lockfile from the package manifest",
        expected.import_path,
        expected.source_library_id,
        expected.source_path.display(),
        expected.source_module_path,
        expected.target_library_id,
        expected.target_path.display(),
        expected.target_module_path,
        actual.import_path,
        actual.source_library_id,
        actual.source_path.display(),
        actual.source_module_path,
        actual.target_library_id,
        actual.target_path.display(),
        actual.target_module_path
    ))
}

impl PackageLockfileInputs {
    fn validate_shape(&self) -> Result<(), CompileError> {
        if self.digest_algorithm != PACKAGE_LOCKFILE_DIGEST_ALGORITHM {
            return Err(package_lockfile_error(format!(
                "unsupported input digest algorithm {:?}; expected {PACKAGE_LOCKFILE_DIGEST_ALGORITHM:?}",
                self.digest_algorithm
            )));
        }
        if self.files.is_empty() {
            return Err(package_lockfile_error(
                "input identity must declare at least one source file",
            ));
        }
        let mut seen = BTreeSet::new();
        let mut previous_file: Option<&PackageLockfileInputFile> = None;
        for file in &self.files {
            validate_lockfile_replay_library_id("input identity file", file.library_id)?;
            validate_resolved_source_path("input file", &file.path)?;
            if let Some(previous_file) = previous_file {
                if compare_input_file_identity(previous_file, file).is_gt() {
                    return Err(package_lockfile_error(format!(
                        "input identity files must be sorted by library id and canonical path; library {} {} appears after library {} {}; regenerate the package lockfile from the package manifest",
                        file.library_id,
                        file.path.display(),
                        previous_file.library_id,
                        previous_file.path.display()
                    )));
                }
            }
            previous_file = Some(file);
            if file.byte_len == 0 {
                return Err(package_lockfile_error(format!(
                    "input file {} byte length must be greater than zero; package source inputs require leading module metadata",
                    file.path.display()
                )));
            }
            if file.digest.trim().is_empty() {
                return Err(package_lockfile_error(format!(
                    "input file {} digest must not be empty",
                    file.path.display()
                )));
            }
            if !valid_stable_content_digest(&file.digest) {
                return Err(package_lockfile_error(format!(
                    "input file {} has invalid digest {:?}",
                    file.path.display(),
                    file.digest
                )));
            }
            if !seen.insert((file.library_id, file.path.clone())) {
                return Err(package_lockfile_error(format!(
                    "duplicate input file for library {} {}",
                    file.library_id,
                    file.path.display()
                )));
            }
        }
        Ok(())
    }
}

impl PackageLockfileSourceIdentities {
    fn validate_shape(&self) -> Result<(), CompileError> {
        if self.files.is_empty() {
            return Err(package_lockfile_error(
                "source identities must declare at least one source file",
            ));
        }
        let mut seen = BTreeSet::new();
        let mut seen_modules = BTreeMap::new();
        let mut previous_file: Option<&PackageLockfileSourceIdentityFile> = None;
        for file in &self.files {
            validate_lockfile_replay_library_id("source identity file", file.library_id)?;
            validate_resolved_source_path("source identity file", &file.path)?;
            if let Some(previous_file) = previous_file {
                if compare_source_identity_file_identity(previous_file, file).is_gt() {
                    return Err(package_lockfile_error(format!(
                        "source identity files must be sorted by library id and canonical path; library {} {} appears after library {} {}; regenerate the package lockfile from the package manifest",
                        file.library_id,
                        file.path.display(),
                        previous_file.library_id,
                        previous_file.path.display()
                    )));
                }
            }
            previous_file = Some(file);
            if !seen.insert((file.library_id, file.path.clone())) {
                return Err(package_lockfile_error(format!(
                    "duplicate source identity file for library {} {}",
                    file.library_id,
                    file.path.display()
                )));
            }
            if file.source_root_index.is_none() {
                return Err(package_lockfile_error(format!(
                    "source identity file {} in library {} is missing source-root index metadata",
                    file.path.display(),
                    file.library_id
                )));
            }
            if let Some(relative_path) = &file.source_root_relative_path {
                validate_source_root_relative_path("source identity relative path", relative_path)?;
            } else {
                return Err(package_lockfile_error(format!(
                    "source identity file {} in library {} is missing source-root relative path metadata",
                    file.path.display(),
                    file.library_id
                )));
            }
            if let Some(module_path) = &file.module_path {
                if !valid_module_path(module_path) {
                    return Err(package_lockfile_error(format!(
                        "source identity file {} has invalid module path {:?}",
                        file.path.display(),
                        module_path
                    )));
                }
                let module_identity = (file.library_id, module_path.clone());
                if let Some(previous_path) = seen_modules.insert(module_identity, file.path.clone())
                {
                    return Err(package_lockfile_error(format!(
                        "duplicate source identity module {:?} in library {} for {} and {}; package lockfiles require one source file per module identity",
                        module_path,
                        file.library_id,
                        previous_path.display(),
                        file.path.display()
                    )));
                }
            } else {
                return Err(package_lockfile_error(format!(
                    "source identity file {} in library {} is missing module path metadata",
                    file.path.display(),
                    file.library_id
                )));
            }
        }
        Ok(())
    }
}

impl PackageLockfileDocument {
    fn from_lockfile(
        lockfile: &PackageLockfile,
        inputs: Option<PackageLockfileInputs>,
        source_identities: Option<PackageLockfileSourceIdentities>,
        import_graph: Option<PackageLockfileImportGraph>,
        artifacts: Option<PackageLockfileArtifacts>,
    ) -> Self {
        Self {
            version: lockfile.version,
            package: lockfile.package.clone(),
            language_edition: lockfile.language_edition.clone(),
            compiler_version: lockfile.compiler_version.clone(),
            roots: lockfile.roots.clone(),
            stdlib_root: lockfile.stdlib_root.clone(),
            entry: lockfile.entry.clone(),
            inputs,
            source_identities,
            import_graph,
            artifacts,
        }
    }

    fn to_lockfile(&self) -> PackageLockfile {
        PackageLockfile {
            version: self.version,
            package: self.package.clone(),
            language_edition: self.language_edition.clone(),
            compiler_version: self.compiler_version.clone(),
            roots: self.roots.clone(),
            stdlib_root: self.stdlib_root.clone(),
            entry: self.entry.clone(),
            artifacts: self
                .artifacts
                .as_ref()
                .map(|artifacts| artifacts.files.clone())
                .unwrap_or_default(),
            replay_integrity: None,
        }
    }

    fn to_validated_lockfile(&self) -> Result<PackageLockfile, CompileError> {
        let mut lockfile = self.to_lockfile();
        lockfile.validate_shape()?;
        let import_graph = self.import_graph.as_ref().ok_or_else(|| {
            package_lockfile_error(
                "missing import graph; regenerate the package lockfile from the package manifest",
            )
        })?;
        let inputs = self.inputs.as_ref().ok_or_else(|| {
            package_lockfile_error(
                "missing input identity; regenerate the package lockfile from the package manifest",
            )
        })?;
        let source_identities = self.source_identities.as_ref().ok_or_else(|| {
            package_lockfile_error(
                "missing source identities; regenerate the package lockfile from the package manifest",
            )
        })?;
        inputs.validate_shape()?;
        source_identities.validate_shape()?;
        import_graph.validate_shape()?;
        lockfile.validate_existing_package_source_state()?;
        lockfile.validate_persisted_input_identity_bytes(inputs)?;
        lockfile.validate_section_consistency(inputs, source_identities, import_graph)?;
        if let Some(artifacts) = &self.artifacts {
            artifacts.validate_shape()?;
        }
        lockfile.validate_import_graph_with_input_staleness(import_graph, inputs)?;
        lockfile.validate_entry_input_identity(inputs)?;
        lockfile.validate_entry_replay_metadata()?;
        lockfile.validate_source_identities(source_identities)?;
        lockfile.validate_inputs(inputs)?;
        lockfile.validate_artifact_source_collisions(inputs)?;
        lockfile.validate_artifacts()?;
        lockfile.replay_integrity = Some(PackageLockfileReplayIntegrity {
            inputs: inputs.clone(),
            source_identities: source_identities.clone(),
            import_graph: import_graph.clone(),
        });
        Ok(lockfile)
    }
}

fn compare_input_file_identity(
    left: &PackageLockfileInputFile,
    right: &PackageLockfileInputFile,
) -> std::cmp::Ordering {
    left.library_id
        .cmp(&right.library_id)
        .then_with(|| left.path.cmp(&right.path))
}

fn compare_source_identity_file_identity(
    left: &PackageLockfileSourceIdentityFile,
    right: &PackageLockfileSourceIdentityFile,
) -> std::cmp::Ordering {
    left.library_id
        .cmp(&right.library_id)
        .then_with(|| left.path.cmp(&right.path))
}

fn source_identity_module_paths_by_file(
    source_identities: PackageLockfileSourceIdentities,
) -> Result<BTreeMap<(u32, PathBuf), String>, CompileError> {
    source_identities
        .files
        .into_iter()
        .map(|file| {
            let module_path = file.module_path.ok_or_else(|| {
                package_lockfile_error(format!(
                    "source identity file {} in library {} is missing module path metadata",
                    file.path.display(),
                    file.library_id
                ))
            })?;
            Ok(((file.library_id, file.path), module_path))
        })
        .collect()
}

fn source_root_relative_module_path(relative_path: &Path) -> Result<String, CompileError> {
    source_root_relative_module_path_with_label("source identity relative path", relative_path)
}

fn source_root_relative_module_path_with_label(
    label: &str,
    relative_path: &Path,
) -> Result<String, CompileError> {
    package_source_root_relative_module_path_with_label(label, relative_path)
        .map_err(package_lockfile_error)
}

fn stable_content_digest(bytes: &[u8]) -> String {
    let mut hash = 0xcbf2_9ce4_8422_2325u64;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    let mut digest = String::with_capacity("fnv1a64:".len() + 16);
    digest.push_str("fnv1a64:");
    write!(&mut digest, "{hash:016x}").expect("writing to a string cannot fail");
    digest
}

fn valid_stable_content_digest(digest: &str) -> bool {
    let Some(hex) = digest.strip_prefix("fnv1a64:") else {
        return false;
    };
    hex.len() == 16
        && hex
            .bytes()
            .all(|byte| byte.is_ascii_digit() || matches!(byte, b'a'..=b'f'))
}

fn validate_lockfile_replay_library_id(label: &str, library_id: u32) -> Result<(), CompileError> {
    match library_id {
        PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID | PACKAGE_LOCKFILE_USER_LIBRARY_ID => Ok(()),
        other => Err(package_lockfile_error(format!(
            "{label} library {other} is unsupported; package lockfile replay metadata currently supports stdlib library {PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID} and package/user library {PACKAGE_LOCKFILE_USER_LIBRARY_ID}"
        ))),
    }
}

fn validate_resolved_path(label: &str, path: &Path) -> Result<(), CompileError> {
    if path.as_os_str().is_empty() {
        return Err(package_lockfile_error(format!("{label} must not be empty")));
    }
    if !path.is_absolute() {
        return Err(package_lockfile_error(format!(
            "{label} {} must be an absolute resolved path",
            path.display()
        )));
    }
    validate_normalized_resolved_path(label, path)?;
    validate_canonical_resolved_path_if_present(label, path)?;
    Ok(())
}

fn validate_resolved_source_root_path(label: &str, path: &Path) -> Result<(), CompileError> {
    validate_resolved_path(label, path)?;
    if path.parent().is_none() {
        return Err(package_lockfile_error(format!(
            "{label} {} must not be the filesystem root; package lockfiles require a package-owned source directory so imports cannot resolve arbitrary absolute paths",
            path.display()
        )));
    }
    Ok(())
}

fn validate_normalized_resolved_path(label: &str, path: &Path) -> Result<(), CompileError> {
    let has_non_normal_component = path.components().any(|component| {
        matches!(
            component,
            std::path::Component::CurDir | std::path::Component::ParentDir
        )
    }) || path
        .to_string_lossy()
        .split(['/', '\\'])
        .any(|component| component == "." || component == "..");
    if has_non_normal_component {
        return Err(package_lockfile_error(format!(
            "{label} {} is not a canonical resolved path; remove current-directory and parent-directory components before writing package lockfile metadata",
            path.display()
        )));
    }
    Ok(())
}

fn validate_resolved_source_path(label: &str, path: &Path) -> Result<(), CompileError> {
    validate_resolved_path(label, path)?;
    validate_lockfile_source_path(label, path)
}

fn validate_existing_resolved_source_file(label: &str, path: &Path) -> Result<(), CompileError> {
    validate_existing_resolved_file(label, path)?;
    validate_lockfile_source_path(label, path)
}

fn validate_lockfile_source_path(label: &str, path: &Path) -> Result<(), CompileError> {
    if is_lani_source_path(path) {
        return Ok(());
    }
    Err(package_lockfile_error(format!(
        "{label} {} must use the .lani source file extension",
        path.display()
    )))
}

fn validate_source_root_relative_path(label: &str, path: &Path) -> Result<(), CompileError> {
    if path.as_os_str().is_empty() {
        return Err(package_lockfile_error(format!("{label} must not be empty")));
    }
    if path.is_absolute() {
        return Err(package_lockfile_error(format!(
            "{label} {} must be relative to its resolved source root",
            path.display()
        )));
    }
    let raw_path = path.to_string_lossy();
    if raw_path.contains('\\') {
        return Err(package_lockfile_error(format!(
            "{label} {} must use '/' separators; package lockfiles do not accept backslash path separators in source-root relative metadata",
            path.display()
        )));
    }
    let has_unnormalized_component = raw_path
        .split(['/', '\\'])
        .any(|component| component.is_empty() || component == "." || component == "..");
    if path.components().any(|component| {
        matches!(
            component,
            std::path::Component::Prefix(_)
                | std::path::Component::RootDir
                | std::path::Component::CurDir
                | std::path::Component::ParentDir
        )
    }) || has_unnormalized_component
    {
        return Err(package_lockfile_error(format!(
            "{label} {} must be a normalized source-root relative path",
            path.display()
        )));
    }
    Ok(())
}

fn validate_existing_resolved_dir(label: &str, path: &Path) -> Result<(), CompileError> {
    let metadata = fs::metadata(path).map_err(|err| {
        package_lockfile_error(format!(
            "{label} {} no longer resolves to a directory: {err}",
            path.display()
        ))
    })?;
    if !metadata.is_dir() {
        return Err(package_lockfile_error(format!(
            "{label} {} no longer resolves to a directory",
            path.display()
        )));
    }
    validate_canonical_resolved_path(label, path)?;
    Ok(())
}

fn validate_existing_resolved_file(label: &str, path: &Path) -> Result<(), CompileError> {
    let metadata = fs::metadata(path).map_err(|err| {
        package_lockfile_error(format!(
            "{label} {} no longer resolves to a file: {err}",
            path.display()
        ))
    })?;
    if !metadata.is_file() {
        return Err(package_lockfile_error(format!(
            "{label} {} no longer resolves to a file",
            path.display()
        )));
    }
    validate_canonical_resolved_path(label, path)?;
    Ok(())
}

fn validate_canonical_resolved_path(label: &str, path: &Path) -> Result<(), CompileError> {
    let canonical = fs::canonicalize(path).map_err(|err| {
        package_lockfile_error(format!(
            "canonicalize resolved {label} {}: {err}",
            path.display()
        ))
    })?;
    if canonical != path {
        return Err(package_lockfile_error(format!(
            "{label} {} is not a canonical resolved path; expected {}",
            path.display(),
            canonical.display()
        )));
    }
    Ok(())
}

fn validate_canonical_resolved_path_if_present(
    label: &str,
    path: &Path,
) -> Result<(), CompileError> {
    let Ok(canonical) = fs::canonicalize(path) else {
        return Ok(());
    };
    if canonical != path {
        return Err(package_lockfile_error(format!(
            "{label} {} is not a canonical resolved path; expected {}",
            path.display(),
            canonical.display()
        )));
    }
    Ok(())
}

fn canonicalize_import_root(label: &str, path: &Path) -> Result<PathBuf, CompileError> {
    let root = fs::canonicalize(path).map_err(|err| {
        package_lockfile_error(format!("canonicalize {label} {}: {err}", path.display()))
    })?;
    if !root.is_dir() {
        return Err(package_lockfile_error(format!(
            "{label} {} is not a directory",
            root.display()
        )));
    }
    Ok(root)
}

fn resolve_lockfile_import(
    import: &LeadingImportPath,
    roots: &[PackageLockfileImportSearchRoot],
    source_library_id: u32,
    source_path: &Path,
    source: &str,
) -> Result<PackageLockfileResolvedImport, CompileError> {
    let import_path = import.path.as_str();
    let mut searched_paths = Vec::with_capacity(roots.len());
    if source_library_id == PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID {
        let mut stdlib_matches = collect_lockfile_import_matches(
            import_path,
            roots
                .iter()
                .filter(|root| root.library_id == PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID),
            &mut searched_paths,
        )?;
        match stdlib_matches.len() {
            0 => {}
            1 => return Ok(stdlib_matches.remove(0)),
            _ => {
                let candidates = lockfile_import_candidates(&stdlib_matches);
                return Err(package_lockfile_error(format!(
                    "import graph ambiguous source-root module {import_path} from {}; candidates: {candidates}",
                    source_path.display()
                )));
            }
        }

        let user_matches = collect_lockfile_import_matches(
            import_path,
            roots
                .iter()
                .filter(|root| root.library_id == PACKAGE_LOCKFILE_USER_LIBRARY_ID),
            &mut searched_paths,
        )?;
        if !user_matches.is_empty() {
            let candidates = lockfile_import_candidates(&user_matches);
            return Err(package_lockfile_error(format!(
                "package boundary: stdlib source {} imports user source-root module {import_path}; stdlib sources may not import package/user roots; candidates: {candidates}",
                source_path.display()
            )));
        }

        let searched = searched_paths
            .iter()
            .map(|path| path.display().to_string())
            .collect::<Vec<_>>()
            .join("; ");
        return Err(missing_lockfile_import_diagnostic(
            source,
            source_path,
            import,
            &searched,
        ));
    }

    let user_matches = collect_lockfile_import_matches(
        import_path,
        roots
            .iter()
            .filter(|root| root.library_id == PACKAGE_LOCKFILE_USER_LIBRARY_ID),
        &mut searched_paths,
    )?;
    match user_matches.len() {
        0 => {}
        1 => return Ok(user_matches.into_iter().next().expect("one user match")),
        _ => {
            let candidates = lockfile_import_candidates(&user_matches);
            return Err(package_lockfile_error(format!(
                "import graph ambiguous source-root module {import_path} from {}; candidates: {candidates}",
                source_path.display()
            )));
        }
    }

    let mut matches = collect_lockfile_import_matches(
        import_path,
        roots
            .iter()
            .filter(|root| root.library_id == PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID),
        &mut searched_paths,
    )?;

    match matches.len() {
        0 => {
            let searched = searched_paths
                .iter()
                .map(|path| path.display().to_string())
                .collect::<Vec<_>>()
                .join("; ");
            Err(missing_lockfile_import_diagnostic(
                source,
                source_path,
                import,
                &searched,
            ))
        }
        1 => Ok(matches.remove(0)),
        _ => {
            let candidates = lockfile_import_candidates(&matches);
            Err(package_lockfile_error(format!(
                "import graph ambiguous source-root module {import_path} from {}; candidates: {candidates}",
                source_path.display()
            )))
        }
    }
}

fn missing_lockfile_import_diagnostic(
    source: &str,
    source_path: &Path,
    import: &LeadingImportPath,
    searched: &str,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0001", format!("missing source-root module {}", import.path))
            .with_primary_label(diagnostic_label_from_source_span(
                source_path,
                source,
                import.start,
                import.len.max("import".len()),
                "imported here",
            ))
            .with_note(format!("package replay searched {searched}"))
            .with_note(
                "package names and lockfile roots are control-plane metadata; provide a source-root .lani file whose leading module declaration matches the import path",
            ),
    )
}

fn collect_lockfile_import_matches<'a>(
    import_path: &str,
    roots: impl Iterator<Item = &'a PackageLockfileImportSearchRoot>,
    searched_paths: &mut Vec<PathBuf>,
) -> Result<Vec<PackageLockfileResolvedImport>, CompileError> {
    let mut matches = Vec::new();

    for root in roots {
        let source_path = lockfile_import_source_path(&root.root, import_path);
        searched_paths.push(source_path.clone());
        let Ok(canonical_source_path) = fs::canonicalize(&source_path) else {
            continue;
        };
        if !canonical_source_path.starts_with(&root.root) {
            return Err(package_lockfile_error(format!(
                "import graph path {import_path} resolves outside {} {}",
                root.label,
                root.root.display()
            )));
        }
        if canonical_source_path.is_file()
            && !matches
                .iter()
                .any(|candidate: &PackageLockfileResolvedImport| {
                    candidate.path == canonical_source_path
                        && candidate.library_id == root.library_id
                })
        {
            matches.push(PackageLockfileResolvedImport {
                library_id: root.library_id,
                label: root.label,
                path: canonical_source_path,
            });
        }
    }

    Ok(matches)
}

fn lockfile_import_candidates(matches: &[PackageLockfileResolvedImport]) -> String {
    matches
        .iter()
        .map(|candidate| format!("{}: {}", candidate.label, candidate.path.display()))
        .collect::<Vec<_>>()
        .join("; ")
}

fn lockfile_import_source_path(source_root: &Path, import_path: &str) -> PathBuf {
    let mut path = source_root.to_path_buf();
    for segment in import_path.split("::") {
        path.push(segment);
    }
    path.set_extension("lani");
    path
}

fn valid_lockfile_label(label: &str) -> bool {
    let bytes = label.as_bytes();
    !bytes.is_empty()
        && bytes
            .first()
            .is_some_and(|byte| byte.is_ascii_alphanumeric())
        && bytes
            .last()
            .is_some_and(|byte| byte.is_ascii_alphanumeric())
        && bytes
            .iter()
            .all(|&byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-' | b':'))
}

fn package_lockfile_error(message: impl Into<String>) -> CompileError {
    CompileError::GpuFrontend(format!("package lockfile: {}", message.into()))
}
