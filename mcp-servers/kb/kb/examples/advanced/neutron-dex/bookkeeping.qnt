module bookkeeping {
    import basicSpells.* from "lib/basicSpells"
    import utils.* from "utils"
    import types.* from "types"
    import dec.* from "lib/dec"

    pure def trackTranchePlacement(t: TrackedValue, addr: Addr, key: Option[TrancheKey], amount: int): TrackedValue = {
        match key {
          | None => t
          | Some(key) => {
              pure val placements = t.tranches.placements
              pure val newPlacements =
                  if (placements.has((addr, key)))
                      placements.setBy((addr, key), v => v + amount)
                  else
                      placements.put((addr, key), amount)

              { ...t, tranches: { ...t.tranches, placements: newPlacements } }
          }
        }
    }

    pure def trackTrancheWithdrawal(t: TrackedValue, addr: Addr, key: TrancheKey, amount: int): TrackedValue = {
        pure val withdrawals = t.tranches.withdrawals
        pure val newWithdrawals =
            if (withdrawals.has((addr, key)))
                withdrawals.setBy((addr, key), v => v + amount)
            else
                withdrawals.put((addr, key), amount)

        // Reset swaps being tracked by for this address and tranche key
        pure val newSwaps = t.tranches.swaps.put((addr, key), Set())
        pure val newProceeds = t.tranches.proceedsToBeWithdrawn.put((addr, key), 0)

        { ...t, tranches: { ...t.tranches, withdrawals: newWithdrawals, swaps: newSwaps, proceedsToBeWithdrawn: newProceeds } }
    }

    pure def trackTrancheCancelation(t: TrackedValue, addr: Addr, key: TrancheKey, makerAmount: int, takerAmount: int): TrackedValue = {
        pure val cancelations = t.tranches.cancelations
        pure val newCancelations =
            if (cancelations.has((addr, key)))
                cancelations.setBy((addr, key), v => (v._1 + makerAmount, v._2 + takerAmount))
            else
                cancelations.put((addr, key), (makerAmount, takerAmount))

        // Reset swaps being tracked by for this address and tranche key
        pure val newSwaps = t.tranches.swaps.put((addr, key), Set())
        pure val newProceeds = t.tranches.proceedsToBeWithdrawn.put((addr, key), 0)

        { ...t, tranches: { ...t.tranches, cancelations: newCancelations, swaps: newSwaps, proceedsToBeWithdrawn: newProceeds } }
    }

    pure def trackPoolDeposit(t: TrackedValue, addr: Addr, poolId: PoolId, amounts: (int, int), performAutoswap: bool,
                             residualAmounts: (int, int), poolShares: PoolShares, token0SellTick: int, autoswapFeeValue: Dec): TrackedValue = {
        pure val swappedAmounts = if (performAutoswap) Some(residualAmounts) else None

        pure val depositedValue = computeDepositValue(amounts, token0SellTick)
        pure val pureDepositedValue = sub(depositedValue, autoswapFeeValue).truncate()

        pure val deposits = t.pools.deposits
        pure val newDeposits =
            if (deposits.has((addr, poolId)))
                deposits.setBy((addr, poolId), (oldAmounts) => (oldAmounts._1 + amounts._1, oldAmounts._2 + amounts._2))
            else
                deposits.put((addr, poolId), amounts)

        pure val newSwaps = match swappedAmounts {
            | Some(amounts) => {
                pure val diff = { token0Diff: amounts._1, token1Diff: amounts._2 }
                poolShares.keys().filter(((_addr, id)) => id == poolId).fold(t.pools.swaps, (swaps, shareKey) => {
                    swaps.setByWithDefault(shareKey, s => s.union(Set(diff)), Set())
                })
            }
            | None => t.pools.swaps
        }

        pure val depositValues = t.pools.depositValues
        pure val newDepositValues =
            if (depositValues.has((addr, poolId)))
                depositValues.setBy((addr, poolId), v => v + pureDepositedValue)
            else
                depositValues.put((addr, poolId), pureDepositedValue)


        { ...t, pools: { ...t.pools, deposits: newDeposits, swaps: newSwaps, depositValues: newDepositValues } }
    }

    pure def trackPoolWithdrawal(t: TrackedValue, addr: Addr, poolId: PoolId, amounts: (int, int), poolShares: PoolShares): TrackedValue = {
        pure val withdrawals = t.pools.withdrawals
        pure val newWithdrawals =
            if (withdrawals.has((addr, poolId)))
                withdrawals.setBy((addr, poolId), (oldAmounts) => (oldAmounts._1 + amounts._1, oldAmounts._2 + amounts._2))
            else
                withdrawals.put((addr, poolId), amounts)

        // Reset swaps being tracked by for this address and pool id if the user doesn't have shares left
        pure val newSwaps = if (poolShares.get((addr, poolId)) == 0) t.pools.swaps.put((addr, poolId), Set()) else t.pools.swaps

        { ...t, pools: { ...t.pools, withdrawals: newWithdrawals, swaps: newSwaps } }
    }

    pure def trackSwap(t: TrackedValue, tranches: TrancheKey->Tranche, tranchesShares: TrancheShares, poolShares: PoolShares, swapUpdate: SwapUpdateInfo): TrackedValue = {
        pure val newTrancheSwaps = swapUpdate.tranchesUpdates.keys().fold(t.tranches.swaps, (swaps, key) => {
            pure val diffForKey = swapUpdate.tranchesUpdates.get(key)
            tranchesShares.keys().filter(((_addr, k)) => k == key).fold(swaps, (swaps, key) => {
                swaps.setByWithDefault(key, s => s.union(Set(diffForKey)), Set())
            })
        })

        pure val newProceeds = swapUpdate.tranchesUpdates.keys().fold(t.tranches.proceedsToBeWithdrawn, (proceeds, key) => {
            pure val diffForKey = swapUpdate.tranchesUpdates.get(key)
            tranchesShares.keys().filter(((_addr, k)) => k == key).fold(proceeds, (proceeds, shareKey) => {
                val userShares = tranchesShares.get(shareKey)
                val tranche = tranches.get(key)
                pure def proRataShare(x: int): Dec = fromRatio(userShares.sharesOwned * x, tranche.totalMaker)
                val usersPart = proRataShare(diffForKey.takerReservesDiff).truncate()

                proceeds.setByWithDefault(shareKey, s => s + usersPart, 0)
            })
        })

        pure val newPoolSwaps = swapUpdate.poolUpdates.keys().fold(t.pools.swaps, (swaps, poolId) => {
            pure val diffForPool = swapUpdate.poolUpdates.get(poolId)
            poolShares.keys().filter(((_addr, id)) => id == poolId).fold(swaps, (swaps, shareKey) => {
                swaps.setByWithDefault(shareKey, s => s.union(Set(diffForPool)), Set())
            })
        })

        { tranches: { ...t.tranches, swaps: newTrancheSwaps, proceedsToBeWithdrawn: newProceeds }, pools: { ...t.pools, swaps: newPoolSwaps } }
    }
}
