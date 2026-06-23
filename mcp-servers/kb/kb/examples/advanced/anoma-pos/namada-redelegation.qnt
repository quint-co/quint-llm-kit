// ****************************************************************************
//  This encodes the proof-of-stake system of Namada.
//
//  Manuel Bravo, Informal Systems, 2023
// ****************************************************************************

module namada {

  import helperFunctions.* from "./helper-functions"
  import basicSpells.* from "./basicSpells"
  import extraSpells.* from "./extraSpells"
  import Dec.* from "./dec"
  import types.* from "./namada-types"

    // ****************************************************************************
    // State machine state
    // ************************************************************************* 

    // Delegator state
    var delegators: Address -> DelegatorState
    // Validator state
    var validators: Address -> ValidatorState
    // Proof-of-stake state
    var pos: PosState

    // ****************************************************************************
    // Execution state
    // ************************************************************************* 


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

    var totalInflation: Dec

    // **************************************************************************
    // Main functions
    // ************************************************************************* 

    // The function delegate is called when a user wants to delegate tokens to a validator.
    // 1. It first checks that the user has enough tokens in its account.
    // 2. Then it locks those tokens by transferring them from the user's account to the PoS special account.
    // 3. It records that the user has delegated amount tokens to the validator.
    // 4. It increases the validator's stake at the PIPELINE_OFFSET and updates the totalBonded variable.
    pure def delegate(delegator: DelegatorState, validator: ValidatorState, posState: PosState, amount: int): ResultTx = {
      if (amount <= delegator.balance and amount > 0) {
        val updatedDelegator = delegator.with("balance", delegator.balance - amount)
                                        .with("bonded", delegator.bonded.set(validator.address,
                                                                             delegator.bonded.get(validator.address).addBond(posState.epoch + PIPELINE_OFFSET, amount)))                                                                       
        val updatedValidator = validator.with("stake", validator.stake.set(posState.epoch + PIPELINE_OFFSET,
                                                                           validator.stake.get(posState.epoch + PIPELINE_OFFSET) + amount))
                                        .with("totalBonded", validator.totalBonded.addBond(posState.epoch + PIPELINE_OFFSET, amount)) 
        val updatedPos = posState.with("posAccount", posState.posAccount + amount)
        {success: true, delegator: updatedDelegator, validator: updatedValidator, posState: updatedPos}
      } else {
        {success: false, delegator: delegator, validator: validator, posState: posState}
      }
    }

    // The function unbond is called when a user wants to unbond tokens from a validator.
    // 1. It first checks that the user has enough tokens bonded to the validator and that the validator is not frozen.
    // 2. Then it uses iterateBondsUpToAmount to compute the set of bonds that must be unbonded.
    // 3. It computes the set of unbond records to be added to the delegators unbonded variable.
    // 4. It updates the delegator state by removing the unbonded bonds and adding the newly computed unbonds.
    // 5. It applies any slashes to the unbonded bonds and stroes it in amountAfterSlashing.
    // 6. It updates the validator's totalUnbonded.
    // 7. It finally updates the validator's stale at the PIPELINE_OFFSET by subtracting amountAfterSlashing.

    pure def unbond(delegator: DelegatorState, validatorAddress: Address, allValidators: Address -> ValidatorState, posState: PosState, amount: int, isRedelegation: bool): ResultUnbondTx = {
      val validator = allValidators.get(validatorAddress)
      val bonds = delegator.bonded.get(validator.address)
      val redelegatedBonds = delegator.redelegatedBonded.get(validator.address)
      val totalBonded = bonds.keys().fold(0, (sum, e) => sum + bonds.get(e))      
      if (amount > 0 and amount <= totalBonded and validator.frozen < posState.epoch) {
        // Compute the epoch at which the unbonded bonds will be withdrawable
        val endEpoch = posState.epoch + PIPELINE_OFFSET + CUBIC_OFFSET + UNBONDING_OFFSET
        // Compute the set of bonds to be unbonded
        val resultUnbonding = iterateBondsUpToAmount(bonds, amount)
        // Compute the updated delegators bonded variable by removing the unbonded bonds and adding a new bond in case one was partially unbonded                                                     
        val updatedBonded = if (resultUnbonding.new.start == -1) bonds.mapRemoveSet(resultUnbonding.toRemove)
                            else bonds.mapRemoveSet(resultUnbonding.toRemove).set(resultUnbonding.new.start, resultUnbonding.new.amount)
        // Compute a modified redelegation bond in case one was partially unbonded
        val modifiedRedelegation =  if (not(redelegatedBonds.has(resultUnbonding.new.start))) {epoch: -1, valsToRemove: Set(), valToModify: "", epochsToRemove: Set(), epochToModify: -1, newAmount: -1}
                                    else computeModifiedRedelegation(redelegatedBonds.get(resultUnbonding.new.start), resultUnbonding.new.start, bonds.get(resultUnbonding.new.start) - resultUnbonding.new.amount)
        // Compute the updated delegator's redelegated bonded by removing the unbonded bonds and updating the partially unbonded one computed in the previous step
        val updatedRedelegatedBonded = if (modifiedRedelegation.epoch == -1) redelegatedBonds.mapRemoveSet(resultUnbonding.toRemove)
                                       else if (modifiedRedelegation.valsToRemove == Set()) redelegatedBonds.mapRemoveSet(resultUnbonding.toRemove.setAdd(modifiedRedelegation.epoch))
                                            else redelegatedBonds.mapRemoveSet(resultUnbonding.toRemove).set(modifiedRedelegation.epoch, updateRedelegatedBondsMap(redelegatedBonds.get(modifiedRedelegation.epoch), modifiedRedelegation))
        // Compute the set of unbond records that have to be recorded out of the set of unbonded bonds computed at the previous step
        val keysUnbonds = if (resultUnbonding.new.start == -1) resultUnbonding.toRemove else resultUnbonding.toRemove.setAdd(resultUnbonding.new.start)
        val newUnbonds = tuples(keysUnbonds, Set(endEpoch)).mapBy(unbondKey => val start = unbondKey._1
                                                                               if (start == resultUnbonding.new.start) bonds.get(start) - resultUnbonding.new.amount
                                                                               else bonds.get(start))
        // Compute the updated delegators unbonded variable by adding the new unbonds if the unbonding is not happenging due to a redelegation                                                                                                                                 
        val updatedUnbonded = if (isRedelegation) delegator.unbonded.get(validator.address) else delegator.unbonded.get(validator.address).mapAddSet(newUnbonds)
        // Compute the new redelegated unbonds
        val newRedelegatedUnbonds = computeNewRedelegatedUnbonds(redelegatedBonds, resultUnbonding.toRemove, modifiedRedelegation)
        val updatedRedelegatedUnbonded = if (isRedelegation) delegator.redelegatedUnbonded.get(validator.address)
                                         else updateRedelegatedUnbonded(delegator.redelegatedUnbonded.get(validator.address), newRedelegatedUnbonds, endEpoch)
        // Compute rewards produced by the unbonded tokens
        val lastClaim = delegator.lastClaim.get(validator.address)
        val sumRewardsBonds = newUnbonds.keys().fold((0,1), (sum, key) => val start = key._1
                                                                          val redelegatedBond = delegator.redelegatedBonded.get(validator.address).getOrElse(start, Map())
                                                                          val reward = computeBondRewards(start, newUnbonds.get(key), redelegatedBond, validator.address, allValidators.keys().mapBy(v => allValidators.get(v).slashes), lastClaim, validator.rewardsProducts)
                                                                          sum.add(reward))
        // Compute the updated delegator's state
        val updatedDelegator = delegator.with("bonded", delegator.bonded.set(validator.address, updatedBonded))
                                        .with("redelegatedBonded", delegator.redelegatedBonded.set(validator.address, updatedRedelegatedBonded))
                                        .with("unbonded", delegator.unbonded.set(validator.address, updatedUnbonded))
                                        .with("redelegatedUnbonded", delegator.redelegatedUnbonded.set(validator.address, updatedRedelegatedUnbonded))
                                        .with("rewards", delegator.rewards.set(validator.address, delegator.rewards.get(validator.address).add(sumRewardsBonds)))
        // Compute the updated validator's totalBonded variable
        val updatedTotalBonded = val bondToSubtract = keysUnbonds.mapBy(start => newUnbonds.get((start, endEpoch)))
                                 subtractBondsFromTotalBonded(validator.totalBonded, bondToSubtract)
        // Compute the updated validator's totalRedelegatedBonded variable
        val updatedTotalRedelegatedBonded = subtractRedelegationsFromTotalRedelegatedBonded(validator.totalRedelegatedBonded, newRedelegatedUnbonds)
        // Compute the updated validator's totalUnbonded variable
        val updatedTotalUnbonded = newUnbonds.keys().fold(validator.totalUnbonded.get(posState.epoch + PIPELINE_OFFSET),
                                                          (acc, unbondKey) => val start = unbondKey._1
                                                                              acc.mapSafeSet(start, acc.getOrElse(start, 0) + newUnbonds.get(unbondKey)))
        // Compute the updated validator's total redelegated unbonded
        val updatedTotalRedelegatedUnbonded = updateTotalRedelegatedUnbonded(validator.totalRedelegatedUnbonded.get(posState.epoch + PIPELINE_OFFSET), newRedelegatedUnbonds)
        // Compute how much out of amount has not been already removed from the validator's stake when slashing validators
        // at the end of previous epochs
        val resultSlashing = computeAmountAfterSlashingUnbond(newUnbonds, newRedelegatedUnbonds, validatorAddress, allValidators.keys().mapBy(v => allValidators.get(v).slashes))
        val amountAfterSlashing = resultSlashing.sum
        val mapEpochAmountAfterSlashing = resultSlashing.epochMap.keys().filter(e => resultSlashing.epochMap.get(e) > 0).mapBy(e => resultSlashing.epochMap.get(e))
        // Compute the updated validator's state by updating its state and totalUnbonded.
        val updatedValidator = validator.with("stake", validator.stake.set(posState.epoch + PIPELINE_OFFSET,
                                                                           validator.stake.get(posState.epoch + PIPELINE_OFFSET) - amountAfterSlashing))
                                        .with("totalUnbonded", validator.totalUnbonded.set(posState.epoch + PIPELINE_OFFSET, updatedTotalUnbonded))
                                        .with("totalRedelegatedUnbonded", validator.totalRedelegatedUnbonded.set(posState.epoch + PIPELINE_OFFSET, updatedTotalRedelegatedUnbonded))
                                        .with("totalBonded", updatedTotalBonded)
                                        .with("totalRedelegatedBonded", updatedTotalRedelegatedBonded)
        {result: {success: true, delegator: updatedDelegator, validator: updatedValidator, posState: posState},  resultSlashing: {sum: amountAfterSlashing, epochMap: mapEpochAmountAfterSlashing}}
      } else {
        {result: {success: false, delegator: delegator, validator: validator, posState: posState}, resultSlashing: {sum: -1, epochMap: Map()}}
      }
    }

    // The function withdraw is called when a user wants to withdraw tokens from a validator.
    // 1. First it computes whether there are tokens ready to be withdrawn and returns an error in case there are none.
    // 2. Then records that those tokens are withdrawn by removing the withdrawable unbond records from unbonded.
    // 3. Finally, it unlocks the tokens by transferring them from the PoS special account to the user's account, after slashing them.
    pure def withdraw(delegator: DelegatorState, validatorAddress: Address, allValidators: Address -> ValidatorState, posState: PosState): ResultTx = {
      val validator = allValidators.get(validatorAddress)
      val unbonds = delegator.unbonded.get(validator.address)
      val redelegatedUnbonds = delegator.redelegatedUnbonded.get(validator.address)
      // Select the set of unbonds that can be withdrawn
      val setWithdrawn = unbonds.keys().filter(unbondKey => unbondKey._2 <= posState.epoch).mapBy(unbondKey => unbonds.get(unbondKey))
      if (size(setWithdrawn.keys()) > 0) {
        // Compute how much out of amount is withdrawn after slashing by leveraging applyListSlashes
        val amountAfterSlashing = computeAmountAfterSlashingWithdraw(setWithdrawn, redelegatedUnbonds, validatorAddress, allValidators.keys().mapBy(v => allValidators.get(v).slashes)).sum
        // Remove the sent of withdrawn unbonds from the set of unbonds
        // Transfer withdrawn tokens from the PoS account to the user's account
        val updatedDelegator = delegator.with("unbonded", delegator.unbonded.set(validator.address, unbonds.mapRemoveSet(setWithdrawn.keys())))
                                        .with("redelegatedUnbonded", delegator.redelegatedUnbonded.set(validator.address, redelegatedUnbonds.mapRemoveSet(setWithdrawn.keys())))
                                        .with("balance", delegator.balance + amountAfterSlashing)
        val updatedPos = posState.with("posAccount", posState.posAccount - amountAfterSlashing)
        {success: true, delegator: updatedDelegator, validator: validator, posState: updatedPos}
      } else {
        {success: false, delegator: delegator, validator: validator, posState: posState}
      }
    }

    // The function redelegate is called when a user wants to redelegate tokens from a source validator to a destination validator.
    // 1. The function first attempts to unbond the desired amount from the source validator.
    // 2. It only proceeds if the redelegation is not a chain redelegation and the unbonding succeeded.
    //    - The design does not track chain redelegation precisely.
    //    - Instead, it approximates it by preventing a validator from redelegating tokens belonging to a delegator if it has received a
    //      redelegation of tokens belonging to the same delegator that ended less than UNBONDING_OFFSET + CUBIC_OFFSET epochs ago.
    // 3. It updates the delegator's variables bonded and redelegatedBonded to register that the target amount of tokens are now
    //    bonded to the destination validator.
    // 4. It registers the redelegation in the source validator's outgoingRedelegations variable.
    // 5. It updates the destinations validator stake, registers the redelegation in its incomingRedelegations and updates its totalBonded variable.
    pure def redelegate(delegator: DelegatorState, allValidators: Address -> ValidatorState, srcAddress: Address, destAddress: Address, posState: PosState, amount: int): ResultRedelegationTx = {
      val srcValidator = allValidators.get(srcAddress)
      val destValidator = allValidators.get(destAddress)
      val endEpochRedelegation = srcValidator.incomingRedelegations.get(delegator.address)
      val isNotChained = endEpochRedelegation >=0 implies posState.epoch >= endEpochRedelegation + slashProcessingDelay
      val resultUnbond = unbond(delegator, srcAddress, allValidators, posState, amount, true)
      if (isNotChained and resultUnbond.result.success == true) {
        val newDelegatorState = resultUnbond.result.delegator
        val newSrcValidatorState = resultUnbond.result.validator
        val amountAfterSlashing = resultUnbond.resultSlashing.sum
        val updatedRedelegatedBonds = val existing = newDelegatorState.redelegatedBonded.get(destAddress).getOrElse(posState.epoch + PIPELINE_OFFSET, Map()).getOrElse(srcAddress, Map())
                                      val updatedMap = mergeBondsMap(existing, resultUnbond.resultSlashing.epochMap)
                                      newDelegatorState.redelegatedBonded.get(destAddress).mapSafeSet(posState.epoch + PIPELINE_OFFSET,
                                                                                                      newDelegatorState.redelegatedBonded.get(destAddress).getOrElse(posState.epoch + PIPELINE_OFFSET, Map()).mapSafeSet(srcAddress, updatedMap))
        val updatedDelegator = newDelegatorState.with("bonded", newDelegatorState.bonded.set(destValidator.address,
                                                                                             newDelegatorState.bonded.get(destValidator.address).addBond(posState.epoch + PIPELINE_OFFSET, amountAfterSlashing))) 
                                                .with("redelegatedBonded", newDelegatorState.redelegatedBonded.set(destValidator.address, updatedRedelegatedBonds))
        val updatedOutgoingRedelegations = mergeOutgoingRedelegations(newSrcValidatorState.outgoingRedelegations.get(destAddress), resultUnbond.resultSlashing.epochMap, posState.epoch)
        val updatedSrcValidator = newSrcValidatorState.with("outgoingRedelegations", newSrcValidatorState.outgoingRedelegations.set(destAddress, updatedOutgoingRedelegations))
        val updatedDestValidator = destValidator.with("stake", destValidator.stake.set(posState.epoch + PIPELINE_OFFSET,
                                                                                       destValidator.stake.get(posState.epoch + PIPELINE_OFFSET) + amountAfterSlashing))
                                                .with("totalBonded", destValidator.totalBonded.addBond(posState.epoch + PIPELINE_OFFSET, amountAfterSlashing))
                                                .with("totalRedelegatedBonded", destValidator.totalRedelegatedBonded.mapSafeSet(posState.epoch + PIPELINE_OFFSET, mergeRedelegatedBondsMap(destValidator.totalRedelegatedBonded.getOrElse(posState.epoch + PIPELINE_OFFSET, Map()),
                                                                                                                                                                                           Map(srcAddress -> resultUnbond.resultSlashing.epochMap))))
                                                .with("incomingRedelegations", destValidator.incomingRedelegations.set(delegator.address, posState.epoch + PIPELINE_OFFSET))      
        {success: true, delegator: updatedDelegator, srcValidator: updatedSrcValidator, destValidator: updatedDestValidator, posState: posState}
      } else {
        {success: false, delegator: delegator, srcValidator: srcValidator, destValidator: destValidator, posState: posState}
      }
    }

    // The function claim is called when a user wants to claim its rewards generated by delegating to a given a validator .
    // 1. The function first computes the total amount of rewards by multiplying the validator's rewardsProducts to the
    //    delegators current bonds.
    // 2. It adds any rewards already computed at unbonding (and those coming from commissions for validators) .
    // 3. If there are rewards to claim, the tokens are moved to the delegator's balanceRewards, and lastClaima and rewards
    //    are updated accordingly. lastClaim is key to guarantee that rewards for a given bond and epoch are claimed at most once.
    // 4. Note that the rewards should be moved to the delegators account. We do not do that in the Quint spec because balance is an integer and rewards
    //    are decimals. Maybe in the future when Quint supports fractions vatively, we will refactor the spec. The implementation should move the rewards
    //    to the delegator's account.
    pure def claim(delegator: DelegatorState, validator: ValidatorState, slashes: Address -> List[Slash], posState: PosState): ResultTx = {
      val totalRewards = computeAllRewards(delegator, validator, slashes)
      if (ceil(totalRewards) > 0) {
        val updatedDelegator = delegator.with("lastClaim", delegator.lastClaim.set(validator.address, posState.epoch-1))
                                        //.with("balance", delegator.balance + truncate(totalRewards))
                                        .with("balanceRewards", delegator.balanceRewards.add(totalRewards))
                                        .with("rewards", delegator.rewards.set(validator.address, (0,1)))
        {success: true, delegator: updatedDelegator, validator: validator, posState: posState}
      } else {
        {success: false, delegator: delegator, validator: validator, posState: posState}
      }
    }
    
    // The function processSlash processes a slash by (i) slashing the misbehaving validator; and (ii) any validator to which it has redelegated some tokens and the slash misbehaving epoch
    // is wihtin the redelegation slashing window.
    // - @param misbehavingValidator the misbehaving validator.
    // - @param slashRate the slash rate.
    // - @param curEpoch the current epoch.
    // - @param slashedAmountsMap a map from validator address to a map from epoch to already processed slash amounts.
    // - @param validatorsState a map from validatro address to validator's state.
    // - @returns a map that adds any newly processed slash amount of any involved validator to slashedAmountsMap.
    pure def processSlash(misbehavingValidator: Address,
                          slashRate: int,
                          curEpoch: Epoch,
                          slashedAmountMap: Address -> Epoch -> int,
                          validatorsState: Address -> ValidatorState,
                          slashes: Address -> List[Slash]): Address -> Epoch -> int = { 
      val infractionEpoch = curEpoch - slashProcessingDelay
      val resultSlashValidator = slashValidator(misbehavingValidator,
                                                curEpoch,
                                                slashes,
                                                validatorsState.get(misbehavingValidator).totalUnbonded,
                                                validatorsState.get(misbehavingValidator).totalRedelegatedUnbonded,
                                                validatorsState.get(misbehavingValidator).totalBonded,
                                                validatorsState.get(misbehavingValidator).totalRedelegatedBonded,                                            
                                                slashRate,
                                                slashedAmountMap.get(misbehavingValidator))
      val updatedSlashedAmountMap = slashedAmountMap.set(misbehavingValidator, resultSlashValidator)
      val outgoingRedelegations = validatorsState.get(misbehavingValidator).outgoingRedelegations
      outgoingRedelegations.keys().fold(updatedSlashedAmountMap, (acc, destValidator) => acc.set(destValidator, slashValidatorRedelegation(misbehavingValidator,
                                                                                                                                           curEpoch,             
                                                                                                                                           outgoingRedelegations.get(destValidator),
                                                                                                                                           validatorsState.get(misbehavingValidator).slashes,
                                                                                                                                           validatorsState.get(destValidator).totalRedelegatedUnbonded,
                                                                                                                                           slashRate,
                                                                                                                                           acc.get(destValidator))))
    }

    // This function is executed at the end of an epoch.
    // 1. It first computes the final rate for all slashes scheduled to be processed at the end of the current epoch.
    // 2. It computes for each validator how much it should be slashed based of the slashes scheduled to be processed. It already computes 
    // how much should be substracted from each validator's stake variable at every epoch between the current epoch and the current epoch + PIPELINE_OFFSET.
    // 3. It computes rewards.
    // 4. It updates the validators' state by (i) shifting the epoched stake variable and applying any precomputed slash; (ii) shifting totalUnbonded, totalRedelegatedUnbonded and totalBonded;
    // and (iii) appending newly created slash records.
    // 5. It update PoS state by increasing the epoch, setting counterTxs to zero, transferring totalAmountSlashed from the PoS accoun tot the slash pool
    // and shifting equeued slashes.
    pure def endOfEpoch(delegatorsState: Address -> DelegatorState, validatorsState: Address -> ValidatorState, posState: PosState, curEpoch: Epoch): {delegatorsState: Address -> DelegatorState, validatorsState: Address -> ValidatorState, posState: PosState} = {
      val finalRate = computeFinalRate((curEpoch-CUBIC_OFFSET).to(curEpoch+CUBIC_OFFSET).fold(Set(), (acc, e) => acc.union(posState.enqueuedSlashes.get(e))))
      val initMap = VALIDATORS.mapBy(v => (curEpoch+1).to(curEpoch+PIPELINE_OFFSET).mapBy(e => 0))
      val infractionEpoch = posState.epoch - CUBIC_OFFSET - UNBONDING_OFFSET
      val slashPerValidator = posState.enqueuedSlashes.get(curEpoch).fold(Map(), (acc, slash) => acc.mapSafeSet(slash.validator, min(1, acc.getOrElse(slash.validator, 0) + finalRate)))
      val slashesMap = VALIDATORS.mapBy(v => validatorsState.get(v).slashes)
      val mapValidatorSlash = slashPerValidator.keys().fold(initMap, (acc, validator) => processSlash(validator, slashPerValidator.get(validator), curEpoch, acc, validatorsState, slashesMap))
      val updatedSlashesMap = VALIDATORS.mapBy(v => if (slashPerValidator.has(v)) validatorsState.get(v).slashes.append({epoch: infractionEpoch, rate: slashPerValidator.get(v)})
                                                    else validatorsState.get(v).slashes)
      val rewards = VALIDATORS.mapBy(v => val commission = validatorsState.get(v).commission.get(curEpoch)
                                          val rewardProduct = computeRewardProduct(updatedSlashesMap.get(v))
                                          val stake = validatorsState.get(v).stake.get(curEpoch)
                                          {fromCommission: (stake,1).mul(rewardProduct).mul(commission), product: rewardProduct.mul((1,1).sub(commission))})
      val updatedDelegators = USERS.mapBy(x => if (not(x.in(VALIDATORS))) delegatorsState.get(x)
                                               else delegatorsState.get(x).with("rewards", delegatorsState.get(x).rewards.set(x, delegatorsState.get(x).rewards.get(x).add(rewards.get(x).fromCommission))))
      val updatedValidators = VALIDATORS.mapBy(v => validatorsState.get(v).with("stake",(curEpoch-UNBONDING_OFFSET-CUBIC_OFFSET+1).to(curEpoch+1+PIPELINE_OFFSET).mapBy(e => if (e < curEpoch+1+PIPELINE_OFFSET) validatorsState.get(v).stake.get(e) -
                                                                                                                                                                              if (e >= curEpoch+1) mapValidatorSlash.get(v).get(e) else 0
                                                                                                                                                                             else validatorsState.get(v).stake.get(e-1) - mapValidatorSlash.get(v).get(e-1))) 
                                                                          .with("totalUnbonded", (curEpoch-CUBIC_OFFSET-UNBONDING_OFFSET+1).to(curEpoch+1+PIPELINE_OFFSET).mapBy(e => if (e < curEpoch+1+PIPELINE_OFFSET) validatorsState.get(v).totalUnbonded.get(e)
                                                                                                                                                                                      else Map()))
                                                                          .with("totalRedelegatedUnbonded", (curEpoch-CUBIC_OFFSET-UNBONDING_OFFSET+1).to(curEpoch+1+PIPELINE_OFFSET).mapBy(e => if (e < curEpoch+1+PIPELINE_OFFSET) validatorsState.get(v).totalRedelegatedUnbonded.get(e)
                                                                                                                                                                                                 else Map()))                                                                                                                                                                                                                                                                                                 
                                                                          .with("slashes", updatedSlashesMap.get(v))
                                                                          .with("commission", (curEpoch+1).to(curEpoch+1+PIPELINE_OFFSET).mapBy(e => if (e < curEpoch+1+PIPELINE_OFFSET) validatorsState.get(v).commission.get(e)
                                                                                                                                                     else validatorsState.get(v).commission.get(e-1))) 
                                                                          .with("rewardsProducts", validatorsState.get(v).rewardsProducts.mapSafeSet(curEpoch, rewards.get(v).product)))
      //val totalAmountSlashed = slashPerValidator.keys().fold(0, (sum, validator) => sum + validatorsState.get(validator).stake.get(infractionEpoch)*slashPerValidator.get(validator))
      val updatedPos =  posState.with("epoch", curEpoch + 1)
                                .with("counterTxs", 0)
                                .with("counterInfractions", 0)
                                //.with("posAccount", posState.posAccount - totalAmountSlashed)
                                //.with("slashPool", posState.slashPool + totalAmountSlashed)
                                .with("enqueuedSlashes", (curEpoch-CUBIC_OFFSET+1).to(curEpoch+1+CUBIC_OFFSET+UNBONDING_OFFSET).mapBy(e => if (e < curEpoch+1+CUBIC_OFFSET+UNBONDING_OFFSET) posState.enqueuedSlashes.get(e)
                                                                                                                                           else Set()))                                                                      
      {delegatorsState: updatedDelegators, validatorsState: updatedValidators, posState: updatedPos}                                                                                                                             
    }

    // The function proccessEvidence is called when a validator misbehaves.
    // 1. If first checks if the evidence is too old.
    // 2. The function then creates a slash record.
    // 3. Next, it updates the validator's state by freezing the validator.
    // 4. It finally enqueues the slash and schedules it to be proccessed at the end of the epoch resulting from adding UNBONDING_OFFSET
    // to the misbehaving epoch. 
    pure def proccessEvidence(e: Epoch, validator: ValidatorState, posState: PosState): {success: bool, validator: ValidatorState, posState: PosState} = {
      if (e >= posState.epoch - UNBONDING_OFFSET and e <= posState.epoch) {
        val id = posState.counterInfractions + 1
        val infraction = {id: id, epoch: e, validator: validator.address}
        {success: true, 
         validator: validator.with("frozen", max(validator.frozen, e + CUBIC_OFFSET + UNBONDING_OFFSET)),
         posState: posState.with("enqueuedSlashes", posState.enqueuedSlashes.set(e + CUBIC_OFFSET + UNBONDING_OFFSET, posState.enqueuedSlashes.get(e + CUBIC_OFFSET + UNBONDING_OFFSET).union(Set(infraction))))
                           .with("counterInfractions", id)}
      } else {
        {success: false, validator: validator, posState: posState}
      }
    }


    // ****************************************************************************
    // Actions
    // *************************************************************************

    // The action commonTxAfter is called after a transaction is executed.
    // 1. It first checks if it is the last transaction of the current epoch.
    // 2. If it is the last transaction of the epoch, it calls the endOfEpoch function.
    // 3. Otherwise, it updates the variables using the result of the transaciton and increases counterTxs.
    action commonTxAfter(updatedDelegators: Address -> DelegatorState, updatedValidators: Address -> ValidatorState, updatedPos: PosState): bool = all {
      nextInfractionEpoch' = nextInfractionEpoch,
      if (pos.counterTxs + 1 == TXS_EPOCH) {
        val resultEndOfEpoch = endOfEpoch(updatedDelegators, updatedValidators, updatedPos, pos.epoch)
        all {
          delegators' = resultEndOfEpoch.delegatorsState,
          validators' = resultEndOfEpoch.validatorsState,
          pos' = resultEndOfEpoch.posState,
          totalInflation' = totalInflation.add(computeEpochInflation(updatedValidators, updatedPos.epoch))
        }
      } else {
        all {
          delegators' = updatedDelegators,
          validators' = updatedValidators,
          pos' = updatedPos.with("counterTxs", updatedPos.counterTxs + 1),
          totalInflation' = totalInflation,
        }
      }
    }

    action actionDelegate(user: Address, validator: Address, amount: int): bool = all {
      val result = delegate(delegators.get(user), validators.get(validator), pos, amount)
      all {
        require(enforceStateTransition implies result.success),
        commonTxAfter(delegators.set(user, result.delegator),
                      validators.set(validator, result.validator),
                      result.posState),
        lastTx' = {tag: "Delegate", result: result.success, user: user, validator: validator, amount: amount}
      }
    }

    action actionUnbond(user: Address, validator: Address, amount: int): bool = all {
      val result = unbond(delegators.get(user), validator, validators, pos, amount, false).result
      all {
        require(enforceStateTransition implies result.success),
        commonTxAfter(delegators.set(user, result.delegator),
                      validators.set(validator, result.validator),
                      result.posState),
        lastTx' = {tag: "Unbond", result: result.success, user: user, validator: validator, amount: amount}
      }
    }

    action actionWithdraw(user: Address, validator: Address): bool = all {
      val result = withdraw(delegators.get(user), validator, validators, pos)
      all {
        require(enforceStateTransition implies result.success),
        commonTxAfter(delegators.set(user, result.delegator),
                      validators.set(validator, result.validator),
                      result.posState),
        lastTx' = {tag: "Withdraw", result: result.success, user: user, validator: validator, amount: 0}
      }
    }

    action actionClaim(user: Address, validator: Address): bool = all {
      val slashes = validators.keys().mapBy(v => validators.get(v).slashes)
      val result = claim(delegators.get(user), validators.get(validator), slashes, pos)
      all {
        require(enforceStateTransition implies result.success),
        commonTxAfter(delegators.set(user, result.delegator),
                      validators.set(validator, result.validator),
                      result.posState),
        lastTx' = {tag: "Claim", result: result.success, user: user, validator: validator, amount: 0}
      }
    }

    action actionRedelegate(user: Address, srcValidator: Address, destValidator: Address, amount: int): bool = all {
      val result = redelegate(delegators.get(user), validators, srcValidator, destValidator, pos, amount)
      all {
        require(enforceStateTransition implies result.success),
        commonTxAfter(delegators.set(user, result.delegator),
                      validators.set(srcValidator, result.srcValidator).set(destValidator, result.destValidator),
                      result.posState),
        lastTx' = {tag: "Redelegate", result: result.success, user: user, validator: srcValidator, amount: amount}
      }
    }

    action actionEvidence(e: Epoch, validator: Address): bool = all {
      require(limitEvidence == 1 implies nextInfractionEpoch.get(validator) < e),
      require(limitEvidence == 2 implies validators.get(validator).frozen < e),
      val result = proccessEvidence(e, validators.get(validator), pos)
      all {
        require(enforceStateTransition implies result.success),
        validators' = validators.set(validator, result.validator),
        pos' = result.posState,
        delegators' = delegators,
        lastTx' = {tag: "Evidence", result: result.success, user: "", validator: validator, amount: e},
        nextInfractionEpoch' = if (result.success) nextInfractionEpoch.set(validator, e + UNBONDING_OFFSET)
                               else nextInfractionEpoch,
        totalInflation' = totalInflation
      }
    }

    action actionFauxTransaction(user: Address, validator: Address, amountDelegate: int, amountUnbond: int, e: Epoch): bool = all {
      require(limitEvidence == 1 implies nextInfractionEpoch.get(validator) >= e),
      require(limitEvidence == 2 implies validators.get(validator).frozen >= e),
      require(amountUnbond == 0 or validators.get(validator).frozen >= pos.epoch),
      require(amountDelegate == 0),
      commonTxAfter(delegators, validators, pos),
      lastTx' = {tag: "Advance", result: true, user: user, validator: validator, amount: 0}
    }

    // ****************************************************************************
    // Invariants
    // *************************************************************************

    // PoS invariants

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
    val totalAmountTokensConstant = USERS.fold(0, (sum, user) => sum + delegators.get(user).balance) + pos.posAccount + pos.slashPool == size(USERS)*INIT_BALANCE

    // Invariant 7: A validator's stake cannot become negative.
    val stakeGreaterZero = VALIDATORS.forall(validator =>
                                             pos.epoch.to(pos.epoch + PIPELINE_OFFSET).forall(e => validators.get(validator).stake.get(e) >= 0))

    //Invariant 8: The user's balance cannot become greater than the initial balance
    val boundedBalance = USERS.forall(user => delegators.get(user).balance <= INIT_BALANCE)

    // Invariant 9: The validator's voting power at a given epoch equal to the total amount of tokens delegated to that validator after applying slashes.
    val stakeEqualSumSlashedBonds = VALIDATORS.forall(validator => USERS.fold(0, (sum, user) => val bonds = delegators.get(user).bonded.get(validator)
                                                                                                val slashes = VALIDATORS.mapBy(v => validators.get(v).slashes)
                                                                                                sum + bonds.keys().fold(0, (total, start) => val redelegatedBond = delegators.get(user).redelegatedBonded.get(validator).getOrElse(start, Map())
                                                                                                                                             val afterSlashes = computeBondAtEpoch(pos.epoch + PIPELINE_OFFSET, start, bonds.get(start), redelegatedBond, validator, slashes)
                                                                                                                                             total + afterSlashes)) == validators.get(validator).stake.get(pos.epoch + PIPELINE_OFFSET))
    // Invariant 10: The sum of rewards in user's balance can never be greater than the total inflation
    val transferredRewardsLessOrEqualInflation = val sumBalances = USERS.fold((0,1), (sum, user) => sum.add(delegators.get(user).balanceRewards))
                                                 sumBalances.le(totalInflation)

    // Invariant 11: The sum of rewards in user's balance plus the non-cliamed rewards is less than or equal to the total inflation
    val rewardsLessOrEqualInflation = val sumBalances = USERS.fold((0,1), (sum, user) => sum.add(delegators.get(user).balanceRewards))
                                      val pairsDelegatorValidator = tuples(USERS, VALIDATORS)
                                      val sumNonTransferredRewards = pairsDelegatorValidator.fold((0,1), (total, pair) => val delegator = delegators.get(pair._1)
                                                                                                                          val validator = validators.get(pair._2)
                                                                                                                          val slashes = VALIDATORS.mapBy(v => validators.get(v).slashes)
                                                                                                                          val totalRewards = computeAllRewards(delegator, validator, slashes)
                                                                                                                          total.add(totalRewards))
                                      sumBalances.add(sumNonTransferredRewards).le(totalInflation)
    
    // Implementation invariants

    // delegator's bonded for a given validator and epoch is always greater or equal than redelegatedBonded for that epoch and validator
    val bondsGreaterRedelegations = USERS.forall(user => 
                                    VALIDATORS.forall(validator => val epochs = delegators.get(user).bonded.get(validator).keys()
                                    epochs.forall(epoch => if (not(delegators.get(user).redelegatedBonded.get(validator).has(epoch))) true
                                                           else val redelegatedBonds = delegators.get(user).redelegatedBonded.get(validator).get(epoch)
                                                                val totalRedelegated =  redelegatedBonds.keys().fold(0, (sum, src) => redelegatedBonds.get(src).keys().fold(sum, (acc, e) => acc + redelegatedBonds.get(src).get(e)))
                                                                delegators.get(user).bonded.get(validator).get(epoch) >= totalRedelegated)))

    // All invariants
    val allInvariants = balanceGreaterZero and
                        posAccountGreaterZero and
                        posAccountZero and
                        stakeEqualOrLessSumBonds and
                        noSlashingStakeEqualSumBonds and
                        totalAmountTokensConstant and
                        stakeGreaterZero and
                        boundedBalance and
                        stakeEqualSumSlashedBonds and
                        bondsGreaterRedelegations and
                        transferredRewardsLessOrEqualInflation and
                        rewardsLessOrEqualInflation
                  
    // All invariants without slash pool
    // Due to the lack of slashing pool posAccountZero and noSlashingStakeEqualSumBonds do not hold
    val allInvariantsWithNoSlashPool = balanceGreaterZero and
                                       posAccountGreaterZero and
                                       stakeEqualOrLessSumBonds and
                                       totalAmountTokensConstant and
                                       stakeGreaterZero and
                                       boundedBalance and
                                       // the following two only make sense in the context of redelegations and rewards
                                       stakeEqualSumSlashedBonds and
                                       bondsGreaterRedelegations and
                                       transferredRewardsLessOrEqualInflation and
                                       rewardsLessOrEqualInflation

    
    // ****************************************************************************
    // Execution
    // *************************************************************************

    action allUnchanged: bool = all {
      delegators' = delegators,
      validators' = validators,
      pos' = pos,
      lastTx' = lastTx,
      nextInfractionEpoch' = nextInfractionEpoch,
      totalInflation' = totalInflation
    }

    // State initialization: assumes that users start with some initial balance.
    action init: bool = all {
      val initEpoch = UNBONDING_OFFSET + CUBIC_OFFSET
      all {
        delegators' = USERS.mapBy(user => {address: user,
                                           balance: INIT_BALANCE,
                                           bonded: VALIDATORS.mapBy(x => Map()),
                                           redelegatedBonded: VALIDATORS.mapBy(x => Map()),
                                           redelegatedUnbonded: VALIDATORS.mapBy(x => Map()),
                                           unbonded: VALIDATORS.mapBy(x => Map()),
                                           rewards: VALIDATORS.mapBy(x => (0,1)),
                                           lastClaim: VALIDATORS.mapBy(x => initEpoch - 1),
                                           balanceRewards: (0,1)}),
        validators' = VALIDATORS.mapBy(validator => {address: validator,
                                                     stake: 0.to(initEpoch+PIPELINE_OFFSET).mapBy(e => 0),
                                                     totalUnbonded: 0.to(initEpoch+PIPELINE_OFFSET).mapBy(e => Map()),
                                                     totalRedelegatedUnbonded: 0.to(initEpoch+PIPELINE_OFFSET).mapBy(e => Map()),
                                                     totalRedelegatedBonded: Map(),
                                                     totalBonded: Map(),
                                                     incomingRedelegations: USERS.mapBy(user => -1),
                                                     outgoingRedelegations: VALIDATORS.setRemove(validator).mapBy(x => Map()),
                                                     slashes: List(),
                                                     frozen: 0,
                                                     commission: initEpoch.to(initEpoch+PIPELINE_OFFSET).mapBy(e => (1, 5)),
                                                     rewardsProducts: Map()}),
        pos' = {posAccount: 0,
                slashPool: 0,
                epoch: initEpoch,
                counterTxs: 0,
                counterInfractions: 0,
                enqueuedSlashes: (initEpoch-CUBIC_OFFSET).to(initEpoch+CUBIC_OFFSET+UNBONDING_OFFSET).mapBy(e => Set())},
        lastTx' = { tag: "Init", result: true, user: "", validator: "", amount: 0},
        nextInfractionEpoch' = VALIDATORS.mapBy(validator => 0),
        totalInflation' = (0,1)
      }
    }

    // Execution of the state machine.
    // 1. Pick a random amount from 0 to MAX_UINT, a user, a validator, and an epoch between
    //    the current epoch and the current epoch - UNBONDING_OFFSET
    // 2. Execute one of the actions: delegate, unbond, withdraw or evidence.
    // 3. In case none of the above actions are executable, it executes the actionFauxTransaction action.
    // 4. The above logic is implemented by the precondition in actionFauxTransaction.
    action step: bool = {
        nondet user = USERS.oneOf()
        nondet validator = VALIDATORS.oneOf()
        nondet destValidator = VALIDATORS.setRemove(validator).oneOf()
        //nondet amount = 0.to(MAX_UINT).oneOf()
        nondet amountDelegate = 0.to(delegators.get(user).balance).oneOf()
        nondet amountUnbond = 0.to(delegators.get(user).bonded.get(validator).keys().fold(0, (sum, e) => sum + delegators.get(user).bonded.get(validator).get(e))).oneOf()
        nondet e = (pos.epoch - UNBONDING_OFFSET).to(pos.epoch).oneOf()
        // Execute one of the available actions/methods
        any {
            actionDelegate(user, validator, amountDelegate),
            actionUnbond(user, validator, amountUnbond),
            actionWithdraw(user, validator),
            actionClaim(user, validator),
            actionEvidence(e, validator),
            actionRedelegate(user, validator, destValidator, amountUnbond),
            //allUnchanged
            actionFauxTransaction(user, validator, amountDelegate, amountUnbond, e)
        }
    }

    // ****************************************************************************
    // Tests
    // *************************************************************************

    //The test testDelegate is a unitest-like test for the delegate function.
    //TODO: refactor, epoch ranges are off.
    run delegateTest = {
      val delegatorState = {address: "bob",
                            balance: INIT_BALANCE, 
                            bonded: USERS.mapBy(x => Map()),
                            redelegatedBonded: VALIDATORS.mapBy(x => Map()),
                            redelegatedUnbonded: VALIDATORS.mapBy(x => Map()),
                            unbonded: USERS.mapBy(x => Map()),
                            rewards: VALIDATORS.mapBy(x => (0,1)),
                            lastClaim: VALIDATORS.mapBy(x => 0),
                            balanceRewards: (0,1)}
      val validatorState = {address: "alice",
                            stake: 0.to(UNBONDING_OFFSET).mapBy(e => 0),
                            totalUnbonded: 1.to(1+PIPELINE_OFFSET).mapBy(e => Map()),
                            totalRedelegatedUnbonded: 1.to(1+PIPELINE_OFFSET).mapBy(e => Map()),
                            totalRedelegatedBonded: Map(),
                            totalBonded: Map(),
                            incomingRedelegations: USERS.mapBy(user => -1),
                            outgoingRedelegations: VALIDATORS.mapBy(x => Map()),
                            slashes: List(),
                            frozen: 0,
                            commission: 1.to(1+PIPELINE_OFFSET).mapBy(e => (1, 5)),
                            rewardsProducts: Map()}
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
          assert(result.delegator.balance == INIT_BALANCE - amount),
          assert(result.delegator.bonded.get(validatorState.address).get(1 + PIPELINE_OFFSET) == amount),
          assert(result.delegator.unbonded.get(validatorState.address) == Map()),
          assert(result.validator.stake.get(1 + PIPELINE_OFFSET) == amount),
          assert(result.posState.posAccount == amount)
        }
      } else {
        all {
          assert(amount > INIT_BALANCE or amount == 0),
          assert(result.delegator == delegatorState),
          assert(result.validator == validatorState),
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
        .then(actionDelegate(user, validator, 10))
        .then(actionUnbond(user, validator, 5))
        .then((UNBONDING_OFFSET+PIPELINE_OFFSET+CUBIC_OFFSET).reps(_ => actionFauxTransaction(user, validator, 0, 0, -1)))
        .then(actionWithdraw(user, validator))
        .then(all{ assert(delegators.get(user).balance == 15), allUnchanged})
      }
    }

    // The test testUnbondingPeriod checks that the unbonding period is enforced.
    run unbondingPeriodTest = {
      nondet user = USERS.oneOf()
      nondet validator = VALIDATORS.oneOf()
      all {
        init
        .then(actionDelegate(user, validator, 8))
        .then(actionUnbond(user, validator, 5))
        .then(actionWithdraw(user, validator))
        .then(all{ assert(delegators.get(user).balance == 12), allUnchanged})
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
        .then((slashingOffset - 1).reps(_ => actionFauxTransaction(user, validator, 0, 0, -1)))//epoch=2*UNBONDING_OFFSET+2*CUBIC_OFFSET
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
        delegators' = USERS.mapBy(user => {address: user,
                                           balance: 1000000,
                                           bonded: VALIDATORS.mapBy(x => if (x == "alice" and user == "alice") Map(UNBONDING_OFFSET + CUBIC_OFFSET - 1 -> 200000) else Map()),
                                           redelegatedBonded: VALIDATORS.mapBy(x => Map()),
                                           redelegatedUnbonded: VALIDATORS.mapBy(x => Map()),
                                           unbonded: VALIDATORS.mapBy(x => Map()),
                                           rewards: VALIDATORS.mapBy(x => (0,1)),
                                           lastClaim: VALIDATORS.mapBy(x => initEpoch - 1),
                                           balanceRewards: (0,1)}),
        validators' = VALIDATORS.mapBy(validator => {address: validator,
                                                     stake: 0.to(initEpoch+PIPELINE_OFFSET).mapBy(e => if (validator=="alice" and e >= UNBONDING_OFFSET + CUBIC_OFFSET - 1) 200000 else 0),
                                                     totalUnbonded: 0.to(initEpoch+PIPELINE_OFFSET).mapBy(e => Map()),
                                                     totalRedelegatedUnbonded: 0.to(initEpoch+PIPELINE_OFFSET).mapBy(e => Map()),
                                                     totalRedelegatedBonded: Map(),
                                                     totalBonded: if (validator=="alice") Map(UNBONDING_OFFSET+CUBIC_OFFSET-1 -> 200000) else Map(),
                                                     incomingRedelegations: USERS.mapBy(user => -1),
                                                     outgoingRedelegations: VALIDATORS.mapBy(x => Map()),
                                                     slashes: List(),
                                                     frozen: 0,
                                                     commission: initEpoch.to(initEpoch+PIPELINE_OFFSET).mapBy(e => (1, 5)),
                                                     rewardsProducts: Map()}),
        pos' = {posAccount: 200000,
                slashPool: 0,
                epoch: initEpoch,
                counterTxs: 0,
                counterInfractions: 0,
                enqueuedSlashes: (initEpoch-CUBIC_OFFSET).to(initEpoch+CUBIC_OFFSET+UNBONDING_OFFSET).mapBy(e => Set())},
        lastTx' = { tag: "Init", result: true, user: "", validator: "", amount: 0},
        nextInfractionEpoch' = VALIDATORS.mapBy(validator => 0),
        totalInflation' = (0,1)
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

    run redelegateTest = {
      nondet user = USERS.oneOf()
      nondet srcValidator = VALIDATORS.oneOf()
      nondet destValidator = VALIDATORS.setRemove(srcValidator).oneOf()
      nondet amountDelegate = 2.to(INIT_BALANCE).oneOf()
      nondet amountRedelegate = 2.to(amountDelegate).oneOf()
      nondet amountUnbond = 1.to(amountRedelegate-1).oneOf()
      val initEpoch = UNBONDING_OFFSET + CUBIC_OFFSET
      all {
        require(size(VALIDATORS) >= 2),
        init
        .then(actionDelegate(user, srcValidator, amountDelegate))
        .then(PIPELINE_OFFSET.reps(_ => actionFauxTransaction(user, srcValidator, 0, 0, -1)))
        .then(actionRedelegate(user, srcValidator, destValidator, amountRedelegate))
        .then(all {assert(delegators.get(user).redelegatedBonded.get(destValidator).get(initEpoch+2*PIPELINE_OFFSET+1).get(srcValidator).get(initEpoch+PIPELINE_OFFSET) == amountRedelegate),
                   assert(validators.get(destValidator).incomingRedelegations.get(user) == initEpoch+2*PIPELINE_OFFSET+1),
                   assert(validators.get(srcValidator).outgoingRedelegations.get(destValidator).get((initEpoch+PIPELINE_OFFSET, initEpoch+PIPELINE_OFFSET+1)) == amountRedelegate),
                   allUnchanged})
        .then(PIPELINE_OFFSET.reps(_ => actionFauxTransaction(user, srcValidator, 0, 0, -1)))
        .then(actionUnbond(user, destValidator, amountUnbond))
        .then(val bondStart = initEpoch+PIPELINE_OFFSET
              val redelegationEnd = bondStart+PIPELINE_OFFSET+1
              val unbondEnd = redelegationEnd+PIPELINE_OFFSET+CUBIC_OFFSET+UNBONDING_OFFSET+1
              val unbondMaterialized = redelegationEnd+PIPELINE_OFFSET+1
              all {assert(delegators.get(user).redelegatedBonded.get(destValidator).get(redelegationEnd).get(srcValidator).get(bondStart) == amountRedelegate - amountUnbond),
                   assert(delegators.get(user).redelegatedUnbonded.get(destValidator).get((redelegationEnd, unbondEnd)).get(srcValidator).get(bondStart) == amountUnbond),
                   assert(validators.get(destValidator).totalRedelegatedUnbonded.get(unbondMaterialized).get(redelegationEnd).get(srcValidator).get(bondStart) == amountUnbond),
                   allUnchanged})
        .then((CUBIC_OFFSET+UNBONDING_OFFSET+1).reps(_ => actionFauxTransaction(user, srcValidator, 0, 0, -1)))
        .then(actionWithdraw(user, destValidator))
        .then(all {assert(delegators.get(user).redelegatedUnbonded.get(destValidator) == Map()),
                   assert(delegators.get(user).balance == INIT_BALANCE - amountDelegate + amountUnbond),
                   allUnchanged})
      }
    }
    run redelegateWithSlashingTest = {
      nondet user = USERS.oneOf()
      nondet srcValidator = VALIDATORS.oneOf()
      nondet destValidator = VALIDATORS.setRemove(srcValidator).oneOf()
      nondet amountDelegate = 2.to(INIT_BALANCE).oneOf()
      nondet amountRedelegate = 2.to(amountDelegate).oneOf()
      nondet amountUnbond = 1.to(amountRedelegate-1).oneOf()
      val initEpoch = UNBONDING_OFFSET + CUBIC_OFFSET
      all {
        require(size(VALIDATORS) >= 2),
        init
        .then(actionDelegate(user, srcValidator, amountDelegate))
        .then(PIPELINE_OFFSET.reps(_ => actionFauxTransaction(user, srcValidator, 0, 0, -1)))
        .then(actionRedelegate(user, srcValidator, destValidator, amountRedelegate))
        .then(all {assert(delegators.get(user).redelegatedBonded.get(destValidator).get(initEpoch+2*PIPELINE_OFFSET+1).get(srcValidator).get(initEpoch+PIPELINE_OFFSET) == amountRedelegate),
                   assert(validators.get(destValidator).incomingRedelegations.get(user) == initEpoch+2*PIPELINE_OFFSET+1),
                   assert(validators.get(srcValidator).outgoingRedelegations.get(destValidator).get((initEpoch+PIPELINE_OFFSET, initEpoch+PIPELINE_OFFSET+1)) == amountRedelegate),
                   allUnchanged})
        .then(PIPELINE_OFFSET.reps(_ => actionFauxTransaction(user, srcValidator, 0, 0, -1)))
        .then(actionUnbond(user, destValidator, amountUnbond))
        //an epoch before the end of the redelegation, i.e., within the redelegation slashing window
        .then(actionEvidence(initEpoch+2*PIPELINE_OFFSET, srcValidator))
        .then(val bondStart = initEpoch+PIPELINE_OFFSET
              val redelegationEnd = bondStart+PIPELINE_OFFSET+1
              val unbondEnd = redelegationEnd+PIPELINE_OFFSET+CUBIC_OFFSET+UNBONDING_OFFSET+1
              val unbondMaterialized = redelegationEnd+PIPELINE_OFFSET+1
              all {assert(delegators.get(user).redelegatedBonded.get(destValidator).get(redelegationEnd).get(srcValidator).get(bondStart) == amountRedelegate - amountUnbond),
                   assert(delegators.get(user).redelegatedUnbonded.get(destValidator).get((redelegationEnd, unbondEnd)).get(srcValidator).get(bondStart) == amountUnbond),
                   assert(validators.get(destValidator).totalRedelegatedUnbonded.get(unbondMaterialized).get(redelegationEnd).get(srcValidator).get(bondStart) == amountUnbond),
                   allUnchanged})
        .then((CUBIC_OFFSET+UNBONDING_OFFSET+1).reps(_ => actionFauxTransaction(user, srcValidator, 0, 0, -1)))
        .then(actionWithdraw(user, destValidator))
        .then(all {assert(delegators.get(user).redelegatedUnbonded.get(destValidator) == Map()),
                   assert(delegators.get(user).balance == INIT_BALANCE - amountDelegate),
                   allUnchanged})
      }
    }
}