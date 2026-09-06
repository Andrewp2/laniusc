#!/usr/bin/env python3
"""Run the untrusted native extractor and wrap its output for Lean checking.

This launcher does not parse Lanius or implement runtime services. The ELF
executable uses the native runtime and OS. Output is accepted only on success.
"""
import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
import subprocess

PREFIX = """import Lanius.Extraction.ParseChunks
open Lanius.Extraction
open Lanius.Data
set_option maxRecDepth 100000
set_option linter.unnecessarySimpa false
"""
SURFACE_PREFIX = """import Lanius.Extraction.ParseChunks
import Lanius.Extraction.Reconstruction.Chunks
import Lanius.Extraction.SurfaceChecker
open Lanius.Extraction
open Lanius.Data
set_option maxRecDepth 100000
set_option linter.unnecessarySimpa false
"""
METADATA_PROOFS = """
theorem extractedTokens : checkTokenArtifact extracted = true := by kernel_rfl
theorem extractedTokenValid : TokenArtifactValid extracted :=
  checkTokenArtifact_sound extractedTokens
theorem extractedSemantic : semanticKindsValid laniusGrammar extracted.tokens
    extracted.semantic_token_kinds = true := by kernel_rfl
"""

FINAL_PROOFS = """
theorem extractedNodesCached : checkNodesFromParseView laniusGrammar extracted
    extractedParseView 0 extracted.parse_nodes = true :=
  extractedParseNodeTreeChecked
theorem extractedNodesView : checkNodesFromView laniusGrammar extracted
    extractedView 0 extracted.parse_nodes = true := by
  change checkNodesFromView laniusGrammar extracted
    extractedParseView.artifactView 0 extracted.parse_nodes = true
  rw [← checkNodesFromParseView_eq laniusGrammar extracted extractedParseView]
  exact extractedNodesCached
noncomputable def extractedRoot : Nat := extracted.parse_root.getD 0
theorem extractedRootFound : extracted.parse_root = some extractedRoot := by kernel_rfl
theorem extractedRootShapeView : rootShapeValidView laniusGrammar
    extractedView extractedRoot = true := by kernel_rfl
theorem extractedRootShape : rootShapeValid laniusGrammar extracted.tokens.length
    extracted.parse_nodes extractedRoot = true := by
  rw [← rootShapeValidView_eq laniusGrammar extractedView extractedRoot]
  exact extractedRootShapeView
theorem extractedValid : ParseArtifactValid extracted :=
  parseArtifactValid_of_view_validity extracted extractedView extractedRoot
    extractedTokenValid extractedSemantic extractedNodesView extractedRootFound
    extractedRootShape
#print axioms extractedValid
"""

@dataclass(frozen=True)
class TreeNode:
    name: str
    start: int
    size: int
    height: int
    left: "TreeNode | None" = None
    right: "TreeNode | None" = None
    chunk_name: str | None = None


@dataclass(frozen=True)
class SurfaceItemStep:
    index: int
    list_node: int
    item_node: int
    rest_node: int
    start_id: int
    finish_id: int
    item_fuel: int
    list_fuel: int


@dataclass(frozen=True)
class SurfaceStatementStep:
    index: int
    list_node: int
    statement_node: int
    rest_node: int
    start_id: int
    finish_id: int
    statement_fuel: int
    list_fuel: int
    term: str


@dataclass(frozen=True)
class SurfaceFunctionBody:
    item_index: int
    block_node: int
    list_node: int
    tail_node: int
    start_id: int
    finish_id: int
    block_fuel: int
    statements: list[SurfaceStatementStep]
    body_literal: str


@dataclass(frozen=True)
class SurfaceWhileBody:
    item_index: int
    statement_index: int
    statement_node: int
    condition_node: int
    block_node: int
    block_production: int
    list_node: int
    tail_node: int
    start_id: int
    condition_finish_id: int
    body_finish_id: int
    finish_id: int
    statement_fuel: int
    condition_term: str
    statements: list[SurfaceStatementStep]


@dataclass(frozen=True)
class SurfaceCertificate:
    items: list[str]
    root_term: str
    root_id: int
    root_parse_node: int
    tail_node: int
    final_id: int
    total_fuel: int
    steps: list[SurfaceItemStep]
    function_bodies: list[SurfaceFunctionBody]
    while_bodies: list[SurfaceWhileBody]


def render_seq_tree(tree_name: str, list_name: str, element_type: str,
                    item_count: int, chunk_size: int) -> tuple[str, TreeNode, list[TreeNode]]:
    """Build a named balanced tree over already-emitted list chunks."""
    declarations: list[str] = []
    nodes: list[TreeNode] = []
    if item_count == 0:
        root = TreeNode(tree_name, 0, 0, 1, chunk_name=list_name)
        declarations.append(
            f"def {tree_name} : SeqTree {element_type} := .leaf {list_name}\n")
        nodes.append(root)
        return "".join(declarations), root, nodes

    leaves: list[TreeNode] = []
    for index, start in enumerate(range(0, item_count, chunk_size)):
        size = min(chunk_size, item_count - start)
        name = tree_name if item_count <= chunk_size else f"{tree_name}Leaf{index}"
        chunk_name = f"{list_name}Chunk{index}"
        leaf = TreeNode(name, start, size, 1, chunk_name=chunk_name)
        leaves.append(leaf)
        if item_count > chunk_size:
            declarations.append(
                f"def {name} : SeqTree {element_type} := .leaf {chunk_name}\n")

    branch_index = 0

    def build(lo: int, hi: int, is_root: bool) -> TreeNode:
        nonlocal branch_index
        if hi - lo == 1:
            return leaves[lo]
        middle = lo + (hi - lo) // 2
        left = build(lo, middle, False)
        right = build(middle, hi, False)
        name = tree_name if is_root else f"{tree_name}Branch{branch_index}"
        if not is_root:
            branch_index += 1
        node = TreeNode(
            name, left.start, left.size + right.size,
            max(left.height, right.height) + 1, left, right)
        declarations.append(
            f"def {name} : SeqTree {element_type} :=\n"
            f"  .branch {node.size} {node.height} {left.name} {right.name}\n")
        nodes.append(node)
        return node

    if item_count <= chunk_size:
        declarations.append(
            f"def {tree_name} : SeqTree {element_type} := .leaf {list_name}Chunk0\n")
        nodes.append(leaves[0])
        root = leaves[0]
    else:
        nodes.extend(leaves)
        root = build(0, len(leaves), True)
    return "".join(declarations), root, nodes


def render_tree_invariants(nodes: list[TreeNode], capacity: int) -> str:
    """Prove tree metadata compositionally so no command scans the full table."""
    output: list[str] = []
    for node in nodes:
        output.append(
            f"theorem {node.name}Size : {node.name}.size = {node.size} := by kernel_rfl\n"
            f"theorem {node.name}Height : {node.name}.height = {node.height} := by rfl\n"
            f"theorem {node.name}Length : {node.name}.flatten.length = {node.size} := by\n")
        if node.chunk_name is not None:
            output.append("  kernel_rfl\n")
            output.append(
                f"theorem {node.name}WellFormed : {node.name}.WellFormed {capacity} := by\n"
                "  apply SeqTree.wellFormed_sound\n"
                "  kernel_rfl\n")
        else:
            assert node.left is not None and node.right is not None
            left = node.left
            right = node.right
            output.append(
                f"  change ({left.name}.flatten ++ {right.name}.flatten).length = {node.size}\n"
                f"  simpa only [List.length_append, {left.name}Length, {right.name}Length]\n"
                f"theorem {node.name}WellFormed : {node.name}.WellFormed {capacity} := by\n"
                "  change (\n"
                f"    {node.size} = {left.name}.size + {right.name}.size ∧\n"
                f"    {node.height} = Nat.max {left.name}.height {right.name}.height + 1 ∧\n"
                f"    {left.name}.WellFormed {capacity} ∧ {right.name}.WellFormed {capacity} ∧\n"
                f"    0 < {left.name}.size ∧ 0 < {right.name}.size ∧\n"
                f"    {left.name}.height ≤ {right.name}.height + 1 ∧\n"
                f"    {right.name}.height ≤ {left.name}.height + 1)\n"
                f"  rw [{left.name}Size, {right.name}Size, {left.name}Height, {right.name}Height]\n"
                f"  exact ⟨rfl, rfl, {left.name}WellFormed, {right.name}WellFormed,\n"
                "    by omega, by omega, by omega, by omega⟩\n")
    return "".join(output)


def render_parse_tree_checks(nodes: list[TreeNode]) -> str:
    """Check leaf ranges independently and compose adjacent checked trees."""
    output: list[str] = []
    for node in nodes:
        output.append(
            f"theorem {node.name}Checked : checkNodesFromParseView laniusGrammar\n"
            f"    extracted extractedParseView {node.start} {node.name}.flatten = true := by\n")
        if node.chunk_name is not None:
            output.append("  kernel_rfl\n")
        else:
            assert node.left is not None and node.right is not None
            left = node.left
            right = node.right
            output.append(
                f"  change checkNodesFromParseView laniusGrammar extracted extractedParseView\n"
                f"    {node.start} ({left.name}.flatten ++ {right.name}.flatten) = true\n"
                f"  rw [checkNodesFromParseView_append, {left.name}Checked,\n"
                f"    {left.name}Length, {right.name}Checked]\n"
                "  rfl\n")
    return "".join(output)


def split_list_literal(value: str) -> list[str]:
    """Split one emitted Lean list without interpreting any element."""
    value = value.strip()
    if not (value.startswith("[") and value.endswith("]")):
        raise ValueError("expected an emitted Lean list literal")
    body = value[1:-1]
    if not body.strip():
        return []
    pairs = {"(": ")", "[": "]", "{": "}", "⟨": "⟩"}
    closing = set(pairs.values())
    stack: list[str] = []
    quoted = False
    escaped = False
    start = 0
    items: list[str] = []
    for index, char in enumerate(body):
        if quoted:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
            continue
        if char == '"':
            quoted = True
        elif char in pairs:
            stack.append(pairs[char])
        elif char in closing:
            if not stack or stack.pop() != char:
                raise ValueError("unbalanced emitted Lean term")
        elif char == "," and not stack:
            items.append(body[start:index].strip())
            start = index + 1
    if quoted or stack:
        raise ValueError("unterminated emitted Lean term")
    items.append(body[start:].strip())
    if any(not item for item in items):
        raise ValueError("empty element in emitted Lean list")
    return items


def split_top_level(value: str, separator: str) -> list[str]:
    """Split on one character outside strings and balanced delimiters."""
    if len(separator) != 1:
        raise ValueError("top-level separator must be one character")
    pairs = {"(": ")", "[": "]", "{": "}", "⟨": "⟩"}
    closing = set(pairs.values())
    stack: list[str] = []
    quoted = False
    escaped = False
    start = 0
    parts: list[str] = []
    for index, char in enumerate(value):
        if quoted:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
            continue
        if char == '"':
            quoted = True
        elif char in pairs:
            stack.append(pairs[char])
        elif char in closing:
            if not stack or stack.pop() != char:
                raise ValueError("unbalanced emitted Lean term")
        elif char == separator and not stack:
            parts.append(value[start:index].strip())
            start = index + 1
    if quoted or stack:
        raise ValueError("unterminated emitted Lean term")
    parts.append(value[start:].strip())
    if any(not part for part in parts):
        raise ValueError("empty top-level emitted Lean segment")
    return parts


def split_let_term(term: str) -> tuple[dict[str, str], str]:
    """Split the canonical parenthesized let chain emitted for Surface nodes."""
    term = term.strip()
    if not (term.startswith("(") and term.endswith(")")):
        raise ValueError("Surface node is not a parenthesized let term")
    segments = split_top_level(term[1:-1], ";")
    bindings: dict[str, str] = {}
    for segment in segments[:-1]:
        match = re.fullmatch(
            r"let ([A-Za-z][A-Za-z0-9_]*) : .+? := (.+)", segment)
        if match is None or match.group(1) in bindings:
            raise ValueError("invalid canonical Surface let binding")
        bindings[match.group(1)] = match.group(2)
    return bindings, segments[-1]


def split_balanced_prefix(value: str) -> tuple[str, str]:
    """Split one leading balanced Lean term from its uninterpreted suffix."""
    value = value.strip()
    pairs = {"(": ")", "[": "]", "{": "}", "⟨": "⟩"}
    closing = set(pairs.values())
    if not value or value[0] not in pairs:
        raise ValueError("expected a balanced emitted Lean term")
    stack: list[str] = []
    quoted = False
    escaped = False
    for index, char in enumerate(value):
        if quoted:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
            continue
        if char == '"':
            quoted = True
        elif char in pairs:
            stack.append(pairs[char])
        elif char in closing:
            if not stack or stack.pop() != char:
                raise ValueError("unbalanced emitted Lean term")
            if not stack:
                return value[:index + 1], value[index + 1:]
    raise ValueError("unterminated emitted Lean term")


def split_tuple_literal(value: str) -> list[str]:
    value = value.strip()
    if not (value.startswith("⟨") and value.endswith("⟩")):
        raise ValueError("expected an emitted Lean tuple literal")
    return split_list_literal("[" + value[1:-1] + "]")


def parse_natural(value: str, description: str) -> int:
    value = value.strip()
    if not value.isdecimal():
        raise ValueError(f"invalid emitted {description}")
    return int(value)


def parse_node_term(value: str) -> tuple[int, list[str]]:
    fields = split_tuple_literal(value)
    if len(fields) != 5:
        raise ValueError("invalid emitted ParseNode")
    return (parse_natural(fields[0], "ParseNode production"),
            split_list_literal(fields[4]))


def parse_node_child(value: str) -> int:
    value = value.strip()
    prefix = ".node "
    if not value.startswith(prefix):
        raise ValueError("Surface reconstruction expected a parse-node child")
    return parse_natural(value[len(prefix):], "parse-node child")


def split_surface_proposal(surface: str) -> tuple[list[str], str, int, int]:
    """Split the canonical Lanius-emitted Surface file at item boundaries."""
    prefix = "(some (let "
    suffix = "))"
    if not surface.startswith(prefix) or not surface.endswith(suffix):
        raise ValueError("invalid canonical emitted Surface proposal")
    body = surface[len(prefix):-len(suffix)]
    binding, separator, body = body.partition(
        " : List Lanius.Extraction.SurfaceItem := ")
    if not separator or not binding or not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", binding):
        raise ValueError("invalid emitted Surface item binding")
    item_list, remainder = split_balanced_prefix(body)
    if not remainder.startswith("; "):
        raise ValueError("emitted Surface proposal omitted its file value")
    root_term = remainder[2:].strip()
    root_pattern = re.fullmatch(
        r"⟨([0-9]+),([0-9]+),\{ items := " + re.escape(binding) + r" \}⟩",
        root_term)
    if root_pattern is None:
        raise ValueError("invalid emitted Surface file value")
    items = split_list_literal(item_list)
    return (items, root_term, int(root_pattern.group(1)),
            int(root_pattern.group(2)))


def surface_item_location(item: str) -> tuple[int, int]:
    matches = list(re.finditer(r"⟨([0-9]+),([0-9]+),", item))
    if not matches:
        raise ValueError("invalid emitted Surface item")
    outer = matches[-1]
    return int(outer.group(1)), int(outer.group(2))


def surface_node_id_range(term: str) -> tuple[int, int]:
    """Return the first allocated ID and one past the outer located node."""
    matches = list(re.finditer(r"⟨([0-9]+),([0-9]+),", term))
    if not matches:
        raise ValueError("emitted Surface term has no located node")
    ids = [int(match.group(1)) for match in matches]
    return min(ids), int(matches[-1].group(1)) + 1


def split_function_body(item: str) -> tuple[str, list[str]] | None:
    """Find the canonical body list of a Lanius-emitted function item."""
    marker = " : Lanius.Extraction.SurfaceFunction := "
    if marker not in item:
        return None
    _, remainder = item.split(marker, 1)
    record, _ = split_balanced_prefix(remainder)
    if not (record.startswith("{") and record.endswith("}")):
        raise ValueError("function item has no canonical record")
    fields = split_list_literal("[" + record[1:-1] + "]")
    body_fields = [field for field in fields if field.startswith("body := ")]
    if len(body_fields) != 1:
        raise ValueError("function item must have exactly one body field")
    body = body_fields[0][len("body := "):]
    return body, split_list_literal(body)


TOKEN_TEXT_TERM = (
    r"\(String\.fromUTF8! \(ByteArray\.mk \(\(\[[0-9,]*\]: List Nat\)"
    r"\.toArray\.map UInt8\.ofNat\)\)\)"
)


def share_surface_token_text(term: str, threshold: int = 512) -> str:
    """Replace duplicated emitted spellings by authenticated token lookups.

    The native extractor emits every SpelledName and textual literal as both a
    token ID and a byte-expanded String.  The token ID already authenticates
    that text against the checked source, so retaining the second expansion is
    needlessly expensive for Lean's kernel (and catastrophic for large string
    literals).  Keep the token ID and derive its spelling from extractedSyntax.
    """
    spelled_name = re.compile(
        r"⟨([0-9]+)," + TOKEN_TEXT_TERM + r"⟩")
    textual_literal = re.compile(
        r"\.(integer|string|character) ([0-9]+) " + TOKEN_TEXT_TERM)
    def is_large(match: re.Match[str]) -> bool:
        byte_list = re.search(r"\[([0-9,]*)\]", match.group(0))
        if byte_list is None:
            raise ValueError("emitted token spelling has no byte list")
        contents = byte_list.group(1)
        return bool(contents) and contents.count(",") + 1 > threshold

    term = spelled_name.sub(
        lambda match: (f"⟨{match.group(1)},extractedLargeTokenText{match.group(1)}⟩"
                       if is_large(match) else match.group(0)),
        term)
    return textual_literal.sub(
        lambda match: ((f".{match.group(1)} {match.group(2)} "
                        f"extractedLargeTokenText{match.group(2)}")
                       if is_large(match) else match.group(0)),
        term)


def collect_large_surface_token_texts(
        certificate: SurfaceCertificate, threshold: int = 512
) -> dict[int, str]:
    """Collect large canonical text terms keyed by their authenticated token."""
    patterns = [
        re.compile(r"⟨([0-9]+),(" + TOKEN_TEXT_TERM + r")⟩"),
        re.compile(r"\.(?:integer|string|character) ([0-9]+) (" +
                   TOKEN_TEXT_TERM + r")"),
    ]
    found: dict[int, str] = {}
    for item in certificate.items:
        for pattern in patterns:
            for match in pattern.finditer(item):
                contents = re.search(r"\[([0-9,]*)\]", match.group(2))
                if contents is None:
                    raise ValueError("emitted token spelling has no byte list")
                size = 0 if not contents.group(1) else contents.group(1).count(",") + 1
                if size <= threshold:
                    continue
                token = int(match.group(1))
                previous = found.setdefault(token, match.group(2))
                if previous != match.group(2):
                    raise ValueError("one Surface token has conflicting spellings")
    return found


def function_parse_node(parsed_nodes: list[tuple[int, list[str]]],
                        item_node: int) -> int | None:
    production, children = parsed_nodes[item_node]
    if production == 4:
        return parse_node_child(children[0])
    if production != 3:
        return None
    public_node = parse_node_child(children[1])
    public_production, public_children = parsed_nodes[public_node]
    if public_production != 266:
        return None
    return parse_node_child(public_children[0])


def build_statement_steps(
        parsed_nodes: list[tuple[int, list[str]]], statement_terms: list[str],
        list_node: int, start_id: int, list_fuel: int
) -> tuple[list[SurfaceStatementStep], int, int, int]:
    """Authenticate one statement-list spine and its emitted ID intervals."""
    steps: list[SurfaceStatementStep] = []
    next_id = start_id
    current_list = list_node
    current_fuel = list_fuel
    for index, term in enumerate(statement_terms):
        production, children = parsed_nodes[current_list]
        if production != 73 or len(children) != 2:
            raise ValueError("Surface statement list has the wrong parse shape")
        statement_node = parse_node_child(children[0])
        rest_node = parse_node_child(children[1])
        statement_start, statement_finish = surface_node_id_range(term)
        _, statement_parse_node = surface_item_location(term)
        if statement_start != next_id or statement_parse_node != statement_node:
            raise ValueError("Surface statement identity disagrees with its parse spine")
        steps.append(SurfaceStatementStep(
            index=index,
            list_node=current_list,
            statement_node=statement_node,
            rest_node=rest_node,
            start_id=statement_start,
            finish_id=statement_finish,
            statement_fuel=current_fuel - 1,
            list_fuel=current_fuel,
            term=term,
        ))
        next_id = statement_finish
        current_list = rest_node
        current_fuel -= 1
    tail_production, tail_children = parsed_nodes[current_list]
    if tail_production != 74 or tail_children:
        raise ValueError("Surface statement list has no canonical empty tail")
    return steps, current_list, next_id, current_fuel


def build_while_body(
        parsed_nodes: list[tuple[int, list[str]]], item_index: int,
        statement: SurfaceStatementStep
) -> SurfaceWhileBody | None:
    production, children = parsed_nodes[statement.statement_node]
    if production != 80:
        return None
    if len(children) != 5:
        raise ValueError("Surface while statement has the wrong parse shape")
    bindings, result = split_let_term(statement.term)
    result_fields = split_tuple_literal(result)
    if len(result_fields) != 3:
        raise ValueError("Surface while statement has no located result")
    match = re.fullmatch(
        r"\.while_loop ([A-Za-z][A-Za-z0-9_]*) ([A-Za-z][A-Za-z0-9_]*)",
        result_fields[2])
    if match is None:
        raise ValueError("Surface while value is not canonical")
    condition_name, body_name = match.groups()
    if condition_name not in bindings or body_name not in bindings:
        raise ValueError("Surface while value references an absent binding")
    condition_term = bindings[condition_name]
    body_literal = bindings[body_name]
    body_terms = split_list_literal(body_literal)
    condition_node = parse_node_child(children[2])
    block_node = parse_node_child(children[4])
    block_production, block_children = parsed_nodes[block_node]
    if block_production not in (12, 14, 71, 72) or len(block_children) < 2:
        raise ValueError("Surface while body has the wrong block shape")
    list_node = parse_node_child(block_children[1])
    condition_start, condition_finish = surface_node_id_range(condition_term)
    if condition_start != statement.start_id:
        raise ValueError("Surface while condition has a discontinuous identity")
    child_fuel = statement.statement_fuel - 1
    body_steps, tail_node, body_finish, _ = build_statement_steps(
        parsed_nodes, body_terms, list_node, condition_finish, child_fuel - 1)
    outer_id = parse_natural(result_fields[0], "Surface while ID")
    outer_parse = parse_natural(result_fields[1], "Surface while parse node")
    if (outer_id != body_finish or outer_parse != statement.statement_node
            or statement.finish_id != body_finish + 1):
        raise ValueError("Surface while result has a discontinuous identity")
    return SurfaceWhileBody(
        item_index=item_index,
        statement_index=statement.index,
        statement_node=statement.statement_node,
        condition_node=condition_node,
        block_node=block_node,
        block_production=block_production,
        list_node=list_node,
        tail_node=tail_node,
        start_id=statement.start_id,
        condition_finish_id=condition_finish,
        body_finish_id=body_finish,
        finish_id=statement.finish_id,
        statement_fuel=statement.statement_fuel,
        condition_term=condition_term,
        statements=body_steps,
    )


def build_surface_certificate(fields: dict[str, str]) -> SurfaceCertificate:
    surface = fields.get("surface")
    if surface is None or not has_surface_proposal(fields):
        raise ValueError("Surface certificate requires a present proposal")
    items, root_term, root_id, root_parse_node = split_surface_proposal(surface)
    nodes = split_list_literal(fields["parse_nodes"])
    parsed_nodes = [parse_node_term(node) for node in nodes]
    parse_root_match = re.fullmatch(r"some ([0-9]+)", fields["parse_root"])
    if parse_root_match is None:
        raise ValueError("Surface proposal requires a canonical parse root")
    parse_root = int(parse_root_match.group(1))
    if parse_root != root_parse_node or parse_root >= len(parsed_nodes):
        raise ValueError("Surface file and Artifact parse roots disagree")
    root_production, root_children = parsed_nodes[parse_root]
    if root_production != 0 or len(root_children) != 1:
        raise ValueError("Surface file root has the wrong parse shape")
    list_node = parse_node_child(root_children[0])
    total_fuel = len(nodes) + 1
    next_id = 0
    steps: list[SurfaceItemStep] = []
    function_bodies: list[SurfaceFunctionBody] = []
    while_bodies: list[SurfaceWhileBody] = []
    for index, item in enumerate(items):
        if list_node >= len(parsed_nodes):
            raise ValueError("Surface item list references an absent node")
        production, children = parsed_nodes[list_node]
        if production != 1 or len(children) != 2:
            raise ValueError("Surface item list has the wrong parse shape")
        item_node = parse_node_child(children[0])
        rest_node = parse_node_child(children[1])
        item_id, item_parse_node = surface_item_location(item)
        if item_parse_node != item_node or item_id < next_id:
            raise ValueError("Surface item identity disagrees with its parse spine")
        finish_id = item_id + 1
        item_fuel = total_fuel - index - 1
        steps.append(SurfaceItemStep(
            index=index,
            list_node=list_node,
            item_node=item_node,
            rest_node=rest_node,
            start_id=next_id,
            finish_id=finish_id,
            item_fuel=item_fuel,
            list_fuel=total_fuel - index,
        ))
        split_body = split_function_body(item)
        function_node = function_parse_node(parsed_nodes, item_node)
        if (split_body is None) != (function_node is None):
            raise ValueError("Surface function term and parse production disagree")
        if split_body is not None and function_node is not None:
            body_literal, statement_terms = split_body
            function_production, function_children = parsed_nodes[function_node]
            if function_production != 11 or len(function_children) != 9:
                raise ValueError("Surface function has the wrong parse shape")
            block_node = parse_node_child(function_children[8])
            block_production, block_children = parsed_nodes[block_node]
            if block_production != 12 or len(block_children) != 3:
                raise ValueError("Surface function body has the wrong block shape")
            statement_list = parse_node_child(block_children[1])
            block_fuel = item_fuel - 1
            list_fuel = block_fuel - 1
            body_start = item_id if not statement_terms else surface_node_id_range(
                statement_terms[0])[0]
            statement_steps, current_list, statement_next_id, _ = (
                build_statement_steps(parsed_nodes, statement_terms,
                                      statement_list, body_start, list_fuel))
            if statement_next_id != item_id:
                raise ValueError("Surface function body has a discontinuous identity")
            for statement in statement_steps:
                while_body = build_while_body(parsed_nodes, index, statement)
                if while_body is not None:
                    while_bodies.append(while_body)
            function_bodies.append(SurfaceFunctionBody(
                item_index=index,
                block_node=block_node,
                list_node=statement_list,
                tail_node=current_list,
                start_id=body_start,
                finish_id=item_id,
                block_fuel=block_fuel,
                statements=statement_steps,
                body_literal=body_literal,
            ))
        next_id = finish_id
        list_node = rest_node
    if list_node >= len(parsed_nodes):
        raise ValueError("Surface item tail references an absent node")
    tail_production, tail_children = parsed_nodes[list_node]
    if tail_production != 2 or tail_children:
        raise ValueError("Surface item list has no canonical empty tail")
    if next_id != root_id:
        raise ValueError("Surface file identity does not follow its items")
    return SurfaceCertificate(items, root_term, root_id, root_parse_node,
                              list_node, next_id, total_fuel, steps,
                              function_bodies, while_bodies)


def render_surface_data(certificate: SurfaceCertificate) -> str:
    output: list[str] = []
    for token, text_term in collect_large_surface_token_texts(certificate).items():
        output.append(
            f"noncomputable def extractedLargeTokenText{token} : String :=\n"
            f"  {text_term}\n")
    bodies = {body.item_index: body for body in certificate.function_bodies}
    whiles = {(body.item_index, body.statement_index): body
              for body in certificate.while_bodies}
    for index, item in enumerate(certificate.items):
        body = bodies.get(index)
        if body is not None:
            count = len(body.statements)
            for statement in body.statements:
                while_body = whiles.get((index, statement.index))
                if while_body is not None:
                    while_prefix = (f"extractedSurfaceBody{index}Statement"
                                    f"{statement.index}While")
                    output.append(
                        f"noncomputable def {while_prefix}Condition : SurfaceExpr :=\n"
                        f"  {share_surface_token_text(while_body.condition_term)}\n")
                    nested_count = len(while_body.statements)
                    for nested in while_body.statements:
                        output.append(
                            f"noncomputable def {while_prefix}Statement{nested.index} "
                            f": SurfaceStmt :=\n  "
                            f"{share_surface_token_text(nested.term)}\n")
                    output.append(
                        f"noncomputable def {while_prefix}Statements{nested_count} "
                        ": List SurfaceStmt := []\n")
                    for nested_index in reversed(range(nested_count)):
                        output.append(
                            f"noncomputable def {while_prefix}Statements{nested_index} "
                            ": List SurfaceStmt :=\n"
                            f"  {while_prefix}Statement{nested_index} :: "
                            f"{while_prefix}Statements{nested_index + 1}\n")
                    output.append(
                        f"noncomputable def {while_prefix}Body : List SurfaceStmt :=\n"
                        f"  {while_prefix}Statements0\n"
                        f"noncomputable def {while_prefix} : SurfaceStmt :=\n"
                        f"  ⟨{while_body.body_finish_id},{while_body.statement_node},"
                        f".while_loop {while_prefix}Condition {while_prefix}Body⟩\n")
                    statement_term = while_prefix
                else:
                    statement_term = share_surface_token_text(statement.term)
                output.append(
                    f"noncomputable def extractedSurfaceBody{index}Statement"
                    f"{statement.index} : SurfaceStmt :=\n  "
                    f"{statement_term}\n")
            output.append(
                f"noncomputable def extractedSurfaceBody{index}Statements{count} "
                ": List SurfaceStmt := []\n")
            for statement_index in reversed(range(count)):
                output.append(
                    f"noncomputable def extractedSurfaceBody{index}Statements"
                    f"{statement_index} : List SurfaceStmt :=\n"
                    f"  extractedSurfaceBody{index}Statement{statement_index} :: "
                    f"extractedSurfaceBody{index}Statements{statement_index + 1}\n")
            output.append(
                f"noncomputable def extractedSurfaceBody{index} : List SurfaceStmt :=\n"
                f"  extractedSurfaceBody{index}Statements0\n")
            item = item.replace(
                "body := " + body.body_literal,
                f"body := extractedSurfaceBody{index}", 1)
        item = share_surface_token_text(item)
        output.append(
            f"noncomputable def extractedSurfaceItem{index} : SurfaceItem :=\n  {item}\n")
    item_count = len(certificate.items)
    output.append(
        f"noncomputable def extractedSurfaceItems{item_count} : List SurfaceItem := []\n")
    for index in reversed(range(item_count)):
        output.append(
            f"noncomputable def extractedSurfaceItems{index} : List SurfaceItem :=\n"
            f"  extractedSurfaceItem{index} :: extractedSurfaceItems{index + 1}\n")
    root_term = re.sub(
        r"\{ items := [A-Za-z][A-Za-z0-9_]* \}",
        "{ items := extractedSurfaceItems0 }", certificate.root_term,
        count=1)
    output.append(
        "noncomputable def extractedSurfaceProposal : SurfaceFile :=\n"
        f"  {root_term}\n")
    return "".join(output)


def render_surface_proofs(certificate: SurfaceCertificate) -> str:
    output = [
        "\nnoncomputable section\n"
        "local instance extractedSurfaceAccess : ArtifactAccess :=\n"
        "  ArtifactAccess.ofView extractedView\n"
    ]
    for token in collect_large_surface_token_texts(certificate):
        output.append(
            f"theorem extractedLargeTokenText{token}Accepted :\n"
            f"    tokenTextEqWithView extracted extractedView {token} "
            f"extractedLargeTokenText{token} = true := by\n"
            "  kernel_rfl\n"
            f"theorem extractedLargeTokenText{token}Found :\n"
            f"    artifactTokenText? extracted {token} = "
            f"some extractedLargeTokenText{token} := by\n"
            "  change tokenTextWithView? extracted extractedView _ = _\n"
            f"  exact tokenTextEqWithView_sound extractedView "
            f"extractedLargeTokenText{token}Accepted\n")
    bodies = {body.item_index: body for body in certificate.function_bodies}
    whiles = {(body.item_index, body.statement_index): body
              for body in certificate.while_bodies}
    for body in certificate.function_bodies:
        prefix = f"extractedSurfaceBody{body.item_index}"
        for statement in body.statements:
            while_body = whiles.get((body.item_index, statement.index))
            if while_body is not None:
                while_prefix = f"{prefix}Statement{statement.index}While"
                child_fuel = while_body.statement_fuel - 1
                output.append(
                    f"theorem {while_prefix}ConditionReconstructed :\n"
                    f"    (reconstructExpr {child_fuel} extracted "
                    f"{while_body.condition_node}).run {while_body.start_id} =\n"
                    f"      some ({while_prefix}Condition, "
                    f"{while_body.condition_finish_id}) := by\n"
                    "  kernel_rfl\n")
                for nested in while_body.statements:
                    output.append(
                        f"theorem {while_prefix}Statement{nested.index}Reconstructed :\n"
                        f"    (reconstructStatement {nested.statement_fuel} extracted "
                        f"{nested.statement_node}).run {nested.start_id} =\n"
                        f"      some ({while_prefix}Statement{nested.index}, "
                        f"{nested.finish_id}) := by\n"
                        "  kernel_rfl\n")
                nested_count = len(while_body.statements)
                tail_fuel = child_fuel - 1 - nested_count
                output.append(
                    f"theorem {while_prefix}Statements{nested_count}Reconstructed :\n"
                    f"    (reconstructStatements {tail_fuel} extracted "
                    f"{while_body.tail_node}).run {while_body.body_finish_id} =\n"
                    f"      some ({while_prefix}Statements{nested_count}, "
                    f"{while_body.body_finish_id}) := by\n"
                    "  apply reconstructStatements_nil_of\n"
                    "  kernel_rfl\n")
                for nested in reversed(while_body.statements):
                    output.append(
                        f"theorem {while_prefix}Statements{nested.index}Reconstructed :\n"
                        f"    (reconstructStatements {nested.list_fuel} extracted "
                        f"{nested.list_node}).run {nested.start_id} =\n"
                        f"      some ({while_prefix}Statements{nested.index}, "
                        f"{while_body.body_finish_id}) := by\n"
                        f"  simpa only [{while_prefix}Statements{nested.index}] using\n"
                        "    (reconstructStatements_cons_of (artifact := extracted)\n"
                        "      (by kernel_rfl) (by kernel_rfl) (by kernel_rfl)\n"
                        f"      {while_prefix}Statement{nested.index}Reconstructed\n"
                        f"      {while_prefix}Statements{nested.index + 1}Reconstructed)\n")
                output.append(
                    f"theorem {while_prefix}BodyReconstructed :\n"
                    f"    (reconstructBlock {child_fuel} extracted "
                    f"{while_body.block_node}).run "
                    f"{while_body.condition_finish_id} =\n"
                    f"      some ({while_prefix}Body, {while_body.body_finish_id}) := by\n"
                    f"  simpa only [{while_prefix}Body] using\n"
                    "    (reconstructNestedBlock_of (artifact := extracted) "
                    f"(production := {while_body.block_production})\n"
                    "      (by kernel_rfl) (by omega) (by kernel_rfl)\n"
                    f"      {while_prefix}Statements0Reconstructed)\n"
                    f"theorem {while_prefix}Reconstructed :\n"
                    f"    (reconstructStatement {while_body.statement_fuel} extracted "
                    f"{while_body.statement_node}).run {while_body.start_id} =\n"
                    f"      some ({while_prefix}, {while_body.finish_id}) := by\n"
                    f"  simpa only [{while_prefix}] using\n"
                    "    (reconstructWhileStatement_of (artifact := extracted)\n"
                    "      (by kernel_rfl) (by kernel_rfl) (by kernel_rfl)\n"
                    f"      {while_prefix}ConditionReconstructed\n"
                    f"      {while_prefix}BodyReconstructed)\n")
                statement_proof = (
                    f"  simpa only [{prefix}Statement{statement.index}] using\n"
                    f"    {while_prefix}Reconstructed\n")
            else:
                statement_proof = "  kernel_rfl\n"
            output.append(
                f"theorem {prefix}Statement{statement.index}Reconstructed :\n"
                f"    (reconstructStatement {statement.statement_fuel} extracted "
                f"{statement.statement_node}).run {statement.start_id} =\n"
                f"      some ({prefix}Statement{statement.index}, "
                f"{statement.finish_id}) := by\n"
                f"{statement_proof}")
        count = len(body.statements)
        tail_fuel = body.block_fuel - 1 - count
        output.append(
            f"theorem {prefix}Statements{count}Reconstructed :\n"
            f"    (reconstructStatements {tail_fuel} extracted {body.tail_node}).run "
            f"{body.finish_id} = some ({prefix}Statements{count}, "
            f"{body.finish_id}) := by\n"
            "  apply reconstructStatements_nil_of\n"
            "  kernel_rfl\n")
        for statement in reversed(body.statements):
            output.append(
                f"theorem {prefix}Statements{statement.index}Reconstructed :\n"
                f"    (reconstructStatements {statement.list_fuel} extracted "
                f"{statement.list_node}).run {statement.start_id} =\n"
                f"      some ({prefix}Statements{statement.index}, "
                f"{body.finish_id}) := by\n"
                f"  simpa only [{prefix}Statements{statement.index}] using\n"
                "    (reconstructStatements_cons_of (artifact := extracted)\n"
                "      (by kernel_rfl) (by kernel_rfl) (by kernel_rfl)\n"
                f"      {prefix}Statement{statement.index}Reconstructed\n"
                f"      {prefix}Statements{statement.index + 1}Reconstructed)\n")
        output.append(
            f"theorem {prefix}Reconstructed :\n"
            f"    (reconstructBlock {body.block_fuel} extracted "
            f"{body.block_node}).run {body.start_id} =\n"
            f"      some ({prefix}, {body.finish_id}) := by\n"
            f"  simpa only [{prefix}] using\n"
            "    (reconstructFunctionBlock_of (artifact := extracted)\n"
            "      (by kernel_rfl) (by kernel_rfl)\n"
            f"      {prefix}Statements0Reconstructed)\n")
    for step in certificate.steps:
        body = bodies.get(step.index)
        proof = "  kernel_rfl\n"
        if body is not None:
            proof = (
                f"  simp only [extractedSurfaceItem{step.index}]\n"
                "  simp [reconstructItem, reconstructFunction, "
                f"extractedSurfaceBody{step.index}Reconstructed]\n")
        output.append(
            f"theorem extractedSurfaceItem{step.index}Reconstructed :\n"
            f"    (reconstructItem {step.item_fuel} extracted {step.item_node}).run "
            f"{step.start_id} =\n"
            f"      some (extractedSurfaceItem{step.index}, {step.finish_id}) := by\n"
            f"{proof}")
    item_count = len(certificate.items)
    tail_fuel = certificate.total_fuel - item_count
    output.append(
        f"theorem extractedSurfaceItems{item_count}Reconstructed :\n"
        f"    (reconstructItems {tail_fuel} extracted {certificate.tail_node}).run "
        f"{certificate.final_id} =\n"
        f"      some (extractedSurfaceItems{item_count}, {certificate.final_id}) := by\n"
        "  apply reconstructItems_nil_of\n"
        "  kernel_rfl\n")
    for step in reversed(certificate.steps):
        output.append(
            f"theorem extractedSurfaceItems{step.index}Reconstructed :\n"
            f"    (reconstructItems {step.list_fuel} extracted {step.list_node}).run "
            f"{step.start_id} =\n"
            f"      some (extractedSurfaceItems{step.index}, "
            f"{certificate.final_id}) := by\n"
            f"  simpa only [extractedSurfaceItems{step.index}] using\n"
            "    (reconstructItems_cons_of (artifact := extracted)\n"
            "      (by kernel_rfl) (by kernel_rfl) (by kernel_rfl)\n"
            f"      extractedSurfaceItem{step.index}Reconstructed\n"
            f"      extractedSurfaceItems{step.index + 1}Reconstructed)\n")
    output.append(
        "theorem extractedSurfaceFileReconstructed :\n"
        f"    (reconstructFile {certificate.total_fuel} extracted "
        f"{certificate.root_parse_node}).run 0 =\n"
        f"      some (extractedSurfaceProposal, {certificate.root_id + 1}) := by\n"
        "  simpa only [extractedSurfaceProposal] using\n"
        "    (reconstructFile_of (artifact := extracted)\n"
        "      (by kernel_rfl) (by kernel_rfl)\n"
        "      extractedSurfaceItems0Reconstructed)\n"
        "theorem extractedSurfaceReconstructedView :\n"
        "    reconstructArtifactSurfaceView extracted extractedView =\n"
        "      some extractedSurfaceProposal := by\n"
        "  unfold reconstructArtifactSurfaceView reconstructArtifactSurfaceWithAccess\n"
        f"  rw [show extracted.parse_root = some {certificate.root_parse_node} by "
        "kernel_rfl]\n"
        f"  have nodeCount : extracted.parse_nodes.length + 1 = "
        f"{certificate.total_fuel} := by\n"
        "    change extractedParseNodeTree.flatten.length + 1 = _\n"
        "    rw [extractedParseNodeTreeLength]\n"
        "  rw [nodeCount]\n"
        "  exact option_map_fst_of_run_eq extractedSurfaceFileReconstructed\n"
        "theorem extractedSurfaceReconstructed :\n"
        "    reconstructArtifactSurface extracted = some extractedSurfaceProposal := by\n"
        "  rw [← reconstructArtifactSurfaceView_eq extracted extractedView]\n"
        "  exact extractedSurfaceReconstructedView\n"
        "theorem extractedSurfaceMatches :\n"
        "    extracted.surface = reconstructArtifactSurface extracted := by\n"
        "  rw [extractedSurfaceReconstructed]\n"
        "  rfl\n"
        "#print axioms extractedSurfaceMatches\n"
        "end\n")
    return "".join(output)


def balanced_append_expression(names: list[str]) -> str:
    """Build the same balanced concatenation shape used by ``render_seq_tree``."""
    if not names:
        return "[]"
    if len(names) == 1:
        return names[0]
    middle = len(names) // 2
    return (f"({balanced_append_expression(names[:middle])} ++ "
            f"{balanced_append_expression(names[middle:])})")


def chunked_list(name: str, element_type: str, value: str,
                 chunk_size: int) -> str:
    items = split_list_literal(value)
    if not items:
        return f"def {name} : List {element_type} := []\n"
    chunks = [items[index:index + chunk_size]
              for index in range(0, len(items), chunk_size)]
    declarations = []
    references = []
    for index, chunk in enumerate(chunks):
        chunk_name = f"{name}Chunk{index}"
        references.append(chunk_name)
        declarations.append(
            f"def {chunk_name} : List {element_type} :=\n  [" +
            ",".join(chunk) + "]\n")
    declarations.append(
        f"def {name} : List {element_type} :=\n  " +
        balanced_append_expression(references) + "\n")
    return "".join(declarations)


def split_artifact_term(term: str) -> dict[str, str]:
    prefix = "{ Lanius.Extraction.Artifact.empty with sources := "
    suffix = " }"
    if not term.startswith(prefix) or not term.endswith(suffix):
        raise ValueError("extractor did not emit the canonical Artifact term")
    body = term[len(prefix):-len(suffix)]
    markers = [
        ("sources", ", raw_tokens := "),
        ("raw_tokens", ", tokens := "),
        ("tokens", ", semantic_token_kinds := "),
        ("semantic_token_kinds", ", parse_nodes := "),
        ("parse_nodes", ", parse_root := "),
    ]
    result: dict[str, str] = {}
    remaining = body
    for field, marker in markers:
        value, separator, remaining = remaining.partition(marker)
        if not separator:
            raise ValueError(f"extractor omitted Artifact field {field}")
        result[field] = value.strip()
    parse_root, surface_marker, surface = remaining.partition(", surface := ")
    result["parse_root"] = parse_root.strip()
    if surface_marker:
        surface = surface.strip()
        if not surface:
            raise ValueError("extractor emitted an empty Artifact surface")
        result["surface"] = surface
    return result


def has_surface_proposal(fields: dict[str, str]) -> bool:
    """Recognize a canonical present Surface proposal without interpreting it."""
    surface = fields.get("surface")
    if surface is None or surface == "none":
        return False
    if surface.startswith("some ") or surface.startswith("(some "):
        return True
    raise ValueError("invalid emitted Surface option")


def render_chunked_artifact(term: str) -> str:
    fields = split_artifact_term(term.strip())
    has_surface = has_surface_proposal(fields)
    surface_certificate = build_surface_certificate(fields) if has_surface else None
    sources = fields["sources"]
    source_prefix = "[{ path := "
    source_suffix = " }]"
    bytes_marker = ", bytes := "
    if not sources.startswith(source_prefix) or not sources.endswith(source_suffix):
        raise ValueError("expected one canonical emitted source")
    source_body = sources[len(source_prefix):-len(source_suffix)]
    path, separator, source_bytes = source_body.rpartition(bytes_marker)
    if not separator:
        raise ValueError("emitted source has no byte table")

    source_byte_count = len(split_list_literal(source_bytes))
    source_chunk_count = (source_byte_count + 255) // 256
    token_count = len(split_list_literal(fields["tokens"]))
    semantic_count = len(split_list_literal(fields["semantic_token_kinds"]))
    parse_node_count = len(split_list_literal(fields["parse_nodes"]))
    cache_capacity = max(64, source_byte_count, token_count)

    output = [SURFACE_PREFIX if has_surface else PREFIX]
    output.append(chunked_list("extractedSourceBytes", "Nat", source_bytes, 256))
    if source_chunk_count == 0:
        output.append("def extractedDecodedSourceBytes : List (Fin 256) := []\n")
    else:
        decoded_source_chunks: list[str] = []
        for index in range(source_chunk_count):
            name = f"extractedDecodedSourceBytesChunk{index}"
            decoded_source_chunks.append(name)
            output.append(
                f"def {name} : List (Fin 256) :=\n"
                f"  (decodeBytes extractedSourceBytesChunk{index}).getD []\n")
        output.append(
            "def extractedDecodedSourceBytes : List (Fin 256) :=\n  " +
            balanced_append_expression(decoded_source_chunks) + "\n")
    source_tree, source_root, source_nodes = render_seq_tree(
        "extractedSourceByteTree", "extractedDecodedSourceBytes", "(Fin 256)",
        source_byte_count, 256)
    output.append(source_tree)
    output.append(
        "def extractedSources : List SourceFile :=\n"
        f"  [{{ path := {path}, bytes := extractedSourceBytes }}]\n")

    raw_tokens = fields["raw_tokens"]
    if raw_tokens == "none":
        output.append("def extractedRawTokens : Option (List Token) := none\n")
    elif raw_tokens.startswith("some "):
        output.append(chunked_list(
            "extractedRawTokenList", "Token", raw_tokens[5:], 128))
        output.append(
            "def extractedRawTokens : Option (List Token) :=\n"
            "  some extractedRawTokenList\n")
    else:
        raise ValueError("invalid emitted raw-token option")
    # Keep emitted data names distinct from the public proof names in SUFFIX.
    # In particular, `extractedTokens` is the token-validity theorem.
    output.append(chunked_list(
        "extractedTokenData", "Token", fields["tokens"], 128))
    output.append(chunked_list(
        "extractedSemanticKinds", "Nat", fields["semantic_token_kinds"], 256))
    semantic_tree, semantic_root, semantic_nodes = render_seq_tree(
        "extractedSemanticKindTree", "extractedSemanticKinds", "Nat",
        semantic_count, 256)
    output.append(semantic_tree)
    output.append(chunked_list(
        "extractedParseNodes", "ParseNode", fields["parse_nodes"], 64))
    parse_tree, parse_root, parse_nodes = render_seq_tree(
        "extractedParseNodeTree", "extractedParseNodes", "ParseNode",
        parse_node_count, 64)
    output.append(parse_tree)
    output.append(render_tree_invariants(source_nodes, cache_capacity))
    output.append(render_tree_invariants(semantic_nodes, cache_capacity))
    output.append(render_tree_invariants(parse_nodes, cache_capacity))
    artifact_name = "extractedSyntax" if has_surface else "extracted"
    surface_field = ""
    if not has_surface and "surface" in fields:
        surface_field = f"\n  surface := {fields['surface']}"
    output.append(
        f"noncomputable def {artifact_name} : Artifact := {{ Artifact.empty with\n"
        "  sources := extractedSources\n"
        "  raw_tokens := extractedRawTokens\n"
        "  tokens := extractedTokenData\n"
        f"  semantic_token_kinds := {semantic_root.name}.flatten\n"
        f"  parse_nodes := {parse_root.name}.flatten\n"
        f"  parse_root := {fields['parse_root']}"
        f"{surface_field} }}\n")
    if surface_certificate is not None:
        output.append(render_surface_data(surface_certificate))
        output.append(
            "noncomputable def extracted : Artifact := { extractedSyntax with\n"
            "  surface := some extractedSurfaceProposal }\n")
    output.append("-- GENERATED_VIEW_PHASE\n")
    source_decode_proofs: list[str] = []
    if source_chunk_count == 0:
        source_decode_proofs.append(
            "theorem extractedSourceDecoded : decodeBytes extractedSourceBytes =\n"
            "    some extractedSourceByteTree.flatten := by rfl\n"
            "theorem extractedSourceTreeRepresents :\n"
            "    extractedSourceByteTree.flatten = extractedDecodedSourceBytes := by rfl\n")
    else:
        decoded_names: list[str] = []
        for index in range(source_chunk_count):
            theorem_name = f"extractedSourceBytesChunk{index}Decoded"
            decoded_names.append(theorem_name)
            source_decode_proofs.append(
                f"theorem {theorem_name} :\n"
                f"    decodeBytes extractedSourceBytesChunk{index} =\n"
                f"      some extractedDecodedSourceBytesChunk{index} := by\n"
                "  kernel_rfl\n")
        source_decode_proofs.append(
            "theorem extractedSourceDecodedFlat : decodeBytes extractedSourceBytes =\n"
            "    some extractedDecodedSourceBytes := by\n"
            "  unfold extractedSourceBytes extractedDecodedSourceBytes\n"
            f"  simp only [decodeBytes_append, {', '.join(decoded_names)}]\n"
            "theorem extractedSourceTreeRepresents :\n"
            f"    {source_root.name}.flatten = extractedDecodedSourceBytes := by rfl\n"
            "theorem extractedSourceDecoded : decodeBytes extractedSourceBytes =\n"
            f"    some {source_root.name}.flatten := by\n"
            "  rw [extractedSourceTreeRepresents]\n"
            "  exact extractedSourceDecodedFlat\n")
    output.append("".join(source_decode_proofs))
    output.append(
        f"theorem extractedDecodedSourceBytesLength : extractedDecodedSourceBytes.length = {source_byte_count} := by\n"
        f"  rw [← extractedSourceTreeRepresents, {source_root.name}Length]\n"
        f"theorem extractedTokenDataLength : extractedTokenData.length = {token_count} := by\n"
        "  kernel_rfl\n"
        f"theorem extractedTokenTreeWellFormed : (SeqTree.leaf extractedTokenData).WellFormed {cache_capacity} := by\n"
        "  change extractedTokenData.length ≤ " + str(cache_capacity) + "\n"
        "  rw [extractedTokenDataLength]\n"
        "  omega\n"
        "def extractedCache : ArtifactCache := {\n"
        f"  leafCapacity := {cache_capacity}\n"
        f"  parseNodes := {parse_root.name}\n"
        "  tokens := .leaf extractedTokenData\n"
        f"  primarySourceBytes := {source_root.name}\n"
        "}\n"
        "theorem extractedSourceBytesRepresent : ∀ source,\n"
        "    extracted.sources[0]? = some source →\n"
        "    decodeBytes source.bytes = some extractedCache.primarySourceBytes.flatten := by\n"
        "  intro source found\n"
        f"  change some {{ path := {path}, bytes := extractedSourceBytes }} = some source at found\n"
        "  injection found with same\n"
        "  subst source\n"
        "  exact extractedSourceDecoded\n"
        "noncomputable def extractedView : ArtifactView extracted := {\n"
        "  cache := extractedCache\n"
        f"  parseNodesWellFormed := {parse_root.name}WellFormed\n"
        "  parseNodesRepresent := rfl\n"
        "  tokensWellFormed := extractedTokenTreeWellFormed\n"
        "  tokensRepresent := rfl\n"
        f"  sourceBytesWellFormed := {source_root.name}WellFormed\n"
        "  sourceBytesRepresent := extractedSourceBytesRepresent\n"
        "}\n"
        "noncomputable def extractedParseView : ParseArtifactView extracted := {\n"
        "  artifactView := extractedView\n"
        f"  leafCapacity := {cache_capacity}\n"
        f"  semanticKinds := {semantic_root.name}\n"
        f"  semanticKindsWellFormed := {semantic_root.name}WellFormed\n"
        "  semanticKindsRepresent := rfl\n"
        "}\n")
    output.append("-- GENERATED_NODE_CHECK_PHASE\n")
    output.append(render_parse_tree_checks(parse_nodes))
    output.append("-- GENERATED_METADATA_PHASE\n")
    output.append(METADATA_PROOFS)
    output.append("-- GENERATED_VALIDITY_PHASE\n")
    output.append(FINAL_PROOFS)
    if surface_certificate is not None:
        output.append(render_surface_proofs(surface_certificate))
    return "".join(output)


def split_artifact_pack_term(term: str) -> list[str]:
    prefix = "Lanius.Extraction.ArtifactPack.mk Lanius.Extraction.schemaVersion "
    term = term.strip()
    if not term.startswith(prefix):
        raise ValueError("extractor did not emit the canonical ArtifactPack term")
    return split_list_literal(term[len(prefix):])


def render_chunked_pack(term: str) -> str:
    units = split_artifact_pack_term(term)
    if not units:
        raise ValueError("extractor emitted an empty ArtifactPack")
    surface_flags = [has_surface_proposal(split_artifact_term(unit))
                     for unit in units]
    output = [SURFACE_PREFIX if any(surface_flags) else PREFIX]
    unit_names: list[str] = []
    valid_names: list[str] = []
    surface_names: list[str] = []
    for index, (unit, has_surface) in enumerate(zip(units, surface_flags)):
        namespace = f"ExtractedUnit{index}"
        rendered = render_chunked_artifact(unit)
        unit_prefix = SURFACE_PREFIX if has_surface else PREFIX
        if not rendered.startswith(unit_prefix):
            raise AssertionError("unit renderer omitted shared prefix")
        output.append(f"namespace {namespace}\n")
        output.append(rendered[len(unit_prefix):])
        output.append(f"end {namespace}\n")
        unit_names.append(f"{namespace}.extracted")
        valid_names.append(f"{namespace}.extractedValid")
        if has_surface:
            surface_names.append(f"{namespace}.extractedSurfaceMatches")
    output.append(render_pack_assembly(
        unit_names, valid_names,
        surface_names if len(surface_names) == len(unit_names) else None))
    return "".join(output)


def render_pack_assembly(unit_names: list[str], valid_names: list[str],
                         surface_names: list[str] | None = None) -> str:
    unit_list = "[" + ",".join(unit_names) + "]"
    membership_proof: list[str] = []
    for valid_name in valid_names:
        membership_proof.append(
            "  rw [List.mem_cons] at member\n"
            "  rcases member with same | member\n"
            "  · subst unit\n"
            f"    exact {valid_name}\n")
    membership_proof.append("  · simp at member\n")
    output = (
        "noncomputable def extractedPack : ArtifactPack :=\n"
        f"  ArtifactPack.mk schemaVersion {unit_list}\n"
        "theorem extractedPackValid :\n"
        "    ∀ unit ∈ extractedPack.units, ParseArtifactValid unit := by\n"
        "  intro unit member\n"
        f"  change unit ∈ {unit_list} at member\n"
        f"{''.join(membership_proof)}"
        "#print axioms extractedPackValid\n")
    if surface_names is not None:
        surface_membership_proof: list[str] = []
        for surface_name in surface_names:
            surface_membership_proof.append(
                "  rw [List.mem_cons] at member\n"
                "  rcases member with same | member\n"
                "  · subst unit\n"
                f"    exact {surface_name}\n")
        surface_membership_proof.append("  · simp at member\n")
        output += (
            "theorem extractedPackSurfacesMatch :\n"
            "    ∀ unit ∈ extractedPack.units,\n"
            "      unit.surface = reconstructArtifactSurface unit := by\n"
            "  intro unit member\n"
            f"  change unit ∈ {unit_list} at member\n"
            f"{''.join(surface_membership_proof)}"
            "#print axioms extractedPackSurfacesMatch\n")
    return output


def render_pack_modules(term: str) -> dict[str, str]:
    """Render independently compilable source units plus one logical pack."""
    units = split_artifact_pack_term(term)
    if not units:
        raise ValueError("extractor emitted an empty ArtifactPack")
    modules: dict[str, str] = {}
    unit_names: list[str] = []
    valid_names: list[str] = []
    surface_names: list[str] = []
    all_have_surface = True
    imports: list[str] = []
    for index, unit in enumerate(units):
        namespace = f"ExtractedUnit{index}"
        has_surface = has_surface_proposal(split_artifact_term(unit))
        if not has_surface:
            all_have_surface = False
        rendered = render_chunked_artifact(unit)
        unit_prefix = SURFACE_PREFIX if has_surface else PREFIX
        body = rendered[len(unit_prefix):]
        data, marker, remainder = body.partition("-- GENERATED_VIEW_PHASE\n")
        if not marker:
            raise AssertionError("unit renderer omitted view phase")
        view, marker, remainder = remainder.partition(
            "-- GENERATED_NODE_CHECK_PHASE\n")
        if not marker:
            raise AssertionError("unit renderer omitted node-check phase")
        nodes, marker, remainder = remainder.partition(
            "-- GENERATED_METADATA_PHASE\n")
        if not marker:
            raise AssertionError("unit renderer omitted metadata phase")
        metadata, marker, validity = remainder.partition(
            "-- GENERATED_VALIDITY_PHASE\n")
        if not marker:
            raise AssertionError("unit renderer omitted validity phase")

        base = f"SelfClosure.Unit{index}"
        module_path = f"SelfClosure/Unit{index}"

        def phase(import_name: str | None, contents: str) -> str:
            imports_text = (PREFIX if import_name is None else (
                f"import {import_name}\nopen Lanius.Extraction\nopen Lanius.Data\n"
                "set_option maxRecDepth 100000\n"
                "set_option linter.unnecessarySimpa false\n"))
            return (imports_text + f"namespace {namespace}\n" + contents +
                    f"end {namespace}\n")

        modules[f"{module_path}/Data.lean"] = phase(None, data)
        modules[f"{module_path}/View.lean"] = phase(f"{base}.Data", view)
        modules[f"{module_path}/Nodes.lean"] = phase(f"{base}.View", nodes)
        modules[f"{module_path}/Metadata.lean"] = phase(
            f"{base}.View", metadata)
        modules[f"{module_path}/Valid.lean"] = (
            f"import {base}.Nodes\nimport {base}.Metadata\n"
            + ("import Lanius.Extraction.Reconstruction.Chunks\n"
               "import Lanius.Extraction.SurfaceChecker\n"
               if has_surface else "") +
            "open Lanius.Extraction\nopen Lanius.Data\n"
            "set_option maxRecDepth 100000\n"
            f"namespace {namespace}\n{validity}end {namespace}\n")
        imports.append(f"import {base}.Valid\n")
        unit_names.append(f"{namespace}.extracted")
        valid_names.append(f"{namespace}.extractedValid")
        if has_surface:
            surface_names.append(f"{namespace}.extractedSurfaceMatches")
    modules["SelfClosure/Pack.lean"] = (
        "".join(imports) + "open Lanius.Extraction\n" +
        render_pack_assembly(
            unit_names, valid_names,
            surface_names if all_have_surface else None))
    return modules


def render_extractor_output(term: str) -> str:
    stripped = term.strip()
    if stripped.startswith(
            "Lanius.Extraction.ArtifactPack.mk Lanius.Extraction.schemaVersion "):
        return render_chunked_pack(stripped)
    return render_chunked_artifact(stripped)


def load_bootstrap_closure(manifest_path: Path, executable: Path) -> list[Path]:
    manifest = json.loads(manifest_path.read_text())
    if manifest.get("target") != "x86_64-linux":
        raise ValueError("bootstrap manifest does not target x86_64-linux")
    executable_hash = hashlib.sha256(executable.read_bytes()).hexdigest()
    if executable_hash != manifest.get("executable_sha256"):
        raise ValueError("extractor does not match bootstrap manifest")
    records = manifest.get("source_closure")
    if not isinstance(records, list) or not records:
        raise ValueError("bootstrap manifest has no exact source closure")
    paths: list[Path] = []
    digest = hashlib.sha256()
    for record in records:
        if not isinstance(record, dict) or not isinstance(record.get("path"), str):
            raise ValueError("invalid source-closure record")
        path = Path(record["path"]).resolve()
        data = path.read_bytes()
        actual_hash = hashlib.sha256(data).hexdigest()
        if actual_hash != record.get("sha256"):
            raise ValueError(f"source changed since bootstrap: {path}")
        encoded = str(path).encode("utf-8")
        digest.update(len(encoded).to_bytes(8, "little"))
        digest.update(encoded)
        digest.update(len(data).to_bytes(8, "little"))
        digest.update(data)
        paths.append(path)
    if digest.hexdigest() != manifest.get("source_closure_sha256"):
        raise ValueError("source closure does not match its aggregate digest")
    return paths


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bootstrap-manifest", type=Path,
                        help="use and authenticate its exact source closure")
    parser.add_argument("--module-pack", action="store_true",
                        help="write a SelfClosure module directory instead of one Lean file")
    parser.add_argument("executable", type=Path)
    parser.add_argument("input", type=Path, nargs="*")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    executable = args.executable.resolve()
    with executable.open("rb") as stream:
        header = stream.read(20)
    if (len(header) != 20 or header[:6] != b"\x7fELF\x02\x01"
            or int.from_bytes(header[18:20], "little") != 62):
        parser.error("expected a little-endian x86-64 ELF executable")
    if args.bootstrap_manifest is not None:
        if args.input:
            parser.error("explicit inputs cannot be combined with --bootstrap-manifest")
        input_paths = load_bootstrap_closure(
            args.bootstrap_manifest.resolve(), executable)
    else:
        if not args.input:
            parser.error("provide at least one input or --bootstrap-manifest")
        input_paths = [path.resolve() for path in args.input]
    inputs = [str(path) for path in input_paths]
    result = subprocess.run([str(executable), *inputs],
                            stdout=subprocess.PIPE, check=True, timeout=300)
    term = result.stdout.decode("utf-8", errors="strict")
    if args.module_pack:
        modules = render_pack_modules(term)
        args.output.mkdir(parents=True, exist_ok=True)
        for relative, contents in modules.items():
            destination = args.output / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(contents)
        result_path = args.output / "SelfClosure/Pack.lean"
    else:
        args.output.write_text(render_extractor_output(term))
        result_path = args.output
    print(result_path)


if __name__ == "__main__":
    main()
