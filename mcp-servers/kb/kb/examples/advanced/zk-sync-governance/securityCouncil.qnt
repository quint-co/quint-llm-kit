module securityCouncil {
    import hashing.* from "./hashing"
    import multisig.* from "./multisig"
    import protocolUpgradeHandler.* from "./protocolUpgradeHandler"
    import state.* from "./state"
    import types.* from "./types"

    /// -------------------------------------------------------------------------------------------
    /// Security council constants
    /// -------------------------------------------------------------------------------------------

    // EIP-712 TypeHash for protocol upgrades approval by the Security Council.
    pure val APPROVE_UPGRADE_SECURITY_COUNCIL_TYPEHASH = keccak256_str("ApproveUpgradeSecurityCouncil(bytes32 id)")

    // EIP-712 TypeHash for soft emergency freeze approval by the Security Council.
    pure val SOFT_FREEZE_SECURITY_COUNCIL_TYPEHASH = keccak256_str("SoftFreeze(uint256 nonce,uint256 validUntil)")

    // EIP-712 TypeHash for hard emergency freeze approval by the Security Council.
    pure val  HARD_FREEZE_SECURITY_COUNCIL_TYPEHASH = keccak256_str("HardFreeze(uint256 nonce,uint256 validUntil)")

    // EIP-712 TypeHash for setting threshold for soft freeze approval by the Security Council.
    pure val  SET_SOFT_FREEZE_THRESHOLD_TYPEHASH = keccak256_str("SetSoftFreezeThreshold(uint256 threshold,uint256 nonce,uint256 validUntil)")

    // EIP-712 TypeHash for unfreezing the protocol upgrade by the Security Council.
    pure val UNFREEZE_TYPEHASH = keccak256_str("Unfreeze(uint256 nonce,uint256 validUntil)")

    // The default threshold for soft freeze initiated by the Security Council.
    pure val SOFT_FREEZE_CONSERVATIVE_THRESHOLD = 9
    
    // The recommended threshold parameter for soft freeze initiated by the Security Council.
    pure val RECOMMENDED_SOFT_FREEZE_THRESHOLD = 3
    
    // The number of signatures needed to trigger hard freeze.
    pure val HARD_FREEZE_THRESHOLD = 9

    /// @dev The number of signatures needed to approve upgrade.
    pure val APPROVE_UPGRADE_SECURITY_COUNCIL_THRESHOLD = 6;

    /// @dev The number of signatures needed to unfreeze the protocol.
    pure val UNFREEZE_THRESHOLD = 9;

    /// @notice SecurityCouncil contract initialization
    /// @dev Initializes the Security Council contract with predefined members and setup for EIP-712.
    /// @param _protocolUpgradeHandler The address of the protocol upgrade handler contract, responsible for executing the upgrades.
    /// @param _members Array of addresses representing the members of the Security Council.
    /// Expected to be sorted in ascending order without duplicates.
    pure def newSecurityCouncil(_members: Set[Address]): Result[SecurityCouncilState] = {
        pure val multisig = newMultisig(_members, 9)
        pure val empty = { multisig: multisig.v, softFreezeThreshold: 0, softFreezeNonce: 0, hardFreezeNonce: 0, softFreezeThresholdSettingNonce: 0, unfreezeNonce: 0 }
        if (isOk(multisig)) {
            pure val membersSize = _members.size()
            pure val e = require(membersSize == 12, "SecurityCouncil requires exactly 12 members")
            if (e != "") {
                err(empty, e)
            } else {
                ok({
                    multisig: multisig.v,
                    softFreezeThreshold : RECOMMENDED_SOFT_FREEZE_THRESHOLD,
                    softFreezeNonce: 0,
                    hardFreezeNonce: 0,
                    softFreezeThresholdSettingNonce: 0,
                    unfreezeNonce: 0
                })
            }
        } else {
            err(empty, multisig.err)
        }
    }

    /// @notice Approves ZKsync protocol upgrade, by the 6 out of 12 Security Council approvals.
    /// @param _id Unique identifier of the upgrade proposal to be approved.
    /// @param _signers An array of signers associated with the signatures.
    /// @param _signatures An array of signatures from council members approving the upgrade.
    pure def securityCouncil::ApproveUpgradeSecurityCouncil(evm: EvmState, _id: AbiElem, _signers: Set[Address], _signatures: Set[Signature]): Result[EvmState] = {
        val self = evm.securityCouncil
        val digest = _securityCouncilHashTypedDataV4([_id])
        val e = self.multisig.checkSignatures(digest, _signers, _signatures, APPROVE_UPGRADE_SECURITY_COUNCIL_THRESHOLD)
        if (e != "") err(evm, e) else {
            val evm2 = evm.internalCall(SECURITY_COUNCIL_ADDR, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionApproveUpgradeSecurityCouncil)
            protocolUpgradeHandler::ApproveUpgradeSecurityCouncil(evm2, _id)
        }
    }

    /// @notice Initiates the protocol soft freeze by small threshold of the Security Council members.
    /// @param _validUntil The timestamp until which the signature should remain valid.
    /// @param _signers An array of signers associated with the signatures.
    /// @param _signatures An array of signatures from council members approving the freeze.
    pure def securityCouncil::SoftFreeze(evm: EvmState, _validUntil: Uint256, _signers: Set[Address], _signatures: Set[Signature]): Result[EvmState] = {
        val e = require(evm.blockTimestamp < _validUntil, "Signature expired")
        pure val self = evm.securityCouncil
        if (e != "") err(evm, e) else {
            val digest = _securityCouncilHashTypedDataV4(
                keccak256(abi_encode3(SOFT_FREEZE_SECURITY_COUNCIL_TYPEHASH, AbiInt(self.softFreezeNonce), AbiInt(_validUntil)))
            )
            pure val self2 = { ...self, softFreezeNonce: self.softFreezeNonce + 1 }
            val e2 = checkSignatures(self.multisig, digest, _signers, _signatures, self.softFreezeThreshold)
            if (e2 != "" ) {
                err({ ...evm, securityCouncil: self2 }, e2)
            } else {
                // Reset threshold
                pure val self3 = {
                    ...self2,
                    softFreezeThreshold: SOFT_FREEZE_CONSERVATIVE_THRESHOLD,
                }
                val evm2 = {
                    ...evm,
                    securityCouncil: self3,
                }.internalCall(SECURITY_COUNCIL_ADDR, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionSoftFreeze)
                protocolUpgradeHandler::SoftFreeze({ ...evm2, securityCouncil: self3 })
            }
        }
    }

    /// @notice Initiates the protocol hard freeze by majority of the Security Council members.
    /// @param _validUntil The timestamp until which the signature should remain valid.
    /// @param _signers An array of signers associated with the signatures.
    /// @param _signatures An array of signatures from council members approving the freeze.
    pure def securityCouncil::HardFreeze(evm: EvmState, _validUntil: Uint256, _signers: Set[Address], _signatures: Set[Signature]): Result[EvmState] = {
        val e = require(evm.blockTimestamp < _validUntil, "Signature expired")
        pure val self = evm.securityCouncil

        if (e != "") err(evm, e) else {
            val digest = _securityCouncilHashTypedDataV4(
                keccak256(abi_encode3(HARD_FREEZE_SECURITY_COUNCIL_TYPEHASH, AbiInt(self.softFreezeNonce), AbiInt(_validUntil)))
            )
            pure val self2 = { ...self, hardFreezeNonce: self.hardFreezeNonce + 1 }
            val e2 = checkSignatures(self.multisig, digest, _signers, _signatures, HARD_FREEZE_THRESHOLD)
            if (e2 != "" ) {
                err({ ...evm, securityCouncil: self2 }, e2)
            } else {
                val evm2 = {
                    ...evm,
                    securityCouncil: self2,
                }.internalCall(SECURITY_COUNCIL_ADDR, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionHardFreeze)
                protocolUpgradeHandler::HardFreeze({ ...evm2, securityCouncil: self2 })
            }
        }
    }

    /// @notice Initiates the protocol unfreeze by the Security Council members.
    /// @param _validUntil The timestamp until which the signature should remain valid.
    /// @param _signers An array of signers associated with the signatures.
    /// @param _signatures An array of signatures from council members approving the unfreeze.
    pure def securityCouncil::Unfreeze(evm: EvmState, _validUntil: Uint256, _signers: Set[Address], _signatures: Set[Signature]): Result[EvmState] = {
        val e = require(evm.blockTimestamp < _validUntil, "Signature expired")
        pure val self = evm.securityCouncil

        if (e != "") err(evm, e) else {
            val digest = _securityCouncilHashTypedDataV4(
                keccak256(abi_encode3(UNFREEZE_TYPEHASH, AbiInt(self.unfreezeNonce), AbiInt(_validUntil)))
            )
            pure val self2 = { ...self, unfreezeNonce: self.unfreezeNonce + 1 }
            val e2 = checkSignatures(self.multisig, digest, _signers, _signatures, UNFREEZE_THRESHOLD)
            if (e2 != "" ) {
                err({ ...evm, securityCouncil: self2 }, e2)
            } else {
                val evm2 = {
                    ...evm,
                    securityCouncil: self2,
                }.internalCall(SECURITY_COUNCIL_ADDR, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionUnfreeze)
                protocolUpgradeHandler::Unfreeze({ ...evm2, securityCouncil: self2 })
            }
        }
    }

    /// @notice Sets the threshold for triggering a soft freeze.
    /// @param _threshold New threshold for the Security Council members for approving the soft freeze.
    /// @param _validUntil The timestamp until which the signature should remain valid.
    /// @param _signers An array of signers associated with the signatures.
    /// @param _signatures An array of signatures from council members approving the threshold setting.
    pure def securityCouncil::SetSoftFreezeThreshold(evm: EvmState, _threshold: Uint256, _validUntil: Uint256, _signers: Set[Address], _signatures: Set[Signature]): Result[EvmState] = {
        val e = require(_threshold > 0, "Threshold is too small").
            andRequire(_threshold <= SOFT_FREEZE_CONSERVATIVE_THRESHOLD, "Threshold is too big").
            andRequire(evm.blockTimestamp < _validUntil, "Signature expired");
        pure val self = evm.securityCouncil

        if (e != "") err(evm, e) else {
            val digest = _securityCouncilHashTypedDataV4(
                keccak256(abi_encode4(SET_SOFT_FREEZE_THRESHOLD_TYPEHASH, AbiInt(_threshold), AbiInt(self.softFreezeThresholdSettingNonce), AbiInt(_validUntil)))
            )
            pure val self2 = { ...self, softFreezeThresholdSettingNonce: self.softFreezeThresholdSettingNonce + 1 }
            val e2 = checkSignatures(self.multisig, digest, _signers, _signatures, SOFT_FREEZE_CONSERVATIVE_THRESHOLD)
            if (e2 != "" ) {
                err({ ...evm, securityCouncil: self2 }, e2)
            } else {
                pure val self3 = {
                    ...self2,
                    softFreezeThreshold: _threshold,
                }
                ok({ ...evm, securityCouncil: self3})
                
            }
        }
    }
}