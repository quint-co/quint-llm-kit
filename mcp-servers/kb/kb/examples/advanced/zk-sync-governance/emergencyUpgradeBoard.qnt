module emergencyUpgradeBoard {
    import guardians.* from "./guardians"
    import hashing.* from "./hashing"
    import multisig.* from "./multisig"
    import protocolUpgradeHandler.* from "./protocolUpgradeHandler"
    import securityCouncil.* from "./securityCouncil"
    import state.* from "./state"
    import types.* from "./types"

    /// -------------------------------------------------------------------------------------------
    /// EmergencyUpgradeBoard constants
    /// -------------------------------------------------------------------------------------------

    /// @dev EIP-712 TypeHash for the emergency protocol upgrade execution approved by the guardians.
    pure val EXECUTE_EMERGENCY_UPGRADE_GUARDIANS_TYPEHASH =
        keccak256_str("ExecuteEmergencyUpgradeGuardians(bytes32 id)");

    /// @dev EIP-712 TypeHash for the emergency protocol upgrade execution approved by the Security Council.
    pure val EXECUTE_EMERGENCY_UPGRADE_SECURITY_COUNCIL_TYPEHASH =
        keccak256_str("ExecuteEmergencyUpgradeSecurityCouncil(bytes32 id)");

    /// @dev EIP-712 TypeHash for the emergency protocol upgrade execution approved by the ZK Foundation.
    pure val EXECUTE_EMERGENCY_UPGRADE_ZK_FOUNDATION_TYPEHASH =
        keccak256_str("ExecuteEmergencyUpgradeZKFoundation(bytes32 id)");

    /// @notice Executes an emergency protocol upgrade approved by the Security Council, Guardians and ZK Foundation.
    /// @param _calls Array of `Call` structures specifying the calls to be made in the upgrade.
    /// @param _salt A bytes32 value used for creating unique upgrade proposal hashes.
    /// @param _guardiansSignatures Encoded signers & signatures from the guardians multisig, required to authorize the emergency upgrade.
    /// @param _securityCouncilSignatures Encoded signers & signatures from the Security Council multisig, required to authorize the emergency upgrade.
    /// @param _zkFoundationSignatures Signatures from the ZK Foundation multisig, required to authorize the emergency upgrade.
    pure def emergencyUpgradeBoard::ExecuteEmergencyUpgrade(
        evm: EvmState,
        _calls: UpgradeProposalCallsOpaque,
        _salt: Bytes32,
        _guardiansSignatures: Set[Signature],
        _securityCouncilSignatures: Set[Signature],
        _zkFoundationSignatures: Set[Signature]
    ) : Result[EvmState] = {
        val upgradeProposal: UpgradeProposal = {
            calls: _calls,
            salt: _salt,
            executor: EMERGENCY_UPGRADE_BOARD_ADDR,
        }
        val id = keccak256_UpgradeProposal(upgradeProposal)

        val securityCouncilDigest = _emergencyUpgradeBoardCouncilHashTypedDataV4( 
            keccak256(abi_encode2(EXECUTE_EMERGENCY_UPGRADE_GUARDIANS_TYPEHASH, id))
        )    

        val guardiansDigest = _emergencyUpgradeBoardCouncilHashTypedDataV4(
            keccak256(abi_encode2(EXECUTE_EMERGENCY_UPGRADE_SECURITY_COUNCIL_TYPEHASH, id))
        )

        val zkFoundationDigest = _emergencyUpgradeBoardCouncilHashTypedDataV4(
            keccak256(abi_encode2(EXECUTE_EMERGENCY_UPGRADE_ZK_FOUNDATION_TYPEHASH, id))
        )

        val e1 = require(isValidSignatureNow(evm.guardians.multisig, guardiansDigest, _guardiansSignatures), "Invalid guardians signatures")
        if (e1 != "" ) {
            err(evm, e1)
        } else {
            val e2 = require(isValidSignatureNow(evm.securityCouncil.multisig, securityCouncilDigest, _securityCouncilSignatures), "Invalid Security Council signatures") 
            if (e2 != "" ) {
                err(evm, e2)
            } else {
                val e3 = require(isValidSignatureNow(evm.zkFoundation, zkFoundationDigest, _zkFoundationSignatures), "Invalid ZK Foundation signatures")
                if (e3 != "" ) {
                    err(evm, e3)
                } else {
                    val evm2 = evm.internalCall(EMERGENCY_UPGRADE_BOARD_ADDR, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionExecuteEmergencyUpgrade)
                    protocolUpgradeHandler::ExecuteEmergencyUpgrade(evm2, upgradeProposal)
                }
            }
        }
    }
}