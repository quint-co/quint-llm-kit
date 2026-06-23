
/**
 * Bounded unsigned integers with arbitrary bitwidth.
 * 
 * To instantiate this module, use e.g.
 *
 * import uintN(BITWIDTH=8).* from "uintN"
 * type Uint8 = UintN
 *
 * Andrey Kuprianov, Informal Systems, 2023
 */

module uintN {
    
// How many bits are there?
const BITWIDTH: int

// Bounded unsigned integer
type UintN = int

pure def toUint(i: int): UintN = 
    i % (2^BITWIDTH)

pure def wrapping_add(a: UintN, b: UintN): UintN =
    toUint(a+b)

pure def wrapping_sub(a: UintN, b: UintN): UintN =
    toUint(a+b)

pure def wrapping_mul(a: UintN, b: UintN): UintN =
    toUint(a*b)

}