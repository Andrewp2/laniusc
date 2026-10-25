//! Native C linking uses the ordinary checked unit scheduler and program
//! admission. Only its final artifact serialization/linking boundary differs.
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
        if !cfg!(all(target_os = "linux", target_arch = "x86_64", target_env = "gnu")) {
            return Err(CompileError::GpuCodegen(
                "native C linking currently requires Linux x86_64 with glibc".into()));
        }
        x86::native::validate_options(options)
            .map_err(|error| super::x86_codegen::x86_source_pack_link_error(
                "validate native link inputs", error))?;
        let limits = self.resident_source_unit_limits();
        if source_pack.requires_bounded_compilation_with_limits(limits) {
            return Err(CompileError::GpuCodegen(
                "native C linking currently requires a resident-sized source pack; file-backed native ELF linking is not implemented".into()));
        }
        let batch_limits = SourcePackJobBatchLimits::from_codegen_unit_limits(limits);
        let units = self.stable_frontend_unit_plan(source_pack, limits);
        let plan = source_pack.bounded_frontend_build_plan_with_units(units);
        let mut executor = ResidentSourcePackExecutor::new(self, SourcePackArtifactTarget::X86_64)
            .with_standard_library(source_pack.standard_library_id)
            .with_native_link(options);
        let linked = execute_path_batched_link_build_async(
            source_pack, &plan, batch_limits, &mut executor,
        ).await?.linked_output;
        match linked {
            ResidentLinkedOutput::Bytes(bytes) => Ok(bytes),
            ResidentLinkedOutput::File(_) => Err(CompileError::GpuCodegen(
                "native C link unexpectedly returned a file instead of executable bytes".into())),
        }
    }
}

pub(super) fn native_main_bridge(
    objects: &[x86::GpuX86RelocatableObject],
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
