module runs {
    import dec.* from "lib/dec"
    import types.* from "types"
    import consts.* from "consts"
    import utils.* from "utils"
    import basicSpells.* from "lib/basicSpells"
    import Dex.* from "dex"
    import baseDexEvolution.* from "baseDexEvolution"
    import runsUtils.* from "runsUtils"

    run test =
        val poolKey1 = { fee: 10, tick: 23027, tokenPair: ("A", "B") }
        val poolKey2 = { fee: 10, tick: 200, tokenPair: ("A", "B") }
        val msg: DepositMsg = depositMsgPool("Bob", poolKey1, (200, 0), true)
        val msg2 = depositMsgPool("Carol", poolKey2, (200,0), true)

        init
          .then(state' = deposit(state, msg).state)
          .then(state' = deposit(state, msg).state)

    run depositLimitInteraction =
        val poolKey = { fee: 39, tick: 130, tokenPair: ("A", "B") }
        init.then(
            val msg = depositMsgPool("Bob", poolKey, (0, 6071), true)
            val res = deposit(state, msg)
            all{
                state' = res.state,
                assert(res.state.poolShares.get(("Bob", poolKey)) == 6150),
                assert(res.state.pools.get(poolKey).reserves == (0, 6071))
            }
        )
        .then(
            val msg: PlaceLimitOrderMsg = {
                creator: "Alice",
                orderType: GoodTillCancelled,
                tokenIn: "A",
                tokenOut: "B",
                amountIn: 9123,
                sellTick: 69,
                maxAmountOut: -1
            }
            val res = placeLimitOrder(state, msg)
            all{
                assert(res.error == "nil"),
                assert(res.state.pools.get(poolKey).reserves == (6126,0)),
                assert(res.state.bookkeeping.pools.swaps.get(("Bob", poolKey)) != Set()),
                state' = res.state,
            }
        )

    run swapExample_run =
        val poolKey = { fee: 10, tick: 23027, tokenPair: ("A", "B") }
        val trancheKey = { id: 1, makerToken: "A", takerToken: "B", sellTick: 23037 }
        init.then(
            val msg: PlaceLimitOrderMsg = {
                creator: "Alice",
                orderType: GoodTillCancelled,
                tokenIn: trancheKey.makerToken,
                tokenOut: trancheKey.takerToken,
                amountIn: 100,
                sellTick: trancheKey.sellTick,
                maxAmountOut: -1
            }
            val res = placeLimitOrder(state, msg)
            all{
                state' = res.state,
                assert(res.error == "nil")
            }
        )
        .then(
            val msg: DepositMsg = depositMsgPool("Bob", poolKey, (10, 0), true)
            val res = deposit(state, msg)
            state' = res.state
        )
        .then(
            val msg: SwapMsg = {
                creator: "Carol",
                tokenPair: ("B", "A"),
                amount: 50,
                limitPriceTick: 30000
            }
            val res = singlehopSwap(state, msg)
            val tranche = res.state.tranches.get(trancheKey)
            val pool  = res.state.pools.get(poolKey)
            all{
                assert(res.error == "nil"),
                // the swap didn't reach the tranche
                assert(tranche.isFresh),
                assert(pool.reserves == (6, 41)),
                assert(res.state.coins.get(("Carol", "A")) == 10004 and res.state.coins.get(("Carol", "B")) == 9959),
                state' = res.state,
            }
        )
        .then(
            val msg: SwapMsg = {
                creator: "Carol",
                tokenPair: ("B", "A"),
                amount: 200,
                limitPriceTick: 30000
            }
            val res = singlehopSwap(state, msg)
            val tranche = res.state.tranches.get(trancheKey)
            val pool  = res.state.pools.get(poolKey)
            all{
                state' = res.state,
                assert(res.error == "nil"),
                assert(not(tranche.isFresh)),
                assert(tranche.reservesMaker == 87),
                assert(pool.reserves == (0, 102)),
                assert(res.state.coins.get(("Carol", "A")) == 10023 and res.state.coins.get(("Carol", "B")) == 9767),
            }
        )

    run behindTrancheEnemyLines_run =
        val creator = DEFAULT_CREATOR
        init.then(
            val order: PlaceLimitOrderMsg = {
                creator: creator,
                orderType: GoodTillCancelled,
                tokenIn: "A",
                tokenOut: "B",
                amountIn: 10,
                sellTick: 100,
                maxAmountOut: -1
            }
            val res = placeLimitOrder(state, order)
            state' = res.state
        )
        .then(
            val key1: PoolId = {fee: 5, tick: 104, tokenPair: ("A", "B")}
            val depositMsg: DepositMsg = depositMsgPool(creator, key1, (0, 10), true)
            val res = deposit(state, depositMsg)
            all{
                // not behind enemy lines yet
                assert(res.error == "nil"),
                state' = res.state
            }
        )
        .then(
            val key1: PoolId = {fee: 5, tick: 106, tokenPair: ("A", "B")}
            val depositMsg: DepositMsg = depositMsgPool(creator, key1, (0, 10), true)
            val res = deposit(state, depositMsg)
            all{
                // now we are behind enemy lines
                assert(not(res.error == "nil")),
                state' = res.state
            }
        )
        .then(
            val key1: PoolId = { fee: 0, tick: 0, tokenPair: ("A", "B") }
            val depositMsg: DepositMsg = depositMsgPool(creator, key1, (10, 0), true)
            val res = deposit(state, depositMsg)
            all{
                // again behind enemy lines
                assert(not(res.error == "nil")),
                state' = res.state
            }
        )

    run behindPoolEnemyLine_run =
        val creator = DEFAULT_CREATOR
        init.then(
            val key1: PoolId = { fee: 5, tick: -100, tokenPair: ("A", "B") }
            val depositMsg: DepositMsg = depositMsgPool(creator, key1, (10, 10), true)
            val res = deposit(state, depositMsg)
            all{
                assert(res.error == "nil"),
                state' = res.state,
            }
        )
        .then(
            val key1: PoolId = { fee: 3, tick: -100, tokenPair: ("A", "B") }
            val depositMsg: DepositMsg = depositMsgPool(creator, key1, (10, 10), true)
            val res = deposit(state, depositMsg)
            all{
                assert(res.error == "nil"),
                state' = res.state,
            }
        )
        .then(
            val key1: PoolId = { fee: 5, tick: -80, tokenPair: ("A", "B") }
            val depositMsg: DepositMsg = depositMsgPool(creator, key1, (10, 10), true)
            val res = deposit(state, depositMsg)
            all {
                state' = res.state,
                assert(res.error == "Pool behind enemy lines"),
            }
        )

    run limitOrderTrade_run =
        init.then(
            val bobsOrder: PlaceLimitOrderMsg = {
                creator: "Bob",
                orderType: GoodTillCancelled,
                tokenIn: "A",
                tokenOut: "B",
                amountIn: 10,
                sellTick: 19460,
                maxAmountOut: -1
            }
            val updatedState = placeLimitOrder(state, bobsOrder).state
            all{
                state' = updatedState,
                val trancheKey = { id: 1, makerToken: "A", takerToken: "B", sellTick: 19460 }
                val updatedTranche = updatedState.tranches.get(trancheKey)
                all{
                    assert(updatedTranche.reservesMaker == 10),
                    assert(updatedTranche.reservesTaker == 0),
                    assert(updatedTranche.sellTick == 19460),
                    assert(updatedTranche.makerDenomination == "A")
                }
            }
        )
        // Run Alice's order to match the Bob's existing order
        .then(
            val alicesOrder: PlaceLimitOrderMsg = {
                creator: "Alice",
                orderType: GoodTillCancelled,
                tokenIn: "B",
                tokenOut: "A",
                amountIn: 20,
                sellTick: -20000,
                maxAmountOut: -1
            }
            val updatedState = placeLimitOrder(state, alicesOrder).state

            all{
                state' = updatedState,
                val trancheKey = { id: 1, makerToken: "A", takerToken: "B", sellTick: 19460 }
                val updatedTranche = updatedState.tranches.get(trancheKey)
                all{
                    assert(updatedTranche.reservesMaker == 8),
                    assert(updatedTranche.reservesTaker == 14),
                }
            }
        )
        // Run again Alice's order to completely fill Bob's order and create a new tranche
        .then(
            val alicesOrder: PlaceLimitOrderMsg = {
                creator: "Alice",
                orderType: GoodTillCancelled,
                tokenIn: "B",
                tokenOut: "A",
                amountIn: 20000,
                sellTick: -20000,
                maxAmountOut: -1
            }
            val updatedState = placeLimitOrder(state, alicesOrder).state
            all{
                state' = updatedState,
                val newTrancheKey = { id: 2, makerToken: "B", takerToken: "A", sellTick: -20000 }
                val newTranche = updatedState.tranches.get(newTrancheKey)
                all{
                    assert(newTranche.reservesMaker == 19950),
                    assert(newTranche.reservesTaker == 0),
                    assert(newTranche.makerDenomination == "B")
                }
            }
        )
    }
