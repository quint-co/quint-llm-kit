
module postconditions {
    import dec.* from "lib/dec"
    import types.* from "types"
    import consts.* from "consts"
    import utils.* from "utils"
    import basicSpells.* from "lib/basicSpells"

    /* Postconditions for basic state changes */

    pure def withdrawPoolStateChanges(before: State, after: State, msg: WithdrawPoolMsg): bool =
       val pair = orderTokenPair(msg.tokenPair)
       val tick = if (pair == msg.tokenPair) msg.tick else -msg.tick
       val poolId = getPoolId(pair, tick, msg.fee)
       // We assume that we do not remove empty pools
       // We do not check that poolBefore exists, as it is a precondition and not a postcondition
       val reservesBefore = before.pools.get(poolId).reserves
       val reservesAfter = after.pools.get(poolId).reserves
       val sharesBefore = before.pools.get(poolId).shares
       val sharesAfter = after.pools.get(poolId).shares
       val outAmounts = computeAmountsWithdrawnPool(reservesBefore, sharesBefore, msg.sharesAmount)
       and {
          // Reserves are updated
          reservesAfter._1 == reservesBefore._1 - outAmounts._1,
          reservesAfter._1 >= 0,
          reservesAfter._2 == reservesBefore._2 - outAmounts._2,
          reservesAfter._2 >= 0,
          // Coins are transferred
          after.coins.get((msg.creator, pair._1)) == before.coins.get((msg.creator, pair._1)) + outAmounts._1,
          after.coins.get((msg.creator, pair._2)) == before.coins.get((msg.creator, pair._2)) + outAmounts._2,
          // Shares are burned
          // We assume that we do not remove empty shares
          after.poolShares.get((msg.creator, poolId)) >= 0,
          after.poolShares.get((msg.creator, poolId)) == before.poolShares.get((msg.creator, poolId)) - msg.sharesAmount,
          sharesAfter >= 0,
          sharesAfter == sharesBefore - msg.sharesAmount,
       }


    pure def depositStateChanges(before: State, after: State, msg: DepositMsg): bool =
       // We could guarantee by design that the token pair is submitted in order
       val pair = orderTokenPair(msg.tokenPair)
       val amounts = if (pair == msg.tokenPair) msg.amountPair else (msg.amountPair._2, msg.amountPair._1)
       val token0SellTick = if (pair == msg.tokenPair) msg.token0SellTick else -msg.token0SellTick
       val poolId = getPoolId(pair, token0SellTick, msg.fee)

       val reservesBefore = if (before.pools.has(poolId)) before.pools.get(poolId).reserves else (0,0)
       val reservesAfter = after.pools.get(poolId).reserves
       val sharesBefore = if (before.pools.has(poolId)) before.pools.get(poolId).shares else 0
       val sharesAfter = after.pools.get(poolId).shares
       // Deposit and shares computation considering the optional autoswap
       val inAmountsBeforeAutoswap = computeAmountsDeposit(reservesBefore, amounts)
       val residualAmounts = calcAutoswapAmount(amounts, reservesBefore, token0SellTick)
       val inAmounts = if (msg.autoswap) amounts else inAmountsBeforeAutoswap
       val autoswapFee = if (msg.autoswap) computeAutoswapFeeValue(residualAmounts, token0SellTick, msg.fee) else zero
       val outShares = computeSharesDeposit(sharesBefore, reservesBefore, inAmounts, token0SellTick, autoswapFee)

       and {
          // Pool exists
          after.pools.has(poolId),

          // Reserves are updated
          reservesAfter._1 == reservesBefore._1 + inAmounts._1,
          reservesAfter._2 == reservesBefore._2 + inAmounts._2,

          // Coins are transferred
          after.coins.get((msg.creator, pair._1)) >= 0 and after.coins.get((msg.creator, pair._2)) >= 0,
          after.coins.get((msg.creator, pair._1)) == before.coins.get((msg.creator, pair._1)) - inAmounts._1,
          after.coins.get((msg.creator, pair._2)) == before.coins.get((msg.creator, pair._2)) - inAmounts._2,

          // Shares are minted
          after.poolShares.has((msg.creator, poolId)),
          after.poolShares.get((msg.creator, poolId)) == before.poolShares.getOrElse((msg.creator, poolId), 0) + outShares,
          sharesAfter == sharesBefore + outShares,

          // Pool ratio is maintained if no autoswap and both sides of the pool exist
          // @audit-issue DOES NOT HOLD
          // if (before.pools.has(poolId) and not(msg.autoswap) and before.pools.get(poolId).bothSides())
          //    val reservesBefore = before.pools.get(poolId).reserves
          //    val reservesAfter = after.pools.get(poolId).reserves
          //    if (reservesBefore._2 > 0)
          //        val ratioBefore = fromRatio(reservesBefore._1, reservesBefore._2)
          //        val ratioAfter = fromRatio(reservesAfter._1, reservesAfter._2)
          //        approxEqualDec(ratioAfter, ratioBefore, div(ratioBefore, fromInt(5)))
          //    else reservesAfter._2 == 0
          // else true
       }

    pure def placeLimitOrderStateChanges(before: State, after: State, msg: PlaceLimitOrderMsg): bool =
       val maxBuyTick = -msg.sellTick
       val fulfilledOrderInfo = swap(
          (msg.tokenIn, msg.tokenOut),
          before.tranches,
          before.pools,
          msg.amountIn,
          maxBuyTick,
          msg.maxAmountOut

       )
       val poolsUpdateInfo = fulfilledOrderInfo.poolUpdates
       val tranchesUpdateInfo = debug("tranchesUpdates: ", fulfilledOrderInfo.tranchesUpdates)
       val remainingAmount = debug("remaining amount = ", fulfilledOrderInfo.remainingAmount)
       val outAmount = debug("outAmount = ", fulfilledOrderInfo.outAmount)

       // A not fully filled fillOrKill: the state is not changed at all
       if (remainingAmount > 0 and msg.orderType == FillOrKill)
          before == after
       else and {
          // pools and tranches are updated correctly
          validatePoolsUpdates(before, after, poolsUpdateInfo),
          validateTranchesUpdates(before, after, tranchesUpdateInfo),
          swapInternallyConsistent(msg, fulfilledOrderInfo),

          // if there was still some extra amount, and we are not in the immediateOrCancel case, then it was added as a new tranche
          remainingAmount > 0 and not(msg.orderType == ImmediateOrCancel) implies (
             val userGotRest = if (msg.orderType == ImmediateOrCancel) outAmount else 0
             val userDiffOut = after.coins.get((msg.creator, msg.tokenOut)) - before.coins.get((msg.creator, msg.tokenOut))
             val makerToken = msg.tokenIn
             val takerToken = msg.tokenOut
             val blockExpirationTime = match msg.orderType {
                | GoodTillTime(time) => time
                | GoodTillCancelled => -1
                | JustInTime => before.blockNumber + 1
                | _ => -1
             }

             val trancheKey = calculateTrancheKey(makerToken, takerToken, msg.sellTick, before.tranches, blockExpirationTime)
             and {
                // user should have received the correct amount
                outAmount + userGotRest == userDiffOut,
                // the tranche key exists in the after state
                after.tranches.keys().contains(trancheKey),
                // the amount in this tranche is increased by the remainingAmount
                val totalMakerAmountBefore = if (before.tranches.keys().contains(trancheKey)) before.tranches.get(trancheKey).totalMaker else 0
                after.tranches.get(trancheKey).totalMaker == totalMakerAmountBefore + remainingAmount,
                // the user's shares now exists
                after.tranchesShares.has((msg.creator, trancheKey)),
                // the tranche shares are updated
                val totalSharesBefore =
                    if (before.tranches.keys().contains(trancheKey) and before.tranchesShares.has((msg.creator, trancheKey)))
                       before.tranchesShares.get((msg.creator, trancheKey)).sharesOwned
                    else 0
                val sharesDiff = after.tranchesShares.get((msg.creator, trancheKey)).sharesOwned - totalSharesBefore
                sharesDiff == remainingAmount
             }
          ),

          // checking that the user's amount got updated correctly
          val tokenOutGained = outAmount
          tokenOutGained == after.coins.get((msg.creator, msg.tokenOut)) - before.coins.get((msg.creator, msg.tokenOut)),
          val tokenInSpent = tokenInSpentBasedOnOrderType(msg.orderType, msg.amountIn, remainingAmount)
          tokenInSpent == before.coins.get((msg.creator, msg.tokenIn)) - after.coins.get((msg.creator, msg.tokenIn))
       }

    pure def singlehopSwapStateChanges(before: State, after: State, msg: SwapMsg): bool =
       val inAmount = msg.amount
       val fulfilledOrderInfo = swap(
          msg.tokenPair,
          before.tranches,
          before.pools,
          inAmount,
          msg.limitPriceTick,
          0
       )
       val poolsUpdateInfo = debug("pool update: ", fulfilledOrderInfo.poolUpdates)
       val tranchesUpdateInfo = fulfilledOrderInfo.tranchesUpdates
       val remainingAmount = debug("remaining Amount :",fulfilledOrderInfo.remainingAmount)
       val outAmount = debug("outAmount: ", fulfilledOrderInfo.outAmount)
       val usedAmount = debug("usedAmount: ", inAmount - remainingAmount)

       and {
          // Coins are transferred
          after.coins.get((msg.creator, msg.tokenPair._1)) == before.coins.get((msg.creator, msg.tokenPair._1)) - usedAmount,
          after.coins.get((msg.creator, msg.tokenPair._2)) == before.coins.get((msg.creator, msg.tokenPair._2)) + outAmount,

          // Reserves are updated
          validatePoolsUpdates(before, after, poolsUpdateInfo),

          // Tranches changes
          validateTranchesUpdates(before, after, tranchesUpdateInfo),

          // Sanity: I didn't use more than I put in
          inAmount >= usedAmount,

          // TODO: Perhaps a better postcondition would be that at least one of tranches or pools should have been updated.
       }

    pure def withdrawLimitOrderStateChanges(before: State, after: State, msg: WithdrawLimitOrderMsg): bool = {
        val tranche = before.tranches.get(msg.trancheKey)
        val usersTrancheShares = before.tranchesShares.get((msg.creator, msg.trancheKey))
        val withdrawnAmounts = computeWithdrawAmountTakerToken(tranche, usersTrancheShares)
        val withdrawnAmountTakerToken = withdrawnAmounts.taker_token
        val withdrawnShares = withdrawnAmounts.shares

        and {
           // the user's taker balance has increased for what was withdrawn
           withdrawnAmountTakerToken ==
              after.coins.get((msg.creator, before.tranches.get(msg.trancheKey).takerDenomination)) -
              before.coins.get((msg.creator, before.tranches.get(msg.trancheKey).takerDenomination)),

           // the reserves has decreased for what was withdrawn
           withdrawnAmountTakerToken ==
              before.tranches.get(msg.trancheKey).reservesTaker -
              after.tranches.get(msg.trancheKey).reservesTaker,

           // the user's shares withdrawn have increased appropriately
           withdrawnShares ==
              after.tranchesShares.get((msg.creator, msg.trancheKey)).sharesWithdrawn -
              before.tranchesShares.get((msg.creator, msg.trancheKey)).sharesWithdrawn,
        }
    }

    pure def cancelLimitOrderStateChanges(before: State, after: State, msg: CancelLimitOrderMsg): bool =
       val tranche_before: Tranche = before.tranches.get(msg.trancheKey)
       val users_tranches_shares_before = before.tranchesShares.get((msg.creator, msg.trancheKey))

       val cancelAmountOutMakerToken = computeCancelAmountMakerToken(tranche_before, users_tranches_shares_before)
       val withdrawAmountTakerToken = computeWithdrawAmountTakerToken(tranche_before, users_tranches_shares_before).taker_token
       and {
          // the user's balance has increased for what was cancelled
          cancelAmountOutMakerToken ==
          after.coins.get((msg.creator, tranche_before.makerDenomination)) -
          before.coins.get((msg.creator, tranche_before.makerDenomination)),

          // the totalMaker has decreased for what was cancelled
          users_tranches_shares_before.sharesOwned ==
          before.tranches.get(msg.trancheKey).totalMaker -
          after.tranches.get(msg.trancheKey).totalMaker,

          // This part corresponds to the point 2b from the spec document
          // user received their fair amount of maker tokens back
          // the user's taker token balance has increased for what was withdrawn when cancelling
          withdrawAmountTakerToken ==
             after.coins.get((msg.creator, tranche_before.takerDenomination)) -
             before.coins.get((msg.creator, tranche_before.takerDenomination)),

          // the totalTaker has decreased for what was cancelled
          withdrawAmountTakerToken ==
             before.tranches.get(msg.trancheKey).totalTaker -
             after.tranches.get(msg.trancheKey).totalTaker,

          // the user has no more shares in that tranche.
          after.tranchesShares.get((msg.creator, msg.trancheKey)) == { sharesOwned: 0, sharesWithdrawn: 0 },
       }

    /* Postconditions for specification invariants */

    /// Swap.1: When a user swaps, their limit price is honored
    pure def swapLimitPriceIsHonored(before: State, after: State, msg: SwapMsg): bool = {
       pure val buyingPrice = priceFromTick(msg.limitPriceTick)
       pure val usedAmount = after.coins.get((msg.creator, msg.tokenPair._1)) - before.coins.get((msg.creator, msg.tokenPair._1))
       pure val outAmount = after.coins.get((msg.creator, msg.tokenPair._2)) - before.coins.get((msg.creator, msg.tokenPair._2))
       // The amount I would get at my limit price
       val minAmount = intDivDec(usedAmount, buyingPrice).truncate()
       outAmount >= minAmount
    }

    /// After a tranche withdrawal and cancelation, the user will get the pro-rata portion of all
    /// the swap proceeds not yet claimed (since the user’s last withdrawal).
    /// [Maker Limit Order Invariants, 1]
    /// LO.1: When limit orders are swapped through the pro-rata portion of the swap value will returnable to all participants via withdraws
    /// LO.2: When canceling a limit order the participants will receive their pro-rata share of any unused maker denom as well as their pro-rata share of all swap proceeds.
    /// Cancellations will not change the future withdraw or cancel outcomes for other participants.
    pure def userGetsProRataPortionTaker(before: State, after: State, creator: Addr, trancheKey: TrancheKey): bool = {
        // How much the user actually got
        pure val takerDenom = before.tranches.get(trancheKey).takerDenomination
        pure val withdrawnAmountTakerToken = after.coins.get((creator, takerDenom)) - before.coins.get((creator, takerDenom))

        // How much it should have gotten
        pure val swaps = before.bookkeeping.tranches.swaps.getOrElse((creator, trancheKey), Set())
        pure val userShares = before.tranchesShares.get((creator, trancheKey))
        pure val tranche = before.tranches.get(trancheKey)
        pure def proRataShare(x: int): Dec = fromRatio(userShares.sharesOwned * x, tranche.totalMaker)
        pure val totalSwappedTakerAmount = swaps.fold(0, (acc, diff) => {
           acc + diff.takerReservesDiff
        })

        // There can be up to one off-by-one error per swap
        // Adding multiplication to allow for multiple roundings in calculations per single swap.
        pure val tolerance = debug("tolerance", swaps.size() * computeUnitTolerance(-tranche.sellTick))
        pure val expected = debug("expected: ", before.bookkeeping.tranches.proceedsToBeWithdrawn.getOrElse((creator, trancheKey), 0))
        pure val diff = debug("diff", abs(withdrawnAmountTakerToken - expected))
        diff <= tolerance
    }

    pure def userGetsProRataPortionMaker(before: State, after: State, creator: Addr, trancheKey: TrancheKey): bool = {
        // How much the user actually got
        pure val makerDenom = before.tranches.get(trancheKey).makerDenomination
        pure val withdrawnAmountMakerToken = after.coins.get((creator, makerDenom)) - before.coins.get((creator, makerDenom))

        // How much it should have gotten
        pure val userShares = before.tranchesShares.get((creator, trancheKey))
        pure val tranche = before.tranches.get(trancheKey)
        pure def proRataShare(x: int): Dec = fromRatio(userShares.sharesOwned * x, tranche.totalMaker)

        // allowing for rounding errors
        val tolerance = 1
        abs(withdrawnAmountMakerToken - proRataShare(tranche.reservesMaker).truncate()) <= tolerance
    }

    // Invariant: LP profit from their deposits
    // simplified LP.5 in specification invariants
    // This doesn't check the exact value of profit, but should hold even for partial withdrawals
    pure def poolProfit(before: State, after: State, msg: WithdrawPoolMsg): bool =
       after.bookkeeping.pools.deposits.keys().forall(((creator, poolId)) =>
          // If the user has withdrawn all their shares
          after.poolShares.get((creator, poolId)) == 0 implies
             val depositedValue = before.bookkeeping.pools.depositValues.getOrElse((creator, poolId), 0)
             val withdrawn = after.bookkeeping.pools.withdrawals.getOrElse((creator, poolId), (0, 0))
             val swaps = before.bookkeeping.pools.swaps.getOrElse((creator, poolId), Set())
             // If there were swaps, the user withdrew more value than deposited
             // TODO: We could maybe calculate the exact amount here from the swapped amounts as we do for tranches
             // Actually that might not be possible with the current tracking of swaps since there are partial withdraws for pools
            //  TODO: If there were swaps, the user collected also the fee on those swaps
            val totalWithdrawn = debug("totalWithdrawn: ", computeDepositValue(withdrawn, poolId.tick).truncate())
            val totalDeposited = debug("totalDeposited: ", depositedValue)
            val tol = TOLERANCE * computeUnitTolerance(poolId.tick)
             if (swaps != Set()) totalWithdrawn + tol >= totalDeposited
             // Otherwise, the user withdrew no less value than deposited
             else
                abs(totalWithdrawn - totalDeposited) <= tol

       )

    /// LP.5: When a single user withdraws 100% of their shares from the pool
    /// - For each time period t when a swap occurs a user receives the correct proportion of the swap fee
    /// - depositValue = token0 + token1 * price
    /// - swapFee = token0In * poolFee + token1In  * poolFee * price
    /// - poolValue = reserves0 + reserves1 * price
    pure def userGetsProRataPortionIfFullWithdraw(before: State, after: State, msg: WithdrawPoolMsg): bool = {
      // TODO
      true
    }

    /// LP.3: Swapping through a pool can only increase the total value of the pool (assuming token price is the tick price)
    pure def poolValueIncreased(before: State, after: State, msg: DepositMsg): bool = {
       val pair = orderTokenPair(msg.tokenPair)
       val amounts = if (pair == msg.tokenPair) msg.amountPair else (msg.amountPair._2, msg.amountPair._1)
       val token0SellTick = if (pair == msg.tokenPair) msg.token0SellTick else -msg.token0SellTick
       val poolId = getPoolId(pair, token0SellTick, msg.fee)

       val poolValueBefore: Dec =
          if (before.pools.has(poolId)) computePoolValue(before.pools.get(poolId).reserves, token0SellTick) else zero
       val poolValueAfter: Dec = computePoolValue(after.pools.get(poolId).reserves, token0SellTick)

       // since this is a single step, setting the tolerance to 1
       poolValueAfter.approx_gt(poolValueBefore, one)
    }

    /// After each singlehopSwap, deposit, or placeLimitOrder, the values of
    /// pools with the relevant pair has remained the same or it has increased (L.P.3).
    pure def nonDecreasingPools(before: State, after: State, tokenPair: TokenPair): bool = {
       pure def relevantPoolIdsBefore = before.pools.keys().filter(p => p.tokenPair == tokenPair)
       pure def relevantPoolIdsAfter = after.pools.keys().filter(p => p.tokenPair == tokenPair)

       and {
          relevantPoolIdsBefore.subseteq(relevantPoolIdsAfter),
          relevantPoolIdsBefore.forall(p => {
             approx_gte(
                computePoolValue(after.pools.get(p).reserves, p.tick),
                computePoolValue(before.pools.get(p).reserves, p.tick),
                one
             )
          })
       }
    }

    pure def postconditionForMessage(before: State, after: State, message: Message): bool = {
        match message {
            | DepositPool(msg) => and {
                depositStateChanges(before, after, msg).reportIfFalse("depositStateChanges postcondition"),
                poolValueIncreased(before, after, msg).reportIfFalse("poolValueIncreased postcondition"),
            }

            | PlaceLimitOrder(msg) => and {
                placeLimitOrderStateChanges(before, after, msg).reportIfFalse("placeLimitOrderStateChanges postcondition"),
                nonDecreasingPools(before, after, (msg.tokenIn, msg.tokenOut)).reportIfFalse("nonDecreasingPools postcondition"),
            }

            | CancelLimitOrder(msg) => and {
                cancelLimitOrderStateChanges(before, after, msg).reportIfFalse("cancelLimitOrderStateChanges postcondition"),
                userGetsProRataPortionTaker(before, after, msg.creator, msg.trancheKey).reportIfFalse("userGetsProRataPortionTaker postcondition"),
                userGetsProRataPortionMaker(before, after, msg.creator, msg.trancheKey).reportIfFalse("userGetsProRataPortionMaker postcondition"),
            }

            | WithdrawLimitOrder(msg) => all {
                withdrawLimitOrderStateChanges(before, after, msg).reportIfFalse("withdrawLimitOrderStateChanges postcondition"),
                userGetsProRataPortionTaker(before, after, msg.creator, msg.trancheKey).reportIfFalse("userGetsProRataPortionTaker postcondition"),
            }

            | WithdrawPool(msg) => and {
                withdrawPoolStateChanges(before, after, msg).reportIfFalse("withdrawPoolStateChanges postcondition"),
                poolProfit(before, after, msg).reportIfFalse("poolProfit postcondition"),
            }

            | Swap(msg) => and {
                swapLimitPriceIsHonored(before, after, msg).reportIfFalse("swapLimitPriceIsHonored postcondition"),
                nonDecreasingPools(before, after, msg.tokenPair).reportIfFalse("nonDecreasingPools postcondition"),
            }

            | _ => true
        }
    }
}
