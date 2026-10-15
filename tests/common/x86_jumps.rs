//! Checks that the direct jumps in a Lanius x86-64 executable stay inside
//! their own function.
//!
//! A jmp or jcc whose target lies in another function is a miscompile even
//! when the program happens to pass. One such bug: when every arm of an
//! if/else returned, the false edge into the `else` block resolved to a stale
//! row in another function. Most of those programs crashed, but some passed
//! only because the bad edge was never taken.
//!
//! The executables have no symbols, so `objdump` disassembles the executable
//! load segment linearly from the end of the program headers. The check walks
//! the code reachable from the entry point through direct jumps, calls and
//! fallthrough, plus every `push %rbp; mov %rsp,%rbp` prologue. Bytes it
//! never reaches, such as string data after the code, are never checked.
//! Function starts are the entry point, every direct call target and every
//! prologue. Each reachable jmp or jcc must land inside
//! [its function's start, the next function's start), on an instruction
//! start. Each direct call must land on an instruction start in the code.
//! A function reached only through an indirect call and without a prologue
//! is not checked.

use std::{
    collections::{BTreeSet, HashMap},
    fmt,
    fs,
    io,
    path::Path,
    process::Command,
    time::Duration,
};

const ET_EXEC: u16 = 2;
const EM_X86_64: u16 = 62;
const PT_LOAD: u32 = 1;
const PF_X: u32 = 1;
const OBJDUMP_TIMEOUT: Duration = Duration::from_secs(120);
const REPORTED_PROBLEMS: usize = 12;

/// The executable load segment that holds the entry point.
struct CodeSegment<'a> {
    entry: u64,
    vaddr: u64,
    bytes: &'a [u8],
    /// First address after the ELF and program headers when they share the
    /// segment, else the segment start.
    code_start: u64,
}

impl CodeSegment<'_> {
    fn end(&self) -> u64 {
        self.vaddr + self.bytes.len() as u64
    }

    fn contains_code(&self, address: u64) -> bool {
        address >= self.code_start && address < self.end()
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Flow {
    /// Falls through to the next instruction.
    Next,
    /// Unconditional jump: no fallthrough.
    Jump,
    /// Conditional jump: target and fallthrough.
    Branch,
    /// Call: target and fallthrough.
    Call,
    /// Return or trap: no successor.
    Stop,
}

struct Instruction {
    length: u64,
    flow: Flow,
    target: Option<u64>,
    bytes: Vec<u8>,
    text: String,
}

/// What the check found in one executable.
pub struct JumpCheck {
    /// Reachable direct jmp and jcc instructions.
    pub jumps: usize,
    /// Function starts found.
    pub functions: usize,
    pub problems: Vec<String>,
}

fn read_u16(bytes: &[u8], offset: usize) -> Option<u16> {
    Some(u16::from_le_bytes(bytes.get(offset..offset + 2)?.try_into().ok()?))
}

fn read_u32(bytes: &[u8], offset: usize) -> Option<u32> {
    Some(u32::from_le_bytes(bytes.get(offset..offset + 4)?.try_into().ok()?))
}

fn read_u64(bytes: &[u8], offset: usize) -> Option<u64> {
    Some(u64::from_le_bytes(bytes.get(offset..offset + 8)?.try_into().ok()?))
}

/// True for a little-endian ELF64 x86-64 executable (not an object file).
pub fn is_x86_64_executable(bytes: &[u8]) -> bool {
    bytes.len() >= 64
        && &bytes[0..4] == b"\x7fELF"
        && bytes[4] == 2
        && bytes[5] == 1
        && read_u16(bytes, 16) == Some(ET_EXEC)
        && read_u16(bytes, 18) == Some(EM_X86_64)
}

fn code_segment(elf: &[u8]) -> Result<CodeSegment<'_>, String> {
    let header = |what: &str| format!("ELF header has no valid {what}");
    let entry = read_u64(elf, 24).ok_or_else(|| header("entry point"))?;
    let program_headers = read_u64(elf, 32).ok_or_else(|| header("program header offset"))?;
    let entry_size = read_u16(elf, 54).ok_or_else(|| header("program header size"))? as u64;
    let count = read_u16(elf, 56).ok_or_else(|| header("program header count"))? as u64;
    let headers_end = program_headers + entry_size * count;
    for index in 0..count {
        let base = (program_headers + index * entry_size) as usize;
        let segment_type = read_u32(elf, base).ok_or_else(|| header("program header"))?;
        let flags = read_u32(elf, base + 4).ok_or_else(|| header("program header"))?;
        let offset = read_u64(elf, base + 8).ok_or_else(|| header("program header"))?;
        let vaddr = read_u64(elf, base + 16).ok_or_else(|| header("program header"))?;
        let file_size = read_u64(elf, base + 32).ok_or_else(|| header("program header"))?;
        if segment_type != PT_LOAD || flags & PF_X == 0 {
            continue;
        }
        if entry < vaddr || entry - vaddr >= file_size {
            continue;
        }
        let bytes = usize::try_from(offset)
            .ok()
            .zip(usize::try_from(offset + file_size).ok())
            .and_then(|(start, end)| elf.get(start..end))
            .ok_or_else(|| "the executable segment lies outside the file".to_string())?;
        let skipped = if offset < headers_end {
            (headers_end - offset).min(file_size)
        } else {
            0
        };
        return Ok(CodeSegment {
            entry,
            vaddr,
            bytes,
            code_start: vaddr + skipped,
        });
    }
    Err(format!("no executable load segment holds the entry point {entry:#x}"))
}

fn parse_hex_address(token: &str) -> Option<u64> {
    let digits = token.strip_prefix("0x")?;
    if digits.is_empty() || !digits.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return None;
    }
    u64::from_str_radix(digits, 16).ok()
}

fn is_prefix(token: &str) -> bool {
    matches!(
        token,
        "addr32"
            | "bnd"
            | "cs"
            | "data16"
            | "ds"
            | "es"
            | "fs"
            | "gs"
            | "lock"
            | "notrack"
            | "rep"
            | "repe"
            | "repne"
            | "repnz"
            | "repz"
            | "ss"
    ) || token.starts_with("rex")
}

fn flow_of(mnemonic: &str) -> Flow {
    match mnemonic {
        "jmp" | "jmpq" | "ljmp" => Flow::Jump,
        "call" | "callq" | "lcall" => Flow::Call,
        "ud0" | "ud1" | "ud2" | "hlt" | "int3" | "(bad)" => Flow::Stop,
        _ if mnemonic.starts_with("ret") || mnemonic == "lret" || mnemonic.starts_with("iret") => {
            Flow::Stop
        }
        _ if mnemonic.starts_with('j') || mnemonic.starts_with("loop") => Flow::Branch,
        _ => Flow::Next,
    }
}

/// One line of `objdump -d --insn-width=16`: `  400078:\t49 89 e7 \tmov ...`.
fn parse_line(line: &str) -> Option<(u64, Instruction)> {
    let mut parts = line.split('\t');
    let address = parts.next()?.trim().strip_suffix(':')?;
    let address = u64::from_str_radix(address, 16).ok()?;
    let bytes = parts
        .next()?
        .split_whitespace()
        .map(|byte| u8::from_str_radix(byte, 16).ok())
        .collect::<Option<Vec<u8>>>()?;
    let text = parts.collect::<Vec<_>>().join(" ").trim().to_string();
    if bytes.is_empty() || text.is_empty() {
        return None;
    }
    let mut tokens = text.split_whitespace().skip_while(|token| is_prefix(token));
    let mnemonic = tokens.next().unwrap_or("");
    let flow = flow_of(mnemonic);
    let target = match flow {
        Flow::Jump | Flow::Branch | Flow::Call => tokens.next().and_then(parse_hex_address),
        Flow::Next | Flow::Stop => None,
    };
    Some((
        address,
        Instruction {
            length: bytes.len() as u64,
            flow,
            target,
            bytes,
            text,
        },
    ))
}

fn disassemble(segment: &CodeSegment<'_>) -> Result<HashMap<u64, Instruction>, String> {
    // Not a TempArtifact: its write_bytes checks executables, and this file
    // is a raw segment image, never an executable.
    let image = super::temp_artifact_path("laniusc_jump_check", "segment", Some("bin"));
    fs::write(&image, segment.bytes)
        .map_err(|err| format!("write segment image {}: {err}", image.display()))?;
    let mut command = Command::new("objdump");
    command
        .args(["-D", "-z", "-b", "binary", "-m", "i386:x86-64", "--insn-width=16"])
        .arg(format!("--adjust-vma={:#x}", segment.vaddr))
        .arg(format!("--start-address={:#x}", segment.code_start))
        .arg(format!("--stop-address={:#x}", segment.end()))
        .arg(&image);
    let output = super::command_output_result_with_timeout(
        "objdump for the x86 jump check",
        &mut command,
        OBJDUMP_TIMEOUT,
        super::TimeoutDetails::default(),
    );
    let _ = fs::remove_file(&image);
    let output = output.map_err(|err| {
        format!(
            "run objdump (GNU binutils), which the x86 jump check needs: {err}{}",
            if err.kind() == io::ErrorKind::NotFound {
                "; install binutils"
            } else {
                ""
            }
        )
    })?;
    if !output.status.success() {
        return Err(format!(
            "objdump failed ({}): {}",
            output.status,
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    let text = String::from_utf8_lossy(&output.stdout);
    Ok(text.lines().filter_map(parse_line).collect())
}

/// Checks every reachable direct jump in `elf`. Returns `Ok(None)` when
/// `elf` is not an x86-64 executable.
pub fn check_x86_64_jumps(elf: &[u8]) -> Result<Option<JumpCheck>, String> {
    if !is_x86_64_executable(elf) {
        return Ok(None);
    }
    let segment = code_segment(elf)?;
    let instructions = disassemble(&segment)?;
    if !instructions.contains_key(&segment.entry) {
        return Err(format!(
            "the entry point {:#x} is not an instruction start",
            segment.entry
        ));
    }

    let mut starts = BTreeSet::from([segment.entry]);
    let mut work = vec![segment.entry];
    for (&address, instruction) in &instructions {
        let prologue = instruction.bytes == [0x55]
            && instructions
                .get(&(address + instruction.length))
                .is_some_and(|next| next.bytes == [0x48, 0x89, 0xe5]);
        if prologue {
            starts.insert(address);
            work.push(address);
        }
    }

    let mut problems = Vec::new();
    let mut reached = BTreeSet::new();
    while let Some(address) = work.pop() {
        if !reached.insert(address) {
            continue;
        }
        let Some(instruction) = instructions.get(&address) else {
            // Only fallthrough lands here unchecked; it runs off the decoded
            // code (the segment end).
            continue;
        };
        if matches!(instruction.flow, Flow::Next | Flow::Branch | Flow::Call) {
            work.push(address + instruction.length);
        }
        if !matches!(instruction.flow, Flow::Jump | Flow::Branch | Flow::Call) {
            continue;
        }
        let Some(target) = instruction.target else {
            continue;
        };
        if !segment.contains_code(target) || !instructions.contains_key(&target) {
            problems.push(format!(
                "`{}` at {address:#x} targets {target:#x}, which is not an instruction start in the code",
                instruction.text
            ));
            continue;
        }
        if instruction.flow == Flow::Call {
            starts.insert(target);
        }
        work.push(target);
    }

    let starts = starts.into_iter().collect::<Vec<_>>();
    let mut jumps = 0;
    for &address in &reached {
        let Some(instruction) = instructions.get(&address) else {
            continue;
        };
        let (Flow::Jump | Flow::Branch, Some(target)) = (instruction.flow, instruction.target)
        else {
            continue;
        };
        jumps += 1;
        let function = starts.partition_point(|&start| start <= address);
        let Some(&low) = function.checked_sub(1).and_then(|index| starts.get(index)) else {
            continue;
        };
        let high = starts.get(function).copied().unwrap_or(segment.end());
        if target < low || target >= high {
            problems.push(format!(
                "`{}` at {address:#x} leaves its function [{low:#x}, {high:#x})",
                instruction.text
            ));
        }
    }
    problems.sort();
    problems.dedup();
    Ok(Some(JumpCheck {
        jumps,
        functions: starts.len(),
        problems,
    }))
}

/// Panics when a reachable direct jmp or jcc in the x86-64 executable `elf`
/// leaves its function, or a direct jump or call misses an instruction
/// start. Bytes that are not an x86-64 executable are ignored.
pub fn assert_x86_64_jumps_stay_in_functions(context: impl fmt::Display, elf: &[u8]) {
    let check = match check_x86_64_jumps(elf) {
        Ok(Some(check)) => check,
        Ok(None) => return,
        Err(err) => panic!("{context}: x86 jump check: {err}"),
    };
    if check.problems.is_empty() {
        return;
    }
    let shown = check
        .problems
        .iter()
        .take(REPORTED_PROBLEMS)
        .map(|problem| format!("\n  {problem}"))
        .collect::<String>();
    let more = check.problems.len().saturating_sub(REPORTED_PROBLEMS);
    panic!(
        "{context}: {} bad direct jumps or calls ({} jumps, {} functions checked):{shown}{}",
        check.problems.len(),
        check.jumps,
        check.functions,
        if more > 0 {
            format!("\n  ... and {more} more")
        } else {
            String::new()
        }
    );
}

/// Reads the executable at `path` (for example one the CLI wrote) and checks
/// it like [`assert_x86_64_jumps_stay_in_functions`].
pub fn assert_x86_64_file_jumps_stay_in_functions(path: impl AsRef<Path>) {
    let path = path.as_ref();
    let bytes = fs::read(path)
        .unwrap_or_else(|err| panic!("read executable {} for the x86 jump check: {err}", path.display()));
    assert_x86_64_jumps_stay_in_functions(path.display(), &bytes);
}

/// `fs::write` for a test executable: checks its jumps first.
pub fn write_x86_64_executable(path: impl AsRef<Path>, bytes: impl AsRef<[u8]>) -> io::Result<()> {
    let path = path.as_ref();
    let bytes = bytes.as_ref();
    assert_x86_64_jumps_stay_in_functions(path.display(), bytes);
    fs::write(path, bytes)
}
