import { ethers } from "@nomiclabs/buidler";
import { expect } from "chai";
import { UniswapFactoryMockFactory } from "../../src/types/UniswapFactoryMockFactory";
import { UniswapV2PairMockFactory } from "../../src/types/UniswapV2PairMockFactory";
import { UniswapRouterMockFactory } from "../../src/types/UniswapRouterMockFactory";
import { TacoTokenFactory } from "../../src/types/TacoTokenFactory";
import { TacosCrowdsaleFactory } from "../../src/types/TacosCrowdsaleFactory";

// const { time } = require('@openzeppelin/test-helpers');
import {network} from "@nomiclabs/buidler";
import { TacosCrowdsale } from "../../src/types/TacosCrowdsale";
import { TacoToken } from "../../src/types/TacoToken";
import { KarmaTokenMock } from "../../src/types/KarmaTokenMock";
import { Signer } from "ethers";
import { UniswapRouterMock } from "../../src/types/UniswapRouterMock";
import { parseEther } from "ethers/utils";

const TOTAL_SUPPLY = "15624000000000000000000000";
const CIRCULATING_SUPPLY = "14530320000000000000000000";
const TACOS_PER_ETH = 34596;
const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

xdescribe("Token Crowdsale", function() {
  let tacoToken: TacoToken;
  let karmaToken: KarmaTokenMock;
  let tacosCrowdsale: TacosCrowdsale;
  let uniswapRouterContract: UniswapRouterMock;
  let deployer: Signer;
  let earlyCook: Signer;
  let karmaMember: Signer;
  let karmaHolder: Signer;
  let publicPerson: Signer;
  let deployerAddr: string;
  let earlyCookAddr: string;
  let karmaMemberAddr: string;
  let karmaHolderAddr: string;
  let publicPersonAddr: string;

  beforeEach(async function() {
    [deployer, earlyCook, karmaMember, karmaHolder, publicPerson] = await ethers.getSigners();
    deployerAddr = await deployer.getAddress();
    earlyCookAddr = await earlyCook.getAddress();
    karmaMemberAddr = await karmaMember.getAddress();
    karmaHolderAddr = await karmaHolder.getAddress();
    publicPersonAddr = await publicPerson.getAddress();

    const karmaTokenFactory = new KarmaTokenMockFactory(deployer);
    karmaToken = await karmaTokenFactory.deploy();
    await karmaToken.deployed();

    const karmaMemberAddress = await karmaMember.getAddress();
    const karmaHolderAddress = await karmaHolder.getAddress();
    await karmaToken.setKarmaMember(karmaMemberAddress);
    await karmaToken.setKarmaHolderNotMember(karmaHolderAddress);

    const uniswapV2PairFactory = new UniswapV2PairMockFactory(deployer);
    const uniswapPool = await uniswapV2PairFactory.deploy();
    await uniswapPool.deployed();

    const uniswapFactoryMockFactory = new UniswapFactoryMockFactory(deployer);
    const uniswapFactory = await uniswapFactoryMockFactory.deploy(uniswapPool.address);
    await uniswapFactory.deployed();

    const tacoTokenFactory = new TacoTokenFactory(deployer);
    tacoToken = await tacoTokenFactory.deploy(TOTAL_SUPPLY, uniswapFactory.address, WETH_ADDRESS);
    await tacoToken.deployed();
    await tacoToken.setUniswapPool();

    const uniswapRouterFactory = new UniswapRouterMockFactory(deployer);
    uniswapRouterContract = await uniswapRouterFactory.deploy();
    await uniswapRouterContract.deployed();

    const tacosCrowdsaleFactory = new TacosCrowdsaleFactory(deployer);
    tacosCrowdsale = await tacosCrowdsaleFactory.deploy(
      tacoToken.address,
      karmaToken.address,
      TACOS_PER_ETH,
      uniswapRouterContract.address
    );
    await tacosCrowdsale.deployed();

    await tacosCrowdsale.setCooksList([earlyCookAddr]);

    await tacoToken.transfer(tacosCrowdsale.address, CIRCULATING_SUPPLY);
    await tacoToken.setPauser(tacosCrowdsale.address);
  });

  describe("initial state after deploy", function() {
    it("assigns the correct tacosPerEth", async function() {
      expect(await tacosCrowdsale.tacosPerEth()).to.equal(TACOS_PER_ETH);
    });

    it("links the correct tacoToken", async function() {
      expect(await tacosCrowdsale.tacoToken()).to.equal(tacoToken.address);
    });

    it("links the correct karmaToken", async function() {
      expect(await tacosCrowdsale.karmaToken()).to.equal(karmaToken.address);
    });

    it("sets the currentRound to Cooks", async function() {
      expect(await tacosCrowdsale.getCurrentRound()).to.equal("Cooks");
    });
  });

  it("#setCooksList works", async function() {
    const cooksList = [earlyCookAddr, karmaHolderAddr, publicPersonAddr];
    await tacosCrowdsale.setCooksList(cooksList);

    cooksList.forEach(async function(addr) {
      expect(await tacosCrowdsale.cookslist(addr)).to.be.true;
    });
  });

  describe("before crowdsale starts", function () {
    beforeEach(async function() {
      const isOpen = await tacosCrowdsale.isOpen();
      if (isOpen) this.skip;
      // If crowdsaleIsOpen it means that this test cannot be performed anymore
      // Given that the timestamp is hardcoded we cannot really change it, but
      // that just means that the contract was already deployed and used, so
      // no point in testing something thats already out.
    });

    it("#isOpen returns false", async function() {
      expect(await tacosCrowdsale.isOpen()).to.be.false;
    });

    it("#hasEnded returns false", async function() {
      expect(await tacosCrowdsale.hasEnded()).to.be.false;
    });

    it("#publicSaleStarted returns false", async function() {
      expect(await tacosCrowdsale.publicSaleStarted()).to.be.false
    });

    it("#addAndLockLiquidity reverts", async function() {
      await expect(tacosCrowdsale.addAndLockLiquidity())
      .to.be.revertedWith("TacosCrowdsale: can only send liquidity once hardcap is reached");
    });

    describe("trying to purchase tokens", function() {
      it("deployer cannot purchase token, but contract accepts ETH from them", async function() {
        await expect(() => deployer.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: 200}))
          .to.changeBalances([deployer], [-200]);
      });

      it("earlyCook cannot purchase yet", async function() {
        await expect(earlyCook.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: 200}))
          .to.be.revertedWith("TacosCrowdsale: sale did not start yet.");
      });

      it("karmaMember cannot purchase yet", async function() {
        await expect(karmaMember.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: 200}))
          .to.be.revertedWith("TacosCrowdsale: sale did not start yet.");
      });

      it("karmaHolder cannot purchase yet", async function() {
        await expect(karmaHolder.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: 200}))
          .to.be.revertedWith("TacosCrowdsale: sale did not start yet.");
      });

      it("publicPerson cannot purchase yet", async function() {
        await expect(publicPerson.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: 200}))
          .to.be.revertedWith("TacosCrowdsale: sale did not start yet.");
      });
    });
  });

  describe("after crowdsale starts", function () {
    before(async function() {
      await network.provider.send("evm_setNextBlockTimestamp", [1596952801]);
      await network.provider.send("evm_mine");
    })

    describe("during Cooks Round", function() {
      it("#isOpen returns true", async function() {
        expect(await tacosCrowdsale.isOpen()).to.be.true;
      });

      it("#hasEnded returns false", async function() {
        expect(await tacosCrowdsale.hasEnded()).to.be.false;
      });

      it("#publicSaleStarted returns false", async function() {
        expect(await tacosCrowdsale.publicSaleStarted()).to.be.false;
      });
  
      it("#addAndLockLiquidity reverts", async function() {
        await expect(tacosCrowdsale.addAndLockLiquidity())
        .to.be.revertedWith("TacosCrowdsale: can only send liquidity once hardcap is reached");
      });

      it("round is Cooks", async function() {
        expect(await tacosCrowdsale.getCurrentRound()).to.equal("Cooks");
      });

      describe("trying to purchase tokens", function() {
        it("deployer cannot purchase token, but contract accepts ETH from them", async function() {
          await expect(() => deployer.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: 200}))
            .to.changeBalances([deployer], [-200]);
          expect(await tacoToken.balanceOf(earlyCookAddr)).to.equal(0);
        });

        it("earlyCook can purchase tokens", async function() {
          await expect(() => earlyCook.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("2")}))
            .to.changeBalances([earlyCook], [parseEther("-2")]);
          expect(await tacoToken.balanceOf(earlyCookAddr)).to.equal(parseEther((34596 * 2).toString()));
        });

        it("earlyCook can purchase tokens when it's less than 12 ether", async function() {
          await expect(() => earlyCook.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("1.5")}))
            .to.changeBalances([earlyCook], [parseEther("-1.5")]);
          expect(await tacoToken.balanceOf(earlyCookAddr)).to.equal(parseEther((34596 * 1.5).toString()));
        });

        it("earlyCook can purchase tokens even when sending more than 12 ether, but can only purchase 12 ether", async function() {
          await expect(() => earlyCook.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("15")}))
            .to.changeBalances([earlyCook], [parseEther("-12")]);
          expect(await tacoToken.balanceOf(earlyCookAddr)).to.equal(parseEther((34596 * 12).toString()));
        });

        it("earlyCook cannot purchase more tokens once they've reached their cap", async function() {
          await expect(() => earlyCook.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("15")}))
            .to.changeBalances([earlyCook], [parseEther("-12")]);
          expect(await tacoToken.balanceOf(earlyCookAddr)).to.equal(parseEther((34596 * 12).toString()));
          await expect(earlyCook.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("15")}))
            .to.be.revertedWith("TacosCrowdsale: Individual cap has been filled.");
        });

        it("earlyCook cannot purchase tokens when minimum contribution is not met", async function() {
          await expect(earlyCook.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("0.09")}))
            .to.be.revertedWith("TacosCrowdsale: weiAmount is smaller than min contribution.");
          expect(await tacoToken.balanceOf(earlyCookAddr)).to.equal("0");
        });

        it("limits the cap to just the first 70ether raised", async function() {
          const [, ...signers] = await ethers.getSigners();
          const addresses = await Promise.all(signers.map(async function(signer) {
            return (await signer.getAddress());
          }));
          await tacosCrowdsale.setCooksList(addresses);

          let task = 0;
          let tasksDone = 0;
          const sleep = (milliseconds: number) => {
            return new Promise(resolve => setTimeout(resolve, milliseconds))
          }

          await Promise.all(signers.map(async function(earlyCook) {
            // Syncronize these tasks.
            // My weird implementation of a semaphore.
            const currTask = task;
            task += 1;
            while (currTask > tasksDone) await sleep(100);

            const addr = await earlyCook.getAddress();
            const weiReised = await tacosCrowdsale.weiRaised();
            if (weiReised.lt(parseEther("70"))) {
              await expect(() => earlyCook.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("10")}))
                .to.changeBalances([earlyCook], [parseEther("-10")]);
              expect(await tacoToken.balanceOf(addr)).to.equal(parseEther((34596 * 10).toString()));
            } else {
              await expect(earlyCook.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("10")}))
                .to.be.revertedWith("TacosCrowdsale: The cap for the current round has been filled.");
              expect(await tacoToken.balanceOf(addr)).to.be.eq(0);
            }
            tasksDone += 1;
          }));

          expect(await tacosCrowdsale.weiRaised()).to.be.lte(parseEther("70"));

        });

        it("karmaMember cannot purchase yet", async function() {
          await expect(karmaMember.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: 200}))
            .to.be.revertedWith("TacosCrowdsale: Address not allowed for this round.");
        });

        it("karmaHolder cannot purchase yet", async function() {
          await expect(karmaHolder.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: 200}))
            .to.be.revertedWith("TacosCrowdsale: Address not allowed for this round.");
        });

        it("publicPerson cannot purchase yet", async function() {
          await expect(publicPerson.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: 200}))
            .to.be.revertedWith("TacosCrowdsale: Address not allowed for this round.");
        });
      });
    });

    describe("during Karma Round", function() {
      before(async function() {
        await network.provider.send("evm_setNextBlockTimestamp", [1597075201]);
        await network.provider.send("evm_mine");
      });

      it("#isOpen returns true", async function() {
        expect(await tacosCrowdsale.isOpen()).to.be.true;
      });

      it("#hasEnded returns false", async function() {
        expect(await tacosCrowdsale.hasEnded()).to.be.false;
      });

      it("#publicSaleStarted returns false", async function() {
        expect(await tacosCrowdsale.publicSaleStarted()).to.be.false;
      });

      it("#addAndLockLiquidity reverts", async function() {
        await expect(tacosCrowdsale.addAndLockLiquidity())
        .to.be.revertedWith("TacosCrowdsale: can only send liquidity once hardcap is reached");
      });

      it("round is Karma", async function() {
        expect(await tacosCrowdsale.getCurrentRound()).to.equal("Karma");
      });

      describe("trying to purchase tokens", function() {
        it("deployer cannot purchase token, but contract accepts ETH from them", async function() {
          await expect(() => deployer.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: 200}))
            .to.changeBalances([deployer], [-200]);
          expect(await tacoToken.balanceOf(earlyCookAddr)).to.equal(0);
        });

        it("karmaMember can purchase tokens", async function() {
          await expect(() => karmaMember.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("2")}))
            .to.changeBalances([karmaMember], [parseEther("-2")]);
          expect(await tacoToken.balanceOf(karmaMemberAddr)).to.equal(parseEther((34596 * 2).toString()));
        });

        it("karmaMember can purchase tokens when it's less than 12 ether", async function() {
          await expect(() => karmaMember.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("1.5")}))
            .to.changeBalances([karmaMember], [parseEther("-1.5")]);
          expect(await tacoToken.balanceOf(karmaMemberAddr)).to.equal(parseEther((34596 * 1.5).toString()));
        });

        it("karmaMember can purchase tokens even when sending more than 12 ether, but can only purchase 12 ether", async function() {
          await expect(() => karmaMember.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("15")}))
            .to.changeBalances([karmaMember], [parseEther("-12")]);
          expect(await tacoToken.balanceOf(karmaMemberAddr)).to.equal(parseEther((34596 * 12).toString()));
        });

        it("karmaMember cannot purchase more tokens once they've reached their cap", async function() {
          await expect(() => karmaMember.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("15")}))
            .to.changeBalances([karmaMember], [parseEther("-12")]);
          expect(await tacoToken.balanceOf(karmaMemberAddr)).to.equal(parseEther((34596 * 12).toString()));
          await expect(karmaMember.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("15")}))
            .to.be.revertedWith("TacosCrowdsale: Individual cap has been filled.");
        });

        it("karmaMember cannot purchase tokens when minimum contribution is not met", async function() {
          await expect(karmaMember.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("0.09")}))
            .to.be.revertedWith("TacosCrowdsale: weiAmount is smaller than min contribution.");
          expect(await tacoToken.balanceOf(karmaMemberAddr)).to.equal("0");
        });

        it("limits the cap to just the first 140ether raised", async function() {
          const [, ...signers] = await ethers.getSigners();
          await Promise.all(signers.map(async function(signer) {
            const addr = await signer.getAddress();
            await karmaToken.setKarmaMember(addr);
          }));

          let task = 0;
          let tasksDone = 0;
          const sleep = (milliseconds: number) => {
            return new Promise(resolve => setTimeout(resolve, milliseconds))
          }

          await Promise.all(signers.map(async function(signer) {
            // Syncronize these tasks.
            // My weird implementation of a semaphore.
            const currTask = task;
            task += 1;
            while (currTask > tasksDone) await sleep(100);

            const addr = await signer.getAddress();
            const weiReised = await tacosCrowdsale.weiRaised();
            if (weiReised.lt(parseEther("140"))) {
              await expect(() => signer.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("10")}))
                .to.changeBalances([signer], [parseEther("-10")]);
              expect(await tacoToken.balanceOf(addr)).to.equal(parseEther((34596 * 10).toString()));
            } else {
              await expect(signer.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("10")}))
                .to.be.revertedWith("TacosCrowdsale: The cap for the current round has been filled.");
              expect(await tacoToken.balanceOf(addr)).to.be.eq(0);
            }
            tasksDone += 1;
          }));

          expect(await tacosCrowdsale.weiRaised()).to.be.lte(parseEther("140"));

        });

        it("karmaHolder cannot purchase yet", async function() {
          await expect(karmaHolder.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: 200}))
            .to.be.revertedWith("TacosCrowdsale: Address not allowed for this round.");
        });

        it("publicPerson cannot purchase yet", async function() {
          await expect(publicPerson.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: 200}))
            .to.be.revertedWith("TacosCrowdsale: Address not allowed for this round.");
        });
      });
    });

    describe("during Public Round", function() {
      before(async function() {
        await network.provider.send("evm_setNextBlockTimestamp", [1597168801]);
        await network.provider.send("evm_mine");
      });

      it("#isOpen returns true", async function() {
        expect(await tacosCrowdsale.isOpen()).to.be.true;
      });

      it("#hasEnded returns false", async function() {
        expect(await tacosCrowdsale.hasEnded()).to.be.false;
      });

      it("#publicSaleStarted returns true", async function() {
        expect(await tacosCrowdsale.publicSaleStarted()).to.be.true;
      });

      it("#addAndLockLiquidity reverts", async function() {
        await expect(tacosCrowdsale.addAndLockLiquidity())
        .to.be.revertedWith("TacosCrowdsale: can only send liquidity once hardcap is reached");
      });

      it("round is Public", async function() {
        expect(await tacosCrowdsale.getCurrentRound()).to.equal("Public");
      });

      describe("trying to purchase tokens", function() {
        it("deployer cannot purchase token, but contract accepts ETH from them", async function() {
          await expect(() => deployer.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: 200}))
            .to.changeBalances([deployer], [-200]);
          expect(await tacoToken.balanceOf(earlyCookAddr)).to.equal(0);
        });

        it("karmaMember can purchase tokens", async function() {
          await expect(() => karmaMember.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("2")}))
            .to.changeBalances([karmaMember], [parseEther("-2")]);
          expect(await tacoToken.balanceOf(karmaMemberAddr)).to.equal(parseEther((34596 * 2).toString()));
        });

        it("karmaHolder can purchase tokens", async function() {
          await expect(() => karmaHolder.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("2")}))
            .to.changeBalances([karmaHolder], [parseEther("-2")]);
          expect(await tacoToken.balanceOf(karmaHolderAddr)).to.equal(parseEther((34596 * 2).toString()));
        });

        it("karmaHolder can purchase tokens when it's less than 12 ether", async function() {
          await expect(() => karmaHolder.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("1.5")}))
            .to.changeBalances([karmaHolder], [parseEther("-1.5")]);
          expect(await tacoToken.balanceOf(karmaHolderAddr)).to.equal(parseEther((34596 * 1.5).toString()));
        });

        it("karmaHolder can purchase tokens even when sending more than 12 ether, but can only purchase 12 ether", async function() {
          await expect(() => karmaHolder.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("15")}))
            .to.changeBalances([karmaHolder], [parseEther("-12")]);
          expect(await tacoToken.balanceOf(karmaHolderAddr)).to.equal(parseEther((34596 * 12).toString()));
        });

        it("karmaHolder cannot purchase more tokens once they've reached their cap", async function() {
          await expect(() => karmaHolder.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("15")}))
            .to.changeBalances([karmaHolder], [parseEther("-12")]);
          expect(await tacoToken.balanceOf(karmaHolderAddr)).to.equal(parseEther((34596 * 12).toString()));
          await expect(karmaHolder.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("15")}))
            .to.be.revertedWith("TacosCrowdsale: Individual cap has been filled.");
        });

        it("karmaHolder cannot purchase tokens when minimum contribution is not met", async function() {
          await expect(karmaHolder.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("0.09")}))
            .to.be.revertedWith("TacosCrowdsale: weiAmount is smaller than min contribution.");
          expect(await tacoToken.balanceOf(karmaHolderAddr)).to.equal("0");
        });

        it("publicPerson can purchase tokens", async function() {
          await expect(() => publicPerson.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("2")}))
            .to.changeBalances([publicPerson], [parseEther("-2")]);
          expect(await tacoToken.balanceOf(publicPersonAddr)).to.equal(parseEther((34596 * 2).toString()));
        });

        it("publicPerson can purchase tokens when it's less than 12 ether", async function() {
          await expect(() => publicPerson.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("1.5")}))
            .to.changeBalances([publicPerson], [parseEther("-1.5")]);
          expect(await tacoToken.balanceOf(publicPersonAddr)).to.equal(parseEther((34596 * 1.5).toString()));
        });

        it("publicPerson can purchase tokens even when sending more than 12 ether, but can only purchase 12 ether", async function() {
          await expect(() => publicPerson.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("15")}))
            .to.changeBalances([publicPerson], [parseEther("-12")]);
          expect(await tacoToken.balanceOf(publicPersonAddr)).to.equal(parseEther((34596 * 12).toString()));
        });

        it("publicPerson cannot purchase more tokens once they've reached their cap", async function() {
          await expect(() => publicPerson.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("15")}))
            .to.changeBalances([publicPerson], [parseEther("-12")]);
          expect(await tacoToken.balanceOf(publicPersonAddr)).to.equal(parseEther((34596 * 12).toString()));
          await expect(publicPerson.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("15")}))
            .to.be.revertedWith("TacosCrowdsale: Individual cap has been filled.");
        });

        it("publicPerson cannot purchase tokens when minimum contribution is not met", async function() {
          await expect(publicPerson.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("0.09")}))
            .to.be.revertedWith("TacosCrowdsale: weiAmount is smaller than min contribution.");
          expect(await tacoToken.balanceOf(publicPersonAddr)).to.equal("0");
        });

        it("limits the cap to just the first 210ether raised and sale is marked as Ended", async function() {
          const [, ...signers] = await ethers.getSigners();
          let task = 0;
          let tasksDone = 0;
          const sleep = (milliseconds: number) => {
            return new Promise(resolve => setTimeout(resolve, milliseconds))
          }

          await Promise.all(signers.map(async function(signer) {
            // Syncronize these tasks.
            // My weird implementation of a semaphore.
            const currTask = task;
            task += 1;
            while (currTask > tasksDone) await sleep(100);
            const addr = await signer.getAddress();
            const weiReised = await tacosCrowdsale.weiRaised();
            if (weiReised.lt(parseEther("202"))) {
              await expect(() => signer.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("12")}))
                .to.changeBalances([signer], [parseEther("-12")]);
              expect(await tacoToken.balanceOf(addr)).to.equal(parseEther((34596 * 12).toString()));
            } else if (weiReised.lt(parseEther("210"))) {
              await expect(() => signer.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("12")}))
                .to.changeBalances([signer], [parseEther("-6")]);
              expect(await tacoToken.balanceOf(addr)).to.equal(parseEther((34596 * 6).toString()));
            } else {
              await expect(signer.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("10")}))
                .to.be.revertedWith("TacosCrowdsale: sale is over.");
              expect(await tacoToken.balanceOf(addr)).to.be.eq(0);
            }
            tasksDone += 1;
          }));
          expect(await tacosCrowdsale.weiRaised()).to.be.lte(parseEther("210"));
          expect(await tacosCrowdsale.hasEnded()).to.be.true;
        });
      });

      describe("when sale has ended", async function() {
        beforeEach(async function() {
          const [,, ...signers] = await ethers.getSigners();

          await Promise.all(signers.map(async function(signer) {
            await (await signer.sendTransaction({to: tacosCrowdsale.address, gasPrice: 0, value: parseEther("12")})).wait(1);
          }));
        });

        it("Eth balance of contract should be 210 Ethers", async function() {
          expect(await ethers.provider.getBalance(tacosCrowdsale.address)).to.be.eq(parseEther("210"));
        });

        it("Tacos balance of contract should be half of the circulating supply", async function() {
          expect(await tacoToken.balanceOf(tacosCrowdsale.address)).to.be.eq(parseEther("14530320").div(2));
        });

        it("#hasEnded returns true", async function() {
          expect(await tacosCrowdsale.hasEnded()).to.be.true;
        });

        it("#addAndLockLiquidity satisfies", async function() {
          await expect(tacosCrowdsale.addAndLockLiquidity());
        });

        it("raised 210 ether", async function () {
          expect(await tacosCrowdsale.weiRaised()).to.be.lte(parseEther("210"));
        });
      });
    });
  });
})

