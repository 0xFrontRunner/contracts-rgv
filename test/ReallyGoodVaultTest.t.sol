// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import "../src/ReallyGoodVault.sol";
import "@solmate/tokens/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals) {}

    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }
}

contract ReallyGoodVaultTest is Test {
    ReallyGoodVault vault;
    address owner;
    address feeCollector;

    address user1;
    address user2;

    MockERC20 asset;

    function setUp() public {
        owner = address(0xAA);
        feeCollector = address(0x1);
        user1 = address(0x2);
        user2 = address(0x3);
        asset = new MockERC20("Asset", "AST", 8);
        vault = new ReallyGoodVault(
            asset,
            "ReallyGoodVault",
            "RGV",
            500,
            50,
            owner,
            feeCollector,
            100 * 1e8
        );

        asset.mint(user1, 10000000000000 * 1e8);
        asset.mint(user2, 10000000000000 * 1e8);
        vm.startPrank(owner);
        vault.whitelistContract(address(this), true);
        vault.whitelistContract(user1, true);
        vault.whitelistContract(user2, true);
        vault.initialVaultState(100 * 1e8, 100 * 1e8);
        vm.stopPrank();
    }

    /// Test constructor and basic settings
    function testConstructorAndSettings() public {}

    /// Test deposit and mint
    function testDepositAndMint() public {
        // ... deposit and mint test cases here
        vm.startPrank(user1);
        asset.approve(address(vault), 1000 * 1e8);
        vm.expectRevert(ReallyGoodVault.AmountTooSmall.selector);
        vault.deposit(99 * 1e8, user1);

        vault.deposit(100 * 1e8, user1);
        assertEq(vault.balanceOf(user1), 100 * 1e8);
        assertEq(vault.totalSupply(), 100 * 1e8);
        assertEq(asset.balanceOf(owner), 100 * 1e8);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(feeCollector), 0);
        vm.stopPrank();

        vm.startPrank(user2);
        asset.approve(address(vault), 1000 * 1e8);
        vm.expectRevert(ReallyGoodVault.AmountTooSmall.selector);
        vault.mint(99 * 1e8, user2);

        uint256 sharesToAssets = vault.convertToAssets(100 * 1e8);
        console.log("sharesToAssets", sharesToAssets);

        vault.mint(100 * 1e8, user2);
        assertEq(vault.balanceOf(user2), 100 * 1e8);
        assertEq(vault.totalSupply(), 200 * 1e8);
        assertEq(asset.balanceOf(owner), 200 * 1e8);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(feeCollector), 0);
        vm.stopPrank();
    }

    /// Test withdraw and redeem
    function testWithdrawAndRedeem() public {
        uint256 amount1 = 100 * 1e8;
        uint256 amountToLittle = 99 * 1e8;
        // ... Add your withdraw and redeem test cases here
        helperDeposit(user1, amount1);
        vm.startPrank(user1);
        vm.expectRevert(ReallyGoodVault.AmountTooSmall.selector);
        vault.withdraw(amountToLittle, user1, user1);

        // test withdraw as well as withdrawal queue
        assertEq(vault.withdrawalsLenght(), 0);
        assertEq(vault.withdrawalsIsEmpty(), true);

        vault.withdraw(amount1, user1, user1);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), 0);
        assertEq(vault.pendingBalance(user1), amount1);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.withdrawalsLenght(), 1);
        assertEq(vault.withdrawalsIsEmpty(), false);
        assertEq(vault.rear(), 1);
        assertEq(vault.front(), 0);

        (address recipient, uint256 shares, uint256 timestamp) = vault
            .getWithdrawalItem(0);
        assertEq(recipient, user1);
        assertEq(shares, vault.previewDeposit(amount1));
        assertEq(timestamp, block.timestamp);

        assertEq(asset.balanceOf(owner), amount1);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(feeCollector), 0);

        // test redeem
        uint256 shares2 = vault.previewDeposit(200 * 1e8);

        helperDeposit(user2, 200 * 1e8);

        console.log("shares2", shares2);
        console.log("totalSupply", vault.totalSupply());
        console.log("balanceOf", vault.balanceOf(user2));
        console.log("balance owner", asset.balanceOf(owner));

        vm.startPrank(user2);

        vm.expectRevert(ReallyGoodVault.AmountTooSmall.selector);
        vault.redeem(60 * 1e8, user2, user2);

        console.log("previewWithdraw", vault.previewRedeem(200 * 1e8));

        vault.redeem(shares2, user2, user2);
        vm.stopPrank();

        assertEq(vault.balanceOf(user2), 0);
        assertEq(vault.pendingBalance(user2), shares2);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.withdrawalsLenght(), 2);
        assertEq(vault.withdrawalsIsEmpty(), false);
        assertEq(vault.rear(), 2);
        assertEq(vault.front(), 0);
        (recipient, shares, timestamp) = vault.getWithdrawalItem(1);
        assertEq(recipient, user2);
        assertEq(shares, shares2);
        // assertEq(amount, 200 * 1e8);
        assertEq(timestamp, block.timestamp);
        // check withdrawal TVL
        uint256 tvl = vault.getOutstandingWithdrawalShares();
        assertEq(tvl, (100 * 1e8) + (200 * 1e8));
    }

    /// Test vault management logic
    function testVaultManagementLogic() public {
        // ... Add your vault management logic test cases here
    }

    /// Test access-controlled setter functions
    function testAccessControlledSetterFunctions() public {
        // ... Add your access-controlled setter functions test cases here
    }

    /// Test view functions
    function testViewFunctions() public {
        // ... Add your view functions test cases here
    }

    function helperDeposit(address user, uint256 amount) public {
        vm.startPrank(user);
        asset.approve(address(vault), amount);
        vault.deposit(amount, user);
        vm.stopPrank();
    }

    function helperWithdraw(address user, uint256 amount) public {
        vm.startPrank(user);
        vault.withdraw(amount, user, user);
        vm.stopPrank();
    }
}
