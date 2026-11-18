//! Original-call symbols of a retained native build
//! (docs/compiler-retained-projection.md, "Native compilation").
//!
//! A retained build's original objects define no generic function. Each
//! call to a generic template is an undefined symbol whose identity the
//! original lowering wrote. Right behind a job's export, while the export
//! scratch still maps the job's HIR rows to retained uses, one GPU kernel
//! (`shaders/type_checker/retention/projection/project_provisional_native_call_symbols.slang`) gives each
//! such symbol the provisional identity `(RESERVED, NS_USE, global use)` in
//! the object's own rows, before the object is read, and records the
//! caller's ABI facts of the use (accepted result and argument terms) in
//! [`NativeCallTables`]. The host only binds the buffers and sizes the
//! tables from capacities.

use crate::gpu::copies::{CountedCommands, CountedWrites};
use super::*;

const KERNEL: &str = "type_checker/retention/projection/project_provisional_native_call_symbols";

/// Caller ABI facts per build-global use, for the certification
/// (certify_retained_native_abi.slang): `nc_use_abi` (result term, argument count,
/// flags, generation; argument base, 0, 0, 0) and a compact `nc_use_args`
/// pool of (term, passing mode) pairs. Rows of
/// another build carry another generation and never certify.
pub struct NativeCallTables {
    pub(crate) abi: wgpu::Buffer,
    pub(crate) args: wgpu::Buffer,
    uses: u64,
    /// Generation of the build whose rows the tables hold.
    generation: u32,
    /// The most argument rows this build's rewrites can append.
    argument_bound: u64,
}

impl NativeCallTables {
    /// Tables for `uses` uses (grown with the store's use arena).
    pub fn new(uses: u32) -> Self {
        Self::new_with_device(&crate::gpu::device::global().device, uses)
    }

    pub(crate) fn new_with_device(device: &wgpu::Device, uses: u32) -> Self {
        let uses = u64::from(uses.max(64));
        Self {
            abi: storage(device, "nc_use_abi", uses * 32, false),
            args: storage(device, "nc_use_args", 64 * 8, false),
            uses,
            generation: 0,
            argument_bound: 0,
        }
    }

    /// Use rows the tables hold.
    pub fn rows(&self) -> u32 {
        self.uses as u32
    }

    pub fn buffers(&self) -> [(&'static str, &wgpu::Buffer); 2] {
        [("nc_use_abi", &self.abi), ("nc_use_args", &self.args)]
    }

    /// Grows the argument pool to `rows` rows, keeping the rows recorded so
    /// far.
    fn ensure_arguments(&mut self, device: &wgpu::Device, encoder: &mut wgpu::CommandEncoder, rows: u64) {
        let bytes = rows.max(64).next_power_of_two() * 8;
        if bytes <= self.args.size() {
            return;
        }
        let args = storage(device, "nc_use_args", bytes, false);
        encoder.copy_buffer_counted(&self.args, 0, &args, 0, self.args.size());
        self.args = args;
    }

    /// Grows to `uses` rows, keeping the rows recorded so far.
    fn ensure(&mut self, device: &wgpu::Device, encoder: &mut wgpu::CommandEncoder, uses: u64) {
        if uses <= self.uses {
            return;
        }
        let n = uses.next_power_of_two();
        let abi = storage(device, "nc_use_abi", n * 32, false);
        encoder.copy_buffer_counted(&self.abi, 0, &abi, 0, self.abi.size());
        self.abi = abi;
        self.uses = n;
    }
}

impl ProgramRetention {
    /// Records the call rewrite of the object behind `rows` into `encoder`
    /// (see the module documentation) and returns its status buffer
    /// (`NC_STATUS_WORDS` words). The argument pool is sized from the job's
    /// call-argument rows and the object's row capacity, never from words
    /// read back.
    pub(super) fn record_call_rewrite(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        store: &Store,
        snapshot: &JobSnapshot,
        tables: &mut NativeCallTables,
        rows: ObjectCallRows<'_>,
    ) -> Result<wgpu::Buffer> {
        let device = &self.device;
        let pass = if let Some(pass) = self.native_call_pass.get() {
            pass
        } else {
            let pass = passes_core::make_pass_data_from_shader_key(device, KERNEL, "main", KERNEL)?;
            self.native_call_pass.get_or_init(|| pass)
        };
        let mut kept = self.native_call_scratch.lock().unwrap();
        let mut keep = |label: &'static str, bytes: u64| {
            let bytes = bytes.max(16).next_power_of_two();
            kept.entry(label)
                .and_modify(|buffer| {
                    if buffer.size() < bytes {
                        *buffer = storage(device, label, bytes, false);
                    }
                })
                .or_insert_with(|| storage(device, label, bytes, false))
                .clone()
        };
        let config = keep("nc_config", 32);
        let status = keep("nc_status", (NC_STATUS_WORDS * 4) as u64);
        let identity = keep("nc_identity", u64::from(rows.lanes).max(1) * 12);
        drop(kept);
        // The argument cursor (status word 1) runs over the build; each job
        // clears only the error word.
        if tables.generation != store.generation {
            tables.generation = store.generation;
            tables.argument_bound = 0;
            self.queue.write_buffer_counted(&status, 0, &words_bytes(&[0; NC_STATUS_WORDS]));
        } else {
            self.queue.write_buffer_counted(&status, 0, &words_bytes(&[0]));
        }
        tables.ensure(device, encoder, u64::from(store.capacity.arenas[A_USES]));
        // Each rewritten call appends its arguments, plus a receiver for a
        // method call: at most the job's call-argument rows and one row per
        // object row.
        let call_args = snapshot.tables().get("compact_call_args").map_or(0, |table| table.size / 16);
        tables.argument_bound += call_args + u64::from(rows.lanes);
        tables.ensure_arguments(device, encoder, tables.argument_bound);
        let argument_rows = u32::try_from(tables.args.size() / 8).unwrap_or(u32::MAX);
        self.queue.write_buffer_counted(&config, 0, &words_bytes(&[
            rows.mode, rows.lanes, store.generation, argument_rows, 0, 0, 0, 0,
        ]));
        encoder.copy_buffer_counted(&rows.count.0, rows.count.1, &config, 16, 4);
        fn row_binding(table: &JobTable) -> wgpu::BindingResource<'_> {
            wgpu::BindingResource::Buffer(wgpu::BufferBinding {
                buffer: &table.buffer,
                offset: table.offset,
                size: std::num::NonZeroU64::new(table.size),
            })
        }
        let names = reflected_names(pass);
        let mut entries = Vec::with_capacity(names.len());
        for name in &names {
            let n = name.as_str();
            let resource = match n {
                "nc_config" => config.as_entire_binding(),
                "nc_status" => status.as_entire_binding(),
                "nc_identity" => identity.as_entire_binding(),
                "nc_use_abi" => tables.abi.as_entire_binding(),
                "nc_use_args" => tables.args.as_entire_binding(),
                "nc_rows" => row_binding(&rows.rows),
                // A Wasm row carries its call; the binding is unused.
                "nc_call_hirs" => match &rows.call_hirs {
                    Some(table) => row_binding(table),
                    None => config.as_entire_binding(),
                },
                _ => if let Some(buffer) = store.buffers.get(n) {
                    buffer.as_entire_binding()
                } else if let Some(buffer) = store.scratch.get(n) {
                    buffer.as_entire_binding()
                } else if let Some(table) = snapshot.tables().get(n) {
                    row_binding(table)
                } else {
                    bail!("{KERNEL} binds unknown buffer {n}");
                },
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
        let groups = rows.lanes.div_ceil(256).max(1);
        super::substitution::record_timed(
            encoder,
            "program_retention.native_calls",
            &[(pass, &bind, super::substitution::Launch::Groups(groups.min(65535), groups.div_ceil(65535), 1))],
        );
        if let Some(park) = rows.park_identities {
            park(encoder, &identity);
        }
        Ok(status)
    }
}


