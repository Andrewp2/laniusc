use super::*;

/// Source-pack executor that emits GPU artifact descriptors into a filesystem store.
///
/// This executor is used by descriptor-mode source-pack builds. It validates
/// source/job metadata, checks that dependency artifacts exist, and writes
/// JSON descriptor artifacts that describe each stage's contract.
pub struct GpuSourcePackArtifactExecutor<'compiler, 'gpu> {
    pub(super) compiler: &'compiler GpuCompiler<'gpu>,
    pub(super) artifact_root: PathBuf,
    pub(super) target: SourcePackArtifactTarget,
}

/// In-flight library-interface descriptor build state.
#[derive(Clone, Debug)]
pub struct GpuSourcePackLibraryInterfaceBuildHandle {
    pub(super) job: SourcePackJob,
    pub(super) source_files: Vec<ExplicitSourcePathFile>,
    pub(super) dependency_interfaces: GpuSourcePackDependencyInterfaceSummary,
}

/// In-flight codegen-object descriptor build state.
#[derive(Clone, Debug)]
pub struct GpuSourcePackCodegenObjectBuildHandle {
    pub(super) job: SourcePackJob,
    pub(super) source_files: Vec<ExplicitSourcePathFile>,
    pub(super) library_interface_artifact: ArtifactPath,
    pub(super) dependency_interfaces: GpuSourcePackDependencyInterfaceSummary,
}

/// Accumulated input counts for a source-pack link descriptor.
#[derive(Clone, Debug, Default)]
pub struct GpuSourcePackLinkHandle {
    pub(super) interface_count: usize,
    pub(super) object_count: usize,
    pub(super) partial_link_count: usize,
}

/// Validates that source-file metadata still matches a descriptor job record.
pub(in crate::compiler) fn validate_gpu_source_pack_descriptor_job_source_file_records(
    stage: &str,
    job: &SourcePackJob,
    source_files: &[ExplicitSourcePathFile],
) -> Result<(), CompileError> {
    let expected_phase = match stage {
        "library-interface" => Some(SourcePackJobPhase::LibraryFrontend),
        "codegen" => Some(SourcePackJobPhase::Codegen),
        _ => None,
    };
    if let Some(expected_phase) = expected_phase {
        if job.phase != expected_phase {
            return Err(artifact_shard_contract_error(format!(
                "source-pack {stage} descriptor job {} has phase {:?} but expected {:?}",
                job.job_index, job.phase, expected_phase
            )));
        }
    }
    let source_end = job
        .first_source_index
        .checked_add(job.source_file_count)
        .ok_or_else(|| {
            artifact_shard_contract_error(format!(
                "source-pack {stage} descriptor job {} source range {}+{} overflows",
                job.job_index, job.first_source_index, job.source_file_count
            ))
        })?;
    if source_files.len() != job.source_file_count {
        return Err(artifact_shard_contract_error(format!(
            "source-pack {stage} descriptor job {} received {} source-file records but expected {}",
            job.job_index,
            source_files.len(),
            job.source_file_count
        )));
    }
    let mut source_bytes = 0usize;
    let mut source_lines = 0usize;
    for (offset, file) in source_files.iter().enumerate() {
        if file.library_id != job.library_id {
            let source_index = job.first_source_index.saturating_add(offset);
            return Err(artifact_shard_contract_error(format!(
                "source-pack {stage} descriptor job {} source file {} belongs to library {} but expected {}",
                job.job_index, source_index, file.library_id, job.library_id
            )));
        }
        source_bytes = source_bytes.checked_add(file.byte_len).ok_or_else(|| {
            artifact_shard_contract_error(format!(
                "source-pack {stage} descriptor job {} source byte count overflows before source {}",
                job.job_index,
                job.first_source_index.saturating_add(offset)
            ))
        })?;
        source_lines = source_lines
            .checked_add(file.line_count.unwrap_or(0))
            .ok_or_else(|| {
                artifact_shard_contract_error(format!(
                    "source-pack {stage} descriptor job {} source line count overflows before source {}",
                    job.job_index,
                    job.first_source_index.saturating_add(offset)
                ))
            })?;
    }
    if source_bytes != job.source_bytes {
        return Err(artifact_shard_contract_error(format!(
            "source-pack {stage} descriptor job {} source range {}..{} has {} bytes but job record declares {}",
            job.job_index, job.first_source_index, source_end, source_bytes, job.source_bytes
        )));
    }
    if source_lines != job.source_lines {
        return Err(artifact_shard_contract_error(format!(
            "source-pack {stage} descriptor job {} source range {}..{} has {} lines but job record declares {}",
            job.job_index, job.first_source_index, source_end, source_lines, job.source_lines
        )));
    }
    Ok(())
}

/// Validates that every dependency descriptor artifact in a batch exists on disk.
pub(in crate::compiler) fn validate_gpu_source_pack_descriptor_artifact_paths(
    stage: &str,
    owner_index: usize,
    artifacts: &[ArtifactPath],
) -> Result<(), CompileError> {
    for artifact in artifacts {
        if !artifact.path.is_file() {
            return Err(source_pack_artifact_store_error(format!(
                "source-pack {stage} {owner_index} is missing dependency artifact {} at {}",
                artifact.key,
                artifact.path.display()
            )));
        }
    }
    Ok(())
}

impl<'compiler, 'gpu> GpuSourcePackArtifactExecutor<'compiler, 'gpu> {
    /// Creates a descriptor executor for one compiler, artifact root, and target.
    pub fn new(
        compiler: &'compiler GpuCompiler<'gpu>,
        artifact_root: impl Into<PathBuf>,
        target: SourcePackArtifactTarget,
    ) -> Self {
        Self {
            compiler,
            artifact_root: artifact_root.into(),
            target,
        }
    }

    /// Returns the GPU compiler used to validate frontend interface jobs.
    pub fn compiler(&self) -> &'compiler GpuCompiler<'gpu> {
        self.compiler
    }

    /// Returns the filesystem root where descriptor artifacts are written.
    pub fn artifact_root(&self) -> &Path {
        &self.artifact_root
    }

    /// Returns the source-pack artifact target this executor emits for.
    pub fn target(&self) -> SourcePackArtifactTarget {
        self.target
    }

    /// Finishes a library-interface job by type-checking its sources and writing a descriptor.
    pub(super) async fn finish_library_interface_artifact(
        &self,
        handle: GpuSourcePackLibraryInterfaceBuildHandle,
    ) -> Result<ArtifactPath, CompileError> {
        self.validate_job_source_file_records(
            "library-interface",
            &handle.job,
            &handle.source_files,
        )?;
        let sources = read_explicit_source_path_files(
            "source-pack library-interface job",
            &handle.source_files,
        )?;
        self.compiler.type_check_source_pack(&sources).await?;
        let descriptor = GpuSourcePackArtifactDescriptor::library_interface_for_job(
            self.target,
            &handle.job,
            handle.dependency_interfaces,
        );
        self.write_descriptor_artifact(
            GpuSourcePackArtifactStage::LibraryInterface,
            &handle.job,
            &descriptor,
        )
    }

    /// Finishes a codegen-object job by validating its owning interface and writing a descriptor.
    pub(super) fn finish_codegen_object_artifact(
        &self,
        handle: GpuSourcePackCodegenObjectBuildHandle,
    ) -> Result<ArtifactPath, CompileError> {
        self.validate_job_source_file_records("codegen", &handle.job, &handle.source_files)?;
        if !handle.library_interface_artifact.path.is_file() {
            return Err(source_pack_artifact_store_error(format!(
                "source-pack codegen descriptor job {} is missing owning interface artifact {}",
                handle.job.job_index,
                handle.library_interface_artifact.path.display()
            )));
        }
        let descriptor = GpuSourcePackArtifactDescriptor::codegen_object_contract_for_job(
            self.target,
            &handle.job,
            handle.dependency_interfaces,
        );
        self.write_descriptor_artifact(
            GpuSourcePackArtifactStage::CodegenObject,
            &handle.job,
            &descriptor,
        )
    }

    /// Finishes a direct link job by writing a linked-output descriptor.
    pub(super) fn finish_linked_output_artifact(
        &self,
        job: &SourcePackJob,
        link_handle: GpuSourcePackLinkHandle,
    ) -> Result<ArtifactPath, CompileError> {
        let descriptor = GpuSourcePackArtifactDescriptor::linked_output_contract_for_job(
            self.target,
            job,
            link_handle.interface_count,
            link_handle.object_count,
        );
        self.write_descriptor_artifact(GpuSourcePackArtifactStage::LinkedOutput, job, &descriptor)
    }

    /// Finishes a hierarchical partial-link group by writing a partial-link descriptor.
    pub(super) fn finish_hierarchical_partial_link_artifact(
        &self,
        page: &SourcePackHierarchicalLinkExecutionPage,
        link_handle: GpuSourcePackLinkHandle,
    ) -> Result<ArtifactPath, CompileError> {
        let descriptor = GpuSourcePackArtifactDescriptor::partial_link_contract_for_page(
            page,
            link_handle.interface_count,
            link_handle.object_count,
            link_handle.partial_link_count,
        );
        self.write_descriptor_artifact_for_suffix(
            GpuSourcePackArtifactStage::PartialLink,
            format!("group-{}", page.group_index),
            &descriptor,
        )
    }

    /// Finishes a hierarchical final-link group by writing a linked-output descriptor.
    pub(super) fn finish_hierarchical_linked_output_artifact(
        &self,
        page: &SourcePackHierarchicalLinkExecutionPage,
        link_handle: GpuSourcePackLinkHandle,
    ) -> Result<ArtifactPath, CompileError> {
        let descriptor =
            GpuSourcePackArtifactDescriptor::hierarchical_linked_output_contract_for_page(
                page,
                link_handle.interface_count,
                link_handle.object_count,
                link_handle.partial_link_count,
            );
        self.write_descriptor_artifact_for_suffix(
            GpuSourcePackArtifactStage::LinkedOutput,
            format!("group-{}", page.group_index),
            &descriptor,
        )
    }

    /// Writes a job-scoped descriptor artifact using the standard job key suffix.
    pub(super) fn write_descriptor_artifact(
        &self,
        stage: GpuSourcePackArtifactStage,
        job: &SourcePackJob,
        descriptor: &GpuSourcePackArtifactDescriptor,
    ) -> Result<ArtifactPath, CompileError> {
        self.write_descriptor_artifact_for_suffix(
            stage,
            format!("job-{}", job.job_index),
            descriptor,
        )
    }

    /// Serializes and writes a descriptor artifact using an explicit key suffix.
    pub(super) fn write_descriptor_artifact_for_suffix(
        &self,
        stage: GpuSourcePackArtifactStage,
        key_suffix: impl AsRef<str>,
        descriptor: &GpuSourcePackArtifactDescriptor,
    ) -> Result<ArtifactPath, CompileError> {
        let key = gpu_source_pack_descriptor_artifact_key(self.target, stage, key_suffix.as_ref());
        let path = artifact_path(&self.artifact_root, &key)?;
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|err| {
                source_pack_artifact_store_error(format!(
                    "create source-pack descriptor artifact directory {}: {err}",
                    parent.display()
                ))
            })?;
        }
        let bytes = serde_json::to_vec_pretty(descriptor).map_err(|err| {
            source_pack_artifact_store_error(format!(
                "serialize source-pack {:?} descriptor for {}: {err}",
                stage,
                key_suffix.as_ref()
            ))
        })?;
        write_file_atomic_with_error(
            &path,
            &bytes,
            "source-pack descriptor artifact",
            source_pack_artifact_store_error,
        )?;
        Ok(ArtifactPath { key, path })
    }

    /// Validates that source-file metadata still matches a job record.
    pub(super) fn validate_job_source_file_records(
        &self,
        stage: &str,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
    ) -> Result<(), CompileError> {
        validate_gpu_source_pack_descriptor_job_source_file_records(stage, job, source_files)
    }

    /// Validates that every dependency artifact in a batch exists on disk.
    pub(super) fn validate_existing_path_artifact_batch(
        &self,
        stage: &str,
        owner_index: usize,
        artifacts: &[ArtifactPath],
    ) -> Result<(), CompileError> {
        validate_gpu_source_pack_descriptor_artifact_paths(stage, owner_index, artifacts)
    }
}

/// Builds the artifact key for a source-pack descriptor artifact.
pub(super) fn gpu_source_pack_descriptor_artifact_key(
    target: SourcePackArtifactTarget,
    stage: GpuSourcePackArtifactStage,
    key_suffix: &str,
) -> String {
    let target = target.key_prefix().unwrap_or("generic");
    let stage = match stage {
        GpuSourcePackArtifactStage::LibraryInterface => "library-interface",
        GpuSourcePackArtifactStage::CodegenObject => "codegen-object",
        GpuSourcePackArtifactStage::PartialLink => "partial-link",
        GpuSourcePackArtifactStage::LinkedOutput => "linked-output",
    };
    format!("gpu-source-pack/{target}/{stage}/{key_suffix}.json")
}

impl<'compiler, 'gpu> AsyncPagedArtifactBuildExecutor
    for GpuSourcePackArtifactExecutor<'compiler, 'gpu>
{
    type LibraryInterfaceArtifact = ArtifactPath;
    type CodegenObjectArtifact = ArtifactPath;
    type LinkHandle = GpuSourcePackLinkHandle;
    type LinkedOutputArtifact = ArtifactPath;
    type LibraryInterfaceBuildHandle = GpuSourcePackLibraryInterfaceBuildHandle;
    type CodegenObjectBuildHandle = GpuSourcePackCodegenObjectBuildHandle;

    fn begin_library_interface<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        source_files: &'a [ExplicitSourcePathFile],
    ) -> SourcePackBoxFuture<'a, Self::LibraryInterfaceBuildHandle> {
        Box::pin(async move {
            Ok(GpuSourcePackLibraryInterfaceBuildHandle {
                job: job.clone(),
                source_files: source_files.to_vec(),
                dependency_interfaces: GpuSourcePackDependencyInterfaceSummary::default(),
            })
        })
    }

    fn add_library_interface_dependency_batch<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        handle: &'a mut Self::LibraryInterfaceBuildHandle,
        dependency_interfaces: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            self.validate_existing_path_artifact_batch(
                "library-interface dependency batch",
                job.job_index,
                dependency_interfaces,
            )?;
            handle
                .dependency_interfaces
                .add_batch(dependency_interfaces.len());
            Ok(())
        })
    }

    fn finish_library_interface<'a>(
        &'a mut self,
        _job: &'a SourcePackJob,
        handle: Self::LibraryInterfaceBuildHandle,
    ) -> SourcePackBoxFuture<'a, Self::LibraryInterfaceArtifact> {
        Box::pin(async move { self.finish_library_interface_artifact(handle).await })
    }

    fn begin_codegen_object<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        source_files: &'a [ExplicitSourcePathFile],
        library_interface: &'a Self::LibraryInterfaceArtifact,
    ) -> SourcePackBoxFuture<'a, Self::CodegenObjectBuildHandle> {
        Box::pin(async move {
            Ok(GpuSourcePackCodegenObjectBuildHandle {
                job: job.clone(),
                source_files: source_files.to_vec(),
                library_interface_artifact: library_interface.clone(),
                dependency_interfaces: GpuSourcePackDependencyInterfaceSummary::default(),
            })
        })
    }

    fn add_codegen_object_dependency_batch<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        handle: &'a mut Self::CodegenObjectBuildHandle,
        dependency_interfaces: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            self.validate_existing_path_artifact_batch(
                "codegen dependency batch",
                job.job_index,
                dependency_interfaces,
            )?;
            handle
                .dependency_interfaces
                .add_batch(dependency_interfaces.len());
            Ok(())
        })
    }

    fn finish_codegen_object<'a>(
        &'a mut self,
        _job: &'a SourcePackJob,
        handle: Self::CodegenObjectBuildHandle,
    ) -> SourcePackBoxFuture<'a, Self::CodegenObjectArtifact> {
        Box::pin(async move { self.finish_codegen_object_artifact(handle) })
    }

    fn begin_link_codegen_objects<'a>(
        &'a mut self,
        _job: &'a SourcePackJob,
    ) -> SourcePackBoxFuture<'a, Self::LinkHandle> {
        Box::pin(async move { Ok(GpuSourcePackLinkHandle::default()) })
    }

    fn link_library_interface_batch<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        link_handle: &'a mut Self::LinkHandle,
        _batch: &'a SourcePackLinkInterfaceBatch,
        library_interfaces: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            self.validate_existing_path_artifact_batch(
                "link interface batch",
                job.job_index,
                library_interfaces,
            )?;
            link_handle.interface_count = link_handle
                .interface_count
                .saturating_add(library_interfaces.len());
            Ok(())
        })
    }

    fn link_codegen_object_batch<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        link_handle: &'a mut Self::LinkHandle,
        _batch: &'a SourcePackLinkObjectBatch,
        codegen_objects: &'a [Self::CodegenObjectArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            self.validate_existing_path_artifact_batch(
                "link object batch",
                job.job_index,
                codegen_objects,
            )?;
            link_handle.object_count = link_handle
                .object_count
                .saturating_add(codegen_objects.len());
            Ok(())
        })
    }

    fn finish_link_codegen_objects<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        link_handle: Self::LinkHandle,
    ) -> SourcePackBoxFuture<'a, Self::LinkedOutputArtifact> {
        Box::pin(async move { self.finish_linked_output_artifact(job, link_handle) })
    }
}

impl<'compiler, 'gpu> AsyncHierarchicalLinkExecutor
    for GpuSourcePackArtifactExecutor<'compiler, 'gpu>
{
    type PartialLinkArtifact = ArtifactPath;

    fn begin_hierarchical_link_group<'a>(
        &'a mut self,
        _page: &'a SourcePackHierarchicalLinkExecutionPage,
    ) -> SourcePackBoxFuture<'a, Self::LinkHandle> {
        Box::pin(async move { Ok(GpuSourcePackLinkHandle::default()) })
    }

    fn link_hierarchical_library_interfaces<'a>(
        &'a mut self,
        page: &'a SourcePackHierarchicalLinkExecutionPage,
        link_handle: &'a mut Self::LinkHandle,
        library_interfaces: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            self.validate_existing_path_artifact_batch(
                "hierarchical link interface batch",
                page.group_index,
                library_interfaces,
            )?;
            link_handle.interface_count = link_handle
                .interface_count
                .saturating_add(library_interfaces.len());
            Ok(())
        })
    }

    fn link_hierarchical_codegen_objects<'a>(
        &'a mut self,
        page: &'a SourcePackHierarchicalLinkExecutionPage,
        link_handle: &'a mut Self::LinkHandle,
        codegen_objects: &'a [Self::CodegenObjectArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            self.validate_existing_path_artifact_batch(
                "hierarchical link object batch",
                page.group_index,
                codegen_objects,
            )?;
            link_handle.object_count = link_handle
                .object_count
                .saturating_add(codegen_objects.len());
            Ok(())
        })
    }

    fn link_hierarchical_partial_links<'a>(
        &'a mut self,
        page: &'a SourcePackHierarchicalLinkExecutionPage,
        link_handle: &'a mut Self::LinkHandle,
        partial_links: &'a [Self::PartialLinkArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            self.validate_existing_path_artifact_batch(
                "hierarchical partial-link batch",
                page.group_index,
                partial_links,
            )?;
            link_handle.partial_link_count = link_handle
                .partial_link_count
                .saturating_add(partial_links.len());
            Ok(())
        })
    }

    fn finish_hierarchical_partial_link_group<'a>(
        &'a mut self,
        page: &'a SourcePackHierarchicalLinkExecutionPage,
        link_handle: Self::LinkHandle,
    ) -> SourcePackBoxFuture<'a, Self::PartialLinkArtifact> {
        Box::pin(async move { self.finish_hierarchical_partial_link_artifact(page, link_handle) })
    }

    fn finish_hierarchical_link_output<'a>(
        &'a mut self,
        page: &'a SourcePackHierarchicalLinkExecutionPage,
        link_handle: Self::LinkHandle,
    ) -> SourcePackBoxFuture<'a, Self::LinkedOutputArtifact> {
        Box::pin(async move { self.finish_hierarchical_linked_output_artifact(page, link_handle) })
    }
}
