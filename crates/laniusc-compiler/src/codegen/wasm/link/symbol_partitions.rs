use super::{GpuWasmLinkInput, GpuWasmRelocationTargetKind};

const IDENTITY_BITS: usize = 96;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct GpuWasmSymbolPartition {
    pub definition_indices: Vec<usize>,
    pub relocation_indices: Vec<usize>,
    pub exact_identity_duplicate_probe: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct GpuWasmSymbolPartitionPlan {
    pub partitions: Vec<GpuWasmSymbolPartition>,
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

impl GpuWasmSymbolPartitionPlan {
    pub(super) fn new(input: &GpuWasmLinkInput, max_definitions: usize) -> Result<Self, String> {
        if max_definitions < 2 {
            return Err(format!(
                "Wasm symbol partition capacity {max_definitions} cannot diagnose duplicate definitions"
            ));
        }
        let mut partitions = Vec::new();
        let root = build_node(
            input,
            (0..input.symbols.len()).collect(),
            0,
            max_definitions,
            &mut partitions,
        );
        for (relocation_index, relocation) in input.relocations.iter().enumerate() {
            if relocation.target_kind != GpuWasmRelocationTargetKind::Symbol {
                continue;
            }
            let partition_index = route(&root, relocation.target_identity);
            partitions[partition_index]
                .relocation_indices
                .push(relocation_index);
        }
        Ok(Self { partitions })
    }
}

fn build_node(
    input: &GpuWasmLinkInput,
    mut definition_indices: Vec<usize>,
    depth: usize,
    max_definitions: usize,
    partitions: &mut Vec<GpuWasmSymbolPartition>,
) -> PartitionNode {
    if definition_indices.len() <= max_definitions || depth == IDENTITY_BITS {
        let exact_identity_duplicate_probe =
            depth == IDENTITY_BITS && definition_indices.len() > max_definitions;
        if exact_identity_duplicate_probe {
            // All 96 identity bits are equal. Two records are sufficient for
            // the GPU insertion/definition passes to diagnose the duplicate.
            definition_indices.truncate(2);
        }
        let partition_index = partitions.len();
        partitions.push(GpuWasmSymbolPartition {
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
        wasm::link::{GpuWasmLinkRelocationRecord, GpuWasmLinkSymbolRecord},
    };

    fn input(definitions: &[[u32; 3]], relocation_identities: &[[u32; 3]]) -> GpuWasmLinkInput {
        GpuWasmLinkInput {
            function_count: definitions.len(),
            type_bytes: GpuLinkByteSource::resident("test Wasm types", Vec::new()),
            body_bytes: GpuLinkByteSource::resident("test Wasm bodies", Vec::new()),
            relocations: relocation_identities
                .iter()
                .copied()
                .enumerate()
                .map(|(index, target_identity)| GpuWasmLinkRelocationRecord {
                    body_offset: index as u32 * 5,
                    target_kind: GpuWasmRelocationTargetKind::Symbol,
                    target_index: 0,
                    target_identity,
                    addend: 0,
                })
                .collect(),
            symbols: definitions
                .iter()
                .copied()
                .enumerate()
                .map(|(index, identity)| GpuWasmLinkSymbolRecord {
                    identity,
                    function_index: index as u32,
                    flags: 0,
                })
                .collect(),
            entry_function: 0,
        }
    }

    #[test]
    fn partitions_definitions_without_loss_and_routes_relocations_by_identity() {
        let input = input(
            &[[0, 0, 1], [0, 0, 2], [u32::MAX, 0, 3], [u32::MAX, 0, 4]],
            &[[0, 0, 2], [u32::MAX, 0, 4], [123, 456, 789]],
        );
        let plan = GpuWasmSymbolPartitionPlan::new(&input, 2).expect("partition plan");
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
        for (relocation_index, relocation) in input.relocations.iter().enumerate() {
            let partition = plan
                .partitions
                .iter()
                .find(|partition| partition.relocation_indices.contains(&relocation_index))
                .expect("routed relocation");
            assert!(
                partition.definition_indices.is_empty()
                    || partition
                        .definition_indices
                        .iter()
                        .all(|&definition_index| {
                            let definition = input.symbols[definition_index].identity;
                            let mut common_bits = 0;
                            while common_bits < IDENTITY_BITS
                                && identity_bit(definition, common_bits)
                                    == identity_bit(relocation.target_identity, common_bits)
                            {
                                common_bits += 1;
                            }
                            common_bits > 0
                        })
            );
        }
    }

    #[test]
    fn exact_identity_overflow_keeps_gpu_duplicate_probe() {
        let input = input(&[[7, 8, 9]; 6], &[[7, 8, 9]]);
        let plan = GpuWasmSymbolPartitionPlan::new(&input, 2).expect("partition plan");
        let duplicate = plan
            .partitions
            .iter()
            .find(|partition| partition.exact_identity_duplicate_probe)
            .expect("duplicate probe partition");
        assert_eq!(duplicate.definition_indices.len(), 2);
        assert_eq!(duplicate.relocation_indices, vec![0]);
    }
}
