use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
};

use super::{
    Options,
    artifact_target_for_emit,
    artifacts::{has_prepared_metadata, prepared_library_prefix_count, require_artifact_root},
    build_max_items,
    manifest,
    metadata_max_libraries,
    metadata_max_source_files,
};
use crate::{
    codegen::unit::{
        CodegenUnitLimits,
        SourcePackArtifactTarget,
        SourcePackBuildShardLimits,
        SourcePackJobBatchLimits,
    },
    compiler::{
        ExplicitSourceLibraryPathDependencyStream,
        ExplicitSourcePackPathManifest,
        FilesystemArtifactStore,
        FilesystemLibraryMetadataPrepareStepResult,
        SourcePackLibraryPartition,
        prepare_artifact_build_chunk,
        resume_metadata_chunk_for_target,
    },
};

pub(crate) fn prepare_metadata_only(
    emit: &str,
    stdlib_paths: &[PathBuf],
    inputs: &[PathBuf],
    source_pack: &Options,
) -> Result<(), String> {
    let artifact_root = require_artifact_root(
        source_pack,
        "--source-pack-metadata-only requires --source-pack-artifact-root",
    )?;
    let target = artifact_target_for_emit(emit);
    if has_prepared_metadata(artifact_root, emit) {
        eprintln!(
            "source-pack metadata already prepared at {}; target={:?}",
            artifact_root.display(),
            target
        );
        return Ok(());
    }
    if source_pack.library_manifest.is_some()
        || source_pack.metadata_max_libraries.is_some()
        || source_pack.metadata_max_source_files.is_some()
    {
        let metadata = prepare_metadata_chunk(
            stdlib_paths,
            inputs,
            source_pack,
            artifact_root,
            target,
            metadata_max_libraries(source_pack),
            metadata_max_source_files(source_pack),
        )?;
        eprintln!(
            "source-pack metadata chunk prepared at {}; target={:?} complete={} libraries={} new_libraries={} source_files={} source_bytes={} source_lines={}",
            artifact_root.display(),
            metadata.target,
            metadata.complete,
            metadata.library_count,
            metadata.new_library_count,
            metadata.source_file_count,
            metadata.source_byte_count,
            metadata.source_line_count
        );
        return Ok(());
    }
    if let Some(manifest_path) = source_pack.manifest.as_deref() {
        return Err(format!(
            "--source-pack-metadata-only with --source-pack-manifest would require reading the whole JSON manifest {}; use --source-pack-library-manifest for bounded JSONL metadata chunks",
            manifest_path.display()
        ));
    }
    if !stdlib_paths.is_empty() || !inputs.is_empty() {
        return Err(
            "--source-pack-metadata-only with raw --stdlib or positional source paths would prepare a whole path list; use --source-pack-library-manifest for bounded JSONL metadata chunks"
                .into(),
        );
    }
    Err(
        "--source-pack-metadata-only requires --source-pack-library-manifest source-pack inputs"
            .into(),
    )
}

pub(crate) fn prepare_path_manifest_metadata_only(
    emit: &str,
    path_manifest: ExplicitSourcePackPathManifest,
    source_pack: &Options,
    package_selector: &str,
    package_path: &Path,
) -> Result<(), String> {
    let artifact_root = require_artifact_root(
        source_pack,
        "--source-pack-metadata-only requires --source-pack-artifact-root",
    )?;
    let target = artifact_target_for_emit(emit);
    let libraries = path_manifest_libraries(path_manifest)?;
    validate_persisted_path_manifest_prefix(artifact_root, target, &libraries)?;
    if has_prepared_metadata(artifact_root, emit) {
        eprintln!(
            "source-pack package metadata already prepared at {}; target={:?}; selector={} {}",
            artifact_root.display(),
            target,
            package_selector,
            package_path.display()
        );
        return Ok(());
    }

    let max_new_libraries = metadata_max_libraries(source_pack);
    let max_new_source_files = metadata_max_source_files(source_pack);
    let persisted_library_count = prepared_library_prefix_count(artifact_root, target);
    let (chunk, manifest_complete_after_input) = path_manifest_library_chunk(
        libraries,
        persisted_library_count,
        max_new_libraries,
        max_new_source_files,
        package_selector,
        package_path,
    )?;
    let result = resume_metadata_chunk_for_target(
        chunk.into_iter().map(PathManifestLibrary::into_stream),
        artifact_root,
        target,
        max_new_libraries,
        manifest_complete_after_input,
    )
    .map_err(|err| err.to_string())?;
    eprintln!(
        "source-pack package metadata chunk prepared at {}; target={:?} complete={} libraries={} new_libraries={} source_files={} source_bytes={} source_lines={} selector={} {}",
        artifact_root.display(),
        result.target,
        result.complete,
        result.library_count,
        result.new_library_count,
        result.source_file_count,
        result.source_byte_count,
        result.source_line_count,
        package_selector,
        package_path.display()
    );
    Ok(())
}

pub(crate) fn prepare_build_from_metadata_chunk_only(
    emit: &str,
    source_pack: &Options,
) -> Result<(), String> {
    let artifact_root = require_artifact_root(
        source_pack,
        "--source-pack-build-from-metadata requires --source-pack-artifact-root",
    )?;
    let limits = CodegenUnitLimits::default();
    let batch_limits = SourcePackJobBatchLimits::from_codegen_unit_limits(limits);
    let shard_limits = SourcePackBuildShardLimits::default();
    let step = prepare_artifact_build_chunk(
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        artifact_target_for_emit(emit),
        build_max_items(source_pack),
    )
    .map_err(|err| err.to_string())?;
    eprintln!(
        "source-pack build chunk prepared at {}; target={:?} complete={} stage={:?} next_stage={:?} new_items={}",
        artifact_root.display(),
        step.target,
        step.complete,
        step.stage,
        step.next_stage,
        step.new_item_count
    );
    if let Some(prepared) = step.prepared {
        eprintln!(
            "source-pack build prepared at {}; target={:?} libraries={} source_files={} jobs={} batches={} artifact_shards={} work_items={}",
            prepared.artifact_root.display(),
            prepared.target,
            prepared.library_count,
            prepared.source_file_count,
            prepared.scheduled_job_count,
            prepared.batch_count,
            prepared.artifact_shard_count,
            prepared.work_queue_item_count
        );
    }
    Ok(())
}

pub(crate) fn prepare_inputs_chunk_only(
    emit: &str,
    stdlib_paths: &[PathBuf],
    inputs: &[PathBuf],
    source_pack: &Options,
) -> Result<(), String> {
    let artifact_root = require_artifact_root(
        source_pack,
        "--source-pack-prepare-only requires --source-pack-artifact-root",
    )?;
    let target = artifact_target_for_emit(emit);
    if !has_prepared_metadata(artifact_root, emit) {
        if source_pack.manifest.is_some() || source_pack.library_manifest.is_some() {
            let metadata = prepare_metadata_chunk(
                stdlib_paths,
                inputs,
                source_pack,
                artifact_root,
                target,
                metadata_max_libraries(source_pack),
                metadata_max_source_files(source_pack),
            )?;
            eprintln!(
                "source-pack prepare chunk stored metadata at {}; target={:?} complete={} libraries={} new_libraries={} source_files={} source_bytes={} source_lines={}",
                artifact_root.display(),
                metadata.target,
                metadata.complete,
                metadata.library_count,
                metadata.new_library_count,
                metadata.source_file_count,
                metadata.source_byte_count,
                metadata.source_line_count
            );
            return Ok(());
        }
        return Err(
            "--source-pack-prepare-only with raw --stdlib or positional source paths would prepare a whole path list; use --source-pack-library-manifest for bounded JSONL metadata chunks"
                .into(),
        );
    }
    prepare_build_from_metadata_chunk_only(emit, source_pack)
}

fn prepare_metadata_chunk(
    stdlib_paths: &[PathBuf],
    inputs: &[PathBuf],
    source_pack: &Options,
    artifact_root: &Path,
    target: SourcePackArtifactTarget,
    max_new_libraries: usize,
    max_new_source_files: usize,
) -> Result<FilesystemLibraryMetadataPrepareStepResult, String> {
    if let Some(library_manifest_path) = source_pack.library_manifest.as_deref() {
        let persisted_library_count = prepared_library_prefix_count(artifact_root, target);
        let progress = manifest::load_progress_or_default(
            artifact_root,
            target,
            library_manifest_path,
            persisted_library_count,
        )?;
        if progress.library_count != persisted_library_count {
            return Err(format!(
                "source-pack library manifest {} read progress records {} libraries, but artifact root {} contains {} persisted metadata partitions",
                library_manifest_path.display(),
                progress.library_count,
                artifact_root.display(),
                persisted_library_count
            ));
        }
        let chunk = manifest::load_entries_chunk_from_offset(
            library_manifest_path,
            progress.next_byte_offset,
            max_new_libraries,
            max_new_source_files,
        )?;
        let manifest_complete_after_input = chunk.manifest_complete_after_input;
        let next_byte_offset = chunk.next_byte_offset;
        let libraries = manifest::path_dependency_streams(chunk.entries)?;
        let result = resume_metadata_chunk_for_target(
            libraries,
            artifact_root,
            target,
            max_new_libraries,
            manifest_complete_after_input,
        )
        .map_err(|err| err.to_string())?;
        let next_progress = manifest::Progress {
            library_count: progress
                .library_count
                .checked_add(result.new_library_count)
                .ok_or_else(|| {
                    "source-pack library manifest read progress library count overflows".to_string()
                })?,
            next_byte_offset,
            ..progress
        };
        manifest::store_progress(artifact_root, &next_progress)?;
        Ok(result)
    } else if let Some(manifest_path) = source_pack.manifest.as_deref() {
        Err(format!(
            "--source-pack-metadata chunk limits with --source-pack-manifest would require reading the whole JSON manifest {}; use --source-pack-library-manifest for bounded JSONL metadata chunks",
            manifest_path.display()
        ))
    } else if !stdlib_paths.is_empty() || !inputs.is_empty() {
        Err(
            "--source-pack-metadata chunk limits require --source-pack-manifest or --source-pack-library-manifest for multi-library metadata chunks"
                .into(),
        )
    } else {
        Err("--source-pack-metadata chunk limits require source-pack inputs".into())
    }
}

#[derive(Clone, Debug)]
struct PathManifestLibrary {
    library_id: u32,
    paths: Vec<PathBuf>,
    dependency_library_ids: Vec<u32>,
}

impl PathManifestLibrary {
    fn into_stream(self) -> ExplicitSourceLibraryPathDependencyStream<Vec<PathBuf>, Vec<u32>> {
        let mut dependency_library_ids = self.dependency_library_ids;
        dependency_library_ids.sort_unstable();
        ExplicitSourceLibraryPathDependencyStream {
            library_id: self.library_id,
            source_file_count: self.paths.len(),
            paths: self.paths,
            dependency_library_count: dependency_library_ids.len(),
            dependency_library_ids,
        }
    }
}

fn path_manifest_libraries(
    path_manifest: ExplicitSourcePackPathManifest,
) -> Result<Vec<PathManifestLibrary>, String> {
    let mut library_order = Vec::new();
    let mut paths_by_library = BTreeMap::<u32, Vec<PathBuf>>::new();
    for file in path_manifest.files {
        paths_by_library
            .entry(file.library_id)
            .or_insert_with(|| {
                library_order.push(file.library_id);
                Vec::new()
            })
            .push(file.path);
    }
    let mut dependencies_by_library = BTreeMap::<u32, Vec<u32>>::new();
    for dependency in path_manifest.library_dependencies {
        dependencies_by_library
            .entry(dependency.library_id)
            .or_default()
            .push(dependency.depends_on_library_id);
    }

    let mut libraries = Vec::with_capacity(library_order.len());
    for library_id in library_order {
        let paths = paths_by_library
            .remove(&library_id)
            .expect("library order was derived from path map keys");
        if paths.is_empty() {
            return Err(format!(
                "package source-pack path manifest library {library_id} has no source files"
            ));
        }
        let mut dependency_library_ids = dependencies_by_library
            .remove(&library_id)
            .unwrap_or_default();
        dependency_library_ids.sort_unstable();
        libraries.push(PathManifestLibrary {
            library_id,
            paths,
            dependency_library_ids,
        });
    }
    if libraries.is_empty() {
        return Err("package source-pack path manifest has no source files".into());
    }
    Ok(libraries)
}

fn path_manifest_library_chunk(
    libraries: Vec<PathManifestLibrary>,
    persisted_library_count: usize,
    max_new_libraries: usize,
    max_new_source_files: usize,
    package_selector: &str,
    package_path: &Path,
) -> Result<(Vec<PathManifestLibrary>, bool), String> {
    if persisted_library_count > libraries.len() {
        return Err(format!(
            "source-pack package metadata for {package_selector} {} has {} libraries, but artifact metadata already contains {persisted_library_count} persisted library partitions",
            package_path.display(),
            libraries.len()
        ));
    }

    let total_library_count = libraries.len();
    let mut selected = Vec::new();
    let mut selected_source_file_count = 0usize;
    for library in libraries.into_iter().skip(persisted_library_count) {
        if selected.len() >= max_new_libraries {
            break;
        }
        let next_source_file_count = selected_source_file_count
            .checked_add(library.paths.len())
            .ok_or_else(|| {
                format!(
                    "source-pack package metadata chunk source-file count overflows for {package_selector} {}",
                    package_path.display()
                )
            })?;
        if next_source_file_count > max_new_source_files {
            if selected.is_empty() {
                return Err(format!(
                    "source-pack package metadata library {} has {} source files, exceeding the per-chunk source-file limit {}; reduce the package source graph or use smaller package libraries before metadata preparation",
                    library.library_id,
                    library.paths.len(),
                    max_new_source_files
                ));
            }
            break;
        }
        selected_source_file_count = next_source_file_count;
        selected.push(library);
    }

    let next_library_count = persisted_library_count
        .checked_add(selected.len())
        .ok_or_else(|| "source-pack package metadata library count overflows".to_string())?;
    let manifest_complete_after_input = next_library_count == total_library_count;
    if selected.is_empty() && !manifest_complete_after_input {
        return Err(format!(
            "source-pack package metadata chunk for {package_selector} {} selected no new libraries; increase --source-pack-metadata-max-libraries or --source-pack-metadata-max-source-files",
            package_path.display()
        ));
    }
    Ok((selected, manifest_complete_after_input))
}

fn validate_persisted_path_manifest_prefix(
    artifact_root: &Path,
    target: SourcePackArtifactTarget,
    libraries: &[PathManifestLibrary],
) -> Result<(), String> {
    let store = FilesystemArtifactStore::new(artifact_root);
    let index_path = store.library_partition_index_path_for_target(target);
    let complete_library_count = if index_path.is_file() {
        Some(
            store
                .load_library_partition_index_for_target(target)
                .map_err(|err| err.to_string())?
                .partition_count,
        )
    } else {
        None
    };
    let persisted_library_count = prepared_library_prefix_count(artifact_root, target);
    if persisted_library_count > libraries.len() {
        return Err(format!(
            "source-pack artifact root {} contains {persisted_library_count} persisted metadata partitions, but package source-pack metadata has only {} libraries",
            artifact_root.display(),
            libraries.len()
        ));
    }
    if let Some(complete_library_count) = complete_library_count {
        if complete_library_count != libraries.len() {
            return Err(format!(
                "source-pack artifact root {} has a complete metadata index with {complete_library_count} libraries, but package source-pack metadata has {} libraries",
                artifact_root.display(),
                libraries.len()
            ));
        }
    }
    for (partition_index, expected) in libraries.iter().take(persisted_library_count).enumerate() {
        let partition = store
            .load_library_partition_for_target(target, partition_index)
            .map_err(|err| err.to_string())?;
        validate_persisted_path_manifest_library(
            &store,
            target,
            artifact_root,
            partition_index,
            &partition,
            expected,
        )?;
    }
    Ok(())
}

fn validate_persisted_path_manifest_library(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    artifact_root: &Path,
    partition_index: usize,
    partition: &SourcePackLibraryPartition,
    expected: &PathManifestLibrary,
) -> Result<(), String> {
    if partition.library_id != expected.library_id {
        return Err(format!(
            "source-pack artifact root {} partition {partition_index} is library {}, but package source-pack metadata expects library {}",
            artifact_root.display(),
            partition.library_id,
            expected.library_id
        ));
    }
    if partition.source_file_count != expected.paths.len() {
        return Err(format!(
            "source-pack artifact root {} partition {partition_index} for library {} stores {} source files, but package source-pack metadata declares {}",
            artifact_root.display(),
            partition.library_id,
            partition.source_file_count,
            expected.paths.len()
        ));
    }
    let stored_dependency_ids =
        stored_partition_dependency_ids(store, target, partition).map_err(|err| err.to_string())?;
    if stored_dependency_ids != expected.dependency_library_ids {
        return Err(format!(
            "source-pack artifact root {} partition {partition_index} for library {} stores dependency libraries {:?}, but package source-pack metadata declares {:?}",
            artifact_root.display(),
            partition.library_id,
            stored_dependency_ids,
            expected.dependency_library_ids
        ));
    }
    Ok(())
}

fn stored_partition_dependency_ids(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    partition: &SourcePackLibraryPartition,
) -> Result<Vec<u32>, crate::compiler::CompileError> {
    let mut dependency_ids = partition.dependency_library_ids.clone();
    for page_index in 0..partition.dependency_page_count {
        let page = store.load_library_dependency_page_for_target(
            target,
            partition.partition_index,
            page_index,
        )?;
        dependency_ids.extend(page.dependency_library_ids);
    }
    dependency_ids.sort_unstable();
    if dependency_ids.len() != partition.dependency_library_count {
        return Err(crate::compiler::CompileError::GpuFrontend(format!(
            "source-pack partition {} dependency count mismatch: partition declares {}, loaded {}",
            partition.partition_index,
            partition.dependency_library_count,
            dependency_ids.len()
        )));
    }
    Ok(dependency_ids)
}
