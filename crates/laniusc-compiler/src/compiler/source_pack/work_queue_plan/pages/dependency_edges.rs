use std::collections::BTreeSet;

use super::super::super::{
    FilesystemArtifactStore,
    SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE,
    SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_PAGE_VERSION,
    SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE,
    SOURCE_PACK_WORK_QUEUE_DEPENDENTS_PAGE_VERSION,
    SourcePackArtifactTarget,
    SourcePackJobIndexRange,
    SourcePackLibraryScheduleIndex,
    SourcePackWorkQueueDependenciesPage,
    SourcePackWorkQueueDependentsPage,
    SourcePackWorkQueuePage,
    for_each_schedule_job_explicit_dependency_index,
    library_partition_contract_error,
    validate_work_queue_dependencies_page,
    validate_work_queue_dependents_page,
    validate_work_queue_page,
};
use crate::compiler::CompileError;

pub(in crate::compiler) fn write_work_queue_dependencies_from_stored_schedule_job(
    store: &FilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    job_index: usize,
    writer: &mut WorkQueueDependencyPageWriter<'_>,
) -> Result<(), CompileError> {
    let job_page = store.load_library_schedule_job_page_for_target(
        schedule_index.target,
        job_index,
        schedule_index.job_count,
    )?;
    for_each_schedule_job_explicit_dependency_index(
        store,
        schedule_index,
        &job_page,
        |dependency_job_index| writer.push(dependency_job_index),
    )?;
    for range in &job_page.dependency_job_ranges {
        writer.push_range(range.first_job_index, range.job_count)?;
    }
    Ok(())
}

pub(in crate::compiler) fn work_queue_append_dependent_page(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    dependency_item_index: usize,
    dependent_item_index: usize,
    work_item_count: usize,
) -> Result<(), CompileError> {
    if dependency_item_index >= work_item_count || dependent_item_index >= work_item_count {
        return Err(library_partition_contract_error(format!(
            "work queue dependent edge {dependency_item_index}->{dependent_item_index} exceeds item count {work_item_count}"
        )));
    }
    if dependent_item_index <= dependency_item_index {
        return Err(library_partition_contract_error(format!(
            "work queue dependent edge {dependency_item_index}->{dependent_item_index} is not forward"
        )));
    }
    let mut dependency_page =
        store.load_work_queue_page_for_target(target, dependency_item_index)?;
    if !dependency_page.dependent_item_indices.is_empty() {
        return Err(library_partition_contract_error(format!(
            "work queue page {dependency_item_index} mixes inline dependents with stored dependent pages"
        )));
    }
    if dependency_page.dependent_item_ranges.iter().any(|range| {
        range
            .iter()
            .is_some_and(|indices| indices.contains(&dependent_item_index))
    }) {
        return Err(library_partition_contract_error(format!(
            "work queue page {dependency_item_index} contains duplicate ranged dependent item {dependent_item_index}"
        )));
    }

    let dependent_position = dependency_page.dependent_item_count;
    let page_index = dependent_position / SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE;
    let is_new_dependents_page =
        dependent_position % SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE == 0;
    let mut dependents_page = if is_new_dependents_page {
        SourcePackWorkQueueDependentsPage {
            version: SOURCE_PACK_WORK_QUEUE_DEPENDENTS_PAGE_VERSION,
            target,
            item_index: dependency_item_index,
            page_index,
            first_dependent_position: page_index
                .saturating_mul(SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE),
            dependent_count: 0,
            dependent_item_indices: Vec::new(),
        }
    } else {
        store.load_work_queue_dependents_page_for_target(
            target,
            dependency_item_index,
            page_index,
        )?
    };

    dependents_page
        .dependent_item_indices
        .push(dependent_item_index);
    dependents_page.dependent_count = dependents_page.dependent_item_indices.len();
    validate_work_queue_dependents_page(
        &dependents_page,
        target,
        dependency_item_index,
        page_index,
    )?;
    store.store_work_queue_dependents_page(&dependents_page)?;

    dependency_page.dependent_item_count = dependency_page.dependent_item_count.saturating_add(1);
    dependency_page.dependent_page_count = dependency_page
        .dependent_item_count
        .div_ceil(SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE);
    validate_work_queue_page(&dependency_page, target, Some(dependency_item_index))?;
    store.store_work_queue_page(&dependency_page)?;
    Ok(())
}

pub(in crate::compiler) fn work_queue_try_append_dependent_range(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    dependency_item_index: usize,
    first_dependent_item_index: usize,
    dependent_item_count: usize,
    work_item_count: usize,
) -> Result<bool, CompileError> {
    if dependent_item_count == 0 {
        return Ok(true);
    }
    let end_dependent_item_index =
        first_dependent_item_index
            .checked_add(dependent_item_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "work queue dependent range {dependency_item_index}->{first_dependent_item_index}+{dependent_item_count} overflows"
                ))
            })?;
    if dependency_item_index >= work_item_count || end_dependent_item_index > work_item_count {
        return Err(library_partition_contract_error(format!(
            "work queue dependent range {dependency_item_index}->{first_dependent_item_index}..{end_dependent_item_index} exceeds item count {work_item_count}"
        )));
    }
    if first_dependent_item_index <= dependency_item_index {
        return Err(library_partition_contract_error(format!(
            "work queue dependent range {dependency_item_index}->{first_dependent_item_index}..{end_dependent_item_index} is not forward"
        )));
    }
    let mut dependency_page =
        store.load_work_queue_page_for_target(target, dependency_item_index)?;
    if !dependency_page.dependent_item_indices.is_empty() {
        return Err(library_partition_contract_error(format!(
            "work queue page {dependency_item_index} mixes inline dependents with stored dependent ranges"
        )));
    }
    if let Some(range) = dependency_page.dependent_item_ranges.iter().find(|range| {
        range.end_job_index().is_some_and(|range_end| {
            first_dependent_item_index < range_end
                && range.first_job_index < end_dependent_item_index
        })
    }) {
        let duplicate_end = range
            .end_job_index()
            .unwrap_or(range.first_job_index.saturating_add(range.job_count));
        return Err(library_partition_contract_error(format!(
            "work queue page {dependency_item_index} dependent range {first_dependent_item_index}..{end_dependent_item_index} overlaps existing range {}..{}",
            range.first_job_index, duplicate_end
        )));
    }
    if !try_push_dependent_item_range(
        &mut dependency_page.dependent_item_ranges,
        dependency_item_index,
        first_dependent_item_index,
        dependent_item_count,
    )? {
        return Ok(false);
    }
    validate_work_queue_page(&dependency_page, target, Some(dependency_item_index))?;
    store.store_work_queue_page(&dependency_page)?;
    Ok(true)
}

pub(in crate::compiler) fn append_work_queue_dependent_range_to_dependency_range(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    first_dependency_item_index: usize,
    dependency_item_count: usize,
    first_dependent_item_index: usize,
    dependent_item_count: usize,
    work_item_count: usize,
) -> Result<(), CompileError> {
    if dependency_item_count == 0 || dependent_item_count == 0 {
        return Ok(());
    }
    let dependency_end = first_dependency_item_index
        .checked_add(dependency_item_count)
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "work queue reverse dependency range {first_dependency_item_index}+{dependency_item_count} overflows"
            ))
        })?;
    let dependent_end = first_dependent_item_index
        .checked_add(dependent_item_count)
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "work queue reverse dependent range {first_dependent_item_index}+{dependent_item_count} overflows"
            ))
        })?;
    if dependency_end > work_item_count || dependent_end > work_item_count {
        return Err(library_partition_contract_error(format!(
            "work queue reverse range dependencies {}..{} dependents {}..{} exceed item count {}",
            first_dependency_item_index,
            dependency_end,
            first_dependent_item_index,
            dependent_end,
            work_item_count
        )));
    }

    for dependency_item_index in first_dependency_item_index..dependency_end {
        if work_queue_try_append_dependent_range(
            store,
            target,
            dependency_item_index,
            first_dependent_item_index,
            dependent_item_count,
            work_item_count,
        )? {
            continue;
        }
        for dependent_item_index in first_dependent_item_index..dependent_end {
            work_queue_append_dependent_page(
                store,
                target,
                dependency_item_index,
                dependent_item_index,
                work_item_count,
            )?;
        }
    }
    Ok(())
}

pub(in crate::compiler) struct WorkQueueDependencyPageWriter<'a> {
    pub(in crate::compiler) store: &'a FilesystemArtifactStore,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) item_index: usize,
    pub(in crate::compiler) work_item_count: usize,
    pub(in crate::compiler) page_index: usize,
    pub(in crate::compiler) first_dependency_position: usize,
    pub(in crate::compiler) dependency_item_count: usize,
    pub(in crate::compiler) dependency_item_ranges: Vec<SourcePackJobIndexRange>,
    pub(in crate::compiler) seen_dependency_item_indices: BTreeSet<usize>,
    pub(in crate::compiler) current_dependency_item_indices: Vec<usize>,
}

impl<'a> WorkQueueDependencyPageWriter<'a> {
    pub(in crate::compiler) fn new(
        store: &'a FilesystemArtifactStore,
        target: SourcePackArtifactTarget,
        item_index: usize,
        work_item_count: usize,
    ) -> Self {
        Self {
            store,
            target,
            item_index,
            work_item_count,
            page_index: 0,
            first_dependency_position: 0,
            dependency_item_count: 0,
            dependency_item_ranges: Vec::new(),
            seen_dependency_item_indices: BTreeSet::new(),
            current_dependency_item_indices: Vec::with_capacity(
                SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE,
            ),
        }
    }

    pub(in crate::compiler) fn push(
        &mut self,
        dependency_item_index: usize,
    ) -> Result<(), CompileError> {
        self.push_impl(dependency_item_index, true)
    }

    pub(in crate::compiler) fn push_impl(
        &mut self,
        dependency_item_index: usize,
        record_reverse_dependent: bool,
    ) -> Result<(), CompileError> {
        if dependency_item_index >= self.item_index {
            return Err(library_partition_contract_error(format!(
                "work queue page {} depends on non-prior item {}",
                self.item_index, dependency_item_index
            )));
        }
        if self.dependency_item_ranges.iter().any(|range| {
            range
                .iter()
                .is_some_and(|indices| indices.contains(&dependency_item_index))
        }) {
            return Err(library_partition_contract_error(format!(
                "work queue page {} contains duplicate ranged dependency item {}",
                self.item_index, dependency_item_index
            )));
        }
        if !self
            .seen_dependency_item_indices
            .insert(dependency_item_index)
        {
            return Err(library_partition_contract_error(format!(
                "work queue page {} contains duplicate dependency item {}",
                self.item_index, dependency_item_index
            )));
        }
        self.current_dependency_item_indices
            .push(dependency_item_index);
        if self.current_dependency_item_indices.len()
            == SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE
        {
            self.flush()?;
        }
        if record_reverse_dependent {
            work_queue_append_dependent_page(
                self.store,
                self.target,
                dependency_item_index,
                self.item_index,
                self.work_item_count,
            )?;
        }
        Ok(())
    }

    pub(in crate::compiler) fn flush(&mut self) -> Result<(), CompileError> {
        if self.current_dependency_item_indices.is_empty() {
            return Ok(());
        }
        let dependency_item_indices = std::mem::take(&mut self.current_dependency_item_indices);
        let dependency_page = SourcePackWorkQueueDependenciesPage {
            version: SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_PAGE_VERSION,
            target: self.target,
            item_index: self.item_index,
            page_index: self.page_index,
            first_dependency_position: self.first_dependency_position,
            dependency_count: dependency_item_indices.len(),
            dependency_item_indices,
        };
        validate_work_queue_dependencies_page(
            &dependency_page,
            self.target,
            self.item_index,
            self.page_index,
        )?;
        self.store
            .store_work_queue_dependencies_page(&dependency_page)?;
        self.dependency_item_count = self
            .dependency_item_count
            .saturating_add(dependency_page.dependency_count);
        self.first_dependency_position = self
            .first_dependency_position
            .saturating_add(dependency_page.dependency_count);
        self.page_index += 1;
        Ok(())
    }

    pub(in crate::compiler) fn push_range(
        &mut self,
        first_item_index: usize,
        item_count: usize,
    ) -> Result<(), CompileError> {
        self.push_range_impl(first_item_index, item_count, true)
    }

    pub(in crate::compiler) fn push_range_impl(
        &mut self,
        first_item_index: usize,
        item_count: usize,
        record_reverse_dependents: bool,
    ) -> Result<(), CompileError> {
        if item_count == 0 {
            return Ok(());
        }
        let end_item_index = first_item_index.checked_add(item_count).ok_or_else(|| {
            library_partition_contract_error(format!(
                "work queue page {} dependency item range {}+{} overflows",
                self.item_index, first_item_index, item_count
            ))
        })?;
        if end_item_index > self.item_index {
            return Err(library_partition_contract_error(format!(
                "work queue page {} depends on non-prior item range {}..{}",
                self.item_index, first_item_index, end_item_index
            )));
        }
        if let Some(duplicate) = self
            .seen_dependency_item_indices
            .range(first_item_index..end_item_index)
            .next()
        {
            return Err(library_partition_contract_error(format!(
                "work queue page {} dependency range {}..{} duplicates explicit dependency item {}",
                self.item_index, first_item_index, end_item_index, duplicate
            )));
        }
        if try_push_dependency_item_range(
            &mut self.dependency_item_ranges,
            self.item_index,
            first_item_index,
            item_count,
        )? {
            if record_reverse_dependents {
                append_work_queue_dependent_range_to_dependency_range(
                    self.store,
                    self.target,
                    first_item_index,
                    item_count,
                    self.item_index,
                    1,
                    self.work_item_count,
                )?;
            }
            return Ok(());
        }

        for dependency_item_index in first_item_index..end_item_index {
            self.push_impl(dependency_item_index, record_reverse_dependents)?;
        }
        Ok(())
    }

    pub(in crate::compiler) fn finish(
        mut self,
    ) -> Result<(usize, usize, Vec<SourcePackJobIndexRange>), CompileError> {
        self.flush()?;
        Ok((
            self.dependency_item_count,
            self.page_index,
            self.dependency_item_ranges,
        ))
    }
}

pub(in crate::compiler) fn try_push_dependency_item_range(
    dependency_item_ranges: &mut Vec<SourcePackJobIndexRange>,
    item_index: usize,
    first_item_index: usize,
    item_count: usize,
) -> Result<bool, CompileError> {
    let end_item_index = first_item_index.checked_add(item_count).ok_or_else(|| {
        library_partition_contract_error(format!(
            "work queue page {item_index} dependency item range {first_item_index}+{item_count} overflows"
        ))
    })?;
    if end_item_index > item_index {
        return Err(library_partition_contract_error(format!(
            "work queue page {item_index} depends on non-prior item range {first_item_index}..{end_item_index}"
        )));
    }

    let mut merged_ranges = dependency_item_ranges.clone();
    merged_ranges.push(SourcePackJobIndexRange {
        first_job_index: first_item_index,
        job_count: item_count,
    });
    merged_ranges.sort_by_key(|range| range.first_job_index);

    let mut compact_ranges = Vec::<SourcePackJobIndexRange>::with_capacity(merged_ranges.len());
    for range in merged_ranges {
        let Some(range_end) = range.end_job_index() else {
            return Err(library_partition_contract_error(format!(
                "work queue page {item_index} dependency item range starting at {} overflows",
                range.first_job_index
            )));
        };
        if let Some(last) = compact_ranges.last_mut() {
            let Some(last_end) = last.end_job_index() else {
                return Err(library_partition_contract_error(format!(
                    "work queue page {item_index} dependency item range starting at {} overflows",
                    last.first_job_index
                )));
            };
            if range.first_job_index <= last_end {
                let compact_end = last_end.max(range_end);
                last.job_count = compact_end - last.first_job_index;
                continue;
            }
        }
        compact_ranges.push(range);
    }

    if compact_ranges.len() > SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE {
        return Ok(false);
    }
    *dependency_item_ranges = compact_ranges;
    Ok(true)
}

pub(in crate::compiler) fn try_push_dependent_item_range(
    dependent_item_ranges: &mut Vec<SourcePackJobIndexRange>,
    item_index: usize,
    first_item_index: usize,
    item_count: usize,
) -> Result<bool, CompileError> {
    let end_item_index = first_item_index.checked_add(item_count).ok_or_else(|| {
        library_partition_contract_error(format!(
            "work queue page {item_index} dependent item range {first_item_index}+{item_count} overflows"
        ))
    })?;
    if first_item_index <= item_index {
        return Err(library_partition_contract_error(format!(
            "work queue page {item_index} has non-later dependent item range {first_item_index}..{end_item_index}"
        )));
    }

    let mut merged_ranges = dependent_item_ranges.clone();
    merged_ranges.push(SourcePackJobIndexRange {
        first_job_index: first_item_index,
        job_count: item_count,
    });
    merged_ranges.sort_by_key(|range| range.first_job_index);

    let mut compact_ranges = Vec::<SourcePackJobIndexRange>::with_capacity(merged_ranges.len());
    for range in merged_ranges {
        let Some(range_end) = range.end_job_index() else {
            return Err(library_partition_contract_error(format!(
                "work queue page {item_index} dependent item range starting at {} overflows",
                range.first_job_index
            )));
        };
        if let Some(last) = compact_ranges.last_mut() {
            let Some(last_end) = last.end_job_index() else {
                return Err(library_partition_contract_error(format!(
                    "work queue page {item_index} dependent item range starting at {} overflows",
                    last.first_job_index
                )));
            };
            if range.first_job_index <= last_end {
                let compact_end = last_end.max(range_end);
                last.job_count = compact_end - last.first_job_index;
                continue;
            }
        }
        compact_ranges.push(range);
    }

    if compact_ranges.len() > SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE {
        return Ok(false);
    }
    *dependent_item_ranges = compact_ranges;
    Ok(true)
}

pub(in crate::compiler) fn store_work_queue_page_with_dependency_writer<F>(
    store: &FilesystemArtifactStore,
    page: &SourcePackWorkQueuePage,
    work_item_count: usize,
    mut write_dependencies: F,
) -> Result<SourcePackWorkQueuePage, CompileError>
where
    F: FnMut(&mut WorkQueueDependencyPageWriter<'_>) -> Result<(), CompileError>,
{
    validate_work_queue_page(page, page.target, Some(page.item_index))?;
    if page.item_index >= work_item_count {
        return Err(library_partition_contract_error(format!(
            "stored work queue page {} exceeds item count {}",
            page.item_index, work_item_count
        )));
    }
    let mut writer =
        WorkQueueDependencyPageWriter::new(store, page.target, page.item_index, work_item_count);
    write_dependencies(&mut writer)?;
    let (dependency_item_count, dependency_page_count, dependency_item_ranges) = writer.finish()?;
    let mut stored_page = page.clone();
    stored_page.dependency_item_indices.clear();
    stored_page.dependency_item_count = dependency_item_count;
    stored_page.dependency_page_count = dependency_page_count;
    stored_page.dependency_item_ranges = dependency_item_ranges;
    stored_page.dependent_item_indices.clear();
    stored_page.dependent_item_count = 0;
    stored_page.dependent_page_count = 0;
    stored_page.dependent_item_ranges.clear();
    validate_work_queue_page(&stored_page, page.target, Some(page.item_index))?;
    store.store_work_queue_page(&stored_page)?;
    Ok(stored_page)
}
