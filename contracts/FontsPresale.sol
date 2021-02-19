/**
 *Submitted for verification at Etherscan.io on 2021-01-08
*/

pragma solidity ^0.7.3;
//SPDX-License-Identifier: UNLICENSED

interface IERC20 {
    function totalSupply() external view returns (uint);
    function balanceOf(address who) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);
    function transfer(address to, uint value) external returns (bool);
    function approve(address spender, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
    
    function unPauseTransferForever() external;
    function uniswapV2Pair() external returns(address);
}
interface IUNIv2 {
    function addLiquidityETH(address token, uint amountTokenDesired, uint amountTokenMin, uint amountETHMin, address to, uint deadline) 
    external 
    payable 
    returns (uint amountToken, uint amountETH, uint liquidity);
    
    function WETH() external pure returns (address);

}

interface IUnicrypt {
    event onDeposit(address, uint256, uint256);
    event onWithdraw(address, uint256);
    function depositToken(address token, uint256 amount, uint256 unlock_date) external payable; 
    function withdrawToken(address token, uint256 amount) external;

}

interface IUniswapV2Factory {
  event PairCreated(address indexed token0, address indexed token1, address pair, uint);

  function createPair(address tokenA, address tokenB) external returns (address pair);
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor () {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}


contract Fonts_Presale is Context, ReentrancyGuard {
    using SafeMath for uint;

    //===============================================//
    //          Contract Variables                   //
    //===============================================//

    uint256 public constant MIN_CONTRIBUTION = 0.1 ether;
    uint256 public constant MAX_CONTRIBUTION = 6 ether;

    uint256 public constant HARD_CAP = 180 ether; //@change for testing 

    uint256 constant tokensPerETH = 1111;

    uint256 constant public UNI_LP_ETH = 86 ether;
    uint256 constant public UNI_LP_FONT = 60000 * 10**18;

    uint256 public constant UNLOCK_PERCENT_PRESALE_INITIAL = 50; //For presale buyers instant
    uint256 public constant UNLOCK_PERCENT_PRESALE_SECOND = 30; //For presale buyers after 30 days
    uint256 public constant UNLOCK_PERCENT_PRESALE_FINAL = 20; //For presale buyers after 60 days

    uint256 public constant DURATION_REFUND = 7 days;
    uint256 public constant DURATION_LIQUIDITY_LOCK = 365 days;

    uint256 public constant DURATION_TOKEN_DISTRIBUTION_ROUND_2 = 30 days;
    uint256 public constant DURATION_TOKEN_DISTRIBUTION_ROUND_3 = 60 days;    

    address public ERC20_uniswapV2Pair;


    IERC20 public FONT_ERC20;
    IERC20 public UNI_V2_ERC20;

    

    IUNIv2 constant UNISWAP_V2_ADDRESS =  IUNIv2(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    IUniswapV2Factory constant uniswapFactory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    IUnicrypt constant unicrypt = IUnicrypt(0x17e00383A843A9922bCA3B280C0ADE9f8BA48449);


    


    
    uint256 public tokensBought; //Total tokens bought

    bool public isStopped = false;
    bool public moonMissionStarted = false;
    bool public isRefundEnabled = false;
    bool public presaleStarted = false;
    bool public liquidityLocked = false;

    bool public isFontDistributedR1 = false;
    bool public isFontDistributedR2 = false;
    bool public isFontDistributedR3 = false;

    uint256 public roundTwoUnlockTime; 
    uint256 public roundThreeUnlockTime; 
    
    bool liquidityAdded = false;

    address payable owner;
    
    address public pool;
    
    uint256 public liquidityUnlock;
    
    uint256 public ethSent; //ETH Received
    
    uint256 public lockedLiquidityAmount;
    uint256 public refundTime; 

    mapping(address => uint) ethSpent;
    mapping(address => uint) fontBought;
    address[] public contributors;

    
    modifier onlyOwner() {
        require(msg.sender == owner, "You are not the owner");
        _;
    }
    
    constructor() {
        owner = _msgSender(); 
        liquidityUnlock = block.timestamp.add(DURATION_LIQUIDITY_LOCK);
        refundTime = block.timestamp.add(DURATION_REFUND);
    }
    
    //@done
    receive() external payable {   
        buyTokens();
    }
    



    function lockWithUnicrypt() external onlyOwner  {
        pool = RWD.uniswapV2Pair();
        IERC20 liquidityTokens = IERC20(pool);
        // Lock the whole contract LP balance
        uint256 liquidityBalance = liquidityTokens.balanceOf(address(this));
        uint256 timeToLock = liquidityUnlock;
        liquidityTokens.approve(address(unicrypt), liquidityBalance);

        unicrypt.depositToken{value: 0} (pool, liquidityBalance, timeToLock);
        lockedLiquidityAmount = lockedLiquidityAmount.add(liquidityBalance);
        liquidityLocked = true;
    }
    
    function withdrawFromUnicrypt(uint256 amount) external onlyOwner {
        unicrypt.withdrawToken(pool, amount);
    }
    
    //@todoAdd in variable to save gas
    function setRWD(IERC20 addr) external onlyOwner nonReentrant {
        require(FONT_ERC20 == IERC20(address(0)), "You can set the address only once");
        FONT_ERC20 = addr;
    }
    


    function unlockTokensAfterOneYear(address tokenAddress, uint256 tokenAmount) external onlyOwner  {
        require(block.timestamp >= liquidityUnlock, "You cannot withdraw yet");
        IERC20(tokenAddress).transfer(owner, tokenAmount);
    }

    //@done
    function allowRefunds() external onlyOwner nonReentrant {
        isRefundEnabled = true;
        isStopped = true;
    }

    //@done
    function buyTokens() public payable nonReentrant {
        require(_msgSender() == tx.origin);
        require(presaleStarted == true, "Presale is paused, do not send ETH");
        require(msg.value >= MIN_CONTRIBUTION, "You sent less than 0.1 ETH");
        require(msg.value <= MAX_CONTRIBUTION, "You sent more than 6 ETH");
        require(ethSent < HARD_CAP, "Hard cap reached");        
        require(msg.value.add(ethSent) <= HARD_CAP, "Hardcap will be reached");
        require(ethSpent[_msgSender()].add(msg.value) <= MAX_CONTRIBUTION, "You cannot buy more");

        require(FONT_ERC20 != IERC20(address(0)), "Main contract address not set"); //@todo
        require(!isStopped, "Presale stopped by contract, do not send ETH"); //@todo

        
        uint256 tokens = msg.value.mul(tokensPerETH);
        require(FONT_ERC20.balanceOf(address(this)) >= tokens, "Not enough tokens in the contract"); //@tod


        ethSpent[_msgSender()] = ethSpent[_msgSender()].add(msg.value);


        tokensBought = tokensBought.add(tokens);
        ethSent = ethSent.add(msg.value);

        contributors.push(_msgSender()); //Create list of contributors
        
        fontBought[_msgSender()] = fontBought[_msgSender()].add(tokens); //Add fonts bought by contributor

    }
   
    //@done
    function addLiquidity() external onlyOwner {
        require(!liquidityAdded, "liquidity Already added");
        require(ethSent >= HARD_CAP, "Hard cap not reached");        

        ERC20_uniswapV2Pair = uniswapFactory.createPair(address(FONT_ERC20), UNISWAP_V2_ADDRESS.WETH());


        FONT_ERC20.approve(address(UNISWAP_V2_ADDRESS), UNI_LP_FONT);
        
        UNISWAP_V2_ADDRESS.addLiquidityETH{ value: UNI_LP_ETH } (
            address(FONT_ERC20),
            UNI_LP_FONT,
            UNI_LP_FONT,
            UNI_LP_ETH,
            address(this),
            block.timestamp
        );
       
        liquidityAdded = true;
       
        if(!isStopped)
            isStopped = true;

        //

        IERC20 liquidityTokens = IERC20(ERC20_uniswapV2Pair); //Get the Uni LP token
        
        uint256 liquidityBalance = liquidityTokens.balanceOf(address(this));
        
        uint256 timeToLockTill = liquidityUnlock;

        //Approve the LP token to unicrypt
        liquidityTokens.approve(address(unicrypt), liquidityBalance);

        //Lock it in Unicrypto
        unicrypt.depositToken{value: 0}(uniswapV2Pair, liquidityBalance, timeToLockTill);


        lockedLiquidityAmount = lockedLiquidityAmount.add(liquidityBalance);



        //Set duration for FONT distribution 
        roundTwoUnlockTime = block.timestamp.add(DURATION_TOKEN_DISTRIBUTION_ROUND_2); 
        roundThreeUnlockTime = block.timestamp.add(DURATION_TOKEN_DISTRIBUTION_ROUND_3); 
    }
    

    //FONT can be claim by investors after sale success, It is optional 
    //@done
    function claimFontRoundOne() external nonReentrant {
        require(liquidityAdded,"FontsCrowdsale: can only claim after listing in UNI");  
        require(font_buyers[_msgSender()] > 0, "FontsCrowdsale: No FONT token available for this address to claim");       
        uint256 tokenAmount_ = font_buyers[_msgSender()];

        tokenAmount_ = tokenAmount_.mul(UNLOCK_PERCENT_PRESALE_INITIAL).div(100);
        fontBought[_msgSender()] = fontBought[_msgSender()].sub(tokenAmount_);

        // Transfer the $FONTs to the beneficiary
        FONT_ERC20.safeTransfer(_msgSender(), tokenAmount_);
        tokensWithdrawn = tokensWithdrawn.add(tokenAmount_);
    }

    //30% of FONT can be claim by investors after 30 days from unilisting
    //@done
    function claimFontRoundTwo() external nonReentrant {
        require(liquidityAdded,"FontsCrowdsale: can only claim after listing in UNI");  
        require(font_buyers[_msgSender()] > 0, "FontsCrowdsale: No FONT token available for this address to claim");
        require(block.timestamp >= roundTwoUnlockTime, "You cannot withdraw yet");

        uint256 tokenAmount_ = font_buyers[_msgSender()];

        tokenAmount_ = tokenAmount_.mul(UNLOCK_PERCENT_PRESALE_SECOND).div(100);
        fontBought[_msgSender()] = fontBought[_msgSender()].sub(tokenAmount_);

        // Transfer the $FONTs to the beneficiary
        FONT_ERC20.safeTransfer(_msgSender(), tokenAmount_);
        tokensWithdrawn = tokensWithdrawn.add(tokenAmount_);
    }

    //20% of FONT can be claim by investors after 20 days from unilisting
    //@done
    function claimFontRoundThree() external nonReentrant {
        require(liquidityAdded,"FontsCrowdsale: can only claim after listing in UNI");  
        require(font_buyers[_msgSender()] > 0, "FontsCrowdsale: No FONT token available for this address to claim");
        require(block.timestamp >= roundThreeUnlockTime, "You cannot withdraw yet");

        uint256 tokenAmount_ = font_buyers[_msgSender()];

        tokenAmount_ = tokenAmount_.mul(UNLOCK_PERCENT_PRESALE_FINAL).div(100);
        fontBought[_msgSender()] = 0;//fontBought[_msgSender()].sub(tokenAmount_);

        // Transfer the $FONTs to the beneficiary
        FONT_ERC20.safeTransfer(_msgSender(), tokenAmount_);
        tokensWithdrawn = tokensWithdrawn.add(tokenAmount_);
    }

    //@todo
    function distributeTokensRoundOne() external onlyOwner {
        require(liquidityAdded, "FontCrowdsale: can only distribute tokens after crowdsale success");        
        require(!isFontDistributedR1, "Already FONT Round 1 Distributed");
        for (uint i=0; i<contributors.length; i++) {
            uint256 tokenAmount_ = fontBought[contributors[i]];
            if(tokenAmount_ > 0) {
                tokenAmount_ = tokenAmount_.mul(UNLOCK_PERCENT_PRESALE_INITIAL).div(100);
                fontBought[contributors[i]] = fontBought[contributors[i]].sub(tokenAmount_);
                // Transfer the $FONTs to the beneficiary
                FONT_ERC20.safeTransfer(contributors[i], tokenAmount_);
                tokensWithdrawn = tokensWithdrawn.add(tokenAmount_);
            }
        }
        isFontDistributedR1 = true;
    }

    //Let any one call next 30% of distribution
    //@done
    function distributeTokensRoundTwo() external nonReentrant{
        require(block.timestamp >= roundTwoUnlockTime, "You cannot withdraw yet");
        require(!isFontDistributedR2, "Already FONT Round 2 Distributed");
        for (uint i=0; i<contributors.length; i++) {
            uint256 tokenAmount_ = fontBought[contributors[i]];
            if(tokenAmount_ > 0) {
                tokenAmount_ = tokenAmount_.mul(UNLOCK_PERCENT_PRESALE_SECOND).div(100);
                fontBought[contributors[i]] = fontBought[contributors[i]].sub(tokenAmount_);
                // Transfer the $FONTs to the beneficiary
                FONT_ERC20.safeTransfer(contributors[i], tokenAmount_);
                tokensWithdrawn = tokensWithdrawn.add(tokenAmount_);
            }
        }
        isFontDistributedR2 = true;
    }

    //Let any one call final 20% of distribution
    //@done
    function distributeTokensRoundThree() external nonReentrant{
        require(block.timestamp >= roundThreeUnlockTime, "You cannot withdraw yet");
        require(!isFontDistributedR3, "Already FONT Round 3 Distributed");
        for (uint i=0; i<contributors.length; i++) {
            uint256 tokenAmount_ = fontBought[contributors[i]];
            if(tokenAmount_ > 0) {
                tokenAmount_ = tokenAmount_.mul(UNLOCK_PERCENT_PRESALE_FINAL).div(100);
                fontBought[contributors[i]] = 0;//fontBought[contributors[i]].sub(tokenAmount_);
                // Transfer the $FONTs to the beneficiary
                FONT_ERC20.safeTransfer(contributors[i], tokenAmount_);
                tokensWithdrawn = tokensWithdrawn.add(tokenAmount_);
            }
        }
        isFontDistributedR3 = true;
    }



    //@done
    function withdrawEth(uint amount) external onlyOwner returns(bool){
        require(liquidityAdded,"FontsPresale: withdraw only after liquidity added to uniswap");        
        require(amount <= address(this).balance);
        owner.transfer(amount);
        return true;
    }    


    //@done
    function userFontBalance(address user) external view returns (uint256) {
        return fontBought[user];
    }

    //@done
    function userEthContribution(address user) external view returns (uint256) {
        return ethSpent[user];
    }    

    //@done
    function getRefund() external nonReentrant {
        require(_msgSender() == tx.origin);
        require(!liquidityAdded);
        // To get refund it should be enabled by the owner OR 7 days had passed 
        require(ethSent < HARD_CAP && block.timestamp >= refundTime, "Cannot refund");
        address payable user = _msgSender();
        uint256 amount = ethSpent[user];
        ethSpent[user] = 0;
        fontBought[user] = 0;
        user.transfer(amount);
    }
    
    //@done
    function userEthSpenttInPresale(address user) external view returns(uint){
        return ethSpent[user];
    }


    //@done
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    //@done
    function _msgData() internal view virtual returns (bytes calldata) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }

    //@done
    function startPresale() external onlyOwner { 
        presaleStarted = true;
    }
    
    //@done
    function pausePresale() external onlyOwner { 
        presaleStarted = false;
    }


}


library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}