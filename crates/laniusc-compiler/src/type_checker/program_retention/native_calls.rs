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


use super::*;
use crate::codegen::x86::{GpuX86RelocatableObject, finalize::X86SymbolColumns};

const KERNEL: &str = "type_checker/retention/native/00_provisional";

/// Caller ABI facts per build-global use, for the certification
/// (projection/10_certify.slang): `nc_use_abi` (result term, argument count,
/// flags, generation; argument base, 0, 0, 0) and a compact `nc_use_args`
/// pool of (term, passing mode) pairs. Rows of
/// another build carry another generation and never certify.
pub struct NativeCallTables {
    pub(crate) abi: wgpu::Buffer,
    pub(crate) args: wgpu::Buffer,
    uses: u64,
    arguments: u32,
    generation: u32,
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
            arguments: 0,
            generation: 0,
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
        let abi = storage(device, "nc_use_abi", n * 32, false);
        encoder.copy_buffer_to_buffer(&self.abi, 0, &abi, 0, self.abi.size());
        self.abi = abi;
        self.uses = n;
    }
}

impl ProgramRetention {
    /// Rewrites the generic-call symbols of the object the job behind
    /// `snapshot` just exported (see the module documentation).
    /// `call_hirs[k]` is the call HIR of the object's k-th undefined symbol.
    /// With `export`, the job's export was submitted and not yet read: the
    /// rewrite is submitted behind it and both are read in one round trip.
    pub(crate) fn provisionalize_x86_calls(
        &self,
        snapshot: &JobSnapshot,
        tables: &mut NativeCallTables,
        object: &mut GpuX86RelocatableObject,
        call_hirs: &[u32],
        export: Option<ExportSubmitted>,
    ) -> Result<()> {
        let columns = X86SymbolColumns::of_object(object);
        let unit = Some((object.library_id, object.unit_id));
        self.provisionalize_calls(snapshot, tables, columns, call_hirs, unit, export)?.apply_to_object(object)
    }

    /// [`Self::provisionalize_x86_calls`] for an object whose sections stay
    /// in the GPU link store.
    pub(crate) fn provisionalize_x86_file_calls(
        &self,
        snapshot: &JobSnapshot,
        tables: &mut NativeCallTables,
        object: &mut crate::codegen::x86::GpuX86FileObject,
        call_hirs: &[u32],
        export: Option<ExportSubmitted>,
    ) -> Result<()> {
        let columns = X86SymbolColumns::of_file_object(object);
        let unit = Some((object.layout.library_id, object.layout.unit_id));
        self.provisionalize_calls(snapshot, tables, columns, call_hirs, unit, export)?.apply_to_file_object(object)
    }

    pub(crate) fn provisionalize_wasm_calls(
        &self, snapshot:&JobSnapshot, tables:&mut NativeCallTables,
        object:&mut crate::codegen::wasm::GpuWasmRelocatableObject, call_hirs:&[u32],
        export: Option<ExportSubmitted>,
    ) -> Result<()> {
        let columns=X86SymbolColumns::of_wasm_object(object);
        self.provisionalize_calls(snapshot,tables,columns,call_hirs,None,export)?.apply_to_wasm_object(object)
    }

    /// `unit` names an x86 object whose rewritten identities the resident
    /// native link keeps (`codegen/x86/link/resident.rs`).
    fn provisionalize_calls(&self,snapshot:&JobSnapshot,tables:&mut NativeCallTables,
        mut columns:X86SymbolColumns,call_hirs:&[u32],unit:Option<(u32,u32)>,
        mut export:Option<ExportSubmitted>) -> Result<X86SymbolColumns> {
        if call_hirs.is_empty() {
            if let Some(submitted) = export {
                self.finish_export_job(snapshot.tables(), submitted)?;
            }
            return Ok(columns);
        }
        match self.provisionalize_calls_now(snapshot, tables, &mut columns, call_hirs, unit, &mut export) {
            Ok(true) => Ok(columns),
            Ok(false) => {
                // The export's first attempt did not commit and the rewrite
                // did nothing. Grow and export again, then rewrite.
                let submitted = export.take().expect("an export that did not commit is pending");
                self.finish_export_job(snapshot.tables(), submitted)?;
                self.provisionalize_calls(snapshot, tables, columns, call_hirs, unit, None)
            }
            Err(error) => {
                if export.is_some() {
                    self.abandon_export();
                }
                Err(error)
            }
        }
    }

    /// Records, submits and reads the rewrite, and the export with it while
    /// `export` is pending. `false` when that export did not commit.
    fn provisionalize_calls_now(&self,snapshot:&JobSnapshot,tables:&mut NativeCallTables,
        columns:&mut X86SymbolColumns,call_hirs:&[u32],unit:Option<(u32,u32)>,
        export:&mut Option<ExportSubmitted>) -> Result<bool> {
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
        let pass = if let Some(pass) = self.native_call_pass.get() {
            pass
        } else {
            let pass = passes_core::make_pass_data_from_shader_key(device, KERNEL, "main", KERNEL)?;
            self.native_call_pass.get_or_init(|| pass)
        };
        let mut store = self.store.lock().unwrap();
        if tables.generation != store.generation {
            tables.generation = store.generation;
            tables.arguments = 0;
        }
        let mut encoder = device.create_command_encoder(&Default::default());
        tables.ensure(device, &mut encoder, u64::from(store.capacity.arenas[A_USES]));
        // An early export's commit steps run first in the same submission.
        let commit = export.as_mut().and_then(ExportSubmitted::take_commit);
        self.queue.submit(commit.into_iter().chain(Some(encoder.finish())));
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
        let config = keep("nc_config", 16);
        let mut upload = |label: &'static str, bytes: &[u8]| {
            let buffer = keep(label, bytes.len() as u64);
            self.queue.write_buffer(&buffer, 0, bytes);
            buffer
        };
        let hirs = upload("nc_call_hirs", &words_bytes(call_hirs));
        let rows = upload("nc_symbols", &columns.symbol_rows);
        let identity = upload("nc_identity", &columns.identity_bytes);
        let status = keep("nc_status", 16);
        drop(kept);
        let names = reflected_names(pass);
        loop {
        self.queue.write_buffer(&config, 0, &words_bytes(&[
            symbols, undefined, store.generation, (tables.args.size() / 8) as u32,
        ]));
        self.queue.write_buffer(&status, 0, &words_bytes(&[0, tables.arguments, 0, 0]));
        let mut encoder = device.create_command_encoder(&Default::default());
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
        let groups = undefined.div_ceil(256).max(1);
        super::substitution::record_timed(
            &mut encoder,
            "program_retention.native_calls",
            &[(pass, &bind, super::substitution::Launch::Groups(groups.min(65535), groups.div_ceil(65535), 1))],
        );
        // Work recorded before the export's counters existed runs behind
        // the rewrite, in the same submit, and is read with it.
        let follower = export.is_some().then(|| self.take_follower(&store)).flatten();
        let mut follower_state = None;
        let follower = match follower {
            Some(follower) => {
                self.queue.submit([encoder.finish(), follower.commands]);
                follower_state = Some(follower.state);
                Some(follower.reads)
            }
            None => {
                self.queue.submit(Some(encoder.finish()));
                None
            }
        };
        // The status and the rewritten prefix of both symbol columns in one
        // readback, with the export's counters while it is pending; the
        // columns are used only when the status is clean. Only the first
        // `undefined` rows and their identity words can change.
        let identity_words = columns.symbol_rows[..undefined as usize * 32]
            .chunks_exact(32)
            .map(|row| {
                let word = |at: usize| u32::from_le_bytes(row[at..at + 4].try_into().unwrap()) as usize;
                (word(8) + word(12)).div_ceil(4)
            })
            .max()
            .unwrap_or(0)
            .min(columns.identity_bytes.len() / 4);
        let mut parts = vec![
            (&status, 2),
            (&rows, undefined as usize * 8),
            (&identity, identity_words),
        ];
        if export.is_some() {
            parts.push((&store.buffers["rt_counts"], counts::WORDS));
            parts.push((&store.scratch["rt_x_counts"], X_WORDS));
        }
        let follows = parts.len();
        for (buffer, words) in follower.iter().flatten() {
            parts.push((buffer, *words));
        }
        let mut read = self.read_parts(&parts)?;
        let followed = read.split_off(follows);
        if export.is_some() {
            let x = read.pop().unwrap_or_default();
            let words = read.pop().unwrap_or_default();
            match committed_export(1, words, &x) {
                Some(report) => {
                    store.reports.push(report);
                    *export = None;
                    if let Some(state) = follower_state {
                        *self.followed.lock().unwrap() = Some(FollowedWords {
                            generation: store.generation,
                            jobs: store.reports.len(),
                            words: followed,
                            state,
                        });
                    }
                }
                None => return Ok(false),
            }
        }
        let result = read[0].clone();
        if result[0] & !4 != 0 {
            bail!("retained original call symbols failed on the GPU (status {:#x})", result[0]);
        }
        if result[0] & 4 != 0 {
            let bytes = (u64::from(result[1]) * 8).next_power_of_two();
            if bytes <= tables.args.size() || bytes > u64::from(device.limits().max_storage_buffer_binding_size) {
                bail!("original-call argument pool demand {bytes} exceeds the device limit");
            }
            let args = storage(device, "nc_use_args", bytes, false);
            let mut copy = device.create_command_encoder(&Default::default());
            copy.copy_buffer_to_buffer(&tables.args, 0, &args, 0, u64::from(tables.arguments) * 8);
            self.queue.submit(Some(copy.finish()));
            tables.args = args;
            continue;
        }
        tables.arguments = result[1];
        if let Some((library_id, unit_id)) = unit {
            crate::codegen::x86::park_resident_identities(device, &self.queue, library_id, unit_id, &identity, undefined);
        }
        let identity_prefix = words_to_bytes(&read.pop().unwrap_or_default());
        let rows_prefix = words_to_bytes(&read.pop().unwrap_or_default());
        drop(store);
        columns.symbol_rows[..rows_prefix.len()].copy_from_slice(&rows_prefix);
        columns.identity_bytes[..identity_prefix.len()].copy_from_slice(&identity_prefix);
        return Ok(true);
        }
    }
}

fn words_to_bytes(words: &[u32]) -> Vec<u8> {
    words.iter().flat_map(|w| w.to_le_bytes()).collect()
}
