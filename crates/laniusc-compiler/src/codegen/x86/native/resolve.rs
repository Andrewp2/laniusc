//! Shared-library resolution for the GPU-emitted dynamic executable.
//!
//! This reads system inputs only: it finds each `-l` library the way the GNU
//! linker does, follows GNU ld scripts, reads each shared object's SONAME and
//! dynamic symbol table, and picks the library and default symbol version that
//! defines every imported C function. Layout and byte emission are GPU work.
//!
//! Inputs this module cannot model exactly go to the C driver. Each such case
//! returns `NativeResolution::Driver` with the rule that applied:
//! - a caller-chosen linker driver;
//! - an explicit input that is not an x86-64 shared object (a relocatable
//!   object, an archive, a linker script);
//! - a library found only outside the GNU linker's default search path, or one
//!   the C driver's private directories also provide;
//! - an archive that defines a symbol still unresolved at its place in the
//!   link, so the static linker would extract a member of it;
//! - an archive without a symbol index, a thin archive, or a linker script
//!   command other than `OUTPUT_FORMAT`, `OUTPUT_ARCH`, `GROUP`, `INPUT` and
//!   `AS_NEEDED` naming absolute paths or `-l` libraries;
//! - a shared object without section headers or a dynamic symbol table.

use std::{
    collections::{BTreeMap, HashMap},
    fs::File,
    os::unix::fs::FileExt,
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
};

use anyhow::{Context, Result, bail, ensure};

use super::NativeLinkOptions;

/// The glibc entry the GPU-emitted `_start` calls with the C main bridge.
pub(crate) const LIBC_START_MAIN: &str = "__libc_start_main";

/// The GNU linker's default search directories on x86-64 Linux, in order
/// (`ld --verbose`, SEARCH_DIR).
const STANDARD_DIRECTORIES: &[&str] = &[
    "/usr/local/lib/x86_64-linux-gnu",
    "/lib/x86_64-linux-gnu",
    "/usr/lib/x86_64-linux-gnu",
    "/usr/lib/x86_64-linux-gnu64",
    "/usr/local/lib64",
    "/lib64",
    "/usr/lib64",
    "/usr/local/lib",
    "/lib",
    "/usr/lib",
    "/usr/x86_64-linux-gnu/lib64",
    "/usr/x86_64-linux-gnu/lib",
];
/// The C driver searches its private library directories before the linker's
/// defaults. A library found there links as the driver chooses it.
const DRIVER_PRIVATE_ROOT: &str = "/usr/lib/gcc/x86_64-linux-gnu";
const MAX_LINKER_SCRIPT_BYTES: u64 = 64 * 1024;
const MAX_SCRIPT_DEPTH: usize = 8;
const MAX_TABLE_BYTES: u64 = 256 * 1024 * 1024;

/// One imported C function: its name and the default version that the
/// defining library gives it, as (needed-library index, version name).
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct NativeImport {
    pub name: String,
    pub version: Option<(usize, String)>,
}

/// The dynamic-link inventory of one program: the libraries it needs, in
/// link order, and every imported function. Imports are sorted by name, except
/// that `__libc_start_main` is always the first.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct NativeDynamicImports {
    pub needed: Vec<String>,
    pub imports: Vec<NativeImport>,
}

#[derive(Debug)]
pub(crate) enum NativeResolution {
    Dynamic(NativeDynamicImports),
    Driver(String),
}

/// A shared object's soname and the default-version definitions of the
/// requested names it exports.
struct SharedDefinitions {
    soname: String,
    defined: Vec<(usize, Option<String>)>,
}

/// Every exported name of one shared object with its default version, or
/// the reason its version is unreadable. The first export of a name wins.
struct SharedTable {
    soname: Option<String>,
    exports: HashMap<String, std::result::Result<Option<String>, String>>,
}

/// What this process last read from one system input, valid while the
/// file's identity, size and modification time are unchanged. These are
/// system inputs, not compile results.
struct CachedInput {
    stamp: (u64, u64, u64, std::time::SystemTime),
    kind: InputKind,
    shared: Option<Arc<SharedTable>>,
    archive: Option<Arc<Option<Vec<String>>>>,
    packed: Option<Arc<PackedTable>>,
}

static INPUTS: Mutex<Option<HashMap<PathBuf, CachedInput>>> = Mutex::new(None);

fn stamp(path: &Path) -> Result<(u64, u64, u64, std::time::SystemTime)> {
    use std::os::unix::fs::MetadataExt;
    let metadata =
        std::fs::metadata(path).with_context(|| format!("open native input {}", path.display()))?;
    Ok((metadata.dev(), metadata.ino(), metadata.len(), metadata.modified()?))
}

/// Runs `with` on the cached entry of `path`, reading the file's kind again
/// when it changed.
fn cached_input<T>(path: &Path, with: impl FnOnce(&mut CachedInput) -> Result<T>) -> Result<T> {
    let stamp = stamp(path)?;
    let mut inputs = INPUTS.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
    let inputs = inputs.get_or_insert_with(HashMap::new);
    if inputs.get(path).is_none_or(|entry| entry.stamp != stamp) {
        let kind = read_input_kind(path)?;
        inputs.insert(
            path.to_path_buf(),
            CachedInput { stamp, kind, shared: None, archive: None, packed: None },
        );
    }
    with(inputs.get_mut(path).expect("cached input"))
}

#[derive(Clone, Copy)]
enum InputKind {
    Shared,
    Archive,
    Script,
    Other,
}

struct Resolver<'a> {
    wanted: HashMap<&'a str, usize>,
    names: Vec<&'a str>,
    /// Defining library (index into `needed`) and version per wanted name.
    resolved: Vec<Option<(usize, Option<String>)>>,
    needed: Vec<String>,
    search: Vec<PathBuf>,
}

/// Resolve `names` (distinct C function names) against the request's shared
/// libraries and the C driver's implicit `-lc`. An `Err` is a diagnostic: an
/// unresolved symbol or an unreadable input.
pub(crate) fn resolve_native_imports(
    names: &[&str],
    options: &NativeLinkOptions,
) -> Result<NativeResolution> {
    if options.linker.is_some() {
        return Ok(NativeResolution::Driver(
            "the request names its own C linker driver".into(),
        ));
    }
    let mut all = vec![LIBC_START_MAIN];
    all.extend(
        names
            .iter()
            .copied()
            .filter(|name| *name != LIBC_START_MAIN),
    );
    all[1..].sort_unstable();
    all.dedup();
    let mut resolver = Resolver {
        wanted: all
            .iter()
            .enumerate()
            .map(|(index, name)| (*name, index))
            .collect(),
        resolved: vec![None; all.len()],
        names: all,
        needed: Vec::new(),
        search: options
            .library_paths
            .iter()
            .cloned()
            .chain(STANDARD_DIRECTORIES.iter().map(PathBuf::from))
            .collect(),
    };
    for object in &options.objects {
        match input_kind(object)? {
            InputKind::Shared => resolver.shared(object, object.to_string_lossy().into_owned())?,
            _ => {
                return Ok(NativeResolution::Driver(format!(
                    "native object {} is not a shared library",
                    object.display()
                )));
            }
        }
    }
    for library in options.libraries.iter().map(String::as_str).chain(["c"]) {
        if let Some(reason) = walk_library(&mut resolver, library, 0)? {
            return Ok(NativeResolution::Driver(reason));
        }
    }
    let unresolved = resolver
        .names
        .iter()
        .zip(&resolver.resolved)
        .filter(|(_, resolved)| resolved.is_none())
        .map(|(name, _)| *name)
        .collect::<Vec<_>>();
    if !unresolved.is_empty() {
        return Err(super::NativeLinkerFailed {
            status: "unresolved symbols".into(),
            diagnostics: unresolved
                .iter()
                .map(|name| format!("\nundefined symbol: {name}"))
                .collect(),
        }
        .into());
    }
    // As the driver's default --as-needed does, a library is needed only when
    // it is the first to define an imported symbol.
    let mut used = BTreeMap::new();
    for (library, _) in resolver.resolved.iter().flatten() {
        used.insert(*library, 0);
    }
    let mut needed = Vec::with_capacity(used.len());
    for (library, index) in &mut used {
        *index = needed.len();
        needed.push(resolver.needed[*library].clone());
    }
    let imports = resolver
        .names
        .iter()
        .zip(resolver.resolved)
        .map(|(name, resolved)| {
            let (library, version) = resolved.expect("every import is resolved");
            NativeImport {
                name: (*name).to_owned(),
                version: version.map(|version| (used[&library], version)),
            }
        })
        .collect();
    Ok(NativeResolution::Dynamic(NativeDynamicImports {
        needed,
        imports,
    }))
}

/// Visits the inputs of a link in the GNU linker's order ([`walk_library`]).
trait InputVisitor {
    fn search(&self) -> &[PathBuf];
    fn shared(&mut self, path: &Path, soname: String) -> Result<()>;
    /// Returns a driver-fallback reason when one applies.
    fn archive(&mut self, path: &Path) -> Result<Option<String>>;
    /// Every file the walk opens: a library, an archive or a linker script.
    fn input(&mut self, _path: &Path) {}
    /// Every library file name the search looked up and did not find.
    fn absent(&mut self, _path: &Path) {}
}

impl InputVisitor for Resolver<'_> {
    fn search(&self) -> &[PathBuf] {
        &self.search
    }

    fn shared(&mut self, path: &Path, soname: String) -> Result<()> {
        let definitions = shared_definitions(path, &self.wanted, soname)
            .with_context(|| format!("read shared library {}", path.display()))?;
        let library = self.needed.len();
        self.needed.push(definitions.soname);
        for (index, version) in definitions.defined {
            if self.resolved[index].is_none() {
                self.resolved[index] = Some((library, version));
            }
        }
        Ok(())
    }

    /// The static linker extracts an archive member only for a symbol still
    /// undefined where the archive appears.
    fn archive(&mut self, path: &Path) -> Result<Option<String>> {
        if !self.resolved.iter().any(Option::is_none) {
            return Ok(None);
        }
        let symbols = archive_symbols(path)?;
        let Some(symbols) = symbols.as_ref() else {
            return Ok(Some(format!(
                "archive {} has no symbol index",
                path.display()
            )));
        };
        for symbol in symbols {
            if let Some(&index) = self.wanted.get(symbol.as_str())
                && self.resolved[index].is_none()
            {
                return Ok(Some(format!(
                    "archive {} defines {symbol}, which needs the static linker",
                    path.display()
                )));
            }
        }
        Ok(None)
    }
}

/// Resolve `-lname`. Returns a driver-fallback reason when one applies.
fn walk_library(visitor: &mut impl InputVisitor, name: &str, depth: usize) -> Result<Option<String>> {
    if driver_private_library(name) {
        return Ok(Some(format!(
            "library -l{name} is in the C driver's private directories"
        )));
    }
    let files = [format!("lib{name}.so"), format!("lib{name}.a")];
    let mut found = None;
    let mut directory = 0;
    while found.is_none() && directory < visitor.search().len() {
        for file in &files {
            let path = visitor.search()[directory].join(file);
            if path.is_file() {
                found = Some(path);
                break;
            }
            visitor.absent(&path);
        }
        directory += 1;
    }
    let Some(path) = found else {
        return Ok(Some(format!(
            "library -l{name} is not on the linker's default search path"
        )));
    };
    let soname = path
        .file_name()
        .expect("library file name")
        .to_string_lossy()
        .into_owned();
    walk_input(visitor, &path, soname, depth)
}

fn walk_input(visitor: &mut impl InputVisitor, path: &Path, soname: String, depth: usize) -> Result<Option<String>> {
    visitor.input(path);
    match input_kind(path)? {
        InputKind::Shared => {
            visitor.shared(path, soname)?;
            Ok(None)
        }
        InputKind::Archive => visitor.archive(path),
        InputKind::Script => walk_script(visitor, path, depth),
        InputKind::Other => Ok(Some(format!(
            "native input {} is neither a shared library, an archive nor a linker script",
            path.display()
        ))),
    }
}

fn walk_script(visitor: &mut impl InputVisitor, path: &Path, depth: usize) -> Result<Option<String>> {
    if depth >= MAX_SCRIPT_DEPTH {
        return Ok(Some(format!(
            "linker script {} nests too deeply",
            path.display()
        )));
    }
    let length = std::fs::metadata(path)?.len();
    ensure!(
        length <= MAX_LINKER_SCRIPT_BYTES,
        "linker script {} exceeds {MAX_LINKER_SCRIPT_BYTES} bytes",
        path.display()
    );
    let text = std::fs::read_to_string(path)
        .with_context(|| format!("read linker script {}", path.display()))?;
    let entries = match script_inputs(&text) {
        Ok(entries) => entries,
        Err(reason) => {
            return Ok(Some(format!("linker script {}: {reason}", path.display())));
        }
    };
    for entry in entries {
        let reason = match entry.strip_prefix("-l") {
            Some(name) => walk_library(visitor, name, depth + 1)?,
            None => {
                let entry = PathBuf::from(entry);
                let soname = entry.to_string_lossy().into_owned();
                walk_input(visitor, &entry, soname, depth + 1)?
            }
        };
        if reason.is_some() {
            return Ok(reason);
        }
    }
    Ok(None)
}

/// The files a native link of one request reads, for a build tool that
/// decides whether the executable is current. The executable is current
/// while every file in `inputs` is unchanged and no path in `absent_paths`
/// exists.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct NativeLinkDependencies {
    /// The request's native objects and every shared library, archive and
    /// linker script that the library search above selects, as canonical
    /// paths, sorted. The implicit C library is included.
    pub inputs: Vec<PathBuf>,
    /// Library file names the search looked up in an earlier directory and
    /// did not find, sorted. A file created at one of them replaces the
    /// library found later.
    pub absent_paths: Vec<PathBuf>,
    /// `-l` names this search does not locate: a library in the C driver's
    /// private directories, one off the search path, or one whose linker
    /// script it cannot follow. The C driver chooses their files, and
    /// `inputs` does not list them. The C driver's startup objects are not
    /// listed either.
    pub unlocated_libraries: Vec<String>,
}

struct Lister {
    search: Vec<PathBuf>,
    dependencies: NativeLinkDependencies,
}

impl InputVisitor for Lister {
    fn search(&self) -> &[PathBuf] {
        &self.search
    }

    fn shared(&mut self, _path: &Path, _soname: String) -> Result<()> {
        Ok(())
    }

    fn archive(&mut self, _path: &Path) -> Result<Option<String>> {
        Ok(None)
    }

    fn input(&mut self, path: &Path) {
        self.dependencies.inputs.push(path.to_path_buf());
    }

    fn absent(&mut self, path: &Path) {
        self.dependencies.absent_paths.push(path.to_path_buf());
    }
}

/// Lists the files a native link of `options` reads. It runs the library
/// search of this module again and reads no symbol table.
pub fn native_link_dependencies(options: &NativeLinkOptions) -> NativeLinkDependencies {
    let mut lister = Lister {
        search: options
            .library_paths
            .iter()
            .cloned()
            .chain(STANDARD_DIRECTORIES.iter().map(PathBuf::from))
            .collect(),
        dependencies: NativeLinkDependencies::default(),
    };
    for object in &options.objects {
        lister.input(object);
    }
    for library in options.libraries.iter().map(String::as_str).chain(["c"]) {
        if !matches!(walk_library(&mut lister, library, 0), Ok(None)) {
            lister.dependencies.unlocated_libraries.push(library.to_owned());
        }
    }
    let mut dependencies = lister.dependencies;
    for input in &mut dependencies.inputs {
        if let Ok(canonical) = std::fs::canonicalize(&*input) {
            *input = canonical;
        }
    }
    dependencies.inputs.sort_unstable();
    dependencies.inputs.dedup();
    dependencies.absent_paths.sort_unstable();
    dependencies.absent_paths.dedup();
    dependencies.unlocated_libraries.sort_unstable();
    dependencies.unlocated_libraries.dedup();
    dependencies
}

/// One input's names for the resident link's GPU name match
/// (`shaders/codegen/x86/link/resident_linking/resident_c_name_lookup.slang`), built once per
/// version of the file: a system input, like the tables it comes from.
pub(crate) struct PackedTable {
    /// Export names, then version names, without terminators.
    pub bytes: Vec<u8>,
    /// Per row: byte offset, length and code ([`PACKED_ARCHIVE`],
    /// [`PACKED_ERROR`], 0 for an unversioned export, else 1 + its version).
    /// An archive without a symbol index has one row of length `u32::MAX`.
    pub rows: Vec<u32>,
    /// Per version: byte offset and length, sorted by name.
    pub versions: Vec<u32>,
}

pub(crate) const PACKED_ERROR: u32 = u32::MAX;
pub(crate) const PACKED_ARCHIVE: u32 = u32::MAX - 1;

/// A link input in the GNU linker's order.
pub(crate) struct PackedInput {
    /// The soname of a shared object; `None` for an archive.
    pub soname: Option<String>,
    pub table: Arc<PackedTable>,
}

pub(crate) enum PackedInputs {
    Inputs(Vec<PackedInput>),
    Driver(String),
}

struct Packer {
    search: Vec<PathBuf>,
    inputs: Vec<PackedInput>,
}

impl InputVisitor for Packer {
    fn search(&self) -> &[PathBuf] {
        &self.search
    }

    fn shared(&mut self, path: &Path, soname: String) -> Result<()> {
        let table = shared_table(path).with_context(|| format!("read shared library {}", path.display()))?;
        let packed = cached_input(path, |entry| {
            Ok(entry.packed.get_or_insert_with(|| Arc::new(pack_shared(&table))).clone())
        })?;
        self.inputs.push(PackedInput { soname: Some(table.soname.clone().unwrap_or(soname)), table: packed });
        Ok(())
    }

    fn archive(&mut self, path: &Path) -> Result<Option<String>> {
        let symbols = archive_symbols(path)?;
        let packed = cached_input(path, |entry| {
            Ok(entry.packed.get_or_insert_with(|| Arc::new(pack_archive(symbols.as_ref().as_deref()))).clone())
        })?;
        self.inputs.push(PackedInput { soname: None, table: packed });
        Ok(None)
    }
}

fn pack_shared(table: &SharedTable) -> PackedTable {
    let mut versions = table
        .exports
        .values()
        .filter_map(|version| version.as_ref().ok()?.as_deref())
        .collect::<Vec<_>>();
    versions.sort_unstable();
    versions.dedup();
    let mut bytes = Vec::new();
    let mut rows = Vec::with_capacity(table.exports.len() * 3);
    for (name, version) in &table.exports {
        let code = match version {
            Err(_) => PACKED_ERROR,
            Ok(None) => 0,
            Ok(Some(version)) => versions.binary_search(&version.as_str()).expect("listed version") as u32 + 1,
        };
        rows.extend_from_slice(&[bytes.len() as u32, name.len() as u32, code]);
        bytes.extend_from_slice(name.as_bytes());
    }
    let mut version_rows = Vec::with_capacity(versions.len() * 2);
    for version in versions {
        version_rows.extend_from_slice(&[bytes.len() as u32, version.len() as u32]);
        bytes.extend_from_slice(version.as_bytes());
    }
    PackedTable { bytes, rows, versions: version_rows }
}

fn pack_archive(symbols: Option<&[String]>) -> PackedTable {
    let Some(symbols) = symbols else {
        return PackedTable { bytes: Vec::new(), rows: vec![0, u32::MAX, PACKED_ARCHIVE], versions: Vec::new() };
    };
    let mut bytes = Vec::new();
    let mut rows = Vec::with_capacity(symbols.len() * 3);
    for symbol in symbols {
        rows.extend_from_slice(&[bytes.len() as u32, symbol.len() as u32, PACKED_ARCHIVE]);
        bytes.extend_from_slice(symbol.as_bytes());
    }
    PackedTable { bytes, rows, versions: Vec::new() }
}

/// The inputs a dynamic link reads, in the GNU linker's order, packed for
/// the GPU name match; `Driver` when the C driver links instead, for any
/// program. `resolve_native_imports` makes the same walk for given names.
pub(crate) fn packed_link_inputs(options: &NativeLinkOptions) -> Result<PackedInputs> {
    if options.linker.is_some() {
        return Ok(PackedInputs::Driver("the request names its own C linker driver".into()));
    }
    let mut packer = Packer {
        search: options
            .library_paths
            .iter()
            .cloned()
            .chain(STANDARD_DIRECTORIES.iter().map(PathBuf::from))
            .collect(),
        inputs: Vec::new(),
    };
    for object in &options.objects {
        match input_kind(object)? {
            InputKind::Shared => packer.shared(object, object.to_string_lossy().into_owned())?,
            _ => {
                return Ok(PackedInputs::Driver(format!(
                    "native object {} is not a shared library",
                    object.display()
                )));
            }
        }
    }
    for library in options.libraries.iter().map(String::as_str).chain(["c"]) {
        if let Some(reason) = walk_library(&mut packer, library, 0)? {
            return Ok(PackedInputs::Driver(reason));
        }
    }
    Ok(PackedInputs::Inputs(packer.inputs))
}

fn driver_private_library(name: &str) -> bool {
    let Ok(versions) = std::fs::read_dir(DRIVER_PRIVATE_ROOT) else {
        return false;
    };
    versions.flatten().any(|version| {
        ["so", "a"].iter().any(|extension| {
            version
                .path()
                .join(format!("lib{name}.{extension}"))
                .exists()
        })
    })
}

fn input_kind(path: &Path) -> Result<InputKind> {
    cached_input(path, |entry| Ok(entry.kind))
}

fn read_input_kind(path: &Path) -> Result<InputKind> {
    let file = File::open(path).with_context(|| format!("open native input {}", path.display()))?;
    let mut magic = [0u8; 20];
    let length = read_prefix(&file, &mut magic)?;
    let magic = &magic[..length];
    if magic.starts_with(b"\x7fELF") {
        let shared = magic.len() >= 20
            && magic[4] == 2
            && magic[5] == 1
            && u16::from_le_bytes([magic[16], magic[17]]) == 3
            && u16::from_le_bytes([magic[18], magic[19]]) == 62;
        return Ok(if shared {
            InputKind::Shared
        } else {
            InputKind::Other
        });
    }
    if magic.starts_with(b"!<arch>\n") {
        return Ok(InputKind::Archive);
    }
    if magic.is_ascii() && !magic.is_empty() {
        return Ok(InputKind::Script);
    }
    Ok(InputKind::Other)
}

fn read_prefix(file: &File, buffer: &mut [u8]) -> Result<usize> {
    let mut length = 0;
    while length < buffer.len() {
        match file.read_at(&mut buffer[length..], length as u64)? {
            0 => break,
            read => length += read,
        }
    }
    Ok(length)
}

/// The inputs a GNU ld script names, in order. AS_NEEDED inputs are listed as
/// others are: every shared input of this link is already as-needed.
fn script_inputs(text: &str) -> std::result::Result<Vec<String>, String> {
    let mut stripped = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(start) = rest.find("/*") {
        stripped.push_str(&rest[..start]);
        let end = rest[start + 2..]
            .find("*/")
            .ok_or_else(|| "unterminated comment".to_string())?;
        stripped.push(' ');
        rest = &rest[start + 2 + end + 2..];
    }
    stripped.push_str(rest);
    let spaced = stripped
        .replace('(', " ( ")
        .replace(')', " ) ")
        .replace(',', " ");
    let mut tokens = spaced.split_whitespace().peekable();
    let mut inputs = Vec::new();
    let mut depth = 0usize;
    while let Some(token) = tokens.next() {
        match token {
            "OUTPUT_FORMAT" | "OUTPUT_ARCH" if depth == 0 => {
                if tokens.next() != Some("(") {
                    return Err(format!("{token} has no argument list"));
                }
                for token in tokens.by_ref() {
                    if token == ")" {
                        break;
                    }
                }
            }
            "GROUP" | "INPUT" | "AS_NEEDED" => {
                if tokens.next() != Some("(") {
                    return Err(format!("{token} has no argument list"));
                }
                depth += 1;
            }
            ")" if depth > 0 => depth -= 1,
            path if depth > 0 && (path.starts_with('/') || path.starts_with("-l")) => {
                inputs.push(path.to_owned())
            }
            other => return Err(format!("unsupported linker script element {other:?}")),
        }
    }
    if depth != 0 {
        return Err("unbalanced parentheses".into());
    }
    Ok(inputs)
}

/// The global symbols an archive's index defines, or `None` for a non-empty
/// archive without an index.
fn archive_symbols(path: &Path) -> Result<Arc<Option<Vec<String>>>> {
    cached_input(path, |entry| {
        if entry.archive.is_none() {
            entry.archive = Some(Arc::new(read_archive_symbols(path)?));
        }
        Ok(entry.archive.clone().expect("archive symbols"))
    })
}

fn read_archive_symbols(path: &Path) -> Result<Option<Vec<String>>> {
    let file = File::open(path)?;
    let length = file.metadata()?.len();
    if length == 8 {
        return Ok(Some(Vec::new()));
    }
    let mut header = [0u8; 60];
    file.read_exact_at(&mut header, 8)
        .with_context(|| format!("read archive member header of {}", path.display()))?;
    let name = &header[..16];
    let wide = name.starts_with(b"/SYM64/");
    if !(wide || name.starts_with(b"/ ")) {
        return Ok(None);
    }
    let size = std::str::from_utf8(&header[48..58])
        .ok()
        .and_then(|size| size.trim().parse::<u64>().ok())
        .context("archive symbol index size is malformed")?;
    ensure!(
        size <= MAX_TABLE_BYTES && 68 + size <= length,
        "archive symbol index exceeds {}",
        path.display()
    );
    let mut table = vec![0u8; size as usize];
    file.read_exact_at(&mut table, 68)?;
    let word = if wide { 8 } else { 4 };
    ensure!(table.len() >= word, "archive symbol index is truncated");
    let count = if wide {
        u64::from_be_bytes(table[..8].try_into().unwrap())
    } else {
        u64::from(u32::from_be_bytes(table[..4].try_into().unwrap()))
    } as usize;
    let names_start = count
        .checked_add(1)
        .and_then(|words| words.checked_mul(word))
        .filter(|&start| start <= table.len())
        .context("archive symbol index count exceeds its table")?;
    let names = table[names_start..]
        .split(|byte| *byte == 0)
        .take(count)
        .map(|name| String::from_utf8_lossy(name).into_owned())
        .collect();
    Ok(Some(names))
}

struct Section {
    kind: u32,
    offset: u64,
    size: u64,
    link: u32,
}

fn read_table(file: &File, section: &Section) -> Result<Vec<u8>> {
    ensure!(
        section.size <= MAX_TABLE_BYTES,
        "shared library table is too large"
    );
    let mut bytes = vec![0u8; section.size as usize];
    file.read_exact_at(&mut bytes, section.offset)?;
    Ok(bytes)
}

fn c_string(table: &[u8], offset: usize) -> Result<&str> {
    let tail = table
        .get(offset..)
        .context("string offset exceeds its table")?;
    let end = tail
        .iter()
        .position(|byte| *byte == 0)
        .context("unterminated string")?;
    std::str::from_utf8(&tail[..end]).context("string is not UTF-8")
}

/// Read the soname and default-version definitions of `wanted` names from
/// one x86-64 ELF shared object.
fn shared_definitions(
    path: &Path,
    wanted: &HashMap<&str, usize>,
    fallback_soname: String,
) -> Result<SharedDefinitions> {
    let table = shared_table(path)?;
    // Definitions in the order of `wanted`'s names, as the symbol table's
    // order does not change which library resolves a name.
    let mut defined = Vec::new();
    for (name, &index) in wanted {
        match table.exports.get(*name) {
            Some(Ok(version)) => defined.push((index, version.clone())),
            Some(Err(reason)) => bail!("{reason}"),
            None => {}
        }
    }
    Ok(SharedDefinitions {
        soname: table.soname.clone().unwrap_or(fallback_soname),
        defined,
    })
}

fn shared_table(path: &Path) -> Result<Arc<SharedTable>> {
    cached_input(path, |entry| {
        if entry.shared.is_none() {
            entry.shared = Some(Arc::new(read_shared_table(path)?));
        }
        Ok(entry.shared.clone().expect("shared table"))
    })
}

fn read_shared_table(path: &Path) -> Result<SharedTable> {
    let file = File::open(path)?;
    let mut header = [0u8; 64];
    file.read_exact_at(&mut header, 0)?;
    let section_offset = u64::from_le_bytes(header[40..48].try_into().unwrap());
    let entry_size = u16::from_le_bytes([header[58], header[59]]) as u64;
    let count = u16::from_le_bytes([header[60], header[61]]) as u64;
    if section_offset == 0 || count == 0 || entry_size != 64 {
        bail!("shared library has no section headers");
    }
    let mut table = vec![0u8; (count * 64) as usize];
    file.read_exact_at(&mut table, section_offset)?;
    let sections = table
        .chunks_exact(64)
        .map(|row| Section {
            kind: u32::from_le_bytes(row[4..8].try_into().unwrap()),
            offset: u64::from_le_bytes(row[24..32].try_into().unwrap()),
            size: u64::from_le_bytes(row[32..40].try_into().unwrap()),
            link: u32::from_le_bytes(row[40..44].try_into().unwrap()),
        })
        .collect::<Vec<_>>();
    let find = |kind: u32| sections.iter().find(|section| section.kind == kind);
    let dynsym = find(11).context("shared library has no dynamic symbol table")?;
    let strings_section = sections
        .get(dynsym.link as usize)
        .context("dynamic symbol table names no string table")?;
    let strings = read_table(&file, strings_section)?;
    let symbols = read_table(&file, dynsym)?;
    let versions = find(0x6fff_ffff)
        .map(|section| read_table(&file, section))
        .transpose()?;
    let mut version_names = HashMap::<u16, Option<String>>::new();
    if let Some(verdef) = find(0x6fff_fffd) {
        let bytes = read_table(&file, verdef)?;
        let verdef_strings = read_table(
            &file,
            sections
                .get(verdef.link as usize)
                .context("version table names no strings")?,
        )?;
        let mut offset = 0usize;
        loop {
            let record = bytes
                .get(offset..offset + 20)
                .context("version definition is truncated")?;
            let flags = u16::from_le_bytes([record[2], record[3]]);
            let index = u16::from_le_bytes([record[4], record[5]]);
            let aux = u32::from_le_bytes(record[12..16].try_into().unwrap()) as usize;
            let next = u32::from_le_bytes(record[16..20].try_into().unwrap()) as usize;
            let name_offset = bytes
                .get(offset + aux..offset + aux + 4)
                .context("version definition name is truncated")?;
            let name = c_string(
                &verdef_strings,
                u32::from_le_bytes(name_offset.try_into().unwrap()) as usize,
            )?;
            // The base definition names the library, not a symbol version.
            version_names.insert(index, (flags & 1 == 0).then(|| name.to_owned()));
            if next == 0 {
                break;
            }
            offset += next;
        }
    }
    let mut soname = None;
    if let Some(dynamic) = find(6) {
        let bytes = read_table(&file, dynamic)?;
        for entry in bytes.chunks_exact(16) {
            let tag = u64::from_le_bytes(entry[..8].try_into().unwrap());
            if tag == 0 {
                break;
            }
            if tag == 14 {
                let value = u64::from_le_bytes(entry[8..].try_into().unwrap()) as usize;
                soname = Some(c_string(&strings, value)?.to_owned());
            }
        }
    }
    let mut exports = HashMap::new();
    for (index, symbol) in symbols.chunks_exact(24).enumerate().skip(1) {
        let section = u16::from_le_bytes([symbol[6], symbol[7]]);
        let binding = symbol[4] >> 4;
        let visibility = symbol[5] & 3;
        if section == 0 || !matches!(binding, 1 | 2 | 10) || matches!(visibility, 1 | 2) {
            continue;
        }
        let name = c_string(
            &strings,
            u32::from_le_bytes(symbol[..4].try_into().unwrap()) as usize,
        )?;
        let version = match &versions {
            Some(versions) => {
                let Some(raw) = versions.get(index * 2..index * 2 + 2) else {
                    record(&mut exports, name, Err("symbol version table is truncated".into()));
                    continue;
                };
                let raw = u16::from_le_bytes([raw[0], raw[1]]);
                // A hidden version is not the default an unversioned
                // reference binds to; a local one is not exported.
                if raw & 0x8000 != 0 || raw == 0 {
                    continue;
                }
                match raw {
                    1 => Ok(None),
                    index => version_names
                        .get(&index)
                        .cloned()
                        .ok_or_else(|| "symbol names an undefined version".to_string()),
                }
            }
            None => Ok(None),
        };
        record(&mut exports, name, version);
    }
    Ok(SharedTable { soname, exports })
}

/// The first export of `name` wins; an unreadable version of any export of
/// it is an error, as reading only the requested names reported it.
fn record(
    exports: &mut HashMap<String, std::result::Result<Option<String>, String>>,
    name: &str,
    version: std::result::Result<Option<String>, String>,
) {
    match exports.get_mut(name) {
        None => {
            exports.insert(name.to_owned(), version);
        }
        Some(entry) => {
            if entry.is_ok() && version.is_err() {
                *entry = version;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dynamic(names: &[&str], libraries: &[&str]) -> NativeDynamicImports {
        let options = NativeLinkOptions {
            libraries: libraries.iter().map(|name| (*name).to_owned()).collect(),
            ..Default::default()
        };
        match resolve_native_imports(names, &options).unwrap() {
            NativeResolution::Dynamic(imports) => imports,
            NativeResolution::Driver(reason) => panic!("unexpected driver fallback: {reason}"),
        }
    }

    #[test]
    fn libc_and_libm_resolve_with_default_versions_and_as_needed_libraries() {
        let imports = dynamic(&["cos", "puts", "exit"], &["m", "dl", "pthread"]);
        assert_eq!(imports.imports[0].name, LIBC_START_MAIN);
        let version = |name: &str| {
            let import = imports
                .imports
                .iter()
                .find(|import| import.name == name)
                .unwrap();
            let (library, version) = import.version.clone().unwrap();
            (imports.needed[library].clone(), version)
        };
        assert_eq!(
            version(LIBC_START_MAIN),
            ("libc.so.6".into(), "GLIBC_2.34".into())
        );
        assert_eq!(version("cos").0, "libm.so.6");
        assert_eq!(version("puts").0, "libc.so.6");
        // libdl.a and libpthread.a are empty, and libmvec defines nothing used.
        assert_eq!(imports.needed, ["libm.so.6", "libc.so.6"]);
    }

    #[test]
    fn unused_libraries_are_not_needed_and_missing_symbols_are_diagnosed() {
        let imports = dynamic(&["puts"], &["m"]);
        assert_eq!(imports.needed, ["libc.so.6"]);
        let error =
            resolve_native_imports(&["lanius_no_such_c_symbol"], &Default::default()).unwrap_err();
        let failed = error
            .downcast_ref::<super::super::NativeLinkerFailed>()
            .unwrap();
        assert!(
            failed
                .diagnostics
                .contains("undefined symbol: lanius_no_such_c_symbol")
        );
    }

    #[test]
    fn static_inputs_and_driver_choices_fall_back_to_the_c_driver() {
        let fallback = |options: NativeLinkOptions, names: &[&str]| {
            matches!(
                resolve_native_imports(names, &options).unwrap(),
                NativeResolution::Driver(_)
            )
        };
        // libc_nonshared.a defines atexit, so the static linker must run.
        assert!(fallback(Default::default(), &["atexit"]));
        assert!(fallback(
            NativeLinkOptions {
                linker: Some("cc".into()),
                ..Default::default()
            },
            &["puts"]
        ));
        assert!(fallback(
            NativeLinkOptions {
                libraries: vec!["lanius_no_such_library".into()],
                ..Default::default()
            },
            &["puts"]
        ));
        let directory = std::env::temp_dir().join(format!("lanius-resolve-{}", std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let object = directory.join("probe.o");
        std::fs::write(
            &object,
            b"\x7fELF\x02\x01\x01\0\0\0\0\0\0\0\0\0\x01\0\x3e\0",
        )
        .unwrap();
        assert!(fallback(
            NativeLinkOptions {
                objects: vec![object],
                ..Default::default()
            },
            &["puts"]
        ));
        std::fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn linker_scripts_accept_only_input_lists() {
        assert_eq!(
            script_inputs(
                "/* c */ OUTPUT_FORMAT(elf64-x86-64)\nGROUP ( /a.so /b.a AS_NEEDED ( /c.so ) -lz )"
            )
            .unwrap(),
            ["/a.so", "/b.a", "/c.so", "-lz"]
        );
        assert!(script_inputs("SEARCH_DIR(/x) GROUP(/a.so)").is_err());
        assert!(script_inputs("GROUP(relative.so)").is_err());
    }
}
