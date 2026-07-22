// src/compiler/gpu_compiler/x86_codegen.rs

use super::*;

impl<'gpu> GpuCompiler<'gpu> {
    /// Returns the initialized x86 linker or its deferred initialization error.
    pub(super) fn x86_linker(&self) -> Result<&x86::GpuX86Linker, &str> {
        self.x86_linker.as_deref().map_err(String::as_str)
    }

    /// Compile one in-memory source string through the x86_64 backend using
    /// `<source>` as the diagnostic path.
    pub async fn compile_source_to_x86_64(&self, src: &str) -> Result<Vec<u8>, CompileError> {
        let src = prepare_source_for_gpu(src)?;
        self.compile_expanded_source_to_x86_64_with_diagnostic_path(&src, PathBuf::from("<source>"))
            .await
    }
    /// Read a source file from disk and compile it through the x86_64 backend
    /// with diagnostics labeled by that path.
    pub async fn compile_source_to_x86_64_from_path(
        &self,
        path: impl AsRef<Path>,
    ) -> Result<Vec<u8>, CompileError> {
        let path = path.as_ref();
        let src = prepare_source_for_gpu_from_path(path)?;
        self.compile_expanded_source_to_x86_64_with_diagnostic_path(&src, path.to_path_buf())
            .await
    }
    /// Compile an in-memory source pack through the x86_64 backend after
    /// bounded codegen-unit validation.
    pub async fn compile_source_pack_to_x86_64<S: AsRef<str>>(
        &self,
        sources: &[S],
    ) -> Result<Vec<u8>, CompileError> {
        self.compile_source_pack_to_x86_64_with_paths(sources, None)
            .await
    }

    async fn compile_source_pack_to_x86_64_with_paths<S: AsRef<str>>(
        &self,
        sources: &[S],
        source_paths: Option<&[Option<PathBuf>]>,
    ) -> Result<Vec<u8>, CompileError> {
        if sources.is_empty() {
            return Err(x86_empty_source_pack_compile_error());
        }
        validate_in_memory_source_pack_fits_default_codegen_unit(
            "compile source pack to x86_64",
            sources,
        )?;
        self.compile_checked_source_pack_with_lowering(
            sources,
            source_paths,
            LoweringTarget::X86_64,
        )
        .await
    }

    /// Compiles one bounded source-pack unit to a durable relocatable x86 object.
    pub(in crate::compiler) async fn compile_source_pack_to_x86_object<S: AsRef<str>>(
        &self,
        sources: &[S],
        library_id: u32,
        unit_id: u32,
        dependency_interfaces: &[crate::compiler::GpuSemanticInterfaceArtifact],
    ) -> Result<x86::GpuX86RelocatableObject, CompileError> {
        if sources.is_empty() {
            return Err(x86_empty_source_pack_compile_error());
        }
        validate_in_memory_source_pack_fits_default_codegen_unit(
            "compile source pack to x86_64 object",
            sources,
        )?;
        self.compile_checked_source_pack_to_x86_object_with_lowering(
            sources,
            library_id,
            unit_id,
            dependency_interfaces,
        )
        .await
    }

    /// Compile an explicit in-memory source-pack manifest through the x86_64
    /// backend and preserve manifest source paths for diagnostics.
    pub async fn compile_source_pack_manifest_to_x86_64(
        &self,
        source_pack: &ExplicitSourcePack,
    ) -> Result<Vec<u8>, CompileError> {
        self.compile_source_pack_to_x86_64_with_paths(
            &source_pack.sources,
            Some(&source_pack.source_paths),
        )
        .await
    }
    /// Compiles prepared source text to x86_64 output using a synthetic path.
    pub(in crate::compiler) async fn compile_expanded_source_to_x86_64(
        &self,
        src: &str,
    ) -> Result<Vec<u8>, CompileError> {
        self.compile_expanded_source_to_x86_64_with_diagnostic_path(src, PathBuf::from("<source>"))
            .await
    }

    async fn compile_expanded_source_to_x86_64_with_diagnostic_path(
        &self,
        src: &str,
        diagnostic_path: PathBuf,
    ) -> Result<Vec<u8>, CompileError> {
        self.compile_checked_source_with_lowering(
            src,
            diagnostic_path,
            Some(LoweringTarget::X86_64),
        )
        .await?
        .ok_or_else(|| CompileError::GpuCodegen("x86 lowering produced no artifact".into()))
    }
}

fn x86_empty_source_pack_compile_error() -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0017", "missing main entrypoint")
            .with_primary_label(DiagnosticLabel::primary(
                PathBuf::from("<source-pack>"),
                1,
                1,
                1,
                None,
                "the source pack is empty",
            ))
            .with_note("x86 source packs must contain at least one source file before native entry selection can run"),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn gpu_projects_compiled_user_call_to_relocatable_x86_object() {
        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let object = pollster::block_on(compiler.compile_source_pack_to_x86_object(
            &[r#"
pub fn seven() -> i32 {
    return 7;
}

fn main() -> i32 {
    return seven();
}
"#],
            11,
            3,
            &[],
        ))
        .expect("compile relocatable x86 object");
        assert_eq!(object.library_id, 11);
        assert_eq!(object.unit_id, 3);
        assert!(object.entry_offset.is_some());
        assert!(
            object.relocations.is_empty(),
            "local calls must stay position-independent"
        );
        assert!(object.symbols.iter().any(|symbol| {
            symbol.section == x86::GpuX86ObjectSection::Text
                && x86_object_symbol_identity(&object, symbol) == [11, 3, 0]
        }));
        let encoded = object.to_bytes().expect("serialize x86 object");
        assert_eq!(
            x86::GpuX86RelocatableObject::from_bytes(&encoded).unwrap(),
            object
        );
        let input =
            x86::GpuX86LinkInput::for_executable(&[object]).expect("flatten projected x86 object");
        let linked = compiler
            .x86_linker()
            .expect("x86 linker")
            .link_executable(&compiler.gpu.device, &compiler.gpu.queue, &input)
            .expect("link projected x86 object");
        assert_x86_main_exit(&linked, "projected-local-call", 7);
    }

    #[test]
    fn gpu_links_graph_projected_x86_call_across_compilation_units() {
        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let provider_source = [r#"
module core::math;

pub fn seven() -> i32 {
    return 7;
}
"#];
        let provider_interface =
            pollster::block_on(compiler.semantic_interface_for_source_pack(7, &provider_source))
                .expect("project provider semantic interface");
        let provider_object = pollster::block_on(compiler.compile_source_pack_to_x86_object(
            &provider_source,
            7,
            0,
            &[],
        ))
        .expect("compile provider x86 object");
        assert_eq!(provider_object.entry_offset, None);

        let consumer_source = [r#"
module app::main;
import core::math;

fn main() -> i32 {
    return seven();
}
"#];
        let consumer_object = pollster::block_on(compiler.compile_source_pack_to_x86_object(
            &consumer_source,
            11,
            2,
            &[provider_interface],
        ))
        .expect("compile consumer x86 object against provider interface");
        assert!(consumer_object.entry_offset.is_some());
        assert_eq!(consumer_object.relocations.len(), 1);
        let relocation = &consumer_object.relocations[0];
        assert_eq!(relocation.kind, x86::GpuX86RelocationKind::CallRel32);
        assert_eq!(
            relocation.target_kind,
            x86::GpuX86RelocationTargetKind::Symbol
        );
        let undefined = &consumer_object.symbols[relocation.target_index as usize];
        assert_eq!(undefined.section, x86::GpuX86ObjectSection::Undefined);
        let definition = provider_object
            .symbols
            .iter()
            .find(|symbol| symbol.section == x86::GpuX86ObjectSection::Text)
            .expect("provider public function definition");
        assert_eq!(
            x86_object_symbol_identity(&consumer_object, undefined),
            x86_object_symbol_identity(&provider_object, definition),
            "dependency declaration identity must survive semantic and target lowering"
        );

        let input = x86::GpuX86LinkInput::for_executable(&[provider_object, consumer_object])
            .expect("flatten cross-unit x86 objects");
        let linked = compiler
            .x86_linker()
            .expect("x86 linker")
            .link_executable(&compiler.gpu.device, &compiler.gpu.queue, &input)
            .expect("link cross-unit x86 objects");
        assert_x86_main_exit(&linked, "projected-cross-unit-call", 7);
    }

    fn x86_object_symbol_identity(
        object: &x86::GpuX86RelocatableObject,
        symbol: &x86::GpuX86ObjectSymbolRecord,
    ) -> [u32; 3] {
        let start = symbol.identity_byte_start as usize;
        let bytes = &object.identity_bytes[start..start + 12];
        [
            u32::from_le_bytes(bytes[0..4].try_into().unwrap()),
            u32::from_le_bytes(bytes[4..8].try_into().unwrap()),
            u32::from_le_bytes(bytes[8..12].try_into().unwrap()),
        ]
    }

    fn assert_x86_main_exit(bytes: &[u8], artifact_name: &str, expected: i32) {
        use std::os::unix::fs::PermissionsExt;

        let path =
            std::env::temp_dir().join(format!("laniusc-{artifact_name}-{}", std::process::id()));
        std::fs::write(&path, bytes).expect("write projected linked x86 executable");
        let mut permissions = std::fs::metadata(&path).unwrap().permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(&path, permissions).unwrap();
        let status = std::process::Command::new(&path)
            .status()
            .expect("run projected linked x86 executable");
        let _ = std::fs::remove_file(path);
        assert_eq!(status.code(), Some(expected));
    }
}
