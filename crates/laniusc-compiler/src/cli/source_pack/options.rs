use std::path::PathBuf;

use crate::codegen::unit::{DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES, SourcePackArtifactTarget};

/// Maximum work items submitted by one descriptor worker run.
pub(crate) const DEFAULT_SOURCE_PACK_MAX_ITEMS: usize = 64;
/// Maximum ready work items inspected by one descriptor worker run.
pub(crate) const DEFAULT_SOURCE_PACK_MAX_READY_ITEMS: usize = 64;
/// Maximum libraries consumed by one metadata-preparation chunk.
pub(crate) const DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES: usize = 64;
/// Maximum source files consumed by one metadata-preparation chunk.
pub(crate) const DEFAULT_SOURCE_PACK_METADATA_MAX_SOURCE_FILES: usize =
    DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES * DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES;
/// Maximum build-preparation items consumed by one chunk.
pub(crate) const DEFAULT_SOURCE_PACK_BUILD_MAX_ITEMS: usize = 64;

/// Source-pack command-line options after parsing.
#[derive(Clone, Debug)]
pub(crate) struct Options {
    pub(crate) descriptors: bool,
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

impl Default for Options {
    fn default() -> Self {
        Self {
            descriptors: false,
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

impl Options {
    /// Returns true when any flag selects the source-pack CLI path.
    pub(crate) fn uses_source_pack_mode_flag(&self) -> bool {
        self.manifest.is_some()
            || self.library_manifest.is_some()
            || self.descriptors
            || self.artifact_root.is_some()
            || self.metadata_only
            || self.prepare_only
            || self.build_from_metadata
            || self.build_prepare_only
            || self.emit_contract
    }

    /// Returns true when these source-pack flags cannot be combined with
    /// source-root compilation.
    pub(crate) fn conflicts_with_source_root_compile(&self) -> bool {
        self.metadata_only
            || self.prepare_only
            || self.build_prepare_only
            || self.descriptors
            || self.artifact_root.is_some()
    }

    /// Returns true when compile should use source-pack execution rather than
    /// the single-entry in-memory path.
    pub(crate) fn uses_source_pack_compile_path(
        &self,
        has_stdlib_paths: bool,
        input_count: usize,
    ) -> bool {
        self.uses_source_pack_mode_flag() || has_stdlib_paths || input_count > 1
    }

    /// Returns true when package metadata may feed bounded metadata preparation.
    pub(crate) fn uses_package_metadata_prepare_path(&self) -> bool {
        self.metadata_only
            && !self.descriptors
            && !self.emit_contract
            && self.manifest.is_none()
            && self.library_manifest.is_none()
            && !self.prepare_only
            && !self.build_from_metadata
            && !self.build_prepare_only
    }

    /// Returns true when a source-pack output path should be treated as a
    /// linked-output contract descriptor.
    pub(crate) fn requests_contract_descriptor_output(&self, uses_source_pack: bool) -> bool {
        uses_source_pack && !self.metadata_only && !self.prepare_only && !self.build_prepare_only
    }
}

/// Effective metadata library chunk limit after applying the CLI cap.
pub(crate) fn metadata_max_libraries(source_pack: &Options) -> usize {
    source_pack
        .metadata_max_libraries
        .unwrap_or(DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES)
        .min(DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES)
        .max(1)
}

/// Effective metadata source-file chunk limit after applying the CLI cap.
pub(crate) fn metadata_max_source_files(source_pack: &Options) -> usize {
    source_pack
        .metadata_max_source_files
        .unwrap_or(DEFAULT_SOURCE_PACK_METADATA_MAX_SOURCE_FILES)
        .min(DEFAULT_SOURCE_PACK_METADATA_MAX_SOURCE_FILES)
        .max(1)
}

/// Effective build-preparation chunk limit after applying the CLI cap.
pub(crate) fn build_max_items(source_pack: &Options) -> usize {
    source_pack
        .build_max_items
        .min(DEFAULT_SOURCE_PACK_BUILD_MAX_ITEMS)
        .max(1)
}

/// Effective descriptor worker item limit after applying the CLI cap.
pub(crate) fn max_items(source_pack: &Options) -> usize {
    source_pack
        .max_items
        .min(DEFAULT_SOURCE_PACK_MAX_ITEMS)
        .max(1)
}

/// Effective descriptor worker ready-item limit after applying the CLI cap.
pub(crate) fn max_ready_items(source_pack: &Options) -> usize {
    source_pack
        .max_ready_items
        .min(DEFAULT_SOURCE_PACK_MAX_READY_ITEMS)
        .max(1)
}

/// Converts `--emit` into the source-pack artifact target enum.
pub(crate) fn artifact_target_for_emit(emit: &str) -> SourcePackArtifactTarget {
    if emit == "wasm" {
        SourcePackArtifactTarget::Wasm
    } else {
        SourcePackArtifactTarget::X86_64
    }
}
