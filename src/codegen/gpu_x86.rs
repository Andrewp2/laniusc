use std::{
    collections::HashMap,
    sync::{Mutex, mpsc},
    time::{Duration, Instant},
};

use anyhow::Result;
use encase::ShaderType;
use log::warn;
use wgpu::util::DeviceExt;

use crate::gpu::{
    device,
    passes_core::{PassData, bind_group, make_pass_data},
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct X86Params {
    n_tokens: u32,
    source_len: u32,
    out_capacity: u32,
    n_hir_nodes: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct BoolScanParams {
    n_tokens: u32,
    scan_step: u32,
}

pub struct RecordedX86Codegen {
    output_capacity: usize,
    token_capacity: u32,
}

struct ResidentX86Buffers {
    input_fingerprint: u64,
    output_capacity: usize,
    token_capacity: u32,
    params_buf: wgpu::Buffer,
    _array_len_buf: wgpu::Buffer,
    _array_values_buf: wgpu::Buffer,
    _body_dispatch_buf: wgpu::Buffer,
    _body_buf: wgpu::Buffer,
    body_status_buf: wgpu::Buffer,
    _bool_probe_status_buf: wgpu::Buffer,
    _bool_body_slots_buf: wgpu::Buffer,
    _bool_stmt_len_buf: wgpu::Buffer,
    _bool_prefix_a_buf: wgpu::Buffer,
    _bool_prefix_b_buf: wgpu::Buffer,
    _bool_stmt_offsets_buf: wgpu::Buffer,
    _bool_scan_status_buf: wgpu::Buffer,
    _bool_body_buf: wgpu::Buffer,
    _bool_body_status_buf: wgpu::Buffer,
    _functions_buf: wgpu::Buffer,
    functions_status_buf: wgpu::Buffer,
    functions_dispatch_buf: wgpu::Buffer,
    _reg_map_buf: wgpu::Buffer,
    _reg_status_buf: wgpu::Buffer,
    _out_buf: wgpu::Buffer,
    packed_out_buf: wgpu::Buffer,
    status_buf: wgpu::Buffer,
    out_readback: wgpu::Buffer,
    status_readback: wgpu::Buffer,
    arrays_bind_group: wgpu::BindGroup,
    body_bind_group: wgpu::BindGroup,
    bool_probe_bind_group: wgpu::BindGroup,
    bool_body_bind_group: wgpu::BindGroup,
    bool_compact_bind_group: wgpu::BindGroup,
    functions_probe_bind_group: wgpu::BindGroup,
    functions_bind_group: wgpu::BindGroup,
    regalloc_bind_group: wgpu::BindGroup,
    elf_bind_group: wgpu::BindGroup,
    pack_bind_group: wgpu::BindGroup,
}

pub struct GpuX86CodeGenerator {
    arrays_pass: PassData,
    body_pass: PassData,
    bool_probe_pass: PassData,
    bool_body_pass: PassData,
    bool_scan_pass: PassData,
    bool_compact_pass: PassData,
    functions_probe_pass: PassData,
    functions_pass: PassData,
    regalloc_pass: PassData,
    elf_pass: PassData,
    pack_pass: PassData,
    buffers: Mutex<Option<ResidentX86Buffers>>,
}

impl GpuX86CodeGenerator {
    pub fn new_with_device(gpu: &device::GpuDevice) -> Result<Self> {
        trace_x86_codegen("arrays.pipeline.start");
        let arrays_pass = make_pass_data(
            &gpu.device,
            "codegen_x86_arrays",
            "main",
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/wasm_arrays.spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/wasm_arrays.reflect.json"
            )),
        )?;
        trace_x86_codegen("arrays.pipeline.done");
        trace_x86_codegen("body.pipeline.start");
        let body_pass = make_pass_data(
            &gpu.device,
            "codegen_wasm_body",
            "main",
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/wasm_body.spv")),
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/wasm_body.reflect.json")),
        )?;
        trace_x86_codegen("body.pipeline.done");
        trace_x86_codegen("bool_probe.pipeline.start");
        let bool_probe_pass = make_pass_data(
            &gpu.device,
            "codegen_x86_wasm_bool_probe",
            "main",
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/wasm_bool_probe.spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/wasm_bool_probe.reflect.json"
            )),
        )?;
        trace_x86_codegen("bool_probe.pipeline.done");
        trace_x86_codegen("bool_body.pipeline.start");
        let bool_body_pass = make_pass_data(
            &gpu.device,
            "codegen_x86_wasm_bool_body",
            "main",
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/wasm_bool_body.spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/wasm_bool_body.reflect.json"
            )),
        )?;
        trace_x86_codegen("bool_body.pipeline.done");
        trace_x86_codegen("bool_scan.pipeline.start");
        let bool_scan_pass = make_pass_data(
            &gpu.device,
            "codegen_x86_wasm_bool_scan",
            "main",
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/wasm_bool_scan.spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/wasm_bool_scan.reflect.json"
            )),
        )?;
        trace_x86_codegen("bool_scan.pipeline.done");
        trace_x86_codegen("bool_compact.pipeline.start");
        let bool_compact_pass = make_pass_data(
            &gpu.device,
            "codegen_x86_wasm_bool_compact",
            "main",
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/wasm_bool_compact.spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/wasm_bool_compact.reflect.json"
            )),
        )?;
        trace_x86_codegen("bool_compact.pipeline.done");
        trace_x86_codegen("functions_probe.pipeline.start");
        let functions_probe_pass = make_pass_data(
            &gpu.device,
            "codegen_x86_wasm_functions_probe",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/wasm_functions_probe.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/wasm_functions_probe.reflect.json"
            )),
        )?;
        trace_x86_codegen("functions_probe.pipeline.done");
        trace_x86_codegen("functions.pipeline.start");
        let functions_pass = make_pass_data(
            &gpu.device,
            "codegen_wasm_functions",
            "main",
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/wasm_functions.spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/wasm_functions.reflect.json"
            )),
        )?;
        trace_x86_codegen("functions.pipeline.done");
        trace_x86_codegen("regalloc.pipeline.start");
        let regalloc_pass = make_pass_data(
            &gpu.device,
            "codegen_x86_regalloc",
            "main",
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/x86_regalloc.spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/x86_regalloc.reflect.json"
            )),
        )?;
        trace_x86_codegen("regalloc.pipeline.done");
        trace_x86_codegen("elf.pipeline.start");
        let elf_pass = make_pass_data(
            &gpu.device,
            "codegen_x86_elf",
            "main",
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/x86_from_wasm.spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/x86_from_wasm.reflect.json"
            )),
        )?;
        trace_x86_codegen("elf.pipeline.done");
        trace_x86_codegen("pack.pipeline.start");
        let pack_pass = make_pass_data(
            &gpu.device,
            "codegen_x86_pack_output",
            "main",
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/pack_output.spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/pack_output.reflect.json"
            )),
        )?;
        trace_x86_codegen("pack.pipeline.done");
        Ok(Self {
            arrays_pass,
            body_pass,
            bool_probe_pass,
            bool_body_pass,
            bool_scan_pass,
            bool_compact_pass,
            functions_probe_pass,
            functions_pass,
            regalloc_pass,
            elf_pass,
            pack_pass,
            buffers: Mutex::new(None),
        })
    }

    #[allow(clippy::too_many_arguments)]
    pub fn record_x86_from_gpu_token_buffer(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        source_len: u32,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        source_buf: &wgpu::Buffer,
        hir_node_capacity: u32,
        hir_kind_buf: &wgpu::Buffer,
        hir_token_pos_buf: &wgpu::Buffer,
        hir_token_end_buf: &wgpu::Buffer,
        hir_status_buf: &wgpu::Buffer,
        visible_decl_buf: &wgpu::Buffer,
        visible_type_buf: &wgpu::Buffer,
        call_fn_index_buf: &wgpu::Buffer,
        call_return_type_buf: &wgpu::Buffer,
    ) -> Result<RecordedX86Codegen> {
        let output_capacity = estimate_x86_output_capacity(source_len as usize, token_capacity);
        let input_fingerprint = buffer_fingerprint(&[
            token_buf,
            token_count_buf,
            source_buf,
            hir_kind_buf,
            hir_token_pos_buf,
            hir_token_end_buf,
            hir_status_buf,
            visible_decl_buf,
            visible_type_buf,
            call_fn_index_buf,
            call_return_type_buf,
        ]);
        let mut guard = self
            .buffers
            .lock()
            .expect("GpuX86CodeGenerator.buffers poisoned");
        let bufs = self.resident_buffers_for(
            &mut guard,
            device,
            input_fingerprint,
            output_capacity,
            token_capacity,
            token_buf,
            token_count_buf,
            source_buf,
            visible_decl_buf,
        )?;

        let params = X86Params {
            n_tokens: token_capacity,
            source_len,
            out_capacity: output_capacity as u32,
            n_hir_nodes: hir_node_capacity,
        };
        queue.write_buffer(&bufs.params_buf, 0, &x86_params_bytes(&params));
        queue.write_buffer(&bufs.body_status_buf, 0, &zero_status_bytes());
        queue.write_buffer(&bufs._bool_probe_status_buf, 0, &zero_status_bytes());
        queue.write_buffer(&bufs._bool_scan_status_buf, 0, &zero_status_bytes());
        queue.write_buffer(&bufs._bool_body_status_buf, 0, &zero_status_bytes());

        let token_groups = token_capacity.div_ceil(256).max(1);
        let output_groups = (output_capacity as u32).div_ceil(256).max(1);
        let packed_output_groups = ((output_capacity as u32).div_ceil(4)).div_ceil(256).max(1);
        let (output_groups_x, output_groups_y) = workgroup_grid_1d(output_groups);
        let (packed_output_groups_x, packed_output_groups_y) =
            workgroup_grid_1d(packed_output_groups);
        trace_x86_codegen("arrays.record.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.x86.arrays"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&self.arrays_pass.pipeline);
        compute.set_bind_group(0, Some(&bufs.arrays_bind_group), &[]);
        compute.dispatch_workgroups(token_groups, 1, 1);
        drop(compute);
        trace_x86_codegen("arrays.record.done");

        trace_x86_codegen("bool_probe.record.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.x86.wasm_bool_probe"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&self.bool_probe_pass.pipeline);
        compute.set_bind_group(0, Some(&bufs.bool_probe_bind_group), &[]);
        compute.dispatch_workgroups(token_groups, 1, 1);
        drop(compute);
        trace_x86_codegen("bool_probe.record.done");

        trace_x86_codegen("bool_body.record.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.x86.wasm_bool_body"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&self.bool_body_pass.pipeline);
        compute.set_bind_group(0, Some(&bufs.bool_body_bind_group), &[]);
        compute.dispatch_workgroups(token_groups, 1, 1);
        drop(compute);
        trace_x86_codegen("bool_body.record.done");

        self.record_bool_scan(device, encoder, bufs, token_count_buf, token_capacity)?;

        trace_x86_codegen("bool_compact.record.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.x86.wasm_bool_compact"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&self.bool_compact_pass.pipeline);
        compute.set_bind_group(0, Some(&bufs.bool_compact_bind_group), &[]);
        compute.dispatch_workgroups(token_groups, 1, 1);
        drop(compute);
        trace_x86_codegen("bool_compact.record.done");

        trace_x86_codegen("body.record.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.x86.wasm_body"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&self.body_pass.pipeline);
        compute.set_bind_group(0, Some(&bufs.body_bind_group), &[]);
        compute.dispatch_workgroups(output_groups_x, output_groups_y, 1);
        drop(compute);
        trace_x86_codegen("body.record.done");

        encoder.clear_buffer(&bufs.functions_status_buf, 0, None);
        encoder.clear_buffer(&bufs.functions_dispatch_buf, 0, None);
        trace_x86_codegen("functions_probe.record.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.x86.wasm_functions_probe"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&self.functions_probe_pass.pipeline);
        compute.set_bind_group(0, Some(&bufs.functions_probe_bind_group), &[]);
        compute.dispatch_workgroups(token_groups, 1, 1);
        drop(compute);
        trace_x86_codegen("functions_probe.record.done");

        trace_x86_codegen("functions.record.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.x86.wasm_functions"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&self.functions_pass.pipeline);
        compute.set_bind_group(0, Some(&bufs.functions_bind_group), &[]);
        compute.dispatch_workgroups_indirect(&bufs.functions_dispatch_buf, 0);
        drop(compute);
        trace_x86_codegen("functions.record.done");

        let regalloc_groups = token_groups;
        trace_x86_codegen("regalloc.record.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.x86.regalloc"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&self.regalloc_pass.pipeline);
        compute.set_bind_group(0, Some(&bufs.regalloc_bind_group), &[]);
        compute.dispatch_workgroups(regalloc_groups, 1, 1);
        drop(compute);
        trace_x86_codegen("regalloc.record.done");

        trace_x86_codegen("elf.record.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.x86.elf"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&self.elf_pass.pipeline);
        compute.set_bind_group(0, Some(&bufs.elf_bind_group), &[]);
        compute.dispatch_workgroups(output_groups_x, output_groups_y, 1);
        drop(compute);
        trace_x86_codegen("elf.record.done");

        trace_x86_codegen("pack.record.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.x86.pack_output"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&self.pack_pass.pipeline);
        compute.set_bind_group(0, Some(&bufs.pack_bind_group), &[]);
        compute.dispatch_workgroups(packed_output_groups_x, packed_output_groups_y, 1);
        drop(compute);
        trace_x86_codegen("pack.record.done");

        encoder.copy_buffer_to_buffer(&bufs.status_buf, 0, &bufs.status_readback, 0, 8);

        Ok(RecordedX86Codegen {
            output_capacity,
            token_capacity,
        })
    }

    fn record_bool_scan(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ResidentX86Buffers,
        token_count_buf: &wgpu::Buffer,
        token_capacity: u32,
    ) -> Result<()> {
        self.record_bool_scan_step(
            device,
            encoder,
            bufs,
            token_count_buf,
            token_capacity,
            0,
            false,
            true,
        )?;
        let mut scan_step = 1u32;
        let mut current_is_a = true;
        while scan_step < token_capacity {
            self.record_bool_scan_step(
                device,
                encoder,
                bufs,
                token_count_buf,
                token_capacity,
                scan_step,
                current_is_a,
                !current_is_a,
            )?;
            current_is_a = !current_is_a;
            scan_step = scan_step.saturating_mul(2);
        }
        self.record_bool_scan_step(
            device,
            encoder,
            bufs,
            token_count_buf,
            token_capacity,
            token_capacity,
            current_is_a,
            !current_is_a,
        )
    }

    fn record_bool_scan_step(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ResidentX86Buffers,
        token_count_buf: &wgpu::Buffer,
        token_capacity: u32,
        scan_step: u32,
        read_from_a: bool,
        write_to_a: bool,
    ) -> Result<()> {
        let params = BoolScanParams {
            n_tokens: token_capacity,
            scan_step,
        };
        let params_buf = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("codegen.x86.bool_scan.params"),
            contents: &bool_scan_params_bytes(&params),
            usage: wgpu::BufferUsages::UNIFORM,
        });
        let prefix_in = if read_from_a {
            &bufs._bool_prefix_a_buf
        } else {
            &bufs._bool_prefix_b_buf
        };
        let prefix_out = if write_to_a {
            &bufs._bool_prefix_a_buf
        } else {
            &bufs._bool_prefix_b_buf
        };
        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gScan".into(), params_buf.as_entire_binding()),
            ("token_count".into(), token_count_buf.as_entire_binding()),
            (
                "bool_probe_status".into(),
                bufs._bool_probe_status_buf.as_entire_binding(),
            ),
            (
                "bool_stmt_len".into(),
                bufs._bool_stmt_len_buf.as_entire_binding(),
            ),
            ("prefix_in".into(), prefix_in.as_entire_binding()),
            ("prefix_out".into(), prefix_out.as_entire_binding()),
            (
                "bool_stmt_offsets".into(),
                bufs._bool_stmt_offsets_buf.as_entire_binding(),
            ),
            (
                "bool_scan_status".into(),
                bufs._bool_scan_status_buf.as_entire_binding(),
            ),
        ]);
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("codegen_x86_wasm_bool_scan"),
            &self.bool_scan_pass.bind_group_layouts[0],
            &self.bool_scan_pass.reflection,
            0,
            &resources,
        )?;
        let groups = token_capacity.div_ceil(256).max(1);
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.x86.wasm_bool_scan"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&self.bool_scan_pass.pipeline);
        compute.set_bind_group(0, Some(&bind_group), &[]);
        compute.dispatch_workgroups(groups, 1, 1);
        drop(compute);
        Ok(())
    }

    pub fn finish_recorded_x86(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        recorded: &RecordedX86Codegen,
    ) -> Result<Vec<u8>> {
        let guard = self
            .buffers
            .lock()
            .expect("GpuX86CodeGenerator.buffers poisoned");
        let bufs = guard
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("GPU x86 codegen buffers missing"))?;
        read_x86_output(
            device,
            queue,
            &bufs.packed_out_buf,
            &bufs.status_readback,
            &bufs.out_readback,
            recorded.output_capacity,
            recorded.token_capacity,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn resident_buffers_for<'a>(
        &self,
        slot: &'a mut Option<ResidentX86Buffers>,
        device: &wgpu::Device,
        input_fingerprint: u64,
        output_capacity: usize,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        source_buf: &wgpu::Buffer,
        visible_decl_buf: &wgpu::Buffer,
    ) -> Result<&'a ResidentX86Buffers> {
        let needs_rebuild = slot.as_ref().is_none_or(|cached| {
            cached.input_fingerprint != input_fingerprint
                || cached.output_capacity < output_capacity
                || cached.token_capacity < token_capacity
        });
        if needs_rebuild {
            *slot = Some(self.create_resident_buffers(
                device,
                input_fingerprint,
                output_capacity,
                token_capacity,
                token_buf,
                token_count_buf,
                source_buf,
                visible_decl_buf,
            )?);
        }
        Ok(slot.as_ref().expect("resident x86 buffers allocated"))
    }

    #[allow(clippy::too_many_arguments)]
    fn create_resident_buffers(
        &self,
        device: &wgpu::Device,
        input_fingerprint: u64,
        output_capacity: usize,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        source_buf: &wgpu::Buffer,
        visible_decl_buf: &wgpu::Buffer,
    ) -> Result<ResidentX86Buffers> {
        let params_buf = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("codegen.x86.params"),
            size: 16,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let array_len_buf = storage_u32_rw(
            device,
            "codegen.x86.array_len",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let array_values_buf = storage_u32_rw(
            device,
            "codegen.x86.array_values",
            token_capacity as usize * 16,
            wgpu::BufferUsages::empty(),
        );
        let body_buf = storage_u32_rw(
            device,
            "codegen.x86.wasm_body_words",
            output_capacity,
            wgpu::BufferUsages::empty(),
        );
        let body_dispatch_buf = storage_u32_rw(
            device,
            "codegen.x86.wasm_body_dispatch",
            3,
            wgpu::BufferUsages::empty(),
        );
        let body_status_buf = storage_u32_rw(
            device,
            "codegen.x86.wasm_body_status",
            2,
            wgpu::BufferUsages::empty(),
        );
        let bool_body_buf = storage_u32_rw(
            device,
            "codegen.x86.wasm_bool_body_words",
            output_capacity,
            wgpu::BufferUsages::empty(),
        );
        let bool_probe_status_buf = storage_u32_rw(
            device,
            "codegen.x86.wasm_bool_probe_status",
            2,
            wgpu::BufferUsages::empty(),
        );
        let bool_body_slots_buf = storage_u32_rw(
            device,
            "codegen.x86.wasm_bool_body_slots",
            output_capacity,
            wgpu::BufferUsages::empty(),
        );
        let bool_stmt_len_buf = storage_u32_rw(
            device,
            "codegen.x86.wasm_bool_stmt_len",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let bool_prefix_a_buf = storage_u32_rw(
            device,
            "codegen.x86.wasm_bool_prefix_a",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let bool_prefix_b_buf = storage_u32_rw(
            device,
            "codegen.x86.wasm_bool_prefix_b",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let bool_stmt_offsets_buf = storage_u32_rw(
            device,
            "codegen.x86.wasm_bool_stmt_offsets",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let bool_scan_status_buf = storage_u32_rw(
            device,
            "codegen.x86.wasm_bool_scan_status",
            2,
            wgpu::BufferUsages::empty(),
        );
        let bool_body_status_buf = storage_u32_rw(
            device,
            "codegen.x86.wasm_bool_body_status",
            2,
            wgpu::BufferUsages::empty(),
        );
        let functions_buf = storage_u32_rw(
            device,
            "codegen.x86.wasm_functions_words",
            output_capacity,
            wgpu::BufferUsages::empty(),
        );
        let functions_status_buf = storage_u32_rw(
            device,
            "codegen.x86.wasm_functions_status",
            2,
            wgpu::BufferUsages::empty(),
        );
        let functions_dispatch_buf = storage_u32_rw(
            device,
            "codegen.x86.wasm_functions_dispatch",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let reg_map_buf = storage_u32_rw(
            device,
            "codegen.x86.reg_map",
            token_capacity as usize + 16,
            wgpu::BufferUsages::empty(),
        );
        let reg_status_buf = storage_u32_rw(
            device,
            "codegen.x86.reg_status",
            2,
            wgpu::BufferUsages::empty(),
        );
        let out_buf = storage_u32_rw(
            device,
            "codegen.x86.out_words",
            output_capacity,
            wgpu::BufferUsages::COPY_SRC,
        );
        let packed_out_buf = storage_u32_rw(
            device,
            "codegen.x86.packed_out_words",
            output_capacity.div_ceil(4),
            wgpu::BufferUsages::COPY_SRC,
        );
        let status_buf = storage_u32_rw(
            device,
            "codegen.x86.status",
            2,
            wgpu::BufferUsages::COPY_SRC,
        );
        let out_readback = readback_u32s(
            device,
            "rb.codegen.x86.out_words",
            output_capacity.div_ceil(4),
        );
        let status_readback = readback_u32s(device, "rb.codegen.x86.status", 2);

        let arrays_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), params_buf.as_entire_binding()),
            ("token_words".into(), token_buf.as_entire_binding()),
            ("token_count".into(), token_count_buf.as_entire_binding()),
            ("source_bytes".into(), source_buf.as_entire_binding()),
            ("array_len".into(), array_len_buf.as_entire_binding()),
            ("array_values".into(), array_values_buf.as_entire_binding()),
            ("body_status".into(), body_status_buf.as_entire_binding()),
        ]);
        let arrays_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("codegen_x86_arrays"),
            &self.arrays_pass.bind_group_layouts[0],
            &self.arrays_pass.reflection,
            0,
            &arrays_resources,
        )?;

        let body_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), params_buf.as_entire_binding()),
            ("token_words".into(), token_buf.as_entire_binding()),
            ("token_count".into(), token_count_buf.as_entire_binding()),
            ("source_bytes".into(), source_buf.as_entire_binding()),
            ("visible_decl".into(), visible_decl_buf.as_entire_binding()),
            ("array_len".into(), array_len_buf.as_entire_binding()),
            ("array_values".into(), array_values_buf.as_entire_binding()),
            (
                "bool_body_status".into(),
                bool_body_status_buf.as_entire_binding(),
            ),
            ("body_words".into(), body_buf.as_entire_binding()),
            ("body_status".into(), body_status_buf.as_entire_binding()),
        ]);
        let body_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("codegen_x86_wasm_body"),
            &self.body_pass.bind_group_layouts[0],
            &self.body_pass.reflection,
            0,
            &body_resources,
        )?;

        let bool_probe_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), params_buf.as_entire_binding()),
            ("token_words".into(), token_buf.as_entire_binding()),
            ("token_count".into(), token_count_buf.as_entire_binding()),
            (
                "bool_probe_status".into(),
                bool_probe_status_buf.as_entire_binding(),
            ),
        ]);
        let bool_probe_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("codegen_x86_wasm_bool_probe"),
            &self.bool_probe_pass.bind_group_layouts[0],
            &self.bool_probe_pass.reflection,
            0,
            &bool_probe_resources,
        )?;

        let bool_body_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), params_buf.as_entire_binding()),
            ("token_words".into(), token_buf.as_entire_binding()),
            ("token_count".into(), token_count_buf.as_entire_binding()),
            ("source_bytes".into(), source_buf.as_entire_binding()),
            ("visible_decl".into(), visible_decl_buf.as_entire_binding()),
            ("body_status".into(), body_status_buf.as_entire_binding()),
            (
                "bool_probe_status".into(),
                bool_probe_status_buf.as_entire_binding(),
            ),
            (
                "body_dispatch_args".into(),
                body_dispatch_buf.as_entire_binding(),
            ),
            (
                "bool_body_slots".into(),
                bool_body_slots_buf.as_entire_binding(),
            ),
            (
                "bool_stmt_len".into(),
                bool_stmt_len_buf.as_entire_binding(),
            ),
        ]);
        let bool_body_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("codegen_x86_wasm_bool_body"),
            &self.bool_body_pass.bind_group_layouts[0],
            &self.bool_body_pass.reflection,
            0,
            &bool_body_resources,
        )?;

        let bool_compact_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), params_buf.as_entire_binding()),
            ("token_count".into(), token_count_buf.as_entire_binding()),
            (
                "bool_body_slots".into(),
                bool_body_slots_buf.as_entire_binding(),
            ),
            (
                "bool_stmt_len".into(),
                bool_stmt_len_buf.as_entire_binding(),
            ),
            (
                "bool_stmt_offsets".into(),
                bool_stmt_offsets_buf.as_entire_binding(),
            ),
            (
                "bool_scan_status".into(),
                bool_scan_status_buf.as_entire_binding(),
            ),
            ("bool_body_words".into(), bool_body_buf.as_entire_binding()),
            (
                "bool_body_status".into(),
                bool_body_status_buf.as_entire_binding(),
            ),
        ]);
        let bool_compact_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("codegen_x86_wasm_bool_compact"),
            &self.bool_compact_pass.bind_group_layouts[0],
            &self.bool_compact_pass.reflection,
            0,
            &bool_compact_resources,
        )?;

        let functions_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), params_buf.as_entire_binding()),
            ("token_words".into(), token_buf.as_entire_binding()),
            ("token_count".into(), token_count_buf.as_entire_binding()),
            ("source_bytes".into(), source_buf.as_entire_binding()),
            ("visible_decl".into(), visible_decl_buf.as_entire_binding()),
            ("body_status".into(), body_status_buf.as_entire_binding()),
            ("out_words".into(), functions_buf.as_entire_binding()),
            ("status".into(), functions_status_buf.as_entire_binding()),
        ]);
        let functions_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("codegen_x86_wasm_functions"),
            &self.functions_pass.bind_group_layouts[0],
            &self.functions_pass.reflection,
            0,
            &functions_resources,
        )?;

        let functions_probe_resources: HashMap<String, wgpu::BindingResource<'_>> =
            HashMap::from([
                ("gParams".into(), params_buf.as_entire_binding()),
                ("token_words".into(), token_buf.as_entire_binding()),
                ("token_count".into(), token_count_buf.as_entire_binding()),
                ("source_bytes".into(), source_buf.as_entire_binding()),
                ("status".into(), functions_status_buf.as_entire_binding()),
                (
                    "dispatch_args".into(),
                    functions_dispatch_buf.as_entire_binding(),
                ),
            ]);
        let functions_probe_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("codegen_x86_wasm_functions_probe"),
            &self.functions_probe_pass.bind_group_layouts[0],
            &self.functions_probe_pass.reflection,
            0,
            &functions_probe_resources,
        )?;

        let regalloc_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), params_buf.as_entire_binding()),
            ("token_words".into(), token_buf.as_entire_binding()),
            ("token_count".into(), token_count_buf.as_entire_binding()),
            ("visible_decl".into(), visible_decl_buf.as_entire_binding()),
            ("reg_map".into(), reg_map_buf.as_entire_binding()),
            ("reg_status".into(), reg_status_buf.as_entire_binding()),
        ]);
        let regalloc_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("codegen_x86_regalloc"),
            &self.regalloc_pass.bind_group_layouts[0],
            &self.regalloc_pass.reflection,
            0,
            &regalloc_resources,
        )?;

        let elf_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), params_buf.as_entire_binding()),
            ("token_words".into(), token_buf.as_entire_binding()),
            ("token_count".into(), token_count_buf.as_entire_binding()),
            ("source_bytes".into(), source_buf.as_entire_binding()),
            ("visible_decl".into(), visible_decl_buf.as_entire_binding()),
            ("array_len".into(), array_len_buf.as_entire_binding()),
            ("array_values".into(), array_values_buf.as_entire_binding()),
            ("body_words".into(), body_buf.as_entire_binding()),
            ("body_status".into(), body_status_buf.as_entire_binding()),
            ("bool_body_words".into(), bool_body_buf.as_entire_binding()),
            (
                "bool_body_status".into(),
                bool_body_status_buf.as_entire_binding(),
            ),
            ("functions_words".into(), functions_buf.as_entire_binding()),
            (
                "functions_status".into(),
                functions_status_buf.as_entire_binding(),
            ),
            ("reg_map".into(), reg_map_buf.as_entire_binding()),
            ("reg_status".into(), reg_status_buf.as_entire_binding()),
            ("out_words".into(), out_buf.as_entire_binding()),
            ("status".into(), status_buf.as_entire_binding()),
        ]);
        let elf_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("codegen_x86_elf"),
            &self.elf_pass.bind_group_layouts[0],
            &self.elf_pass.reflection,
            0,
            &elf_resources,
        )?;

        let pack_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), params_buf.as_entire_binding()),
            ("unpacked_words".into(), out_buf.as_entire_binding()),
            ("packed_words".into(), packed_out_buf.as_entire_binding()),
            ("status".into(), status_buf.as_entire_binding()),
        ]);
        let pack_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("codegen_x86_pack_output"),
            &self.pack_pass.bind_group_layouts[0],
            &self.pack_pass.reflection,
            0,
            &pack_resources,
        )?;

        Ok(ResidentX86Buffers {
            input_fingerprint,
            output_capacity,
            token_capacity,
            params_buf,
            _array_len_buf: array_len_buf,
            _array_values_buf: array_values_buf,
            _body_dispatch_buf: body_dispatch_buf,
            _body_buf: body_buf,
            body_status_buf,
            _bool_probe_status_buf: bool_probe_status_buf,
            _bool_body_slots_buf: bool_body_slots_buf,
            _bool_stmt_len_buf: bool_stmt_len_buf,
            _bool_prefix_a_buf: bool_prefix_a_buf,
            _bool_prefix_b_buf: bool_prefix_b_buf,
            _bool_stmt_offsets_buf: bool_stmt_offsets_buf,
            _bool_scan_status_buf: bool_scan_status_buf,
            _bool_body_buf: bool_body_buf,
            _bool_body_status_buf: bool_body_status_buf,
            _functions_buf: functions_buf,
            functions_status_buf,
            functions_dispatch_buf,
            _reg_map_buf: reg_map_buf,
            _reg_status_buf: reg_status_buf,
            _out_buf: out_buf,
            packed_out_buf,
            status_buf,
            out_readback,
            status_readback,
            arrays_bind_group,
            body_bind_group,
            bool_probe_bind_group,
            bool_body_bind_group,
            bool_compact_bind_group,
            functions_probe_bind_group,
            functions_bind_group,
            regalloc_bind_group,
            elf_bind_group,
            pack_bind_group,
        })
    }
}

fn x86_params_bytes(params: &X86Params) -> Vec<u8> {
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(params)
        .expect("failed to encode x86 codegen params");
    ub.as_ref().to_vec()
}

fn bool_scan_params_bytes(params: &BoolScanParams) -> Vec<u8> {
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(params)
        .expect("failed to encode x86 bool scan params");
    ub.as_ref().to_vec()
}

fn zero_status_bytes() -> [u8; 8] {
    [0u8; 8]
}

fn trace_x86_codegen(stage: &str) {
    if crate::gpu::env::env_bool_strict("LANIUS_X86_TRACE", false) {
        eprintln!("[laniusc][x86-codegen] {stage}");
    }
}

fn read_x86_output(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    out_buf: &wgpu::Buffer,
    status_readback: &wgpu::Buffer,
    out_readback: &wgpu::Buffer,
    output_capacity: usize,
    token_capacity: u32,
) -> Result<Vec<u8>> {
    let status_slice = status_readback.slice(..);
    trace_x86_codegen("status.readback.start");
    wait_for_map(device, &status_slice, "codegen.x86.status")?;
    trace_x86_codegen("status.readback.done");

    let len = {
        let data = status_readback.slice(..).get_mapped_range();
        let len = u32::from_le_bytes(data[0..4].try_into().unwrap()) as usize;
        let ok = u32::from_le_bytes(data[4..8].try_into().unwrap()) != 0;
        drop(data);
        status_readback.unmap();
        if !ok || len > output_capacity {
            return Err(anyhow::anyhow!(
                "GPU x86 emitter produced {} bytes for capacity {} with {} tokens",
                len,
                output_capacity,
                token_capacity
            ));
        }
        len
    };

    let output_bytes = (len.div_ceil(4) * 4) as u64;
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("codegen.x86.exact_output_readback.encoder"),
    });
    encoder.copy_buffer_to_buffer(out_buf, 0, out_readback, 0, output_bytes);
    crate::gpu::passes_core::submit_with_progress(
        queue,
        "codegen.x86.output-readback",
        encoder.finish(),
    );

    let output_slice = out_readback.slice(0..output_bytes);
    trace_x86_codegen("output.readback.start");
    wait_for_map(device, &output_slice, "codegen.x86.output")?;
    trace_x86_codegen("output.readback.done");

    let bytes = {
        let data = out_readback.slice(0..output_bytes).get_mapped_range();
        let mut bytes = Vec::with_capacity(len);
        for &byte in data.iter().take(len) {
            bytes.push(byte);
        }
        drop(data);
        out_readback.unmap();
        bytes
    };
    Ok(bytes)
}

fn wait_for_map(device: &wgpu::Device, slice: &wgpu::BufferSlice<'_>, label: &str) -> Result<()> {
    let label = label.to_string();
    let cb_label = label.clone();
    let (tx, rx) = mpsc::channel();
    crate::gpu::passes_core::trace_gpu_progress(&format!("map.start :: {label}"));
    slice.map_async(wgpu::MapMode::Read, move |result| {
        if let Err(err) = tx.send(result) {
            warn!("failed to dispatch readback status for {cb_label}: {err}");
        }
    });
    crate::gpu::passes_core::trace_gpu_progress(&format!("map.queued :: {label}"));

    let timeout = x86_readback_timeout();
    let start = Instant::now();
    let mut spins = 0u32;
    loop {
        crate::gpu::passes_core::wait_for_map_progress(
            device,
            &format!("codegen.x86.output-poll({label})"),
            wgpu::PollType::Poll,
        );
        match rx.try_recv() {
            Ok(Ok(())) => return Ok(()),
            Ok(Err(err)) => {
                return Err(anyhow::anyhow!("{label} readback map failed: {err}"));
            }
            Err(mpsc::TryRecvError::Empty) => {}
            Err(mpsc::TryRecvError::Disconnected) => {
                return Err(anyhow::anyhow!("{label} readback callback disconnected"));
            }
        }
        if start.elapsed() >= timeout {
            return Err(anyhow::anyhow!(
                "{label} readback did not complete within {} ms",
                timeout.as_millis()
            ));
        }
        if spins < 64 {
            std::hint::spin_loop();
            spins += 1;
        } else {
            std::thread::yield_now();
        }
    }
}

fn x86_readback_timeout() -> Duration {
    let ms = crate::gpu::env::env_u64("LANIUS_X86_READBACK_TIMEOUT_MS", 3_000);
    Duration::from_millis(ms)
}

fn estimate_x86_output_capacity(source_len: usize, token_capacity: u32) -> usize {
    source_len
        .saturating_mul(16)
        .max((token_capacity as usize).saturating_mul(32))
        .saturating_add(40_000)
        .max(40_000)
}

fn workgroup_grid_1d(groups: u32) -> (u32, u32) {
    const MAX_X: u32 = 65_535;
    let groups = groups.max(1);
    if groups <= MAX_X {
        (groups, 1)
    } else {
        (MAX_X, groups.div_ceil(MAX_X))
    }
}

fn buffer_fingerprint(buffers: &[&wgpu::Buffer]) -> u64 {
    use std::hash::{Hash, Hasher};
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    for buffer in buffers {
        buffer.hash(&mut hasher);
    }
    hasher.finish()
}

fn storage_u32_rw(
    device: &wgpu::Device,
    label: &str,
    len: usize,
    extra: wgpu::BufferUsages,
) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: (len.max(1) * 4) as u64,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | extra,
        mapped_at_creation: false,
    })
}

fn readback_u32s(device: &wgpu::Device, label: &str, len: usize) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: (len.max(1) * 4) as u64,
        usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    })
}
