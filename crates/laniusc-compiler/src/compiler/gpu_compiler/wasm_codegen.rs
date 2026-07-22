// src/compiler/gpu_compiler/wasm_codegen.rs

use super::*;

impl<'gpu> GpuCompiler<'gpu> {
    /// Compile one in-memory source string through the WASM backend using
    /// `<source>` as the diagnostic path.
    pub async fn compile_source_to_wasm(&self, src: &str) -> Result<Vec<u8>, CompileError> {
        let src = prepare_source_for_gpu(src)?;
        self.compile_expanded_source_to_wasm_with_diagnostic_path(&src, PathBuf::from("<source>"))
            .await
    }
    /// Read a source file from disk and compile it through the WASM backend with
    /// diagnostics labeled by that path.
    pub async fn compile_source_to_wasm_from_path(
        &self,
        path: impl AsRef<Path>,
    ) -> Result<Vec<u8>, CompileError> {
        let path = path.as_ref();
        let src = prepare_source_for_gpu_from_path(path)?;
        self.compile_expanded_source_to_wasm_with_diagnostic_path(&src, path.to_path_buf())
            .await
    }
    /// Compile an in-memory source pack through the WASM backend after bounded
    /// codegen-unit validation.
    pub async fn compile_source_pack_to_wasm<S: AsRef<str>>(
        &self,
        sources: &[S],
    ) -> Result<Vec<u8>, CompileError> {
        validate_in_memory_source_pack_fits_default_codegen_unit(
            "compile source pack to WASM",
            sources,
        )?;
        self.compile_checked_source_pack_with_lowering(sources, None, LoweringTarget::Wasm)
            .await
    }

    /// Compiles one bounded source-pack unit to a durable relocatable Wasm object.
    pub(in crate::compiler) async fn compile_source_pack_to_wasm_object<S: AsRef<str>>(
        &self,
        sources: &[S],
        library_id: u32,
        unit_id: u32,
        dependency_interfaces: &[crate::compiler::GpuSemanticInterfaceArtifact],
    ) -> Result<wasm::GpuWasmRelocatableObject, CompileError> {
        validate_in_memory_source_pack_fits_default_codegen_unit(
            "compile source pack to Wasm object",
            sources,
        )?;
        self.compile_checked_source_pack_to_wasm_object_with_lowering(
            sources,
            library_id,
            unit_id,
            dependency_interfaces,
        )
        .await
    }

    /// Compile an explicit in-memory source-pack manifest through the WASM
    /// backend and preserve manifest source paths for diagnostics.
    pub async fn compile_source_pack_manifest_to_wasm(
        &self,
        source_pack: &ExplicitSourcePack,
    ) -> Result<Vec<u8>, CompileError> {
        self.compile_source_pack_to_wasm(&source_pack.sources).await
    }
    /// Compiles prepared source text to WASM output using a synthetic path.
    pub(in crate::compiler) async fn compile_expanded_source_to_wasm(
        &self,
        src: &str,
    ) -> Result<Vec<u8>, CompileError> {
        self.compile_expanded_source_to_wasm_with_diagnostic_path(src, PathBuf::from("<source>"))
            .await
    }

    async fn compile_expanded_source_to_wasm_with_diagnostic_path(
        &self,
        src: &str,
        diagnostic_path: PathBuf,
    ) -> Result<Vec<u8>, CompileError> {
        self.compile_checked_source_with_lowering(src, diagnostic_path, Some(LoweringTarget::Wasm))
            .await?
            .ok_or_else(|| CompileError::GpuCodegen("Wasm lowering produced no artifact".into()))
    }

    /// Returns the initialized Wasm linker or its deferred initialization error.
    pub(super) fn wasm_linker(&self) -> Result<&wasm::GpuWasmLinker, &str> {
        trace_wasm_compile("wasm.linker");
        self.wasm_linker.as_deref().map_err(String::as_str)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn gpu_projects_compiled_user_call_to_relocatable_wasm_object() {
        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let object = pollster::block_on(compiler.compile_source_pack_to_wasm_object(
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
        .expect("compile relocatable Wasm object");
        assert_eq!(object.library_id, 11);
        assert_eq!(object.unit_id, 3);
        assert_eq!(object.functions.len(), 2);
        assert_eq!(object.entry_function, Some(1));
        assert_eq!(object.relocations.len(), 1);
        assert_eq!(
            object.relocations[0].target_kind,
            wasm::GpuWasmRelocationTargetKind::LocalFunction
        );
        assert_eq!(object.relocations[0].target_index, 0);
        let encoded = object.to_bytes().expect("serialize Wasm object");
        assert_eq!(
            wasm::GpuWasmRelocatableObject::from_bytes(&encoded).unwrap(),
            object
        );
        let input = wasm::link::GpuWasmLinkInput::for_executable(&[object])
            .expect("flatten projected Wasm object");
        let linker = compiler.wasm_linker().expect("Wasm linker");
        let linked = linker
            .link_executable(&compiler.gpu.device, &compiler.gpu.queue, &input)
            .expect("link projected Wasm object");
        assert_wasm_main_result(&linked, "projected-local-call", b"7");
    }

    #[test]
    fn gpu_links_graph_projected_call_across_compilation_units() {
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
        let provider_object = pollster::block_on(compiler.compile_source_pack_to_wasm_object(
            &provider_source,
            7,
            0,
            &[],
        ))
        .expect("compile provider Wasm object");
        assert_eq!(provider_object.entry_function, None);

        let consumer_source = [r#"
module app::main;
import core::math;

fn main() -> i32 {
    return seven();
}
"#];
        let consumer_object = pollster::block_on(compiler.compile_source_pack_to_wasm_object(
            &consumer_source,
            11,
            2,
            &[provider_interface],
        ))
        .expect("compile consumer Wasm object against provider interface");
        assert_eq!(consumer_object.entry_function, Some(0));
        assert_eq!(consumer_object.relocations.len(), 1);
        let relocation = &consumer_object.relocations[0];
        assert_eq!(
            relocation.target_kind,
            wasm::GpuWasmRelocationTargetKind::Symbol
        );
        let undefined = &consumer_object.symbols[relocation.target_index as usize];
        assert_eq!(undefined.kind, wasm::GpuWasmSymbolKind::Undefined);
        let definition = provider_object
            .symbols
            .iter()
            .find(|symbol| symbol.kind == wasm::GpuWasmSymbolKind::Function)
            .expect("provider public function definition");
        assert_eq!(
            wasm_object_symbol_identity(&consumer_object, undefined),
            wasm_object_symbol_identity(&provider_object, definition),
            "dependency declaration identity must survive semantic and target lowering"
        );

        let input =
            wasm::link::GpuWasmLinkInput::for_executable(&[provider_object, consumer_object])
                .expect("flatten cross-unit Wasm objects");
        let linked = compiler
            .wasm_linker()
            .expect("Wasm linker")
            .link_executable(&compiler.gpu.device, &compiler.gpu.queue, &input)
            .expect("link cross-unit Wasm objects");
        assert_wasm_main_result(&linked, "projected-cross-unit-call", b"7");
    }

    fn wasm_object_symbol_identity(
        object: &wasm::GpuWasmRelocatableObject,
        symbol: &wasm::GpuWasmObjectSymbolRecord,
    ) -> [u32; 3] {
        let start = symbol.identity_byte_start as usize;
        let bytes = &object.identity_bytes[start..start + 12];
        [
            u32::from_le_bytes(bytes[0..4].try_into().unwrap()),
            u32::from_le_bytes(bytes[4..8].try_into().unwrap()),
            u32::from_le_bytes(bytes[8..12].try_into().unwrap()),
        ]
    }

    fn assert_wasm_main_result(bytes: &[u8], artifact_name: &str, expected: &[u8]) {
        let node = match which::which("node") {
            Ok(node) => node,
            Err(_) => return,
        };
        let path = std::env::temp_dir().join(format!(
            "laniusc-{artifact_name}-{}.wasm",
            std::process::id()
        ));
        std::fs::write(&path, bytes).expect("write projected linked Wasm");
        let output = std::process::Command::new(node)
            .args([
                "-e",
                "const fs=require('fs'); WebAssembly.instantiate(fs.readFileSync(process.argv[1])).then(x=>process.stdout.write(String(x.instance.exports.main())))",
                path.to_str().unwrap(),
            ])
            .output()
            .expect("run projected linked Wasm");
        let _ = std::fs::remove_file(path);
        assert!(
            output.status.success(),
            "Node rejected projected linked Wasm: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert_eq!(output.stdout, expected);
    }
}
