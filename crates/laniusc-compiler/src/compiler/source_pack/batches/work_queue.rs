use super::*;

/// Returns the effective dependency count for a work-queue page.
pub(in crate::compiler) fn work_queue_page_dependency_count(
    page: &SourcePackWorkQueuePage,
) -> usize {
    page.dependency_item_count
        .max(page.dependency_item_indices.len())
        .saturating_add(job_index_range_dependency_count(
            &page.dependency_item_ranges,
        ))
}

/// Returns the effective dependent count for a work-queue page.
pub(in crate::compiler) fn work_queue_page_dependent_count(
    page: &SourcePackWorkQueuePage,
) -> usize {
    page.dependent_item_count
        .max(page.dependent_item_indices.len())
        .saturating_add(job_index_range_dependency_count(
            &page.dependent_item_ranges,
        ))
}
