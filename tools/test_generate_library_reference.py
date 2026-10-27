"""Focused CPU-only checks of documentation extraction and output ownership."""
import json
import os
from pathlib import Path
import tempfile
import unittest

import generate_library_reference as reference


class DeclarationTests(unittest.TestCase):
    def scan(self, source):
        return reference.Scanner(source, "example.lani").scan()

    def test_comments_literals_and_source_locations(self):
        source = '''// λ pub fn fake() {}\n/* pub struct Fake { x: i32 } */\nmodule core::sample;
pub const TEXT: str = "pub fn nope() { \\\" }";
pub fn actual() -> char { let a: char = '\\''; return a; }
'''
        module = self.scan(source)
        self.assertEqual([item.name for item in module.declarations], ["TEXT", "actual"])
        self.assertEqual(module.public_keywords, 2)
        item = module.declarations[1]
        self.assertEqual((item.line, item.end_line), (5, 5))
        self.assertEqual(item.signature, "pub fn actual() -> char")
        token = next(token for token in reference.tokens(source) if token.text == "actual")
        self.assertEqual(source[token.start:token.end], "actual")

    def test_multiline_bounds_const_generics_and_exact_header(self):
        header = '''pub fn choose<T: a::Trait<core::pair::Pair<i32, u8>>, const N: usize>(
    value: [T; N], fallback: &T
) -> core::result::Result<T, Error>
    where T: a::More<T> + a::Other<T>, T: a::Final<T>'''
        module = self.scan("module core::sample;\n" + header + " { return fallback; }")
        self.assertEqual(module.declarations[0].signature, header)
        self.assertEqual(module.declarations[0].line, 2)
        self.assertEqual(module.declarations[0].end_line, 5)

    def test_multiple_declarations_on_one_line_and_private_bodies(self):
        module = self.scan('''module core::sample; fn helper() { let x = "pub enum Fake {}"; }
pub fn first() {} pub fn second() { if (true) { let a: [i32;2] = [1,2]; } }
struct Hidden { field: i32 } enum HiddenEnum { Gone }
''')
        self.assertEqual([item.name for item in module.declarations], ["first", "second"])
        self.assertNotIn("let a", "\n".join(item.signature for item in module.declarations))

    def test_fields_and_variants_retain_nested_payloads(self):
        module = self.scan('''module core::sample;
pub struct Value<T, const N: usize> where T: a::Trait<T> {
  first: core::pair::Pair<T, core::option::Option<T>>, second: [u8; N],
}
pub enum Choice<T> { Empty, Pair(core::pair::Pair<T, T>, [u8; 2]), One(T), }
''')
        record, enum = module.declarations
        self.assertEqual(record.signature, "pub struct Value<T, const N: usize> where T: a::Trait<T>")
        self.assertEqual([child.signature for child in record.children], [
            "first: core::pair::Pair<T, core::option::Option<T>>", "second: [u8; N]"])
        self.assertEqual([child.name for child in enum.children], ["Empty", "Pair", "One"])
        self.assertEqual(enum.children[1].signature, "Pair(core::pair::Pair<T, T>, [u8; 2])")
        self.assertEqual(record.children[0].line, 3)

    def test_impl_and_trait_contexts_are_not_flattened(self):
        module = self.scan('''module core::sample;
pub trait Read<T> where T: a::Value<T> { fn read(value: T) -> T; pub fn size(value: T) -> i32; }
pub impl<T> Read<T> for Value<T> where T: a::Value<T> { pub fn read(value: T) -> T { return value; } fn internal() {} }
impl Other { pub fn read(&self) -> i32 { return 2; } }
trait Private { pub fn hidden() -> i32; }
''')
        trait, first, second = module.declarations
        self.assertEqual([item.name for item in trait.children], ["read", "size"])
        self.assertEqual(trait.children[0].kind, "trait member")
        self.assertEqual(first.signature, "pub impl<T> Read<T> for Value<T> where T: a::Value<T>")
        self.assertEqual([item.name for item in first.children], ["read"])
        self.assertEqual(second.signature, "impl Other")
        self.assertEqual(second.children[0].signature, "pub fn read(&self) -> i32")

    def test_private_nominal_implementations_do_not_publish_helpers(self):
        source = '''module core::sample;
pub trait Read<T> { pub fn read(value:T) -> T; }
pub impl<T> Read<T> for Hidden<T> { pub fn read(value:T) -> T { return value; } }
impl Hidden<i32> { pub fn leak() {} }
pub impl<T> core::sample::Hidden<T> { pub fn leak_qualified() {} }
pub impl Read<i32> for Secret { pub fn read(value:i32) -> i32 { return value; } }
struct Hidden<T> { value:T }
enum Secret { Empty }
'''
        module = self.scan(source)
        self.assertEqual([(item.kind, item.name) for item in module.declarations], [("trait", "Read")])
        self.assertEqual([item.name for item in module.declarations[0].children], ["read"])
        self.assertEqual(module.public_keywords, sum(token.text == "pub" for token in reference.tokens(source)))

    def test_public_unknown_external_and_shadowed_receivers_remain_visible(self):
        module = self.scan('''module core::sample;
struct Hidden<T> { value:T }
pub struct Visible<T> { value:T }
pub trait Read<T> { fn read(value:T) -> T; }
pub impl<T, const N:usize> Read<T> for Visible<Hidden<T>> where T:a::Trait<T> { pub fn read(value:T) -> T { return value; } }
impl core::sample::Visible<i32> { pub fn local() {} }
pub impl Read<i32> for external::Hidden<i32> { pub fn external() {} }
pub impl Read<i32> for i32 { pub fn builtin() {} }
pub impl Read<i32> for Imported { pub fn unknown() {} }
pub impl<Hidden:a::Trait<core::pair::Pair<i32,u8>>> Read<Hidden> for Hidden { pub fn generic() {} }
pub impl Read<i32> for [Hidden<i32>;2] { pub fn array() {} }
''')
        blocks = [item for item in module.declarations if item.kind == "impl"]
        self.assertEqual([item.children[0].name for item in blocks],
                         ["read", "local", "external", "builtin", "unknown", "generic", "array"])
        self.assertEqual([item.name for item in module.declarations[0].children], ["value"])
        self.assertEqual([item.name for item in module.declarations[1].children], ["read"])

    def test_hidden_receiver_still_rejects_unsupported_public_syntax(self):
        with self.assertRaisesRegex(reference.ReferenceError, "unsupported public declaration shape"):
            self.scan('''module core::sample; struct Hidden {}
pub impl Hidden { pub unsafe fn action() {} }
''')

    def test_externs_aliases_and_constant_initializer(self):
        module = self.scan('''module core::sample;
pub extern "lanius_std" fn send(value: ptr, count: usize) -> i32;
pub extern fn other();
pub type Alias<T> where T: a::Value<T> = core::option::Option<T>;
pub const PAIR: Pair<i32, i32> = Pair { first: 1, second: 2 };
''')
        self.assertEqual([item.kind for item in module.declarations], ["extern function", "extern function", "type alias", "constant"])
        self.assertTrue(module.declarations[0].signature.endswith("-> i32;"))
        self.assertEqual(module.declarations[-1].signature, "pub const PAIR: Pair<i32, i32> = Pair { first: 1, second: 2 };")

    def test_unknown_or_incomplete_shapes_fail_at_source(self):
        for body in ["pub unsafe fn action() {}", "pub union Value {}", 'pub extern "C" {}',
                     "pub fn absent() -> i32;", "pub fn absent { }", "pub struct Broken {", "pub fn broken() { [) }",
                     "pub trait Broken { pub fn absent() {} }", "pub enum Choice { Value { x: i32 } }"]:
            with self.subTest(body=body), self.assertRaisesRegex(reference.ReferenceError, r"example.lani:\d+:"):
                self.scan("module core::sample; " + body)
        for source in ['module core::sample; /* no end', 'module core::sample; pub const X: str = "no end']:
            with self.assertRaisesRegex(reference.ReferenceError, "unterminated"):
                self.scan(source)

    def test_duplicate_names_rejected_only_within_owner(self):
        for body in ["pub fn x() {} pub fn x() {}", "pub struct Value { x: i32, x: i32 }",
                     "pub enum Value { A, A }", "pub impl Value { pub fn x() {} pub fn x() {} }"]:
            with self.subTest(body=body), self.assertRaisesRegex(reference.ReferenceError, "duplicate"):
                self.scan("module core::sample; " + body)
        module = self.scan("module core::sample; pub impl A { pub fn x() {} } pub impl A { pub fn y() {} } pub impl B { pub fn x() {} }")
        self.assertEqual(len(module.declarations), 3)

    def test_module_and_import_declarations(self):
        module = self.scan("module core::sample; import core::option; import ext::thing; pub fn done() {}")
        self.assertEqual(module.name, "core::sample")
        self.assertEqual(module.imports, [("core::option", 1), ("ext::thing", 1)])
        for source in ["pub fn missing() {}", "module core::a; module core::b;", 'module core::a; import "other";',
                       "module core::a; import core::b as b;", "module core::a; import core::b::*;",
                       "module core::a; use core::b;", "module core::a; import core::b; import core::b;"]:
            with self.subTest(source=source), self.assertRaises(reference.ReferenceError):
                self.scan(source)

    def test_item_imports_and_ergonomic_bodies_preserve_source_spans(self):
        module = self.scan('''module core::sample;
import core::result::Result;
pub fn read() -> Result<i32, Error> {
    let item = load()?;
    let inferred = choose(item);
    return Ok(inferred);
}
''')
        self.assertEqual(module.imports, [("core::result::Result", 2)])
        self.assertEqual(module.declarations[0].signature, "pub fn read() -> Result<i32, Error>")
        self.assertEqual((module.declarations[0].line, module.declarations[0].end_line), (3, 3))
        self.assertEqual(module.public_keywords, 1)

    def test_public_markers_cannot_disappear_in_skipped_shapes(self):
        for source in ["module core::a; struct Private { pub field: i32 }",
                       "module core::a; fn private() { pub fn nested() {} }"]:
            with self.subTest(source=source), self.assertRaisesRegex(reference.ReferenceError, "outside inventoried item boundary"):
                self.scan(source)


class GenerationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / "stdlib/core").mkdir(parents=True)
        (self.root / "extended/ext").mkdir(parents=True)
        (self.root / "tools").mkdir()
        (self.root / "docs").mkdir()
        (self.root / "stdlib/core/a.lani").write_text("module core::a; pub fn first<T>(value:T) -> T { return value; }\n")
        (self.root / "extended/ext/b.lani").write_text("module ext::b; import core::a; pub enum Item { A, B(i32) }\n")
        self.metadata({})

    def metadata(self, entries):
        (self.root / "tools/library_reference_metadata.json").write_text(json.dumps({"modules": entries}))

    def test_generation_order_default_status_and_source_links(self):
        output, modules = reference.generate(self.root)
        self.assertEqual([module.name for module in modules], ["core::a", "ext::b"])
        page = output["docs/api/ext/b.md"]
        self.assertIn("No contract guide registered", page)
        self.assertIn("Profile: **Source inventory**", page)
        self.assertIn("[core::a](../core/a.md)", page)
        self.assertIn("../../../extended/ext/b.lani#L1", page)
        self.assertIn("pub fn first<T>(value:T) -> T", output["docs/api/core/a.md"])
        self.assertNotIn("return value", output["docs/api/core/a.md"])
        self.assertEqual(output, reference.generate(self.root)[0])
        self.assertNotIn(str(self.root), "\n".join(output.values()))

    def test_item_import_links_the_public_declaration_and_keeps_module_import(self):
        (self.root / "extended/ext/b.lani").write_text('''module ext::b;
import core::a;
import core::a::first;
pub fn call(value:i32) -> i32 { let result = first(value); return result; }
''')
        output, modules = reference.generate(self.root)
        page = output["docs/api/ext/b.md"]
        self.assertIn("[core::a](../core/a.md) · [source](../../../extended/ext/b.lani#L2)", page)
        self.assertIn("[core::a::first](../core/a.md) (item: function)", page)
        self.assertIn("[declaration](../../../stdlib/core/a.lani#L1)", page)
        self.assertIn("[source](../../../extended/ext/b.lani#L3)", page)
        self.assertEqual(modules[1].imports, [("core::a", 2), ("core::a::first", 3)])
        self.assertNotIn("docs/api/core/a/first.md", output)

    def test_item_import_accepts_public_declaration_kinds_and_enum_variants(self):
        (self.root / "stdlib/core/a.lani").write_text('''module core::a;
pub struct Value { field:i32 }
pub enum Choice { One(i32), Empty }
pub trait Read { fn read() -> i32; }
pub const LIMIT:i32 = 4;
pub type Alias = i32;
pub extern "C" fn native() -> i32;
''')
        imports = [("Value", "struct"), ("Choice", "enum"), ("One", "variant"),
                   ("Empty", "variant"), ("Read", "trait"), ("LIMIT", "constant"),
                   ("Alias", "type alias"), ("native", "extern function")]
        (self.root / "extended/ext/b.lani").write_text(
            "module ext::b;\n" + "".join(f"import core::a::{name};\n" for name, _ in imports))
        output, _ = reference.generate(self.root)
        page = output["docs/api/ext/b.md"]
        for name, kind in imports:
            self.assertIn(f"[core::a::{name}](../core/a.md) (item: {kind})", page)

    def test_whole_module_path_wins_over_same_named_public_item(self):
        nested = self.root / "stdlib/core/a/first.lani"
        nested.parent.mkdir()
        nested.write_text("module core::a::first; pub fn nested() {}\n")
        (self.root / "extended/ext/b.lani").write_text("module ext::b; import core::a::first;\n")
        output, _ = reference.generate(self.root)
        page = output["docs/api/ext/b.md"]
        self.assertIn("[core::a::first](../core/a/first.md)", page)
        self.assertNotIn("(item:", page)
        self.assertNotIn("[declaration]", page)

    def test_missing_private_and_nested_items_are_rejected_at_import_line(self):
        (self.root / "stdlib/core/a.lani").write_text('''module core::a;
fn private_function() {}
struct PrivateType { field:i32 }
enum PrivateEnum { PrivateVariant }
const PRIVATE:i32 = 1;
pub struct Value { field:i32 }
pub enum Choice { Variant }
impl Value { pub fn method() {} }
''')
        for name in ["absent", "private_function", "PrivateType", "PrivateEnum", "PrivateVariant",
                     "PRIVATE", "field", "method", "Value::method", "Choice::Variant"]:
            (self.root / "extended/ext/b.lani").write_text(f"module ext::b;\nimport core::a::{name};\n")
            with self.subTest(name=name), self.assertRaisesRegex(
                    reference.ReferenceError, r"extended/ext/b.lani:2: .*absent from inventory"):
                reference.generate(self.root)

    def test_item_imports_do_not_reexport_imported_names(self):
        (self.root / "extended/ext/b.lani").write_text("module ext::b; import core::a::first;\n")
        (self.root / "extended/ext/c.lani").write_text("module ext::c;\nimport ext::b::first;\n")
        with self.assertRaisesRegex(reference.ReferenceError, "public item absent from inventory: ext::b::first"):
            reference.generate(self.root)

    def test_reviewed_support_status_and_declaration_note(self):
        (self.root / "docs/contract.md").write_text("# Reviewed contract\n")
        self.metadata({"core::a": {"guides": ["docs/contract.md"], "role": "support", "profile": "Mixed host bindings", "note": "Reviewed module note.", "declarations": {"first": "Reviewed declaration note."}}})
        output, _ = reference.generate(self.root)
        self.assertIn("support/implementation data", output["docs/api/core/a.md"])
        self.assertIn("Reviewed declaration note.", output["docs/api/core/a.md"])
        index = output["docs/api/README.md"]
        self.assertGreater(index.index("[core::a]"), index.index("## Support and implementation data"))
        self.assertIn("[ext::b]", index[index.index("## Modules without a registered"):])

    def test_unknown_metadata_invalid_guide_and_unknown_declaration(self):
        for entries in [{"core::absent": {}}, {"core::a": {"extra": True}}, {"core::a": {"profile": "verified"}},
                        {"core::a": {"guides": ["../private.md"]}}, {"core::a": {"guides": ["."]}},
                        {"core::a": {"declarations": {"absent": "note"}}}]:
            with self.subTest(entries=entries):
                self.metadata(entries)
                with self.assertRaises(reference.ReferenceError):
                    reference.generate(self.root)
        (self.root / "tools/library_reference_metadata.json").write_text('{"modules": {}, "modules": {}}')
        with self.assertRaisesRegex(reference.ReferenceError, "duplicate metadata"):
            reference.generate(self.root)

    def test_source_identity_missing_import_and_symlinks(self):
        path = self.root / "stdlib/core/a.lani"
        original = path.read_text()
        path.write_text("module core::wrong;")
        with self.assertRaisesRegex(reference.ReferenceError, "module/path mismatch"):
            reference.generate(self.root)
        path.write_text("module core::a; import core::absent;")
        with self.assertRaisesRegex(reference.ReferenceError, "absent from inventory"):
            reference.generate(self.root)
        path.write_text(original)
        path.rename(path.with_suffix(".saved"))
        path.symlink_to(path.with_suffix(".saved"))
        with self.assertRaisesRegex(reference.ReferenceError, "symlink"):
            reference.generate(self.root)

    def test_nonregular_sources_rejected_without_waiting_for_writer(self):
        fifo = self.root / "stdlib/core/fifo.lani"
        os.mkfifo(fifo)
        with self.assertRaisesRegex(reference.ReferenceError, "not a regular file"):
            reference.generate(self.root)

    def test_generated_output_check_is_read_only_and_reports_stale_pages(self):
        output, _ = reference.generate(self.root)
        self.assertEqual(set(reference.publish(self.root, output, True)), set(output))
        self.assertFalse((self.root / "docs/api").exists())
        reference.publish(self.root, output, False)
        self.assertEqual(reference.publish(self.root, output, True), [])
        page = self.root / "docs/api/core/a.md"
        original = page.read_text()
        page.write_text(original + "stale\n")
        self.assertEqual(reference.publish(self.root, output, True), ["docs/api/core/a.md"])
        self.assertEqual(page.read_text(), original + "stale\n")
        reference.publish(self.root, output, False)
        self.assertEqual(page.read_text(), original)

    def test_only_owned_generated_pages_replaced_or_deleted(self):
        output, _ = reference.generate(self.root)
        base = self.root / "docs/api"
        base.mkdir()
        (base / "README.md").write_text("handwritten\n")
        with self.assertRaisesRegex(reference.ReferenceError, "refusing to replace"):
            reference.publish(self.root, output, False)
        self.assertEqual((base / "README.md").read_text(), "handwritten\n")
        self.assertFalse((base / "core").exists())
        (base / "README.md").unlink()
        (base / "notes.md").write_text("handwritten notes\n")
        (base / "old.md").write_text(reference.BANNER + "old generated page\n")
        reference.publish(self.root, output, False)
        self.assertFalse((base / "old.md").exists())
        self.assertEqual((base / "notes.md").read_text(), "handwritten notes\n")

    def test_symlinked_output_and_non_directory_ancestor_refused(self):
        output, _ = reference.generate(self.root)
        base = self.root / "docs/api"
        elsewhere = self.root / "elsewhere"
        elsewhere.mkdir()
        base.symlink_to(elsewhere, target_is_directory=True)
        with self.assertRaisesRegex(reference.ReferenceError, "symlink"):
            reference.publish(self.root, output, False)
        self.assertEqual(list(elsewhere.iterdir()), [])
        base.unlink()
        base.mkdir()
        (base / "core").write_text("user content")
        with self.assertRaisesRegex(reference.ReferenceError, "non-directory"):
            reference.publish(self.root, output, False)
        self.assertFalse((base / "README.md").exists())

    def test_code_fences_cannot_be_closed_by_source_literal(self):
        fenced = reference.code('pub const TEXT: str = "```";')
        self.assertTrue(fenced.startswith("````lanius\n"))
        self.assertTrue(fenced.endswith("\n````\n"))

    def test_whole_current_tree_has_one_page_per_source_and_all_import_links(self):
        output, modules = reference.generate(reference.ROOT)
        sources = set()
        for directory in ["stdlib", "extended"]:
            sources.update(path.relative_to(reference.ROOT).as_posix()
                           for path in (reference.ROOT / directory).rglob("*.lani"))
        self.assertEqual({module.path for module in modules}, sources)
        self.assertEqual(len(output), len(modules) + 1)
        self.assertTrue(all(text.startswith(reference.BANNER) for text in output.values()))
        self.assertTrue(all(reference.page_path(module) in output for module in modules))
        for module in modules:
            source = reference.read_regular(reference.ROOT / module.path)
            self.assertEqual(module.public_keywords, sum(token.text == "pub" for token in reference.tokens(source)))
            lines = source.splitlines(keepends=True)

            def check_spans(items):
                for item in items:
                    self.assertIn(item.signature, "".join(lines[item.line - 1:item.end_line]),
                                  (module.name, item.kind, item.name))
                    check_spans(item.children)
            check_spans(module.declarations)


if __name__ == "__main__":
    unittest.main()
