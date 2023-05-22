// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title RefactoredEarlyAdopterPool
 * @dev Contract for a pool where users can deposit supported ERC20 tokens or Ether and earn points based on the amount of time and the amount deposited. Users can claim their points at a later time.
 */
contract RefactoredEarlyAdopterPool is Ownable, ReentrancyGuard, Pausable {
    using Math for uint256;

    error TokenTransferFailed();

    // After a certain time, claiming funds is not allowed and users will need to simply withdraw
    uint256 public claimDeadline;

    // Time when depositing closed and will be used for calculating rewards
    uint256 public endTime;

    // Address of the rEth contract : 0xae78736Cd615f374D3085123A210448E74Fc6393
    IERC20 private immutable _rETH;

    // Address of the wstEth contract : 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
    IERC20 private immutable _wstETH;

    // Address ofthe sfrxEth contract : 0xac3E018457B222d93114458476f3E3416Abbe38F
    IERC20 private immutable _sfrxETH;

    // Address of the cbEth contract : 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704
    IERC20 private immutable _cbETH;

    // Future contract which funds will be sent to on claim (Most likely LP)
    address public claimReceiverContract;

    // Status of claims, 1 means claiming is open
    uint8 public claimingOpen;

    // Mapping of user addresses to their deposit information
    mapping(address => UserDepositInfo) public depositInfo;

    // Mapping of user addresses to their token balances
    // user address => token address => balance
    mapping(address => mapping(IERC20 => uint256)) public userToErc20Balance;

    // Mapping of supported tokens
    mapping(IERC20 => bool) public isSupportedToken;

    struct UserDepositInfo {
        uint256 depositTime;
        uint256 etherBalance;
        uint256 totalERC20Balance;
    }

    // Modifier to check if deposit amount is between 0.1 ether and 100 ether
    modifier onlyCorrectAmount(uint256 _amount) {
        require(
            _amount >= 0.1 ether && _amount <= 100 ether,
            "Incorrect Deposit Amount"
        );
        _;
    }

    // Modifier to check if depositing is open
    modifier depositingOpen() {
        require(claimingOpen == 0, "Depositing closed");
        _;
    }

    /**
     * @dev Emitted when an ERC20 deposit is made
     * @param sender The address of the user making the deposit
     * @param amount The amount of ERC20 tokens deposited
     */
    event DepositERC20(address indexed sender, uint256 amount);

    /**
     * @dev Emitted when an Ether deposit is made
     * @param sender The address of the user making the deposit
     * @param amount The amount of Ether deposited
     */
    event DepositEth(address indexed sender, uint256 amount);

    /**
     * @dev Emitted when a user withdraws their deposit
     * @param sender The address of the user withdrawing their deposit
     */
    event Withdrawn(address indexed sender);

    /**
     * @dev Emitted when the claim receiver contract address is set
     * @param receiverAddress The address of the claim receiver contract
     */
    event ClaimReceiverContractSet(address indexed receiverAddress);

    /**
     * @dev Emitted when claiming is opened
     * @param deadline The epoch time until which claiming is open
     */
    event ClaimingOpened(uint256 deadline);

    /**
     * @dev Emitted when a user claims their funds
     * @param user The address of the user claiming their funds
     * @param pointsAccumulated The number of points accumulated by the user
     */
    event Fundsclaimed(address indexed user, uint256 indexed pointsAccumulated);

    /**
     * @dev Allows ether to be sent to this contract
     */
    receive() external payable {}

    /**
     * @dev Sets state variables needed for future functions
     * @param __rETH Address of the rEth contract
     * @param __wstETH Address of the wstEth contract
     * @param __sfrxETH Address of the sfrxEth contract
     * @param __cbETH Address of the cbEth contract
     */
    constructor(
        IERC20 __rETH,
        IERC20 __wstETH,
        IERC20 __sfrxETH,
        IERC20 __cbETH
    ) {
        _rETH = __rETH;
        _wstETH = __wstETH;
        _sfrxETH = __sfrxETH;
        _cbETH = __cbETH;

        isSupportedToken[__rETH] = true;
        isSupportedToken[__wstETH] = true;
        isSupportedToken[__sfrxETH] = true;
        isSupportedToken[__cbETH] = true;
    }

    /**
     * @dev Deposits ERC20 tokens into contract
     * @param _erc20Contract ERC20 token contract being deposited
     * @param _amount Amount of the ERC20 token being deposited
     */
    function deposit(
        IERC20 _erc20Contract,
        uint256 _amount
    ) external onlyCorrectAmount(_amount) depositingOpen whenNotPaused {
        require(isSupportedToken[_erc20Contract], "Unsupported token");

        UserDepositInfo storage userInfo = depositInfo[msg.sender];

        userInfo.depositTime = block.timestamp;
        userInfo.totalERC20Balance += _amount;
        userToErc20Balance[msg.sender][_erc20Contract] += _amount;

        if (!_erc20Contract.transferFrom(msg.sender, address(this), _amount))
            revert TokenTransferFailed();

        emit DepositERC20(msg.sender, _amount);
    }

    /**
     * @dev Deposits Ether into the contract
     * @dev Emits a `DepositEth` event when the deposit is successful
     * The amount of Ether being deposited, must be between 0.1 ether and 100 ether
     */
    function depositEther()
        external
        payable
        onlyCorrectAmount(msg.value)
        depositingOpen
        whenNotPaused
    {
        UserDepositInfo storage userInfo = depositInfo[msg.sender];

        userInfo.depositTime = block.timestamp;
        userInfo.etherBalance += msg.value;

        emit DepositEth(msg.sender, msg.value);
    }

    /**
     * @dev Withdraws all funds from the pool for the user calling
     * @dev Emits a `Withdrawn` event when the withdrawal is successful
     */
    function withdraw() public nonReentrant {
        require(depositInfo[msg.sender].depositTime != 0, "No deposit stored");
        _transferFunds(0);
        emit Withdrawn(msg.sender);
    }

    /**
     * @dev Transfers users funds to a new contract such as LP
     * @dev Can only be called once the receiver contract is ready and claiming is open
     * @dev Emits a `Fundsclaimed` event when the transfer is successful
     */
    function claim() public nonReentrant {
        require(claimingOpen == 1, "Claiming not open");
        require(
            claimReceiverContract != address(0),
            "Claiming address not set"
        );
        require(block.timestamp <= claimDeadline, "Claiming is complete");
        require(depositInfo[msg.sender].depositTime != 0, "No deposit stored");

        uint256 pointsRewarded = calculateUserPoints(msg.sender);
        _transferFunds(1);

        emit Fundsclaimed(msg.sender, pointsRewarded);
    }

    /**
     * @dev Sets claiming to be open, to allow users to claim their points
     * @dev Emits a `ClaimingOpened` event when claiming is opened
     * @param _claimDeadline The amount of time in days until claiming will close
     */
    function setClaimingOpen(uint256 _claimDeadline) public onlyOwner {
        claimDeadline = block.timestamp + (_claimDeadline * 86400);
        claimingOpen = 1;
        endTime = block.timestamp;

        emit ClaimingOpened(claimDeadline);
    }

    /**
     * @dev Sets the contract which will receive claimed funds
     * @dev Emitsa `ClaimReceiverContractSet` event when the receiver contract is set
     * @param _receiverContract The contract address for where claimed funds will be sent
     */
    function setClaimReceiverContract(
        address _receiverContract
    ) public onlyOwner {
        require(_receiverContract != address(0), "Cannot set as address zero");
        claimReceiverContract = _receiverContract;

        emit ClaimReceiverContractSet(_receiverContract);
    }

    /**
     * @notice Calculates how many points a user currently has owed to them
     * @param _user The address of the user to calculate the points for
     * @return The amount of points a user currently has accumulated
     */
    function calculateUserPoints(address _user) public view returns (uint256) {
        uint256 lengthOfDeposit;

        UserDepositInfo storage userInfo = depositInfo[_user];

        if (claimingOpen == 0) {
            lengthOfDeposit = block.timestamp - userInfo.depositTime;
        } else {
            lengthOfDeposit = endTime - userInfo.depositTime;
        }

        //Scaled by 1000, therefore, 1005 would be 1.005
        uint256 userMultiplier = Math.min(
            2000,
            1000 + ((lengthOfDeposit * 10) / 2592) / 10
        );
        uint256 totalUserBalance = userInfo.etherBalance +
            userInfo.totalERC20Balance;

        //Formula for calculating points total
        return
            ((Math.sqrt(totalUserBalance) * lengthOfDeposit) * userMultiplier) /
            1e14;
    }

    /**
     * @notice Pauses the contract
     */
    function pauseContract() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract
     */
    function unPauseContract() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Transfers funds to relevant parties and updates data structures
     * @param _identifier Identifies which contract function called the function
     */
    function _transferFunds(uint256 _identifier) internal {
        UserDepositInfo storage userInfo = depositInfo[msg.sender];

        uint256 ethBalance = userInfo.etherBalance;

        userInfo.depositTime = 0;
        userInfo.totalERC20Balance = 0;
        userInfo.etherBalance = 0;

        address receiver = (_identifier == 0)
            ? msg.sender
            : claimReceiverContract;

        IERC20[4] memory validTokens = [_rETH, _wstETH, _sfrxETH, _cbETH];

        for (uint256 i = 0; i < 4; i++) {
            IERC20 token = validTokens[i];
            uint256 tokenBalance = userToErc20Balance[msg.sender][token];
            if (tokenBalance > 0) {
                userToErc20Balance[msg.sender][token] = 0;
                if (!token.transfer(receiver, tokenBalance))
                    revert TokenTransferFailed();
            }
        }

        payable(receiver).transfer(ethBalance);
    }

    /**
     * @dev Returns the balance for each currency, ether, and total value locked (TVL) of contract
     * @return rETHBal The balance of rETH held by the contract
     * @return wstETHBal The balance of wstETH held by the contract
     * @return sfrxETHBal The balance of sfrxETH held by the contract
     * @return cbETHBal The balance of cbETH held by the contract
     * @return ethBal The balance of ether held by the contract
     * @return tvl The total value locked in the contract
     */
    function getContractTVL()
        public
        view
        returns (
            uint256 rETHBal,
            uint256 wstETHBal,
            uint256 sfrxETHBal,
            uint256 cbETHBal,
            uint256 ethBal,
            uint256 tvl
        )
    {
        rETHBal = _rETH.balanceOf(address(this));
        wstETHBal = _wstETH.balanceOf(address(this));
        sfrxETHBal = _sfrxETH.balanceOf(address(this));
        cbETHBal = _cbETH.balanceOf(address(this));
        ethBal = address(this).balance;
        tvl = rETHBal + wstETHBal + sfrxETHBal + cbETHBal + ethBal;
    }

    /**
     * @dev Returns the balance for each currency, ether, and total value locked (TVL) of a specific user
     * @param _user The address of the user to get the TVL for
     * @return rETHBal The balance of rETH held by the user
     * @return wstETHBal The balance of wstETH held by the user
     * @return sfrxETHBal The balance of sfrxETH held by the user
     * @return cbETHBal The balance of cbETH held by the user
     * @return ethBal The balance of ether held by the user
     * @return totalBal The total value locked by the user
     */
    function getUserTVL(
        address _user
    )
        public
        view
        returns (
            uint256 rETHBal,
            uint256 wstETHBal,
            uint256 sfrxETHBal,
            uint256 cbETHBal,
            uint256 ethBal,
            uint256 totalBal
        )
    {
        rETHBal = userToErc20Balance[_user][_rETH];
        wstETHBal = userToErc20Balance[_user][_wstETH];
        sfrxETHBal = userToErc20Balance[_user][_sfrxETH];
        cbETHBal = userToErc20Balance[_user][_cbETH];
        ethBal = depositInfo[_user].etherBalance;
        totalBal = (rETHBal + wstETHBal + sfrxETHBal + cbETHBal + ethBal);
    }
}
