//! Makes the storage buffers of step programs coherent
//! (`shaders/shared/collectives/step_program.slang`).
//!
//! A step program runs several steps in one dispatch, and a step reads what
//! lanes of other workgroups wrote in an earlier step. On NVIDIA a plain read
//! of a storage buffer does not see such a write: each workgroup's processor
//! keeps its own cached copy of the word. A read through a variable with the
//! SPIR-V `Coherent` decoration does see it (measured on an RTX 3090 by
//! `gpu/program_barrier_tests.rs`).
//!
//! Slang emits the decoration for a buffer declared `globallycoherent`, but
//! refuses to pass such a buffer to a function with a buffer parameter, which
//! shared helpers have. The build therefore adds the decoration to the
//! SPIR-V: every writable storage buffer of a step program gets it. A buffer
//! declared `StructuredBuffer` is left alone: the program cannot write it, so
//! no read of it can be stale.
//!
//! A kernel is a step program when its SPIR-V names the workgroup variable
//! `step_program_group_failed`, which every use of the helper keeps.

use std::collections::{HashMap, HashSet};

use anyhow::{Result, ensure};

const SPIRV_MAGIC: u32 = 0x0723_0203;
const HEADER_WORDS: usize = 5;
const OP_NAME: u32 = 5;
const OP_TYPE_POINTER: u32 = 32;
const OP_VARIABLE: u32 = 59;
const OP_DECORATE: u32 = 71;
const DECORATION_BLOCK: u32 = 2;
const DECORATION_BUFFER_BLOCK: u32 = 3;
const DECORATION_COHERENT: u32 = 23;
const DECORATION_NON_WRITABLE: u32 = 24;
const STORAGE_CLASS_UNIFORM: u32 = 2;
const STORAGE_CLASS_STORAGE_BUFFER: u32 = 12;

/// The kernel that must be recognized as a step program. The build fails when
/// it is not, so a Slang release that stops naming variables cannot turn the
/// check off without notice.
pub const REFERENCE_STEP_PROGRAM: &str = "tests/probe_program_barrier";

const MARKER_NAME: &str = "step_program_group_failed";

/// What the check found in one kernel.
#[derive(Debug, PartialEq)]
pub struct StepProgramBuffers {
    pub is_step_program: bool,
    /// Writable storage buffers without `Coherent`: variable id and name,
    /// sorted by name.
    pub incoherent: Vec<(u32, String)>,
}

pub fn step_program_buffers(words: &[u32]) -> Result<StepProgramBuffers> {
    ensure!(
        words.len() >= HEADER_WORDS && words[0] == SPIRV_MAGIC,
        "not a SPIR-V module"
    );
    let mut names: HashMap<u32, String> = HashMap::new();
    let mut decorations: HashSet<(u32, u32)> = HashSet::new();
    // Pointer type id to the id of the type it points to.
    let mut pointees: HashMap<u32, u32> = HashMap::new();
    // (variable id, pointer type id, storage class)
    let mut variables = Vec::new();
    let mut at = HEADER_WORDS;
    while at < words.len() {
        let count = (words[at] >> 16) as usize;
        ensure!(
            count > 0 && at + count <= words.len(),
            "malformed instruction at word {at}"
        );
        let operands = &words[at + 1..at + count];
        match words[at] & 0xffff {
            OP_NAME if !operands.is_empty() => {
                names.insert(operands[0], literal_string(&operands[1..]));
            }
            OP_DECORATE if operands.len() >= 2 => {
                decorations.insert((operands[0], operands[1]));
            }
            OP_TYPE_POINTER if operands.len() >= 3 => {
                pointees.insert(operands[0], operands[2]);
            }
            OP_VARIABLE if operands.len() >= 3 => {
                variables.push((operands[1], operands[0], operands[2]));
            }
            _ => {}
        }
        at += count;
    }

    let is_step_program = names.values().any(|name| name == MARKER_NAME);
    let mut incoherent = Vec::new();
    for (variable, pointer_type, storage_class) in variables {
        let Some(&pointee) = pointees.get(&pointer_type) else {
            continue;
        };
        // SPIR-V 1.3 declares a storage buffer as a `BufferBlock` struct in
        // the Uniform class, later versions as a `Block` struct in the
        // StorageBuffer class.
        let storage_buffer = match storage_class {
            STORAGE_CLASS_UNIFORM => decorations.contains(&(pointee, DECORATION_BUFFER_BLOCK)),
            STORAGE_CLASS_STORAGE_BUFFER => decorations.contains(&(pointee, DECORATION_BLOCK)),
            _ => false,
        };
        if !storage_buffer
            || decorations.contains(&(variable, DECORATION_NON_WRITABLE))
            || decorations.contains(&(variable, DECORATION_COHERENT))
        {
            continue;
        }
        let name = names
            .get(&variable)
            .cloned()
            .unwrap_or_else(|| format!("%{variable}"));
        incoherent.push((variable, name));
    }
    incoherent.sort_by(|left, right| (&left.1, left.0).cmp(&(&right.1, right.0)));
    Ok(StepProgramBuffers {
        is_step_program,
        incoherent,
    })
}

/// Adds `Coherent` to every writable storage buffer of a step program.
/// Returns whether the module changed.
pub fn make_step_program_buffers_coherent(words: &mut Vec<u32>) -> Result<bool> {
    let buffers = step_program_buffers(words)?;
    if !buffers.is_step_program || buffers.incoherent.is_empty() {
        return Ok(false);
    }
    // Decorations are one section of a module. The new ones go before its
    // first instruction. A module with a storage buffer has one, since the
    // buffer's struct is decorated.
    let mut at = HEADER_WORDS;
    while at < words.len() && words[at] & 0xffff != OP_DECORATE {
        at += (words[at] >> 16) as usize;
    }
    ensure!(
        at < words.len(),
        "a module with storage buffers has no decoration"
    );
    let added: Vec<u32> = buffers
        .incoherent
        .iter()
        .flat_map(|&(variable, _)| [(3 << 16) | OP_DECORATE, variable, DECORATION_COHERENT])
        .collect();
    words.splice(at..at, added);
    Ok(true)
}

fn literal_string(words: &[u32]) -> String {
    let bytes: Vec<u8> = words
        .iter()
        .flat_map(|word| word.to_le_bytes())
        .take_while(|&byte| byte != 0)
        .collect();
    String::from_utf8_lossy(&bytes).into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn instruction(opcode: u32, operands: &[u32]) -> Vec<u32> {
        let mut words = vec![((operands.len() as u32 + 1) << 16) | opcode];
        words.extend_from_slice(operands);
        words
    }

    fn name(id: u32, text: &str) -> Vec<u32> {
        let mut bytes = text.as_bytes().to_vec();
        bytes.push(0);
        bytes.resize(bytes.len().div_ceil(4) * 4, 0);
        let mut operands = vec![id];
        operands.extend(
            bytes
                .chunks_exact(4)
                .map(|chunk| u32::from_le_bytes(chunk.try_into().unwrap())),
        );
        instruction(OP_NAME, &operands)
    }

    /// Buffers %10 (writable), %11 (read-only) and %12 (coherent) of the
    /// buffer struct %3, and the workgroup variable %13 named `marker`.
    fn module(marker: &str) -> Vec<u32> {
        let mut words = vec![SPIRV_MAGIC, 0x0001_0300, 0, 100, 0];
        words.extend(name(10, "written"));
        words.extend(name(11, "read_only"));
        words.extend(name(12, "coherent"));
        words.extend(name(13, marker));
        words.extend(instruction(OP_DECORATE, &[3, DECORATION_BUFFER_BLOCK]));
        words.extend(instruction(OP_DECORATE, &[11, DECORATION_NON_WRITABLE]));
        words.extend(instruction(OP_DECORATE, &[12, DECORATION_COHERENT]));
        words.extend(instruction(OP_TYPE_POINTER, &[4, STORAGE_CLASS_UNIFORM, 3]));
        words.extend(instruction(OP_TYPE_POINTER, &[5, 4, 6]));
        for variable in [10, 11, 12] {
            words.extend(instruction(
                OP_VARIABLE,
                &[4, variable, STORAGE_CLASS_UNIFORM],
            ));
        }
        words.extend(instruction(OP_VARIABLE, &[5, 13, 4]));
        words
    }

    #[test]
    fn lists_writable_buffers_without_the_coherent_decoration() {
        assert_eq!(
            step_program_buffers(&module(MARKER_NAME)).unwrap(),
            StepProgramBuffers {
                is_step_program: true,
                incoherent: vec![(10, "written".to_owned())],
            }
        );
    }

    #[test]
    fn decorates_the_writable_buffers_of_a_step_program() {
        let mut words = module(MARKER_NAME);
        assert!(make_step_program_buffers_coherent(&mut words).unwrap());
        assert_eq!(
            step_program_buffers(&words).unwrap(),
            StepProgramBuffers {
                is_step_program: true,
                incoherent: Vec::new(),
            }
        );
        assert!(!make_step_program_buffers_coherent(&mut words).unwrap());

        let mut other = module("other");
        let before = other.clone();
        assert!(!make_step_program_buffers_coherent(&mut other).unwrap());
        assert_eq!(other, before);
    }

    #[test]
    fn a_kernel_without_the_marker_is_not_a_step_program() {
        assert!(
            !step_program_buffers(&module("other"))
                .unwrap()
                .is_step_program
        );
    }
}
