// SPDX-License-Identifier: MIT
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./IFarm.sol";
import "./swap/interfaces/IUniswapV2Router02.sol";
pragma solidity 0.6.12;

contract Industrial is Ownable, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    struct UserInfo {
        uint256 shares; // number of shares for a user
        uint256 lastDepositedTime; // keeps track of deposited time for potential penalty
        uint256 rewardPaid; // keeps track of cake deposited at the last user action
        uint256 totalRewardPaid;
    }

    IERC20 public token; // Cake token
    IERC20 public lp; // Cake token

    address public masterchef;

    mapping(address => UserInfo) public userInfo;
    mapping(address => bool) public callers;

    uint256 public pid_lp;
    uint256 public totalShares;
    uint256 public lastHarvestedTime;
    address public admin;
    address public treasury;

    uint256 public constant MAX_PERFORMANCE_FEE = 500; // 5%
    uint256 public constant MAX_CALL_FEE = 500; // 1%
    uint256 public constant MAX_WITHDRAW_FEE = 500; // 5%
    uint256 public constant MAX_WITHDRAW_FEE_PERIOD = 30 days; // 30 days

    uint256 public performanceFee = 500; // 5%
    uint256 public callFee = 500; // 5%
    uint256 public withdrawFee = 10; // 0.1%
    uint256 public withdrawFeePeriod = 72 hours; // 3 days

    event Deposit(address indexed sender, uint256 amount, uint256 shares, uint256 lastDepositedTime);
    event Withdraw(address indexed sender, uint256 amount, uint256 shares);
    event WithdrawReward(address indexed sender, uint256 shares);
    event Harvest(address indexed sender, uint256 performanceFee, uint256 callFee);
    event Pause();
    event Unpause();

    constructor(address _token, address _lp, address _masterchef, uint256 _pid_lp)
    public {

        require(_token != address(0) && _lp != address(0) && _masterchef != address(0), "invalid config");

        pid_lp = _pid_lp;
        token = IERC20(_token);
        lp = IERC20(_lp);
        masterchef = _masterchef;

        admin = msg.sender;
        treasury = msg.sender;

        IERC20(_lp).safeApprove(address(masterchef), uint256(- 1));
        IERC20(_token).safeApprove(address(masterchef), uint256(- 1));

        callers[ msg.sender ] = true;
    }

    /**
     * @notice Checks if the msg.sender is the admin address
     */
    modifier onlyAdmin() {
        require(msg.sender == admin, "admin: wut?");
        _;
    }

    /**
     * @notice Checks if the msg.sender is a contract or a proxy
     */
    modifier notContract() {
        require(!_isContract(msg.sender), "contract not allowed");
        require(msg.sender == tx.origin, "proxy contract not allowed");
        _;
    }
    /**
         * @notice Checks if address is a contract
         * @dev It prevents contract from being targetted
         */
    function _isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
    /**
     * @notice Deposits funds into the Cake Vault
     * @dev Only possible when contract not paused.
     * @param _amount: number of tokens to deposit (in CAKE)
     */
    function deposit(uint256 _pid, uint256 _amount) external whenNotPaused notContract nonReentrant {
        require(_amount > 0, "Nothing to deposit");

        uint256 pool = balanceOf(_pid);
        // if there is a deposit fee, compute it here
        uint256 oldBalance = pool.lpToken.balanceOf(address(this));
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        uint256 newBalance = pool.lpToken.balanceOf(address(this));
        _amount = newBalance.sub(oldBalance);

        uint256 currentShares = 0;
        if (totalShares != 0) {
            currentShares = (_amount.mul(totalShares)).div(pool);
        } else {
            currentShares = _amount;
        }
        UserInfo storage user = userInfo[msg.sender];

        user.shares = user.shares.add(currentShares);
        user.lastDepositedTime = block.timestamp;

        totalShares = totalShares.add(currentShares);
        _earn();
        IFarm(masterchef).deposit(_pid, _amount);
        emit Deposit(msg.sender, _amount, currentShares, block.timestamp);
    }

    function balanceOfUser(uint pid, address user) public view returns (uint){
        return userInfo[msg.sender].shares;
    }

    /**
     * @notice Withdraws all funds for a user
     */
    function withdrawAll(uint256 _pid) external notContract {
        withdraw(_pid, userInfo[msg.sender].shares);
    }


    function changeLpId(uint256 _pid_lp) external onlyAdmin {
        uint256 bal = balanceOf(_pid_lp);
        IFarm(masterchef).withdraw(pid_lp, bal);
        pid_lp = _pid_lp;
    }

    function setCaller(bool status) external onlyAdmin {
        callers[ msg.sender ] = status;
    }

    /**
     * @notice Sets admin address
     * @dev Only callable by the contract owner.
     */
    function setAdmin(address _admin) external onlyOwner {
        require(_admin != address(0), "Cannot be zero address");
        admin = _admin;
    }

    /**
     * @notice Sets treasury address
     * @dev Only callable by the contract owner.
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Cannot be zero address");
        treasury = _treasury;
    }

    /**
     * @notice Sets performance fee
     * @dev Only callable by the contract admin.
     */
    function setPerformanceFee(uint256 _performanceFee) external onlyAdmin {
        require(_performanceFee <= MAX_PERFORMANCE_FEE, "performanceFee cannot be more than MAX_PERFORMANCE_FEE");
        performanceFee = _performanceFee;
    }

    /**
     * @notice Sets call fee
     * @dev Only callable by the contract admin.
     */
    function setCallFee(uint256 _callFee) external onlyAdmin {
        require(_callFee <= MAX_CALL_FEE, "callFee cannot be more than MAX_CALL_FEE");
        callFee = _callFee;
    }

    /**
     * @notice Sets withdraw fee
     * @dev Only callable by the contract admin.
     */
    function setWithdrawFee(uint256 _withdrawFee) external onlyAdmin {
        require(_withdrawFee <= MAX_WITHDRAW_FEE, "withdrawFee cannot be more than MAX_WITHDRAW_FEE");
        withdrawFee = _withdrawFee;
    }

    /**
     * @notice Sets withdraw fee period
     * @dev Only callable by the contract admin.
     */
    function setWithdrawFeePeriod(uint256 _withdrawFeePeriod) external onlyAdmin {
        require(
            _withdrawFeePeriod <= MAX_WITHDRAW_FEE_PERIOD,
            "withdrawFeePeriod cannot be more than MAX_WITHDRAW_FEE_PERIOD"
        );
        withdrawFeePeriod = _withdrawFeePeriod;
    }

    /**
     * @notice Withdraws from MasterChef to Vault without caring about rewards.
     * @dev EMERGENCY ONLY. Only callable by the contract admin.
     */
    function emergencyWithdraw(uint256 pid) external onlyAdmin nonReentrant {
        IFarm(masterchef).emergencyWithdraw(pid);
    }

    /**
     * @notice Withdraw unexpected tokens sent to the Cake Vault
     */
    function inCaseTokensGetStuck(address _token) external onlyAdmin {
        require(_token != address(token), "!token");
        require(_token != address(lp), "!lp");
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Triggers stopped state
     * @dev Only possible when contract not paused.
     */
    function pause() external onlyAdmin whenNotPaused {
        _pause();
        emit Pause();
    }

    /**
     * @notice Returns to normal state
     * @dev Only possible when contract is paused.
     */
    function unpause() external onlyAdmin whenPaused {
        _unpause();
        emit Unpause();
    }

    function setswapRewardToProfitStatus(bool status) external onlyAdmin {
        swapRewardToProfitStatus = status;
    }

    /**
     * @notice Calculates the expected harvest reward from third party
     * @return Expected reward to collect in CAKE
     */
    function calculateHarvestCakeRewards() external view returns (uint256) {
        uint256 amount = IFarm(masterchef).pendingEgg(0, address(this));
        amount = amount.add(available());
        uint256 currentCallFee = amount.mul(callFee).div(10000);

        return currentCallFee;
    }

    /**
     * @notice Calculates the total pending rewards that can be restaked
     * @return Returns total pending cake rewards
     */
    function calculateTotalPendingCakeRewards() external view returns (uint256) {
        uint256 amount = IFarm(masterchef).pendingEgg(0, address(this));
        amount = amount.add(available());

        return amount;
    }

    /**
     * @notice Calculates the price per share
     */
    function getPricePerFullShare(uint256 pid) external view returns (uint256) {
        return totalShares == 0 ? 1e18 : balanceOf(pid).mul(1e18).div(totalShares);
    }

    /**
     * @notice Withdraws from funds from the Cake Vault
     * @param _shares: Number of shares to withdraw
     */
    function withdraw(uint pid, uint256 _shares) public notContract nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require(_shares > 0, "Nothing to withdraw");
        require(_shares <= user.shares, "Withdraw amount exceeds balance");

        uint256 currentAmount = (balanceOf(pid).mul(_shares)).div(totalShares);
        user.shares = user.shares.sub(_shares);
        totalShares = totalShares.sub(_shares);
        IFarm(masterchef).withdraw(pid, currentAmount);

        if (block.timestamp < user.lastDepositedTime.add(withdrawFeePeriod)) {
            uint256 currentWithdrawFee = currentAmount.mul(withdrawFee).div(10000);
            lp.safeTransfer(treasury, currentWithdrawFee);
            currentAmount = currentAmount.sub(currentWithdrawFee);
        }
        _earn();
        lp.safeTransfer(msg.sender, currentAmount);
        emit Withdraw(msg.sender, currentAmount, _shares);
    }

    /**
     * @notice Custom logic for how much the vault allows to be borrowed
     * @dev The contract puts 100% of the tokens to work.
     */
    function available() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @notice Calculates the total underlying tokens
     * @dev It includes tokens held by the contract and held in MasterChef
     */
    function balanceOf(uint256 pid) public view returns (uint256) {
        (uint256 amount,) = IFarm(masterchef).userInfo(pid, address(this));
        return lp.balanceOf(address(this)).add(amount);
    }






    /**
     * @notice Reinvests CAKE tokens into MasterChef
     * @dev Only possible when contract not paused.
     */
    function harvest() external whenNotPaused nonReentrant {
        require( callers[msg.sender], "huh! want a slice of my cake?");
        _earn();
    }



    /**
     * @notice Deposits tokens into MasterChef to earn staking rewards
     */
    function _earn() internal {
        IFarm(masterchef).withdraw(pid_lp, 0);

        uint256 bal = available();
        if (bal > 0.00001 ether ) {
            swapTokensForEth(bal);
        }

        uint256 profitWETH = routerReward.WETH().balanceOf(address(this));
        if( profitWETH > 0.00001 ether ){
            getFee();
            swapProfitToNative(profitWETH);
        }

        lastHarvestedTime = block.timestamp;
        emit Harvest(msg.sender, currentPerformanceFee, currentCallFee);
    }

    function getFee(){
        uint256 bal = routerReward.WETH().balanceOf(address(this));
        uint256 currentPerformanceFee = bal.mul(performanceFee).div(10000);
        routerReward.WETH().safeTransfer(treasury, currentPerformanceFee);

        uint256 currentCallFee = bal.mul(callFee).div(10000);
        routerReward.WETH().safeTransfer(msg.sender, currentCallFee);
    }

    bool swapRewardToProfitStatus = true;

    IUniswapV2Router02 public routerReward;
    address public pairReward;

    IUniswapV2Router02 public routerNative;
    address public pairNative;

    function swapRewardToProfit(uint256 tokenAmount) private {
        if (pairReward == address(0)) {
            return;
        }
        if (swapRewardToProfitStatus == false) {
            return;
        }
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = routerReward.WETH();
        path[1] = address(token);
        _approve(address(this), address(routerReward), tokenAmount);
        // make the swap
        routerReward.swapExactETHForTokensSupportingFeeOnTransferTokens{value: tokenAmount}(
            0, path, treasury, block.timestamp
        );
    }

    function swapProfitToNative(uint256 tokenAmount) private {
        if (pairReward == address(0)) {
            return;
        }
        if (swapRewardToProfitStatus == false) {
            return;
        }
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = routerReward.WETH();
        _approve(address(this), address(routerReward), tokenAmount);
        // make the swap
        routerReward.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function router_init(
        address router_reward,
        address router_native,
        address _native) public onlyAdmin {

        require(router_reward != address(0) && router_native != address(0) &&
            _native != address(0), "invalid config");

        routerReward = IUniswapV2Router02(router);
        pairReward = IUniswapV2Factory(routerReward.factory())
        .getPair(_native, routerReward.WETH());
        require(pairReward != address(0), "invalid reward pair");

        routerNative = IUniswapV2Router02(router_native);
        pairNative = IUniswapV2Factory(routerNative.factory())
        .getPair(token, routerNative.WETH());
        require(pairNative != address(0), "invalid native pair");

        require( _routerReward.WETH() == _routerNative.WETH(), "incompatible WETH");

        IERC20( _routerReward.WETH() ).safeApprove( address(_routerReward) , 0);
        IERC20( _routerReward.WETH() ).safeApprove( address(_routerReward) , uint256(- 1) );
        IERC20( _routerNative.WETH() ).safeApprove( address(_routerNative) , 0);
        IERC20( _routerNative.WETH() ).safeApprove( address(_routerNative) , uint256(- 1) );

        IERC20( pairReward ).safeApprove( address(_routerReward) , 0);
        IERC20( pairReward ).safeApprove( address(_routerReward) , uint256(- 1) );

        IERC20( pairNative ).safeApprove( address(routerNative) , 0);
        IERC20( pairNative ).safeApprove( address(routerNative) , uint256(- 1) );

    }
}
