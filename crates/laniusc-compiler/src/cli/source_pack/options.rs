use std::path::PathBuf;

use crate::codegen::unit::{DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES, SourcePackArtifactTarget};

pub(crate) const DEFAULT_SOURCE_PACK_MAX_ITEMS: usize = 64;
pub(crate) const DEFAULT_SOURCE_PACK_MAX_READY_ITEMS: usize = 64;
pub(crate) const DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES: usize = 64;
pub(crate) const DEFAULT_SOURCE_PACK_METADATA_MAX_SOURCE_FILES: usize =
    DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES * DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES;
pub(crate) const DEFAULT_SOURCE_PACK_BUILD_MAX_ITEMS: usize = 64;

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

    pub(crate) fn conflicts_with_source_root_compile(&self) -> bool {
        self.metadata_only
            || self.prepare_only
            || self.build_prepare_only
            || self.descriptors
            || self.artifact_root.is_some()
    }

    pub(crate) fn uses_source_pack_compile_path(
        &self,
        has_stdlib_paths: bool,
        input_count: usize,
    ) -> bool {
        self.uses_source_pack_mode_flag() || has_stdlib_paths || input_count > 1
    }

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

    pub(crate) fn requests_contract_descriptor_output(&self, uses_source_pack: bool) -> bool {
        uses_source_pack && !self.metadata_only && !self.prepare_only && !self.build_prepare_only
    }
}

pub(crate) fn metadata_max_libraries(source_pack: &Options) -> usize {
    source_pack
        .metadata_max_libraries
        .unwrap_or(DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES)
        .min(DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES)
        .max(1)
}

pub(crate) fn metadata_max_source_files(source_pack: &Options) -> usize {
    source_pack
        .metadata_max_source_files
        .unwrap_or(DEFAULT_SOURCE_PACK_METADATA_MAX_SOURCE_FILES)
        .min(DEFAULT_SOURCE_PACK_METADATA_MAX_SOURCE_FILES)
        .max(1)
}

pub(crate) fn build_max_items(source_pack: &Options) -> usize {
    source_pack
        .build_max_items
        .min(DEFAULT_SOURCE_PACK_BUILD_MAX_ITEMS)
        .max(1)
}

pub(crate) fn max_items(source_pack: &Options) -> usize {
    source_pack
        .max_items
        .min(DEFAULT_SOURCE_PACK_MAX_ITEMS)
        .max(1)
}

pub(crate) fn max_ready_items(source_pack: &Options) -> usize {
    source_pack
        .max_ready_items
        .min(DEFAULT_SOURCE_PACK_MAX_READY_ITEMS)
        .max(1)
}

pub(crate) fn artifact_target_for_emit(emit: &str) -> SourcePackArtifactTarget {
    if emit == "wasm" {
        SourcePackArtifactTarget::Wasm
    } else {
        SourcePackArtifactTarget::X86_64
    }
}
