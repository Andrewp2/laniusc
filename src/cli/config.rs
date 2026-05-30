use std::{collections::BTreeSet, fs, path::PathBuf};

use laniusc::codegen::unit::{DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES, SourcePackArtifactTarget};

pub(crate) const DEFAULT_SOURCE_PACK_MAX_ITEMS: usize = 64;
pub(crate) const DEFAULT_SOURCE_PACK_MAX_READY_ITEMS: usize = 64;
pub(crate) const DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES: usize = 64;
pub(crate) const DEFAULT_SOURCE_PACK_METADATA_MAX_SOURCE_FILES: usize =
    DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES * DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES;
pub(crate) const DEFAULT_SOURCE_PACK_BUILD_MAX_ITEMS: usize = 64;

#[derive(Clone, Debug)]
pub(crate) struct SourcePackCliOptions {
    pub(crate) descriptors: bool,
    pub(crate) legacy_in_memory: bool,
    pub(crate) emit_contract: bool,
    pub(crate) manifest: Option<PathBuf>,
    pub(crate) library_manifest: Option<PathBuf>,
    pub(crate) metadata_only: bool,
    pub(crate) prepare_only: bool,
    pub(crate) build_from_metadata: bool,
    pub(crate) build_prepare_only: bool,
    pub(crate) metadata_max_libraries: Option<usize>,
    pub(crate) metadata_max_source_files: Option<usize>,
    pub(crate) build_max_items: usize,
    pub(crate) artifact_root: Option<PathBuf>,
    pub(crate) max_items: usize,
    pub(crate) max_ready_items: usize,
}

impl Default for SourcePackCliOptions {
    fn default() -> Self {
        Self {
            descriptors: false,
            legacy_in_memory: false,
            emit_contract: false,
            manifest: None,
            library_manifest: None,
            metadata_only: false,
            prepare_only: false,
            build_from_metadata: false,
            build_prepare_only: false,
            metadata_max_libraries: None,
            metadata_max_source_files: None,
            build_max_items: DEFAULT_SOURCE_PACK_BUILD_MAX_ITEMS,
            artifact_root: None,
            max_items: DEFAULT_SOURCE_PACK_MAX_ITEMS,
            max_ready_items: DEFAULT_SOURCE_PACK_MAX_READY_ITEMS,
        }
    }
}

pub(crate) fn parse_usize_value(flag: &str, value: &str) -> Result<usize, String> {
    value
        .parse::<usize>()
        .map_err(|err| format!("{flag} requires a non-negative integer, got {value:?}: {err}"))
}

pub(crate) fn canonical_directory_path(label: &str, path: PathBuf) -> Result<PathBuf, String> {
    let canonical = fs::canonicalize(&path)
        .map_err(|err| format!("canonicalize {label} {}: {err}", path.display()))?;
    if !canonical.is_dir() {
        return Err(format!(
            "{label} {} is not a directory",
            canonical.display()
        ));
    }
    Ok(canonical)
}

pub(crate) fn canonical_unique_directory_paths(
    label: &str,
    paths: Vec<PathBuf>,
) -> Result<Vec<PathBuf>, String> {
    let mut seen = BTreeSet::new();
    let mut unique = Vec::with_capacity(paths.len());
    for path in paths {
        let canonical = canonical_directory_path(label, path)?;
        if seen.insert(canonical.clone()) {
            unique.push(canonical);
        }
    }
    Ok(unique)
}

pub(crate) fn metadata_max_libraries(source_pack: &SourcePackCliOptions) -> usize {
    source_pack
        .metadata_max_libraries
        .unwrap_or(DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES)
        .min(DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES)
        .max(1)
}

pub(crate) fn metadata_max_source_files(source_pack: &SourcePackCliOptions) -> usize {
    source_pack
        .metadata_max_source_files
        .unwrap_or(DEFAULT_SOURCE_PACK_METADATA_MAX_SOURCE_FILES)
        .min(DEFAULT_SOURCE_PACK_METADATA_MAX_SOURCE_FILES)
        .max(1)
}

pub(crate) fn build_max_items(source_pack: &SourcePackCliOptions) -> usize {
    source_pack
        .build_max_items
        .min(DEFAULT_SOURCE_PACK_BUILD_MAX_ITEMS)
        .max(1)
}

pub(crate) fn max_items(source_pack: &SourcePackCliOptions) -> usize {
    source_pack
        .max_items
        .min(DEFAULT_SOURCE_PACK_MAX_ITEMS)
        .max(1)
}

pub(crate) fn max_ready_items(source_pack: &SourcePackCliOptions) -> usize {
    source_pack
        .max_ready_items
        .min(DEFAULT_SOURCE_PACK_MAX_READY_ITEMS)
        .max(1)
}

pub(crate) fn source_pack_artifact_target(emit: &str) -> SourcePackArtifactTarget {
    if emit == "wasm" {
        SourcePackArtifactTarget::Wasm
    } else {
        SourcePackArtifactTarget::X86_64
    }
}
