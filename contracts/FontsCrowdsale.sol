// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IUniswapV2Router.sol";

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
 *        All liquidity is added to Uniswap and locked automatically, 0% risk of rug pull.
 *
 * @author soulbar@protonmail.com ($TEND)
 * @author @Onchained ($TACO)
 * @author @adalquardz ($FONT)
 */
contract FontsCrowdsale is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    address owner;

    //===============================================//
    //          Contract Variables                   //
    //===============================================//


    // Caps
    uint256 public constant ROUND_1_CAP = 180 ether; 
    uint256 public constant ROUND_2_CAP = 400 ether; 

    uint256 public constant SOFT_CAP = 300 ether; // Softcap  = 300
    uint256 public constant HARD_CAP = 400 ether; // hardcap = +100

    uint256 public constant FONT_PER_ETH_ROUND_1 = 1111;
    uint256 public constant FONT_PER_ETH_ROUND_2 = 909;
    
    
    // During tests, we should use 12 ether instead given that by default we only have 20 addresses.
    uint256 public constant CAP_PER_ADDRESS = 6 ether;
    uint256 public constant MIN_CONTRIBUTION = 0.1 ether;


    //TIME
    // Start time 08/09/2020 @ 6:00am (UTC) // For Cooks
    uint256 public constant CROWDSALE_START_TIME = 1596952800;
    // Start time 08/11/2020 @ 4:00pm (UTC)

    // End time
    uint256 public constant CROWDSALE_END_TIME = 7 days;


    // How many ETH need to lock in Uniswap LP 
    uint256 AMOUNT_ETH_FOR_UNISWAP_LP = 143 ether;
  
    // How many $FONTs need to lock in Uniswap LP 
    uint256 AMOUNT_FONT_FOR_UNISWAP_LP = 100000 * 10**18;


    // Contributions state
    mapping(address => uint256) public contributions;

    // Total wei raised (ETH)
    uint256 public weiRaised;

    // Flag to know if liquidity has been locked
    bool public liquidityLocked = false;

    // Pointer to the FONTToken
    IERC20 public fontToken;



    // Pointer to the UniswapRouter
    IUniswapV2Router02 internal uniswapRouter;

    //===============================================//
    //                 Constructor                   //
    //===============================================//
    constructor(
        IERC20 _fontToken,
        address _uniswapRouter
    ) public Ownable() {
        owner = msg.sender;        
        fontToken = _fontToken;
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
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
        if (owner() != msg.sender) {
            // Validations.

            require(isOpen(), "FontsCrowdsale: sale did not start yet.");
            require(!hasEnded(), "FontsCrowdsale: sale is over.");
            require(
                weiRaised < _totalCapForCurrentRound(),
                "FontsCrowdsale: The cap for the current round has been filled."
            );
            require(
                contributions[msg.sender] < CAP_PER_ADDRESS,
                "FontsCrowdsale: Individual cap has been filled."
            );

            // If we've passed most validations, let's get them $FONTs
            _buyTokens(msg.sender);
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
        // Transfer the $FONTs to the beneficiary
        fontToken.safeTransfer(beneficiary, tokenAmount);

        // Create an event for this purchase
        emit TokenPurchase(beneficiary, weiAmount, tokenAmount);
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
        return now >= CROWDSALE_START_TIME;
    }

    // Has the sale ended?
    //@done
    function hasEnded() public view returns (bool) {
        return now >= CROWDSALE_END_TIME || weiRaised >= ROUND_2_CAP;
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
    function addAndLockLiquidity() external onlyOwner {
        require(
            isCrowdsaleSuccess(),
            "FontCrowdsale: can only send liquidity once softcap is reached"
        );
        require(!liquidityLocked, "FontCrowdsale: Liquidity already locked");

        // Unpause FONTToken forever. This will kick off the game.
        Pauseable(address(fontToken)).unpause();

        // Send the entire balance and all tokens in the contract to Uniswap LP
        fontToken.approve(address(uniswapRouter), AMOUNT_FONT_FOR_UNISWAP_LP);

        uniswapRouter.addLiquidityETH{value: AMOUNT_ETH_FOR_UNISWAP_LP}(
            address(fontToken),
            AMOUNT_FONT_FOR_UNISWAP_LP,
            AMOUNT_FONT_FOR_UNISWAP_LP,
            AMOUNT_ETH_FOR_UNISWAP_LP,
            owner, // burn address
            now
        );
        liquidityLocked = true;
    }

    // Return bool when crowdsale reached soft cap and time is over
    //@Done
    function isCrowdsaleSuccess() public view returns (bool) {
        return now >= CROWDSALE_END_TIME && weiRaised >= SOFT_CAP;
    }    
    //@Done
    function isCrowdsaleEnded() public view returns (bool) {
        return now >= CROWDSALE_END_TIME;
    }
    //@Done
    function withdrawEth(uint amount) external onlyOwner returns(bool){
        require(
            isCrowdsaleSuccess(),
            "FontsCrowdsale: can only send liquidity once hardcap is reached"
        );        
        require(liquidityLocked, "FontCrowdsale: Can't withdraw before Uniswap liquidity locked");
        require(amount <= this.balance);
        owner.transfer(amount);
        return true;
    }
    //@Done
    function withdrawFonts(uint amount) external onlyOwner returns(bool){
        require(
            isCrowdsaleEnded(),
            "FontCrowdsale: can only withdraw after crowdsale time ends"
        );  
        require(liquidityLocked, "FontCrowdsale: Can't withdraw before Uniswap liquidity locked");
        require(amount <= fontToken.balanceOf(address(this)));
        fontToken.safeTransfer(owner, amount);
        return true;
    }
    //@Done
    function getFontBalance() public view returns(uint){
        return fontToken.balanceOf(address(this));
    }
    //@Done 
    function getEthBalance() public view returns(uint){
        return this.balance;
    }

}
