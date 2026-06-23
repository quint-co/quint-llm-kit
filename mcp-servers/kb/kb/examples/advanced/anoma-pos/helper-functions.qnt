/**
 *
 * Manuel Bravo, Informal Systems, 2023
 */
module helperFunctions {

  import basicSpells.* from "./basicSpells"
  import extraSpells.* from "./extraSpells"
  import Dec.* from "./dec"
  import types.* from "./namada-types"

    pure def slashProcessingDelay = CUBIC_OFFSET + UNBONDING_OFFSET

    pure def inRedelegationSlashingWindow(infractionEpoch: Epoch, redelegationStart: Epoch, redelegationEnd: Epoch): bool = {
      redelegationStart - UNBONDING_OFFSET - CUBIC_OFFSET <= infractionEpoch and infractionEpoch < redelegationEnd
    }

    pure def endRedelegationFromStart(redelegationStart: Epoch): Epoch = {
      redelegationStart + PIPELINE_OFFSET
    }

    pure def startRedelegationFromEnd(redelegationEnd: Epoch): Epoch = {
      redelegationEnd - PIPELINE_OFFSET
    }

    // **************************************************************************
    // Delegate helper functions
    // ************************************************************************* 

    // The function addBond adds a bond to a map of bonds. If there is an existing bond with the same 
    // starting epoch, then the function simply adds the amount of tokens to the existing entry.
    // - @param bonds a map of bonds.
    // - @param start the starting epoch of the bond to add.
    // - @param amount the amount of tokens of the bond to add.
    // - @returns a map of bonds accounting for the new bond.
    pure def addBond(bonds: Epoch -> int, start: Epoch, amount: int): Epoch -> int = {
      if (bonds.has(start)) bonds.set(start, bonds.get(start) + amount)
      else bonds.mapSafeSet(start, amount)
    }

    run addBondTest = all {
      val bonds = Map(1 -> 5, 2 -> 3, 6 -> 8)
      all {
        assert(addBond(bonds, 2, 6) == Map(1 -> 5, 2 -> 9, 6 -> 8)),
        assert(addBond(bonds, 3, 6) == Map(1 -> 5, 2 -> 3, 3 -> 6, 6 -> 8)),
      }
    }

    // **************************************************************************
    // Unbond helper functions
    // ************************************************************************* 

    // The function unbonds a bond record contraint to a maximum amount (acc.remainder).
    // - @param acc a record with three fields:
    //   - remainder: the maximum amount of tokens to be unbonded.
    //   - toRemove: a set of bond records which includes the set of bond records that have been unbonded so far.
    //   - new: a bond record with start epoch equal to -1.
    // - @param bond the bond record to be unbonded by the function.
    // - @returns an update acc record: subtracts the minimum between bond.amount and acc.remainder from acc.remainder; adds the bond to acc.toRemove;
    // and if bond.amount if gretaer than acc.remainder (meaning that the bond is only partially unbonded), creates a new bond record in acc.new
    // of bond.amount - acc.remainder tokens.
    pure def unbondBond(acc: {remainder: int, toRemove: Set[Epoch], new: {start: int, amount: int}}, bond: {start: int, amount: int}): {remainder: int, toRemove: Set[Epoch], new: {start: int, amount: int}} = { 
      val amountUnbonded = min(bond.amount, acc.remainder)
      {remainder: acc.remainder - amountUnbonded,
       toRemove: if (bond.amount <= acc.remainder) acc.toRemove.setAdd(bond.start) else acc.toRemove,
       new: if (bond.amount > acc.remainder) {start: bond.start, amount: bond.amount - acc.remainder} else acc.new}
    }

    run unbondBondTest = all {
      assert(unbondBond({remainder: 10, toRemove: Set(9, 8), new: {start: -1, amount: 0}}, {start: 6, amount: 5}) ==
             {remainder: 5, toRemove: Set(9, 8, 6), new: {start: -1, amount: 0}}),
      assert(unbondBond({remainder: 10, toRemove: Set(9, 8), new: {start: -1, amount: 0}}, {start: 6, amount: 11}) ==
             {remainder: 0, toRemove: Set(9, 8), new: {start: 6, amount: 1}})
    }

    // The function `iterateBondsUpToAmount` computes the set of bonds that have to be unbonded in order to unbond a given amount. To do so, it iterates
    // over a map of bonds in decreasing starting epoch order until the amount is reached. For each iterated bond, the function calls unbondBond while
    // there are still tokens to be unbonded.
    // - @param bonds a map of bonds that can be unbonded.
    // - @param amount the amount of tokens that have to be unbonded.
    // - @returns a record with two fields: toRemove the set of bonds starting epochs that have been unbonded and a new bond 
    //   that contains a bond record (starting epoch and amount) if a bond has to be partially unbonded or a bond record with start epoch equal to -1
    //   otherwise, indicating that no bond has to be partially unbonded.
    pure def iterateBondsUpToAmount(bonds: Epoch -> int,  amount: int): {toRemove: Set[Epoch], new: {start: int, amount: int}} = {
      val setEpochs = sortSetDecreasing(bonds.keys())
      val result = setEpochs.foldl({remainder: amount, toRemove: Set(), new: {start: -1, amount: 0}},
                                   (acc, e) => if (acc.remainder == 0) acc else unbondBond(acc, {start: e, amount: bonds.get(e)}))
      {toRemove: result.toRemove, new: result.new}
    }

    run iterateBondsUpToAmountTest = {
      val bonds = Map(1 -> 5, 2 -> 3, 6 -> 8)
      all {
        assert(iterateBondsUpToAmount(bonds, 8) == {toRemove: Set(6), new: {start: -1, amount: 0}}),
        assert(iterateBondsUpToAmount(bonds, 10) == {toRemove: Set(6), new: {start: 2, amount: 1}}),
        assert(iterateBondsUpToAmount(bonds, 11) == {toRemove: Set(6, 2), new: {start: -1, amount: 0}}),
        assert(iterateBondsUpToAmount(bonds, 12) == {toRemove: Set(6, 2), new: {start: 1, amount: 4}}),
      }
    }

  /// Orders a set of validators addresses in decreasing order.
  ///
  /// - @param __set a set of validator addresses.
  /// - @param __rank a map from validator addresse to rank (int).
  /// - @returns a list with the validator addresses ordered in decreasing order
  pure def sortValidatorsDecreasing(__set: Set[Address], __rank: Address -> int): List[Address] = {
    __set.fold({unordered: __set, ordered: List()}, (acc, _) => val __max = maxValidator(acc.unordered, __rank)
                                                    {unordered: acc.unordered.setRemove(__max), ordered: acc.ordered.append(__max)}).ordered
  }

  run sortValidatorsDecreasingTest = all {
    val __rank = Map("alice" -> 1, "bob" -> 2, "john" -> 4)
    all {
      assert(sortValidatorsDecreasing(Set("alice", "bob", "john"), __rank) == List("john", "bob", "alice")),
      assert(sortValidatorsDecreasing(Set("alice", "bob", "john"), __rank) == List("john", "bob", "alice")),
      assert(sortValidatorsDecreasing(Set("alice", "john", "bob"), __rank) == List("john", "bob", "alice")),
      assert(sortValidatorsDecreasing(Set("john", "bob", "alice"), __rank) == List("john", "bob", "alice")),
      assert(sortValidatorsDecreasing(Set(), __rank) == List()),
    }
  }
  /// Compute the max of a set of validator addresses according to a rank map.
  ///
  /// - @param __set a set of validator addresses.
  /// - @param __rank a map from validator addresse to rank (int).
  /// - @returns the max.
  pure def maxValidator(__set: Set[Address], __rank: Address -> int): Address = {
     __set.fold((true, ""), (__max, __i) => if (__max._1) (false, __i)
                                           else if (__rank.get(__i) > __rank.get(__max._2)) (false, __i) else (false, __max._2))._2
  }

  run maxValidatorTest = all {
    val __rank = Map("alice" -> 1, "bob" -> 2, "john" -> 4)
    all {
      assert(maxValidator(Set("alice", "bob", "john"), __rank) == "john"),
      assert(maxValidator(Set("alice", "bob", "john"), __rank) == "john"),
      assert(maxValidator(Set("alice", "john", "bob"), __rank) == "john"),
      assert(maxValidator(Set("john", "bob", "alice"), __rank) == "john"),
      assert(maxValidator(Set(), __rank) == ""),
    }
  }

    // **************************************************************************
    // Redelegation helper functions
    // ************************************************************************* 

    // It partially unbonds a redelegated bonds map.
    // - @param redelegatedBonds a map of redelegated bonds from source validator to bond starting epoch at the source validator to amount.
    // - @param epoch the epoch at which the redelegated bonds being modified were bonded to the validator
    // - @param amount the amount of tokens that have to be unbonded.
    // - @returns a ModifiedRedelegation record with all information related to the partially unbonded redelegated tokens. The iteration over source validators is non-deterministic at the moment
    //   (this should be made deterministic). Within a source validator, the iteration over bond starting epochs is done deterministically in the epoch order
    //   picked by the iterateBondsUpToAmount function. At the moment, the iterateBondsUpToAmount function iterates over these epochs in decreasing order.
    //   Note that valsToRemove includes valToModify if different to "" and epochsToRemove includes epochToModify if different to -1.
    pure def computeModifiedRedelegation(redelegatedBonds: RedelegatedBondsMap, epoch: Epoch, amount: int): ModifiedRedelegation = {
      val totalRedelegated = redelegatedBonds.keys().fold(0, (sum, src) => redelegatedBonds.get(src).keys().fold(sum, (acc, e) => acc + redelegatedBonds.get(src).get(e)))
      val orderedValidators = sortValidatorsDecreasing(redelegatedBonds.keys(), VALIDATORS_RANK)
      // If the total amount of redelegated bonds is less than the target amount, then all redelegated bonds must be unbonded.
      if (totalRedelegated <= amount) {epoch: epoch, valsToRemove: Set(), valToModify: "", epochsToRemove: Set(), epochToModify: -1, newAmount: -1}
      // If the total amount of redelegated bonds is greater than the target amount, then we need to iterate over the redelegated bonds
      // until the target amount is unbonded. The iteration works as follows (comments interleaved with the folds):
      // 1. It first iterates over source validators in a deterministic order (ranking decreasing order)
      else orderedValidators.foldl({remainder: amount, modified: {epoch: epoch, valsToRemove: Set(), valToModify: "", epochsToRemove: Set(), epochToModify: -1, newAmount: -1}}, 
                                   (acc, src) => if (acc.remainder == 0) acc
                                                 else {
                                                   val totalSrcValidator = redelegatedBonds.get(src).keys().fold(0, (sum, e) => sum + redelegatedBonds.get(src).get(e))
                                                   // 2. For a given validator, if the remaining is greater or equal to the total amount of redelegated tokens of that source validator, the
                                                   //   function removes the source validator: all its redelegated tokens will be  effectively unbonded.
                                                   if (totalSrcValidator <= acc.remainder) {remainder: acc.remainder - totalSrcValidator,
                                                                                           modified: acc.modified.with("valsToRemove", acc.modified.valsToRemove.setAdd(src))}
                                                   else {
                                                     // 3. If the remaining is less than the total amount of redelegated tokens of that source validator, the function iterates over all the bonds
                                                     //   of that validator in epoch decreasing order until the remaining is unbonded.
                                                     val resultIteration = iterateBondsUpToAmount(redelegatedBonds.get(src), acc.remainder)
                                                     {remainder: 0,
                                                     modified: if (resultIteration.new.start == -1) acc.modified.with("valsToRemove", acc.modified.valsToRemove.setAdd(src))
                                                                                                                .with("valToModify", src)
                                                                                                                .with("epochsToRemove", resultIteration.toRemove)
                                                               else acc.modified.with("valsToRemove", acc.modified.valsToRemove.setAdd(src))
                                                                                .with("valToModify", src)
                                                                                .with("epochsToRemove", resultIteration.toRemove.setAdd(resultIteration.new.start))
                                                                                .with("epochToModify", resultIteration.new.start)
                                                                                .with("newAmount", resultIteration.new.amount)}
                                                  }
                                                 }).modified
    }

    // TODO: more tests here now that we iterate over source validators deterministically
    run computeModifiedRedelegationTest = {
      val redelegatedBonds = Map("alice" -> Map(2 -> 6, 4 -> 7), "bob" -> Map(1 -> 5, 4 -> 7))
      all {
        assert(computeModifiedRedelegation(redelegatedBonds, 5, 25) == {epoch: 5,
                                                                        valsToRemove: Set(),
                                                                        valToModify: "",
                                                                        epochsToRemove: Set(),
                                                                        epochToModify: -1,
                                                                        newAmount: -1}),
        assert(computeModifiedRedelegation(redelegatedBonds, 5, 30) == {epoch: 5,
                                                                        valsToRemove: Set(),
                                                                        valToModify: "",
                                                                        epochsToRemove: Set(),
                                                                        epochToModify: -1,
                                                                        newAmount: -1}),
        assert(computeModifiedRedelegation(redelegatedBonds, 5, 7) == {epoch: 5,
                                                                       valsToRemove: Set("bob"),
                                                                       valToModify: "bob",
                                                                       epochsToRemove: Set(4),
                                                                       epochToModify: -1,
                                                                       newAmount: -1}),
        assert(computeModifiedRedelegation(redelegatedBonds, 5, 8) == {epoch: 5,
                                                                       valsToRemove: Set("bob"),
                                                                       valToModify: "bob",
                                                                       epochsToRemove: Set(1, 4),
                                                                       epochToModify: 1,
                                                                       newAmount: 4}),
        assert(computeModifiedRedelegation(redelegatedBonds, 5, 12) == {epoch: 5,
                                                                        valsToRemove: Set("bob"),
                                                                        valToModify: "",
                                                                        epochsToRemove: Set(),
                                                                        epochToModify: -1,
                                                                        newAmount: -1}),
        assert(computeModifiedRedelegation(redelegatedBonds, 5, 14) == {epoch: 5,
                                                                        valsToRemove: Set("bob", "alice"),
                                                                        valToModify: "alice",
                                                                        epochsToRemove: Set(4),
                                                                        epochToModify: 4,
                                                                        newAmount: 5}),
        assert(computeModifiedRedelegation(redelegatedBonds, 5, 19) == {epoch: 5,
                                                                        valsToRemove: Set("bob", "alice"),
                                                                        valToModify: "alice",
                                                                        epochsToRemove: Set(4),
                                                                        epochToModify: -1,
                                                                        newAmount: -1}),
        assert(computeModifiedRedelegation(redelegatedBonds, 5, 21) == {epoch: 5,
                                                                        valsToRemove: Set("bob", "alice"),
                                                                        valToModify: "alice",
                                                                        epochsToRemove: Set(4,2),
                                                                        epochToModify: 2,
                                                                        newAmount: 4}),                                                                                                                                                                                   
      }
    }

    // The function computeNewRedelegatedUnbonds computes a set of redelegated unbonds from a set of redelegated bonds.
    // - @param redelegatedBonds a map of redelegated bonds from epoch to RedelegatedBondsMap.
    // - @param unbondedEpochs a set of epochs that indicate the set of epochs unbonded.
    // - @param modified a ModifiedRedelegation record that represents a redelegated bond that it is only partially unbonded.
    // - @returns a map with the redelegated unbonds.
    // The function assumes that
    // - modified.epoch is not in the unbondedEpochs set.
    // - modified.valToModify is in modified.valsToRemove.
    // - modified.epochToModify is in in modified.epochsToRemove.
    pure def computeNewRedelegatedUnbonds(redelegatedBonds: Epoch -> RedelegatedBondsMap, unbondedEpochs: Set[Epoch], modified: ModifiedRedelegation): Epoch -> RedelegatedBondsMap = {
      // Add the modified epoch if there exists and filter out those epochs that do not include redelegations
      val updatedUnbondedEpochs = if (modified.epoch == -1) unbondedEpochs.filter(e => redelegatedBonds.has(e)) else unbondedEpochs.setAdd(modified.epoch).filter(e => redelegatedBonds.has(e))
      updatedUnbondedEpochs.mapBy(start => if (start != modified.epoch or modified.valsToRemove == Set()) redelegatedBonds.get(start)
                                           else modified.valsToRemove.mapBy(src => if (src != modified.valToModify) redelegatedBonds.get(start).get(src)
                                                                                   else modified.epochsToRemove.mapBy(bondStart => if (bondStart != modified.epochToModify) redelegatedBonds.get(start).get(src).get(bondStart)
                                                                                                                                   else redelegatedBonds.get(start).get(src).get(bondStart) - modified.newAmount)))
    }

    run computeNewRedelegatedUnbondsTest = {
      val redelegatedBonds = Map(5 -> Map("alice" -> Map(2 -> 1, 4 -> 1), "bob" -> Map(1 -> 1, 4 -> 2)),
                                 7 -> Map("alice" -> Map(2 -> 1, 4 -> 1), "bob" -> Map(1 -> 1, 4 -> 2)))
      val emptyModified = {epoch: -1, valsToRemove: Set(), valToModify: "", epochsToRemove: Set(), epochToModify: -1, newAmount: -1}
      val modifiedAll = {epoch: 7, valsToRemove: Set("alice", "bob"), valToModify: "", epochsToRemove: Set(), epochToModify: -1, newAmount: -1}
      val modifiedValidator = {epoch: 7, valsToRemove: Set("alice"), valToModify: "", epochsToRemove: Set(), epochToModify: -1, newAmount: -1}
      val modifiedValidatorPartial = {epoch: 7, valsToRemove: Set("alice", "bob"), valToModify: "bob", epochsToRemove: Set(1), epochToModify: -1, newAmount: -1}
      val modifiedEpochPartial = {epoch: 7, valsToRemove: Set("alice", "bob"), valToModify: "bob", epochsToRemove: Set(1, 4), epochToModify: 4, newAmount: 1}                           
      all {
        assert(computeNewRedelegatedUnbonds(redelegatedBonds, Set(), emptyModified) == Map()),
        assert(computeNewRedelegatedUnbonds(redelegatedBonds, Set(5), emptyModified) == Map(5 -> Map("alice" -> Map(2 -> 1, 4 -> 1), "bob" -> Map(1 -> 1, 4 -> 2)))),
        assert(computeNewRedelegatedUnbonds(redelegatedBonds, Set(5, 6), emptyModified) == Map(5 -> Map("alice" -> Map(2 -> 1, 4 -> 1), "bob" -> Map(1 -> 1, 4 -> 2)))),
        assert(computeNewRedelegatedUnbonds(redelegatedBonds, Set(5, 6), emptyModified) == Map(5 -> Map("alice" -> Map(2 -> 1, 4 -> 1), "bob" -> Map(1 -> 1, 4 -> 2)))),
        assert(computeNewRedelegatedUnbonds(redelegatedBonds, Set(5, 6), modifiedAll) == Map(5 -> Map("alice" -> Map(2 -> 1, 4 -> 1), "bob" -> Map(1 -> 1, 4 -> 2)),
                                                                                             7 -> Map("alice" -> Map(2 -> 1, 4 -> 1), "bob" -> Map(1 -> 1, 4 -> 2)))),
        assert(computeNewRedelegatedUnbonds(redelegatedBonds, Set(5, 6), modifiedValidator) == Map(5 -> Map("alice" -> Map(2 -> 1, 4 -> 1), "bob" -> Map(1 -> 1, 4 -> 2)),
                                                                                                   7 -> Map("alice" -> Map(2 -> 1, 4 -> 1)))),
        assert(computeNewRedelegatedUnbonds(redelegatedBonds, Set(5, 6), modifiedValidatorPartial) == Map(5 -> Map("alice" -> Map(2 -> 1, 4 -> 1), "bob" -> Map(1 -> 1, 4 -> 2)),
                                                                                                          7 -> Map("alice" -> Map(2 -> 1, 4 -> 1), "bob" -> Map(1 -> 1)))),
        assert(computeNewRedelegatedUnbonds(redelegatedBonds, Set(5, 6), modifiedEpochPartial) == Map(5 -> Map("alice" -> Map(2 -> 1, 4 -> 1), "bob" -> Map(1 -> 1, 4 -> 2)),
                                                                                                      7 -> Map("alice" -> Map(2 -> 1, 4 -> 1), "bob" -> Map(1 -> 1, 4 -> 1)))),                                                                                          
      }
    }

    // The function mergeBondsMap merges two maps of bonds from epoch to bond amount.
    // - @param map1 a map from epoch to int.
    // - @param map2 a map from epoch to int.
    // - @returns a map resulting from merging map1 and map2. If both maps have the same entry, the
    // resulting entry would be the sum of both.
    pure def mergeBondsMap(map1: Epoch -> int, map2: Epoch -> int): Epoch -> int = {
      map1.keys().union(map2.keys()).mapBy(e => if (map1.has(e) and map2.has(e)) map1.get(e) + map2.get(e)
                                                else if (map1.has(e)) map1.get(e) else map2.get(e))

    }

    run mergeBondsMapTest() = all {
      assert(mergeBondsMap(Map(), Map()) == Map()),
      assert(mergeBondsMap(Map(1 -> 2, 2 -> 3), Map()) == Map(1 -> 2, 2 -> 3)),
      assert(mergeBondsMap(Map(), Map(1 -> 2, 2 -> 3)) == Map(1 -> 2, 2 -> 3)),
      assert(mergeBondsMap(Map(1 -> 2, 2 -> 3), Map(3 -> 4, 4 -> 5)) == Map(1 -> 2, 2 -> 3, 3 -> 4, 4 -> 5)),
      assert(mergeBondsMap(Map(1 -> 2, 2 -> 3), Map(2 -> 4, 4 -> 5)) == Map(1 -> 2, 2 -> 7, 4 -> 5)),
    }

    // The function mergeRedelegatedBondsMap merges two RedelegatedBondsMap.
    // - @param map1 a RedelegatedBondsMap.
    // - @param map2 a RedelegatedBondsMap.
    // - @returns a RedelegatedBondsMap resulting from merging map1 and map2. If a given entry is in both maps, the
    // resulting map merges boths leveraging mergeBondsMap
    pure def mergeRedelegatedBondsMap(map1: RedelegatedBondsMap, map2: RedelegatedBondsMap): RedelegatedBondsMap = {
      map1.keys().union(map2.keys()).mapBy(src => if (map1.has(src) and map2.has(src)) mergeBondsMap( map1.get(src), map2.get(src))
                                                  else if (map1.has(src)) map1.get(src) else map2.get(src))

    }

    run mergeRedelegatedBondsMapTest = all {
      assert(mergeRedelegatedBondsMap(Map(), Map()) == Map()),
      assert(mergeRedelegatedBondsMap(Map("alice" -> Map(1 -> 2, 2 -> 3), "bob" -> Map(1 -> 2, 2 -> 3)), Map()) == Map("alice" -> Map(1 -> 2, 2 -> 3), "bob" -> Map(1 -> 2, 2 -> 3))),
      assert(mergeRedelegatedBondsMap(Map(), Map("alice" -> Map(1 -> 2, 2 -> 3), "bob" -> Map(1 -> 2, 2 -> 3))) == Map("alice" -> Map(1 -> 2, 2 -> 3), "bob" -> Map(1 -> 2, 2 -> 3))),
      assert(mergeRedelegatedBondsMap(Map("bob" -> Map(1 -> 2, 2 -> 3)), Map("alice" -> Map(1 -> 2, 2 -> 3))) == Map("alice" -> Map(1 -> 2, 2 -> 3), "bob" -> Map(1 -> 2, 2 -> 3))),
      assert(mergeRedelegatedBondsMap(Map("bob" -> Map(1 -> 2, 2 -> 3), "tom" -> Map(4 -> 3, 5 -> 6)), Map("tom" -> Map(4 -> 3, 7 -> 6), "alice" -> Map(1 -> 2, 2 -> 3))) == 
                                      Map("alice" -> Map(1 -> 2, 2 -> 3), "bob" -> Map(1 -> 2, 2 -> 3), "tom" -> Map(4 -> 6, 5 -> 6, 7 -> 6))),       
    }

    // The function updateRedelegatedBonded updates a map of redelegated bonds according to a modified bond record.
    // - @param redelegatedBonds a map of redelegated bonds.
    // - @param modified a ModifiedRedelegation record.
    // - @returns an updated map.
    pure def updateRedelegatedBondsMap(redelegatedBonds: RedelegatedBondsMap, modified: ModifiedRedelegation): RedelegatedBondsMap = {
      if (modified.valToModify == "") redelegatedBonds.mapRemoveSet(modified.valsToRemove)
      else {
        val updatedValsToRemoved = modified.valsToRemove.setRemove(modified.valToModify)
        if (modified.epochToModify == -1) redelegatedBonds.mapRemoveSet(updatedValsToRemoved).set(modified.valToModify, redelegatedBonds.get(modified.valToModify).mapRemoveSet(modified.epochsToRemove))
        else {
          val updatedEpochsToRemove = modified.epochsToRemove.setRemove(modified.epochToModify)
          val updatedValBonds = redelegatedBonds.get(modified.valToModify).mapRemoveSet(updatedEpochsToRemove).set(modified.epochToModify, modified.newAmount)
          redelegatedBonds.mapRemoveSet(updatedValsToRemoved).set(modified.valToModify, updatedValBonds)
        }
      }
    }

    run updateRedelegatedBondsMapTest = {
      val redelegatedBonds = Map("alice" -> Map(2 -> 1, 4 -> 1), "bob" -> Map(1 -> 1, 4 -> 2))
      val emptyModified = {epoch: -1, valsToRemove: Set(), valToModify: "", epochsToRemove: Set(), epochToModify: -1, newAmount: -1}
      val modifiedAll = {epoch: 7, valsToRemove: Set("alice", "bob"), valToModify: "", epochsToRemove: Set(), epochToModify: -1, newAmount: -1}
      val modifiedValidator = {epoch: 7, valsToRemove: Set("alice"), valToModify: "", epochsToRemove: Set(), epochToModify: -1, newAmount: -1}
      val modifiedValidatorPartial = {epoch: 7, valsToRemove: Set("alice", "bob"), valToModify: "bob", epochsToRemove: Set(1), epochToModify: -1, newAmount: -1}
      val modifiedEpochPartial = {epoch: 7, valsToRemove: Set("alice", "bob"), valToModify: "bob", epochsToRemove: Set(1, 4), epochToModify: 4, newAmount: 1}  
      all {
        assert(updateRedelegatedBondsMap(redelegatedBonds, emptyModified) == redelegatedBonds),
        assert(updateRedelegatedBondsMap(redelegatedBonds, modifiedAll) == Map()),
        assert(updateRedelegatedBondsMap(redelegatedBonds, modifiedValidator) == Map("bob" -> Map(1 -> 1, 4 -> 2))),
        assert(updateRedelegatedBondsMap(redelegatedBonds, modifiedValidatorPartial) == Map("bob" -> Map(4 -> 2))),
        assert(updateRedelegatedBondsMap(redelegatedBonds, modifiedEpochPartial) == Map("bob" -> Map(4 -> 1))),
      }
    }

    // The function updateRedelegatedUnbonded updates an entry of a delegator's redelegated unbonded map.
    // - @param existing a map of redelegated unbonds from starting bonded epoch and ending bonded epoch to RedelegatedBondsMap.
    // - @param redelegatedUnbonds a map from bond starting epoch to RedelegatedBondsMap.
    // - @param end the epoch at which the redelegated bonds being added are withdrawable.
    // - @returns an updated map that includes redelegatedUnbonds.
    pure def updateRedelegatedUnbonded(existing: (Epoch, Epoch) -> RedelegatedBondsMap, redelegatedUnbonds: Epoch -> RedelegatedBondsMap, end: Epoch): (Epoch, Epoch) -> RedelegatedBondsMap = {
      val newTuples =  tuples(redelegatedUnbonds.keys(), Set(end))
      val existingTuples = existing.keys()
      existingTuples.union(newTuples).mapBy(pair => val start = pair._1
                                                    if (pair.in(existingTuples) and pair.in(newTuples)) mergeRedelegatedBondsMap(existing.get(pair), redelegatedUnbonds.get(start))
                                                    else if (pair.in(existingTuples)) existing.get(pair) else redelegatedUnbonds.get(start))
    }

    run updateRedelegatedUnbondedTest = {
      val existing = Map((2, 6) -> Map("alice" -> Map(1 -> 2, 3 -> 4), "bob" -> Map(1 -> 2, 3 -> 4)),
                         (2, 5) -> Map("alice" -> Map(1 -> 2, 3 -> 4)),
                         (3, 6) -> Map("bob" -> Map(1 -> 2, 3 -> 4)))
      all {
        assert(updateRedelegatedUnbonded(Map(),Map(), 6) == Map()),
        assert(updateRedelegatedUnbonded(existing, Map(), 6) == existing ),
        assert(updateRedelegatedUnbonded(Map(), Map(2 -> Map("alice" -> Map(1 -> 2, 3 -> 4), "bob" -> Map(1 -> 2, 3 -> 4))), 6) ==
                                         Map((2, 6) -> Map("alice" -> Map(1 -> 2, 3 -> 4), "bob" -> Map(1 -> 2, 3 -> 4)))),
        assert(updateRedelegatedUnbonded(existing, Map(2 -> Map("alice" -> Map(1 -> 2, 3 -> 4), "bob" -> Map(1 -> 2, 3 -> 4))), 6) ==
                                         Map((2, 6) -> Map("alice" -> Map(1 -> 4, 3 -> 8), "bob" -> Map(1 -> 4, 3 -> 8)),
                                             (2, 5) -> Map("alice" -> Map(1 -> 2, 3 -> 4)),
                                             (3, 6) -> Map("bob" -> Map(1 -> 2, 3 -> 4)))),
      }
    }

    // The function updateTotalRedelegatedUnbonded updates an entry of a delegator's total redelegated unbonded map.
    // - @param existing a map of total redelegated unbonds from starting bonded epoch and source validator to a map of bonds.
    // - @param redelegatedUnbonds a set of redelegated unbonds.
    // - @returns an updated map that includes redelegatedUnbonds.
    pure def updateTotalRedelegatedUnbonded(existing: Epoch -> RedelegatedBondsMap, new: Epoch -> RedelegatedBondsMap): Epoch -> RedelegatedBondsMap = {
      existing.keys().union(new.keys()).mapBy(e => if (existing.has(e) and new.has(e)) mergeRedelegatedBondsMap(existing.get(e), new.get(e))
                                                   else if (existing.has(e)) existing.get(e) else new.get(e))
    }

    run updateTotalRedelegatedUnbondedTest = {
      val existing = Map(2 -> Map("alice" -> Map(1 -> 2, 3 -> 4), "bob" -> Map(1 -> 2, 3 -> 4)),
                         3 -> Map("alice" -> Map(1 -> 2, 3 -> 4)))
      all {
        assert(updateTotalRedelegatedUnbonded(Map(), Map()) == Map()),
        assert(updateTotalRedelegatedUnbonded(existing, Map()) == existing),
        assert(updateTotalRedelegatedUnbonded(Map(), Map(2 -> Map("alice" -> Map(1 -> 2, 3 -> 4), "bob" -> Map(1 -> 2, 3 -> 4)))) ==
                                              Map(2 -> Map("alice" -> Map(1 -> 2, 3 -> 4), "bob" -> Map(1 -> 2, 3 -> 4)))),
        assert(updateTotalRedelegatedUnbonded(existing, Map(2 -> Map("alice" -> Map(1 -> 2, 3 -> 4), "bob" -> Map(1 -> 2, 3 -> 4)))) ==
                                              Map(2 -> Map("alice" -> Map(1 -> 4, 3 -> 8), "bob" -> Map(1 -> 4, 3 -> 8)),
                                                  3 -> Map("alice" -> Map(1 -> 2, 3 -> 4))))
      }
    }

    // The function mergeOutgoingRedelegations updates a validators's outgoing redelegations variable.
    // - @param existing a map of outgoing redelegations.
    // - @param new a new outgoing redelegation.
    // - @param curEpoch the current epoch
    // - @returns an updated map that includes new.
    pure def mergeOutgoingRedelegations(existing: (Epoch, Epoch) -> int, new: Epoch -> int, curEpoch: Epoch): (Epoch, Epoch) -> int = {
      val newTuples = tuples(new.keys(), Set(curEpoch))
      existing.keys().union(newTuples).mapBy(pair => val start = pair._1
                                                     if (existing.has(pair) and pair.in(newTuples)) existing.get(pair) + new.get(start)
                                                     else if (existing.has(pair)) existing.get(pair)
                                                          else new.get(start))
    }

    run mergeOutgoingRedelegationsTest = {
      val existing = Map((2, 6) -> 4,
                         (2, 5) -> 6,
                         (3, 6) -> 3)
      all {
        assert(mergeOutgoingRedelegations(Map(),Map(), 6) == Map()),
        assert(mergeOutgoingRedelegations(existing, Map(), 6) == existing ),
        assert(mergeOutgoingRedelegations(Map(), Map(2 -> 5), 6) == Map((2, 6) -> 5)),
        assert(mergeOutgoingRedelegations(existing, Map(2 -> 5), 6) == Map((2, 6) -> 9, (2, 5) -> 6, (3, 6) -> 3))
      }
    }

    // **************************************************************************
    // Slashing helper functions
    // ************************************************************************* 

    // The function computeSlashableAmount computes how much is left from a bond or unbond after applying a slash given that a set of slashes may have been
    // previously applied.
    // - @param slash the slash record to be applied.
    // - @param initAmount the tokens to be slashed.
    // - @param computeSlashes a map from misbehaving epoch to already computed slashable amount.
    // - @returns an integer with the amount that remains after applying slash constraint to computeSlashes.
    pure def computeSlashableAmount(slash: Slash, initAmount: int, computedSlashes: Epoch -> int): int = {
      val updatedAmount = computedSlashes.keys().filter(x => x + slashProcessingDelay < slash.epoch)
                                                .fold(initAmount, (acc, e) => max(0, acc - computedSlashes.get(e)))
      updatedAmount*slash.rate
    }

    run computeSlashableAmountTest = {
      val initEpoch = 2
      all {
        assert(computeSlashableAmount({epoch: initEpoch + UNBONDING_OFFSET + CUBIC_OFFSET, rate: 1}, 100, Map()) == 100),
        assert(computeSlashableAmount({epoch: initEpoch + UNBONDING_OFFSET + CUBIC_OFFSET + 1, rate: 1}, 100, Map(initEpoch -> 50)) == 50),
        assert(computeSlashableAmount({epoch: initEpoch + UNBONDING_OFFSET + CUBIC_OFFSET, rate: 1}, 100, Map(initEpoch -> 50)) == 100)
      }
    }

    // The function applyListSlashes computes how much remains from an amount of tokens after applying a list of slashes.
    // - @param listSlashes a list of slashes ordered by misbehaving epoch.
    // - @param amount the amount of slashable tokens.
    // - @returns an integer with the amount that remains after applying the list of slashes.
    pure def applyListSlashes(listSlashes: List[Slash], amount: int): int = {
      listSlashes.foldl({finalAmount: amount, computedSlashes: Map()}, (acc, slash) => val slashAmount = computeSlashableAmount(slash, amount, acc.computedSlashes)
                                                                                       {finalAmount: max(0, acc.finalAmount - slashAmount),
                                                                                        computedSlashes: acc.computedSlashes.mapSafeSet(slash.epoch, slashAmount)}).finalAmount
    }

    run applyListSlashesTest = {
      val initEpoch = 2
      val list1 = [{epoch: initEpoch, rate: 1}]
      val list2 = [{epoch: initEpoch, rate: 1}, {epoch: initEpoch+UNBONDING_OFFSET+CUBIC_OFFSET+1, rate: 1} ]
      val list3 = [{epoch: initEpoch, rate: 1},
                   {epoch: initEpoch, rate: 1}]
      val list4 = [{epoch: initEpoch, rate: 1},
                   {epoch: initEpoch, rate: 1},
                   {epoch: initEpoch+UNBONDING_OFFSET+CUBIC_OFFSET+1, rate: 1} ]
      all {
        assert(applyListSlashes([], 100) == 100),
        assert(applyListSlashes(list1, 100) == 0),
        assert(applyListSlashes(list2, 100) == 0),
        assert(applyListSlashes(list3, 100) == 0),
        assert(applyListSlashes(list4, 100) == 0)
      }
    }

    // The function nextSlash compares the slash at the head of two lists and returns the one with smaller
    // misbheaving epoch. It assumes that at least one list has an element.
    // - @param list1 a list of slashes ordered by misbehaving epoch.
    // - @param list2 a second list of slashes ordered by misbehaving epoch.
    // - @returns the slash at the head of any of the lists with smaller misbheaving epoch.

    pure def nextSlash(list1: List[Slash], list2: List[Slash]): (Slash, List[Slash], List[Slash]) = {
      if (list1 == List()) (head(list2), list1, tail(list2))
      else if (list2 == List()) (head(list1), tail(list1), list2)
           else if (head(list1).epoch <= head(list2).epoch) (head(list1), tail(list1), list2)
                else (head(list2), list1, tail(list2))
    }
    
    run nextSlashTest = {
      val slash = {epoch: 0, rate: 1}
      val list1 = [slash.with("epoch", 1),
                   slash.with("epoch", 6),
                   slash.with("epoch", 9)]
      val list2 = [slash.with("epoch", 2),
                   slash.with("epoch", 6),
                   slash.with("epoch", 8)]
      all {
        assert(nextSlash(List(), List(slash.with("epoch", 1))) == (slash.with("epoch", 1), List(), List())),
        assert(nextSlash(List(slash.with("epoch", 1)), List()) == (slash.with("epoch", 1), List(), List()))
      }
    }

    // The function mergeListSlashes merges two lists of slashes ordered by misbehaving epoch.
    // - @param list1 a list of slashes ordered by misbehaving epoch.
    // - @param list2 a second list of slashes ordered by misbehaving epoch.
    // - @returns a third list of slashes including all elements in both imput lists ordered by misbehaving epoch.
    pure def mergeListSlashes(list1: List[Slash], list2: List[Slash]): List[Slash] = {
      val sumLength = length(list1) + length(list2)
      if (sumLength == 0) List()
      else 1.to(sumLength).fold(([], list1, list2), (acc, _) => val result = nextSlash(acc._2, acc._3)
                                                                (acc._1.append(result._1), result._2, result._3))._1
    }

    run mergeListSlashesTest = all {
      val slash = {epoch: 0, rate: 1}
      val list1 = [slash.with("epoch", 1),
                   slash.with("epoch", 6),
                   slash.with("epoch", 9)]
      val list2 = [slash.with("epoch", 2),
                   slash.with("epoch", 6),
                   slash.with("epoch", 8)]
      val resultMerge = [slash.with("epoch", 1),
                         slash.with("epoch", 2),
                         slash.with("epoch", 6),
                         slash.with("epoch", 6),
                         slash.with("epoch", 8),
                         slash.with("epoch", 9)]
      all {
        assert(mergeListSlashes(list1, list2) == resultMerge),
        assert(mergeListSlashes(list2, list1) == resultMerge),
        assert(mergeListSlashes(List(), List()) == List()),
        assert(mergeListSlashes(list1, List()) == list1),
        assert(mergeListSlashes(List(), list2) == list2)
      }
    }
    
    // The function foldAndSlashRedelegatedBondsMap iterates over a RedelegatedBondsMap and computes the both the sum of all rdelegated tokens and
    //  how much is left after applying all relevant slashes.
    // - @param bonds a RedelegatedBondsMap.
    // - @param start the epoch at which the redelegated bonds were effectively bonded.
    // - @param listSlashes a list of slashes to be applied to the redelegated bonds.
    // - @param slashes a map from validator address to list of slashes.
    // - @returns the total amount of redelegated tokens and the total amount after slashing.
    pure def foldAndSlashRedelegatedBondsMap(bonds: RedelegatedBondsMap, start: Epoch, listSlashes: List[Slash], slashes: Address -> List[Slash]): {totalRedelegated: int, totalAfterSlashing: int} = {
      bonds.keys().fold({totalRedelegated: 0, totalAfterSlashing: 0},
                        (accSrc, src) => bonds.get(src).keys().fold(accSrc,
                                                                    (accEpoch, redBondStart) => val selectList = slashes.get(src).select(slash => inRedelegationSlashingWindow(slash.epoch, startRedelegationFromEnd(start), start) and
                                                                                                                                                  redBondStart <= slash.epoch)
                                                                                                val mergedList = mergeListSlashes(listSlashes, selectList)
                                                                                                {totalRedelegated: accEpoch.totalRedelegated + bonds.get(src).get(redBondStart),
                                                                                                totalAfterSlashing: accEpoch.totalAfterSlashing + applyListSlashes(mergedList, bonds.get(src).get(redBondStart))}))
    }

    run foldAndSlashRedelegatedBondsMapTest = {
      val allValidators = Set("alice", "bob")
      val start = 7
      val redelegatedBonds = Map("alice" -> Map(2 -> 1, 4 -> 1), "bob" -> Map(1 -> 1, 4 -> 2))
      all {
        assert(foldAndSlashRedelegatedBondsMap(redelegatedBonds, start, List(), allValidators.mapBy(x => List())) == {totalRedelegated: 5, totalAfterSlashing: 5}),
        assert(foldAndSlashRedelegatedBondsMap(redelegatedBonds, start, List({epoch: 0, rate: 1}), allValidators.mapBy(x => List())) == {totalRedelegated: 5, totalAfterSlashing: 0}),
        assert(foldAndSlashRedelegatedBondsMap(redelegatedBonds, start, List(), allValidators.mapBy(x => if (x=="alice") List({epoch: 6, rate: 1}) else List())) == {totalRedelegated: 5, totalAfterSlashing: 3}),
      }
    }

    // The function computeAmountAfterSlashingUnbond computes from a set of unbonds (both redelegated and not) how much is left after applying all relevant
    // slashes.
    // - @param unbonds a set of unbonds: a map from bond starting epoch and unbond ending epoch to amount of tokens.
    // - @param redelegatedUnbonds a set of redelegated unbonds: a map from bonds tarting epoch to RedelegatedBondsMap.
    // - @param validator the address of the validator from which the the bonds have been unbonded.
    // - @param slashes a map from validator address to list of slashes.
    // - @returns the total amount after slashing and a map from bond starting epoch to amount after slashing.
    pure def computeAmountAfterSlashingUnbond(unbonds: (Epoch, Epoch) -> int, redelegatedUnbonds: Epoch -> RedelegatedBondsMap, validator: Address, slashes: Address -> List[Slash]): {sum: int, epochMap: Epoch -> int} = {
      val initMap = unbonds.keys().map(pair => pair._1).mapBy(e => 0)
      unbonds.keys().fold({sum: 0, epochMap: initMap}, (acc, unbondKey) => val start = unbondKey._1
                                                                           val listSlashes = slashes.get(validator).select(slash => start <= slash.epoch)
                                                                           val resultFold = if (redelegatedUnbonds.has(start)) foldAndSlashRedelegatedBondsMap(redelegatedUnbonds.get(start), start, listSlashes, slashes)
                                                                                            else {totalRedelegated: 0, totalAfterSlashing: 0}
                                                                           val totalNoRedelegated = unbonds.get(unbondKey) - resultFold.totalRedelegated
                                                                           val afterNoRedelegated = applyListSlashes(listSlashes, totalNoRedelegated)
                                                                           val amountAfterSlashing = afterNoRedelegated + resultFold.totalAfterSlashing
                                                                           {sum: acc.sum + amountAfterSlashing,
                                                                            epochMap: acc.epochMap.set(start, amountAfterSlashing)})
    }
    
    run computeAmountAfterSlashingUnbondTest = {
      val allValidators = Set("alice", "bob")
      val unbonds = Map((2, 6) -> 5, (4, 6) -> 6)
      val redelegatedBonds = Map(2 -> Map("alice" -> Map(1 -> 1)))
      all {
        assert(computeAmountAfterSlashingUnbond(unbonds, redelegatedBonds, "bob", allValidators.mapBy(x => List())) == {sum: 11, epochMap: Map(2 -> 5, 4 -> 6)}),
        assert(computeAmountAfterSlashingUnbond(unbonds, redelegatedBonds, "bob", allValidators.mapBy(x => if (x=="bob") List({epoch: 5, rate: 1}) else List())) == {sum: 0, epochMap: Map(2 -> 0, 4 -> 0)}),
        assert(computeAmountAfterSlashingUnbond(unbonds, redelegatedBonds, "bob", allValidators.mapBy(x => if (x=="alice") List({epoch: 0, rate: 1}) else List())) == {sum: 11, epochMap: Map(2 -> 5, 4 -> 6)}),
        assert(computeAmountAfterSlashingUnbond(unbonds, redelegatedBonds, "bob", allValidators.mapBy(x => if (x=="alice") List({epoch: 1, rate: 1}) else List())) == {sum: 10, epochMap: Map(2 -> 4, 4 -> 6)})
      }
    }

    // The function computeAmountAfterSlashingWithdraw computes from a set of unbonds (both redelegated and not) how much is left after applying all relevant
    // slashes.
    // - @param unbonds a set of unbonds: a map from bond starting epoch and unbond ending epoch to amount of tokens.
    // - @param redelegatedUnbonds a set of redelegated unbonds: a map from bonds tarting epoch to RedelegatedBondsMap.
    // - @param validator the address of the validator from which the the bonds have been unbonded.
    // - @param slashes a map from validator address to list of slashes.
    // - @returns the total amount after slashing and a map from bond starting epoch to amount after slashing.
    pure def computeAmountAfterSlashingWithdraw(unbonds: (Epoch, Epoch) -> int, redelegatedUnbonds: (Epoch, Epoch) -> RedelegatedBondsMap, validator: Address, slashes: Address -> List[Slash]): {sum: int, epochMap: Epoch -> int} = {
      val initMap = unbonds.keys().map(pair => pair._1).mapBy(e => 0)
      unbonds.keys().fold({sum: 0, epochMap: initMap}, (acc, unbondKey) => val start = unbondKey._1
                                                                           val end = unbondKey._2
                                                                           val listSlashes = slashes.get(validator).select(slash => start <= slash.epoch and
                                                                                                                           end - UNBONDING_OFFSET - CUBIC_OFFSET > slash.epoch)
                                                                           val resultFold = if (redelegatedUnbonds.has(unbondKey)) foldAndSlashRedelegatedBondsMap(redelegatedUnbonds.get(unbondKey), start, listSlashes, slashes)
                                                                                            else {totalRedelegated: 0, totalAfterSlashing: 0}
                                                                           val totalNoRedelegated = unbonds.get(unbondKey) - resultFold.totalRedelegated
                                                                           val afterNoRedelegated = applyListSlashes(listSlashes, totalNoRedelegated)
                                                                           val amountAfterSlashing = afterNoRedelegated + resultFold.totalAfterSlashing
                                                                           {sum: acc.sum + amountAfterSlashing,
                                                                            epochMap: acc.epochMap.set(start, amountAfterSlashing)})
    }

    run computeAmountAfterSlashingWithdrawTest = {
      val allValidators = Set("alice", "bob")
      val unbonds = Map((2, 20) -> 5, (4, 20) -> 6)
      val redelegatedBonds = Map((2, 20) -> Map("alice" -> Map(1 -> 1)))
      all {
        assert(computeAmountAfterSlashingWithdraw(unbonds, redelegatedBonds, "bob", allValidators.mapBy(x => List())) == {sum: 11, epochMap: Map(2 -> 5, 4 -> 6)}),
        assert(computeAmountAfterSlashingWithdraw(unbonds, redelegatedBonds, "bob", allValidators.mapBy(x => if (x=="bob") List({epoch: 5, rate: 1}) else List())) == {sum: 0, epochMap: Map(2 -> 0, 4 -> 0)}),
        assert(computeAmountAfterSlashingWithdraw(unbonds, redelegatedBonds, "bob", allValidators.mapBy(x => if (x=="alice") List({epoch: 0, rate: 1}) else List())) == {sum: 11, epochMap: Map(2 -> 5, 4 -> 6)}),
        assert(computeAmountAfterSlashingWithdraw(unbonds, redelegatedBonds, "bob", allValidators.mapBy(x => if (x=="alice") List({epoch: 1, rate: 1}) else List())) == {sum: 10, epochMap: Map(2 -> 4, 4 -> 6)})
      }
    }

    // The function computeTotalUnbonded computes the total amount of tokens unbonded from a validator that were contributing to the validator's stake when this misbehaved at
    // a previous epoch, after applying a set of relevant slashes.
    // - @param validator the misbehaving validator's address.
    // - @param infractionEpoch the epoch at which the validator misbehaved.
    // - @param slashes a map from validator address to a list of already processed slashes.
    // - @param totalUnbonded a map of bonds from epoch to amount of tokens from which the final amount is computed.
    // - @param totalRedelegatedUnbonded a map of redelegated bonds from epoch to RedelegatedBondsMap.
    // - @returns an integer with the amount of tokens that were contributing to the validator at the misbehaving epoch that have been unbonded.
    pure def computeTotalUnbonded(validator: Address, infractionEpoch: Epoch, slashes: Address -> List[Slash], totalUnbonded: Epoch -> int, totalRedelegatedUnbonded: Epoch -> RedelegatedBondsMap): int = {
      val epochs = totalUnbonded.keys().filter(e => e <= infractionEpoch and totalUnbonded.get(e) > 0)
      epochs.fold(0, (sum, e) => val listSlashes = slashes.get(validator).select(s => e <= s.epoch and s.epoch + slashProcessingDelay < infractionEpoch)
                                 val filteredSlashMap = slashes.keys().mapBy(v => slashes.get(v).select(s => s.epoch + slashProcessingDelay < infractionEpoch))
                                 val resultFold = if (totalRedelegatedUnbonded.has(e)) foldAndSlashRedelegatedBondsMap(totalRedelegatedUnbonded.get(e), e, listSlashes, filteredSlashMap)
                                                  else {totalRedelegated: 0, totalAfterSlashing: 0}
                                 val totalNoRedelegated = totalUnbonded.get(e) - resultFold.totalRedelegated
                                 val afterNoRedelegated = applyListSlashes(listSlashes, totalNoRedelegated)
                                 val amountAfterSlashing = afterNoRedelegated + resultFold.totalAfterSlashing
                                 sum + amountAfterSlashing)
    }

    run computeTotalUnbondedTest = {
      val allValidators = Set("alice", "bob")
      val totalUnbonded = Map(2 -> 5, 8 -> 20)
      val totalRedelegateUnbonded = Map(8 -> Map("bob" -> Map(4 -> 10)))
      all {
        assert(computeTotalUnbonded("alice", 10, allValidators.mapBy(v => List()), totalUnbonded, totalRedelegateUnbonded) == 25),
        assert(computeTotalUnbonded("alice", 7, allValidators.mapBy(v => List()), totalUnbonded, totalRedelegateUnbonded) == 5),
        assert(computeTotalUnbonded("alice", 10, allValidators.mapBy(v => if (v == "alice") List({epoch: 2, rate: 1}) else List()), totalUnbonded, totalRedelegateUnbonded) == 20),
        assert(computeTotalUnbonded("alice", 10, allValidators.mapBy(v => if (v == "alice") List({epoch: 2, rate: 1}) else List({epoch: 4, rate: 1})), totalUnbonded, totalRedelegateUnbonded) == 10),
      }
    }
    // The function foldBondsMap computes the total amount of tokens in a map of bonds.
    // - @param bonds a map of bonds from epoch to amount of tokens.
    // - @returns the sum of all bonds.
    pure def foldBondsMap(bonds: Epoch -> int): int = {
      bonds.keys().fold(0, (sum, e) => sum + bonds.get(e))
    }

    run foldBondsMapTest = all {
      assert(foldBondsMap(Map()) == 0),
      assert(foldBondsMap(Map(5 -> 6)) == 6),
      assert(foldBondsMap(Map(5 -> 6, 7 -> 8)) == 14),
    }

    // The function foldRedelegatedBondsMap computes the total amount of redelegated tokens in a RedelegatedBondsMap.
    // - @param redelegatedBonds a RedelegatedBondsMap map.
    // - @returns the sum of all redelegated tokens.
    pure def foldRedelegatedBondsMap(redelegatedBonds: RedelegatedBondsMap): int = {
      redelegatedBonds.keys().fold(0, (sum, src) => sum + redelegatedBonds.get(src).foldBondsMap())
    }

    run foldRedelegatedBondsMapTest = all {
      assert(foldRedelegatedBondsMap(Map()) == 0),
      assert(foldRedelegatedBondsMap(Map("alice" -> Map(5 -> 6))) == 6),
      assert(foldRedelegatedBondsMap(Map("alice" -> Map(5 -> 6, 6 -> 8))) == 14),
      assert(foldRedelegatedBondsMap(Map("alice" -> Map(5 -> 6, 6 -> 8), "bob" -> Map(3 -> 7))) == 21),
    }

    // The function minSlashRate returns a slash rate depending on the type of infraction.
    // - @param infraction a string identifying the type of infraction.
    // - @returns a Dec representing the slash rate
    pure def minSlashRate(infraction: str): Dec = {
      if (infraction == "duplicate_vote") DUPLICATE_RATE else LIGHT_RATE
    }

    // The function computeFinalRate computes a slash rate based on a set of slashes
    // - @param setSlashes a set of slashes
    // - @returns an integer representing the slash rate
    pure def computeFinalRate(setInfractions: Set[Infraction]): int = {
      1
    } 

    // The function hasRedelegation checks whether a map of redelegations contains a given redelegation.
    // - @param mapRedelegations a map of redelegations from epoch to RedelegatedBondsMap.
    // - @param redBondStart the epoch at which the redelegated bonds started contributing the destination validator. We also say the end of the redelegation.
    // - @param validator the address of the source validator.
    // - @param bondStart the epoch at which the tokens started contributing at the source validator.
    // - @returns true if the mapRedelegations contains the redelegation defined by redBondStart, validator and bondStart; it returns false otherwise.
    pure def hasRedelegation(mapRedelegations: Epoch -> RedelegatedBondsMap, redBondStart: Epoch, validator: Address, bondStart: Epoch): bool = {
      if (mapRedelegations.has(redBondStart))
        if (mapRedelegations.get(redBondStart).has(validator)) 
          if (mapRedelegations.get(redBondStart).get(validator).has(bondStart)) true
          else false
        else false
      else false
    }

    
    run hasRedelegationTest = {
      val mapRedelegations = Map(4 -> Map("alice" -> Map(2 -> 6, 3 -> 7)), 6 -> Map("bob" -> Map(1 -> 8)))
      all {
        assert(hasRedelegation(Map(), 4, "alice", 3) == false),
        assert(hasRedelegation(mapRedelegations, 4, "alice", 3) == true),
        assert(hasRedelegation(mapRedelegations, 4, "alice", 4) == false),
        assert(hasRedelegation(mapRedelegations, 4, "bob", 3) == false),
        assert(hasRedelegation(mapRedelegations, 6, "alice", 3) == false),
      }
    }

    // The function computeRemainderRedelegation takes a redelegation record and computes how many tokens are left from the redelegation at the destination validator considering 
    // that the source validator may have misbehaved while the redelegated tokens were contributing to its stake and that some may have unbonded from the destination
    // validator. The function computes the how much is left at the destination validator at epochs from curEpoch + 1 to curEpoch + PIPELINE_LENGTH.
    // - @param redelegation a Redelegation record.
    // - @param curEpoch the the current epoch.
    // - @param slashes a list of slashes of the source validator.
    // - @param totalRedelegatedUnbonded a map from epoch to unbonded redelegated tokens.
    // - @param balanceMap a map from epoch to stake. It accumulates how much stake is left at a given epoch from all already processed redelegation records.
    // - @returns an updated balanceMap resulting from processing redelegation.
    pure def computeRemainderRedelegation(redelegation: Redelegation,
                                          curEpoch: Epoch,
                                          slashes: List[Slash],
                                          totalRedelegatedUnbonded: Epoch -> Epoch -> RedelegatedBondsMap,
                                          balanceMap: Epoch -> int): Epoch -> int = {
      // We must iterate in epoch increasing order.
      val epochRange = range(redelegation.redBondStart, curEpoch+PIPELINE_OFFSET+1)
      epochRange.foldl((0, balanceMap), (acc, e) => val updatedTotalUnbonded = if (not(totalRedelegatedUnbonded.get(e).hasRedelegation(redelegation.redBondStart, redelegation.srcValidator, redelegation.bondStart))) acc._1
                                                                               else acc._1 + totalRedelegatedUnbonded.get(e).get(redelegation.redBondStart).get(redelegation.srcValidator).get(redelegation.bondStart)
                                                    if (e <= curEpoch) (updatedTotalUnbonded, acc._2)
                                                    else {
                                                    val stakeLeft = val listSlashes = slashes.select(s => inRedelegationSlashingWindow(s.epoch, startRedelegationFromEnd(redelegation.redBondStart), redelegation.redBondStart) and
                                                                                                          redelegation.bondStart <= s.epoch)
                                                                    applyListSlashes(listSlashes, redelegation.amount - updatedTotalUnbonded)
                                                    (updatedTotalUnbonded, acc._2.set(e, acc._2.get(e) + stakeLeft))})._2                                                                                                             
    }

    run computeRemainderRedelegationTest = {
      val emptyRedelegatedTotalUnbonded = Map(5 -> Map(), 6 -> Map(), 7 -> Map(), 8 -> Map(), 9 -> Map(), 10 -> Map())
      val redelegation = {redBondStart: 8, srcValidator: "alice", bondStart: 5, amount: 10}
      all {
        assert(computeRemainderRedelegation(redelegation, 8, [], emptyRedelegatedTotalUnbonded, Map(9 -> 0, 10 -> 0)) == Map(9 -> 10, 10 -> 10)),
        assert(computeRemainderRedelegation(redelegation, 8, [{epoch: 4, rate: 1}], emptyRedelegatedTotalUnbonded, Map(9 -> 0, 10 -> 0)) == Map(9 -> 10, 10 -> 10)),
        assert(computeRemainderRedelegation(redelegation, 8, [{epoch: 4, rate: 1}], emptyRedelegatedTotalUnbonded, Map(9 -> 5, 10 -> 4)) == Map(9 -> 15, 10 -> 14)),
        assert(computeRemainderRedelegation(redelegation, 8, [{epoch: 5, rate: 1}], emptyRedelegatedTotalUnbonded, Map(9 -> 0, 10 -> 0)) == Map(9 -> 0, 10 -> 0)),
        assert(computeRemainderRedelegation(redelegation, 8, [{epoch: 5, rate: 1}, {epoch: 6, rate: 1}], emptyRedelegatedTotalUnbonded, Map(9 -> 0, 10 -> 0)) == Map(9 -> 0, 10 -> 0)),
        assert(computeRemainderRedelegation(redelegation, 8, [], emptyRedelegatedTotalUnbonded.set(8, Map(8 -> Map("bob" -> Map(5 -> 8)))), Map(9 -> 0, 10 -> 0)) == Map(9 -> 10, 10 -> 10)),
        assert(computeRemainderRedelegation(redelegation, 8, [], emptyRedelegatedTotalUnbonded.set(8, Map(8 -> Map("alice" -> Map(5 -> 8)))), Map(9 -> 0, 10 -> 0)) == Map(9 -> 2, 10 -> 2)),
        assert(computeRemainderRedelegation(redelegation, 8, [], emptyRedelegatedTotalUnbonded.set(10, Map(8 -> Map("alice" -> Map(5 -> 8)))), Map(9 -> 0, 10 -> 0)) == Map(9 -> 10, 10 -> 2)),
      }
    }

    // The computeBondAtEpoch function computes how much is left from a bond after applying a set of slashes.
    // - @param epoch an epoch upper-bound that determines which slashes are included: those that were processed before.
    // - @param start the epoch at which the bond started.
    // - @param amount the bonded amount.
    // - @param redelegatedBond a RedelegatedBondsMap.
    // - @param validator the address of the bonding validator.
    // - @param slashes a map from address validator to a list of slashes.
    // - @returns the amount of tokens left after slashing.
    pure def computeBondAtEpoch(epoch: Epoch, start: Epoch, amount: int, redelegatedBond: RedelegatedBondsMap, validator: Address, slashes: Address -> List[Slash]): int = {
       val listSlashes = slashes.get(validator).select(s => start <= s.epoch and s.epoch + slashProcessingDelay < epoch)
       val filteredSlashMap = slashes.keys().mapBy(v => slashes.get(v).select(s => s.epoch + slashProcessingDelay < epoch))
       val resultFold = foldAndSlashRedelegatedBondsMap(redelegatedBond, start, listSlashes, filteredSlashMap)
       val totalNoRedelegated = amount - resultFold.totalRedelegated
       val afterNoRedelegated = applyListSlashes(listSlashes, totalNoRedelegated)
       afterNoRedelegated + resultFold.totalAfterSlashing
    }

    run computeBondAtEpochTest = {
      all {
        // no previous slashes and no redelegations
        assert(computeBondAtEpoch(12, 3, 23, Map(), "bob", Map("alice" -> [], "bob" -> [])) == 23),
        // no redelegation, one previous slash
        assert(computeBondAtEpoch(12, 3, 23, Map(), "bob", Map("alice" -> [], "bob" -> [{ epoch: 4, rate: 1 }])) == 0),
        // redelegation but no slashes for that validator, also no slash for main validator
        assert(computeBondAtEpoch(12, 3, 23, Map("alice" -> Map(1 -> 5)), "bob", Map("alice" -> [], "bob" -> [])) == 23),
        // redelegation but no slashes for that validator, but slash for the main validator
        assert(computeBondAtEpoch(12, 3, 23, Map("alice" -> Map(1 -> 5)), "bob", Map("alice" -> [], "bob" -> [{ epoch: 4, rate: 1 }])) == 0),
        // redelegation with slash for that source validator out of the slashing window [4, 6), no slash for the dest validator
        assert(computeBondAtEpoch(12, 3, 23, Map("alice" -> Map(1 -> 5)), "bob", Map("alice" -> [{ epoch: 6, rate: 1 }], "bob" -> [])) == 23),
        // redelegation with slash for that source validator within the slashing window [4, 6), no slash for the dest validator
        assert(computeBondAtEpoch(18, 9, 23, Map("alice" -> Map(1 -> 5)), "bob", Map("alice" -> [{ epoch: 4, rate: 1 }], "bob" -> [])) == 18),
      }
    }
    
    // Given a slash and epoch, the computeSlashBondAtEpoch function computes how much can be slashed from the bond at the considered epoch
    // considering that the bond might have been already slashed.
    // for the same stake.
    // - @param epoch the epoch at which we want to compute the slashable amount for.
    // - @param infractionEpoch the slash infraction epoch.
    // - @param bondStart the epoch at which the bond started.
    // - @param bondAmount the bonded amount.
    // - @param redelegatedBond a RedelegatedBondsMap to consider when computing how much is left.
    // = @param slashRate the slash final rate.
    // - @param validator the address of the bonding validator.
    // - @param slashes a map from address validator to a list of slashes.
    // - @returns the amount of tokens that can be slashed at the given epoch.
    pure def computeSlashBondAtEpoch(epoch: Epoch, infractionEpoch: Epoch, bondStart: Epoch, bondAmount: int, redelegatedBond: RedelegatedBondsMap, slashRate: int, validator: Address, slashes: Address -> List[Slash]): int = {
      val AmountDue = computeBondAtEpoch(infractionEpoch, bondStart, bondAmount, redelegatedBond, validator, slashes)*slashRate
      val SlashableAmount = computeBondAtEpoch(epoch, bondStart, bondAmount, redelegatedBond, validator, slashes)
      min(AmountDue, SlashableAmount) 
    }

    run computeSlashBondAtEpochTest = {
      val curEpoch = 20
      val infractionEpoch = curEpoch - slashProcessingDelay
      val redelegatedBond = Map("alice" -> Map(infractionEpoch-4 -> 10))
      all {
        // no other slash, no redelegation
        assert(computeSlashBondAtEpoch(curEpoch+1, infractionEpoch, infractionEpoch-2, 30, Map(), 1, "bob", Map("alice" -> [], "bob" -> [])) == 30),
        // no other slash, redelegation
        assert(computeSlashBondAtEpoch(curEpoch+1, infractionEpoch, infractionEpoch-2, 30, redelegatedBond, 1, "bob", Map("alice" -> [], "bob" -> [])) == 30),
        // other slash, no redelegation
        assert(computeSlashBondAtEpoch(curEpoch+1, infractionEpoch, infractionEpoch-2, 30, Map(), 1, "bob", Map("alice" -> [], "bob" -> [{epoch: infractionEpoch-1, rate: 1}])) == 0),
        // other slash, redelegation
        assert(computeSlashBondAtEpoch(curEpoch+1, infractionEpoch, infractionEpoch-2, 30, redelegatedBond, 1, "bob", Map("alice" -> [], "bob" -> [{epoch: infractionEpoch-1, rate: 1}])) == 0),
      }
    }

    // The slashValidator function computes for a given validator and a slash how much should be slashed at all epochs between the currentå
    // epoch (curEpoch) + 1 and the current epoch + 1 + PIPELINE_OFFSET, accounting for any tokens already unbonded.
    // - @param validator the misbehaving validator.
    // - @param curEpoch the current epoch.
    // - @param slashes list of slashes already processed slashes of the misbehaving validator.
    // - @param totalUnbonded a map from epoch to unbonded tokens.
    // - @param totalRedelegatedUnbonded a map from epoch to unbonded redelegated tokens.
    // - @param totalBonded a map from epoch to amount of bonded tokens.
    // - @param finalRate the rate of the slash being processed.
    // - @param slashedAmountsMap a map from epoch to already processed slash amounts.
    // - @returns a map that adds any newly processed slash amount to slashedAmountsMap.
    pure def slashValidator(validator: Address,
                            curEpoch: Epoch,
                            slashes: Address -> List[Slash],
                            totalUnbonded: Epoch -> Epoch -> int,
                            totalRedelegatedUnbonded: Epoch -> Epoch -> RedelegatedBondsMap,
                            totalBonded: Epoch -> int,
                            totalRedelegatedBonded: Epoch -> RedelegatedBondsMap,
                            finalRate: int,
                            slashesMap: Epoch -> int): Epoch -> int = {
      val infractionEpoch = curEpoch - slashProcessingDelay
      val bonds = totalBonded.keys().filter(e => e <= infractionEpoch).mapBy(start => totalBonded.get(start))
      val redelegatedBonds = bonds.keys().mapBy(e => totalRedelegatedBonded.getOrElse(e, Map()))
      val epochRange = (curEpoch+1).to(curEpoch+PIPELINE_OFFSET).sortSetDecreasing()
      epochRange.foldl({bonds: bonds,
                        redelegatedBonds: redelegatedBonds,
                        sum: 0, 
                        slashesMap: slashesMap}, (acc, epoch) => val amount = acc.bonds.keys().fold(0, (total, bondStart) => total + computeSlashBondAtEpoch(epoch,
                                                                                                                                                             infractionEpoch,
                                                                                                                                                             bondStart,
                                                                                                                                                             acc.bonds.get(bondStart),                                                                                                                
                                                                                                                                                             acc.redelegatedBonds.get(bondStart),
                                                                                                                                                             finalRate,
                                                                                                                                                             validator,
                                                                                                                                                             slashes))
                                                                 val newBonds = val keysBonds = totalUnbonded.get(epoch).keys().filter(e => e <= infractionEpoch)
                                                                                keysBonds.mapBy(start => totalUnbonded.get(epoch).get(start))
                                                                 val newRedelegatedBonds = newBonds.keys().mapBy(e => totalRedelegatedUnbonded.get(epoch).getOrElse(e, Map()))
                                                                 val newSum = acc.sum + amount
                                                                 val newSlashesMap = acc.slashesMap.set(epoch, slashesMap.get(epoch) + newSum)
                                                                 {bonds: newBonds, redelegatedBonds: newRedelegatedBonds, sum: newSum, slashesMap: newSlashesMap}).slashesMap                                                                      
    }

    run slashValidatorTest = {
      val curEpoch = 10
      val infractionEpoch = curEpoch - slashProcessingDelay
      val rate = 1
      val emptyTotalUnbonded = (curEpoch-CUBIC_OFFSET-UNBONDING_OFFSET).to(curEpoch+PIPELINE_OFFSET).mapBy(e => Map())
      val emptyTotalRedelegatedUnbonded = emptyTotalUnbonded
      val emptytotalRedelegatedBonded = Map()
      val emptySlashAmountsMap = (curEpoch+1).to(curEpoch+PIPELINE_OFFSET).mapBy(e => 0)
      val emptySlashes = Map("alice" -> [], "bob" -> [])
      all {
        // clean slashing: no new bonds or slashes
        assert(slashValidator("bob",
                              curEpoch,
                              emptySlashes,
                              emptyTotalUnbonded,
                              emptyTotalRedelegatedUnbonded,
                              Map(infractionEpoch-2 -> 23), //totalBonded
                              emptytotalRedelegatedBonded,
                              rate,
                              emptySlashAmountsMap) == (curEpoch+1).to(curEpoch+PIPELINE_OFFSET).mapBy(e => 23)),
        // part of the infraction stake is unbonded before the evidence is submitted
        assert(slashValidator("bob",
                              curEpoch,
                              emptySlashes,
                              emptyTotalUnbonded.set(curEpoch+PIPELINE_OFFSET, Map(infractionEpoch-2 -> 6)),
                              emptyTotalRedelegatedUnbonded,
                              Map(infractionEpoch-2 -> 17), //totalBonded
                              emptytotalRedelegatedBonded,
                              rate,
                              emptySlashAmountsMap) == (curEpoch+1).to(curEpoch+PIPELINE_OFFSET).mapBy(e => if (e == curEpoch+PIPELINE_OFFSET) 17 else 23)),
        // part of the infraction stake is redelagated and is unbonded before the evidence is submitted
        assert(slashValidator("bob",
                              curEpoch,
                              emptySlashes,
                              emptyTotalUnbonded.set(curEpoch+PIPELINE_OFFSET, Map(infractionEpoch-2 -> 6)),
                              emptyTotalRedelegatedUnbonded,
                              Map(infractionEpoch-2 -> 17), //totalBonded
                              Map(infractionEpoch-1 -> Map("alice" -> Map(2 -> 5, 3 -> 1))), //totalRedelegatedBonded
                              rate,
                              emptySlashAmountsMap) == (curEpoch+1).to(curEpoch+PIPELINE_OFFSET).mapBy(e => if (e == curEpoch+PIPELINE_OFFSET) 17 else 23)),
        // part of the infraction stake is redelagated and those redelegated tokens are unbonded before the evidence is submitted
        assert(slashValidator("bob",
                              curEpoch,
                              emptySlashes,
                              emptyTotalUnbonded.set(curEpoch+PIPELINE_OFFSET, Map(infractionEpoch-1 -> 6)),
                              emptyTotalRedelegatedUnbonded.set(curEpoch+PIPELINE_OFFSET, Map(infractionEpoch-1  -> Map("alice" -> Map(2 -> 5, 3 -> 1)))),
                              Map(infractionEpoch-2 -> 17), //totalBonded
                              Map(infractionEpoch-1 -> Map("alice" -> Map(2 -> 5, 3 -> 1))), //totalRedelegatedBonded
                              rate,
                              emptySlashAmountsMap) == (curEpoch+1).to(curEpoch+PIPELINE_OFFSET).mapBy(e => if (e == curEpoch+PIPELINE_OFFSET) 17 else 23)),
        // part of the infraction stake is redelagated and some of those redelegated tokens are unbonded before the evidence is submitted
        assert(slashValidator("bob",
                              curEpoch,
                              emptySlashes,
                              emptyTotalUnbonded.set(curEpoch+PIPELINE_OFFSET, Map(infractionEpoch-1 -> 4)),
                              emptyTotalRedelegatedUnbonded.set(curEpoch+PIPELINE_OFFSET, Map(infractionEpoch-1 -> Map("alice" -> Map(2 -> 4)))),
                              Map(infractionEpoch-2 -> 19), //totalBonded
                              Map(infractionEpoch-1 -> Map("alice" -> Map(2 -> 1, 3 -> 1))), //totalRedelegatedBonded
                              rate,
                              emptySlashAmountsMap) == (curEpoch+1).to(curEpoch+PIPELINE_OFFSET).mapBy(e => if (e == curEpoch+PIPELINE_OFFSET) 19 else 23)),
        // there is a bond happening at curEpoch
        assert(slashValidator("bob",
                              curEpoch,
                              emptySlashes,
                              emptyTotalUnbonded,
                              emptyTotalRedelegatedUnbonded,
                              Map(infractionEpoch-2 -> 23, curEpoch -> 6), //totalBonded
                              emptytotalRedelegatedBonded,
                              rate,
                              emptySlashAmountsMap) == (curEpoch+1).to(curEpoch+PIPELINE_OFFSET).mapBy(e => 23)),
        // there is a bond happening at curEpoch which is unbonded at curEpoch + 1
        assert(slashValidator("bob",
                              curEpoch,
                              emptySlashes,
                              emptyTotalUnbonded.set(curEpoch+1, Map(curEpoch -> 6)),
                              emptyTotalRedelegatedUnbonded,
                              Map(infractionEpoch-2 -> 23), //totalBonded
                              emptytotalRedelegatedBonded,
                              rate,
                              emptySlashAmountsMap) == (curEpoch+1).to(curEpoch+PIPELINE_OFFSET).mapBy(e => 23)),
        // there is a bond happening at curEpoch which is partially unbonded at curEpoch + 1
        assert(slashValidator("bob",
                              curEpoch,
                              emptySlashes,
                              emptyTotalUnbonded.set(curEpoch+1, Map(curEpoch -> 3)),
                              emptyTotalRedelegatedUnbonded,
                              Map(infractionEpoch-2 -> 23, curEpoch -> 3), //totalBonded
                              emptytotalRedelegatedBonded,
                              rate,
                              emptySlashAmountsMap) == (curEpoch+1).to(curEpoch+PIPELINE_OFFSET).mapBy(e => 23)),
        // there is a redelegation happening at curEpoch
        assert(slashValidator("bob",
                              curEpoch,
                              emptySlashes,
                              emptyTotalUnbonded,
                              emptyTotalRedelegatedUnbonded,
                              Map(infractionEpoch-2 -> 23, curEpoch -> 6), //totalBonded
                              Map(curEpoch -> Map("alice" -> Map(2 -> 5, 3 -> 1))), //totalRedelegatedBonded
                              rate,
                              emptySlashAmountsMap) == (curEpoch+1).to(curEpoch+PIPELINE_OFFSET).mapBy(e => 23)),
        // there is a redelegation happening at curEpoch that is unbonded at curEpoch + 1
        assert(slashValidator("bob",
                              curEpoch,
                              emptySlashes,
                              emptyTotalUnbonded,
                              emptyTotalRedelegatedUnbonded.set(curEpoch+1, Map(curEpoch -> Map("alice" -> Map(2 -> 5, 3 -> 1)))),
                              Map(infractionEpoch-2 -> 23), //totalBonded
                              Map(), //totalRedelegatedBonded
                              rate,
                              emptySlashAmountsMap) == (curEpoch+1).to(curEpoch+PIPELINE_OFFSET).mapBy(e => 23)),
        // there is a redelegation at curEpoch that is partially unbonded at curEpoch + 1
        assert(slashValidator("bob",
                              curEpoch,
                              emptySlashes,
                              emptyTotalUnbonded,
                              emptyTotalRedelegatedUnbonded.set(curEpoch+1, Map(curEpoch -> Map("alice" -> Map(2 -> 4)))),
                              Map(infractionEpoch-2 -> 23, curEpoch -> 2), //totalBonded
                              Map(curEpoch -> Map("alice" -> Map(2 -> 1, 3 -> 1))), //totalRedelegatedBonded
                              rate,
                              emptySlashAmountsMap) == (curEpoch+1).to(curEpoch+PIPELINE_OFFSET).mapBy(e => 23)),
        // there is a bond at curEpoch, redelegation at curEpoch+1 that is partially unbonded at curEpoch+1
        assert(slashValidator("bob",
                              curEpoch,
                              emptySlashes,
                              emptyTotalUnbonded,
                              emptyTotalRedelegatedUnbonded.set(curEpoch+1, Map(curEpoch -> Map("alice" -> Map(2 -> 4)))),
                              Map(infractionEpoch-2 -> 23, curEpoch -> 6, curEpoch+1 -> 2), //totalBonded
                              Map(curEpoch+1 -> Map("alice" -> Map(2 -> 1, 3 -> 1))), //totalRedelegatedBonded
                              rate,
                              emptySlashAmountsMap) == (curEpoch+1).to(curEpoch+PIPELINE_OFFSET).mapBy(e => 23)),
        // there is a bond at curEpoch and there exists a slash for "alice"
        assert(slashValidator("bob",
                              curEpoch,
                              emptySlashes.set("bob", [{epoch: infractionEpoch-1, rate: 1}]),
                              emptyTotalUnbonded,
                              emptyTotalRedelegatedUnbonded,
                              Map(infractionEpoch-2 -> 23, curEpoch -> 6), //totalBonded
                              emptytotalRedelegatedBonded,
                              rate,
                              emptySlashAmountsMap) == (curEpoch+1).to(curEpoch+PIPELINE_OFFSET).mapBy(e => 0)),
      }
    }

    // The function slashRedelegation computes how much can be slashed from a redelegated bond considering that the bond may have been completely or partially 
    // unbonded and that the source validator may have misbehaved already within the redelegation slashing window.
    // - @param amount the amount of tokens of the redelegated bond.
    // - @param bondStart the epoch at which the redelegated tokens started contributing to the source validator's stake.
    // - @param redBondStart the epoch at which the redelegated tokens started contributing to the destination validator's stake.
    // - @param srcValidator the source validator.
    // - @param curEpoch the current epoch.
    // - @param slashes a list of slashes of the source validator.
    // - @param totalRedelegatedUnbonded a map of unbonded redelegated tokens at the destination validator.
    // - @param finalRate the rate of the slash being processed.
    // - @param slashedAmountsMap a map from epoch to already processed slash amounts.
    // - @returns a map that adds any newly processed slash amount to slashedAmountsMap.
    pure def slashRedelegation(amount: int,
                               bondStart: Epoch,
                               redBondStart: Epoch,
                               srcValidator: Address,
                               curEpoch: Epoch,
                               slashes: List[Slash],
                               totalRedelegatedUnbonded: Epoch -> Epoch -> RedelegatedBondsMap,
                               finalRate: int,
                               slashedAmountsMap: Epoch -> int): Epoch -> int = {
      val infractionEpoch = curEpoch - slashProcessingDelay
      val initTotalUnbonded = (infractionEpoch+1).to(curEpoch).fold(0, (sum, e) => if (not(totalRedelegatedUnbonded.get(e).hasRedelegation(redBondStart, srcValidator, bondStart))) sum
                                                                                   else sum + totalRedelegatedUnbonded.get(e).get(redBondStart).get(srcValidator).get(bondStart))
      // We must iterate in epoch increasing order.
      val epochRange = range(curEpoch+1, curEpoch+PIPELINE_OFFSET+1)
      val result = epochRange.foldl((initTotalUnbonded, slashedAmountsMap), (acc, e) => val updatedTotalUnbonded = if (not(totalRedelegatedUnbonded.get(e).hasRedelegation(redBondStart, srcValidator, bondStart))) acc._1
                                                                                                                   else acc._1 + totalRedelegatedUnbonded.get(e).get(redBondStart).get(srcValidator).get(bondStart)
                                                                                        val slashAmount = val listSlashes = slashes.select(s => inRedelegationSlashingWindow(s.epoch, startRedelegationFromEnd(redBondStart), redBondStart) and
                                                                                                                                                s.epoch + slashProcessingDelay < infractionEpoch and
                                                                                                                                                bondStart <= s.epoch)
                                                                                                          applyListSlashes(listSlashes, amount - updatedTotalUnbonded) * finalRate
                                                                                        val slashableStake = val listSlashes = slashes.select(s => inRedelegationSlashingWindow(s.epoch, startRedelegationFromEnd(redBondStart), redBondStart) and
                                                                                                                                                   bondStart <= s.epoch)
                                                                                                             applyListSlashes(listSlashes, amount - updatedTotalUnbonded)
                                                                                        if (e > curEpoch + 1) (updatedTotalUnbonded, acc._2.set(e, acc._2.get(e) + min(slashAmount, slashableStake)))
                                                                                        else (updatedTotalUnbonded, acc._2))
      result._2                                                                                                                                  
    }

    run slashRedelegationTest = {
      val totalRedelegatedUnbonded = Map(10 -> Map(), 11 -> Map(), 12 -> Map(), 13 -> Map(10 -> Map("alice" -> Map(7 -> 2))), 14 -> Map(), 15 -> Map(), 16 -> Map(), 9 -> Map())
      val slashedAmountsMap = Map(15 -> 0, 16 -> 0)
      all {
        assert(slashRedelegation(7, 7, 10, "alice", 14, [], totalRedelegatedUnbonded, 1, slashedAmountsMap) == Map(15 -> 0, 16 -> 5)),
        assert(slashRedelegation(7, 7, 11, "alice", 14, [], totalRedelegatedUnbonded, 1, slashedAmountsMap) == Map(15 -> 0, 16 -> 7)),
        assert(slashRedelegation(7, 7, 10, "alice", 14, [], totalRedelegatedUnbonded, 1,  Map(15 -> 2, 16 -> 3)) == Map(15 -> 2, 16 -> 8)),
        // existing slash processed before the one being computed
        assert(slashRedelegation(7, 7, 10, "alice", 14, [{epoch: 8, rate: 1}], totalRedelegatedUnbonded, 1, slashedAmountsMap) == Map(15 -> 0, 16 -> 0)),
        // existing slash not processed before the one being computed
        assert(slashRedelegation(7, 7, 10, "alice", 14, [{epoch: 9, rate: 1}], totalRedelegatedUnbonded, 1, slashedAmountsMap) == Map(15 -> 0, 16 -> 0)),
        // existing slashes one processed before the one being computed and one not
        assert(slashRedelegation(7, 7, 10, "alice", 14, [{epoch: 8, rate: 1}, {epoch: 9, rate: 1}], totalRedelegatedUnbonded, 1, slashedAmountsMap) == Map(15 -> 0, 16 -> 0)),
      }
    }

    // In the context of a redelegation, the slashValidatorRedelegation function computes how much a validator (the destination validator of the redelegation) should be slashed
    // due to the misbehaving of a second validator (the source validator of the redelegation). The function computes how much the validator whould be slashed at all epochs
    // between the current epoch (curEpoch) + 1 and the current epoch + 1 + PIPELINE_OFFSET, accounting for any tokens of the redelegation already unbonded.
    // - @param srcValidator the source validator
    // - @param curEpoch the current epoch
    // - @param redelegations a map from pair of epochs to int that includes all the redelegations from the source validator to the destination validator. 
    //          - The first epoch in the pair is the epoch at which the bond started at the source validator.
    //          - The second epoch in the pair is the epoch at which the redelegation started (the epoch at which was issued).
    // - @param slashes a list of slashes of the source validator.
    // - @param totalRedelegatedUnbonded a map of unbonded redelegated tokens at the destination validator.
    // - @param finalRate the rate of the slash being processed.
    // - @param slashedAmountsMap a map from epoch to already processed slash amounts.
    // - @returns a map that adds any newly processed slash amount to slashedAmountsMap.
    pure def slashValidatorRedelegation(srcValidator: Address,
                                        curEpoch: Epoch,
                                        redelegations: (Epoch, Epoch) -> int,
                                        slashes: List[Slash],
                                        totalRedelegatedUnbonded: Epoch -> Epoch -> RedelegatedBondsMap,
                                        finalRate: int,
                                        slashedAmountsMap: Epoch -> int): Epoch -> int = {
      val infractionEpoch = curEpoch - slashProcessingDelay
      redelegations.keys().fold(slashedAmountsMap, (acc, pairEpochs) => val bondStart = pairEpochs._1
                                                                        val redelegationStart = pairEpochs._2
                                                                        if (inRedelegationSlashingWindow(infractionEpoch, redelegationStart, endRedelegationFromStart(redelegationStart)) and                         
                                                                            bondStart <= infractionEpoch) slashRedelegation(redelegations.get(pairEpochs),
                                                                                                                            bondStart,
                                                                                                                            endRedelegationFromStart(redelegationStart),
                                                                                                                            srcValidator,
                                                                                                                            curEpoch,
                                                                                                                            slashes,
                                                                                                                            totalRedelegatedUnbonded,
                                                                                                                            finalRate,
                                                                                                                            acc) 
                                                                        else acc)                                   
    }

    run slashValidatorRedelegationTest = {
      val redelegations = Map((7, 8) -> 7)
      val totalRedelegatedUnbonded = Map(10 -> Map(), 11 -> Map(), 12 -> Map(), 13 -> Map(10 -> Map("alice" -> Map(7 -> 2))), 14 -> Map(), 15 -> Map(), 16 -> Map(), 9 -> Map())
      val slashedAmountsMap = Map(15 -> 0, 16 -> 0)
      all {
        assert(slashValidatorRedelegation("alice", 14,  Map(), [], totalRedelegatedUnbonded, 1, slashedAmountsMap) == Map(15 -> 0, 16 -> 0)),
        assert(slashValidatorRedelegation("alice", 14,  Map(), [], Map(), 1, slashedAmountsMap) == Map(15 -> 0, 16 -> 0)),
        assert(slashValidatorRedelegation("alice", 14,  Map((6, 8) -> 7), [], totalRedelegatedUnbonded, 1, slashedAmountsMap) == Map(15 -> 0, 16 -> 7)),
        assert(slashValidatorRedelegation("alice", 14, redelegations, [], totalRedelegatedUnbonded, 1, slashedAmountsMap) == Map(15 -> 0, 16 -> 5)),
        assert(slashValidatorRedelegation("alice", 14, redelegations, [], totalRedelegatedUnbonded, 1, Map(15 -> 2, 16 -> 3)) == Map(15 -> 2, 16 -> 8)),
        assert(slashValidatorRedelegation("alice", 14, redelegations, [{epoch: 8, rate: 1}], totalRedelegatedUnbonded, 1, slashedAmountsMap) == Map(15 -> 0, 16 -> 0))
      }
    }
    
    // The function subtractBondsFromTotalBonded removes a set of bonds from a map of bonds.
    // - @param srcMap a map of bonds from which to subtract bonds.
    // - @param subtractMap a map of bonds to be subtracted.
    // - @returns an updated srcMap without the bonds in subtractMap.
    // Contract:
    // - Any epoch in subtractMap.keys() is in srcMap.keys()
    // - Given any epoch in subtractMap.keys(), srcMap.get(start) >= subtractMap.get(start)
    pure def subtractBondsFromTotalBonded(srcMap: Epoch -> int, subtractMap: Epoch -> int): Epoch -> int = {
      val filteredKeys = srcMap.keys().filter(epoch => subtractMap.has(epoch) implies srcMap.get(epoch) > subtractMap.get(epoch))
      filteredKeys.mapBy(epoch => if (subtractMap.has(epoch)) srcMap.get(epoch) - subtractMap.get(epoch)
                                  else srcMap.get(epoch))
    }

    run subtractBondsFromTotalBondedTest = {
      all {
        assert(subtractBondsFromTotalBonded(Map(), Map()) == Map()),
        assert(subtractBondsFromTotalBonded(Map(3 -> 5, 5 -> 6), Map()) == Map(3 -> 5, 5 -> 6)),
        assert(subtractBondsFromTotalBonded(Map(3 -> 5, 5 -> 6), Map(5 -> 6)) == Map(3 -> 5)),
        assert(subtractBondsFromTotalBonded(Map(3 -> 5, 5 -> 6), Map(5 -> 3)) == Map(3 -> 5, 5 -> 3)),
        assert(subtractBondsFromTotalBonded(Map(3 -> 5, 5 -> 6), Map(3 -> 5, 5 -> 6)) == Map()),
      }
    }

    // The function subtractFromRedelegatedBondsMap removes a set of redelegated bonds from a map of redelegated bonds.
    // - @param srcMap a map of redelegated bonds from which to subtract bonds.
    // - @param subtractMap a map of redelegated bonds to be subtracted.
    // - @returns an updated srcMap without the redelegated bonds in subtractMap.
    // Contract:
    // - Any epoch in subtractMap.keys() is in srcMap.keys()
    // - Given any source validator (src) in subtractMap.keys(), foldBondsMap(srcMap.get(src)) >= foldBondsMap(subtractMap.get(src))
    pure def subtractFromRedelegatedBondsMap(srcMap: RedelegatedBondsMap, subtractMap: RedelegatedBondsMap): RedelegatedBondsMap = {
      val filteredKeys = srcMap.keys().filter(src => subtractMap.has(src) implies foldBondsMap(srcMap.get(src)) > foldBondsMap(subtractMap.get(src)))
      filteredKeys.mapBy(src => if (subtractMap.has(src)) subtractBondsFromTotalBonded(srcMap.get(src), subtractMap.get(src))
                                else srcMap.get(src))
    }

    run subtractFromRedelegatedBondsMapTest = {
      val srcMap = Map("alice" -> Map(3 -> 5, 5 -> 6), "bob" -> Map(2 -> 6, 7 -> 8))
      all {
        assert(subtractFromRedelegatedBondsMap(Map(), Map()) == Map()),
        assert(subtractFromRedelegatedBondsMap(srcMap, Map()) == srcMap),
        assert(subtractFromRedelegatedBondsMap(srcMap, Map("alice" -> Map(3 -> 5, 5 -> 6))) == Map("bob" -> Map(2 -> 6, 7 -> 8))),
        assert(subtractFromRedelegatedBondsMap(srcMap, Map("alice" -> Map(3 -> 5))) == Map("alice" -> Map(5 -> 6), "bob" -> Map(2 -> 6, 7 -> 8))),
        assert(subtractFromRedelegatedBondsMap(srcMap, srcMap) == Map()),
      }
    }

    // The function subtractRedelegationsFromTotalRedelegatedBonded removes a the set of redelegated bonds from a map of redelegated bonds.
    // - @param totalRedelegatedBonded a map from epoch to RedelegatedBondsMap from which to subtract redelegate bonds.
    // - @param redelegationsToSubtract a map epoch to RedelegatedBondsMap with the redelegated bonds to be subtracted.
    // - @returns an updated totalRedelegatedBonded without the redelegated bonds in redelegationsToSubtract.
    // Contract:
    // - Any epoch in redelegationsToSubtract.keys() is in totalRedelegatedBonded.keys()
    // - Given any epoch any redelegation in redelegationsToSubtract.keys() is also in totalRedelegatedBonded.get(start).
    //   This implies that the total amount of redelegated tokens for any of those epochs in totalRedelegatedBonded is greater
    //   or equal to the total amount of redelegated tokens for that epoch in redelegationsToSubtract.
    pure def subtractRedelegationsFromTotalRedelegatedBonded(totalRedelegatedBonded: Epoch -> RedelegatedBondsMap, redelegationsToSubtract: Epoch -> RedelegatedBondsMap): Epoch -> RedelegatedBondsMap = {
      val filteredKeys = totalRedelegatedBonded.keys().filter(epoch => redelegationsToSubtract.has(epoch) implies foldRedelegatedBondsMap(totalRedelegatedBonded.get(epoch)) > foldRedelegatedBondsMap(redelegationsToSubtract.get(epoch)))
      filteredKeys.mapBy(epoch => if (redelegationsToSubtract.has(epoch)) subtractFromRedelegatedBondsMap(totalRedelegatedBonded.get(epoch), redelegationsToSubtract.get(epoch))
                                  else totalRedelegatedBonded.get(epoch))
    }

    run subtractRedelegationsFromTotalRedelegatedBondedTest = {
      val srcMapEpoch5 = Map("alice" -> Map(3 -> 5, 5 -> 6), "bob" -> Map(2 -> 6, 7 -> 8))
      val srcMapEpoch7 = Map("alice" -> Map(8 -> 12, 5 -> 6))
      val srcMap = Map(5 -> srcMapEpoch5, 7 -> srcMapEpoch7)
      all {
        assert(subtractRedelegationsFromTotalRedelegatedBonded(Map(), Map()) == Map()),
        assert(subtractRedelegationsFromTotalRedelegatedBonded(srcMap, Map()) == srcMap),
        assert(subtractRedelegationsFromTotalRedelegatedBonded(srcMap, Map(5 -> srcMapEpoch5)) == Map(7 -> srcMapEpoch7)),
        assert(subtractRedelegationsFromTotalRedelegatedBonded(srcMap, Map(5 -> Map("alice" -> Map(3 -> 5, 5 -> 6)))) == Map(5 -> Map("bob" -> Map(2 -> 6, 7 -> 8)), 7 -> srcMapEpoch7)),
        assert(subtractRedelegationsFromTotalRedelegatedBonded(srcMap, srcMap) == Map()),
      }
    }

    // **************************************************************************
    // Rewards helper functions
    // ************************************************************************* 

    // The function computeRewardProduct blackboxes the computation of reward products based on a list of slashes.
    pure def computeRewardProduct(slashes: List[Slash]): Dec = {
      (1,5)
    }

    // The function computeBondRewards computes the rewards produced by a bond that have not been claimed.
    // - @param start bond start epoch.
    // - @param amount bond amount.
    // - @param redelegatedBond a RedelegatedBondsMap associated with the bond (which may be empty (Map())).
    // - @param validator the validator address to which the tokens are delegated.
    // - @param slashes a map from validator to list of slashes
    // - @param lastClaim epoch up to which the rewards have been already claimed.
    // - @param rewardsProducts applicable rewards products.
    // - @returns the total amount of rewards.
    pure def computeBondRewards(start: Epoch, amount: int, redelegatedBond: RedelegatedBondsMap, validator: Address, slashes: Address -> List[Slash], lastClaim: Epoch, rewardsProducts: Epoch -> Dec): Dec = {
      val epochProducts = rewardsProducts.keys().filter(e => e > lastClaim and e >= start)
      epochProducts.fold((0,1), (sum, e) => val slashedAmount = computeBondAtEpoch(e, start, amount, redelegatedBond, validator, slashes)
                                            val reward = (slashedAmount, 1).mul(rewardsProducts.get(e))
                                            sum.add(reward))
    }

    run computeBondRewardsTest = {
      val rewardsProducts = Map(1 -> (1, 5), 2 -> (1, 5), 3 -> (1, 4), 4 -> (1, 4))
      val emptySlashes = Map("alice" -> [], "bob" -> [])
      all {
        // tests  without slashes or redelegation bond
        // bond started too late
        assert(computeBondRewards(5, 20, Map(), "alice", emptySlashes, 2, rewardsProducts).equal((0,1))),
        // bond started in the middle, nothing claimed
        assert(computeBondRewards(2, 20, Map(), "alice", emptySlashes,1, rewardsProducts).equal((14,1))),
        // bond started in the middle, partially claimed
        assert(computeBondRewards(2, 20, Map(), "alice", emptySlashes,2, rewardsProducts).equal((10,1))),
        // bond started in the middle, all claimed
        assert(computeBondRewards(2, 20, Map(), "alice", emptySlashes,4, rewardsProducts).equal((0,1))),
        // bond started in the middle, all claimed
        assert(computeBondRewards(2, 20, Map(), "alice", emptySlashes,4, rewardsProducts).equal((0,1))),
      }
    }

    // Given a validator and a delegator, the function computeAllRewards computes the total amount of rewards that have not yet been claimed.
    // - @param delegator delegator's state
    // - @param validator validator's state.
    // - @param slashes a map from validator to list of slashes.
    // - @returns the total amount of rewards.
    pure def computeAllRewards(delegator: DelegatorState, validator: ValidatorState, slashes: Address -> List[Slash]): Dec = {
      val bonds = delegator.bonded.get(validator.address)
      val lastClaim = delegator.lastClaim.get(validator.address)
      val sumRewardsBonds = bonds.keys().fold((0,1), (sum, e) => val redelegatedBond = delegator.redelegatedBonded.get(validator.address).getOrElse(e, Map())
                                                                 val reward = computeBondRewards(e, bonds.get(e), redelegatedBond, validator.address, slashes, lastClaim, validator.rewardsProducts)
                                                                 sum.add(reward))                                                            
      sumRewardsBonds.add(delegator.rewards.get(validator.address))
    }

    // The function computeEpochInflation computes total amount of minted tokens at a given epoch based on the stake of each validator
    // and the function computeRewardProduct.
    // - @param validatorsState a map from validator address to validator state.
    // - @param epoch an epoch.
    // - @returns the total amount of minted tokens.
    pure def computeEpochInflation(validatorsState: Address -> ValidatorState, epoch: Epoch): Dec = {
      validatorsState.keys().fold((0,1), (sum, v) => val stake = validatorsState.get(v).stake.get(epoch)
                                                     val rewards = (stake, 1).mul(computeRewardProduct(List()))
                                                     sum.add(rewards))
    }
}