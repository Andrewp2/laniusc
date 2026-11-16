//! Descriptor bindings a compute kernel's entry point uses, numbered densely.
//!
//! Slang reflection lists every global of a module in each kernel of the
//! module, so a scan that touches three buffers can reflect a hundred. The
//! runtime builds bind group layouts from reflection, and wgpu tracks and
//! validates every buffer in a bound group on every dispatch, so unused
//! bindings cost host time on each dispatch.
//!
//! The build therefore keeps the bindings an entry point uses, plus every
//! constant buffer (so callers' dynamic offsets keep their count), and
//! renumbers them 0..n in their reflected order: it rewrites the SPIR-V
//! `Binding` decorations and lists the kept reflected indices, in their new
//! order, in the reflection (`laniusBindings`). The runtime drops the other
//! parameters and renumbers the kept ones the same way when it parses the
//! reflection. Bindings that are not kept move after the kept ones, so no two
//! variables share a number. The numbering must stay dense: NVIDIA 615.71
//! crashes compiling a large kernel whose layout leaves five or more binding
//! numbers unused (`type_checker/calls/03d_bind_method_receiver_environment`
//! with 95 of its 104 bindings).
//!
//! SPIR-V 1.3 entry points list only their input and output variables, so a
//! binding counts as used when any instruction in a function reachable from
//! an entry point names its variable. Every operand word is treated as a
//! possible id, so a literal that happens to equal a variable's id keeps that
//! binding: the set can only be too large, never too small.

use std::collections::{BTreeSet, HashMap, HashSet};

use anyhow::{Result, anyhow, ensure};

const SPIRV_MAGIC: u32 = 0x0723_0203;
const HEADER_WORDS: usize = 5;
const OP_ENTRY_POINT: u32 = 15;
const OP_DECORATE: u32 = 71;
const OP_FUNCTION: u32 = 54;
const OP_FUNCTION_END: u32 = 56;
const DECORATION_BINDING: u32 = 33;
const DECORATION_DESCRIPTOR_SET: u32 = 34;

/// The reflection key that lists the kept reflected binding indices.
pub const REFLECTION_KEY: &str = "laniusBindings";

/// The descriptor bindings of a SPIR-V module.
#[derive(Debug, PartialEq)]
pub struct ModuleBindings {
    /// Binding indices of set 0 that an entry point uses.
    pub used: BTreeSet<u32>,
    /// Binding indices of set 0 that any variable carries.
    pub declared: BTreeSet<u32>,
    /// Whether a variable is bound in a set other than 0.
    pub other_sets: bool,
}

/// One instruction: (word offset, opcode, operand range).
fn instructions(words: &[u32]) -> Result<Vec<(usize, u32, std::ops::Range<usize>)>> {
    ensure!(
        words.len() >= HEADER_WORDS && words[0] == SPIRV_MAGIC,
        "not a SPIR-V module"
    );
    let mut out = Vec::new();
    let mut at = HEADER_WORDS;
    while at < words.len() {
        let count = (words[at] >> 16) as usize;
        ensure!(
            count > 0 && at + count <= words.len(),
            "malformed instruction at word {at}"
        );
        out.push((at, words[at] & 0xffff, at + 1..at + count));
        at += count;
    }
    Ok(out)
}

pub fn module_bindings(words: &[u32]) -> Result<ModuleBindings> {
    let mut entries = Vec::new();
    let mut set = HashMap::new();
    let mut binding = HashMap::new();
    let mut functions: HashMap<u32, Vec<u32>> = HashMap::new();
    let mut current: Option<(u32, Vec<u32>)> = None;
    for (_, opcode, range) in instructions(words)? {
        let operands = &words[range];
        match opcode {
            OP_ENTRY_POINT => entries.push(
                *operands
                    .get(1)
                    .ok_or_else(|| anyhow!("OpEntryPoint without a function"))?,
            ),
            OP_DECORATE if operands.len() >= 3 => match operands[1] {
                DECORATION_DESCRIPTOR_SET => {
                    set.insert(operands[0], operands[2]);
                }
                DECORATION_BINDING => {
                    binding.insert(operands[0], operands[2]);
                }
                _ => {}
            },
            OP_FUNCTION => {
                let id = *operands
                    .get(1)
                    .ok_or_else(|| anyhow!("OpFunction without a result id"))?;
                current = Some((id, Vec::new()));
            }
            OP_FUNCTION_END => {
                let (id, body) = current
                    .take()
                    .ok_or_else(|| anyhow!("OpFunctionEnd outside a function"))?;
                functions.insert(id, body);
            }
            _ => {
                if let Some((_, body)) = current.as_mut() {
                    body.extend_from_slice(operands);
                }
            }
        }
    }
    ensure!(!entries.is_empty(), "no entry point");

    let mut reached = HashSet::new();
    let mut named = HashSet::new();
    let mut pending = entries;
    while let Some(function) = pending.pop() {
        if !reached.insert(function) {
            continue;
        }
        let Some(body) = functions.get(&function) else {
            continue;
        };
        for &word in body {
            named.insert(word);
            if functions.contains_key(&word) && !reached.contains(&word) {
                pending.push(word);
            }
        }
    }

    let mut out = ModuleBindings {
        used: BTreeSet::new(),
        declared: BTreeSet::new(),
        other_sets: false,
    };
    for (variable, index) in &binding {
        if set.get(variable).copied().unwrap_or(0) != 0 {
            out.other_sets = true;
            continue;
        }
        out.declared.insert(*index);
        if named.contains(variable) {
            out.used.insert(*index);
        }
    }
    Ok(out)
}

/// The kept reflected indices in their new order (new index = position), or
/// `None` when the kernel keeps its reflected numbering. `reflected` lists each
/// top-level descriptor binding with whether it is a resource.
pub fn plan(module: &ModuleBindings, reflected: &[(u32, bool)]) -> Option<Vec<u32>> {
    let reflected_indices: BTreeSet<u32> = reflected.iter().map(|(index, _)| *index).collect();
    if module.other_sets
        || reflected_indices.len() != reflected.len()
        || !module.declared.is_subset(&reflected_indices)
    {
        return None;
    }
    let kept: Vec<u32> = reflected_indices
        .iter()
        .copied()
        .filter(|index| {
            module.used.contains(index)
                || reflected
                    .iter()
                    .any(|(reflected, resource)| reflected == index && !resource)
        })
        .collect();
    (kept.len() < reflected.len()).then_some(kept)
}

/// The new number of each reflected index: kept ones by position, the rest
/// after them in reflected order.
pub fn renumbering(kept: &[u32], reflected: &[(u32, bool)]) -> HashMap<u32, u32> {
    let mut map: HashMap<u32, u32> = kept
        .iter()
        .enumerate()
        .map(|(position, index)| (*index, position as u32))
        .collect();
    let mut dropped: Vec<u32> = reflected
        .iter()
        .map(|(index, _)| *index)
        .filter(|index| !map.contains_key(index))
        .collect();
    dropped.sort_unstable();
    for (offset, index) in dropped.into_iter().enumerate() {
        map.insert(index, (kept.len() + offset) as u32);
    }
    map
}

/// Rewrites the set-0 `Binding` decorations of `words` through `map`.
pub fn rewrite_bindings(words: &mut [u32], map: &HashMap<u32, u32>) -> Result<()> {
    for (_, opcode, range) in instructions(words)? {
        if opcode == OP_DECORATE && range.len() >= 3 && words[range.start + 1] == DECORATION_BINDING
        {
            let slot = range.start + 2;
            words[slot] = *map
                .get(&words[slot])
                .ok_or_else(|| anyhow!("binding {} is not reflected", words[slot]))?;
        }
    }
    Ok(())
}

/// `reflection` with `"laniusBindings": [...]` as its first key.
pub fn annotate_reflection(reflection: &str, kept: &[u32]) -> Result<String> {
    ensure!(
        !reflection.contains(REFLECTION_KEY),
        "reflection already lists kept bindings"
    );
    let open = reflection
        .find('{')
        .ok_or_else(|| anyhow!("reflection JSON has no object"))?;
    let list = kept
        .iter()
        .map(u32::to_string)
        .collect::<Vec<_>>()
        .join(", ");
    let mut out = String::with_capacity(reflection.len() + list.len() + 32);
    out.push_str(&reflection[..=open]);
    out.push_str(&format!("\n    \"{REFLECTION_KEY}\": [{list}],"));
    out.push_str(&reflection[open + 1..]);
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn instruction(opcode: u32, operands: &[u32]) -> Vec<u32> {
        let mut words = vec![((operands.len() as u32 + 1) << 16) | opcode];
        words.extend_from_slice(operands);
        words
    }

    /// %10 binding 0 is read by main (%1), %11 binding 1 by a helper %2
    /// that main calls, %12 binding 2 only by the unreachable %3.
    fn module() -> Vec<u32> {
        let mut words = vec![SPIRV_MAGIC, 0x0001_0300, 0, 100, 0];
        words.extend(instruction(OP_ENTRY_POINT, &[5, 1, 0x6e69_616d, 0]));
        for (variable, index) in [(10, 0), (11, 1), (12, 2)] {
            words.extend(instruction(OP_DECORATE, &[variable, DECORATION_DESCRIPTOR_SET, 0]));
            words.extend(instruction(OP_DECORATE, &[variable, DECORATION_BINDING, index]));
        }
        let load = 61;
        let call = 57;
        for (function, body) in [
            (1, vec![instruction(load, &[7, 20, 10]), instruction(call, &[4, 21, 2])]),
            (2, vec![instruction(load, &[7, 22, 11])]),
            (3, vec![instruction(load, &[7, 23, 12])]),
        ] {
            words.extend(instruction(OP_FUNCTION, &[4, function, 0, 6]));
            for body in body {
                words.extend(body);
            }
            words.extend(instruction(OP_FUNCTION_END, &[]));
        }
        words
    }

    #[test]
    fn keeps_bindings_named_in_reachable_functions_only() {
        let bindings = module_bindings(&module()).unwrap();
        assert_eq!(bindings.used, BTreeSet::from([0, 1]));
        assert_eq!(bindings.declared, BTreeSet::from([0, 1, 2]));
        assert!(!bindings.other_sets);
    }

    #[test]
    fn kept_bindings_are_renumbered_densely_and_constant_buffers_stay() {
        let module = ModuleBindings {
            used: BTreeSet::from([2, 5]),
            declared: BTreeSet::from([2, 4, 5]),
            other_sets: false,
        };
        // 0 is an unused constant buffer, 1, 3 and 4 unused resources.
        let reflected = [(0, false), (1, true), (2, true), (3, true), (4, true), (5, true)];
        let kept = plan(&module, &reflected).unwrap();
        assert_eq!(kept, vec![0, 2, 5]);
        let map = renumbering(&kept, &reflected);
        assert_eq!(
            [0, 1, 2, 3, 4, 5].map(|index| map[&index]),
            [0, 3, 1, 4, 5, 2]
        );
        let all_used = ModuleBindings {
            used: BTreeSet::from([0, 1]),
            declared: BTreeSet::from([0, 1]),
            other_sets: false,
        };
        assert_eq!(plan(&all_used, &[(0, true), (1, true)]), None);
    }

    #[test]
    fn rewriting_moves_binding_decorations_only() {
        let mut words = module();
        let map = HashMap::from([(0, 1), (1, 0), (2, 2)]);
        rewrite_bindings(&mut words, &map).unwrap();
        let bindings = module_bindings(&words).unwrap();
        assert_eq!(bindings.used, BTreeSet::from([0, 1]));
        assert_eq!(words.len(), module().len());
        assert!(rewrite_bindings(&mut words, &HashMap::new()).is_err());
    }

    #[test]
    fn annotation_is_the_first_key() {
        let out = annotate_reflection("{\n    \"parameters\": []\n}", &[0, 3]).unwrap();
        assert_eq!(
            out,
            "{\n    \"laniusBindings\": [0, 3],\n    \"parameters\": []\n}"
        );
    }
}
