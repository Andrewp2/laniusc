use super::*;

pub trait SourcePackBuildExecutor {
    type LibraryInterface;
    type CodegenObject;
    type LinkedOutput;

    fn build_library_interface(
        &mut self,
        job: &SourcePackJob,
        sources: &[String],
        dependency_interfaces: &[&Self::LibraryInterface],
    ) -> Result<Self::LibraryInterface, CompileError>;

    fn build_codegen_object(
        &mut self,
        job: &SourcePackJob,
        sources: &[String],
        library_interface: &Self::LibraryInterface,
        dependency_interfaces: &[&Self::LibraryInterface],
    ) -> Result<Self::CodegenObject, CompileError>;

    fn link_codegen_objects(
        &mut self,
        job: &SourcePackJob,
        library_interfaces: &[&Self::LibraryInterface],
        codegen_objects: &[&Self::CodegenObject],
    ) -> Result<Self::LinkedOutput, CompileError>;
}

pub trait SourcePackPathBuildExecutor {
    type LibraryInterface;
    type CodegenObject;
    type LinkedOutput;

    fn build_library_interface(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        dependency_interfaces: &[&Self::LibraryInterface],
    ) -> Result<Self::LibraryInterface, CompileError>;

    fn build_codegen_object(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        library_interface: &Self::LibraryInterface,
        dependency_interfaces: &[&Self::LibraryInterface],
    ) -> Result<Self::CodegenObject, CompileError>;

    fn link_codegen_objects(
        &mut self,
        job: &SourcePackJob,
        library_interfaces: &[&Self::LibraryInterface],
        codegen_objects: &[&Self::CodegenObject],
    ) -> Result<Self::LinkedOutput, CompileError>;
}

pub trait SourcePackPathHandleBuildExecutor {
    type LibraryInterfaceHandle: Clone;
    type CodegenObjectHandle: Clone;
    type LinkedOutput;

    fn build_library_interface(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        dependency_interfaces: &[Self::LibraryInterfaceHandle],
    ) -> Result<Self::LibraryInterfaceHandle, CompileError>;

    fn build_codegen_object(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        library_interface: &Self::LibraryInterfaceHandle,
        dependency_interfaces: &[Self::LibraryInterfaceHandle],
    ) -> Result<Self::CodegenObjectHandle, CompileError>;

    fn link_codegen_objects(
        &mut self,
        job: &SourcePackJob,
        library_interfaces: &[Self::LibraryInterfaceHandle],
        codegen_objects: &[Self::CodegenObjectHandle],
    ) -> Result<Self::LinkedOutput, CompileError>;

    fn release_library_interface(
        &mut self,
        _handle: Self::LibraryInterfaceHandle,
    ) -> Result<(), CompileError> {
        Ok(())
    }

    fn release_codegen_object(
        &mut self,
        _handle: Self::CodegenObjectHandle,
    ) -> Result<(), CompileError> {
        Ok(())
    }
}

pub trait SourcePackPathHandleBatchedLinkBuildExecutor {
    type LibraryInterfaceHandle: Clone;
    type CodegenObjectHandle: Clone;
    type LinkHandle;
    type LinkedOutput;

    fn build_library_interface(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        dependency_interfaces: &[Self::LibraryInterfaceHandle],
    ) -> Result<Self::LibraryInterfaceHandle, CompileError>;

    fn build_codegen_object(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        library_interface: &Self::LibraryInterfaceHandle,
        dependency_interfaces: &[Self::LibraryInterfaceHandle],
    ) -> Result<Self::CodegenObjectHandle, CompileError>;

    fn begin_link_codegen_objects(
        &mut self,
        job: &SourcePackJob,
    ) -> Result<Self::LinkHandle, CompileError>;

    fn link_library_interface_batch(
        &mut self,
        job: &SourcePackJob,
        link_handle: &mut Self::LinkHandle,
        batch: &SourcePackLinkInterfaceBatch,
        library_interfaces: &[Self::LibraryInterfaceHandle],
    ) -> Result<(), CompileError>;

    fn link_codegen_object_batch(
        &mut self,
        job: &SourcePackJob,
        link_handle: &mut Self::LinkHandle,
        batch: &SourcePackLinkObjectBatch,
        codegen_objects: &[Self::CodegenObjectHandle],
    ) -> Result<(), CompileError>;

    fn finish_link_codegen_objects(
        &mut self,
        job: &SourcePackJob,
        link_handle: Self::LinkHandle,
    ) -> Result<Self::LinkedOutput, CompileError>;

    fn release_library_interface(
        &mut self,
        _handle: Self::LibraryInterfaceHandle,
    ) -> Result<(), CompileError> {
        Ok(())
    }

    fn release_codegen_object(
        &mut self,
        _handle: Self::CodegenObjectHandle,
    ) -> Result<(), CompileError> {
        Ok(())
    }
}

pub trait SourcePackPathArtifactBuildExecutor {
    type LibraryInterfaceArtifact;
    type CodegenObjectArtifact;
    type LinkHandle;
    type LinkedOutputArtifact;

    fn build_library_interface(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        dependency_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<Self::LibraryInterfaceArtifact, CompileError>;

    fn build_codegen_object(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        library_interface: &Self::LibraryInterfaceArtifact,
        dependency_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<Self::CodegenObjectArtifact, CompileError>;

    fn begin_link_codegen_objects(
        &mut self,
        job: &SourcePackJob,
    ) -> Result<Self::LinkHandle, CompileError>;

    fn link_library_interface_batch(
        &mut self,
        job: &SourcePackJob,
        link_handle: &mut Self::LinkHandle,
        batch: &SourcePackLinkInterfaceBatch,
        library_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<(), CompileError>;

    fn link_codegen_object_batch(
        &mut self,
        job: &SourcePackJob,
        link_handle: &mut Self::LinkHandle,
        batch: &SourcePackLinkObjectBatch,
        codegen_objects: &[Self::CodegenObjectArtifact],
    ) -> Result<(), CompileError>;

    fn finish_link_codegen_objects(
        &mut self,
        job: &SourcePackJob,
        link_handle: Self::LinkHandle,
    ) -> Result<Self::LinkedOutputArtifact, CompileError>;
}

pub trait SourcePackPathPagedArtifactBuildExecutor: SourcePackPathArtifactBuildExecutor {
    type LibraryInterfaceBuildHandle;
    type CodegenObjectBuildHandle;

    fn begin_library_interface(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
    ) -> Result<Self::LibraryInterfaceBuildHandle, CompileError>;

    fn add_library_interface_dependency_batch(
        &mut self,
        job: &SourcePackJob,
        handle: &mut Self::LibraryInterfaceBuildHandle,
        dependency_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<(), CompileError>;

    fn finish_library_interface(
        &mut self,
        job: &SourcePackJob,
        handle: Self::LibraryInterfaceBuildHandle,
    ) -> Result<Self::LibraryInterfaceArtifact, CompileError>;

    fn begin_codegen_object(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        library_interface: &Self::LibraryInterfaceArtifact,
    ) -> Result<Self::CodegenObjectBuildHandle, CompileError>;

    fn add_codegen_object_dependency_batch(
        &mut self,
        job: &SourcePackJob,
        handle: &mut Self::CodegenObjectBuildHandle,
        dependency_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<(), CompileError>;

    fn finish_codegen_object(
        &mut self,
        job: &SourcePackJob,
        handle: Self::CodegenObjectBuildHandle,
    ) -> Result<Self::CodegenObjectArtifact, CompileError>;
}

pub type SourcePackBoxFuture<'a, T> =
    std::pin::Pin<Box<dyn std::future::Future<Output = Result<T, CompileError>> + 'a>>;

pub trait SourcePackPathAsyncPagedArtifactBuildExecutor {
    type LibraryInterfaceArtifact;
    type CodegenObjectArtifact;
    type LinkHandle;
    type LinkedOutputArtifact;
    type LibraryInterfaceBuildHandle;
    type CodegenObjectBuildHandle;

    fn begin_library_interface<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        source_files: &'a [ExplicitSourcePathFile],
    ) -> SourcePackBoxFuture<'a, Self::LibraryInterfaceBuildHandle>;

    fn add_library_interface_dependency_batch<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        handle: &'a mut Self::LibraryInterfaceBuildHandle,
        dependency_interfaces: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()>;

    fn finish_library_interface<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        handle: Self::LibraryInterfaceBuildHandle,
    ) -> SourcePackBoxFuture<'a, Self::LibraryInterfaceArtifact>;

    fn begin_codegen_object<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        source_files: &'a [ExplicitSourcePathFile],
        library_interface: &'a Self::LibraryInterfaceArtifact,
    ) -> SourcePackBoxFuture<'a, Self::CodegenObjectBuildHandle>;

    fn add_codegen_object_dependency_batch<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        handle: &'a mut Self::CodegenObjectBuildHandle,
        dependency_interfaces: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()>;

    fn finish_codegen_object<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        handle: Self::CodegenObjectBuildHandle,
    ) -> SourcePackBoxFuture<'a, Self::CodegenObjectArtifact>;

    fn begin_link_codegen_objects<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
    ) -> SourcePackBoxFuture<'a, Self::LinkHandle>;

    fn link_library_interface_batch<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        link_handle: &'a mut Self::LinkHandle,
        batch: &'a SourcePackLinkInterfaceBatch,
        library_interfaces: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()>;

    fn link_codegen_object_batch<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        link_handle: &'a mut Self::LinkHandle,
        batch: &'a SourcePackLinkObjectBatch,
        codegen_objects: &'a [Self::CodegenObjectArtifact],
    ) -> SourcePackBoxFuture<'a, ()>;

    fn finish_link_codegen_objects<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        link_handle: Self::LinkHandle,
    ) -> SourcePackBoxFuture<'a, Self::LinkedOutputArtifact>;
}

pub trait SourcePackPathHierarchicalLinkExecutor: SourcePackPathArtifactBuildExecutor {
    type PartialLinkArtifact;

    fn begin_hierarchical_link_group(
        &mut self,
        page: &SourcePackHierarchicalLinkExecutionPage,
    ) -> Result<Self::LinkHandle, CompileError>;

    fn link_hierarchical_library_interfaces(
        &mut self,
        page: &SourcePackHierarchicalLinkExecutionPage,
        link_handle: &mut Self::LinkHandle,
        library_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<(), CompileError>;

    fn link_hierarchical_codegen_objects(
        &mut self,
        page: &SourcePackHierarchicalLinkExecutionPage,
        link_handle: &mut Self::LinkHandle,
        codegen_objects: &[Self::CodegenObjectArtifact],
    ) -> Result<(), CompileError>;

    fn link_hierarchical_partial_links(
        &mut self,
        page: &SourcePackHierarchicalLinkExecutionPage,
        link_handle: &mut Self::LinkHandle,
        partial_links: &[Self::PartialLinkArtifact],
    ) -> Result<(), CompileError>;

    fn finish_hierarchical_partial_link_group(
        &mut self,
        page: &SourcePackHierarchicalLinkExecutionPage,
        link_handle: Self::LinkHandle,
    ) -> Result<Self::PartialLinkArtifact, CompileError>;

    fn finish_hierarchical_link_output(
        &mut self,
        page: &SourcePackHierarchicalLinkExecutionPage,
        link_handle: Self::LinkHandle,
    ) -> Result<Self::LinkedOutputArtifact, CompileError>;
}

pub trait SourcePackPathPagedHierarchicalLinkExecutor:
    SourcePackPathPagedArtifactBuildExecutor + SourcePackPathHierarchicalLinkExecutor
{
}

impl<T> SourcePackPathPagedHierarchicalLinkExecutor for T where
    T: SourcePackPathPagedArtifactBuildExecutor + SourcePackPathHierarchicalLinkExecutor
{
}

pub trait SourcePackPathAsyncHierarchicalLinkExecutor:
    SourcePackPathAsyncPagedArtifactBuildExecutor
{
    type PartialLinkArtifact;

    fn begin_hierarchical_link_group<'a>(
        &'a mut self,
        page: &'a SourcePackHierarchicalLinkExecutionPage,
    ) -> SourcePackBoxFuture<'a, Self::LinkHandle>;

    fn link_hierarchical_library_interfaces<'a>(
        &'a mut self,
        page: &'a SourcePackHierarchicalLinkExecutionPage,
        link_handle: &'a mut Self::LinkHandle,
        library_interfaces: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()>;

    fn link_hierarchical_codegen_objects<'a>(
        &'a mut self,
        page: &'a SourcePackHierarchicalLinkExecutionPage,
        link_handle: &'a mut Self::LinkHandle,
        codegen_objects: &'a [Self::CodegenObjectArtifact],
    ) -> SourcePackBoxFuture<'a, ()>;

    fn link_hierarchical_partial_links<'a>(
        &'a mut self,
        page: &'a SourcePackHierarchicalLinkExecutionPage,
        link_handle: &'a mut Self::LinkHandle,
        partial_links: &'a [Self::PartialLinkArtifact],
    ) -> SourcePackBoxFuture<'a, ()>;

    fn finish_hierarchical_partial_link_group<'a>(
        &'a mut self,
        page: &'a SourcePackHierarchicalLinkExecutionPage,
        link_handle: Self::LinkHandle,
    ) -> SourcePackBoxFuture<'a, Self::PartialLinkArtifact>;

    fn finish_hierarchical_link_output<'a>(
        &'a mut self,
        page: &'a SourcePackHierarchicalLinkExecutionPage,
        link_handle: Self::LinkHandle,
    ) -> SourcePackBoxFuture<'a, Self::LinkedOutputArtifact>;
}

pub trait SourcePackPathAsyncPagedHierarchicalLinkExecutor:
    SourcePackPathAsyncPagedArtifactBuildExecutor + SourcePackPathAsyncHierarchicalLinkExecutor
{
}

impl<T> SourcePackPathAsyncPagedHierarchicalLinkExecutor for T where
    T: SourcePackPathAsyncPagedArtifactBuildExecutor + SourcePackPathAsyncHierarchicalLinkExecutor
{
}

pub trait SourcePackPathArtifactStore {
    type LibraryInterfaceArtifact;
    type CodegenObjectArtifact;
    type LinkedOutputArtifact;

    fn load_library_interface(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<Self::LibraryInterfaceArtifact, CompileError>;

    fn store_library_interface(
        &mut self,
        artifact: &SourcePackArtifactRef,
        interface: Self::LibraryInterfaceArtifact,
    ) -> Result<(), CompileError>;

    fn release_library_interface(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<(), CompileError>;

    fn load_codegen_object(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<Self::CodegenObjectArtifact, CompileError>;

    fn store_codegen_object(
        &mut self,
        artifact: &SourcePackArtifactRef,
        object: Self::CodegenObjectArtifact,
    ) -> Result<(), CompileError>;

    fn release_codegen_object(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<(), CompileError>;

    fn store_linked_output(
        &mut self,
        artifact: &SourcePackArtifactRef,
        output: Self::LinkedOutputArtifact,
    ) -> Result<(), CompileError>;
}

pub trait SourcePackPathHierarchicalLinkArtifactStore: SourcePackPathArtifactStore {
    type PartialLinkArtifact;

    fn load_partial_link_output(
        &mut self,
        key: &str,
    ) -> Result<Self::PartialLinkArtifact, CompileError>;

    fn store_partial_link_output(
        &mut self,
        key: &str,
        output: Self::PartialLinkArtifact,
    ) -> Result<(), CompileError>;

    fn store_hierarchical_linked_output(
        &mut self,
        key: &str,
        output: Self::LinkedOutputArtifact,
    ) -> Result<(), CompileError>;
}

pub trait SourcePackFilesystemExecutionShardLoader {
    fn load_execution_shard(
        &self,
        target: SourcePackArtifactTarget,
        shard_index: usize,
    ) -> Result<SourcePackBuildArtifactExecutionShard, CompileError>;

    fn load_source_file_for_index(
        &self,
        target: SourcePackArtifactTarget,
        source_index: usize,
    ) -> Result<ExplicitSourcePathFile, CompileError>;

    fn load_job_artifact_input_interface_page(
        &self,
        target: SourcePackArtifactTarget,
        job_index: usize,
        page_index: usize,
    ) -> Result<SourcePackJobArtifactInputInterfacePage, CompileError>;

    fn load_build_artifact_ref_index(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildArtifactRefIndex, CompileError>;

    fn load_build_artifact_ref_page(
        &self,
        target: SourcePackArtifactTarget,
        artifact_index: usize,
        artifact_count: usize,
    ) -> Result<SourcePackBuildArtifactRefPage, CompileError>;

    fn load_hierarchical_link_execution_interface_page(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        page_index: usize,
    ) -> Result<SourcePackHierarchicalLinkExecutionInterfacePage, CompileError>;

    fn load_hierarchical_link_execution_object_page(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        page_index: usize,
    ) -> Result<SourcePackHierarchicalLinkExecutionObjectPage, CompileError>;

    fn load_hierarchical_link_execution_partial_page(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        page_index: usize,
    ) -> Result<SourcePackHierarchicalLinkExecutionPartialPage, CompileError>;

    fn load_source_files_for_range(
        &self,
        target: SourcePackArtifactTarget,
        first_source_index: usize,
        source_file_count: usize,
    ) -> Result<Vec<ExplicitSourcePathFile>, CompileError> {
        let source_end = first_source_index
            .checked_add(source_file_count)
            .ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack source range {first_source_index}+{source_file_count} overflows"
                ))
            })?;
        let mut files = Vec::with_capacity(source_file_count);
        for source_index in first_source_index..source_end {
            files.push(self.load_source_file_for_index(target, source_index)?);
        }
        validate_explicit_source_path_files_metadata("source-pack job", &files)?;
        Ok(files)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackBuildExecutionResult<LibraryInterface, CodegenObject, LinkedOutput> {
    pub library_interfaces: Vec<LibraryInterface>,
    pub codegen_objects: Vec<CodegenObject>,
    pub linked_output: LinkedOutput,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackHandleBuildExecutionResult<LinkedOutput> {
    pub linked_output: LinkedOutput,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackArtifactStoreBuildExecutionResult {
    pub linked_output_key: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackArtifactStoreBatchExecutionResult {
    pub batch_index: usize,
    pub job_count: usize,
    pub linked_output_key: Option<String>,
}
