//! Catalog-owned nominal definition recipes. This sidecar copies accepted
//! definition relations and graph roots; the GPU admits them and derives layout.
//! Its root and atom indexes are meaningful only beside the immutable catalog
//! with the exact recorded epoch. No host layout, substitution, or graph match
//! occurs here.

use std::sync::Arc;

use anyhow::{Result, anyhow, ensure};

use super::{
    abi::{INVALID, Span, TABLE_COUNT, add, mul, u32_len},
    catalog::{FrozenCatalog, GraphCopier, nominal_atom},
};
use crate::type_checker::{CheckedNominalIdentity, CheckedNominalRecipeKind};

pub(super) const NATIVE_LAYOUT_MAGIC: u32 = 0x504c_5231; // PLR1
pub(super) const NATIVE_LAYOUT_VERSION: u32 = 1;
pub(super) const NATIVE_LAYOUT_HEADER_WORDS: u32 = 24;
pub(super) const RECIPE_DIRECTORY_WORD: u32 = 8;
pub(super) const GROUP_DIRECTORY_WORD: u32 = 11;
pub(super) const STATUS_DIRECTORY_WORD: u32 = 14;
pub(super) const ATOM_RECIPE_DIRECTORY_WORD: u32 = 17;
pub(super) const RECIPE_WIDTH: u32 = 8;
pub(super) const GROUP_WIDTH: u32 = 3;
pub(super) const STATUS_WIDTH: u32 = 8;
pub(super) const ATOM_RECIPE_WIDTH: u32 = 1;

/// Word offsets address the single sidecar buffer. Empty regions have offset 0;
/// width is retained even for an empty region so the GPU validates the ABI.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct NativeLayoutDirectory {
    pub offset: u32,
    pub count: u32,
    pub width: u32,
}

impl NativeLayoutDirectory {
    fn allocate(cursor: &mut u32, count: u32, width: u32) -> Result<Self> {
        let offset = if count == 0 { 0 } else { *cursor };
        *cursor = add(
            *cursor,
            mul(count, width, "native recipe region")?,
            "native recipe arena",
        )?;
        Ok(Self {
            offset,
            count,
            width,
        })
    }

    fn write(self, words: &mut [u32], at: u32) {
        words[at as usize..at as usize + 3].copy_from_slice(&[self.offset, self.count, self.width]);
    }
}

/// Immutable CPU upload image, including fresh output state. Device-side
/// admission writes status and atom_map in the upload's output region;
/// it does not mutate this retained image or confer authority on another epoch.
#[derive(Clone, Debug)]
pub(super) struct FrozenNativeLayout {
    pub epoch: u64,
    pub words: Arc<[u32]>,
    pub input_end_words: u32,
    pub recipes: NativeLayoutDirectory,
    pub groups: NativeLayoutDirectory,
    pub status: NativeLayoutDirectory,
    pub atom_map: NativeLayoutDirectory,
}

impl FrozenNativeLayout {
    /// A valid empty image used only while FrozenCatalog is being assembled.
    /// The completed capture replaces it before the catalog can escape freeze.
    pub fn empty(epoch: u64) -> Result<Self> {
        Self::from_rows(epoch, 0, &[], &[])
    }

    pub fn capture(catalog: &mut FrozenCatalog) -> Result<Self> {
        let mut recipes = Vec::<[u32; RECIPE_WIDTH as usize]>::new();
        let mut groups = Vec::<[u32; GROUP_WIDTH as usize]>::new();
        for (snapshot_index, snapshot) in catalog.snapshots.iter().enumerate() {
            let snapshot_index = u32_len(snapshot_index, "recipe snapshot")?;
            let contracts = &snapshot.contracts;
            ensure!(
                contracts.source_unit == Some(snapshot.unit),
                "nominal recipe snapshot is unscoped or foreign"
            );
            for recipe in &contracts.nominal_recipes {
                ensure!(
                    recipe.identity.unit() == snapshot.unit,
                    "nominal recipe belongs to another snapshot"
                );
                ensure!(
                    recipe.source_hir != INVALID,
                    "nominal recipe has an invalid source HIR"
                );
                let owned = contracts
                    .binders
                    .get(recipe.owner as usize)
                    .ok_or_else(|| anyhow!("nominal recipe owner was not retained"))?;
                ensure!(
                    owned.source_hir == recipe.source_hir,
                    "nominal recipe owner does not name its definition"
                );
                let owner = *catalog
                    .owner_by_hir
                    .get(&(snapshot_index, recipe.source_hir))
                    .ok_or_else(|| anyhow!("nominal recipe owner is absent from the catalog"))?;
                let owner_header = catalog.tables.row(2, owner)?;
                ensure!(
                    owner_header[1] == snapshot_index && owner_header[2] == recipe.source_hir,
                    "nominal recipe owner maps to a different snapshot or definition"
                );

                let row = u32_len(recipes.len(), "nominal recipe rows")?;
                ensure!(row != INVALID, "nominal recipe identity capacity exhausted");
                let atom = nominal_atom(
                    &mut catalog.atoms,
                    &catalog.snapshot_by_unit,
                    recipe.identity,
                )?;
                let (kind, declaration_name_token) = (
                    match recipe.kind {
                        CheckedNominalRecipeKind::Record => 1,
                        CheckedNominalRecipeKind::Enum => 2,
                    },
                    match recipe.identity {
                        CheckedNominalIdentity::Public(_) => INVALID,
                        CheckedNominalIdentity::SourceLocal {
                            declaration_token, ..
                        } => {
                            ensure!(
                                declaration_token != INVALID,
                                "private nominal recipe has an invalid name anchor"
                            );
                            declaration_token
                        }
                    },
                );
                // The source name token and binder declaration-start token are
                // different coordinates. This accepted definition relation
                // links them; neither token is reconstructed from the other.
                let group_first = u32_len(groups.len(), "nominal recipe groups")?;
                let mut copier = GraphCopier::new(
                    &catalog.snapshot_by_unit,
                    &mut catalog.atoms,
                    &mut catalog.tables,
                    [0; TABLE_COUNT],
                );
                for payloads in &recipe.groups {
                    let mut first = 0;
                    for (ordinal, payload) in payloads.iter().enumerate() {
                        let root = copier.root(payload)?;
                        if ordinal == 0 {
                            first = root;
                        } else {
                            ensure!(
                                root == add(
                                    first,
                                    u32_len(ordinal, "recipe payload ordinal")?,
                                    "recipe roots"
                                )?,
                                "nominal recipe payload roots are not contiguous"
                            );
                        }
                    }
                    let roots = Span::new(first, u32_len(payloads.len(), "recipe payload roots")?)?;
                    groups.try_reserve(1)?;
                    groups.push([row, roots.first, roots.count]);
                }
                let span = Span::new(group_first, u32_len(recipe.groups.len(), "recipe groups")?)?;
                recipes.try_reserve(1)?;
                recipes.push([
                    atom,
                    owner,
                    kind,
                    span.first,
                    span.count,
                    recipe.source_hir,
                    declaration_name_token,
                    0,
                ]);
            }
        }
        Self::from_rows(
            catalog.epoch,
            u32_len(catalog.atoms.keys.len(), "recipe map atoms")?,
            &recipes,
            &groups,
        )
    }

    fn from_rows(
        epoch: u64,
        atom_count: u32,
        recipes: &[[u32; RECIPE_WIDTH as usize]],
        groups: &[[u32; GROUP_WIDTH as usize]],
    ) -> Result<Self> {
        ensure!(epoch != 0, "nominal recipes require a catalog epoch");
        let mut cursor = NATIVE_LAYOUT_HEADER_WORDS;
        let recipes_directory = NativeLayoutDirectory::allocate(
            &mut cursor,
            u32_len(recipes.len(), "nominal recipes")?,
            RECIPE_WIDTH,
        )?;
        let groups_directory = NativeLayoutDirectory::allocate(
            &mut cursor,
            u32_len(groups.len(), "nominal recipe groups")?,
            GROUP_WIDTH,
        )?;
        let input_end_words = cursor;
        let status = NativeLayoutDirectory::allocate(&mut cursor, 1, STATUS_WIDTH)?;
        let atom_map = NativeLayoutDirectory::allocate(&mut cursor, atom_count, ATOM_RECIPE_WIDTH)?;
        let mut words = Vec::new();
        words.try_reserve_exact(cursor as usize)?;
        words.resize(cursor as usize, 0);
        words[..8].copy_from_slice(&[
            NATIVE_LAYOUT_MAGIC,
            NATIVE_LAYOUT_VERSION,
            epoch as u32,
            (epoch >> 32) as u32,
            input_end_words,
            cursor,
            atom_count,
            0,
        ]);
        recipes_directory.write(&mut words, RECIPE_DIRECTORY_WORD);
        groups_directory.write(&mut words, GROUP_DIRECTORY_WORD);
        status.write(&mut words, STATUS_DIRECTORY_WORD);
        atom_map.write(&mut words, ATOM_RECIPE_DIRECTORY_WORD);
        for (index, row) in recipes.iter().enumerate() {
            let offset = add(
                recipes_directory.offset,
                mul(u32_len(index, "recipe row")?, RECIPE_WIDTH, "recipe row")?,
                "recipe row",
            )? as usize;
            words[offset..offset + RECIPE_WIDTH as usize].copy_from_slice(row);
        }
        for (index, row) in groups.iter().enumerate() {
            let offset = add(
                groups_directory.offset,
                mul(u32_len(index, "group row")?, GROUP_WIDTH, "group row")?,
                "group row",
            )? as usize;
            words[offset..offset + GROUP_WIDTH as usize].copy_from_slice(row);
        }
        if atom_count != 0 {
            let first = atom_map.offset as usize;
            words[first..cursor as usize].fill(INVALID);
        }
        Ok(Self {
            epoch,
            words: words.into(),
            input_end_words,
            recipes: recipes_directory,
            groups: groups_directory,
            status,
            atom_map,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn region(image: &FrozenNativeLayout, directory: NativeLayoutDirectory) -> &[u32] {
        let first = directory.offset as usize;
        let count = directory.count as usize * directory.width as usize;
        &image.words[first..first + count]
    }

    #[test]
    fn nominal_recipe_transport_preserves_owned_rows_and_resets_gpu_outputs() {
        let epoch = 0x1234_5678_90ab_cdef;
        // Public record, private enum (with an empty variant), empty enum.
        // The private name anchor 77 deliberately differs from source HIR 41.
        let recipes = [
            [3, 8, 1, 0, 1, 40, INVALID, 0],
            [7, 9, 2, 1, 2, 41, 77, 0],
            [9, 10, 2, 0, 0, 42, 88, 0],
        ];
        let groups = [[0, 12, 2], [1, 0, 0], [1, 14, 1]];
        let image = FrozenNativeLayout::from_rows(epoch, 11, &recipes, &groups).unwrap();
        assert_eq!(image.epoch, epoch);
        assert_eq!(
            &image.words[..8],
            &[
                NATIVE_LAYOUT_MAGIC,
                1,
                epoch as u32,
                (epoch >> 32) as u32,
                57,
                76,
                11,
                0,
            ]
        );
        assert_eq!(region(&image, image.recipes), recipes.as_flattened());
        assert_eq!(region(&image, image.groups), groups.as_flattened());
        assert_eq!(image.input_end_words, image.status.offset);
        assert_eq!(region(&image, image.status), &[0; STATUS_WIDTH as usize]);
        assert_eq!(region(&image, image.atom_map), &[INVALID; 11]);
        assert_eq!(&image.words[20..24], &[0; 4]);
        for (at, directory) in [
            (RECIPE_DIRECTORY_WORD, image.recipes),
            (GROUP_DIRECTORY_WORD, image.groups),
            (STATUS_DIRECTORY_WORD, image.status),
            (ATOM_RECIPE_DIRECTORY_WORD, image.atom_map),
        ] {
            assert_eq!(
                &image.words[at as usize..at as usize + 3],
                &[directory.offset, directory.count, directory.width]
            );
        }
        let retained = image.clone();
        let other = FrozenNativeLayout::from_rows(epoch + 1, 0, &[], &[]).unwrap();
        assert!(Arc::ptr_eq(&retained.words, &image.words));
        assert_ne!(retained.epoch, other.epoch);
        assert_eq!(region(&retained, retained.groups), groups.as_flattened());
    }

    #[test]
    fn nominal_recipe_transport_normalizes_empty_regions_and_rejects_size_overflow() {
        let image = FrozenNativeLayout::empty(23).unwrap();
        assert_eq!(image.words.len(), 32);
        assert_eq!(image.input_end_words, 24);
        for directory in [image.recipes, image.groups, image.atom_map] {
            assert_eq!((directory.offset, directory.count), (0, 0));
            assert_ne!(directory.width, 0);
        }
        assert_eq!(
            (image.status.offset, image.status.count, image.status.width),
            (24, 1, 8)
        );
        assert!(
            FrozenNativeLayout::empty(0)
                .unwrap_err()
                .to_string()
                .contains("epoch")
        );
        // Both fail arithmetic before reserving an enormous allocation.
        assert!(
            FrozenNativeLayout::from_rows(1, INVALID, &[], &[])
                .unwrap_err()
                .to_string()
                .contains("overflow")
        );
        let mut cursor = 24;
        assert!(
            NativeLayoutDirectory::allocate(&mut cursor, 1 << 31, 3)
                .unwrap_err()
                .to_string()
                .contains("overflow")
        );
    }
}
