//! Retained native builds (docs/compiler-retained-projection.md, "Native
//! compilation").
//!
//! A retained build compiles each source unit once with the ordinary
//! resident source-pack machinery and a program retention store attached.
//! Its original objects define the unit's nongeneric functions only; each
//! call to a generic template is an undefined symbol that the GPU made
//! provisional right after the unit's export (`program_retention::native_calls`).
//! At link, GPU catalog admission checks whole-program coherence, discovery
//! publishes the closed instances and one root route per build-global use,
//! projection checks and lowers the
//! instances and certifies every recorded root call against its target, the
//! GPU finalizer rewrites the provisional symbols to their routes, and the
//! ordinary x86 linker links the original and instance objects.
//!
//! No step replays a source or falls back to a frontend: a rejected
//! catalog, discovery, projection, certification or finalization fails the build.

use std::{num::NonZeroU32, sync::Arc};

use super::{
    resident_source_pack_executor::{ResidentLinkedOutput, ResidentSourcePackExecutor},
    typecheck::CompiledSourcePackObject,
    *,
};
use crate::{
    codegen::x86::{
        finalize::{GpuX86SymbolFinalizer, X86RouteTable, X86SymbolColumns},
    },
    type_checker::program_retention::{
        NativeCallTables,
        ProgramRetention,
        ProgramRetentionCapacity,
        discovery::{DiscoveryCapacity, DiscoveryOutcome, DiscoveryReport, RetainedDiscovery},
        projection::{
            ProjectionOptions,
            ProjectionOutcome,
            ProjectionReport,
            RetainedProjection,
            RootCertification,
            error,
        },
        substitution::SubstitutionCapacity,
    },
};

/// Figures of the last retained build.
#[derive(Clone, Debug, Default)]
pub struct RetainedNativeReport {
    /// Original objects, one per frontend unit.
    pub units: usize,
    /// Instance objects (projection batches).
    pub instance_objects: usize,
    /// Objects whose section bytes were spilled before the next unit or batch.
    pub spilled_objects: usize,
    /// GPU catalog admission, coherence and proof receipts. Semantic rows
    /// stay on the GPU (`read_rows` is false).
    pub catalog: Option<RetainedTraitCheck>,
    pub discovery: DiscoveryReport,
    pub projection: ProjectionReport,
}

/// The state of retained builds that reuse one store, discovery,
/// projection and finalizer allocation.
pub struct RetainedNativeBuild {
    store: Arc<ProgramRetention>,
    projection: RetainedProjection,
    finalizer: Option<GpuX86SymbolFinalizer>,
    discovery: RetainedDiscovery,
    calls: Option<NativeCallTables>,
    sources: Vec<RetainedDiagnosticSources>,
    pub options: ProjectionOptions,
    pub report: RetainedNativeReport,
    pub native_link: Option<NativeLinkOptions>,
    /// Fault injection for tests: before the link, every recorded caller
    /// argument term becomes this term.
    #[doc(hidden)]
    pub test_caller_arg_fault: Option<u32>,
}

impl RetainedNativeBuild {
    pub fn new(discovery: DiscoveryCapacity) -> anyhow::Result<Self> {
        Self::new_with_device(crate::gpu::device::global(), discovery)
    }

    pub fn new_with_device(gpu: &crate::gpu::device::GpuDevice, discovery: DiscoveryCapacity) -> anyhow::Result<Self> {
        let store = ProgramRetention::new_native(gpu, ProgramRetentionCapacity::default())?;
        let uses = store.capacity().0.arenas[8];
        Ok(Self {
            store,
            projection: RetainedProjection::new_with_device(gpu, SubstitutionCapacity::default())?,
            finalizer: None,
            discovery: RetainedDiscovery::new_with_device(gpu, discovery, SubstitutionCapacity::default())?,
            calls: Some(NativeCallTables::new_with_device(&gpu.device, uses)),
            sources: Vec::new(),
            options: ProjectionOptions::default(),
            report: RetainedNativeReport::default(),
            native_link: None,
            test_caller_arg_fault: None,
        })
    }

    pub fn store(&self) -> &Arc<ProgramRetention> {
        &self.store
    }
}

fn retained_error(context: &str, error: impl std::fmt::Display) -> CompileError {
    CompileError::GpuCodegen(format!("retained native build: {context}: {error}"))
}

/// Source text is retained only for rendering a GPU-selected diagnostic.
/// No instance body or environment is reconstructed from these inputs.
pub(super) struct RetainedDiagnosticSources {
    texts: Arc<[String]>,
    paths: Arc<[Option<PathBuf>]>,
}

impl RetainedDiagnosticSources {
    pub(super) fn of(facts: &typecheck::OriginalUnitFacts) -> Self {
        Self { texts: facts.template_sources().clone(), paths: facts.template_source_paths().clone() }
    }
}

impl RetainedNativeBuild {
    fn source_diagnostic(&self, span: [u32;4], code: gpu_type_checker::GpuTypeCheckCode, detail:u32) -> Option<CompileError> {
        let [job,file,byte,len] = span;
        let unit = self.sources.get(job as usize)?;
        let source = unit.texts.get(file as usize)?;
        let path = unit.paths.get(file as usize).and_then(Option::as_deref).unwrap_or(Path::new("<source>"));
        Some(typecheck::type_check_diagnostic_at_span(path,source,byte as usize,len as usize,code,detail))
    }

    fn projection_error(&self, e: crate::type_checker::program_retention::projection::ProjectionError) -> CompileError {
        if e.code == error::SUBST && e.detail == 11
            && let Some(error) = self.source_diagnostic([e.job,e.file,e.byte,e.len],
                gpu_type_checker::GpuTypeCheckCode::GenericInstantiationBoundary,0)
        { return error; }
        if e.code == error::RULE
            && let Some(unit) = self.sources.get(e.job as usize)
            && let Some(source) = unit.texts.get(e.file as usize)
        {
            let code = match e.detail >> 24 {
                error::RULE_ASSIGN_MISMATCH => gpu_type_checker::GpuTypeCheckCode::AssignMismatch,
                error::RULE_INTEGER_RANGE => gpu_type_checker::GpuTypeCheckCode::IntegerLiteralRange,
                error::RULE_FLOAT_LITERAL => gpu_type_checker::GpuTypeCheckCode::FloatLiteral,
                _ => return retained_error("instance language rule", e),
            };
            let path = unit.paths.get(e.file as usize).and_then(Option::as_deref).unwrap_or(Path::new("<source>"));
            return typecheck::type_check_diagnostic_at_span(path, source, e.byte as usize,
                e.len as usize, code, e.detail & 0xffffff);
        }
        retained_error("projection rejected the program", e)
    }
}

impl GpuCompiler<'_> {
    pub(super) async fn compile_native_program(
        &self,
        source_pack: &ExplicitSourcePackPathManifest,
        options: Option<&NativeLinkOptions>,
        output: Option<&Path>,
    ) -> Result<ResidentLinkedOutput, CompileError> {
        self.compile_retained_program(SourcePackArtifactTarget::X86_64,source_pack,options,output).await
    }

    pub(super) async fn compile_retained_program(
        &self,target:SourcePackArtifactTarget,source_pack:&ExplicitSourcePackPathManifest,
        options:Option<&NativeLinkOptions>,output:Option<&Path>,
    )->Result<ResidentLinkedOutput,CompileError> {
        // A program that fits one resident unit compiles as one frontend
        // unit, whatever its libraries: one recording of the frontend, not
        // one per library. Visibility is a module rule, so the unit split does
        // not change it. A program above the resident limits keeps the
        // bounded multi-unit plan.
        let whole_program = super::bounded_path_codegen::whole_program_manifest(
            source_pack, self.resident_source_unit_limits());
        let source_pack = whole_program.as_ref().unwrap_or(source_pack);
        let mut state = self.retained_native_build.lock().await;
        if state.is_none() {
            *state = Some(RetainedNativeBuild::new_with_device(self.gpu, DiscoveryCapacity::default())
                .map_err(|e| retained_error("initialize", e))?);
        }
        let build = state.as_mut().unwrap();
        build.native_link = options.cloned();
        self.compile_retained_output(target,source_pack, build, output).await
    }

    pub(super) async fn compile_native_source_pack<S: AsRef<str>>(
        &self,
        sources: &[S],
        source_paths: Option<&[Option<PathBuf>]>,
    ) -> Result<Vec<u8>, CompileError> {
        self.compile_retained_source_pack(SourcePackArtifactTarget::X86_64,sources,source_paths).await
    }

    pub(super) async fn compile_retained_source_pack<S:AsRef<str>>(
        &self,target:SourcePackArtifactTarget,sources:&[S],source_paths:Option<&[Option<PathBuf>]>,
    )->Result<Vec<u8>,CompileError> {
        let mut state = self.retained_native_build.lock().await;
        if state.is_none() {
            *state = Some(RetainedNativeBuild::new_with_device(self.gpu, DiscoveryCapacity::default())
                .map_err(|e| retained_error("initialize", e))?);
        }
        let build = state.as_mut().unwrap();
        build.native_link = None;
        build.report = RetainedNativeReport::default();
        build.store.begin_build().map_err(|e| retained_error("begin build", e))?;
        *self.retained_native_calls.lock().unwrap() = build.calls.take();
        self.attach_program_retention(Some(build.store.clone()));
        let pending = self.compile_pending_original_source_pack_unit_for_target(
            target,
            sources.iter().map(|s| s.as_ref().to_owned()).collect::<Vec<_>>().into(),
            0, 0, Vec::new().into(), source_paths, false,
        ).await;
        self.attach_program_retention(None);
        build.calls = self.retained_native_calls.lock().unwrap().take();
        let pending = pending?;
        build.sources = vec![RetainedDiagnosticSources::of(pending.facts())];
        let native = pending.facts().native_c_functions().map_err(source_pack_artifact_store_error)?;
        if !native.is_empty() {
            return Err(super::x86_codegen::x86_native_link_required_error(&native));
        }
        match self.link_retained(target,vec![pending.release_closed()], &[], build, false, None)? {
            ResidentLinkedOutput::Bytes(bytes) => Ok(bytes),
            ResidentLinkedOutput::File(_) => unreachable!("no output file requested"),
        }
    }

    /// Preserve the explicit unit/dependency identities of frontend unit tests,
    /// then execute them through the same GPU build/link boundary as the driver.
    #[cfg(test)]
    pub(super) async fn compile_test_units(
        &self, units: &[&typecheck::CompiledSourcePackUnit],
    ) -> Result<Vec<u8>, CompileError> {
        let mut state = self.retained_native_build.lock().await;
        if state.is_none() {
            *state = Some(RetainedNativeBuild::new_with_device(self.gpu, DiscoveryCapacity::default())
                .map_err(|e| retained_error("initialize",e))?);
        }
        let build = state.as_mut().unwrap();
        build.native_link = None;
        build.report = RetainedNativeReport::default();
        build.sources.clear();
        build.store.begin_build().map_err(|e|retained_error("begin build",e))?;
        *self.retained_native_calls.lock().unwrap() = build.calls.take();
        self.attach_program_retention(Some(build.store.clone()));
        let originals = async {
            let mut objects = Vec::new();
            for unit in units {
                let pending = self.compile_pending_original_source_pack_unit_for_target(
                    SourcePackArtifactTarget::X86_64, unit.template_sources.clone(),
                    unit.interface.library_id, unit.interface.unit_id,
                    unit.template_dependency_pages.clone(), Some(&unit.template_source_paths), false,
                ).await?;
                build.sources.push(RetainedDiagnosticSources::of(pending.facts()));
                objects.push(pending.release_closed());
            }
            Ok::<_,CompileError>(objects)
        }.await;
        self.attach_program_retention(None);
        build.calls = self.retained_native_calls.lock().unwrap().take();
        match self.link_retained(SourcePackArtifactTarget::X86_64, originals?, &[], build, false, None)? {
            ResidentLinkedOutput::Bytes(bytes)=>Ok(bytes),
            ResidentLinkedOutput::File(_)=>unreachable!(),
        }
    }

    /// Counters from the last default native build, including GPU instances.
    #[doc(hidden)]
    pub async fn native_monomorphization_report(&self) -> Option<RetainedNativeReport> {
        self.retained_native_build.lock().await.as_ref().map(|b| b.report.clone())
    }

    /// Compiles a path manifest as a retained native build:
    /// one frontend job per unit, no source replay (module documentation).
    pub async fn compile_path_manifest_to_x86_64_retained(
        &self,
        source_pack: &ExplicitSourcePackPathManifest,
        build: &mut RetainedNativeBuild,
    ) -> Result<Vec<u8>, CompileError> {
        match self.compile_retained_output(SourcePackArtifactTarget::X86_64,source_pack, build, None).await? {
            ResidentLinkedOutput::Bytes(bytes) => Ok(bytes),
            ResidentLinkedOutput::File(_) => unreachable!("no output file requested"),
        }
    }

    /// Compiles directly to an atomically replaced executable, spilling each
    /// original and instance batch. The complete image is never read into a Vec.
    pub async fn compile_path_manifest_to_x86_64_retained_to_file(
        &self,
        source_pack: &ExplicitSourcePackPathManifest,
        build: &mut RetainedNativeBuild,
        output: &Path,
    ) -> Result<u64, CompileError> {
        match self.compile_retained_output(SourcePackArtifactTarget::X86_64,source_pack, build, Some(output)).await? {
            ResidentLinkedOutput::File(bytes) => Ok(bytes),
            ResidentLinkedOutput::Bytes(_) => unreachable!("output file requested"),
        }
    }

    async fn compile_retained_output(
        &self,
        target:SourcePackArtifactTarget,
        source_pack: &ExplicitSourcePackPathManifest,
        build: &mut RetainedNativeBuild,
        output: Option<&Path>,
    ) -> Result<ResidentLinkedOutput, CompileError> {
        build.report = RetainedNativeReport::default();
        let limits = self.resident_source_unit_limits();
        let spill = target==SourcePackArtifactTarget::X86_64 && (output.is_some() || build.native_link.is_some()
            || source_pack.requires_bounded_compilation_with_limits(limits));
        build.store.begin_build().map_err(|e| retained_error("begin build", e))?;
        *self.retained_native_calls.lock().unwrap() = build.calls.take();
        self.attach_program_retention(Some(build.store.clone()));
        let originals = self.compile_retained_originals(target,source_pack, limits, build.native_link.as_ref(), spill).await;
        self.attach_program_retention(None);
        build.calls = self.retained_native_calls.lock().unwrap().take();
        let (originals, native_functions, sources) = originals?;
        build.sources = sources;
        self.link_retained(target,originals, &native_functions, build, spill, output)
    }

    async fn compile_retained_originals(
        &self,
        target:SourcePackArtifactTarget,
        source_pack: &ExplicitSourcePackPathManifest,
        limits: CompilationUnitLimits,
        native_link: Option<&NativeLinkOptions>,
        spill: bool,
    ) -> Result<(Vec<CompiledSourcePackObject>, Vec<NativeCFunction>, Vec<RetainedDiagnosticSources>), CompileError> {
        let batch_limits = SourcePackJobBatchLimits::from_codegen_unit_limits(limits);
        let unit_plan = self.stable_frontend_unit_plan(source_pack, limits);
        let build_plan = source_pack.bounded_frontend_build_plan_with_units(unit_plan);
        let mut executor = ResidentSourcePackExecutor::new(self, target)
            .spill_objects(spill);
        if let Some(options) = native_link {
            x86::native::validate_options(options)
                .map_err(|e| retained_error("native link options", e))?;
            executor = executor.with_native_link(options);
        }
        let _prepared = self.prepare_unit_sources(source_pack, &build_plan);
        execute_path_batched_link_build_async(source_pack, &build_plan, batch_limits, &mut executor).await?;
        let originals = executor
            .take_retained_originals()
            .ok_or_else(|| retained_error("link", "the executor published no original objects"))?;
        Ok((originals, executor.take_retained_native_functions(), executor.take_retained_sources()))
    }

    fn link_retained(
        &self,
        target:SourcePackArtifactTarget,
        mut originals: Vec<CompiledSourcePackObject>,
        native_functions: &[NativeCFunction],
        build: &mut RetainedNativeBuild,
        spill: bool,
        output: Option<&Path>,
    ) -> Result<ResidentLinkedOutput, CompileError> {
        let store = build.store.clone();
        // Coherence is a whole-program rule, including impls whose methods
        // are never called. Discovery's rejection of unsupported bound uses
        // cannot replace catalog admission.
        let (mut catalog, publication) = self.retained_trait_publish(&store, &RetainedTraitOptions::default())
            .map_err(|e| retained_error("trait catalog", format!("{e:#}")))?;
        catalog.publication_status = publication.as_ref().map(|p| p.status()).transpose()
            .map_err(|e| retained_error("trait publication", e))?;
        if catalog.publication_status != Some([1, 0, u32::MAX]) {
            if let Some(publication) = &publication
                && let Some(span) = publication.diagnostic_span().map_err(|e| retained_error("trait diagnostic",e))?
                && let Some(error) = build.source_diagnostic(span,gpu_type_checker::GpuTypeCheckCode::TraitBoundUnsatisfied,0)
            { return Err(error); }
            if let Some(status) = catalog.catalog_status && status[0] != 1 {
                return Err(CompileError::Diagnostic(Diagnostic::error("LNC0017", "program trait evidence checking failed")
                    .with_note(format!("program catalog GPU admission/coherence failed: {status:?}"))));
            }
            return Err(CompileError::Diagnostic(Diagnostic::error("LNC0017", "program trait evidence checking failed").with_note(format!(
                "stage {:?}, producer {:?}, admission {:?}, publication {:?}",
                catalog.stage, catalog.first_failure, catalog.catalog_status,
                catalog.publication_status,
            ))));
        }
        let mut publication = publication.ok_or_else(|| retained_error("trait catalog", "no GPU publication"))?;
        let roots = match build.discovery.run_with_traits(&store, &mut publication).map_err(|e| retained_error("discovery", format!("{e:#}")))? {
            DiscoveryOutcome::Published(roots) => roots,
            DiscoveryOutcome::Rejected(e) => {
                return Err(retained_error("discovery rejected the program", format!("{e:?}")));
            }
        };
        drop(publication); // Discovery has consumed the proof map on the GPU.
        if roots.generation != store.generation() {
            return Err(retained_error("discovery", "the root routes belong to another build"));
        }
        let calls = build.calls.as_ref().ok_or_else(|| retained_error("certify", "no caller ABI tables"))?;
        if let Some(term) = build.test_caller_arg_fault {
            let words = vec![term; (calls.args.size() / 4) as usize];
            self.gpu.queue.write_buffer(&calls.args, 0, &words.iter().flat_map(|w| w.to_le_bytes()).collect::<Vec<u8>>());
        }
        let outcome = build
            .projection
            .run_with_lowerer(
                &store,
                &roots.inputs,
                &build.options,
                Some(RootCertification { routes: &roots.root_routes, readiness: &roots.root_readiness, calls }),
                |bytes,tokens,rows,hir,semantic| {
                    let object=self.lower_projected_batch(target,bytes,tokens,rows,hir,semantic,
                        x86::finalize::NATIVE_RESERVED_LIBRARY,x86::finalize::NATIVE_NS_INSTANCE)?;
                    if spill { object.spill_native().map_err(|e|anyhow::anyhow!("{e:?}")) }
                    else { Ok(object) }
                },
            )
            .map_err(|e| retained_error("projection", format!("{e:#}")))?;
        let (instances, report) = match outcome {
            ProjectionOutcome::Objects { objects, report } => (objects, report),
            ProjectionOutcome::Rejected { error, .. } => return Err(build.projection_error(error)),
        };
        let finalizer = match &mut build.finalizer {
            Some(finalizer) => finalizer,
            slot => slot.insert(
                GpuX86SymbolFinalizer::new_with_device(self.gpu).map_err(|e| retained_error("finalizer", e))?,
            ),
        };
        let columns = originals.iter().map(|object| match object {
            CompiledSourcePackObject::X86_64(object) => X86SymbolColumns::of_object(object),
            CompiledSourcePackObject::X86_64File(object) => X86SymbolColumns::of_file_object(object),
            CompiledSourcePackObject::Wasm(object) => X86SymbolColumns::of_wasm_object(object),
        }).collect::<Vec<_>>();
        let generation = NonZeroU32::new(roots.generation)
            .ok_or_else(|| retained_error("finalize", "build generation zero"))?;
        let table = X86RouteTable {
            routes: &roots.root_routes,
            route_capacity: roots.root_route_capacity,
            readiness: &roots.root_readiness,
        };
        let published = finalizer
            .finalize(&self.gpu.device, &self.gpu.queue, &columns, &table, generation)
            .map_err(|e| retained_error("finalize", format!("{e:#}")))?
            .map_err(|failure| retained_error("finalizer rejected the objects", format!("{failure:?}")))?;
        for (object, columns) in originals.iter_mut().zip(&published) {
            match object {
                CompiledSourcePackObject::X86_64(object) => columns.apply_to_object(object),
                CompiledSourcePackObject::X86_64File(object) => columns.apply_to_file_object(object),
                CompiledSourcePackObject::Wasm(object) => columns.apply_to_wasm_object(object),
            }.map_err(|e| retained_error("finalize", e))?;
        }
        build.report = RetainedNativeReport {
            units: originals.len(),
            instance_objects: instances.len(),
            spilled_objects: if spill { originals.len() + instances.len() } else { 0 },
            catalog: Some(catalog),
            discovery: roots.report.clone(),
            projection: report,
        };
        originals.extend(instances);
        if target==SourcePackArtifactTarget::Wasm {
            let objects=originals.iter().map(|o|match o { CompiledSourcePackObject::Wasm(o)=>o,_=>unreachable!("Wasm build") });
            let input=wasm::GpuWasmLinkInput::for_executable_refs(objects).map_err(super::wasm_codegen::wasm_link_input_error)?;
            let linker=self.wasm_linker().map_err(|e|retained_error("Wasm linker",e))?;
            let (device,queue)=(&self.gpu.device,&self.gpu.queue);
            return match output {
                Some(path)=>super::bounded_path_codegen::write_output_file_atomically(path,target,|file|
                    linker.link_executable_to_writer(device,queue,&input,file).map(|n|n as u64)
                        .map_err(|e|retained_error("Wasm link",e))).map(ResidentLinkedOutput::File),
                None=>linker.link_executable(device,queue,&input).map(ResidentLinkedOutput::Bytes)
                    .map_err(|e|retained_error("Wasm link",e)),
            };
        }
        if !spill {
            let objects = originals.into_iter().map(|object| match object {
                CompiledSourcePackObject::X86_64(object) => object,
                _ => unreachable!("resident native object"),
            }).collect::<Vec<_>>();
            return self.link_x86_objects(&objects).map(ResidentLinkedOutput::Bytes)
                .map_err(|e| retained_error("link", format!("{e:#}")));
        }
        let objects = originals.into_iter().map(|object| match object {
            CompiledSourcePackObject::X86_64File(object) => object,
            _ => unreachable!("spilled native object"),
        }).collect::<Vec<_>>();
        let linker = self.x86_linker().map_err(|e| retained_error("native linker", e))?;
        let (device, queue) = (&self.gpu.device, &self.gpu.queue);
        if let Some(options) = &build.native_link {
            let bridge = super::native_codegen::native_main_bridge(&objects)?;
            let plan = x86::native::plan_native_link(&objects, native_functions, bridge, options)
                .map_err(|e| retained_error("native link plan", e))?;
            if let x86::native::NativeLinkPlan::Gpu { input, image } = &plan {
                return match output {
                    Some(path) => super::bounded_path_codegen::write_output_file_atomically(
                        path, SourcePackArtifactTarget::X86_64, |file| linker
                        .link_dynamic_executable_to_writer(device, queue, input, image, file)
                        .map(|len| len as u64).map_err(|e| retained_error("native link", e)))
                        .map(ResidentLinkedOutput::File),
                    None => linker.link_dynamic_executable(device, queue, input, image)
                        .map(ResidentLinkedOutput::Bytes).map_err(|e| retained_error("native link", e)),
                };
            }
            let executable = x86::native::link_native_file_executable(&objects, native_functions, bridge, options)
                .map_err(|e| retained_error("native link", e))?;
            return match output {
                Some(path) => super::bounded_path_codegen::write_output_file_atomically(
                    path, SourcePackArtifactTarget::X86_64,
                    |file| executable.write_to(file).map_err(|e| retained_error("write native executable", e)),
                ).map(ResidentLinkedOutput::File),
                None => executable.read_bytes(options.max_output_bytes).map(ResidentLinkedOutput::Bytes)
                    .map_err(|e| retained_error("native link", e)),
            };
        }
        let input = x86::GpuX86LinkInput::for_executable_spilled(&objects)
            .map_err(|e| retained_error("link inputs", e))?;
        match output {
            Some(path) => super::bounded_path_codegen::write_output_file_atomically(
                path, SourcePackArtifactTarget::X86_64,
                |file| linker.link_executable_to_writer(device, queue, &input, file)
                    .map(|len| len as u64).map_err(|e| retained_error("link", e)),
            ).map(ResidentLinkedOutput::File),
            None => linker.link_executable(device, queue, &input).map(ResidentLinkedOutput::Bytes)
                .map_err(|e| retained_error("link", e)),
        }
    }
}
