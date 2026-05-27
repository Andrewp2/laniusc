use super::*;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemArtifactPrepareResult {
    pub target: SourcePackArtifactTarget,
    pub artifact_root: PathBuf,
    pub source_file_count: usize,
    pub source_byte_count: usize,
    pub source_line_count: usize,
    pub library_count: usize,
    pub artifact_count: usize,
    pub scheduled_job_count: usize,
    pub batch_count: usize,
    pub initial_ready_batch_count: usize,
    pub first_ready_batch_index: Option<usize>,
    pub build_manifest_path: PathBuf,
    pub library_partition_index_path: PathBuf,
    pub library_partition_count: usize,
    pub library_source_file_page_count: usize,
    pub library_build_unit_page_count: usize,
    pub library_schedule_index_path: PathBuf,
    pub library_schedule_page_count: usize,
    pub hierarchical_link_plan_index_path: PathBuf,
    pub hierarchical_link_group_count: usize,
    pub hierarchical_link_execution_index_path: PathBuf,
    pub hierarchical_link_execution_group_count: usize,
    pub work_queue_index_path: PathBuf,
    pub work_queue_item_count: usize,
    pub work_queue_progress_index_path: PathBuf,
    pub work_queue_progress_page_count: usize,
    pub initial_ready_work_item_count: usize,
    pub first_ready_work_item_index: Option<usize>,
    pub artifact_manifest_path: PathBuf,
    pub artifact_shard_index_path: PathBuf,
    pub artifact_shard_count: usize,
    pub build_state_path: PathBuf,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SourcePackFilesystemArtifactBuildPrepareStage {
    LibrarySchedule,
    ArtifactRefs,
    JobBatches,
    LinkBatches,
    JobBatchDependents,
    ArtifactShards,
    HierarchicalLinkLeafGroups,
    HierarchicalLinkPlanReduceGroups,
    HierarchicalLinkExecution,
    WorkQueuePages,
    WorkQueueProgress,
    BuildManifests,
    BuildState,
    Complete,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemArtifactBuildPrepareStepResult {
    pub target: SourcePackArtifactTarget,
    pub complete: bool,
    pub stage: SourcePackFilesystemArtifactBuildPrepareStage,
    pub next_stage: SourcePackFilesystemArtifactBuildPrepareStage,
    pub new_item_count: usize,
    pub prepared: Option<SourcePackFilesystemArtifactPrepareResult>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemPreparedArtifactBuildSummary {
    pub target: SourcePackArtifactTarget,
    pub artifact_root: PathBuf,
    pub source_file_count: usize,
    pub source_byte_count: usize,
    pub source_line_count: usize,
    pub library_count: usize,
    pub scheduled_job_count: usize,
    pub frontend_job_count: usize,
    pub codegen_job_count: usize,
    pub batch_count: usize,
    pub dependency_edge_count: usize,
    pub artifact_count: usize,
    pub interface_artifact_count: usize,
    pub object_artifact_count: usize,
    pub artifact_shard_count: usize,
    pub hierarchical_link_execution_group_count: usize,
    pub final_output_key: String,
    pub work_queue_item_count: usize,
    pub work_queue_progress_page_count: usize,
    pub progress: SourcePackFilesystemWorkQueueProgressSnapshot,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemPreparedArtifactBuild {
    pub(in crate::compiler) artifact_root: PathBuf,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
}

impl SourcePackFilesystemPreparedArtifactBuild {
    pub fn new(artifact_root: impl Into<PathBuf>, target: SourcePackArtifactTarget) -> Self {
        Self {
            artifact_root: artifact_root.into(),
            target,
        }
    }

    pub fn generic(artifact_root: impl Into<PathBuf>) -> Self {
        Self::new(artifact_root, SourcePackArtifactTarget::Generic)
    }

    pub fn artifact_root(&self) -> &Path {
        &self.artifact_root
    }

    pub fn target(&self) -> SourcePackArtifactTarget {
        self.target
    }

    pub fn bounded_summary(
        &self,
        max_ready_items: usize,
    ) -> Result<SourcePackFilesystemPreparedArtifactBuildSummary, CompileError> {
        let store = SourcePackFilesystemArtifactStore::new(&self.artifact_root);
        let library_partitions = store.load_library_partition_index_for_target(self.target)?;
        let schedule = store.load_library_schedule_index_for_target(self.target)?;
        let job_batches = store.load_build_job_batch_page_index_for_target(self.target)?;
        let artifact_refs = store.load_build_artifact_ref_index_for_target(self.target)?;
        let artifact_shards = store.load_build_artifact_shard_index_for_target(self.target)?;
        let link_execution =
            store.load_hierarchical_link_execution_index_for_target(self.target)?;
        let progress_index = store.load_work_queue_progress_index_for_target(self.target)?;
        let progress = self.work_queue_progress_snapshot(max_ready_items)?;

        if library_partitions.partition_count != schedule.partition_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "prepared source-pack summary partition count mismatch: library index {} schedule {}",
                library_partitions.partition_count, schedule.partition_count
            )));
        }
        if schedule.job_count != job_batches.scheduled_job_count
            || schedule.job_count != artifact_shards.job_count
        {
            return Err(source_pack_library_partition_contract_error(format!(
                "prepared source-pack summary job count mismatch: schedule {} job batches {} shards {}",
                schedule.job_count, job_batches.scheduled_job_count, artifact_shards.job_count
            )));
        }
        if job_batches.batch_count != artifact_shards.job_batch_count {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "prepared source-pack summary batch count mismatch: job batches {} shards {}",
                job_batches.batch_count, artifact_shards.job_batch_count
            )));
        }
        if artifact_refs.artifact_count != artifact_shards.artifact_count {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "prepared source-pack summary artifact count mismatch: artifact refs {} shards {}",
                artifact_refs.artifact_count, artifact_shards.artifact_count
            )));
        }
        if library_partitions.source_file_count != artifact_refs.total_source_file_count
            || library_partitions.source_byte_count != artifact_refs.total_source_byte_count
            || library_partitions.source_line_count != artifact_refs.total_source_line_count
        {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "prepared source-pack summary source totals mismatch: library index files/bytes/lines {}/{}/{} artifact refs {}/{}/{}",
                library_partitions.source_file_count,
                library_partitions.source_byte_count,
                library_partitions.source_line_count,
                artifact_refs.total_source_file_count,
                artifact_refs.total_source_byte_count,
                artifact_refs.total_source_line_count
            )));
        }
        if progress_index.work_item_count != progress.work_item_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "prepared source-pack summary work item count mismatch: progress index {} snapshot {}",
                progress_index.work_item_count, progress.work_item_count
            )));
        }

        Ok(SourcePackFilesystemPreparedArtifactBuildSummary {
            target: self.target,
            artifact_root: self.artifact_root.clone(),
            source_file_count: library_partitions.source_file_count,
            source_byte_count: library_partitions.source_byte_count,
            source_line_count: library_partitions.source_line_count,
            library_count: library_partitions.partition_count,
            scheduled_job_count: schedule.job_count,
            frontend_job_count: schedule.frontend_job_count,
            codegen_job_count: schedule.codegen_job_count,
            batch_count: job_batches.batch_count,
            dependency_edge_count: job_batches.dependency_edge_count,
            artifact_count: artifact_refs.artifact_count,
            interface_artifact_count: artifact_refs.interface_artifact_count,
            object_artifact_count: artifact_refs.object_artifact_count,
            artifact_shard_count: artifact_shards.shard_count(),
            hierarchical_link_execution_group_count: link_execution.link_group_count,
            final_output_key: link_execution.final_output_key,
            work_queue_item_count: progress.work_item_count,
            work_queue_progress_page_count: progress_index.page_count,
            progress,
        })
    }

    pub fn submit_path_artifact_work_queue_chunk<E>(
        &self,
        worker_id: impl Into<String>,
        max_items: usize,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
        executor: &mut E,
    ) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
    where
        E: SourcePackPathPagedHierarchicalLinkExecutor<
                LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
                CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
                LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
                PartialLinkArtifact = SourcePackFilesystemArtifactPath,
            >,
    {
        execute_source_pack_filesystem_work_queue_worker_run_with_path_artifacts_for_target(
            &self.artifact_root,
            self.target,
            worker_id,
            max_items,
            lease_expires_unix_nanos,
            max_ready_items,
            executor,
        )
    }

    pub fn submit_path_artifact_work_queue_step<E>(
        &self,
        worker_id: impl Into<String>,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
        executor: &mut E,
    ) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
    where
        E: SourcePackPathPagedHierarchicalLinkExecutor<
                LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
                CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
                LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
                PartialLinkArtifact = SourcePackFilesystemArtifactPath,
            >,
    {
        execute_source_pack_filesystem_work_queue_worker_step_with_path_artifacts_for_target_at(
            &self.artifact_root,
            self.target,
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
            Some(source_pack_build_now_unix_nanos()?),
            executor,
        )
    }

    pub async fn submit_path_artifact_work_queue_chunk_async<E>(
        &self,
        worker_id: impl Into<String>,
        max_items: usize,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
        executor: &mut E,
    ) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
    where
        E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
                LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
                CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
                LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
                PartialLinkArtifact = SourcePackFilesystemArtifactPath,
            >,
    {
        execute_source_pack_filesystem_work_queue_worker_run_async_with_path_artifacts_for_target(
            &self.artifact_root,
            self.target,
            worker_id,
            max_items,
            lease_expires_unix_nanos,
            max_ready_items,
            executor,
        )
        .await
    }

    pub async fn submit_path_artifact_work_queue_step_async<E>(
        &self,
        worker_id: impl Into<String>,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
        executor: &mut E,
    ) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
    where
        E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
                LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
                CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
                LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
                PartialLinkArtifact = SourcePackFilesystemArtifactPath,
            >,
    {
        execute_source_pack_filesystem_work_queue_worker_step_async_with_path_artifacts_for_target_at(
            &self.artifact_root,
            self.target,
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
            Some(source_pack_build_now_unix_nanos()?),
            executor,
        )
        .await
    }

    pub fn work_queue_progress_snapshot(
        &self,
        max_ready_items: usize,
    ) -> Result<SourcePackFilesystemWorkQueueProgressSnapshot, CompileError> {
        source_pack_filesystem_work_queue_progress_snapshot_for_target(
            &self.artifact_root,
            self.target,
            max_ready_items,
        )
    }

    pub async fn submit_gpu_descriptor_work_queue_chunk_using(
        &self,
        worker_id: impl Into<String>,
        max_items: usize,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
        compiler: &GpuCompiler<'_>,
    ) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError> {
        compiler
            .execute_prepared_source_pack_filesystem_work_queue_worker_run_with_gpu_descriptors_for_target(
                &self.artifact_root,
                self.target,
                worker_id,
                max_items,
                lease_expires_unix_nanos,
                max_ready_items,
            )
            .await
    }

    pub async fn submit_gpu_descriptor_work_queue_step_using(
        &self,
        worker_id: impl Into<String>,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
        compiler: &GpuCompiler<'_>,
    ) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError> {
        compiler
            .execute_prepared_source_pack_filesystem_work_queue_worker_step_with_gpu_descriptors_for_target(
                &self.artifact_root,
                self.target,
                worker_id,
                lease_expires_unix_nanos,
                max_ready_items,
            )
            .await
    }
}

impl SourcePackFilesystemArtifactPrepareResult {
    pub fn prepared_build(&self) -> SourcePackFilesystemPreparedArtifactBuild {
        SourcePackFilesystemPreparedArtifactBuild::new(&self.artifact_root, self.target)
    }

    pub fn bounded_summary(
        &self,
        max_ready_items: usize,
    ) -> Result<SourcePackFilesystemPreparedArtifactBuildSummary, CompileError> {
        self.prepared_build().bounded_summary(max_ready_items)
    }

    pub fn submit_path_artifact_work_queue_chunk<E>(
        &self,
        worker_id: impl Into<String>,
        max_items: usize,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
        executor: &mut E,
    ) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
    where
        E: SourcePackPathPagedHierarchicalLinkExecutor<
                LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
                CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
                LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
                PartialLinkArtifact = SourcePackFilesystemArtifactPath,
            >,
    {
        self.prepared_build().submit_path_artifact_work_queue_chunk(
            worker_id,
            max_items,
            lease_expires_unix_nanos,
            max_ready_items,
            executor,
        )
    }

    pub fn submit_path_artifact_work_queue_step<E>(
        &self,
        worker_id: impl Into<String>,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
        executor: &mut E,
    ) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
    where
        E: SourcePackPathPagedHierarchicalLinkExecutor<
                LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
                CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
                LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
                PartialLinkArtifact = SourcePackFilesystemArtifactPath,
            >,
    {
        self.prepared_build().submit_path_artifact_work_queue_step(
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
            executor,
        )
    }

    pub async fn submit_path_artifact_work_queue_chunk_async<E>(
        &self,
        worker_id: impl Into<String>,
        max_items: usize,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
        executor: &mut E,
    ) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
    where
        E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
                LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
                CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
                LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
                PartialLinkArtifact = SourcePackFilesystemArtifactPath,
            >,
    {
        self.prepared_build()
            .submit_path_artifact_work_queue_chunk_async(
                worker_id,
                max_items,
                lease_expires_unix_nanos,
                max_ready_items,
                executor,
            )
            .await
    }

    pub async fn submit_path_artifact_work_queue_step_async<E>(
        &self,
        worker_id: impl Into<String>,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
        executor: &mut E,
    ) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
    where
        E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
                LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
                CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
                LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
                PartialLinkArtifact = SourcePackFilesystemArtifactPath,
            >,
    {
        self.prepared_build()
            .submit_path_artifact_work_queue_step_async(
                worker_id,
                lease_expires_unix_nanos,
                max_ready_items,
                executor,
            )
            .await
    }

    pub fn work_queue_progress_snapshot(
        &self,
        max_ready_items: usize,
    ) -> Result<SourcePackFilesystemWorkQueueProgressSnapshot, CompileError> {
        self.prepared_build()
            .work_queue_progress_snapshot(max_ready_items)
    }

    pub async fn submit_gpu_descriptor_work_queue_chunk_using(
        &self,
        worker_id: impl Into<String>,
        max_items: usize,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
        compiler: &GpuCompiler<'_>,
    ) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError> {
        self.prepared_build()
            .submit_gpu_descriptor_work_queue_chunk_using(
                worker_id,
                max_items,
                lease_expires_unix_nanos,
                max_ready_items,
                compiler,
            )
            .await
    }

    pub async fn submit_gpu_descriptor_work_queue_step_using(
        &self,
        worker_id: impl Into<String>,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
        compiler: &GpuCompiler<'_>,
    ) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError> {
        self.prepared_build()
            .submit_gpu_descriptor_work_queue_step_using(
                worker_id,
                lease_expires_unix_nanos,
                max_ready_items,
                compiler,
            )
            .await
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemLibraryMetadataPrepareResult {
    pub target: SourcePackArtifactTarget,
    pub source_file_count: usize,
    pub source_byte_count: usize,
    pub source_line_count: usize,
    pub library_count: usize,
    pub library_partition_index_path: PathBuf,
    pub library_partition_count: usize,
    pub library_source_file_page_count: usize,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemLibraryMetadataPrepareStepResult {
    pub target: SourcePackArtifactTarget,
    pub complete: bool,
    pub source_file_count: usize,
    pub source_byte_count: usize,
    pub source_line_count: usize,
    pub library_count: usize,
    pub new_library_count: usize,
    pub library_partition_index_path: Option<PathBuf>,
    pub library_partition_count: usize,
    pub library_source_file_page_count: usize,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackFilesystemLibraryMetadataPrepareProgress {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub source_file_count: usize,
    pub source_byte_count: usize,
    pub source_line_count: usize,
    pub library_count: usize,
    pub library_partition_count: usize,
    pub library_source_file_page_count: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum SourcePackFilesystemLibrarySchedulePreparePhase {
    BuildUnitPages,
    SchedulePages,
    Complete,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackFilesystemLibrarySchedulePrepareProgress {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub phase: SourcePackFilesystemLibrarySchedulePreparePhase,
    pub next_partition_index: usize,
    pub source_file_count: usize,
    pub source_byte_count: usize,
    pub source_line_count: usize,
    pub library_count: usize,
    pub library_partition_count: usize,
    pub library_source_file_page_count: usize,
    pub library_build_unit_page_count: usize,
    pub library_schedule_page_count: usize,
    pub frontend_job_count: usize,
    pub codegen_job_count: usize,
    pub next_frontend_job_index: usize,
    pub next_codegen_job_index: usize,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemLibrarySchedulePrepareStepResult {
    pub target: SourcePackArtifactTarget,
    pub complete: bool,
    pub source_file_count: usize,
    pub source_byte_count: usize,
    pub source_line_count: usize,
    pub library_count: usize,
    pub library_partition_count: usize,
    pub library_source_file_page_count: usize,
    pub library_build_unit_page_count: usize,
    pub new_library_build_unit_page_count: usize,
    pub library_schedule_index_path: Option<PathBuf>,
    pub library_schedule_page_count: usize,
    pub new_library_schedule_page_count: usize,
    pub frontend_job_count: usize,
    pub codegen_job_count: usize,
    pub scheduled_job_count: usize,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemArtifactRefPrepareStepResult {
    pub target: SourcePackArtifactTarget,
    pub complete: bool,
    pub artifact_count: usize,
    pub artifact_ref_page_count: usize,
    pub new_library_count: usize,
    pub interface_artifact_count: usize,
    pub object_artifact_count: usize,
    pub final_output_artifact_index: usize,
    pub final_output_key: Option<String>,
    pub artifact_ref_index_path: Option<PathBuf>,
    pub total_source_file_count: usize,
    pub total_source_byte_count: usize,
    pub total_source_line_count: usize,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::compiler) struct SourcePackBuildArtifactRefPrepareProgress {
    pub(in crate::compiler) version: u32,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) partition_count: usize,
    pub(in crate::compiler) artifact_count: usize,
    pub(in crate::compiler) next_partition_index: usize,
    pub(in crate::compiler) artifact_ref_page_count: usize,
    pub(in crate::compiler) interface_artifact_count: usize,
    pub(in crate::compiler) object_artifact_count: usize,
    pub(in crate::compiler) total_source_file_count: usize,
    pub(in crate::compiler) total_source_byte_count: usize,
    pub(in crate::compiler) total_source_line_count: usize,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemJobBatchPrepareStepResult {
    pub target: SourcePackArtifactTarget,
    pub complete: bool,
    pub scheduled_job_count: usize,
    pub batch_count: usize,
    pub new_batch_count: usize,
    pub dependency_edge_count: usize,
    pub next_job_index: usize,
    pub job_batch_index_path: Option<PathBuf>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemJobBatchDependentsPrepareStepResult {
    pub target: SourcePackArtifactTarget,
    pub complete: bool,
    pub batch_count: usize,
    pub next_batch_index: usize,
    pub new_batch_count: usize,
    pub dependent_edge_count: usize,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemArtifactShardPrepareStepResult {
    pub target: SourcePackArtifactTarget,
    pub complete: bool,
    pub shard_count: usize,
    pub new_shard_count: usize,
    pub next_input_kind: Option<SourcePackBuildArtifactShardKind>,
    pub next_batch_index: usize,
    pub new_input_batch_count: usize,
    pub progress_directory_page_count: usize,
    pub progress_directory_index_page_count: usize,
    pub next_progress_directory_page_index: usize,
    pub next_progress_directory_index_page_index: usize,
    pub new_progress_directory_page_count: usize,
    pub new_progress_directory_index_page_count: usize,
    pub job_batch_count: usize,
    pub link_interface_batch_count: usize,
    pub link_object_batch_count: usize,
    pub job_batch_shard_count: usize,
    pub ready_batch_count: usize,
    pub first_ready_batch_index: Option<usize>,
    pub artifact_shard_index_path: Option<PathBuf>,
    pub link_input_shard_index_path: Option<PathBuf>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemLinkBatchPrepareStepResult {
    pub target: SourcePackArtifactTarget,
    pub complete: bool,
    pub link_interface_batch_count: usize,
    pub link_object_batch_count: usize,
    pub new_batch_count: usize,
    pub next_interface_artifact_index: usize,
    pub next_object_artifact_index: usize,
    pub link_batch_index_path: Option<PathBuf>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemHierarchicalLinkLeafPrepareStepResult {
    pub target: SourcePackArtifactTarget,
    pub complete: bool,
    pub schedule_partition_count: usize,
    pub next_partition_index: usize,
    pub leaf_group_count: usize,
    pub new_leaf_group_count: usize,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemHierarchicalLinkPlanPrepareStepResult {
    pub target: SourcePackArtifactTarget,
    pub complete: bool,
    pub input_partition_count: usize,
    pub reduce_level: usize,
    pub current_level_first_group_index: usize,
    pub current_level_group_count: usize,
    pub next_input_group_index: usize,
    pub link_group_count: usize,
    pub new_reduce_group_count: usize,
    pub final_link_group_index: Option<usize>,
    pub hierarchical_link_plan_index_path: Option<PathBuf>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemHierarchicalLinkExecutionPrepareStepResult {
    pub target: SourcePackArtifactTarget,
    pub complete: bool,
    pub link_group_count: usize,
    pub next_group_index: usize,
    pub new_execution_page_count: usize,
    pub final_output_seen: bool,
    pub final_output_key: String,
    pub hierarchical_link_execution_index_path: Option<PathBuf>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemWorkQueuePrepareStepResult {
    pub target: SourcePackArtifactTarget,
    pub complete: bool,
    pub work_item_count: usize,
    pub artifact_item_count: usize,
    pub next_item_index: usize,
    pub new_work_item_count: usize,
    pub work_queue_index_path: Option<PathBuf>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemWorkQueueProgressPrepareStepResult {
    pub target: SourcePackArtifactTarget,
    pub complete: bool,
    pub work_item_count: usize,
    pub page_size: usize,
    pub page_count: usize,
    pub next_page_index: usize,
    pub new_progress_page_count: usize,
    pub artifact_item_count: usize,
    pub ready_item_count: usize,
    pub ready_artifact_item_count: usize,
    pub first_ready_item_index: Option<usize>,
    pub first_ready_artifact_item_index: Option<usize>,
    pub work_queue_progress_index_path: Option<PathBuf>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemLibraryPartitionStoreResult {
    pub library_partition_index_path: PathBuf,
    pub library_partition_count: usize,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemLibrarySourceFilePageStoreResult {
    pub library_source_file_page_count: usize,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemLibraryBuildUnitPageStoreResult {
    pub library_build_unit_page_count: usize,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemLibrarySchedulePageStoreResult {
    pub library_schedule_page_count: usize,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemArtifactShardStoreResult {
    pub artifact_shard_index_path: PathBuf,
    pub link_input_shard_index_path: PathBuf,
    pub artifact_shard_count: usize,
    pub artifact_execution_shard_count: usize,
    pub batch_shard_locator_count: usize,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemArtifactExecutionShardStoreResult {
    pub artifact_execution_shard_count: usize,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemBuildProgressShardStoreResult {
    pub build_progress_shard_count: usize,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemArtifactLinkInputReleaseResult {
    pub target: SourcePackArtifactTarget,
    pub shard_index: usize,
    pub shard_kind: SourcePackBuildArtifactShardKind,
    pub released_interface_count: usize,
    pub released_object_count: usize,
    pub linked_output_key: String,
    pub linked_output_path: PathBuf,
    pub artifact_shard_index_path: PathBuf,
    pub artifact_execution_shard_path: PathBuf,
}
