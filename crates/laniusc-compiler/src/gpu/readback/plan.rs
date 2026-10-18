//! Read plans for host decoders whose reads depend on earlier reads.
//!
//! A decoder such as the unit-facts reader issues a chain of dependent word
//! reads: counts, then the rows those counts name, then the rows those rows
//! name, one round trip each. Run again on the same unit in a later job, it
//! usually issues the same reads. A [`ReadPlan`] records them by buffer
//! allocation identity and absolute byte range, so it never keeps a buffer
//! alive. Replaying it fetches every planned read with the first read the
//! run makes, and each later read that is in the plan is answered from that
//! fetch. A read outside the plan (the unit changed) is read from the GPU as
//! before, so a stale plan costs only its wasted transfer.
//!
//! A run whose reads follow the plan in order is matched read by read
//! against it, without building keys, and keeps the plan itself for the next
//! run. Its fetch is compiled the first time (gather records and copies, see
//! [`super::CompiledWords`]), so later runs record it again without planning
//! tens of thousands of gathered rows.
//!
//! An answer from the fetch equals a fresh read only while no GPU work writes
//! the planned buffers. That holds for a decoder that runs after its job's
//! GPU work, under the resident pipeline lock, and records no GPU work of its
//! own (the gather pass writes only its own output).

use std::{
    collections::HashMap,
    sync::{Arc, OnceLock},
};

use anyhow::Result;

use super::{CompiledWords, ReadbackRegion, ReadbackRows, ReadbackRowsColumn, WordRead};
use crate::gpu::buffers::TrackedBufferView;

/// Compiled fetches larger than this are planned again on each replay rather
/// than retained (a 1 MB narrow program's is about 0.8 MB).
const MAX_COMPILED_FETCH_BYTES: usize = 8 << 20;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
struct PlannedColumn {
    allocation: u64,
    base: u64,
    stride_words: usize,
    width_words: usize,
}

impl PlannedColumn {
    fn matches(&self, column: &ReadbackRowsColumn<'_>) -> bool {
        column.allocation == Some(self.allocation)
            && column.base == self.base
            && column.stride_words == self.stride_words
            && column.width_words == self.width_words
    }
}

/// One word read by allocation identity and absolute byte range.
#[derive(Clone, Debug, PartialEq, Eq)]
enum PlannedRead {
    Region {
        allocation: u64,
        offset: u64,
        bytes: usize,
    },
    Rows {
        indices: Arc<[u32]>,
        columns: Arc<[PlannedColumn]>,
    },
}

impl std::hash::Hash for PlannedRead {
    /// Hashes a row read by its columns, its row count and a few sampled
    /// rows, so a lookup does not hash every row of a read of thousands;
    /// equality still compares them all.
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        match self {
            Self::Region {
                allocation,
                offset,
                bytes,
            } => (0u8, allocation, offset, bytes).hash(state),
            Self::Rows { indices, columns } => {
                (1u8, columns, indices.len()).hash(state);
                let step = indices.len().div_ceil(8).max(1);
                for index in indices.iter().step_by(step) {
                    index.hash(state);
                }
                indices.last().hash(state);
            }
        }
    }
}

impl PlannedRead {
    /// The plan entry of `read`, if each of its buffers has an allocation
    /// identity.
    fn of(read: &WordRead<'_>) -> Option<Self> {
        Some(match read {
            WordRead::Region(region) => Self::Region {
                allocation: region.allocation?,
                offset: region.source_offset,
                bytes: region.byte_len,
            },
            WordRead::Rows(rows) => Self::Rows {
                indices: rows.indices.as_slice().into(),
                columns: rows
                    .columns
                    .iter()
                    .map(|column| {
                        Some(PlannedColumn {
                            allocation: column.allocation?,
                            base: column.base,
                            stride_words: column.stride_words,
                            width_words: column.width_words,
                        })
                    })
                    .collect::<Option<_>>()?,
            },
        })
    }

    /// Whether `read` is this read, compared without building its entry.
    fn matches(&self, read: &WordRead<'_>) -> bool {
        match (self, read) {
            (
                Self::Region {
                    allocation,
                    offset,
                    bytes,
                },
                WordRead::Region(region),
            ) => {
                region.allocation == Some(*allocation)
                    && region.source_offset == *offset
                    && region.byte_len == *bytes
            }
            (Self::Rows { indices, columns }, WordRead::Rows(rows)) => {
                columns.len() == rows.columns.len()
                    && columns
                        .iter()
                        .zip(&rows.columns)
                        .all(|(planned, column)| planned.matches(column))
                    && indices[..] == rows.indices[..]
            }
            _ => false,
        }
    }

    fn words(&self) -> usize {
        match self {
            Self::Region { bytes, .. } => bytes / 4,
            Self::Rows { indices, columns } => {
                indices.len() * columns.iter().map(|column| column.width_words).sum::<usize>()
            }
        }
    }

    /// The read again, if every buffer it names is still live.
    fn resolve<'a>(&self, buffers: &'a PlanBuffers) -> Option<WordRead<'a>> {
        Some(match self {
            Self::Region {
                allocation,
                offset,
                bytes,
            } => WordRead::Region(ReadbackRegion {
                source: buffers.get(*allocation)?,
                source_offset: *offset,
                byte_len: *bytes,
                allocation: Some(*allocation),
            }),
            Self::Rows { indices, columns } => WordRead::Rows(ReadbackRows {
                indices: indices.to_vec(),
                max_index: indices.iter().copied().max(),
                columns: columns
                    .iter()
                    .map(|column| {
                        Some(ReadbackRowsColumn {
                            source: buffers.get(column.allocation)?,
                            base: column.base,
                            stride_words: column.stride_words,
                            width_words: column.width_words,
                            allocation: Some(column.allocation),
                        })
                    })
                    .collect::<Option<_>>()?,
            }),
        })
    }
}

/// The word reads of one decoder run, in request order.
#[derive(Clone, Default)]
pub(crate) struct ReadPlan {
    inner: Arc<PlanReads>,
}

#[derive(Default)]
struct PlanReads {
    reads: Vec<PlannedRead>,
    /// Each read's first word in the plan's fetch, which holds the reads in
    /// order.
    starts: Vec<usize>,
    /// The fetch, compiled by the first replay that fetched every read.
    compiled: OnceLock<CompiledWords>,
}

impl ReadPlan {
    fn new(reads: Vec<PlannedRead>) -> Self {
        let mut word = 0;
        let starts = reads
            .iter()
            .map(|read| {
                let start = word;
                word += read.words();
                start
            })
            .collect();
        Self {
            inner: Arc::new(PlanReads {
                reads,
                starts,
                compiled: OnceLock::new(),
            }),
        }
    }

    pub(crate) fn len(&self) -> usize {
        self.inner.reads.len()
    }

    fn reads(&self) -> &[PlannedRead] {
        &self.inner.reads
    }
}

/// The live buffers a plan may name, by allocation identity. It holds the
/// buffers only for one decoder run.
#[derive(Default)]
pub(crate) struct PlanBuffers {
    by_allocation: HashMap<u64, wgpu::Buffer>,
}

impl PlanBuffers {
    pub(crate) fn new<'a>(views: impl IntoIterator<Item = TrackedBufferView<'a>>) -> Self {
        let mut buffers = Self::default();
        for view in views {
            if let Some(allocation) = view.allocation_id() {
                buffers
                    .by_allocation
                    .entry(allocation)
                    .or_insert_with(|| view.buffer.clone());
            }
        }
        buffers
    }

    pub(super) fn get(&self, allocation: u64) -> Option<&wgpu::Buffer> {
        self.by_allocation.get(&allocation)
    }
}

/// What one replay did, for host timing.
#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct ReplayStats {
    /// Reads answered from the plan's fetch.
    pub(crate) answered: usize,
    /// Reads that went to the GPU (the plan fetch rides on the first one).
    pub(crate) read: usize,
    /// Planned reads fetched, and their words.
    pub(crate) fetched: usize,
    pub(crate) fetched_words: usize,
    /// Whether the fetch was a compiled one, recorded without planning.
    pub(crate) compiled: bool,
}

/// The GPU reads a replay makes.
pub(super) trait PlanReader {
    /// Reads `reads` now.
    fn read_now(&self, reads: &[WordRead<'_>]) -> Result<Vec<u32>>;
    /// Reads `reads` now and compiles the readback, when it can be compiled.
    fn read_compiling(&self, reads: &[WordRead<'_>])
    -> Result<(Vec<u32>, Option<CompiledWords>)>;
    /// Reads a compiled readback again, or returns `None`, reading nothing.
    fn read_compiled(
        &self,
        compiled: &CompiledWords,
        buffers: &PlanBuffers,
    ) -> Result<Option<Vec<u32>>>;
}

/// The plan's fetched words.
struct Fetched {
    words: Vec<u32>,
    /// Each planned read's first word, when the fetch did not hold every
    /// planned read in plan order; otherwise the plan's own starts apply.
    starts: Option<Vec<Option<usize>>>,
}

impl Fetched {
    fn start(&self, plan: &ReadPlan, read: usize) -> Option<usize> {
        match &self.starts {
            Some(starts) => starts[read],
            None => Some(plan.inner.starts[read]),
        }
    }
}

/// One decoder run: its plan from an earlier run, the fetch of that plan,
/// and the reads this run makes, which become the next run's plan.
pub(super) struct PlanReplay {
    buffers: PlanBuffers,
    plan: Option<ReadPlan>,
    fetched: Option<Fetched>,
    /// The plan read this run is expected to make next.
    cursor: usize,
    /// This run's reads, once they no longer follow the plan in order;
    /// `None` while they do.
    recorded: Option<Vec<PlannedRead>>,
    /// The plan's reads by entry, for a read out of plan order.
    by_key: Option<HashMap<PlannedRead, usize>>,
    stats: ReplayStats,
}

impl PlanReplay {
    pub(super) fn new(buffers: PlanBuffers, plan: Option<ReadPlan>) -> Self {
        Self {
            buffers,
            recorded: plan.is_none().then(Vec::new),
            plan,
            fetched: None,
            cursor: 0,
            by_key: None,
            stats: ReplayStats::default(),
        }
    }

    /// The reads this run made, which are the plan again when they followed
    /// it to its end, and what the replay did.
    pub(super) fn finish(self) -> (ReadPlan, ReplayStats) {
        let plan = match (self.recorded, self.plan) {
            (Some(reads), _) => ReadPlan::new(reads),
            (None, Some(plan)) if self.cursor == plan.len() => plan,
            (None, Some(plan)) => ReadPlan::new(plan.reads()[..self.cursor].to_vec()),
            (None, None) => ReadPlan::default(),
        };
        (plan, self.stats)
    }

    /// Answers `reads` from the plan's fetch when it holds all of them;
    /// otherwise reads them with `reader`, which also fetches the plan the
    /// first time.
    pub(super) fn read(
        &mut self,
        reads: &[WordRead<'_>],
        reader: &impl PlanReader,
    ) -> Result<Vec<u32>> {
        if !reads.iter().all(plannable) {
            // A buffer without an allocation identity cannot be planned.
            self.stats.read += 1;
            return reader.read_now(reads);
        }
        if self.fetched.is_none()
            && let Some(plan) = self.plan.clone()
        {
            if self.follows(&plan, reads) {
                self.fetch(&plan, reader)?;
            } else {
                return self.fetch_with(&plan, reads, reader);
            }
        }
        if let Some(words) = self.answer(reads) {
            return Ok(words);
        }
        self.stats.read += 1;
        let words = reader.read_now(reads)?;
        self.record(reads);
        Ok(words)
    }

    /// Whether `reads` are the plan's next reads.
    fn follows(&self, plan: &ReadPlan, reads: &[WordRead<'_>]) -> bool {
        plan.reads().get(self.cursor..).is_some_and(|rest| {
            reads.len() <= rest.len()
                && reads.iter().zip(rest).all(|(read, planned)| planned.matches(read))
        })
    }

    /// Fetches every planned read in plan order: a compiled fetch again, or
    /// the reads resolved now, compiling the fetch for later runs.
    fn fetch(&mut self, plan: &ReadPlan, reader: &impl PlanReader) -> Result<()> {
        self.stats.read += 1;
        if let Some(compiled) = plan.inner.compiled.get()
            && let Some(words) = reader.read_compiled(compiled, &self.buffers)?
        {
            self.stats.compiled = true;
            self.fetched_all(plan, words);
            return Ok(());
        }
        let resolved = plan
            .reads()
            .iter()
            .map(|read| read.resolve(&self.buffers))
            .collect::<Vec<_>>();
        if resolved.iter().all(Option::is_some) {
            let (words, compiled) = {
                let reads = resolved.into_iter().flatten().collect::<Vec<_>>();
                reader.read_compiling(&reads)?
            };
            if let Some(compiled) = compiled
                && compiled.retained_bytes() <= MAX_COMPILED_FETCH_BYTES
            {
                let _ = plan.inner.compiled.set(compiled);
            }
            self.fetched_all(plan, words);
            return Ok(());
        }
        // Some planned buffer is gone: fetch the reads that remain.
        let mut starts = Vec::with_capacity(plan.len());
        let mut word = 0;
        let mut reads = Vec::with_capacity(plan.len());
        for read in resolved {
            starts.push(read.as_ref().map(|read| {
                let start = word;
                word += read.words();
                start
            }));
            reads.extend(read);
        }
        let words = reader.read_now(&reads)?;
        self.stats.fetched += reads.len();
        self.stats.fetched_words += words.len();
        self.fetched = Some(Fetched {
            words,
            starts: Some(starts),
        });
        Ok(())
    }

    fn fetched_all(&mut self, plan: &ReadPlan, words: Vec<u32>) {
        self.stats.fetched += plan.len();
        self.stats.fetched_words += words.len();
        self.fetched = Some(Fetched {
            words,
            starts: None,
        });
    }

    /// Reads `reads`, which do not follow the plan, together with every
    /// planned read whose buffers are live.
    fn fetch_with(
        &mut self,
        plan: &ReadPlan,
        reads: &[WordRead<'_>],
        reader: &impl PlanReader,
    ) -> Result<Vec<u32>> {
        self.stats.read += 1;
        let requested = reads.iter().map(WordRead::words).sum::<usize>();
        let (words, starts, fetched) = {
            let mut all = reads.to_vec();
            let mut starts = Vec::with_capacity(plan.len());
            let mut word = 0;
            for read in plan.reads() {
                let resolved = read.resolve(&self.buffers);
                starts.push(resolved.as_ref().map(|read| {
                    let start = word;
                    word += read.words();
                    start
                }));
                all.extend(resolved);
            }
            let fetched = all.len() - reads.len();
            (reader.read_now(&all)?, starts, fetched)
        };
        let mut words = words;
        let plan_words = words.split_off(requested);
        self.stats.fetched += fetched;
        self.stats.fetched_words += plan_words.len();
        self.fetched = Some(Fetched {
            words: plan_words,
            starts: Some(starts),
        });
        self.record(reads);
        Ok(words)
    }

    /// The plan entry `read` names, by key.
    fn lookup(&mut self, plan: &ReadPlan, read: &WordRead<'_>) -> Option<usize> {
        let by_key = self.by_key.get_or_insert_with(|| {
            let mut by_key = HashMap::with_capacity(plan.len());
            for (index, read) in plan.reads().iter().enumerate() {
                by_key.entry(read.clone()).or_insert(index);
            }
            by_key
        });
        by_key.get(&PlannedRead::of(read)?).copied()
    }

    /// The fetched words of `reads` when the fetch holds every one.
    fn answer(&mut self, reads: &[WordRead<'_>]) -> Option<Vec<u32>> {
        let plan = self.plan.clone()?;
        self.fetched.as_ref()?;
        let mut found = Vec::with_capacity(reads.len());
        let mut next = self.cursor;
        let mut in_order = true;
        for read in reads {
            let index = if plan.reads().get(next).is_some_and(|planned| planned.matches(read)) {
                next
            } else {
                in_order = false;
                self.lookup(&plan, read)?
            };
            let start = self.fetched.as_ref()?.start(&plan, index)?;
            found.push(start);
            next = index + 1;
        }
        let fetched = &self.fetched.as_ref()?.words;
        let mut words = Vec::with_capacity(reads.iter().map(WordRead::words).sum());
        for (read, &start) in reads.iter().zip(&found) {
            words.extend_from_slice(&fetched[start..start + read.words()]);
        }
        self.stats.answered += reads.len();
        if !in_order || self.recorded.is_some() {
            self.record(reads);
        }
        self.cursor = next;
        Some(words)
    }

    /// Records `reads` as this run's next reads: from here on the run no
    /// longer follows the plan, so its reads so far are the plan's first ones.
    fn record(&mut self, reads: &[WordRead<'_>]) {
        let recorded = self.recorded.get_or_insert_with(|| {
            self.plan
                .as_ref()
                .map(|plan| plan.reads()[..self.cursor.min(plan.len())].to_vec())
                .unwrap_or_default()
        });
        recorded.extend(reads.iter().filter_map(PlannedRead::of));
    }
}

fn plannable(read: &WordRead<'_>) -> bool {
    match read {
        WordRead::Region(region) => region.allocation.is_some(),
        WordRead::Rows(rows) => rows.columns.iter().all(|column| column.allocation.is_some()),
    }
}
