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

contract ReallyGoodVaultTest {
    ReallyGoodVault vault;
    address owner;

    function beforeEach() public {
        owner = address(this);
        ERC20Mock _asset = new ERC20Mock("Asset", "AST", 18);
        vault = new ReallyGoodVault(
            _asset,
            "ReallyGoodVault",
            "RGV",
            50,
            50,
            owner,
            address(0x1)
        );
    }

    /// Test constructor and basic settings
    function testConstructorAndSettings() public {
        Assert.notEqual(
            address(vault.asset()),
            address(0),
            "Asset address should not be 0"
        );
        Assert.equal(
            vault.name(),
            "ReallyGoodVault",
            "Name should be ReallyGoodVault"
        );
        Assert.equal(vault.symbol(), "RGV", "Symbol should be RGV");
        Assert.equal(
            vault.WITHDRAW_FEE(),
            uint16(50),
            "Withdraw fee should be 50"
        );
        Assert.equal(
            vault.MANAGEMENT_FEE(),
            uint16(50),
            "Management fee should be 50"
        );
        Assert.equal(
            vault.owner(),
            owner,
            "Owner should be the contract address"
        );
    }

    /// Test deposit and mint
    function testDepositAndMint() public {
        // ... Add your deposit and mint test cases here
    }

    /// Test withdraw and redeem
    function testWithdrawAndRedeem() public {
        // ... Add your withdraw and redeem test cases here
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
}
