//! ELF packaging for the opt-in Linux x86_64 C-library profile.
//!
//! Machine instructions and the CRT-facing bridge are emitted by the GPU.
//! This module copies those sections unchanged, translates recorded relocation
//! metadata, and delegates ordinary native linking and startup to the system C
//! driver. It neither decodes nor patches generated instructions.

use std::{
    collections::BTreeMap,
    fs::{self, File},
    io::{Read, Write},
    path::{Component, Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant},
};

use anyhow::{Context, Result, bail, ensure};

use super::{
    GpuX86ObjectSection,
    GpuX86ObjectSymbolRecord,
    GpuX86RelocatableObject,
    GpuX86RelocationKind,
    GpuX86RelocationTargetKind,
};
use crate::compiler::{NativeCFunction, NativeCSignature, NativeCType};

/// Explicit native inputs for the Linux x86_64/glibc profile.
///
/// `objects` are absolute paths to caller-supplied native objects or shared
/// libraries. `library_paths` are absolute search directories. `libraries`
/// contains plain library names, such as `crypto` or `sqlite3`, rather than
/// driver arguments. The linker is one executable path/name, never a shell
/// command. The system C driver supplies its normal CRT and libc dependencies.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeLinkOptions {
    pub libraries: Vec<String>,
    pub objects: Vec<PathBuf>,
    pub library_paths: Vec<PathBuf>,
    pub linker: Option<PathBuf>,
    pub timeout: Duration,
    pub max_output_bytes: usize,
}

impl Default for NativeLinkOptions {
    fn default() -> Self {
        Self {
            libraries: Vec::new(),
            objects: Vec::new(),
            library_paths: Vec::new(),
            linker: None,
            timeout: Duration::from_secs(30),
            max_output_bytes: 256 * 1024 * 1024,
        }
    }
}

/// GPU-provided location of the C-facing `main` bridge.
///
/// The compiler must supply this only after native-profile GPU emission has
/// succeeded. An ordinary raw-entry wrapper is not a C-facing main bridge.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct NativeMainBridge {
    pub object_index: usize,
    pub text_offset: u32,
    pub byte_len: u32,
}

const SHN_UNDEF: u16 = 0;
const TEXT: u16 = 1;
const RODATA: u16 = 2;
const RELA_TEXT: usize = 3;
const RELA_RODATA: usize = 4;
const SYMTAB: usize = 5;
const STRTAB: usize = 6;
const SHSTRTAB: usize = 7;
const GNU_STACK: usize = 8;
const SECTION_COUNT: usize = 9;
const ELF_HEADER_BYTES: usize = 64;
const SECTION_HEADER_BYTES: usize = 64;
const SYMBOL_BYTES: usize = 24;
const RELA_BYTES: usize = 24;
const INTERNAL_SYMBOL_PREFIX: &str = "__lanius_";
const MAX_LINK_TIMEOUT: Duration = Duration::from_secs(120);
const MAX_DIAGNOSTIC_BYTES: u64 = 64 * 1024;

type Identity = [u32; 3];

struct NativeSymbols<'a> {
    foreign: BTreeMap<Identity, &'a NativeCFunction>,
}

impl<'a> NativeSymbols<'a> {
    fn validate(
        objects: &[GpuX86RelocatableObject],
        bindings: &'a [NativeCFunction],
        main: NativeMainBridge,
    ) -> Result<Self> {
        ensure!(
            !objects.is_empty(),
            "native link requires at least one Lanius object"
        );
        let main_object = objects
            .get(main.object_index)
            .context("native main bridge names an absent object")?;
        ensure!(
            main_object.entry_offset.is_some()
                && objects
                    .iter()
                    .filter(|object| object.entry_offset.is_some())
                    .count()
                    == 1,
            "native C link requires exactly one entry object, containing its main bridge"
        );
        ensure!(
            main.byte_len != 0,
            "native main bridge has an empty text range"
        );
        let main_end = main
            .text_offset
            .checked_add(main.byte_len)
            .context("native main bridge text range overflows")?;
        ensure!(
            main_end as usize <= main_object.text.len(),
            "native main bridge exceeds its object's text section"
        );

        let mut foreign = BTreeMap::<Identity, &NativeCFunction>::new();
        let mut signatures = BTreeMap::<&str, &NativeCSignature>::new();
        for binding in bindings {
            validate_foreign_name(&binding.name)?;
            ensure!(
                binding.signature.parameters.len() <= 32,
                "native symbol {} exceeds the 32-parameter C profile",
                binding.name
            );
            ensure!(
                !binding.signature.parameters.contains(&NativeCType::Void),
                "native symbol {} has a void parameter",
                binding.name
            );
            if let Some(previous) = foreign.insert(binding.identity, binding) {
                ensure!(
                    previous == binding,
                    "native declaration {:?} has conflicting bindings",
                    binding.identity
                );
            }
            if let Some(previous) = signatures.insert(&binding.name, &binding.signature) {
                ensure!(
                    previous == &binding.signature,
                    "native symbol {} has conflicting checked signatures",
                    binding.name
                );
            }
        }

        let mut definitions = BTreeMap::<Identity, usize>::new();
        for (object_index, object) in objects.iter().enumerate() {
            object
                .validate()
                .map_err(anyhow::Error::msg)
                .with_context(|| format!("validate native Lanius object {object_index}"))?;
            for symbol in &object.symbols {
                let identity = symbol_identity(object, symbol)?;
                if symbol.section != GpuX86ObjectSection::Undefined {
                    ensure!(
                        !foreign.contains_key(&identity),
                        "native declaration {identity:?} has both a Lanius definition and a foreign binding"
                    );
                    if let Some(previous) = definitions.insert(identity, object_index) {
                        bail!(
                            "native declaration {identity:?} is defined more than once (objects {previous} and {object_index})"
                        );
                    }
                }
            }
        }
        for object in objects {
            for symbol in &object.symbols {
                let identity = symbol_identity(object, symbol)?;
                ensure!(
                    symbol.section != GpuX86ObjectSection::Undefined
                        || definitions.contains_key(&identity)
                        || foreign.contains_key(&identity),
                    "native declaration {identity:?} has no Lanius definition or checked foreign binding"
                );
            }
        }
        Ok(Self { foreign })
    }

    fn name(&self, identity: Identity) -> String {
        self.foreign.get(&identity).map_or_else(
            || {
                format!(
                    "{INTERNAL_SYMBOL_PREFIX}{}_{}_{}",
                    identity[0], identity[1], identity[2]
                )
            },
            |binding| binding.name.clone(),
        )
    }
}

fn validate_foreign_name(name: &str) -> Result<()> {
    ensure!(
        !name.is_empty()
            && name
                .bytes()
                .enumerate()
                .all(|(index, byte)| byte.is_ascii_alphabetic()
                    || byte == b'_'
                    || (index != 0 && byte.is_ascii_digit())),
        "native C symbol {name:?} is not a plain C identifier"
    );
    ensure!(
        name != "main" && !name.starts_with(INTERNAL_SYMBOL_PREFIX),
        "native C symbol {name:?} uses a compiler-reserved name"
    );
    Ok(())
}

fn symbol_identity(
    object: &GpuX86RelocatableObject,
    symbol: &GpuX86ObjectSymbolRecord,
) -> Result<Identity> {
    ensure!(
        symbol.identity_byte_len == 12,
        "native ELF export requires twelve-byte Lanius declaration identities"
    );
    let start = symbol.identity_byte_start as usize;
    let end = start
        .checked_add(12)
        .context("native declaration identity range overflows")?;
    let bytes = object
        .identity_bytes
        .get(start..end)
        .context("native declaration identity exceeds its object identity bytes")?;
    Ok(std::array::from_fn(|index| {
        u32::from_le_bytes(
            bytes[index * 4..index * 4 + 4]
                .try_into()
                .expect("four-byte identity word"),
        )
    }))
}

/// Serialize the GPU-produced sections as ordinary ELF64 relocatable objects.
///
/// Unbound declarations, duplicate definitions and inconsistent declarations of
/// the same C symbol reject before invoking an external linker. The returned
/// object's text and rodata sections are exact copies of the GPU byte arrays.
pub(crate) fn emit_native_elf_objects(
    objects: &[GpuX86RelocatableObject],
    bindings: &[NativeCFunction],
    main: NativeMainBridge,
) -> Result<Vec<Vec<u8>>> {
    let symbols = NativeSymbols::validate(objects, bindings, main)?;
    objects
        .iter()
        .enumerate()
        .map(|(object_index, object)| {
            emit_object(
                object,
                &symbols,
                (object_index == main.object_index).then_some(main),
            )
            .with_context(|| format!("export native ELF object {object_index}"))
        })
        .collect()
}

fn emit_object(
    object: &GpuX86RelocatableObject,
    names: &NativeSymbols<'_>,
    main: Option<NativeMainBridge>,
) -> Result<Vec<u8>> {
    let mut strings = StringTable::new();
    let mut symbols = vec![0; SYMBOL_BYTES];
    // Section symbols are local and precede every global symbol. ELF sh_info
    // points at the first global symbol, even for an object without functions.
    push_symbol(&mut symbols, 0, 3, TEXT, 0, 0);
    push_symbol(&mut symbols, 0, 3, RODATA, 0, 0);
    let mut declarations = BTreeMap::<Identity, &GpuX86ObjectSymbolRecord>::new();
    for symbol in &object.symbols {
        let identity = symbol_identity(object, symbol)?;
        // Calls can produce repeated undefined records for the same function.
        // A local definition supersedes those rows in this ELF symbol table.
        let entry = declarations.entry(identity).or_insert(symbol);
        if symbol.section != GpuX86ObjectSection::Undefined {
            *entry = symbol;
        }
    }
    let mut symbol_indices = BTreeMap::<Identity, u32>::new();
    for (identity, symbol) in declarations {
        let index = checked_u32(symbols.len() / SYMBOL_BYTES, "ELF symbol count")?;
        symbol_indices.insert(identity, index);
        let section = section_index(symbol.section);
        let symbol_type = if section == RODATA { 1 } else { 2 };
        push_symbol(
            &mut symbols,
            strings.insert(&names.name(identity))?,
            0x10 | symbol_type,
            section,
            symbol.offset as u64,
            symbol.size as u64,
        );
    }
    if let Some(main) = main {
        push_symbol(
            &mut symbols,
            strings.insert("main")?,
            0x12,
            TEXT,
            main.text_offset as u64,
            main.byte_len as u64,
        );
    }

    let mut text_relocations = Vec::new();
    let mut rodata_relocations = Vec::new();
    for relocation in &object.relocations {
        let (symbol_index, addend) = match relocation.target_kind {
            GpuX86RelocationTargetKind::SectionOffset => {
                let section = match relocation.target_index {
                    1 => TEXT as u32,
                    2 => RODATA as u32,
                    _ => bail!("native relocation targets an unsupported section"),
                };
                let addend = relocation
                    .addend
                    .checked_add(i64::from(relocation.target_offset))
                    .context("native ELF relocation addend overflows i64")?;
                (section, addend)
            }
            GpuX86RelocationTargetKind::Symbol => {
                let target = object
                    .symbols
                    .get(relocation.target_index as usize)
                    .context("native relocation symbol index exceeds its object")?;
                let identity = symbol_identity(object, target)?;
                (
                    *symbol_indices
                        .get(&identity)
                        .context("native ELF symbol was not emitted")?,
                    relocation.addend,
                )
            }
        };
        let relocation_type = match relocation.kind {
            GpuX86RelocationKind::Rel32 => 2,     // R_X86_64_PC32
            GpuX86RelocationKind::CallRel32 => 4, // R_X86_64_PLT32
            GpuX86RelocationKind::Abs32 => 10,    // R_X86_64_32
        };
        let output = match relocation.site_section {
            GpuX86ObjectSection::Text => &mut text_relocations,
            GpuX86ObjectSection::Rodata => &mut rodata_relocations,
            GpuX86ObjectSection::Undefined => {
                bail!("native relocation has an undefined site section")
            }
        };
        put_u64(output, u64::from(relocation.site_offset));
        put_u64(output, (u64::from(symbol_index) << 32) | relocation_type);
        put_u64(output, addend as u64);
    }

    let mut section_names = StringTable::new();
    let text_name = section_names.insert(".text")?;
    let rodata_name = section_names.insert(".rodata")?;
    let rela_text_name = section_names.insert(".rela.text")?;
    let rela_rodata_name = section_names.insert(".rela.rodata")?;
    let symtab_name = section_names.insert(".symtab")?;
    let strtab_name = section_names.insert(".strtab")?;
    let shstrtab_name = section_names.insert(".shstrtab")?;
    let stack_name = section_names.insert(".note.GNU-stack")?;
    let mut output = vec![0; ELF_HEADER_BYTES];
    let mut sections = vec![SectionHeader::default(); SECTION_COUNT];
    sections[TEXT as usize] = append_section(
        &mut output,
        &object.text,
        16,
        SectionHeader {
            name: text_name,
            section_type: 1,
            flags: 6,
            ..Default::default()
        },
    )?;
    sections[RODATA as usize] = append_section(
        &mut output,
        &object.rodata,
        1,
        SectionHeader {
            name: rodata_name,
            section_type: 1,
            flags: 2,
            ..Default::default()
        },
    )?;
    sections[RELA_TEXT] = append_section(
        &mut output,
        &text_relocations,
        8,
        SectionHeader {
            name: rela_text_name,
            section_type: 4,
            link: SYMTAB as u32,
            info: TEXT as u32,
            entry_size: RELA_BYTES as u64,
            ..Default::default()
        },
    )?;
    sections[RELA_RODATA] = append_section(
        &mut output,
        &rodata_relocations,
        8,
        SectionHeader {
            name: rela_rodata_name,
            section_type: 4,
            link: SYMTAB as u32,
            info: RODATA as u32,
            entry_size: RELA_BYTES as u64,
            ..Default::default()
        },
    )?;
    sections[SYMTAB] = append_section(
        &mut output,
        &symbols,
        8,
        SectionHeader {
            name: symtab_name,
            section_type: 2,
            link: STRTAB as u32,
            info: 3,
            entry_size: SYMBOL_BYTES as u64,
            ..Default::default()
        },
    )?;
    sections[STRTAB] = append_section(
        &mut output,
        &strings.bytes,
        1,
        SectionHeader {
            name: strtab_name,
            section_type: 3,
            ..Default::default()
        },
    )?;
    sections[SHSTRTAB] = append_section(
        &mut output,
        &section_names.bytes,
        1,
        SectionHeader {
            name: shstrtab_name,
            section_type: 3,
            ..Default::default()
        },
    )?;
    sections[GNU_STACK] = append_section(
        &mut output,
        &[],
        1,
        SectionHeader {
            name: stack_name,
            section_type: 1,
            ..Default::default()
        },
    )?;
    align_output(&mut output, 8)?;
    let section_header_offset = output.len() as u64;
    output
        .try_reserve(SECTION_COUNT * SECTION_HEADER_BYTES)
        .context("reserve native ELF section headers")?;
    for section in sections {
        section.write(&mut output);
    }

    let mut header = Vec::with_capacity(ELF_HEADER_BYTES);
    header.extend_from_slice(&[0x7f, b'E', b'L', b'F', 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    put_u16(&mut header, 1); // ET_REL
    put_u16(&mut header, 62); // EM_X86_64
    put_u32(&mut header, 1);
    put_u64(&mut header, 0); // e_entry
    put_u64(&mut header, 0); // e_phoff
    put_u64(&mut header, section_header_offset);
    put_u32(&mut header, 0);
    put_u16(&mut header, ELF_HEADER_BYTES as u16);
    put_u16(&mut header, 0);
    put_u16(&mut header, 0);
    put_u16(&mut header, SECTION_HEADER_BYTES as u16);
    put_u16(&mut header, SECTION_COUNT as u16);
    put_u16(&mut header, SHSTRTAB as u16);
    output[..ELF_HEADER_BYTES].copy_from_slice(&header);
    Ok(output)
}

#[derive(Clone, Copy, Default)]
struct SectionHeader {
    name: u32,
    section_type: u32,
    flags: u64,
    offset: u64,
    size: u64,
    link: u32,
    info: u32,
    align: u64,
    entry_size: u64,
}

impl SectionHeader {
    fn write(self, output: &mut Vec<u8>) {
        put_u32(output, self.name);
        put_u32(output, self.section_type);
        put_u64(output, self.flags);
        put_u64(output, 0); // sh_addr
        put_u64(output, self.offset);
        put_u64(output, self.size);
        put_u32(output, self.link);
        put_u32(output, self.info);
        put_u64(output, self.align);
        put_u64(output, self.entry_size);
    }
}

fn append_section(
    output: &mut Vec<u8>,
    bytes: &[u8],
    align: usize,
    mut header: SectionHeader,
) -> Result<SectionHeader> {
    align_output(output, align)?;
    header.offset = output.len() as u64;
    header.size = bytes.len() as u64;
    header.align = align as u64;
    output
        .len()
        .checked_add(bytes.len())
        .context("native ELF section size overflows")?;
    output
        .try_reserve(bytes.len())
        .context("reserve native ELF section bytes")?;
    output.extend_from_slice(bytes);
    Ok(header)
}

fn align_output(output: &mut Vec<u8>, align: usize) -> Result<()> {
    let padding = (align - output.len() % align) % align;
    let aligned_len = output
        .len()
        .checked_add(padding)
        .context("native ELF alignment overflows")?;
    output
        .try_reserve(padding)
        .context("reserve native ELF alignment padding")?;
    output.resize(aligned_len, 0);
    Ok(())
}

struct StringTable {
    bytes: Vec<u8>,
}
impl StringTable {
    fn new() -> Self {
        Self { bytes: vec![0] }
    }
    fn insert(&mut self, value: &str) -> Result<u32> {
        ensure!(
            !value.as_bytes().contains(&0),
            "native ELF string contains NUL"
        );
        let offset = checked_u32(self.bytes.len(), "ELF string table offset")?;
        let new_len = self
            .bytes
            .len()
            .checked_add(value.len())
            .and_then(|len| len.checked_add(1))
            .context("native ELF string table size overflows")?;
        checked_u32(new_len, "ELF string table length")?;
        self.bytes
            .try_reserve(value.len() + 1)
            .context("reserve native ELF string table")?;
        self.bytes.extend_from_slice(value.as_bytes());
        self.bytes.push(0);
        Ok(offset)
    }
}

fn section_index(section: GpuX86ObjectSection) -> u16 {
    match section {
        GpuX86ObjectSection::Undefined => SHN_UNDEF,
        GpuX86ObjectSection::Text => TEXT,
        GpuX86ObjectSection::Rodata => RODATA,
    }
}

fn push_symbol(output: &mut Vec<u8>, name: u32, info: u8, section: u16, value: u64, size: u64) {
    put_u32(output, name);
    output.extend_from_slice(&[info, 0]);
    put_u16(output, section);
    put_u64(output, value);
    put_u64(output, size);
}
fn put_u16(output: &mut Vec<u8>, value: u16) {
    output.extend_from_slice(&value.to_le_bytes());
}
fn put_u32(output: &mut Vec<u8>, value: u32) {
    output.extend_from_slice(&value.to_le_bytes());
}
fn put_u64(output: &mut Vec<u8>, value: u64) {
    output.extend_from_slice(&value.to_le_bytes());
}
fn checked_u32(value: usize, description: &str) -> Result<u32> {
    u32::try_from(value).with_context(|| format!("native {description} exceeds u32"))
}

/// Link exact GPU-generated object sections using the system C driver.
///
/// This opt-in profile deliberately selects a non-PIE executable, because the
/// existing object relocations use the small absolute-address code model.
pub(crate) fn link_native_executable(
    objects: &[GpuX86RelocatableObject],
    bindings: &[NativeCFunction],
    main: NativeMainBridge,
    options: &NativeLinkOptions,
) -> Result<Vec<u8>> {
    ensure!(
        cfg!(all(
            target_os = "linux",
            target_arch = "x86_64",
            target_env = "gnu"
        )),
        "native C linking currently supports Linux x86_64/glibc hosts"
    );
    validate_options(options)?;
    let elf_objects = emit_native_elf_objects(objects, bindings, main)?;
    let directory = NativeTempDirectory::create()?;
    let mut object_paths = Vec::with_capacity(elf_objects.len());
    for (index, bytes) in elf_objects.iter().enumerate() {
        let path = directory.path.join(format!("lanius-{index}.o"));
        write_private_file(&path, bytes)?;
        object_paths.push(path);
    }
    let output_path = directory.path.join("program");
    let diagnostics_path = directory.path.join("link.stderr");
    let diagnostics = create_private_file(&diagnostics_path)?;
    let mut command = link_command(options, &object_paths, &output_path)?;
    command
        .current_dir(&directory.path)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::from(diagnostics));
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        command.process_group(0);
    }
    let mut child = command.spawn().context("start native C linker")?;
    let started = Instant::now();
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) => {}
            Err(error) => {
                terminate_linker(&mut child);
                return Err(error).context("wait for native C linker");
            }
        }
        if started.elapsed() >= options.timeout {
            terminate_linker(&mut child);
            bail!(
                "native C linker exceeded its {} ms timeout{}",
                options.timeout.as_millis(),
                read_diagnostics(&diagnostics_path)
            );
        }
        thread::sleep(
            Duration::from_millis(10).min(options.timeout.saturating_sub(started.elapsed())),
        );
    };
    ensure!(
        status.success(),
        "native C linker failed ({status}){}",
        read_diagnostics(&diagnostics_path)
    );
    let file = File::open(&output_path).context("open native linked executable")?;
    let output_len = file
        .metadata()
        .context("stat native linked executable")?
        .len();
    ensure!(
        output_len != 0 && output_len <= options.max_output_bytes as u64,
        "native linked executable size {output_len} exceeds the admitted range 1..={}",
        options.max_output_bytes
    );
    let mut bytes = Vec::new();
    file.take(options.max_output_bytes as u64 + 1)
        .read_to_end(&mut bytes)
        .context("read native linked executable")?;
    ensure!(
        bytes.len() <= options.max_output_bytes,
        "native linked executable grew beyond its output limit"
    );
    Ok(bytes)
}

pub(crate) fn validate_options(options: &NativeLinkOptions) -> Result<()> {
    ensure!(
        !options.timeout.is_zero() && options.timeout <= MAX_LINK_TIMEOUT,
        "native linker timeout must be greater than zero and at most 120 seconds"
    );
    ensure!(
        options.max_output_bytes != 0 && options.max_output_bytes <= u32::MAX as usize,
        "native linker output limit must be in 1..=u32::MAX bytes"
    );
    if let Some(linker) = &options.linker {
        ensure!(
            !linker.as_os_str().is_empty()
                && (linker.is_absolute()
                    || (linker.components().count() == 1
                        && matches!(linker.components().next(), Some(Component::Normal(_))))),
            "native linker must be an absolute executable path or one executable name"
        );
    }
    for name in &options.libraries {
        ensure!(
            !name.is_empty()
                && !name.starts_with('-')
                && name
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || b"_+.-".contains(&byte)),
            "native library {name:?} must be a plain library name"
        );
    }
    for path in &options.objects {
        ensure!(
            path.is_absolute() && path.is_file(),
            "native object {} must be an absolute path to a regular file",
            path.display()
        );
    }
    for path in &options.library_paths {
        ensure!(
            path.is_absolute() && path.is_dir(),
            "native library search path {} must be an absolute directory",
            path.display()
        );
    }
    Ok(())
}

fn link_command(
    options: &NativeLinkOptions,
    object_paths: &[PathBuf],
    output: &Path,
) -> Result<Command> {
    let executable = options.linker.as_deref().unwrap_or_else(|| Path::new("cc"));
    // Resolve PATH before changing the command's working directory; relative
    // PATH entries otherwise acquire a different meaning inside the stage.
    let executable = which::which(executable)
        .with_context(|| format!("find native C linker {}", executable.display()))?;
    let mut command = Command::new(executable);
    command
        .arg("-no-pie")
        .arg("-Wl,-z,noexecstack")
        .arg("-o")
        .arg(output);
    command.args(object_paths);
    command.args(&options.objects);
    for directory in &options.library_paths {
        command.arg("-L").arg(directory);
    }
    for library in &options.libraries {
        command.arg(format!("-l{library}"));
    }
    Ok(command)
}

fn terminate_linker(child: &mut std::process::Child) {
    #[cfg(unix)]
    {
        unsafe extern "C" {
            fn kill(pid: i32, signal: i32) -> i32;
        }
        if let Ok(group) = i32::try_from(child.id()) {
            // SAFETY: process_group(0) created this child's isolated group.
            // Negative pid signals that group, including its linker children.
            unsafe {
                kill(-group, 9);
            }
        }
    }
    let _ = child.kill();
    let _ = child.wait();
}

fn read_diagnostics(path: &Path) -> String {
    let Ok(file) = File::open(path) else {
        return String::new();
    };
    let mut bytes = Vec::new();
    if file
        .take(MAX_DIAGNOSTIC_BYTES + 1)
        .read_to_end(&mut bytes)
        .is_err()
        || bytes.is_empty()
    {
        return String::new();
    }
    let truncated = bytes.len() as u64 > MAX_DIAGNOSTIC_BYTES;
    bytes.truncate(MAX_DIAGNOSTIC_BYTES as usize);
    format!(
        "\n{}{}",
        String::from_utf8_lossy(&bytes),
        if truncated {
            "\n[linker diagnostics truncated]"
        } else {
            ""
        }
    )
}

struct NativeTempDirectory {
    path: PathBuf,
}
impl NativeTempDirectory {
    fn create() -> Result<Self> {
        let parent = fs::canonicalize(std::env::temp_dir())
            .context("resolve native link temporary directory")?;
        for _ in 0..16 {
            let path = parent.join(format!(
                "lanius-native-{}-{:032x}",
                std::process::id(),
                rand::random::<u128>()
            ));
            let mut builder = fs::DirBuilder::new();
            #[cfg(unix)]
            {
                use std::os::unix::fs::DirBuilderExt;
                builder.mode(0o700);
            }
            match builder.create(&path) {
                Ok(()) => return Ok(Self { path }),
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(error).context("create private native link directory"),
            }
        }
        bail!("could not create a unique private native link directory")
    }
}
impl Drop for NativeTempDirectory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}
fn create_private_file(path: &Path) -> Result<File> {
    let mut options = fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    options
        .open(path)
        .with_context(|| format!("create private native link file {}", path.display()))
}
fn write_private_file(path: &Path, bytes: &[u8]) -> Result<()> {
    create_private_file(path)?
        .write_all(bytes)
        .with_context(|| format!("write native ELF object {}", path.display()))
}

#[cfg(test)]
mod tests;
