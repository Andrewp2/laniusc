use super::{
    source_pack_executor::validate_gpu_source_pack_descriptor_job_source_file_records,
    typecheck::{CompiledSourcePackObject, OriginalUnitFacts, PendingOriginalUnit},
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
    native_link: Option<NativeLinkOptions>,
    retained_originals: Option<Vec<CompiledSourcePackObject>>,
    retained_spill: super::typecheck::NativeObjectStore,
    retained_native_functions: Vec<NativeCFunction>,
    retained_sources: Vec<super::retained_native::RetainedDiagnosticSources>,
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
        Self {
            compiler, target, pending_originals: Vec::new(), native_link: None,
            retained_originals: None, retained_spill: super::typecheck::NativeObjectStore::Keep,
            retained_native_functions: Vec::new(),
            retained_sources: Vec::new(),
        }
    }

    /// Spill original x86 sections after each unit; semantic templates stay
    /// in the build-scoped GPU store.
    pub(super) fn spill_objects(mut self, spill:super::typecheck::NativeObjectStore)->Self {
        self.retained_spill=spill;
        self
    }

    /// The original objects of a retained build's link.
    pub(super) fn take_retained_originals(&mut self) -> Option<Vec<CompiledSourcePackObject>> {
        self.retained_originals.take()
    }

    pub(super) fn take_retained_native_functions(&mut self) -> Vec<NativeCFunction> {
        std::mem::take(&mut self.retained_native_functions)
    }

    pub(super) fn take_retained_sources(&mut self) -> Vec<super::retained_native::RetainedDiagnosticSources> {
        std::mem::take(&mut self.retained_sources)
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
        let pending=self.compiler.compile_pending_unit(self.target,&handle.job,&handle.source_files,
            dependency_pages.into(),self.retained_spill).await?;
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
            let ResidentSourcePackArtifact::PendingNative(artifact) = artifact;
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
        // instances retain those original foreign identities.
        let mut native_functions = Vec::new();
        if self.target == SourcePackArtifactTarget::X86_64 {
            for pending in &self.pending_originals {
                native_functions.extend(pending.facts().native_c_functions()
                    .map_err(source_pack_artifact_store_error)?);
            }
            if self.native_link.is_none() && !native_functions.is_empty() {
                return Err(super::x86_codegen::x86_native_link_required_error(&native_functions));
            }
        }
        let pending = std::mem::take(&mut self.pending_originals);
        self.retained_sources=pending.iter().map(|p|super::retained_native::RetainedDiagnosticSources::of(p.facts())).collect();
        self.retained_originals=Some(pending.into_iter().map(PendingOriginalUnit::release_closed).collect());
        self.retained_native_functions=native_functions;
        Ok(ResidentLinkedOutput::Bytes(Vec::new()))
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
