//! GPU Wasm object and linker boundary.
//!
//! Frontend and machine-byte emission live in the compiler graph lowering
//! pipeline. This module retains only the durable object contract and the GPU
//! linker used to combine independently compiled units.

use std::sync::Mutex;

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

pub(crate) mod link;
pub(crate) use link::GpuWasmLinkInput;

use crate::gpu::{
    buffers::CapacityBufferCache,
    device,
    passes_core::{PassData, make_traced_main_pass},
};

/// Daemon-resident GPU linker pipelines for durable Wasm objects.
pub struct GpuWasmLinker {
    link_module_pass: PassData,
    link_symbol_clear_pass: PassData,
    link_symbol_insert_pass: PassData,
    link_symbol_define_pass: PassData,
    link_resolve_pass: PassData,
    link_relocate_pass: PassData,
    job_buffers: CapacityBufferCache,
    executable_page_graph: Mutex<Option<link::WasmExecutablePageGraph>>,
    symbol_partition_graph: Mutex<Option<link::WasmSymbolPartitionGraph>>,
}

impl GpuWasmLinker {
    /// Materializes every linker pipeline during daemon startup.
    pub fn new_with_device(gpu: &device::GpuDevice) -> Result<Self> {
        macro_rules! spawn_pass {
            ($stage:literal, $label:literal, $spv:literal, $reflection:literal) => {{
                let device = gpu.device.clone();
                std::thread::spawn(move || -> Result<PassData> {
                    Ok(make_traced_main_pass!(
                        &device,
                        trace_wasm_codegen,
                        $stage,
                        $label,
                        artifacts: ($spv, $reflection)
                    ))
                })
            }};
        }
        macro_rules! finish_pass {
            ($handle:ident, $stage:literal) => {{
                $handle
                    .join()
                    .map_err(|_| anyhow!("Wasm linker pass {} initialization panicked", $stage))??
            }};
        }

        let link_module_pass = spawn_pass!(
            "link_module",
            "codegen_wasm_link_module",
            "codegen/wasm/link/write_linked_wasm_module.spv",
            "codegen/wasm/link/write_linked_wasm_module.reflect.json"
        );
        let link_symbol_clear_pass = spawn_pass!(
            "link_symbol_clear",
            "codegen_wasm_link_symbol_clear",
            "codegen/wasm/link/clear_wasm_link_symbol_table.spv",
            "codegen/wasm/link/clear_wasm_link_symbol_table.reflect.json"
        );
        let link_symbol_insert_pass = spawn_pass!(
            "link_symbol_insert",
            "codegen_wasm_link_symbol_insert",
            "codegen/wasm/link/index_wasm_link_symbol_definitions.spv",
            "codegen/wasm/link/index_wasm_link_symbol_definitions.reflect.json"
        );
        let link_symbol_define_pass = spawn_pass!(
            "link_symbol_define",
            "codegen_wasm_link_symbol_define",
            "codegen/wasm/link/write_wasm_link_symbol_definitions.spv",
            "codegen/wasm/link/write_wasm_link_symbol_definitions.reflect.json"
        );
        let link_resolve_pass = spawn_pass!(
            "link_resolve",
            "codegen_wasm_link_resolve",
            "codegen/wasm/link/resolve_wasm_link_symbols.spv",
            "codegen/wasm/link/resolve_wasm_link_symbols.reflect.json"
        );
        let link_relocate_pass = spawn_pass!(
            "link_relocate",
            "codegen_wasm_link_relocate",
            "codegen/wasm/link/apply_wasm_link_relocations.spv",
            "codegen/wasm/link/apply_wasm_link_relocations.reflect.json"
        );

        let linker = Self {
            link_module_pass: finish_pass!(link_module_pass, "link_module"),
            link_symbol_clear_pass: finish_pass!(link_symbol_clear_pass, "link_symbol_clear"),
            link_symbol_insert_pass: finish_pass!(link_symbol_insert_pass, "link_symbol_insert"),
            link_symbol_define_pass: finish_pass!(link_symbol_define_pass, "link_symbol_define"),
            link_resolve_pass: finish_pass!(link_resolve_pass, "link_resolve"),
            link_relocate_pass: finish_pass!(link_relocate_pass, "link_relocate"),
            job_buffers: CapacityBufferCache::default(),
            executable_page_graph: Mutex::new(None),
            symbol_partition_graph: Mutex::new(None),
        };
        Ok(linker)
    }

    pub(crate) fn release_job_buffers(&self) {
        self.job_buffers.clear();
        self.executable_page_graph
            .lock()
            .expect("Wasm executable-page graph cache poisoned")
            .take();
        self.symbol_partition_graph
            .lock()
            .expect("Wasm symbol-partition graph cache poisoned")
            .take();
    }
}

fn trace_wasm_codegen(stage: &str) {
    if crate::options::get().trace.wasm {
        eprintln!("[laniusc][wasm-link] {stage}");
    }
}
