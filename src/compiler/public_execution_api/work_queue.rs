use super::*;

mod progress;
pub(in crate::compiler) use progress::{
    completed_hierarchical_link_output_path,
    final_linked_output_for_progress,
};
pub use progress::{work_queue_progress_snapshot, work_queue_progress_snapshot_at};

mod completion;
pub(in crate::compiler) use completion::{
    ChangedProgressPages,
    record_work_item_dependents_completed,
    release_work_queue_consumed_outputs_after_completion,
    work_queue_singleton_artifact_batch_index_for_item,
};
mod claims;
pub(in crate::compiler) use claims::work_queue_record_artifact_batch_claim;
pub use claims::{
    claim_ready_artifact_work_queue_item,
    claim_ready_work_queue_item,
    complete_claimed_work_queue_item,
};

mod execute_sync;
pub use execute_sync::{
    execute_claimed_artifact_path_work_queue_item,
    execute_claimed_artifact_work_queue_item,
    execute_claimed_link_path_work_queue_item,
    execute_claimed_link_work_queue_item,
    execute_claimed_path_work_queue_item,
    execute_claimed_work_queue_item,
    run_path_work_queue,
    run_path_work_queue_at,
    run_work_queue,
    step_path_work_queue,
    step_work_queue,
};
pub(in crate::compiler) use execute_sync::{
    work_queue_item_claim_lease_expires_by,
    work_queue_item_completed_or_claimed_by,
};

mod execute_async;
pub use execute_async::{
    execute_claimed_artifact_path_work_queue_item_async,
    execute_claimed_link_path_work_queue_item_async,
    execute_claimed_path_work_queue_item_async,
    run_path_work_queue_async,
    run_path_work_queue_async_at,
    step_path_work_queue_async,
};
