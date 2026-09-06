import Lanius.Extraction.ParseTrace
import Lanius.Data.SeqTree
import Lanius.Extraction.KernelReduction

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
          kernel_rfl
        theorem $length :
            ((($view).cache.parseNodes.rangeToList $start $count)).length =
              $count := by
          kernel_rfl
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
          kernel_rfl
        theorem $length :
            ((($view).artifactView.cache.parseNodes.rangeToList $start $count)).length =
              $count := by
          kernel_rfl
        end)

syntax "kernel_parse_token " ident " for " term : command
macro_rules
  | `(kernel_parse_token $checked:ident for $artifact:term) =>
      `(theorem $checked : checkTokenArtifact $artifact = true := by
          kernel_rfl)


syntax "kernel_parse_semantic " ident " for " term : command
macro_rules
  | `(kernel_parse_semantic $checked:ident for $artifact:term) =>
      `(theorem $checked :
          semanticKindsValid laniusGrammar ($artifact).tokens
            ($artifact).semantic_token_kinds = true := by
          kernel_rfl)

syntax "kernel_parse_root " ident ", " ident ", " ident ", " ident
  " for " term ", " term : command

theorem parseOptionEqSomeGet {value : Option α}
    (present : value.isSome = true) : value = some (value.get present) := by
  cases value <;> simp_all

macro_rules
  | `(kernel_parse_root $present:ident, $root:ident, $found:ident,
        $shape:ident for $artifact:term, $view:term) =>
      `(section
        theorem $present : ($artifact).parse_root.isSome = true := by
          kernel_rfl
        def $root : ParseNodeId := ($artifact).parse_root.get $present
        theorem $found : ($artifact).parse_root = some $root :=
          parseOptionEqSomeGet $present
        theorem $shape :
            rootShapeValid laniusGrammar ($artifact).tokens.length
              ($artifact).parse_nodes $root = true := by
          apply rootShapeValid_of_view laniusGrammar $view $root
          kernel_rfl
        end)

theorem parseArtifactValid_of_view_validity
    (artifact : Artifact) (view : ArtifactView artifact) (rootId : Nat)
    (tokensValid : TokenArtifactValid artifact)
    (semanticAccepted : semanticKindsValid laniusGrammar artifact.tokens
      artifact.semantic_token_kinds = true)
    (nodesAccepted : checkNodesFromView laniusGrammar artifact view 0
      artifact.parse_nodes = true)
    (rootFound : artifact.parse_root = some rootId)
    (rootAccepted : rootShapeValid laniusGrammar artifact.tokens.length
      artifact.parse_nodes rootId = true) :
    ParseArtifactValid artifact := by
  refine ⟨tokensValid, semanticAccepted, ?_, rootId, rootFound,
    rootShapeValid_sound rootAccepted⟩
  apply checkNodesFrom_sound
  rw [← checkNodesFromView_eq laniusGrammar artifact view]
  exact nodesAccepted

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
  apply parseArtifactValid_of_view_validity artifact view rootId
    (checkTokenArtifact_sound tokensAccepted) semanticAccepted
  · exact nodesAccepted
  · exact rootFound
  · exact rootAccepted

end Lanius.Extraction
