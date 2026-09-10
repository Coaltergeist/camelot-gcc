/* Symbol references, shared expressions and external-call relocations. */
extern unsigned state_a, state_b;
extern unsigned table[16];
extern unsigned transform(unsigned);
unsigned update_state(unsigned index, unsigned mask)
{
    unsigned old = state_a;
    unsigned next = (old & ~mask) | (state_b & mask);
    table[index & 15] = next;
    state_a = next;
    return transform(next) + old;
}
unsigned repeated_address(unsigned index)
{
    unsigned *p = &table[index & 15];
    unsigned a = *p;
    *p = a + state_b;
    return *p ^ a;
}
