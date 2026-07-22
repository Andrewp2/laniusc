//! GPU Wasm object and linker boundary.
//!
//! Frontend and machine-byte emission live in the compiler graph lowering
//! pipeline. This module retains only the durable object contract and the GPU
//! linker used to combine independently compiled units.

use anyhow::{Result, anyhow};

mod object;
pub(crate) use object::{GPU_WASM_OBJECT_HEADER_BYTES, GpuWasmRelocatableObjectLayout};
pub use object::{
    GPU_WASM_OBJECT_VERSION,
    GpuWasmFunctionRecord,
    GpuWasmObjectSymbolRecord,
    GpuWasmRelocatableObject,
    GpuWasmRelocationRecord,
    GpuWasmRelocationTargetKind,
    GpuWasmSymbolKind,
};

mod lazy_pass;
pub(super) use lazy_pass::{LazyWasmPass, create_wasm_bind_group};

pub(crate) mod link;
pub(crate) use link::GpuWasmLinkInput;

use crate::gpu::device;

/// Daemon-resident GPU linker pipelines for durable Wasm objects.
pub struct GpuWasmLinker {
    link_module_pass: LazyWasmPass,
    link_symbol_clear_pass: LazyWasmPass,
    link_symbol_insert_pass: LazyWasmPass,
    link_symbol_define_pass: LazyWasmPass,
    link_resolve_pass: LazyWasmPass,
    link_relocate_pass: LazyWasmPass,
}

impl GpuWasmLinker {
    /// Materializes every linker pipeline during daemon startup.
    pub fn new_with_device(gpu: &device::GpuDevice) -> Result<Self> {
        macro_rules! spawn_pass {
            ($stage:literal, $label:literal, $spv:literal, $reflection:literal) => {{
                let device = gpu.device.clone();
                std::thread::spawn(move || {
                    LazyWasmPass::from_artifacts(&device, $stage, $label, $spv, $reflection)
                })
            }};
        }
        macro_rules! finish_pass {
            ($handle:ident, $stage:literal) => {{
                let pass = $handle.join().map_err(|_| {
                    anyhow!("Wasm linker pass {} initialization panicked", $stage)
                })??;
                pass.pipeline()?;
                pass
            }};
        }

        let link_module_pass = spawn_pass!(
            "link_module",
            "codegen_wasm_link_module",
            "codegen/wasm/link/module.spv",
            "codegen/wasm/link/module.reflect.json"
        );
        let link_symbol_clear_pass = spawn_pass!(
            "link_symbol_clear",
            "codegen_wasm_link_symbol_clear",
            "codegen/wasm/link/symbol_clear.spv",
            "codegen/wasm/link/symbol_clear.reflect.json"
        );
        let link_symbol_insert_pass = spawn_pass!(
            "link_symbol_insert",
            "codegen_wasm_link_symbol_insert",
            "codegen/wasm/link/symbol_insert.spv",
            "codegen/wasm/link/symbol_insert.reflect.json"
        );
        let link_symbol_define_pass = spawn_pass!(
            "link_symbol_define",
            "codegen_wasm_link_symbol_define",
            "codegen/wasm/link/symbol_define.spv",
            "codegen/wasm/link/symbol_define.reflect.json"
        );
        let link_resolve_pass = spawn_pass!(
            "link_resolve",
            "codegen_wasm_link_resolve",
            "codegen/wasm/link/resolve.spv",
            "codegen/wasm/link/resolve.reflect.json"
        );
        let link_relocate_pass = spawn_pass!(
            "link_relocate",
            "codegen_wasm_link_relocate",
            "codegen/wasm/link/relocate.spv",
            "codegen/wasm/link/relocate.reflect.json"
        );

        let linker = Self {
            link_module_pass: finish_pass!(link_module_pass, "link_module"),
            link_symbol_clear_pass: finish_pass!(link_symbol_clear_pass, "link_symbol_clear"),
            link_symbol_insert_pass: finish_pass!(link_symbol_insert_pass, "link_symbol_insert"),
            link_symbol_define_pass: finish_pass!(link_symbol_define_pass, "link_symbol_define"),
            link_resolve_pass: finish_pass!(link_resolve_pass, "link_resolve"),
            link_relocate_pass: finish_pass!(link_relocate_pass, "link_relocate"),
        };
        gpu.persist_pipeline_cache();
        Ok(linker)
    }
}

fn trace_wasm_codegen(stage: &str) {
    if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
        eprintln!("[laniusc][wasm-link] {stage}");
    }
}

fn workgroup_grid_1d(groups: u32) -> (u32, u32) {
    let x = groups.min(65_535).max(1);
    (x, groups.div_ceil(x).max(1))
}
