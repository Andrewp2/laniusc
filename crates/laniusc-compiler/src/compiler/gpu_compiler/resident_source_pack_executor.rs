use std::sync::Arc;

use super::{
    source_pack_executor::validate_gpu_source_pack_descriptor_job_source_file_records,
    typecheck::{CompiledSourcePackObject, CompiledSourcePackUnit},
    *,
};

/// Executes a dependency-ordered source-pack build while retaining only its
/// compact semantic interfaces and backend objects in host memory.
///
/// This is the ordinary daemon path for a multi-library project that fits the
/// resident source-unit capacity. Larger projects use the durable file-backed
/// executor so compact artifacts do not grow with the whole project.
pub(super) struct ResidentSourcePackExecutor<'compiler, 'gpu> {
    compiler: &'compiler GpuCompiler<'gpu>,
    target: SourcePackArtifactTarget,
}

#[derive(Clone)]
pub(super) struct ResidentSourcePackArtifact(Arc<CompiledSourcePackUnit>);

pub(super) struct ResidentLibraryBuildHandle {
    job: SourcePackJob,
    source_files: Vec<ExplicitSourcePathFile>,
    dependency_pages: Vec<Vec<ResidentSourcePackArtifact>>,
}

pub(super) struct ResidentCodegenBuildHandle {
    unit: ResidentSourcePackArtifact,
}

#[derive(Default)]
pub(super) struct ResidentLinkHandle {
    objects: Vec<ResidentSourcePackArtifact>,
}

impl<'compiler, 'gpu> ResidentSourcePackExecutor<'compiler, 'gpu> {
    pub(super) fn new(
        compiler: &'compiler GpuCompiler<'gpu>,
        target: SourcePackArtifactTarget,
    ) -> Self {
        debug_assert_ne!(target, SourcePackArtifactTarget::Generic);
        Self { compiler, target }
    }

    async fn compile_unit(
        &self,
        handle: ResidentLibraryBuildHandle,
    ) -> Result<ResidentSourcePackArtifact, CompileError> {
        validate_gpu_source_pack_descriptor_job_source_file_records(
            "library-interface",
            &handle.job,
            &handle.source_files,
        )?;
        let dependency_pages = handle
            .dependency_pages
            .iter()
            .map(|page| {
                page.iter()
                    .map(|artifact| artifact.0.interface.clone())
                    .collect::<Vec<_>>()
            })
            .collect::<Vec<_>>();
        self.compiler
            .compile_cached_path_source_pack_unit(
                self.target,
                &handle.job,
                &handle.source_files,
                &dependency_pages,
            )
            .await
            .map(|compiled| ResidentSourcePackArtifact(compiled.value))
    }

    async fn link(&self, handle: ResidentLinkHandle) -> Result<Vec<u8>, CompileError> {
        match self.target {
            SourcePackArtifactTarget::X86_64 => {
                let objects = handle
                    .objects
                    .iter()
                    .map(|artifact| match &artifact.0.object {
                        CompiledSourcePackObject::X86_64(object) => Ok(object),
                        CompiledSourcePackObject::Wasm(_) => {
                            Err("resident x86_64 source-pack link received a Wasm object")
                        }
                    })
                    .collect::<Result<Vec<_>, _>>()
                    .map_err(source_pack_artifact_store_error)?;
                let input = x86::GpuX86LinkInput::for_executable_refs(objects)
                    .map_err(source_pack_artifact_store_error)?;
                let linker = self.compiler.x86_linker().map_err(|reason| {
                    source_pack_artifact_store_error(format!(
                        "initialize resident x86_64 source-pack linker: {reason}"
                    ))
                })?;
                let _resident_guard = self.compiler.resident_pipeline_lock.lock().await;
                linker
                    .link_executable(&self.compiler.gpu.device, &self.compiler.gpu.queue, &input)
                    .map_err(|err| {
                        source_pack_artifact_store_error(format!(
                            "execute resident x86_64 source-pack linker: {err}"
                        ))
                    })
            }
            SourcePackArtifactTarget::Wasm => {
                let objects = handle
                    .objects
                    .iter()
                    .map(|artifact| match &artifact.0.object {
                        CompiledSourcePackObject::Wasm(object) => Ok(object),
                        CompiledSourcePackObject::X86_64(_) => {
                            Err("resident Wasm source-pack link received an x86_64 object")
                        }
                    })
                    .collect::<Result<Vec<_>, _>>()
                    .map_err(source_pack_artifact_store_error)?;
                let input = wasm::GpuWasmLinkInput::for_executable_refs(objects)
                    .map_err(source_pack_artifact_store_error)?;
                let linker = self.compiler.wasm_linker().map_err(|reason| {
                    source_pack_artifact_store_error(format!(
                        "initialize resident Wasm source-pack linker: {reason}"
                    ))
                })?;
                let _resident_guard = self.compiler.resident_pipeline_lock.lock().await;
                linker
                    .link_executable(&self.compiler.gpu.device, &self.compiler.gpu.queue, &input)
                    .map_err(|err| {
                        source_pack_artifact_store_error(format!(
                            "execute resident Wasm source-pack linker: {err}"
                        ))
                    })
            }
            SourcePackArtifactTarget::Generic => unreachable!("resident target is concrete"),
        }
    }
}

impl AsyncPagedArtifactBuildExecutor for ResidentSourcePackExecutor<'_, '_> {
    type LibraryInterfaceArtifact = ResidentSourcePackArtifact;
    type CodegenObjectArtifact = ResidentSourcePackArtifact;
    type LinkHandle = ResidentLinkHandle;
    type LinkedOutputArtifact = Vec<u8>;
    type LibraryInterfaceBuildHandle = ResidentLibraryBuildHandle;
    type CodegenObjectBuildHandle = ResidentCodegenBuildHandle;

    fn begin_library_interface<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        source_files: &'a [ExplicitSourcePathFile],
    ) -> SourcePackBoxFuture<'a, Self::LibraryInterfaceBuildHandle> {
        Box::pin(async move {
            Ok(ResidentLibraryBuildHandle {
                job: job.clone(),
                source_files: source_files.to_vec(),
                dependency_pages: Vec::new(),
            })
        })
    }

    fn add_library_interface_dependency_batch<'a>(
        &'a mut self,
        _job: &'a SourcePackJob,
        handle: &'a mut Self::LibraryInterfaceBuildHandle,
        dependencies: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            if !dependencies.is_empty() {
                handle.dependency_pages.push(dependencies.to_vec());
            }
            Ok(())
        })
    }

    fn finish_library_interface<'a>(
        &'a mut self,
        _job: &'a SourcePackJob,
        handle: Self::LibraryInterfaceBuildHandle,
    ) -> SourcePackBoxFuture<'a, Self::LibraryInterfaceArtifact> {
        Box::pin(async move { self.compile_unit(handle).await })
    }

    fn begin_codegen_object<'a>(
        &'a mut self,
        _job: &'a SourcePackJob,
        _source_files: &'a [ExplicitSourcePathFile],
        library_interface: &'a Self::LibraryInterfaceArtifact,
    ) -> SourcePackBoxFuture<'a, Self::CodegenObjectBuildHandle> {
        let unit = library_interface.clone();
        Box::pin(async move { Ok(ResidentCodegenBuildHandle { unit }) })
    }

    fn add_codegen_object_dependency_batch<'a>(
        &'a mut self,
        _job: &'a SourcePackJob,
        _handle: &'a mut Self::CodegenObjectBuildHandle,
        _dependencies: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move { Ok(()) })
    }

    fn finish_codegen_object<'a>(
        &'a mut self,
        _job: &'a SourcePackJob,
        handle: Self::CodegenObjectBuildHandle,
    ) -> SourcePackBoxFuture<'a, Self::CodegenObjectArtifact> {
        Box::pin(async move { Ok(handle.unit) })
    }

    fn begin_link_codegen_objects<'a>(
        &'a mut self,
        _job: &'a SourcePackJob,
    ) -> SourcePackBoxFuture<'a, Self::LinkHandle> {
        Box::pin(async move { Ok(ResidentLinkHandle::default()) })
    }

    fn link_library_interface_batch<'a>(
        &'a mut self,
        _job: &'a SourcePackJob,
        _link_handle: &'a mut Self::LinkHandle,
        _batch: &'a SourcePackLinkInterfaceBatch,
        _interfaces: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move { Ok(()) })
    }

    fn link_codegen_object_batch<'a>(
        &'a mut self,
        _job: &'a SourcePackJob,
        link_handle: &'a mut Self::LinkHandle,
        _batch: &'a SourcePackLinkObjectBatch,
        objects: &'a [Self::CodegenObjectArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            link_handle.objects.extend_from_slice(objects);
            Ok(())
        })
    }

    fn finish_link_codegen_objects<'a>(
        &'a mut self,
        _job: &'a SourcePackJob,
        handle: Self::LinkHandle,
    ) -> SourcePackBoxFuture<'a, Self::LinkedOutputArtifact> {
        Box::pin(async move { self.link(handle).await })
    }
}
