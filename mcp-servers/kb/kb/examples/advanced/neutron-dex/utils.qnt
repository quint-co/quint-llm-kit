
module utils {
    import dec.* from "lib/dec"
    import types.* from "types"
    import consts.* from "consts"
    import basicSpells.* from "lib/basicSpells"

    pure def debug(msg, expr) =
        if (DEBUG_ENABLED)
            q::debug(msg, expr)
        else
            expr

    // TRANCHE related functions
    pure def calculatePercentFilled(t: Tranche): Dec =
        if (t.totalMaker == 0)
            one
        else
            fromRatio(t.totalMaker - t.reservesMaker, t.totalMaker)

    pure def calculatePercentUnfilled(t: Tranche): Dec =
        if (t.totalMaker == 0)
            zero
        else
            fromRatio(t.reservesMaker, t.totalMaker)

    // ------- OTHER

    pure def min(a,b) = if (a<b) a else b

    pure def priceFromTick(tick: int): Dec =
        BASE_PRICE.pow(tick)

    pure def reverse(tokenPair: (str, str)): (str, str) = (tokenPair._2, tokenPair._1)

    pure def ok(state: State): Result = {state: state, error: "nil"}

    pure def error(state: State, error: str): Result = {state: state, error: error}

    pure val emptyTrackedValue: TrackedValue = {
        tranches: {
            placements: Map(),
            withdrawals: Map(),
            cancelations: Map(),
            swaps: Map(),
            proceedsToBeWithdrawn: Map()
        },
        pools: {
            deposits: Map(),
            depositValues: Map(),
            withdrawals: Map(),
            swaps: Map(),
        }
    }


    pure val initState: State = {
        tranches: Map(),
        coins: tuples(CREATORS, TOKENS).mapBy(_ => INITIAL_CREATOR_BALANCE),
        tranchesShares: Map(),
        blockNumber: 0,
        poolShares: Map(),
        pools: Map(),
        bookkeeping: emptyTrackedValue
    }

    // ----

    pure def unwrapTick(tick: Option[int]): int =
        match tick {
            | Some(t) => t
            | None => MAX_TICK
        }

    pure def computeUnitTolerance(tick: TickIndex): int =
        if (tick >= 0) 1 else computeDepositValue((0,1), tick).ceil()


    pure def computePoolValue(reserves: (int, int), token0SellTick: int): Dec =
        val token0SellPrice = priceFromTick(token0SellTick)
        fromInt(reserves._1).add(intDivDec(reserves._2, token0SellPrice))

    pure def computeDepositValue(amounts: (int, int), token0SellTick: int): Dec = computePoolValue(amounts, token0SellTick)

    pure def tokenLT(t1: Token, t2: Token, token_num_values: Token -> int): bool =
        // @audit-info What is the best practice to encode assumptions on pure functions,
        // without making the code too verbose?
        // assuming that both tokens are in the TOKEN_NUM_VALUES
        token_num_values.get(t1) < token_num_values.get(t2)

    pure def orderTokenPair(pair: TokenPair): TokenPair =
        if (tokenLT(pair._1, pair._2, TOKEN_NUM_VALUES)) pair else (pair._2, pair._1)

    pure def normalizeCoinAndTick(tokenPair: TokenPair, tick: int): (TokenPair, int) =
        val tokenIn = tokenPair._1
        val tokenOut = tokenPair._2
        if (tokenLT(tokenIn, tokenOut, TOKEN_NUM_VALUES))
            ((tokenIn, tokenOut), tick)
        else
            ((tokenOut, tokenIn), -tick)

    pure def swapInternallyConsistent(msg: PlaceLimitOrderMsg, swapUpdate: SwapUpdateInfo): bool =
        // sanity check that the output from the swap is internally consistent: what user got from pools and tranches
        // should correspond to the outAmount
        val poolsUpdateInfo = swapUpdate.poolUpdates
        val tranchesUpdateInfo = swapUpdate.tranchesUpdates
        val isPairNormalized = tokenLT(msg.tokenIn, msg.tokenOut, TOKEN_NUM_VALUES)
        val userGotFromPools = poolsUpdateInfo.keys().fold(
            0,
            (acc, poolId) =>
            val userGot =
                if (isPairNormalized)
                    abs(poolsUpdateInfo.get(poolId).token1Diff)
                else
                    abs(poolsUpdateInfo.get(poolId).token0Diff)
            acc + userGot
        )
        val userGotFromTranches = tranchesUpdateInfo.keys().fold(
            0,
            (acc, trancheKey) =>
            // the abs is because of the way the diff is expressed as negative to signify that the amount was taken from the tranche
            val userGot = abs(tranchesUpdateInfo.get(trancheKey).makerReservesDiff)
            acc + userGot
        )

        // the tranches and pool updates are in line with what the user received
        userGotFromPools + userGotFromTranches == swapUpdate.outAmount

    pure def calculateTrancheKey(makerToken: Token, takerToken: Token, sellTick: TickIndex, tranches: TrancheKey -> Tranche, expirationBlockTime: BlockTime): TrancheKey =
        val appropriateTrancheKeys = tranches.keys().filter(key =>
            val tranche = tranches.get(key)
            and{
                key.makerToken == makerToken,
                key.takerToken == takerToken,
                key.sellTick == sellTick,
                tranche.isFresh,
                tranche.expirationTime == expirationBlockTime,
                tranche.isActive
            }
        )

        if (size(appropriateTrancheKeys) > 0)
            getMinimumTrancheKey(appropriateTrancheKeys)
        else
            val maxTrancheId = tranches.keys().fold(
                0,
                (acc, key) => if (key.id > acc) key.id else acc
            )
            // in the implementation, the id is connected to the block number. Here, we use increasing values
            {makerToken: makerToken, takerToken: takerToken, sellTick: sellTick, id: maxTrancheId + 1}

    // given an amount in the taker token, return how much of it the tranche can exchange and then update amount of the tranche
    pure def calculateTrancheExchangableAmount(amount: int, tranche: Tranche):
    {
        trancheRemainingAmount: int,
        exchangedTakerAmount: int,
        exchangedMakerAmount: int
    } =
        val makerPrice = priceFromTick(tranche.sellTick)
        val userWantsToGetMakerToken = intDivDec(amount, makerPrice).truncate()
        val outMakerToken = min(userWantsToGetMakerToken, tranche.reservesMaker)
        val inTakerToken = mulInt(makerPrice, outMakerToken).ceil()
        {
            trancheRemainingAmount: tranche.reservesMaker - outMakerToken,
            exchangedTakerAmount: inTakerToken,
            exchangedMakerAmount: outMakerToken
        }

    pure def getMinimumTrancheKey(trancheKeys: Set[TrancheKey]): TrancheKey =
        trancheKeys.fold(
            // @audit-issue trancheKeys.chooseSome() ideally, but that one is still unimplemented in the simulation
            {makerToken: "_", takerToken: "_", sellTick: MAX_TICK*10, id: 0},
            (acc, key) => if (trancheLTE(key, acc)) key else acc
        )

    pure def getMinimumPoolKey(poolKeys: Set[PoolId], isToken0Liquidity: bool): PoolId =
        // start with a max_tick as initial, so that as soon as there is something found we replace the initial tick
        val initTick = if (isToken0Liquidity) MAX_TICK else -MAX_TICK
        val minKey = poolKeys.fold(
            // ideally, choose some, but doesn't work in the simulation
            {tokenPair: ("_", "_"), tick: initTick, fee: 0},
            (acc, key) => if (poolLTE(key, acc, isToken0Liquidity)) key else acc
        )
        minKey

    // TRADE-RELATED FUNCTIONS
    // this function returns:
    //  - a mapping from poolIds to amounts that should be swapped with this pool
    //  - a mapping from trancheKeys to amounts that should be filled with this tranche
    //  - an integer saying how much of the order amount is still remaining
    pure def swap(
        tokenPair: (Token, Token),
        tranches: TrancheKey -> Tranche,
        pools: PoolId -> Pool,
        amount: int,
        maxPriceTick: int,
        // TODO: maxAmountOut parameter not taken into account
        maxAmountOut: int
    ): SwapUpdateInfo =
        // Token pairs are stored only under normalized pairs for pools
        val normalizedPair = orderTokenPair(tokenPair)
        val isPairNormalized = tokenPair == normalizedPair
        val askingForToken0Liquidity = tokenPair._2 == normalizedPair._1

        // @audit-info check if key.tick < maxPriceTick is the right semantics, or it should be on average
        // checked: it should be both.
        val relevantTranches = tranches.keys().filter(key =>
            and {
                key.takerToken == tokenPair._1,
                key.makerToken == tokenPair._2,
                key.sellTick <= maxPriceTick,
                tranches.get(key).isActive,
                tranches.get(key).reservesMaker > 0,
            }
        )

        // Find the pools that has liquidity that the user is asking for, and the tick is better than maxPriceTick
        val relevantPools = pools.keys().filter(id =>
            and {
                id.tokenPair == normalizedPair,
                askingForToken0Liquidity implies pools.get(id).reserves._1 > 0,
                not(askingForToken0Liquidity) implies pools.get(id).reserves._2 > 0,
                computeReserveTick(id.tick, askingForToken0Liquidity, id.fee) <= maxPriceTick,
            }
        )

        val relevantLiquiditySize = size(relevantTranches) + size(relevantPools)

        // the purpose of this fold is to iterate as many times as there are keys. But the iteration is not
        // happening over keys: instead, a minimum key is found in each iteration and the iteration continues.
        val foldResult = 1.to(relevantLiquiditySize).fold(
            {
                tranchesUpdates: Map(),
                poolUpdates: Map(),
                remainingAmountToExchange: amount,
                remainingTranches: relevantTranches,
                remainingPools: relevantPools,
                outAmount: 0
            },
            (acc, _) =>
                // Iterate only if there is still amount to exchange
                if (acc.remainingAmountToExchange == 0) acc else

                // find me the minumum tranche key and the minimum pool key
                val minTrancheKey: TrancheKey = getMinimumTrancheKey(acc.remainingTranches)
                val minPoolKey = getMinimumPoolKey(acc.remainingPools, askingForToken0Liquidity)

                // the pool price includes the fee
                val minPoolReserveTick = computeReserveTick(minPoolKey.tick, askingForToken0Liquidity, minPoolKey.fee)

                // use the tranche key only if there are no more pools or there are pools, but
                // their best price is strictly larger than that of the tranches
                if (acc.remainingPools == Set() or minTrancheKey.sellTick < minPoolReserveTick)
                    // I want to know how much I can exchange in this tranche
                    val tranche = tranches.get(minTrancheKey)
                    val exchangeInfo = calculateTrancheExchangableAmount(acc.remainingAmountToExchange, tranche)
                    // update the acc value
                    if (exchangeInfo.exchangedTakerAmount == 0)
                        acc
                    else
                    {
                        ...acc,
                        tranchesUpdates: acc.tranchesUpdates.put(
                            minTrancheKey,
                            { makerReservesDiff: -exchangeInfo.exchangedMakerAmount, takerReservesDiff: exchangeInfo.exchangedTakerAmount }
                        ),
                        remainingAmountToExchange: acc.remainingAmountToExchange - exchangeInfo.exchangedTakerAmount,
                        remainingTranches: acc.remainingTranches.setRemove(minTrancheKey),
                        outAmount: acc.outAmount + exchangeInfo.exchangedMakerAmount,
                    }

                // otherwise, I am using the pool
                else
                    val pool = pools.get(minPoolKey)
                    // tokenB is the one that the user will be getting
                    val reservesTokenOut = debug("reservesTokenOut: ",if (askingForToken0Liquidity) pool.reserves._1 else pool.reserves._2)
                    val priceTokenOut = priceFromTick(minPoolReserveTick)

                    val wantFromPool = debug("want from pool", intDivDec(acc.remainingAmountToExchange, priceTokenOut).truncate())
                    val userGetsFromPool = min(wantFromPool, reservesTokenOut)
                    val userPutsIntoPool = debug("puts into pool",
                        mulInt(priceTokenOut, userGetsFromPool).ceil()
                    )

                    {
                        ...acc,
                        remainingPools: acc.remainingPools.setRemove(minPoolKey),
                        remainingAmountToExchange: acc.remainingAmountToExchange - userPutsIntoPool,
                        outAmount: acc.outAmount + userGetsFromPool,
                        poolUpdates: acc.poolUpdates.put(
                            minPoolKey,
                            if (isPairNormalized)
                              { token0Diff: userPutsIntoPool, token1Diff: -userGetsFromPool }
                            else
                              { token0Diff: -userGetsFromPool, token1Diff: userPutsIntoPool }
                        ),
                        outAmount: acc.outAmount + userGetsFromPool,
                    }
        )

        {
          remainingAmount: foldResult.remainingAmountToExchange,
          outAmount: foldResult.outAmount,
          poolUpdates: foldResult.poolUpdates,
          tranchesUpdates: foldResult.tranchesUpdates
        }

    pure def mayExpire(tranche: Tranche): bool =
        tranche.expirationTime >= 0

    pure def validatePoolsUpdates(before: State, after: State, poolsUpdates: PoolId -> PoolUpdateDiff): bool =

        // updated pools equal the 'after' state, the rest is unchanged
        before.pools.keys().forall(poolId =>
            if (poolsUpdates.keys().contains(poolId))
                val updatedReserves = (before.pools.get(poolId).reserves._1 + poolsUpdates.get(poolId).token0Diff,
                                        before.pools.get(poolId).reserves._2 + poolsUpdates.get(poolId).token1Diff)
                after.pools.get(poolId).reserves == updatedReserves
            else
                before.pools.get(poolId).reserves == after.pools.get(poolId).reserves
        )

    pure def validateTranchesUpdates(before: State, after: State, tranchesUpdateInfo: TrancheKey -> TrancheUpdateDiff) : bool =

        // for all traded tranches, we check whether the difference matches
        tranchesUpdateInfo.keys().forall(trancheKey =>
            after.tranches.get(trancheKey) ==
            {
                reservesMaker: before.tranches.get(trancheKey).reservesMaker + tranchesUpdateInfo.get(trancheKey).makerReservesDiff,
                reservesTaker: before.tranches.get(trancheKey).reservesTaker + tranchesUpdateInfo.get(trancheKey).takerReservesDiff,
                totalTaker: before.tranches.get(trancheKey).totalTaker + tranchesUpdateInfo.get(trancheKey).takerReservesDiff,
                isFresh: false,
                ...before.tranches.get(trancheKey),
            }
        )

    pure def updatePools(pools: PoolId -> Pool, poolUpdates: PoolId -> PoolUpdateDiff): PoolId -> Pool =
        pools.keys().mapBy(poolId =>
            if (poolUpdates.keys().contains(poolId))
                {
                    reserves: (pools.get(poolId).reserves._1 + poolUpdates.get(poolId).token0Diff,
                               pools.get(poolId).reserves._2 + poolUpdates.get(poolId).token1Diff),
                    shares: pools.get(poolId).shares
                }
            else
                pools.get(poolId)
        )

    pure def updateTranches(tranches: TrancheKey -> Tranche, tranchesUpdateInfo: TrancheKey -> TrancheUpdateDiff): TrancheKey -> Tranche =
        tranches.keys().mapBy(trancheKey =>
            if (tranchesUpdateInfo.keys().contains(trancheKey))
                {
                    reservesMaker: tranches.get(trancheKey).reservesMaker + tranchesUpdateInfo.get(trancheKey).makerReservesDiff,
                    reservesTaker: tranches.get(trancheKey).reservesTaker + tranchesUpdateInfo.get(trancheKey).takerReservesDiff,
                    totalTaker: tranches.get(trancheKey).totalTaker + tranchesUpdateInfo.get(trancheKey).takerReservesDiff,
                    isFresh: false,
                    ...tranches.get(trancheKey)
                }
            else
                tranches.get(trancheKey)
        )

    pure def tokenInSpentBasedOnOrderType(orderType: LimitOrderType, amountIn: int, remainingAmount: int): int =
        match orderType {
            | GoodTillCancelled => amountIn
            | FillOrKill => if (remainingAmount > 0 ) 0 else amountIn
            | ImmediateOrCancel => amountIn - remainingAmount
            // not taking into account if the block is given in the past, assuming the code forbids this
            | GoodTillTime(_) => amountIn
            | JustInTime => amountIn
        }

    pure def placeRemainingLimitOrderAmount(tranches: TrancheKey->Tranche, shares: TrancheShares, msg: PlaceLimitOrderMsg, amount: int, expirationBlockTime: BlockTime)
    : { tranches: TrancheKey->Tranche, tranchesShares: TrancheShares, key: Option[TrancheKey] } =

        if (amount == 0) { tranches: tranches, tranchesShares: shares, key: None }
        else
        // now it is reversed: the remaining amount of the tokenIn becomes a maker token of a new tranche
        val makerToken = msg.tokenIn
        // and the tokenOut, the one that the creator wants to receive, becomes the taker token
        val takerToken = msg.tokenOut
        val creator = msg.creator

        val trancheKey = calculateTrancheKey(makerToken, takerToken, msg.sellTick, tranches, expirationBlockTime)

        if (tranches.has(trancheKey)) // if the key was one of the previously existing
            val updatedTranches = tranches.setBy(
                trancheKey,
                old => { ...old, reservesMaker: old.reservesMaker + amount, totalMaker: old.totalMaker + amount }
            )

            val updatedShares = shares.setByWithDefault(
                (creator, trancheKey),
                old => { ...old, sharesOwned: old.sharesOwned + amount },
                { sharesOwned: 0, sharesWithdrawn: 0 }
            )

            { tranches: updatedTranches, tranchesShares:updatedShares, key: Some(trancheKey) }
        else // if we are adding a fully new tranche
            val newTranche = {
                isFresh: true,
                isActive: true,
                reservesMaker: amount,
                reservesTaker: 0,
                totalMaker: amount,
                totalTaker: 0,
                sellTick: msg.sellTick,
                expirationTime: expirationBlockTime,
                trancheKey: trancheKey,
                makerDenomination: makerToken,
                takerDenomination: takerToken
            }

            val updatedTranches = tranches.put(trancheKey, newTranche)
            val updatedShares = shares.put((creator, trancheKey), { sharesOwned: amount, sharesWithdrawn: 0 })

            { tranches: updatedTranches, tranchesShares: updatedShares, key: Some(trancheKey) }

    // DEPOSIT RELATED FUNCTIONS

    val emptyPool = {reserves: (0, 0), shares: 0}

    pure def isTokenBehindEnemyLines(state: State, isPlacingToken0: bool, pair: TokenPair, tick: TickIndex, fee: TickIndex): bool =
        // the tick at which I want to place the token
        val tickWithFee = computeReserveTick(tick, isPlacingToken0, fee)
        // the tick below which there should be no token1 liquidity
        val borderTick = -tickWithFee
        // if there is a pool with liquidity for the counterparty token
        // which is crossed by borderTick
        val poolLiquidityBehindEnemyLine = state.pools.keys().exists(id =>
            id.tokenPair == pair and
            // If we are placing token0, there are positive reserves of token1
            implies(isPlacingToken0, state.pools.get(id).reserves._2 > 0) and
            // If we are placing token1, there are positive reserves of token0
            implies(not(isPlacingToken0), state.pools.get(id).reserves._1 > 0) and
            // the tick at which the liquidity for the counterparty token is placed
            val existingTickWithFee1 = computeReserveTick(id.tick, not(isPlacingToken0), id.fee)
            borderTick > existingTickWithFee1
            )

        val tokenToPlace = if (isPlacingToken0) pair._1 else pair._2
        val counterpartyToken = if (isPlacingToken0) pair._2 else pair._1

        // if there is a tranche with liquidity for the counterparty token which is crossed by borderTick
        val trancheLiquidityBehindEnemyLine = state.tranches.keys().exists(key =>
            key.makerToken == counterpartyToken and
            key.takerToken == tokenToPlace and
            state.tranches.get(key).isActive and
            state.tranches.get(key).reservesMaker > 0 and
            borderTick > state.tranches.get(key).sellTick
            )

        poolLiquidityBehindEnemyLine or trancheLiquidityBehindEnemyLine

    // assumes that `pair` is sorted
    pure def isPoolBehindEnemyLines(state: State, pair: TokenPair, tick: TickIndex, fee: TickIndex, amounts: (int, int)): bool =
        val token0BEL = if (amounts._1 > 0) isTokenBehindEnemyLines(state, true, pair, tick, fee) else false
        val token1BEL = if (amounts._2 > 0) isTokenBehindEnemyLines(state, false, pair, tick, fee) else false
        token0BEL or token1BEL

    // Calculates the amounts that may be deposited so that the pool ratios get preserved
    pure def computeAmountsDeposit(reserves: (int, int), amounts: (int, int)): (int, int) = {
        val inAmount0 =
            if (reserves._2 > 0) min(amounts._1, fromRatio(reserves._1, reserves._2).mulInt(amounts._2).truncate())
            else amounts._1
        val inAmount1 =
            if (reserves._1 > 0) min(amounts._2, fromRatio(reserves._2, reserves._1).mulInt(amounts._1).truncate())
            else amounts._2

        (inAmount0, inAmount1)
    }

    pure def reservesRatio(p: Pool): Dec =
        // assumes that reserves._2 is positive
        fromRatio(p.reserves._1, p.reserves._2)

    pure def calcAutoswapAmount(amounts: (int, int), reserves: (int, int), token0SellTick: TickIndex): (int, int) = {
        val p = priceFromTick(-token0SellTick)
        if (reserves == (0, 0)) (0, 0) else
        val swapAmount = intDivDec(
            reserves._1 * amounts._2 - reserves._2 * amounts._1,
            fromInt(reserves._1).add(mul(p, fromInt(reserves._2)))
        )
        if (swapAmount.eq(zero)) (0, 0) else
        if (swapAmount.gt(zero)) (0, swapAmount.ceil())
        else
            val swapAmountAs1 = mulInt(swapAmount, -1)
            val amountSwapped0 = mul(swapAmountAs1, p)
            (amountSwapped0.ceil(), 0)
    }

    // LP.2 in specification invariants
    // autoswapFee = residualValue0 * (1 - 1.0001^-fee) + residualValue1 * (1 - 1.0001^-fee) * price1To0
    pure def computeAutoswapFeeValue(residualAmounts: (int, int), token0SellTick: TickIndex, fee: TickIndex): Dec =
        val res0 : Dec = residualAmounts._1.fromInt()
        val res1 : Dec = residualAmounts._2.fromInt()
        val factor: Dec = one.sub(priceFromTick(-fee))
        val price1To0: Dec = BASE_PRICE.pow(-token0SellTick)
        add(
            res0.mul(factor),
            res1.mul(factor).mul(price1To0)
        )

    // @audit-info not sure if to compute depositValue when autoswapping I should use the full amount in the
    // deposit message or just the one computed by computeAmountsDeposit
    // can totalPoolValue be 0? Invariant candidate!
    //
    // LP.1 and LP.2 in specification invariants
    // shareValue = totalPreexistingShares / (totalPoolValue + autswapFee)
    // sharesMinted = (depositValue - autoswapFee) * shareValue
    pure def computeSharesDeposit(existingShares: int, reserves: (int, int), amounts: (int, int), token0SellTick: int, autoswapFee: Dec): int =

        val poolValue = computePoolValue(reserves, token0SellTick)
        val depositValue: Dec = computeDepositValue(amounts, token0SellTick)
        if (poolValue.equal(zero)) depositValue.truncate()
        else
            val shareValue = intDivDec(existingShares, poolValue.add(autoswapFee))
            sub(depositValue, autoswapFee).mul(shareValue).truncate()


    // WITHDRAW TRANCHE RELATED FUNCTIONS

    // Assembles a set of tuples of creator and trancheKey, where the creator has some ownership in the tranche
    // Useful when nondeterministically selecting a creator and a tranche inside withdraw or cancel action
    pure def nonTrivialTranchesOwners(tranchesShares: TrancheShares): Set[(Addr, TrancheKey)] =
        tranchesShares.keys()
            // take into account those shares in which the creator has some ownership
            .filter(key => tranchesShares.get(key).sharesOwned > 0)

    pure def computeWithdrawAmountTakerToken(tranche: Tranche, userShares: UserTrancheShares): {taker_token: int, shares: int} =
        val percentFilled = calculatePercentFilled(tranche)
        val withdrawAmountInMakerToken = percentFilled.mulInt(userShares.sharesOwned).truncate() - userShares.sharesWithdrawn
        val withdrawAmountInTakerToken = mulInt(priceFromTick(tranche.sellTick), withdrawAmountInMakerToken).truncate()

        { taker_token: withdrawAmountInTakerToken, shares: withdrawAmountInMakerToken }


    // WITHDRAW POOL RELATED FUNCTIONS

    // Assumes that totalShares > 0, which is checked by the invariants
    // LP.4 in specification invariants
    pure def computeAmountsWithdrawnPool(reserves: (int, int), totalShares: int, sharesToRemove: int): (int, int) =
        // We mimic the implementation here for capturing truncation. The spec gives a more intuitive expression,
        // proRataShare = sharesToRemove / totalShares, which is then multiplies with total reserves.
        val outAmount0 = fromRatio(reserves._1*sharesToRemove, totalShares).truncate()
        val outAmount1 = fromRatio(reserves._2*sharesToRemove, totalShares).truncate()
        (outAmount0, outAmount1)

    pure def bothSides(p: Pool): bool =
        p.reserves._1 > 0 and p.reserves._2 > 0

    pure def getPoolId(tokens: (Token, Token), tick: TickIndex, fee: Fee): PoolId =
      {tokenPair: tokens, tick: tick, fee: fee}

    pure def trancheLTE(t1: TrancheKey, t2: TrancheKey): bool =
        // assume here: t1.pair == t2.pair; otherwise, unordered
        if (t1.sellTick == t2.sellTick)
            t1.id <= t2.id
        else
            t1.sellTick <= t2.sellTick

    pure def poolLTE(p1: PoolId, p2: PoolId, isToken0Liquidity: bool): bool =
        val tick1 = computeReserveTick(p1.tick, isToken0Liquidity, p1.fee)
        val tick2 = computeReserveTick(p2.tick, isToken0Liquidity, p2.fee)
        // if the ticks are the same
        if (tick1 == tick2)
            // then order by fee
            p1.fee <= p2.fee
        else
            // otherwise, order by ticks
            tick1 <= tick2

    pure def computeReserveTick(poolTick: TickIndex, isToken0Liquidity: bool, fee: Fee): TickIndex =
        if (isToken0Liquidity)
            poolTick + fee
        else
            -poolTick + fee

    // CANCEL RELATED FUNCTIONS
    pure def computeCancelAmountMakerToken(tranche: Tranche, usersShares: UserTrancheShares): int =
        // @audit-info The calculation here is different (but equivalent) than the one in the spec.
        // Are there perhaps some reasons to stick to the spec calculation?
        val percentUnfilled = calculatePercentUnfilled(tranche)
        val sharesOwned = usersShares.sharesOwned
        percentUnfilled.mulInt(sharesOwned).truncate()

    // OTHER HELPER FUNCTIONS
    pure def setByWithDefault(m: a -> b, k: a, op: (b) => b, default: b): a -> b = {
        if (m.has(k))
            m.setBy(k, op)
        else
            m.put(k, default).setBy(k, op)
    }

    pure def addAmounts(a: (int, int), b: (int, int)): (int, int) = {
        (a._1 + b._1, a._2 + b._2)
    }

    pure def reportIfFalse(cond: bool, name: str): bool =
        if (cond) true else q::debug(name, false)

    // Returns total amount of all coins (at users, tranches, or pools) for a state
    pure def totalCoins(s: State): Token -> int =
        val coinsAtUsers = s.coins.keys().fold(
            TOKENS.mapBy(token => 0),
            (acc, key) => acc.setBy(key._2, amount => amount + s.coins.get(key))
        )

        val updatedWithTranches = s.tranches.keys().fold(
            coinsAtUsers,
            (acc, key) => {
                val tranche = s.tranches.get(key)
                acc.setBy(tranche.makerDenomination, old => old + tranche.reservesMaker)
                    .setBy(tranche.takerDenomination, old => old + tranche.reservesTaker)
            }
        )
        val updatedWithPools = s.pools.keys().fold(
            updatedWithTranches,
            (acc, key) => {
                val pool = s.pools.get(key)
                acc
                    .setBy(key.tokenPair._1, old => old + pool.reserves._1)
                    .setBy(key.tokenPair._2, old => old + pool.reserves._2)
            }
        )
        updatedWithPools

    pure def isRatioReasonable(reserves: (int, int), amounts: (int, int)): bool =
        if (reserves._1 == 0 and amounts._2 == 0 or reserves._2 == 0 and amounts._1 == 0)
            false
        else if ((reserves._1 == 0 and amounts._1 == 0) or (reserves._2 == 0 and amounts._2 == 0))
            true
        else
            val reservesRatio = if (reserves._2 > 0) fromRatio(reserves._1, reserves._2) else fromInt(MAX_AMOUNT)
            val depositRatio = if (amounts._2 > 0) fromRatio(amounts._1, amounts._2) else fromInt(MAX_AMOUNT)
            div(reservesRatio, depositRatio).gt(fromRatio(1, 2)) and fromInt(2).gt(div(reservesRatio, depositRatio))

}
