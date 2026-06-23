/* ****************************************************************************
  This encodes the proof-of-stake system of Namada.

  Manuel Bravo, Informal Systems, 2023
**************************************************************************** */

module namada {

  import basicSpells.* from "./basicSpells"
  import extraSpells.* from "./extraSpells"
  import Dec.* from "./dec"

    /* ****************************************************************************
    * Data Types
    * ************************************************************************* */

    // Represent addresses as strings
    type Address = str

    // Represent epochs as integers
    type Epoch = int

    // Slash record
    type Slash = {
      // Misbehaving epoch
      epoch: epoch,
      // Misbehaving validator
      validator: Address,
      // slash rate
      rate: int
    }

    // Enqueued infraction record
    type Infraction = {
      // Unique identifier
      id: int,
      // Misbehaving epoch
      epoch: epoch,
      // Misbehaving validator
      validator: Address,
    }

    // Delegator state
    type DelegatorState = {
      // User's current balance
      balance: int,
      // User's bonds: a map from validator to a map storing the tokens that the user has currently delegated to the validator
      // The latter maps bond starting epoch to amount of tokens
      bonded: Address -> Epoch -> int,
      // User's unbonds: a map from validator to a map storing the tokens that the user has unbonded (not yet withdrawn) from the validator
      // The latter maps the pair bond starting epoch and unbond ending epoch to amount of tokens
      unbonded: Address -> (Epoch, Epoch) -> int
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
      // Each validator keeps track of unbonded tokens per epoch
      // totalUnbonded is a map from unbonding epoch to unbonded bonds
      // The unbonded bonds are tracked in a map from bond starting epoch to amount of tokens
      totalUnbonded: Epoch -> Epoch -> int,
      // Each validatro keeps track of bonded tokens per epoch
      // totalBonded is a map from bond starting epoch to amount of bonded tokens
      // It is used an the en of en epoch to compute how many tokens have been delegated
      // to a validator after a given infraction epoch
      totalBonded: Epoch -> int
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
      delegatorState: DelegatorState,
      validatorState: ValidatorState,
      posState: PosState
    }

    /* ****************************************************************************
    * Specification Parameters
    * ************************************************************************* */

    // Max uint
    pure val MAX_UINT: int = 10

    // Users initial balances
    pure val INIT_BALANCE: int = 20

    // Set of all user addresses
    pure val USERS: Set[str] = Set("alice", "bob")

    // Set of all validator addresses
    pure val VALIDATORS: Set[str] = Set("alice")

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

    /* ****************************************************************************
    * State machine state
    * ************************************************************************* */

    // Delegator state
    var delegators: Address -> DelegatorState
    // Validator state
    var validators: Address -> ValidatorState
    // Proof-of-stake state
    var pos: PosState

    /* ****************************************************************************
    * Execution state
    * ************************************************************************* */


    // Used to limit the misbehaving of a validator:
    // 0: no limit
    // 1: limited but it allows multiple infractions with the same stake
    // 2: disallow multiple infractions with the same stake
    pure val limitEvidence = 0

    // Used to guarantee every step produces a state transition
    // IMPORTANT: Set to false for tests
    pure val enforceStateTransition = false

    // Last transaction executed by step.
    // Amount is over used by the actions:
    // It respresents the amount delegated or unbonded for delegate and unbond respectively; 
    // It is always 0 for withdraw and actionFauxTransaction;
    // It is the misbehaving epoch in Processevidence;
    var lastTx: {tag: str, result: bool, user: Address, validator: Address, amount: int}

    // Keeps tracks of when a validator may misbehave again in the case when limitEvidence == 1
    var nextInfractionEpoch: Address -> int

    /**************************************************************************
    * Main functions
    * ************************************************************************* */


    // The function addBond adds a bond to a map of bonds. If there is an existing bond with the same 
    // starting epoch, then the function simply adds the amount of toekns of the bond to add to tyhe existing entry
    // - @param bonds a map of bonds
    // - @param start the starting epoch of the bond to add 
    // - @param amount the amount of tokens of the bond to add
    // - @returns a map of bonds accounting for the new bond
    pure def addBond(bonds: Epoch -> int, start: Epoch, amount: int): Epoch -> int = {
      if (bonds.has(start)) bonds.set(start, bonds.get(start) + amount)
      else bonds.mapSafeSet(start, amount)
    }

    // The function delegate is called when a user wants to delegate tokens to a validator.
    // 1. It first checks that the user has enough tokens in its account.
    // 2. Then it locks those tokens by transferring them from the user's account to the PoS special account.
    // 3. It records that the user has delegated amount tokens to the validator.
    // 4. It increases the validator's stake at the PIPELINE_OFFSET and updates the totalBonded variable.
    pure def delegate(delegatorState: DelegatorState, validatorState: ValidatorState, posState: PosState, amount: int): ResultTx = {
      if (amount <= delegatorState.balance and amount > 0) {
        val updatedDelegatorState = delegatorState.with("balance", delegatorState.balance - amount)
                                                  .with("bonded", delegatorState.bonded.set(validatorState.address,
                                                                                            delegatorState.bonded.get(validatorState.address).addBond(posState.epoch + PIPELINE_OFFSET, amount)))                                                                       
        val updatedValidatorState = validatorState.with("stake", validatorState.stake.set(posState.epoch + PIPELINE_OFFSET,
                                                                                          validatorState.stake.get(posState.epoch + PIPELINE_OFFSET) + amount))
                                                  .with("totalBonded", validatorState.totalBonded.set(posState.epoch + PIPELINE_OFFSET,
                                                                                                      validatorState.totalBonded.get(posState.epoch + PIPELINE_OFFSET) + amount))      
        val updatedPosState = posState.with("posAccount", posState.posAccount + amount)
        {success: true, delegatorState: updatedDelegatorState, validatorState: updatedValidatorState, posState: updatedPosState}
      } else {
        {success: false, delegatorState: delegatorState, validatorState: validatorState, posState: posState}
      }
    }

    // The function unbonds a bond record contraint to a maximum amount (acc.remainder).
    // - @param acc a record with three fields:
    //   - remainder: the maximum amount of tokens to be unbonded.
    //   - toRemove: a set of bond records which includes the set of bond records that have been unbonded so far.
    //   - new: a bond record with start epoch equal to -1.
    // - @param bond the bond record to be unbonded by the function.
    // - @returns an update acc record: subtracts the minimum between bond.amount and acc.remainder from acc.remainder; adds the bond to acc.toRemove;
    // and if bond.amount if gretaer than acc.remainder (meaning that the bond is only partially unbonded), creates a new bond record in acc.new
    // of bond.amount - acc.remainder tokens.
    pure def unbondBond(acc: {remainder: int, toRemove: Set[Epoch], new: {start: int, amount: int}}, bond: {start: int, amount: int}): {remainder: int, toRemove: Set[Epoch], new: {start: int, amount: int}} = 
      val amountUnbonded = min(bond.amount, acc.remainder)
      {remainder: acc.remainder - amountUnbonded,
       toRemove: acc.toRemove.setAdd(bond.start),
       new: if (bond.amount > acc.remainder) {start: bond.start, amount: bond.amount - acc.remainder} else acc.new}

    // It iterates over a map of bonds in decreasing starting epoch order until a given amount of tokens is unbonded. For each iterated bond,
    // the function calls unbondBond while there are still tokens to be unbonded.
    // - @param bonds a map of bonds that can be unbonded.
    // - @param amount the amount of tokens that have to be unbonded.
    // - @returns a record with two fields: toRemove the set of bonds starting epochs of the bonds that have been unbonded and a new bond 
    //   that either contains a bond record (starting epoch and amount) if a bond has been partially unbonded or a bond record with start epoch equal to -1
    //   otherwise.
    pure def iterateBondsUpToAmount(bonds: Epoch -> int, amount: int): {toRemove: Set[Epoch], new: {start: int, amount: int}} = {
      val setEpochs = sortSetDecreasing(bonds.keys())
      val result = setEpochs.foldl({remainder: amount, toRemove: Set(), new: {start: -1, amount: 0}},
                                   (acc, e) => if (acc.remainder == 0) acc else unbondBond(acc, {start: e, amount: bonds.get(e)}))
      {toRemove: result.toRemove, new: result.new}
    }

    // Computes how much remains from an amount of tokens after applying a slash given that a set of slashes may have been
    // previously applied.
    // - @param slash the slash record to be applied.
    // - @param initAmount the tokens to be slashed.
    // - @param computeSlashes a map from misbehaving epoch to already applied.
    // - @returns an integer with the amount that remains after applying slash constraint to computeSlashes.
    pure def computeSlashableAmount(slash: Slash, initAmount: int, computedSlashes: Epoch -> int): int = {
      val updatedAmount = computedSlashes.keys().filter(x => x + UNBONDING_OFFSET + CUBIC_OFFSET < slash.epoch)
                                                .fold(initAmount, (acc, e) => max(0, acc - computedSlashes.get(e)))
      updatedAmount*slash.rate
    }

    // Computes how much remains from an amount of tokens after applying a list of slashes.
    // - @param listSlashes a list of slashes ordered by misbehaving epoch.
    // - @param amount the tokens to be slashed.
    // - @returns an integer with the amount that remains after applying the list of slashes.
    pure def applyListSlashes(listSlashes: List[Slash], amount: int): int = {

      listSlashes.foldl({finalAmount: amount, computedSlashes: Map()}, (acc, slash) => val slashAmount = computeSlashableAmount(slash, amount, acc.computedSlashes)
                                                                                       {finalAmount: max(0, acc.finalAmount - slashAmount),
                                                                                        computedSlashes: acc.computedSlashes.mapSafeSet(slash.epoch, slashAmount)}).finalAmount
    }

    // The function unbond is called when a user wants to unbond tokens from a validator.
    // 1. It first checks that the user has enough tokens bonded to the validator and that the validator is not frozen.
    // 2. Then it uses iterateBondsUpToAmount to compute the set of bonds that must be unbonded.
    // 3. It computes the set of unbond records to be added to the delegators unbonded variable.
    // 4. It updates the delegator state by removing the unbonded bonds and adding the newly computed unbonds.
    // 5. It applies any slashes to the unbonded bonds and stroes it in amountAfterSlashing.
    // 6. It updates the validator's totalUnbonded.
    // 7. It finally updates the validator's stale at the PIPELINE_OFFSET by subtracting amountAfterSlashing.

    pure def unbond(delegatorState: DelegatorState, validatorState: ValidatorState, posState: PosState, amount: int): ResultTx = {
      val bonds = delegatorState.bonded.get(validatorState.address)
      val totalBonded = bonds.keys().fold(0, (sum, e) => sum + bonds.get(e))      
      if (amount > 0 and amount <= totalBonded and validatorState.frozen < posState.epoch) {
        // Compute the epoch at which the unbonded bonds will be withdrawable
        val endEpoch = posState.epoch + PIPELINE_OFFSET + CUBIC_OFFSET + UNBONDING_OFFSET
        // Compute the set of bonds to be unbonded
        val resultUnbonding = iterateBondsUpToAmount(bonds, amount)
        // Compute the updated delegators bonded variable by removing the unbonded bonds and adding a new bond in case one was partially unbonded                                                     
        val updatedBonded = if (resultUnbonding.new.start == -1) bonds.mapRemoveSet(resultUnbonding.toRemove)
                            else bonds.mapRemoveSet(resultUnbonding.toRemove).mapSafeSet(resultUnbonding.new.start, resultUnbonding.new.amount)
        // Compute the set of unbond records that have to be recorded out of the set of unbonded bonds computed at the previous step
        val newUnbonds = tuples(resultUnbonding.toRemove, Set(endEpoch)).mapBy(unbondKey => val start = unbondKey._1
                                                                                            if (start == resultUnbonding.new.start) bonds.get(start) - resultUnbonding.new.amount
                                                                                            else bonds.get(start))
        // Compute the updated delegators unbonded variable by adding the new unbonds                                                                                                                                 
        val updatedUnbonded = delegatorState.unbonded.get(validatorState.address).mapAddSet(newUnbonds)
        // Compute the updated delegator's state
        val updatedDelegatorState = delegatorState.with("bonded", delegatorState.bonded.set(validatorState.address, updatedBonded))
                                                  .with("unbonded", delegatorState.unbonded.set(validatorState.address, updatedUnbonded))                                  
        // Compute how much out of amount has not been already removed from the validator's stake when slashing validators
        // at the end of previous epochs by leveraging applyListSlashes
        val amountAfterSlashing = newUnbonds.keys().fold(0, (sum, unbondKey) => val start = unbondKey._1
                                                                                val listSlashes = validatorState.slashes.select(slash => start <= slash.epoch)
                                                                                sum + applyListSlashes(listSlashes, newUnbonds.get(unbondKey)))
        // Compute the updated validator's totalUnbonded variable
        val updatedTotalUnbonded = newUnbonds.keys().fold(validatorState.totalUnbonded.get(posState.epoch + PIPELINE_OFFSET),
                                                          (acc, unbondKey) => val start = unbondKey._1
                                                                              acc.mapSafeSet(start, acc.getOrElse(start, 0) + newUnbonds.get(unbondKey)))
        // Compute the updated validator's state by updating its state and totalUnbonded.
        val updatedValidatorState = validatorState.with("stake", validatorState.stake.set(posState.epoch + PIPELINE_OFFSET,
                                                                                          validatorState.stake.get(posState.epoch + PIPELINE_OFFSET) - amountAfterSlashing))
                                                  .with("totalUnbonded", validatorState.totalUnbonded.set(posState.epoch + PIPELINE_OFFSET, updatedTotalUnbonded))
        {success: true, delegatorState: updatedDelegatorState, validatorState: updatedValidatorState, posState: posState}
      } else {
        {success: false, delegatorState: delegatorState, validatorState: validatorState, posState: posState}
      }
    }

    // The function withdraw is called when a user wants to withdraw tokens from a validator.
    // 1. First it computes whether there are tokens ready to be withdrawn and returns an error in case there are none.
    // 2. Then records that those tokens are withdrawn by removing the withdrawable unbond records from unbonded.
    // 3. Finally, it unlocks the tokens by transferring them from the PoS special account to the user's account, after slashing them.
    pure def withdraw(delegatorState: DelegatorState, validatorState: ValidatorState, posState: PosState): ResultTx = {
      val unbonds = delegatorState.unbonded.get(validatorState.address)
      // Filter the the set of unbonds that can be withdrawn
      val setWithdrawn = unbonds.keys().filter(unbondKey => val end = unbondKey._2
                                                            end <= posState.epoch)
      if (size(setWithdrawn) > 0) {
        // Compute how much out of amount is withdrawn after slashing by leveraging applyListSlashes
        val amountAfterSlashing = setWithdrawn.fold(0, (sum, unbondKey) => val start = unbondKey._1
                                                                           val end = unbondKey._2
                                                                           val listSlashes = validatorState.slashes.select(slash => start <= slash.epoch and
                                                                                                                                    end  - UNBONDING_OFFSET - CUBIC_OFFSET > slash.epoch)
                                                                           sum + applyListSlashes(listSlashes, unbonds.get(unbondKey)))
        // Remove the sent of withdrawn unbonds from the set of unbonds
        // Transfer withdrawn tokens from the PoS account to the user's account
        val updatedDelegatorState = delegatorState.with("unbonded", delegatorState.unbonded.set(validatorState.address, unbonds.mapRemoveSet(setWithdrawn)))
                                                  .with("balance", delegatorState.balance + amountAfterSlashing)
        val updatedPosState = posState.with("posAccount", posState.posAccount - amountAfterSlashing)
        {success: true, delegatorState: updatedDelegatorState, validatorState: validatorState, posState: updatedPosState}
      } else {
        {success: false, delegatorState: delegatorState, validatorState: validatorState, posState: posState}
      }
    }

    // Computes the total amount of tokens unbonded by a validator that were contributing to the validator's stake when this misbehaved at
    // a previous epoch, after applying a set of slashes that were potentially processed before the misbehaving epoch.
    // - @param slash the slash record.
    // - @param prevSlashes a list of slash records ordered by misbehaving epoch that were protentially processed before slash.epoch.
    // - @param totalUnbonded a map from epoch to integer.
    // - @returns an integer with the amount of tokens unbonded.
    pure def computeTotalUnbonded(infractionEpoch: Epoch, prevSlashes: List[Slash], totalUnbonded: Epoch -> int): int = {
      val epochs = totalUnbonded.keys().filter(e => e <= infractionEpoch and totalUnbonded.get(e) > 0)
      epochs.fold(0, (sum, e) => sum + applyListSlashes(prevSlashes.select(s => e <= s.epoch and s.epoch + UNBONDING_OFFSET + CUBIC_OFFSET < infractionEpoch),
                                                        totalUnbonded.get(e)))
    }

    // Computes the total amount of tokens unbonded by a validator that were contributing to the validator's that were bonded
    // to the validator after this misbehaved at a given epoch
    // - @param infractionEpoch the misbehaving epoch.
    // - @param totalUnbonded the set of unbonded tokens in a map from bond starting epoch to amount of tokens.
    // - @returns an integer with the amount of tokens unbonded.
    pure def computeRecentTotalUnbonded(infractionEpoch: Epoch, totalUnbonded: Epoch -> int): int = {
      val epochs = totalUnbonded.keys().filter(e => e > infractionEpoch and totalUnbonded.get(e) > 0)
      epochs.fold(0, (sum, e) => sum + totalUnbonded.get(e))
    }

    // Computes for a given validator and a slash how it much should be slashed at all epochs between the current epoch (curEpoch) + 1 and the current epoch + 1 + 
    // PIPELINE_OFFSET, accounting for any tokens already unbonded.
    pure def slashValidator(initMap: Epoch -> int,
                            stakes: Epoch -> int,
                            curEpoch: Epoch,
                            infractionStake: int,
                            prevSlashes: List[Slash],
                            totalUnbonded: Epoch -> Epoch -> int,
                            totalBonded: Epoch -> int,
                            finalRate: int): Epoch -> int = {
      val infractionEpoch = curEpoch - CUBIC_OFFSET - UNBONDING_OFFSET
      val initTotalUnbonded = (infractionEpoch+1).to(curEpoch).fold(0, (sum, e) => sum + computeTotalUnbonded(infractionEpoch, prevSlashes, totalUnbonded.get(e)))
      val initBalanceBonds = (infractionEpoch+1).to(curEpoch).fold(0, (sum, e) => sum +(totalBonded.get(e) - computeRecentTotalUnbonded(infractionEpoch, totalUnbonded.get(e))))
      val result = (curEpoch+1).to(curEpoch+PIPELINE_OFFSET).fold((initTotalUnbonded, initBalanceBonds, initMap), (acc, e) => val updatedTotalUnbonded = acc._1 + computeTotalUnbonded(infractionEpoch, prevSlashes, totalUnbonded.get(e))
                                                                                                                             val updatedBalanceBonds = acc._2 + (totalBonded.get(e) - computeRecentTotalUnbonded(infractionEpoch, totalUnbonded.get(e)))
                                                                                                                             val slashedAmount = (infractionStake - updatedTotalUnbonded) * finalRate
                                                                                                                             val slashableStake = (stakes.get(e) - updatedBalanceBonds)
                                                                                                                             (updatedTotalUnbonded, updatedBalanceBonds, acc._3.set(e, min(slashedAmount, slashableStake))))
      result._3
    }

    // Returns the slahs rate depending of the type of infraction
    pure def minSlashRate(infraction: str): Dec = {
      if (infraction == "duplicate_vote") DUPLICATE_RATE else LIGHT_RATE
    }

    // Computes a slash rate based on a set of slashes
    // - @param setSlashes a set of slashes
    // - @returns an integer represting the slash rate
    pure def computeFinalRate(setInfractions: Set[Infraction]): int = {
      1
    } 

    // This function is executed at the end of an epoch.
    // 1. It first computes the final rate for all slashes scheduled to be processed at the end of the current epoch.
    // 2. It computes for each validator how much it should be slashed based of the slashes scheduled to be processed. It already computes 
    // how much should be substracted from each validator's stake variable at every epoch between the current epoch and the current epoch + PIPELINE_OFFSET.
    // 3. It updates the validators' state by (i) shifting the epoched stake variable and applying any precomputed slash; (ii) shifting totalUnbonded;
    // and (iii) appending newly created slash records.
    // 4. It computes how much has been slashed in total and stores it in totalAmountSlashed.
    // 5. It update PoS state by increasing the epoch, setting counterTxs to zero, transferring totalAmountSlashed from the PoS accoun tot the slash pool
    // and shifting equeued slashes.
    pure def endOfEpoch(validatorsState: Address -> ValidatorState, posState: PosState, curEpoch: Epoch): {validatorsState: Address -> ValidatorState, posState: PosState} = {
      val finalRate = computeFinalRate((curEpoch-CUBIC_OFFSET).to(curEpoch+CUBIC_OFFSET).fold(Set(), (acc, e) => acc.union(posState.enqueuedSlashes.get(e))))
      val initMap = VALIDATORS.mapBy(v => (curEpoch+1).to(curEpoch+PIPELINE_OFFSET).mapBy(e => 0))
      val infractionEpoch = posState.epoch - CUBIC_OFFSET - UNBONDING_OFFSET
      val slashPerValidator = posState.enqueuedSlashes.get(curEpoch).fold(Map(), (acc, slash) => acc.mapSafeSet(slash.validator, min(1, acc.getOrElse(slash.validator, 0) + finalRate)))
      val mapValidatorSlash = slashPerValidator.keys().fold(initMap, (acc, validator) => acc.set(validator, slashValidator(acc.get(validator),
                                                                                                 (curEpoch+1).to(curEpoch+PIPELINE_OFFSET).mapBy(e => validatorsState.get(validator).stake.get(e)),
                                                                                                 curEpoch,
                                                                                                 validatorsState.get(validator).stake.get(infractionEpoch),
                                                                                                 validatorsState.get(validator).slashes,
                                                                                                 validatorsState.get(validator).totalUnbonded,
                                                                                                 validatorsState.get(validator).totalBonded,                                               
                                                                                                 slashPerValidator.get(validator))))
      val updatedValidators = VALIDATORS.mapBy(v => validatorsState.get(v).with("stake",(curEpoch-UNBONDING_OFFSET-CUBIC_OFFSET+1).to(curEpoch+1+PIPELINE_OFFSET).mapBy(e => if (e < curEpoch+1+PIPELINE_OFFSET) validatorsState.get(v).stake.get(e) -
                                                                                                                                                                              if (e >= curEpoch+1) mapValidatorSlash.get(v).get(e) else 0
                                                                                                                                                                             else validatorsState.get(v).stake.get(e-1) - mapValidatorSlash.get(v).get(e-1))) 
                                                                          .with("totalUnbonded", (curEpoch-CUBIC_OFFSET-UNBONDING_OFFSET+1).to(curEpoch+1+PIPELINE_OFFSET).mapBy(e => if (e < curEpoch+1+PIPELINE_OFFSET) validatorsState.get(v).totalUnbonded.get(e)
                                                                                                                                                                                      else Map()))  
                                                                          .with("totalBonded", (curEpoch-CUBIC_OFFSET-UNBONDING_OFFSET+1).to(curEpoch+1+PIPELINE_OFFSET).mapBy(e => if (e < curEpoch+1+PIPELINE_OFFSET) validatorsState.get(v).totalBonded.get(e)
                                                                                                                                                                                    else 0))                                                                                                                                                                                  
                                                                          .with("slashes", if (slashPerValidator.has(v)) validatorsState.get(v).slashes.append({epoch: infractionEpoch, validator: v, rate: slashPerValidator.get(v)})
                                                                                           else validatorsState.get(v).slashes))
      //val totalAmountSlashed = slashPerValidator.keys().fold(0, (sum, validator) => sum + validatorsState.get(validator).stake.get(infractionEpoch)*slashPerValidator.get(validator))
      val updatedPos =  posState.with("epoch", curEpoch + 1)
                                .with("counterTxs", 0)
                                .with("counterInfractions", 0)
                                //.with("posAccount", posState.posAccount - totalAmountSlashed)
                                //.with("slashPool", posState.slashPool + totalAmountSlashed)
                                .with("enqueuedSlashes", (curEpoch-CUBIC_OFFSET+1).to(curEpoch+1+CUBIC_OFFSET+UNBONDING_OFFSET).mapBy(e => if (e < curEpoch+1+CUBIC_OFFSET+UNBONDING_OFFSET) posState.enqueuedSlashes.get(e)
                                                                                                                                           else Set()))                                                                      
      {validatorsState: updatedValidators, posState: updatedPos}                                                                                                                             
    }

    // The function proccessEvidence is called when a validator misbehaves.
    // 1. It first creates a slash record.
    // 2. Then it updates the validator's state by freezing the validator.
    // 3. It finally enqueues the slash and schedules it to be proccessed at the end of the epoch resulting from adding UNBONDING_OFFSET
    // to the misbehaving epoch. 
    pure def proccessEvidence(e: Epoch, validatorState: ValidatorState, posState: PosState): {validatorState: ValidatorState, posState: PosState} = {
      val id = posState.counterInfractions + 1
      val infraction = {id: id, epoch: e, validator: validatorState.address}
      {validatorState: validatorState.with("frozen", max(validatorState.frozen, e + CUBIC_OFFSET + UNBONDING_OFFSET)),
       posState: posState.with("enqueuedSlashes", posState.enqueuedSlashes.set(e + CUBIC_OFFSET + UNBONDING_OFFSET, posState.enqueuedSlashes.get(e + CUBIC_OFFSET + UNBONDING_OFFSET).union(Set(infraction))))
                         .with("counterInfractions", id)}
    }


    /* ****************************************************************************
    * Actions
    * ************************************************************************* */

    // The action commonTxAfter is called after a transaction is executed.
    // 1. It first checks if it is the last transaction of the current epoch.
    // 2. If it is the last transaction of the epoch, it calls the endOfEpoch function.
    // 3. Otherwise, it updates the variables using the result of the transaciton and increases counterTxs.
    action commonTxAfter(user: Address, validator: Address, result: ResultTx): bool = all {
      if (pos.counterTxs + 1 == TXS_EPOCH) {
        val resultEndOfEpoch = endOfEpoch(validators.set(validator, result.validatorState), result.posState, pos.epoch)
        all {
          delegators' = delegators.set(user, result.delegatorState),
          validators' = resultEndOfEpoch.validatorsState,
          pos' = resultEndOfEpoch.posState,
          nextInfractionEpoch' = nextInfractionEpoch
        }
      } else {
        all {
          delegators' = delegators.set(user, result.delegatorState),
          validators' = validators.set(validator, result.validatorState),
          pos' = result.posState.with("counterTxs", result.posState.counterTxs + 1),
          nextInfractionEpoch' = nextInfractionEpoch
        }
      }
    }

    action actionDelegate(user: Address, validator: Address, amount: int): bool = all {
      val result = delegate(delegators.get(user), validators.get(validator), pos, amount)
      all {
        if (enforceStateTransition) require(result.success) else true,
        commonTxAfter(user, validator, result),
        lastTx' = {tag: "Delegate", result: result.success, user: user, validator: validator, amount: amount}
      }
    }

    action actionUnbond(user: Address, validator: Address, amount: int): bool = all {
      val result = unbond(delegators.get(user), validators.get(validator), pos, amount)
      all {
        if (enforceStateTransition) require(result.success) else true,
        commonTxAfter(user, validator, result),
        lastTx' = {tag: "Unbond", result: result.success, user: user, validator: validator, amount: amount}
      }
    }

    action actionWithdraw(user: Address, validator: Address): bool = all {
      val result = withdraw(delegators.get(user), validators.get(validator), pos)
      all {
        if (enforceStateTransition) require(result.success) else true,
        commonTxAfter(user, validator, result),
        lastTx' = {tag: "Withdraw", result: result.success, user: user, validator: validator, amount: 0}
      }
    }

    action actionEvidence(e: Epoch, validator: Address): bool = all {
      require(limitEvidence == 1 implies nextInfractionEpoch.get(validator) < e),
      require(limitEvidence == 2 implies validators.get(validator).frozen < e),
      val result = proccessEvidence(e, validators.get(validator), pos)
      all {
        validators' = validators.set(validator, result.validatorState),
        pos' = result.posState,
        delegators' = delegators,
        lastTx' = {tag: "Evidence", result: true, user: "", validator: validator, amount: e},
        nextInfractionEpoch' = nextInfractionEpoch.set(validator, e + UNBONDING_OFFSET)
      }
    }

    action actionFauxTransaction(user: Address, validator: Address, amountDelegate: int, amountUnbond: int, e: Epoch): bool = all {
      require(limitEvidence == 1 implies nextInfractionEpoch.get(validator) >= e),
      require(limitEvidence == 2 implies validators.get(validator).frozen >= e),
      require(amountUnbond == 0 or validators.get(validator).frozen >= pos.epoch),
      require(amountDelegate == 0),
      val result = {success: true, delegatorState: delegators.get(user), validatorState: validators.get(validator), posState: pos}
      all {
        commonTxAfter(user, validator, result),
        lastTx' = {tag: "Advance", result: result.success, user: user, validator: validator, amount: 0}
      }
    }

    /* ****************************************************************************
    * Invariants
    * ************************************************************************* */

    // Invariant 1: A delegator's balance cannot become negative.
    val balanceGreaterZero = USERS.forall(user => delegators.get(user).balance >= 0)

    // Invariant 2: The PoS account cannot become negative.
    val posAccountGreaterZero = pos.posAccount >= 0

    // Invariant 3: If there are no bonds and all unbonds have been withdrawn, the PoS balance must be equal to zero.
    val posAccountZero = USERS.forall(user => VALIDATORS.forall(validator => delegators.get(user).bonded.get(validator) == Map() and
                                                                             delegators.get(user).unbonded.get(validator) == Map())) implies pos.posAccount == 0

    // Invariant 4: The validator's voting power at a given epoch is less or equal to the total amount of tokens delegated to that validator.
    // This is not an equality due to slashing. Next invariant checks the equality restricted to no slashing.
    val stakeEqualOrLessSumBonds = VALIDATORS.forall(validator => USERS.fold(0, (sum, user) => val bonds = delegators.get(user).bonded.get(validator)
                                                                                               sum + bonds.keys().fold(0, (total, start) => total + bonds.get(start))) >= validators.get(validator).stake.get(pos.epoch + PIPELINE_OFFSET))

    // Invariant 5: If no slashing occurs, the validator's voting power at a given epoch is equal to the total amount of tokens delegated to that validator.
    val noSlashingStakeEqualSumBonds = pos.slashPool == 0 implies VALIDATORS.forall(validator => USERS.fold(0, (sum, user) => val bonds = delegators.get(user).bonded.get(validator)
                                                                                                                              sum + bonds.keys().fold(0, (total, start) => total + bonds.get(start))) == validators.get(validator).stake.get(pos.epoch + PIPELINE_OFFSET))

    // Invariant 6: The total amount of tokens is constant.
    val totalAmountTokensConstant = USERS.fold(0, (sum, user) => sum + delegators.get(user).balance) + pos.posAccount + pos.slashPool== size(USERS)*INIT_BALANCE

    // Invariant 7: A validator's stake cannot become negative.
    val stakeGreaterZero = VALIDATORS.forall(validator =>
                                             pos.epoch.to(pos.epoch + PIPELINE_OFFSET).forall(e => validators.get(validator).stake.get(e) >= 0))

    //Invariant 8: The user's balance cannot become greater than the initial balance
    val boundedBalance = USERS.forall(user => delegators.get(user).balance <= INIT_BALANCE)

    // All invariants
    val allInvariants = balanceGreaterZero and
                        posAccountGreaterZero and
                        posAccountZero and
                        stakeEqualOrLessSumBonds and
                        noSlashingStakeEqualSumBonds and
                        totalAmountTokensConstant and
                        stakeGreaterZero and
                        boundedBalance
                  
    // All invariants without slash pool
    val allInvariantsWithNoSlashPool = balanceGreaterZero and
                                       posAccountGreaterZero and
                                       //posAccountZero and
                                       stakeEqualOrLessSumBonds and
                                       //noSlashingStakeEqualSumBonds and
                                       totalAmountTokensConstant and
                                       stakeGreaterZero and
                                       boundedBalance
    
    /* ****************************************************************************
    * Execution
    * ************************************************************************* */

    action allUnchanged: bool = all {
      delegators' = delegators,
      validators' = validators,
      pos' = pos,
      lastTx' = lastTx,
      nextInfractionEpoch' = nextInfractionEpoch
    }

    // State initialization: assumes that users start with some initial balance.
    action init: bool = all {
      val initEpoch = UNBONDING_OFFSET + CUBIC_OFFSET
      all {
        delegators' = USERS.mapBy(user => {balance: INIT_BALANCE,
                                          bonded: VALIDATORS.mapBy(x => Map()),
                                          unbonded: VALIDATORS.mapBy(x => Map())}),
        validators' = VALIDATORS.mapBy(validator => {address: validator,
                                                     stake: 0.to(initEpoch+PIPELINE_OFFSET).mapBy(e => 0),
                                                     totalUnbonded: 0.to(initEpoch+PIPELINE_OFFSET).mapBy(e => Map()),
                                                     totalBonded: 0.to(initEpoch+PIPELINE_OFFSET).mapBy(e => 0),
                                                     slashes: List(),
                                                     frozen: 0}),
        pos' = {posAccount: 0,
                slashPool: 0,
                epoch: initEpoch,
                counterTxs: 0,
                counterInfractions: 0,
                enqueuedSlashes: (initEpoch-CUBIC_OFFSET).to(initEpoch+CUBIC_OFFSET+UNBONDING_OFFSET).mapBy(e => Set())},
        lastTx' = { tag: "Init", result: true, user: "", validator: "", amount: 0},
        nextInfractionEpoch' = VALIDATORS.mapBy(validator => 0)
      }
    }

    /*
    * Execution of the state machine.
    * 1. Pick a random amount from 0 to MAX_UINT, a user, a validator, and an epoch between
    *    the current epoch and the current epoch - UNBONDING_OFFSET
    * 2. Execute one of the actions: delegate, unbond, withdraw or evidence.
    * 3. In case none of the above actions are executable, it executes the actionFauxTransaction action.
    * 4. The above logic is implemented by the precondition in actionFauxTransaction.
    */
    action step: bool = {
        nondet user = USERS.oneOf()
        nondet validator = VALIDATORS.oneOf()
        //nondet amount = 0.to(MAX_UINT).oneOf()
        nondet amountDelegate = 0.to(delegators.get(user).balance).oneOf()
        nondet amountUnbond = 0.to(delegators.get(user).bonded.get(validator).keys().fold(0, (sum, e) => sum + delegators.get(user).bonded.get(validator).get(e))).oneOf()
        nondet e = (pos.epoch - UNBONDING_OFFSET).to(pos.epoch).oneOf()
        // Execute one of the available actions/methods
        any {
            actionDelegate(user, validator, amountDelegate),
            actionUnbond(user, validator, amountUnbond),
            actionWithdraw(user, validator),
            actionEvidence(e, validator),
            //allUnchanged
            actionFauxTransaction(user, validator, amountDelegate, amountUnbond, e)
        }
    }

    /* ****************************************************************************
    * Tests
    * ************************************************************************* */

    //The test applyListSlashesTest is a unitest-like test for the applyListSlashes function.
    run applyListSlashesTest = {
      val initEpoch = 2
      val list1 = [{epoch: initEpoch, validator: "alice", rate: 1}]
      val list2 = [{epoch: initEpoch, validator: "alice", rate: 1}, {epoch: initEpoch+UNBONDING_OFFSET+CUBIC_OFFSET+1, validator: "alice", rate: 1} ]
      val list3 = [{epoch: initEpoch, validator: "alice", rate: 1},
                   {epoch: initEpoch, validator: "alice", rate: 1} ]
      val list4 = [{epoch: initEpoch, validator: "alice", rate: 1},
                   {epoch: initEpoch, validator: "alice", rate: 1},
                   {epoch: initEpoch+UNBONDING_OFFSET+CUBIC_OFFSET+1, validator: "alice", rate: 1} ]
      all {
        assert(applyListSlashes([], 100) == 100),
        assert(applyListSlashes(list1, 100) == 0),
        assert(applyListSlashes(list2, 100) == 0),
        assert(applyListSlashes(list3, 100) == 0),
        assert(applyListSlashes(list4, 100) == 0)
      }
    }

    //The test testDelegate is a unitest-like test for the delegate function.
    run delegateTest = {
      val delegatorState = {balance: INIT_BALANCE, bonded: USERS.mapBy(x => Map()), unbonded: USERS.mapBy(x => Map())}
      val validatorState = {address: "alice",
                            stake: 0.to(UNBONDING_OFFSET).mapBy(e => 0),
                            totalUnbonded: 1.to(1+PIPELINE_OFFSET).mapBy(e => Map()),
                            totalBonded: 1.to(1+PIPELINE_OFFSET).mapBy(e => 0),
                            slashes: List(),
                            frozen: 0}
      val posState = {posAccount: 0,
                      slashPool: 0,
                      epoch: 1,
                      counterTxs: 0,
                      counterInfractions: 0,
                      enqueuedSlashes: 0.to(UNBONDING_OFFSET).mapBy(e => Set())}
      nondet amount = 0.to(MAX_UINT).oneOf()
      val result = delegate(delegatorState, validatorState, posState, amount)
      if (result.success) {
        all {
          assert(result.delegatorState.balance == INIT_BALANCE - amount),
          assert(result.delegatorState.bonded.get(validatorState.address).get(1 + PIPELINE_OFFSET) == amount),
          assert(result.delegatorState.unbonded.get(validatorState.address) == Map()),
          assert(result.validatorState.stake.get(1 + PIPELINE_OFFSET) == amount),
          assert(result.posState.posAccount == amount)
        }
      } else {
        all {
          assert(amount > INIT_BALANCE or amount == 0),
          assert(result.delegatorState == delegatorState),
          assert(result.validatorState == validatorState),
          assert(result.posState == posState)
        }
      }
    }

    // The test successfulWithdrawTest checks that the withdraw works.
    run successfulWithdrawTest = {
      nondet user = USERS.oneOf()
      nondet validator = VALIDATORS.oneOf()
      all {
        init
        .then(all {
          assert(INIT_BALANCE >= 10),
          actionDelegate(user, validator, 10),
          })
        .then(actionUnbond(user, validator, 5))
        .then((UNBONDING_OFFSET+PIPELINE_OFFSET+CUBIC_OFFSET).reps(_ => actionFauxTransaction(user, validator, 0, 0, -1)))
        .then(actionWithdraw(user, validator))
        .then(all{ assert(delegators.get(user).balance == INIT_BALANCE - 10 + 5), allUnchanged})
        
      }
    }

    // The test testUnbondingPeriod checks that the unbonding period is enforced.
    run unbondingPeriodTest = {
      nondet user = USERS.oneOf()
      nondet validator = VALIDATORS.oneOf()
      all {
        init
        .then(all {
          assert(INIT_BALANCE >= 8),
          actionDelegate(user, validator, 8)
          })
        .then(actionUnbond(user, validator, 5))
        .then(actionWithdraw(user, validator))
        .then(all{ assert(delegators.get(user).balance == INIT_BALANCE - 8), allUnchanged})
      }
    }

    // The test fullExecutionTest describes an execution that involves all actions.
    run fullExecutionTest = {
      nondet user = USERS.oneOf()
      nondet validator = VALIDATORS.oneOf()
      nondet amount = 1.to(INIT_BALANCE).oneOf()
      nondet amountUnbonded = 1.to(amount).oneOf()
      val initEpoch = UNBONDING_OFFSET + CUBIC_OFFSET
      all {
        init
        .then(actionDelegate(user, validator, amount))
        .then(actionUnbond(user, validator, amountUnbonded))//epoch=UNBONDING_OFFSET+1
        .then(actionEvidence(initEpoch + 1, validator))//to be processed at the end of 2*UNBONDING_OFFSET+2*CUBIC_OFFSET+1
        .then((UNBONDING_OFFSET+CUBIC_OFFSET).reps(_ => actionFauxTransaction(user, validator, 0, 0, -1)))
        //slash already processed
        .then(actionWithdraw(user, validator))
        // the 5 tokens unbonded shoul be slashed
        .then(all{ assert(delegators.get(user).balance == INIT_BALANCE - amount),
                   //assert(pos.slashPool == amount),
                   allUnchanged })
        
      }
    }

    // The test earlyUnbondingTest is the most complete test involving all actions.
    run earlyUnbondingTest = {
      nondet user = USERS.oneOf()
      nondet validator = VALIDATORS.oneOf()
      nondet amount = 1.to(INIT_BALANCE).oneOf()
      nondet amountUnbonded = 1.to(amount).oneOf()
      //when the evidence will be processed
      val initEpoch = UNBONDING_OFFSET+CUBIC_OFFSET
      val slashingOffset = UNBONDING_OFFSET+CUBIC_OFFSET
      all {
        init
        .then(actionDelegate(user, validator, amount)) //epoch=UNBONDING_OFFSET assuming init epoch=UNBONDING_OFFSET
        .then(actionUnbond(user, validator, amountUnbonded))//epoch=UNBONDING_OFFSET+CUBIC_OFFSET+1
        .then(actionEvidence(initEpoch + 1, validator)) //to be processed at the end of 2*UNBONDING_OFFSET+2*CUBIC_OFFSET+1
        .then((slashingOffset - 1).reps(_ => actionFauxTransaction(user, validator, 0, 0, -1))) //epoch=2*UNBONDING_OFFSET+2*CUBIC_OFFSET
        //check that slash has not been processed yet
        .then(all{ assert(validators.get(validator).slashes == List()),
                   allUnchanged })
        .then(actionWithdraw(user, validator))//epoch=2*UNBONDING_OFFSET+2*CUBIC_OFFSET+1
        //no withdrawing should be allowed yet
        .then(all{ assert(delegators.get(user).balance == INIT_BALANCE - amount),
                   assert(pos.epoch == 2*UNBONDING_OFFSET+2*CUBIC_OFFSET+2),
                   allUnchanged })
        //check that slash has been processed
        .then(actionWithdraw(user, validator))//epoch=2*UNBONDING_OFFSET+2+PIPELINE_OFFSET+CUBIC_OFFSET
        //all tokens are slashed
        .then(all{ assert(delegators.get(user).balance == INIT_BALANCE - amount),
                   //assert(pos.slashPool == amount),
                   allUnchanged })
      }
    }

    //namadaScenarioTest tests a specific scenario that the Namada team use to test their implementation
    //It requires a different intialization of state variables whihc is done in initNamadaTest
    action initNamadaScenario: bool = all {
      val initEpoch = UNBONDING_OFFSET + CUBIC_OFFSET
      all {
        delegators' = USERS.mapBy(user => {balance: 1000000,
                                          bonded: VALIDATORS.mapBy(x => if (x == "alice" and user == "alice") Map(UNBONDING_OFFSET + CUBIC_OFFSET - 1 -> 200000) else Map()),
                                          unbonded: VALIDATORS.mapBy(x => Map())}),
        validators' = VALIDATORS.mapBy(validator => {address: validator,
                                                     stake: 0.to(initEpoch+PIPELINE_OFFSET).mapBy(e => if (validator=="alice" and e >= UNBONDING_OFFSET + CUBIC_OFFSET - 1) 200000 else 0),
                                                     totalUnbonded: 0.to(initEpoch+PIPELINE_OFFSET).mapBy(e => Map()),
                                                     totalBonded: 0.to(initEpoch+PIPELINE_OFFSET).mapBy(e => if (validator=="alice" and e==UNBONDING_OFFSET + CUBIC_OFFSET - 1) 200000 else 0),
                                                     slashes: List(),
                                                     frozen: 0}),
        pos' = {posAccount: 200000,
                slashPool: 0,
                epoch: initEpoch,
                counterTxs: 0,
                counterInfractions: 0,
                enqueuedSlashes: (initEpoch-CUBIC_OFFSET).to(initEpoch+CUBIC_OFFSET+UNBONDING_OFFSET).mapBy(e => Set())},
        lastTx' = { tag: "Init", result: true, user: "", validator: "", amount: 0},
        nextInfractionEpoch' = VALIDATORS.mapBy(validator => 0)
      }
    }

    run namadaScenarioTest = {
      val validator = "alice"
      nondet user = USERS.exclude(Set(validator)).oneOf()
      val initEpoch = UNBONDING_OFFSET + CUBIC_OFFSET // = 5
      val cubicSlashingRate = 1
      val initialStake = 200000
      val del1Amount = 67231
      val selfUnbond1Amount = 154654
      val delUnbond1Amount = 18000
      val selfBond1Amount = 9123
      val selfUnbond2Amount = 15000
      val del2Amount = 8144
      val stakeAfterProcessing = (1 - min(1, 2*cubicSlashingRate))*(initialStake + del1Amount - selfUnbond1Amount - delUnbond1Amount - selfUnbond2Amount + selfBond1Amount) + del2Amount
      all{
        //making preconditions explicit to ease debugging
        require(UNBONDING_OFFSET == 4),
        require(PIPELINE_OFFSET == 2),
        require(CUBIC_OFFSET == 1),
        require(VALIDATORS.exists(v => v == "alice")),
        require(size(USERS.exclude(Set(validator))) > 0),
        initNamadaScenario
        //bonded at initEpoch + PIPELINE_OFFSET = initEpoch + 2
        .then(actionDelegate(user, validator, 67231)) // epoch = initEpoch
        //unbonded at initEpoch + 1 + PIPELINE_OFFSET = initEpoch + 3
        .then(actionUnbond(validator, validator, 154654)) // epoch = initEpoch + 1
        //unbonded at initEpoch + 2 + PIPELINE_OFFSET = initEpoch + 4
        .then(actionUnbond(user, validator, 18000)) // epoch = initEpoch + 2
        //bonded at initEpoch + 3 + PIPELINE_OFFSET = initEpoch + 5
        .then(actionDelegate(validator, validator, 9123)) // epoch = initEpoch + 3
        //unbonded at initEpoch + 4 + PIPELINE_OFFSET = initEpoch + 6
        .then(actionUnbond(validator, validator, 15000)) // epoch = initEpoch + 4
        //bonded at initEpoch + 5 + PIPELINE_OFFSET = initEpoch + 7
        .then(actionDelegate(user, validator, 8144)) // epoch = initEpoch + 5
        //slash processed at initEpoch + PIPELINE_OFFSET + 1 + CUBIC_OFFSET + UNBONDING_OFFSET = (initEpoch + 3) + 5 = initEpoch + 8
        .then(actionEvidence(initEpoch + PIPELINE_OFFSET + 1, validator)) // epoch = initEpoch + 6
        //slash processed at initEpoch + PIPELINE_OFFSET + 1 + CUBIC_OFFSET + UNBONDING_OFFSET = (initEpoch + 3) + 5 = initEpoch + 8
        .then(actionEvidence(initEpoch + PIPELINE_OFFSET + 1, validator)) // epoch = initEpoch + 6
        //slash processed at initEpoch + PIPELINE_OFFSET + 2 + CUBIC_OFFSET + UNBONDING_OFFSET = (initEpoch + 4) + 5 = initEpoch + 9
        .then(actionEvidence(initEpoch + PIPELINE_OFFSET + 2, validator)) // epoch = initEpoch + 6
        .then(3.reps(_ => actionFauxTransaction(user, validator, 0, 0, -1))) // epoch = initEpoch + 6..initEpoch + 8
        .then(all{assert(validators.get(validator).stake.get(initEpoch + 9) == stakeAfterProcessing),
                  allUnchanged })
      }
    }
}