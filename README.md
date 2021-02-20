
**Rules :**

 1. Only hardcap, 180ETH in 7 days duration else refund 
 2. 1111 FONTs pre ETH and vesting is 50%-30%-20%, send in batch (we covering the gas)
 3. Owner will call startPresale to kickstart funding
 4. Once it reached hardcap, owner call
     1. createUniPair -> addLiquidity -> lockLiquidity -> distributeTokensRoundOne (50%) -> withdrawEth
     2. distributeTokensRoundTwo (30%) after 30 days
     3. distributeTokensRoundThree (20%) after 60 days
     4. can unlock LP tokens after given period


Anyone can call getRefund if target not reached after 7 days.

----

For quick testing purpose i have created bool IS_TESTNET_LOCAL, set this to true to make testing quicker. 

Setting it "true" will make other variables like target, durations, unclock small. All those variables are under the comment of "Contract Testnet Variables". All those variables are prefixed with " _TN_"


----

Mainnet FONT ERC20 : 0x4C25Bdf026Ea05F32713F00f73Ca55857Fbf6342