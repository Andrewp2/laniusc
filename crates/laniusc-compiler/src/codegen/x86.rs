//! GPU x86 object and linker boundary.
//!
//! Frontend lowering and machine-byte emission live in the compiler graph LIR
//! pipeline. This module retains only the durable object contract and the GPU
//! linker used to combine independently compiled units.

use anyhow::Result;

use crate::gpu::{
    device,
    passes_core::{PassData, make_traced_main_pass},
};

mod link;
pub(crate) use link::GpuX86LinkInput;

mod object;
pub(crate) use object::{GPU_X86_OBJECT_HEADER_BYTES, GpuX86RelocatableObjectLayout};
pub use object::{
    GPU_X86_OBJECT_VERSION,
    GpuX86ObjectSection,
    GpuX86ObjectSymbolRecord,
    GpuX86RelocatableObject,
    GpuX86RelocationKind,
    GpuX86RelocationRecord,
    GpuX86RelocationTargetKind,
};

mod support;
use support::trace_x86_codegen;

/// Daemon-resident GPU linker pipelines for durable x86 objects.
pub struct GpuX86Linker {
    link_layout_scan_local_pass: PassData,
    link_layout_scan_blocks_pass: PassData,
    link_layout_pass: PassData,
    link_copy_sections_pass: PassData,
    link_symbol_partition_clear_pass: PassData,
    link_symbol_partition_insert_pass: PassData,
    link_symbol_partition_define_pass: PassData,
    link_symbol_partition_resolve_pass: PassData,
    link_relocate_pass: PassData,
    elf_write_pass: PassData,
}

impl GpuX86Linker {
    /// Materializes every linker pipeline during daemon startup.
    pub fn new_with_device(gpu: &device::GpuDevice) -> Result<Self> {
        macro_rules! load_x86_pass {
            ($name:literal, $spv:literal, $reflection:literal) => {{
                make_traced_main_pass!(
                    &gpu.device,
                    trace_x86_codegen,
                    $name,
                    concat!("codegen_x86_", $name),
                    artifacts: ($spv, $reflection)
                )
            }};
        }

        let linker = Self {
            link_layout_scan_local_pass: load_x86_pass!(
                "link_layout_scan_local",
                "codegen/x86/link/layout_scan_local.spv",
                "codegen/x86/link/layout_scan_local.reflect.json"
            ),
            link_layout_scan_blocks_pass: load_x86_pass!(
                "link_layout_scan_blocks",
                "codegen/x86/link/layout_scan_blocks.spv",
                "codegen/x86/link/layout_scan_blocks.reflect.json"
            ),
            link_layout_pass: load_x86_pass!(
                "link_layout",
                "codegen/x86/link/layout.spv",
                "codegen/x86/link/layout.reflect.json"
            ),
            link_copy_sections_pass: load_x86_pass!(
                "link_copy_sections",
                "codegen/x86/link/copy_sections.spv",
                "codegen/x86/link/copy_sections.reflect.json"
            ),
            link_symbol_partition_clear_pass: load_x86_pass!(
                "link_symbol_partition_clear",
                "codegen/x86/link/symbol_partition_clear.spv",
                "codegen/x86/link/symbol_partition_clear.reflect.json"
            ),
            link_symbol_partition_insert_pass: load_x86_pass!(
                "link_symbol_partition_insert",
                "codegen/x86/link/symbol_partition_insert.spv",
                "codegen/x86/link/symbol_partition_insert.reflect.json"
            ),
            link_symbol_partition_define_pass: load_x86_pass!(
                "link_symbol_partition_define",
                "codegen/x86/link/symbol_partition_define.spv",
                "codegen/x86/link/symbol_partition_define.reflect.json"
            ),
            link_symbol_partition_resolve_pass: load_x86_pass!(
                "link_symbol_partition_resolve",
                "codegen/x86/link/symbol_partition_resolve.spv",
                "codegen/x86/link/symbol_partition_resolve.reflect.json"
            ),
            link_relocate_pass: load_x86_pass!(
                "link_relocate",
                "codegen/x86/link/relocate.spv",
                "codegen/x86/link/relocate.reflect.json"
            ),
            elf_write_pass: load_x86_pass!(
                "elf_write",
                "codegen/x86/elf/write.spv",
                "codegen/x86/elf/write.reflect.json"
            ),
        };
        gpu.persist_pipeline_cache();
        Ok(linker)
    }
}
