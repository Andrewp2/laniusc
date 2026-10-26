//! ELF packaging for the opt-in Linux x86_64 C-library profile.
//!
//! Machine instructions and the CRT-facing bridge are emitted by the GPU.
//! This module copies those sections unchanged, translates recorded relocation
//! metadata, and delegates ordinary native linking and startup to the system C
//! driver. It neither decodes nor patches generated instructions.

use std::{
    collections::BTreeMap,
    fs::{self, File},
    io::{BufWriter, Read, Seek, SeekFrom, Write},
    path::{Component, Path, PathBuf},
    process::{Command, Stdio},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::{Duration, Instant},
};

use anyhow::{Context, Result, bail, ensure};

use super::{
    GpuX86FileObject,
    GpuX86ObjectSection,
    GpuX86ObjectSymbolRecord,
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
const MAX_RESPONSE_BYTES: u64 = 64 * 1024 * 1024;

type Identity = [u32; 3];

struct NativeSymbols<'a> {
    foreign: BTreeMap<Identity, &'a NativeCFunction>,
}

impl<'a> NativeSymbols<'a> {
    fn validate(
        objects: &[GpuX86FileObject],
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
            main_object.layout.entry_offset.is_some()
                && objects
                    .iter()
                    .filter(|object| object.layout.entry_offset.is_some())
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
            main_end as usize <= main_object.layout.text_byte_len as usize,
            "native main bridge exceeds its object's text section"
        );
        let emitted_bridge = main_object
            .crt_main_bridge_range()
            .map_err(anyhow::Error::msg)?
            .context("native main object has no admitted CRT bridge")?;
        ensure!(
            main.text_offset == emitted_bridge.start && main_end == emitted_bridge.end,
            "native main bridge must exactly match its GPU-emitted versioned trailer"
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
            for relocation in &object.relocations {
                if relocation.target_kind == GpuX86RelocationTargetKind::SectionOffset {
                    relocation
                        .addend
                        .checked_add(i64::from(relocation.target_offset))
                        .context("native ELF relocation addend overflows i64")?;
                }
            }
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
    object: &GpuX86FileObject,
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

/// Validate the complete metadata inventory before streaming unchanged GPU
/// payloads into one ELF file at a time. Only metadata remains resident.
fn emit_native_elf_objects(
    objects: &[GpuX86FileObject],
    bindings: &[NativeCFunction],
    main: NativeMainBridge,
    directory: &NativeTempDirectory,
) -> Result<Vec<PathBuf>> {
    let symbols = NativeSymbols::validate(objects, bindings, main)?;
    let mut paths = Vec::with_capacity(objects.len());
    for (object_index, object) in objects.iter().enumerate() {
        let path = directory.path.join(format!("lanius-{object_index}.o"));
        let mut file = create_private_file(&path)?;
        emit_object(
            object,
            &symbols,
            (object_index == main.object_index).then_some(main),
            &mut file,
        )
        .with_context(|| format!("export native ELF object {object_index}"))?;
        file.flush().context("flush native ELF object")?;
        paths.push(path);
    }
    Ok(paths)
}

fn emit_object<W: Write + Seek>(
    object: &GpuX86FileObject,
    names: &NativeSymbols<'_>,
    main: Option<NativeMainBridge>,
    output: &mut W,
) -> Result<()> {
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
    output.write_all(&[0; ELF_HEADER_BYTES])?;
    let mut sections = [SectionHeader::default(); SECTION_COUNT];
    sections[TEXT as usize] = append_payload_section(
        output,
        object,
        true,
        16,
        SectionHeader {
            name: text_name,
            section_type: 1,
            flags: 6,
            ..Default::default()
        },
    )?;
    sections[RODATA as usize] = append_payload_section(
        output,
        object,
        false,
        1,
        SectionHeader {
            name: rodata_name,
            section_type: 1,
            flags: 2,
            ..Default::default()
        },
    )?;
    sections[RELA_TEXT] = append_section(
        output,
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
        output,
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
        output,
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
        output,
        &strings.bytes,
        1,
        SectionHeader {
            name: strtab_name,
            section_type: 3,
            ..Default::default()
        },
    )?;
    sections[SHSTRTAB] = append_section(
        output,
        &section_names.bytes,
        1,
        SectionHeader {
            name: shstrtab_name,
            section_type: 3,
            ..Default::default()
        },
    )?;
    sections[GNU_STACK] = append_section(
        output,
        &[],
        1,
        SectionHeader {
            name: stack_name,
            section_type: 1,
            ..Default::default()
        },
    )?;
    align_output(output, 8)?;
    let section_header_offset = output.stream_position()?;
    for section in sections {
        let mut row = Vec::with_capacity(SECTION_HEADER_BYTES);
        section.write(&mut row);
        output.write_all(&row)?;
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
    output.seek(SeekFrom::Start(0))?;
    output.write_all(&header)?;
    Ok(())
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

fn append_section<W: Write + Seek>(
    output: &mut W,
    bytes: &[u8],
    align: u64,
    mut header: SectionHeader,
) -> Result<SectionHeader> {
    align_output(output, align)?;
    header.offset = output.stream_position()?;
    header.size = bytes.len() as u64;
    header.align = align;
    output.write_all(bytes)?;
    Ok(header)
}

fn append_payload_section<W: Write + Seek>(
    output: &mut W,
    object: &GpuX86FileObject,
    text: bool,
    align: u64,
    mut header: SectionHeader,
) -> Result<SectionHeader> {
    align_output(output, align)?;
    header.offset = output.stream_position()?;
    header.size = u64::from(if text {
        object.layout.text_byte_len
    } else {
        object.layout.rodata_byte_len
    });
    header.align = align;
    let copied = if text {
        object.copy_text_to(output)
    } else {
        object.copy_rodata_to(output)
    }
    .map_err(anyhow::Error::msg)?;
    ensure!(
        copied == header.size,
        "native GPU payload length changed during export"
    );
    Ok(header)
}

fn align_output<W: Write + Seek>(output: &mut W, align: u64) -> Result<()> {
    let position = output.stream_position()?;
    let padding = (align - position % align) % align;
    position
        .checked_add(padding)
        .context("native ELF alignment overflows")?;
    ensure!(
        padding <= 15,
        "native ELF section alignment exceeds supported padding"
    );
    output.write_all(&[0; 15][..padding as usize])?;
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

/// A private, completed native executable. Its directory stays alive until
/// this guard is dropped. Every read/copy checks the admitted size first.
pub(crate) struct NativeLinkedExecutable {
    directory: NativeTempDirectory,
    byte_len: u64,
    max_output_bytes: u64,
}

impl NativeLinkedExecutable {
    fn open_checked(&self, maximum: u64) -> Result<File> {
        let file = File::open(self.directory.path.join("program"))
            .context("open native linked executable")?;
        let metadata = file.metadata().context("stat native linked executable")?;
        ensure!(
            metadata.is_file(),
            "native linker output is not a regular file"
        );
        ensure!(
            metadata.len() == self.byte_len && self.byte_len != 0 && self.byte_len <= maximum,
            "native linked executable size {} exceeds the admitted range 1..={maximum} or changed after linking",
            metadata.len()
        );
        Ok(file)
    }

    pub(crate) fn read_bytes(&self, maximum: usize) -> Result<Vec<u8>> {
        let maximum = self.max_output_bytes.min(maximum as u64);
        let mut file = self.open_checked(maximum)?;
        let length = usize::try_from(self.byte_len).context("native executable exceeds usize")?;
        let mut bytes = Vec::new();
        bytes
            .try_reserve_exact(length)
            .context("reserve bounded native executable bytes")?;
        bytes.resize(length, 0);
        file.read_exact(&mut bytes)
            .context("read bounded native executable")?;
        self.check_end(&mut file)?;
        Ok(bytes)
    }

    pub(crate) fn write_to<W: Write>(&self, output: &mut W) -> Result<u64> {
        let mut file = self.open_checked(self.max_output_bytes)?;
        let copied = std::io::copy(&mut (&mut file).take(self.byte_len), output)
            .context("copy bounded native executable")?;
        ensure!(
            copied == self.byte_len,
            "native linked executable shrank during copy"
        );
        self.check_end(&mut file)?;
        Ok(copied)
    }

    fn check_end(&self, file: &mut File) -> Result<()> {
        let mut extra = [0; 1];
        ensure!(
            file.read(&mut extra)? == 0 && file.metadata()?.len() == self.byte_len,
            "native linked executable changed during bounded transfer"
        );
        Ok(())
    }
}

/// Link exact GPU-generated file payloads using the system C driver.
/// The non-PIE profile matches the admitted small absolute-address code model.
pub(crate) fn link_native_file_executable(
    objects: &[GpuX86FileObject],
    bindings: &[NativeCFunction],
    main: NativeMainBridge,
    options: &NativeLinkOptions,
) -> Result<NativeLinkedExecutable> {
    ensure!(
        cfg!(all(
            target_os = "linux",
            target_arch = "x86_64",
            target_env = "gnu"
        )),
        "native C linking currently supports Linux x86_64/glibc hosts"
    );
    validate_options(options)?;
    let directory = NativeTempDirectory::create()?;
    let object_paths = emit_native_elf_objects(objects, bindings, main, &directory)?;
    let output_path = directory.path.join("program");
    let response_path = directory.path.join("link.rsp");
    write_link_response(options, &object_paths, &output_path, &response_path)?;
    let diagnostics_path = directory.path.join("link.stderr");
    let diagnostics = create_private_file(&diagnostics_path)?;
    let mut command = link_command(options, &response_path)?;
    command
        .current_dir(&directory.path)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped());
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        command.process_group(0);
    }
    let mut child = command.spawn().context("start native C linker")?;
    let diagnostic_overflow = Arc::new(AtomicBool::new(false));
    let overflow = Arc::clone(&diagnostic_overflow);
    let stderr = child.stderr.take().expect("piped native linker stderr");
    let collector = match thread::Builder::new()
        .name("native-link-diagnostics".into())
        .spawn(move || collect_diagnostics(stderr, diagnostics, &overflow))
    {
        Ok(collector) => collector,
        Err(error) => {
            terminate_linker(&mut child);
            return Err(error).context("start bounded native linker diagnostics");
        }
    };
    let started = Instant::now();
    let status = (|| -> Result<_> {
        loop {
            if diagnostic_overflow.load(Ordering::Relaxed) {
                bail!(
                    "native C linker diagnostics exceeded their {MAX_DIAGNOSTIC_BYTES} byte limit"
                );
            }
            match child.try_wait().context("wait for native C linker")? {
                Some(status) => return Ok(status),
                None => {}
            }
            if let Ok(metadata) = fs::metadata(&output_path) {
                ensure!(
                    metadata.len() <= options.max_output_bytes as u64,
                    "native linked executable exceeds its {} byte output limit",
                    options.max_output_bytes
                );
            }
            if started.elapsed() >= options.timeout {
                bail!(
                    "native C linker exceeded its {} ms timeout{}",
                    options.timeout.as_millis(),
                    read_diagnostics(&diagnostics_path)
                );
            }
            thread::sleep(
                Duration::from_millis(10).min(options.timeout.saturating_sub(started.elapsed())),
            );
        }
    })();
    // A driver can exit while its linker descendants still own stderr/output.
    // End that entire group before joining the bounded stderr reader, including
    // nonzero and successful driver exits as well as watchdog failures.
    terminate_linker(&mut child);
    collector
        .join()
        .map_err(|_| anyhow::anyhow!("native linker diagnostic collector panicked"))??;
    let status = status?;
    ensure!(
        !diagnostic_overflow.load(Ordering::Relaxed),
        "native C linker diagnostics exceeded their {MAX_DIAGNOSTIC_BYTES} byte limit"
    );
    ensure!(
        status.success(),
        "native C linker failed ({status}){}",
        read_diagnostics(&diagnostics_path)
    );
    let metadata = fs::metadata(&output_path).context("stat native linked executable")?;
    ensure!(
        metadata.is_file(),
        "native linker output is not a regular file"
    );
    let byte_len = metadata.len();
    ensure!(
        byte_len != 0 && byte_len <= options.max_output_bytes as u64,
        "native linked executable size {byte_len} exceeds the admitted range 1..={}",
        options.max_output_bytes
    );
    Ok(NativeLinkedExecutable {
        directory,
        byte_len,
        max_output_bytes: options.max_output_bytes as u64,
    })
}

/// Bounded bytes boundary for callers that explicitly request resident output.
pub(crate) fn link_native_executable(
    objects: &[GpuX86FileObject],
    bindings: &[NativeCFunction],
    main: NativeMainBridge,
    options: &NativeLinkOptions,
) -> Result<Vec<u8>> {
    link_native_file_executable(objects, bindings, main, options)?
        .read_bytes(options.max_output_bytes)
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

/// GCC/Clang driver response grammar: each argument is double-quoted;
/// backslash escapes a following quote or backslash. Whitespace stays inside
/// the quotes. Absolute input paths cannot introduce nested @response files.
struct LinkResponse {
    file: BufWriter<File>,
    byte_len: u64,
}

impl LinkResponse {
    fn argument(&mut self, value: &std::ffi::OsStr) -> Result<()> {
        let bytes = value.as_encoded_bytes();
        ensure!(!bytes.contains(&0), "native response argument contains NUL");
        let escaped = bytes
            .iter()
            .filter(|byte| matches!(**byte, b'\\' | b'"'))
            .count();
        let length = (bytes.len() as u64)
            .checked_add(escaped as u64)
            .and_then(|length| length.checked_add(3))
            .and_then(|length| self.byte_len.checked_add(length))
            .context("native link response length overflows")?;
        ensure!(
            length <= MAX_RESPONSE_BYTES,
            "native link response exceeds its {MAX_RESPONSE_BYTES} byte limit"
        );
        self.file.write_all(b"\"")?;
        for &byte in bytes {
            if matches!(byte, b'\\' | b'"') {
                self.file.write_all(b"\\")?;
            }
            self.file.write_all(&[byte])?;
        }
        self.file.write_all(b"\"\n")?;
        self.byte_len = length;
        Ok(())
    }
}

fn write_link_response(
    options: &NativeLinkOptions,
    object_paths: &[PathBuf],
    output: &Path,
    response: &Path,
) -> Result<()> {
    let mut response = LinkResponse {
        file: BufWriter::new(create_private_file(response)?),
        byte_len: 0,
    };
    for option in ["-no-pie", "-Wl,-z,noexecstack", "-o"] {
        response.argument(option.as_ref())?;
    }
    response.argument(output.as_os_str())?;
    for path in object_paths.iter().chain(&options.objects) {
        ensure!(
            path.is_absolute(),
            "native response object path must be absolute"
        );
        response.argument(path.as_os_str())?;
    }
    for directory in &options.library_paths {
        response.argument("-L".as_ref())?;
        response.argument(directory.as_os_str())?;
    }
    for library in &options.libraries {
        response.argument(format!("-l{library}").as_ref())?;
    }
    response.file.flush().context("flush native link response")
}

fn link_command(options: &NativeLinkOptions, response: &Path) -> Result<Command> {
    let executable = options.linker.as_deref().unwrap_or_else(|| Path::new("cc"));
    // Resolve PATH before changing the command's working directory.
    let executable = which::which(executable)
        .with_context(|| format!("find native C linker {}", executable.display()))?;
    let mut command = Command::new(executable);
    let mut argument = std::ffi::OsString::from("@");
    argument.push(response);
    command.arg(argument);
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

fn collect_diagnostics<R: Read>(
    mut input: R,
    mut output: File,
    overflow: &AtomicBool,
) -> Result<()> {
    let mut remaining = MAX_DIAGNOSTIC_BYTES as usize;
    let mut buffer = [0; 8192];
    loop {
        let count = match input.read(&mut buffer) {
            Ok(0) => return Ok(()),
            Ok(count) => count,
            Err(error) if error.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(error) => return Err(error).context("read native linker diagnostics"),
        };
        let retained = remaining.min(count);
        output
            .write_all(&buffer[..retained])
            .context("write bounded native linker diagnostics")?;
        remaining -= retained;
        if retained < count {
            overflow.store(true, Ordering::Relaxed);
        }
        // Drain and discard excess until the watchdog ends the process group.
        // The disk spool itself never exceeds MAX_DIAGNOSTIC_BYTES.
    }
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
#[cfg(test)]
fn write_private_file(path: &Path, bytes: &[u8]) -> Result<()> {
    create_private_file(path)?
        .write_all(bytes)
        .with_context(|| format!("write native ELF object {}", path.display()))
}

#[cfg(test)]
mod tests;
