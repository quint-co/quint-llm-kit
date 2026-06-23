module types {
    import dec.* from "lib/dec"

    type Addr = str
    type TokenPair = (Token, Token)
    type TickIndex = int
    type Fee = int
    // a tranche index is there for multiple tranches of the same tick
    type TrancheIndex = int

    type TrancheKey = {
        makerToken: Token,
        takerToken: Token,
        sellTick: TickIndex,
        id: TrancheIndex
    }

    type LimitOrderType =
        | FillOrKill
        | ImmediateOrCancel
        | GoodTillCancelled
        | GoodTillTime(BlockTime)
        | JustInTime

    type Message =
      | DepositPool(DepositMsg)
      | PlaceLimitOrder(PlaceLimitOrderMsg)
      | CancelLimitOrder(CancelLimitOrderMsg)
      | WithdrawLimitOrder(WithdrawLimitOrderMsg)
      | WithdrawPool(WithdrawPoolMsg)
      | Swap(SwapMsg)
      | Init
      | AdvanceTime

    // @audit-info : Simplified to only allow deposit in a single position
    type DepositMsg = {
        creator: Addr,
        tokenPair: (Token, Token),
        amountPair: (int, int),
        token0SellTick: TickIndex,
        fee: TickIndex,
        autoswap: bool
    }

    type WithdrawPoolMsg = {
        creator: Addr,
        tokenPair: (Token, Token),
        sharesAmount: int,
        tick: TickIndex,
        fee: Fee,
    }

    type SwapMsg = {
        creator: Addr,
        tokenPair: (Token, Token),
        amount: int,
        limitPriceTick: TickIndex
    }

    type PlaceLimitOrderMsg = {
        creator: Addr,
        orderType: LimitOrderType,
        // we have to choose tickIndex because the log operation is missing
        // @audit-info : If we will really need the log operation, what are our Quint options?
        // semantics: 1 tokenIn = price(sellTick) * 1 tokenOut
        sellTick: TickIndex,
        // semantics: I want to exchange tokenIn for tokenOut
        tokenIn: Token,
        tokenOut: Token,
        amountIn: int,
        maxAmountOut: int,
    }

    type CancelLimitOrderMsg = {
        creator: Addr,
        trancheKey: TrancheKey
    }

    type WithdrawLimitOrderMsg = {
        creator: Addr,
        trancheKey: TrancheKey
    }

    // Coins captures the balances of all the users in the system
    type Coins = (Addr, Token) -> int
    type Token = str

    // we model Time as int. The special value -1 will denote that the time is None
    type BlockTime = int

    // @audit-info Is there a way to factor out the two types below? So that
    // Liquidity = LimitOrderTranche | PoolReserves, and then they are defined elsewhere?
    // I tried, but the checker complained about it.
    type Liquidity =
        | LimitOrderTranche(Tranche)
        // @audit-info merge this in the merging session with Manu
        | PoolReserves

    type LiquidityKey = TrancheLiquidityKey(TrancheKey) | PoolLiquidityKey(PoolId)
    type Tranche = {
        // does not exist in the code: here, we want to be explicit about it.
        // should only be true until a first exchange happens through the tranche
        // isFresh <=> reservesMaker == totalMaker
        isFresh: bool,
        isActive: bool,
        reservesMaker: int,
        reservesTaker: int,
        totalMaker: int,
        totalTaker: int,
        // working directly with the tick instead of the `PriceTakerToMaker`
        sellTick: int,
        expirationTime: BlockTime,
        trancheKey: TrancheKey,
        // @audit-issue This is saved in the code under TrancheUser. Is there a good reason
        // for why this could not be udner tranche?
        makerDenomination: Token,
        takerDenomination: Token
    }

    type PoolId = {
        tokenPair: (Token, Token),
        // Pool's tick is the token0 sell tick, that is: 1 Token0 = price(tick)* 1 Token1
        tick: TickIndex,
        fee: Fee
    }

    type Pool = {
        reserves: (int, int),
        shares: int
    }

    type UserTrancheShares = {
        sharesOwned: int,
        sharesWithdrawn: int
    }

    type TrancheShares = (Addr, TrancheKey) -> UserTrancheShares
    type PoolShares = (Addr, PoolId) -> int

    type State = {
        tranches: TrancheKey -> Tranche,
        tranchesShares: TrancheShares,

        pools: PoolId -> Pool,
        poolShares: PoolShares,

        // balances of all the users in the system
        coins: Coins,

        // we will model time by blocks (integer value).
        // In the code, it is done through BlockTime. Departing from that.
        // @audit-info could that cause any issue down the line?
        blockNumber: BlockTime,

        // helper state variables, to be used in invariants
        bookkeeping: TrackedValue
    }

    /// Bookkeeping values
    type TrackedValue = {
        tranches: {
            placements: (Addr, TrancheKey) -> int, // only maker tokens can be deposited
            withdrawals: (Addr, TrancheKey) -> int, // only taker tokens can be withdrawn
            cancelations: (Addr, TrancheKey) -> (int, int), // both maker and taker can be withdrawn on cancelations
            swaps: (Addr, TrancheKey) -> Set[{ makerReservesDiff: int, takerReservesDiff: int }],
            proceedsToBeWithdrawn: (Addr, TrancheKey) -> int // proceeds in the taker token

        },
        pools: {
            deposits: (Addr, PoolId) -> (int, int),
            // tracking the values deposited (if the autoswap fee is paid, then this minus the fee)
            depositValues: (Addr, PoolId) -> int,
            withdrawals: (Addr, PoolId) -> (int, int),
            swaps: (Addr, PoolId) -> Set[{ token0Diff: int, token1Diff: int }]
        }
    }


    type TrancheUpdateDiff = { makerReservesDiff: int, takerReservesDiff: int }
    type PoolUpdateDiff = { token0Diff: int, token1Diff: int }

    type SwapUpdateInfo = {
        remainingAmount: int,
        outAmount: int,
        tranchesUpdates: TrancheKey -> TrancheUpdateDiff,
        poolUpdates: PoolId -> PoolUpdateDiff
    }

    type Result = { state: State, error: str }
}
