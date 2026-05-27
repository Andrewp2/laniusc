mod config;
mod output;
pub(crate) mod source_pack;
pub(crate) mod source_pack_manifest;

#[cfg(test)]
pub(crate) use config::{
    DEFAULT_SOURCE_PACK_BUILD_MAX_ITEMS,
    DEFAULT_SOURCE_PACK_MAX_ITEMS,
    DEFAULT_SOURCE_PACK_MAX_READY_ITEMS,
    DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES,
    DEFAULT_SOURCE_PACK_METADATA_MAX_SOURCE_FILES,
};
pub(crate) use config::{
    SourcePackCliOptions,
    build_max_items,
    max_items,
    max_ready_items,
    metadata_max_libraries,
    metadata_max_source_files,
    parse_usize_arg,
    parse_usize_value,
    source_pack_artifact_target,
};
pub(crate) use output::{CliEmission, write_cli_emission};
