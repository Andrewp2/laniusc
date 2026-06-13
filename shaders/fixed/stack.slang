public bool fixed_stack_empty(uint top)
{
    return top == 0u;
}

public bool fixed_stack_full<let CAPACITY: int>(uint top)
{
    return top >= uint(CAPACITY);
}

public uint fixed_stack_frame(uint top)
{
    return top == 0u ? 0u : top - 1u;
}

public bool fixed_stack_push<T, let CAPACITY: int>(
    inout uint top,
    inout T values[CAPACITY],
    T value)
{
    if (fixed_stack_full<CAPACITY>(top))
        return false;
    values[top] = value;
    top += 1u;
    return true;
}

public bool fixed_stack_pop<T, let CAPACITY: int>(
    inout uint top,
    inout T values[CAPACITY],
    out T value,
    T invalid)
{
    value = invalid;
    if (fixed_stack_empty(top))
        return false;
    top -= 1u;
    value = values[top];
    return true;
}

public T fixed_stack_peek_or<T, let CAPACITY: int>(
    uint top,
    inout T values[CAPACITY],
    T invalid)
{
    if (fixed_stack_empty(top))
        return invalid;
    return values[fixed_stack_frame(top)];
}
