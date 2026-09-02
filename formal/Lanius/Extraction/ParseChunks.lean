import Lanius.Extraction.ParseTrace
import Lanius.Data.SeqTree

namespace Lanius.Extraction

open Lanius.Data

syntax "kernel_parse_nodes_chunk " ident ", " ident " for " term ", " term
  ", " num ", " num : command

macro_rules
  | `(kernel_parse_nodes_chunk $checked:ident, $length:ident for
        $artifact:term, $view:term, $start:num, $count:num) =>
      `(section
        theorem $checked :
            checkNodesFromView laniusGrammar $artifact $view $start
              (($view).cache.parseNodes.rangeToList $start $count) = true := by
          with_unfolding_all rfl
        theorem $length :
            ((($view).cache.parseNodes.rangeToList $start $count)).length =
              $count := by
          with_unfolding_all rfl
        end)

syntax "kernel_parse_nodes_cached_chunk " ident ", " ident " for " term ", " term
  ", " num ", " num : command

macro_rules
  | `(kernel_parse_nodes_cached_chunk $checked:ident, $length:ident for
        $artifact:term, $view:term, $start:num, $count:num) =>
      `(section
        theorem $checked :
            checkNodesFromParseView laniusGrammar $artifact $view $start
              (($view).artifactView.cache.parseNodes.rangeToList $start $count) = true := by
          with_unfolding_all rfl
        theorem $length :
            ((($view).artifactView.cache.parseNodes.rangeToList $start $count)).length =
              $count := by
          with_unfolding_all rfl
        end)

syntax "kernel_parse_token " ident " for " term : command
macro_rules
  | `(kernel_parse_token $checked:ident for $artifact:term) =>
      `(theorem $checked : checkTokenArtifact $artifact = true := by
          with_unfolding_all rfl)

syntax "kernel_parse_token_header " ident " for " term : command
macro_rules
  | `(kernel_parse_token_header $checked:ident for $artifact:term) =>
      `(theorem $checked : checkTokenArtifactTraceHeader $artifact = true := by
          with_unfolding_all rfl)

syntax "kernel_parse_token_raw " ident " for " term : command
macro_rules
  | `(kernel_parse_token_raw $checked:ident for $artifact:term) =>
      `(theorem $checked : checkTokenArtifactRawTrace $artifact = true := by
          with_unfolding_all rfl)

syntax "kernel_parse_token_canonical " ident " for " term : command
macro_rules
  | `(kernel_parse_token_canonical $checked:ident for $artifact:term) =>
      `(theorem $checked : checkTokenArtifactCanonicalTrace $artifact = true := by
          with_unfolding_all rfl)

syntax "kernel_parse_semantic " ident " for " term : command
macro_rules
  | `(kernel_parse_semantic $checked:ident for $artifact:term) =>
      `(theorem $checked :
          semanticKindsValid laniusGrammar ($artifact).tokens
            ($artifact).semantic_token_kinds = true := by
          with_unfolding_all rfl)

syntax "kernel_parse_root " ident ", " ident ", " ident ", " ident
  " for " term : command

theorem parseOptionEqSomeGet {value : Option α}
    (present : value.isSome = true) : value = some (value.get present) := by
  cases value <;> simp_all

macro_rules
  | `(kernel_parse_root $present:ident, $root:ident, $found:ident,
        $shape:ident for $artifact:term) =>
      `(section
        theorem $present : ($artifact).parse_root.isSome = true := by
          with_unfolding_all rfl
        def $root : ParseNodeId := ($artifact).parse_root.get $present
        theorem $found : ($artifact).parse_root = some $root :=
          parseOptionEqSomeGet $present
        theorem $shape :
            rootShapeValid laniusGrammar ($artifact).tokens.length
              ($artifact).parse_nodes $root = true := by
          with_unfolding_all rfl
        end)

theorem parseArtifactValid_of_view_checks
    (artifact : Artifact) (view : ArtifactView artifact) (rootId : Nat)
    (tokensAccepted : checkTokenArtifact artifact = true)
    (semanticAccepted : semanticKindsValid laniusGrammar artifact.tokens
      artifact.semantic_token_kinds = true)
    (nodesAccepted : checkNodesFromView laniusGrammar artifact view 0
      artifact.parse_nodes = true)
    (rootFound : artifact.parse_root = some rootId)
    (rootAccepted : rootShapeValid laniusGrammar artifact.tokens.length
      artifact.parse_nodes rootId = true) :
    ParseArtifactValid artifact := by
  apply parseArtifactValid_of_trace artifact rootId tokensAccepted
    semanticAccepted
  · apply checkNodesFrom_sound
    rw [← checkNodesFromView_eq laniusGrammar artifact view]
    exact nodesAccepted
  · exact rootFound
  · exact rootAccepted

end Lanius.Extraction
