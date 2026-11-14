//! The layout of a catalog whose rows the GPU writes from the program
//! retention store (docs/compiler-retained-trait-catalog.md). The host
//! knows only row counts: it places each table and output region exactly as
//! `materialize` does for a serialized catalog, and serializes no row.
use std::{collections::BTreeMap, sync::Arc};

use anyhow::{Result, ensure};

use super::{Atoms, FrozenCatalog, FrozenNativeLayout, owned_id};
use crate::compiler::gpu_compiler::trait_solver::abi::*;

/// Catalog tables a GPU-produced catalog fills (0-10).
pub(in crate::compiler::gpu_compiler::trait_solver) const RETAINED_CATALOG_TABLES: usize = 11;

/// Placement of a GPU-produced catalog.
pub(in crate::compiler::gpu_compiler::trait_solver) struct RetainedCatalogLayout {
    pub catalog: Arc<FrozenCatalog>,
    /// Word offset of each catalog table (0-10) in the catalog arena.
    pub table_offsets: [u32; RETAINED_CATALOG_TABLES],
}

impl FrozenCatalog {
    /// A catalog of `counts[t]` rows in table `t` (0-10), without host rows.
    /// Tables follow the header in table order and output regions follow the
    /// tables, as in `materialize`; nothing here depends on row contents.
    pub(in crate::compiler::gpu_compiler::trait_solver) fn retained_layout(
        counts: [u32; RETAINED_CATALOG_TABLES],
    ) -> Result<RetainedCatalogLayout> {
        ensure!(counts[0] != 0, "a retained catalog needs at least one snapshot");
        let epoch = owned_id()?;
        let mut slices = [Slice::default(); TABLE_COUNT];
        let mut table_offsets = [0; RETAINED_CATALOG_TABLES];
        let mut next = 4u32;
        for table in 0..RETAINED_CATALOG_TABLES {
            table_offsets[table] = next;
            if counts[table] != 0 {
                slices[table] = Slice { offset: next, count: counts[table], capacity: counts[table] };
                next = add(next, mul(counts[table], WIDTHS[table], "retained catalog table")?, "retained catalog")?;
            }
        }
        let impls = counts[9];
        let index_rows = counts[1].max(impls);
        let mut outputs = [Slice::default(); OUTPUT_COUNT];
        for (table, count) in [
            (0, 1),
            (1, impls),
            (6, index_rows),
            (7, buckets(index_rows)?),
            (11, impls),
            (12, buckets(index_rows)?),
        ] {
            if count == 0 {
                continue;
            }
            outputs[table] = Slice { offset: next, count, capacity: count };
            next = add(next, mul(count, OUTPUT_WIDTHS[table], "retained catalog output")?, "retained catalog")?;
        }
        let catalog = Self {
            epoch,
            native_layout: FrozenNativeLayout::without_recipes(epoch, counts[1])?,
            snapshots: Vec::new(),
            snapshot_by_unit: BTreeMap::new(),
            tables: Tables::default(),
            atoms: Atoms::default(),
            owner_by_hir: BTreeMap::new(),
            callable_by_native: BTreeMap::new(),
            callable_by_owner: BTreeMap::new(),
            predicate_by_owned_row: BTreeMap::new(),
            implementation_by_owned_row: BTreeMap::new(),
            predicate_sources: Vec::new(),
            implementation_sources: Vec::new(),
            words: Arc::from([]),
            slices,
            outputs,
            retained_word_count: Some(next),
        };
        Ok(RetainedCatalogLayout { catalog: Arc::new(catalog), table_offsets })
    }
}
