
/**
 * Rational numbers, represented as a tuple of (numerator, denominator)
 *
 * Andrey Kuprianov, Informal Systems, 2023
 * Ivan Gavran, Informal Systems, 2024
 */
module dec {
    type Dec = (int, int)

    pure def fromInt(i: int): Dec =
        (i, 1)

    // assumes that b!=0
    pure def fromRatio(a: int, b: int): Dec =
        (a, b)

    pure def zero(): Dec = fromInt(0)
    pure def one(): Dec = fromInt(1)



    pure def add(a: Dec, b: Dec): Dec =
        (a._1 * b._2 + b._1 * a._2, a._2 * b._2)

    pure def sub(a: Dec, b: Dec): Dec =
        (a._1 * b._2 - b._1 * a._2, a._2 * b._2)

    pure def mul(a: Dec, b: Dec): Dec =
        (a._1 * b._1, a._2 * b._2)

    pure def mulInt(a: Dec, b: int): Dec =
        a.mul(fromInt(b))

    // assumes that b!=0
    pure def div(a: Dec, b: Dec): Dec =
        (a._1 * b._2, a._2 * b._1)
    pure def intDivDec(a: int, b: Dec): Dec =
        div(
            fromInt(a),
            b
        )

    pure def pow(a: Dec, n: int): Dec =
        if(a._1 == 0) a
        else
            if(n>=0) (a._1 ^ n, a._2 ^ n)
            else (a._2 ^ (-n), a._1 ^ (-n))

    pure def gt(a: Dec, b: Dec): bool =
        (a.sub(b))._1 > 0 

    pure def gte(a: Dec, b: Dec): bool = 
        a.sub(b) == zero or gt(a, b)
    
    pure def equal(a: Dec, b: Dec): bool =
        a._1 * b._2 == a._2 * b._1
    
    pure def _abs(a: Dec): Dec =
        if (gt(zero, a)) (-a._1, a._2)
        else a

    // Evaluates to true if a+epsilon is greater than b (allows for a to even be smaller than b).
    //  assumes epsilon > 0
    pure def approx_gt(a: Dec, b: Dec, epsilon: Dec): bool =
        gt(
            a.add(epsilon),
            b
        )

    // Evaluates to true if a+epsilon is greater than or equal to b (allows for a to even be smaller than b).
    //  assumes epsilon > 0
    pure def approx_gte(a: Dec, b: Dec, epsilon: Dec): bool =
        gte(
            a.add(epsilon),
            b
        )


    pure def approxEqualDec(a: Dec, b: Dec, epsilon: Dec): bool =
    // assumes epsilon > 0
        gt(
            epsilon,
            _abs(a.sub(b))
        )

    pure def truncate(a: Dec): int =
        a._1 / a._2

    pure def ceil(a: Dec): int =
        val quo = a._1 / a._2
        if(a._1 % a._2 <= 0) quo
        else quo + 1
}
