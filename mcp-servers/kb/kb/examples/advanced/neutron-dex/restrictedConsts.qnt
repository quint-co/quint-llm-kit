module restrictedConsts {
    import types.* from "types"
    import dec.* from "lib/dec"

    pure val DEBUG_ENABLED = true

    // This value is taken from neutron/x/dex/types/price.go#L20-L20
    // This is not used for non-deterministic samples. See `TICKS` instead.
    pure val MAX_TICK = 559680

    /// Price = BASE_PRICE^tick
    pure val BASE_PRICE: Dec = (10001, 10000) // =1.0001

    // Values from which to pick on nondeterministic choices
    pure val CREATORS: Set[Addr] = Set("Alice", "Bob")
    pure val INITIAL_CREATOR_BALANCE: int = 10000
    pure val ORDER_TYPES: Set[LimitOrderType] = Set(GoodTillCancelled, ImmediateOrCancel, FillOrKill, JustInTime, GoodTillTime(-1))
    pure val TOKENS: Set[Token] = Set("A", "B")

    // We will use this value to denote how much we can advance time and (at the same time!) the maximum
    // good_til value for a limit order
    pure val MAX_FUTURE_BLOCKS: int = 10

    pure val FEES: Set[Fee] = Set(0, 20000, 10, 50)
    pure val TICKS: Set[TickIndex] = Set(0, 20000, 100)
    pure val MAX_AMOUNT = 10000

    // Helper values
    pure val TOKEN_PAIRS: Set[TokenPair] = tuples(TOKENS, TOKENS).filter(x => x._1 != x._2)
    pure val TOKEN_NUM_VALUES: Token -> int = Map("A" -> 0, "B" -> 1, "C" -> 2)

    // Constants for different setups when running
    // tolerance for equality comparisons
    pure val TOLERANCE = 20
}
