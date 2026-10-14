//! Fully inlined size of a SPIR-V compute module.
//!
//! Slang keeps helpers out of line at -O0, but drivers inline every call
//! before compiling a pipeline, and NVIDIA's pipeline compile time grows
//! superlinearly with the inlined size (RTX 3070 on 615.71: 41k instructions
//! take 0.8 s, 68k take ~20 s, 110k take 156 s and 5.5 GB, 200k run out of
//! memory). A helper called from several sites is therefore paid for once per
//! call path, and the size the driver sees is what this module computes.

use std::collections::HashMap;

use anyhow::{Result, anyhow, ensure};

const SPIRV_MAGIC: u32 = 0x0723_0203;
const HEADER_WORDS: usize = 5;
const OP_NAME: u16 = 5;
const OP_ENTRY_POINT: u16 = 15;
const OP_FUNCTION: u16 = 54;
const OP_FUNCTION_END: u16 = 56;
const OP_FUNCTION_CALL: u16 = 57;

#[derive(Default)]
struct Function {
    own_instructions: u64,
    callees: Vec<u32>,
}

/// Size of one module as the driver sees it after inlining.
pub struct InlinedSize {
    /// Instructions of the entry point with every call inlined.
    pub inlined: u64,
    /// Instructions as written, each function counted once.
    pub own: u64,
    /// Helpers that contribute most to `inlined`: (name, copies, own size),
    /// largest `copies * own` first.
    pub top_helpers: Vec<(String, u64, u64)>,
}

pub fn inlined_size(words: &[u32], top: usize) -> Result<InlinedSize> {
    ensure!(
        words.len() >= HEADER_WORDS && words[0] == SPIRV_MAGIC,
        "not a little-endian SPIR-V module"
    );
    let mut names: HashMap<u32, String> = HashMap::new();
    let mut functions: HashMap<u32, Function> = HashMap::new();
    let mut entry_points = Vec::new();
    let mut current: Option<u32> = None;
    let mut at = HEADER_WORDS;
    while at < words.len() {
        let count = (words[at] >> 16) as usize;
        let opcode = (words[at] & 0xffff) as u16;
        ensure!(
            count > 0 && at + count <= words.len(),
            "malformed SPIR-V instruction at word {at}"
        );
        match opcode {
            OP_NAME if count >= 3 => {
                names.insert(words[at + 1], literal_string(&words[at + 2..at + count]));
            }
            OP_ENTRY_POINT if count >= 3 => entry_points.push(words[at + 2]),
            OP_FUNCTION => {
                ensure!(count == 5, "malformed OpFunction at word {at}");
                functions.insert(words[at + 2], Function::default());
                current = Some(words[at + 2]);
            }
            OP_FUNCTION_END => current = None,
            _ => {
                if let Some(id) = current {
                    let function = functions.get_mut(&id).expect("current function");
                    function.own_instructions += 1;
                    if opcode == OP_FUNCTION_CALL && count >= 4 {
                        function.callees.push(words[at + 3]);
                    }
                }
            }
        }
        at += count;
    }

    // Post-order from the entry points: callees before callers.
    let mut order = Vec::new();
    let mut state: HashMap<u32, bool> = HashMap::new(); // false = on stack
    for &entry in &entry_points {
        post_order(entry, &functions, &mut state, &mut order)?;
    }
    let mut inlined: HashMap<u32, u64> = HashMap::new();
    for &id in &order {
        let function = &functions[&id];
        let size = function
            .callees
            .iter()
            .fold(function.own_instructions, |size, callee| size.saturating_add(inlined[callee]));
        inlined.insert(id, size);
    }
    // Copies of each function in the inlined entry points: callers first.
    let mut copies: HashMap<u32, u64> = HashMap::new();
    for &entry in &entry_points {
        *copies.entry(entry).or_default() += 1;
    }
    for &id in order.iter().rev() {
        let n = copies.get(&id).copied().unwrap_or(0);
        for &callee in &functions[&id].callees {
            let slot = copies.entry(callee).or_default();
            *slot = slot.saturating_add(n);
        }
    }
    let mut top_helpers = order
        .iter()
        .filter(|id| !entry_points.contains(id))
        .map(|id| {
            let name = names.get(id).cloned().unwrap_or_else(|| format!("%{id}"));
            (name, copies[id], functions[id].own_instructions)
        })
        .collect::<Vec<_>>();
    top_helpers.sort_by_key(|(_, copies, own)| std::cmp::Reverse(copies.saturating_mul(*own)));
    top_helpers.truncate(top);

    Ok(InlinedSize {
        inlined: entry_points.iter().map(|id| inlined[id]).fold(0, u64::saturating_add),
        own: functions.values().map(|function| function.own_instructions).sum(),
        top_helpers,
    })
}

/// TEMPORARY test harness, opt-in via `LANIUS_SHADER_NOINLINE_MIN_INSTRUCTIONS`:
/// in a kernel whose fully inlined size is at least `min_kernel`, sets
/// `DontInline` on every helper whose fully inlined size is at least
/// `min_instructions`, so oversized kernels can be created while they are
/// being rewritten to fit the budget. NVIDIA hangs some dispatches whose lanes
/// diverge inside out-of-line calls, so this is never a fix and never the
/// default; delete it once `inlined_size_budget.txt` is empty. Returns how
/// many functions were marked.
pub fn mark_dont_inline(words: &mut [u32], min_kernel: u64, min_instructions: u64) -> Result<usize> {
    const DONT_INLINE: u32 = 0x2;
    const INLINE: u32 = 0x1;
    let mut controls: HashMap<u32, usize> = HashMap::new();
    let mut entry_points = Vec::new();
    let mut functions: HashMap<u32, Function> = HashMap::new();
    let mut current = None;
    let mut at = HEADER_WORDS;
    while at < words.len() {
        let count = (words[at] >> 16) as usize;
        let opcode = (words[at] & 0xffff) as u16;
        ensure!(count > 0 && at + count <= words.len(), "malformed SPIR-V instruction at word {at}");
        match opcode {
            OP_ENTRY_POINT if count >= 3 => entry_points.push(words[at + 2]),
            OP_FUNCTION => {
                controls.insert(words[at + 2], at + 3);
                functions.insert(words[at + 2], Function::default());
                current = Some(words[at + 2]);
            }
            OP_FUNCTION_END => current = None,
            _ => {
                if let Some(id) = current {
                    let function = functions.get_mut(&id).expect("current function");
                    function.own_instructions += 1;
                    if opcode == OP_FUNCTION_CALL && count >= 4 {
                        function.callees.push(words[at + 3]);
                    }
                }
            }
        }
        at += count;
    }
    let mut order = Vec::new();
    let mut state = HashMap::new();
    for &entry in &entry_points {
        post_order(entry, &functions, &mut state, &mut order)?;
    }
    let mut inlined: HashMap<u32, u64> = HashMap::new();
    for &id in &order {
        let function = &functions[&id];
        let size = function
            .callees
            .iter()
            .fold(function.own_instructions, |size, callee| size.saturating_add(inlined[callee]));
        inlined.insert(id, size);
    }
    let kernel = entry_points.iter().map(|id| inlined[id]).fold(0, u64::saturating_add);
    if kernel < min_kernel {
        return Ok(0);
    }
    let mut marked = 0;
    for &id in &order {
        if inlined[&id] >= min_instructions && !entry_points.contains(&id) {
            let control = &mut words[controls[&id]];
            *control = (*control & !INLINE) | DONT_INLINE;
            marked += 1;
        }
    }
    Ok(marked)
}

fn post_order(
    id: u32,
    functions: &HashMap<u32, Function>,
    state: &mut HashMap<u32, bool>,
    order: &mut Vec<u32>,
) -> Result<()> {
    match state.get(&id) {
        Some(true) => return Ok(()),
        Some(false) => return Err(anyhow!("recursive SPIR-V call graph through %{id}")),
        None => {}
    }
    let function = functions
        .get(&id)
        .ok_or_else(|| anyhow!("OpFunctionCall targets unknown function %{id}"))?;
    state.insert(id, false);
    for &callee in &function.callees {
        post_order(callee, functions, state, order)?;
    }
    state.insert(id, true);
    order.push(id);
    Ok(())
}

fn literal_string(words: &[u32]) -> String {
    let bytes = words.iter().flat_map(|word| word.to_le_bytes()).collect::<Vec<_>>();
    let end = bytes.iter().position(|&b| b == 0).unwrap_or(bytes.len());
    String::from_utf8_lossy(&bytes[..end]).into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn op(opcode: u16, operands: &[u32]) -> Vec<u32> {
        let mut words = vec![((operands.len() as u32 + 1) << 16) | opcode as u32];
        words.extend_from_slice(operands);
        words
    }

    fn function(id: u32, body: &[Vec<u32>]) -> Vec<u32> {
        let mut words = op(OP_FUNCTION, &[1, id, 0, 2]);
        for instruction in body {
            words.extend(instruction);
        }
        words.extend(op(OP_FUNCTION_END, &[]));
        words
    }

    #[test]
    fn helpers_are_counted_once_per_call_path() {
        const NOP: u16 = 0;
        let mut words = vec![SPIRV_MAGIC, 0x0001_0500, 0, 100, 0];
        words.extend(op(OP_ENTRY_POINT, &[5, 10]));
        words.extend(op(OP_NAME, &[30, u32::from_le_bytes(*b"leaf"), 0]));
        // leaf: 3 instructions; mid calls leaf twice; main calls mid twice.
        words.extend(function(30, &[op(NOP, &[]), op(NOP, &[]), op(NOP, &[])]));
        words.extend(function(20, &[op(OP_FUNCTION_CALL, &[1, 21, 30]), op(OP_FUNCTION_CALL, &[1, 22, 30])]));
        words.extend(function(10, &[op(OP_FUNCTION_CALL, &[1, 11, 20]), op(OP_FUNCTION_CALL, &[1, 12, 20])]));

        let size = inlined_size(&words, 1).unwrap();
        assert_eq!(size.own, 3 + 2 + 2);
        assert_eq!(size.inlined, 2 + 2 * (2 + 2 * 3));
        assert_eq!(size.top_helpers, vec![("leaf".to_string(), 4, 3)]);
    }
}
