//! Read plans for host decoders whose reads depend on earlier reads.
//!
//! A decoder such as the unit-facts reader issues a chain of dependent word
//! reads: counts, then the rows those counts name, then the rows those rows
//! name, one round trip each. Run again on the same unit in a later job, it
//! usually issues the same reads. A [`ReadPlan`] records them by buffer
//! allocation identity and absolute byte range, so it never keeps a buffer
//! alive. Replaying it fetches every planned read together with the first
//! dependent read, and each later read that is in the plan is answered from
//! that fetch. A read outside the plan (the unit changed) is read from the
//! GPU as before, so a stale plan costs only its wasted transfer.
//!
//! An answer from the fetch equals a fresh read only while no GPU work writes
//! the planned buffers. That holds for a decoder that runs after its job's
//! GPU work, under the resident pipeline lock, and records no GPU work of its
//! own (the gather pass writes only its own output).

use std::collections::{HashMap, HashSet};

use anyhow::Result;

use super::{ReadbackRegion, ReadbackRows, ReadbackRowsColumn, WordRead};
use crate::gpu::buffers::TrackedBufferView;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
struct PlannedColumn {
    allocation: u64,
    base: u64,
    stride_words: usize,
    width_words: usize,
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
        indices: Vec<u32>,
        columns: Vec<PlannedColumn>,
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
                indices: rows.indices.clone(),
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

    /// The read again, if every buffer it names is still live.
    fn resolve<'a>(&self, buffers: &'a PlanBuffers) -> Option<WordRead<'a>> {
        Some(match self {
            Self::Region {
                allocation,
                offset,
                bytes,
            } => WordRead::Region(ReadbackRegion {
                source: buffers.by_allocation.get(allocation)?,
                source_offset: *offset,
                byte_len: *bytes,
                allocation: Some(*allocation),
            }),
            Self::Rows { indices, columns } => WordRead::Rows(ReadbackRows {
                indices: indices.clone(),
                max_index: indices.iter().copied().max(),
                columns: columns
                    .iter()
                    .map(|column| {
                        Some(ReadbackRowsColumn {
                            source: buffers.by_allocation.get(&column.allocation)?,
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
#[derive(Clone, Debug, Default)]
pub(crate) struct ReadPlan {
    reads: Vec<PlannedRead>,
}

impl ReadPlan {
    pub(crate) fn len(&self) -> usize {
        self.reads.len()
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
}

/// One decoder run: its plan from an earlier run, the fetch of that plan,
/// and the reads this run makes, which become the next run's plan.
pub(super) struct PlanReplay {
    buffers: PlanBuffers,
    pending: Option<ReadPlan>,
    fetched: HashMap<PlannedRead, (usize, usize)>,
    words: Vec<u32>,
    recorded: Vec<PlannedRead>,
    stats: ReplayStats,
}

impl PlanReplay {
    pub(super) fn new(buffers: PlanBuffers, plan: Option<ReadPlan>) -> Self {
        Self {
            buffers,
            pending: plan,
            fetched: HashMap::new(),
            words: Vec::new(),
            recorded: Vec::new(),
            stats: ReplayStats::default(),
        }
    }

    pub(super) fn finish(self) -> (ReadPlan, ReplayStats) {
        (
            ReadPlan {
                reads: self.recorded,
            },
            self.stats,
        )
    }

    /// Answers `reads` from the plan's fetch when it holds all of them;
    /// otherwise reads them with `read_now`, which also fetches the pending
    /// plan the first time.
    pub(super) fn read(
        &mut self,
        reads: &[WordRead<'_>],
        read_now: impl FnOnce(&[WordRead<'_>]) -> Result<Vec<u32>>,
    ) -> Result<Vec<u32>> {
        let Some(keys) = reads
            .iter()
            .map(PlannedRead::of)
            .collect::<Option<Vec<_>>>()
        else {
            // A buffer without an allocation identity cannot be planned.
            self.stats.read += 1;
            return read_now(reads);
        };
        if keys.iter().all(|key| self.fetched.contains_key(key)) {
            let total = reads.iter().map(WordRead::words).sum::<usize>();
            let mut words = Vec::with_capacity(total);
            for key in &keys {
                let (start, len) = self.fetched[key];
                words.extend_from_slice(&self.words[start..start + len]);
            }
            self.stats.answered += reads.len();
            self.recorded.extend(keys);
            return Ok(words);
        }
        let Self {
            buffers,
            pending,
            fetched,
            words: fetched_words,
            recorded,
            stats,
        } = self;
        let mut planned = Vec::new();
        if let Some(plan) = pending.take() {
            let mut seen = keys.iter().collect::<HashSet<_>>();
            for read in &plan.reads {
                if seen.insert(read)
                    && let Some(resolved) = read.resolve(buffers)
                {
                    planned.push((read.clone(), resolved));
                }
            }
        }
        stats.read += 1;
        if planned.is_empty() {
            recorded.extend(keys);
            return read_now(reads);
        }
        let mut all = reads.to_vec();
        all.extend(planned.iter().map(|(_, read)| read.clone()));
        let mut words = read_now(&all)?;
        let requested = reads.iter().map(WordRead::words).sum::<usize>();
        let mut start = requested;
        for (key, read) in planned {
            let len = read.words();
            fetched.insert(key, (fetched_words.len(), len));
            fetched_words.extend_from_slice(&words[start..start + len]);
            start += len;
            stats.fetched += 1;
            stats.fetched_words += len;
        }
        words.truncate(requested);
        recorded.extend(keys);
        Ok(words)
    }
}
