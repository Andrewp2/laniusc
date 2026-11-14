//! Native C linking uses the ordinary checked unit scheduler and program
//! admission. Only its final artifact serialization/linking boundary differs.
use std::sync::Arc;

use super::{
    resident_source_pack_executor::{ResidentLinkedOutput, ResidentSourcePackExecutor},
    *,
};

impl GpuCompiler<'_> {
    pub async fn compile_path_manifest_with_native_link(
        &self,
        source_pack: &ExplicitSourcePackPathManifest,
        options: &NativeLinkOptions,
    ) -> Result<Vec<u8>, CompileError> {
        match self.compile_native_path_output(source_pack, options, None).await? {
            ResidentLinkedOutput::Bytes(bytes) => Ok(bytes),
            ResidentLinkedOutput::File(_) => Err(source_pack_artifact_store_error(
                "native C link wrote a file without an output path")),
        }
    }

    /// Compile native C linking directly to an atomically replaced executable.
    /// The complete executable is never materialized in a host byte vector.
    pub async fn compile_path_manifest_with_native_link_to_file(
        &self,
        source_pack: &ExplicitSourcePackPathManifest,
        options: &NativeLinkOptions,
        output: &Path,
    ) -> Result<u64, CompileError> {
        match self.compile_native_path_output(source_pack, options, Some(output)).await? {
            ResidentLinkedOutput::File(bytes) => Ok(bytes),
            ResidentLinkedOutput::Bytes(_) => Err(source_pack_artifact_store_error(
                "native C link returned bytes instead of writing its output path")),
        }
    }

    async fn compile_native_path_output(
        &self,
        source_pack: &ExplicitSourcePackPathManifest,
        options: &NativeLinkOptions,
        output: Option<&Path>,
    ) -> Result<ResidentLinkedOutput, CompileError> {
        if !cfg!(all(target_os = "linux", target_arch = "x86_64", target_env = "gnu")) {
            return Err(CompileError::GpuCodegen(
                "native C linking currently requires Linux x86_64 with glibc".into()));
        }
        x86::native::validate_options(options)
            .map_err(|error| super::x86_codegen::x86_source_pack_link_error(
                "validate native link inputs", error))?;
        let limits = self.resident_source_unit_limits();
        let whole_program = super::bounded_path_codegen::whole_program_manifest(source_pack, limits);
        let source_pack = whole_program.as_ref().unwrap_or(source_pack);
        let batch_limits = SourcePackJobBatchLimits::from_codegen_unit_limits(limits);
        let units = self.stable_frontend_unit_plan(source_pack, limits);
        let plan = source_pack.bounded_frontend_build_plan_with_units(units);
        let mut executor = match output {
            Some(output) => ResidentSourcePackExecutor::with_output_file(
                self, SourcePackArtifactTarget::X86_64, output),
            None => ResidentSourcePackExecutor::new(self, SourcePackArtifactTarget::X86_64),
        }.with_standard_library(source_pack.standard_library_id)
            .with_native_link(options);
        let _prepared = self.prepare_unit_sources(source_pack, &plan);
        execute_path_batched_link_build_async(
            source_pack, &plan, batch_limits, &mut executor,
        ).await.map(|result| result.linked_output)
    }

    /// Elaborates the files of every frontend unit of `plan` in one run of
    /// each rewrite (`elaborate_source_loads`), before the first unit
    /// compiles. Each unit takes its texts when it compiles; the returned
    /// guard drops the rest when the build ends. When the run cannot stand
    /// in for one elaboration per unit, nothing is prepared and each unit
    /// reads and elaborates its own files.
    fn prepare_unit_sources(
        &self,
        source_pack: &ExplicitSourcePackPathManifest,
        plan: &SourcePackBuildPlan,
    ) -> PreparedUnitSources<'_> {
        let guard = PreparedUnitSources { compiler: self };
        let mut units = Vec::new();
        let mut loads = Vec::new();
        for job in &plan.schedule.jobs {
            if job.phase != crate::codegen::unit::SourcePackJobPhase::LibraryFrontend {
                continue;
            }
            let files = source_pack.source_files_for_job(job);
            let Ok(texts) = read_explicit_source_path_texts(UNIT_SOURCES_LABEL, files) else {
                return guard;
            };
            units.push((job.library_id, job.phase_unit_index, files.to_vec()));
            loads.push(texts);
        }
        if loads.len() < 2 {
            return guard;
        }
        // No more than the largest unit, which the frontend reads anyway.
        let max_bytes = loads
            .iter()
            .map(|load| load.iter().map(|(_, text)| text.len()).sum::<usize>())
            .max()
            .unwrap_or(0);
        let _span = crate::gpu::trace::HostSpan::new("host.compiler", "compile.source-pack.elaborate_units");
        let Some(texts) = crate::compiler::machine_elaboration::elaborate_source_loads(loads, max_bytes) else {
            return guard;
        };
        *self.prepared_unit_sources.lock().expect("prepared unit sources mutex poisoned") = units
            .into_iter()
            .zip(texts)
            .map(|((library_id, unit_index, files), texts)| PreparedUnitSource { library_id, unit_index, files, texts })
            .collect();
        guard
    }

    /// The texts `prepare_unit_sources` elaborated for this unit's files.
    fn take_prepared_unit_sources(
        &self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
    ) -> Option<Vec<String>> {
        let mut prepared = self.prepared_unit_sources.lock().expect("prepared unit sources mutex poisoned");
        let index = prepared.iter().position(|unit| {
            unit.library_id == job.library_id && unit.unit_index == job.phase_unit_index && unit.files == source_files
        })?;
        Some(prepared.swap_remove(index).texts)
    }

    /// This is a storage policy around the existing pending constructor. Its
    /// immutable fact identity and later publication receipt are unchanged.
    pub(super) async fn compile_file_pending_native_unit(
        &self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        dependencies: Arc<[Vec<GpuSemanticInterfaceArtifact>]>,
    ) -> Result<typecheck::PendingOriginalUnit, CompileError> {
        let unit_id = u32::try_from(job.phase_unit_index).map_err(|_|
            source_pack_artifact_store_error("pending native source-unit index exceeds u32"))?;
        let sources = match self.take_prepared_unit_sources(job, source_files) {
            Some(sources) => sources,
            None => read_explicit_source_path_files(UNIT_SOURCES_LABEL, source_files)?,
        };
        let paths = source_files.iter().map(|file| Some(file.path.clone())).collect::<Vec<_>>();
        self.compile_pending_original_source_pack_unit_for_target(
            SourcePackArtifactTarget::X86_64, sources.into(), job.library_id, unit_id,
            dependencies, Some(&paths), false,
        ).await?.spill_native()
    }
}

const UNIT_SOURCES_LABEL: &str = "pending native library-interface job";

/// One unit's elaborated texts, prepared at the start of its build.
pub(super) struct PreparedUnitSource {
    library_id: u32,
    unit_index: usize,
    files: Vec<ExplicitSourcePathFile>,
    texts: Vec<String>,
}

/// Drops the prepared texts a build did not take when the build ends.
struct PreparedUnitSources<'a> {
    compiler: &'a GpuCompiler<'a>,
}

impl Drop for PreparedUnitSources<'_> {
    fn drop(&mut self) {
        self.compiler
            .prepared_unit_sources
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clear();
    }
}

pub(super) fn native_main_bridge(
    objects: &[x86::GpuX86FileObject],
) -> Result<NativeMainBridge, CompileError> {
    let mut main = None;
    for (object_index, object) in objects.iter().enumerate() {
        if let Some(range) = object.crt_main_bridge_range()
            .map_err(source_pack_artifact_store_error)? {
            if main.is_some() {
                return Err(CompileError::GpuCodegen(
                    "native C link requires exactly one main entrypoint".into()));
            }
            main = Some(NativeMainBridge {
                object_index,
                text_offset: range.start,
                byte_len: range.end - range.start,
            });
        }
    }
    main.ok_or_else(|| super::x86_codegen::x86_link_input_error(
        x86::X86_LINK_NO_ENTRY_OBJECT.into(), None))
}
