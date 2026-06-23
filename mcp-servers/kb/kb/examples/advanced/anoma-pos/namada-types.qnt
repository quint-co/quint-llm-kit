/**
 *
 * Manuel Bravo, Informal Systems, 2023
 */

module types {

  import Dec.* from "./dec"

  // ****************************************************************************
  // Data Types
  // *************************************************************************
  // Represent addresses as strings
  type Address = str

  // Represent epochs as integers
  type Epoch = int

  // A map from source validator to a map of bonds: from bond starting epoch at the source validator to amount of tokens
  type RedelegatedBondsMap = Address -> Epoch -> int

  type Redelegation = {
    redBondStart: Epoch,
    srcValidator: Address,
    bondStart: Epoch,
    amount: int
  }

  type ModifiedRedelegation = {
    epoch: Epoch,
    valsToRemove: Set[Address],
    valToModify: Address,
    epochsToRemove: Set[Epoch],
    epochToModify: Epoch,
    newAmount: int
  }

  // Slash record
  type Slash = {
    // Misbehaving epoch
    epoch: Epoch,
    // slash rate
    rate: int
  }

  // Enqueued infraction record
  type Infraction = {
    // Unique identifier
    id: int,
    // Misbehaving epoch
    epoch: Epoch,
    // Misbehaving validator
    validator: Address,
  }

  // Delegator state
  type DelegatorState = {
    // Delegator's address
    address: Address,
    // User's current balance
    balance: int,
    // User's bonds: a map from validator to a map storing the tokens that the user has currently delegated to the validator
    // The latter maps bond starting epoch to amount of tokens
    bonded: Address -> Epoch -> int,
    // User's bonds that come from redelegations: a map from validator to a map storing the redelegated tokens that the user has currently
    //delegated to the validator. The latter maps bond starting epoch to a RedelegatedBondsMap (from source validator to a map of bonds from bond starting epoch at the source validator to amount of tokens)
    redelegatedBonded: Address -> Epoch -> RedelegatedBondsMap,
    // User's unbonds: a map from validator to a map storing the tokens that the user has unbonded (not yet withdrawn) from the validator
    // The latter maps the pair bond starting epoch and unbond ending epoch to amount of tokens
    unbonded: Address -> (Epoch, Epoch) -> int,
    // User's unbonds that come from redelegations: a map from validator to a map storing the redelegtated tokens that the user has unbonded (not yet withdrawn)/
    // The latter maps the pair bond starting epoch and unbond ending epoch to a RedelegatedBondsMap (from source validator to a map of bonds from bond starting epoch at the source validator to amount of tokens)
    redelegatedUnbonded: Address -> (Epoch, Epoch) -> RedelegatedBondsMap,
    // User's precomputed rewards coming from delegation that have not yet been claimed. If the user is a valiadtor, it also includes rewards coming from commissions.
    // It is a map from validator address to decimal.
    rewards: Address -> Dec,
    // The last epoch at which the user has claimed its rewards for each validator.
    lastClaim: Address -> Epoch,
    // User's rewards balance. The implementation should not need this state variable as rewards should be transferred to the delegator's balance.
    balanceRewards: Dec  
  }

  // Validator state
  type ValidatorState = {
    // Validator's address
    address: Address,
    // Epoched stake: a map from epoch to stake
    stake: Epoch -> int,
    // Ordered by epoch list of already processed slashes
    slashes: List[Slash],
    // Keeps tracks of the epoch until which a validator is frozen
    frozen: Epoch,
    // Each validator keeps track of the amount of tokens that have been unbonded at a given epoch.
    // totalUnbonded is a map from unbonding epoch to unbonded bonds
    // The unbonded bonds are tracked in a map from bond starting epoch to amount of tokens
    totalUnbonded: Epoch -> Epoch -> int,
    // Each validator keeps track of the amount of redelegated tokens that have been unbonded at a given epoch.
    // totalRedelegatedUnbonded is a map from unbonding epoch to unbonded redelegated bonds
    // The unbonded redelegated bonds are tracked in a map from bond starting epoch at the validator to RedelegatedBondsMap.
    // (from source validator to a map of bonds from bond starting epoch at the source validator to amount of tokens)
    totalRedelegatedUnbonded: Epoch -> Epoch -> RedelegatedBondsMap,
    // Each validator keeps track of the amount of tokens bonded at a given epoch
    // totalBonded is a map from bond starting epoch to amount of bonded tokens
    // It is used an the end of an epoch to compute how many tokens have been delegated
    // to a validator after a given infraction epoch.
    totalBonded: Epoch -> int,
    // Each validator keeps track of the amount of redelegated tokens bonded at a given epoch.
    // totalBonded is a map from bond starting epoch to RedelegatedBondsMap.
    // (from source validator to a map of bonds from bond starting epoch at the source validator to amount of tokens)
    // It is used an the end of an epoch to compute how many redelegated tokens have been delegated
    // to a validator after a given infraction epoch.
    totalRedelegatedBonded: Epoch -> RedelegatedBondsMap,
    // Each validator keeps track of incoming redelegations.
    // For each source validator, the validator keeps track the epoch at which the latest
    // redelegation ends: when the redelegated tokens start contributing to the validator.
    // This is used to prevent chain redelegations.
    incomingRedelegations: Address -> Epoch,
    // Each validator keeps track of outgoing redelegations.
    // For each destination validator, the validator keeps a map of redelegated tokens.
    // The map uses a pair of epochs as key: bond starting epoch at the validator, redelegation starting epoch (when the redelagation was issued).
    // This is used to slash destination validator when a slash for the validator is processed at the end of an epoch.
    outgoingRedelegations: Address -> (Epoch, Epoch) -> int,
    // Epoched commission rate.
    commission: Epoch -> Dec,
    // Computed rewards products indexed by epoch.
    rewardsProducts: Epoch -> Dec
  }

  // Proof-of-stake system state
  type PosState = {
    // A special PoS account that receives staked tokens
    posAccount: int,
    // The slash pool receives slashed tokens
    slashPool: int,
    // Current epoch
    epoch: Epoch,
    // Number of transactions executed in the current epoch
    counterTxs: int,
    // Number of infractions submitted at the current epoch
    counterInfractions: int,
    // A map from epoch to the set of slashes scheduled to be processed
    enqueuedSlashes: Epoch -> Set[Infraction],
  }

  // Result record returned by any of the three PoS functions: delegate, unbond and withdraw
  type ResultTx = {
    success: bool,
    delegator: DelegatorState,
    validator: ValidatorState,
    posState: PosState
  }

  // Result record returned by any of the unbond function
  type ResultUnbondTx = {
    result: ResultTx,
    resultSlashing: {sum: int, epochMap: Epoch -> int}
  }

  // Result record returned by the redelegation PoS function
  type ResultRedelegationTx = {
    success: bool,
    delegator: DelegatorState,
    srcValidator: ValidatorState,
    destValidator: ValidatorState,
    posState: PosState
  }

  // ****************************************************************************
  // Specification Parameters
  // *************************************************************************

  // Max uint
  pure val MAX_UINT: int = 10

  // Users initial balances
  pure val INIT_BALANCE: int = 20

  // Set of all user addresses
  pure val USERS: Set[str] = Set("alice", "bob")

  // Set of all validator addresses
  pure val VALIDATORS: Set[str] = Set("alice", "bob")

  // A map from validator address to integer. Used to iterate deterministically over validator addresses
  pure val VALIDATORS_RANK: Address -> int = Map("alice" -> 1, "bob" -> 2)

  // Transactions per epoch
  // the spec is not fully ready to handle multiple txs per epoch
  // we would need to handle duplicate bonds and unbonds
  pure val TXS_EPOCH: int = 1

  // Unbonding offset
  pure val UNBONDING_OFFSET: int = 4

  // Pipeline offset
  pure val PIPELINE_OFFSET: int = 2

  // Cubic offset
  pure val CUBIC_OFFSET: int = 1

  // Slash rate duplicate vote
  pure val DUPLICATE_RATE: Dec = (1, 5)

  // Slash rate light client attack
  pure val LIGHT_RATE: Dec = (1, 5)

}