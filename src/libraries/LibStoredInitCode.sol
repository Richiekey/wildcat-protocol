// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

library LibStoredInitCode {
  // Contract size limit is 24kb (24,576 bytes) as of Spurious Dragon
  // Subtract one for the STOP prefix.
  uint256 internal constant DeployableDataSizeLimit = 24_575;

  error InitCodeExceedsSizeLimit();

  function deployInitCode(bytes memory data) internal returns (address initCodeStorage) {
    assembly {
      let size := mload(data)
      // if (data.length > 24_575) revert InitCodeExceedsSizeLimit();
      if gt(size, DeployableDataSizeLimit) {
        mstore(0, 0xfa91252a)
        revert(0x1c, 0x04)
      }
      let createSize := add(size, 0x0b)
      // Prefix Code
      //
      // Has trailing STOP instruction so the deployed data
      // can not be executed as a smart contract.
      //
      // Instruction                | Stack
      // ----------------------------------------------------
      // PUSH2 size                 | size                  |
      // PUSH0                      | 0, size               |
      // DUP2                       | size, 0, size         |
      // PUSH1 10 (offset to STOP)  | 10, size, 0, size     |
      // PUSH0                      | 0, 10, size, 0, size  |
      // CODECOPY                   | 0, size               |
      // RETURN                     |                       |
      // STOP                       |                       |
      // ----------------------------------------------------

      // Shift (size + 1) to position it in front of the PUSH2 instruction.
      // Reuse `data.length` memory for the create prefix to avoid
      // unnecessary memory allocation.
      mstore(data, or(shl(64, add(size, 1)), 0x6100005f81600a5f39f300))
      // Deploy the code storage
      initCodeStorage := create(0, add(data, 21), createSize)
      // Restore `data.length`
      mstore(data, size)
    }
  }

  /**
   * @dev Returns the create2 prefix for a given deployer address.
   *      Equivalent to `uint256(uint160(deployer)) | (0xff << 160)`
   */
  function getCreate2Prefix(address deployer) internal pure returns (uint256 create2Prefix) {
    assembly {
      create2Prefix := or(deployer, 0xff0000000000000000000000000000000000000000)
    }
  }

  function calculateCreate2Address(
    uint256 create2Prefix,
    bytes32 salt,
    uint256 initCodeHash
  ) internal pure returns (address create2Address) {
    assembly {
      // Cache the free memory pointer so it can be restored
      // at the end
      let ptr := mload(0x40)

      // Write 0xff + address to bytes 11:32
      mstore(0x00, create2Prefix)

      // Write salt to bytes 32:64
      mstore(0x20, salt)

      // Write initcode hash to bytes 64:96
      mstore(0x40, initCodeHash)

      // Calculate create2 hash for token0, token1
      // The EVM only looks at the last 20 bytes, so the dirty
      // bits at the beginning do not need to be cleaned
      create2Address := keccak256(0x0b, 0x55)

      // Restore the free memory pointer
      mstore(0x40, ptr)
    }
  }

  function createWithStoredInitCode(address initCodeStorage) internal returns (address deployment) {
    deployment = createWithStoredInitCode(initCodeStorage, 0);
  }

  function createWithStoredInitCode(
    address initCodeStorage,
    uint256 value
  ) internal returns (address deployment) {
    assembly {
      let initCodePointer := mload(0x40)
      let initCodeSize := sub(extcodesize(initCodeStorage), 1)
      extcodecopy(initCodeStorage, initCodePointer, 1, initCodeSize)
      deployment := create(value, initCodePointer, initCodeSize)
    }
  }

  function create2WithStoredInitCode(
    address initCodeStorage,
    bytes32 salt
  ) internal returns (address deployment) {
    deployment = create2WithStoredInitCode(initCodeStorage, salt, 0);
  }

  function create2WithStoredInitCode(
    address initCodeStorage,
    bytes32 salt,
    uint256 value
  ) internal returns (address deployment) {
    assembly {
      let initCodePointer := mload(0x40)
      let initCodeSize := sub(extcodesize(initCodeStorage), 1)
      extcodecopy(initCodeStorage, initCodePointer, 1, initCodeSize)
      deployment := create2(value, initCodePointer, initCodeSize, salt)
    }
  }
}
