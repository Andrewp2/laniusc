//! GPU discovery of closed instances from retained call uses.
//!
//! Direct calls and accepted implementation methods follow exact ENV edges.
//! Required trait members need concrete solver routes. Bounded direct calls
//! require a current retained trait publication, checked per use on the GPU. No unsupported call is omitted or sent to source replay.
use crate::gpu::copies::{CountedCommands, CountedWrites};
use std::collections::BTreeMap;

use anyhow::{Result, anyhow, bail};

use super::{
    ProgramRetention,
    Store,
    counts,
    projection::ProjectionInputs,
    reflected_names,
    storage,
    substitution::{
        RetainedSubstitution,
        SubstitutionCapacity,
        SubstitutionRequests,
        SubstitutionRun,
    },
    words_bytes,
};
use crate::compiler::{ClosedChainInputs, ClosedTraitPublication, RetainedTraitPublication};
use crate::gpu::{
    buffers::LaniusBuffer,
    operations::{StepProgramOperation, step_program_group_counts, step_program_group_variant},
    passes_core::{self, PassData, make_pass_data_from_shader_key, map_readback_blocking},
};

const RANK_INSTANCES_PROGRAM: &str = "type_checker/retention/discovery/rank_retained_instances";
const COLLECT_PROGRAM: &str = "type_checker/retention/discovery/collect_retained_requests";
const RESOLVE_PROGRAM: &str = "type_checker/retention/discovery/resolve_retained_requests";
const CLOSED_WAVE_PROGRAM: &str = "type_checker/retention/discovery/expand_closed_retained_discovery_wave";
const WAVE_PROGRAM: &str = "type_checker/retention/discovery/expand_retained_discovery_wave";
// DG_SORT_BLOCK in discovery_workspace.slang.
const RANK_BLOCK_ROWS: u32 = 512;
const COLLECT: usize = 0;
const RESOLVE: usize = 1;
const PUBLISH_RANKS: usize = 2;
const RANK_INSTANCES: usize = 3;
const PUBLISH_WAVE: usize = 4;
const ATTACH_METHOD_ROUTES: usize = 5;
const EXPAND_CLOSED_WAVE: usize = 6;
const COLLECT_FRONTIER: usize = 7;
const EXPAND_WAVE: usize = 8;
const VALIDATE_TERMS: usize = 9;
const KERNELS: &[&str] = &[
    COLLECT_PROGRAM,
    RESOLVE_PROGRAM,
    "type_checker/retention/discovery/publish_ranked_instances",
    RANK_INSTANCES_PROGRAM,
    "type_checker/retention/discovery/publish_discovery_wave",
    "type_checker/retention/discovery/attach_discovered_method_routes",
    CLOSED_WAVE_PROGRAM,
    "type_checker/retention/discovery/collect_discovery_frontier",
    WAVE_PROGRAM,
    "type_checker/retention/discovery/validate_discovery_terms",
];
const STATUS_WORDS: usize = 32;
const METHOD_ROUTES_SYNC_FAILED: usize = 31;
const RANK_SYNC_FAILED: usize = 30;
const COLLECT_SYNC_FAILED: usize = 29;
const RESOLVE_SYNC_FAILED: usize = 28;
const CLOSED_WAVE_SYNC_FAILED: usize = 24;
/// Route header words 8-10 of a retained trait publication: status (1
/// valid), route failures, first failure (retained_route_abi.slang).
const PUBLICATION_STATUS_WORD: u64 = 8;
const PUBLICATION_STATUS_WORDS: usize = 3;
const FIRST_ERROR: usize = 6;
/// Waves without closed predicates that the first chain of a discovery
/// records back to back in one submit (`chain_waves`), with one readback
/// after the last. Each further chain of the same attempt records twice as
/// many, up to `CHAIN_WAVES_MAX`.
const CHAIN_WAVES: u32 = 3;
const CHAIN_WAVES_MAX: u32 = 48;
/// Waves of a closed chain (`chain_closed`) that record a closed solve,
/// before its tail of waves without one.
const CLOSED_CHAIN_WAVES: u32 = 3;
/// Bound of a chained wave's instances with closed predicates, unless the
/// first wave has more (`chain_closed`).
const CLOSED_CHAIN_SELECTED: u32 = 64;
/// dg_wave word counting the chained closed solves that ran (plan_closed_obligation_dispatches).
const WAVE_CLOSED_RAN: u32 = 4 + 2 * CHAIN_WAVES_MAX;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DiscoveryCapacity {
    pub instances: u32,
    pub edges: u32,
    pub requests: u32,
}
impl Default for DiscoveryCapacity {
    fn default() -> Self {
        Self {
            instances: 4096,
            edges: 16384,
            requests: 16384,
        }
    }
}
impl DiscoveryCapacity {
    pub fn tiny() -> Self {
        Self {
            instances: 2,
            edges: 2,
            requests: 2,
        }
    }
}
#[derive(Clone, Debug, Default)]
pub struct DiscoveryReport {
    pub attempts: u32,
    pub waves: u32,
    pub dispatches: u32,
    pub readbacks: u32,
    pub instances: u32,
    pub edges: u32,
    pub roots: u32,
    pub substitution_dispatches: u32,
    pub closed_trait_waves: u32,
    pub method_route_waves: u32,
    /// Closed chains recorded (`chain_closed`), and those that came back
    /// with a capacity overflow (the attempt grew and ran again chained)
    /// or otherwise not clean (it ran again without chaining).
    pub closed_chains: u32,
    pub closed_chain_growths: u32,
    pub closed_chain_fallbacks: u32,
}
#[derive(Clone, Debug)]
pub struct DiscoveryError {
    pub code: u32,
    pub use_index: u32,
    pub instance: u32,
    pub detail: u32,
}
pub enum DiscoveryOutcome {
    Published(DiscoveryPublication),
    Rejected(DiscoveryError),
}
pub struct DiscoveryPublication {
    pub inputs: ProjectionInputs,
    pub root_routes: LaniusBuffer<u32>,
    pub root_readiness: LaniusBuffer<u32>,
    pub root_route_capacity: u32,
    pub generation: u32,
    pub report: DiscoveryReport,
    /// Whether discovery read its final status before publishing. When it
    /// did not ([`RetainedDiscovery::defer_final_status`]), a failure after
    /// the last wave leaves the projection inputs not ready, and the caller
    /// asks [`RetainedDiscovery::final_failure`] when projection rejects
    /// them.
    pub status_checked: bool,
}

struct TraitAdmission {
    routes: wgpu::Buffer,
    offset: u64,
    size: u64,
    identity: [u32; 8],
}

pub struct RetainedDiscovery {
    device: std::sync::Arc<wgpu::Device>,
    queue: std::sync::Arc<wgpu::Queue>,
    passes: Vec<PassData>,
    capacity: DiscoveryCapacity,
    /// Taken while a resolution records into the substitution's submit.
    substitution: Option<RetainedSubstitution>,
    scratch: BTreeMap<&'static str, wgpu::Buffer>,
    configs: Vec<wgpu::Buffer>,
    config_cursor: usize,
    hash_mask: u32,
    admission: Option<TraitAdmission>,
    /// Taken while the bound routes record into the method routes' submit.
    method_routes: Option<super::method_routes::MethodRoutes>,
    /// Set for the rest of this discovery's life after a closed solve did
    /// not finish in its first submit: later closed waves read the solver's
    /// progress before their resolution, as the solve requires.
    eager_closed: bool,
    /// The published buffers of the last attempt, with the capacities
    /// (instances, edges, requests) they hold: a warm build with the
    /// same capacities binds the same buffers, so its bind groups are the
    /// cached ones.
    published: Option<([u32; 3], ProjectionInputs, SubstitutionRequests)>,
    root_routes: Option<LaniusBuffer<u32>>,
    root_readiness: Option<LaniusBuffer<u32>>,
    /// See [`Self::defer_final_status`].
    defer_final_status: bool,
    /// Dispatches recorded but not yet in the encoder: kernel, bind group
    /// and launch. `flush` records them as one compute pass; it runs before
    /// every other use of the encoder (a copy, a clear, another module's
    /// recording, `finish`). wgpu-core's `finish` costs about 13 µs per
    /// compute pass, so one pass per dispatch cost discovery milliseconds.
    pending: Vec<(usize, wgpu::BindGroup, u32)>,
}
impl RetainedDiscovery {
    pub fn new(capacity: DiscoveryCapacity, substitution: SubstitutionCapacity) -> Result<Self> {
        Self::new_with_device(crate::gpu::device::global(), capacity, substitution)
    }

    pub(crate) fn new_with_device(gpu: &crate::gpu::device::GpuDevice, capacity: DiscoveryCapacity, substitution: SubstitutionCapacity) -> Result<Self> {
        let passes = KERNELS
            .iter()
            .map(|key| make_pass_data_from_shader_key(&gpu.device, key, "main", key))
            .collect::<Result<Vec<_>>>()?;
        Ok(Self {
            device: gpu.device.clone(),
            queue: gpu.queue.clone(),
            passes,
            capacity,
            substitution: Some(RetainedSubstitution::new_with_device(gpu, substitution)?),
            scratch: BTreeMap::new(),
            configs: Vec::new(),
            config_cursor: 0,
            hash_mask: u32::MAX,
            admission: None,
            method_routes: Some(super::method_routes::MethodRoutes::new_with_device(gpu)?),
            eager_closed: false,
            published: None,
            root_routes: None,
            root_readiness: None,
            defer_final_status: false,
            pending: Vec::new(),
        })
    }
    /// With `defer`, discovery publishes without reading the status of its
    /// ranking and publish passes. Those passes write the projection's and
    /// the roots' readiness only when nothing failed, so the projection's
    /// plan rejects the inputs of a failed discovery, and its readback is
    /// the first one after discovery. The caller then reads the failure
    /// with [`Self::final_failure`].
    pub fn defer_final_status(&mut self, defer: bool) {
        self.defer_final_status = defer;
    }
    /// The failure the last discovery's final passes reported, read from
    /// its status words; for a publication that did not check them.
    pub fn final_failure(&mut self) -> Result<Option<DiscoveryError>> {
        let mut report = DiscoveryReport::default();
        let status = self.read_status(&mut report)?;
        Ok(failure(&status))
    }
    pub fn set_hash_mask(&mut self, mask: u32) {
        self.hash_mask = mask;
    }
    pub fn run(&mut self, store: &ProgramRetention) -> Result<DiscoveryOutcome> {
        self.run_admitted(store, None, None)
    }
    /// The GPU checks the publication identity, immutable source-store extent,
    /// and the proof map for each bounded direct call before admitting it.
    pub fn run_with_traits(
        &mut self,
        store: &ProgramRetention,
        publication: &mut RetainedTraitPublication,
    ) -> Result<DiscoveryOutcome> {
        let view = publication.view(store)?;
        let id = view.identity;
        self.run_admitted(store, Some(TraitAdmission {
            routes: view.routes.buffer.clone(),
            offset: view.routes.offset,
            size: view.routes.size,
            identity: [1, id.epoch as u32, (id.epoch >> 32) as u32,
                id.arena_id as u32, (id.arena_id >> 32) as u32,
                id.serial, id.generation, 0],
        }), Some(publication))
    }
    fn run_admitted(&mut self, store: &ProgramRetention, admission: Option<TraitAdmission>, publication: Option<&mut RetainedTraitPublication>) -> Result<DiscoveryOutcome> {
        self.admission = admission;
        let result = self.run_inner(store, publication);
        self.admission = None;
        if result.is_err() {
            let guard = store.store.lock().unwrap();
            self.queue.write_buffer_counted(
                &guard.buffers["rt_counts"],
                (counts::READY * 4) as u64,
                &0u32.to_le_bytes(),
            );
            self.queue.submit(None);
        }
        result
    }
    fn run_inner(&mut self, store: &ProgramRetention, mut publication: Option<&mut RetainedTraitPublication>) -> Result<DiscoveryOutcome> {
        // The catalog read the store's counters with its publication
        // status; nothing writes the store between them.
        let initial = match publication.as_deref().and_then(|p| p.take_store_counts(store)) {
            Some(words) => words,
            None => store.status()?,
        };
        let uses = initial[8];
        let generation = store.generation();
        let mut report = DiscoveryReport::default();
        // Waves without closed predicates run as chains until a chain does
        // not come back clean; the attempt then runs again unchained.
        let mut chain = true;
        'attempt: loop {
            report.attempts += 1;
            report.waves = 0;
            self.capacity.instances = self
                .capacity
                .instances
                .max(2)
                .checked_next_power_of_two()
                .ok_or_else(|| anyhow!("discovery instance capacity exhausted"))?;
            self.capacity.edges = self.capacity.edges.max(1);
            self.capacity.requests = self.capacity.requests.max(1);
            self.allocate(uses)?;
            let identity = self.admission.as_ref().map_or([0; 8], |a| a.identity);
            self.queue.write_buffer_counted(&self.scratch["dg_proof_identity"], 0, &words_bytes(&identity));
            let key = [self.capacity.instances, self.capacity.edges, self.capacity.requests];
            if self.published.as_ref().is_none_or(|(held, ..)| *held != key) {
                self.published = Some((
                    key,
                    ProjectionInputs::new_with_device(&self.device, self.capacity.instances, self.capacity.edges),
                    SubstitutionRequests::new_with_device(&self.device, self.capacity.requests),
                ));
            }
            let root_route_capacity = uses.max(1);
            let route_bytes = u64::from(root_route_capacity) * 16;
            if self.root_routes.as_ref().is_none_or(|buf| buf.buffer.size() < route_bytes) {
                let buffer = self.buffer("dg_root_routes", route_bytes)?;
                self.root_routes = Some(LaniusBuffer::new_labeled(
                    (buffer, route_bytes),
                    root_route_capacity as usize * 4,
                    "dg_root_routes",
                ));
            }
            if self.root_readiness.is_none() {
                let buffer = self.buffer("dg_root_readiness", 16)?;
                self.root_readiness = Some(LaniusBuffer::new_labeled(
                    (buffer, 16), 4, "dg_root_readiness",
                ));
            }
            let root_routes = self.root_routes.as_ref().expect("root routes allocated").clone();
            let root_readiness = self.root_readiness.as_ref().expect("root readiness allocated").clone();
            let (_, inputs, requests) =
                self.published.clone().ok_or_else(|| anyhow!("discovery buffers are not allocated"))?;
            let mut extra: Vec<(&str, &wgpu::Buffer)> = inputs.buffers().into_iter().collect();
            extra.extend([
                ("dg_root_routes", &root_routes.buffer),
                ("dg_root_readiness", &root_readiness.buffer),
            ]);
            extra.extend(requests.buffers());
            let mut config = [0u32; 16];
            config[4] = 1;
            config[6] = 1;
            config[7] = self.hash_mask;
            config[15] = generation;
            let mut encoder = self.encoder();
            for name in ["dg_slots", "dg_instances", "dg_roots", "dg_status"] {
                self.flush(&mut encoder);
                encoder.clear_buffer_counted(&self.scratch[name], 0, None);
            }
            for (_, buffer) in inputs.buffers() {
                self.flush(&mut encoder);
                encoder.clear_buffer_counted(buffer, 0, None);
            }
            self.flush(&mut encoder);
            encoder.clear_buffer_counted(&root_routes, 0, None);
            self.flush(&mut encoder);
            encoder.clear_buffer_counted(&root_readiness, 0, None);
            self.flush(&mut encoder);
            encoder.clear_buffer_counted(requests.buffers()[1].1, 0, None);
            { let commands = self.finish(encoder); self.queue.submit(Some(commands)); }
            self.queue.write_buffer_counted(
                &self.scratch["dg_status"],
                (FIRST_ERROR * 4) as u64,
                &u32::MAX.to_le_bytes(),
            );
            self.config_cursor = 0;
            let guard = store.store.lock().unwrap();
            let mut encoder = self.encoder();
            // The source publication's status words come back with the
            // roots' resolution readback (dg_receipt is free until the
            // first closed wave).
            let receipt_buffer = self.scratch["dg_receipt"].clone();
            if let Some(admission) = &self.admission {
                encoder.copy_buffer_counted(
                    &admission.routes,
                    admission.offset + PUBLICATION_STATUS_WORD * 4,
                    &receipt_buffer,
                    0,
                    PUBLICATION_STATUS_WORDS as u64 * 4,
                );
            }
            let publication_read = publication.as_ref().map(|_| (&receipt_buffer, PUBLICATION_STATUS_WORDS));
            config[10] = u32::from(self.admission.is_some());
            { let commands = self.finish(encoder); self.queue.submit(Some(commands)); }
            drop(guard);
            // As in a wave, resolution skips itself after a root failure or
            // overflow (status 12), and its readback reports both.
            let resolved = self.resolve(store, &requests, &extra, config, publication_read, None, &mut report)?;
            let request_capacity = resolved.is_none();
            let mut status = match resolved {
                Some((words, _)) => words,
                None => self.read_status_counts(store, publication_read.as_slice(), &mut report)?,
            };
            // A source publication that is not valid rejects discovery
            // before any growth or failure of the roots; the caller reads
            // the noted status and reports the publication's failure.
            if let Some(source) = publication.as_deref() {
                let at = STATUS_WORDS + counts::WORDS;
                let words = [status[at], status[at + 1], status[at + 2]];
                source.note_status(words);
                if words != [1, 0, u32::MAX] {
                    return Ok(DiscoveryOutcome::Rejected(DiscoveryError {
                        code: 10,
                        use_index: u32::MAX,
                        instance: u32::MAX,
                        detail: words[2],
                    }));
                }
            }

            if self.grow(&status)? {
                continue 'attempt;
            }
            if request_capacity {
                bail!("discovery request capacity exceeded without a growth request");
            }
            if let Some(error) = failure(&status) {
                return Ok(DiscoveryOutcome::Rejected(error));
            }
            let mut lo = 0;
            let mut hi = status[0];
            let mut edges = 0;
            let mut depth = 1;
            let mut predicated = 0;
            let mut chain_waves = CHAIN_WAVES;
            while lo < hi {
                // Concrete instances have closed goals, even when their
                // source call was proved parametrically. Reuse the admitted
                // catalog; the GPU writes and solves this wave's hard goals.
                // The GPU counts inserted instances with closed predicates
                // (status 11); a wave without any needs no solver work.
                let wave_predicated = status[11] - predicated;
                if chain && !self.eager_closed && wave_predicated != 0
                    && let Some(source) = publication.as_deref_mut()
                {
                    let tail = chain_waves;
                    chain_waves = (chain_waves * 2).min(CHAIN_WAVES_MAX - CLOSED_CHAIN_WAVES);
                    let wave = [lo, hi, edges, depth, predicated, wave_predicated, tail];
                    report.closed_chains += 1;
                    match self.chain_closed(store, source, &requests, &extra, config, wave, &status[STATUS_WORDS..], &mut report)? {
                        ClosedChain::Clean(chained) => {
                            status = chained.status;
                            report.waves += chained.ran;
                            lo = chained.lo;
                            hi = status[0];
                            edges = status[2];
                            predicated = chained.predicated;
                            depth += chained.ran;
                            if depth > 65 {
                                bail!("discovery exceeded its depth contract");
                            }
                            continue;
                        }
                        ClosedChain::Grown => {
                            report.closed_chain_growths += 1;
                            continue 'attempt;
                        }
                        ClosedChain::Fallback => {
                            report.closed_chain_fallbacks += 1;
                            chain = false;
                            continue 'attempt;
                        }
                    }
                }
                predicated = status[11];
                let mut closed = if let Some(source) = publication.as_deref_mut()
                    && wave_predicated != 0
                {
                    let buffer = self.scratch["dg_instances"].clone();
                    let bytes = buffer.size();
                    let instances = LaniusBuffer::new((buffer, bytes), bytes as usize / 4);
                    let (check, proofs) = source.solve_instances_with_counts(
                        store,
                        &instances,
                        lo,
                        hi,
                        Some(&status[STATUS_WORDS..]),
                        true,
                        (!self.eager_closed).then_some(wave_predicated),
                    )?;
                    report.closed_trait_waves += 1;
                    if check.producer_failures != 0 {
                        return Ok(DiscoveryOutcome::Rejected(DiscoveryError {
                            code: 8, use_index: u32::MAX, instance: check.first_failure, detail: check.producer_failures,
                        }));
                    }
                    // The publication's receipt comes back with this wave's
                    // resolution readback.
                    proofs
                } else { None };
                if closed.is_none() && chain {
                    let waves = chain_waves;
                    chain_waves = (chain_waves * 2).min(CHAIN_WAVES_MAX);
                    match self.chain_waves(store, &requests, &extra, config, [lo, hi, edges, depth, predicated, waves], &mut report)? {
                        Some(chained) => {
                            status = chained.status;
                            report.waves += chained.ran;
                            lo = chained.lo;
                            hi = status[0];
                            edges = status[2];
                            depth += chained.ran;
                            if depth > 65 {
                                bail!("discovery exceeded its depth contract");
                            }
                            continue;
                        }
                        None => {
                            chain = false;
                            continue 'attempt;
                        }
                    }
                }
                // One lane expands each newly interned instance's uses.
                report.waves += 1;
                config[0] = 0;
                config[1] = lo;
                config[2] = hi;
                config[3] = edges;
                config[4] = 0;
                config[6] = depth + 1;
                config[9] = 0;
                self.config_cursor = 0;
                let guard = store.store.lock().unwrap();
                let mut encoder = self.encoder();
                if let Some(proofs) = &closed {
                    proofs.copy_receipt(&mut encoder, &self.scratch["dg_receipt"], 0);
                }
                self.record(&mut encoder, &guard, COLLECT, config, &extra, hi - lo, &mut report)?;
                { let commands = self.finish(encoder); self.queue.submit(Some(commands)); }
                drop(guard);
                // Resolution reads back the status (and store counters)
                // with the substitution's counts.
                let receipt_buffer = self.scratch["dg_receipt"].clone();
                let receipt_read = closed
                    .as_ref()
                    .map(|_| (&receipt_buffer, ClosedTraitPublication::RECEIPT_WORDS));
                // With closed proofs, the first method-route batch rides in
                // resolution's first submit.
                let mut routes = self
                    .method_routes
                    .take()
                    .ok_or_else(|| anyhow!("discovery method routes are in use"))?;
                let resolved = match (publication.as_deref(), closed.as_ref()) {
                    (Some(source), Some(proofs)) => {
                        let nodes_bound = proofs.proof_node_bound();
                        routes.prepare(requests.capacity(), nodes_bound).and_then(|()| {
                            let spec = SpeculativeRoutes {
                                routes: &routes,
                                view: proofs.view(source, store)?,
                                receipt: &receipt_buffer,
                                nodes_bound,
                                metadata: self.scratch["dg_req_meta"].clone(),
                                instances: self.scratch["dg_instances"].clone(),
                            };
                            self.resolve(store, &requests, &extra, config, receipt_read, Some(&spec), &mut report)
                        })
                    }
                    _ => self.resolve(store, &requests, &extra, config, receipt_read, None, &mut report),
                };
                self.method_routes = Some(routes);
                let mut first_batch = false;
                status = match resolved? {
                    Some((words, first)) => {
                        first_batch = first;
                        words
                    }
                    None => {
                        let words = self.read_status_counts(store, receipt_read.as_slice(), &mut report)?;
                        match closed_receipt_failure(closed.as_mut(), &words, lo)? {
                            Closed::Rejected(error) => return Ok(DiscoveryOutcome::Rejected(error)),
                            Closed::Unfinished => {
                                self.eager_closed = true;
                                continue 'attempt;
                            }
                            Closed::Accepted => {}
                        }
                        if self.grow(&words)? {
                            continue 'attempt;
                        }
                        bail!("discovery request capacity exceeded without a growth request");
                    }
                };
                // A deferred closed solve that did not finish leaves this
                // wave's routes incomplete: the attempt runs again with
                // eager closed solves.
                match closed_receipt_failure(closed.as_mut(), &status, lo)? {
                    Closed::Rejected(error) => return Ok(DiscoveryOutcome::Rejected(error)),
                    Closed::Unfinished => {
                        self.eager_closed = true;
                        continue 'attempt;
                    }
                    Closed::Accepted => {}
                }
                if self.grow(&status)? {
                    continue 'attempt;
                }
                if let Some(error) = failure(&status) {
                    return Ok(DiscoveryOutcome::Rejected(error));
                }
                let speculative = STATUS_WORDS + counts::WORDS + ClosedTraitPublication::RECEIPT_WORDS;
                let finished = |state: &[u32]| {
                    state[super::method_routes::MR_PENDING] == 0 && state[0] != 3
                };
                if closed.is_some() && first_batch && finished(&status[speculative..speculative + 32]) {
                    // The first batch's routes finished: their bound routes
                    // already ran, and `status` came after them.
                    let state = &status[speculative..speculative + 32];
                    report.method_route_waves += 1;
                    if state[0] != 2 {
                        return Ok(DiscoveryOutcome::Rejected(DiscoveryError {
                            code: 9,
                            use_index: state[16],
                            instance: state[17],
                            detail: state[18] | (state[3] << 24),
                        }));
                    }
                } else if let (Some(source), Some(proofs)) = (publication.as_deref(), closed.as_ref()) {
                    let engine = self
                        .substitution
                        .take()
                        .ok_or_else(|| anyhow!("discovery substitution is in use"))?;
                    let Some(mut routes) = self.method_routes.take() else {
                        self.substitution = Some(engine);
                        bail!("discovery method routes are in use");
                    };
                    let state = self.method_route_wave(
                        store, source, proofs, &engine, &mut routes, &extra, &mut config, &mut report,
                    );
                    self.method_routes = Some(routes);
                    self.substitution = Some(engine);
                    let state = state?;
                    report.method_route_waves += 1;
                    report.readbacks += 1;
                    if state[0] != 2 {
                        return Ok(DiscoveryOutcome::Rejected(DiscoveryError {
                            code: 9,
                            use_index: state[16],
                            instance: state[17],
                            detail: state[18] | (state[3] << 24),
                        }));
                    }
                    status = state[32..].to_vec();
                    if self.grow(&status)? {
                        continue 'attempt;
                    }
                    if let Some(error) = failure(&status) {
                        return Ok(DiscoveryOutcome::Rejected(error));
                    }
                }
                lo = hi;
                hi = status[0];
                edges = status[2];
                depth += 1;
                if depth > 65 {
                    bail!("discovery exceeded its depth contract");
                }
            }
            report.instances = status[1];
            report.edges = status[2];
            report.roots = status[9];
            if crate::options::get().report.resources.is_some() {
                eprintln!(
                    "[program_retention] discovery term_rows={} spare_term_rows={} instance_rows={} live_instances={}",
                    status[STATUS_WORDS + super::A_TERMS],
                    status[STATUS_WORDS + counts::SPARE + super::A_TERMS],
                    status[0],
                    status[1],
                );
            }
            // Rank by full environment structure. Hashes do not determine
            // the order, even with forced table collisions.
            self.rank_instances(store, &status, uses, &extra, config, &mut report)?;
            if !self.defer_final_status {
                let status = self.read_status(&mut report)?;
                if let Some(error) = failure(&status) {
                    return Ok(DiscoveryOutcome::Rejected(error));
                }
            }
            drop(extra);
            return Ok(DiscoveryOutcome::Published(DiscoveryPublication {
                inputs,
                root_routes,
                root_readiness,
                root_route_capacity,
                generation,
                report,
                status_checked: !self.defer_final_status,
            }));
        }
    }
    /// Converts this wave's bound-member proofs to method routes. The bound
    /// routes and the publish pass share the routes' submit; they run only
    /// after the routes finished, and the discovery status and store
    /// counters come back with the routes' state (from word 32).
    #[allow(clippy::too_many_arguments)]
    fn method_route_wave(
        &mut self,
        store: &ProgramRetention,
        source: &RetainedTraitPublication,
        proofs: &ClosedTraitPublication,
        engine: &RetainedSubstitution,
        routes: &mut super::method_routes::MethodRoutes,
        extra: &[(&str, &wgpu::Buffer)],
        config: &mut [u32; 16],
        report: &mut DiscoveryReport,
    ) -> Result<Vec<u32>> {
        let sub = engine
            .publication(store)
            .ok_or_else(|| anyhow!("missing method substitution"))?;
        config[5] = sub.id.run;
        let config = *config;
        let requests = sub.id.requests;
        let req_meta = self.scratch["dg_req_meta"].clone();
        let instances = self.scratch["dg_instances"].clone();
        let status_buffer = self.scratch["dg_status"].clone();
        let counts_buffer = store.store.lock().unwrap().buffers["rt_counts"].clone();
        let mut then = |encoder: &mut wgpu::CommandEncoder,
                        guard: &Store,
                        state: &wgpu::Buffer,
                        output: &wgpu::Buffer|
         -> Result<()> {
            let mut bound = extra.to_vec();
            bound.push(("mr_out", output));
            bound.push(("mr_state", state));
            self.config_cursor = 0;
            self.record(encoder, guard, ATTACH_METHOD_ROUTES, config, &bound, requests, report)?;
            self.record(encoder, guard, PUBLISH_WAVE, config, extra, 1, report)?;
            self.flush(encoder);
            Ok(())
        };
        routes.run(
            store,
            source,
            proofs,
            &sub,
            &req_meta,
            &instances,
            &mut then,
            &[(&status_buffer, STATUS_WORDS), (&counts_buffer, counts::WORDS)],
        )
    }
    /// Records waves without closed predicates in one submit, starting
    /// with the frontier `lo..hi` (`wave` is lo, hi, edges, depth, the
    /// predicated instance count and the number of waves). Wave 0 is the
    /// host's. Before each later wave the program places the
    /// instances the previous wave inserted, or an empty frontier when the
    /// host must decide first (a failure, an overflow, new closed
    /// predicates), and copies (lo, hi, edges) into the wave's configs.
    /// Each wave substitutes its requests in its own run
    /// and resolves them; a run that did not publish fails resolution with
    /// code 11. One readback returns the status, the store counters, the
    /// last run's status words, the waves' frontiers and the level counts.
    /// Returns None unless the chain came back clean: no failure, no
    /// overflow, the last run published. The caller then runs the attempt
    /// again without chaining.
    fn chain_waves(
        &mut self,
        store: &ProgramRetention,
        requests: &SubstitutionRequests,
        extra: &[(&str, &wgpu::Buffer)],
        config: [u32; 16],
        wave: [u32; 6],
        report: &mut DiscoveryReport,
    ) -> Result<Option<Chained>> {
        let mut engine = self
            .substitution
            .take()
            .ok_or_else(|| anyhow!("discovery substitution is in use"))?;
        let result = self.record_chain(&mut engine, store, requests, extra, config, wave, report);
        self.substitution = Some(engine);
        result
    }
    #[allow(clippy::too_many_arguments)]
    fn record_chain(
        &mut self,
        engine: &mut RetainedSubstitution,
        store: &ProgramRetention,
        requests: &SubstitutionRequests,
        extra: &[(&str, &wgpu::Buffer)],
        config: [u32; 16],
        [lo, hi, edges, depth, predicated, waves]: [u32; 6],
        report: &mut DiscoveryReport,
    ) -> Result<Option<Chained>> {
        let log_words = 4 + 2 * waves as usize;
        let wave_buffer = self.scratch["dg_wave"].clone();
        self.queue.write_buffer_counted(&wave_buffer, 0, &words_bytes(&[lo, hi, edges, predicated]));
        let runs = engine.begin_chain(requests, waves as usize)?;
        let counts_buffer = store.store.lock().unwrap().buffers["rt_counts"].clone();
        let status_buffer = self.scratch["dg_status"].clone();
        let mut bindings = extra.to_vec();
        bindings.extend(engine.chain_bindings()?);
        self.config_cursor = 0;
        let guard = store.store.lock().unwrap();
        let mut encoder = self.encoder();
        self.record_open_waves(
            engine, &mut encoder, &guard, requests, &bindings, config, depth, &runs, 0, report,
        )?;
        { let commands = self.finish(encoder); self.queue.submit(Some(commands)); }
        let generation = guard.generation;
        drop(guard);
        let sb_counts = engine
            .counts_buffer()
            .ok_or_else(|| anyhow!("retained substitution has no status words"))?
            .clone();
        let words = self.read_many(
            &[
                (&status_buffer, STATUS_WORDS),
                (&counts_buffer, counts::WORDS),
                (&sb_counts, super::substitution::words::COUNT),
                (&wave_buffer, log_words),
            ],
            report,
        )?;
        let (status, rest) = words.split_at(STATUS_WORDS + counts::WORDS);
        check_discovery_sync(status)?;
        let (sb, rest) = rest.split_at(super::substitution::words::COUNT);
        let log = &rest[..log_words];
        let last = runs[waves as usize - 1];
        if !engine.finish_chain(sb, last, generation)? || status[3] != 0 || failure(status).is_some() {
            return Ok(None);
        }
        let ran = 1 + (1..waves as usize).filter(|&i| log[5 + 2 * i] > log[4 + 2 * i]).count() as u32;
        Ok(Some(Chained { status: status.to_vec(), lo: log[1], ran, predicated }))
    }
    /// Records waves with closed solves back to back, then a tail of waves
    /// without, with one readback after the last (`wave` is lo, hi, edges,
    /// depth, the instances with closed predicates before the first wave,
    /// those in it, and the tail's length). The first wave's frontier is
    /// the host's and has closed predicates.
    ///
    /// Each of the first `CLOSED_CHAIN_WAVES` waves records its closed
    /// solve before the host has read the wave before it
    /// (`RetainedTraitPublication::record_chained`): sized from the
    /// capacities, gated by plan_closed_obligation_dispatches, which skips it unless the wave has new
    /// instances with closed predicates. The following program checks the
    /// receipt and stops the chain with code 12 when a solve that ran did not place
    /// its batch or did not finish, and gates the wave's method and bound
    /// routes. Routes that did not finish stop it with code 13
    /// (attach_discovered_method_routes). The tail stops at new closed predicates, as
    /// `chain_waves` does.
    ///
    /// Each wave with a closed solve takes two submits. The solve goes first.
    /// The second submit collects the current frontier's calls, resolves them
    /// and prepares the next frontier.
    #[allow(clippy::too_many_arguments)]
    fn chain_closed(
        &mut self,
        store: &ProgramRetention,
        source: &mut RetainedTraitPublication,
        requests: &SubstitutionRequests,
        extra: &[(&str, &wgpu::Buffer)],
        config: [u32; 16],
        wave: [u32; 7],
        counters: &[u32],
        report: &mut DiscoveryReport,
    ) -> Result<ClosedChain> {
        let mut engine = self
            .substitution
            .take()
            .ok_or_else(|| anyhow!("discovery substitution is in use"))?;
        let Some(mut routes) = self.method_routes.take() else {
            self.substitution = Some(engine);
            bail!("discovery method routes are in use");
        };
        let result = self.record_closed_chain(&mut engine, &mut routes, store, source, requests, extra, config, wave, counters, report);
        self.method_routes = Some(routes);
        self.substitution = Some(engine);
        let (words, last, waves) = result?;
        let log_words = WAVE_CLOSED_RAN as usize + 1;
        let (status, rest) = words.split_at(STATUS_WORDS + counts::WORDS);
        check_discovery_sync(status)?;
        let (sb, rest) = rest.split_at(super::substitution::words::COUNT);
        let log = &rest[..log_words];
        let generation = store.generation();
        let engine = self.substitution.as_mut().ok_or_else(|| anyhow!("discovery substitution is in use"))?;
        if !engine.finish_chain(sb, last, generation)? || status[3] != 0 || failure(status).is_some() {
            return Ok(if status[10] == 0 && self.grow(status)? { ClosedChain::Grown } else { ClosedChain::Fallback });
        }
        let ran = 1 + (1..waves as usize).filter(|&i| log[5 + 2 * i] > log[4 + 2 * i]).count() as u32;
        let closed = log[WAVE_CLOSED_RAN as usize];
        report.closed_trait_waves += closed;
        report.method_route_waves += closed;
        Ok(ClosedChain::Clean(Chained {
            status: status.to_vec(),
            lo: log[1],
            ran,
            predicated: log[3],
        }))
    }
    /// `chain_closed`'s recording. Returns the readback words (status,
    /// store counters, the last run's status, the wave log through the
    /// closed count), the last run and the number of waves.
    #[allow(clippy::too_many_arguments)]
    fn record_closed_chain(
        &mut self,
        engine: &mut RetainedSubstitution,
        routes: &mut super::method_routes::MethodRoutes,
        store: &ProgramRetention,
        source: &mut RetainedTraitPublication,
        requests: &SubstitutionRequests,
        extra: &[(&str, &wgpu::Buffer)],
        mut config: [u32; 16],
        [lo, hi, edges, depth, predicated, selected, tail]: [u32; 7],
        counters: &[u32],
        report: &mut DiscoveryReport,
    ) -> Result<(Vec<u32>, u32, u32)> {
        let waves = CLOSED_CHAIN_WAVES + tail;
        let wave_buffer = self.scratch["dg_wave"].clone();
        self.queue.write_buffer_counted(&wave_buffer, 0, &words_bytes(&[lo, hi, edges, predicated]));
        self.queue.write_buffer_counted(&wave_buffer, u64::from(WAVE_CLOSED_RAN) * 4, &words_bytes(&[0]));
        let runs = engine.begin_chain(requests, waves as usize)?;
        let counts_buffer = store.store.lock().unwrap().buffers["rt_counts"].clone();
        let status_buffer = self.scratch["dg_status"].clone();
        let receipt_buffer = self.scratch["dg_receipt"].clone();
        let instances = self.scratch["dg_instances"].clone();
        let instance_buffer = LaniusBuffer::new((instances.clone(), instances.size()), instances.size() as usize / 4);
        let mut bindings = extra.to_vec();
        bindings.extend(engine.chain_bindings()?);
        let request_lanes = requests.capacity();
        let instance_lanes = self.capacity.instances;
        let term_capacity = store.store.lock().unwrap().capacity.arenas[super::A_TERMS];
        let inputs = ClosedChainInputs {
            wave: &wave_buffer,
            discovery: &status_buffer,
            ran_word: WAVE_CLOSED_RAN,
            selected: CLOSED_CHAIN_SELECTED.max(selected.saturating_mul(2)),
            instances: instance_lanes,
            terms: term_capacity,
        };
        self.config_cursor = 0;
        for i in 0..CLOSED_CHAIN_WAVES {
            config[1] = lo;
            config[2] = hi;
            config[3] = edges;
            config[4] = 0;
            config[6] = depth + 1 + i;
            config[8] = i + 1;
            config[9] = 0;
            config[12] = if i + 1 < CLOSED_CHAIN_WAVES { 2 } else { u32::from(tail != 0) };
            let proofs = source.record_chained(store, &instance_buffer, counters, &inputs)?;
            let mut encoder = self.encoder();
            proofs.copy_receipt(&mut encoder, &receipt_buffer, 0);
            let view = proofs.view(source, store)?;
            let guard = store.store.lock().unwrap();
            let nodes_bound = proofs.proof_node_bound();
            routes.prepare(request_lanes, nodes_bound)?;
            let run = runs[i as usize];
            config[5] = run;
            let rows = if i == 0 { hi - lo } else { instance_lanes };
            engine.record_chain_prelude(&mut encoder, i as usize)?;
            let method_bindings = routes.prepare_wave(
                &mut encoder, &guard, &view, run,
                (&receipt_buffer, (RECEIPT_PROOF_NODE_ROWS * 4) as u64, nodes_bound),
            );
            self.record_wave_requests(&mut encoder, &guard, requests, config, &bindings, rows, report)?;
            self.record_with_resources(
                &mut encoder, &guard, EXPAND_CLOSED_WAVE, config, &bindings,
                &method_bindings, rows.max(request_lanes).max(nodes_bound), report,
            )?;
            { let commands = self.finish(encoder); self.queue.submit(Some(commands)); }
            drop(guard);
            // The next solve may reuse this one's buffers: the GPU runs
            // its submits after this wave's.
            drop(proofs);
        }
        let guard = store.store.lock().unwrap();
        let mut encoder = self.encoder();
        self.record_open_waves(
            engine, &mut encoder, &guard, requests, &bindings, config, depth,
            &runs, CLOSED_CHAIN_WAVES as usize, report,
        )?;
        { let commands = self.finish(encoder); self.queue.submit(Some(commands)); }
        drop(guard);
        let sb_counts = engine
            .counts_buffer()
            .ok_or_else(|| anyhow!("retained substitution has no status words"))?
            .clone();
        let log_words = WAVE_CLOSED_RAN as usize + 1;
        let words = self.read_many(
            &[
                (&status_buffer, STATUS_WORDS),
                (&counts_buffer, counts::WORDS),
                (&sb_counts, super::substitution::words::COUNT),
                (&wave_buffer, log_words),
            ],
            report,
        )?;
        Ok((words, runs[waves as usize - 1], waves))
    }
    #[allow(clippy::too_many_arguments)]
    fn record_open_waves(
        &mut self,
        engine: &RetainedSubstitution,
        encoder: &mut wgpu::CommandEncoder,
        guard: &Store,
        requests: &SubstitutionRequests,
        bindings: &[(&str, &wgpu::Buffer)],
        mut config: [u32; 16],
        depth: u32,
        runs: &[u32],
        first: usize,
        report: &mut DiscoveryReport,
    ) -> Result<()> {
        config[4] = 0;
        for (wave, &run) in runs.iter().enumerate().skip(first) {
            config[5] = run;
            config[6] = depth + 1 + wave as u32;
            config[8] = wave as u32 + 1;
            config[12] = u32::from(wave + 1 < runs.len());
            engine.record_chain_prelude(encoder, wave)?;
            self.record_wave_requests(encoder, guard, requests, config, bindings, self.capacity.instances, report)?;
            self.record(encoder, guard, EXPAND_WAVE, config, bindings, requests.capacity(), report)?;
        }
        Ok(())
    }

    #[allow(clippy::too_many_arguments)]
    fn record_wave_requests(
        &mut self,
        encoder: &mut wgpu::CommandEncoder,
        store: &Store,
        requests: &SubstitutionRequests,
        config: [u32; 16],
        bindings: &[(&str, &wgpu::Buffer)],
        rows: u32,
        report: &mut DiscoveryReport,
    ) -> Result<()> {
        self.flush(encoder);
        let [_, (_, count)] = requests.buffers();
        encoder.clear_buffer_counted(count, 0, None);
        self.record(encoder, store, COLLECT_FRONTIER, config, bindings, rows, report)
    }

    /// Substitutes the requests and records resolution in the same submit.
    /// Returns the status words and store counters after resolution, or
    /// None when the requests exceeded the buffers (the request pass
    /// flagged the overflow in status 3, bit 4, and the caller grows).
    fn resolve(
        &mut self,
        store: &ProgramRetention,
        requests: &SubstitutionRequests,
        extra: &[(&str, &wgpu::Buffer)],
        mut config: [u32; 16],
        also_read: Option<(&wgpu::Buffer, usize)>,
        speculative: Option<&SpeculativeRoutes<'_>>,
        report: &mut DiscoveryReport,
    ) -> Result<Option<(Vec<u32>, bool)>> {
        let mut engine = self
            .substitution
            .take()
            .ok_or_else(|| anyhow!("discovery substitution is in use"))?;
        let counts_buffer = store.store.lock().unwrap().buffers["rt_counts"].clone();
        let status_buffer = self.scratch["dg_status"].clone();
        let request_lanes = requests.capacity();
        let uses_for_root = (self.scratch["dg_roots"].size() / 16) as u32;
        config[0] = 0;
        let ran = if config[4] != 0 {
            let mut initial = |engine: &RetainedSubstitution,
                               encoder: &mut wgpu::CommandEncoder,
                               guard: &Store,
                               run: u32| {
                let mut bindings = extra.to_vec();
                bindings.extend(engine.chain_bindings()?);
                let mut config = config;
                config[5] = run;
                self.record_wave_requests(encoder, guard, requests, config, &bindings, uses_for_root, report)?;
                self.record(encoder, guard, EXPAND_WAVE, config, &bindings, request_lanes, report)
            };
            let mut reads = vec![(&status_buffer, STATUS_WORDS), (&counts_buffer, counts::WORDS)];
            reads.extend(also_read);
            engine.run_then(store, requests, None, Some(&mut initial), &reads)
        } else {
            // resolve_discovery_requests does nothing unless this run's publication
            // committed, so it may follow the first batch on the GPU.
            let mut consumer = |encoder: &mut wgpu::CommandEncoder,
                                guard: &Store,
                                run: u32,
                                results: &wgpu::Buffer,
                                counts: &wgpu::Buffer|
             -> Result<()> {
                let mut config = config;
                config[5] = run;
                let mut bindings = extra.to_vec();
                bindings.extend([("sb_results", results), ("sb_counts", counts)]);
                self.config_cursor = 0;
                self.record(encoder, guard, RESOLVE, config, &bindings, request_lanes, report)?;
                let Some(spec) = speculative else { return Ok(()) };
                // The method routes, the bound routes and the publish pass
                // follow in this submit. The routes select nothing unless
                // this run published, and the bound routes do nothing
                // unless the routes finished and resolution left no
                // failure (status 12). The counts come from sb_counts and
                // the receipt copy on the GPU.
                self.flush(encoder);
                spec.routes.record_first_batch(
                    encoder,
                    guard,
                    &spec.view,
                    run,
                    (results, counts),
                    (counts, (super::substitution::words::REQUESTS * 4) as u64, request_lanes),
                    (spec.receipt, (RECEIPT_PROOF_NODE_ROWS * 4) as u64, spec.nodes_bound),
                    &spec.metadata,
                    &spec.instances,
                )?;
                let mut bound = extra.to_vec();
                bound.push(("mr_out", spec.routes.output()));
                bound.push(("mr_state", spec.routes.state()));
                // No config slot of this submit is rewritten.
                self.record(encoder, guard, ATTACH_METHOD_ROUTES, config, &bound, request_lanes, report)?;
                self.record(encoder, guard, PUBLISH_WAVE, config, extra, 1, report)?;
                // Substitution owns this encoder and only flushes its own
                // work. Record these discovery dispatches before it submits.
                self.flush(encoder);
                Ok(())
            };
            let mut reads = vec![(&status_buffer, STATUS_WORDS), (&counts_buffer, counts::WORDS)];
            reads.extend(also_read);
            if let Some(spec) = speculative {
                reads.push((spec.routes.state(), 32));
            }
            engine.run_then(store, requests, Some(&mut consumer), None, &reads)
        };
        self.substitution = Some(engine);
        let (sub, words) = match ran? {
            (SubstitutionRun::Published(r), words) => (r, words),
            (SubstitutionRun::RequestCapacity { .. }, _) => return Ok(None),
        };
        report.substitution_dispatches += sub.dispatches;
        if let Some(words) = words {
            check_discovery_sync(&words)?;
            report.readbacks += 1;
            return Ok(Some((words, true)));
        }
        // The first batch did not finish: resolve the final publication.
        config[5] = sub.publication.run;
        let publication = self
            .substitution
            .as_ref()
            .and_then(|engine| engine.publication(store))
            .ok_or_else(|| anyhow!("missing discovery substitution publication"))?;
        let results = publication.results.clone();
        let counts = publication.counts.clone();
        let mut bindings = extra.to_vec();
        bindings.extend([("sb_results", &results), ("sb_counts", &counts)]);
        self.config_cursor = 0;
        let guard = store.store.lock().unwrap();
        let mut encoder = self.encoder();
        self.record(
            &mut encoder,
            &guard,
            RESOLVE,
            config,
            &bindings,
            sub.publication.requests,
            report,
        )?;
        { let commands = self.finish(encoder); self.queue.submit(Some(commands)); }
        drop(guard);
        self.read_status_counts(store, also_read.as_slice(), report)
            .map(|words| Some((words, false)))
    }
    fn rank_instances(
        &mut self,
        store: &ProgramRetention,
        status: &[u32],
        uses: u32,
        extra: &[(&str, &wgpu::Buffer)],
        mut config: [u32; 16],
        report: &mut DiscoveryReport,
    ) -> Result<()> {
        let terms = status[STATUS_WORDS + super::A_TERMS];
        self.config_cursor = 0;
        let guard = store.store.lock().unwrap();
        let mut encoder = self.encoder();
        config[13] = status[0].max(1).next_power_of_two();
        self.record(&mut encoder, &guard, VALIDATE_TERMS, config, extra, terms, report)?;
        self.record(&mut encoder, &guard, RANK_INSTANCES, config, extra, config[13], report)?;
        let rows = uses.max(status[0]).max(status[2]);
        self.record(&mut encoder, &guard, PUBLISH_RANKS, config, extra, rows, report)?;
        let commands = self.finish(encoder);
        self.queue.submit(Some(commands));
        Ok(())
    }

    fn grow(&mut self, s: &[u32]) -> Result<bool> {
        if s[3] == 0 {
            return Ok(false);
        }
        let grow = |old: u32, demand: u32| -> Result<u32> {
            old.max(demand)
                .checked_mul(2)
                .ok_or_else(|| anyhow!("discovery capacity exhausted"))
        };
        if s[3] & 1 != 0 {
            self.capacity.instances = grow(self.capacity.instances, s[4])?;
        }
        if s[3] & 2 != 0 {
            self.capacity.edges = grow(self.capacity.edges, s[5])?;
        }
        if s[3] & 4 != 0 {
            self.capacity.requests = grow(self.capacity.requests, s[7])?;
        }
        Ok(true)
    }
    fn allocate(&mut self, uses: u32) -> Result<()> {
        let c = self.capacity;
        let i = c.instances as u64;
        let e = c.edges as u64;
        let r = c.requests as u64;
        for (name, bytes) in [
            ("dg_status", STATUS_WORDS as u64 * 4),
            ("dg_proof_identity", 32),
            ("dg_no_proofs", 48 * 4),
            ("dg_instances", i * 32),
            ("dg_slots", i * 16),
            ("dg_edges", e * 16),
            ("dg_targets",e*8),
            ("dg_edge_owner", e * 8),
            ("dg_roots", uses.max(1) as u64 * 16),
            ("dg_errors", (uses as u64 + e) * 16),
            ("dg_req_meta", r * 16),
            ("dg_order", i * 4),
            ("dg_rank", i * 4),
            ("dg_receipt", ClosedTraitPublication::RECEIPT_WORDS as u64 * 4),
            ("dg_wave", u64::from(WAVE_CLOSED_RAN + 1) * 4),
        ] {
            self.ensure(name, bytes)?;
        }
        Ok(())
    }
    fn buffer(&self, name: &str, bytes: u64) -> Result<wgpu::Buffer> {
        let limits = self.device.limits();
        if bytes > limits.max_storage_buffer_binding_size as u64 || bytes > limits.max_buffer_size {
            bail!("discovery {name} requires {bytes} bytes beyond the device limit");
        }
        Ok(storage(&self.device, name, bytes.max(4), false))
    }
    /// Grows `name` to at least `bytes`, by powers of two: sizes that grow
    /// from build to build (the term count) then keep their buffer, and so
    /// their cached bind groups, across warm builds. The instance and edge
    /// tables keep their exact size, since the kernels read their capacity
    /// from the buffer length and it must match the projection inputs.
    fn ensure(&mut self, name: &'static str, bytes: u64) -> Result<()> {
        if self.scratch.get(name).is_none_or(|b| b.size() < bytes) {
            let limits = self.device.limits();
            let limit = u64::from(limits.max_storage_buffer_binding_size).min(limits.max_buffer_size);
            let rounded = bytes.max(4).next_power_of_two();
            let exact = matches!(name, "dg_instances" | "dg_edges") || rounded > limit;
            let b = self.buffer(name, if exact { bytes } else { rounded })?;
            self.scratch.insert(name, b);
        }
        Ok(())
    }
    fn encoder(&mut self) -> wgpu::CommandEncoder {
        // A recording that failed leaves its dispatches here; they belong
        // to no encoder.
        self.pending.clear();
        self.device.create_command_encoder(&Default::default())
    }
    /// Records the pending dispatches, in order, as one compute pass.
    fn flush(&mut self, encoder: &mut wgpu::CommandEncoder) {
        if self.pending.is_empty() {
            return;
        }
        let steps = self
            .pending
            .iter()
            .map(|(kernel, bind, groups)| {
                let launch = super::substitution::Launch::Groups((*groups).min(65535), groups.div_ceil(65535), 1);
                (&self.passes[*kernel], bind, launch)
            })
            .collect::<Vec<_>>();
        let label = match self.pending.as_slice() {
            [(kernel, ..)] => KERNELS[*kernel],
            _ => "retained_discovery",
        };
        super::substitution::record_timed(encoder, label, &steps);
        self.pending.clear();
    }
    /// `flush`, then the finished command buffer.
    fn finish(&mut self, mut encoder: wgpu::CommandEncoder) -> wgpu::CommandBuffer {
        self.flush(&mut encoder);
        encoder.finish()
    }
    fn record(
        &mut self,
        encoder: &mut wgpu::CommandEncoder,
        store: &Store,
        kernel: usize,
        config: [u32; 16],
        extra: &[(&str, &wgpu::Buffer)],
        lanes: u32,
        report: &mut DiscoveryReport,
    ) -> Result<()> {
        self.record_with_resources(encoder, store, kernel, config, extra, &[], lanes, report)
    }
    #[allow(clippy::too_many_arguments)]
    fn record_with_resources(
        &mut self,
        encoder: &mut wgpu::CommandEncoder,
        store: &Store,
        kernel: usize,
        config: [u32; 16],
        extra: &[(&str, &wgpu::Buffer)],
        resources: &[(&str, wgpu::BindingResource<'_>)],
        lanes: u32,
        report: &mut DiscoveryReport,
    ) -> Result<()> {
        let program = match kernel {
            RANK_INSTANCES => Some((RANK_INSTANCES_PROGRAM, super::DISCOVERY_RANK_SYNC_SLOT, RANK_SYNC_FAILED)),
            COLLECT => Some((COLLECT_PROGRAM, super::DISCOVERY_COLLECT_SYNC_SLOT, COLLECT_SYNC_FAILED)),
            RESOLVE => Some((RESOLVE_PROGRAM, super::DISCOVERY_RESOLVE_SYNC_SLOT, RESOLVE_SYNC_FAILED)),
            EXPAND_CLOSED_WAVE => Some((CLOSED_WAVE_PROGRAM, super::DISCOVERY_CLOSED_WAVE_SYNC_SLOT, CLOSED_WAVE_SYNC_FAILED + config[8] as usize - 1)),
            EXPAND_WAVE => Some((WAVE_PROGRAM, super::DISCOVERY_WAVE_SYNC_SLOT, super::substitution::words::SYNC_FAILED)),
            _ => None,
        };
        if program.is_some() {
            self.flush(encoder);
        }
        if self.config_cursor == self.configs.len() {
            self.configs.push(self.buffer("dg_config", 64)?);
        }
        let config_buffer = &self.configs[self.config_cursor];
        self.config_cursor += 1;
        self.queue
            .write_buffer_counted(config_buffer, 0, &words_bytes(&config));
        let pass = &self.passes[kernel];
        let names = reflected_names(pass);
        let mut entries = Vec::new();
        for name in &names {
            let n = name.as_str();
            if matches!(n, "program_launch" | "step_program_sync") {
                continue;
            }
            if let Some((_, binding)) = resources.iter().find(|(name, _)| *name == n) {
                entries.push((n, binding.clone()));
                continue;
            }
            if n == "dg_proofs" {
                let binding = self.admission.as_ref().map_or_else(
                    || self.scratch["dg_no_proofs"].as_entire_binding(),
                    |a| wgpu::BindingResource::Buffer(wgpu::BufferBinding {
                        buffer: &a.routes, offset: a.offset,
                        size: std::num::NonZeroU64::new(a.size),
                    }),
                );
                entries.push((n, binding));
                continue;
            }
            let buffer = if n == "dg_config" {
                Some(config_buffer)
            } else {
                None
            }
            .or_else(|| self.scratch.get(n))
            .or_else(|| extra.iter().find(|(key, _)| *key == n).map(|(_, b)| *b))
            .or_else(|| store.buffers.get(n))
            .ok_or_else(|| anyhow!("{} binds unknown {n}", pass.shader_id))?;
            entries.push((n, buffer.as_entire_binding()));
        }
        if let Some((key, slot, failure_word)) = program {
            let counts = step_program_group_counts();
            let groups = if kernel == RANK_INSTANCES {
                lanes.div_ceil(RANK_BLOCK_ROWS).min(counts[1])
            } else {
                counts[step_program_group_variant(u64::from(lanes))]
            };
            let (status, options) = if kernel == EXPAND_WAVE {
                let counts = extra.iter().find(|(name, _)| *name == "sb_counts")
                    .map(|(_, buffer)| *buffer)
                    .ok_or_else(|| anyhow!("{key} has no substitution status"))?;
                (counts, super::substitution::FIRST_BATCH_OPTIONS)
            } else if kernel == EXPAND_CLOSED_WAVE {
                (&self.scratch["dg_status"], super::substitution::FIRST_BATCH_OPTIONS)
            } else {
                (&self.scratch["dg_status"], 0)
            };
            let program = StepProgramOperation::new_reflected(
                &self.device, key, pass, &entries,
                &store.step_program_sync, slot, groups, options,
            )?;
            program.record(encoder)?;
            passes_core::flush_deferred_compute(encoder);
            encoder.copy_buffer_counted(
                &store.step_program_sync,
                StepProgramOperation::failed_offset(slot),
                status,
                (failure_word * 4) as u64,
                4,
            );
            if kernel == EXPAND_CLOSED_WAVE || (kernel == EXPAND_WAVE && config[4] == 0) {
                report.substitution_dispatches += 1;
            } else if kernel != EXPAND_WAVE {
                report.dispatches += 1;
            }
            return Ok(());
        }
        let bind = passes_core::bind_group::create_bind_group_from_bindings(
            &self.device,
            Some(&pass.shader_id),
            pass,
            0,
            &entries,
        )?;
        self.pending.push((kernel, bind, lanes.div_ceil(256).max(1)));
        report.dispatches += 1;
        Ok(())
    }
    fn read_status(&self, report: &mut DiscoveryReport) -> Result<Vec<u32>> {
        self.read(&self.scratch["dg_status"], STATUS_WORDS, report)
    }
    /// The status words followed by the store's `rt_counts` and `also`,
    /// in one readback.
    fn read_status_counts(
        &self,
        store: &ProgramRetention,
        also: &[(&wgpu::Buffer, usize)],
        report: &mut DiscoveryReport,
    ) -> Result<Vec<u32>> {
        let counts = store.store.lock().unwrap().buffers["rt_counts"].clone();
        let mut parts = vec![(&self.scratch["dg_status"], STATUS_WORDS), (&counts, counts::WORDS)];
        parts.extend_from_slice(also);
        self.read_many(&parts, report)
    }
    fn read(
        &self,
        buffer: &wgpu::Buffer,
        words: usize,
        report: &mut DiscoveryReport,
    ) -> Result<Vec<u32>> {
        self.read_many(&[(buffer, words)], report)
    }
    /// The leading `words` of each buffer, concatenated, in one readback.
    fn read_many(
        &self,
        parts: &[(&wgpu::Buffer, usize)],
        report: &mut DiscoveryReport,
    ) -> Result<Vec<u32>> {
        let bytes = parts.iter().map(|(_, words)| *words as u64 * 4).sum();
        report.readbacks += 1;
        let rb = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("discovery.status"),
            size: bytes,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        // Only copies: every recording submitted its dispatches before.
        let mut encoder = self.device.create_command_encoder(&Default::default());
        let mut at = 0;
        for (buffer, words) in parts {
            encoder.copy_buffer_counted(buffer, 0, &rb, at, *words as u64 * 4);
            at += *words as u64 * 4;
        }
        self.queue.submit(Some(encoder.finish()));
        let slice = rb.slice(..);
        map_readback_blocking(&self.device, &slice, crate::readback_label!("discovery.status"))?;
        let data: Vec<u32> = slice
            .get_mapped_range()
            .chunks_exact(4)
            .map(|w| u32::from_le_bytes(w.try_into().unwrap()))
            .collect();
        rb.unmap();
        let mut offset = 0;
        for &(buffer, words) in parts {
            if buffer == &self.scratch["dg_status"] {
                check_discovery_sync(&data[offset..offset + words])?;
            }
            offset += words;
        }
        Ok(data)
    }
}
/// Receipt word with the admitted proof node rows (retained_route_abi.slang
/// RP_H_PROOF_NODE_ROWS).
const RECEIPT_PROOF_NODE_ROWS: usize = 24;
/// A first method-route batch recorded into resolution's submit before the
/// host knows the request and proof node counts.
struct SpeculativeRoutes<'a> {
    routes: &'a super::method_routes::MethodRoutes,
    view: crate::compiler::RetainedTraitView<'a>,
    /// `dg_receipt`, already holding this wave's publication receipt.
    receipt: &'a wgpu::Buffer,
    nodes_bound: u32,
    metadata: wgpu::Buffer,
    instances: wgpu::Buffer,
}
/// How a closed chain came back (`chain_closed`).
enum ClosedChain {
    Clean(Chained),
    /// A capacity overflowed: the capacities grew, and the attempt runs
    /// again with chaining.
    Grown,
    /// Anything else not clean: the attempt runs again without chaining,
    /// which reports a failure or takes the slow path that needs the host.
    Fallback,
}
/// The outcome of a clean chain of waves.
struct Chained {
    /// Status words and store counters after the last wave.
    status: Vec<u32>,
    /// The last wave's frontier end: the next wave's first instance.
    lo: u32,
    /// Waves with a nonempty frontier.
    ran: u32,
    /// Instances with closed predicates before the next wave (dg_wave
    /// word 3).
    predicated: u32,
}
/// Accepts a deferred closed publication receipt, which follows the status
/// words and store counters in `words`. A publication that did not finish
/// rejects the wave, before any growth or discovery failure is reported.
enum Closed {
    Accepted,
    Rejected(DiscoveryError),
    /// The wave's deferred closed solve did not finish in its first submit.
    Unfinished,
}
fn closed_receipt_failure(
    closed: Option<&mut ClosedTraitPublication>,
    words: &[u32],
    first: u32,
) -> Result<Closed> {
    let Some(closed) = closed else { return Ok(Closed::Accepted) };
    let Some(status) = closed.accept_receipt(&words[STATUS_WORDS + counts::WORDS..])? else {
        return Ok(Closed::Unfinished);
    };
    Ok(if status != [1, 0, u32::MAX] {
        Closed::Rejected(DiscoveryError { code: 8, use_index: u32::MAX, instance: first, detail: status[2] })
    } else {
        Closed::Accepted
    })
}
fn check_discovery_sync(status: &[u32]) -> Result<()> {
    for wave in 0..CLOSED_CHAIN_WAVES as usize {
        if status.get(CLOSED_WAVE_SYNC_FAILED + wave).copied() == Some(1) {
            bail!("retention program {CLOSED_WAVE_PROGRAM} failed to synchronize in wave {wave}");
        }
    }
    for (word, key) in [
        (RANK_SYNC_FAILED, RANK_INSTANCES_PROGRAM),
        (COLLECT_SYNC_FAILED, COLLECT_PROGRAM),
        (RESOLVE_SYNC_FAILED, RESOLVE_PROGRAM),
    ] {
        if status.get(word).copied() == Some(1) {
            bail!("retention program {key} failed to synchronize");
        }
    }
    if status.get(METHOD_ROUTES_SYNC_FAILED).copied() == Some(1) {
        bail!("retained method routes failed to synchronize");
    }
    Ok(())
}

fn failure(s: &[u32]) -> Option<DiscoveryError> {
    if s[10] != 0 {
        Some(DiscoveryError {
            code: s[10],
            use_index: u32::MAX,
            instance: u32::MAX,
            detail: 0,
        })
    } else if s[FIRST_ERROR] != u32::MAX {
        Some(DiscoveryError {
            code: s[16],
            use_index: s[17],
            detail: s[18],
            instance: s[19],
        })
    } else {
        None
    }
}
