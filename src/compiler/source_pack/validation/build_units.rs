use super::*;

pub(in crate::compiler) fn validate_library_build_unit_page(
    page: &SourcePackLibraryBuildUnitPage,
    target: SourcePackArtifactTarget,
    expected_partition_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_LIBRARY_BUILD_UNIT_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library build-unit page version {}; expected {}",
            page.version, SOURCE_PACK_LIBRARY_BUILD_UNIT_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(library_partition_contract_error(format!(
            "build-unit page {} target {:?} does not match requested target {:?}",
            page.partition_index, page.target, target
        )));
    }
    if let Some(expected_partition_index) = expected_partition_index {
        if page.partition_index != expected_partition_index {
            return Err(library_partition_contract_error(format!(
                "loaded build-unit page {} but expected {}",
                page.partition_index, expected_partition_index
            )));
        }
    }
    if page.source_file_count == 0 {
        return Err(library_partition_contract_error(format!(
            "build-unit page {} has no source files",
            page.partition_index
        )));
    }
    if page.dependency_library_ids.len() > SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE {
        return Err(library_partition_contract_error(format!(
            "build-unit page {} stores {} inline dependency records, exceeding record cap {}",
            page.partition_index,
            page.dependency_library_ids.len(),
            SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE
        )));
    }
    if page.frontend_units.len() > SOURCE_PACK_LIBRARY_BUILD_UNIT_INLINE_DEFAULT_RECORD_CAP {
        return Err(library_partition_contract_error(format!(
            "build-unit page {} stores {} inline frontend-unit records, exceeding record cap {}",
            page.partition_index,
            page.frontend_units.len(),
            SOURCE_PACK_LIBRARY_BUILD_UNIT_INLINE_DEFAULT_RECORD_CAP
        )));
    }
    if page.codegen_units.len() > SOURCE_PACK_LIBRARY_BUILD_UNIT_INLINE_DEFAULT_RECORD_CAP {
        return Err(library_partition_contract_error(format!(
            "build-unit page {} stores {} inline codegen-unit records, exceeding record cap {}",
            page.partition_index,
            page.codegen_units.len(),
            SOURCE_PACK_LIBRARY_BUILD_UNIT_INLINE_DEFAULT_RECORD_CAP
        )));
    }
    let codegen_unit_count = library_build_unit_page_codegen_unit_count(page);
    let frontend_unit_count = library_build_unit_page_frontend_unit_count(page);
    if frontend_unit_count == 0 {
        return Err(library_partition_contract_error(format!(
            "build-unit page {} has no frontend units",
            page.partition_index
        )));
    }
    if codegen_unit_count == 0 {
        return Err(library_partition_contract_error(format!(
            "build-unit page {} has no codegen units",
            page.partition_index
        )));
    }
    if !page.frontend_units.is_empty() && page.frontend_units.len() != frontend_unit_count {
        return Err(library_partition_contract_error(format!(
            "build-unit page {} has {} inline frontend units but frontend_unit_count {}",
            page.partition_index,
            page.frontend_units.len(),
            frontend_unit_count
        )));
    }
    if !page.codegen_units.is_empty() && page.codegen_units.len() != codegen_unit_count {
        return Err(library_partition_contract_error(format!(
            "build-unit page {} has {} inline codegen units but codegen_unit_count {}",
            page.partition_index,
            page.codegen_units.len(),
            codegen_unit_count
        )));
    }
    if page.limits != page.limits.normalized() {
        return Err(library_partition_contract_error(format!(
            "build-unit page {} has unnormalized limits {:?}",
            page.partition_index, page.limits
        )));
    }

    let source_end = page
        .first_source_index
        .checked_add(page.source_file_count)
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "build-unit page {} source range overflows",
                page.partition_index
            ))
        })?;
    let frontend_end = page
        .frontend_unit
        .first_source_index
        .checked_add(page.frontend_unit.source_file_count)
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "build-unit page {} frontend source range overflows",
                page.partition_index
            ))
        })?;
    if page.frontend_unit.library_id != page.library_id
        || page.frontend_unit.first_source_index != page.first_source_index
        || page.frontend_unit.source_file_count != page.source_file_count
        || page.frontend_unit.source_bytes != page.source_byte_count
        || page.frontend_unit.source_lines != page.source_line_count
        || frontend_end != source_end
    {
        return Err(library_partition_contract_error(format!(
            "build-unit page {} frontend unit does not match library partition",
            page.partition_index
        )));
    }

    if !page.frontend_units.is_empty() {
        let mut expected_source_index = page.first_source_index;
        let mut source_byte_count = 0usize;
        let mut source_line_count = 0usize;
        for (position, unit) in page.frontend_units.iter().enumerate() {
            validate_frontend_unit_shape(
                unit,
                page.target,
                page.partition_index,
                page.library_id,
                page.limits,
                position,
            )?;
            if unit.first_source_index != expected_source_index {
                return Err(library_partition_contract_error(format!(
                    "build-unit page {} frontend unit {} starts at source {}, expected {}",
                    page.partition_index,
                    unit.unit_index,
                    unit.first_source_index,
                    expected_source_index
                )));
            }
            expected_source_index = expected_source_index
                .checked_add(unit.source_file_count)
                .ok_or_else(|| {
                    library_partition_contract_error(format!(
                        "build-unit page {} frontend unit {} source range overflows",
                        page.partition_index, unit.unit_index
                    ))
                })?;
            source_byte_count = source_byte_count
                .checked_add(unit.source_bytes)
                .ok_or_else(|| {
                    library_partition_contract_error(format!(
                        "build-unit page {} frontend byte count overflows",
                        page.partition_index
                    ))
                })?;
            source_line_count = source_line_count
                .checked_add(unit.source_lines)
                .ok_or_else(|| {
                    library_partition_contract_error(format!(
                        "build-unit page {} frontend source-line count overflows",
                        page.partition_index
                    ))
                })?;
        }
        if expected_source_index != source_end {
            return Err(library_partition_contract_error(format!(
                "build-unit page {} frontend source range ends at {}, expected {}",
                page.partition_index, expected_source_index, source_end
            )));
        }
        if source_byte_count != page.source_byte_count {
            return Err(library_partition_contract_error(format!(
                "build-unit page {} frontend byte total {} does not match source_byte_count {}",
                page.partition_index, source_byte_count, page.source_byte_count
            )));
        }
        if source_line_count != page.source_line_count {
            return Err(library_partition_contract_error(format!(
                "build-unit page {} frontend source-line total {} does not match source_line_count {}",
                page.partition_index, source_line_count, page.source_line_count
            )));
        }
    }

    if !page.codegen_units.is_empty() {
        let mut expected_source_index = page.first_source_index;
        let mut source_byte_count = 0usize;
        let mut source_line_count = 0usize;
        for (position, unit) in page.codegen_units.iter().enumerate() {
            validate_codegen_unit_shape(
                unit,
                page.target,
                page.partition_index,
                page.library_id,
                page.limits,
                position,
            )?;
            if unit.first_source_index != expected_source_index {
                return Err(library_partition_contract_error(format!(
                    "build-unit page {} codegen unit {} starts at source {}, expected {}",
                    page.partition_index,
                    unit.unit_index,
                    unit.first_source_index,
                    expected_source_index
                )));
            }
            expected_source_index = expected_source_index
                .checked_add(unit.source_file_count)
                .ok_or_else(|| {
                    library_partition_contract_error(format!(
                        "build-unit page {} codegen unit {} source range overflows",
                        page.partition_index, unit.unit_index
                    ))
                })?;
            source_byte_count = source_byte_count
                .checked_add(unit.source_bytes)
                .ok_or_else(|| {
                    library_partition_contract_error(format!(
                        "build-unit page {} codegen byte count overflows",
                        page.partition_index
                    ))
                })?;
            source_line_count = source_line_count
                .checked_add(unit.source_lines)
                .ok_or_else(|| {
                    library_partition_contract_error(format!(
                        "build-unit page {} codegen source-line count overflows",
                        page.partition_index
                    ))
                })?;
        }
        if expected_source_index != source_end {
            return Err(library_partition_contract_error(format!(
                "build-unit page {} codegen source range ends at {}, expected {}",
                page.partition_index, expected_source_index, source_end
            )));
        }
        if source_byte_count != page.source_byte_count {
            return Err(library_partition_contract_error(format!(
                "build-unit page {} codegen byte total {} does not match source_byte_count {}",
                page.partition_index, source_byte_count, page.source_byte_count
            )));
        }
        if source_line_count != page.source_line_count {
            return Err(library_partition_contract_error(format!(
                "build-unit page {} codegen source-line total {} does not match source_line_count {}",
                page.partition_index, source_line_count, page.source_line_count
            )));
        }
    }

    let mut dependency_ids = BTreeSet::new();
    for dependency_library_id in &page.dependency_library_ids {
        if *dependency_library_id == page.library_id {
            return Err(library_partition_contract_error(format!(
                "build-unit page {} library {} depends on itself",
                page.partition_index, page.library_id
            )));
        }
        if !dependency_ids.insert(*dependency_library_id) {
            return Err(library_partition_contract_error(format!(
                "build-unit page {} contains duplicate dependency library {}",
                page.partition_index, dependency_library_id
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_frontend_unit_shape(
    unit: &FrontendUnit,
    _target: SourcePackArtifactTarget,
    partition_index: usize,
    library_id: u32,
    limits: CodegenUnitLimits,
    expected_unit_index: usize,
) -> Result<(), CompileError> {
    if unit.unit_index != expected_unit_index {
        return Err(library_partition_contract_error(format!(
            "build-unit page {partition_index} frontend unit entry {expected_unit_index} has unit_index {}",
            unit.unit_index
        )));
    }
    if unit.library_id != library_id {
        return Err(library_partition_contract_error(format!(
            "build-unit page {partition_index} frontend unit {} has library {}, expected {}",
            unit.unit_index, unit.library_id, library_id
        )));
    }
    if unit.source_file_count == 0 {
        return Err(library_partition_contract_error(format!(
            "build-unit page {partition_index} frontend unit {} has no source files",
            unit.unit_index
        )));
    }
    if !unit.oversized_source_file
        && (unit.source_file_count > limits.max_source_files
            || unit.source_bytes > limits.max_source_bytes)
    {
        return Err(library_partition_contract_error(format!(
            "build-unit page {partition_index} frontend unit {} exceeds limits {:?}",
            unit.unit_index, limits
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_frontend_unit_page(
    page: &SourcePackLibraryFrontendUnitPage,
    target: SourcePackArtifactTarget,
    expected_partition_index: Option<usize>,
    expected_frontend_unit_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_LIBRARY_FRONTEND_UNIT_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library frontend-unit page version {}; expected {}",
            page.version, SOURCE_PACK_LIBRARY_FRONTEND_UNIT_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(library_partition_contract_error(format!(
            "frontend-unit page {}:{} target {:?} does not match requested target {:?}",
            page.partition_index, page.frontend_unit_index, page.target, target
        )));
    }
    if let Some(expected_partition_index) = expected_partition_index {
        if page.partition_index != expected_partition_index {
            return Err(library_partition_contract_error(format!(
                "loaded frontend-unit page partition {} but expected {}",
                page.partition_index, expected_partition_index
            )));
        }
    }
    if let Some(expected_frontend_unit_index) = expected_frontend_unit_index {
        if page.frontend_unit_index != expected_frontend_unit_index {
            return Err(library_partition_contract_error(format!(
                "loaded frontend-unit page {} but expected {}",
                page.frontend_unit_index, expected_frontend_unit_index
            )));
        }
    }
    if page.frontend_unit_count == 0 || page.frontend_unit_index >= page.frontend_unit_count {
        return Err(library_partition_contract_error(format!(
            "frontend-unit page {}:{} has invalid count {}",
            page.partition_index, page.frontend_unit_index, page.frontend_unit_count
        )));
    }
    if page.limits != page.limits.normalized() {
        return Err(library_partition_contract_error(format!(
            "frontend-unit page {}:{} has unnormalized limits {:?}",
            page.partition_index, page.frontend_unit_index, page.limits
        )));
    }
    validate_frontend_unit_shape(
        &page.unit,
        page.target,
        page.partition_index,
        page.library_id,
        page.limits,
        page.frontend_unit_index,
    )?;
    Ok(())
}

pub(in crate::compiler) fn validate_codegen_unit_shape(
    unit: &CodegenUnit,
    _target: SourcePackArtifactTarget,
    partition_index: usize,
    library_id: u32,
    limits: CodegenUnitLimits,
    expected_unit_index: usize,
) -> Result<(), CompileError> {
    if unit.unit_index != expected_unit_index {
        return Err(library_partition_contract_error(format!(
            "build-unit page {partition_index} codegen unit entry {expected_unit_index} has unit_index {}",
            unit.unit_index
        )));
    }
    if unit.library_id != library_id {
        return Err(library_partition_contract_error(format!(
            "build-unit page {partition_index} codegen unit {} has library {}, expected {}",
            unit.unit_index, unit.library_id, library_id
        )));
    }
    if unit.source_file_count == 0 {
        return Err(library_partition_contract_error(format!(
            "build-unit page {partition_index} codegen unit {} has no source files",
            unit.unit_index
        )));
    }
    if !unit.oversized_source_file
        && (unit.source_file_count > limits.max_source_files
            || unit.source_bytes > limits.max_source_bytes)
    {
        return Err(library_partition_contract_error(format!(
            "build-unit page {partition_index} codegen unit {} exceeds limits {:?}",
            unit.unit_index, limits
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_codegen_unit_page(
    page: &SourcePackLibraryCodegenUnitPage,
    target: SourcePackArtifactTarget,
    expected_partition_index: Option<usize>,
    expected_codegen_unit_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_LIBRARY_CODEGEN_UNIT_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library codegen-unit page version {}; expected {}",
            page.version, SOURCE_PACK_LIBRARY_CODEGEN_UNIT_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(library_partition_contract_error(format!(
            "codegen-unit page {}:{} target {:?} does not match requested target {:?}",
            page.partition_index, page.codegen_unit_index, page.target, target
        )));
    }
    if let Some(expected_partition_index) = expected_partition_index {
        if page.partition_index != expected_partition_index {
            return Err(library_partition_contract_error(format!(
                "loaded codegen-unit page partition {} but expected {}",
                page.partition_index, expected_partition_index
            )));
        }
    }
    if let Some(expected_codegen_unit_index) = expected_codegen_unit_index {
        if page.codegen_unit_index != expected_codegen_unit_index {
            return Err(library_partition_contract_error(format!(
                "loaded codegen-unit page {} but expected {}",
                page.codegen_unit_index, expected_codegen_unit_index
            )));
        }
    }
    if page.codegen_unit_count == 0 || page.codegen_unit_index >= page.codegen_unit_count {
        return Err(library_partition_contract_error(format!(
            "codegen-unit page {}:{} has invalid count {}",
            page.partition_index, page.codegen_unit_index, page.codegen_unit_count
        )));
    }
    if page.limits != page.limits.normalized() {
        return Err(library_partition_contract_error(format!(
            "codegen-unit page {}:{} has unnormalized limits {:?}",
            page.partition_index, page.codegen_unit_index, page.limits
        )));
    }
    validate_codegen_unit_shape(
        &page.unit,
        page.target,
        page.partition_index,
        page.library_id,
        page.limits,
        page.codegen_unit_index,
    )?;
    Ok(())
}
