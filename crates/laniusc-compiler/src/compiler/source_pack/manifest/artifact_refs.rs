use super::*;

/// Validates the top-level artifact-ref index for a target.
///
/// The index must describe dense interface artifacts, object artifacts, and one
/// final linked-output artifact whose key and source summary match the index.
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
        .checked_add(index.object_artifact_count)
        .and_then(|count| count.checked_add(1))
        .ok_or_else(|| {
            artifact_shard_contract_error(format!(
                "artifact-ref index artifact counts overflow: interface {} + object {} + final output",
                index.interface_artifact_count, index.object_artifact_count
            ))
        })?;
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
    validate_artifact_ref_index_final_output_key(index)?;
    validate_artifact_ref_source_byte_summary(
        "artifact-ref index",
        index.total_source_byte_count,
        index.total_source_file_count,
    )?;
    Ok(())
}

fn validate_artifact_ref_index_final_output_key(
    index: &SourcePackBuildArtifactRefIndex,
) -> Result<(), CompileError> {
    let expected_prefix = match index.target.key_prefix() {
        Some(target_prefix) => format!("{target_prefix}/linked-output/job-"),
        None => "linked-output/job-".into(),
    };
    let Some(suffix) = index.final_output_key.strip_prefix(&expected_prefix) else {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref index final output key {:?} does not start with expected prefix {:?}",
            index.final_output_key, expected_prefix
        )));
    };
    let Some((producer_job_index, source_range)) = suffix.split_once("/src-") else {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref index final output key {:?} must include a producer job and source range",
            index.final_output_key
        )));
    };
    let producer_job_index = parse_artifact_ref_index_key_usize(
        producer_job_index,
        &index.final_output_key,
        "producer job index",
    )?;
    if producer_job_index != index.final_output_artifact_index {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref index final output key {:?} records producer job {} but final output artifact index is {}",
            index.final_output_key, producer_job_index, index.final_output_artifact_index
        )));
    }
    let Some((first_source_index, source_end)) = source_range.split_once('-') else {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref index final output key {:?} has invalid source range",
            index.final_output_key
        )));
    };
    let first_source_index = parse_artifact_ref_index_key_usize(
        first_source_index,
        &index.final_output_key,
        "first source index",
    )?;
    if first_source_index != 0 {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref index final output key {:?} starts at source {}; expected source 0",
            index.final_output_key, first_source_index
        )));
    }
    let source_end =
        parse_artifact_ref_index_key_usize(source_end, &index.final_output_key, "source end")?;
    if source_end <= first_source_index {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref index final output key {:?} has empty source range {}..{}",
            index.final_output_key, first_source_index, source_end
        )));
    }
    if source_end != index.total_source_file_count {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref index final output key {:?} source end {} does not match total source file count {}",
            index.final_output_key, source_end, index.total_source_file_count
        )));
    }
    Ok(())
}

fn parse_artifact_ref_index_key_usize(
    value: &str,
    key: &str,
    field: &str,
) -> Result<usize, CompileError> {
    if value.is_empty() || !value.as_bytes().iter().all(|byte| byte.is_ascii_digit()) {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref index final output key {key:?} has invalid {field}"
        )));
    }
    if value.len() > 1 && value.starts_with('0') {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref index final output key {key:?} has non-canonical {field} {value:?}; expected no leading zeroes"
        )));
    }
    value.parse::<usize>().map_err(|err| {
        artifact_shard_contract_error(format!(
            "artifact-ref index final output key {key:?} has invalid {field}: {err}"
        ))
    })
}

/// Validates one artifact-ref page.
///
/// Artifact refs are dense by producing job index. The page key, kind, final
/// slot rules, and source-byte summary are checked against that dense layout.
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
    validate_artifact_ref_page_final_slot(page, artifact_count)?;
    validate_artifact_key_kind(
        target,
        &page.artifact_ref.key,
        page.artifact_ref.kind,
        &format!("artifact-ref page {}", page.artifact_index),
        artifact_shard_contract_error,
    )?;
    validate_artifact_ref_page_key(page)?;
    validate_artifact_ref_source_byte_summary(
        &format!("artifact-ref page {}", page.artifact_index),
        page.source_bytes,
        page.source_file_count,
    )?;
    Ok(())
}

fn validate_artifact_ref_source_byte_summary(
    label: &str,
    source_bytes: usize,
    source_file_count: usize,
) -> Result<(), CompileError> {
    if source_bytes >= source_file_count {
        return Ok(());
    }
    Err(artifact_shard_contract_error(format!(
        "{label} source-byte summary {source_bytes} is smaller than source-file count {source_file_count}; artifact-ref replay needs concrete source-byte provenance for every source file"
    )))
}

fn validate_artifact_ref_page_final_slot(
    page: &SourcePackBuildArtifactRefPage,
    artifact_count: usize,
) -> Result<(), CompileError> {
    let final_artifact_index = artifact_count - 1;
    let is_final_slot = page.artifact_index == final_artifact_index;
    if is_final_slot && page.artifact_ref.kind != SourcePackArtifactKind::LinkedOutput {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref page {} is the dense final artifact slot {} but contains {:?}; final artifact rows must be linked-output evidence",
            page.artifact_index, final_artifact_index, page.artifact_ref.kind
        )));
    }
    if !is_final_slot && page.artifact_ref.kind == SourcePackArtifactKind::LinkedOutput {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref page {} contains linked-output evidence before dense final artifact slot {}; linked outputs must not occupy non-final artifact rows",
            page.artifact_index, final_artifact_index
        )));
    }
    Ok(())
}

fn validate_artifact_ref_page_key(
    page: &SourcePackBuildArtifactRefPage,
) -> Result<(), CompileError> {
    let label = format!("artifact-ref page {}", page.artifact_index);
    let (key_producer_job_index, key_first_source_index, key_source_end) =
        parse_artifact_ref_page_key(page, &label)?;
    if key_producer_job_index != page.artifact_ref.producing_job_index {
        return Err(artifact_shard_contract_error(format!(
            "{label} key {:?} records producer job {} but artifact ref producer job {}",
            page.artifact_ref.key, key_producer_job_index, page.artifact_ref.producing_job_index
        )));
    }
    let key_source_file_count = key_source_end - key_first_source_index;
    if key_source_file_count != page.source_file_count {
        return Err(artifact_shard_contract_error(format!(
            "{label} key {:?} source range {}..{} covers {} files but page records source file count {}",
            page.artifact_ref.key,
            key_first_source_index,
            key_source_end,
            key_source_file_count,
            page.source_file_count
        )));
    }
    if page.artifact_ref.kind == SourcePackArtifactKind::LinkedOutput && key_first_source_index != 0
    {
        return Err(artifact_shard_contract_error(format!(
            "{label} linked-output key {:?} starts at source {}; expected source 0",
            page.artifact_ref.key, key_first_source_index
        )));
    }
    Ok(())
}

fn parse_artifact_ref_page_key(
    page: &SourcePackBuildArtifactRefPage,
    label: &str,
) -> Result<(usize, usize, usize), CompileError> {
    let key = &page.artifact_ref.key;
    if page.artifact_ref.kind == SourcePackArtifactKind::LinkedOutput {
        let expected_prefix = match page.target.key_prefix() {
            Some(target_prefix) => format!("{target_prefix}/linked-output/job-"),
            None => "linked-output/job-".into(),
        };
        let Some(suffix) = key.strip_prefix(&expected_prefix) else {
            return Err(artifact_shard_contract_error(format!(
                "{label} key {key:?} does not start with expected prefix {expected_prefix:?}"
            )));
        };
        let Some((producer_job_index, source_range)) = suffix.split_once("/src-") else {
            return Err(artifact_shard_contract_error(format!(
                "{label} key {key:?} must include a producer job and source range"
            )));
        };
        return parse_artifact_ref_page_key_job_and_source_range(
            key,
            label,
            producer_job_index,
            source_range,
        );
    }

    let expected_prefix = match page.target.key_prefix() {
        Some(target_prefix) => format!(
            "{target_prefix}/{}/lib-",
            page.artifact_ref.kind.key_segment()
        ),
        None => format!("{}/lib-", page.artifact_ref.kind.key_segment()),
    };
    let Some(suffix) = key.strip_prefix(&expected_prefix) else {
        return Err(artifact_shard_contract_error(format!(
            "{label} key {key:?} does not start with expected prefix {expected_prefix:?}"
        )));
    };
    let Some((library_id, job_suffix)) = suffix.split_once("/job-") else {
        return Err(artifact_shard_contract_error(format!(
            "{label} key {key:?} must include a library id and producer job"
        )));
    };
    parse_artifact_ref_page_key_usize(key, label, "library id", library_id)?;
    let Some((producer_job_index, source_range)) = job_suffix.split_once("/src-") else {
        return Err(artifact_shard_contract_error(format!(
            "{label} key {key:?} must include a source range"
        )));
    };
    parse_artifact_ref_page_key_job_and_source_range(key, label, producer_job_index, source_range)
}

fn parse_artifact_ref_page_key_job_and_source_range(
    key: &str,
    label: &str,
    producer_job_index: &str,
    source_range: &str,
) -> Result<(usize, usize, usize), CompileError> {
    let producer_job_index =
        parse_artifact_ref_page_key_usize(key, label, "producer job index", producer_job_index)?;
    let Some((first_source_index, source_end)) = source_range.split_once('-') else {
        return Err(artifact_shard_contract_error(format!(
            "{label} key {key:?} has invalid source range"
        )));
    };
    let first_source_index =
        parse_artifact_ref_page_key_usize(key, label, "first source index", first_source_index)?;
    let source_end = parse_artifact_ref_page_key_usize(key, label, "source end", source_end)?;
    if source_end <= first_source_index {
        return Err(artifact_shard_contract_error(format!(
            "{label} key {key:?} has empty source range {first_source_index}..{source_end}"
        )));
    }
    Ok((producer_job_index, first_source_index, source_end))
}

fn parse_artifact_ref_page_key_usize(
    key: &str,
    label: &str,
    field: &str,
    value: &str,
) -> Result<usize, CompileError> {
    if value.is_empty() || !value.as_bytes().iter().all(|byte| byte.is_ascii_digit()) {
        return Err(artifact_shard_contract_error(format!(
            "{label} key {key:?} has invalid {field}"
        )));
    }
    if value.len() > 1 && value.starts_with('0') {
        return Err(artifact_shard_contract_error(format!(
            "{label} key {key:?} has non-canonical {field} {value:?}; expected no leading zeroes"
        )));
    }
    value.parse::<usize>().map_err(|err| {
        artifact_shard_contract_error(format!("{label} key {key:?} has invalid {field}: {err}"))
    })
}

/// Validates one sidecar page of job input interface refs.
///
/// Pages must be dense by page index, non-empty, bounded by the interface input
/// page size, and contain only library-interface artifact refs.
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

#[cfg(test)]
mod tests {
    use super::*;

    fn artifact_ref_index(final_output_key: impl Into<String>) -> SourcePackBuildArtifactRefIndex {
        SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target: SourcePackArtifactTarget::Generic,
            artifact_count: 3,
            interface_artifact_count: 1,
            object_artifact_count: 1,
            final_output_artifact_index: 2,
            final_output_key: final_output_key.into(),
            total_source_file_count: 2,
            total_source_byte_count: 64,
            total_source_line_count: 8,
        }
    }

    #[test]
    fn artifact_ref_index_rejects_overflowed_dense_artifact_totals() {
        let index = SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target: SourcePackArtifactTarget::Generic,
            artifact_count: usize::MAX,
            interface_artifact_count: usize::MAX,
            object_artifact_count: 0,
            final_output_artifact_index: usize::MAX - 1,
            final_output_key: format!("linked-output/job-{}/src-0-1", usize::MAX - 1),
            total_source_file_count: 1,
            total_source_byte_count: 64,
            total_source_line_count: 8,
        };

        let err = validate_artifact_ref_index(&index, SourcePackArtifactTarget::Generic)
            .expect_err("overflowed artifact-ref totals must not saturate to a dense count");
        let message = err.to_string();
        assert!(
            message.contains("artifact counts overflow")
                && message.contains("interface")
                && message.contains("final output"),
            "unexpected overflow validation error: {message}"
        );
    }

    #[test]
    fn artifact_ref_index_final_output_key_matches_dense_artifact_and_source_total() {
        validate_artifact_ref_index(
            &artifact_ref_index("linked-output/job-2/src-0-2"),
            SourcePackArtifactTarget::Generic,
        )
        .expect("matching final output artifact key should validate");

        let err = validate_artifact_ref_index(
            &artifact_ref_index("linked-output/job-1/src-0-2"),
            SourcePackArtifactTarget::Generic,
        )
        .expect_err("final output key producer must match the dense final artifact");
        let message = err.to_string();
        assert!(
            message.contains("producer job 1") && message.contains("artifact index is 2"),
            "unexpected producer mismatch error: {message}"
        );

        let err = validate_artifact_ref_index(
            &artifact_ref_index("linked-output/job-2/src-0-1"),
            SourcePackArtifactTarget::Generic,
        )
        .expect_err("final output key source range must cover the artifact source total");
        let message = err.to_string();
        assert!(
            message.contains("source end 1") && message.contains("total source file count 2"),
            "unexpected source range mismatch error: {message}"
        );
    }
}
