//! GPU x86 object and linker boundary.
//!
//! Frontend lowering and machine-byte emission live in the compiler graph LIR
//! pipeline. This module retains the durable object contract, the GPU linker
//! for freestanding executables, and opt-in ELF packaging for system C linking.

use std::{collections::HashMap, sync::Mutex};

use anyhow::Result;

use crate::gpu::{
    buffers::CapacityBufferCache,
    device,
    passes_core::{PassData, make_main_pass},
};

mod link;
pub(crate) use link::{
    GpuX86LinkInput,
    GpuX86LinkStore,
    ParkRegion,
    ParkSources,
    ParkTicket,
    ParkedSlot,
    ResidentEmitFault,
    ResidentObjectKey,
    ResidentRoutes,
    ResidentSections,
    park as park_resident_object,
    GpuX86MissingSymbolDefinition,
    X86_LINK_NO_ENTRY_OBJECT,
    X86DynamicImage,
    X86DynamicMain,
};

mod object;
pub(crate) mod finalize;
mod file_object;
pub(crate) use file_object::GpuX86FileObject;
pub(crate) mod native;
pub(crate) use object::{
    GPU_X86_OBJECT_HEADER_BYTES,
    GpuX86LinkObjectMetadata,
    GpuX86RelocatableObjectLayout,
};
pub use object::{
    GPU_X86_OBJECT_VERSION,
    GPU_X86_CRT_MAIN_BRIDGE_BYTES,
    GpuX86ObjectBodyRange,
    GpuX86ObjectSection,
    GpuX86ObjectSymbolRecord,
    GpuX86RelocatableObject,
    GpuX86RelocationKind,
    GpuX86RelocationRecord,
    GpuX86RelocationTargetKind,
};

mod support;
pub(crate) use support::TailSpan;

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
    elf_dynamic_write_pass: PassData,
    rl_compare_pass: PassData,
    rl_plan_pass: PassData,
    rl_bind_pass: PassData,
    rl_define_pass: PassData,
    rl_insert_pass: PassData,
    rl_undefined_pass: PassData,
    rl_park_pass: PassData,
    rl_dynsym_pass: PassData,
    rl_name_hash_pass: PassData,
    rl_import_match_pass: PassData,
    rl_dynamic_rows_pass: PassData,
    rl_gather_pass: PassData,
    rl_reloc_pass: PassData,
    resident_store: Mutex<Option<std::sync::Arc<link::GpuX86LinkStore>>>,
    job_buffers: CapacityBufferCache,
    executable_page_graph: Mutex<Option<link::X86ExecutablePageGraph>>,
    layout_chunk_graph: Mutex<Option<link::X86LayoutChunkGraph>>,
    symbol_partition_graph: Mutex<Option<link::X86SymbolPartitionGraph>>,
    input_shadows: Mutex<HashMap<String, X86InputShadow>>,
}

struct X86InputShadow {
    allocation_id: Option<u64>,
    bytes: Vec<u8>,
}

impl GpuX86Linker {
    /// Materializes every linker pipeline during daemon startup.
    pub fn new_with_device(gpu: &device::GpuDevice) -> Result<Self> {
        macro_rules! load_x86_pass {
            ($name:literal, $spv:literal, $reflection:literal) => {{
                make_main_pass!(
                    &gpu.device,
                    concat!("codegen_x86_", $name),
                    artifacts: ($spv, $reflection)
                )?
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
            elf_dynamic_write_pass: load_x86_pass!(
                "elf_dynamic_write",
                "codegen/x86/elf/dynamic_write.spv",
                "codegen/x86/elf/dynamic_write.reflect.json"
            ),
            rl_compare_pass: load_x86_pass!(
                "link_resident_rl_compare",
                "codegen/x86/link/resident/rl_compare.spv",
                "codegen/x86/link/resident/rl_compare.reflect.json"
            ),
            rl_plan_pass: load_x86_pass!(
                "link_resident_rl_plan",
                "codegen/x86/link/resident/rl_plan.spv",
                "codegen/x86/link/resident/rl_plan.reflect.json"
            ),
            rl_bind_pass: load_x86_pass!(
                "link_resident_rl_bind",
                "codegen/x86/link/resident/rl_bind.spv",
                "codegen/x86/link/resident/rl_bind.reflect.json"
            ),
            rl_define_pass: load_x86_pass!(
                "link_resident_rl_define",
                "codegen/x86/link/resident/rl_define.spv",
                "codegen/x86/link/resident/rl_define.reflect.json"
            ),
            rl_insert_pass: load_x86_pass!(
                "link_resident_rl_insert",
                "codegen/x86/link/resident/rl_insert.spv",
                "codegen/x86/link/resident/rl_insert.reflect.json"
            ),
            rl_undefined_pass: load_x86_pass!(
                "link_resident_rl_undefined",
                "codegen/x86/link/resident/rl_undefined.spv",
                "codegen/x86/link/resident/rl_undefined.reflect.json"
            ),
            rl_park_pass: load_x86_pass!(
                "link_resident_rl_park",
                "codegen/x86/link/resident/rl_park.spv",
                "codegen/x86/link/resident/rl_park.reflect.json"
            ),
            rl_dynsym_pass: load_x86_pass!(
                "link_resident_rl_dynsym",
                "codegen/x86/link/resident/rl_dynsym.spv",
                "codegen/x86/link/resident/rl_dynsym.reflect.json"
            ),
            rl_name_hash_pass: load_x86_pass!(
                "link_resident_rl_name_hash",
                "codegen/x86/link/resident/rl_name_hash.spv",
                "codegen/x86/link/resident/rl_name_hash.reflect.json"
            ),
            rl_import_match_pass: load_x86_pass!(
                "link_resident_rl_import_match",
                "codegen/x86/link/resident/rl_import_match.spv",
                "codegen/x86/link/resident/rl_import_match.reflect.json"
            ),
            rl_dynamic_rows_pass: load_x86_pass!(
                "link_resident_rl_dynamic_rows",
                "codegen/x86/link/resident/rl_dynamic_rows.spv",
                "codegen/x86/link/resident/rl_dynamic_rows.reflect.json"
            ),
            rl_gather_pass: load_x86_pass!(
                "link_resident_rl_gather",
                "codegen/x86/link/resident/rl_gather.spv",
                "codegen/x86/link/resident/rl_gather.reflect.json"
            ),
            rl_reloc_pass: load_x86_pass!(
                "link_resident_rl_reloc",
                "codegen/x86/link/resident/rl_reloc.spv",
                "codegen/x86/link/resident/rl_reloc.reflect.json"
            ),
            resident_store: Mutex::new(None),
            job_buffers: CapacityBufferCache::default(),
            executable_page_graph: Mutex::new(None),
            layout_chunk_graph: Mutex::new(None),
            symbol_partition_graph: Mutex::new(None),
            input_shadows: Mutex::new(HashMap::new()),
        };
        Ok(linker)
    }
}
