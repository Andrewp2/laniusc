use anyhow::{Result, anyhow};
use wgpu::util::DeviceExt;

use super::GpuWasmLinkInput;
use crate::codegen::wasm::{GpuWasmCodeGenerator, create_wasm_bind_group, workgroup_grid_1d};

impl GpuWasmCodeGenerator {
    /// Emits and relocates a complete multi-unit Wasm module on the GPU.
    pub(crate) fn link_executable(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        input: &GpuWasmLinkInput,
    ) -> Result<Vec<u8>> {
        let n = input.functions.len();
        let type_section = 11usize
            .checked_add(input.type_bytes.len())
            .ok_or_else(|| anyhow!("Wasm type section length overflows"))?;
        let function_section = 11usize
            .checked_add(
                n.checked_mul(5)
                    .ok_or_else(|| anyhow!("Wasm function section length overflows"))?,
            )
            .ok_or_else(|| anyhow!("Wasm function section length overflows"))?;
        let code_section = 11usize
            .checked_add(input.body_bytes.len())
            .ok_or_else(|| anyhow!("Wasm code section length overflows"))?;
        let output_len = 8usize
            .checked_add(type_section)
            .and_then(|x| x.checked_add(function_section))
            .and_then(|x| x.checked_add(22))
            .and_then(|x| x.checked_add(code_section))
            .ok_or_else(|| anyhow!("Wasm output length overflows"))?;
        let output_words = output_len.div_ceil(4);
        let hash_capacity = (input.symbols.len().saturating_mul(2))
            .next_power_of_two()
            .max(1);
        let params = [
            n as u32,
            input.type_bytes.len() as u32,
            input.body_bytes.len() as u32,
            input.entry_function,
            input.symbols.len() as u32,
            input.relocations.len() as u32,
            hash_capacity as u32,
            u32::try_from(output_len).map_err(|_| anyhow!("Wasm output exceeds u32"))?,
        ];
        let params = input_u32(
            device,
            "codegen.wasm.link.params",
            &params,
            wgpu::BufferUsages::UNIFORM,
        );
        let types = input_bytes(device, "codegen.wasm.link.types", &input.type_bytes);
        let bodies = input_bytes(device, "codegen.wasm.link.bodies", &input.body_bytes);
        let mut symbol_words = Vec::with_capacity(input.symbols.len() * 4);
        for symbol in &input.symbols {
            symbol_words.extend_from_slice(&[
                symbol.identity[0],
                symbol.identity[1],
                symbol.identity[2],
                symbol.function_index,
            ]);
        }
        let symbols = input_u32(
            device,
            "codegen.wasm.link.symbols",
            &symbol_words,
            wgpu::BufferUsages::STORAGE,
        );
        let mut relocation_words = Vec::with_capacity(input.relocations.len() * 4);
        for relocation in &input.relocations {
            relocation_words.extend_from_slice(&[
                relocation.body_offset,
                relocation.target_kind as u32,
                relocation.target_index,
                relocation.addend as u32,
            ]);
        }
        let relocations = input_u32(
            device,
            "codegen.wasm.link.relocations",
            &relocation_words,
            wgpu::BufferUsages::STORAGE,
        );
        let output = rw_u32(
            device,
            "codegen.wasm.link.output",
            output_words,
            wgpu::BufferUsages::COPY_SRC,
        );
        let hash_table = rw_u32(
            device,
            "codegen.wasm.link.hash_table",
            hash_capacity,
            wgpu::BufferUsages::empty(),
        );
        let definitions = rw_u32(
            device,
            "codegen.wasm.link.definitions",
            input.symbols.len(),
            wgpu::BufferUsages::empty(),
        );
        let status = rw_u32(
            device,
            "codegen.wasm.link.status",
            4,
            wgpu::BufferUsages::COPY_SRC,
        );
        let module_group = create_wasm_bind_group(
            device,
            Some("codegen.wasm.link.module.bind_group"),
            &self.link_module_pass,
            0,
            &[
                ("gLink", params.as_entire_binding()),
                ("link_type_bytes", types.as_entire_binding()),
                ("link_body_bytes", bodies.as_entire_binding()),
                ("out_words", output.as_entire_binding()),
            ],
        )?;
        let common = |pass, label| {
            create_wasm_bind_group(
                device,
                Some(label),
                pass,
                0,
                &[
                    ("gLink", params.as_entire_binding()),
                    ("link_symbol", symbols.as_entire_binding()),
                    ("link_hash_table", hash_table.as_entire_binding()),
                    ("link_symbol_definition", definitions.as_entire_binding()),
                    ("link_status", status.as_entire_binding()),
                ],
            )
        };
        let clear_group = create_wasm_bind_group(
            device,
            Some("codegen.wasm.link.clear.bind_group"),
            &self.link_symbol_clear_pass,
            0,
            &[
                ("gLink", params.as_entire_binding()),
                ("link_hash_table", hash_table.as_entire_binding()),
                ("link_symbol_definition", definitions.as_entire_binding()),
                ("link_status", status.as_entire_binding()),
            ],
        )?;
        let insert_group = common(
            &self.link_symbol_insert_pass,
            "codegen.wasm.link.insert.bind_group",
        )?;
        let define_group = common(
            &self.link_symbol_define_pass,
            "codegen.wasm.link.define.bind_group",
        )?;
        let relocate_group = create_wasm_bind_group(
            device,
            Some("codegen.wasm.link.relocate.bind_group"),
            &self.link_relocate_pass,
            0,
            &[
                ("gLink", params.as_entire_binding()),
                ("link_symbol", symbols.as_entire_binding()),
                ("link_hash_table", hash_table.as_entire_binding()),
                ("link_symbol_definition", definitions.as_entire_binding()),
                ("link_status", status.as_entire_binding()),
                ("link_relocation", relocations.as_entire_binding()),
                ("out_words", output.as_entire_binding()),
            ],
        )?;
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("codegen.wasm.link.encoder"),
        });
        dispatch(
            &mut encoder,
            "codegen.wasm.link.clear",
            &self.link_symbol_clear_pass,
            &clear_group,
            hash_capacity.max(input.symbols.len()).div_ceil(256) as u32,
        )?;
        dispatch(
            &mut encoder,
            "codegen.wasm.link.module",
            &self.link_module_pass,
            &module_group,
            output_words.div_ceil(256) as u32,
        )?;
        if !input.symbols.is_empty() {
            dispatch(
                &mut encoder,
                "codegen.wasm.link.insert",
                &self.link_symbol_insert_pass,
                &insert_group,
                input.symbols.len().div_ceil(256) as u32,
            )?;
            dispatch(
                &mut encoder,
                "codegen.wasm.link.define",
                &self.link_symbol_define_pass,
                &define_group,
                input.symbols.len().div_ceil(256) as u32,
            )?;
        }
        if !input.relocations.is_empty() {
            dispatch(
                &mut encoder,
                "codegen.wasm.link.relocate",
                &self.link_relocate_pass,
                &relocate_group,
                input.relocations.len().div_ceil(256) as u32,
            )?;
        }
        let readback = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.codegen.wasm.link"),
            size: (output_words * 4 + 16) as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(&output, 0, &readback, 0, (output_words * 4) as u64);
        encoder.copy_buffer_to_buffer(&status, 0, &readback, (output_words * 4) as u64, 16);
        crate::gpu::passes_core::submit_with_progress(queue, "codegen.wasm.link", encoder.finish());
        let slice = readback.slice(..);
        crate::gpu::passes_core::wait_for_readback_map(
            device,
            &slice,
            "codegen.wasm.link",
            std::time::Duration::from_secs(30),
        )?;
        let result = {
            let mapped = slice.get_mapped_range();
            let status_words = crate::gpu::readback::read_u32_words::<4>(
                &mapped[output_words * 4..],
                "Wasm link status",
            )?;
            if status_words[0] != 1 || status_words[1] != 0 {
                Err(anyhow!(
                    "Wasm GPU linker failed with status {status_words:?}"
                ))
            } else {
                Ok(mapped[..output_len].to_vec())
            }
        };
        readback.unmap();
        result
    }
}

fn dispatch(
    encoder: &mut wgpu::CommandEncoder,
    label: &str,
    pass: &crate::codegen::wasm::LazyWasmPass,
    group: &wgpu::BindGroup,
    groups: u32,
) -> Result<()> {
    let pipeline = pass.pipeline()?;
    let grid = workgroup_grid_1d(groups);
    let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
        label: Some(label),
        timestamp_writes: None,
    });
    compute.set_pipeline(&pipeline);
    compute.set_bind_group(0, group, &[]);
    compute.dispatch_workgroups(grid.0, grid.1, 1);
    Ok(())
}

fn input_u32(
    device: &wgpu::Device,
    label: &str,
    words: &[u32],
    usage: wgpu::BufferUsages,
) -> wgpu::Buffer {
    let fallback = [0u32];
    let words = if words.is_empty() {
        &fallback[..]
    } else {
        words
    };
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: bytemuck_words(words),
        usage,
    })
}
fn input_bytes(device: &wgpu::Device, label: &str, bytes: &[u8]) -> wgpu::Buffer {
    let mut data = bytes.to_vec();
    data.resize(data.len().div_ceil(4).max(1) * 4, 0);
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &data,
        usage: wgpu::BufferUsages::STORAGE,
    })
}
fn rw_u32(
    device: &wgpu::Device,
    label: &str,
    count: usize,
    extra: wgpu::BufferUsages,
) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: (count.max(1) * 4) as u64,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | extra,
        mapped_at_creation: false,
    })
}
fn bytemuck_words(words: &[u32]) -> &[u8] {
    unsafe { std::slice::from_raw_parts(words.as_ptr().cast(), words.len() * 4) }
}
