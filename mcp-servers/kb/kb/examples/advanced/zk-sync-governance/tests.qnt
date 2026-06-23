module tests {
    import guardians.* from "./guardians"
    import hashing.* from "./hashing"
    import multisig.* from "./multisig"
    import protocolUpgradeHandler.* from "./protocolUpgradeHandler"
    import securityCouncil.* from "./securityCouncil"
    import state.* from "./state"
    import types.* from "./types"

    run multisig_Test = {
        val m = newMultisig(Set("a", "b", "c", "d"), 2)
        if (isOk(m)) {
            assert(m.v.isValidSignature([], Set({signer: "a", digest: [AbiStr("a")]})) != EIP1271_MAGICVALUE)
        } else {
            assert(false)
        }
    }


    run multisig_2_Test = {
        val m = newMultisig(Set("a","b","c","d"), 2)
        if (isOk(m)) {
            assert(m.v.isValidSignature([], Set({signer: "a", digest: [AbiStr("a")]})) != EIP1271_MAGICVALUE)
        } else {
            assert(false)
        }
    }

    run multisig_3_Test = {
        val m = newMultisig(Set("a", "b", "c", "d"), 2)
        if (isOk(m)) {
            assert(EIP1271_MAGICVALUE == m.v.isValidSignature([AbiStr("a"), AbiStr("b")], Set({signer: "a", digest: [AbiStr("a"), AbiStr("b")]}, {signer: "b", digest: [AbiStr("a"), AbiStr("b")]})))
        } else {
            assert(false)
        }
    }

    run newSecurityCouncil_ok_Test = {
        val members = Set("a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9", "a10", "a11", "a12")
        val sc = newSecurityCouncil(members)
        if (isOk(sc)) {
            assert(sc.v.multisig.members == members)
        } else {
            assert(false)
        }
    }

    run newSecurityCouncil_small_Test = {
        val members = Set("a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9", "a10", "a11")
        val sc = newSecurityCouncil(members)
        assert(isErr(sc))
    }

    run newSecurityCouncil_large_Test = {
        val members = Set("a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9", "a10", "a11", "a12", "a13")
        val sc = newSecurityCouncil(members)
        assert(isErr(sc))
    }

    run securityCouncil_SoftFreeze_Test = {
        val members = Set("a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9", "a10", "a11", "a12")
        val guardiansMembers = Set("g1", "g2", "g3", "g4", "g5", "g6", "g7", "g8")
        val zkFoundationMultisig = newMultisig(members, 3)
        val sc = newSecurityCouncil(members)
        val guardians = newGuardians(guardiansMembers)
        if (isErr(sc) or isErr(guardians) or isErr(zkFoundationMultisig)) {
            assert(false)
        } else {
            val evm = {
                blockTimestamp: 0,
                securityCouncil: sc.v,
                guardians: guardians.v,
                zkFoundation: zkFoundationMultisig.v,
                protocolUpgradeHandler: {
                    securityCouncil: "sc1",
                    guardians: "g",
                    emergencyUpgradeBoard: "b",
                    upgradeStatus: Map(),
                    lastFreezeStatusInUpgradeCycle: FreezeStatusNone,
                    protocolFrozenUntil: 0,
                },
                priorityQueue: [],
                frozenChains: Map(),
                zkFrozen: false,
                ghostCallHistory: {
                    lastSender: "",
                    calls: [],
                },
                emittedEvents: [
                    EventChangeSecurityCouncil((ZERO_ADDRESS, SECURITY_COUNCIL_ADDR)),
                    EventChangeGuardians((ZERO_ADDRESS, GUARDIANS_ADDR)),
                    EventChangeEmergencyUpgradeBoard((ZERO_ADDRESS, EMERGENCY_UPGRADE_BOARD_ADDR))
                ],
            }
            val nine = Set("a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9")
            val evm2 = evm.externalCall("sender", "SECURITY_COUNCIL_ADDR", FunctionSoftFreeze)
            val digest = _securityCouncilHashTypedDataV4(
                keccak256(abi_encode3(SOFT_FREEZE_SECURITY_COUNCIL_TYPEHASH, AbiInt(evm.securityCouncil.softFreezeNonce), AbiInt(100)))
            )
            val signers = nine
            val signatures = signDigest(signers, digest)
            val res = securityCouncil::SoftFreeze(evm, 100, signers, signatures)
            if (isErr(res)) {
                assert(false)
            } else {
                and {
                    assert(res.v.protocolUpgradeHandler.lastFreezeStatusInUpgradeCycle == FreezeStatusSoft),
                    //assert(res.v.protocolUpgradeHandler.protocolFrozenUntil == 50 + 12 * 3600),
                    assert(res.v.protocolUpgradeHandler.protocolFrozenUntil == 12),
                    assert(res.v.zkFrozen),
                }
            }
            
        }
    }

    run upgrade_Flow_SecurityCouncil_Guardians_Test = {
        val members = Set("a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9", "a10", "a11", "a12")
        val guardiansMembers = Set("g1", "g2", "g3", "g4", "g5", "g6", "g7", "g8")
        val zkFoundationMultisig = newMultisig(members, 3)
        val sc = newSecurityCouncil(members)
        val proposerAddr = "0xPROPOSER"
        val guardians = newGuardians(guardiansMembers)
        if (isErr(sc) or isErr(guardians) or isErr(zkFoundationMultisig)) {
            assert(false)
        } else {
            
            val evm = {
                blockTimestamp: 50,
                securityCouncil: sc.v,
                guardians: guardians.v,
                zkFoundation: zkFoundationMultisig.v,
                protocolUpgradeHandler: {
                    securityCouncil: SECURITY_COUNCIL_ADDR,
                    guardians: GUARDIANS_ADDR,
                    emergencyUpgradeBoard: EMERGENCY_UPGRADE_BOARD_ADDR,
                    upgradeStatus: Map(),
                    lastFreezeStatusInUpgradeCycle: FreezeStatusNone,
                    protocolFrozenUntil: 0,
                },
                priorityQueue: [],
                frozenChains: Map(),
                zkFrozen: false,
                ghostCallHistory: {
                    lastSender: "",
                    calls: [],
                },
                emittedEvents: [
                    EventChangeSecurityCouncil((ZERO_ADDRESS, SECURITY_COUNCIL_ADDR)),
                    EventChangeGuardians((ZERO_ADDRESS, GUARDIANS_ADDR)),
                    EventChangeEmergencyUpgradeBoard((ZERO_ADDRESS, EMERGENCY_UPGRADE_BOARD_ADDR))
                ],
            }
            
            val proposal = { calls: "calls", executor: proposerAddr, salt: "salt" }
            val proposalId = keccak256_UpgradeProposal(proposal)
            val timestamp = evm.blockTimestamp
            
            val res1 = protocolUpgradeHandler::StartUpgrade(evm, proposal)
            if (isErr(res1)) {
                assert(false)
            } else {
                val newEvm1 = res1.v
                if (newEvm1.protocolUpgradeHandler.upgradeStatus.get(proposalId).guardiansApproval != false or
                        newEvm1.protocolUpgradeHandler.upgradeStatus.get(proposalId).creationTimestamp != timestamp or 
                        // upgradeState(newEvm1.protocolUpgradeHandler, evm.blockTimestamp+1000ma, proposalId) != UpgradeStateLegalVetoPeriod) {
                        upgradeState(newEvm1.protocolUpgradeHandler, evm.blockTimestamp+1, proposalId) != UpgradeStateLegalVetoPeriod) {
                    assert(false)
                } else {
                    
                    val evm1 = {...newEvm1, blockTimestamp: timestamp + UPGRADE_WAIT_OR_EXPIRE_PERIOD + STANDARD_LEGAL_VETO_PERIOD-2}.
                        externalCall(GUARDIANS_ADDR, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionApproveUpgradeGuardians)
                    val res2 = protocolUpgradeHandler::ApproveUpgradeGuardians(evm1, proposalId)
                    if (isErr(res2)) {
                        assert(false)
                    } else {
                        val newEvm2 = res2.v
                        if (upgradeState(newEvm1.protocolUpgradeHandler, evm1.blockTimestamp, proposalId) != UpgradeStateWaiting) {
                            assert(false)
                        } else {
                            val evm2 = {...newEvm2, blockTimestamp: timestamp + STANDARD_LEGAL_VETO_PERIOD + UPGRADE_DELAY_PERIOD}
                                .externalCall(SECURITY_COUNCIL_ADDR, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionApproveUpgradeSecurityCouncil)
                            val res3 = protocolUpgradeHandler::ApproveUpgradeSecurityCouncil(evm2, proposalId)
                            if (isErr(res3)) {
                                assert(false)
                            } else {
                                val newEvm3 = res3.v
                                val evm3 = {...newEvm3, blockTimestamp: timestamp + STANDARD_LEGAL_VETO_PERIOD + UPGRADE_DELAY_PERIOD + UPGRADE_DELAY_PERIOD + 1}
                                    .externalCall(proposerAddr, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionExecute)
                                val res4 = protocolUpgradeHandler::Execute(evm3, proposal)
                                if (isErr(res4)) {
                                    assert(false)
                                } else {
                                    val newEvm4 = res4.v
                                    assert(newEvm4.protocolUpgradeHandler.upgradeStatus.get(proposalId).executed == true) 
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    run upgrade_Flow_SecurityCouncil_Test = {
        val members = Set("a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9", "a10", "a11", "a12")
        val guardiansMembers = Set("g1", "g2", "g3", "g4", "g5", "g6", "g7", "g8")
        val zkFoundationMultisig = newMultisig(members, 3)
        val sc = newSecurityCouncil(members)
        val proposerAddr = "0xPROPOSER"
        val guardians = newGuardians(guardiansMembers)
        if (isErr(sc) or isErr(guardians) or isErr(zkFoundationMultisig)) {
            assert(false)
        } else {
            
            val evm0 = {
                blockTimestamp: 1,
                securityCouncil: sc.v,
                guardians: guardians.v,
                zkFoundation: zkFoundationMultisig.v,
                protocolUpgradeHandler: {
                    securityCouncil: SECURITY_COUNCIL_ADDR,
                    guardians: GUARDIANS_ADDR,
                    emergencyUpgradeBoard: EMERGENCY_UPGRADE_BOARD_ADDR,
                    upgradeStatus: Map(),
                    lastFreezeStatusInUpgradeCycle: FreezeStatusNone,
                    protocolFrozenUntil: 0,
                },
                priorityQueue: [],
                frozenChains: Map(),
                zkFrozen: false,
                ghostCallHistory: {
                    lastSender: "",
                    calls: [],
                },
                emittedEvents: [
                    EventChangeSecurityCouncil((ZERO_ADDRESS, SECURITY_COUNCIL_ADDR)),
                    EventChangeGuardians((ZERO_ADDRESS, GUARDIANS_ADDR)),
                    EventChangeEmergencyUpgradeBoard((ZERO_ADDRESS, EMERGENCY_UPGRADE_BOARD_ADDR))
                ]
            }
            
            val proposal = { calls: "calls", executor: proposerAddr, salt: "salt" }
            val proposalId = keccak256_UpgradeProposal(proposal)
            val timestamp = evm0.blockTimestamp
            
            val res1 = protocolUpgradeHandler::StartUpgrade(evm0, proposal)
            if (isErr(res1)) {
                assert(false)
            } else {
                val evm1 = {...res1.v, blockTimestamp: STANDARD_LEGAL_VETO_PERIOD+evm0.blockTimestamp}.
                    externalCall(SECURITY_COUNCIL_ADDR, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionApproveUpgradeSecurityCouncil)
                val res2 = protocolUpgradeHandler::ApproveUpgradeSecurityCouncil(evm1, proposalId)
                if (isErr(res2)) {
                    assert(false)
                } else {
                    val evm2 = {...res2.v, blockTimestamp: UPGRADE_WAIT_OR_EXPIRE_PERIOD }
                        .externalCall(proposerAddr, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionExecute)
                    val res3 = protocolUpgradeHandler::Execute(evm2, proposal)
                    if (isErr(res3)) {
                        assert(false)
                    } else {
                        val evm3 = res3.v
                        assert(evm3.protocolUpgradeHandler.upgradeStatus.get(proposalId).executed == true) 
                    }
                }
            }
        }
    }
}