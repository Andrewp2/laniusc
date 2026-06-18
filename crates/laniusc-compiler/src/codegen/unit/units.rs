use super::*;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
/// User-facing bounds for splitting a source pack into bounded compiler units.
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
    /// Returns limits clamped to at least one byte and one source file.
    pub fn normalized(self) -> Self {
        Self {
            max_source_bytes: self.max_source_bytes.max(1),
            max_source_files: self.max_source_files.max(1),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
/// Lightweight source-file facts used by unit planners.
pub struct SourceFileUnitInput {
    pub library_id: u32,
    pub source_index: usize,
    pub byte_len: usize,
    pub line_count: usize,
}

impl SourceFileUnitInput {
    /// Builds unit-planning input from an in-memory source string.
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
/// Bounded frontend/type-check unit produced from contiguous source files.
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
    /// Returns the source-index range covered by this unit.
    pub fn source_range(&self) -> Range<usize> {
        self.first_source_index..self.first_source_index + self.source_file_count
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
/// Bounded backend codegen unit produced from contiguous source files.
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
    /// Returns the source-index range covered by this unit.
    pub fn source_range(&self) -> Range<usize> {
        self.first_source_index..self.first_source_index + self.source_file_count
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
/// Contiguous files belonging to one source-pack library.
pub struct LibraryUnit {
    pub library_index: usize,
    pub library_id: u32,
    pub first_source_index: usize,
    pub source_file_count: usize,
    pub source_bytes: usize,
    pub source_lines: usize,
}

impl LibraryUnit {
    /// Returns the source-index range covered by this library unit.
    pub fn source_range(&self) -> Range<usize> {
        self.first_source_index..self.first_source_index + self.source_file_count
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
/// Collected library units for a source pack.
pub struct LibraryUnitPlan {
    pub libraries: Vec<LibraryUnit>,
}

impl LibraryUnitPlan {
    /// Builds a single-library plan from in-memory source strings.
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

    /// Builds a plan from in-memory source strings and explicit library ids.
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

    /// Builds a plan from precomputed source-file facts.
    pub fn from_files(files: &[SourceFileUnitInput]) -> Self {
        let mut libraries = Vec::new();
        Self::try_for_each_from_files(files.iter().copied(), |library| {
            libraries.push(library);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible library-unit collection failed"));
        Self { libraries }
    }

    /// Streams library units to a visitor without retaining the full plan.
    pub fn try_for_each_from_files<I, F, E>(files: I, visit: F) -> Result<usize, E>
    where
        I: IntoIterator<Item = SourceFileUnitInput>,
        F: FnMut(LibraryUnit) -> Result<(), E>,
    {
        Self::try_for_each_from_fallible_files(files.into_iter().map(Ok), visit)
    }

    /// Streams library units from a fallible source-file iterator.
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

    /// Returns the number of libraries represented by the plan.
    pub fn library_count(&self) -> usize {
        self.libraries.len()
    }

    /// Returns the largest source-byte total among planned libraries.
    pub fn max_library_source_bytes(&self) -> usize {
        self.libraries
            .iter()
            .map(|library| library.source_bytes)
            .max()
            .unwrap_or(0)
    }

    /// Returns the largest source-file count among planned libraries.
    pub fn max_library_source_files(&self) -> usize {
        self.libraries
            .iter()
            .map(|library| library.source_file_count)
            .max()
            .unwrap_or(0)
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
/// Collected frontend units for a source pack.
pub struct FrontendUnitPlan {
    pub units: Vec<FrontendUnit>,
}

impl FrontendUnitPlan {
    /// Builds bounded frontend units for a single-library in-memory source pack.
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

    /// Builds bounded frontend units from sources and explicit library ids.
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

    /// Builds bounded frontend units from precomputed source-file facts.
    pub fn from_files(files: &[SourceFileUnitInput], limits: CodegenUnitLimits) -> Self {
        let mut units = Vec::new();
        Self::try_for_each_from_files(files.iter().copied(), limits, |unit| {
            units.push(unit);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible frontend-unit collection failed"));
        Self { units }
    }

    /// Streams frontend units to a visitor without retaining the full plan.
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

    /// Streams frontend units from a fallible source-file iterator.
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

    /// Returns the number of frontend units in this plan.
    pub fn unit_count(&self) -> usize {
        self.units.len()
    }

    /// Returns the number of one-file units that exceed the configured byte limit.
    pub fn oversized_unit_count(&self) -> usize {
        self.units
            .iter()
            .filter(|unit| unit.oversized_source_file)
            .count()
    }

    /// Returns the largest source-byte total among planned frontend units.
    pub fn max_unit_source_bytes(&self) -> usize {
        self.units
            .iter()
            .map(|unit| unit.source_bytes)
            .max()
            .unwrap_or(0)
    }

    /// Returns the largest source-file count among planned frontend units.
    pub fn max_unit_source_files(&self) -> usize {
        self.units
            .iter()
            .map(|unit| unit.source_file_count)
            .max()
            .unwrap_or(0)
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
/// Collected backend codegen units for a source pack.
pub struct CodegenUnitPlan {
    pub units: Vec<CodegenUnit>,
}

impl CodegenUnitPlan {
    /// Builds bounded codegen units for a single-library in-memory source pack.
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

    /// Builds bounded codegen units from sources and explicit library ids.
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

    /// Builds bounded codegen units from precomputed source-file facts.
    pub fn from_files(files: &[SourceFileUnitInput], limits: CodegenUnitLimits) -> Self {
        let mut units = Vec::new();
        Self::try_for_each_from_files(files.iter().copied(), limits, |unit| {
            units.push(unit);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible codegen-unit collection failed"));
        Self { units }
    }

    /// Streams codegen units to a visitor without retaining the full plan.
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

    /// Streams codegen units from a fallible source-file iterator.
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

    /// Returns the number of codegen units in this plan.
    pub fn unit_count(&self) -> usize {
        self.units.len()
    }

    /// Returns the number of one-file units that exceed the configured byte limit.
    pub fn oversized_unit_count(&self) -> usize {
        self.units
            .iter()
            .filter(|unit| unit.oversized_source_file)
            .count()
    }

    /// Returns the largest source-byte total among planned codegen units.
    pub fn max_unit_source_bytes(&self) -> usize {
        self.units
            .iter()
            .map(|unit| unit.source_bytes)
            .max()
            .unwrap_or(0)
    }

    /// Returns the largest source-file count among planned codegen units.
    pub fn max_unit_source_files(&self) -> usize {
        self.units
            .iter()
            .map(|unit| unit.source_file_count)
            .max()
            .unwrap_or(0)
    }
}

#[derive(Clone, Copy, Debug, Default)]
/// Mutable accumulator for one codegen or frontend unit within a single library.
pub(in crate::codegen::unit) struct UnitBuilder {
    library_id: u32,
    first_source_index: usize,
    source_file_count: usize,
    source_bytes: usize,
    source_lines: usize,
}

#[derive(Clone, Copy, Debug, Default)]
/// Mutable accumulator for one library unit spanning contiguous source files.
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

    /// Returns whether the current library unit must finish before `file`.
    pub(in crate::codegen::unit) fn should_flush_before(self, file: SourceFileUnitInput) -> bool {
        !self.is_empty() && self.library_id != file.library_id
    }

    /// Adds one source file to the pending library unit.
    pub(in crate::codegen::unit) fn push(&mut self, file: SourceFileUnitInput) {
        if self.is_empty() {
            self.library_id = file.library_id;
            self.first_source_index = file.source_index;
        }
        self.source_file_count += 1;
        self.source_bytes = self.source_bytes.saturating_add(file.byte_len);
        self.source_lines = self.source_lines.saturating_add(file.line_count);
    }

    /// Emits the pending library unit and resets the builder, or returns `None` when empty.
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

    /// Returns whether the current codegen unit must finish before `file`.
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

    /// Adds one source file to the pending codegen unit.
    pub(in crate::codegen::unit) fn push(&mut self, file: SourceFileUnitInput) {
        if self.is_empty() {
            self.library_id = file.library_id;
            self.first_source_index = file.source_index;
        }
        self.source_file_count += 1;
        self.source_bytes = self.source_bytes.saturating_add(file.byte_len);
        self.source_lines = self.source_lines.saturating_add(file.line_count);
    }

    /// Emits the pending codegen unit and resets the builder, or returns `None` when empty.
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

    /// Emits the pending frontend unit and resets the builder, or returns `None` when empty.
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
