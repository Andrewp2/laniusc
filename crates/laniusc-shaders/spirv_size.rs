//! Fully inlined size, per-thread local array bytes and known driver hazards
//! of a SPIR-V compute module.
//!
//! Slang keeps helpers out of line at -O0, but drivers inline every call
//! before compiling a pipeline, and NVIDIA's pipeline compile time grows
//! superlinearly with the inlined size (RTX 3070 on 615.71: 41k instructions
//! take 0.8 s, 68k take ~20 s, 110k take 156 s and 5.5 GB, 200k run out of
//! memory). A helper called from several sites is therefore paid for once per
//! call path, and the size the driver sees is what this module computes.

use std::collections::{HashMap, HashSet};

use anyhow::{Result, anyhow, ensure};

const SPIRV_MAGIC: u32 = 0x0723_0203;
const HEADER_WORDS: usize = 5;
const OP_NAME: u16 = 5;
const OP_ENTRY_POINT: u16 = 15;
const OP_FUNCTION: u16 = 54;
const OP_FUNCTION_END: u16 = 56;
const OP_FUNCTION_CALL: u16 = 57;
const OP_TYPE_BOOL: u16 = 20;
const OP_TYPE_INT: u16 = 21;
const OP_TYPE_FLOAT: u16 = 22;
const OP_TYPE_VECTOR: u16 = 23;
const OP_TYPE_MATRIX: u16 = 24;
const OP_TYPE_ARRAY: u16 = 28;
const OP_TYPE_STRUCT: u16 = 30;
const OP_TYPE_POINTER: u16 = 32;
const OP_CONSTANT_TRUE: u16 = 41;
const OP_CONSTANT_FALSE: u16 = 42;
const OP_CONSTANT: u16 = 43;
const OP_CONSTANT_COMPOSITE: u16 = 44;
const OP_CONSTANT_NULL: u16 = 46;
const OP_VARIABLE: u16 = 59;
const OP_STORE: u16 = 62;
const OP_COPY_MEMORY: u16 = 63;
const OP_COPY_MEMORY_SIZED: u16 = 64;
const OP_ACCESS_CHAIN: u16 = 65;
const OP_IN_BOUNDS_ACCESS_CHAIN: u16 = 66;
const OP_PTR_ACCESS_CHAIN: u16 = 67;
const OP_IN_BOUNDS_PTR_ACCESS_CHAIN: u16 = 70;
const OP_COMPOSITE_CONSTRUCT: u16 = 80;
const OP_COPY_OBJECT: u16 = 83;
const OP_UDIV: u16 = 134;
const STORAGE_PRIVATE: u32 = 6;
const STORAGE_FUNCTION: u32 = 7;

/// Integer divisions that NVIDIA 615 cannot compile when the dividend is the
/// all-ones constant 0xffffffff and the divisor is not a constant, typically
/// an overflow guard such as `0xffffffffu / count`: pipeline creation fails
/// with "NVVM compilation failed: 3" and the device is lost, although
/// spirv-val accepts the module. Probed on single kernels: OpUMod, OpSDiv and
/// OpSRem of 0xffffffff (-1) by a runtime value compile, and so do OpUDiv of
/// 0xfffffffe, 0x7fffffff, 0x80000000 or 1000 and variable / variable.
const ALL_ONES_DIVIDEND_HAZARDS: [(u16, &str); 1] = [(OP_UDIV, "OpUDiv")];

#[derive(Default)]
struct Function {
    own_instructions: u64,
    callees: Vec<u32>,
    /// Bytes of this function's own written local arrays.
    own_local_bytes: u64,
}

/// A Function- or Private-storage variable whose type holds an array.
struct LocalArray {
    bytes: u64,
    /// The function that declares it; None for a Private global.
    function: Option<u32>,
    /// Stored to through an element pointer, copied into, stored a runtime
    /// value, or passed to a call. An array that only ever holds constants is
    /// a read-only table, which drivers keep out of local memory.
    written: bool,
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
    /// Per-thread bytes of written local arrays (Function- or Private-storage
    /// variables whose type holds an array) along the deepest call chain: a
    /// function's arrays are live for the whole function, so they add to
    /// those of the callee that needs the most, while sibling calls reuse the
    /// same space. Private globals count once. Drivers keep such arrays in
    /// local (scratch) memory, and NVIDIA reserves the largest per-thread
    /// figure of any created pipeline for every resident thread of the
    /// process. Arrays that only ever hold constants (lookup tables) are not
    /// counted: drivers keep them in registers or constant memory.
    pub local_bytes: u64,
    /// Divisions the driver cannot compile (see `ALL_ONES_DIVIDEND_HAZARDS`)
    /// as (function name, opcode name), in module order, in any function.
    pub all_ones_divisions: Vec<(String, &'static str)>,
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
    let mut locals = LocalArrays::default();
    let mut all_ones_divisions = Vec::new();
    let mut at = HEADER_WORDS;
    while at < words.len() {
        let count = (words[at] >> 16) as usize;
        let opcode = (words[at] & 0xffff) as u16;
        ensure!(
            count > 0 && at + count <= words.len(),
            "malformed SPIR-V instruction at word {at}"
        );
        locals.visit(opcode, &words[at + 1..at + count], current);
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
                    if let Some(&(_, op_name)) =
                        ALL_ONES_DIVIDEND_HAZARDS.iter().find(|(op, _)| *op == opcode)
                        && count >= 5
                        && locals.all_ones.contains(&words[at + 3])
                        && !locals.constant_values.contains(&words[at + 4])
                    {
                        all_ones_divisions.push((id, op_name));
                    }
                }
            }
        }
        at += count;
    }
    let mut private_local_bytes = 0u64;
    for array in locals.arrays.values().filter(|array| array.written) {
        match array.function.and_then(|id| functions.get_mut(&id)) {
            Some(function) => function.own_local_bytes += array.bytes,
            None => private_local_bytes += array.bytes,
        }
    }

    // Post-order from the entry points: callees before callers.
    let mut order = Vec::new();
    let mut state: HashMap<u32, bool> = HashMap::new(); // false = on stack
    for &entry in &entry_points {
        post_order(entry, &functions, &mut state, &mut order)?;
    }
    let mut inlined: HashMap<u32, u64> = HashMap::new();
    let mut inlined_local_bytes: HashMap<u32, u64> = HashMap::new();
    for &id in &order {
        let function = &functions[&id];
        let size = function
            .callees
            .iter()
            .fold(function.own_instructions, |size, callee| size.saturating_add(inlined[callee]));
        inlined.insert(id, size);
        let deepest_callee = function.callees.iter().map(|callee| inlined_local_bytes[callee]).max();
        inlined_local_bytes
            .insert(id, function.own_local_bytes.saturating_add(deepest_callee.unwrap_or(0)));
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
        local_bytes: entry_points
            .iter()
            .map(|id| inlined_local_bytes[id])
            .fold(0, u64::max)
            .saturating_add(private_local_bytes),
        all_ones_divisions: all_ones_divisions
            .into_iter()
            .map(|(id, op_name)| (names.get(&id).cloned().unwrap_or_else(|| format!("%{id}")), op_name))
            .collect(),
    })
}

/// Collects a module's local arrays and whether each one is written, and the
/// constants that decide both that and the division hazards.
#[derive(Default)]
struct LocalArrays {
    /// Byte size of every sized type, and whether it holds an array.
    types: HashMap<u32, (u64, bool)>,
    /// Pointer type -> (storage class, pointee type).
    pointers: HashMap<u32, (u32, u32)>,
    /// Integer constant values (array lengths).
    integers: HashMap<u32, u64>,
    /// Values known at compile time: constants and composites of them.
    constant_values: HashSet<u32>,
    /// 32-bit constants with every bit set, and composites of them.
    all_ones: HashSet<u32>,
    arrays: HashMap<u32, LocalArray>,
    /// Pointer -> the local array variable it points into.
    roots: HashMap<u32, u32>,
}

impl LocalArrays {
    fn visit(&mut self, opcode: u16, operands: &[u32], current: Option<u32>) {
        match opcode {
            OP_TYPE_BOOL if !operands.is_empty() => {
                self.types.insert(operands[0], (4, false));
            }
            OP_TYPE_INT | OP_TYPE_FLOAT if operands.len() >= 2 => {
                self.types.insert(operands[0], (u64::from(operands[1]).div_ceil(8), false));
            }
            OP_TYPE_VECTOR | OP_TYPE_MATRIX if operands.len() >= 3 => {
                let (element, array) = self.types.get(&operands[1]).copied().unwrap_or((4, false));
                self.types.insert(operands[0], (element.saturating_mul(u64::from(operands[2])), array));
            }
            OP_TYPE_ARRAY if operands.len() >= 3 => {
                let (element, _) = self.types.get(&operands[1]).copied().unwrap_or((4, false));
                let length = self.integers.get(&operands[2]).copied().unwrap_or(0);
                self.types.insert(operands[0], (element.saturating_mul(length), true));
            }
            OP_TYPE_STRUCT if !operands.is_empty() => {
                let (bytes, array) = operands[1..].iter().fold((0u64, false), |(bytes, array), member| {
                    let (size, has) = self.types.get(member).copied().unwrap_or((4, false));
                    (bytes.saturating_add(size), array || has)
                });
                self.types.insert(operands[0], (bytes, array));
            }
            OP_TYPE_POINTER if operands.len() >= 3 => {
                self.pointers.insert(operands[0], (operands[1], operands[2]));
            }
            OP_CONSTANT if operands.len() >= 3 => {
                self.integers.insert(operands[1], u64::from(operands[2]));
                self.constant_values.insert(operands[1]);
                if operands.len() == 3 && operands[2] == u32::MAX {
                    self.all_ones.insert(operands[1]);
                }
            }
            OP_CONSTANT_TRUE | OP_CONSTANT_FALSE | OP_CONSTANT_COMPOSITE | OP_CONSTANT_NULL
                if operands.len() >= 2 =>
            {
                self.constant_values.insert(operands[1]);
                if opcode == OP_CONSTANT_COMPOSITE
                    && operands.len() > 2
                    && operands[2..].iter().all(|part| self.all_ones.contains(part))
                {
                    self.all_ones.insert(operands[1]);
                }
            }
            OP_COMPOSITE_CONSTRUCT if operands.len() >= 2 => {
                if operands[2..].iter().all(|part| self.constant_values.contains(part)) {
                    self.constant_values.insert(operands[1]);
                }
            }
            OP_VARIABLE if operands.len() >= 3 => {
                let Some(&(storage, pointee)) = self.pointers.get(&operands[0]) else {
                    return;
                };
                if storage != STORAGE_FUNCTION && storage != STORAGE_PRIVATE {
                    return;
                }
                let Some(&(bytes, true)) = self.types.get(&pointee) else {
                    return;
                };
                let written = operands.get(3).is_some_and(|value| !self.constant_values.contains(value));
                let function = if storage == STORAGE_FUNCTION { current } else { None };
                self.arrays.insert(operands[1], LocalArray { bytes, function, written });
                self.roots.insert(operands[1], operands[1]);
            }
            OP_ACCESS_CHAIN
            | OP_IN_BOUNDS_ACCESS_CHAIN
            | OP_PTR_ACCESS_CHAIN
            | OP_IN_BOUNDS_PTR_ACCESS_CHAIN
            | OP_COPY_OBJECT
                if operands.len() >= 3 =>
            {
                if let Some(&root) = self.roots.get(&operands[2]) {
                    self.roots.insert(operands[1], root);
                }
            }
            OP_STORE if operands.len() >= 2 => {
                // A whole-variable store of a constant keeps a table read-only.
                let pointer = operands[0];
                if !(self.arrays.contains_key(&pointer) && self.constant_values.contains(&operands[1])) {
                    self.mark_written(pointer);
                }
            }
            OP_COPY_MEMORY | OP_COPY_MEMORY_SIZED if !operands.is_empty() => {
                self.mark_written(operands[0]);
            }
            OP_FUNCTION_CALL if operands.len() >= 3 => {
                // The callee may write through any pointer argument.
                for &argument in &operands[3..] {
                    self.mark_written(argument);
                }
                // A constructor of constants (a table row built by a helper)
                // folds to a constant once inlined.
                if operands.len() > 3
                    && operands[3..].iter().all(|argument| self.constant_values.contains(argument))
                {
                    self.constant_values.insert(operands[1]);
                }
            }
            _ => {}
        }
    }

    fn mark_written(&mut self, pointer: u32) {
        if let Some(array) = self.roots.get(&pointer).and_then(|root| self.arrays.get_mut(root)) {
            array.written = true;
        }
    }
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
        assert_eq!(size.local_bytes, 0);
    }

    #[test]
    fn written_local_arrays_add_up_along_the_deepest_call_chain() {
        const OP_LOAD: u16 = 61;
        let mut words = vec![SPIRV_MAGIC, 0x0001_0500, 0, 200, 0];
        words.extend(op(OP_ENTRY_POINT, &[5, 10]));
        // %1 uint, %2 = 16, %3 uint[16] (64 bytes), %4 Function pointer to it,
        // %5 Private pointer to it, %6 Function pointer to uint, %7 = 0.
        words.extend(op(OP_TYPE_INT, &[1, 32, 0]));
        words.extend(op(OP_CONSTANT, &[1, 2, 16]));
        words.extend(op(OP_TYPE_ARRAY, &[3, 1, 2]));
        words.extend(op(OP_TYPE_POINTER, &[4, STORAGE_FUNCTION, 3]));
        words.extend(op(OP_TYPE_POINTER, &[5, STORAGE_PRIVATE, 3]));
        words.extend(op(OP_TYPE_POINTER, &[6, STORAGE_FUNCTION, 1]));
        words.extend(op(OP_CONSTANT, &[1, 7, 0]));
        // A Private global stored through an element pointer: counted once.
        words.extend(op(OP_VARIABLE, &[5, 40, STORAGE_PRIVATE]));
        // stack: a helper's stack, written through an element pointer.
        words.extend(function(
            30,
            &[
                op(OP_VARIABLE, &[4, 31, STORAGE_FUNCTION]),
                op(OP_ACCESS_CHAIN, &[6, 32, 31, 7]),
                op(OP_STORE, &[32, 7]),
            ],
        ));
        // outer: its own written array stays live across its call to stack.
        words.extend(function(
            50,
            &[
                op(OP_VARIABLE, &[4, 51, STORAGE_FUNCTION]),
                op(OP_FUNCTION_CALL, &[1, 52, 30]),
                op(OP_STORE, &[51, 52]),
            ],
        ));
        // row: a table row constructor.
        words.extend(function(26, &[]));
        // table: filled with constants (one row from a constructor called with
        // constants) and only read.
        words.extend(function(
            20,
            &[
                op(OP_VARIABLE, &[4, 21, STORAGE_FUNCTION]),
                op(OP_FUNCTION_CALL, &[1, 25, 26, 7]),
                op(OP_COMPOSITE_CONSTRUCT, &[3, 22, 25, 7]),
                op(OP_STORE, &[21, 22]),
                op(OP_ACCESS_CHAIN, &[6, 23, 21, 7]),
                op(OP_LOAD, &[1, 24, 23]),
            ],
        ));
        // main calls stack twice (the copies reuse one space), outer and table
        // once each, and writes the Private array.
        words.extend(function(
            10,
            &[
                op(OP_FUNCTION_CALL, &[1, 11, 30]),
                op(OP_FUNCTION_CALL, &[1, 12, 30]),
                op(OP_FUNCTION_CALL, &[1, 13, 50]),
                op(OP_FUNCTION_CALL, &[1, 15, 20]),
                op(OP_ACCESS_CHAIN, &[6, 14, 40, 7]),
                op(OP_STORE, &[14, 7]),
            ],
        ));

        let size = inlined_size(&words, 1).unwrap();
        assert_eq!(size.local_bytes, (64 + 64) + 64);
        assert!(size.all_ones_divisions.is_empty());
    }

    #[test]
    fn unsigned_divisions_of_all_ones_by_a_runtime_value_are_reported() {
        const OP_LOAD: u16 = 61;
        const OP_SDIV: u16 = 135;
        const OP_UMOD: u16 = 137;
        const OP_SREM: u16 = 138;
        let mut words = vec![SPIRV_MAGIC, 0x0001_0500, 0, 100, 0];
        words.extend(op(OP_ENTRY_POINT, &[5, 10]));
        words.extend(op(OP_NAME, &[30, u32::from_le_bytes(*b"guar"), u32::from_le_bytes(*b"d\0\0\0")]));
        // %1 uint, %2 = 0xffffffff, %3 = 7, %4 = 0xfffffffe, %5 Function
        // pointer to uint, %6 uint2, %7 = (0xffffffff, 0xffffffff), %8
        // Function pointer to uint2.
        words.extend(op(OP_TYPE_INT, &[1, 32, 0]));
        words.extend(op(OP_CONSTANT, &[1, 2, u32::MAX]));
        words.extend(op(OP_CONSTANT, &[1, 3, 7]));
        words.extend(op(OP_CONSTANT, &[1, 4, 0xffff_fffe]));
        words.extend(op(OP_TYPE_POINTER, &[5, STORAGE_FUNCTION, 1]));
        words.extend(op(OP_TYPE_VECTOR, &[6, 1, 2]));
        words.extend(op(OP_CONSTANT_COMPOSITE, &[6, 7, 2, 2]));
        words.extend(op(OP_TYPE_POINTER, &[8, STORAGE_FUNCTION, 6]));
        // guard: %33 is only known at run time.
        words.extend(function(
            30,
            &[
                op(OP_VARIABLE, &[5, 31, STORAGE_FUNCTION]),
                op(OP_LOAD, &[1, 33, 31]),
                op(OP_UDIV, &[1, 34, 2, 33]),  // hazard
                op(OP_UDIV, &[1, 35, 2, 3]),   // constant divisor: folded
                op(OP_UDIV, &[1, 36, 4, 33]),  // another dividend: compiles
                op(OP_UDIV, &[1, 37, 33, 33]), // variable / variable: compiles
                op(OP_UMOD, &[1, 38, 2, 33]),  // remainders and signed: compile
                op(OP_SDIV, &[1, 39, 2, 33]),
                op(OP_SREM, &[1, 40, 2, 33]),
            ],
        ));
        words.extend(function(
            10,
            &[
                op(OP_FUNCTION_CALL, &[1, 11, 30]),
                op(OP_VARIABLE, &[8, 12, STORAGE_FUNCTION]),
                op(OP_LOAD, &[6, 13, 12]),
                op(OP_UDIV, &[6, 14, 7, 13]), // hazard: an all-ones vector
            ],
        ));

        let size = inlined_size(&words, 1).unwrap();
        assert_eq!(
            size.all_ones_divisions,
            vec![("guard".to_string(), "OpUDiv"), ("%10".to_string(), "OpUDiv")]
        );
    }
}
