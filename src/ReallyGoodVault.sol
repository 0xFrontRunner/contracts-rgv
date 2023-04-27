// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "@solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {Owned} from "@solmate/auth/Owned.sol";
import {ReentrancyGuard} from "@solmate/utils//ReentrancyGuard.sol";
import {Queue} from "./utils/Queue.sol";

contract ReallyGoodVault is ERC4626, Owned, ReentrancyGuard, Queue {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    uint16 public WITHDRAW_FEE;
    uint16 public MANAGEMENT_FEE;
    uint256 public minDeposit;
    State public vaultState;
    uint256 public totalAssetSnapshot;
    address public feeDistributor;

    mapping(address => uint256) public pendingBalance;
    mapping(address => bool) public whitelistedContract;

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint16 _withdrawFee,
        uint16 _managementFee,
        address _owner,
        address _feeDistributor,
        uint256 _minDeposit,
    ) ERC4626(_asset, _name, _symbol) Owned(_owner) {
        if (address(_asset) == address(0)) {
            revert InvalidAddress();
        }

        if (_owner == address(0)) {
            revert InvalidAddress();
        }

        if (_feeDistributor == address(0)) {
            revert InvalidAddress();
        }

        WITHDRAW_FEE = _withdrawFee;
        MANAGEMENT_FEE = _managementFee;
        feeDistributor = _feeDistributor;
    }

    /*///////////////////////////////////////////////////////////////
                         DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(
        uint256 assets,
        address receiver
    ) public override nonReentrant returns (uint256 shares) {
        _senderIsEligible();
        if (vaultState == State.PROCESSING) revert Paused();

        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    function mint(
        uint256 shares,
        address receiver
    ) public override nonReentrant returns (uint256 assets) {
        _senderIsEligible();
        if (vaultState == State.PROCESSING) revert Paused();

        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        beforeWithdraw(assets, shares);
        _burn(owner, shares);

        _mintPending(owner, shares);

        _queueWithdrawal(owner, receiver, assets, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        // asset.safeTransfer(receiver, assets); all withdrawal transfers must be processed by owner
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        _mintPending(owner, shares);

        _queueWithdrawal(owner, receiver, assets, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        // asset.safeTransfer(receiver, assets); all withdrawal transfers must be initiated by owner
    }

    function _queueWithdrawal(
        address owner,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal {
        enqueue(WithdrawalItem(receiver, assets, shares, block.timestamp));
        emit PendingWithdrawal(
            owner,
            receiver,
            assets,
            shares,
            block.timestamp,
            generateWithdrawalId(receiver, assets, shares, block.timestamp)
        );
    }

    function _burnPending(address _owner, uint256 _amount) internal {
        pendingBalance[_owner] -= _amount;
    }

    function _mintPending(address _owner, uint256 _amount) internal {
        pendingBalance[_owner] += _amount;
    }

    /*///////////////////////////////////////////////////////////////
                         VAULT-MANAGEMENT-LOGIC
    //////////////////////////////////////////////////////////////*/

    function setVaultState(State _vaultState) external onlyOwner {
        vaultState = _vaultState;
    }

    function setTotalAssets(uint256 _totalAssets) external onlyOwner {
        if (vaultState == State.OPEN) revert InvalidState();
        if (_totalAssets == 0) revert ZeroAmount();
        if (withdrawalsLenght() > 0) revert WithdrawalsPending();

        uint256 profit = totalAssetSnapshot < _totalAssets
            ? _totalAssets - totalAssetSnapshot
            : 0;
        uint256 mFee;
        if (profit > 0) mFee = _chargeManagementFee(profit);
        // set new value of shares after management fee
        totalAssetSnapshot = _totalAssets - mFee;
        // allow deposits and withdrawals again
        vaultState = State.OPEN;
    }

    function _chargeManagementFee(
        uint256 amount
    ) internal returns (uint256 fee) {
        // 0.5% = multiply by 10000 then divide by 50
        fee = amount.mulDivDown(MANAGEMENT_FEE, 10000);
        if (fee > 0) {
            asset.safeTransferFrom(msg.sender, feeDistributor, fee);
        }
    }

    function processWithdrawals(uint256 max) external onlyOwner {
        // only process withdrawals if vault is closed
        if (vaultState == State.OPEN) revert InvalidState();
        if (max == 0) revert ZeroAmount();
        uint256 lenght = withdrawalsLenght();
        if (max > lenght) max = lenght;
        uint256 processed = 0;
        while (processed < max && lenght > 0) {
            WithdrawalItem memory request = dequeue();
            // if (block.timestamp - request.timestamp < 24 hours) break;
            _processWithdrawal(request);
            processed++;
        }
    }

    function _processWithdrawal(WithdrawalItem memory request) internal {
        _burnPending(request.recipient, request.shares);
        uint256 amount = _chargeWithdrawFee(request.amount);
        asset.safeTransferFrom(msg.sender, request.recipient, amount);
        emit Withdrawal(
            request.recipient,
            request.shares,
            amount,
            block.timestamp,
            generateWithdrawalId(
                request.recipient,
                request.amount,
                request.shares,
                request.timestamp
            )
        );
    }

    function _chargeWithdrawFee(uint256 amount) internal returns (uint256) {
        // 0.5% = multiply by 10000 then divide by 50
        uint256 fee = amount.mulDivDown(WITHDRAW_FEE, 10000);
        if (fee > 0) {
            asset.safeTransferFrom(msg.sender, feeDistributor, fee);
        }
        return amount - fee;
    }

    /*///////////////////////////////////////////////////////////////
                         ACCESS-CONTROLLED-SETTER-FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setWithdrawFee(uint16 _withdrawFee) external onlyOwner {
        if (_withdrawFee == 0) revert ZeroAmount();
        if (_withdrawFee > 10000) revert InvalidAmount();
        WITHDRAW_FEE = _withdrawFee;
    }

    function setManagementFee(uint16 _managementFee) external onlyOwner {
        if (_managementFee == 0) revert ZeroAmount();
        if (_managementFee > 10000) revert InvalidAmount();
        MANAGEMENT_FEE = _managementFee;
    }

    function setFeeDistributor(address _feeDistributor) external onlyOwner {
        if (_feeDistributor == address(0)) revert InvalidAddress();
        feeDistributor = _feeDistributor;
    }

    function setWhitelistedContract(
        address _contract,
        bool _whitelisted
    ) external onlyOwner {
        if (_contract == address(0)) revert InvalidAddress();
        whitelistedContract[_contract] = _whitelisted;
    }

    function setMinAmount(uint256 _minAmount) external onlyOwner {
        if (_minAmount == 0) revert ZeroAmount();
        minAmount = _minAmount;
    }

    /*///////////////////////////////////////////////////////////////
                         VIEW-FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function allOutstandingWithdrawals() external view returns (uint256 sum) {
        for (uint256 i = front; i < rear; i++) {
            sum += withdrawals[i].amount;
        }
    }

    function totalAssets() public view override returns (uint256) {
        return totalAssetSnapshot;
    }

    function generateWithdrawalId(
        address r, // recipient
        uint256 a, // amount
        uint256 s, // shares
        uint256 t // timestamp
    ) public pure returns (uint256 id) {
        id = uint256(keccak256(abi.encodePacked(r, a, s, t)));
    }

    /*///////////////////////////////////////////////////////////////
                         INTERNAL-UTILS
    //////////////////////////////////////////////////////////////*/

    function _senderIsEligible() internal view {
        if (msg.sender != tx.origin) {
            if (!whitelistedContract[msg.sender]) {
                revert ContractNotWhitelisted();
            }
        }
    }

    function afterDeposit(uint256 amount, uint256) internal override {
        // Do something after depositing
        if(amount < minDeposit) revert AmountTooSmall();
        asset.safeTransferFrom(address(this), owner, amount);
    }

    function beforeWithdraw(uint256, uint256) internal view override {
        // Do something before withdrawing
        if (vaultState == State.PROCESSING) revert Paused();
        if(amount < minDeposit) revert AmountTooSmall();
    }

    /*///////////////////////////////////////////////////////////////
                       ENUMS/STURCTS
    //////////////////////////////////////////////////////////////*/

    enum State {
        OPEN,
        PROCESSING
    }

    struct WithdrawalRequest {
        address owner;
        uint256 shares;
        uint256 assets;
        uint256 timestamp;
    }

    /*///////////////////////////////////////////////////////////////
                       EVENTS
    //////////////////////////////////////////////////////////////*/

    event PendingWithdrawal(
        address indexed owner,
        address indexed receiver,
        uint256 assets,
        uint256 shares,
        uint256 timestamp,
        uint256 id
    );
    event Withdrawal(
        address indexed owner,
        uint256 amountAfterFee,
        uint256 shares,
        uint256 executedAt,
        uint256 id
    );

    /*///////////////////////////////////////////////////////////////
                        CUSTOM ERROR MESSAGES
    //////////////////////////////////////////////////////////////*/

    error ZeroAmount();
    error InvalidAddress();
    error InvalidAmount();
    error Paused();
    error InvalidState();
    error WithdrawalsPending();
    error ContractNotWhitelisted();
    error AmountTooSmall();
}
