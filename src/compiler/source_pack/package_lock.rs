use std::{
    collections::{BTreeMap, BTreeSet},
    fmt::Write as _,
    fs,
    path::{Path, PathBuf},
};

use serde::{Deserialize, Deserializer, Serialize, Serializer, de::Error as _, ser::Error as _};

use super::{
    package_manifest::{
        PACKAGE_MODULE_PATH_SEGMENT_LIMIT,
        PACKAGE_NAME_RULES,
        is_lani_source_path,
        package_source_root_relative_module_path_with_label,
        resolved_paths_overlap,
        valid_package_name,
    },
    write_file_atomic,
};
use crate::compiler::{
    CompileError,
    Diagnostic,
    EntrySourceRoots,
    ExplicitSourcePack,
    ExplicitSourcePackPathManifest,
    PACKAGE_MANIFEST_MAX_ROOTS,
    ResolvedPackageManifest,
    SourcePackLibraryDependency,
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

/// Optional produced-artifact identity metadata. Paths and hashes are
/// control-plane reproducibility evidence; each produced path has one
/// unambiguous identity, and semantic module identity remains owned by
/// GPU-parsed module/import records.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PackageLockfileArtifact {
    pub target: String,
    pub kind: String,
    pub path: PathBuf,
    pub byte_len: usize,
    pub digest: String,
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
        self.validate().map_err(S::Error::custom)?;
        self.validate_replay_integrity().map_err(S::Error::custom)?;
        let path_manifest = self
            .load_path_manifest_without_input_validation()
            .map_err(S::Error::custom)?;
        self.validate_path_manifest_file_set(&path_manifest)
            .map_err(S::Error::custom)?;
        let inputs =
            Self::input_identity_from_path_manifest(&path_manifest).map_err(S::Error::custom)?;
        self.validate_artifact_source_collisions(&inputs)
            .map_err(S::Error::custom)?;
        let source_identities = self
            .source_identities_from_path_manifest(&path_manifest)
            .map_err(S::Error::custom)?;
        let import_graph = self
            .import_graph_from_path_manifest(&path_manifest)
            .map_err(S::Error::custom)?;
        let artifacts = PackageLockfileArtifacts::from_files(self.artifacts.clone())
            .map_err(S::Error::custom)?;
        let document = PackageLockfileDocument::from_lockfile(
            self,
            Some(inputs),
            Some(source_identities),
            Some(import_graph),
            artifacts,
        );
        document.serialize(serializer)
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

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct PackageLockfileImportGraph {
    library_dependencies: Vec<SourcePackLibraryDependency>,
    imports: Vec<PackageLockfileImportEdge>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct PackageLockfileReplayIntegrity {
    inputs: PackageLockfileInputs,
    source_identities: PackageLockfileSourceIdentities,
    import_graph: PackageLockfileImportGraph,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct PackageLockfileArtifacts {
    digest_algorithm: String,
    files: Vec<PackageLockfileArtifact>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct PackageLockfileImportEdge {
    source_library_id: u32,
    source_path: PathBuf,
    source_module_path: String,
    import_path: String,
    target_library_id: u32,
    target_path: PathBuf,
    target_module_path: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct PackageLockfileImportSearchRoot {
    library_id: u32,
    label: &'static str,
    root: PathBuf,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct PackageLockfileResolvedImport {
    library_id: u32,
    label: &'static str,
    path: PathBuf,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum PackageLockfilePathKind {
    Module,
    Import,
}

impl PackageLockfilePathKind {
    fn label(self) -> &'static str {
        match self {
            PackageLockfilePathKind::Module => "module",
            PackageLockfilePathKind::Import => "import",
        }
    }
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
        let document = serde_json::from_str::<PackageLockfileDocument>(source).map_err(|err| {
            CompileError::GpuFrontend(format!("parse package lockfile JSON: {err}"))
        })?;
        document.to_validated_lockfile()
    }

    pub fn load_json_file(path: impl AsRef<Path>) -> Result<Self, CompileError> {
        let path = path.as_ref();
        let source = fs::read_to_string(path).map_err(|err| {
            CompileError::GpuFrontend(format!("read package lockfile {}: {err}", path.display()))
        })?;
        Self::parse_json(&source)
    }

    pub fn to_json_pretty(&self) -> Result<String, CompileError> {
        serde_json::to_string_pretty(self).map_err(|err| {
            CompileError::GpuFrontend(format!("serialize package lockfile JSON: {err}"))
        })
    }

    pub fn write_json_file(&self, path: impl AsRef<Path>) -> Result<(), CompileError> {
        let path = path.as_ref();
        let source = self.to_json_pretty()?;
        self.validate_output_path_is_outside_source_roots(path)?;
        write_file_atomic(path, source.as_bytes(), "package lockfile")
    }

    fn validate_output_path_is_outside_source_roots(
        &self,
        path: &Path,
    ) -> Result<(), CompileError> {
        let Some(output_path) = lockfile_output_identity_path(path) else {
            return Ok(());
        };
        if self.roots.iter().any(|root| output_path.starts_with(root))
            || self
                .stdlib_root
                .as_ref()
                .is_some_and(|root| output_path.starts_with(root))
        {
            return Err(package_lockfile_error(format!(
                "lockfile output path {} is inside a package source root; choose a separate lockfile path so package source files and control-plane artifacts stay separate",
                output_path.display()
            )));
        }
        Ok(())
    }
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

impl PackageLockfileArtifact {
    pub fn from_existing_file(
        target: impl Into<String>,
        kind: impl Into<String>,
        path: impl AsRef<Path>,
    ) -> Result<Self, CompileError> {
        let path = path.as_ref();
        let canonical_path = fs::canonicalize(path).map_err(|err| {
            package_lockfile_error(format!(
                "canonicalize artifact file {}: {err}",
                path.display()
            ))
        })?;
        let bytes = fs::read(&canonical_path).map_err(|err| {
            package_lockfile_error(format!(
                "read artifact file {}: {err}",
                canonical_path.display()
            ))
        })?;
        let artifact = Self {
            target: target.into(),
            kind: kind.into(),
            path: canonical_path,
            byte_len: bytes.len(),
            digest: stable_content_digest(&bytes),
        };
        artifact.validate_shape()?;
        Ok(artifact)
    }

    fn validate_shape(&self) -> Result<(), CompileError> {
        if !valid_lockfile_label(&self.target) {
            return Err(package_lockfile_error(format!(
                "artifact target {:?} must contain only ASCII letters, digits, '.', '_', '-' or ':'",
                self.target
            )));
        }
        if !valid_lockfile_label(&self.kind) {
            return Err(package_lockfile_error(format!(
                "artifact kind {:?} must contain only ASCII letters, digits, '.', '_', '-' or ':'",
                self.kind
            )));
        }
        validate_resolved_path("artifact file", &self.path)?;
        if !valid_stable_content_digest(&self.digest) {
            return Err(package_lockfile_error(format!(
                "artifact file {} has invalid digest {:?}",
                self.path.display(),
                self.digest
            )));
        }
        Ok(())
    }
}

impl PackageLockfile {
    pub fn validate(&self) -> Result<(), CompileError> {
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
            validate_resolved_path("source root", root)?;
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
            validate_resolved_path("stdlib root", stdlib_root)?;
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
                "entry {} is not under any resolved source root",
                self.entry.display()
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
        for root in &self.roots {
            validate_existing_resolved_dir("source root", root)?;
        }
        if let Some(stdlib_root) = &self.stdlib_root {
            validate_existing_resolved_dir("stdlib root", stdlib_root)?;
        }
        validate_existing_resolved_file("entry", &self.entry)?;
        self.validate_artifacts()?;
        Ok(())
    }

    fn validate_artifacts(&self) -> Result<(), CompileError> {
        let Some(artifacts) = PackageLockfileArtifacts::from_files(self.artifacts.clone())? else {
            return Ok(());
        };
        artifacts.validate_shape()?;
        for artifact in &artifacts.files {
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
        self.validate_section_consistency(
            &integrity.inputs,
            &integrity.source_identities,
            &integrity.import_graph,
        )?;
        self.validate_artifact_source_collisions(&integrity.inputs)?;
        self.validate_import_graph(&integrity.import_graph)?;
        self.validate_source_identities(&integrity.source_identities)?;
        self.validate_inputs(&integrity.inputs)?;
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
        self.validate()?;
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
        self.validate()?;
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
            files.push(PackageLockfileSourceIdentityFile {
                library_id: file.library_id,
                path: file.path.clone(),
                source_root_index: Some(source_root_index),
                source_root_relative_path: Some(source_root_relative_path),
                module_path: leading_lockfile_module_path(&source, &file.path)?,
            });
        }
        files.sort_by(compare_source_identity_file_identity);
        let identities = PackageLockfileSourceIdentities { files };
        identities.validate_shape()?;
        self.validate_source_identity_ownership(&identities)?;
        Ok(identities)
    }

    fn import_graph(&self) -> Result<PackageLockfileImportGraph, CompileError> {
        self.validate()?;
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
        let mut seen_import_edges = BTreeSet::new();

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
            for import_path in leading_lockfile_import_paths(&source, &file.path)? {
                let target = resolve_lockfile_import(
                    &import_path,
                    &search_roots,
                    file.library_id,
                    &file.path,
                )?;
                let target_library_id =
                    file_library_ids
                        .get(&target.path)
                        .copied()
                        .ok_or_else(|| {
                            package_lockfile_error(format!(
                                "import graph resolved {} from {} to {}, but the target is not in the source-pack file set",
                                import_path,
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
                    import_path,
                    target_library_id,
                    target_path: target.path,
                    target_module_path,
                };
                if seen_import_edges.insert(edge.identity_key()) {
                    imports.push(edge);
                }
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

    fn validate_import_graph(
        &self,
        expected: &PackageLockfileImportGraph,
    ) -> Result<(), CompileError> {
        expected.validate_shape()?;
        let actual = self.import_graph()?;
        if actual.library_dependencies != expected.library_dependencies {
            return Err(package_lockfile_error(format!(
                "library dependency graph changed; expected {:?}, found {:?}",
                expected.library_dependencies, actual.library_dependencies
            )));
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
                return Err(package_lockfile_error(format!(
                    "import graph changed at edge {index}; expected {} from {} to {}, found {} from {} to {}",
                    expected_import.import_path,
                    expected_import.source_path.display(),
                    expected_import.target_path.display(),
                    actual_import.import_path,
                    actual_import.source_path.display(),
                    actual_import.target_path.display()
                )));
            }
        }
        Ok(())
    }

    fn validate_section_consistency(
        &self,
        inputs: &PackageLockfileInputs,
        source_identities: &PackageLockfileSourceIdentities,
        import_graph: &PackageLockfileImportGraph,
    ) -> Result<(), CompileError> {
        inputs.validate_shape()?;
        source_identities.validate_shape()?;
        import_graph.validate_shape()?;
        self.validate_input_identity_ownership(inputs)?;
        self.validate_import_graph_ownership(import_graph)?;
        self.validate_source_identity_ownership(source_identities)?;

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
            self.validate_file_library_ownership(
                "source identity file",
                file.library_id,
                &file.path,
            )?;
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
                        "source identity file {} in user library {PACKAGE_LOCKFILE_USER_LIBRARY_ID} is not under any resolved source root",
                        path.display()
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
                "import graph edge {edge_index} {endpoint} module path {:?} matches package metadata {:?}, but resolved source-root relative path {} maps to {:?}; package names are control-plane identity and must not replace GPU module declarations",
                edge_module_path,
                self.package,
                relative_path.display(),
                expected_module_path
            )));
        }
        Err(package_lockfile_error(format!(
            "import graph edge {edge_index} {endpoint} module path {:?} does not match resolved source-root relative path {} mapping {:?}",
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
                        "{label} {} in user library {PACKAGE_LOCKFILE_USER_LIBRARY_ID} is not under any resolved source root",
                        path.display()
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
        self.validate()?;
        self.validate_replay_integrity()?;
        self.validate_live_import_graph()?;
        load_entry_with_source_roots(&self.entry, &self.to_entry_source_roots())
    }

    pub fn load_path_manifest(&self) -> Result<ExplicitSourcePackPathManifest, CompileError> {
        self.validate()?;
        self.validate_replay_integrity()?;
        let path_manifest = self.load_path_manifest_without_input_validation()?;
        self.import_graph_from_path_manifest(&path_manifest)?;
        Ok(path_manifest)
    }

    fn load_path_manifest_without_input_validation(
        &self,
    ) -> Result<ExplicitSourcePackPathManifest, CompileError> {
        load_entry_path_manifest_with_source_roots(&self.entry, &self.to_entry_source_roots())
    }

    fn validate_live_import_graph(&self) -> Result<(), CompileError> {
        let path_manifest = self.load_path_manifest_without_input_validation()?;
        self.import_graph_from_path_manifest(&path_manifest)?;
        Ok(())
    }
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
            if let Some(relative_path) = &file.source_root_relative_path {
                validate_source_root_relative_path("source identity relative path", relative_path)?;
            }
            if !seen.insert((file.library_id, file.path.clone())) {
                return Err(package_lockfile_error(format!(
                    "duplicate source identity file for library {} {}",
                    file.library_id,
                    file.path.display()
                )));
            }
            if let Some(module_path) = &file.module_path {
                if !valid_lockfile_module_path(module_path) {
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
            }
        }
        Ok(())
    }
}

impl PackageLockfileArtifacts {
    fn from_files(mut files: Vec<PackageLockfileArtifact>) -> Result<Option<Self>, CompileError> {
        if files.is_empty() {
            return Ok(None);
        }
        files.sort_by(compare_artifact_identity);
        let artifacts = Self {
            digest_algorithm: PACKAGE_LOCKFILE_DIGEST_ALGORITHM.to_string(),
            files,
        };
        artifacts.validate_shape()?;
        Ok(Some(artifacts))
    }

    fn validate_shape(&self) -> Result<(), CompileError> {
        if self.digest_algorithm != PACKAGE_LOCKFILE_DIGEST_ALGORITHM {
            return Err(package_lockfile_error(format!(
                "unsupported artifact digest algorithm {:?}; expected {PACKAGE_LOCKFILE_DIGEST_ALGORITHM:?}",
                self.digest_algorithm
            )));
        }
        if self.files.is_empty() {
            return Err(package_lockfile_error(
                "artifact identity must declare at least one produced file",
            ));
        }
        let mut seen_identities = BTreeSet::new();
        let mut seen_paths = BTreeSet::new();
        let mut previous_artifact: Option<&PackageLockfileArtifact> = None;
        for artifact in &self.files {
            artifact.validate_shape()?;
            if let Some(previous_artifact) = previous_artifact {
                if compare_artifact_identity(previous_artifact, artifact).is_gt() {
                    return Err(package_lockfile_error(format!(
                        "artifact identity files must be sorted by target, kind, and canonical path; artifact {} kind {} path {} appears after artifact {} kind {} path {}; regenerate the package lockfile",
                        artifact.target,
                        artifact.kind,
                        artifact.path.display(),
                        previous_artifact.target,
                        previous_artifact.kind,
                        previous_artifact.path.display()
                    )));
                }
            }
            previous_artifact = Some(artifact);
            if !seen_paths.insert(artifact.path.clone()) {
                return Err(package_lockfile_error(format!(
                    "duplicate artifact path {}; produced artifact paths must be unique across targets and kinds",
                    artifact.path.display()
                )));
            }
            if !seen_identities.insert((
                artifact.target.clone(),
                artifact.kind.clone(),
                artifact.path.clone(),
            )) {
                return Err(package_lockfile_error(format!(
                    "duplicate artifact file for target {} kind {} {}",
                    artifact.target,
                    artifact.kind,
                    artifact.path.display()
                )));
            }
        }
        Ok(())
    }
}

fn compare_artifact_identity(
    left: &PackageLockfileArtifact,
    right: &PackageLockfileArtifact,
) -> std::cmp::Ordering {
    left.target
        .cmp(&right.target)
        .then_with(|| left.kind.cmp(&right.kind))
        .then_with(|| left.path.cmp(&right.path))
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
        if let Some(artifacts) = &self.artifacts {
            artifacts.validate_shape()?;
        }
        let mut lockfile = self.to_lockfile();
        lockfile.validate()?;
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
        lockfile.validate_section_consistency(inputs, source_identities, import_graph)?;
        lockfile.validate_artifact_source_collisions(inputs)?;
        lockfile.validate_import_graph(import_graph)?;
        lockfile.validate_source_identities(source_identities)?;
        lockfile.validate_inputs(inputs)?;
        lockfile.replay_integrity = Some(PackageLockfileReplayIntegrity {
            inputs: inputs.clone(),
            source_identities: source_identities.clone(),
            import_graph: import_graph.clone(),
        });
        Ok(lockfile)
    }
}

impl PackageLockfileImportGraph {
    fn validate_shape(&self) -> Result<(), CompileError> {
        let mut seen_dependencies = BTreeSet::new();
        let mut previous_dependency: Option<&SourcePackLibraryDependency> = None;
        for dependency in &self.library_dependencies {
            if dependency.library_id == dependency.depends_on_library_id {
                return Err(package_lockfile_error(format!(
                    "library {} depends on itself",
                    dependency.library_id
                )));
            }
            if dependency.library_id == PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID
                && dependency.depends_on_library_id == PACKAGE_LOCKFILE_USER_LIBRARY_ID
            {
                return Err(package_lockfile_error(format!(
                    "package boundary: stdlib library {PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID} may not depend on package/user library {PACKAGE_LOCKFILE_USER_LIBRARY_ID}"
                )));
            }
            if !seen_dependencies.insert((dependency.library_id, dependency.depends_on_library_id))
            {
                return Err(package_lockfile_error(format!(
                    "duplicate library dependency {} -> {}",
                    dependency.library_id, dependency.depends_on_library_id
                )));
            }
            if let Some(previous_dependency) = previous_dependency {
                if (
                    previous_dependency.library_id,
                    previous_dependency.depends_on_library_id,
                ) > (dependency.library_id, dependency.depends_on_library_id)
                {
                    return Err(package_lockfile_error(format!(
                        "import graph library dependencies must be sorted by library id and dependency library id; dependency {} -> {} appears after {} -> {}; regenerate the package lockfile from the package manifest",
                        dependency.library_id,
                        dependency.depends_on_library_id,
                        previous_dependency.library_id,
                        previous_dependency.depends_on_library_id
                    )));
                }
            }
            previous_dependency = Some(dependency);
        }

        let allowed_cross_library_imports = self
            .library_dependencies
            .iter()
            .map(|dependency| (dependency.library_id, dependency.depends_on_library_id))
            .collect::<BTreeSet<_>>();
        let mut seen_imports = BTreeSet::new();
        let mut seen_source_import_targets = BTreeMap::new();
        let mut cross_library_imports = BTreeSet::new();
        let mut previous_import: Option<&PackageLockfileImportEdge> = None;
        for (edge_index, import) in self.imports.iter().enumerate() {
            validate_resolved_source_path("import graph source file", &import.source_path)?;
            validate_resolved_source_path("import graph target file", &import.target_path)?;
            if !valid_lockfile_import_path(&import.import_path) {
                return Err(package_lockfile_error(format!(
                    "invalid import graph path {:?}",
                    import.import_path
                )));
            }
            if !valid_lockfile_module_path(&import.source_module_path) {
                return Err(package_lockfile_error(format!(
                    "invalid import graph source module path {:?}",
                    import.source_module_path
                )));
            }
            if import.source_module_path == import.import_path {
                return Err(package_lockfile_error(format!(
                    "import graph semantic self-cycle: source module {} in library {} {} imports its own module path; package imports must resolve to a different module identity",
                    import.source_module_path,
                    import.source_library_id,
                    import.source_path.display()
                )));
            }
            if !valid_lockfile_module_path(&import.target_module_path) {
                return Err(package_lockfile_error(format!(
                    "invalid import graph target module path {:?}",
                    import.target_module_path
                )));
            }
            if import.target_module_path != import.import_path {
                return Err(package_lockfile_error(format!(
                    "import graph edge {edge_index} import path {} resolves to target module {}; package imports must resolve by declared module identity",
                    import.import_path, import.target_module_path
                )));
            }
            if import.source_library_id != import.target_library_id
                && !allowed_cross_library_imports
                    .contains(&(import.source_library_id, import.target_library_id))
            {
                if import.source_library_id == PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID
                    && import.target_library_id == PACKAGE_LOCKFILE_USER_LIBRARY_ID
                {
                    return Err(package_lockfile_error(format!(
                        "package boundary: stdlib source {} imports user source-root module {}; stdlib sources may not import package/user roots (target {})",
                        import.source_path.display(),
                        import.import_path,
                        import.target_path.display()
                    )));
                }
                return Err(package_lockfile_error(format!(
                    "import graph edge {edge_index} from library {} to library {} is not permitted by the library dependency graph",
                    import.source_library_id, import.target_library_id
                )));
            }
            if import.source_library_id == import.target_library_id
                && import.source_path == import.target_path
            {
                return Err(package_lockfile_error(format!(
                    "import graph self-cycle: source {} in library {} imports its own module {}; package imports must resolve to a different source file",
                    import.source_path.display(),
                    import.source_library_id,
                    import.import_path
                )));
            }
            if import.source_library_id != import.target_library_id {
                cross_library_imports.insert((import.source_library_id, import.target_library_id));
            }
            let source_import_key = (
                import.source_library_id,
                import.source_path.clone(),
                import.import_path.clone(),
            );
            let target_key = (import.target_library_id, import.target_path.clone());
            if let Some(previous_target) = seen_source_import_targets.get(&source_import_key) {
                if previous_target != &target_key {
                    let (previous_library_id, previous_path) = previous_target;
                    return Err(package_lockfile_error(format!(
                        "ambiguous import graph edge {} from library {} {}; previous target library {} {}, new target library {} {}; package imports must resolve to one target per source import path",
                        import.import_path,
                        import.source_library_id,
                        import.source_path.display(),
                        previous_library_id,
                        previous_path.display(),
                        import.target_library_id,
                        import.target_path.display()
                    )));
                }
            } else {
                seen_source_import_targets.insert(source_import_key, target_key);
            }
            if !seen_imports.insert(import.identity_key()) {
                return Err(package_lockfile_error(format!(
                    "duplicate import graph edge {} from library {} {} to library {} {}",
                    import.import_path,
                    import.source_library_id,
                    import.source_path.display(),
                    import.target_library_id,
                    import.target_path.display()
                )));
            }
            if let Some(previous_import) = previous_import {
                if compare_import_edge_identity(previous_import, import).is_gt() {
                    return Err(package_lockfile_error(format!(
                        "import graph edges must be sorted by source library, source path, import path, target library, and target path; edge {} from library {} {} to library {} {} appears after edge {} from library {} {} to library {} {}; regenerate the package lockfile from the package manifest",
                        import.import_path,
                        import.source_library_id,
                        import.source_path.display(),
                        import.target_library_id,
                        import.target_path.display(),
                        previous_import.import_path,
                        previous_import.source_library_id,
                        previous_import.source_path.display(),
                        previous_import.target_library_id,
                        previous_import.target_path.display()
                    )));
                }
            }
            previous_import = Some(import);
        }
        for dependency in &self.library_dependencies {
            if !cross_library_imports
                .contains(&(dependency.library_id, dependency.depends_on_library_id))
            {
                return Err(package_lockfile_error(format!(
                    "import graph library dependency {} -> {} has no matching cross-library import edge",
                    dependency.library_id, dependency.depends_on_library_id
                )));
            }
        }
        Ok(())
    }
}

impl PackageLockfileImportEdge {
    fn identity_key(&self) -> (u32, PathBuf, String, u32, PathBuf) {
        (
            self.source_library_id,
            self.source_path.clone(),
            self.import_path.clone(),
            self.target_library_id,
            self.target_path.clone(),
        )
    }
}

fn compare_import_edge_identity(
    left: &PackageLockfileImportEdge,
    right: &PackageLockfileImportEdge,
) -> std::cmp::Ordering {
    left.source_library_id
        .cmp(&right.source_library_id)
        .then_with(|| left.source_path.cmp(&right.source_path))
        .then_with(|| left.import_path.cmp(&right.import_path))
        .then_with(|| left.target_library_id.cmp(&right.target_library_id))
        .then_with(|| left.target_path.cmp(&right.target_path))
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

fn import_graph_edge_summary(imports: &[PackageLockfileImportEdge]) -> String {
    if imports.is_empty() {
        return "none".to_string();
    }
    let mut edges = imports
        .iter()
        .take(8)
        .map(|edge| {
            format!(
                "{} from library {} {} to library {} {}",
                edge.import_path,
                edge.source_library_id,
                edge.source_path.display(),
                edge.target_library_id,
                edge.target_path.display()
            )
        })
        .collect::<Vec<_>>();
    if imports.len() > edges.len() {
        edges.push(format!("{} more", imports.len() - edges.len()));
    }
    edges.join("; ")
}

fn import_graph_reachable_files_from_entry(
    entry_key: &(u32, PathBuf),
    import_graph: &PackageLockfileImportGraph,
) -> BTreeSet<(u32, PathBuf)> {
    let mut edges_by_source = BTreeMap::<(u32, PathBuf), Vec<(u32, PathBuf)>>::new();
    for import in &import_graph.imports {
        edges_by_source
            .entry((import.source_library_id, import.source_path.clone()))
            .or_default()
            .push((import.target_library_id, import.target_path.clone()));
    }

    let mut reachable = BTreeSet::new();
    let mut pending = vec![entry_key.clone()];
    while let Some(file_key) = pending.pop() {
        if !reachable.insert(file_key.clone()) {
            continue;
        }
        if let Some(targets) = edges_by_source.get(&file_key) {
            pending.extend(
                targets
                    .iter()
                    .filter(|target| !reachable.contains(*target))
                    .cloned(),
            );
        }
    }
    reachable
}

fn validate_import_graph_module_endpoint(
    edge_index: usize,
    endpoint: &str,
    library_id: u32,
    path: &Path,
    edge_module_path: &str,
    source_identity_module_path: &str,
    package_module_path: Option<&str>,
    package: &str,
) -> Result<(), CompileError> {
    if edge_module_path == source_identity_module_path {
        return Ok(());
    }
    if package_module_path == Some(edge_module_path) {
        return Err(package_lockfile_error(format!(
            "import graph edge {edge_index} {endpoint} module path {:?} matches package metadata {:?}, but source identity module is {:?} for library {} {}; package names are control-plane identity and must not replace GPU module declarations",
            edge_module_path,
            package,
            source_identity_module_path,
            library_id,
            path.display()
        )));
    }
    Err(package_lockfile_error(format!(
        "import graph edge {edge_index} {endpoint} module path {:?} does not match source identity module {:?} for library {} {}",
        edge_module_path,
        source_identity_module_path,
        library_id,
        path.display()
    )))
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
    hex.len() == 16 && hex.bytes().all(|byte| byte.is_ascii_hexdigit())
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
    validate_canonical_resolved_path_if_present(label, path)?;
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

fn leading_lockfile_module_path(
    source: &str,
    source_path: &Path,
) -> Result<Option<String>, CompileError> {
    let bytes = source.as_bytes();
    let offset = skip_ws_and_comments(bytes, 0, source_path)?;
    if !keyword_at(bytes, offset, b"module") {
        return Ok(None);
    }

    let offset = offset + "module".len();
    let (module_path, next_offset) =
        parse_lockfile_path(source, offset, source_path, PackageLockfilePathKind::Module)?;
    let next_offset = expect_semicolon(source, next_offset, source_path, "module")?;
    ensure_no_additional_module_declaration(source, next_offset, source_path, &module_path)?;
    Ok(Some(module_path))
}

fn leading_lockfile_import_paths(
    source: &str,
    source_path: &Path,
) -> Result<Vec<String>, CompileError> {
    let bytes = source.as_bytes();
    let mut imports = Vec::new();
    let mut offset = 0usize;

    loop {
        offset = skip_ws_and_comments(bytes, offset, source_path)?;
        if keyword_at(bytes, offset, b"module") {
            offset += "module".len();
            let (_, next_offset) =
                parse_lockfile_path(source, offset, source_path, PackageLockfilePathKind::Module)?;
            offset = expect_semicolon(source, next_offset, source_path, "module")?;
            continue;
        }
        if keyword_at(bytes, offset, b"import") {
            let import_start = offset;
            offset += "import".len();
            offset = skip_ws_and_comments(bytes, offset, source_path)?;
            if bytes.get(offset) == Some(&b'"') {
                let quoted_end = skip_quoted_import_path(source, offset, source_path)?;
                return Err(unsupported_lockfile_import_form_diagnostic(
                    source,
                    source_path,
                    import_start,
                    quoted_end.saturating_sub(import_start),
                ));
            }
            let (path, next_offset) =
                parse_lockfile_path(source, offset, source_path, PackageLockfilePathKind::Import)?;
            offset = expect_semicolon(source, next_offset, source_path, "import")?;
            imports.push(path);
            continue;
        }
        reject_non_leading_lockfile_imports(source, offset, source_path)?;
        return Ok(imports);
    }
}

fn reject_non_leading_lockfile_imports(
    source: &str,
    offset: usize,
    source_path: &Path,
) -> Result<(), CompileError> {
    let bytes = source.as_bytes();
    let mut offset = offset;

    while offset < bytes.len() {
        if bytes.get(offset..offset + 2) == Some(b"//") {
            offset += 2;
            while bytes.get(offset).is_some_and(|byte| *byte != b'\n') {
                offset += 1;
            }
            continue;
        }
        if bytes.get(offset..offset + 2) == Some(b"/*") {
            let comment_start = offset;
            offset += 2;
            while offset + 1 < bytes.len() && bytes.get(offset..offset + 2) != Some(b"*/") {
                offset += 1;
            }
            if offset + 1 >= bytes.len() {
                return Err(unterminated_block_comment_error(source_path, comment_start));
            }
            offset += 2;
            continue;
        }
        if bytes.get(offset) == Some(&b'"') {
            offset = skip_string_literal(source, offset, source_path)?;
            continue;
        }
        if bytes.get(offset) == Some(&b'\'') {
            offset = skip_char_literal(source, offset, source_path)?;
            continue;
        }
        if keyword_at_anywhere(bytes, offset, b"import") {
            return Err(package_lockfile_error(format!(
                "non-leading import declaration in {}; package lockfile import graphs require module-path imports before other items so persisted import edges stay complete",
                source_path.display()
            )));
        }
        offset += 1;
    }

    Ok(())
}

fn ensure_no_additional_module_declaration(
    source: &str,
    offset: usize,
    source_path: &Path,
    first_module_path: &str,
) -> Result<(), CompileError> {
    let bytes = source.as_bytes();
    let mut offset = offset;
    let mut still_leading_declarations = true;

    loop {
        offset = skip_ws_and_comments(bytes, offset, source_path)?;
        if offset >= bytes.len() {
            return Ok(());
        }
        if keyword_at_anywhere(bytes, offset, b"module") {
            offset += "module".len();
            let (module_path, _) =
                parse_lockfile_path(source, offset, source_path, PackageLockfilePathKind::Module)?;
            if still_leading_declarations {
                return Err(package_lockfile_error(format!(
                    "source identity file {} has multiple leading module declarations ({first_module_path} and {module_path}); package lockfiles require exactly one module declaration per source file",
                    source_path.display()
                )));
            }
            return Err(package_lockfile_error(format!(
                "source identity file {} has non-leading module declaration {module_path} after leading module {first_module_path}; package lockfiles require exactly one module declaration per source file",
                source_path.display()
            )));
        }
        if still_leading_declarations && keyword_at(bytes, offset, b"import") {
            let import_start = offset;
            offset += "import".len();
            offset = skip_ws_and_comments(bytes, offset, source_path)?;
            if bytes.get(offset) == Some(&b'"') {
                let quoted_end = skip_quoted_import_path(source, offset, source_path)?;
                return Err(unsupported_lockfile_import_form_diagnostic(
                    source,
                    source_path,
                    import_start,
                    quoted_end.saturating_sub(import_start),
                ));
            } else {
                let (_, next_offset) = parse_lockfile_path(
                    source,
                    offset,
                    source_path,
                    PackageLockfilePathKind::Import,
                )?;
                offset = next_offset;
            }
            offset = expect_semicolon(source, offset, source_path, "import")?;
            continue;
        }
        still_leading_declarations = false;
        if bytes.get(offset) == Some(&b'"') {
            offset = skip_string_literal(source, offset, source_path)?;
        } else if bytes.get(offset) == Some(&b'\'') {
            offset = skip_char_literal(source, offset, source_path)?;
        } else {
            offset += 1;
        }
    }
}

fn resolve_lockfile_import(
    import_path: &str,
    roots: &[PackageLockfileImportSearchRoot],
    source_library_id: u32,
    source_path: &Path,
) -> Result<PackageLockfileResolvedImport, CompileError> {
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
        return Err(package_lockfile_error(format!(
            "import graph missing source-root module {import_path} from {}; searched {searched}",
            source_path.display()
        )));
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
            Err(package_lockfile_error(format!(
                "import graph missing source-root module {import_path} from {}; searched {searched}",
                source_path.display()
            )))
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

fn parse_lockfile_path(
    source: &str,
    offset: usize,
    source_path: &Path,
    kind: PackageLockfilePathKind,
) -> Result<(String, usize), CompileError> {
    let bytes = source.as_bytes();
    let mut offset = skip_ws_and_comments(bytes, offset, source_path)?;
    let mut segments = Vec::new();

    loop {
        let segment_start = offset;
        offset = parse_ident(bytes, offset).ok_or_else(|| {
            package_lockfile_error(format!(
                "import graph expected identifier in {} path at {} byte {segment_start}",
                kind.label(),
                source_path.display()
            ))
        })?;
        segments.push(&source[segment_start..offset]);
        if segments.len() > PACKAGE_MODULE_PATH_SEGMENT_LIMIT {
            return Err(package_lockfile_error(format!(
                "package lockfile supports at most {PACKAGE_MODULE_PATH_SEGMENT_LIMIT} path segments in {} path at {} byte {segment_start}; deeper module identities are not part of the current GPU resolver slice",
                kind.label(),
                source_path.display()
            )));
        }
        offset = skip_ws_and_comments(bytes, offset, source_path)?;
        if bytes.get(offset..offset + 2) != Some(b"::") {
            break;
        }
        offset += 2;
        offset = skip_ws_and_comments(bytes, offset, source_path)?;
    }

    Ok((segments.join("::"), offset))
}

fn skip_quoted_import_path(
    source: &str,
    offset: usize,
    source_path: &Path,
) -> Result<usize, CompileError> {
    skip_string_literal(source, offset, source_path)
}

fn unsupported_lockfile_import_form_diagnostic(
    source: &str,
    source_path: &Path,
    start: usize,
    len: usize,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0011", "unsupported import form")
            .with_primary_label(diagnostic_label_from_source_span(
                source_path,
                source,
                start,
                len,
                "package lockfiles require module-path imports here",
            ))
            .with_note(
                "package lockfile import graphs record module-path imports such as `import app::module;`",
            )
            .with_note(
                "quoted imports are unsupported in this edition and are rejected instead of being persisted as incomplete package metadata",
            ),
    )
}

fn skip_string_literal(
    source: &str,
    offset: usize,
    source_path: &Path,
) -> Result<usize, CompileError> {
    skip_quoted_literal(source, offset, source_path, b'"', "string literal")
}

fn skip_char_literal(
    source: &str,
    offset: usize,
    source_path: &Path,
) -> Result<usize, CompileError> {
    skip_quoted_literal(source, offset, source_path, b'\'', "character literal")
}

fn skip_quoted_literal(
    source: &str,
    offset: usize,
    source_path: &Path,
    quote: u8,
    label: &str,
) -> Result<usize, CompileError> {
    let bytes = source.as_bytes();
    let literal_start = offset;
    let mut offset = offset + 1;
    while let Some(byte) = bytes.get(offset) {
        if *byte == b'\\' {
            offset = (offset + 2).min(bytes.len());
            continue;
        }
        if *byte == b'\n' {
            return Err(malformed_literal_error(source_path, literal_start, label));
        }
        if *byte == quote {
            return Ok(offset + 1);
        }
        offset += 1;
    }
    Err(malformed_literal_error(source_path, literal_start, label))
}

fn malformed_literal_error(source_path: &Path, offset: usize, label: &str) -> CompileError {
    package_lockfile_error(format!(
        "malformed {label} in {} at byte {offset}; package source-root replay must not skip malformed source while discovering module/import metadata",
        source_path.display()
    ))
}

fn expect_semicolon(
    source: &str,
    offset: usize,
    source_path: &Path,
    context: &str,
) -> Result<usize, CompileError> {
    let bytes = source.as_bytes();
    let offset = skip_ws_and_comments(bytes, offset, source_path)?;
    if bytes.get(offset) == Some(&b';') {
        return Ok(offset + 1);
    }
    Err(package_lockfile_error(format!(
        "import graph expected ';' after {context} path at {} byte {offset}",
        source_path.display()
    )))
}

fn skip_ws_and_comments(
    bytes: &[u8],
    mut offset: usize,
    source_path: &Path,
) -> Result<usize, CompileError> {
    loop {
        while bytes
            .get(offset)
            .is_some_and(|byte| byte.is_ascii_whitespace())
        {
            offset += 1;
        }
        if bytes.get(offset..offset + 2) == Some(b"//") {
            offset += 2;
            while bytes.get(offset).is_some_and(|byte| *byte != b'\n') {
                offset += 1;
            }
            continue;
        }
        if bytes.get(offset..offset + 2) == Some(b"/*") {
            let comment_start = offset;
            offset += 2;
            while offset + 1 < bytes.len() && bytes.get(offset..offset + 2) != Some(b"*/") {
                offset += 1;
            }
            if offset + 1 >= bytes.len() {
                return Err(unterminated_block_comment_error(source_path, comment_start));
            }
            offset += 2;
            continue;
        }
        return Ok(offset);
    }
}

fn unterminated_block_comment_error(source_path: &Path, offset: usize) -> CompileError {
    package_lockfile_error(format!(
        "unterminated block comment in {} at byte {offset}; package source-root replay must not skip malformed source while discovering module/import metadata",
        source_path.display()
    ))
}

fn keyword_at(bytes: &[u8], offset: usize, keyword: &[u8]) -> bool {
    bytes.get(offset..offset + keyword.len()) == Some(keyword)
        && bytes
            .get(offset + keyword.len())
            .is_none_or(|byte| !is_ident_continue(*byte))
}

fn keyword_at_anywhere(bytes: &[u8], offset: usize, keyword: &[u8]) -> bool {
    keyword_at(bytes, offset, keyword)
        && offset
            .checked_sub(1)
            .and_then(|previous| bytes.get(previous))
            .is_none_or(|byte| !is_ident_continue(*byte))
}

fn parse_ident(bytes: &[u8], offset: usize) -> Option<usize> {
    let first = *bytes.get(offset)?;
    if !is_ident_start(first) {
        return None;
    }
    let mut end = offset + 1;
    while bytes.get(end).is_some_and(|byte| is_ident_continue(*byte)) {
        end += 1;
    }
    Some(end)
}

fn is_ident_start(byte: u8) -> bool {
    byte == b'_' || byte.is_ascii_alphabetic()
}

fn is_ident_continue(byte: u8) -> bool {
    is_ident_start(byte) || byte.is_ascii_digit()
}

fn valid_lockfile_import_path(path: &str) -> bool {
    let mut count = 0usize;
    for segment in path.split("::") {
        count += 1;
        if count > PACKAGE_MODULE_PATH_SEGMENT_LIMIT || !valid_lockfile_ident(segment) {
            return false;
        }
    }
    count != 0
}

fn valid_lockfile_module_path(path: &str) -> bool {
    let mut count = 0usize;
    for segment in path.split("::") {
        count += 1;
        if count > PACKAGE_MODULE_PATH_SEGMENT_LIMIT || !valid_lockfile_ident(segment) {
            return false;
        }
    }
    count != 0
}

fn package_name_module_path(package: &str) -> Option<String> {
    let segments = package.split('.').collect::<Vec<_>>();
    if segments.is_empty()
        || segments.len() > PACKAGE_MODULE_PATH_SEGMENT_LIMIT
        || !segments.iter().all(|segment| valid_lockfile_ident(segment))
    {
        return None;
    }
    Some(segments.join("::"))
}

fn valid_lockfile_ident(segment: &str) -> bool {
    let Some(first) = segment.bytes().next() else {
        return false;
    };
    is_ident_start(first) && segment.bytes().skip(1).all(is_ident_continue)
}

fn valid_lockfile_label(label: &str) -> bool {
    !label.is_empty()
        && label
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-' | b':'))
}

fn package_lockfile_error(message: impl Into<String>) -> CompileError {
    CompileError::GpuFrontend(format!("package lockfile: {}", message.into()))
}

#[cfg(test)]
mod tests {
    use std::{
        fs,
        path::{Path, PathBuf},
        sync::atomic::{AtomicU64, Ordering},
        time::{SystemTime, UNIX_EPOCH},
    };

    use super::*;

    static TEMP_DIR_COUNTER: AtomicU64 = AtomicU64::new(0);

    struct TempPackageRoot {
        path: PathBuf,
    }

    impl TempPackageRoot {
        fn new(stem: &str) -> Self {
            let nonce = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("system time should be after unix epoch")
                .as_nanos();
            let path = std::env::temp_dir().join(format!(
                "laniusc_package_lock_{stem}_{}_{}_{}",
                std::process::id(),
                TEMP_DIR_COUNTER.fetch_add(1, Ordering::Relaxed),
                nonce
            ));
            fs::create_dir_all(&path).expect("create package lock test root");
            Self { path }
        }

        fn path(&self) -> &Path {
            &self.path
        }
    }

    impl Drop for TempPackageRoot {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.path);
        }
    }

    #[test]
    fn package_lockfile_serializes_artifacts_in_canonical_identity_order() {
        let root = TempPackageRoot::new("artifact_order_serialize");
        let lockfile = lockfile_with_out_of_order_artifacts(root.path());

        let document =
            serde_json::to_value(&lockfile).expect("serialize lockfile with artifact identities");
        let artifact_files = document
            .get("artifacts")
            .and_then(|artifacts| artifacts.get("files"))
            .and_then(serde_json::Value::as_array)
            .expect("serialized lockfile should include artifact identity files");
        let artifact_kinds = artifact_files
            .iter()
            .map(|artifact| artifact.get("kind").and_then(serde_json::Value::as_str))
            .collect::<Vec<_>>();
        assert_eq!(
            artifact_kinds,
            vec![Some("a-final"), Some("z-final")],
            "public package lockfile serialization should canonicalize artifact identity order"
        );

        let roundtrip = serde_json::from_value::<PackageLockfile>(document)
            .expect("canonically serialized artifact identities should deserialize");
        assert_eq!(
            roundtrip
                .artifacts
                .iter()
                .map(|artifact| artifact.kind.as_str())
                .collect::<Vec<_>>(),
            vec!["a-final", "z-final"],
            "parsed package lockfiles should retain canonical artifact identity order"
        );
    }

    #[test]
    fn package_lockfile_rejects_persisted_artifacts_outside_canonical_identity_order() {
        let root = TempPackageRoot::new("artifact_order_parse");
        let lockfile = lockfile_with_out_of_order_artifacts(root.path());

        let mut document =
            serde_json::to_value(&lockfile).expect("serialize lockfile with artifact identities");
        let artifact_files = document
            .get_mut("artifacts")
            .and_then(|artifacts| artifacts.get_mut("files"))
            .and_then(serde_json::Value::as_array_mut)
            .expect("serialized lockfile should include mutable artifact identity files");
        assert_eq!(
            artifact_files
                .iter()
                .map(|artifact| artifact.get("kind").and_then(serde_json::Value::as_str))
                .collect::<Vec<_>>(),
            vec![Some("a-final"), Some("z-final")],
            "fixture should start from canonical artifact order"
        );
        artifact_files.swap(0, 1);

        let tampered_lockfile =
            serde_json::to_string_pretty(&document).expect("serialize tampered package lockfile");
        let err = PackageLockfile::parse_json(&tampered_lockfile)
            .expect_err("persisted artifact identities must already be canonical");
        let message = format!("{err:?}");
        assert!(
            message.contains("artifact identity files must be sorted")
                && message.contains("target")
                && message.contains("kind")
                && message.contains("canonical path"),
            "expected canonical artifact order error, got {message}"
        );
    }

    fn lockfile_with_out_of_order_artifacts(root: &Path) -> PackageLockfile {
        let source_root = root.join("src");
        let app_root = source_root.join("app");
        fs::create_dir_all(&app_root).expect("create package app source root");
        let entry_path = app_root.join("main.lani");
        fs::write(
            &entry_path,
            r#"
module app::main;

fn main() {
    return 0;
}
"#,
        )
        .expect("write package entry source");

        let artifact_root = root.join("target");
        fs::create_dir_all(&artifact_root).expect("create package artifact root");
        let alpha_artifact_path = artifact_root.join("alpha.wasm");
        let zeta_artifact_path = artifact_root.join("zeta.wasm");
        fs::write(&alpha_artifact_path, b"\0asm\x01\0\0\0alpha")
            .expect("write alpha package artifact");
        fs::write(&zeta_artifact_path, b"\0asm\x01\0\0\0zeta")
            .expect("write zeta package artifact");

        PackageLockfile {
            version: PACKAGE_LOCKFILE_VERSION,
            package: "artifact-order".to_string(),
            language_edition: PACKAGE_LOCKFILE_LANGUAGE_EDITION.to_string(),
            compiler_version: PACKAGE_LOCKFILE_COMPILER_VERSION.to_string(),
            roots: vec![fs::canonicalize(&source_root).expect("canonicalize source root")],
            stdlib_root: None,
            entry: fs::canonicalize(&entry_path).expect("canonicalize package entry"),
            artifacts: vec![
                PackageLockfileArtifact::from_existing_file(
                    "wasm32-unknown-unknown",
                    "z-final",
                    &zeta_artifact_path,
                )
                .expect("record zeta artifact identity"),
                PackageLockfileArtifact::from_existing_file(
                    "wasm32-unknown-unknown",
                    "a-final",
                    &alpha_artifact_path,
                )
                .expect("record alpha artifact identity"),
            ],
            replay_integrity: None,
        }
    }
}
