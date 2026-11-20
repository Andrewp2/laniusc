//! Parallel schema instantiation. A closed nominal is its own binding
//! context. Each round's frontier contains the terms appended since the
//! previous round; one request per schema record realizes its field type.
//!
//! One program prepares the round's requests. Substitution records its own
//! batch, and the publication program writes the realized field types. The
//! caller reads `ps_status` with its next readback. An unfinished round can
//! resume through the full substitution path.

use crate::gpu::copies::{CountedCommands, CountedWrites};
use super::*;
use crate::type_checker::program_retention::substitution::read_many_labeled;

const PREPARE: &str = "type_checker/retention/projection_schema/prepare_retained_schema_requests";
const PUBLISH: &str = "type_checker/retention/projection_schema/publish_retained_schema_fields";
const PREPARE_FAILED: usize = 9;
const PUBLISH_FAILED: usize = 10;

/// `ps_status` words (common.slang `PS_*`).
pub(super) const STATUS_WORDS: usize = 16;
const S_LO: usize = 1;
const S_ERROR: usize = 2;
const S_STOP: usize = 3;
const S_BASE: usize = 4;
const S_DEMAND_REQUESTS: usize = 5;
const S_DEMAND_FIELDS: usize = 6;
const S_ROUNDS: usize = 7;
const STOP_RUNNING: u32 = 0;
const STOP_CONVERGED: u32 = 1;
const STOP_UNPUBLISHED: u32 = 2;
const STOP_CAPACITY: u32 = 3;
const STOP_FAILED: u32 = 4;
/// The first term a round can contain (`RT_FIRST_TERM`).
const FIRST_TERM: u32 = 32;
/// Rounds recorded per chain at first. A chain that ends with the rounds
/// still running doubles it, and the count is kept for later projections.
const FIRST_ROUNDS: u32 = 1;
const MAX_ROUNDS: u32 = 64;
/// Request and field rows at first; a round that needs more stops with its
/// demand, and the host grows them.
const FIRST_ROWS: u32 = 1024;

#[derive(Clone, Debug, Default)]
pub struct SchemaReport {
    pub rounds: u32,
    pub requests: u32,
    pub dispatches: u32,
    pub substitution_dispatches: u32,
    pub readbacks: u32,
    /// Chains of rounds recorded.
    pub chains: u32,
    /// Rounds the host substituted again after a run did not publish or
    /// the round's buffers were too small.
    pub resumed: u32,
}

struct Kernels {
    device: std::sync::Arc<wgpu::Device>,
    queue: std::sync::Arc<wgpu::Queue>,
    prepare: PassData,
    publish: PassData,
    buffers: BTreeMap<&'static str, wgpu::Buffer>,
    configs: Vec<wgpu::Buffer>,
    cursor: usize,
}

impl Kernels {
    fn ensure(&mut self, name: &'static str, bytes: u64, preserve: bool) -> Result<()> {
        if self.buffers.get(name).is_some_and(|b| b.size() >= bytes) {
            return Ok(());
        }
        let size = bytes
            .max(16)
            .checked_next_power_of_two()
            .ok_or_else(|| anyhow!("schema capacity overflow"))?;
        if size > u64::from(self.device.limits().max_storage_buffer_binding_size) {
            bail!("schema table {name} requires {size} bytes, beyond device binding limit");
        }
        let next = storage(&self.device, name, size, false);
        if preserve && let Some(previous) = self.buffers.get(name) {
            let mut encoder = self.device.create_command_encoder(&Default::default());
            encoder.copy_buffer_counted(previous, 0, &next, 0, previous.size());
            self.queue.submit(Some(encoder.finish()));
        }
        self.buffers.insert(name, next);
        Ok(())
    }

    #[allow(clippy::too_many_arguments)]
    fn record(
        &mut self,
        encoder: &mut wgpu::CommandEncoder,
        store: &Store,
        prepare: bool,
        options: bool,
        config: [u32; 8],
        extra: &[(&str, &wgpu::Buffer)],
        report: &mut SchemaReport,
    ) -> Result<()> {
        if self.cursor == self.configs.len() {
            self.configs.push(storage(&self.device, "ps_config", 32, false));
        }
        let cfg = &self.configs[self.cursor];
        self.cursor += 1;
        self.queue.write_buffer_counted(cfg, 0, &words_bytes(&config));
        let (key, pass, slot, failure_word, rows) = if prepare {
            (
                PREPARE, &self.prepare, super::super::PREPARE_SCHEMA_SYNC_SLOT,
                PREPARE_FAILED, store.capacity.arenas[A_TERMS],
            )
        } else {
            (
                PUBLISH, &self.publish, super::super::PUBLISH_SCHEMA_SYNC_SLOT,
                PUBLISH_FAILED, config[4],
            )
        };
        let names = reflected_names(pass);
        let mut bindings = Vec::with_capacity(names.len());
        for name in &names {
            let n = name.as_str();
            if matches!(n, "step_program_sync" | "program_launch") {
                continue;
            }
            let buffer = if n == "ps_config" { Some(cfg) } else { None }
                .or_else(|| self.buffers.get(n))
                .or_else(|| extra.iter().find(|(k, _)| *k == n).map(|(_, b)| *b))
                .or_else(|| store.buffers.get(n))
                .ok_or_else(|| anyhow!("{key} binds unknown {n}"))?;
            bindings.push((n, buffer.as_entire_binding()));
        }
        let groups = step_program_group_counts()[step_program_group_variant(u64::from(rows))];
        let program = StepProgramOperation::new_reflected(
            &self.device, key, pass, &bindings, &store.step_program_sync,
            slot, groups, u32::from(options),
        )?;
        program.record(encoder)?;
        passes_core::flush_deferred_compute(encoder);
        encoder.copy_buffer_counted(
            &store.step_program_sync,
            StepProgramOperation::failed_offset(slot),
            &self.buffers["ps_status"],
            (failure_word * 4) as u64,
            4,
        );
        report.dispatches += 1;
        Ok(())
    }
}

pub(super) struct SchemaProjection {
    kernels: Kernels,
    engine: RetainedSubstitution,
    requests: SubstitutionRequests,
    field_capacity: u32,
    rounds: u32,
    report: SchemaReport,
}

impl SchemaProjection {
    pub fn new_with_device(gpu: &crate::gpu::device::GpuDevice, capacity: SubstitutionCapacity) -> Result<Self> {
        let mut buffers = BTreeMap::new();
        for (name, bytes, indirect) in [
            ("ps_status", STATUS_WORDS as u64 * 4, false),
            ("ps_round", 32, false),
            ("ps_scan_total", 4, false),
            ("pj_schema_ranges", 8, false),
            ("pj_schema_fields", 8, false),
        ] {
            buffers.insert(name, storage(&gpu.device, name, bytes, indirect));
        }
        Ok(Self {
            kernels: Kernels {
                device: gpu.device.clone(),
                queue: gpu.queue.clone(),
                prepare: make_pass_data_from_shader_key(&gpu.device, PREPARE, "main", PREPARE)?,
                publish: make_pass_data_from_shader_key(&gpu.device, PUBLISH, "main", PUBLISH)?,
                buffers,
                configs: Vec::new(),
                cursor: 0,
            },
            engine: RetainedSubstitution::new_with_device(gpu, capacity)?,
            requests: SubstitutionRequests::new_with_device(&gpu.device, FIRST_ROWS),
            field_capacity: FIRST_ROWS,
            rounds: FIRST_ROUNDS,
            report: SchemaReport::default(),
        })
    }

    /// Request and field rows of the next chain.
    pub fn set_rows(&mut self, rows: u32) {
        self.requests = SubstitutionRequests::new_with_device(&self.kernels.device, rows.max(1));
        self.field_capacity = rows.max(1);
    }

    pub fn binding(&self, name: &str) -> Option<&wgpu::Buffer> {
        self.kernels.buffers.get(name)
    }

    /// The status words the caller reads after a chain.
    pub fn status_buffer(&self) -> &wgpu::Buffer {
        &self.kernels.buffers["ps_status"]
    }

    /// Starts the rounds of one projection: the first round begins at the
    /// first term, with no field written. The next chain clears the ranges.
    pub fn begin(&mut self) {
        self.report = SchemaReport::default();
        let mut status = [0u32; STATUS_WORDS];
        status[S_LO] = FIRST_TERM;
        self.kernels
            .queue
            .write_buffer_counted(&self.kernels.buffers["ps_status"], 0, &words_bytes(&status));
    }

    fn config(&self, mode: u32, run: u32, gate: u32, generation: u32) -> [u32; 8] {
        [mode, run, gate, generation, self.requests.capacity(), self.field_capacity, 0, 0]
    }

    /// Records and submits one chain of rounds and its close; `first`
    /// clears the ranges of an earlier projection. Nothing is read.
    pub fn record_chain(&mut self, store: &ProgramRetention, first: bool) -> Result<()> {
        let guard = store.store.lock().unwrap();
        let terms = u64::from(guard.capacity.arenas[A_TERMS]);
        let generation = guard.generation;
        // Every table is sized from the store's term capacity, which no
        // chained run grows: a run that would grow it does not publish.
        self.kernels.ensure("pj_schema_ranges", terms * 8, !first)?;
        self.kernels.ensure("ps_scan_a", (terms + 1) * 4, false)?;
        self.kernels.ensure("ps_scan_b", (terms + 1) * 4, false)?;
        self.kernels.ensure("ps_blocks", (terms + 1).div_ceil(256) * 4, false)?;
        self.kernels.ensure("pj_schema_fields", u64::from(self.field_capacity) * 8, true)?;
        let rounds = self.rounds as usize;
        let runs = self.engine.begin_chain(&self.requests, rounds)?;
        let (results, counts) = self
            .engine
            .chain_buffers()
            .ok_or_else(|| anyhow!("schema substitution buffers are not allocated"))?;
        let (results, counts) = (results.clone(), counts.clone());
        let gate_extra = [("sb_results", &results), ("sb_counts", &counts)];
        let requests = self.requests.buffers().map(|(n, b)| (n, b.clone()));
        let request_extra = requests.iter().map(|(n, b)| (*n, b)).collect::<Vec<_>>();
        let mut report = std::mem::take(&mut self.report);
        report.chains += 1;
        self.kernels.cursor = 0;
        let mut encoder = self.kernels.device.create_command_encoder(&Default::default());
        if first {
            encoder.clear_buffer_counted(&self.kernels.buffers["pj_schema_ranges"], 0, None);
        }
        for (i, &run) in runs.iter().enumerate() {
            let gate = if i == 0 { 0 } else { runs[i - 1] };
            let config = self.config(0, run, gate, generation);
            let k = &mut self.kernels;
            let mut extra = gate_extra.to_vec();
            extra.extend_from_slice(&request_extra);
            k.record(&mut encoder, &guard, true, false, config, &extra, &mut report)?;
            let mut consumer = |encoder: &mut wgpu::CommandEncoder,
                                guard: &Store,
                                run: u32,
                                results: &wgpu::Buffer,
                                counts: &wgpu::Buffer|
             -> Result<()> {
                let mut config = config;
                let close = i + 1 == rounds;
                config[1] = run;
                config[2] = if close { run } else { 0 };
                let extra = [
                    ("sb_results", results),
                    ("sb_counts", counts),
                    request_extra[1],
                ];
                k.record(encoder, guard, false, close, config, &extra, &mut report)
            };
            let dispatches = self
                .engine
                .record_chained(&mut encoder, &guard, &self.requests, i, run, &mut consumer);
            drop(consumer);
            report.substitution_dispatches += dispatches?;
        }
        self.kernels.queue.submit(Some(encoder.finish()));
        self.report = report;
        Ok(())
    }

    fn read_status(&mut self) -> Result<Vec<u32>> {
        self.report.readbacks += 1;
        read_many_labeled(
            &self.kernels.device,
            &self.kernels.queue,
            &[(&self.kernels.buffers["ps_status"], STATUS_WORDS)],
            crate::readback_label!("retained_schema.status"),
        )
    }

    /// Finishes the rounds from `status`, the words a readback after
    /// `record_chain` returned: it resumes stopped rounds and records more
    /// chains until the rounds converge. Returns the report and whether
    /// anything ran after that readback (a pass recorded before it must
    /// then be recorded again). With `reopen`, rounds that converged run
    /// again for terms the store gained after the readback.
    pub fn settle(&mut self, store: &ProgramRetention, status: &[u32], reopen: bool) -> Result<(SchemaReport, bool)> {
        let result = self.settle_inner(store, status, reopen);
        if result.is_err() {
            let guard = store.store.lock().unwrap();
            self.kernels.queue.write_buffer_counted(
                &guard.buffers["rt_counts"],
                (crate::type_checker::program_retention::counts::READY * 4) as u64,
                &0u32.to_le_bytes(),
            );
            self.kernels.queue.submit(None);
        }
        result
    }

    fn settle_inner(&mut self, store: &ProgramRetention, status: &[u32], reopen: bool) -> Result<(SchemaReport, bool)> {
        let mut status = status.to_vec();
        check_sync(&status)?;
        let mut ran = false;
        if reopen && status[S_STOP] == STOP_CONVERGED {
            self.kernels.queue.write_buffer_counted(
                &self.kernels.buffers["ps_status"],
                (S_STOP * 4) as u64,
                &STOP_RUNNING.to_le_bytes(),
            );
            self.record_chain(store, false)?;
            ran = true;
            status = self.read_status()?;
            check_sync(&status)?;
        }
        loop {
            match status[S_STOP] {
                STOP_CONVERGED => {
                    self.report.rounds = status[S_ROUNDS];
                    self.report.requests = status[S_BASE];
                    return Ok((self.report.clone(), ran));
                }
                STOP_RUNNING => {
                    // Every recorded round ran and the store still gained
                    // terms: record more rounds, from the GPU's state.
                    self.rounds = (self.rounds * 2).min(MAX_ROUNDS);
                    self.record_chain(store, false)?;
                }
                STOP_UNPUBLISHED | STOP_CAPACITY => {
                    if status[S_STOP] == STOP_CAPACITY {
                        let requests = status[S_DEMAND_REQUESTS];
                        if self.requests.capacity() < requests {
                            let rows = requests.max(self.requests.capacity().saturating_mul(2));
                            self.requests = SubstitutionRequests::new_with_device(&self.kernels.device, rows);
                        }
                        let fields = status[S_DEMAND_FIELDS];
                        if fields == u32::MAX {
                            bail!("schema record count overflow");
                        }
                        if self.field_capacity < fields {
                            self.field_capacity = fields.max(self.field_capacity.saturating_mul(2));
                        }
                    }
                    self.resume(store)?;
                }
                STOP_FAILED => bail!("schema planning failed: {}", status[S_ERROR]),
                stop => bail!("schema rounds stopped in state {stop}"),
            }
            ran = true;
            status = self.read_status()?;
            check_sync(&status)?;
        }
    }

    /// Substitutes the armed round again on the full substitution path,
    /// which grows its tables and the store, then consumes and closes it.
    fn resume(&mut self, store: &ProgramRetention) -> Result<()> {
        self.report.resumed += 1;
        self.kernels.ensure("pj_schema_fields", u64::from(self.field_capacity) * 8, true)?;
        self.kernels.queue.write_buffer_counted(
            &self.kernels.buffers["ps_status"],
            (S_STOP * 4) as u64,
            &STOP_RUNNING.to_le_bytes(),
        );
        let requests = self.requests.buffers().map(|(n, b)| (n, b.clone()));
        let request_extra = requests.iter().map(|(n, b)| (*n, b)).collect::<Vec<_>>();
        let mut report = std::mem::take(&mut self.report);
        {
            let guard = store.store.lock().unwrap();
            let config = self.config(1, 0, 0, guard.generation);
            self.kernels.cursor = 0;
            let mut encoder = self.kernels.device.create_command_encoder(&Default::default());
            let (_, counts) = self.engine.chain_buffers()
                .ok_or_else(|| anyhow!("schema substitution buffers are not allocated"))?;
            let mut extra = request_extra.clone();
            extra.push(("sb_counts", counts));
            self.kernels.record(&mut encoder, &guard, true, true, config, &extra, &mut report)?;
            self.kernels.queue.submit(Some(encoder.finish()));
        }
        let substitution = match self.engine.run(store, &self.requests) {
            Ok(SubstitutionRun::Published(r)) => r,
            Ok(SubstitutionRun::RequestCapacity { requested, capacity }) => {
                self.report = report;
                bail!("schema wrote {requested} requests into {capacity} rows")
            }
            Err(error) => {
                self.report = report;
                return Err(error);
            }
        };
        report.substitution_dispatches += substitution.dispatches;
        let run = substitution.publication.run;
        let published = self
            .engine
            .publication(store)
            .ok_or_else(|| anyhow!("schema publication not current"))?;
        let results = published.results.clone();
        let counts = published.counts.clone();
        let guard = store.store.lock().unwrap();
        let mut encoder = self.kernels.device.create_command_encoder(&Default::default());
        let consume = self.config(1, run, run, guard.generation);
        let extra = [("sb_results", &results), ("sb_counts", &counts), request_extra[1]];
        self.kernels.record(&mut encoder, &guard, false, true, consume, &extra, &mut report)?;
        self.kernels.queue.submit(Some(encoder.finish()));
        self.report = report;
        Ok(())
    }
}


fn check_sync(status: &[u32]) -> Result<()> {
    if status[PREPARE_FAILED] != 0 || status[PUBLISH_FAILED] != 0 || status[S_ERROR] & 4 != 0 {
        bail!("retained schema program failed to synchronize");
    }
    Ok(())
}
