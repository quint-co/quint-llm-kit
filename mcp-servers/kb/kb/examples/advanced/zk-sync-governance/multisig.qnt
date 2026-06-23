module multisig {
    import hashing.* from "./hashing"
    import state.* from "./state"
    import types.* from "./types"
 
    /// -------------------------------------------------------------------------------------------
    /// EIP1271 constants
    /// -------------------------------------------------------------------------------------------

    // EIP1271 magic value meaning that the signature is correct.
    pure val EIP1271_MAGICVALUE = "0x1626ba7e"

    // Multisig contract initialization
    pure def newMultisig(_members: Set[Address], _eip1271Threshold: Uint256): Result[MultisigState] = {
        pure val e = require(_eip1271Threshold > 0, "EIP-1271 threshold is too small").
                    andRequire(_eip1271Threshold <= _members.size(), "EIP-1271 threshold is too big").
                    andRequire(not(_members.contains(ZERO_ADDRESS)), "Zero address member")
        if (e != "") {
            err({ members: Set(), EIP1271_THRESHOLD: 0 }, e)
        } else {
            pure val v = { members: _members, EIP1271_THRESHOLD: _eip1271Threshold }
            ok(v)
        }
    }

    // The function to check if the provided signatures meet the threshold requirement.
    // Signatures must be from unique members and are expected in the same order as the members list (sorted order).
    // @param _digest The hash of the data being signed.
    // @param _signers An array of signers associated with the signatures.
    // @param _signatures An array of signatures to be validated.
    // @param _threshold The minimum number of valid signatures required to pass the check.
    pure def checkSignatures(self: MultisigState, _digest: AbiEncoded, _signers: Set[Address], _signatures: Set[Signature], _threshold: Uint256): Error = {
        // Ensure the total number of signatures meets or exceeds the threshold.
        // In our modeling, we do not check signatures against the digest.
        val signaturesLength = _signatures.size()
        val signersLength = _signers.size()
        // Ensure the total number of signatures meets or exceeds the threshold.
        require(signaturesLength >= _threshold, "Insufficient valid signatures")
            .andRequire(signersLength == signaturesLength, "Inconsistent signers/signatures length")
            // Ensure validity of the signatures and signers, within model
            .andRequire(_signers == _signatures.map(s => s.signer), "Signature verification failed")
            .andRequire(_signers.subseteq(self.members), "Signer is not a member")
            .andRequire(_signatures.forall(s => s.digest == _digest), "Digest invalid")
    }

    /// @dev The function to check if the provided signatures are valid and meet predefined threshold.
    /// @param _digest The hash of the data being signed.
    /// @param _signature An array of signers and signatures to be validated ABI encoded from `address[], bytes[]` to `abi.decode(data,(address[],bytes[]))`.
    pure def isValidSignature(self: MultisigState, _digest: AbiEncoded, _signature: Set[Signature]): Bytes4 = {
        pure val err = self.checkSignatures(_digest, _signature.map(s => s.signer), _signature, self.EIP1271_THRESHOLD)
        if (err != "") err
        else EIP1271_MAGICVALUE
    }

    /// @dev Should return whether the signature provided is valid for the provided data
    /// @param hash      Hash of the data to be signed
    /// @param signature Signature byte array associated with _data
    pure def isValidSignatureNow(self: MultisigState, _digest: AbiEncoded, _signature: Set[Signature]): bool = {
        isValidSignature(self, _digest, _signature) == EIP1271_MAGICVALUE
    }
}