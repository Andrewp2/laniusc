use std::path::{Path, PathBuf};

use laniusc::{
    codegen::unit::{
        CodegenUnitLimits,
        SourcePackArtifactTarget,
        SourcePackBuildShardLimits,
        SourcePackJobBatchLimits,
    },
    compiler::{
        FilesystemArtifactStore,
        FilesystemLibraryMetadataPrepareStepResult,
        FilesystemWorkQueueWorkerRunExecutionResult,
        compile_legacy_pack_paths_to_wasm,
        compile_legacy_pack_paths_to_x86_64,
        prepare_artifact_build_chunk,
        resume_metadata_chunk_for_target,
        run_prepared_descriptor_worker_for_target,
    },
};

use super::{
    SourcePackCliOptions,
    build_max_items,
    max_items,
    max_ready_items,
    metadata_max_libraries,
    metadata_max_source_files,
    source_pack_artifact_target,
    source_pack_manifest,
};

pub(crate) fn prepare_metadata_only(
    emit: &str,
    stdlib_paths: &[PathBuf],
    inputs: &[PathBuf],
    source_pack: &SourcePackCliOptions,
) -> Result<(), String> {
    let artifact_root = require_source_pack_artifact_root(
        source_pack,
        "--source-pack-metadata-only requires --source-pack-artifact-root",
    )?;
    let target = source_pack_artifact_target(emit);
    if source_pack_artifact_root_has_prepared_metadata(artifact_root, emit) {
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
        let max_new_libraries = metadata_max_libraries(source_pack);
        let max_new_source_files = metadata_max_source_files(source_pack);
        let metadata = prepare_metadata_chunk(
            stdlib_paths,
            inputs,
            source_pack,
            artifact_root,
            target,
            max_new_libraries,
            max_new_source_files,
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

fn prepare_metadata_chunk(
    stdlib_paths: &[PathBuf],
    inputs: &[PathBuf],
    source_pack: &SourcePackCliOptions,
    artifact_root: &PathBuf,
    target: SourcePackArtifactTarget,
    max_new_libraries: usize,
    max_new_source_files: usize,
) -> Result<FilesystemLibraryMetadataPrepareStepResult, String> {
    if let Some(library_manifest_path) = source_pack.library_manifest.as_deref() {
        let persisted_library_count = prepared_library_prefix_count(artifact_root, target);
        let progress = source_pack_manifest::load_progress_or_default(
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
        let chunk = source_pack_manifest::load_entries_chunk_from_offset(
            library_manifest_path,
            progress.next_byte_offset,
            max_new_libraries,
            max_new_source_files,
        )?;
        let manifest_complete_after_input = chunk.manifest_complete_after_input;
        let next_byte_offset = chunk.next_byte_offset;
        let new_entries = chunk.entries;
        let libraries = source_pack_manifest::path_dependency_streams(new_entries)?;
        let result = resume_metadata_chunk_for_target(
            libraries,
            artifact_root,
            target,
            max_new_libraries,
            manifest_complete_after_input,
        )
        .map_err(|err| err.to_string())?;
        let next_progress = source_pack_manifest::Progress {
            library_count: progress
                .library_count
                .checked_add(result.new_library_count)
                .ok_or_else(|| {
                    "source-pack library manifest read progress library count overflows".to_string()
                })?,
            next_byte_offset,
            ..progress
        };
        source_pack_manifest::store_progress(artifact_root, &next_progress)?;
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

pub(crate) fn prepare_build_from_metadata_chunk_only(
    emit: &str,
    source_pack: &SourcePackCliOptions,
) -> Result<(), String> {
    let artifact_root = require_source_pack_artifact_root(
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
        source_pack_artifact_target(emit),
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
    source_pack: &SourcePackCliOptions,
) -> Result<(), String> {
    let artifact_root = require_source_pack_artifact_root(
        source_pack,
        "--source-pack-prepare-only requires --source-pack-artifact-root",
    )?;
    let target = source_pack_artifact_target(emit);
    if !source_pack_artifact_root_has_prepared_metadata(artifact_root, emit) {
        if source_pack.manifest.is_some() || source_pack.library_manifest.is_some() {
            let max_new_libraries = metadata_max_libraries(source_pack);
            let max_new_source_files = metadata_max_source_files(source_pack);
            let metadata = prepare_metadata_chunk(
                stdlib_paths,
                inputs,
                source_pack,
                artifact_root,
                target,
                max_new_libraries,
                max_new_source_files,
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

pub(crate) fn compile_from_metadata_with_descriptor_queue(
    emit: &str,
    source_pack: &SourcePackCliOptions,
) -> Result<PathBuf, String> {
    let artifact_root = require_source_pack_artifact_root(
        source_pack,
        "--source-pack-build-from-metadata requires --source-pack-artifact-root",
    )?;
    let worker_id = format!("laniusc-{}", std::process::id());
    compile_prepared_root_with_descriptor_queue(emit, artifact_root, source_pack, worker_id)
}

fn compile_prepared_root_with_descriptor_queue(
    emit: &str,
    artifact_root: &PathBuf,
    source_pack: &SourcePackCliOptions,
    worker_id: String,
) -> Result<PathBuf, String> {
    require_source_pack_prepared_build_for_descriptor_compile(artifact_root, emit)?;
    compile_prepared_source_pack_descriptor_queue(emit, artifact_root, source_pack, worker_id)
}

fn require_source_pack_artifact_root<'a>(
    source_pack: &'a SourcePackCliOptions,
    message: &str,
) -> Result<&'a PathBuf, String> {
    source_pack
        .artifact_root
        .as_ref()
        .ok_or_else(|| message.to_string())
}

pub(crate) fn compile_source_pack_legacy_in_memory(
    emit: &str,
    stdlib_paths: &[PathBuf],
    inputs: &[PathBuf],
) -> Result<Vec<u8>, String> {
    if emit == "wasm" {
        pollster::block_on(compile_legacy_pack_paths_to_wasm(stdlib_paths, inputs))
            .map_err(|err| err.to_string())
    } else {
        pollster::block_on(compile_legacy_pack_paths_to_x86_64(stdlib_paths, inputs))
            .map_err(|err| err.to_string())
    }
}

pub(crate) fn compile_source_pack_with_descriptor_queue(
    emit: &str,
    _stdlib_paths: &[PathBuf],
    _inputs: &[PathBuf],
    source_pack: &SourcePackCliOptions,
) -> Result<PathBuf, String> {
    let artifact_root = require_source_pack_artifact_root(
        source_pack,
        "source-pack descriptor compile requires --source-pack-artifact-root; run --source-pack-prepare-only with --source-pack-artifact-root until preparation completes, then rerun compile",
    )?;
    let worker_id = format!("laniusc-{}", std::process::id());
    if source_pack_artifact_root_has_prepared_build(artifact_root, emit) {
        return compile_prepared_source_pack_descriptor_queue(
            emit,
            artifact_root,
            source_pack,
            worker_id,
        );
    }
    if source_pack_artifact_root_has_prepared_metadata(artifact_root, emit) {
        return compile_prepared_root_with_descriptor_queue(
            emit,
            artifact_root,
            source_pack,
            worker_id,
        );
    }
    require_source_pack_prepared_metadata_for_direct_compile(artifact_root, emit, source_pack)?;
    unreachable!("prepared metadata requirement should return or fail")
}

pub(crate) fn compile_source_pack_library_manifest_with_descriptor_queue(
    emit: &str,
    _library_manifest_path: &Path,
    source_pack: &SourcePackCliOptions,
) -> Result<PathBuf, String> {
    let artifact_root = require_source_pack_artifact_root(
        source_pack,
        "--source-pack-library-manifest descriptor compile requires --source-pack-artifact-root",
    )?;
    let worker_id = format!("laniusc-{}", std::process::id());
    if source_pack_artifact_root_has_prepared_build(artifact_root, emit) {
        return compile_prepared_source_pack_descriptor_queue(
            emit,
            artifact_root,
            source_pack,
            worker_id,
        );
    }
    if source_pack_artifact_root_has_prepared_metadata(artifact_root, emit) {
        return compile_prepared_root_with_descriptor_queue(
            emit,
            artifact_root,
            source_pack,
            worker_id,
        );
    }
    require_source_pack_prepared_metadata_for_manifest_compile(artifact_root, emit)?;
    compile_prepared_root_with_descriptor_queue(emit, artifact_root, source_pack, worker_id)
}

pub(crate) fn compile_source_pack_manifest_with_descriptor_queue(
    emit: &str,
    _manifest_path: &Path,
    source_pack: &SourcePackCliOptions,
) -> Result<PathBuf, String> {
    let artifact_root = require_source_pack_artifact_root(
        source_pack,
        "--source-pack-manifest descriptor compile requires --source-pack-artifact-root",
    )?;
    let worker_id = format!("laniusc-{}", std::process::id());
    if source_pack_artifact_root_has_prepared_build(artifact_root, emit) {
        return compile_prepared_source_pack_descriptor_queue(
            emit,
            artifact_root,
            source_pack,
            worker_id,
        );
    }
    if source_pack_artifact_root_has_prepared_metadata(artifact_root, emit) {
        return compile_prepared_root_with_descriptor_queue(
            emit,
            artifact_root,
            source_pack,
            worker_id,
        );
    }
    require_source_pack_prepared_metadata_for_manifest_compile(artifact_root, emit)?;
    compile_prepared_root_with_descriptor_queue(emit, artifact_root, source_pack, worker_id)
}

fn compile_prepared_source_pack_descriptor_queue(
    emit: &str,
    artifact_root: &PathBuf,
    source_pack: &SourcePackCliOptions,
    worker_id: String,
) -> Result<PathBuf, String> {
    let max_items = max_items(source_pack);
    let max_ready_items = max_ready_items(source_pack);
    let run = pollster::block_on(run_prepared_descriptor_worker_for_target(
        artifact_root,
        source_pack_artifact_target(emit),
        worker_id,
        max_items,
        None,
        max_ready_items,
    ))
    .map_err(|err| err.to_string())?;
    complete_source_pack_output_path(artifact_root, run)
}

pub(crate) fn source_pack_artifact_root_has_prepared_build(
    artifact_root: &Path,
    emit: &str,
) -> bool {
    let store = FilesystemArtifactStore::new(artifact_root);
    store
        .build_state_path_for_target(source_pack_artifact_target(emit))
        .is_file()
}

pub(crate) fn source_pack_artifact_root_has_prepared_metadata(
    artifact_root: &Path,
    emit: &str,
) -> bool {
    let store = FilesystemArtifactStore::new(artifact_root);
    store
        .library_partition_index_path_for_target(source_pack_artifact_target(emit))
        .is_file()
}

fn prepared_library_prefix_count(artifact_root: &Path, target: SourcePackArtifactTarget) -> usize {
    let store = FilesystemArtifactStore::new(artifact_root);
    if let Ok(index) = store.load_library_partition_index_for_target(target) {
        return index.partition_count;
    }
    if let Ok(progress) = store.load_library_metadata_prepare_progress_for_target(target) {
        return progress.library_partition_count;
    }
    let mut partition_count = 0usize;
    while store
        .library_partition_path_for_target(target, partition_count)
        .is_file()
    {
        partition_count = partition_count.saturating_add(1);
    }
    partition_count
}

fn require_source_pack_prepared_metadata_for_direct_compile(
    artifact_root: &Path,
    emit: &str,
    _source_pack: &SourcePackCliOptions,
) -> Result<(), String> {
    if source_pack_artifact_root_has_prepared_build(artifact_root, emit)
        || source_pack_artifact_root_has_prepared_metadata(artifact_root, emit)
    {
        return Ok(());
    }
    Err(format!(
        "source-pack descriptor compile at {} has no persisted metadata for target {emit}; run --source-pack-prepare-only with --source-pack-artifact-root {} until preparation completes, then rerun compile",
        artifact_root.display(),
        artifact_root.display()
    ))
}

fn require_source_pack_prepared_metadata_for_manifest_compile(
    artifact_root: &Path,
    emit: &str,
) -> Result<(), String> {
    if source_pack_artifact_root_has_prepared_build(artifact_root, emit)
        || source_pack_artifact_root_has_prepared_metadata(artifact_root, emit)
    {
        return Ok(());
    }
    Err(format!(
        "source-pack manifest descriptor compile at {} has no persisted metadata for target {emit}; run --source-pack-prepare-only with --source-pack-library-manifest and --source-pack-artifact-root {} until preparation completes, then rerun compile",
        artifact_root.display(),
        artifact_root.display()
    ))
}

fn require_source_pack_prepared_build_for_descriptor_compile(
    artifact_root: &Path,
    emit: &str,
) -> Result<(), String> {
    if source_pack_artifact_root_has_prepared_build(artifact_root, emit) {
        return Ok(());
    }
    Err(format!(
        "source-pack descriptor compile at {} has persisted metadata but no prepared build queue for target {emit}; run --source-pack-prepare-only or --source-pack-build-from-metadata --source-pack-build-prepare-only with --source-pack-artifact-root {} until preparation completes, then rerun compile",
        artifact_root.display(),
        artifact_root.display()
    ))
}

fn complete_source_pack_output_path(
    artifact_root: &PathBuf,
    run: FilesystemWorkQueueWorkerRunExecutionResult,
) -> Result<PathBuf, String> {
    if !run.progress.complete {
        return Err(format!(
            "source-pack descriptor build stopped before completion at {}; executed_items={} completed_items={} work_items={} ready_items={}; rerun with --source-pack-artifact-root {} to continue the bounded work queue, or pass --source-pack-legacy-in-memory for the old whole-pack path",
            artifact_root.display(),
            run.executed_item_count,
            run.progress.completed_item_count,
            run.progress.work_item_count,
            run.progress.ready_item_count,
            artifact_root.display(),
        ));
    }
    let linked_output_path = run.linked_output_path.ok_or_else(|| {
        "completed source-pack descriptor build did not report a linked output path".to_string()
    })?;
    if !linked_output_path.is_file() {
        return Err(format!(
            "completed source-pack linked output is missing at {}",
            linked_output_path.display()
        ));
    }
    Ok(linked_output_path)
}

#[cfg(test)]
mod tests;
