use super::*;

fn checked_first_record_position(
    label: &str,
    page_index: usize,
    page_size: usize,
) -> Result<usize, CompileError> {
    page_index.checked_mul(page_size).ok_or_else(|| {
        library_partition_contract_error(format!(
            "{label} page index {page_index} overflows first record position with page size {page_size}"
        ))
    })
}

mod partitions;
pub(in crate::compiler) use partitions::*;

mod source_files;
pub(in crate::compiler) use source_files::*;

mod build_units;
pub(in crate::compiler) use build_units::*;

mod schedule;
pub(in crate::compiler) use schedule::*;

mod jobs;
pub(in crate::compiler) use jobs::*;

mod link_plan;
pub(in crate::compiler) use link_plan::*;

mod link_execution;
pub(in crate::compiler) use link_execution::*;

mod work_queue;
pub(in crate::compiler) use work_queue::*;
