/* Conditional labels, switch dispatch, loop edges and narrow loads. */
unsigned classify(unsigned x)
{
    switch (x) {
    case 2: return 11;
    case 3: return 19;
    case 4: return 7;
    case 5: return 23;
    case 6: return 13;
    default: return 0;
    }
}
unsigned accumulate(const unsigned short *p, unsigned count)
{
    unsigned result = 0;
    while (count--) {
        unsigned v = *p++;
        if (v & 1) result += v * 7;
        else result ^= v << 3;
    }
    return result;
}
