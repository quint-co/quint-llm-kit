module runsUtils {
    import dec.* from "lib/dec"
    import types.* from "types"
    import consts.* from "consts"
    import utils.* from "utils"
    import basicSpells.* from "lib/basicSpells"
    import Dex.* from "dex"
    import dexEvolution.* from "dexEvolution"
    import baseDexEvolution as baseEvolution from "baseDexEvolution"
    import postconditions.* from "postconditions"

    pure val DEFAULT_CREATOR: Addr = "Alice"
    pure val DEFAULT_TOKEN_PAIR: TokenPair = ("A", "B")

    pure def depositMsgPool(creator: Addr, poolKey: PoolId, amountPair: (int, int), doAutoswap: bool): DepositMsg = {
        creator: creator,
        tokenPair: poolKey.tokenPair,
        amountPair: amountPair,
        token0SellTick: poolKey.tick,
        fee: poolKey.fee,
        autoswap: doAutoswap
    }

    pure def placeLimitMsg(creator: Addr, maker: Token, taker: Token, tick: TickIndex, amount: int): PlaceLimitOrderMsg = {
        creator: creator,
        tokenIn: maker,
        tokenOut: taker,
        amountIn: amount,
        sellTick: tick,
        orderType: GoodTillCancelled,
        maxAmountOut: 0
    }

    pure def sharesGained(before: State, after: State, creator: Addr, poolKey: PoolId): int = {
        val beforeShares = before.poolShares.getOrElse((creator, poolKey), 0)
        val afterShares = after.poolShares.getOrElse((creator, poolKey), 0)
        afterShares - beforeShares
    }

    pure def coinsGained(before: State, after: State, creator: Addr, token: Token): int = {
        val beforeBalance = before.coins.get((creator, token))
        val afterBalance = after.coins.get((creator, token))
        afterBalance - beforeBalance
    }

    pure def withdrawMsgPool(creator: Addr, poolKey: PoolId, sharesAmount: int): WithdrawPoolMsg =
        {
            creator: creator,
            tokenPair: poolKey.tokenPair,
            sharesAmount: sharesAmount,
            tick: poolKey.tick,
            fee: poolKey.fee
        }

    }
