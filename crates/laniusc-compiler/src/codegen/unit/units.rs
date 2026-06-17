use super::*;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CodegenUnitLimits {
    pub max_source_bytes: usize,
    pub max_source_files: usize,
}

impl Default for CodegenUnitLimits {
    fn default() -> Self {
        Self {
            max_source_bytes: DEFAULT_CODEGEN_UNIT_MAX_SOURCE_BYTES,
            max_source_files: DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES,
        }
    }
}

impl CodegenUnitLimits {
    pub fn normalized(self) -> Self {
        Self {
            max_source_bytes: self.max_source_bytes.max(1),
            max_source_files: self.max_source_files.max(1),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SourceFileUnitInput {
    pub library_id: u32,
    pub source_index: usize,
    pub byte_len: usize,
    pub line_count: usize,
}

impl SourceFileUnitInput {
    pub fn from_source(library_id: u32, source_index: usize, source: &str) -> Self {
        Self {
            library_id,
            source_index,
            byte_len: source.len(),
            line_count: source.lines().count(),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct FrontendUnit {
    pub unit_index: usize,
    pub library_id: u32,
    pub first_source_index: usize,
    pub source_file_count: usize,
    pub source_bytes: usize,
    pub source_lines: usize,
    pub oversized_source_file: bool,
}

impl FrontendUnit {
    pub fn source_range(&self) -> Range<usize> {
        self.first_source_index..self.first_source_index + self.source_file_count
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CodegenUnit {
    pub unit_index: usize,
    pub library_id: u32,
    pub first_source_index: usize,
    pub source_file_count: usize,
    pub source_bytes: usize,
    pub source_lines: usize,
    pub oversized_source_file: bool,
}

impl CodegenUnit {
    pub fn source_range(&self) -> Range<usize> {
        self.first_source_index..self.first_source_index + self.source_file_count
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LibraryUnit {
    pub library_index: usize,
    pub library_id: u32,
    pub first_source_index: usize,
    pub source_file_count: usize,
    pub source_bytes: usize,
    pub source_lines: usize,
}

impl LibraryUnit {
    pub fn source_range(&self) -> Range<usize> {
        self.first_source_index..self.first_source_index + self.source_file_count
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct LibraryUnitPlan {
    pub libraries: Vec<LibraryUnit>,
}

impl LibraryUnitPlan {
    pub fn from_source_pack<S: AsRef<str>>(sources: &[S]) -> Self {
        let mut libraries = Vec::new();
        Self::try_for_each_from_files(
            sources.iter().enumerate().map(|(source_index, source)| {
                SourceFileUnitInput::from_source(0, source_index, source.as_ref())
            }),
            |library| {
                libraries.push(library);
                Ok::<(), ()>(())
            },
        )
        .unwrap_or_else(|()| unreachable!("infallible library-unit collection failed"));
        Self { libraries }
    }

    pub fn from_source_pack_with_libraries<S, L>(sources: &[S], library_ids: &[L]) -> Self
    where
        S: AsRef<str>,
        L: Copy + Into<u32>,
    {
        assert_eq!(
            sources.len(),
            library_ids.len(),
            "source and library slices must have the same length"
        );
        let mut libraries = Vec::new();
        Self::try_for_each_from_files(
            sources
                .iter()
                .zip(library_ids.iter().copied())
                .enumerate()
                .map(|(source_index, (source, library_id))| {
                    SourceFileUnitInput::from_source(
                        library_id.into(),
                        source_index,
                        source.as_ref(),
                    )
                }),
            |library| {
                libraries.push(library);
                Ok::<(), ()>(())
            },
        )
        .unwrap_or_else(|()| unreachable!("infallible library-unit collection failed"));
        Self { libraries }
    }

    pub fn from_files(files: &[SourceFileUnitInput]) -> Self {
        let mut libraries = Vec::new();
        Self::try_for_each_from_files(files.iter().copied(), |library| {
            libraries.push(library);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible library-unit collection failed"));
        Self { libraries }
    }

    pub fn try_for_each_from_files<I, F, E>(files: I, visit: F) -> Result<usize, E>
    where
        I: IntoIterator<Item = SourceFileUnitInput>,
        F: FnMut(LibraryUnit) -> Result<(), E>,
    {
        Self::try_for_each_from_fallible_files(files.into_iter().map(Ok), visit)
    }

    pub fn try_for_each_from_fallible_files<I, F, E>(files: I, mut visit: F) -> Result<usize, E>
    where
        I: IntoIterator<Item = Result<SourceFileUnitInput, E>>,
        F: FnMut(LibraryUnit) -> Result<(), E>,
    {
        let mut current = LibraryBuilder::default();
        let mut library_count = 0usize;

        for file in files {
            let file = file?;
            if current.should_flush_before(file) {
                if let Some(library) = current.take(library_count) {
                    library_count += 1;
                    visit(library)?;
                }
            }
            current.push(file);
        }

        if let Some(library) = current.take(library_count) {
            library_count += 1;
            visit(library)?;
        }
        Ok(library_count)
    }

    pub fn library_count(&self) -> usize {
        self.libraries.len()
    }

    pub fn max_library_source_bytes(&self) -> usize {
        self.libraries
            .iter()
            .map(|library| library.source_bytes)
            .max()
            .unwrap_or(0)
    }

    pub fn max_library_source_files(&self) -> usize {
        self.libraries
            .iter()
            .map(|library| library.source_file_count)
            .max()
            .unwrap_or(0)
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct FrontendUnitPlan {
    pub units: Vec<FrontendUnit>,
}

impl FrontendUnitPlan {
    pub fn from_source_pack<S: AsRef<str>>(sources: &[S], limits: CodegenUnitLimits) -> Self {
        let mut units = Vec::new();
        Self::try_for_each_from_files(
            sources.iter().enumerate().map(|(source_index, source)| {
                SourceFileUnitInput::from_source(0, source_index, source.as_ref())
            }),
            limits,
            |unit| {
                units.push(unit);
                Ok::<(), ()>(())
            },
        )
        .unwrap_or_else(|()| unreachable!("infallible frontend-unit collection failed"));
        Self { units }
    }

    pub fn from_source_pack_with_libraries<S, L>(
        sources: &[S],
        library_ids: &[L],
        limits: CodegenUnitLimits,
    ) -> Self
    where
        S: AsRef<str>,
        L: Copy + Into<u32>,
    {
        assert_eq!(
            sources.len(),
            library_ids.len(),
            "source and library slices must have the same length"
        );
        let mut units = Vec::new();
        Self::try_for_each_from_files(
            sources
                .iter()
                .zip(library_ids.iter().copied())
                .enumerate()
                .map(|(source_index, (source, library_id))| {
                    SourceFileUnitInput::from_source(
                        library_id.into(),
                        source_index,
                        source.as_ref(),
                    )
                }),
            limits,
            |unit| {
                units.push(unit);
                Ok::<(), ()>(())
            },
        )
        .unwrap_or_else(|()| unreachable!("infallible frontend-unit collection failed"));
        Self { units }
    }

    pub fn from_files(files: &[SourceFileUnitInput], limits: CodegenUnitLimits) -> Self {
        let mut units = Vec::new();
        Self::try_for_each_from_files(files.iter().copied(), limits, |unit| {
            units.push(unit);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible frontend-unit collection failed"));
        Self { units }
    }

    pub fn try_for_each_from_files<I, F, E>(
        files: I,
        limits: CodegenUnitLimits,
        visit: F,
    ) -> Result<usize, E>
    where
        I: IntoIterator<Item = SourceFileUnitInput>,
        F: FnMut(FrontendUnit) -> Result<(), E>,
    {
        Self::try_for_each_from_fallible_files(files.into_iter().map(Ok), limits, visit)
    }

    pub fn try_for_each_from_fallible_files<I, F, E>(
        files: I,
        limits: CodegenUnitLimits,
        mut visit: F,
    ) -> Result<usize, E>
    where
        I: IntoIterator<Item = Result<SourceFileUnitInput, E>>,
        F: FnMut(FrontendUnit) -> Result<(), E>,
    {
        let limits = limits.normalized();
        let mut current = UnitBuilder::default();
        let mut unit_count = 0usize;

        for file in files {
            let file = file?;
            let oversized = file.byte_len > limits.max_source_bytes;
            if oversized {
                if let Some(unit) = current.take_frontend(unit_count, false) {
                    unit_count += 1;
                    visit(unit)?;
                }
                visit(FrontendUnit {
                    unit_index: unit_count,
                    library_id: file.library_id,
                    first_source_index: file.source_index,
                    source_file_count: 1,
                    source_bytes: file.byte_len,
                    source_lines: file.line_count,
                    oversized_source_file: true,
                })?;
                unit_count += 1;
                continue;
            }

            if current.should_flush_before(file, limits) {
                if let Some(unit) = current.take_frontend(unit_count, false) {
                    unit_count += 1;
                    visit(unit)?;
                }
            }
            current.push(file);
        }

        if let Some(unit) = current.take_frontend(unit_count, false) {
            unit_count += 1;
            visit(unit)?;
        }
        Ok(unit_count)
    }

    pub fn unit_count(&self) -> usize {
        self.units.len()
    }

    pub fn oversized_unit_count(&self) -> usize {
        self.units
            .iter()
            .filter(|unit| unit.oversized_source_file)
            .count()
    }

    pub fn max_unit_source_bytes(&self) -> usize {
        self.units
            .iter()
            .map(|unit| unit.source_bytes)
            .max()
            .unwrap_or(0)
    }

    pub fn max_unit_source_files(&self) -> usize {
        self.units
            .iter()
            .map(|unit| unit.source_file_count)
            .max()
            .unwrap_or(0)
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct CodegenUnitPlan {
    pub units: Vec<CodegenUnit>,
}

impl CodegenUnitPlan {
    pub fn from_source_pack<S: AsRef<str>>(sources: &[S], limits: CodegenUnitLimits) -> Self {
        let mut units = Vec::new();
        Self::try_for_each_from_files(
            sources.iter().enumerate().map(|(source_index, source)| {
                SourceFileUnitInput::from_source(0, source_index, source.as_ref())
            }),
            limits,
            |unit| {
                units.push(unit);
                Ok::<(), ()>(())
            },
        )
        .unwrap_or_else(|()| unreachable!("infallible codegen-unit collection failed"));
        Self { units }
    }

    pub fn from_source_pack_with_libraries<S, L>(
        sources: &[S],
        library_ids: &[L],
        limits: CodegenUnitLimits,
    ) -> Self
    where
        S: AsRef<str>,
        L: Copy + Into<u32>,
    {
        assert_eq!(
            sources.len(),
            library_ids.len(),
            "source and library slices must have the same length"
        );
        let mut units = Vec::new();
        Self::try_for_each_from_files(
            sources
                .iter()
                .zip(library_ids.iter().copied())
                .enumerate()
                .map(|(source_index, (source, library_id))| {
                    SourceFileUnitInput::from_source(
                        library_id.into(),
                        source_index,
                        source.as_ref(),
                    )
                }),
            limits,
            |unit| {
                units.push(unit);
                Ok::<(), ()>(())
            },
        )
        .unwrap_or_else(|()| unreachable!("infallible codegen-unit collection failed"));
        Self { units }
    }

    pub fn from_files(files: &[SourceFileUnitInput], limits: CodegenUnitLimits) -> Self {
        let mut units = Vec::new();
        Self::try_for_each_from_files(files.iter().copied(), limits, |unit| {
            units.push(unit);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible codegen-unit collection failed"));
        Self { units }
    }

    pub fn try_for_each_from_files<I, F, E>(
        files: I,
        limits: CodegenUnitLimits,
        visit: F,
    ) -> Result<usize, E>
    where
        I: IntoIterator<Item = SourceFileUnitInput>,
        F: FnMut(CodegenUnit) -> Result<(), E>,
    {
        Self::try_for_each_from_fallible_files(files.into_iter().map(Ok), limits, visit)
    }

    pub fn try_for_each_from_fallible_files<I, F, E>(
        files: I,
        limits: CodegenUnitLimits,
        mut visit: F,
    ) -> Result<usize, E>
    where
        I: IntoIterator<Item = Result<SourceFileUnitInput, E>>,
        F: FnMut(CodegenUnit) -> Result<(), E>,
    {
        let limits = limits.normalized();
        let mut current = UnitBuilder::default();
        let mut unit_count = 0usize;

        for file in files {
            let file = file?;
            let oversized = file.byte_len > limits.max_source_bytes;
            if oversized {
                if let Some(unit) = current.take(unit_count, false) {
                    unit_count += 1;
                    visit(unit)?;
                }
                visit(CodegenUnit {
                    unit_index: unit_count,
                    library_id: file.library_id,
                    first_source_index: file.source_index,
                    source_file_count: 1,
                    source_bytes: file.byte_len,
                    source_lines: file.line_count,
                    oversized_source_file: true,
                })?;
                unit_count += 1;
                continue;
            }

            if current.should_flush_before(file, limits) {
                if let Some(unit) = current.take(unit_count, false) {
                    unit_count += 1;
                    visit(unit)?;
                }
            }
            current.push(file);
        }

        if let Some(unit) = current.take(unit_count, false) {
            unit_count += 1;
            visit(unit)?;
        }
        Ok(unit_count)
    }

    pub fn unit_count(&self) -> usize {
        self.units.len()
    }

    pub fn oversized_unit_count(&self) -> usize {
        self.units
            .iter()
            .filter(|unit| unit.oversized_source_file)
            .count()
    }

    pub fn max_unit_source_bytes(&self) -> usize {
        self.units
            .iter()
            .map(|unit| unit.source_bytes)
            .max()
            .unwrap_or(0)
    }

    pub fn max_unit_source_files(&self) -> usize {
        self.units
            .iter()
            .map(|unit| unit.source_file_count)
            .max()
            .unwrap_or(0)
    }
}

#[derive(Clone, Copy, Debug, Default)]
pub(in crate::codegen::unit) struct UnitBuilder {
    library_id: u32,
    first_source_index: usize,
    source_file_count: usize,
    source_bytes: usize,
    source_lines: usize,
}

#[derive(Clone, Copy, Debug, Default)]
pub(in crate::codegen::unit) struct LibraryBuilder {
    library_id: u32,
    first_source_index: usize,
    source_file_count: usize,
    source_bytes: usize,
    source_lines: usize,
}

impl LibraryBuilder {
    fn is_empty(self) -> bool {
        self.source_file_count == 0
    }

    pub(in crate::codegen::unit) fn should_flush_before(self, file: SourceFileUnitInput) -> bool {
        !self.is_empty() && self.library_id != file.library_id
    }

    pub(in crate::codegen::unit) fn push(&mut self, file: SourceFileUnitInput) {
        if self.is_empty() {
            self.library_id = file.library_id;
            self.first_source_index = file.source_index;
        }
        self.source_file_count += 1;
        self.source_bytes = self.source_bytes.saturating_add(file.byte_len);
        self.source_lines = self.source_lines.saturating_add(file.line_count);
    }

    pub(in crate::codegen::unit) fn take(&mut self, library_index: usize) -> Option<LibraryUnit> {
        if self.is_empty() {
            return None;
        }
        let library = LibraryUnit {
            library_index,
            library_id: self.library_id,
            first_source_index: self.first_source_index,
            source_file_count: self.source_file_count,
            source_bytes: self.source_bytes,
            source_lines: self.source_lines,
        };
        *self = Self::default();
        Some(library)
    }
}

impl UnitBuilder {
    fn is_empty(self) -> bool {
        self.source_file_count == 0
    }

    pub(in crate::codegen::unit) fn should_flush_before(
        self,
        file: SourceFileUnitInput,
        limits: CodegenUnitLimits,
    ) -> bool {
        if self.is_empty() {
            return false;
        }
        self.library_id != file.library_id
            || self.source_file_count >= limits.max_source_files
            || self.source_bytes.saturating_add(file.byte_len) > limits.max_source_bytes
    }

    pub(in crate::codegen::unit) fn push(&mut self, file: SourceFileUnitInput) {
        if self.is_empty() {
            self.library_id = file.library_id;
            self.first_source_index = file.source_index;
        }
        self.source_file_count += 1;
        self.source_bytes = self.source_bytes.saturating_add(file.byte_len);
        self.source_lines = self.source_lines.saturating_add(file.line_count);
    }

    pub(in crate::codegen::unit) fn take(
        &mut self,
        unit_index: usize,
        oversized_source_file: bool,
    ) -> Option<CodegenUnit> {
        if self.is_empty() {
            return None;
        }
        let unit = CodegenUnit {
            unit_index,
            library_id: self.library_id,
            first_source_index: self.first_source_index,
            source_file_count: self.source_file_count,
            source_bytes: self.source_bytes,
            source_lines: self.source_lines,
            oversized_source_file,
        };
        *self = Self::default();
        Some(unit)
    }

    pub(in crate::codegen::unit) fn take_frontend(
        &mut self,
        unit_index: usize,
        oversized_source_file: bool,
    ) -> Option<FrontendUnit> {
        if self.is_empty() {
            return None;
        }
        let unit = FrontendUnit {
            unit_index,
            library_id: self.library_id,
            first_source_index: self.first_source_index,
            source_file_count: self.source_file_count,
            source_bytes: self.source_bytes,
            source_lines: self.source_lines,
            oversized_source_file,
        };
        *self = Self::default();
        Some(unit)
    }
}
