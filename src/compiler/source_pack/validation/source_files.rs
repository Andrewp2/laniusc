use super::*;

pub(in crate::compiler) fn validate_library_partition_locator_page(
    page: &SourcePackLibraryPartitionLocatorPage,
    target: SourcePackArtifactTarget,
    expected_library_id: Option<u32>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_LIBRARY_PARTITION_LOCATOR_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library partition locator page version {}; expected {}",
            page.version, SOURCE_PACK_LIBRARY_PARTITION_LOCATOR_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(library_partition_contract_error(format!(
            "library partition locator for library {} target {:?} does not match requested target {:?}",
            page.library_id, page.target, target
        )));
    }
    if let Some(expected_library_id) = expected_library_id {
        if page.library_id != expected_library_id {
            return Err(library_partition_contract_error(format!(
                "loaded partition locator for library {} but expected {}",
                page.library_id, expected_library_id
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_library_source_file_page(
    page: &SourcePackLibrarySourceFilePage,
    target: SourcePackArtifactTarget,
    expected_partition_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_LIBRARY_SOURCE_FILE_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library source-file page version {}; expected {}",
            page.version, SOURCE_PACK_LIBRARY_SOURCE_FILE_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(library_partition_contract_error(format!(
            "source-file page {} target {:?} does not match requested target {:?}",
            page.partition_index, page.target, target
        )));
    }
    if let Some(expected_partition_index) = expected_partition_index {
        if page.partition_index != expected_partition_index {
            return Err(library_partition_contract_error(format!(
                "loaded source-file page {} but expected {}",
                page.partition_index, expected_partition_index
            )));
        }
    }
    if page.source_file_count == 0 {
        return Err(library_partition_contract_error(format!(
            "source-file page {} has no source files",
            page.partition_index
        )));
    }
    page.first_source_index
        .checked_add(page.source_file_count)
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "source-file page {} source range overflows",
                page.partition_index
            ))
        })?;
    if page.source_files.is_empty() {
        return Ok(());
    }
    if page.source_files.len() > SOURCE_PACK_LIBRARY_SOURCE_FILE_INLINE_DEFAULT_RECORD_CAP {
        return Err(library_partition_contract_error(format!(
            "source-file page {} has {} inline source-file records but the record cap is {}",
            page.partition_index,
            page.source_files.len(),
            SOURCE_PACK_LIBRARY_SOURCE_FILE_INLINE_DEFAULT_RECORD_CAP
        )));
    }
    if page.source_files.len() != page.source_file_count {
        return Err(library_partition_contract_error(format!(
            "source-file page {} has {} files but source_file_count {}",
            page.partition_index,
            page.source_files.len(),
            page.source_file_count
        )));
    }

    let mut source_byte_count = 0usize;
    let mut source_line_count = 0usize;
    for (offset, source_file) in page.source_files.iter().enumerate() {
        let expected_source_index = page.first_source_index + offset;
        if source_file.source_index != expected_source_index {
            return Err(library_partition_contract_error(format!(
                "source-file page {} entry {} has source index {}, expected {}",
                page.partition_index, offset, source_file.source_index, expected_source_index
            )));
        }
        if source_file.file.library_id != page.library_id {
            return Err(library_partition_contract_error(format!(
                "source-file page {} entry {} has library {}, expected {}",
                page.partition_index, offset, source_file.file.library_id, page.library_id
            )));
        }
        source_byte_count = source_byte_count
            .checked_add(source_file.file.byte_len)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "source-file page {} byte count overflows",
                    page.partition_index
                ))
            })?;
        source_line_count = source_line_count
            .checked_add(source_file.file.line_count.unwrap_or(0))
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "source-file page {} source line count overflows",
                    page.partition_index
                ))
            })?;
    }
    if source_byte_count != page.source_byte_count {
        return Err(library_partition_contract_error(format!(
            "source-file page {} byte total {} does not match source_byte_count {}",
            page.partition_index, source_byte_count, page.source_byte_count
        )));
    }
    if source_line_count != page.source_line_count {
        return Err(library_partition_contract_error(format!(
            "source-file page {} line total {} does not match source_line_count {}",
            page.partition_index, source_line_count, page.source_line_count
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_library_source_file_record_page(
    page: &SourcePackLibrarySourceFileRecordPage,
    target: SourcePackArtifactTarget,
    expected_source_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_LIBRARY_SOURCE_FILE_RECORD_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library source-file record page version {}; expected {}",
            page.version, SOURCE_PACK_LIBRARY_SOURCE_FILE_RECORD_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(library_partition_contract_error(format!(
            "source-file record {} target {:?} does not match requested target {:?}",
            page.source_index, page.target, target
        )));
    }
    if let Some(expected_source_index) = expected_source_index {
        if page.source_index != expected_source_index {
            return Err(library_partition_contract_error(format!(
                "loaded source-file record {} but expected {}",
                page.source_index, expected_source_index
            )));
        }
    }
    if page.source_file_count == 0 {
        return Err(library_partition_contract_error(format!(
            "source-file record {} has empty partition range",
            page.source_index
        )));
    }
    let source_end = page
        .first_source_index
        .checked_add(page.source_file_count)
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "source-file record {} partition range overflows",
                page.source_index
            ))
        })?;
    if page.source_index < page.first_source_index || page.source_index >= source_end {
        return Err(library_partition_contract_error(format!(
            "source-file record {} is outside partition source range {}..{}",
            page.source_index, page.first_source_index, source_end
        )));
    }
    if page.file.library_id != page.library_id {
        return Err(library_partition_contract_error(format!(
            "source-file record {} has library {}, expected {}",
            page.source_index, page.file.library_id, page.library_id
        )));
    }
    Ok(())
}
