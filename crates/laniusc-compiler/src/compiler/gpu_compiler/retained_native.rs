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

use crate::gpu::copies::CountedWrites;
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
    /// Trait checks run again with their solver state read back, after a
    /// deferred solve's publication was not valid.
    pub trait_check_retries: usize,
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
    /// Fault injection for tests: the deferred trait solve publishes as
    /// unfinished, so the check runs again with its state read back.
    #[doc(hidden)]
    pub test_unfinished_solve: bool,
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
            discovery: {
                // Projection's plan readback reports a failed discovery.
                let mut discovery = RetainedDiscovery::new_with_device(gpu, discovery, SubstitutionCapacity::default())?;
                discovery.defer_final_status(true);
                discovery
            },
            calls: Some(NativeCallTables::new_with_device(&gpu.device, uses)),
            sources: Vec::new(),
            options: ProjectionOptions::default(),
            report: RetainedNativeReport::default(),
            native_link: None,
            test_caller_arg_fault: None,
            test_unfinished_solve: false,
        })
    }

    pub fn store(&self) -> &Arc<ProgramRetention> {
        &self.store
    }

    /// Test hook: replaces the projection with one on the process-global
    /// GPU whose substitutions start at `capacity` and whose schema rounds
    /// start with `schema_rows` request and field rows, so a build exercises
    /// their capacity retries.
    #[doc(hidden)]
    pub fn reset_projection_for_test(&mut self, capacity: SubstitutionCapacity, schema_rows: u32) -> anyhow::Result<()> {
        let mut projection = RetainedProjection::new(capacity)?;
        projection.set_schema_rows_for_test(schema_rows);
        self.projection = projection;
        Ok(())
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
        match self.link_retained(target,vec![pending.release_closed()], &[], build, typecheck::NativeObjectStore::Keep, None, false)? {
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
        match self.link_retained(SourcePackArtifactTarget::X86_64, originals?, &[], build, typecheck::NativeObjectStore::Keep, None, false)? {
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
        // A bounded build keeps object sections in private files; any other
        // file or native build keeps them in memory.
        let store = if target != SourcePackArtifactTarget::X86_64 {
            typecheck::NativeObjectStore::Keep
        } else if source_pack.requires_bounded_compilation_with_limits(limits) {
            typecheck::NativeObjectStore::Disk
        } else if output.is_some() || build.native_link.is_some() {
            typecheck::NativeObjectStore::Memory
        } else {
            typecheck::NativeObjectStore::Keep
        };
        build.store.begin_build().map_err(|e| retained_error("begin build", e))?;
        *self.retained_native_calls.lock().unwrap() = build.calls.take();
        // A native C build's objects stay on the GPU for the resident link.
        let resident = (target == SourcePackArtifactTarget::X86_64
            && store == typecheck::NativeObjectStore::Memory
            && build.native_link.is_some())
            .then(|| self.x86_linker().ok().map(|linker| linker.activate_resident_store(&self.gpu.device, &self.gpu.queue)))
            .flatten();
        self.attach_program_retention(Some(build.store.clone()));
        // The trait catalog's count passes follow each export and come back
        // with its readback; the catalog continues from the last one.
        build.store.set_export_follower(Some(self.retained_count_follower()));
        let originals = self.compile_retained_originals(target,source_pack, limits, build.native_link.as_ref(), store).await;
        build.store.set_export_follower(None);
        self.attach_program_retention(None);
        build.calls = self.retained_native_calls.lock().unwrap().take();
        let (originals, native_functions, sources) = originals?;
        build.sources = sources;
        let resident_active = resident.as_ref().is_some_and(|active| active.is_active());
        self.link_retained(target,originals, &native_functions, build, store, output, resident_active)
    }

    async fn compile_retained_originals(
        &self,
        target:SourcePackArtifactTarget,
        source_pack: &ExplicitSourcePackPathManifest,
        limits: CompilationUnitLimits,
        native_link: Option<&NativeLinkOptions>,
        spill: typecheck::NativeObjectStore,
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
        object_store: typecheck::NativeObjectStore,
        output: Option<&Path>,
        resident: bool,
    ) -> Result<ResidentLinkedOutput, CompileError> {
        let spill = object_store.file_object();
        let store = build.store.clone();
        // Coherence is a whole-program rule, including impls whose methods
        // are never called. Discovery's rejection of unsupported bound uses
        // cannot replace catalog admission.
        // The solve runs without a readback: discovery reads the
        // publication's status with its first readback and rejects an
        // invalid publication, whose verdict (header words 45 to 47) also
        // covers a solve that did not finish in its first submit. The roots
        // append nothing then, and the check runs again with its state read
        // back, for the exact result and report.
        let deferred = RetainedTraitOptions {
            defer_solve: true,
            test_unfinished_solve: build.test_unfinished_solve,
            ..RetainedTraitOptions::default()
        };
        let mut trait_check_retries = 0;
        let mut options = &deferred;
        let eager = RetainedTraitOptions::default();
        let (catalog, publication, discovered) = loop {
            let (mut catalog, mut publication) = self.retained_trait_publish(&store, options)
                .map_err(|e| retained_error("trait catalog", format!("{e:#}")))?;
            let discovered = publication.as_mut().map(|publication| build.discovery.run_with_traits(&store, publication));
            catalog.publication_status = publication.as_ref().map(|p| p.checked_status()).transpose()
                .map_err(|e| retained_error("trait publication", e))?;
            if options.defer_solve && catalog.publication_status != Some([1, 0, u32::MAX]) {
                options = &eager;
                trait_check_retries += 1;
                continue;
            }
            break (catalog, publication, discovered);
        };
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
        let publication = publication.ok_or_else(|| retained_error("trait catalog", "no GPU publication"))?;
        let discovered = discovered.ok_or_else(|| retained_error("trait catalog", "no GPU publication"))?;
        let roots = match discovered.map_err(|e| retained_error("discovery", format!("{e:#}")))? {
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
            self.gpu.queue.write_buffer_counted(&calls.args, 0, &words.iter().flat_map(|w| w.to_le_bytes()).collect::<Vec<u8>>());
        }
        // The symbol finalizer reads only the original objects and the root
        // routes, so it is submitted while the GPU lowers the first projected
        // batch and read after the projection.
        let finalizer = match &mut build.finalizer {
            Some(finalizer) => &*finalizer,
            slot => &*slot.insert(
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
        let (device, queue) = (&self.gpu.device, &self.gpu.queue);
        let mut finalize_submitted = None;
        let mut submit_finalize = || {
            if finalize_submitted.is_none() {
                finalize_submitted = Some(finalizer.submit_once(device, queue, &columns, &table, generation));
            }
        };
        // The resident link's plan needs only the routes and the parked
        // objects, so it runs on the GPU while the host finishes the objects
        // and finalizes. It is submitted behind the last batch's lowering,
        // before the host reads that batch's object back.
        let resident_link = match (&build.native_link, self.x86_linker()) {
            (Some(options), Ok(linker)) if resident && target == SourcePackArtifactTarget::X86_64 => {
                Some((options, linker))
            }
            _ => None,
        };
        let resident_key = |object: &CompiledSourcePackObject| match object {
            CompiledSourcePackObject::X86_64File(object) => Some(x86::ResidentObjectKey {
                library_id: object.layout.library_id,
                unit_id: object.layout.unit_id,
                text_len: object.layout.text_byte_len,
                rodata_len: object.layout.rodata_byte_len,
                relocation_count: object.layout.relocation_count,
                symbol_count: object.layout.symbol_count,
            }),
            _ => None,
        };
        let routes = || x86::ResidentRoutes {
            routes: &roots.root_routes,
            route_capacity: roots.root_route_capacity,
        };
        let begin_resident = |keys: &[x86::ResidentObjectKey], pending: Option<&x86::ParkedSlot>| {
            let (options, linker) = resident_link.as_ref()?;
            match linker.begin_resident_dynamic(device, queue, keys, pending, native_functions, options, routes()) {
                Ok(plan) => plan,
                Err(error) => {
                    log::warn!("resident x86 link failed, linking on the host: {error:#}");
                    None
                }
            }
        };
        let original_keys = originals.iter().map(resident_key).collect::<Option<Vec<_>>>();
        let mut instance_keys = Vec::new();
        let mut early_plan = None;
        let outcome = build
            .projection
            .run_with_lowerer(
                &store,
                &roots.inputs,
                &build.options,
                Some(RootCertification { routes: &roots.root_routes, readiness: &roots.root_readiness, calls }),
                |bytes,tokens,rows,hir,semantic,last| {
                    let mut submitted = |parked: Option<x86::ParkedSlot>| {
                        submit_finalize();
                        if !last {
                            return;
                        }
                        // A retried lowering parks its object again.
                        early_plan = None;
                        let keys = original_keys.iter().flatten().copied()
                            .map(Some)
                            .chain(instance_keys.iter().copied())
                            .collect::<Option<Vec<_>>>();
                        if let (Some(_), Some(keys), Some(parked)) = (&original_keys, keys, parked) {
                            early_plan = begin_resident(&keys, Some(&parked));
                        }
                    };
                    let object=self.lower_projected_batch(target,bytes,tokens,rows,hir,semantic,
                        x86::finalize::NATIVE_RESERVED_LIBRARY,x86::finalize::NATIVE_NS_INSTANCE,&mut submitted)?;
                    let _span = x86::TailSpan::new("tail.instance.spill");
                    let object = object.spill_native(object_store).map_err(|e|anyhow::anyhow!("{e:?}"))?;
                    instance_keys.push(resident_key(&object));
                    Ok(object)
                },
            )
            .map_err(|e| retained_error("projection", format!("{e:#}")))?;
        let (instances, report) = match outcome {
            ProjectionOutcome::Objects { objects, report } => (objects, report),
            ProjectionOutcome::Rejected { error, .. } => {
                // A discovery that failed after its last wave published no
                // inputs; its own error decides.
                if !roots.status_checked
                    && let Some(e) = build.discovery.final_failure().map_err(|e| retained_error("discovery", format!("{e:#}")))?
                {
                    return Err(retained_error("discovery rejected the program", format!("{e:?}")));
                }
                return Err(build.projection_error(error));
            }
        };
        let _tail = x86::TailSpan::new("tail.after_projection");
        let keys = originals.iter().chain(&instances).map(resident_key).collect::<Option<Vec<_>>>();
        // The early plan holds when the last object committed to the slot it
        // read; otherwise the link is planned now from the committed slots.
        let early_plan = early_plan.take().and_then(|mut plan| {
            let last = keys.as_ref()?.last()?;
            plan.confirm_pending(last).then_some(plan)
        });
        let resident_plan = match early_plan {
            Some(plan) => Some(plan),
            None => keys.and_then(|keys| begin_resident(&keys, None)),
        };
        let finalize_span = x86::TailSpan::new("tail.finalize");
        let submitted = match finalize_submitted {
            Some(submitted) => submitted,
            None => finalizer.submit_once(device, queue, &columns, &table, generation),
        };
        let published = finalizer
            .finish(device, queue, submitted, &columns, &table, generation)
            .map_err(|e| retained_error("finalize", format!("{e:#}")))?
            .map_err(|failure| retained_error("finalizer rejected the objects", format!("{failure:?}")))?;
        for (object, columns) in originals.iter_mut().zip(&published) {
            match object {
                CompiledSourcePackObject::X86_64(object) => columns.apply_to_object(object),
                CompiledSourcePackObject::X86_64File(object) => columns.apply_to_file_object(object),
                CompiledSourcePackObject::Wasm(object) => columns.apply_to_wasm_object(object),
            }.map_err(|e| retained_error("finalize", e))?;
        }
        drop(finalize_span);
        build.report = RetainedNativeReport {
            units: originals.len(),
            instance_objects: instances.len(),
            spilled_objects: if spill { originals.len() + instances.len() } else { 0 },
            catalog: Some(catalog),
            discovery: roots.report.clone(),
            projection: report,
            trait_check_retries,
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
            if let Some(plan) = resident_plan {
                let span = x86::TailSpan::new("tail.native.resident");
                match linker.finish_resident_dynamic(device, queue, plan) {
                    Ok(Some(mut image)) => {
                        drop(span);
                        let _write_span = x86::TailSpan::new("tail.native.write");
                        let len = image.len() as u64;
                        // The file is created and its blocks allocated while the
                        // GPU copies the image.
                        let mut emitted = true;
                        let written = match output {
                            Some(path) => super::bounded_path_codegen::write_output_file_atomically(
                                path, SourcePackArtifactTarget::X86_64, |file| {
                                    super::bounded_path_codegen::preallocate(file, len);
                                    emitted = image.finish()
                                        .map_err(|e| retained_error("read native executable", format!("{e:#}")))?;
                                    if !emitted {
                                        return Err(retained_error("link", "the resident emit failed"));
                                    }
                                    let _span = x86::TailSpan::new("tail.native.write.file");
                                    image.with_bytes(|bytes| std::io::Write::write_all(file, bytes))
                                        .map(|()| len)
                                        .map_err(|e| retained_error("write native executable", e))
                                }).map(ResidentLinkedOutput::File),
                            None => {
                                emitted = image.finish()
                                    .map_err(|e| retained_error("read native executable", format!("{e:#}")))?;
                                Ok(ResidentLinkedOutput::Bytes(image.with_bytes(<[u8]>::to_vec)))
                            }
                        };
                        if emitted {
                            return written;
                        }
                    }
                    Ok(None) => {}
                    Err(error) => log::warn!("resident x86 link failed, linking on the host: {error:#}"),
                }
            }
            let bridge = super::native_codegen::native_main_bridge(&objects)?;
            let plan_span = x86::TailSpan::new("tail.native.plan");
            let plan = x86::native::plan_native_link(&objects, native_functions, bridge, options)
                .map_err(|e| super::x86_codegen::x86_source_pack_link_error("native link plan", e))?;
            drop(plan_span);
            let _write_span = x86::TailSpan::new("tail.native.link_write");
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
