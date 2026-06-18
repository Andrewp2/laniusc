use super::*;

impl<'gpu> GpuCompiler<'gpu> {
    /// Run ready descriptor work-queue items from an already prepared artifact
    /// root using this compiler as the GPU executor.
    #[allow(clippy::too_many_arguments)]
    pub async fn run_descriptor_work_queue(
        &self,
        artifact_root: impl Into<PathBuf>,
        target: SourcePackArtifactTarget,
        worker_id: impl Into<String>,
        max_items: usize,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
    ) -> Result<FilesystemWorkQueueWorkerRunExecutionResult, CompileError> {
        let artifact_root = artifact_root.into();
        let mut executor = GpuSourcePackArtifactExecutor::new(self, artifact_root.clone(), target);
        run_path_work_queue_async(
            artifact_root,
            target,
            worker_id,
            max_items,
            lease_expires_unix_nanos,
            max_ready_items,
            &mut executor,
        )
        .await
    }

    /// Claim and execute one ready descriptor work-queue item from an already
    /// prepared artifact root using this compiler as the GPU executor.
    #[allow(clippy::too_many_arguments)]
    pub async fn step_descriptor_work_queue(
        &self,
        artifact_root: impl Into<PathBuf>,
        target: SourcePackArtifactTarget,
        worker_id: impl Into<String>,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
    ) -> Result<FilesystemWorkQueueWorkerStepExecutionResult, CompileError> {
        let artifact_root = artifact_root.into();
        let mut executor = GpuSourcePackArtifactExecutor::new(self, artifact_root.clone(), target);
        step_path_work_queue_async(
            artifact_root,
            target,
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
            Some(current_unix_nanos()?),
            &mut executor,
        )
        .await
    }

    /// Prepare library path inputs if needed, then claim and execute one
    /// descriptor work-queue item for the requested target.
    #[allow(clippy::too_many_arguments)]
    pub async fn step_library_path_worker<I, P>(
        &self,
        libraries: I,
        artifact_root: impl Into<PathBuf>,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        shard_limits: SourcePackBuildShardLimits,
        target: SourcePackArtifactTarget,
        worker_id: impl Into<String>,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
    ) -> Result<FilesystemWorkQueueWorkerStepExecutionResult, CompileError>
    where
        I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
        P: AsRef<Path>,
    {
        let path_streams = path_streams_from_library_paths(libraries);
        self.step_path_stream_worker(
            path_streams,
            artifact_root,
            limits,
            batch_limits,
            shard_limits,
            target,
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
    }

    /// Prepare library path inputs if needed, then claim and execute one WASM
    /// descriptor work-queue item.
    #[allow(clippy::too_many_arguments)]
    pub async fn step_library_path_worker_to_wasm<I, P>(
        &self,
        libraries: I,
        artifact_root: impl Into<PathBuf>,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        shard_limits: SourcePackBuildShardLimits,
        worker_id: impl Into<String>,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
    ) -> Result<FilesystemWorkQueueWorkerStepExecutionResult, CompileError>
    where
        I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
        P: AsRef<Path>,
    {
        self.step_library_path_worker(
            libraries,
            artifact_root,
            limits,
            batch_limits,
            shard_limits,
            SourcePackArtifactTarget::Wasm,
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
    }

    /// Prepare library path inputs if needed, then claim and execute one x86_64
    /// descriptor work-queue item.
    #[allow(clippy::too_many_arguments)]
    pub async fn step_library_path_worker_to_x86_64<I, P>(
        &self,
        libraries: I,
        artifact_root: impl Into<PathBuf>,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        shard_limits: SourcePackBuildShardLimits,
        worker_id: impl Into<String>,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
    ) -> Result<FilesystemWorkQueueWorkerStepExecutionResult, CompileError>
    where
        I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
        P: AsRef<Path>,
    {
        self.step_library_path_worker(
            libraries,
            artifact_root,
            limits,
            batch_limits,
            shard_limits,
            SourcePackArtifactTarget::X86_64,
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
    }

    /// Prepare ordered path-stream inputs if needed, then run ready descriptor
    /// work-queue items for the requested target.
    #[allow(clippy::too_many_arguments)]
    pub async fn run_path_stream_worker<I, PI, P>(
        &self,
        libraries: I,
        artifact_root: impl Into<PathBuf>,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        shard_limits: SourcePackBuildShardLimits,
        target: SourcePackArtifactTarget,
        worker_id: impl Into<String>,
        max_items: usize,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
    ) -> Result<FilesystemWorkQueueWorkerRunExecutionResult, CompileError>
    where
        I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
        PI: IntoIterator<Item = P>,
        P: AsRef<Path>,
    {
        let artifact_root = artifact_root.into();
        let mut executor = GpuSourcePackArtifactExecutor::new(self, artifact_root.clone(), target);
        run_ordered_path_stream_artifact_worker_async(
            libraries,
            artifact_root,
            limits,
            batch_limits,
            shard_limits,
            target,
            worker_id,
            max_items,
            lease_expires_unix_nanos,
            max_ready_items,
            &mut executor,
        )
        .await
    }

    /// Prepare ordered path-stream inputs if needed, then claim and execute one
    /// descriptor work-queue item for the requested target.
    #[allow(clippy::too_many_arguments)]
    pub async fn step_path_stream_worker<I, PI, P>(
        &self,
        libraries: I,
        artifact_root: impl Into<PathBuf>,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        shard_limits: SourcePackBuildShardLimits,
        target: SourcePackArtifactTarget,
        worker_id: impl Into<String>,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
    ) -> Result<FilesystemWorkQueueWorkerStepExecutionResult, CompileError>
    where
        I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
        PI: IntoIterator<Item = P>,
        P: AsRef<Path>,
    {
        let artifact_root = artifact_root.into();
        let dependency_streams = dependency_streams_from_path_streams(libraries);
        let prepared = prepare_dependency_stream_work_queue_chunk(
            dependency_streams,
            &artifact_root,
            limits,
            batch_limits,
            shard_limits,
            target,
            ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT,
        )?;
        if !prepared {
            return Err(work_queue_not_prepared_error(
                target,
                ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT,
            ));
        }
        PreparedBuild::new(&artifact_root, target)
            .submit_gpu_descriptor_work_queue_step(
                worker_id,
                lease_expires_unix_nanos,
                max_ready_items,
                self,
            )
            .await
    }

    /// Prepare ordered path-stream inputs if needed, then run ready WASM
    /// descriptor work-queue items.
    #[allow(clippy::too_many_arguments)]
    pub async fn run_path_stream_worker_to_wasm<I, PI, P>(
        &self,
        libraries: I,
        artifact_root: impl Into<PathBuf>,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        shard_limits: SourcePackBuildShardLimits,
        worker_id: impl Into<String>,
        max_items: usize,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
    ) -> Result<FilesystemWorkQueueWorkerRunExecutionResult, CompileError>
    where
        I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
        PI: IntoIterator<Item = P>,
        P: AsRef<Path>,
    {
        self.run_path_stream_worker(
            libraries,
            artifact_root,
            limits,
            batch_limits,
            shard_limits,
            SourcePackArtifactTarget::Wasm,
            worker_id,
            max_items,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
    }

    /// Prepare ordered path-stream inputs if needed, then claim and execute one
    /// WASM descriptor work-queue item.
    #[allow(clippy::too_many_arguments)]
    pub async fn step_path_stream_worker_to_wasm<I, PI, P>(
        &self,
        libraries: I,
        artifact_root: impl Into<PathBuf>,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        shard_limits: SourcePackBuildShardLimits,
        worker_id: impl Into<String>,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
    ) -> Result<FilesystemWorkQueueWorkerStepExecutionResult, CompileError>
    where
        I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
        PI: IntoIterator<Item = P>,
        P: AsRef<Path>,
    {
        self.step_path_stream_worker(
            libraries,
            artifact_root,
            limits,
            batch_limits,
            shard_limits,
            SourcePackArtifactTarget::Wasm,
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
    }

    /// Prepare ordered path-stream inputs if needed, then run ready x86_64
    /// descriptor work-queue items.
    #[allow(clippy::too_many_arguments)]
    pub async fn run_path_stream_worker_to_x86_64<I, PI, P>(
        &self,
        libraries: I,
        artifact_root: impl Into<PathBuf>,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        shard_limits: SourcePackBuildShardLimits,
        worker_id: impl Into<String>,
        max_items: usize,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
    ) -> Result<FilesystemWorkQueueWorkerRunExecutionResult, CompileError>
    where
        I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
        PI: IntoIterator<Item = P>,
        P: AsRef<Path>,
    {
        self.run_path_stream_worker(
            libraries,
            artifact_root,
            limits,
            batch_limits,
            shard_limits,
            SourcePackArtifactTarget::X86_64,
            worker_id,
            max_items,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
    }

    /// Prepare ordered path-stream inputs if needed, then claim and execute one
    /// x86_64 descriptor work-queue item.
    #[allow(clippy::too_many_arguments)]
    pub async fn step_path_stream_worker_to_x86_64<I, PI, P>(
        &self,
        libraries: I,
        artifact_root: impl Into<PathBuf>,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        shard_limits: SourcePackBuildShardLimits,
        worker_id: impl Into<String>,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
    ) -> Result<FilesystemWorkQueueWorkerStepExecutionResult, CompileError>
    where
        I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
        PI: IntoIterator<Item = P>,
        P: AsRef<Path>,
    {
        self.step_path_stream_worker(
            libraries,
            artifact_root,
            limits,
            batch_limits,
            shard_limits,
            SourcePackArtifactTarget::X86_64,
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
    }

    /// Prepare dependency-stream inputs if needed, then run ready descriptor
    /// work-queue items for the requested target.
    #[allow(clippy::too_many_arguments)]
    pub async fn run_dependency_stream_worker<I, PI, DI, P>(
        &self,
        libraries: I,
        artifact_root: impl Into<PathBuf>,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        shard_limits: SourcePackBuildShardLimits,
        target: SourcePackArtifactTarget,
        worker_id: impl Into<String>,
        max_items: usize,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
    ) -> Result<FilesystemWorkQueueWorkerRunExecutionResult, CompileError>
    where
        I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
        PI: IntoIterator<Item = P>,
        DI: IntoIterator<Item = u32>,
        P: AsRef<Path>,
    {
        let artifact_root = artifact_root.into();
        let prepare_chunk_limit = limit_work_queue_worker_run_items(max_items).max(1);
        let prepared = prepare_dependency_stream_work_queue_chunk(
            libraries,
            &artifact_root,
            limits,
            batch_limits,
            shard_limits,
            target,
            prepare_chunk_limit,
        )?;
        if !prepared {
            return Err(work_queue_not_prepared_error(target, prepare_chunk_limit));
        }
        self.run_descriptor_work_queue(
            artifact_root,
            target,
            worker_id,
            max_items,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
    }

    /// Prepare dependency-stream inputs if needed, then claim and execute one
    /// descriptor work-queue item for the requested target.
    #[allow(clippy::too_many_arguments)]
    pub async fn step_dependency_stream_worker<I, PI, DI, P>(
        &self,
        libraries: I,
        artifact_root: impl Into<PathBuf>,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        shard_limits: SourcePackBuildShardLimits,
        target: SourcePackArtifactTarget,
        worker_id: impl Into<String>,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
    ) -> Result<FilesystemWorkQueueWorkerStepExecutionResult, CompileError>
    where
        I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
        PI: IntoIterator<Item = P>,
        DI: IntoIterator<Item = u32>,
        P: AsRef<Path>,
    {
        let artifact_root = artifact_root.into();
        let prepared = prepare_dependency_stream_work_queue_chunk(
            libraries,
            &artifact_root,
            limits,
            batch_limits,
            shard_limits,
            target,
            ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT,
        )?;
        if !prepared {
            return Err(work_queue_not_prepared_error(
                target,
                ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT,
            ));
        }
        PreparedBuild::new(&artifact_root, target)
            .submit_gpu_descriptor_work_queue_step(
                worker_id,
                lease_expires_unix_nanos,
                max_ready_items,
                self,
            )
            .await
    }

    /// Prepare dependency-stream inputs if needed, then run ready WASM
    /// descriptor work-queue items.
    #[allow(clippy::too_many_arguments)]
    pub async fn run_dependency_stream_worker_to_wasm<I, PI, DI, P>(
        &self,
        libraries: I,
        artifact_root: impl Into<PathBuf>,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        shard_limits: SourcePackBuildShardLimits,
        worker_id: impl Into<String>,
        max_items: usize,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
    ) -> Result<FilesystemWorkQueueWorkerRunExecutionResult, CompileError>
    where
        I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
        PI: IntoIterator<Item = P>,
        DI: IntoIterator<Item = u32>,
        P: AsRef<Path>,
    {
        self.run_dependency_stream_worker(
            libraries,
            artifact_root,
            limits,
            batch_limits,
            shard_limits,
            SourcePackArtifactTarget::Wasm,
            worker_id,
            max_items,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
    }

    /// Prepare dependency-stream inputs if needed, then claim and execute one
    /// WASM descriptor work-queue item.
    #[allow(clippy::too_many_arguments)]
    pub async fn step_dependency_stream_worker_to_wasm<I, PI, DI, P>(
        &self,
        libraries: I,
        artifact_root: impl Into<PathBuf>,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        shard_limits: SourcePackBuildShardLimits,
        worker_id: impl Into<String>,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
    ) -> Result<FilesystemWorkQueueWorkerStepExecutionResult, CompileError>
    where
        I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
        PI: IntoIterator<Item = P>,
        DI: IntoIterator<Item = u32>,
        P: AsRef<Path>,
    {
        self.step_dependency_stream_worker(
            libraries,
            artifact_root,
            limits,
            batch_limits,
            shard_limits,
            SourcePackArtifactTarget::Wasm,
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
    }

    /// Prepare dependency-stream inputs if needed, then run ready x86_64
    /// descriptor work-queue items.
    #[allow(clippy::too_many_arguments)]
    pub async fn run_dependency_stream_worker_to_x86_64<I, PI, DI, P>(
        &self,
        libraries: I,
        artifact_root: impl Into<PathBuf>,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        shard_limits: SourcePackBuildShardLimits,
        worker_id: impl Into<String>,
        max_items: usize,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
    ) -> Result<FilesystemWorkQueueWorkerRunExecutionResult, CompileError>
    where
        I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
        PI: IntoIterator<Item = P>,
        DI: IntoIterator<Item = u32>,
        P: AsRef<Path>,
    {
        self.run_dependency_stream_worker(
            libraries,
            artifact_root,
            limits,
            batch_limits,
            shard_limits,
            SourcePackArtifactTarget::X86_64,
            worker_id,
            max_items,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
    }

    /// Prepare dependency-stream inputs if needed, then claim and execute one
    /// x86_64 descriptor work-queue item.
    #[allow(clippy::too_many_arguments)]
    pub async fn step_dependency_stream_worker_to_x86_64<I, PI, DI, P>(
        &self,
        libraries: I,
        artifact_root: impl Into<PathBuf>,
        limits: CodegenUnitLimits,
        batch_limits: SourcePackJobBatchLimits,
        shard_limits: SourcePackBuildShardLimits,
        worker_id: impl Into<String>,
        lease_expires_unix_nanos: Option<u128>,
        max_ready_items: usize,
    ) -> Result<FilesystemWorkQueueWorkerStepExecutionResult, CompileError>
    where
        I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
        PI: IntoIterator<Item = P>,
        DI: IntoIterator<Item = u32>,
        P: AsRef<Path>,
    {
        self.step_dependency_stream_worker(
            libraries,
            artifact_root,
            limits,
            batch_limits,
            shard_limits,
            SourcePackArtifactTarget::X86_64,
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
    }
}
