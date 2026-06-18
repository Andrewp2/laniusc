use super::*;

/// Validates the top-level link-batch page index.
pub(in crate::compiler) fn validate_link_batch_page_index(
    index: &SourcePackBuildLinkBatchPageIndex,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if index.version != SOURCE_PACK_BUILD_LINK_BATCH_PAGE_INDEX_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack link-batch page index version {}; expected {}",
            index.version, SOURCE_PACK_BUILD_LINK_BATCH_PAGE_INDEX_VERSION
        )));
    }
    if index.target != target {
        return Err(artifact_shard_contract_error(format!(
            "link-batch page index target {:?} does not match requested target {:?}",
            index.target, target
        )));
    }
    Ok(())
}

/// Validates one link-interface batch page.
///
/// The page must contain a non-empty, sorted, unique, bounded list of interface
/// artifact indices and its embedded batch record must match the page index.
pub(in crate::compiler) fn validate_link_interface_batch_page(
    page: &SourcePackBuildLinkInterfaceBatchPage,
    target: SourcePackArtifactTarget,
    batch_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_BUILD_LINK_INTERFACE_BATCH_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack link-interface batch page version {}; expected {}",
            page.version, SOURCE_PACK_BUILD_LINK_INTERFACE_BATCH_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(artifact_shard_contract_error(format!(
            "link-interface batch page target {:?} does not match requested target {:?}",
            page.target, target
        )));
    }
    if let Some(batch_index) = batch_index {
        if page.batch_index != batch_index {
            return Err(artifact_shard_contract_error(format!(
                "loaded link-interface batch page {} but requested batch {}",
                page.batch_index, batch_index
            )));
        }
    }
    if page.batch.batch_index != page.batch_index {
        return Err(artifact_shard_contract_error(format!(
            "link-interface batch page {} contains batch record {}",
            page.batch_index, page.batch.batch_index
        )));
    }
    if page.batch.input_interface_artifact_indices.is_empty() {
        return Err(artifact_shard_contract_error(format!(
            "link-interface batch page {} has no input artifacts",
            page.batch_index
        )));
    }
    if page.batch.input_interface_artifact_indices.len()
        > SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE
    {
        return Err(artifact_shard_contract_error(format!(
            "link-interface batch page {} has {} input artifacts but the page limit is {}",
            page.batch_index,
            page.batch.input_interface_artifact_indices.len(),
            SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE
        )));
    }
    unique_usize_set(
        &page.batch.input_interface_artifact_indices,
        &format!("link-interface batch page {} inputs", page.batch_index),
    )?;
    validate_usize_values_strictly_ascending(
        &page.batch.input_interface_artifact_indices,
        &format!("link-interface batch page {} inputs", page.batch_index),
        |message| artifact_shard_contract_error(message),
    )?;
    Ok(())
}

/// Validates one link-object batch page.
///
/// The page must contain a non-empty, sorted, unique, bounded list of object
/// artifact indices and its embedded batch record must match the page index.
pub(in crate::compiler) fn validate_link_object_batch_page(
    page: &SourcePackBuildLinkObjectBatchPage,
    target: SourcePackArtifactTarget,
    batch_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_BUILD_LINK_OBJECT_BATCH_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack link-object batch page version {}; expected {}",
            page.version, SOURCE_PACK_BUILD_LINK_OBJECT_BATCH_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(artifact_shard_contract_error(format!(
            "link-object batch page target {:?} does not match requested target {:?}",
            page.target, target
        )));
    }
    if let Some(batch_index) = batch_index {
        if page.batch_index != batch_index {
            return Err(artifact_shard_contract_error(format!(
                "loaded link-object batch page {} but requested batch {}",
                page.batch_index, batch_index
            )));
        }
    }
    if page.batch.batch_index != page.batch_index {
        return Err(artifact_shard_contract_error(format!(
            "link-object batch page {} contains batch record {}",
            page.batch_index, page.batch.batch_index
        )));
    }
    if page.batch.input_object_artifact_indices.is_empty() {
        return Err(artifact_shard_contract_error(format!(
            "link-object batch page {} has no input artifacts",
            page.batch_index
        )));
    }
    if page.batch.input_object_artifact_indices.len()
        > SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE
    {
        return Err(artifact_shard_contract_error(format!(
            "link-object batch page {} has {} input artifacts but the page limit is {}",
            page.batch_index,
            page.batch.input_object_artifact_indices.len(),
            SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE
        )));
    }
    unique_usize_set(
        &page.batch.input_object_artifact_indices,
        &format!("link-object batch page {} inputs", page.batch_index),
    )?;
    validate_usize_values_strictly_ascending(
        &page.batch.input_object_artifact_indices,
        &format!("link-object batch page {} inputs", page.batch_index),
        |message| artifact_shard_contract_error(message),
    )?;
    Ok(())
}

/// Validates the shard ranges used as inputs to the link job.
///
/// Interface and object ranges may be absent, but present ranges must be
/// non-empty, non-overflowing, and non-overlapping.
pub(in crate::compiler) fn validate_link_input_shard_index(
    index: &SourcePackBuildLinkInputShardIndex,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if index.version != SOURCE_PACK_BUILD_LINK_INPUT_SHARD_INDEX_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack link input shard index version {}; expected {}",
            index.version, SOURCE_PACK_BUILD_LINK_INPUT_SHARD_INDEX_VERSION
        )));
    }
    if index.target != target {
        return Err(artifact_shard_contract_error(format!(
            "link input shard index target {:?} does not match requested target {:?}",
            index.target, target
        )));
    }
    validate_link_input_shard_range(index.link_interface_shard_range.as_ref(), "interface")?;
    validate_link_input_shard_range(index.link_object_shard_range.as_ref(), "object")?;
    if let (Some(interface_range), Some(object_range)) = (
        &index.link_interface_shard_range,
        &index.link_object_shard_range,
    ) {
        let interface_end = interface_range.end_shard_index().ok_or_else(|| {
            artifact_shard_contract_error("interface link input shard range overflows")
        })?;
        let object_end = object_range.end_shard_index().ok_or_else(|| {
            artifact_shard_contract_error("object link input shard range overflows")
        })?;
        if interface_range.first_shard_index < object_end
            && object_range.first_shard_index < interface_end
        {
            return Err(artifact_shard_contract_error(format!(
                "link input shard interface range {}..{} overlaps object range {}..{}",
                interface_range.first_shard_index,
                interface_end,
                object_range.first_shard_index,
                object_end
            )));
        }
    }
    Ok(())
}

/// Validates one optional link-input shard range.
pub(in crate::compiler) fn validate_link_input_shard_range(
    range: Option<&SourcePackLinkInputShardRange>,
    label: &str,
) -> Result<(), CompileError> {
    let Some(range) = range else {
        return Ok(());
    };
    if range.shard_count == 0 {
        return Err(artifact_shard_contract_error(format!(
            "{label} link input shard range is empty"
        )));
    }
    if range.end_shard_index().is_none() {
        return Err(artifact_shard_contract_error(format!(
            "{label} link input shard range overflows"
        )));
    }
    Ok(())
}

/// Visits every shard index in the requested link-input shard range.
///
/// Only link-interface and link-object shard kinds are valid here; job-batch
/// shards are not direct inputs to the link job.
pub(in crate::compiler) fn for_each_link_input_shard_index<F>(
    index: &SourcePackBuildLinkInputShardIndex,
    kind: SourcePackBuildArtifactShardKind,
    mut visit: F,
) -> Result<(), CompileError>
where
    F: FnMut(usize) -> Result<(), CompileError>,
{
    let (range, label) = match kind {
        SourcePackBuildArtifactShardKind::LinkInterfaceBatches => {
            (index.link_interface_shard_range.as_ref(), "interface")
        }
        SourcePackBuildArtifactShardKind::LinkObjectBatches => {
            (index.link_object_shard_range.as_ref(), "object")
        }
        SourcePackBuildArtifactShardKind::JobBatches => {
            return Err(artifact_shard_contract_error(
                "job-batch shards are not link-input shards",
            ));
        }
    };
    if let Some(range) = range {
        let Some(indices) = range.iter() else {
            return Err(artifact_shard_contract_error(format!(
                "{label} link input shard range overflows"
            )));
        };
        for shard_index in indices {
            visit(shard_index)?;
        }
    }
    Ok(())
}
