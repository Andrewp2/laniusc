//! Transport of bounded solver progress. These counters schedule GPU work and
//! allocate storage; no goal, type, implementation, or proof edge is read here.
use super::{
    super::{
        abi::*,
        proof_store::{
            PROOF_STORE_DIRECTORY, PROOF_STORE_FIXED_WORDS, PROOF_STORE_MAGIC,
            PROOF_STORE_PERSISTENT, PROOF_STORE_TABLES, PROOF_STORE_VERSION, PROOF_STORE_WIDTHS,
            ProofStoreLayout, ProofStoreSession,
        },
    },
    Submission,
};
use anyhow::{Result, anyhow, ensure};

pub(super) const BATCH_BUILDING: u32 = 0x8000_0001;
pub(super) const STORE_BUILDING: u32 = 0xffff_fffe;
pub(super) const STORE_CAPACITY_DETAIL: u32 = 69;
pub(super) const WORK: usize = 8;
pub(super) const QUEUE: usize = 15;

pub(super) struct ProofProgress {
    pub header: Vec<u32>,
    pub receipt: [u32; 8],
    pub reserved: [u32; PROOF_STORE_TABLES],
    pub admitted: [u32; PROOF_STORE_TABLES],
}
impl ProofProgress {
    pub fn from_owned_readback(
        layout: &ProofStoreLayout,
        submission: &Submission,
        header: Vec<u32>,
        receipt: [u32; 8],
    ) -> Result<Self> {
        ensure!(
            header.len() == PROOF_STORE_FIXED_WORDS as usize,
            "solver progress has an incomplete fixed directory"
        );
        ensure!(
            header[0] == PROOF_STORE_MAGIC
                && header[1] == PROOF_STORE_VERSION
                && header[2] == submission.epoch as u32
                && header[3] == (submission.epoch >> 32) as u32
                && header[4] == submission.arena_id as u32
                && header[5] == (submission.arena_id >> 32) as u32
                && header[6] == submission.serial
                && header[8] == PROOF_STORE_TABLES as u32
                && header[9] == PROOF_STORE_DIRECTORY
                && header[11] == 0,
            "solver progress belongs to another physical submission"
        );
        ensure!(
            receipt[6] == submission.serial && receipt[7] == 0,
            "solver progress has a stale or malformed batch receipt"
        );
        let mut reserved = [0; PROOF_STORE_TABLES];
        let mut admitted = [0; PROOF_STORE_TABLES];
        for table in 0..PROOF_STORE_TABLES {
            let base = PROOF_STORE_DIRECTORY as usize + table * 6;
            let row = &header[base..base + 6];
            let slice = layout.slices[table];
            ensure!(
                row[0] == slice.offset
                    && row[2] == slice.capacity
                    && row[5] == PROOF_STORE_WIDTHS[table],
                "solver progress changed its owned layout"
            );
            ensure!(
                row[1] != INVALID && row[4] <= row[3] && row[3] <= row[1] && row[1] <= row[2],
                "solver progress exceeds reserved physical storage"
            );
            ensure!(
                table < PROOF_STORE_PERSISTENT || row[4] == 0,
                "solver progress accepted a temporary table"
            );
            reserved[table] = row[1];
            admitted[table] = row[3];
        }
        Ok(Self {
            header,
            receipt,
            reserved,
            admitted,
        })
    }

    pub fn is_building(&self) -> bool {
        self.receipt[0] == BATCH_BUILDING && self.header[10] == STORE_BUILDING
    }

    /// Only this exact capacity diagnostic permits retry. Depth, visit, work,
    /// malformed graph, and missing evidence failures must remain terminal.
    pub fn capacity_retry(
        &self,
        session: &ProofStoreSession,
    ) -> Result<Option<[u32; PROOF_STORE_TABLES]>> {
        let layout = session.layout();
        if self.receipt[0] != 3 || self.receipt[1] != STORE_CAPACITY_DETAIL {
            return Ok(None);
        }
        let table = usize::try_from(self.receipt[2])?;
        ensure!(
            table < PROOF_STORE_TABLES && self.receipt[3] == INVALID,
            "solver capacity failure has no owned table"
        );
        let required = self.receipt[4];
        let current = layout.slices[table].capacity;
        // Reserved-ID/word overflow has no realizable larger allocation. Keep
        // the GPU ResourceLimit diagnostic terminal instead of retrying it.
        if required == INVALID {
            return Ok(None);
        }
        ensure!(
            self.receipt[5] == current && required > current && required != INVALID,
            "solver capacity request does not increase an owned table"
        );
        let mut capacities = std::array::from_fn(|index| layout.slices[index].capacity);
        capacities[table] = required
            .checked_next_power_of_two()
            .filter(|&n| n != INVALID)
            .unwrap_or(required);
        size_work_bounded(&mut capacities, session.accepted_prefix())?;
        Ok(Some(capacities))
    }

    pub fn pending(&self, table: usize) -> Result<Span> {
        let first = *self
            .admitted
            .get(table)
            .ok_or_else(|| anyhow!("solver table absent"))?;
        let reserved = self.reserved[table];
        ensure!(
            first <= reserved,
            "solver admitted prefix exceeds reservation"
        );
        Span::new(first, reserved - first)
    }

    pub fn appended(&self, table: usize, cursor: u32) -> Result<Span> {
        let count = *self
            .admitted
            .get(table)
            .ok_or_else(|| anyhow!("solver table absent"))?;
        ensure!(
            cursor <= count,
            "solver work cursor moved beyond admitted rows"
        );
        Span::new(cursor, count - cursor)
    }
}

// Bucket count follows possible Work rows, including every capacity retry.
// This is a storage load-factor bound, independent of semantic goal contents.
fn size_goal_buckets(capacities: &mut [u32; PROOF_STORE_TABLES]) -> Result<()> {
    capacities[11] = capacities[11].max(buckets(capacities[WORK])?);
    ensure!(
        capacities[11].is_power_of_two(),
        "solver goal bucket capacity is not a power of two"
    );
    Ok(())
}

// Tables whose rows each Work row of the solve emits at most once, so the Work
// capacity bounds them exactly and they never need a retry of their own:
// normalization reserves one goal per Work and the goal index one entry per
// Work; selection one substitution per selected Work; expansion one
// requirement per child Work; reduction one proof per ready Work and one proof
// edge per child of its Work; and a Work enqueues at most two events (ready or
// failed, then proven). Persistent tables add this solve's rows after their
// accepted ledger prefix. A larger Work capacity grows them with it.
fn size_work_bounded(
    capacities: &mut [u32; PROOF_STORE_TABLES],
    accepted: &[u32; PROOF_STORE_PERSISTENT],
) -> Result<()> {
    let work = capacities[WORK];
    for table in [3usize, 4, 6, 7] {
        capacities[table] = capacities[table].max(add(accepted[table], work, "work-bounded proof rows")?);
    }
    for table in [9usize, 10] {
        capacities[table] = capacities[table].max(work);
    }
    capacities[QUEUE] = capacities[QUEUE].max(mul(work, 2, "work-bounded reduction events")?);
    size_goal_buckets(capacities)
}

// Each source obligation creates one root Work, Goal, RootLink and normalization
// request before recursive expansion. Seed these linear tables directly rather
// than repeatedly restarting that known root inventory from a fixed small cap.
// Other structural expansion remains GPU requested; no depth-times-arity slab.
pub(super) fn initial_capacities(
    session: &ProofStoreSession,
    source_obligations: u32,
) -> Result<[u32; PROOF_STORE_TABLES]> {
    let layout = session.layout();
    let mut capacities = std::array::from_fn(|table| layout.slices[table].capacity.max(64));
    for table in [WORK, 10, 13, 14] {
        capacities[table] = capacities[table].max(source_obligations);
    }
    // Goal and subject-root rows append after accepted persistent history.
    // Use its exact ledger counts, not capacity as a proxy for existing rows.
    for table in [2usize, 3] {
        capacities[table] = capacities[table].max(add(
            session.accepted_prefix()[table],
            source_obligations,
            "persistent root proof storage",
        )?);
    }
    capacities[QUEUE] = capacities[QUEUE].max(mul(source_obligations, 2, "root proof queue")?);
    size_work_bounded(&mut capacities, session.accepted_prefix())?;
    Ok(capacities)
}
