module hashing {
    import types.* from "./types"

    type AbiElem = AbiStr(str) | AbiInt(int) | AbiUpgradeProposal(UpgradeProposal) | AbiL2Proposal(L2GovernorProposal)

    type AbiEncoded = List[AbiElem]

    // abi.encode(e1, e2, ..., e8) returns a structure of type AbiEncoded

    pure def abi_encode1(e1: AbiElem): AbiEncoded = {
        [e1]
    }

    pure def abi_encode2(e1: AbiElem, e2: AbiElem): AbiEncoded = {
        [e1, e2]
    }

    pure def abi_encode3(e1: AbiElem, e2: AbiElem, e3: AbiElem): AbiEncoded = {
        [e1, e2, e3]
    }

    pure def abi_encode4(e1: AbiElem, e2: AbiElem, e3: AbiElem, e4: AbiElem): AbiEncoded = {
        [e1, e2, e3, e4]
    }

    pure def keccak256(enc: AbiEncoded): AbiEncoded = {
        enc
    }

    pure def keccak256_UpgradeProposal(upg: UpgradeProposal): AbiElem = {
        AbiUpgradeProposal(upg)
    }

    pure def keccak256_str(s: str): AbiElem = {
        AbiStr(s)
    }


    // Given an already hashed struct, this function returns the hash of the fully encoded EIP712 message for this domain.
    // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/EIP712.sol#L107
    // In our modeling, the hash is simply the argument itself. It's perfect, though trivially reversible.
    pure def _hashTypedDataV4(name: Bytes, version: Bytes, structHash: AbiEncoded): AbiEncoded = {
        [ AbiStr(name), AbiStr(version)].concat(structHash)
    }

    pure def _guardiansHashTypedDataV4(structHash: AbiEncoded): AbiEncoded = {
        _hashTypedDataV4("guardians", "1", structHash)
    }

    pure def _securityCouncilHashTypedDataV4(structHash: AbiEncoded): AbiEncoded = {
        _hashTypedDataV4("SecurityCouncil", "1", structHash)
    }

    pure def _emergencyUpgradeBoardCouncilHashTypedDataV4(structHash: AbiEncoded): AbiEncoded = {
        _hashTypedDataV4("EmergencyUpgradeBoard", "1", structHash)
    }


}