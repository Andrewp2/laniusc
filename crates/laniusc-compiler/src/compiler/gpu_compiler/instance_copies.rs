//! Instance copies: one frontend run checks many environments of one generic
//! body by appending a renamed copy of the body's declaration per environment
//! after the template unit's text. Each copy is its own lexical scope, so
//! entries never compete for one scope.
//!
//! A copy resolves names in its body's module. Copies of the template's last
//! file are appended to that file. Copies of an earlier file's bodies go to
//! a continuation file of that file, appended after the template: it holds
//! only copies, and the module kernels give it the module of the file it
//! continues (05c_build_file_module_map), with that module's imports.
//!
//! The host role is mechanical. It copies byte ranges the GPU reported
//! (`CheckedOwnerSpans`), adds fixed text around them and records where every
//! copied range came from. It never lexes, parses or infers anything from the
//! copied text. The segment table maps copy bytes back to template bytes for
//! call evidence and for diagnostics.

use std::{path::PathBuf, sync::Arc};

use anyhow::{Result, anyhow, ensure};

use crate::{
    compiler::{Diagnostic, DiagnosticLabel, diagnostic_label_from_source_span, source_pack_diagnostic_files},
    type_checker::{CheckedOwnerSpan, MAX_BODY_CONTINUATION_FILES},
};
#[cfg(test)]
use crate::type_checker::{CheckedImplHeader, CheckedTraitCut};

/// Copies are named `__lanius_inst_<entry>_<original name>`. Source code
/// cannot rely on this reserved prefix.
pub(super) const INSTANCE_NAME_PREFIX: &str = "__lanius_inst_";

/// Bytes `[instance_start, instance_start + len)` of the instance unit are
/// template bytes `[original_start, original_start + len)`. Global offsets.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct CopiedSegment {
    pub instance_start: u32,
    pub original_start: u32,
    pub len: u32,
}

impl CopiedSegment {
    fn contains(&self, instance: u32) -> bool {
        instance >= self.instance_start && instance - self.instance_start < self.len
    }
}

/// One copied declaration, in entry order.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct InstanceCopy {
    /// The template HIR of the copied callable.
    pub function_hir: u32,
    /// Global byte of the copy's `fn` keyword (its packet selector).
    pub fn_byte: u32,
    /// Global bytes `[start, end)` of the copy's whole text.
    pub range: [u32; 2],
    /// The copied name-to-body-end segment.
    pub body: CopiedSegment,
    /// The copied impl header segments of a method copy: one for an
    /// inherent impl, two around the left-out trait path for a trait impl.
    pub header: Vec<CopiedSegment>,
}

/// Template sources with the copies appended: to the last file, then in
/// continuation files.
#[derive(Clone, Debug)]
pub(super) struct InstanceSources {
    pub sources: Arc<[String]>,
    /// Global byte length of the template text.
    pub template_len: u32,
    /// Per source file after the template's, the template file whose module
    /// it continues, increasing.
    pub continuations: Vec<u32>,
    pub copies: Vec<InstanceCopy>,
}

impl InstanceSources {
    /// Where a body's copy goes, as the order of a run's entries: 0 for a
    /// body of the template's last file, whose copy is appended to it, and
    /// 1 + the file index for a body of an earlier file, whose copy goes to
    /// that file's continuation. None when the body cannot replay as a copy
    /// and replays in its original scope: it crosses a file, or it is a
    /// trait-impl method whose self type is declared in another file (its
    /// inherent copy must be in the type's module). Bodies of earlier files
    /// copy unless `LANIUS_REPLAY_MULTIFILE_COPIES=0`.
    pub(super) fn copy_rank(template: &[String], span: &CheckedOwnerSpan) -> Option<u32> {
        copy_rank_with(template, span, multifile_copies_enabled())
    }

    /// Copy each span once, in the given order, which must be by
    /// `copy_rank`. Spans index the template's global bytes; a top-level
    /// function copy is `fn __lanius_inst_<n>_` + template[name..end], and a
    /// method copy is template[impl..brace_end] + `fn __lanius_inst_<n>_` +
    /// template[name..end] + `}`, each copy on new lines after the previous
    /// one. A trait-impl method's header leaves out its trait path and
    /// `for`, so the copy is a method of an inherent impl of the same self
    /// type. `<n>` is the entry's index, unique in the unit; source names
    /// never use the reserved prefix, so a copy cannot collide with a
    /// declared method. Copy bytes increase with the entry index.
    pub(super) fn build(template: &[String], spans: &[CheckedOwnerSpan]) -> Result<Self> {
        Self::build_with(template, spans, multifile_copies_enabled())
    }

    fn build_with(template: &[String], spans: &[CheckedOwnerSpan], multifile: bool) -> Result<Self> {
        ensure!(!template.is_empty(), "an instance unit needs a template source file");
        let template_len = template.iter().try_fold(0u32, |total, source| {
            u32::try_from(source.len()).ok().and_then(|len| total.checked_add(len))
        }).ok_or_else(|| anyhow!("template source pack exceeds u32 bytes"))?;
        let last_start = template_len as usize - template.last().expect("nonempty").len();
        let ranks = spans.iter()
            .map(|span| copy_rank_with(template, span, multifile))
            .collect::<Option<Vec<_>>>()
            .ok_or_else(|| anyhow!("an instance copy's body cannot be copied from its template file"))?;
        ensure!(ranks.windows(2).all(|pair| pair[0] <= pair[1]),
            "instance copies are not ordered by their template file");
        // Every appended byte in global order: the last file's suffix, then
        // the continuation files, each starting at its `file_starts` byte.
        let mut text = String::new();
        let mut continuations = Vec::new();
        let mut file_starts = Vec::new();
        let mut copies = Vec::with_capacity(spans.len());
        // Global offset of the next byte appended to `text`.
        let offset = |text: &String| -> Result<u32> {
            u32::try_from(template_len as usize + text.len())
                .map_err(|_| anyhow!("instance unit exceeds u32 bytes"))
        };
        for (index, (span, &rank)) in spans.iter().zip(&ranks).enumerate() {
            if rank != 0 && continuations.last() != Some(&(rank - 1)) {
                continuations.push(rank - 1);
                file_starts.push(text.len());
            }
            let copy = |start: u32, end: u32, text: &mut String| -> Result<CopiedSegment> {
                ensure!(start < end && end <= template_len, "owner span is outside the template text");
                let slice = global_slice(template, start, end)
                    .ok_or_else(|| anyhow!("owner span is not a character range of one source file"))?;
                let segment = CopiedSegment { instance_start: offset(text)?, original_start: start, len: end - start };
                text.push_str(slice);
                Ok(segment)
            };
            let start = offset(&text)?;
            text.push('\n');
            let mut header = Vec::new();
            if let Some(implementation) = span.enclosing_impl {
                let (keyword, brace_end) = (implementation.keyword_byte, implementation.brace_end);
                match implementation.trait_cut {
                    None => header.push(copy(keyword, brace_end, &mut text)?),
                    Some(cut) => {
                        header.push(copy(keyword, cut.start, &mut text)?);
                        header.push(copy(cut.end, brace_end, &mut text)?);
                    }
                }
                text.push_str("\n    ");
            }
            let fn_byte = offset(&text)?;
            text.push_str("fn ");
            text.push_str(INSTANCE_NAME_PREFIX);
            text.push_str(&index.to_string());
            text.push('_');
            let body = copy(span.name_byte, span.end_byte, &mut text)?;
            if !header.is_empty() {
                text.push_str("\n}");
            }
            copies.push(InstanceCopy {
                function_hir: span.function_hir,
                fn_byte,
                range: [start, offset(&text)?],
                body,
                header,
            });
        }
        ensure!(continuations.len() <= MAX_BODY_CONTINUATION_FILES,
            "an instance unit needs {} continuation files; at most {MAX_BODY_CONTINUATION_FILES} fit one packet",
            continuations.len());
        offset(&text)?;
        let mut sources = template.to_vec();
        let last = sources.last_mut().expect("nonempty");
        debug_assert_eq!(last_start + last.len(), template_len as usize);
        let suffix_end = file_starts.first().copied().unwrap_or(text.len());
        last.push_str(&text[..suffix_end]);
        for (file, &start) in file_starts.iter().enumerate() {
            let end = file_starts.get(file + 1).copied().unwrap_or(text.len());
            sources.push(text[start..end].to_string());
        }
        Ok(Self { sources: sources.into(), template_len, continuations, copies })
    }

    /// The entry whose copy text holds this global instance byte.
    pub(super) fn copy_at(&self, instance: u32) -> Option<usize> {
        if instance < self.template_len { return None; }
        let index = self.copies.partition_point(|copy| copy.range[1] <= instance);
        (index < self.copies.len() && self.copies[index].range[0] <= instance).then_some(index)
    }

    /// The template span of an instance span `[start, start + len)` inside
    /// one copy's copied body, or None when it is not wholly inside it.
    pub(super) fn original_body_span(&self, entry: usize, span: [u32; 2]) -> Option<[u32; 2]> {
        let body = self.copies.get(entry)?.body;
        let [start, len] = span;
        let end = start.checked_add(len)?;
        (body.contains(start) && end <= body.instance_start + body.len)
            .then(|| [start - body.instance_start + body.original_start, len])
    }

    /// The template byte of a global instance byte. Template bytes map to
    /// themselves; added text maps to the start of its copy's body.
    pub(super) fn original_byte(&self, instance: u32) -> Option<u32> {
        if instance < self.template_len { return Some(instance); }
        let copy = &self.copies[self.copy_at(instance)?];
        for segment in copy.header.iter().chain(std::iter::once(&copy.body)) {
            if segment.contains(instance) {
                return Some(instance - segment.instance_start + segment.original_start);
            }
        }
        Some(copy.body.original_start)
    }

    /// Rewrite a diagnostic from the instance unit to name template bytes
    /// and template declaration names.
    pub(super) fn template_diagnostic(
        &self,
        mut diagnostic: Diagnostic,
        template: &[String],
        paths: Option<&[Option<PathBuf>]>,
    ) -> Diagnostic {
        if let Some(label) = diagnostic.primary_label.take() {
            diagnostic.primary_label = Some(self.template_label(label, template, paths));
        }
        diagnostic.message = strip_instance_names(&diagnostic.message);
        diagnostic.help = diagnostic.help.map(|help| strip_instance_names(&help));
        diagnostic.notes = diagnostic.notes.iter().map(|note| strip_instance_names(note)).collect();
        diagnostic
    }

    fn template_label(
        &self,
        label: DiagnosticLabel,
        template: &[String],
        paths: Option<&[Option<PathBuf>]>,
    ) -> DiagnosticLabel {
        let message = strip_instance_names(&label.message);
        let files = source_pack_diagnostic_files(template, paths);
        let (Some(start), Some(end)) = (label.byte_start, label.byte_end) else {
            return DiagnosticLabel { message, ..label };
        };
        // The frontend named the instance unit's files with the template's
        // paths and `<source pack file N>` past them. Only a label past the
        // template text, in the last template file or a continuation, is in
        // a copy.
        let instance_files = source_pack_diagnostic_files(&self.sources, paths);
        let Some(checked) = instance_files.iter().skip(template.len().saturating_sub(1))
            .find(|file| file.path == label.path)
        else {
            return DiagnosticLabel { message, ..label };
        };
        let global = |local: usize| u32::try_from(checked.global_start + local).ok();
        if global(start).is_none_or(|byte| byte < self.template_len) {
            return DiagnosticLabel { message, ..label };
        }
        let Some(original) = global(start).and_then(|byte| self.original_byte(byte)) else {
            return DiagnosticLabel { message, ..label };
        };
        // Keep the label inside the copied segment that holds its start.
        let original_end = global(end.max(start + 1) - 1)
            .and_then(|byte| self.original_byte(byte))
            .filter(|&byte| byte >= original)
            .map_or(original + 1, |byte| byte + 1);
        let Some(file) = crate::compiler::source_pack_file_for_global_span(&files, original as usize) else {
            return DiagnosticLabel { message, ..label };
        };
        let local = file.local_start_for_global(original as usize);
        diagnostic_label_from_source_span(
            file.path.clone(),
            &file.source,
            local,
            (original_end - original) as usize,
            message,
        )
    }
}

/// `__lanius_inst_<n>_name` becomes `name`.
fn strip_instance_names(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(position) = rest.find(INSTANCE_NAME_PREFIX) {
        out.push_str(&rest[..position]);
        let after = &rest[position + INSTANCE_NAME_PREFIX.len()..];
        let digits = after.bytes().take_while(u8::is_ascii_digit).count();
        if digits > 0 && after.as_bytes().get(digits) == Some(&b'_') {
            rest = &after[digits + 1..];
        } else {
            out.push_str(INSTANCE_NAME_PREFIX);
            rest = after;
        }
    }
    out.push_str(rest);
    out
}

/// `copy_rank` with copies of earlier files allowed or not.
fn copy_rank_with(template: &[String], span: &CheckedOwnerSpan, multifile: bool) -> Option<u32> {
    let first = span.first_byte() as usize;
    let mut file_start = 0usize;
    let mut found = None;
    for (file, source) in template.iter().enumerate() {
        let file_end = file_start + source.len();
        if first >= file_start && first < file_end {
            found = Some((file, file_end));
            break;
        }
        file_start = file_end;
    }
    let (file, file_end) = found?;
    let in_file = |byte: u32| (byte as usize) >= file_start && (byte as usize) < file_end;
    let local = (span.end_byte as usize) <= file_end
        && span.enclosing_impl
            .and_then(|header| header.trait_cut)
            .is_none_or(|cut| in_file(cut.self_declaration_byte));
    if !local {
        None
    } else if file + 1 == template.len() {
        Some(0)
    } else if multifile {
        u32::try_from(file + 1).ok()
    } else {
        None
    }
}

/// `LANIUS_REPLAY_MULTIFILE_COPIES=0` replays bodies of every file but the
/// template's last in their original scope, as before continuation files.
fn multifile_copies_enabled() -> bool {
    crate::gpu::env::env_bool_truthy("LANIUS_REPLAY_MULTIFILE_COPIES", true)
}

/// Template bytes `[start, end)` when they lie in one file on character
/// boundaries.
fn global_slice(template: &[String], start: u32, end: u32) -> Option<&str> {
    let mut file_start = 0usize;
    for source in template {
        let file_end = file_start + source.len();
        if (start as usize) >= file_start && (start as usize) < file_end {
            if end as usize > file_end { return None; }
            return source.get(start as usize - file_start..end as usize - file_start);
        }
        file_start = file_end;
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEMPLATE: &str = "module m;\nstruct Cell<T> { value: T }\nfn keep<T>(value: T) -> T { return value; }\nimpl<T> Cell<T> {\n    pub fn get(&self) -> T { return keep(self.value); }\n}\n";

    fn find(text: &str, needle: &str) -> u32 {
        text.find(needle).expect("needle") as u32
    }

    fn spans() -> Vec<CheckedOwnerSpan> {
        let keep_name = find(TEMPLATE, "keep<T>");
        let keep_end = find(TEMPLATE, "return value; }") + "return value; }".len() as u32;
        let get_name = find(TEMPLATE, "get(&self)");
        let get_end = find(TEMPLATE, "self.value); }") + "self.value); }".len() as u32;
        let keyword = find(TEMPLATE, "impl<T>");
        let brace_end = find(TEMPLATE, "Cell<T> {\n    pub") + "Cell<T> {".len() as u32;
        vec![
            CheckedOwnerSpan { function_hir: 4, name_byte: keep_name, end_byte: keep_end, enclosing_impl: None, native_symbol: 1 },
            CheckedOwnerSpan { function_hir: 9, name_byte: get_name, end_byte: get_end,
                enclosing_impl: Some(CheckedImplHeader { hir: 8, keyword_byte: keyword, brace_end, trait_cut: None }),
                native_symbol: 2 },
            CheckedOwnerSpan { function_hir: 4, name_byte: keep_name, end_byte: keep_end, enclosing_impl: None, native_symbol: 1 },
        ]
    }

    #[test]
    fn copies_append_renamed_declarations_after_the_last_file() {
        let header = "module m;\n".to_string();
        let template = vec![header.clone(), TEMPLATE["module m;\n".len()..].to_string()];
        // Spans are global: they already count the first file.
        let instance = InstanceSources::build(&template, &spans()).unwrap();
        assert_eq!(instance.sources.len(), 2);
        assert_eq!(instance.sources[0], header);
        let last = &instance.sources[1];
        assert!(last.starts_with(&template[1]));
        let appended = &last[template[1].len()..];
        assert_eq!(appended, concat!(
            "\nfn __lanius_inst_0_keep<T>(value: T) -> T { return value; }",
            "\nimpl<T> Cell<T> {\n    fn __lanius_inst_1_get(&self) -> T { return keep(self.value); }\n}",
            "\nfn __lanius_inst_2_keep<T>(value: T) -> T { return value; }",
        ));
        let all = instance.sources.concat();
        assert_eq!(instance.template_len as usize, TEMPLATE.len());
        for (index, copy) in instance.copies.iter().enumerate() {
            assert_eq!(&all[copy.fn_byte as usize..copy.fn_byte as usize + 3], "fn ");
            assert_eq!(instance.copy_at(copy.fn_byte), Some(index));
            assert_eq!(instance.copy_at(copy.range[1] - 1), Some(index));
            let body = copy.body;
            assert_eq!(
                &all[body.instance_start as usize..(body.instance_start + body.len) as usize],
                &TEMPLATE[body.original_start as usize..(body.original_start + body.len) as usize]);
        }
        assert!(instance.copies.windows(2).all(|pair| pair[0].fn_byte < pair[1].fn_byte));
        assert_eq!(instance.copy_at(instance.template_len - 1), None);
        assert_eq!(instance.copy_at(all.len() as u32), None);
        assert_eq!(instance.copies[1].header.len(), 1);
        assert_eq!(instance.copies[1].header[0].original_start, find(TEMPLATE, "impl<T>"));
        assert!(instance.copies[0].header.is_empty());
    }

    #[test]
    fn copy_spans_map_back_to_template_bytes() {
        let instance = InstanceSources::build(&[TEMPLATE.to_string()], &spans()).unwrap();
        let all = instance.sources.concat();
        // The `keep(self.value)` call of the method copy.
        let call = all.rfind("keep(self.value)").unwrap() as u32;
        let len = "keep(self.value)".len() as u32;
        assert_eq!(instance.copy_at(call), Some(1));
        assert_eq!(instance.original_body_span(1, [call, len]),
            Some([find(TEMPLATE, "keep(self.value)"), len]));
        assert_eq!(instance.original_body_span(0, [call, len]), None, "another copy");
        let body = instance.copies[1].body;
        assert_eq!(instance.original_body_span(1, [body.instance_start + body.len - 1, 2]), None,
            "a span leaving the copied body");
        // Template bytes are unchanged; added text maps to the body start.
        assert_eq!(instance.original_byte(7), Some(7));
        assert_eq!(instance.original_byte(instance.copies[1].fn_byte), Some(body.original_start));
        let header = instance.copies[1].header[0];
        assert_eq!(instance.original_byte(header.instance_start + 2), Some(header.original_start + 2));
    }

    #[test]
    fn a_diagnostic_inside_a_copy_names_the_template_declaration() {
        let instance = InstanceSources::build(&[TEMPLATE.to_string()], &spans()).unwrap();
        let all = instance.sources.concat();
        let paths = [Some(PathBuf::from("m.lani"))];
        // The type checker reports `self.value` in copy 1, against the
        // instance text it checked.
        let start = all.rfind("self.value").unwrap();
        let checked = diagnostic_label_from_source_span(
            "m.lani", &all, start, "self.value".len(), "in __lanius_inst_1_get");
        let diagnostic = Diagnostic::error("LNC0005", "mismatched type in __lanius_inst_1_get")
            .with_primary_label(checked)
            .with_note("instantiated as __lanius_inst_12_get and __lanius_inst_x");
        let mapped = instance.template_diagnostic(diagnostic, &[TEMPLATE.to_string()], Some(&paths));
        let label = mapped.primary_label.unwrap();
        let original = TEMPLATE.find("self.value").unwrap();
        assert_eq!(label.path, PathBuf::from("m.lani"));
        assert_eq!(label.byte_start, Some(original));
        assert_eq!(label.byte_end, Some(original + "self.value".len()));
        assert_eq!(label.line, 5);
        assert_eq!(label.source_line.as_deref(), Some("    pub fn get(&self) -> T { return keep(self.value); }"));
        assert_eq!(label.message, "in get");
        assert_eq!(mapped.message, "mismatched type in get");
        assert_eq!(mapped.notes, vec!["instantiated as get and __lanius_inst_x".to_string()]);

        // A label in the template part is unchanged.
        let template_label = diagnostic_label_from_source_span("m.lani", &all, 7, 1, "here");
        let kept = instance.template_diagnostic(
            Diagnostic::error("LNC0005", "x").with_primary_label(template_label.clone()),
            &[TEMPLATE.to_string()], Some(&paths));
        assert_eq!(kept.primary_label, Some(template_label));
    }

    #[test]
    fn copies_reject_spans_outside_one_file() {
        let template = vec!["fn a<T>() {}".to_string(), "fn b<T>() {}".to_string()];
        let crossing = CheckedOwnerSpan { function_hir: 1, name_byte: 3, end_byte: 15, enclosing_impl: None, native_symbol: 0 };
        assert!(InstanceSources::build(&template, &[crossing]).is_err());
        let outside = CheckedOwnerSpan { end_byte: 99, ..crossing };
        assert!(InstanceSources::build(&template, &[outside]).is_err());
        let second = CheckedOwnerSpan { name_byte: 15, end_byte: 24, ..crossing };
        let instance = InstanceSources::build(&template, &[second]).unwrap();
        assert_eq!(&instance.sources[1][12..], "\nfn __lanius_inst_0_b<T>() {}");
    }

    const TRAIT_TEMPLATE: &str = "module m;\ntrait Get<T> { fn get(self) -> T; }\nstruct Slot<T> { value: T }\nimpl<T> Get<T> for Slot<T> where T: Copy {\n    fn get(self) -> T { return self.value; }\n}\n";

    fn trait_span(template: &str) -> CheckedOwnerSpan {
        let keyword = find(template, "impl<T> Get");
        let name = find(template, "get(self) -> T {");
        let end = find(template, "self.value; }") + "self.value; }".len() as u32;
        CheckedOwnerSpan {
            function_hir: 12, name_byte: name, end_byte: end,
            enclosing_impl: Some(CheckedImplHeader {
                hir: 10, keyword_byte: keyword,
                brace_end: find(template, "Copy {") + "Copy {".len() as u32,
                trait_cut: Some(CheckedTraitCut {
                    start: find(template, "Get<T> for"),
                    end: find(template, "Slot<T> where"),
                    self_declaration_byte: find(template, "Slot<T> {"),
                }),
            }),
            native_symbol: 3,
        }
    }

    #[test]
    fn a_trait_impl_method_copies_as_an_inherent_method_of_its_self_type() {
        let span = trait_span(TRAIT_TEMPLATE);
        let instance = InstanceSources::build(&[TRAIT_TEMPLATE.to_string()], &[span, span]).unwrap();
        let all = instance.sources.concat();
        assert_eq!(&all[TRAIT_TEMPLATE.len()..], concat!(
            "\nimpl<T> Slot<T> where T: Copy {\n    fn __lanius_inst_0_get(self) -> T { return self.value; }\n}",
            "\nimpl<T> Slot<T> where T: Copy {\n    fn __lanius_inst_1_get(self) -> T { return self.value; }\n}",
        ));
        let copy = &instance.copies[1];
        assert_eq!(copy.header.len(), 2);
        // Both header segments map back to their own template bytes.
        let [first, second] = [copy.header[0], copy.header[1]];
        assert_eq!(instance.original_byte(first.instance_start), Some(find(TRAIT_TEMPLATE, "impl<T> Get")));
        assert_eq!(instance.original_byte(second.instance_start), Some(find(TRAIT_TEMPLATE, "Slot<T> where")));
        assert_eq!(second.instance_start, first.instance_start + first.len);
        assert_eq!(&all[copy.fn_byte as usize..copy.fn_byte as usize + 3], "fn ");
    }

    #[test]
    fn copy_ranks_follow_the_body_file() {
        let rank = |template: &[String], span: &CheckedOwnerSpan, multifile: bool| {
            copy_rank_with(template, span, multifile)
        };
        // The same declarations split over two files: the trait impl in the
        // first, or its self type in the first.
        let split_at = find(TRAIT_TEMPLATE, "impl<T> Get") as usize;
        let impl_first = vec![TRAIT_TEMPLATE.to_string(), "fn tail() {}\n".to_string()];
        let span = trait_span(TRAIT_TEMPLATE);
        assert_eq!(rank(&impl_first, &span, true), Some(1), "impl and self type share file 0");
        assert_eq!(rank(&impl_first, &span, false), None);
        assert!(InstanceSources::build_with(&impl_first, &[span], false).is_err());
        let instance = InstanceSources::build_with(&impl_first, &[span], true).unwrap();
        assert_eq!(instance.continuations, vec![0]);

        let type_first = vec![TRAIT_TEMPLATE[..split_at].to_string(), TRAIT_TEMPLATE[split_at..].to_string()];
        assert_eq!(rank(&type_first, &span, true), None, "self type declared in another file");
        let mut local_type = span;
        if let Some(header) = local_type.enclosing_impl.as_mut() {
            header.trait_cut.as_mut().unwrap().self_declaration_byte = split_at as u32 + 2;
        }
        assert_eq!(rank(&type_first, &local_type, false), Some(0));

        // A top-level function or inherent method copies by its own bytes.
        let spans = spans();
        let one = vec![TEMPLATE.to_string()];
        assert!(spans.iter().all(|span| rank(&one, span, false) == Some(0)));
        let keep_end = spans[0].end_byte as usize;
        let keep_first = vec![TEMPLATE[..keep_end].to_string(), TEMPLATE[keep_end..].to_string()];
        assert_eq!(rank(&keep_first, &spans[0], false), None);
        assert_eq!(rank(&keep_first, &spans[0], true), Some(1));
        assert_eq!(rank(&keep_first, &spans[1], false), Some(0));
        // A span leaving its file never copies.
        let crossing = CheckedOwnerSpan { end_byte: keep_end as u32 + 2, ..spans[0] };
        assert_eq!(rank(&keep_first, &crossing, true), None);
    }

    const FILES: [&str; 3] = [
        "module a;\nfn keep<T>(value: T) -> T { return value; }\n",
        "module b;\nfn pass<T>(x: T) -> T { return keep(x); }\n",
        "module c;\nfn last<T>(v: T) -> T { return v; }\n",
    ];

    /// The top-level function `name` of FILES, at global bytes.
    fn file_span(name: &str, function_hir: u32) -> CheckedOwnerSpan {
        let all = FILES.concat();
        let name_byte = find(&all, &format!("{name}<T>"));
        let end_byte = all[name_byte as usize..].find("; }").unwrap() as u32 + name_byte + 3;
        CheckedOwnerSpan { function_hir, name_byte, end_byte, enclosing_impl: None, native_symbol: function_hir }
    }

    #[test]
    fn copies_of_earlier_files_go_to_continuation_files() {
        let template = FILES.map(str::to_string).to_vec();
        let (keep, pass, last) = (file_span("keep", 2), file_span("pass", 5), file_span("last", 8));
        let instance = InstanceSources::build_with(&template, &[last, keep, keep, pass], true).unwrap();
        assert_eq!(instance.template_len as usize, FILES.concat().len());
        assert_eq!(instance.continuations, vec![0, 1]);
        assert_eq!(instance.sources.len(), 5);
        assert_eq!(&instance.sources[..2], &template[..2], "template files are unchanged");
        assert_eq!(instance.sources[2], format!("{}\nfn __lanius_inst_0_last<T>(v: T) -> T {{ return v; }}", FILES[2]));
        assert_eq!(instance.sources[3], concat!(
            "\nfn __lanius_inst_1_keep<T>(value: T) -> T { return value; }",
            "\nfn __lanius_inst_2_keep<T>(value: T) -> T { return value; }"));
        assert_eq!(instance.sources[4], "\nfn __lanius_inst_3_pass<T>(x: T) -> T { return keep(x); }");
        // Copy bytes are global and increase with the entry, across files.
        let all = instance.sources.concat();
        assert!(instance.copies.windows(2).all(|pair| pair[0].range[1] <= pair[1].range[0]));
        for (index, copy) in instance.copies.iter().enumerate() {
            assert_eq!(&all[copy.fn_byte as usize..copy.fn_byte as usize + 3], "fn ");
            assert_eq!(instance.copy_at(copy.fn_byte), Some(index));
            let body = copy.body;
            assert_eq!(&all[body.instance_start as usize..(body.instance_start + body.len) as usize],
                &FILES.concat()[body.original_start as usize..(body.original_start + body.len) as usize]);
        }
        // `keep(x)` in the copy of `pass` maps back to file b.
        let call = all.rfind("keep(x)").unwrap() as u32;
        assert_eq!(instance.original_body_span(3, [call, 7]), Some([find(&FILES.concat(), "keep(x)"), 7]));

        // Entries must be in rank order, and earlier files need multifile copies.
        assert!(InstanceSources::build_with(&template, &[keep, last], true).is_err());
        assert!(InstanceSources::build_with(&template, &[pass, keep], true).is_err());
        assert!(InstanceSources::build_with(&template, &[last, keep], false).is_err());
        let single = InstanceSources::build_with(&template, &[last, last], false).unwrap();
        assert!(single.continuations.is_empty());
        assert_eq!(single.sources.len(), 3);
    }

    #[test]
    fn a_diagnostic_in_a_continuation_file_names_the_template_file() {
        let template = FILES.map(str::to_string).to_vec();
        let instance = InstanceSources::build_with(
            &template, &[file_span("keep", 2), file_span("pass", 5)], true).unwrap();
        let paths = [Some(PathBuf::from("a.lani")), Some(PathBuf::from("b.lani")), Some(PathBuf::from("c.lani"))];
        // The frontend names continuation file 4 `<source pack file 4>`.
        let continuation = &instance.sources[4];
        let start = continuation.find("keep(x)").unwrap();
        let checked = diagnostic_label_from_source_span(
            "<source pack file 4>", continuation, start, "keep(x)".len(), "in __lanius_inst_1_pass");
        let mapped = instance.template_diagnostic(
            Diagnostic::error("LNC0005", "x").with_primary_label(checked), &template, Some(&paths));
        let label = mapped.primary_label.unwrap();
        assert_eq!(label.path, PathBuf::from("b.lani"));
        assert_eq!(label.byte_start, Some(FILES[1].find("keep(x)").unwrap()));
        assert_eq!(label.line, 2);
        assert_eq!(label.message, "in pass");
        // A label in a template file is unchanged.
        let kept = diagnostic_label_from_source_span("a.lani", FILES[0], 3, 1, "here");
        let unchanged = instance.template_diagnostic(
            Diagnostic::error("LNC0005", "x").with_primary_label(kept.clone()), &template, Some(&paths));
        assert_eq!(unchanged.primary_label, Some(kept));
    }
}
