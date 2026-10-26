#!/usr/bin/env python3
"""CPU regressions for local control-flow validation and indexed work bounds."""

import unittest

from validate_linked_elf import validate_function_instructions


class LinkedInstructionValidation(unittest.TestCase):
    @staticmethod
    def executable(address, size=1):
        return 0x100 <= address and address + size <= 0x200

    def validate(self, functions, instructions):
        return validate_function_instructions(functions, instructions, self.executable)

    def test_unreachable_cross_function_jump_still_rejects(self):
        functions = [("caller", 0x100, 0x10), ("other", 0x110, 1)]
        instructions = {0x100: ("ret", []), 0x101: ("jmp", ["110"]), 0x110: ("ret", [])}
        with self.assertRaisesRegex(ValueError, "caller: jump.*leaves its function"):
            self.validate(functions, instructions)

    def test_direct_branch_and_call_must_target_an_instruction(self):
        for mnemonic in ("jmp", "call", "callq", "loopne"):
            with self.subTest(mnemonic=mnemonic), self.assertRaisesRegex(ValueError, "not an instruction boundary"):
                self.validate([("function", 0x100, 0x10)],
                              {0x100: (mnemonic, ["102"]), 0x103: ("ret", [])})

    def test_unreachable_bad_and_data_instructions_still_reject(self):
        for mnemonic in ("(bad)", ".byte"):
            with self.subTest(mnemonic=mnemonic), self.assertRaisesRegex(ValueError, "invalid instruction at 0x101"):
                self.validate([("function", 0x100, 0x10)],
                              {0x100: ("ret", []), 0x101: (mnemonic, [])})

    def test_overlapping_ranges_each_keep_their_branch_contract(self):
        # The branch is valid for outer, but must still reject for inner.
        functions = [("outer", 0x100, 0x30), ("inner", 0x110, 0x10)]
        instructions = {0x100: ("ret", []), 0x110: ("ret", []),
                        0x111: ("jmp", ["12f"]), 0x12f: ("ret", [])}
        with self.assertRaisesRegex(ValueError, "inner: jump.*leaves its function"):
            self.validate(functions, instructions)
        # Equal-range aliases both contribute the original branch count.
        self.assertEqual(self.validate([("a", 0x100, 0x10), ("b", 0x100, 0x10)],
                                       {0x100: ("nop", []), 0x101: ("jne", ["108"]),
                                        0x108: ("ret", [])}), 2)

    def test_range_entry_target_and_call_rules_are_unchanged(self):
        instructions = {0x100: ("call", ["110"]), 0x110: ("ret", []), 0x300: ("ret", [])}
        self.assertEqual(self.validate([("function", 0x100, 0x10)], instructions), 0)
        with self.assertRaisesRegex(ValueError, "call target is outside executable"):
            self.validate([("function", 0x100, 0x10)], {**instructions, 0x100: ("call", ["300"])})
        with self.assertRaisesRegex(ValueError, "invalid executable symbol range"):
            self.validate([("function", 0x100, 0)], instructions)
        with self.assertRaisesRegex(ValueError, "entry is not an instruction boundary"):
            self.validate([("function", 0x101, 1)], instructions)
        with self.assertRaisesRegex(ValueError, "leaves its function"):
            self.validate([("function", 0x100, 0x10)], {0x100: ("jmp", ["100"])})
        with self.assertRaisesRegex(ValueError, "unrecognized direct branch target"):
            self.validate([("function", 0x100, 0x10)], {0x100: ("jmp", ["label"])})
        self.assertEqual(self.validate([("function", 0x100, 0x10)],
                                       {0x100: ("jmp", ["*%rax"])}), 0)

    def test_many_functions_visit_only_index_and_covered_instructions(self):
        class BudgetedInstructions(dict):
            visits = 0

            def visited(self):
                self.visits += 1
                if self.visits > 5 * len(self):
                    raise AssertionError("instruction work grew beyond the indexed/covered input")

            def __iter__(self):
                for key in super().__iter__():
                    self.visited()
                    yield key

            def __getitem__(self, key):
                self.visited()
                return super().__getitem__(key)

            def items(self):
                for item in super().items():
                    self.visited()
                    yield item

        count, width = 20_000, 10
        functions = [(f"function_{index}", index * width, width) for index in range(count)]
        instructions = BudgetedInstructions((address, ("ret", [])) for address in range(count * width))
        self.assertEqual(validate_function_instructions(functions, instructions,
                                                        lambda address, size=1: True), 0)
        self.assertLessEqual(instructions.visits, 5 * len(instructions))


if __name__ == "__main__":
    unittest.main()
