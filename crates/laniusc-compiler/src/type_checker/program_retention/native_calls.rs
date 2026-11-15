//! Original-call symbols of a retained native build
//! (docs/compiler-retained-projection.md, "Native compilation").
//!
//! A retained build's original objects define no generic function. Each
//! call to a generic template is an undefined symbol whose identity the
//! original lowering wrote. Right after a job's export, while the export
//! scratch still maps the job's HIR rows to retained uses, one GPU kernel
//! (`shaders/type_checker/retention/native/00_provisional.slang`) gives each
//! such symbol the provisional identity `(RESERVED, NS_USE, global use)`,
//! recomputes its identity hash, and records the caller's ABI facts of the
//! use (accepted result and argument terms) in [`NativeCallTables`]. The
//! host uploads and reads back the object's opaque symbol columns; it never
//! decides which symbol is provisional or reads a use.

use std::sync::OnceLock;

use super::*;
use crate::codegen::x86::{GpuX86RelocatableObject, finalize::X86SymbolColumns};

/// Argument terms recorded per use; a call with more fails certification.
pub const NC_ARGS: u64 = 8;
const KERNEL: &str = "type_checker/retention/native/00_provisional";

/// Caller ABI facts per build-global use, for the certification
/// (projection/10_certify.slang): `nc_use_abi` (result term, argument count,
/// flags, generation) and `nc_use_args` (`NC_ARGS` terms per use). Rows of
/// another build carry another generation and never certify.
pub struct NativeCallTables {
    pub(crate) abi: wgpu::Buffer,
    pub(crate) args: wgpu::Buffer,
    uses: u64,
}

impl NativeCallTables {
    /// Tables for `uses` uses (grown with the store's use arena).
    pub fn new(uses: u32) -> Self {
        let device = &crate::gpu::device::global().device;
        let uses = u64::from(uses.max(64));
        Self {
            abi: storage(device, "nc_use_abi", uses * 16, false),
            args: storage(device, "nc_use_args", uses * NC_ARGS * 4, false),
            uses,
        }
    }

    /// Use rows the tables hold.
    pub fn rows(&self) -> u32 {
        self.uses as u32
    }

    pub fn buffers(&self) -> [(&'static str, &wgpu::Buffer); 2] {
        [("nc_use_abi", &self.abi), ("nc_use_args", &self.args)]
    }

    /// Grows to `uses` rows, keeping the rows recorded so far.
    fn ensure(&mut self, device: &wgpu::Device, encoder: &mut wgpu::CommandEncoder, uses: u64) {
        if uses <= self.uses {
            return;
        }
        let n = uses.next_power_of_two();
        let abi = storage(device, "nc_use_abi", n * 16, false);
        let args = storage(device, "nc_use_args", n * NC_ARGS * 4, false);
        encoder.copy_buffer_to_buffer(&self.abi, 0, &abi, 0, self.abi.size());
        encoder.copy_buffer_to_buffer(&self.args, 0, &args, 0, self.args.size());
        self.abi = abi;
        self.args = args;
        self.uses = n;
    }
}

fn pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<PassData> = OnceLock::new();
    if let Some(pass) = PASS.get() {
        return Ok(pass);
    }
    let pass = passes_core::make_pass_data_from_shader_key(device, KERNEL, "main", KERNEL)?;
    Ok(PASS.get_or_init(|| pass))
}

impl ProgramRetention {
    /// Rewrites the generic-call symbols of the object the job behind
    /// `snapshot` just exported (see the module documentation).
    /// `call_hirs[k]` is the call HIR of the object's k-th undefined symbol.
    pub(crate) fn provisionalize_x86_calls(
        &self,
        snapshot: &JobSnapshot,
        tables: &mut NativeCallTables,
        object: &mut GpuX86RelocatableObject,
        call_hirs: &[u32],
    ) -> Result<()> {
        if call_hirs.is_empty() {
            return Ok(());
        }
        let columns = X86SymbolColumns::of_object(object);
        let symbol_words = columns.symbol_rows.len() / 4;
        if symbol_words == 0 || columns.identity_bytes.len() % 4 != 0 {
            bail!("retained original object has malformed symbol columns");
        }
        let symbols = (symbol_words / 8) as u32;
        let undefined = call_hirs.len() as u32;
        if undefined > symbols {
            bail!("retained original object names {undefined} calls but has {symbols} symbols");
        }
        let device = &self.device;
        let pass = pass(device)?;
        let store = self.store.lock().unwrap();
        let mut encoder = device.create_command_encoder(&Default::default());
        tables.ensure(device, &mut encoder, u64::from(store.capacity.arenas[A_USES]));
        let config = storage(device, "nc_config", 16, false);
        self.queue
            .write_buffer(&config, 0, &words_bytes(&[symbols, undefined, store.generation, 0]));
        let upload = |label: &str, bytes: &[u8]| {
            let buffer = storage(device, label, (bytes.len() as u64).max(16).next_multiple_of(16), false);
            self.queue.write_buffer(&buffer, 0, bytes);
            buffer
        };
        let hirs = upload("nc_call_hirs", &words_bytes(call_hirs));
        let rows = upload("nc_symbols", &columns.symbol_rows);
        let identity = upload("nc_identity", &columns.identity_bytes);
        let status = storage(device, "nc_status", 16, false);
        let names = reflected_names(pass);
        let own: [(&str, &wgpu::Buffer); 7] = [
            ("nc_config", &config),
            ("nc_call_hirs", &hirs),
            ("nc_symbols", &rows),
            ("nc_identity", &identity),
            ("nc_status", &status),
            ("nc_use_abi", &tables.abi),
            ("nc_use_args", &tables.args),
        ];
        let mut entries = Vec::with_capacity(names.len());
        for name in &names {
            let n = name.as_str();
            let resource = if let Some((_, buffer)) = own.iter().find(|(k, _)| *k == n) {
                buffer.as_entire_binding()
            } else if let Some(buffer) = store.buffers.get(n) {
                buffer.as_entire_binding()
            } else if let Some(buffer) = store.scratch.get(n) {
                buffer.as_entire_binding()
            } else if let Some(table) = snapshot.tables().get(n) {
                wgpu::BindingResource::Buffer(wgpu::BufferBinding {
                    buffer: &table.buffer,
                    offset: table.offset,
                    size: std::num::NonZeroU64::new(table.size),
                })
            } else {
                bail!("{KERNEL} binds unknown buffer {n}");
            };
            entries.push((n, resource));
        }
        let bind = passes_core::bind_group::create_bind_group_from_bindings(
            device,
            Some(&pass.shader_id),
            pass,
            0,
            &entries,
        )?;
        {
            let mut cpass = passes_core::begin_counted_compute_pass(
                &mut encoder,
                &wgpu::ComputePassDescriptor { label: Some("program_retention.native_calls"), timestamp_writes: None },
            );
            cpass.set_pipeline(&pass.pipeline);
            cpass.set_bind_group(0, &bind, &[]);
            passes_core::record_compute_dispatch();
            let groups = undefined.div_ceil(256).max(1);
            cpass.dispatch_workgroups(groups.min(65535), groups.div_ceil(65535), 1);
        }
        self.queue.submit(Some(encoder.finish()));
        drop(store);
        let status = self.read(&status, 1)?;
        if status[0] != 0 {
            bail!("retained original call symbols failed on the GPU (status {:#x})", status[0]);
        }
        let symbol_rows = words_to_bytes(&self.read(&rows, symbol_words)?);
        let identity_bytes = words_to_bytes(&self.read(&identity, columns.identity_bytes.len() / 4)?);
        X86SymbolColumns { symbol_rows, identity_bytes }.apply_to_object(object)
    }
}

fn words_to_bytes(words: &[u32]) -> Vec<u8> {
    words.iter().flat_map(|w| w.to_le_bytes()).collect()
}
