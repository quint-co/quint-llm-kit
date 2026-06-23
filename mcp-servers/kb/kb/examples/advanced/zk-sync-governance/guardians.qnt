module guardians {
    import hashing.* from "./hashing"
    import multisig.* from "./multisig"
    import protocolUpgradeHandler.* from "./protocolUpgradeHandler"
    import state.* from "./state"
    import types.* from "./types"

    /// -------------------------------------------------------------------------------------------
    /// Guardians constants
    /// -------------------------------------------------------------------------------------------

    /// @dev EIP-712 TypeHash for extending the legal veto period by the guardians.
    pure val EXTEND_LEGAL_VETO_PERIOD_TYPEHASH = keccak256_str("ExtendLegalVetoPeriod(bytes32 id)");

    /// @dev EIP-712 TypeHash for protocol upgrades approval by the guardians.
    pure val APPROVE_UPGRADE_GUARDIANS_TYPEHASH = keccak256_str("ApproveUpgradeGuardians(bytes32 id)");

    /// @dev EIP-712 TypeHash for canceling the L2 proposals by the guardians.
    pure val CANCEL_L2_GOVERNOR_PROPOSAL_TYPEHASH = keccak256_str(
        "CancelL2GovernorProposal(uint256 l2ProposalId,address l2GovernorAddress,uint256 l2GasLimit,uint256 l2GasPerPubdataByteLimit,address refundRecipient,uint256 txMintValue,uint256 nonce)"
    );

    /// @dev EIP-712 TypeHash for proposing the L2 proposals by the guardians.
    pure val PROPOSE_L2_GOVERNOR_PROPOSAL_TYPEHASH = keccak256_str(
        "ProposeL2GovernorProposal(uint256 l2ProposalId,address l2GovernorAddress,uint256 l2GasLimit,uint256 l2GasPerPubdataByteLimit,address refundRecipient,uint256 txMintValue,uint256 nonce)"
    );

    /// @dev The number of signatures needed to approve the upgrade by guardians.
    pure val APPROVE_UPGRADE_GUARDIANS_THRESHOLD = 5;

    /// @dev The number of signatures needed to extend the legal veto period for the upgrade.
    pure val EXTEND_LEGAL_VETO_THRESHOLD = 2;

    /// @dev The number of signatures needed to cancel the proposal on one of the L2 Governors.
    pure val CANCEL_L2_GOVERNOR_PROPOSAL_THRESHOLD = 5;

    /// @dev The number of signatures needed to propose the proposal on one of the L2 Governors.
    pure val PROPOSE_L2_GOVERNOR_PROPOSAL_THRESHOLD = 5;

    /// @dev Initializes the Guardians contract with predefined members and setup for EIP-712.
    /// @param _protocolUpgradeHandler The address of the protocol upgrade handler contract, responsible for executing the upgrades.
    /// @param _members Array of addresses representing the members of the guardians.
    pure def newGuardians(_members: Set[Address]): Result[GuardiansState] = {
        pure val multisig = newMultisig(_members, 5)
        pure val empty = { multisig: multisig.v, nonce: 0}
        if (isOk(multisig)) {
            pure val membersSize = _members.size()
            pure val e = require(membersSize == 8, "Guardians requires exactly 8 members")
            if (e != "") {
                err(empty, e)
            } else {
                ok({
                    multisig: multisig.v,
                    nonce: 0,
                })
            }
        } else {
            err(empty, multisig.err)
        }
    }

    /// @notice Extends legal veto period for ZKsync protocol upgrade, by the 2 out of 8 Guardians approvals.
    /// @param _id The unique identifier of the upgrade proposal.
    /// @param _signers An array of signers associated with the signatures.
    /// @param _signatures An array of signatures from the guardians approving the extend.
    pure def guardians::ExtendLegalVeto(evm: EvmState, _id: AbiElem, _signers: Set[Address], _signatures: Set[Signature]): Result[EvmState] = {
        val self = evm.guardians
        val digest = _guardiansHashTypedDataV4([EXTEND_LEGAL_VETO_PERIOD_TYPEHASH, _id])
        val e = self.multisig.checkSignatures(digest, _signers, _signatures, EXTEND_LEGAL_VETO_THRESHOLD)
        val evm2 = evm.internalCall(GUARDIANS_ADDR, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionExtendLegalVeto)
        if (e != "") err(evm, e) else protocolUpgradeHandler::ExtendLegalVeto(evm2, _id)
    }

    /// @notice Approves ZKsync protocol upgrade, by the 5 out of 8 Guardians approvals.
    /// @param _id The unique identifier of the upgrade proposal.
    /// @param _signers An array of signers associated with the signatures.
    /// @param _signatures An array of signatures from the guardians approving the upgrade.
    pure def guardians::ApproveUpgradeGuardians(evm: EvmState, _id: AbiElem, _signers: Set[Address], _signatures: Set[Signature]): Result[EvmState] = {
        val self = evm.guardians
        val digest = _guardiansHashTypedDataV4([APPROVE_UPGRADE_GUARDIANS_TYPEHASH, _id])
        val e = self.multisig.checkSignatures(digest, _signers, _signatures, APPROVE_UPGRADE_GUARDIANS_THRESHOLD)
        val evm2 = evm.internalCall(GUARDIANS_ADDR, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionApproveUpgradeGuardians)
        if (e != "") err(evm, e) else protocolUpgradeHandler::ApproveUpgradeGuardians(evm2, _id)
    }

    /// @notice Propose ZKsync proposal on one the L2 governors, by the 5 of 8 Guardians approvals.
    /// @param _l2Proposal The L2 governor proposal to be proposed.
    /// @param _txRequest The L1 -> L2 transaction parameters needed to request execution on L2.
    /// @param _signers An array of signers associated with the signatures.
    /// @param _signatures An array of signatures from the guardians approving the upgrade.
    pure def guardians::ProposeL2GovernorProposal(evm: EvmState,
            _l2Proposal: L2GovernorProposalOpaque,
            _txRequest: TxRequestOpaque,
            _signers: Set[Address],
            _signatures: Set[Signature]): Result[EvmState] = {
        val self = evm.guardians
        val digest = _guardiansHashTypedDataV4(
            [ PROPOSE_L2_GOVERNOR_PROPOSAL_TYPEHASH, AbiStr(_l2Proposal), AbiStr(_txRequest), AbiInt(evm.guardians.nonce) ]
        )
        val e = self.multisig.checkSignatures(digest, _signers, _signatures, PROPOSE_L2_GOVERNOR_PROPOSAL_THRESHOLD)
        val proposeCalldata = [ AbiStr("IL2Governor.propose"), AbiStr(_l2Proposal) ]
        val l2tx = { proposeCalldata: proposeCalldata }
        val newGuardians = { ...evm.guardians, nonce: evm.guardians.nonce + 1 }
        if (e != "") err(evm, e) else ok({ ...evm, priorityQueue: evm.priorityQueue.append(l2tx), guardians: newGuardians })
    }

    /// @notice Cancel ZKsync proposal in one of the L2 governors, by the 5 of 8 Guardians approvals.
    /// @param _l2Proposal The L2 governor proposal to be proposed.
    /// @param _txRequest The L1 -> L2 transaction parameters needed to request execution on L2.
    /// @param _signers An array of signers associated with the signatures.
    /// @param _signatures An array of signatures from the guardians approving the upgrade.
    pure def guardians::CancelL2GovernorProposal(evm: EvmState,
            _l2Proposal: L2GovernorProposalOpaque,
            _txRequest: TxRequestOpaque,
            _signers: Set[Address],
            _signatures: Set[Signature]): Result[EvmState] = {
        val self = evm.guardians
        val digest = _guardiansHashTypedDataV4(
            [ CANCEL_L2_GOVERNOR_PROPOSAL_TYPEHASH, AbiStr(_l2Proposal), AbiStr(_txRequest), AbiInt(evm.guardians.nonce) ]
        )
        val e = self.multisig.checkSignatures(digest, _signers, _signatures, CANCEL_L2_GOVERNOR_PROPOSAL_THRESHOLD)
        val proposeCalldata = [ AbiStr("IL2Governor.cancel"), AbiStr(_l2Proposal) ]
        val l2tx = { proposeCalldata: proposeCalldata }
        val newGuardians = { ...evm.guardians, nonce: evm.guardians.nonce + 1 }
        if (e != "") err(evm, e) else ok({ ...evm, priorityQueue: evm.priorityQueue.append(l2tx), guardians: newGuardians })
    }
}