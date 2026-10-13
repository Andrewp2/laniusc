//! Explicit concrete arguments for replaying one checked generic body.
//!
//! The host validates the retained declaration/argument identity. The GPU
//! substitutes type uses in that declaration's generic scope before normal
//! type-instance collection and native lowering.

use anyhow::{Result, ensure};

use super::{CheckedGenericApplicationArgument, CheckedGenericArgument, CheckedGenericConstant, CheckedGenericType};

pub(super) const MAX_BODY_TYPE_ARGUMENTS: usize = 32;
pub(super) const MAX_BODY_TYPE_NODES: usize = 64;
pub(super) const BODY_TYPE_GRAPH_START: usize = MAX_BODY_TYPE_ARGUMENTS * 2 + 1;
pub(super) const BODY_TYPE_EDGE_START: usize = BODY_TYPE_GRAPH_START + MAX_BODY_TYPE_NODES * 2;
pub(super) const MAX_BODY_TYPE_EDGES: usize = MAX_BODY_TYPE_NODES * MAX_BODY_TYPE_ARGUMENTS;
pub(super) const BODY_CONSTANT_START: usize = BODY_TYPE_EDGE_START * 4 + MAX_BODY_TYPE_EDGES;
pub(super) const BODY_SPECIALIZATION_WORDS: usize =
    BODY_CONSTANT_START + 4 + MAX_BODY_TYPE_ARGUMENTS * 4;

#[derive(Clone, Debug)]
pub(crate) struct CheckedBodySpecialization {
    /// Public declaration index or the existing high-bit associated-method symbol.
    pub target_symbol: u32,
    /// Unit whose immutable declarations are available during this replay.
    pub source_unit: [u32; 2],
    pub arguments: Vec<CheckedGenericArgument>,
    pub constants: Vec<CheckedGenericConstant>,
}

impl CheckedBodySpecialization {
    /// Scheduling identity contains semantic types and values. Native widths
    /// and source-local replay indexes are separately validated layout facts.
    #[cfg(test)]
    pub(crate) fn scheduling_words(&self) -> Result<Vec<u32>> {
        Ok(self.scheduling_environment()?.0)
    }

    pub(crate) fn scheduling_environment(&self) -> Result<(Vec<u32>, Vec<u32>)> {
        let packet = self.packet()?; // Validate closure and bounded replay capacity first.
        let mut canonical = std::collections::BTreeMap::<Vec<u32>, u32>::new();
        let mut nodes = Vec::new();
        let mut rebased = Vec::new();
        let mut layouts = Vec::new();
        for index in 0..packet[2] as usize {
            let start = (BODY_TYPE_GRAPH_START + index * 2) * 4;
            let node = &packet[start..start + 8];
            let mut key = vec![node[0]];
            match node[0] {
                1 | 10 => key.push(node[1]),
                2 => key.extend([rebased[node[1] as usize], node[2]]),
                3 | 4 => key.push(rebased[node[1] as usize]),
                9 => {
                    key.extend_from_slice(&node[4..7]);
                    key.push(node[2]);
                    let edge = BODY_TYPE_EDGE_START * 4 + node[1] as usize;
                    key.extend(
                        packet[edge..edge + node[2] as usize]
                            .iter()
                            .map(|&child| rebased[child as usize]),
                    );
                }
                _ => unreachable!("packet validated complete types"),
            }
            if let Some(&existing) = canonical.get(&key) {
                ensure!(
                    layouts[existing as usize] == node[3],
                    "one checked type has inconsistent native layouts"
                );
                rebased.push(existing);
            } else {
                let new_index = nodes.len() as u32;
                canonical.insert(key.clone(), new_index);
                nodes.push(key);
                layouts.push(node[3]);
                rebased.push(new_index);
            }
        }
        let mut identity = vec![
            self.target_symbol,
            self.arguments.len() as u32,
            nodes.len() as u32,
        ];
        for slot in 0..self.arguments.len() {
            identity.push(rebased[packet[(slot * 2 + 1) * 4 + 2] as usize]);
        }
        for node in nodes {
            identity.push(node.len() as u32);
            identity.extend(node);
        }
        identity.push(self.constants.len() as u32);
        identity.extend(self.constants.iter().map(|argument| {
            argument
                .value
                .literal()
                .expect("packet validated literal constants")
        }));
        Ok((identity, layouts))
    }

    pub(crate) fn packet(&self) -> Result<[u32; BODY_SPECIALIZATION_WORDS]> {
        ensure!(
            self.target_symbol != u32::MAX,
            "body specialization target is invalid"
        );
        ensure!(
            (!self.arguments.is_empty() || !self.constants.is_empty())
                && self.arguments.len() <= MAX_BODY_TYPE_ARGUMENTS
                && self.constants.len() <= MAX_BODY_TYPE_ARGUMENTS,
            "body specialization requires a nonempty environment with at most {MAX_BODY_TYPE_ARGUMENTS} arguments in each parameter domain"
        );
        let mut words = [0; BODY_SPECIALIZATION_WORDS];
        let mut nodes = Vec::new();
        let mut edges = Vec::new();
        words[0] = self.arguments.len() as u32;
        words[1] = self.target_symbol;
        words[BODY_CONSTANT_START] = self.constants.len() as u32;
        for (slot, argument) in self.constants.iter().enumerate() {
            ensure!(
                argument.slot == slot as u32 && argument.value.literal().is_some(),
                "body specialization has an incomplete constant environment"
            );
            let row = BODY_CONSTANT_START + 4 + slot * 4;
            words[row] = argument.slot;
            words[row + 1] = argument
                .value
                .literal()
                .expect("validated literal constant");
        }
        for (slot, argument) in self.arguments.iter().enumerate() {
            ensure!(
                argument.slot == slot as u32,
                "body specialization has an incomplete slot sequence"
            );
            let row = (slot * 2 + 1) * 4;
            words[row] = argument.slot;
            let root = append_checked_node(&argument.ty, &mut nodes, &mut edges)?;
            words[row + 1] = 10; // private checked graph root
            words[row + 2] = root;
        }
        words[2] = nodes.len() as u32;
        words[3] = edges.len() as u32;
        for (index, node) in nodes.iter().enumerate() {
            let start = (BODY_TYPE_GRAPH_START + index * 2) * 4;
            words[start..start + 8].copy_from_slice(node);
            // A declaration identity is stable within this exact source unit.
            // An instance row is not: replay may have rebound its arguments.
            // Preserve only the declaration, alongside all structural children.
            if node[0] == 9 && node[4..6] == self.source_unit {
                words[start + 7] = node[6];
            } else {
                words[start + 7] = u32::MAX;
            }
        }
        let edge_start = BODY_TYPE_EDGE_START * 4;
        words[edge_start..edge_start + edges.len()].copy_from_slice(&edges);
        Ok(words)
    }
}

/// Postorder graph of complete checked types. A nominal node keeps every
/// ordered child and the declaration's scoped identity independently of width.
fn append_checked_node(
    ty: &CheckedGenericType,
    nodes: &mut Vec<[u32; 8]>,
    edges: &mut Vec<u32>,
) -> Result<u32> {
    let mut node = [0; 8];
    let mut arguments = Vec::new();
    match ty {
        CheckedGenericType::Scalar(code) => {
            ensure!(
                (2..=8).contains(code),
                "unsupported body scalar identity {code}"
            );
            node[0] = 1;
            node[1] = *code;
        }
        CheckedGenericType::NativeValue { identity, words } => {
            ensure!(
                *words <= 0xffff && identity.iter().all(|&v| v != u32::MAX),
                "invalid checked value layout"
            );
            node[0] = 9;
            node[3] = *words;
            node[4..7].copy_from_slice(identity);
        }
        CheckedGenericType::Nominal {
            identity,
            arguments: children,
            words,
        } => {
            ensure!(
                children.len() <= MAX_BODY_TYPE_ARGUMENTS,
                "nominal type exceeds {MAX_BODY_TYPE_ARGUMENTS} checked arguments"
            );
            ensure!(
                *words <= 0xffff && identity.iter().all(|&v| v != u32::MAX),
                "invalid checked nominal layout"
            );
            for child in children {
                arguments.push(match child {
                    CheckedGenericApplicationArgument::Type(ty) => {
                        append_checked_node(ty, nodes, edges)?
                    }
                    CheckedGenericApplicationArgument::Constant(value) => {
                        let value = value.literal().ok_or_else(|| anyhow::anyhow!(
                            "body specialization requires a complete nominal constant"))?;
                        intern_checked_node([10, value, 0, 0, 0, 0, 0, 0], &[], nodes, edges)?
                    }
                });
            }
            node[0] = 9;
            node[2] = children.len() as u32;
            node[3] = *words;
            node[4..7].copy_from_slice(identity);
        }
        CheckedGenericType::Reference(referent) => {
            node[0] = 4;
            node[1] = append_checked_node(referent, nodes, edges)?;
            node[3] = 1;
        }
        CheckedGenericType::Slice(element) => {
            node[0] = 3;
            node[1] = append_checked_node(element, nodes, edges)?;
            node[3] = 3;
        }
        CheckedGenericType::Array {
            element,
            length,
            words,
        } => {
            ensure!(
                *words <= 0xffff && (*length != 0 || *words == 0),
                "invalid checked fixed-array layout"
            );
            node[0] = 2;
            node[1] = append_checked_node(element, nodes, edges)?;
            node[2] = *length;
            node[3] = *words;
        }
        _ => anyhow::bail!("body specialization requires a complete checked type; found {ty:?}"),
    }
    intern_checked_node(node, &arguments, nodes, edges)
}

fn intern_checked_node(
    mut node: [u32; 8], arguments: &[u32],
    nodes: &mut Vec<[u32; 8]>, edges: &mut Vec<u32>,
) -> Result<u32> {
    if let Some(index) = nodes.iter().position(|existing| {
        if node[0] != 9 {
            return *existing == node;
        }
        existing[0] == node[0] && existing[2..] == node[2..] && {
            let start = existing[1] as usize;
            edges.get(start..start + arguments.len()) == Some(arguments)
        }
    }) {
        return Ok(index as u32);
    }
    ensure!(
        nodes.len() < MAX_BODY_TYPE_NODES,
        "body specialization exceeds {MAX_BODY_TYPE_NODES} checked type nodes"
    );
    if node[0] == 9 {
        ensure!(
            arguments.len() <= MAX_BODY_TYPE_EDGES - edges.len(),
            "body specialization exceeds {MAX_BODY_TYPE_EDGES} checked type edges"
        );
        node[1] = edges.len() as u32;
        edges.extend_from_slice(arguments);
    }
    let index = nodes.len() as u32;
    nodes.push(node);
    Ok(index)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn specialization_identity_excludes_derived_layout_but_retains_full_types() {
        let environment = |ty| CheckedBodySpecialization {
            target_symbol: 7,
            source_unit: [7, 3],
            constants: Vec::new(),
            arguments: vec![CheckedGenericArgument { slot: 0, ty }],
        };
        let first = environment(nominal(vec![CheckedGenericType::Scalar(2)]));
        let different_type = environment(nominal(vec![CheckedGenericType::Scalar(3)]));
        let mut different_layout = first.clone();
        if let CheckedGenericType::Nominal { words, .. } = &mut different_layout.arguments[0].ty {
            *words = 3;
        }
        assert_ne!(
            first.scheduling_words().unwrap(),
            different_type.scheduling_words().unwrap()
        );
        assert_eq!(
            first.scheduling_words().unwrap(),
            different_layout.scheduling_words().unwrap()
        );
        assert_ne!(
            first.scheduling_environment().unwrap().1,
            different_layout.scheduling_environment().unwrap().1
        );
        let inconsistent = CheckedBodySpecialization {
            arguments: vec![
                first.arguments[0].clone(),
                CheckedGenericArgument {
                    slot: 1,
                    ty: different_layout.arguments[0].ty.clone(),
                },
            ],
            ..first.clone()
        };
        assert!(
            inconsistent.scheduling_environment().is_err(),
            "one semantic type cannot carry conflicting layouts in the same environment"
        );
        let short = environment(CheckedGenericType::Array {
            element: Box::new(CheckedGenericType::Scalar(2)),
            length: 2,
            words: 2,
        });
        let long = environment(CheckedGenericType::Array {
            element: Box::new(CheckedGenericType::Scalar(2)),
            length: 3,
            words: 3,
        });
        assert_ne!(
            short.scheduling_words().unwrap(),
            long.scheduling_words().unwrap()
        );
    }

    #[test]
    fn constant_environments_keep_values_in_specialization_identity() {
        let empty = CheckedBodySpecialization {
            target_symbol: 7,
            source_unit: [1, 2],
            arguments: Vec::new(),
            constants: vec![CheckedGenericConstant::literal(0, 0)],
        };
        let different = CheckedBodySpecialization {
            constants: vec![CheckedGenericConstant::literal(0, 3)],
            ..empty.clone()
        };
        assert_ne!(
            empty.scheduling_words().unwrap(),
            different.scheduling_words().unwrap()
        );
        let typed = CheckedBodySpecialization {
            arguments: vec![CheckedGenericArgument {
                slot: 0,
                ty: CheckedGenericType::Scalar(3),
            }],
            ..different.clone()
        };
        assert_ne!(
            typed.scheduling_words().unwrap(),
            different.scheduling_words().unwrap()
        );
        for constants in [
            vec![],
            vec![CheckedGenericConstant::literal(1, 3)],
            vec![CheckedGenericConstant::literal(0, u32::MAX)],
            vec![CheckedGenericConstant {
                slot: 0,
                value: super::super::generic_calls::CheckedGenericConstantValue::Parameter(3),
            }],
        ] {
            assert!(
                CheckedBodySpecialization {
                    constants,
                    ..empty.clone()
                }
                .packet()
                .is_err()
            );
        }
    }

    #[test]
    fn reference_specializations_keep_referent_identity_and_pointer_width() {
        let first = CheckedGenericType::Nominal {
            identity: [7, 2, 19],
            arguments: vec![CheckedGenericApplicationArgument::Type(CheckedGenericType::Scalar(3))],
            words: 12,
        };
        let second = CheckedGenericType::Nominal {
            identity: [7, 2, 19],
            arguments: vec![CheckedGenericApplicationArgument::Type(CheckedGenericType::Scalar(2))],
            words: 12,
        };
        let reference = CheckedGenericType::Reference(Box::new(first.clone()));
        assert_ne!(
            packet(vec![first]).unwrap(),
            packet(vec![reference.clone()]).unwrap()
        );
        assert_ne!(
            packet(vec![reference.clone()]).unwrap(),
            packet(vec![CheckedGenericType::Reference(Box::new(second))]).unwrap(),
        );
        let mut nodes = Vec::new();
        let mut edges = Vec::new();
        let root = append_checked_node(&reference, &mut nodes, &mut edges).unwrap();
        assert_eq!(
            nodes[root as usize][3], 1,
            "a reference stores one pointer regardless of referent size"
        );
        assert_eq!(
            root,
            append_checked_node(&reference, &mut nodes, &mut edges).unwrap()
        );
    }

    #[test]
    fn reference_specializations_reject_unresolved_referents() {
        assert!(
            packet(vec![CheckedGenericType::Reference(Box::new(
                CheckedGenericType::Unresolved {
                    reference_tag: 2,
                    instance_kind: 0
                },
            ))])
            .is_err()
        );
    }

    fn packet(types: Vec<CheckedGenericType>) -> Result<[u32; BODY_SPECIALIZATION_WORDS]> {
        CheckedBodySpecialization {
            target_symbol: 0,
            source_unit: [0, 0],
            constants: Vec::new(),
            arguments: types
                .into_iter()
                .enumerate()
                .map(|(slot, ty)| CheckedGenericArgument {
                    slot: slot as u32,
                    ty,
                })
                .collect(),
        }
        .packet()
    }

    fn nominal(arguments: Vec<CheckedGenericType>) -> CheckedGenericType {
        CheckedGenericType::Nominal {
            identity: [7, 3, 11],
            arguments: arguments.into_iter().map(CheckedGenericApplicationArgument::Type).collect(),
            words: 2,
        }
    }

    #[test]
    fn replay_keeps_complete_arguments_and_scopes_local_declarations() {
        let specialization = CheckedBodySpecialization {
            target_symbol: 0x4000_0040,
            source_unit: [7, 3],
            constants: Vec::new(),
            arguments: vec![CheckedGenericArgument {
                slot: 0,
                ty: CheckedGenericType::Nominal {
                    identity: [7, 3, 0x2000_0030],
                    arguments: vec![CheckedGenericApplicationArgument::Type(CheckedGenericType::NativeValue {
                        identity: [7, 3, 0x4000_1002],
                        words: 0,
                    })],
                    words: 2,
                },
            }],
        };
        let local = specialization.packet().expect("local structural replay");
        assert_eq!(local[5], 10, "local calls must replay the complete graph");
        let root = (BODY_TYPE_GRAPH_START + local[6] as usize * 2) * 4;
        assert_eq!(local[root + 7], 0x2000_0030);
        assert_eq!(local[root + 2], 1, "retain the nominal argument");
        let edge = BODY_TYPE_EDGE_START * 4 + local[root + 1] as usize;
        let child = (BODY_TYPE_GRAPH_START + local[edge] as usize * 2) * 4;
        assert_eq!(local[child + 7], 0x4000_1002);
        let imported = CheckedBodySpecialization {
            source_unit: [7, 4],
            ..specialization.clone()
        }
        .packet()
        .expect("imported structural replay");
        assert_eq!(
            imported[root + 7],
            u32::MAX,
            "foreign tokens are not local declarations"
        );
        assert_eq!(imported[child + 7], u32::MAX);
        assert_eq!(&local[root..root + 7], &imported[root..root + 7]);
        assert_eq!(&local[child..child + 7], &imported[child..child + 7]);
        let changed = CheckedBodySpecialization {
            arguments: vec![CheckedGenericArgument {
                slot: 0,
                ty: CheckedGenericType::Nominal {
                    identity: [7, 3, 0x2000_0030],
                    arguments: vec![CheckedGenericApplicationArgument::Type(CheckedGenericType::Scalar(3))],
                    words: 2,
                },
            }],
            ..specialization.clone()
        };
        assert_ne!(
            specialization.scheduling_words().unwrap(),
            changed.scheduling_words().unwrap(),
            "equal widths and declaration identity do not erase different arguments"
        );
    }

    #[test]
    fn checked_packets_keep_zero_layouts_distinct_from_missing_layouts() {
        let empty = CheckedGenericType::NativeValue {
            identity: [7, 3, 11],
            words: 0,
        };
        let empty_array = CheckedGenericType::Array {
            element: Box::new(CheckedGenericType::Scalar(7)),
            length: 0,
            words: 0,
        };
        let zero_elements = CheckedGenericType::Array {
            element: Box::new(empty.clone()),
            length: 3,
            words: 0,
        };
        let left = CheckedGenericType::Nominal {
            identity: [7, 3, 12],
            arguments: vec![CheckedGenericApplicationArgument::Type(CheckedGenericType::Scalar(2))],
            words: 0,
        };
        let right = CheckedGenericType::Nominal {
            identity: [7, 3, 12],
            arguments: vec![CheckedGenericApplicationArgument::Type(CheckedGenericType::Scalar(3))],
            words: 0,
        };
        let graph = packet(vec![empty, empty_array, zero_elements, left, right])
            .expect("complete zero layouts");
        assert_ne!(
            graph[30], graph[38],
            "zero width cannot erase type arguments"
        );
        for argument in 0..5 {
            let root = (BODY_TYPE_GRAPH_START + graph[6 + argument * 8] as usize * 2) * 4;
            assert_eq!(graph[root + 3], 0, "zero width survives checked replay");
        }
        for invalid in [
            CheckedGenericType::NativeValue {
                identity: [7, 3, 11],
                words: u32::MAX,
            },
            CheckedGenericType::Array {
                element: Box::new(CheckedGenericType::Scalar(3)),
                length: 0,
                words: 1,
            },
            CheckedGenericType::Unresolved {
                reference_tag: 3,
                instance_kind: 1,
            },
        ] {
            assert!(
                packet(vec![invalid]).is_err(),
                "an unresolved layout must not become empty"
            );
        }
    }

    #[test]
    fn nominal_packets_keep_ordered_children_and_distinct_equal_width_types() {
        let left = nominal(vec![
            CheckedGenericType::Scalar(3),
            CheckedGenericType::Scalar(2),
        ]);
        let right = nominal(vec![
            CheckedGenericType::Scalar(2),
            CheckedGenericType::Scalar(3),
        ]);
        let graph = packet(vec![left.clone(), right, left]).expect("checked graph");
        let roots = [graph[6], graph[14], graph[22]];
        assert_eq!(roots[0], roots[2], "identical applications reuse one node");
        assert_ne!(
            roots[0], roots[1],
            "equal layouts do not erase ordered arguments"
        );
        for (root, expected) in [(roots[0], [3, 2]), (roots[1], [2, 3])] {
            let node = (BODY_TYPE_GRAPH_START + root as usize * 2) * 4;
            assert_eq!(&graph[node + 4..node + 7], &[7, 3, 11]);
            assert_eq!(graph[node + 2], 2);
            let edge = BODY_TYPE_EDGE_START * 4 + graph[node + 1] as usize;
            for (slot, scalar) in expected.into_iter().enumerate() {
                let child = (BODY_TYPE_GRAPH_START + graph[edge + slot] as usize * 2) * 4;
                assert_eq!(&graph[child..child + 2], &[1, scalar]);
            }
        }
        assert_eq!(graph[3], 4, "repeated applications share their edge list");
    }

    #[test]
    fn nominal_packets_preserve_nested_structural_arguments_and_arity_limit() {
        let child = nominal(vec![CheckedGenericType::Array {
            element: Box::new(CheckedGenericType::Slice(Box::new(
                CheckedGenericType::Scalar(7),
            ))),
            length: 2,
            words: 4,
        }]);
        let graph = packet(vec![nominal(vec![child; 32])]).expect("32 ordered arguments");
        let root = (BODY_TYPE_GRAPH_START + graph[6] as usize * 2) * 4;
        assert_eq!(graph[root + 2], 32);
        let start = BODY_TYPE_EDGE_START * 4 + graph[root + 1] as usize;
        assert!(
            graph[start..start + 32]
                .iter()
                .all(|child| *child == graph[start])
        );
        let error = packet(vec![nominal(vec![CheckedGenericType::Scalar(3); 33])]).unwrap_err();
        assert!(
            error.to_string().contains("exceeds 32 checked arguments"),
            "{error}"
        );
    }

    #[test]
    fn nominal_constants_keep_value_identity_and_require_closed_domains() {
        use super::super::generic_calls::CheckedGenericConstantValue as Constant;
        use CheckedGenericApplicationArgument as Argument;
        let environment = |arguments| CheckedBodySpecialization {
            target_symbol: 7,
            source_unit: [7, 3],
            constants: Vec::new(),
            arguments: vec![CheckedGenericArgument {
                slot: 0,
                ty: CheckedGenericType::Nominal {
                    identity: [7, 3, 11], arguments, words: 1,
                },
            }],
        };
        let typed = Argument::Type(CheckedGenericType::Scalar(3));
        let zero = environment(vec![typed.clone(), Argument::Constant(Constant::Literal(0))]);
        let three = environment(vec![typed.clone(), Argument::Constant(Constant::Literal(3))]);
        assert_ne!(zero.scheduling_words().unwrap(), three.scheduling_words().unwrap(),
            "unused constants remain part of nominal identity even at equal widths");
        assert_ne!(environment(vec![typed.clone(), typed.clone()]).scheduling_words().unwrap(),
            three.scheduling_words().unwrap(), "a constant value is not a scalar type code");
        for arguments in [
            vec![typed.clone(), Argument::Constant(Constant::Parameter(9))],
            vec![typed.clone(), Argument::Constant(Constant::Literal(u32::MAX))],
        ] {
            assert!(environment(arguments).packet().is_err(),
                "body replay requires complete nominal operands");
        }
    }

}
