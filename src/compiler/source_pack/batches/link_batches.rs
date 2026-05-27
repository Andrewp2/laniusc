use super::*;
use crate::codegen::unit::link_batch_input_limit;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::compiler) struct LinkBatchPrepareProgress {
    pub(in crate::compiler) version: u32,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) batch_limits: SourcePackJobBatchLimits,
    pub(in crate::compiler) artifact_count: usize,
    pub(in crate::compiler) interface_artifact_count: usize,
    pub(in crate::compiler) object_artifact_count: usize,
    pub(in crate::compiler) next_interface_artifact_index: usize,
    pub(in crate::compiler) next_interface_batch_index: usize,
    pub(in crate::compiler) next_object_artifact_index: usize,
    pub(in crate::compiler) next_object_batch_index: usize,
}

pub(in crate::compiler) fn validate_build_link_batch_prepare_progress(
    progress: &LinkBatchPrepareProgress,
    target: SourcePackArtifactTarget,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<(), CompileError> {
    if progress.version != SOURCE_PACK_BUILD_LINK_BATCH_PREPARE_PROGRESS_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack link-batch prepare progress version {}; expected {}",
            progress.version, SOURCE_PACK_BUILD_LINK_BATCH_PREPARE_PROGRESS_VERSION
        )));
    }
    if progress.target != target {
        return Err(artifact_shard_contract_error(format!(
            "link-batch prepare progress target {:?} does not match requested target {:?}",
            progress.target, target
        )));
    }
    if progress.batch_limits != batch_limits.normalized() {
        return Err(artifact_shard_contract_error(
            "link-batch prepare progress was created with different batch limits",
        ));
    }
    if progress.artifact_count != artifact_ref_index.artifact_count
        || progress.interface_artifact_count != artifact_ref_index.interface_artifact_count
        || progress.object_artifact_count != artifact_ref_index.object_artifact_count
    {
        return Err(artifact_shard_contract_error(
            "link-batch prepare progress artifact counts do not match artifact-ref index",
        ));
    }
    if progress.next_interface_artifact_index > artifact_ref_index.interface_artifact_count {
        return Err(artifact_shard_contract_error(format!(
            "link-batch prepare progress next interface artifact {} exceeds count {}",
            progress.next_interface_artifact_index, artifact_ref_index.interface_artifact_count
        )));
    }
    let object_start = artifact_ref_index.interface_artifact_count;
    let object_end = object_start
        .checked_add(artifact_ref_index.object_artifact_count)
        .ok_or_else(|| artifact_shard_contract_error("object artifact range overflows"))?;
    if progress.next_object_artifact_index < object_start
        || progress.next_object_artifact_index > object_end
    {
        return Err(artifact_shard_contract_error(format!(
            "link-batch prepare progress next object artifact {} is outside {}..={}",
            progress.next_object_artifact_index, object_start, object_end
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn store_build_link_batch_pages_from_artifact_refs_chunk(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    schedule_index: &SourcePackLibraryScheduleIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    batch_limits: SourcePackJobBatchLimits,
    max_new_batches: usize,
) -> Result<FilesystemLinkBatchPrepareStepResult, CompileError> {
    if max_new_batches == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack link-batch chunk max_new_batches must be greater than zero".into(),
        ));
    }
    validate_library_schedule_index(schedule_index, target)?;
    validate_artifact_ref_index(artifact_ref_index, target)?;
    if store
        .build_link_batch_index_path_for_target(target)
        .is_file()
    {
        let index = store.load_build_link_batch_page_index_for_target(target)?;
        return Ok(FilesystemLinkBatchPrepareStepResult {
            target,
            complete: true,
            link_interface_batch_count: index.link_interface_batch_count,
            link_object_batch_count: index.link_object_batch_count,
            new_batch_count: 0,
            next_interface_artifact_index: artifact_ref_index.interface_artifact_count,
            next_object_artifact_index: artifact_ref_index
                .interface_artifact_count
                .saturating_add(artifact_ref_index.object_artifact_count),
            link_batch_index_path: Some(store.build_link_batch_index_path_for_target(target)),
        });
    }
    let frontend_job_count = library_schedule_index_frontend_job_count(schedule_index);
    if artifact_ref_index.artifact_count != schedule_index.job_count
        || artifact_ref_index.interface_artifact_count != frontend_job_count
        || artifact_ref_index.object_artifact_count != schedule_index.codegen_job_count
    {
        return Err(artifact_shard_contract_error(
            "artifact-ref index does not match schedule index for link-batch chunks",
        ));
    }

    let progress_path = store.build_link_batch_prepare_progress_path_for_target(target);
    let object_start = frontend_job_count;
    let object_end = schedule_index.link_job_index;
    let mut progress = if progress_path.is_file() {
        store.load_build_link_batch_prepare_progress_for_target(
            target,
            artifact_ref_index,
            batch_limits,
        )?
    } else {
        LinkBatchPrepareProgress {
            version: SOURCE_PACK_BUILD_LINK_BATCH_PREPARE_PROGRESS_VERSION,
            target,
            batch_limits: batch_limits.normalized(),
            artifact_count: artifact_ref_index.artifact_count,
            interface_artifact_count: artifact_ref_index.interface_artifact_count,
            object_artifact_count: artifact_ref_index.object_artifact_count,
            next_interface_artifact_index: 0,
            next_interface_batch_index: 0,
            next_object_artifact_index: object_start,
            next_object_batch_index: 0,
        }
    };
    validate_build_link_batch_prepare_progress(
        &progress,
        target,
        artifact_ref_index,
        batch_limits,
    )?;

    let mut new_batch_count = 0usize;
    if progress.next_interface_artifact_index < frontend_job_count {
        let step = store_link_interface_batch_pages_chunk(
            store,
            target,
            artifact_ref_index,
            progress.next_interface_artifact_index,
            frontend_job_count,
            progress.next_interface_batch_index,
            batch_limits,
            max_new_batches,
        )?;
        progress.next_interface_artifact_index = step.next_artifact_index;
        progress.next_interface_batch_index = step.next_batch_index;
        new_batch_count += step.new_batch_count;
        store.store_build_link_batch_prepare_progress(&progress)?;
        if new_batch_count >= max_new_batches
            && progress.next_interface_artifact_index < frontend_job_count
        {
            return Ok(FilesystemLinkBatchPrepareStepResult {
                target,
                complete: false,
                link_interface_batch_count: progress.next_interface_batch_index,
                link_object_batch_count: progress.next_object_batch_index,
                new_batch_count,
                next_interface_artifact_index: progress.next_interface_artifact_index,
                next_object_artifact_index: progress.next_object_artifact_index,
                link_batch_index_path: None,
            });
        }
    }

    if progress.next_object_artifact_index < object_end {
        let remaining_new_batches = max_new_batches.saturating_sub(new_batch_count);
        if remaining_new_batches == 0 {
            return Ok(FilesystemLinkBatchPrepareStepResult {
                target,
                complete: false,
                link_interface_batch_count: progress.next_interface_batch_index,
                link_object_batch_count: progress.next_object_batch_index,
                new_batch_count,
                next_interface_artifact_index: progress.next_interface_artifact_index,
                next_object_artifact_index: progress.next_object_artifact_index,
                link_batch_index_path: None,
            });
        }
        let step = store_link_object_batch_pages_from_artifact_refs_chunk(
            store,
            target,
            artifact_ref_index,
            progress.next_object_artifact_index,
            object_end,
            progress.next_object_batch_index,
            batch_limits,
            remaining_new_batches,
        )?;
        progress.next_object_artifact_index = step.next_artifact_index;
        progress.next_object_batch_index = step.next_batch_index;
        new_batch_count += step.new_batch_count;
        store.store_build_link_batch_prepare_progress(&progress)?;
        if new_batch_count >= max_new_batches && progress.next_object_artifact_index < object_end {
            return Ok(FilesystemLinkBatchPrepareStepResult {
                target,
                complete: false,
                link_interface_batch_count: progress.next_interface_batch_index,
                link_object_batch_count: progress.next_object_batch_index,
                new_batch_count,
                next_interface_artifact_index: progress.next_interface_artifact_index,
                next_object_artifact_index: progress.next_object_artifact_index,
                link_batch_index_path: None,
            });
        }
    }

    if progress.next_interface_artifact_index != frontend_job_count
        || progress.next_object_artifact_index != object_end
    {
        return Ok(FilesystemLinkBatchPrepareStepResult {
            target,
            complete: false,
            link_interface_batch_count: progress.next_interface_batch_index,
            link_object_batch_count: progress.next_object_batch_index,
            new_batch_count,
            next_interface_artifact_index: progress.next_interface_artifact_index,
            next_object_artifact_index: progress.next_object_artifact_index,
            link_batch_index_path: None,
        });
    }
    let index = SourcePackBuildLinkBatchPageIndex {
        version: SOURCE_PACK_BUILD_LINK_BATCH_PAGE_INDEX_VERSION,
        target,
        link_interface_batch_count: progress.next_interface_batch_index,
        link_object_batch_count: progress.next_object_batch_index,
    };
    validate_link_batch_page_index(&index, target)?;
    let link_batch_index_path = store.store_build_link_batch_page_index(&index)?;
    Ok(FilesystemLinkBatchPrepareStepResult {
        target,
        complete: true,
        link_interface_batch_count: index.link_interface_batch_count,
        link_object_batch_count: index.link_object_batch_count,
        new_batch_count,
        next_interface_artifact_index: progress.next_interface_artifact_index,
        next_object_artifact_index: progress.next_object_artifact_index,
        link_batch_index_path: Some(link_batch_index_path),
    })
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(in crate::compiler) struct LinkBatchChunkStep {
    pub(in crate::compiler) next_artifact_index: usize,
    pub(in crate::compiler) next_batch_index: usize,
    pub(in crate::compiler) new_batch_count: usize,
}

pub(in crate::compiler) fn store_link_interface_batch_pages_chunk(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    mut artifact_index: usize,
    end_artifact_index: usize,
    mut batch_index: usize,
    batch_limits: SourcePackJobBatchLimits,
    max_new_batches: usize,
) -> Result<LinkBatchChunkStep, CompileError> {
    let limits = batch_limits.normalized();
    let max_input_artifacts_per_batch = link_batch_input_limit(batch_limits);
    let mut current_artifacts = Vec::new();
    let mut current_source_bytes = 0usize;
    let mut current_source_file_count = 0usize;
    let mut current_source_lines = 0usize;
    let mut new_batch_count = 0usize;

    while artifact_index < end_artifact_index {
        let page =
            load_artifact_ref_page_for_index(store, target, artifact_ref_index, artifact_index)?;
        if page.artifact_ref.kind != SourcePackArtifactKind::LibraryInterface {
            return Err(artifact_shard_contract_error(format!(
                "link-interface batch input artifact {} has kind {:?}",
                page.artifact_index, page.artifact_ref.kind
            )));
        }
        let should_flush = !current_artifacts.is_empty()
            && (current_artifacts.len() >= max_input_artifacts_per_batch
                || current_source_bytes.saturating_add(page.source_bytes)
                    > limits.max_source_bytes_per_batch
                || current_source_file_count.saturating_add(page.source_file_count)
                    > limits.max_source_files_per_batch);
        if should_flush {
            store_link_interface_batch_page(
                store,
                target,
                batch_index,
                &mut current_artifacts,
                &mut current_source_bytes,
                &mut current_source_file_count,
                &mut current_source_lines,
            )?;
            batch_index += 1;
            new_batch_count += 1;
            if new_batch_count >= max_new_batches {
                return Ok(LinkBatchChunkStep {
                    next_artifact_index: artifact_index,
                    next_batch_index: batch_index,
                    new_batch_count,
                });
            }
        }
        current_artifacts.push(page.artifact_index);
        current_source_bytes = current_source_bytes.saturating_add(page.source_bytes);
        current_source_file_count =
            current_source_file_count.saturating_add(page.source_file_count);
        current_source_lines = current_source_lines.saturating_add(page.source_lines);
        artifact_index += 1;
    }
    if !current_artifacts.is_empty() {
        store_link_interface_batch_page(
            store,
            target,
            batch_index,
            &mut current_artifacts,
            &mut current_source_bytes,
            &mut current_source_file_count,
            &mut current_source_lines,
        )?;
        batch_index += 1;
        new_batch_count += 1;
    }
    Ok(LinkBatchChunkStep {
        next_artifact_index: artifact_index,
        next_batch_index: batch_index,
        new_batch_count,
    })
}

pub(in crate::compiler) fn store_link_interface_batch_page(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    batch_index: usize,
    current_artifacts: &mut Vec<usize>,
    current_source_bytes: &mut usize,
    current_source_file_count: &mut usize,
    current_source_lines: &mut usize,
) -> Result<(), CompileError> {
    let batch = SourcePackLinkInterfaceBatch {
        batch_index,
        input_interface_artifact_indices: std::mem::take(current_artifacts),
        source_bytes: std::mem::take(current_source_bytes),
        source_file_count: std::mem::take(current_source_file_count),
        source_lines: std::mem::take(current_source_lines),
    };
    let page = SourcePackBuildLinkInterfaceBatchPage {
        version: SOURCE_PACK_BUILD_LINK_INTERFACE_BATCH_PAGE_VERSION,
        target,
        batch_index: batch.batch_index,
        batch,
    };
    store.store_build_link_interface_batch_page(&page)?;
    Ok(())
}

pub(in crate::compiler) fn store_link_object_batch_pages_from_artifact_refs_chunk(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    mut artifact_index: usize,
    end_artifact_index: usize,
    mut batch_index: usize,
    batch_limits: SourcePackJobBatchLimits,
    max_new_batches: usize,
) -> Result<LinkBatchChunkStep, CompileError> {
    let limits = batch_limits.normalized();
    let max_input_artifacts_per_batch = link_batch_input_limit(batch_limits);
    let mut current_artifacts = Vec::new();
    let mut current_source_bytes = 0usize;
    let mut current_source_file_count = 0usize;
    let mut current_source_lines = 0usize;
    let mut new_batch_count = 0usize;

    while artifact_index < end_artifact_index {
        let page =
            load_artifact_ref_page_for_index(store, target, artifact_ref_index, artifact_index)?;
        if page.artifact_ref.kind != SourcePackArtifactKind::CodegenObject {
            return Err(artifact_shard_contract_error(format!(
                "link-object batch input artifact {} has kind {:?}",
                page.artifact_index, page.artifact_ref.kind
            )));
        }
        let should_flush = !current_artifacts.is_empty()
            && (current_artifacts.len() >= max_input_artifacts_per_batch
                || current_source_bytes.saturating_add(page.source_bytes)
                    > limits.max_source_bytes_per_batch
                || current_source_file_count.saturating_add(page.source_file_count)
                    > limits.max_source_files_per_batch);
        if should_flush {
            store_link_object_batch_page(
                store,
                target,
                batch_index,
                &mut current_artifacts,
                &mut current_source_bytes,
                &mut current_source_file_count,
                &mut current_source_lines,
            )?;
            batch_index += 1;
            new_batch_count += 1;
            if new_batch_count >= max_new_batches {
                return Ok(LinkBatchChunkStep {
                    next_artifact_index: artifact_index,
                    next_batch_index: batch_index,
                    new_batch_count,
                });
            }
        }
        current_artifacts.push(page.artifact_index);
        current_source_bytes = current_source_bytes.saturating_add(page.source_bytes);
        current_source_file_count =
            current_source_file_count.saturating_add(page.source_file_count);
        current_source_lines = current_source_lines.saturating_add(page.source_lines);
        artifact_index += 1;
    }
    if !current_artifacts.is_empty() {
        store_link_object_batch_page(
            store,
            target,
            batch_index,
            &mut current_artifacts,
            &mut current_source_bytes,
            &mut current_source_file_count,
            &mut current_source_lines,
        )?;
        batch_index += 1;
        new_batch_count += 1;
    }
    Ok(LinkBatchChunkStep {
        next_artifact_index: artifact_index,
        next_batch_index: batch_index,
        new_batch_count,
    })
}

pub(in crate::compiler) fn store_link_object_batch_page(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    batch_index: usize,
    current_artifacts: &mut Vec<usize>,
    current_source_bytes: &mut usize,
    current_source_file_count: &mut usize,
    current_source_lines: &mut usize,
) -> Result<(), CompileError> {
    let batch = SourcePackLinkObjectBatch {
        batch_index,
        input_object_artifact_indices: std::mem::take(current_artifacts),
        source_bytes: std::mem::take(current_source_bytes),
        source_file_count: std::mem::take(current_source_file_count),
        source_lines: std::mem::take(current_source_lines),
    };
    let page = SourcePackBuildLinkObjectBatchPage {
        version: SOURCE_PACK_BUILD_LINK_OBJECT_BATCH_PAGE_VERSION,
        target,
        batch_index: batch.batch_index,
        batch,
    };
    store.store_build_link_object_batch_page(&page)?;
    Ok(())
}
