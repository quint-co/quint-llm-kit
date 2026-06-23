module dexEvolution {
    import basicSpells.* from "lib/basicSpells"
    import dec from "lib/dec"
    import types.* from "types"
    import utils.* from "utils"
    import postconditions.* from "postconditions"
    import bookkeeping.* from "bookkeeping"
    import baseDexEvolution as base from "baseDexEvolution"

    // EXTRA STATE VARIABLES
    var previousState: State
    var actionSuccess: bool
    var actionTaken: Message

    // STATE MACHINE
    action init = all {
        base::init,
        previousState' = initState,
        actionTaken' = Init,
        actionSuccess' = true,
    }

    action step: bool = any {
        base::placeLimitOrderAction(assignResult),
        base::cancelLimitOrderAction(assignResult),
        base::withdrawLimitOrderAction(assignResult),
        base::withdrawPoolAction(assignResult),
        base::depositAction(assignResult),
        base::singlehopSwapAction(assignResult),
        base::advanceTimeAction(assignResult),
    }

    action assignResult(result: Result, msg: Message): bool = all {
        actionSuccess' = result.error == "nil",
        base::state' = result.state,
        previousState' = base::state,
        actionTaken' = msg
    }

    // INVARIANTS

    // Invariant: postconditions always hold
    val postconditions = actionSuccess implies postconditionForMessage(previousState, base::state, actionTaken)

    val allInvariants = all {
        base::allInvariants,
        postconditions.reportIfFalse("postconditions"),
    }


    // WITNESSES

    val trancheAndPoolForSwap = {
        match actionTaken {
            | Swap(msg) => {
                val relevantTranches = base::state.tranches.keys().filter(key =>
                    key.makerToken == msg.tokenPair._1 and
                    key.takerToken == msg.tokenPair._2 and
                    key.sellTick <= msg.limitPriceTick and
                    base::state.tranches.get(key).isActive and
                    base::state.tranches.get(key).reservesMaker > 0
                )

                val normalizedPair = orderTokenPair(msg.tokenPair)
                val isPairNormalized = msg.tokenPair == normalizedPair
                val askingForToken0Liquidity = msg.tokenPair._2 == normalizedPair._1

                // find the pool that has liquidity that the user is asking for, and the tick is better than maxPriceTick
                val relevantPools = base::state.pools.keys().filter(id =>
                    id.tokenPair == normalizedPair and
                    implies(askingForToken0Liquidity, base::state.pools.get(id).reserves._1 > 0) and
                    implies(not(askingForToken0Liquidity), base::state.pools.get(id).reserves._2 > 0) and
                    computeReserveTick(id.tick, askingForToken0Liquidity, id.fee) <= msg.limitPriceTick
                )

                and {
                  relevantTranches != Set(),
                  relevantPools != Set(),
                }
            }
            | _ => false
        }
    }
}
