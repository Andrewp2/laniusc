use super::{GpuX86LinkInput, GpuX86RelocationTargetKind};

const IDENTITY_BITS: usize = 96;
const SECTION_UNDEFINED: u32 = 0;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct GpuX86SymbolPartition {
    pub definition_indices: Vec<usize>,
    pub relocation_indices: Vec<usize>,
    pub exact_identity_duplicate_probe: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct GpuX86SymbolPartitionPlan {
    pub partitions: Vec<GpuX86SymbolPartition>,
}

#[derive(Debug)]
enum PartitionNode {
    Leaf(usize),
    Branch {
        depth: usize,
        zero: Box<Self>,
        one: Box<Self>,
    },
}

impl GpuX86SymbolPartitionPlan {
    pub(super) fn new(input: &GpuX86LinkInput, max_definitions: usize) -> Result<Self, String> {
        if max_definitions < 2 {
            return Err(format!(
                "x86 symbol partition capacity {max_definitions} cannot diagnose duplicate definitions"
            ));
        }
        let definition_indices = input
            .symbols
            .iter()
            .enumerate()
            .filter_map(|(index, symbol)| (symbol.section != SECTION_UNDEFINED).then_some(index))
            .collect();
        let mut partitions = Vec::new();
        let root = build_node(
            input,
            definition_indices,
            0,
            max_definitions,
            &mut partitions,
        );
        for (relocation_index, relocation) in input.relocations.iter().enumerate() {
            if relocation.target_kind != GpuX86RelocationTargetKind::Symbol as u32 {
                continue;
            }
            let symbol = input
                .symbols
                .get(relocation.target_index as usize)
                .ok_or_else(|| {
                    format!(
                        "x86 symbol relocation {relocation_index} target {} is invalid",
                        relocation.target_index
                    )
                })?;
            let partition_index = route(&root, symbol.identity);
            partitions[partition_index]
                .relocation_indices
                .push(relocation_index);
        }
        Ok(Self { partitions })
    }
}

fn build_node(
    input: &GpuX86LinkInput,
    mut definition_indices: Vec<usize>,
    depth: usize,
    max_definitions: usize,
    partitions: &mut Vec<GpuX86SymbolPartition>,
) -> PartitionNode {
    if definition_indices.len() <= max_definitions || depth == IDENTITY_BITS {
        let exact_identity_duplicate_probe =
            depth == IDENTITY_BITS && definition_indices.len() > max_definitions;
        if exact_identity_duplicate_probe {
            definition_indices.truncate(2);
        }
        let partition_index = partitions.len();
        partitions.push(GpuX86SymbolPartition {
            definition_indices,
            relocation_indices: Vec::new(),
            exact_identity_duplicate_probe,
        });
        return PartitionNode::Leaf(partition_index);
    }

    let mut zero = Vec::new();
    let mut one = Vec::new();
    for definition_index in definition_indices {
        let identity = input.symbols[definition_index].identity;
        if identity_bit(identity, depth) == 0 {
            zero.push(definition_index);
        } else {
            one.push(definition_index);
        }
    }
    PartitionNode::Branch {
        depth,
        zero: Box::new(build_node(
            input,
            zero,
            depth + 1,
            max_definitions,
            partitions,
        )),
        one: Box::new(build_node(
            input,
            one,
            depth + 1,
            max_definitions,
            partitions,
        )),
    }
}

fn route(node: &PartitionNode, identity: [u32; 3]) -> usize {
    match node {
        PartitionNode::Leaf(partition_index) => *partition_index,
        PartitionNode::Branch { depth, zero, one } => {
            if identity_bit(identity, *depth) == 0 {
                route(zero, identity)
            } else {
                route(one, identity)
            }
        }
    }
}

fn identity_bit(identity: [u32; 3], depth: usize) -> u32 {
    let word = depth / 32;
    let bit = 31 - depth % 32;
    (identity[word] >> bit) & 1
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::codegen::{
        GpuLinkByteSource,
        x86::link::{GpuX86LinkObjectRecord, GpuX86LinkRelocationRecord, GpuX86LinkSymbolRecord},
    };

    fn input(definitions: &[[u32; 3]], queries: &[[u32; 3]]) -> GpuX86LinkInput {
        let mut symbols = definitions
            .iter()
            .copied()
            .enumerate()
            .map(|(index, identity)| GpuX86LinkSymbolRecord {
                object_index: 0,
                identity,
                section: 1,
                offset: index as u32,
                size: 1,
                flags: 0,
            })
            .collect::<Vec<_>>();
        let query_start = symbols.len();
        symbols.extend(
            queries
                .iter()
                .copied()
                .map(|identity| GpuX86LinkSymbolRecord {
                    object_index: 0,
                    identity,
                    section: SECTION_UNDEFINED,
                    offset: 0,
                    size: 0,
                    flags: 0,
                }),
        );
        GpuX86LinkInput {
            objects: vec![GpuX86LinkObjectRecord {
                text_input_start: 0,
                text_len: definitions.len() as u32,
                rodata_input_start: 0,
                rodata_len: 0,
                relocation_start: 0,
                relocation_count: queries.len() as u32,
                symbol_start: 0,
                symbol_count: symbols.len() as u32,
                entry_offset: 0,
            }],
            text: GpuLinkByteSource::resident("test x86 text", vec![0; definitions.len()]),
            rodata: GpuLinkByteSource::resident("test x86 rodata", Vec::new()),
            relocations: queries
                .iter()
                .enumerate()
                .map(|(index, _)| GpuX86LinkRelocationRecord {
                    object_index: 0,
                    kind: 1,
                    site_section: 1,
                    site_offset: 0,
                    target_kind: GpuX86RelocationTargetKind::Symbol as u32,
                    target_index: (query_start + index) as u32,
                    target_offset: 0,
                    target_section: 0,
                    addend_lo: 0,
                    addend_hi: 0,
                })
                .collect(),
            symbols,
            entry_object_index: 0,
        }
    }

    #[test]
    fn partitions_definitions_without_loss_and_routes_queries() {
        let input = input(
            &[[0, 0, 1], [0, 0, 2], [u32::MAX, 0, 3], [u32::MAX, 0, 4]],
            &[[0, 0, 2], [u32::MAX, 0, 4], [123, 456, 789]],
        );
        let plan = GpuX86SymbolPartitionPlan::new(&input, 2).expect("partition symbols");
        let mut definitions = plan
            .partitions
            .iter()
            .flat_map(|partition| partition.definition_indices.iter().copied())
            .collect::<Vec<_>>();
        definitions.sort_unstable();
        assert_eq!(definitions, vec![0, 1, 2, 3]);
        assert!(
            plan.partitions
                .iter()
                .all(|partition| partition.definition_indices.len() <= 2)
        );
        let mut queries = plan
            .partitions
            .iter()
            .flat_map(|partition| partition.relocation_indices.iter().copied())
            .collect::<Vec<_>>();
        queries.sort_unstable();
        assert_eq!(queries, vec![0, 1, 2]);
    }

    #[test]
    fn exact_identity_overflow_retains_two_definitions_for_gpu_diagnosis() {
        let input = input(&[[7, 8, 9]; 6], &[[7, 8, 9]]);
        let plan = GpuX86SymbolPartitionPlan::new(&input, 2).expect("partition duplicates");
        let duplicate = plan
            .partitions
            .iter()
            .find(|partition| partition.exact_identity_duplicate_probe)
            .expect("duplicate probe partition");
        assert_eq!(duplicate.definition_indices.len(), 2);
        assert_eq!(duplicate.relocation_indices, vec![0]);
    }
}
