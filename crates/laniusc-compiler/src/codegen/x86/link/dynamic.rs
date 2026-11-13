//! Rows for the GPU writer of a dynamically linked native C executable.
//!
//! `codegen/x86/elf/dynamic_write.slang` writes the bytes. This module packs
//! the inputs it reads: the dynamic string table, one row per imported
//! function, needed library and version need, and one row per Lanius symbol
//! with its file offset from the GPU section layout. It also mirrors the
//! shader's tail layout to size the output; the shader rejects a mismatch.

use std::collections::BTreeMap;

use anyhow::{Context, Result, bail, ensure};

use super::GpuX86LinkInput;
use crate::codegen::x86::native::NativeDynamicImports;

/// `_start` and its padding at the start of the import object.
pub(crate) const X86_DYNAMIC_START_BYTES: u32 = 40;
/// One `jmp [rip + got]` stub per imported function.
pub(crate) const X86_DYNAMIC_STUB_BYTES: u32 = 8;
const TEXT_OFFSET: u32 = 0x78;
const PROGRAM_HEADERS: u32 = 6;
const SECTIONS: u32 = 15;
const FIXED_DYNAMIC: u32 = 15;
const INTERP_BYTES: u32 = 28;
const STRTAB_PREFIX: u32 = 13;
const SHSTRTAB_BYTES: u32 = 123;
const SYMBOL_ROW_WORDS: usize = 8;
const SECTION_TEXT: u32 = 1;
const SECTION_RODATA: u32 = 2;

/// The C main bridge in the link input's text coordinates.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct X86DynamicMain {
    pub object_index: u32,
    pub text_offset: u32,
    pub byte_len: u32,
}

/// Everything a dynamic link adds to the GPU section link, except the Lanius
/// symbol rows, which need the GPU layout.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct X86DynamicImage {
    strings: Vec<u8>,
    import_rows: Vec<u32>,
    needed_rows: Vec<u32>,
    verneed_rows: Vec<u32>,
    verneed_libraries: u32,
    import_count: u32,
    import_object: u32,
    main: X86DynamicMain,
}

/// Offsets the shader derives from the same counts (`dynamic_layout`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct X86DynamicLayout {
    pub tail: u32,
    pub total: u32,
}

/// One dispatch's inputs: uniform words (page fields left zero) and rows.
pub(super) struct X86DynamicRows {
    pub params: [u32; 24],
    pub words: Vec<u32>,
    pub strings: Vec<u8>,
    pub element_count: u32,
}

fn align_up(value: u64, alignment: u64) -> u64 {
    value.div_ceil(alignment) * alignment
}

fn decimal_digits(value: u32) -> u32 {
    value.checked_ilog10().unwrap_or(0) + 1
}

impl X86DynamicImage {
    /// `import_object` is the index of the stub object the link input
    /// appends after every Lanius object.
    pub(crate) fn new(
        imports: &NativeDynamicImports,
        import_object: u32,
        main: X86DynamicMain,
    ) -> Result<Self> {
        let mut strings = vec![0u8];
        let mut intern = |value: &str| -> Result<u32> {
            ensure!(
                !value.as_bytes().contains(&0),
                "dynamic string {value:?} contains NUL"
            );
            let offset =
                u32::try_from(strings.len()).context("dynamic string table exceeds u32")?;
            strings.extend_from_slice(value.as_bytes());
            strings.push(0);
            Ok(offset)
        };
        let needed_rows = imports
            .needed
            .iter()
            .map(|name| intern(name))
            .collect::<Result<Vec<_>>>()?;
        // Version indices count from 2 in record order: libraries in needed
        // order, each with its distinct version names sorted.
        let mut versions = BTreeMap::<usize, BTreeMap<&str, u32>>::new();
        for import in &imports.imports {
            if let Some((library, version)) = &import.version {
                ensure!(
                    *library < imports.needed.len(),
                    "import version names an absent library"
                );
                versions.entry(*library).or_default().insert(version, 0);
            }
        }
        let mut verneed_rows = Vec::new();
        let mut next_index = 2u32;
        let library_count = versions.len();
        for (position, (library, names)) in versions.iter_mut().enumerate() {
            let last_library = position + 1 == library_count;
            verneed_rows.extend_from_slice(&[
                u32::from(last_library) << 1,
                names.len() as u32,
                needed_rows[*library],
                0,
            ]);
            let count = names.len();
            for (index, (name, assigned)) in names.iter_mut().enumerate() {
                *assigned = next_index;
                verneed_rows.extend_from_slice(&[
                    1 | (u32::from(index + 1 == count) << 1),
                    next_index,
                    intern(name)?,
                    0,
                ]);
                next_index = next_index
                    .checked_add(1)
                    .context("version index overflows")?;
            }
        }
        ensure!(
            next_index <= 0x7fff,
            "too many symbol versions for .gnu.version"
        );
        let mut import_rows = Vec::with_capacity(imports.imports.len() * 2);
        for import in &imports.imports {
            let version = match &import.version {
                Some((library, version)) => versions[library][version.as_str()],
                None => 1,
            };
            import_rows.extend_from_slice(&[intern(&import.name)?, version]);
        }
        Ok(Self {
            strings,
            import_rows,
            needed_rows,
            verneed_rows,
            verneed_libraries: library_count as u32,
            import_count: u32::try_from(imports.imports.len())
                .context("import count exceeds u32")?,
            import_object,
            main,
        })
    }

    pub(crate) fn import_text_len(import_count: usize) -> Result<u32> {
        u32::try_from(import_count)
            .ok()
            .and_then(|count| count.checked_mul(X86_DYNAMIC_STUB_BYTES))
            .and_then(|stubs| stubs.checked_add(X86_DYNAMIC_START_BYTES))
            .context("dynamic import stubs exceed u32")
    }

    /// Defined Lanius symbols, in input order, and the strtab name stride.
    fn symbols(&self, input: &GpuX86LinkInput) -> (Vec<usize>, u32) {
        let mut stride = 1;
        let mut symbols = Vec::new();
        for (index, symbol) in input.symbols.iter().enumerate() {
            if symbol.section == 0 || symbol.object_index == self.import_object {
                continue;
            }
            let [a, b, c] = symbol.identity;
            stride = stride
                .max(9 + decimal_digits(a) + 1 + decimal_digits(b) + 1 + decimal_digits(c) + 1);
            symbols.push(index);
        }
        (symbols, stride)
    }

    /// The length of the executable this image completes.
    pub(crate) fn output_len(&self, input: &GpuX86LinkInput) -> Result<usize> {
        Ok(self.layout(input)?.total as usize)
    }

    /// The shader's `dynamic_layout`, from the same counts.
    pub(super) fn layout(&self, input: &GpuX86LinkInput) -> Result<X86DynamicLayout> {
        let (symbols, stride) = self.symbols(input);
        let n = u64::from(self.import_count);
        let rodata_end =
            u64::from(TEXT_OFFSET) + input.text_len() as u64 + input.rodata_len() as u64;
        let tail = align_up(rodata_end, 8);
        let interp = tail + u64::from(PROGRAM_HEADERS) * 56;
        let hash = align_up(interp + u64::from(INTERP_BYTES), 8);
        let dynsym = align_up(hash + 4 * (n + 4), 8);
        let dynstr = dynsym + 24 * (n + 1);
        let versym = align_up(dynstr + self.strings.len() as u64, 2);
        let verneed = align_up(versym + 2 * (n + 1), 8);
        let rela = verneed + 16 * (self.verneed_rows.len() as u64 / 4);
        let rx_end = rela + 24 * n;
        let rw = align_up(rx_end, 4096);
        let got = rw + 16 * (self.needed_rows.len() as u64 + u64::from(FIXED_DYNAMIC));
        let symtab = align_up(got + 8 * n, 8);
        let strtab = symtab + 24 * (3 + symbols.len() as u64);
        let shstrtab = strtab + u64::from(STRTAB_PREFIX) + symbols.len() as u64 * u64::from(stride);
        let sh = align_up(shstrtab + u64::from(SHSTRTAB_BYTES), 8);
        let total = sh + 64 * u64::from(SECTIONS);
        Ok(X86DynamicLayout {
            tail: u32::try_from(tail).context("dynamic executable exceeds the 32-bit ELF model")?,
            total: u32::try_from(total)
                .context("dynamic executable exceeds the 32-bit ELF model")?,
        })
    }

    /// Rows for `dynamic_write.slang`, with Lanius symbol file offsets from
    /// the GPU section layout.
    pub(super) fn rows(
        &self,
        input: &GpuX86LinkInput,
        object_bases: &[[u32; 2]],
    ) -> Result<X86DynamicRows> {
        let layout = self.layout(input)?;
        let (symbols, stride) = self.symbols(input);
        let text_len = u32::try_from(input.text_len()).context("x86 text exceeds u32")?;
        let rodata_len = u32::try_from(input.rodata_len()).context("x86 rodata exceeds u32")?;
        let base = |object: u32, section: u32| -> Result<u32> {
            let bases = object_bases
                .get(object as usize)
                .context("dynamic link names an absent object")?;
            Ok(match section {
                SECTION_TEXT => TEXT_OFFSET + bases[0],
                SECTION_RODATA => TEXT_OFFSET + text_len + bases[1],
                _ => bail!("dynamic link symbol has section {section}"),
            })
        };
        let mut words = Vec::with_capacity(
            self.import_rows.len()
                + self.needed_rows.len()
                + self.verneed_rows.len()
                + symbols.len() * SYMBOL_ROW_WORDS,
        );
        let import_rows = 0u32;
        words.extend_from_slice(&self.import_rows);
        let needed_rows = words.len() as u32;
        words.extend_from_slice(&self.needed_rows);
        let verneed_rows = words.len() as u32;
        words.extend_from_slice(&self.verneed_rows);
        let symbol_rows = words.len() as u32;
        for index in symbols.iter().copied() {
            let symbol = &input.symbols[index];
            let offset = base(symbol.object_index, symbol.section)?
                .checked_add(symbol.offset)
                .context("dynamic link symbol offset exceeds u32")?;
            let [a, b, c] = symbol.identity;
            words.extend_from_slice(&[offset, symbol.size, symbol.section, a, b, c, 0, 0]);
        }
        let start_offset = base(self.import_object, SECTION_TEXT)?;
        let main_offset = base(self.main.object_index, SECTION_TEXT)?
            .checked_add(self.main.text_offset)
            .context("dynamic main bridge offset exceeds u32")?;
        let import_text = Self::import_text_len(self.import_count as usize)?;
        let element_count = TEXT_OFFSET
            .checked_add(import_text)
            .and_then(|count| count.checked_add(layout.total - layout.tail))
            .context("dynamic writer element count exceeds u32")?;
        let params = [
            0,
            0,
            TEXT_OFFSET + text_len + rodata_len,
            start_offset,
            main_offset,
            self.import_count,
            self.needed_rows.len() as u32,
            (self.verneed_rows.len() / 4) as u32,
            self.verneed_libraries,
            self.strings.len() as u32,
            symbols.len() as u32,
            stride,
            text_len,
            rodata_len,
            layout.total,
            element_count,
            import_rows,
            needed_rows,
            verneed_rows,
            symbol_rows,
            self.main.byte_len,
            0,
            0,
            0,
        ];
        Ok(X86DynamicRows {
            params,
            words,
            strings: self.strings.clone(),
            element_count,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::codegen::x86::native::resolve::NativeImport;

    #[test]
    fn version_needs_group_by_library_and_number_from_two() {
        let imports = NativeDynamicImports {
            needed: vec!["libm.so.6".into(), "libc.so.6".into()],
            imports: vec![
                NativeImport {
                    name: "__libc_start_main".into(),
                    version: Some((1, "GLIBC_2.34".into())),
                },
                NativeImport {
                    name: "cos".into(),
                    version: Some((0, "GLIBC_2.2.5".into())),
                },
                NativeImport {
                    name: "puts".into(),
                    version: Some((1, "GLIBC_2.2.5".into())),
                },
                NativeImport {
                    name: "plain".into(),
                    version: None,
                },
            ],
        };
        let main = X86DynamicMain {
            object_index: 0,
            text_offset: 0,
            byte_len: 1,
        };
        let image = X86DynamicImage::new(&imports, 1, main).unwrap();
        assert_eq!(image.verneed_libraries, 2);
        // libm: one need, one aux; libc: one need (last), two aux.
        let kinds = image
            .verneed_rows
            .chunks(4)
            .map(|row| row[0])
            .collect::<Vec<_>>();
        assert_eq!(kinds, [0, 1 | 2, 2, 1, 1 | 2]);
        let versions = image
            .import_rows
            .chunks(2)
            .map(|row| row[1])
            .collect::<Vec<_>>();
        // libm GLIBC_2.2.5 = 2, libc GLIBC_2.2.5 = 3, libc GLIBC_2.34 = 4.
        assert_eq!(versions, [4, 2, 3, 1]);
        let name = |offset: u32| {
            let tail = &image.strings[offset as usize..];
            std::str::from_utf8(&tail[..tail.iter().position(|byte| *byte == 0).unwrap()]).unwrap()
        };
        assert_eq!(name(image.needed_rows[1]), "libc.so.6");
        assert_eq!(name(image.import_rows[2]), "cos");
    }
}
