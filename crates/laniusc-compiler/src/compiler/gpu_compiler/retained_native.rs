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

use super::{resident_source_pack_executor::ResidentSourcePackExecutor, *};
use crate::{
    codegen::x86::{
        GpuX86RelocatableObject,
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
        let store = ProgramRetention::new_native(ProgramRetentionCapacity::default())?;
        let uses = store.capacity().0.arenas[8];
        Ok(Self {
            store,
            projection: RetainedProjection::new(SubstitutionCapacity::default())?,
            finalizer: None,
            discovery: RetainedDiscovery::new(discovery, SubstitutionCapacity::default())?,
            calls: Some(NativeCallTables::new(uses)),
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

impl GpuCompiler<'_> {
    /// Compiles a path manifest as a retained native build:
    /// one frontend job per unit, no source replay (module documentation).
    pub async fn compile_path_manifest_to_x86_64_retained(
        &self,
        source_pack: &ExplicitSourcePackPathManifest,
        build: &mut RetainedNativeBuild,
    ) -> Result<Vec<u8>, CompileError> {
        build.report = RetainedNativeReport::default();
        let limits = self.resident_source_unit_limits();
        if source_pack.requires_bounded_compilation_with_limits(limits) {
            return Err(retained_error(
                "admission",
                "this retained build requires a resident manifest",
            ));
        }
        build.store.begin_build().map_err(|e| retained_error("begin build", e))?;
        *self.retained_native_calls.lock().unwrap() = build.calls.take();
        self.attach_program_retention(Some(build.store.clone()));
        let originals = self.compile_retained_originals(source_pack, limits, build.native_link.as_ref()).await;
        self.attach_program_retention(None);
        build.calls = self.retained_native_calls.lock().unwrap().take();
        let (originals, native_functions) = originals?;
        self.link_retained(originals, &native_functions, build)
    }

    async fn compile_retained_originals(
        &self,
        source_pack: &ExplicitSourcePackPathManifest,
        limits: CompilationUnitLimits,
        native_link: Option<&NativeLinkOptions>,
    ) -> Result<(Vec<GpuX86RelocatableObject>, Vec<NativeCFunction>), CompileError> {
        let batch_limits = SourcePackJobBatchLimits::from_codegen_unit_limits(limits);
        let unit_plan = self.stable_frontend_unit_plan(source_pack, limits);
        let build_plan = source_pack.bounded_frontend_build_plan_with_units(unit_plan);
        let mut executor = ResidentSourcePackExecutor::new(self, SourcePackArtifactTarget::X86_64)
            .with_frontend_units(&build_plan)
            .retained();
        if let Some(options) = native_link {
            x86::native::validate_options(options)
                .map_err(|e| retained_error("native link options", e))?;
            executor = executor.with_native_link(options);
        }
        execute_path_batched_link_build_async(source_pack, &build_plan, batch_limits, &mut executor).await?;
        let originals = executor
            .take_retained_originals()
            .ok_or_else(|| retained_error("link", "the executor published no original objects"))?;
        Ok((originals, executor.take_retained_native_functions()))
    }

    fn link_retained(
        &self,
        mut originals: Vec<GpuX86RelocatableObject>,
        native_functions: &[NativeCFunction],
        build: &mut RetainedNativeBuild,
    ) -> Result<Vec<u8>, CompileError> {
        let store = build.store.clone();
        // Coherence is a whole-program rule, including impls whose methods
        // are never called. Discovery's rejection of unsupported bound uses
        // cannot replace catalog admission.
        let (mut catalog, publication) = self.retained_trait_publish(&store, &RetainedTraitOptions::default())
            .map_err(|e| retained_error("trait catalog", format!("{e:#}")))?;
        catalog.publication_status = publication.as_ref().map(|p| p.status()).transpose()
            .map_err(|e| retained_error("trait publication", e))?;
        if catalog.publication_status != Some([1, 0, u32::MAX]) {
            return Err(retained_error("trait catalog rejected the program", format!(
                "stage {:?}, producer {:?}, admission {:?}, publication {:?}",
                catalog.stage, catalog.first_failure, catalog.catalog_status,
                catalog.publication_status,
            )));
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
            .run_certified(
                self,
                &store,
                &roots.inputs,
                &build.options,
                Some(RootCertification { routes: &roots.root_routes, readiness: &roots.root_readiness, calls }),
            )
            .map_err(|e| retained_error("projection", format!("{e:#}")))?;
        let (instances, report) = match outcome {
            ProjectionOutcome::Objects { objects, report } => (objects, report),
            ProjectionOutcome::Rejected { error: e, report } => {
                return Err(retained_error(
                    "projection rejected the program",
                    format!("{} {e:?} ({} dispatches)", error::name(e.code), report.dispatches),
                ));
            }
        };
        let finalizer = match &mut build.finalizer {
            Some(finalizer) => finalizer,
            slot => slot.insert(
                GpuX86SymbolFinalizer::new_with_device(self.gpu).map_err(|e| retained_error("finalizer", e))?,
            ),
        };
        let columns = originals.iter().map(X86SymbolColumns::of_object).collect::<Vec<_>>();
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
            columns.apply_to_object(object).map_err(|e| retained_error("finalize", e))?;
        }
        build.report = RetainedNativeReport {
            units: originals.len(),
            instance_objects: instances.len(),
            catalog: Some(catalog),
            discovery: roots.report.clone(),
            projection: report,
        };
        originals.extend(instances);
        if let Some(options) = &build.native_link {
            let objects = originals.into_iter().map(x86::GpuX86FileObject::spill)
                .collect::<Result<Vec<_>, _>>().map_err(|e| retained_error("native object storage", e))?;
            let bridge = super::native_codegen::native_main_bridge(&objects)?;
            let plan = x86::native::plan_native_link(&objects, native_functions, bridge, options)
                .map_err(|e| retained_error("native link plan", e))?;
            if let x86::native::NativeLinkPlan::Gpu { input, image } = &plan {
                return self.x86_linker().map_err(|e| retained_error("native linker", e))?
                    .link_dynamic_executable(&self.gpu.device, &self.gpu.queue, input, image)
                    .map_err(|e| retained_error("native link", e));
            }
            return x86::native::link_native_file_executable(&objects, native_functions, bridge, options)
                .and_then(|output| output.read_bytes(options.max_output_bytes))
                .map_err(|e| retained_error("native link", e));
        }
        self.link_x86_objects(&originals).map_err(|e| retained_error("link", format!("{e:#}")))
    }
}
