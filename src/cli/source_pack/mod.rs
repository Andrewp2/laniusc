mod artifacts;
mod descriptor;
mod manifest;
mod options;
mod prepare;

pub(crate) use descriptor::{
    compile_direct,
    compile_from_metadata,
    compile_legacy,
    compile_library_manifest,
    compile_manifest,
};
#[cfg(test)]
pub(crate) use options::{
    DEFAULT_SOURCE_PACK_BUILD_MAX_ITEMS,
    DEFAULT_SOURCE_PACK_MAX_ITEMS,
    DEFAULT_SOURCE_PACK_MAX_READY_ITEMS,
    DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES,
    DEFAULT_SOURCE_PACK_METADATA_MAX_SOURCE_FILES,
};
pub(crate) use options::{
    Options,
    artifact_target_for_emit,
    build_max_items,
    max_items,
    max_ready_items,
    metadata_max_libraries,
    metadata_max_source_files,
};
pub(crate) use prepare::{
    prepare_build_from_metadata_chunk_only,
    prepare_inputs_chunk_only,
    prepare_metadata_only,
    prepare_path_manifest_metadata_only,
};

#[cfg(test)]
mod tests;
