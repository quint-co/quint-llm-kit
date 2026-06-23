
/**
 * Bounded signed integers with arbitrary bitwidth.
 * 
 * To instantiate this module, use e.g.
 *
 * import intN(BITWIDTH=8).* from "intN"
 * type Int8 = IntN
 *
 * Andrey Kuprianov, Informal Systems, 2023
 */

module intN {
    
// How many bits are there?
const BITWIDTH: int

// Bounded signed integer
type IntN = int

pure def toInt(i: int): IntN = 
    val rem = i % (2^BITWIDTH)
    if(-2^(BITWIDTH-1) <= rem and rem <  2^(BITWIDTH-1)) rem
    else 
        if(rem >= 0) -(2^BITWIDTH) + rem
        else (2^BITWIDTH) + rem

pure def wrapping_add(a: IntN, b: IntN): IntN =
    toInt(a+b)

pure def wrapping_sub(a: IntN, b: IntN): IntN =
    toInt(a-b)

pure def wrapping_mul(a: IntN, b: IntN): IntN =
    toInt(a*b)


}