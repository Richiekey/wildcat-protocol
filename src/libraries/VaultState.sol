// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import './BoolUtils.sol';
import './MathUtils.sol';
import './SafeCastLib.sol';
import '../interfaces/IVaultEventsAndErrors.sol';
import { AuthRole } from '../interfaces/WildcatStructsAndEnums.sol';

using VaultStateLib for VaultState global;
using VaultStateLib for Account global;
using BoolUtils for bool;

// scaleFactor = 112 bits
// RAY = 89 bits
// normalize(x) = (x * scaleFactor) / RAY
// which can grow x by 23 bits
// for 128 bit scaled amounts, normalized amounts can't exceed 105 bits (104 since that's a valid type)

/*
rayDiv of normalized amount `x` can reduce result by 23 bits
rayMul of scaled amount `x` can increase result by 23 bits
scaled amount always

*/

struct VaultState {
	uint128 maxTotalSupply;
	uint128 accruedProtocolFees;
	// Underlying assets reserved for protocol fees and withdrawals
	uint128 reservedAssets;
	// Scaled token supply (divided by scaleFactor)
	uint104 scaledTotalSupply;
	// Scaled token amount in withdrawal batches that have not been
	// paid by borrower yet.
	uint104 scaledPendingWithdrawals;
	uint32 pendingWithdrawalExpiry;
	// Whether vault is currently delinquent (liquidity under requirement)
	bool isDelinquent;
	// Seconds borrower has been delinquent
	uint32 timeDelinquent;
	// Annual interest rate accrued to lenders, in basis points
	uint16 annualInterestBips;
	// Percentage of outstanding balance that must be held in liquid reserves
	uint16 liquidityCoverageRatio;
	// Ratio between internal balances and underlying token amounts
	uint112 scaleFactor;
	uint32 lastInterestAccruedTimestamp;
}

struct Account {
	AuthRole approval;
	uint104 scaledBalance;
}

library VaultStateLib {
	using MathUtils for uint256;
	using SafeCastLib for uint256;

	// =====================================================================//
	//                            Read Methods                              //
	// =====================================================================//

	/// @dev Returns the normalized total supply of the vault.
	function totalSupply(VaultState memory state) internal pure returns (uint256) {
		return state.normalizeAmount(state.scaledTotalSupply);
	}

	/// @dev Returns the maximum amount of tokens that can be deposited without
	///      reaching the maximum total supply.
	function maximumDeposit(VaultState memory state) internal pure returns (uint256) {
		return uint256(state.maxTotalSupply).satSub(state.totalSupply());
	}

	/// @dev Normalize an amount of scaled tokens using the current scale factor.
	function normalizeAmount(
		VaultState memory state,
		uint256 amount
	) internal pure returns (uint256) {
		return amount.rayMul(state.scaleFactor);
	}

	/// @dev Scale an amount of normalized tokens using the current scale factor.
	function scaleAmount(VaultState memory state, uint256 amount) internal pure returns (uint256) {
		return amount.rayDiv(state.scaleFactor);
	}

	/**
	 * Collateralization requires all pending withdrawals be covered
	 * and coverage ratio for remaining liquidity.
	 */
	function liquidityRequired(
		VaultState memory state
	) internal pure returns (uint256 _liquidityRequired) {
		uint256 scaledWithdrawals = state.scaledPendingWithdrawals;
		uint256 scaledCoverageLiquidity = (state.scaledTotalSupply - scaledWithdrawals).bipMul(
			state.liquidityCoverageRatio
		) + scaledWithdrawals;
		return
			state.normalizeAmount(scaledCoverageLiquidity) +
			state.accruedProtocolFees +
			state.reservedAssets;
	}

	function liquidAssets(
		VaultState memory state,
		uint256 totalAssets
	) internal pure returns (uint256) {
		return totalAssets.satSub(state.reservedAssets + state.accruedProtocolFees);
	}

	function hasPendingBatch(VaultState memory state) internal pure returns (bool) {
		return state.pendingWithdrawalExpiry != 0;
	}

	function hasPendingExpiredBatch(VaultState memory state) internal view returns (bool result) {
		uint256 expiry = state.pendingWithdrawalExpiry;
		assembly {
			// Equivalent to expiry > 0 && expiry <= block.timestamp
			result := gt(timestamp(), sub(expiry, 1))
		}
	}

	// =====================================================================//
	//                        Simple State Updates                          //
	// =====================================================================//

	/// @dev Decrease the scaled total supply.
	function decreaseScaledTotalSupply(VaultState memory state, uint256 scaledAmount) internal pure {
		state.scaledTotalSupply -= scaledAmount.toUint104();
	}

	/// @dev Increase the scaled total supply.
	function increaseScaledTotalSupply(VaultState memory state, uint256 scaledAmount) internal pure {
		state.scaledTotalSupply += scaledAmount.toUint104();
	}

	function decreaseScaledBalance(Account memory account, uint256 scaledAmount) internal pure {
		account.scaledBalance -= scaledAmount.toUint104();
	}

	function increaseScaledBalance(Account memory account, uint256 scaledAmount) internal pure {
		account.scaledBalance += scaledAmount.toUint104();
	}
}