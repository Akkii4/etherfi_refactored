// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract RefactoredEarlyAdopterPool is Ownable, ReentrancyGuard, Pausable {
    using Math for uint256;

    struct UserDepositInfo {
        uint256 depositTime;
        uint256 etherBalance;
        uint256 totalERC20Balance;
    }

    //--------------------------------------------------------------------------------------
    //---------------------------------  STATE-VARIABLES  ----------------------------------
    //--------------------------------------------------------------------------------------

    //After a certain time, claiming funds is not allowed and users will need to simply withdraw
    uint256 public claimDeadline;

    //Time when depositing closed and will be used for calculating reards
    uint256 public endTime;

    address private immutable _rETH; // 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address private immutable _wstETH; // 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address private immutable _sfrxETH; // 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address private immutable _cbETH; // 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;

    address[4] private _supportedTokens;

    //Future contract which funds will be sent to on claim (Most likely LP)
    address public claimReceiverContract;

    //Status of claims, 1 means claiming is open
    uint8 public claimingOpen;

    //user address => token address = balance
    mapping(address => mapping(address => uint256)) public userToErc20Balance;
    mapping(address => UserDepositInfo) public depositInfo;

    IERC20 private _rETHInstance;
    IERC20 private _wstETHInstance;
    IERC20 private _sfrxETHInstance;
    IERC20 private _cbETHInstance;

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
    /// @param rETH address of the rEth contract to receive
    /// @param wstETH address of the wstEth contract to receive
    /// @param sfrxETH address of the sfrxEth contract to receive
    /// @param cbETH address of the _cbEth contract to receive
    constructor(address rETH, address wstETH, address sfrxETH, address cbETH) {
        _rETH = rETH;
        _wstETH = wstETH;
        _sfrxETH = sfrxETH;
        _cbETH = cbETH;

        _supportedTokens[0] = rETH;
        _supportedTokens[1] = wstETH;
        _supportedTokens[2] = sfrxETH;
        _supportedTokens[3] = cbETH;

        _rETHInstance = IERC20(_rETH);
        _wstETHInstance = IERC20(_wstETH);
        _sfrxETHInstance = IERC20(_sfrxETH);
        _cbETHInstance = IERC20(_cbETH);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------  STATE-CHANGING FUNCTIONS  ------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice deposits ERC20 tokens into contract
    /// @dev User must have approved contract before
    /// @param _erc20Contract erc20 token contract being deposited
    /// @param _amount amount of the erc20 token being deposited
    function deposit(
        address _erc20Contract,
        uint256 _amount
    ) external onlyCorrectAmount(_amount) depositingOpen whenNotPaused {
        uint256 isTokenSupported = 0;
        for (uint256 i = 0; i < 4; i++) {
            if (_erc20Contract == _supportedTokens[i]) {
                isTokenSupported = 1;
                break;
            }
        }
        require(isTokenSupported == 1, "Unsupported token");

        UserDepositInfo storage userInfo = depositInfo[msg.sender];

        userInfo.depositTime = block.timestamp;
        userInfo.totalERC20Balance += _amount;
        userToErc20Balance[msg.sender][_erc20Contract] += _amount;
        require(
            IERC20(_erc20Contract).transferFrom(
                msg.sender,
                address(this),
                _amount
            ),
            "Transfer failed"
        );

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
        uint256 rETHbal = userToErc20Balance[msg.sender][_rETH];
        uint256 wstETHbal = userToErc20Balance[msg.sender][_wstETH];
        uint256 sfrxEthbal = userToErc20Balance[msg.sender][_sfrxETH];
        uint256 cbEthBal = userToErc20Balance[msg.sender][_cbETH];

        UserDepositInfo storage userInfo = depositInfo[msg.sender];

        uint256 ethBalance = userInfo.etherBalance;

        userInfo.depositTime = 0;
        userInfo.totalERC20Balance = 0;
        userInfo.etherBalance = 0;

        userToErc20Balance[msg.sender][_rETH] = 0;
        userToErc20Balance[msg.sender][_wstETH] = 0;
        userToErc20Balance[msg.sender][_sfrxETH] = 0;
        userToErc20Balance[msg.sender][_cbETH] = 0;

        address receiver;

        if (_identifier == 0) {
            receiver = msg.sender;
        } else {
            receiver = claimReceiverContract;
        }

        require(_rETHInstance.transfer(receiver, rETHbal), "Transfer failed");
        require(
            _wstETHInstance.transfer(receiver, wstETHbal),
            "Transfer failed"
        );
        require(
            _sfrxETHInstance.transfer(receiver, sfrxEthbal),
            "Transfer failed"
        );
        require(_cbETHInstance.transfer(receiver, cbEthBal), "Transfer failed");

        payable(receiver).transfer(ethBalance);
    }

    //--------------------------------------------------------------------------------------
    //-------------------------------------     GETTERS  ------------------------------------
    //--------------------------------------------------------------------------------------

    /// @dev Returns the total value locked of all currencies in contract
    function getContractTVL() public view returns (uint256 tvl) {
        tvl = (_rETHInstance.balanceOf(address(this)) +
            _wstETHInstance.balanceOf(address(this)) +
            _sfrxETHInstance.balanceOf(address(this)) +
            _cbETHInstance.balanceOf(address(this)) +
            address(this).balance);
    }

    /// @dev Returns the balance for each currencies and eth locked in contract
    function getContractTokensBalance()
        public
        view
        returns (
            uint256 rETHBal,
            uint256 wstETHBal,
            uint256 sfrxETHBal,
            uint256 cbETHBal,
            uint256 ethBal
        )
    {
        rETHBal = _rETHInstance.balanceOf(address(this));
        wstETHBal = _wstETHInstance.balanceOf(address(this));
        sfrxETHBal = _wstETHInstance.balanceOf(address(this));
        cbETHBal = _wstETHInstance.balanceOf(address(this));
        ethBal = address(this).balance;
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
