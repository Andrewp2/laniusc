// Both grammar owners contain one source value followed by the same postfix
// continuation family. Receiver/callee and span producers share this contract.
import generated_parse_production_ids;

public bool hir_is_postfix_sequence_owner(uint production)
{
    return production == PROD_POSTFIX || production == PROD_RANGE_BOUND_NAME;
}
