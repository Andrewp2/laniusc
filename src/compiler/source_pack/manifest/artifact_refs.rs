use super::*;

pub(in crate::compiler) fn validate_artifact_ref_index(
    index: &SourcePackBuildArtifactRefIndex,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if index.version != SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack artifact-ref index version {}; expected {}",
            index.version, SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION
        )));
    }
    if index.target != target {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref index target {:?} does not match requested target {:?}",
            index.target, target
        )));
    }
    if index.artifact_count == 0 {
        return Err(artifact_shard_contract_error(
            "artifact-ref index has no artifacts",
        ));
    }
    let expected_artifact_count = index
        .interface_artifact_count
        .saturating_add(index.object_artifact_count)
        .saturating_add(1);
    if index.artifact_count != expected_artifact_count {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref index artifact_count {} does not match interface {} + object {} + final output",
            index.artifact_count, index.interface_artifact_count, index.object_artifact_count
        )));
    }
    if index.final_output_artifact_index >= index.artifact_count {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref index final output artifact {} exceeds artifact_count {}",
            index.final_output_artifact_index, index.artifact_count
        )));
    }
    if index.final_output_artifact_index != index.artifact_count - 1 {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref index final output artifact {} is not the dense final artifact {}",
            index.final_output_artifact_index,
            index.artifact_count - 1
        )));
    }
    validate_artifact_key_kind(
        target,
        &index.final_output_key,
        SourcePackArtifactKind::LinkedOutput,
        "artifact-ref index final output",
        artifact_shard_contract_error,
    )?;
    Ok(())
}

pub(in crate::compiler) fn validate_artifact_ref_page(
    page: &SourcePackBuildArtifactRefPage,
    target: SourcePackArtifactTarget,
    artifact_count: usize,
    expected_artifact_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_BUILD_ARTIFACT_REF_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack artifact-ref page version {}; expected {}",
            page.version, SOURCE_PACK_BUILD_ARTIFACT_REF_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref page target {:?} does not match requested target {:?}",
            page.target, target
        )));
    }
    if let Some(expected_artifact_index) = expected_artifact_index {
        if page.artifact_index != expected_artifact_index {
            return Err(artifact_shard_contract_error(format!(
                "loaded artifact-ref page {} but requested artifact {}",
                page.artifact_index, expected_artifact_index
            )));
        }
    }
    if page.artifact_index >= artifact_count {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref page {} exceeds artifact_count {}",
            page.artifact_index, artifact_count
        )));
    }
    if page.artifact_ref.artifact_index != page.artifact_index {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref page {} contains artifact ref {}",
            page.artifact_index, page.artifact_ref.artifact_index
        )));
    }
    if page.artifact_ref.producing_job_index != page.artifact_index {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref page {} is produced by job {}",
            page.artifact_index, page.artifact_ref.producing_job_index
        )));
    }
    validate_artifact_key_kind(
        target,
        &page.artifact_ref.key,
        page.artifact_ref.kind,
        &format!("artifact-ref page {}", page.artifact_index),
        artifact_shard_contract_error,
    )?;
    Ok(())
}

pub(in crate::compiler) fn validate_job_artifact_input_interface_page(
    page: &SourcePackJobArtifactInputInterfacePage,
    target: SourcePackArtifactTarget,
    expected_job_index: usize,
    expected_page_index: usize,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack job artifact input interface page version {}; expected {}",
            page.version, SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(artifact_shard_contract_error(format!(
            "job artifact input interface page {}:{} target {:?} does not match requested target {:?}",
            page.job_index, page.page_index, page.target, target
        )));
    }
    if page.job_index != expected_job_index || page.page_index != expected_page_index {
        return Err(artifact_shard_contract_error(format!(
            "loaded job artifact input interface page {}:{} but expected {}:{}",
            page.job_index, page.page_index, expected_job_index, expected_page_index
        )));
    }
    let expected_first_input_position = expected_page_index
        .saturating_mul(SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE);
    if page.first_input_position != expected_first_input_position {
        return Err(artifact_shard_contract_error(format!(
            "job artifact input interface page {}:{} starts at {} but expected {}",
            page.job_index,
            page.page_index,
            page.first_input_position,
            expected_first_input_position
        )));
    }
    if page.input_count != page.input_interfaces.len() {
        return Err(artifact_shard_contract_error(format!(
            "job artifact input interface page {}:{} count {} does not match {} refs",
            page.job_index,
            page.page_index,
            page.input_count,
            page.input_interfaces.len()
        )));
    }
    if page.input_count == 0
        || page.input_count > SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE
    {
        return Err(artifact_shard_contract_error(format!(
            "job artifact input interface page {}:{} has invalid input count {}",
            page.job_index, page.page_index, page.input_count
        )));
    }
    validate_link_execution_artifact_refs(
        &page.input_interfaces,
        SourcePackArtifactKind::LibraryInterface,
        target,
        page.job_index,
        &format!(
            "job artifact input interface page {}:{} inputs",
            page.job_index, page.page_index
        ),
    )?;
    Ok(())
}
