//! Production substitution over retained program terms
//! (docs/compiler-retained-substitution.md).
//!
//! A request names a retained declaration, a closed ENV term that the
//! declaration owns and a term over its binder chain. The GPU validates the
//! request, expands a memoized task graph of unique `(environment, term)`
//! keys round by round, evaluates the tasks level by level (constant fits
//! included) and publishes one result per request, with a status and the
//! exact provenance of a failure. Results stay on the GPU.
//!
//! The host allocates buffers, clears the memo, records batches of rounds,
//! submits them and reads the status words (`sb_counts`). It never reads a
//! request, a term or a result to make a decision. A batch that leaves the
//! attempt unfinished is followed by a larger batch. An attempt that
//! overflows any capacity publishes only `CAPACITY` statuses and rolls back
//! the store terms it interned; the host grows the overflowed tables (the
//! substitution's own, or the store's) and runs the attempt again from the
//! same retained terms and requests.

use std::collections::BTreeMap;

use anyhow::{Result, anyhow, bail};

use super::{
    ProgramRetention,
    Store,
    counts,
    grown_capacity,
    reflected_names,
    storage,
    words_bytes,
};
use crate::gpu::passes_core::{
    self,
    PassData,
    make_pass_data_from_shader_key,
    map_readback_blocking,
};

/// Result statuses (sb_common.slang SB_*).
pub mod status {
    pub const OK: u32 = 0;
    pub const PENDING: u32 = 1;
    pub const NOT_READY: u32 = 2;
    pub const DECL: u32 = 3;
    pub const ENV: u32 = 4;
    pub const UNRESOLVED: u32 = 5;
    pub const PRIOR_FIT: u32 = 6;
    pub const FOREIGN: u32 = 7;
    pub const UNBOUND: u32 = 8;
    pub const SLOT_PENDING: u32 = 9;
    pub const FIT_FAILED: u32 = 10;
    pub const COUNT: u32 = 11;
    pub const UNSUPPORTED: u32 = 12;
    pub const DEPTH: u32 = 13;
    pub const CAPACITY: u32 = 14;
    pub const INVARIANT: u32 = 15;
}

/// Status words (sb_common.slang SB_C_*).
pub mod words {
    pub const PHASE: usize = 0;
    pub const OVERFLOW: usize = 1;
    pub const TASKS: usize = 2;
    pub const EDGES: usize = 3;
    pub const DEMAND_TASKS: usize = 4;
    pub const DEMAND_EDGES: usize = 5;
    pub const ROUNDS: usize = 10;
    pub const EVAL_ROUNDS: usize = 12;
    pub const MAX_LEVEL: usize = 13;
    pub const REQUESTS: usize = 14;
    pub const SPARE_TASKS: usize = 15;
    pub const EDGE_LANES: usize = 16;
    pub const EDGES_RESOLVED: usize = 17;
    pub const MAX_FRONTIER: usize = 18;
    pub const STATE: usize = 19;
    pub const RUN: usize = 20;
    pub const STORE_OVERFLOW: usize = 28;
    pub const STORE_DEMAND_TERMS: usize = 29;
    pub const STORE_DEMAND_ARGS: usize = 30;
    pub const REQUEST_CLAMPED: usize = 31;
    pub const STATUS: usize = 32;
    pub const EVAL_LANES: usize = 48;
    pub const MAX_ARITY: usize = 49;
    pub const STORE_NEW_TERMS: usize = 50;
    pub const LEVEL_COUNT: usize = 64;
    pub const ROUND_LOG: usize = 832;
    pub const COUNT: usize = 1024;

    pub const PHASE_FINAL: u32 = 6;
    pub const STATE_PUBLISHED: u32 = 2;
    pub const STATE_OVERFLOWED: u32 = 3;
    pub const OVERFLOW_TASKS: u32 = 1;
    pub const OVERFLOW_EDGES: u32 = 2;
    pub const OVERFLOW_MEMO: u32 = 4;
    pub const OVERFLOW_STORE: u32 = 8;
}

/// Words per published result: `(result, status, failed node, failed env,
/// failed child value, request tag, run, 0)`.
pub const RESULT_WORDS: usize = 8;
/// Words per request: `(DeclId, ENV TermId, term reference, tag)`.
pub const REQUEST_WORDS: usize = 4;

const KERNELS: &[&str] = &[
    "type_checker/retention/substitution/00_begin",
    "type_checker/retention/substitution/01_roots",
    "type_checker/retention/substitution/02_expand_plan",
    "type_checker/retention/substitution/03_expand",
    "type_checker/retention/substitution/04_scatter",
    "type_checker/retention/substitution/05_eval_plan",
    "type_checker/retention/substitution/06_eval",
    "type_checker/retention/substitution/07_publish",
    "type_checker/retention/substitution/08_finish",
    "type_checker/retention/substitution/09_rollback",
];
const K_BEGIN: usize = 0;
const K_ROOTS: usize = 1;
const K_EXPAND_PLAN: usize = 2;
const K_EXPAND: usize = 3;
const K_SCATTER: usize = 4;
const K_EVAL_PLAN: usize = 5;
const K_EVAL: usize = 6;
const K_PUBLISH: usize = 7;
const K_FINISH: usize = 8;
const K_ROLLBACK: usize = 9;

// Indirect slots (sb_common.slang SB_D_*).
const D_ROOTS: u64 = 0;
const D_EXPAND: u64 = 1;
const D_SCATTER: u64 = 2;
const D_EVAL: u64 = 3;
const D_PUBLISH: u64 = 4;
const D_ROLLBACK: u64 = 5;
const D_SLOTS: u64 = 6;

/// Test kernel: single-lane construction script (shaders/tests/retention_subst_fixture.slang).
#[doc(hidden)]
pub const FIXTURE_KERNEL: &str = "tests/retention_subst_fixture";
/// Test kernel: requests from retained uses (shaders/tests/retention_subst_uses.slang).
#[doc(hidden)]
pub const USES_KERNEL: &str = "tests/retention_subst_uses";

/// Rounds of the first batch; each further batch of one attempt doubles.
const FIRST_BATCH_ROUNDS: u32 = 8;

/// Capacities of the substitution's own tables.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SubstitutionCapacity {
    /// Task records (unique `(environment, term)` keys).
    pub tasks: u32,
    /// Edge words (one per child of a task).
    pub edges: u32,
    /// Memo slots (a power of two, kept at least twice `tasks`).
    pub memo_slots: u32,
}

impl Default for SubstitutionCapacity {
    fn default() -> Self {
        Self {
            tasks: 16384,
            edges: 32768,
            memo_slots: 32768,
        }
    }
}

impl SubstitutionCapacity {
    /// Deliberately tiny capacities: a test of the overflow/retry protocol.
    pub fn tiny() -> Self {
        Self {
            tasks: 2,
            edges: 2,
            memo_slots: 4,
        }
    }

    fn grown(&self, overflow: u32, counts: &[u32]) -> Self {
        let mut next = *self;
        if overflow & words::OVERFLOW_TASKS != 0 {
            next.tasks = grow_to(self.tasks, counts[words::DEMAND_TASKS]);
        }
        if overflow & words::OVERFLOW_EDGES != 0 {
            next.edges = grow_to(self.edges, counts[words::DEMAND_EDGES]);
        }
        if overflow & words::OVERFLOW_MEMO != 0 {
            next.memo_slots = next.memo_slots.saturating_mul(2);
        }
        next.memo_slots = next
            .memo_slots
            .max((next.tasks as u64 * 2).next_power_of_two() as u32);
        next
    }
}

fn grow_to(current: u32, demand: u32) -> u32 {
    (demand.max(current.saturating_add(1)) as u64 * 2).min(u32::MAX as u64 / 4) as u32
}

/// A GPU request buffer. Producers write `(DeclId, ENV, term, tag)` rows
/// into `sb_requests` and the row count into `sb_request_count[0]`; the
/// host never reads them.
pub struct SubstitutionRequests {
    requests: wgpu::Buffer,
    count: wgpu::Buffer,
    capacity: u32,
}

impl SubstitutionRequests {
    /// Buffers for up to `capacity` requests on the process-global GPU.
    pub fn new(capacity: u32) -> Self {
        let device = &crate::gpu::device::global().device;
        let capacity = capacity.max(1);
        Self {
            requests: storage(device, "sb_requests", capacity as u64 * 16, false),
            count: storage(device, "sb_request_count", 16, false),
            capacity,
        }
    }

    /// Request rows the buffers hold.
    pub fn capacity(&self) -> u32 {
        self.capacity
    }

    /// The buffers a GPU producer binds, by binding name.
    pub fn buffers(&self) -> [(&'static str, &wgpu::Buffer); 2] {
        [
            ("sb_requests", &self.requests),
            ("sb_request_count", &self.count),
        ]
    }
}

/// What one substitution run did. Every figure is a GPU status word.
#[derive(Clone, Debug)]
pub struct SubstitutionReport {
    /// Attempts (1 when nothing overflowed).
    pub attempts: u32,
    /// Submitted batches over all attempts.
    pub batches: u32,
    /// Compute dispatches recorded over all attempts.
    pub dispatches: u32,
    /// Times the substitution's own tables grew.
    pub growths: u32,
    /// Times the store grew for terms the substitution interned.
    pub store_growths: u32,
    /// Capacity of the committed attempt.
    pub capacity: SubstitutionCapacity,
    /// Status words of the committed attempt.
    pub counts: Vec<u32>,
}

impl SubstitutionReport {
    /// Live tasks: unique `(environment, term)` keys.
    pub fn tasks(&self) -> u32 {
        self.counts[words::TASKS] - self.counts[words::SPARE_TASKS]
    }
    /// Edges resolved by expansion lanes (one lane per edge).
    pub fn edges(&self) -> u32 {
        self.counts[words::EDGES_RESOLVED]
    }
    /// Expansion rounds with a nonempty frontier (dependency span, top-down).
    pub fn expansion_rounds(&self) -> u32 {
        self.counts[words::ROUNDS]
    }
    /// Nonempty levels evaluated (dependency span, bottom-up).
    pub fn eval_rounds(&self) -> u32 {
        self.counts[words::EVAL_ROUNDS]
    }
    /// Largest frontier, in tasks.
    pub fn max_frontier(&self) -> u32 {
        self.counts[words::MAX_FRONTIER]
    }
    /// Frontier tasks of each expansion round.
    pub fn frontier_log(&self) -> &[u32] {
        let rounds = (self.expansion_rounds() as usize).min(128);
        &self.counts[words::ROUND_LOG..words::ROUND_LOG + rounds]
    }
    /// Published results per status.
    pub fn status_counts(&self) -> &[u32] {
        &self.counts[words::STATUS..words::STATUS + 16]
    }
}

/// The production substitution engine. Its allocations and pipelines
/// persist across runs and builds; its memo, tasks and results are reset by
/// every run.
pub struct RetainedSubstitution {
    device: std::sync::Arc<wgpu::Device>,
    queue: std::sync::Arc<wgpu::Queue>,
    passes: Vec<PassData>,
    capacity: SubstitutionCapacity,
    scratch: BTreeMap<&'static str, wgpu::Buffer>,
    scratch_capacity: Option<SubstitutionCapacity>,
    results: Option<(u32, wgpu::Buffer, wgpu::Buffer)>,
    hash_mask: u32,
    runs: u32,
}

impl RetainedSubstitution {
    /// An engine on the process-global GPU with initial `capacity`.
    pub fn new(capacity: SubstitutionCapacity) -> Result<Self> {
        let gpu = crate::gpu::device::global();
        let device = gpu.device.clone();
        let passes = KERNELS
            .iter()
            .map(|&key| make_pass_data_from_shader_key(&device, key, "main", key))
            .collect::<Result<Vec<_>>>()?;
        Ok(Self {
            device,
            queue: gpu.queue.clone(),
            passes,
            capacity,
            scratch: BTreeMap::new(),
            scratch_capacity: None,
            results: None,
            hash_mask: u32::MAX,
            runs: 0,
        })
    }

    /// Forces every memo key onto one probe chain (mask 0), or restores the
    /// full hash (`u32::MAX`).
    pub fn set_hash_mask(&mut self, mask: u32) {
        self.hash_mask = mask;
    }

    /// Current capacity of the substitution's own tables.
    pub fn capacity(&self) -> SubstitutionCapacity {
        self.capacity
    }

    /// The GPU-resident publication a consumer binds: `sb_results`
    /// (`RESULT_WORDS` words per request) and `sb_counts`, whose `STATE`
    /// word is `STATE_PUBLISHED` only after a committed run and whose `RUN`
    /// word names that run.
    pub fn publication(&self) -> Option<[(&'static str, &wgpu::Buffer); 2]> {
        let (_, results, _) = self.results.as_ref()?;
        Some([
            ("sb_results", results),
            ("sb_counts", &self.scratch["sb_counts"]),
        ])
    }

    /// Substitutes every request in `requests` against `store`.
    pub fn run(
        &mut self,
        store: &ProgramRetention,
        requests: &SubstitutionRequests,
    ) -> Result<SubstitutionReport> {
        let mut guard = store.store.lock().unwrap();
        if self
            .results
            .as_ref()
            .is_none_or(|(n, _, _)| *n < requests.capacity)
        {
            let n = requests.capacity.next_power_of_two();
            self.results = Some((
                n,
                storage(
                    &self.device,
                    "sb_results",
                    n as u64 * RESULT_WORDS as u64 * 4,
                    false,
                ),
                storage(&self.device, "sb_req_root", n as u64 * 8, false),
            ));
        }
        let mut report = SubstitutionReport {
            attempts: 0,
            batches: 0,
            dispatches: 0,
            growths: 0,
            store_growths: 0,
            capacity: self.capacity,
            counts: Vec::new(),
        };
        loop {
            report.attempts += 1;
            self.ensure_scratch();
            self.runs += 1;
            let mut encoder = self.device.create_command_encoder(&Default::default());
            encoder.clear_buffer(&self.scratch["sb_memo"], 0, None);
            encoder.clear_buffer(&self.scratch["sb_counts"], 0, None);
            self.queue.write_buffer(
                &self.scratch["sb_config"],
                0,
                &words_bytes(&[self.hash_mask, self.runs, 0, 0]),
            );
            let binds = self.bind_all(&guard, requests)?;
            let mut rounds = FIRST_BATCH_ROUNDS;
            self.record_batch(&mut encoder, &binds, true, rounds, &mut report.dispatches);
            self.queue.submit(Some(encoder.finish()));
            report.batches += 1;
            let mut counts = self.read(&self.scratch["sb_counts"], words::COUNT)?;
            while counts[words::PHASE] != words::PHASE_FINAL {
                rounds = rounds.saturating_mul(2);
                let mut encoder = self.device.create_command_encoder(&Default::default());
                self.record_batch(&mut encoder, &binds, false, rounds, &mut report.dispatches);
                self.queue.submit(Some(encoder.finish()));
                report.batches += 1;
                counts = self.read(&self.scratch["sb_counts"], words::COUNT)?;
            }
            if counts[words::STATE] == words::STATE_PUBLISHED {
                report.capacity = self.capacity;
                report.counts = counts;
                return Ok(report);
            }
            if counts[words::STATE] != words::STATE_OVERFLOWED {
                bail!(
                    "retained substitution finished in state {}",
                    counts[words::STATE]
                );
            }
            let overflow = counts[words::OVERFLOW];
            let mut grew = false;
            if overflow & !words::OVERFLOW_STORE != 0 {
                let next = self.capacity.grown(overflow, &counts);
                grew |= next != self.capacity;
                self.capacity = next;
                report.growths += 1;
            }
            if overflow & words::OVERFLOW_STORE != 0 {
                grew |= self.grow_store(store, &mut guard, &counts)?;
                report.store_growths += 1;
            }
            if !grew {
                bail!(
                    "retained substitution overflowed ({overflow:#x}) without a capacity to grow"
                );
            }
        }
    }

    fn grow_store(
        &self,
        retention: &ProgramRetention,
        store: &mut Store,
        sb: &[u32],
    ) -> Result<bool> {
        let mut status = vec![0u32; counts::WORDS];
        status[counts::OVERFLOW] = sb[words::STORE_OVERFLOW];
        status[counts::DEMAND + super::A_TERMS] = sb[words::STORE_DEMAND_TERMS];
        status[counts::DEMAND + super::A_TERM_ARGS] = sb[words::STORE_DEMAND_ARGS];
        let next = grown_capacity(&store.capacity, &status);
        if next == store.capacity {
            return Ok(false);
        }
        retention.grow(store, next)?;
        Ok(true)
    }

    fn ensure_scratch(&mut self) {
        if self.scratch_capacity == Some(self.capacity) {
            return;
        }
        let c = self.capacity;
        let tasks = c.tasks.max(1) as u64;
        let slots = c.memo_slots.max(2).next_power_of_two() as u64;
        self.capacity.memo_slots = slots as u32;
        self.scratch = [
            ("sb_counts", words::COUNT as u64 * 4, false),
            ("sb_config", 16, false),
            ("sb_dispatch", D_SLOTS * 3 * 4, true),
            ("sb_task_key", tasks * 16, false),
            ("sb_task_res", tasks * 16, false),
            ("sb_task_fail", tasks * 4, false),
            ("sb_order", tasks * 4, false),
            ("sb_edges", c.edges.max(1) as u64 * 8, false),
            ("sb_memo", slots * 4, false),
        ]
        .into_iter()
        .map(|(name, bytes, indirect)| (name, storage(&self.device, name, bytes, indirect)))
        .collect();
        self.scratch_capacity = Some(self.capacity);
    }

    fn bind_all(
        &self,
        store: &Store,
        requests: &SubstitutionRequests,
    ) -> Result<Vec<wgpu::BindGroup>> {
        let (_, results, roots) = self.results.as_ref().unwrap();
        let extra = [
            ("sb_requests", &requests.requests),
            ("sb_request_count", &requests.count),
            ("sb_results", results),
            ("sb_req_root", roots),
        ];
        self.passes
            .iter()
            .map(|pass| {
                let names = reflected_names(pass);
                let mut entries = Vec::with_capacity(names.len());
                for name in &names {
                    let buffer = self
                        .scratch
                        .get(name.as_str())
                        .or_else(|| extra.iter().find(|(n, _)| *n == name).map(|(_, b)| *b))
                        .or_else(|| store.buffers.get(name.as_str()))
                        .ok_or_else(|| anyhow!("{} binds unknown buffer {name}", pass.shader_id))?;
                    entries.push((name.as_str(), buffer.as_entire_binding()));
                }
                passes_core::bind_group::create_bind_group_from_bindings(
                    &self.device,
                    Some(&pass.shader_id),
                    pass,
                    0,
                    &entries,
                )
            })
            .collect()
    }

    /// One batch: `rounds` expansion rounds, the scatter, `rounds`
    /// evaluation rounds, then publication and the transaction's end. Each
    /// kernel checks the GPU phase, so the rounds an attempt does not need
    /// dispatch no workgroups.
    fn record_batch(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        binds: &[wgpu::BindGroup],
        first: bool,
        rounds: u32,
        dispatches: &mut u32,
    ) {
        let indirect = &self.scratch["sb_dispatch"];
        let mut pass = passes_core::begin_counted_compute_pass(
            encoder,
            &wgpu::ComputePassDescriptor {
                label: Some("retained_substitution"),
                timestamp_writes: None,
            },
        );
        let mut run = |kernel: usize, slot: Option<u64>| {
            pass.set_pipeline(&self.passes[kernel].pipeline);
            pass.set_bind_group(0, &binds[kernel], &[]);
            passes_core::record_compute_dispatch();
            *dispatches += 1;
            match slot {
                None => pass.dispatch_workgroups(1, 1, 1),
                Some(slot) => {
                    passes_core::record_indirect_compute_dispatch();
                    pass.dispatch_workgroups_indirect(indirect, 3 * slot * 4);
                }
            }
        };
        if first {
            run(K_BEGIN, None);
            run(K_ROOTS, Some(D_ROOTS));
        }
        for _ in 0..rounds {
            run(K_EXPAND_PLAN, None);
            run(K_EXPAND, Some(D_EXPAND));
        }
        run(K_SCATTER, Some(D_SCATTER));
        for _ in 0..rounds {
            run(K_EVAL_PLAN, None);
            run(K_EVAL, Some(D_EVAL));
        }
        run(K_PUBLISH, Some(D_PUBLISH));
        run(K_FINISH, None);
        run(K_ROLLBACK, Some(D_ROLLBACK));
    }

    fn read(&self, buffer: &wgpu::Buffer, words: usize) -> Result<Vec<u32>> {
        read_words(&self.device, &self.queue, buffer, words)
    }

    /// Test oracle: the published results of the first `requests` requests.
    #[doc(hidden)]
    pub fn read_results(&self, requests: usize) -> Result<Vec<[u32; RESULT_WORDS]>> {
        let (_, results, _) = self
            .results
            .as_ref()
            .ok_or_else(|| anyhow!("no substitution has run"))?;
        let words = self.read(results, requests * RESULT_WORDS)?;
        Ok(words
            .chunks_exact(RESULT_WORDS)
            .map(|c| c.try_into().unwrap())
            .collect())
    }

    /// Test oracle: the current status words.
    #[doc(hidden)]
    pub fn read_counts(&self) -> Result<Vec<u32>> {
        self.read(&self.scratch["sb_counts"], words::COUNT)
    }
}

fn read_words(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    buffer: &wgpu::Buffer,
    words: usize,
) -> Result<Vec<u32>> {
    let bytes = (words as u64 * 4).min(buffer.size());
    if bytes == 0 {
        return Ok(Vec::new());
    }
    let readback = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("retained_substitution.readback"),
        size: bytes,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let mut encoder = device.create_command_encoder(&Default::default());
    encoder.copy_buffer_to_buffer(buffer, 0, &readback, 0, bytes);
    queue.submit(Some(encoder.finish()));
    let slice = readback.slice(..);
    map_readback_blocking(device, &slice, "retained_substitution.readback")?;
    let out = slice
        .get_mapped_range()
        .chunks_exact(4)
        .map(|w| u32::from_le_bytes([w[0], w[1], w[2], w[3]]))
        .collect();
    readback.unmap();
    Ok(out)
}

/// Test hook: runs the single-entry GPU kernel `key` over `lanes` lanes,
/// bound to the store's buffers, the request buffers (whose count is
/// cleared first), `fx_config` (`config`) and `fx_out` (`out_words`
/// zeroed words, returned). Fixture and request-producer kernels are GPU
/// code; the host only transfers their configuration and output.
#[doc(hidden)]
pub fn run_test_kernel(
    store: &ProgramRetention,
    key: &str,
    requests: &SubstitutionRequests,
    config: &[u32],
    out_words: usize,
    lanes: u32,
) -> Result<Vec<u32>> {
    let device = &store.device;
    let queue = &store.queue;
    let pass = make_pass_data_from_shader_key(device, key, "main", key)?;
    let guard = store.store.lock().unwrap();
    let config_buffer = storage(device, "fx_config", (config.len().max(4) * 4) as u64, false);
    let mut words = config.to_vec();
    words.resize(config.len().max(4), 0);
    queue.write_buffer(&config_buffer, 0, &words_bytes(&words));
    let out = storage(device, "fx_out", (out_words.max(4) * 4) as u64, false);
    let mut encoder = device.create_command_encoder(&Default::default());
    encoder.clear_buffer(&out, 0, None);
    encoder.clear_buffer(&requests.count, 0, None);
    let names = reflected_names(&pass);
    let mut entries = Vec::new();
    for name in &names {
        let buffer = match name.as_str() {
            "fx_config" => &config_buffer,
            "fx_out" => &out,
            "sb_requests" => &requests.requests,
            "sb_request_count" => &requests.count,
            other => guard
                .buffers
                .get(other)
                .ok_or_else(|| anyhow!("{key} binds unknown buffer {other}"))?,
        };
        entries.push((name.as_str(), buffer.as_entire_binding()));
    }
    let bind = passes_core::bind_group::create_bind_group_from_bindings(
        device,
        Some(&pass.shader_id),
        &pass,
        0,
        &entries,
    )?;
    {
        let mut cpass = passes_core::begin_counted_compute_pass(
            &mut encoder,
            &wgpu::ComputePassDescriptor {
                label: Some("retained_substitution.test"),
                timestamp_writes: None,
            },
        );
        cpass.set_pipeline(&pass.pipeline);
        cpass.set_bind_group(0, &bind, &[]);
        passes_core::record_compute_dispatch();
        cpass.dispatch_workgroups(lanes.div_ceil(64).max(1), 1, 1);
    }
    queue.submit(Some(encoder.finish()));
    drop(guard);
    read_words(device, queue, &out, out_words)
}
