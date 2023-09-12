// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import 'src/interfaces/IVaultEventsAndErrors.sol';
import '../BaseVaultTest.sol';

contract WildcatMarketConfigTest is BaseVaultTest {
	function test_maximumDeposit(uint256 _depositAmount) external returns (uint256) {
		assertEq(vault.maximumDeposit(), parameters.maxTotalSupply);
		_depositAmount = bound(_depositAmount, 1, DefaultMaximumSupply);
		_deposit(alice, _depositAmount);
		assertEq(vault.maximumDeposit(), DefaultMaximumSupply - _depositAmount);
	}

	function test_maximumDeposit_SupplyExceedsMaximum() external returns (uint256) {
		_deposit(alice, parameters.maxTotalSupply);
		fastForward(365 days);
		assertEq(vault.totalSupply(), 110_000e18);
		assertEq(vault.maximumDeposit(), 0);
	}

	function test_maxTotalSupply() external returns (uint256) {
		assertEq(vault.maxTotalSupply(), parameters.maxTotalSupply);
		vm.prank(parameters.controller);
		vault.setMaxTotalSupply(10000);
		assertEq(vault.maxTotalSupply(), 10000);
	}

	function test_annualInterestBips() external returns (uint256) {
		assertEq(vault.annualInterestBips(), parameters.annualInterestBips);
		vm.prank(parameters.controller);
		vault.setAnnualInterestBips(10000);
		assertEq(vault.annualInterestBips(), 10000);
	}

	function test_liquidityCoverageRatio() external returns (uint256) {}

	function test_revokeAccountAuthorization(
		address _account
	) external asAccount(parameters.controller) {
		vm.expectEmit(address(vault));
		emit AuthorizationStatusUpdated(_account, AuthRole.WithdrawOnly);
		vault.revokeAccountAuthorization(_account);
		assertEq(
			uint(vault.getAccountRole(_account)),
			uint(AuthRole.WithdrawOnly),
			'account role should be WithdrawOnly'
		);
	}

	function test_revokeAccountAuthorization_NotController(address _account) external {
		vm.expectRevert(IVaultEventsAndErrors.NotController.selector);
		vault.revokeAccountAuthorization(_account);
	}

	function test_revokeAccountAuthorization_AccountBlacklisted(address _account) external {
		vm.prank(sentinel);
		vault.nukeFromOrbit(_account);
		vm.startPrank(parameters.controller);
		vm.expectRevert(IVaultEventsAndErrors.AccountBlacklisted.selector);
		vault.revokeAccountAuthorization(_account);
	}

	function test_grantAccountAuthorization(
		address _account
	) external asAccount(parameters.controller) {
		vm.expectEmit(address(vault));
		emit AuthorizationStatusUpdated(_account, AuthRole.DepositAndWithdraw);
		vault.grantAccountAuthorization(_account);
		assertEq(
			uint(vault.getAccountRole(_account)),
			uint(AuthRole.DepositAndWithdraw),
			'account role should be DepositAndWithdraw'
		);
	}

	function test_grantAccountAuthorization_NotController(address _account) external {
		vm.expectRevert(IVaultEventsAndErrors.NotController.selector);
		vault.grantAccountAuthorization(_account);
	}

	function test_grantAccountAuthorization_AccountBlacklisted(address _account) external {
		vm.prank(sentinel);
		vault.nukeFromOrbit(_account);
		vm.startPrank(parameters.controller);
		vm.expectRevert(IVaultEventsAndErrors.AccountBlacklisted.selector);
		vault.grantAccountAuthorization(_account);
	}

	function test_nukeFromOrbit(address _account) external asAccount(sentinel) {
		vm.expectEmit(address(vault));
		emit AuthorizationStatusUpdated(_account, AuthRole.Blocked);
		vault.nukeFromOrbit(_account);
		assertEq(
			uint(vault.getAccountRole(_account)),
			uint(AuthRole.Blocked),
			'account role should be Blocked'
		);
	}

	function test_nukeFromOrbit_BadLaunchCode(address _account) external {
		vm.expectRevert(IVaultEventsAndErrors.BadLaunchCode.selector);
		vault.nukeFromOrbit(_account);
	}

	function test_nukeFromOrbit_AccountBlacklisted(address _account) external {
		vm.startPrank(sentinel);
		vault.nukeFromOrbit(_account);
		vm.expectRevert(IVaultEventsAndErrors.AccountBlacklisted.selector);
		vault.nukeFromOrbit(_account);
	}

	function test_setMaxTotalSupply(
		uint256 _totalSupply,
		uint256 _maxTotalSupply
	) external asAccount(parameters.controller) {
		_totalSupply = bound(_totalSupply, 0, DefaultMaximumSupply);
		_maxTotalSupply = bound(_maxTotalSupply, _totalSupply, type(uint128).max);
		if (_totalSupply > 0) {
			_deposit(alice, _totalSupply);
		}
		vault.setMaxTotalSupply(_maxTotalSupply);
		assertEq(vault.maxTotalSupply(), _maxTotalSupply, 'maxTotalSupply should be _maxTotalSupply');
	}

	function test_setMaxTotalSupply_NotController(uint128 _maxTotalSupply) external {
		vm.expectRevert(IVaultEventsAndErrors.NotController.selector);
		vault.setMaxTotalSupply(_maxTotalSupply);
	}

	function test_setMaxTotalSupply_NewMaxSupplyTooLow(
		uint256 _totalSupply,
		uint256 _maxTotalSupply
	) external asAccount(parameters.controller) {
		_totalSupply = bound(_totalSupply, 1, DefaultMaximumSupply - 1);
		_maxTotalSupply = bound(_maxTotalSupply, 0, _totalSupply - 1);
		_deposit(alice, _totalSupply);
		vm.expectRevert(IVaultEventsAndErrors.NewMaxSupplyTooLow.selector);
		vault.setMaxTotalSupply(_maxTotalSupply);
	}

	function test_setAnnualInterestBips(
		uint16 _annualInterestBips
	) external asAccount(parameters.controller) {
		_annualInterestBips = uint16(bound(_annualInterestBips, 0, 10000));
		vault.setAnnualInterestBips(_annualInterestBips);
		assertEq(vault.annualInterestBips(), _annualInterestBips);
	}

	function test_setAnnualInterestBips_InterestRateTooHigh()
		external
		asAccount(parameters.controller)
	{
		vm.expectRevert(IVaultEventsAndErrors.InterestRateTooHigh.selector);
		vault.setAnnualInterestBips(10001);
	}

	function test_setAnnualInterestBips_NotController(uint16 _annualInterestBips) external {
		vm.expectRevert(IVaultEventsAndErrors.NotController.selector);
		vault.setAnnualInterestBips(_annualInterestBips);
	}

	function test_setLiquidityCoverageRatio(
		uint256 _liquidityCoverageRatio
	) external asAccount(parameters.controller) {
		_liquidityCoverageRatio = bound(_liquidityCoverageRatio, 0, 10000);
		vault.setLiquidityCoverageRatio(uint16(_liquidityCoverageRatio));
		assertEq(vault.liquidityCoverageRatio(), _liquidityCoverageRatio);
	}

	function test_setLiquidityCoverageRatio_IncreaseWhileDelinquent(
		uint256 _liquidityCoverageRatio
	) external asAccount(parameters.controller) {
		_liquidityCoverageRatio = bound(
			_liquidityCoverageRatio,
			parameters.liquidityCoverageRatio + 1,
			10000
		);
		_induceDelinquency();
		vm.expectEmit(address(vault));
		emit LiquidityCoverageRatioUpdated(uint16(_liquidityCoverageRatio));
		vault.setLiquidityCoverageRatio(uint16(_liquidityCoverageRatio));
		assertEq(vault.liquidityCoverageRatio(), _liquidityCoverageRatio);
	}

	function _induceDelinquency() internal {
		_deposit(alice, 1e18);
		_borrow(2e17);
		_requestWithdrawal(alice, 9e17);
	}

	// Vault already deliquent, LCR set to lower value
	function test_setLiquidityCoverageRatio_LiquidityCoverageRatioTooHigh()
		external
		asAccount(parameters.controller)
	{
		vm.expectRevert(IVaultEventsAndErrors.LiquidityCoverageRatioTooHigh.selector);
		vault.setLiquidityCoverageRatio(10001);
	}

	function test_setLiquidityCoverageRatio_NotController(uint16 _liquidityCoverageRatio) external {
		vm.expectRevert(IVaultEventsAndErrors.NotController.selector);
		vault.setLiquidityCoverageRatio(_liquidityCoverageRatio);
	}
}