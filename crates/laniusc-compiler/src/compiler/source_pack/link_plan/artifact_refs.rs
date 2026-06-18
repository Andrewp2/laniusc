use super::super::*;

/// Builds a validated artifact-ref page from an artifact reference and source totals.
pub(in crate::compiler) fn build_artifact_ref_page(
    target: SourcePackArtifactTarget,
    artifact_ref: SourcePackArtifactRef,
    source_bytes: usize,
    source_file_count: usize,
    source_lines: usize,
) -> Result<SourcePackBuildArtifactRefPage, CompileError> {
    let page = SourcePackBuildArtifactRefPage {
        version: SOURCE_PACK_BUILD_ARTIFACT_REF_PAGE_VERSION,
        target,
        artifact_index: artifact_ref.artifact_index,
        artifact_ref,
        source_bytes,
        source_file_count,
        source_lines,
    };
    validate_artifact_ref_page(
        &page,
        target,
        page.artifact_index.saturating_add(1),
        Some(page.artifact_index),
    )?;
    Ok(page)
}

/// Loads an artifact-ref page after validating the containing index.
pub(in crate::compiler) fn load_artifact_ref_page_for_index(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    artifact_index: usize,
) -> Result<SourcePackBuildArtifactRefPage, CompileError> {
    validate_artifact_ref_index(artifact_ref_index, target)?;
    store.load_build_artifact_ref_page_for_target(
        target,
        artifact_index,
        artifact_ref_index.artifact_count,
    )
}

/// Loads one artifact ref by index and verifies its kind.
pub(in crate::compiler) fn artifact_ref_for_index_from_stored_pages(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    artifact_index: usize,
    kind: SourcePackArtifactKind,
) -> Result<SourcePackArtifactRef, CompileError> {
    let page = load_artifact_ref_page_for_index(store, target, artifact_ref_index, artifact_index)?;
    if page.artifact_ref.kind != kind {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref page {} has kind {:?}; expected {:?}",
            artifact_index, page.artifact_ref.kind, kind
        )));
    }
    Ok(page.artifact_ref)
}

/// Loads artifact refs for a list of artifact indices from stored pages.
pub(in crate::compiler) fn artifact_refs_for_indices_from_stored_pages(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    artifact_indices: &[usize],
) -> Result<Vec<SourcePackArtifactRef>, CompileError> {
    artifact_indices
        .iter()
        .map(|&artifact_index| {
            Ok(
                load_artifact_ref_page_for_index(
                    store,
                    target,
                    artifact_ref_index,
                    artifact_index,
                )?
                .artifact_ref,
            )
        })
        .collect()
}
