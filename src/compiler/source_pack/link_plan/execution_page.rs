use super::super::*;

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

pub(in crate::compiler) fn hierarchical_link_execution_input_object_count(
    page: &SourcePackHierarchicalLinkExecutionPage,
) -> usize {
    page.input_object_count.max(page.input_objects.len())
}

pub(in crate::compiler) fn hierarchical_link_execution_input_group_count(
    page: &SourcePackHierarchicalLinkExecutionPage,
) -> usize {
    page.input_group_count.max(page.input_group_indices.len())
}
