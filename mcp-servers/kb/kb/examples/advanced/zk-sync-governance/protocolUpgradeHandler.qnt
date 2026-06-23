module protocolUpgradeHandler {
    import hashing.* from "./hashing"
    import state.* from "./state"
    import types.* from "./types"

    /// -------------------------------------------------------------------------------------------
    /// ProtocolUpgradeHandler constants
    /// -------------------------------------------------------------------------------------------

    /// 1 time unit = 1 hour

    /// @dev Duration of the standard legal veto period:
    /// STANDARD_LEGAL_VETO_PERIOD = 3 days;
    /// Note: this value should not exceed EXTENDED_LEGAL_VETO_PERIOD.
    pure val STANDARD_LEGAL_VETO_PERIOD = 72;

    /// @dev Duration of the extended legal veto period:
    /// EXTENDED_LEGAL_VETO_PERIOD = 7 days;
    pure val EXTENDED_LEGAL_VETO_PERIOD = 168;

    /// @dev The mandatory delay period before an upgrade can be executed.
    /// This period is intended to provide a buffer after an upgrade's final approval and before its execution,
    /// allowing for final reviews and preparations for devs and users.
    /// UPGRADE_DELAY_PERIOD = 1 days;
    pure val UPGRADE_DELAY_PERIOD = 24;

    /// @dev Time limit for an upgrade proposal to be approved by guardians or expire, and the waiting period for execution post-guardians approval.
    /// If the Security Council approves, the upgrade can proceed immediately; otherwise,
    /// the proposal will expire after this period if not approved, or wait this period after guardians approval.
    /// UPGRADE_WAIT_OR_EXPIRE_PERIOD = 30 days;
    pure val UPGRADE_WAIT_OR_EXPIRE_PERIOD = 720;

    /// @dev Duration of a soft freeze which temporarily pause protocol contract functionality.
    /// This freeze window is needed for the Security Council to decide whether they want to
    /// do hard freeze and protocol upgrade.
    /// SOFT_FREEZE_PERIOD = 12 hours;
    pure val SOFT_FREEZE_PERIOD = 12;

    /// @dev Duration of a hard freeze which temporarily pause protocol contract functionality.
    /// This freeze window is needed for the Security Council to perform emergency protocol upgrade.
    /// HARD_FREEZE_PERIOD = 7 days;
    pure val HARD_FREEZE_PERIOD = 168;

    /// @notice Initializes the contract with the Security Council address, guardians address and address of L2 voting governor.
    /// @param _securityCouncil The address to be assigned as the Security Council of the contract.
    /// @param _guardians The address to be assigned as the guardians of the contract.
    /// @param _l2ProtocolGovernor The address of the L2 voting governor contract for protocol upgrades.
    pure def newProtocolUpgradeHandler(sa: Address, ga: Address, ea: Address): Result[ProtocolUpgradeHandlerState] = {
        ok({
            securityCouncil: sa,
            emergencyUpgradeBoard: ea,
            guardians: ga,
            upgradeStatus: Map(),
            lastFreezeStatusInUpgradeCycle: FreezeStatusNone,
            protocolFrozenUntil: 0,
        })
    }

    /// @dev Freeze all ZKsync contracts, including bridges, state transition managers and all hyperchains.
    pure def freeze(evm: EvmState): EvmState = {
        val newMap = evm.frozenChains.keys().mapBy(chainID => true)
        {...evm, zkFrozen: true, frozenChains: newMap}
    }

    /// @dev Unfreeze all ZKsync contracts, including bridges, state transition managers and all hyperchains.
    pure def unfreeze(evm: EvmState): EvmState = {
        val newMap = evm.frozenChains.keys().mapBy(chainID => false)
        {...evm, zkFrozen: false, frozenChains: newMap}
    }

    pure def upgradeState(self: ProtocolUpgradeHandlerState, blockTimestamp: Uint256, _id: AbiElem): UpgradeState = {
        // Upgrade doesn't exist from Quint perspective
        val upg = self.upgradeStatus.getOrElse(_id, upgradeStatusZero)
        // Upgrade already executed
        if (upg.executed) {
            UpgradeStateDone
        } else {
            // Upgrade doesn't exist from Solidity perspective
            if (upg.creationTimestamp == 0) {
                UpgradeStateNone
            } else {
                // Legal veto period
                val legalVetoTime = if (upg.guardiansExtendedLegalVeto) {EXTENDED_LEGAL_VETO_PERIOD} else {STANDARD_LEGAL_VETO_PERIOD}

                if (blockTimestamp < upg.creationTimestamp + legalVetoTime) {
                    UpgradeStateLegalVetoPeriod
                } else {
                    if (upg.securityCouncilApprovalTimestamp != 0) {
                        val readyWithSecurityCouncilTimestamp = upg.securityCouncilApprovalTimestamp + UPGRADE_DELAY_PERIOD;
                        if (blockTimestamp >= readyWithSecurityCouncilTimestamp) {UpgradeStateReady} else {UpgradeStateExecutionPending}
                    } else {
                        val waitOrExpiryTimestamp = upg.creationTimestamp + legalVetoTime + UPGRADE_WAIT_OR_EXPIRE_PERIOD;
                        if (blockTimestamp >= waitOrExpiryTimestamp) {
                            if (not(upg.guardiansApproval)) {
                                UpgradeStateExpired
                            } else {
                                val readyWithGuardiansTimestamp = waitOrExpiryTimestamp + UPGRADE_DELAY_PERIOD;
                                if (blockTimestamp >= readyWithGuardiansTimestamp)  {UpgradeStateReady} else {UpgradeStateExecutionPending}
                            }
                        } else {
                            UpgradeStateWaiting
                        }
                    }    
                }
            }    
        }
    }

    /*//////////////////////////////////////////////////////////////
                            UPGRADE PROCESS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initiates the upgrade process by verifying an L2 voting decision.
    /// @dev This function decodes and validates an upgrade proposal message from L2, setting the initial state for the upgrade process.
    /// @param _l2BatchNumber The batch number of the L2 transaction containing the upgrade proposal.
    /// @param _l2MessageIndex The index of the message within the L2 batch.
    /// @param _l2TxNumberInBatch The transaction number of the upgrade proposal in the L2 batch.
    /// @param _proof Merkle proof verifying the inclusion of the upgrade message in the L2 batch.
    /// @param _proposal The upgrade proposal details including proposed actions and the executor address.
    pure def protocolUpgradeHandler::StartUpgrade(evm: EvmState, _proposal: UpgradeProposal): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        val e1 = require(_proposal.executor != self.emergencyUpgradeBoard, "Emergency Upgrade Board can't execute usual upgrade")
        if (e1 != "") {
            err(evm, e1)
        } else {
            val id = keccak256_UpgradeProposal(_proposal)
            val upgState: UpgradeState = upgradeState(self, evm.blockTimestamp, id)
            val e2 = require(upgState == UpgradeStateNone, "Upgrade with this id already exists")
            if (e2 != "") {
                err(evm, e2)
            } else {
                pure val self2 = {
                    ...self,
                    upgradeStatus: self.upgradeStatus.put(id, {
                        securityCouncilApprovalTimestamp: 0,
                        guardiansApproval: false,
                        guardiansExtendedLegalVeto: false,
                        executed: false,
                        creationTimestamp: evm.blockTimestamp,
                    })
                }

                pure val events = evm.emittedEvents.append(EventUpgradeStarted(_proposal))
                ok({ ...evm, protocolUpgradeHandler: self2, emittedEvents: events })
            }

        }
    }

    /// @notice Extends the legal veto period by the guardians.
    /// @param _id The unique identifier of the upgrade proposal to be approved.
    pure def protocolUpgradeHandler::ExtendLegalVeto(evm: EvmState, _id: AbiElem): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        
        val e = require(evm.msgSender() == self.guardians, "Only guardians is allowed to call this function")
        if (e != "") {
            err(evm, e)
        } else {
            // Access map's element according to the Solidity's semantics
            val e1 = require(not(self.upgradeStatus.getOrElse(_id, upgradeStatusZero).guardiansExtendedLegalVeto), "Legal veto period is already extended")
            if (e1 != "") {
                err(evm, e1)
            } else {
                val upgState = upgradeState(self, evm.blockTimestamp, _id)
                val e2 = require(upgState == UpgradeStateLegalVetoPeriod, "Upgrade with this id is not in the legal veto period")
                if (e2 != "") {
                    err(evm, e2)
                } else {
                    pure val self2 = {
                        ...self,
                        upgradeStatus: self.upgradeStatus.setBy(_id, old => {
                            ...old,
                            guardiansExtendedLegalVeto: true,
                        })
                    }
                    pure val events = evm.emittedEvents.append(EventUpgradeLegalVetoExtended(_id))
                    ok({ ...evm, protocolUpgradeHandler: self2, emittedEvents: events })
                }
            }
        }
    }

    /// @notice Approves an upgrade proposal by the Security Council.
    /// @dev Transitions the state of an upgrade proposal to 'VetoPeriod' after approval by the Security Council.
    /// @param _id The unique identifier of the upgrade proposal to be approved.
    pure def protocolUpgradeHandler::ApproveUpgradeSecurityCouncil(evm: EvmState, _id: AbiElem): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        val e1 = require(evm.msgSender() == self.securityCouncil, "Only security council is allowed to call this function")
        if (e1 != "") {
            err(evm, e1)
        } else {
            val upgState = upgradeState(self, evm.blockTimestamp, _id)
            val e2 = require(upgState == UpgradeStateWaiting, "Upgrade with this id is not waiting for the approval from Security Council")
            if (e2 != "") {
                err(evm, e2)
            } else {
                pure val self2 = {
                    ...self,
                    upgradeStatus: self.upgradeStatus.setBy(_id, old => {
                        ...old,
                        securityCouncilApprovalTimestamp: evm.blockTimestamp,
                    })
                }

                pure val events = evm.emittedEvents.append(EventUpgradeApprovedBySecurityCouncil(_id))
                ok({ ...evm, protocolUpgradeHandler: self2, emittedEvents: events})
            }
        }
    }

    /// @notice Approves an upgrade proposal by the guardians.
    /// @dev Marks the upgrade proposal identified by `_id` as approved by guardians.
    /// @param _id The unique identifier of the upgrade proposal to approve.
    pure def protocolUpgradeHandler::ApproveUpgradeGuardians(evm: EvmState, _id: AbiElem): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        val e1 = require(evm.msgSender() == self.guardians, "Only guardians is allowed to call this function")
        if (e1 != "") {
            err(evm, e1)
        } else {
            val upgState = upgradeState(self, evm.blockTimestamp, _id)
            val e2 = require(upgState == UpgradeStateWaiting, "Upgrade with this id is not waiting for the approval from Guardians")
            if (e2 != "") {
                err(evm, e2)
            } else {
                pure val self2 = {
                    ...self,
                    upgradeStatus: self.upgradeStatus.setBy(_id, old => {
                        ...old,
                        guardiansApproval: true,
                    })
                }

                pure val events = evm.emittedEvents.append(EventUpgradeApprovedByGuardians(_id))
                ok({ ...evm, protocolUpgradeHandler: self2, emittedEvents: events})
            }
        }
    }

    /// @notice Executes an upgrade proposal that has reached the 'Ready' state.
    /// @param _proposal The upgrade proposal to be executed, containing the target calls and optionally an executor.
    pure def protocolUpgradeHandler::Execute(evm: EvmState, _proposal: UpgradeProposal): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        val id = keccak256_UpgradeProposal(_proposal)
        val upgState: UpgradeState = upgradeState(self, evm.blockTimestamp, id)
        val e1 = require(upgState == UpgradeStateReady, "Upgrade is not yet ready")
        if (e1 != "") {
            err(evm, e1)
        } else {
            val e2 = require(_proposal.executor == ZERO_ADDRESS or _proposal.executor == evm.msgSender(), "msg.sender is not authorized to perform the upgrade")
            if (e2 != "") {
                err(evm, e2)
            } else {
                pure val self2 = {
                    ...self,
                    upgradeStatus: self.upgradeStatus.setBy(id, old => {
                        ...old,
                        executed: true,
                    }),
                }
                pure val events = evm.emittedEvents.append(EventUpgradeExecuted(id))
                ok({ ...evm, protocolUpgradeHandler: self2, emittedEvents: events })
            }
        }
    }

    /// @notice Executes an emergency upgrade proposal initiated by the emergency upgrade board.
    /// @param _proposal The upgrade proposal details including proposed actions and the executor address.
    pure def protocolUpgradeHandler::ExecuteEmergencyUpgrade(evm: EvmState, _proposal: UpgradeProposal): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler

        val e = require(evm.msgSender() == self.emergencyUpgradeBoard, "Only Emergency Upgrade Board is allowed to call this function")
        if (e != "") {
            err(evm, e)
        } else {
            val id = keccak256_UpgradeProposal(_proposal)
            val upgState: UpgradeState = upgradeState(self, evm.blockTimestamp, id)
            val e1 = require(upgState == UpgradeStateNone, "Upgrade already exists")
            if (e1 != "") {
                err(evm, e1)
            } else {
                val e2 = require(_proposal.executor == evm.msgSender(), "msg.sender is not authorized to perform the upgrade")
                if (e2 != "") {
                    err(evm, e2)
                } else {
                    pure val self2 = {
                        ...self,
                        upgradeStatus: self.upgradeStatus.put(id, {
                            ...self.upgradeStatus.getOrElse(id, upgradeStatusZero),
                            executed: true,
                        }),
                        lastFreezeStatusInUpgradeCycle: FreezeStatusNone,
                        protocolFrozenUntil: 0
                    }
                    pure val events = evm.emittedEvents.append(EventEmergencyUpgradeExecuted(id)).append(EventEmergencyUpgradeExecutedSome).append(EventUnfreeze)
                    ok({ ...unfreeze(evm), protocolUpgradeHandler: self2, emittedEvents: events })
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            FREEZABILITY
    //////////////////////////////////////////////////////////////*/

    /// @notice Initiates a soft protocol freeze.
    pure def protocolUpgradeHandler::SoftFreeze(evm: EvmState): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        val until = evm.blockTimestamp + SOFT_FREEZE_PERIOD
        val e = require(self.lastFreezeStatusInUpgradeCycle == FreezeStatusNone, "Protocol already frozen")
            .andRequire(evm.msgSender() == SECURITY_COUNCIL_ADDR, "Only Security Council is allowed to call this function")
        if (e != "") {
            err(evm, e)
        } else {
            val self2 = {
                ...self,
                lastFreezeStatusInUpgradeCycle: FreezeStatusSoft,
                protocolFrozenUntil: until
            }
            pure val events = evm.emittedEvents.append(EventSoftFreeze(until))
            ok({ ...freeze(evm), protocolUpgradeHandler: self2, emittedEvents: events })
        }
    }

    /// @notice Initiates a hard protocol freeze.
    pure def protocolUpgradeHandler::HardFreeze(evm: EvmState): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        val freezeStatus = self.lastFreezeStatusInUpgradeCycle
        val until = evm.blockTimestamp + HARD_FREEZE_PERIOD
        val e = require(freezeStatus == FreezeStatusNone
                or freezeStatus == FreezeStatusSoft or freezeStatus == FreezeStatusAfterSoftFreeze,
            "Protocol can't be hard frozen")
            .andRequire(evm.msgSender() == SECURITY_COUNCIL_ADDR, "Only Security Council is allowed to call this function")
        if (e != "") {
            err(evm, e)
        } else {
            val self2 = {
                ...self,
                lastFreezeStatusInUpgradeCycle: FreezeStatusHard,
                protocolFrozenUntil: evm.blockTimestamp + HARD_FREEZE_PERIOD
            }
            pure val events = evm.emittedEvents.append(EventHardFreeze(until))
            ok({ ...freeze(evm), protocolUpgradeHandler: self2, emittedEvents: events })
        }
    }

    /// @dev Reinforces the freezing state of the protocol if it is already within the frozen period. This function
    /// can be called by anyone to ensure the protocol remains in a frozen state, particularly useful if there is a need
    /// to confirm or re-apply the freeze due to partial or incomplete application during the initial freeze.
    pure def protocolUpgradeHandler::ReinforceFreeze(evm: EvmState): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        val e = require(evm.blockTimestamp <= self.protocolFrozenUntil, "Protocol should be already frozen")
        if (e != "") {
            err(evm, e)
        } else {
            pure val events = evm.emittedEvents.append(EventReinforceFreeze)
            ok({ ...freeze(evm), emittedEvents: events })
        }
    }

    /// @dev Reinforces the freezing state of the specific chain if the protocol is already within the frozen period.
    /// The function is an analog of `reinforceFreeze` but only for one specific chain, needed in the
    /// rare case where the execution could get stuck at a particular ID for some unforeseen reason.
    pure def protocolUpgradeHandler::ReinforceFreezeOneChain(evm: EvmState, _chainId: ChainID): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        val e = require(evm.blockTimestamp <= self.protocolFrozenUntil, "Protocol should be already frozen")
        if (e != "") {
            err(evm, e)
        } else {
            pure val events = evm.emittedEvents.append(EventReinforceFreezeOneChain(_chainId))
            pure val evm2 = {
                ...evm,
                frozenChains: evm.frozenChains.put(_chainId, true),
                emittedEvents: events
            }
            ok(evm2)
        }
    }

    /// @dev Unfreezes the protocol and resumes normal operations.
    pure def protocolUpgradeHandler::Unfreeze(evm: EvmState): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        val e = require((evm.msgSender() == SECURITY_COUNCIL_ADDR) or
                    ((self.protocolFrozenUntil != 0) and (evm.blockTimestamp > self.protocolFrozenUntil)),
                "Only Security Council is allowed to call this function")
            .andRequire(self.lastFreezeStatusInUpgradeCycle == FreezeStatusSoft
                        or self.lastFreezeStatusInUpgradeCycle == FreezeStatusHard, "Unexpected last freeze status")
        if (e != "") {
            err(evm, e)
        }
        else {
            pure val events = evm.emittedEvents.append(EventUnfreeze)
            val self2 = {
                    ...self,
                    lastFreezeStatusInUpgradeCycle:
                        if (self.lastFreezeStatusInUpgradeCycle == FreezeStatusSoft) {
                            FreezeStatusAfterSoftFreeze
                        } else {
                            FreezeStatusAfterHardFreeze
                        },
                    protocolFrozenUntil: 0
                }
            ok({ ...unfreeze(evm), protocolUpgradeHandler: self2, emittedEvents: events })
        }
    }

    /// @dev Reinforces the unfreeze for protocol if it is not in the freeze mode. This function can be called
    /// by anyone to ensure the protocol remains in an unfrozen state, particularly useful if there is a need
    /// to confirm or re-apply the unfreeze due to partial or incomplete application during the initial unfreeze.
    pure def protocolUpgradeHandler::ReinforceUnfreeze(evm: EvmState): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        val e = require(self.protocolFrozenUntil == 0, "Protocol should be already unfrozen")
        if (e != "") {
            err(evm, e)
        } else {
            pure val events = evm.emittedEvents.append(EventReinforceUnfreeze)
            ok({ ...unfreeze(evm), emittedEvents: events })
        }
    }

    /// @dev Reinforces the unfreeze for one specific chain if the protocol is not in the freeze mode.
    /// The function is an analog of `reinforceUnfreeze` but only for one specific chain, needed in the
    /// rare case where the execution could get stuck at a particular ID for some unforeseen reason.
    pure def protocolUpgradeHandler::ReinforceUnfreezeOneChain(evm: EvmState, _chainId: ChainID): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        val e = require(self.protocolFrozenUntil == 0, "Protocol should be already unfrozen")
        if (e != "") {
            err(evm, e)
        } else {
            pure val events = evm.emittedEvents.append(EventReinforceUnfreezeOneChain(_chainId))
            pure val evm2 = {
                ...evm,
                // we do not emulate revert if the target chainID does not exist
                frozenChains: evm.frozenChains.put(_chainId, false),
                emittedEvents: events
            }
            ok(evm2)
        }
    }

    /*//////////////////////////////////////////////////////////////
                            SELF UPGRADES
    //////////////////////////////////////////////////////////////*/

    /// @dev Updates the address of the Security Council.
    /// @param _newSecurityCouncil The address of the new Security Council.
    pure def  protocolUpgradeHandler::UpdateSecurityCouncil(evm: EvmState, _newSecurityCouncil: Address): Result[EvmState] =  {
        val self = evm.protocolUpgradeHandler
        val e = require(evm.msgSender() == PROTOCOL_UPGRADE_HANDLER_ADDR, "Only upgrade handler contract itself is allowed to call this function")
        if (e != "") {
            err(evm, e)
        } else {
            pure val events = evm.emittedEvents.append(EventChangeSecurityCouncil((self.securityCouncil, _newSecurityCouncil)))
                    
            pure val self2 = {
                ...self,
                securityCouncil: _newSecurityCouncil
            }
            ok({ ...evm, protocolUpgradeHandler: self2, emittedEvents: events })
        }
    }

    /// @dev Updates the address of the guardians.
    /// @param _newGuardians The address of the guardians.
    pure def  protocolUpgradeHandler::UpdateGuardians(evm: EvmState, _newGuardians: Address): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        val e = require(evm.msgSender() == PROTOCOL_UPGRADE_HANDLER_ADDR, "Only upgrade handler contract itself is allowed to call this function")
        if (e != "") {
            err(evm, e)
        } else {
            pure val events = evm.emittedEvents.append(EventChangeGuardians((self.guardians, _newGuardians)))
                    
            pure val self2 = {
                ...self,
                guardians: _newGuardians
            }
            ok({ ...evm, protocolUpgradeHandler: self2, emittedEvents: events })
        }
    }

    /// @dev Updates the address of the emergency upgrade board.
    /// @param _newEmergencyUpgradeBoard The address of the guardians.
    pure def protocolUpgradeHandler::UpdateEmergencyUpgradeBoard(evm: EvmState, _newEmergencyUpgradeBoard: Address): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        val e = require(evm.msgSender() == PROTOCOL_UPGRADE_HANDLER_ADDR, "Only upgrade handler contract itself is allowed to call this function")
        if (e != "") {
            err(evm, e)
        } else {
            pure val events = evm.emittedEvents.append(EventChangeEmergencyUpgradeBoard((self.emergencyUpgradeBoard, _newEmergencyUpgradeBoard)))
            pure val self2 = {
                ...self,
                emergencyUpgradeBoard: _newEmergencyUpgradeBoard
            }
            ok({ ...evm, protocolUpgradeHandler: self2, emittedEvents: events })
        }
    }
}