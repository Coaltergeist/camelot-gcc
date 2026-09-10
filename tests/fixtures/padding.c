/* Adjacent short functions, ABI and literal-pool/zero-padding behavior. */
unsigned identity(unsigned x) { return x; }
unsigned multiply_seven(unsigned x) { return x * 7; }
unsigned mix_constant(unsigned x) { return x ^ 0x12345678U; }
unsigned narrow(unsigned x) { return (unsigned short)(x + 3); }
