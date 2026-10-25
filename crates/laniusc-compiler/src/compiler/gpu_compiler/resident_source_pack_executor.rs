use std::sync::Arc;

use super::{
    source_pack_executor::validate_gpu_source_pack_descriptor_job_source_file_records,
    typecheck::{CompiledSourcePackObject, CompiledSourcePackUnit, OriginalUnitFacts, PendingOriginalUnit},
    *,
};

/// Executes a dependency-ordered source-pack build retaining its interfaces,
/// backend objects, and original source and dependency snapshots in host memory.
///
/// This is the ordinary daemon path for a multi-library project that fits the
/// resident source-unit capacity. Larger projects use the durable file-backed
/// executor so compact artifacts do not grow with the whole project.
pub(super) struct ResidentSourcePackExecutor<'compiler, 'gpu> {
    compiler: &'compiler GpuCompiler<'gpu>,
    target: SourcePackArtifactTarget,
    // Native originals stay owned here until complete program admission. Their
    // cloneable build handles expose facts and an exact slot, never object bytes.
    pending_originals: Vec<PendingOriginalUnit>,
    // When set, the link writes the final pages straight into this file
    // (through a sibling temporary renamed into place) instead of returning
    // the image as bytes.
    output_file: Option<std::path::PathBuf>,
    // The manifest's standard library (`standard_library_id`): only its units
    // enter the warm caches that survive a project clear.
    standard_library_id: Option<u32>,
    native_link: Option<NativeLinkOptions>,
}

/// The linked program: its bytes, or the byte length already written to the
/// executor's output file.
pub(super) enum ResidentLinkedOutput {
    Bytes(Vec<u8>),
    File(u64),
}

#[derive(Clone)]
pub(super) enum ResidentSourcePackArtifact {
    PendingNative(PendingNativeArtifact),
    StrictPublished(Arc<CompiledSourcePackUnit>),
}

#[derive(Clone)]
pub(super) struct PendingNativeArtifact {
    slot: usize,
    facts: OriginalUnitFacts,
}

impl ResidentSourcePackArtifact {
    fn interface(&self) -> &GpuSemanticInterfaceArtifact {
        match self {
            Self::PendingNative(handle) => handle.facts.interface(),
            Self::StrictPublished(unit) => &unit.interface,
        }
    }
}

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
        Self { compiler, target, pending_originals: Vec::new(), output_file: None, standard_library_id: None, native_link: None }
    }

    pub(super) fn with_output_file(
        compiler: &'compiler GpuCompiler<'gpu>,
        target: SourcePackArtifactTarget,
        output: &std::path::Path,
    ) -> Self {
        Self { output_file: Some(output.to_path_buf()), ..Self::new(compiler, target) }
    }

    /// Names the manifest's standard library (its `standard_library_id`).
    pub(super) fn with_standard_library(mut self, standard_library_id: Option<u32>) -> Self {
        self.standard_library_id = standard_library_id;
        self
    }

    pub(super) fn with_native_link(mut self, options: &NativeLinkOptions) -> Self {
        self.native_link = Some(options.clone());
        self
    }

    async fn compile_unit(
        &mut self,
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
                    .map(|artifact| artifact.interface().clone())
                    .collect::<Vec<_>>()
            })
            .collect::<Vec<_>>();
        let standard_library = self.standard_library_id == Some(handle.job.library_id);
        // Both targets admit the whole program before publishing any unit,
        // so generic bodies specialize alike. A standard-library unit may
        // reuse an earlier job's pending original; it is admitted with the
        // rest of this program at link.
        let pending = if self.native_link.is_some() {
            // The native profile spills before any cache or pending inventory
            // can retain its section vectors. Checked source facts still own
            // their exact source and dependency snapshots for admission.
            self.compiler.compile_file_pending_native_unit(
                &handle.job, &handle.source_files, dependency_pages.into(),
            ).await?
        } else {
            self.compiler.compile_cached_pending_original_unit(
                self.target, &handle.job, standard_library, &handle.source_files, dependency_pages.into(),
            ).await?
        };
        let artifact = PendingNativeArtifact {
            slot: self.pending_originals.len(), facts: pending.facts().clone(),
        };
        self.pending_originals.push(pending);
        Ok(ResidentSourcePackArtifact::PendingNative(artifact))
    }

    async fn link(&mut self, handle: ResidentLinkHandle) -> Result<ResidentLinkedOutput, CompileError> {
        // Require the exact complete pending inventory before moving any
        // wrapper into the session's private publication boundary.
        let mut present = vec![false; self.pending_originals.len()];
        for artifact in &handle.objects {
            let ResidentSourcePackArtifact::PendingNative(artifact) = artifact else {
                return Err(source_pack_artifact_store_error(
                    "pending native link received a published object"));
            };
            let pending = self.pending_originals.get(artifact.slot).ok_or_else(||
                source_pack_artifact_store_error("pending native link has a foreign unit slot"))?;
            if !pending.facts().same_snapshot(&artifact.facts) {
                return Err(source_pack_artifact_store_error(
                    "pending native link has a foreign source snapshot"));
            }
            present[artifact.slot] = true;
        }
        if present.iter().any(|included| !included) {
            return Err(source_pack_artifact_store_error(
                "pending native link omitted an original source unit"));
        }
        // Keep source-checked C declarations tied to the exact original unit
        // snapshots admitted below, including private declarations. Generic
        // replays retain those original foreign identities.
        let mut native_functions = Vec::new();
        if self.target == SourcePackArtifactTarget::X86_64 {
            for pending in &self.pending_originals {
                native_functions.extend(pending.facts().interface().native_c_functions()
                    .map_err(source_pack_artifact_store_error)?);
            }
            if self.native_link.is_none() && !native_functions.is_empty() {
                return Err(CompileError::GpuCodegen(
                    "C extern declarations require the native linking profile; use --native-link and explicit --native-library inputs".into()));
            }
        }
        let pending = std::mem::take(&mut self.pending_originals);
        if let Some(options) = &self.native_link {
            let objects = self.compiler.specialize_spilled_native_objects(pending).await?;
            let bridge = super::native_codegen::native_main_bridge(&objects)?;
            let executable = x86::native::link_native_file_executable(
                &objects, &native_functions, bridge, options,
            ).map_err(|error| super::x86_codegen::x86_source_pack_link_error(
                "link native C executable", error))?;
            return match &self.output_file {
                Some(path) => super::bounded_path_codegen::write_output_file_atomically(
                    path, self.target, |file| executable.write_to(file).map_err(|error|
                        super::x86_codegen::x86_source_pack_link_error("write native C executable", error)),
                ).map(ResidentLinkedOutput::File),
                None => executable.read_bytes(options.max_output_bytes)
                    .map(ResidentLinkedOutput::Bytes)
                    .map_err(|error| super::x86_codegen::x86_source_pack_link_error(
                        "read native C executable", error)),
            };
        }
        let objects = self.compiler.specialize_pending_source_pack_objects(pending).await?;
        match self.target {
            SourcePackArtifactTarget::X86_64 => {
                let objects = objects.into_iter().map(|object| match object {
                    CompiledSourcePackObject::X86_64(object) => Ok(object),
                    CompiledSourcePackObject::Wasm(_) | CompiledSourcePackObject::X86_64File(_) => Err(source_pack_artifact_store_error(
                        "resident x86_64 source-pack link received a different object storage")),
                }).collect::<Result<Vec<_>, _>>()?;
                let input_span = crate::gpu::trace::HostSpan::new("host.compiler", "codegen.x86.link.input");
                let input = x86::GpuX86LinkInput::for_executable_refs(objects.iter())
                    .map_err(|error| super::x86_codegen::x86_link_input_error(error, None))?;
                drop(input_span);
                let linker = self.compiler.x86_linker().map_err(|reason| {
                    source_pack_artifact_store_error(format!(
                        "initialize resident x86_64 source-pack linker: {reason}"
                    ))
                })?;
                let _resident_guard = self.compiler.resident_pipeline_lock.lock().await;
                let (device, queue) = (&self.compiler.gpu.device, &self.compiler.gpu.queue);
                let link_error = |err| {
                    super::x86_codegen::x86_source_pack_link_error(
                        "execute resident x86_64 source-pack linker",
                        err,
                    )
                };
                match &self.output_file {
                    Some(path) => super::bounded_path_codegen::write_output_file_atomically(
                        path,
                        self.target,
                        |file| {
                            linker
                                .link_executable_to_writer(device, queue, &input, file)
                                .map(|len| len as u64)
                                .map_err(link_error)
                        },
                    )
                    .map(ResidentLinkedOutput::File),
                    None => linker
                        .link_executable(device, queue, &input)
                        .map(ResidentLinkedOutput::Bytes)
                        .map_err(link_error),
                }
            }
            SourcePackArtifactTarget::Wasm => {
                let objects = objects.iter().map(|object| match object {
                    CompiledSourcePackObject::Wasm(object) => Ok(object),
                    CompiledSourcePackObject::X86_64(_) | CompiledSourcePackObject::X86_64File(_) => Err(source_pack_artifact_store_error(
                        "resident Wasm source-pack link received an x86_64 object")),
                }).collect::<Result<Vec<_>, _>>()?;
                let input = wasm::GpuWasmLinkInput::for_executable_refs(objects)
                    .map_err(super::wasm_codegen::wasm_link_input_error)?;
                let linker = self.compiler.wasm_linker().map_err(|reason| {
                    source_pack_artifact_store_error(format!(
                        "initialize resident Wasm source-pack linker: {reason}"
                    ))
                })?;
                let _resident_guard = self.compiler.resident_pipeline_lock.lock().await;
                let (device, queue) = (&self.compiler.gpu.device, &self.compiler.gpu.queue);
                let link_error = |err| {
                    source_pack_artifact_store_error(format!(
                        "execute resident Wasm source-pack linker: {err}"
                    ))
                };
                match &self.output_file {
                    Some(path) => super::bounded_path_codegen::write_output_file_atomically(
                        path,
                        self.target,
                        |file| {
                            linker
                                .link_executable_to_writer(device, queue, &input, file)
                                .map(|len| len as u64)
                                .map_err(link_error)
                        },
                    )
                    .map(ResidentLinkedOutput::File),
                    None => linker
                        .link_executable(device, queue, &input)
                        .map(ResidentLinkedOutput::Bytes)
                        .map_err(link_error),
                }
            }
            SourcePackArtifactTarget::Generic => unreachable!("resident target is concrete"),
        }
    }
}

impl AsyncPagedArtifactBuildExecutor for ResidentSourcePackExecutor<'_, '_> {
    type LibraryInterfaceArtifact = ResidentSourcePackArtifact;
    type CodegenObjectArtifact = ResidentSourcePackArtifact;
    type LinkHandle = ResidentLinkHandle;
    type LinkedOutputArtifact = ResidentLinkedOutput;
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
