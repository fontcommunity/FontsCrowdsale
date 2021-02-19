// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Context.sol";

import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "./IUnicrypt.sol";

interface Pauseable {
    function unpause() external;
}

/**
 * @title FontsCrowdsale
 * @dev Crowdsale contract for $FONT. 
 *      Pre-Sale done in this manner:
 *        1st Round: 180ETH and 1111 $FONT per $ETH
 *        2nd Round: 220ETH and 909 $FONT per $ETH
 *      Softcap = 300 ETH
 *      Hardcap = 400 ETH
 *      Once hardcap is reached:
 *        Liquidity is added to Uniswap and locked, 0% risk of rug pull.
 *
 * @author soulbar@protonmail.com ($TEND)
 * @author @Onchained ($TACO)
 * @author @adalquardz ($FONT)
 */
contract FontsCrowdsale is Ownable, ReentrancyGuard  {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    address payable contract_owner;

    //===============================================//
    //          Contract Variables                   //
    //===============================================//


    // Caps
    uint256 public constant ROUND_1_CAP = 180 ether; //@change for testing
    uint256 public constant ROUND_2_CAP = 400 ether; //@change for testing

    uint256 public constant SOFT_CAP = 300 ether; // Softcap  = 300 //@change for testing 
    uint256 public constant HARD_CAP = 400 ether; // hardcap = +100 //@change for testing 

    uint256 public constant FONT_PER_ETH_ROUND_1 = 1111;
    uint256 public constant FONT_PER_ETH_ROUND_2 = 909;

    uint256 public constant INITIAL_UNLOCK_PERCENT = 60; //@change this
    
    
    // During tests, we should use 12 ether instead given that by default we only have 20 addresses.
    uint256 public constant CAP_PER_ADDRESS = 6 ether; //@change
    uint256 public constant MIN_CONTRIBUTION = 0.1 ether;


    //TIME
    // Start time 08/09/2020 @ 6:00am (UTC) 
    uint256 public constant CROWDSALE_START_TIME = 1613459928; //@change
    // Start time 08/11/2020 @ 4:00pm (UTC)

    // End time
    uint256 public constant CROWDSALE_END_TIME = CROWDSALE_START_TIME + 7 days; //@change


    // How many ETH need to lock in Uniswap LP 
    uint256 AMOUNT_ETH_FOR_UNISWAP_LP = 143 ether; //@change
  
    // How many $FONTs need to lock in Uniswap LP 
    uint256 AMOUNT_FONT_FOR_UNISWAP_LP = 1000000 * 10**18; //@change


    address public uniswapV2Pair;


    // Contributions state
    mapping(address => uint256) public contributions;
    mapping(address => uint256) public font_buyers;
    address[] public contributors;


    // Total wei raised (ETH)
    uint256 public weiRaised;
    uint256 public tokensBought = 0;
    uint256 public tokensWithdrawn = 0;


    // Flag to know if liquidity has been locked
    bool public liquidityLocked = false;
    uint256 public liquidityUnlockTime;
    uint256 public lockedLiquidityAmount;
    uint256 public liquidityUnlock;
    

    bool public isRefundEnabled = true;
    bool public isFontDistributed = false;

    // Pointer to the FONTToken
    IERC20 public fontToken;



    // Pointer to the UniswapRouter
    IUniswapV2Router02 public constant uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IUniswapV2Factory constant uniswapFactory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    IUnicrypt constant unicrypt = IUnicrypt(0x17e00383A843A9922bCA3B280C0ADE9f8BA48449);



    //===============================================//
    //                 Constructor                   //
    //===============================================//
    constructor(
        IERC20 _fontToken
    ) public Ownable() {
        contract_owner = _msgSender();        
        fontToken = _fontToken;
        liquidityUnlock = block.timestamp.add(372 days);

    }

    //===============================================//
    //                   Events                      //
    //===============================================//
    event TokenPurchase(
        address indexed beneficiary,
        uint256 weiAmount,
        uint256 tokenAmount
    );

    //===============================================//
    //                   Methods                     //
    //===============================================//

    // Main entry point for buying into the Pre-Sale. Contract Receives $ETH
    receive() external payable {
        // Prevent owner from buying tokens, but allow them to add pre-sale ETH to the contract for Uniswap liquidity
        if (owner() != _msgSender()) {
            // Validations.

            require(isOpen(), "FontsCrowdsale: sale did not start yet.");
            require(!hasEnded(), "FontsCrowdsale: sale is over.");
            require(
                weiRaised < _totalCapForCurrentRound(),
                "FontsCrowdsale: The cap for the current round has been filled."
            );
            require(
                contributions[_msgSender()] < CAP_PER_ADDRESS,
                "FontsCrowdsale: Individual cap has been filled."
            );

            // If we've passed most validations, let's get them $FONTs
            _buyTokens(_msgSender());
        }
    }

    /**
     * Function to calculate how many `weiAmount` can the sender purchase
     * based on total available cap for this round, and how many eth they've contributed.
     *
     * At the end of the function we refund the remaining ETH not used for purchase.
     */

    function _buyTokens(address beneficiary) internal {
        // How much ETH still available for the current Round CAP
        uint256 weiAllowanceForRound = _totalCapForCurrentRound().sub(weiRaised);

        // In case there is less allowance in this cap than what was sent, cap that.
        uint256 weiAmountForRound = weiAllowanceForRound < msg.value
            ? weiAllowanceForRound
            : msg.value;

        // How many wei is this sender still able to get per their address CAP.
        uint256 weiAllowanceForAddress = CAP_PER_ADDRESS.sub(
            contributions[beneficiary]
        );

        // In case the allowance of this address is less than what was sent, cap that.
        uint256 weiAmount = weiAllowanceForAddress < weiAmountForRound
            ? weiAllowanceForAddress
            : weiAmountForRound;


        // Internal call to run the final validations, and perform the purchase.
        _buyTokens(beneficiary, weiAmount, weiAllowanceForRound);

        // Refund all unused funds.
        uint256 refund = msg.value.sub(weiAmount);
        if (refund > 0) {
            payable(beneficiary).transfer(refund);
        }
    }

    /**
     * Function that validates the minimum wei amount, then perform the actual transfer of $FONTs
     */
    function _buyTokens(address beneficiary, uint256 weiAmount, uint256 weiAllowanceForRound) internal {
        require(
            weiAmount >= MIN_CONTRIBUTION || weiAllowanceForRound < MIN_CONTRIBUTION,
            "FontsCrowdsale: weiAmount is smaller than min contribution."
        );

        // Update how much wei we have raised
        weiRaised = weiRaised.add(weiAmount);
        // Update how much wei has this address contributed
        contributions[beneficiary] = contributions[beneficiary].add(weiAmount);

        // Calculate how many $FONTs can be bought with that wei amount
        
        uint256 tokenAmount = _getTokenAmount(weiAmount);

        tokenAmount = tokenAmount.mul(INITIAL_UNLOCK_PERCENT).div(100);

        require(
            fontToken.balanceOf(address(this)) >= tokenAmount,
            "Not enough tokens in the contract"
        );


        tokensBought.add(tokenAmount);
        contributions[beneficiary].add(weiAmount);

        font_buyers[beneficiary] = font_buyers[beneficiary].add(tokenAmount);
        contributors.push(beneficiary);

        // Transfer the $FONTs to the beneficiary
        //fontToken.safeTransfer(beneficiary, tokenAmount);

        // Create an event for this purchase
        //emit TokenPurchase(beneficiary, weiAmount, tokenAmount);        

    }

    // Calculate how many fonts do they get given the amount of wei
    //@done
    function _getTokenAmount(uint256 weiAmount) internal view returns (uint256){
        return weiAmount.mul(_getFontsPerETH());
    }

    // CONTROL FUNCTIONS

    // Is the sale open now?
    //@done
    function isOpen() public view returns (bool) {
        return block.timestamp >= CROWDSALE_START_TIME;
    }

    // Has the sale ended?
    //@done
    function hasEnded() public view returns (bool) {
        return block.timestamp >= CROWDSALE_END_TIME || weiRaised >= HARD_CAP;
    }

    // Has the Round 2 started
    //@done
    function roundTwoStarted() public view returns (bool) {
        return weiRaised >= ROUND_1_CAP;
    }

    //@done
    function _getFontsPerETH() internal view returns (uint256) {
        if (roundTwoStarted()) {
            return FONT_PER_ETH_ROUND_2;
        } else { // Cooks sale
            return FONT_PER_ETH_ROUND_1;
        }
    }

    // What's the total cap for the current round?
    //@done
    function _totalCapForCurrentRound() internal view returns (uint256) {
        if (roundTwoStarted()) {
            return ROUND_2_CAP;
        } else { // Cooks sale
            return ROUND_1_CAP;
        }
    }

    // Return human-readable currentRound
    //@done
    function getCurrentRound() public view returns (string memory) {
        if (roundTwoStarted()) return "Round 2";
        return "Round 1";
    }

    //Create Pair, but only after toke sale is success, called by owner in case 
    function createpair() external onlyOwner {
        require(isCrowdsaleSuccess(),"FontCrowdsale: can only create pair once softcap is reached");  
        //require(!uniswapV2Pair, "Pair exists already");
        uniswapV2Pair = uniswapFactory.createPair(address(fontToken), uniswapV2Router.WETH());
    }

    //after crowdsale success distribute the FONTs
    //@todo
    function distributeTokens() external onlyOwner{
        require(
            isCrowdsaleSuccess(),
            "FontCrowdsale: can only distribute tokens after crowdsale success"
        );        
        require(liquidityLocked, "Need to lock the liquidity");

        require(!isFontDistributed, "Already FONT Distributed");

        for (uint i=0; i<contributors.length; i++) {
            uint256 tokenAmount_ = font_buyers[contributors[i]];
            font_buyers[contributors[i]] = 0;

            // Transfer the $FONTs to the beneficiary
            fontToken.safeTransfer(contributors[i], tokenAmount_);

            tokensWithdrawn = tokensWithdrawn.add(tokenAmount_);

            // Create an event for this purchase
            emit TokenPurchase(contributors[i], contributions[contributors[i]], tokenAmount_);        
        }

        isFontDistributed = true;
    }

    //Claim token by users, with their own gas


    /**
     * Function that once sale is complete add the liquidity to Uniswap
     * then locks the liquidity by burning the UNI tokens.
     * 
     * Originally this function was public, however this was abused in $FONT.
     * Somebody made a contract that deployed the liquidity and bought 120ETH
     * worth of $FONT within the same transaction, essentially defeating the
     * purpose of trying to prevent whales from joining in.
     * https://etherscan.io/tx/0xeb84f538c0afeb0b542311236be10529925bd80e5fb34e4e24256b8b456234da/
     *
     * A few things to prevent that have been discussed.
     * 1. Make this function onlyOwner
     * 2. After liquidity is added, when FONTToken is unpaused and for 24 hours
     *      after that, no single transaction can be done for more than X amount.
     *      Forcing whales to execute more than a single transaction.
     * 3. A Bridge Tax or just a sale tax. Everytime a whale sells their tokens
     *      burn as many tokens as they are trying to sell. This would be a bit
     *      tricky to implement, as we need to define what qualifies as a whale.
     *
     * For now the only implementation for future usage is making this function onlyOwner.
     */
    /** 
     * Call this function once crowd sale is over. 
     * 1) Create Pair with WETH
     * 2) Approve the uni to spend FONT
     * 3) Add liquidity
     * 4) Lock the LP token to Unicrypt contract for 1 year + 7 days
     */
    function addAndLockLiquidity() external onlyOwner {
        require(
            isCrowdsaleSuccess(),
            "FontCrowdsale: can only send liquidity once softcap is reached"
        );
        require(!liquidityLocked, "FontCrowdsale: Liquidity already locked");

        //STEP 1: Create Pair
        uniswapV2Pair = uniswapFactory.createPair(address(fontToken), uniswapV2Router.WETH());

        //require(uniswapV2Pair, "Create Uniswap Pair first");


        // Unpause FONTToken forever. This will kick off the game.
        // Pauseable(address(fontToken)).unpause();

        // Send 100,000 FONTs to uniswap apprivl
        fontToken.approve(address(uniswapV2Router), AMOUNT_FONT_FOR_UNISWAP_LP);

        ////STEP 3: Add Liquidity 
        uniswapV2Router.addLiquidityETH{value: AMOUNT_ETH_FOR_UNISWAP_LP}(
            address(fontToken),
            AMOUNT_FONT_FOR_UNISWAP_LP,
            AMOUNT_FONT_FOR_UNISWAP_LP,
            AMOUNT_ETH_FOR_UNISWAP_LP,
            contract_owner, // burn address
            block.timestamp
        );
        liquidityLocked = true;

        IERC20 liquidityTokens = IERC20(uniswapV2Pair); //Get the Uni LP token
        
        //Get the LP token balance 
        uint256 liquidityBalance = liquidityTokens.balanceOf(contract_owner);
        
        uint256 timeToLockTill = liquidityUnlock;

        //Approve the LP token to unicrypt
        liquidityTokens.approve(address(unicrypt), liquidityBalance);

        //Lock it in Unicrypto
        unicrypt.depositToken{value: 0}(uniswapV2Pair, liquidityBalance, timeToLockTill);


        lockedLiquidityAmount = lockedLiquidityAmount.add(liquidityBalance);
        
    }


    //Function to withdraw LP tokens from unicrypt
    function withdrawFromUnicrypt(uint256 amount) external onlyOwner {
        unicrypt.withdrawToken(uniswapV2Pair, amount);
    }


    //Refund is called by investor 
    function getRefund() external nonReentrant {
        require(isRefundEnabled, "Cannot refund");
        require(
            isCrowdsaleFailed(),
            "FontsCrowdsale: Can only refundable if crowdsale failed to secure softcap AND after crowdsale time over"
        );        
        
        address payable beneficiary = _msgSender();
        uint256 amount = contributions[beneficiary];
        contributions[beneficiary] = 0;
        tokensBought = tokensBought.sub(font_buyers[beneficiary]);
        font_buyers[beneficiary] = 0;
        beneficiary.transfer(amount);
    }

    //FONT can be claim by investors after sale success, It is optional 
    function claimFont() external nonReentrant {
        require(
            isCrowdsaleSuccess(),
            "FontsCrowdsale: can only send liquidity once hardcap is reached"
        );  
        require(_msgSender() == tx.origin);
        require(font_buyers[_msgSender()] > 0, "FontsCrowdsale: No FONT token available for this address to claim");
        
        uint256 tokenAmount_ = font_buyers[_msgSender()];



        font_buyers[_msgSender()] = 0;

        // Transfer the $FONTs to the beneficiary
        fontToken.safeTransfer(_msgSender(), tokenAmount_);

        tokensWithdrawn = tokensWithdrawn.add(tokenAmount_);

        // Create an event for this purchase
        //emit TokenPurchase(beneficiary, weiAmount, tokenAmount);        
    }



    // Return bool when crowdsale reached soft cap and time is over
    //@Done
    function isCrowdsaleSuccess() public view returns (bool) {
        return (block.timestamp >= CROWDSALE_END_TIME && weiRaised >= SOFT_CAP) || weiRaised >= HARD_CAP;
    }   

    // Return bool when crowdsale failed
    //@Done
    function isCrowdsaleFailed() public view returns (bool) {
        return block.timestamp >= CROWDSALE_END_TIME && weiRaised <= SOFT_CAP;
    }   

    //@Done
    function isCrowdsaleTimeEnded() public view returns (bool) {
        return block.timestamp >= CROWDSALE_END_TIME;
    }
    //@Done
    function withdrawEth(uint amount) external onlyOwner returns(bool){
        require(
            isCrowdsaleSuccess(),
            "FontsCrowdsale: can only send liquidity once hardcap is reached"
        );        
        require(liquidityLocked, "FontCrowdsale: Can't withdraw before Uniswap liquidity locked");
        require(amount <= address(this).balance);
        contract_owner.transfer(amount);
        return true;
    }
    //@Done
    function withdrawUnsoldFonts(uint amount) external onlyOwner returns(bool){
        require(
            isCrowdsaleTimeEnded(),
            "FontCrowdsale: can only withdraw after crowdsale time ends"
        );  
        require(liquidityLocked, "FontCrowdsale: Can't withdraw before Uniswap liquidity locked");
        require(isFontDistributed, "FontCrowdsale: Can't withdraw before FONT distribution");

        require(amount <= fontToken.balanceOf(address(this)) - tokensBought, "FontCrowdsale: You can withdraw only unsold Fonts");

        fontToken.safeTransfer(contract_owner, amount);
        return true;
    }
    //@Done
    function getFontBalance() public view returns(uint){
        return fontToken.balanceOf(address(this));
    }
    //@Done 
    function getEthBalance() public view returns(uint){
        return address(this).balance;
    }

    //@done
    //Get balance hold by address
    function userFontBalance(address user) external view returns (uint256) {
        return font_buyers[user];
    }

    //@done
    function userEthContribution(address user) external view returns (uint256) {
        return contributions[user];
    }
}
