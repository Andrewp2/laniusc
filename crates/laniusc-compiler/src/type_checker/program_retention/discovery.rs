//! GPU discovery of closed instances from retained call uses.
//!
//! Direct calls and accepted implementation methods follow exact ENV edges.
//! Required trait members need concrete solver routes. Bounded direct calls
//! require a current retained trait publication, checked per use on the GPU. No unsupported call is omitted or sent to source replay.
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
use crate::compiler::RetainedTraitPublication;
use crate::gpu::{
    buffers::LaniusBuffer,
    passes_core::{self, PassData, make_pass_data_from_shader_key, map_readback_blocking},
};

const KERNELS: &[&str] = &[
    "type_checker/retention/discovery/00_requests",
    "type_checker/retention/discovery/01_resolve",
    "type_checker/retention/discovery/02_scan",
    "type_checker/retention/discovery/03_term_order",
    "type_checker/retention/discovery/04_instance_order",
    "type_checker/retention/discovery/05_publish",
    "type_checker/retention/discovery/06_bound_routes",
];
const STATUS_WORDS: usize = 32;
/// Keys one workgroup sorts in shared memory (dg_common.slang DG_SORT_BLOCK).
const SORT_BLOCK: u32 = 512;
const FIRST_ERROR: usize = 6;

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
    method_routes: super::method_routes::MethodRoutes,
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
            method_routes: super::method_routes::MethodRoutes::new_with_device(gpu)?,
        })
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
            self.queue.write_buffer(
                &guard.buffers["rt_counts"],
                (counts::READY * 4) as u64,
                &0u32.to_le_bytes(),
            );
            self.queue.submit(None);
        }
        result
    }
    fn run_inner(&mut self, store: &ProgramRetention, mut publication: Option<&mut RetainedTraitPublication>) -> Result<DiscoveryOutcome> {
        let initial = store.status()?;
        let uses = initial[8];
        let generation = store.generation();
        let mut report = DiscoveryReport::default();
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
            self.queue.write_buffer(&self.scratch["dg_proof_identity"], 0, &words_bytes(&identity));
            let inputs = ProjectionInputs::new_with_device(&self.device, self.capacity.instances, self.capacity.edges);
            let root_routes = self.buffer("dg_root_routes", uses.max(1) as u64 * 16)?;
            let root_readiness = self.buffer("dg_root_readiness", 16)?;
            let requests = SubstitutionRequests::new_with_device(&self.device, self.capacity.requests);
            let mut extra: Vec<(&str, &wgpu::Buffer)> = inputs.buffers().into_iter().collect();
            extra.extend([
                ("dg_root_routes", &root_routes),
                ("dg_root_readiness", &root_readiness),
            ]);
            extra.extend(requests.buffers());
            let mut config = [0u32; 16];
            config[4] = 1;
            config[6] = 1;
            config[7] = self.hash_mask;
            config[15] = generation;
            let mut encoder = self.encoder();
            for name in ["dg_slots", "dg_instances", "dg_roots", "dg_status"] {
                encoder.clear_buffer(&self.scratch[name], 0, None);
            }
            for (_, buffer) in inputs.buffers() {
                encoder.clear_buffer(buffer, 0, None);
            }
            encoder.clear_buffer(&root_routes, 0, None);
            encoder.clear_buffer(&root_readiness, 0, None);
            encoder.clear_buffer(requests.buffers()[1].1, 0, None);
            self.queue.submit(Some(encoder.finish()));
            self.queue.write_buffer(
                &self.scratch["dg_status"],
                (FIRST_ERROR * 4) as u64,
                &u32::MAX.to_le_bytes(),
            );
            self.config_cursor = 0;
            let guard = store.store.lock().unwrap();
            let mut encoder = self.encoder();
            self.record(&mut encoder, &guard, 0, config, &extra, uses, &mut report)?;
            self.record(&mut encoder, &guard, 5, config, &extra, 1, &mut report)?;
            self.queue.submit(Some(encoder.finish()));
            drop(guard);
            let mut status = self.read_status(&mut report)?;
            if self.grow(&status)? {
                continue 'attempt;
            }
            if let Some(error) = failure(&status) {
                return Ok(DiscoveryOutcome::Rejected(error));
            }
            let resolved = self.resolve(store, &requests, &extra, config, &mut report)?;
            let request_capacity = resolved.is_none();
            status = match resolved {
                Some(words) => words,
                None => self.read_status_counts(store, &mut report)?,
            };

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
            while lo < hi {
                // Concrete instances have closed goals, even when their
                // source call was proved parametrically. Reuse the admitted
                // catalog; the GPU writes and solves this wave's hard goals.
                // The GPU counts inserted instances with closed predicates
                // (status 11); a wave without any needs no solver work.
                let wave_predicated = status[11] - predicated;
                predicated = status[11];
                let closed = if let Some(source) = publication.as_deref_mut()
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
                    )?;
                    report.closed_trait_waves += 1;
                    if check.producer_failures != 0 {
                        return Ok(DiscoveryOutcome::Rejected(DiscoveryError {
                            code: 8, use_index: u32::MAX, instance: check.first_failure, detail: check.producer_failures,
                        }));
                    }
                    if let Some(proofs) = &proofs {
                        let receipt = proofs.status(source)?;
                        if receipt != [1, 0, u32::MAX] {
                            return Ok(DiscoveryOutcome::Rejected(DiscoveryError {
                                code: 8, use_index: u32::MAX, instance: lo, detail: receipt[2],
                            }));
                        }
                    }
                    proofs
                } else { None };
                // Each wave expands precisely the newly interned instances.
                // A prefix scan places uses; one lane then handles each use.
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
                self.record(
                    &mut encoder,
                    &guard,
                    2,
                    config,
                    &extra,
                    hi - lo,
                    &mut report,
                )?;
                let mut distance = 1;
                while distance < hi - lo {
                    config[0] = 1;
                    config[8] = distance;
                    self.record(
                        &mut encoder,
                        &guard,
                        2,
                        config,
                        &extra,
                        hi - lo,
                        &mut report,
                    )?;
                    config[9] ^= 1;
                    distance = distance
                        .checked_mul(2)
                        .ok_or_else(|| anyhow!("discovery scan exhausted"))?;
                }
                config[0] = 2;
                self.record(
                    &mut encoder,
                    &guard,
                    2,
                    config,
                    &extra,
                    hi - lo,
                    &mut report,
                )?;
                // The scan's last lane sizes the request pass; no host
                // readback separates them. After an edge overflow the pass
                // has no workgroups, and resolution skips itself after any
                // request failure or overflow (status 12). The host reports
                // both from the wave's status readback, as before.
                encoder.clear_buffer(requests.buffers()[1].1, 0, None);
                encoder.clear_buffer(&self.scratch["dg_status"], 28, Some(4));
                config[0] = 0;
                self.record_with(
                    &mut encoder,
                    &guard,
                    0,
                    config,
                    &extra,
                    Dispatch::Indirect(&self.scratch["dg_indirect"].clone()),
                    &mut report,
                )?;
                self.record(&mut encoder, &guard, 5, config, &extra, 1, &mut report)?;
                self.queue.submit(Some(encoder.finish()));
                drop(guard);
                // Resolution reads back the status (and store counters)
                // with the substitution's counts.
                status = match self.resolve(store, &requests, &extra, config, &mut report)? {
                    Some(words) => words,
                    None => {
                        status = self.read_status(&mut report)?;
                        if self.grow(&status)? {
                            continue 'attempt;
                        }
                        bail!("discovery request capacity exceeded without a growth request");
                    }
                };
                if self.grow(&status)? {
                    continue 'attempt;
                }
                if let Some(error) = failure(&status) {
                    return Ok(DiscoveryOutcome::Rejected(error));
                }
                if let (Some(source),Some(proofs))=(publication.as_deref(),closed.as_ref()) {
                    let sub=self.substitution.as_ref().ok_or_else(||anyhow!("discovery substitution is in use"))?.publication(store).ok_or_else(||anyhow!("missing method substitution"))?;
                    let state=self.method_routes.run(store,source,proofs,&sub,&self.scratch["dg_req_meta"],&self.scratch["dg_instances"])?;
                    report.method_route_waves+=1;
                    if state[0]!=2 {
                        return Ok(DiscoveryOutcome::Rejected(DiscoveryError{code:9,use_index:state[16],instance:state[17],detail:state[18] | (state[3]<<24)}));
                    }
                    config[5]=sub.id.run;
                    let requests=sub.id.requests;
                    let output=self.method_routes.output().clone();
                    let mut bound=extra.clone(); bound.push(("mr_out",&output));
                    let guard=store.store.lock().unwrap(); let mut encoder=self.encoder();
                    self.record(&mut encoder,&guard,6,config,&bound,requests,&mut report)?;
                    self.record(&mut encoder,&guard,5,config,&extra,1,&mut report)?;
                    self.queue.submit(Some(encoder.finish()));
                    drop(guard);
                    status = self.read_status_counts(store, &mut report)?;
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
            // Rank by full structure, height by height. Hashes never decide
            // equality or output order, even with forced table collisions.
            self.rank_terms(store, &extra, config, &mut report)?;
            self.config_cursor = 0;
            let guard = store.store.lock().unwrap();
            let mut encoder = self.encoder();
            config[13] = status[0].max(1).next_power_of_two();
            config[0] = 0;
            self.record(
                &mut encoder,
                &guard,
                4,
                config,
                &extra,
                config[13],
                &mut report,
            )?;
            self.sort(&mut encoder, &guard, 4, 1, 3, config, &extra, &mut report)?;
            config[0] = 2;
            self.record(
                &mut encoder,
                &guard,
                4,
                config,
                &extra,
                config[13],
                &mut report,
            )?;
            config[0] = 1;
            self.record(
                &mut encoder,
                &guard,
                5,
                config,
                &extra,
                uses.max(status[1]).max(status[2]),
                &mut report,
            )?;
            config[0] = 2;
            self.record(&mut encoder, &guard, 5, config, &extra, 1, &mut report)?;
            self.queue.submit(Some(encoder.finish()));
            drop(guard);
            status = self.read_status(&mut report)?;
            if let Some(error) = failure(&status) {
                return Ok(DiscoveryOutcome::Rejected(error));
            }
            drop(extra);
            let root_route_capacity = uses.max(1);
            return Ok(DiscoveryOutcome::Published(DiscoveryPublication {
                inputs,
                root_routes: LaniusBuffer::new(
                    (root_routes, root_route_capacity as u64 * 16),
                    root_route_capacity as usize * 4,
                ),
                root_readiness: LaniusBuffer::new((root_readiness, 16), 4),
                root_route_capacity,
                generation,
                report,
            }));
        }
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
        report: &mut DiscoveryReport,
    ) -> Result<Option<Vec<u32>>> {
        let mut engine = self
            .substitution
            .take()
            .ok_or_else(|| anyhow!("discovery substitution is in use"))?;
        let counts_buffer = store.store.lock().unwrap().buffers["rt_counts"].clone();
        let status_buffer = self.scratch["dg_status"].clone();
        let request_lanes = requests.capacity();
        config[0] = 0;
        let ran = {
            // 01_resolve does nothing unless this run's publication
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
                self.record(encoder, guard, 1, config, &bindings, request_lanes, report)?;
                self.record(encoder, guard, 5, config, extra, 1, report)
            };
            engine.run_then(
                store,
                requests,
                Some(&mut consumer),
                &[(&status_buffer, STATUS_WORDS), (&counts_buffer, counts::WORDS)],
            )
        };
        self.substitution = Some(engine);
        let (sub, words) = match ran? {
            (SubstitutionRun::Published(r), words) => (r, words),
            (SubstitutionRun::RequestCapacity { .. }, _) => return Ok(None),
        };
        report.substitution_dispatches += sub.dispatches;
        if let Some(words) = words {
            report.readbacks += 1;
            return Ok(Some(words));
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
            1,
            config,
            &bindings,
            sub.publication.requests,
            report,
        )?;
        self.record(&mut encoder, &guard, 5, config, extra, 1, report)?;
        self.queue.submit(Some(encoder.finish()));
        drop(guard);
        self.read_status_counts(store, report).map(Some)
    }
    fn rank_terms(
        &mut self,
        store: &ProgramRetention,
        extra: &[(&str, &wgpu::Buffer)],
        mut config: [u32; 16],
        report: &mut DiscoveryReport,
    ) -> Result<()> {
        let status = store.status()?;
        let terms = status[2];
        self.ensure("dg_term_rank", terms.max(1) as u64 * 4)?;
        self.ensure("dg_term_order", terms.max(1) as u64 * 8)?;
        self.config_cursor = 0;
        config[0] = 0;
        let guard = store.store.lock().unwrap();
        let mut encoder = self.encoder();
        encoder.clear_buffer(&self.scratch["dg_levels"], 0, None);
        encoder.clear_buffer(&self.scratch["dg_term_rank"], 0, None);
        self.record(&mut encoder, &guard, 3, config, extra, terms, report)?;
        self.queue.submit(Some(encoder.finish()));
        drop(guard);
        let levels = self.read(&self.scratch["dg_levels"], 128, report)?;
        let mut bases = [0u32; 128];
        let mut sizes = [0u32; 128];
        let mut end = 0u32;
        for height in 1..128 {
            bases[height] = end;
            if levels[height] != 0 {
                sizes[height] = levels[height]
                    .checked_next_power_of_two()
                    .ok_or_else(|| anyhow!("term sort capacity exhausted"))?;
            }
            end = end
                .checked_add(sizes[height])
                .ok_or_else(|| anyhow!("term sort capacity exhausted"))?;
        }
        self.ensure("dg_term_order", end.max(1) as u64 * 4)?;
        self.queue
            .write_buffer(&self.scratch["dg_levels"], 128 * 4, &words_bytes(&bases));
        // Padding has one sentinel key; a GPU fill avoids arena-sized host data.
        self.config_cursor = 0;
        let guard = store.store.lock().unwrap();
        let mut encoder = self.encoder();
        config[0] = 4;
        config[13] = end;
        self.record(&mut encoder, &guard, 3, config, extra, end, report)?;
        config[0] = 1;
        self.record(&mut encoder, &guard, 3, config, extra, terms, report)?;
        for height in 1..128 {
            if sizes[height] == 0 {
                continue;
            }
            config[12] = bases[height];
            config[13] = sizes[height];
            config[14] = height as u32;
            self.sort(&mut encoder, &guard, 3, 2, 5, config, extra, report)?;
            config[0] = 3;
            self.record(
                &mut encoder,
                &guard,
                3,
                config,
                extra,
                sizes[height],
                report,
            )?;
        }
        self.queue.submit(Some(encoder.finish()));
        drop(guard);
        let _ = self.read_status(report)?;
        Ok(())
    }
    /// Bitonic sort of `config[13]` (a power of two) keys. Steps with
    /// j < SORT_BLOCK / 2 run inside one workgroup in shared memory
    /// (`local_mode`), so a stage costs one dispatch per global step plus
    /// one: 10 dispatches for 4096 keys instead of 78.
    fn sort(
        &mut self,
        encoder: &mut wgpu::CommandEncoder,
        store: &Store,
        kernel: usize,
        mode: u32,
        local_mode: u32,
        mut config: [u32; 16],
        extra: &[(&str, &wgpu::Buffer)],
        report: &mut DiscoveryReport,
    ) -> Result<()> {
        let count = config[13];
        if count < 2 {
            return Ok(());
        }
        let local_lanes = (count / 2).max(1);
        config[0] = local_mode;
        config[10] = 0;
        self.record(encoder, store, kernel, config, extra, local_lanes, report)?;
        let mut k = SORT_BLOCK * 2;
        while k <= count {
            config[0] = mode;
            let mut j = k / 2;
            while j >= SORT_BLOCK {
                config[10] = k;
                config[11] = j;
                self.record(encoder, store, kernel, config, extra, count, report)?;
                j /= 2;
            }
            config[0] = local_mode;
            config[10] = k;
            self.record(encoder, store, kernel, config, extra, local_lanes, report)?;
            k *= 2;
        }
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
            ("dg_slots", i * 8),
            ("dg_scan_a", i * 4),
            ("dg_scan_b", i * 4),
            ("dg_edges", e * 16),
            ("dg_targets",e*8),
            ("dg_edge_owner", e * 8),
            ("dg_roots", uses.max(1) as u64 * 16),
            ("dg_errors", (uses as u64 + e) * 16),
            ("dg_req_meta", r * 16),
            ("dg_order", i * 4),
            ("dg_rank", i * 4),
            ("dg_term_order", 4),
            ("dg_term_rank", 4),
            ("dg_levels", 384 * 4),
        ] {
            self.ensure(name, bytes)?;
        }
        if !self.scratch.contains_key("dg_indirect") {
            self.scratch
                .insert("dg_indirect", storage(&self.device, "dg_indirect", 16, true));
            // Every kernel's reflection lists dg_indirect; only the scan
            // writes it. The others bind this one, so the indirect requests
            // dispatch does not bind its own argument buffer as storage.
            self.scratch
                .insert("dg_no_indirect", storage(&self.device, "dg_no_indirect", 16, false));
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
    fn ensure(&mut self, name: &'static str, bytes: u64) -> Result<()> {
        if self.scratch.get(name).is_none_or(|b| b.size() < bytes) {
            let b = self.buffer(name, bytes)?;
            self.scratch.insert(name, b);
        }
        Ok(())
    }
    fn encoder(&self) -> wgpu::CommandEncoder {
        self.device.create_command_encoder(&Default::default())
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
        self.record_with(encoder, store, kernel, config, extra, Dispatch::Lanes(lanes), report)
    }
    fn record_with(
        &mut self,
        encoder: &mut wgpu::CommandEncoder,
        store: &Store,
        kernel: usize,
        config: [u32; 16],
        extra: &[(&str, &wgpu::Buffer)],
        dispatch: Dispatch<'_>,
        report: &mut DiscoveryReport,
    ) -> Result<()> {
        if self.config_cursor == self.configs.len() {
            self.configs.push(self.buffer("dg_config", 64)?);
        }
        let config_buffer = &self.configs[self.config_cursor];
        self.config_cursor += 1;
        self.queue
            .write_buffer(config_buffer, 0, &words_bytes(&config));
        let pass = &self.passes[kernel];
        let names = reflected_names(pass);
        let mut entries = Vec::new();
        for name in &names {
            let n = name.as_str();
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
            } else if n == "dg_indirect" && kernel != 2 {
                self.scratch.get("dg_no_indirect")
            } else {
                None
            }
            .or_else(|| self.scratch.get(n))
            .or_else(|| extra.iter().find(|(key, _)| *key == n).map(|(_, b)| *b))
            .or_else(|| store.buffers.get(n))
            .ok_or_else(|| anyhow!("{} binds unknown {n}", pass.shader_id))?;
            entries.push((n, buffer.as_entire_binding()));
        }
        let bind = passes_core::bind_group::create_bind_group_from_bindings(
            &self.device,
            Some(&pass.shader_id),
            pass,
            0,
            &entries,
        )?;
        let mut compute = passes_core::begin_counted_compute_pass(
            encoder,
            &wgpu::ComputePassDescriptor {
                label: Some("retained_discovery"),
                timestamp_writes: None,
            },
        );
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, &bind, &[]);
        match dispatch {
            Dispatch::Lanes(lanes) => {
                let groups = lanes.div_ceil(256).max(1);
                compute.dispatch_workgroups(groups.min(65535), groups.div_ceil(65535), 1);
            }
            Dispatch::Indirect(buffer) => {
                passes_core::record_indirect_compute_dispatch();
                compute.dispatch_workgroups_indirect(buffer, 0);
            }
        }
        passes_core::record_compute_dispatch();
        report.dispatches += 1;
        Ok(())
    }
    fn read_status(&self, report: &mut DiscoveryReport) -> Result<Vec<u32>> {
        self.read(&self.scratch["dg_status"], STATUS_WORDS, report)
    }
    /// The status words followed by the store's `rt_counts`, in one readback.
    fn read_status_counts(
        &self,
        store: &ProgramRetention,
        report: &mut DiscoveryReport,
    ) -> Result<Vec<u32>> {
        let counts = store.store.lock().unwrap().buffers["rt_counts"].clone();
        self.read_many(
            &[
                (&self.scratch["dg_status"], STATUS_WORDS),
                (&counts, counts::WORDS),
            ],
            report,
        )
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
        let mut encoder = self.encoder();
        let mut at = 0;
        for (buffer, words) in parts {
            encoder.copy_buffer_to_buffer(buffer, 0, &rb, at, *words as u64 * 4);
            at += *words as u64 * 4;
        }
        self.queue.submit(Some(encoder.finish()));
        let slice = rb.slice(..);
        map_readback_blocking(&self.device, &slice, "discovery.status")?;
        let data = slice
            .get_mapped_range()
            .chunks_exact(4)
            .map(|w| u32::from_le_bytes(w.try_into().unwrap()))
            .collect();
        rb.unmap();
        Ok(data)
    }
}
/// How many workgroups a recorded pass runs.
enum Dispatch<'a> {
    /// One lane per item, 256 lanes per workgroup.
    Lanes(u32),
    /// Workgroup counts the GPU wrote at offset 0 of an indirect buffer.
    Indirect(&'a wgpu::Buffer),
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
