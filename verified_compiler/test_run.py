#!/usr/bin/env python3
"""Focused tests for the untrusted Lean artifact presentation layer."""
import unittest

from run import (render_chunked_artifact, render_chunked_pack, render_seq_tree,
                 share_surface_token_text,
                 render_pack_modules, split_artifact_pack_term,
                 split_artifact_term, split_let_term, split_list_literal)


class ArtifactPresentationTests(unittest.TestCase):
    SAMPLE_ARTIFACT = (
        '{ Lanius.Extraction.Artifact.empty with '
        'sources := [{ path := "self.lani", bytes := [1,2] }], '
        'raw_tokens := some [⟨1,⟨0,0,2⟩⟩], '
        'tokens := [⟨1,⟨0,0,2⟩⟩], '
        'semantic_token_kinds := [7], '
        'parse_nodes := [⟨1,2,[.node 3,.token 4]⟩], '
        'parse_root := some 0 }'
    )
    SAMPLE_SURFACE_ARTIFACT = (
        SAMPLE_ARTIFACT
        .replace('parse_nodes := [⟨1,2,[.node 3,.token 4]⟩]',
                 'parse_nodes := [⟨2,0,0,0,[]⟩,⟨0,0,0,0,[.node 0]⟩]')
        .replace('parse_root := some 0 }',
                 'parse_root := some 1, surface := '
                 '(some (let i1 : List Lanius.Extraction.SurfaceItem := []; '
                 '⟨0,1,{ items := i1 }⟩)) }')
    )

    def test_split_list_preserves_nested_terms_and_quoted_commas(self):
        value = '["a,\\\"b",⟨1,[.node 2,.token 3]⟩,{ path := "x,y" }]'

        self.assertEqual(
            split_list_literal(value),
            ['"a,\\\"b"', '⟨1,[.node 2,.token 3]⟩',
             '{ path := "x,y" }'],
        )

    def test_split_list_rejects_unbalanced_term(self):
        with self.assertRaisesRegex(ValueError, "unbalanced"):
            split_list_literal("[⟨1,2]]")

    def test_split_surface_let_chain_preserves_nested_semicolons(self):
        bindings, result = split_let_term(
            "(let x1 : SurfaceExpr := (let e0 : SurfaceExpr := ⟨0,1,.break_loop⟩; e0); "
            "let bt2 : List SurfaceStmt := [⟨1,2,.continue_loop⟩]; "
            "⟨2,3,.while_loop x1 bt2⟩)")

        self.assertEqual(set(bindings), {"x1", "bt2"})
        self.assertTrue(bindings["x1"].startswith("(let e0"))
        self.assertEqual(result, "⟨2,3,.while_loop x1 bt2⟩")

    def test_render_uses_distinct_data_and_proof_names(self):
        rendered = render_chunked_artifact(self.SAMPLE_ARTIFACT)

        self.assertIn("def extractedTokenDataChunk0 : List Token", rendered)
        self.assertIn("  tokens := extractedTokenData\n", rendered)
        self.assertNotIn("def extractedTokens :", rendered)
        self.assertEqual(rendered.count("theorem extractedTokens :"), 1)
        self.assertIn('[⟨1,2,[.node 3,.token 4]⟩]', rendered)
        self.assertIn("def extractedParseNodeTree : SeqTree ParseNode", rendered)
        self.assertIn("  parse_nodes := extractedParseNodeTree.flatten", rendered)
        self.assertIn("theorem extractedParseNodeTreeChecked", rendered)
        self.assertNotIn("kernel_parse_bounded", rendered)

    def test_surface_is_a_first_class_field_and_proof_obligation(self):
        fields = split_artifact_term(self.SAMPLE_SURFACE_ARTIFACT)

        self.assertEqual(fields["parse_root"], "some 1")
        self.assertEqual(fields["surface"],
                         "(some (let i1 : List Lanius.Extraction.SurfaceItem "
                         ":= []; ⟨0,1,{ items := i1 }⟩))")

        rendered = render_chunked_artifact(self.SAMPLE_SURFACE_ARTIFACT)
        self.assertIn("import Lanius.Extraction.Reconstruction.Chunks", rendered)
        self.assertIn("def extractedSurfaceItems0 : List SurfaceItem := []",
                      rendered)
        self.assertIn("def extractedSurfaceProposal : SurfaceFile", rendered)
        self.assertIn("  parse_root := some 1 }\n", rendered)
        self.assertIn("noncomputable def extractedSyntax : Artifact", rendered)
        self.assertIn("  surface := some extractedSurfaceProposal }", rendered)
        self.assertIn("theorem extractedSurfaceMatches", rendered)
        self.assertIn(
            "extracted.surface = reconstructArtifactSurface extracted", rendered)
        self.assertIn("#print axioms extractedSurfaceMatches", rendered)

        syntax_only = render_chunked_artifact(self.SAMPLE_ARTIFACT)
        self.assertNotIn("Reconstruction.Chunks", syntax_only)
        self.assertNotIn("extractedSurfaceMatches", syntax_only)

    def test_surface_token_text_uses_authenticated_syntax_artifact(self):
        spelling = (
            "(String.fromUTF8! (ByteArray.mk (([104,105]: List Nat).toArray.map "
            "UInt8.ofNat)))")
        term = (f"⟨7,{spelling}⟩, .string 9 {spelling}, "
                f".integer 11 {spelling}, .character 13 {spelling}")

        self.assertEqual(
            share_surface_token_text(term, threshold=1),
            "⟨7,extractedLargeTokenText7⟩, .string 9 extractedLargeTokenText9, "
            ".integer 11 extractedLargeTokenText11, .character 13 "
            "extractedLargeTokenText13",
        )

    def test_surface_pack_exposes_pack_wide_reconstruction_theorem(self):
        pack = (
            "Lanius.Extraction.ArtifactPack.mk "
            "Lanius.Extraction.schemaVersion [" +
            self.SAMPLE_SURFACE_ARTIFACT + "]"
        )

        rendered = render_chunked_pack(pack)
        self.assertIn("ExtractedUnit0.extractedSurfaceMatches", rendered)
        self.assertIn("theorem extractedPackSurfacesMatch", rendered)

        modules = render_pack_modules(pack)
        valid = modules["SelfClosure/Unit0/Valid.lean"]
        self.assertIn("import Lanius.Extraction.Reconstruction.Chunks", valid)
        self.assertIn("theorem extractedSurfaceMatches", valid)
        self.assertIn("theorem extractedPackSurfacesMatch",
                      modules["SelfClosure/Pack.lean"])

    def test_balanced_tree_partitions_each_ordered_range_once(self):
        rendered, root, nodes = render_seq_tree(
            "tree", "values", "Nat", 129, 64)

        leaves = sorted(
            (node for node in nodes if node.chunk_name is not None),
            key=lambda node: node.start,
        )
        self.assertEqual(
            [(node.start, node.size) for node in leaves],
            [(0, 64), (64, 64), (128, 1)],
        )
        self.assertEqual((root.start, root.size, root.height), (0, 129, 3))
        self.assertIn(".branch 129 3", rendered)

        def assert_balanced(node):
            if node.left is None:
                return
            self.assertLessEqual(abs(node.left.height - node.right.height), 1)
            self.assertEqual(node.right.start, node.start + node.left.size)
            assert_balanced(node.left)
            assert_balanced(node.right)

        assert_balanced(root)

    def test_pack_keeps_units_separate_and_proves_each_one(self):
        pack = (
            "Lanius.Extraction.ArtifactPack.mk "
            "Lanius.Extraction.schemaVersion [" + self.SAMPLE_ARTIFACT + "," +
            self.SAMPLE_ARTIFACT.replace("self.lani", "other.lani") + "]"
        )

        self.assertEqual(len(split_artifact_pack_term(pack)), 2)
        rendered = render_chunked_pack(pack)

        self.assertIn("namespace ExtractedUnit0", rendered)
        self.assertIn("namespace ExtractedUnit1", rendered)
        self.assertIn("ArtifactPack.mk schemaVersion [ExtractedUnit0.extracted,ExtractedUnit1.extracted]", rendered)
        self.assertIn("ExtractedUnit0.extractedValid", rendered)
        self.assertIn("ExtractedUnit1.extractedValid", rendered)
        self.assertIn("∀ unit ∈ extractedPack.units, ParseArtifactValid unit", rendered)

        modules = render_pack_modules(pack)
        self.assertEqual(len(modules), 11)
        self.assertIn("namespace ExtractedUnit0", modules["SelfClosure/Unit0/Data.lean"])
        self.assertIn("import SelfClosure.Unit0.Valid", modules["SelfClosure/Pack.lean"])
        self.assertIn("import SelfClosure.Unit1.Valid", modules["SelfClosure/Pack.lean"])
        self.assertIn("import SelfClosure.Unit0.View", modules["SelfClosure/Unit0/Nodes.lean"])
        self.assertIn("import SelfClosure.Unit0.Nodes", modules["SelfClosure/Unit0/Valid.lean"])

        unit0_data = modules["SelfClosure/Unit0/Data.lean"]
        unit0_view = modules["SelfClosure/Unit0/View.lean"]
        unit0_nodes = modules["SelfClosure/Unit0/Nodes.lean"]
        unit0_metadata = modules["SelfClosure/Unit0/Metadata.lean"]
        unit0_valid = modules["SelfClosure/Unit0/Valid.lean"]
        self.assertIn("noncomputable def extracted : Artifact", unit0_data)
        self.assertIn("def extractedDecodedSourceBytes", unit0_data)
        self.assertIn("def extractedSourceByteTree : SeqTree (Fin 256)", unit0_data)
        self.assertNotIn("theorem extractedSourceDecoded", unit0_data)
        self.assertIn("theorem extractedSourceDecoded", unit0_view)
        self.assertIn("noncomputable def extractedParseView", unit0_view)
        self.assertNotIn("theorem extractedParseNodeTreeChecked", unit0_view)
        self.assertIn("theorem extractedParseNodeTreeChecked", unit0_nodes)
        self.assertNotIn("theorem extractedTokens", unit0_nodes)
        self.assertIn("theorem extractedTokens", unit0_metadata)
        self.assertIn("theorem extractedTokenValid", unit0_metadata)
        self.assertIn("theorem extractedSemantic", unit0_metadata)
        self.assertNotIn("theorem extractedValid", unit0_metadata)
        self.assertIn("theorem extractedValid", unit0_valid)


if __name__ == "__main__":
    unittest.main()
