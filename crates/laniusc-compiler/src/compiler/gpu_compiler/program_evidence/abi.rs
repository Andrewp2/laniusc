use anyhow::{Result, anyhow, ensure};

pub(super) const INVALID: u32 = u32::MAX;
pub(super) const MAGIC: u32 = 0x5045_5631;
pub(super) const VERSION: u32 = 3;
pub(super) const TABLE_COUNT: usize = 18;
pub(super) const WIDTHS: [u32; TABLE_COUNT] =
    [4, 8, 9, 4, 4, 8, 2, 2, 8, 12, 6, 5, 4, 8, 6, 8, 4, 8];
pub(super) const OUTPUT_COUNT: usize = 13;
pub(super) const OUTPUT_WIDTHS: [u32; OUTPUT_COUNT] = [8, 8, 8, 8, 8, 8, 4, 1, 4, 1, 8, 4, 1];
pub(super) const DIRECTORY_WORD: u32 = 8;
pub(super) const OUTPUT_DIRECTORY_WORD: u32 = DIRECTORY_WORD + TABLE_COUNT as u32 * 6;
pub(super) const BATCH_FIXED_WORDS: u32 = OUTPUT_DIRECTORY_WORD + OUTPUT_COUNT as u32 * 5;
pub(super) const CATALOG_ONLY: [usize; 7] = [0, 2, 3, 4, 8, 9, 10];
pub(super) const BATCH_ONLY_START: usize = 11;
pub(super) const ROOT_VISITS: usize = 65_536;
pub(super) const ROOT_DEPTH: usize = 64;

pub(super) fn u32_len(value: usize, what: &str) -> Result<u32> {
    u32::try_from(value).map_err(|_| anyhow!("{what} exceeds u32 packet capacity"))
}

pub(super) fn add(a: u32, b: u32, what: &str) -> Result<u32> {
    a.checked_add(b)
        .ok_or_else(|| anyhow!("{what} index overflow"))
}

pub(super) fn mul(a: u32, b: u32, what: &str) -> Result<u32> {
    a.checked_mul(b)
        .ok_or_else(|| anyhow!("{what} size overflow"))
}

pub(super) fn buckets(rows: u32) -> Result<u32> {
    rows.checked_mul(2)
        .and_then(|n| n.max(1).checked_next_power_of_two())
        .ok_or_else(|| anyhow!("evidence bucket capacity overflow"))
}

#[derive(Clone, Copy, Debug, Default)]
pub(super) struct Span {
    pub first: u32,
    pub count: u32,
}

impl Span {
    pub fn new(first: u32, count: u32) -> Result<Self> {
        add(first, count, "span")?;
        Ok(if count == 0 {
            Self::default()
        } else {
            Self { first, count }
        })
    }
}

#[derive(Clone, Debug)]
pub(super) struct Tables {
    pub words: [Vec<u32>; TABLE_COUNT],
}

impl Default for Tables {
    fn default() -> Self {
        Self {
            words: std::array::from_fn(|_| Vec::new()),
        }
    }
}

impl Tables {
    pub fn count(&self, table: usize) -> Result<u32> {
        ensure!(table < TABLE_COUNT, "invalid evidence table");
        ensure!(
            self.words[table].len() % WIDTHS[table] as usize == 0,
            "partial table row"
        );
        u32_len(
            self.words[table].len() / WIDTHS[table] as usize,
            "table rows",
        )
    }
    pub fn push(&mut self, table: usize, row: &[u32]) -> Result<u32> {
        ensure!(
            table < TABLE_COUNT && row.len() == WIDTHS[table] as usize,
            "wrong evidence row width"
        );
        let index = self.count(table)?;
        ensure!(index < INVALID, "reserved evidence row index exhausted");
        self.words[table].try_reserve(row.len())?;
        self.words[table].extend_from_slice(row);
        Ok(index)
    }
    pub fn row(&self, table: usize, row: u32) -> Result<&[u32]> {
        let first = mul(row, WIDTHS[table], "row")? as usize;
        self.words[table]
            .get(first..first + WIDTHS[table] as usize)
            .ok_or_else(|| anyhow!("evidence row outside logical table"))
    }
    pub fn row_mut(&mut self, table: usize, row: u32) -> Result<&mut [u32]> {
        let first = mul(row, WIDTHS[table], "row")? as usize;
        self.words[table]
            .get_mut(first..first + WIDTHS[table] as usize)
            .ok_or_else(|| anyhow!("evidence row outside logical table"))
    }
}

#[derive(Clone, Copy, Debug, Default)]
pub(super) struct Slice {
    pub offset: u32,
    pub count: u32,
    pub capacity: u32,
}

#[derive(Clone, Copy, Debug)]
pub(in crate::compiler::gpu_compiler) struct ArenaCopy {
    pub from_word: u32,
    pub to_word: u32,
    pub word_count: u32,
}
#[derive(Clone, Debug)]
pub(in crate::compiler::gpu_compiler) struct ArenaWrite {
    pub first_word: u32,
    pub words: Vec<u32>,
}
#[derive(Clone, Copy, Debug)]
pub(in crate::compiler::gpu_compiler) struct OutputRange {
    pub table: u32,
    pub first_row: u32,
    pub row_count: u32,
}

/// The orchestrator applies copies before writes. It initializes new output
/// ranges before dispatch; bucket heads use INVALID, other state uses the ABI
/// initial status/INVALID fields. This plan never asks to upload old input rows.
#[derive(Clone, Debug)]
pub(in crate::compiler::gpu_compiler) struct UploadPlan {
    pub copies: Vec<ArenaCopy>,
    pub writes: Vec<ArenaWrite>,
    pub output_copies: Vec<ArenaCopy>,
    pub initialize_outputs: Vec<OutputRange>,
    pub input_word_count: u32,
    pub output_word_count: u32,
}

#[derive(Clone, Debug)]
pub(super) struct AppendArena {
    pub slices: [Slice; TABLE_COUNT],
    pub next_word: u32,
}
impl Default for AppendArena {
    fn default() -> Self {
        Self {
            slices: [Slice::default(); TABLE_COUNT],
            next_word: BATCH_FIXED_WORDS,
        }
    }
}
impl AppendArena {
    pub fn prepare(&mut self, tables: &Tables) -> Result<(Vec<ArenaCopy>, Vec<ArenaWrite>)> {
        let mut copies = Vec::new();
        let mut writes = Vec::new();
        for table in 0..TABLE_COUNT {
            let count = tables.count(table)?;
            let prior = self.slices[table];
            ensure!(count >= prior.count, "append-only evidence table shrank");
            let mut slice = prior;
            if count > prior.capacity {
                slice.capacity = count
                    .checked_next_power_of_two()
                    .ok_or_else(|| anyhow!("table growth overflow"))?;
                slice.offset = self.next_word;
                self.next_word = add(
                    self.next_word,
                    mul(slice.capacity, WIDTHS[table], "table capacity")?,
                    "input arena",
                )?;
                if prior.count != 0 {
                    copies.push(ArenaCopy {
                        from_word: prior.offset,
                        to_word: slice.offset,
                        word_count: mul(prior.count, WIDTHS[table], "table copy")?,
                    });
                }
            }
            if count != prior.count {
                let start = mul(prior.count, WIDTHS[table], "new table rows")?;
                writes.push(ArenaWrite {
                    first_word: add(slice.offset, start, "upload")?,
                    words: tables.words[table][start as usize..].to_vec(),
                });
            }
            slice.count = count;
            self.slices[table] = slice;
        }
        Ok((copies, writes))
    }
}

/// This is storage planning only; it does not grant GPU admission or proof.
#[derive(Clone, Debug, Default)]
pub(super) struct OutputArena {
    pub slices: [Slice; OUTPUT_COUNT],
    pub next_word: u32,
}
impl OutputArena {
    pub fn prepare(
        &mut self,
        counts: [u32; OUTPUT_COUNT],
    ) -> Result<(Vec<ArenaCopy>, Vec<OutputRange>)> {
        let mut copies = Vec::new();
        let mut initialize = Vec::new();
        for table in [2usize, 3, 4, 5, 8, 9, 10] {
            let count = counts[table];
            let prior = self.slices[table];
            ensure!(count >= prior.count, "output table shrank");
            let mut slice = prior;
            if count > prior.capacity {
                slice.capacity = count
                    .checked_next_power_of_two()
                    .ok_or_else(|| anyhow!("output growth overflow"))?;
                slice.offset = self.next_word;
                self.next_word = add(
                    self.next_word,
                    mul(slice.capacity, OUTPUT_WIDTHS[table], "output capacity")?,
                    "output arena",
                )?;
                if prior.count != 0 {
                    copies.push(ArenaCopy {
                        from_word: prior.offset,
                        to_word: slice.offset,
                        word_count: mul(prior.count, OUTPUT_WIDTHS[table], "output copy")?,
                    });
                }
            }
            if table == 10 {
                ensure!(count == 1, "each submission requires one batch receipt");
                // A previous receipt never admits this submission, including
                // an empty submission with no newly allocated output rows.
                initialize.push(OutputRange {
                    table: 10,
                    first_row: 0,
                    row_count: 1,
                });
            } else if count > prior.count {
                initialize.push(OutputRange {
                    table: table as u32,
                    first_row: prior.count,
                    row_count: count - prior.count,
                });
            }
            slice.count = count;
            self.slices[table] = slice;
        }
        Ok((copies, initialize))
    }
}
