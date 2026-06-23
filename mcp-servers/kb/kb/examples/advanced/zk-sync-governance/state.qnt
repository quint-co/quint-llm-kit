module state {
    import types.* from "./types"
    import hashing.* from "./hashing"

    val SECURITY_COUNCIL_ADDR = "0xSecurityCouncil"
    val PROTOCOL_UPGRADE_HANDLER_ADDR = "0xProtocolUpgradeHandler"
    val GUARDIANS_ADDR = "0xGuardians"
    val EMERGENCY_UPGRADE_BOARD_ADDR = "0xEmergencyUpgradeBoard"
    val ZERO_ADDRESS = "0x0"
    val ANY_ADDRESS = "0xAny"

    // a signed digest
    type Signature = {
        signer: Address,
        digest: AbiEncoded,
    }

    pure def signDigest(signers: Set[Address], digest: AbiEncoded): Set[Signature] = {
        signers.map(s => { signer: s, digest: digest })
    }

    type L2Transaction = {
        proposeCalldata: AbiEncoded,
    }

    type Event = 
        EventUpgradeStarted(UpgradeProposal) |
        EventUpgradeLegalVetoExtended(AbiElem) |
        EventUpgradeApprovedBySecurityCouncil(AbiElem) |
        EventUpgradeApprovedByGuardians(AbiElem) |
        EventUnfreeze |
        EventUpgradeExecuted(AbiElem) |
        EventEmergencyUpgradeExecutedSome |
        EventEmergencyUpgradeExecuted(AbiElem) |
        EventSoftFreeze(Uint256) |
        EventHardFreeze(Uint256) |
        EventReinforceFreeze |
        EventReinforceFreezeOneChain(Uint256) |
        EventReinforceUnfreeze |
        EventReinforceUnfreezeOneChain(Uint256) |
        EventChangeSecurityCouncil((Address, Address)) |
        EventChangeGuardians((Address, Address)) |
        EventChangeEmergencyUpgradeBoard((Address, Address))

    type Function = 
        FunctionApproveUpgradeSecurityCouncil |
        FunctionApproveUpgradeGuardians |
        FunctionSoftFreeze |
        FunctionHardFreeze |
        FunctionUnfreeze |
        FunctionSetSoftFreezeThreshold |
        FunctionStartUpgrade |
        FunctionExtendLegalVeto |
        FunctionExecute |
        FunctionExecuteEmergencyUpgrade |
        FunctionReinforceFreeze |
        FunctionReinforceUnfreeze |
        FunctionReinforceFreezeOneChain(Uint256) |
        FunctionReinforceUnfreezeOneChain(Uint256) |
        FunctionProposeL2GovernorProposal |
        FunctionCancelL2GovernorProposal |
        FunctionUpdateSecurityCouncil |
        FunctionUpdateGuardians |
        FunctionUpdateEmergencyUpgradeBoard
    
     pure def is_FunctionReinforceUnfreezeOneChain(f: Function): bool = {
        match (f) {
            | FunctionReinforceUnfreezeOneChain(_) => true
            | FunctionApproveUpgradeSecurityCouncil => false
            | FunctionApproveUpgradeGuardians => false
            | FunctionSoftFreeze => false
            | FunctionHardFreeze => false
            | FunctionUnfreeze => false
            | FunctionSetSoftFreezeThreshold => false
            | FunctionStartUpgrade => false
            | FunctionExecute => false
            | FunctionExtendLegalVeto => false
            | FunctionExecuteEmergencyUpgrade => false
            | FunctionReinforceFreeze => false
            | FunctionReinforceUnfreeze => false
            | FunctionReinforceFreezeOneChain(_) => false
            | FunctionProposeL2GovernorProposal => false
            | FunctionCancelL2GovernorProposal => false
            | FunctionUpdateSecurityCouncil => false
            | FunctionUpdateGuardians => false
            | FunctionUpdateEmergencyUpgradeBoard => false
        }
    }

    // An abstract contract implementing a basic multisig wallet functionality.
    // This contract allows a group of members to collectively authorize actions
    // by submitting a threshold number of valid signatures.
    type MultisigState = {
        // List of addresses authorized as members of the multisig.
        members: Set[Address],
        // @notice The threshold for EIP-1271 signature verification.
        EIP1271_THRESHOLD: Uint256
    }

    /// Protocol Upgrade Handler state
    /// @dev The contract that holds ownership of all ZKsync contracts (L1 and L2). It is responsible
    /// for handling ZKsync protocol upgrades proposed by L2 Token Assembly and executing it.
    ///
    /// The upgrade process follows these key stages:
    /// 1. Proposal: Token holders on L2 propose the protocol upgrades and send the L2 -> L1 message
    ///    that this contract reads and starts the upgrade process.
    /// 2. Legal veto: During this period, the guardians can veto the upgrade **offchain**. The default legal period review
    ///    takes 3 days but can be extended by guardians onchain for 7 days in total.
    /// 3. Approval: Requires approval from either the guardians or the Security Council. The Security Council can
    ///    immediately move the proposal to the next stage, while guardians approval will move the proposal to the
    ///    next stage only after 30 days delay after the legal veto passes. If no approval is received within the specified period, the proposal
    ///    is expired.
    /// 4. Pending: A mandatory delay period before the actual execution of the upgrade, allowing for final
    ///    preparations and reviews.
    /// 5. Execution: The proposed changes are executed by the authorized address in the proposal,
    ///    completing the upgrade process.
    ///
    /// The contract implements the state machine that represents the logic of moving upgrade from each
    /// stage by time changes and Guardians/Security Council actions.
    type ProtocolUpgradeHandlerState = {
        securityCouncil: Address,
        guardians: Address,
        emergencyUpgradeBoard: Address,
        upgradeStatus: AbiElem -> UpgradeStatus,
        lastFreezeStatusInUpgradeCycle: FreezeStatus,
        protocolFrozenUntil: Uint256,
    }

    /// SecurityCouncil contract state
    /// @dev The group of security experts who serve as a technical security service for ZKsync protocol.
    type SecurityCouncilState = {
        // Tracks the unique identifier used in the last successful soft emergency freeze,
        // to ensure each request is unique.
        softFreezeNonce: Uint256,
        // Tracks the unique identifier used in the last successful hard emergency freeze,
        // to ensure each request is unique.
        hardFreezeNonce: Uint256,
        // Tracks the unique identifier used in the last successful setting of the soft freeze threshold,
        // to ensure each request is unique.
        softFreezeThresholdSettingNonce: Uint256,
        // Tracks the unique identifier used in the last successful unfreeze.
        unfreezeNonce: Uint256,
        // Represents the number of signatures needed to trigger soft freeze.
        // This value is automatically reset to 9 after each soft freeze, but it can be
        // set by the 9 SC members and requires to be not bigger than 9.
        softFreezeThreshold: Uint256,
        // Multisig is stored here since dy design it is an abstract contratc
        multisig: MultisigState,
    }

    /// @dev Temporary protector of the values of ZKsync. They can approve upgrade changes proposed by the Token Assembly, propose & cancel
    /// L2 proposals as well as extend the legal veto period of L1 upgrade proposals through the `ProtocolUpgradeHandler`.
    type GuardiansState = {
        // @dev Tracks the unique identifier used in the last `cancelL2GovernorProposal`/`proposeL2GovernorProposal` to ensure replay attack protection.
        nonce: Uint256,
        // Multisig
        multisig: MultisigState
    }

    type EvmCallHistory = {
        lastSender: Address,
        calls: List[{ caller: Address, callee: Address, method: Function }]
    }

    type EvmState = {
        blockTimestamp: Uint256,
        protocolUpgradeHandler: ProtocolUpgradeHandlerState,
        securityCouncil: SecurityCouncilState,
        guardians: GuardiansState,
        priorityQueue: List[L2Transaction],
        // We do not interact with ZKSYNC_ERA in this model,
        // instead we have just a boolean variable indication whether we have frozen ZK contracts.
        zkFrozen: bool,
        // frozen chains
        frozenChains: ChainID -> bool,
        // the history of calls made in the last transaction
        ghostCallHistory: EvmCallHistory,
        // zk Foundation SAFE multisig
        zkFoundation: MultisigState,
        // events
        emittedEvents: List[Event],
    }

    def internalCall(evm: EvmState, msgSender: Address, callee: Address, method: Function): EvmState = {
        {
            ...evm,
            ghostCallHistory: {
                ...evm.ghostCallHistory,
                calls: evm.ghostCallHistory.calls.append({ caller: msgSender, callee: callee, method: method }),
                lastSender: msgSender
            }
        }
    }

    def externalCall(evm: EvmState, msgSender: Address, callee: Address, method: Function): EvmState = {
        {
            ...evm,
            ghostCallHistory: {
                calls: [ { caller: msgSender, callee: callee, method: method } ],
                lastSender: msgSender
            }
        }
    }

    pure def msgSender(evm: EvmState): Address = {
        evm.ghostCallHistory.lastSender
    }

    pure def getAllUpgradeIDs(evm: EvmState): Set[AbiElem] = {
        evm.protocolUpgradeHandler.upgradeStatus.keys()
    }

    // An auxiliary definition similar to Solidity's require
    pure def require(cond: bool, msg: str): str = {
        if (cond) "" else msg
    }

    // an easy way to chain require calls
    pure def andRequire(prevErr: str, cond: bool, msg: str): str = {
        if (prevErr != "") prevErr else require(cond, msg)
    }
}