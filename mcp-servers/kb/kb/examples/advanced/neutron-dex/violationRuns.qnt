module violationRuns {
    import dec.* from "lib/dec"
    import types.* from "types"
    import consts.* from "consts"
    import utils.* from "utils"
    import basicSpells.* from "lib/basicSpells"
    import Dex.* from "dex"
    import baseDexEvolution.* from "baseDexEvolution"
    import postconditions.* from "postconditions"
    import runsUtils.* from "runsUtils"

    run noLossViolationAutoswapRun =
        val poolKey = { fee: 20000, tick: -100, tokenPair: ("A", "B") }
        init
        .then(
            val msg = depositMsgPool("Bob", poolKey, (11,0), true)
            val res = deposit(state, msg)
            all {
                state' = res.state,
                assert(res.state.pools.get(poolKey).reserves == (11,0)),
                assert(res.state.poolShares.get(("Bob",poolKey)) == 11),

            }
        )
        .then(
            val msg = depositMsgPool("Alice", poolKey, (0, 2215), true)
            val res = deposit(state, msg)
            all {
                state' = res.state,
                assert(res.state.pools.get(poolKey).reserves == (11,2215)),
                assert(res.state.poolShares.get(("Alice", poolKey)) == 1)
            }
        )
        .then(
            val msg = withdrawMsgPool("Alice", poolKey, 1)
            val res = withdrawPool(state, msg)
            all {
                state' = res.state,
                assert(res.state.pools.get(poolKey).reserves == (11,2215-184)),
                assert(res.state.poolShares.get(("Alice", poolKey)) == 0)
            }
        )
        .then(
            val totalDeposited = state.bookkeeping.pools.depositValues.get(("Alice", poolKey))
            val withdrawnTokens = state.bookkeeping.pools.withdrawals.get(("Alice", poolKey))
            val totalWithdrawn = computeDepositValue(withdrawnTokens, poolKey.tick).truncate()
            all {
                assert(totalDeposited - totalWithdrawn > 100),
                state' = state
            }
        )

    // ------ The run illustrating the violation of the [NO-LOSS] and [NO-GAIN] properties
    // It is a cleared version of the generated trace violations/noLossViolation.itf.json
    run noLossViolationRoundingRun =
        val key = { fee: 6, tick: -9, tokenPair: ("B", "C") }
        init.then(
            val msg = depositMsgPool("Bob", key, (211,337), true)
            val res = deposit(state, msg)
            all {
                state' = res.state,
                assert(res.error == "nil"),
                assert(sharesGained(state, res.state, "Bob", key) == 548)
            })
        .then(
            val msg = withdrawMsgPool("Bob", key, 82)
            val res = withdrawPool(state, msg)
            all {
                state' = res.state,
                assert(res.error == "nil"),
                assert(coinsGained(state, res.state, "Bob", "B") == 31),
                assert(coinsGained(state, res.state, "Bob", "C") == 50)
            })
        .then(
            val msg = depositMsgPool("Carol", key, (927, 11), false)
            val res = deposit(state, msg)
            all {
                state' = res.state,
                assert(res.error == "nil"),
                // only gets 16 due to autoswap=false
                assert(sharesGained(state, res.state, "Carol", key) == 16)
            })
        .then(
            val msg = withdrawMsgPool("Carol", key, 7)
            val res = withdrawPool(state, msg)
            all {
                state' = res.state,
                assert(res.error == "nil"),
                assert(coinsGained(state, res.state, "Carol", "B") == 2),
                assert(coinsGained(state, res.state, "Carol", "C") == 4)
            })
        .then(
            val msg = withdrawMsgPool("Carol", key, 4)
            val res = withdrawPool(state, msg)
            all {
                state' = res.state,
                assert(res.error == "nil"),
                assert(coinsGained(state, res.state, "Carol", "B") == 1),
                assert(coinsGained(state, res.state, "Carol", "C") == 2)
            })
        .then(
            val msg = withdrawMsgPool("Carol", key, 1)
            val res = withdrawPool(state, msg)
            all {
                state' = res.state,
                assert(res.error == "nil"),
                assert(coinsGained(state, res.state, "Carol", "B") == 0),
                assert(coinsGained(state, res.state, "Carol", "C") == 0)
            })
        .then(
            val msg = withdrawMsgPool("Bob", key, 308)
            val res = withdrawPool(state, msg)
            all {
                state' = res.state,
                assert(res.error == "nil"),
                assert(coinsGained(state, res.state, "Bob", "B") == 119),
                assert(coinsGained(state, res.state, "Bob", "C") == 191)
            })
        .then(
            val msg = withdrawMsgPool("Carol", key, 3)
            val res = withdrawPool(state, msg)
            all {
                state' = res.state,
                assert(res.error == "nil"),
                assert(coinsGained(state, res.state, "Carol", "B") == 1),
                assert(coinsGained(state, res.state, "Carol", "C") == 1)
            })
        .then(
            val msg = withdrawMsgPool("Carol", key, 1)
            val res = withdrawPool(state, msg)
            all {
                state' = res.state,
                assert(res.error == "nil"),
                assert(coinsGained(state, res.state, "Carol", "B") == 0),
                assert(coinsGained(state, res.state, "Carol", "C") == 0)
            })
        .then(
            val carolDeposited = state.bookkeeping.pools.depositValues.get(("Carol", key))
            val carolWithdraws = computeDepositValue(state.bookkeeping.pools.withdrawals.get(("Carol", key)), key.tick).truncate()
            all {
             state' = state,
             state.poolShares.get(("Carol", key)) == 0,
             carolDeposited - carolWithdraws == 6
            })
        .then(
            val msg = withdrawMsgPool("Bob", key, 158)
            val res = withdrawPool(state, msg)
            all {
                state' = res.state,
                assert(res.error == "nil"),
                assert(coinsGained(state, res.state, "Bob", "B") == 63),
                assert(coinsGained(state, res.state, "Bob", "C") == 100)
            })
        .then(all {
            state' = state,
            assert(state.poolShares.get(("Bob", key)) == 0),
            val bobDeposited = state.bookkeeping.pools.depositValues.get(("Bob", key))
            val bobWithdrew = computeDepositValue(state.bookkeeping.pools.withdrawals.get(("Bob", key)), key.tick).truncate()
            // Bob has gained something (even though there were no swaps, so he gained what Carol has lost)
            assert(bobWithdrew - bobDeposited > 5)
        })


    run noLossOnTranchesViolationRun =
        val trancheKey = {
        makerToken: "C",
        takerToken: "A",
        sellTick: -68517,
        id: 1
        }
        init
        .then(
            val placeMsg = placeLimitMsg("Alice", trancheKey.makerToken, trancheKey.takerToken, trancheKey.sellTick, 580)
            val res = placeLimitOrder(state, placeMsg)
            all {
                state' = res.state,
                assert(res.error == "nil"),
                assert(res.state.tranchesShares.get(("Alice", trancheKey)).sharesOwned == 580),
                assert(res.state.tranches.get(trancheKey).reservesMaker == 580),
                assert(res.state.tranches.get(trancheKey).reservesTaker == 0)
            }
        )
        .then(
            val swapMsg = {creator: "Bob", tokenPair: ("A", "C"), amount: 2, limitPriceTick: trancheKey.sellTick}
            val res = singlehopSwap(state, swapMsg)
            all{
                state' = res.state,
                assert(res.state.tranchesShares.get(("Alice", trancheKey)).sharesOwned == 580),
                assert(res.state.tranches.get(trancheKey).reservesMaker == 0),
                assert(res.state.tranches.get(trancheKey).reservesTaker == 1)
            }
        )
        .then(
            val withdrawMsg = {creator: "Alice", trancheKey: trancheKey}
            val res = withdrawLimitOrder(state, withdrawMsg)
            all{
                state' = res.state,
                assert(res.state.tranchesShares.get(("Alice", trancheKey)).sharesWithdrawn == 580),
                assert(res.state.tranches.get(trancheKey).reservesMaker == 0),
                assert(res.state.tranches.get(trancheKey).reservesTaker == 1),
                val placementValue = res.state.bookkeeping.tranches.placements.get(("Alice", trancheKey))
                val withdrawnValue = res.state.bookkeeping.tranches.withdrawals.get(("Alice", trancheKey))
                assert(placementValue - withdrawnValue == 580)

            }
        )

    // // ------ The run illustrating the violation of the [POOL-RATIO-CONSTANT] property
    // // The runs showcases how a reserves ratio changed from
    // // 1/73 = 0.0136 to 4/724 = 0.0055
    // // In the inverse, this is going from 73 to 181

    run autoswapIssueRun =
        val testPoolKey: PoolId = { fee: 4, tick: -2, tokenPair: DEFAULT_TOKEN_PAIR }
        val creator = DEFAULT_CREATOR
        init
        .then(
            val depositMsg: DepositMsg = depositMsgPool(creator, testPoolKey, (1, 73), false)
            val res = deposit(state, depositMsg)
            val updatedPool = res.state.pools.get(testPoolKey)
            all {
                state' = res.state,
                assert(updatedPool.reservesRatio() == (1, 73))
            }
        )
        .then(
            val depositMsg: DepositMsg = depositMsgPool(creator, testPoolKey, (21, 145), false)
            val res = deposit(state, depositMsg)
            val updatedPool = res.state.pools.get(testPoolKey)
            all {
                state' = res.state,
                assert(updatedPool.reservesRatio() == (2, 218))
            })
        .then(
            val depositMsg: DepositMsg = depositMsgPool(creator, testPoolKey, (21, 217), false)
            val res = deposit(state, depositMsg)
            val updatedPool = res.state.pools.get(testPoolKey)
            all {
                state' = res.state,
                assert(updatedPool.reservesRatio() == (3, 435))
            })
        .then(
            val depositMsg: DepositMsg = depositMsgPool(creator, testPoolKey, (21, 289), false)
            val res = deposit(state, depositMsg)
            val updatedPool = res.state.pools.get(testPoolKey)
            all {
                state' = res.state,
                assert(updatedPool.reservesRatio() == (4, 724))
            })

    }
