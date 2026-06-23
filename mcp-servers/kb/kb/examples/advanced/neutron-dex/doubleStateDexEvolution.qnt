module doubleStateDexEvolution {
    import types.* from "types"
    import utils.* from "utils"
    import postconditions.* from "postconditions"
    import baseDexEvolution as base from "baseDexEvolution"

    // EXTRA STATE VARIABLES
    var actionSuccess: bool
    var actionTaken: Message
    var stateWithoutAlicesCancellations: State

    // STATE MACHINE
    action init = all {
        base::init,
        actionTaken' = Init,
        actionSuccess' = true,
        stateWithoutAlicesCancellations' = initState,
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
        actionTaken' = msg,
        stateWithoutAlicesCancellations' = match msg {
          // Don't update this variable when alice cancels
          | CancelLimitOrder(r) => if (r.creator == "Alice") stateWithoutAlicesCancellations else result.state
          // Update otherwise
          | _ => result.state
        }
    }

    // INVARIANTS
    val cancellationsFromAliceDontAffectOtherUsersShares = all {
        base::state.tranchesShares.keys().forall(addr => {
            addr != "Alice" implies
                base::state.tranchesShares.get(addr) == stateWithoutAlicesCancellations.tranchesShares.get(addr)
        }),
        base::state.poolShares == stateWithoutAlicesCancellations.poolShares,
        base::state.pools == stateWithoutAlicesCancellations.pools,
        base::state.blockNumber == stateWithoutAlicesCancellations.blockNumber,
    }
}
