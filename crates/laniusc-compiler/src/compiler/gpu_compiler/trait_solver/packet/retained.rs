//! The one submission of a packet whose batch rows the GPU writes from the
//! program retention store (docs/compiler-retained-trait-catalog.md). The
//! host places each batch table by its count and uploads only the directory
//! header; it serializes no row and accepts no result.
use anyhow::{Result, anyhow, ensure};

use super::{ProgramPacket, Submission};
use crate::compiler::gpu_compiler::trait_solver::abi::*;

/// Batch tables a GPU-produced submission fills (11-16).
pub(in crate::compiler::gpu_compiler::trait_solver) const RETAINED_BATCH_FIRST: usize = 11;
pub(in crate::compiler::gpu_compiler::trait_solver) const RETAINED_BATCH_LAST: usize = 16;

impl ProgramPacket {
    /// Plans a fresh packet's first submission with `counts[t]` rows in each
    /// batch table `t` (11-16) and none elsewhere. The returned word offsets
    /// are where the GPU producer writes each table. A packet makes at most
    /// one such submission; it has no host rows to append later.
    pub(in crate::compiler::gpu_compiler::trait_solver) fn prepare_retained_submission(
        &mut self,
        counts: [u32; TABLE_COUNT],
    ) -> Result<(Submission, [u32; TABLE_COUNT])> {
        ensure!(self.catalog.is_retained(), "a retained submission needs a GPU-produced catalog");
        ensure!(
            self.next_serial == 1 && !self.poisoned && self.awaiting_result.is_none(),
            "a retained packet submits once"
        );
        for table in 0..TABLE_COUNT {
            ensure!(
                self.tables.count(table)? == 0
                    && ((RETAINED_BATCH_FIRST..=RETAINED_BATCH_LAST).contains(&table) || counts[table] == 0),
                "a retained submission has rows only in batch tables 11-16"
            );
        }
        let mut offsets = [0; TABLE_COUNT];
        for table in RETAINED_BATCH_FIRST..=RETAINED_BATCH_LAST {
            let count = counts[table];
            offsets[table] = self.arena.next_word;
            if count == 0 {
                continue;
            }
            let capacity = count
                .checked_next_power_of_two()
                .ok_or_else(|| anyhow!("retained batch table growth overflow"))?;
            self.arena.slices[table] = Slice { offset: self.arena.next_word, count, capacity };
            self.arena.next_word = add(
                self.arena.next_word,
                mul(capacity, WIDTHS[table], "retained batch capacity")?,
                "retained batch arena",
            )?;
        }
        let impls = self.catalog.slices[9].count;
        let index_rows = self.catalog.slices[1].count.max(impls);
        let output_counts = [
            1,
            impls,
            counts[13],
            counts[16],
            counts[15],
            counts[16],
            index_rows,
            buckets(index_rows)?,
            counts[14],
            buckets(counts[14])?,
            1,
            impls,
            buckets(index_rows)?,
        ];
        let (output_copies, mut initialize_outputs) = self.outputs.prepare(output_counts)?;
        // A first submission builds the whole assumption index.
        initialize_outputs.retain(|r| r.table != 8 && r.table != 9);
        initialize_outputs.push(OutputRange { table: 8, first_row: 0, row_count: counts[14] });
        initialize_outputs.push(OutputRange { table: 9, first_row: 0, row_count: output_counts[9] });
        let serial = 1;
        self.next_serial = 2;
        let mut header = vec![
            MAGIC,
            VERSION,
            self.catalog.epoch as u32,
            (self.catalog.epoch >> 32) as u32,
            serial,
            TABLE_COUNT as u32,
            DIRECTORY_WORD,
            OUTPUT_DIRECTORY_WORD,
        ];
        for table in 0..TABLE_COUNT {
            let c = self.catalog.slices[table];
            let b = self.arena.slices[table];
            header.extend([c.offset, c.count, b.offset, b.count, b.capacity, WIDTHS[table]]);
        }
        for table in 0..OUTPUT_COUNT {
            let catalog = matches!(table, 0 | 1 | 6 | 7 | 11 | 12);
            let s = if catalog { self.catalog.outputs[table] } else { self.outputs.slices[table] };
            header.extend([if catalog { 0 } else { 1 }, s.offset, s.count, s.capacity, OUTPUT_WIDTHS[table]]);
        }
        ensure!(header.len() == BATCH_FIXED_WORDS as usize, "wrong packet directory width");
        let submission = Submission {
            epoch: self.catalog.epoch,
            arena_id: self.arena_id,
            serial,
            call_span: Span::new(0, counts[15])?,
            context_span: Span::new(0, counts[13])?,
            obligation_span: Span::new(0, counts[16])?,
            assumption_index_span: Span::new(0, counts[14])?,
            plan: UploadPlan {
                copies: Vec::new(),
                writes: vec![ArenaWrite { first_word: 0, words: header }],
                output_copies,
                initialize_outputs,
                input_word_count: self.arena.next_word,
                output_word_count: self.outputs.next_word,
            },
        };
        self.submitted_counts = counts;
        self.awaiting_result = Some(serial);
        Ok((submission, offsets))
    }
}
