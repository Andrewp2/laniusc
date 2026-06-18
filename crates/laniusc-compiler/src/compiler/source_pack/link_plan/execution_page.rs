use super::super::*;

/// Returns the filesystem key for a hierarchical partial-link output.
pub(in crate::compiler) fn hierarchical_link_partial_output_key(
    target: SourcePackArtifactTarget,
    group_index: usize,
    job_index: usize,
) -> String {
    let key = format!("partial-link/group-{group_index:08}/job-{job_index:08}");
    match target.key_prefix() {
        Some(prefix) => format!("{prefix}/{key}"),
        None => key,
    }
}

/// Returns the effective interface-input count for a hierarchical link page.
///
/// The explicit count is compared with inline refs plus compact job-index ranges
/// so compact and expanded records summarize consistently.
pub(in crate::compiler) fn hierarchical_link_execution_input_interface_count(
    page: &SourcePackHierarchicalLinkExecutionPage,
) -> usize {
    page.input_interface_count
        .max(
            page.input_interfaces
                .len()
                .saturating_add(job_index_range_dependency_count(
                    &page.input_interface_ranges,
                )),
        )
}

/// Returns the effective object-input count for a hierarchical link page.
pub(in crate::compiler) fn hierarchical_link_execution_input_object_count(
    page: &SourcePackHierarchicalLinkExecutionPage,
) -> usize {
    page.input_object_count.max(page.input_objects.len())
}

/// Returns the effective partial-link input group count for a reduce page.
pub(in crate::compiler) fn hierarchical_link_execution_input_group_count(
    page: &SourcePackHierarchicalLinkExecutionPage,
) -> usize {
    page.input_group_count.max(page.input_group_indices.len())
}
