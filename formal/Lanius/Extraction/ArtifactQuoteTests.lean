import Lanius.Extraction.ArtifactCacheQuote

open Lean
namespace Lanius.Extraction

open Elab Term in
elab "bounded_fixture% " n:num : term =>
  quoteBounded ((List.range n.getNat).map fun i => [i, i + 1, i * 2])

-- Kernel-checked equality across empty, short, and multi-definition data.
example : (bounded_fixture% 0 : List (List Nat)) = [] := rfl
example : (bounded_fixture% 1 : List (List Nat)) = [[0, 1, 0]] := rfl
example : (bounded_fixture% 31 : List (List Nat)) =
    (List.range 31).map (fun i => [i, i + 1, i * 2]) := rfl
example : (bounded_fixture% 32 : List (List Nat)) =
    (List.range 32).map (fun i => [i, i + 1, i * 2]) := rfl
example : (bounded_fixture% 33 : List (List Nat)) =
    (List.range 33).map (fun i => [i, i + 1, i * 2]) := rfl
set_option maxRecDepth 4096 in
example : (bounded_fixture% 257 : List (List Nat)) =
    (List.range 257).map (fun i => [i, i + 1, i * 2]) := rfl

set_option maxRecDepth 4096 in
#eval show IO Unit from do
  unless (bounded_fixture% 257 : List (List Nat)) ==
      (List.range 257).map (fun i => [i, i + 1, i * 2]) do
    throw (IO.userError "bounded quotation changed compiled data")

#eval do
  let first := "{\"schema_version\":5,\"sources\":[],\"tokens\":[],\"semantic_token_kinds\":[],\"parse_nodes\":[],\"parse_root\":null,\"surface\":null,\"resolutions\":[],\"types\":[],\"core_program\":null,\"lowering\":[]}"
  let second := "{\"schema_version\":6,\"sources\":[],\"tokens\":[],\"semantic_token_kinds\":[17],\"parse_nodes\":[],\"parse_root\":null,\"surface\":null,\"resolutions\":[],\"types\":[],\"core_program\":null,\"lowering\":[]}"
  for left in [first, second, " " ++ first, "{", "{}"] do
    for right in [first, second, " " ++ second, "{", "{}"] do
      for input in [left, left, right, left] do
        let actual ← decodeArtifactInput input
        let expected : Except String Artifact := Json.parse input >>= fromJson?
        match actual, expected with
        | .ok actual, .ok expected =>
          unless toExpr actual == toExpr expected do
            throw (IO.userError "artifact cache changed constructor data")
        | .error actual, .error expected =>
          unless actual == expected do
            throw (IO.userError "artifact cache changed the error")
        | _, _ => throw (IO.userError "artifact cache changed acceptance")

-- Compare every result with uncached decoding across replacements, repeated
-- inputs, equivalent encodings, malformed JSON, and well-formed invalid data.
#eval do
  let inputs := [
    "{\"schema_version\":1,\"units\":[]}",
    "{\"schema_version\":2,\"units\":[]}",
    "{ \"units\" : [], \"schema_version\" : 1 }",
    "{\"schema_version\":1,\"units\":[{\"schema_version\":5,\"sources\":[],\"tokens\":[],\"semantic_token_kinds\":[],\"parse_nodes\":[],\"parse_root\":null,\"surface\":null,\"resolutions\":[],\"types\":[],\"core_program\":null,\"lowering\":[]}]}",
    "{", "{}", "{\"schema_version\":1,\"units\":false}"
  ]
  for first in inputs do
    for second in inputs do
      for input in [first, first, second, first] do
        let actual ← decodeArtifactPackInput input
        let expected : Except String ArtifactPack := Json.parse input >>= fromJson?
        match actual, expected with
        | .ok actual, .ok expected =>
          unless toExpr actual == toExpr expected do
            throw (IO.userError "cached decoding changed constructor data")
        | .error actual, .error expected =>
          unless actual == expected do
            throw (IO.userError "cached decoding changed the error")
        | _, _ => throw (IO.userError "cached decoding changed acceptance")

-- Quotation still emits ordinary constructor terms checked by the kernel.
example : (artifact_pack% "{\"schema_version\":1,\"units\":[]}").schema_version = 1 := rfl
example : (artifact_pack% "{\"schema_version\":2,\"units\":[]}").schema_version = 2 := rfl
example : (artifact_pack% "{\"schema_version\":1,\"units\":[]}").schema_version = 1 := rfl


-- Reusing a node list must preserve every other field, including optional raw
-- tokens. These checks exercise the constructor-slot splice independently of
-- the real frontend fixtures.
example : (artifact_pack_unit_reusing_nodes% "{\"schema_version\":1,\"units\":[{\"schema_version\":5,\"sources\":[{\"path\":\"fixture\",\"bytes\":[97]}],\"tokens\":[],\"raw_tokens\":[],\"semantic_token_kinds\":[6],\"parse_nodes\":[],\"parse_root\":9,\"surface\":null,\"resolutions\":[],\"types\":[],\"core_program\":null,\"lowering\":[]}]}", "fixture", ([] : List ParseNode)) =
    (artifact_pack_unit_full% "{\"schema_version\":1,\"units\":[{\"schema_version\":5,\"sources\":[{\"path\":\"fixture\",\"bytes\":[97]}],\"tokens\":[],\"raw_tokens\":[],\"semantic_token_kinds\":[6],\"parse_nodes\":[],\"parse_root\":9,\"surface\":null,\"resolutions\":[],\"types\":[],\"core_program\":null,\"lowering\":[]}]}", "fixture") := rfl

example : (artifact_pack_unit_reusing_nodes% "{\"schema_version\":1,\"units\":[{\"schema_version\":5,\"sources\":[{\"path\":\"fixture\",\"bytes\":[97]}],\"tokens\":[],\"raw_tokens\":[],\"semantic_token_kinds\":[6],\"parse_nodes\":[],\"parse_root\":9,\"surface\":null,\"resolutions\":[],\"types\":[],\"core_program\":null,\"lowering\":[]}]}", "fixture",
    ([{ production := 1, nonterminal := 2, position_start := 3,
        position_end := 4, children := [] }] : List ParseNode)).parse_nodes =
    [{ production := 1, nonterminal := 2, position_start := 3,
       position_end := 4, children := [] }] := rfl

end Lanius.Extraction
