//! Instance copies: one frontend run checks many environments of one generic
//! body by appending a renamed copy of the body's declaration per environment
//! after the template unit's text. Each copy is its own lexical scope, so
//! entries never compete for one scope.
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
    type_checker::CheckedOwnerSpan,
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

/// Template sources with the copies appended to the last file.
#[derive(Clone, Debug)]
pub(super) struct InstanceSources {
    pub sources: Arc<[String]>,
    /// Global byte length of the template text.
    pub template_len: u32,
    pub copies: Vec<InstanceCopy>,
}

impl InstanceSources {
    /// Whether a body can replay as a copy. Copies are appended to the
    /// template's last file, so they resolve names in that file's module
    /// and imports: a body declared in another file, or a trait-impl method
    /// whose self type is declared in another file, replays in its original
    /// scope instead.
    pub(super) fn copyable(template: &[String], span: &CheckedOwnerSpan) -> bool {
        let Some(last) = template.last() else { return false };
        let total = template.iter().map(String::len).sum::<usize>();
        let last_start = total - last.len();
        let in_last = |byte: u32| (byte as usize) >= last_start && (byte as usize) < total;
        in_last(span.first_byte()) && (span.end_byte as usize) <= total
            && span.enclosing_impl
                .and_then(|header| header.trait_cut)
                .is_none_or(|cut| in_last(cut.self_declaration_byte))
    }

    /// Copy each span once, in the given order. Spans index the template's
    /// global bytes; a top-level function copy is
    /// `fn __lanius_inst_<n>_` + template[name..end], and a method copy is
    /// template[impl..brace_end] + `fn __lanius_inst_<n>_` + template[name..end]
    /// + `}`, each copy on new lines after the template text. A trait-impl
    /// method's header leaves out its trait path and `for`, so the copy is a
    /// method of an inherent impl of the same self type. `<n>` is the
    /// entry's index, unique in the unit; source names never use the
    /// reserved prefix, so a copy cannot collide with a declared method.
    pub(super) fn build(template: &[String], spans: &[CheckedOwnerSpan]) -> Result<Self> {
        ensure!(!template.is_empty(), "an instance unit needs a template source file");
        let template_len = template.iter().try_fold(0u32, |total, source| {
            u32::try_from(source.len()).ok().and_then(|len| total.checked_add(len))
        }).ok_or_else(|| anyhow!("template source pack exceeds u32 bytes"))?;
        let last_start = template_len as usize - template.last().expect("nonempty").len();
        ensure!(spans.iter().all(|span| Self::copyable(template, span)),
            "an instance copy's body is declared outside the template's last file");
        let mut text = String::new();
        let mut copies = Vec::with_capacity(spans.len());
        // Global offset of the next byte appended to `text`.
        let offset = |text: &String| -> Result<u32> {
            u32::try_from(template_len as usize + text.len())
                .map_err(|_| anyhow!("instance unit exceeds u32 bytes"))
        };
        for (index, span) in spans.iter().enumerate() {
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
        let mut sources = template.to_vec();
        let last = sources.last_mut().expect("nonempty");
        debug_assert_eq!(last_start + last.len(), template_len as usize);
        last.push_str(&text);
        offset(&text)?;
        Ok(Self { sources: sources.into(), template_len, copies })
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
        let Some(last) = files.last() else { return DiagnosticLabel { message, ..label } };
        let (Some(start), Some(end)) = (label.byte_start, label.byte_end) else {
            return DiagnosticLabel { message, ..label };
        };
        // Only a label in the last file, past its template text, is in a copy.
        if label.path != last.path || start < last.source.len() {
            return DiagnosticLabel { message, ..label };
        }
        let global = |local: usize| u32::try_from(last.global_start + local).ok();
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
    fn only_bodies_of_the_last_file_are_copyable() {
        // The same declarations split over two files: the trait impl in the
        // first, or its self type in the first.
        let split_at = find(TRAIT_TEMPLATE, "impl<T> Get") as usize;
        let impl_first = vec![TRAIT_TEMPLATE.to_string(), "fn tail() {}\n".to_string()];
        let span = trait_span(TRAIT_TEMPLATE);
        assert!(!InstanceSources::copyable(&impl_first, &span));
        assert!(InstanceSources::build(&impl_first, &[span]).is_err());

        let type_first = vec![TRAIT_TEMPLATE[..split_at].to_string(), TRAIT_TEMPLATE[split_at..].to_string()];
        assert!(!InstanceSources::copyable(&type_first, &span), "self type declared in another file");
        let mut local_type = span;
        if let Some(header) = local_type.enclosing_impl.as_mut() {
            header.trait_cut.as_mut().unwrap().self_declaration_byte = split_at as u32 + 2;
        }
        assert!(InstanceSources::copyable(&type_first, &local_type));

        // A top-level function or inherent method is copyable by its own bytes.
        let spans = spans();
        let one = vec![TEMPLATE.to_string()];
        assert!(spans.iter().all(|span| InstanceSources::copyable(&one, span)));
        let keep_end = spans[0].end_byte as usize;
        let keep_first = vec![TEMPLATE[..keep_end].to_string(), TEMPLATE[keep_end..].to_string()];
        assert!(!InstanceSources::copyable(&keep_first, &spans[0]));
        assert!(InstanceSources::copyable(&keep_first, &spans[1]));
    }
}
