// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract RefactoredEarlyAdopterPool is Ownable, ReentrancyGuard, Pausable {
    using Math for uint256;

    error TokenTransferFailed();

    //--------------------------------------------------------------------------------------
    //---------------------------------  STATE-VARIABLES  ----------------------------------
    //--------------------------------------------------------------------------------------

    //After a certain time, claiming funds is not allowed and users will need to simply withdraw
    uint256 public claimDeadline;

    //Time when depositing closed and will be used for calculating reards
    uint256 public endTime;

    IERC20 private immutable _rETH; // 0xae78736Cd615f374D3085123A210448E74Fc6393;
    IERC20 private immutable _wstETH; // 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    IERC20 private immutable _sfrxETH; // 0xac3E018457B222d93114458476f3E3416Abbe38F;
    IERC20 private immutable _cbETH; // 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;

    //Future contract which funds will be sent to on claim (Most likely LP)
    address public claimReceiverContract;

    //Status of claims, 1 means claiming is open
    uint8 public claimingOpen;

    mapping(address => UserDepositInfo) public depositInfo;

    //user address => token address = balance
    mapping(address => mapping(IERC20 => uint256)) public userToErc20Balance;

    mapping(IERC20 => bool) public isSupportedToken;

    struct UserDepositInfo {
        uint256 depositTime;
        uint256 etherBalance;
        uint256 totalERC20Balance;
    }

    //--------------------------------------------------------------------------------------
    //-------------------------------------  EVENTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    event DepositERC20(address indexed sender, uint256 amount);
    event DepositEth(address indexed sender, uint256 amount);
    event Withdrawn(address indexed sender);
    event ClaimReceiverContractSet(address indexed receiverAddress);
    event ClaimingOpened(uint256 deadline);
    event Fundsclaimed(address indexed user, uint256 indexed pointsAccumulated);

    /// @notice Allows ether to be sent to this contract
    receive() external payable {}

    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTRUCTOR   ------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Sets state variables needed for future functions
    /// @param __rETH address of the rEth contract to receive
    /// @param __wstETH address of the wstEth contract to receive
    /// @param __sfrxETH address of the sfrxEth contract to receive
    /// @param __cbETH address of the cbEth contract to receive
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

    //--------------------------------------------------------------------------------------
    //----------------------------  STATE-CHANGING FUNCTIONS  ------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice deposits ERC20 tokens into contract
    /// @dev User must have approved contract before
    /// @param _erc20Contract erc20 token contract being deposited
    /// @param _amount amount of the erc20 token being deposited
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

    /// @notice deposits Ether into contract
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

    /// @notice withdraws all funds from pool for the user calling
    /// @dev no points allocated to users who withdraw
    function withdraw() public nonReentrant {
        require(depositInfo[msg.sender].depositTime != 0, "No deposit stored");
        _transferFunds(0);
        emit Withdrawn(msg.sender);
    }

    /// @notice Transfers users funds to a new contract such as LP
    /// @dev can only call once receiver contract is ready and claiming is open
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

    /// @notice Sets claiming to be open, to allow users to claim their points
    /// @param _claimDeadline the amount of time in days until claiming will close
    function setClaimingOpen(uint256 _claimDeadline) public onlyOwner {
        claimDeadline = block.timestamp + (_claimDeadline * 86400);
        claimingOpen = 1;
        endTime = block.timestamp;

        emit ClaimingOpened(claimDeadline);
    }

    /// @notice Set the contract which will receive claimed funds
    /// @param _receiverContract contract address for where claiming will send the funds
    function setClaimReceiverContract(
        address _receiverContract
    ) public onlyOwner {
        require(_receiverContract != address(0), "Cannot set as address zero");
        claimReceiverContract = _receiverContract;

        emit ClaimReceiverContractSet(_receiverContract);
    }

    /// @notice Calculates how many points a user currently has owed to them
    /// @return the amount of points a user currently has accumulated
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

    //Pauses the contract
    function pauseContract() external onlyOwner {
        _pause();
    }

    //Unpauses the contract
    function unPauseContract() external onlyOwner {
        _unpause();
    }

    //--------------------------------------------------------------------------------------
    //--------------------------------  INTERNAL FUNCTIONS  --------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Transfers funds to relevant parties and updates data structures
    /// @param _identifier identifies which contract function called the function
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

    //--------------------------------------------------------------------------------------
    //-------------------------------------     GETTERS  ------------------------------------
    //--------------------------------------------------------------------------------------

    /// @dev Returns the balance for each currencies, eth & TVL of contract
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

    //--------------------------------------------------------------------------------------
    //-------------------------------------  MODIFIERS  ------------------------------------
    //--------------------------------------------------------------------------------------

    modifier onlyCorrectAmount(uint256 _amount) {
        require(
            _amount >= 0.1 ether && _amount <= 100 ether,
            "Incorrect Deposit Amount"
        );
        _;
    }

    modifier depositingOpen() {
        require(claimingOpen == 0, "Depositing closed");
        _;
    }
}
