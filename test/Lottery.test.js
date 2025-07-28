const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const { networkConfig, developmentChains } = require("../helper-hardhat-config")
describe("Lottery Contract (VRF v2.5 Mock)", function () {
  let wrapper
  let lottery;
  let VRFCoordinatorV2_5Mock;
  let vrfCoordinatorMock;
  let linkToken;
  let admin;
  let participant1;
  let participant2;
   // This value is the worst-case gas overhead from the wrapper contract under the following
    // conditions, plus some wiggle room:
    //   - 10 words requested
    //   - Refund issued to consumer
    const wrapperGasOverhead = ethers.toBigInt("100000");
    const coordinatorGasOverheadNative = ethers.toBigInt("900000");
    const coordinatorGasOverheadLink = ethers.toBigInt("112000");
    const coordinatorGasOverheadPerWord = ethers.toBigInt("435");
    const coordinatorNativePremiumPercentage = 24;
    const coordinatorLinkPremiumPercentage = 20;
    const maxNumWords = 10;
    const stalenessSeconds = ethers.toBigInt("172800");
    const fallbackWeiPerUnitLink = ethers.toBigInt("5347462396894712");
    const fulfillmentFlatFeeNativePPM = ethers.toBigInt("0");
    const fulfillmentFlatFeeLinkDiscountPPM = ethers.toBigInt("0");
const pointOneLink = ethers.parseUnits("0.1", 18); // 0.1 LINK
const pointZeroZeroThreeLink = ethers.parseUnits("0.003", 18); // 0.003 LINK
const oneHundredLink = ethers.parseUnits("100", 18); // 100 LINK
const oneHundredGwei = ethers.parseUnits("100", 9); // 100 Gwei (9 decimals)

const BASE_FEE = "1000000000000000" // 0.001 ether as base fee
const GAS_PRICE = "50000000000" // 50 gwei 
const WEI_PER_UNIT_LINK = "10000000000000000" // 0.01 ether per LINK



  const estimateRequestPrice = (
    _callbackGasLimit,
    _numWords,
    _requestGasPriceWei = oneHundredGwei,
    _weiPerUnitLink = WEI_PER_UNIT_LINK
  ) => {
  const wrapperCostWei = _requestGasPriceWei + wrapperGasOverhead
  const coordinatorOverhead = coordinatorGasOverheadPerWord * ethers.toBigInt(_numWords) + coordinatorGasOverheadLink
  
  const coordinatorCostWei = _requestGasPriceWei * (ethers.toBigInt(_callbackGasLimit) + coordinatorOverhead);
  
  const coordinatorCostWithPremiumAndFlatFeeWei = 
   ((coordinatorCostWei * (ethers.toBigInt(coordinatorLinkPremiumPercentage) + (ethers.toBigInt(100)))
       ) / ethers.toBigInt(100) ) + (ethers.toBigInt(1000000000000)*(fulfillmentFlatFeeNativePPM - (fulfillmentFlatFeeLinkDiscountPPM)))
  
  return (ethers.toBigInt("1000000000000000000") * (wrapperCostWei + (coordinatorCostWithPremiumAndFlatFeeWei))) / ethers.toBigInt(_weiPerUnitLink)
  }
  beforeEach(async function () {
    // Get signers (admin and participants)
    [admin, participant1, participant2] = await ethers.getSigners();
    
 
    const fund = async (link, linkOwner, receiver, amount) => {
      await expect(link.connect(linkOwner).transfer(receiver, amount)).to.not.be.reverted
    }

    // Step 1: Deploy a mock LINK token
    const LinkTokenFactory = await ethers.getContractFactory("MockLinkToken",admin);
    linkToken = await LinkTokenFactory.deploy();
    await linkToken.waitForDeployment();

    console.log("LinkToken deployed to:", linkToken.target);

    // Step 2: Deploy VRFCoordinatorV2_5Mock with required parameters
    const VRFCoordinatorV2_5MockFactory = await ethers.getContractFactory("VRFCoordinatorV2_5Mock",admin);

    vrfCoordinatorMock = await VRFCoordinatorV2_5MockFactory.deploy(BASE_FEE, GAS_PRICE, WEI_PER_UNIT_LINK);
    await vrfCoordinatorMock.waitForDeployment();

    console.log("VRFCoordinatorV2_5Mock deployed to:", vrfCoordinatorMock.target);

    const transaction = await vrfCoordinatorMock.createSubscription()
    const transactionReceipt = await transaction.wait()
    const events = await vrfCoordinatorMock.queryFilter("SubscriptionCreated", transactionReceipt.blockNumber, transactionReceipt.blockNumber);

    await expect(transaction).to.emit(vrfCoordinatorMock, "SubscriptionCreated")
    const subscriptionId = ethers.toBigInt(events[0].topics[1])
    console.log(events[0].topics[1])
    const linkEthFeedFactory = await ethers.getContractFactory("MockV3Aggregator", admin)
    const linkEthFeed = await linkEthFeedFactory.deploy(18, WEI_PER_UNIT_LINK) // 1 LINK = 0.01 ETH
    await linkEthFeed.waitForDeployment();

    const chainId = network.config.chainId
    const keyHash = networkConfig[chainId]["keyHash"]
    const wrapperFactory =  await ethers.getContractFactory("VRFV2PlusWrapper",admin)
    console.log("Deploying VRFV2PlusWrapper...")
    console.log("LinkToken:", linkToken.target),
    console.log("LinkEthFeed:", linkEthFeed.target),
    console.log("VRFCoordinator:", vrfCoordinatorMock.target),
    console.log("Subscription ID:", subscriptionId)
    wrapper = await wrapperFactory.deploy(
      linkToken.target,
      linkEthFeed.target,
      vrfCoordinatorMock.target,
      subscriptionId,
    )

    await wrapper.waitForDeployment();
    console.log("Configuring VRFV2PlusWrapper...")

    await wrapper
      .connect(admin)
      .setConfig(
        wrapperGasOverhead,
        coordinatorGasOverheadNative,
        coordinatorGasOverheadLink,
        coordinatorGasOverheadPerWord,
        coordinatorNativePremiumPercentage,
        coordinatorLinkPremiumPercentage,
        keyHash,
        maxNumWords,
        stalenessSeconds,
        fallbackWeiPerUnitLink,
        fulfillmentFlatFeeNativePPM,
        fulfillmentFlatFeeLinkDiscountPPM
      )
   console.log(keyHash)
    console.log("Wrapper:", wrapper.target)
    console.log("LinkToken:", linkToken.target)
    console.log("Deploying Lottery...")

    // Step 3: Deploy the Lottery contract
    const LotteryFactory = await ethers.getContractFactory("Lottery",admin);
    lottery = await LotteryFactory.deploy(
      wrapper.target, // VRF Wrapper (mock)
      linkToken.target // LINK token address
    );
    
    console.log("Funding subscription...")
    await vrfCoordinatorMock.connect(admin).fundSubscription(subscriptionId, oneHundredLink)
    console.log("Adding consumer...")
    await vrfCoordinatorMock.connect(admin).addConsumer(subscriptionId, wrapper.target)
    await lottery.waitForDeployment();
    await fund(linkToken, admin,  lottery.target, oneHundredLink)
    
    console.log("Lottery deployed to:", lottery.target);
  });

  it("Should create a new draw", async function () {
    const endDate = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now
    await lottery.connect(admin).createDraw(endDate);

    const drawId = await lottery.getCurrentDrawId();
    const drawDetails = await lottery.getDrawDetails(drawId);
    console.log(drawDetails[3])
    expect(drawDetails[0]).to.equal(endDate);
    expect(drawDetails[1].length).to.equal(0);
    expect(drawDetails[2]).to.be.false;
    expect(drawDetails[3]).to.equal(ethers.ZeroAddress);
  });

  it("Should add participants to a draw", async function () {
    const endDate = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now
    await lottery.connect(admin).createDraw(endDate);

    const drawId = await lottery.getCurrentDrawId();
    await lottery.connect(admin).addParticipant(drawId, participant1.address);
    await lottery.connect(admin).addParticipant(drawId, participant2.address);

    const drawDetails = await lottery.getDrawDetails(drawId);
    expect(drawDetails.participants).to.include(participant1.address);
    expect(drawDetails.participants).to.include(participant2.address);
  });

  it("Should select a winner after the end date", async function () {
    const endDate = Math.floor(Date.now() / 1000) + 5; // 5 seconds ahead
    await lottery.connect(admin).createDraw(endDate);
    const drawId = await lottery.getCurrentDrawId();
  
    await lottery.connect(admin).addParticipant(drawId, participant1.address);
    await lottery.connect(admin).addParticipant(drawId, participant2.address);
  
    // Wait for the draw to expire
    await new Promise((resolve) => setTimeout(resolve, 6000));
  
    // Call requestRandomWinner with nativePayment set to false (using LINK)
    await lottery.connect(admin).requestRandomWinner(drawId, false); // false = pay in LINK
  
    const requestId = await lottery.lastRequestId();
    const randomness = [123];
  
    const tx = await vrfCoordinatorMock.connect(admin).fulfillRandomWordsWithOverride(
      requestId,
      wrapper.target,
      randomness,
      { gasLimit: 1_000_000 }
    );
  
    const receipt = await tx.wait();
    const events = await vrfCoordinatorMock.queryFilter(
      "RandomWordsFulfilled",
      receipt.blockNumber,
      receipt.blockNumber
    );
  
    await expect(tx).to.emit(vrfCoordinatorMock, "RandomWordsFulfilled");
    await expect(tx).to.emit(lottery, "RequestFulfilled");
  
    const { paid, fulfilled, randomWords } = await lottery.getRequestStatus(requestId);
    expect(fulfilled).to.be.true;
    expect(randomWords.length).to.be.greaterThan(0);
  
    const drawDetails = await lottery.getDrawDetails(drawId);
    expect(drawDetails.drawCompleted).to.be.true;
    expect([participant1.address, participant2.address]).to.include(drawDetails.winner);
  });
  it("Should select a winner with native payment", async function () {
    const endDate = Math.floor(Date.now() / 1000) + 5;
    await lottery.connect(admin).createDraw(endDate);
    const drawId = await lottery.getCurrentDrawId();
  
    await lottery.connect(admin).addParticipant(drawId, participant1.address);
    await lottery.connect(admin).addParticipant(drawId, participant2.address);
  
    // Wait until draw expires
    await new Promise((resolve) => setTimeout(resolve, 6000));
  
    const estimatedPrice = await lottery.getEstimatedRequestPrice(true); // true = native
  
    await lottery.connect(admin).requestRandomWinner(drawId, true, {
      value: estimatedPrice,
      gasLimit: 1_000_000,
    });
  
    const requestId = await lottery.lastRequestId();
    const randomness = [456];
  
    const tx = await vrfCoordinatorMock.connect(admin).fulfillRandomWordsWithOverride(
      requestId,
      wrapper.target,
      randomness,
      { gasLimit: 1_000_000 }
    );
  
    const drawDetails = await lottery.getDrawDetails(drawId);
    expect(drawDetails.drawCompleted).to.be.true;
    expect([participant1.address, participant2.address]).to.include(drawDetails.winner);
  });
  it("Should allow admin to update callbackGasLimit", async function () {
    await expect(lottery.connect(admin).setCallbackGasLimit(600_000))
      .to.emit(lottery, "CallbackGasLimitUpdated")
      .withArgs(600_000);
    expect(await lottery.callbackGasLimit()).to.equal(600_000);
  });

  it("Should allow admin to update numWords", async function () {
    await expect(lottery.connect(admin).setNumWords(3))
      .to.emit(lottery, "NumWordsUpdated")
      .withArgs(3);
    expect(await lottery.numWords()).to.equal(3);
  });

  it("Should allow admin to update keyHash", async function () {
    const newKeyHash = ethers.keccak256(ethers.toUtf8Bytes("new-key-hash"));
    await expect(lottery.connect(admin).setKeyHash(newKeyHash))
      .to.emit(lottery, "KeyHashUpdated")
      .withArgs(newKeyHash);
    expect(await lottery.keyHash()).to.equal(newKeyHash);
  });

  it("Should allow admin to update minConfirmations", async function () {
    await expect(lottery.connect(admin).setMinConfirmations(5))
      .to.emit(lottery, "MinConfirmationsUpdated")
      .withArgs(5);
    expect(await lottery.minConfirmations()).to.equal(5);
  });

  it("Should allow admin to update wrapper address", async function () {
    await expect(lottery.connect(admin).setWrapperAddress(mockVRFWrapper.target))
      .to.emit(lottery, "WrapperAddressUpdated")
      .withArgs(mockVRFWrapper.target);
    expect(await lottery.i_vrfV2PlusWrapper()).to.equal(mockVRFWrapper.target);
  });

  it("Should allow admin to update LINK token address", async function () {
    await expect(lottery.connect(admin).setLinkTokenAddress(linkToken.target))
      .to.emit(lottery, "LinkTokenAddressUpdated")
      .withArgs(linkToken.target);
    expect(await lottery.i_linkToken()).to.equal(linkToken.target);
  });

  it("Should revert if non-admin tries to set values", async function () {
    await expect(lottery.connect(participant1).setCallbackGasLimit(600_000)).to.be.revertedWith("Only admin");
    await expect(lottery.connect(participant1).setNumWords(3)).to.be.revertedWith("Only admin");
    await expect(lottery.connect(participant1).setKeyHash(ethers.keccak256(ethers.toUtf8Bytes("x")))).to.be.revertedWith("Only admin");
    await expect(lottery.connect(participant1).setMinConfirmations(5)).to.be.revertedWith("Only admin");
    await expect(lottery.connect(participant1).setWrapperAddress(mockVRFWrapper.target)).to.be.revertedWith("Only admin");
    await expect(lottery.connect(participant1).setLinkTokenAddress(linkToken.target)).to.be.revertedWith("Only admin");
  });
  it("Should allow admin to withdraw LINK", async function () {
    // Fund the contract with LINK
    const linkAmount = ethers.parseEther("10");
    await linkToken.transfer(lottery.target, linkAmount);

    const adminLinkBalanceBefore = await linkToken.balanceOf(admin.address);

    await expect(lottery.connect(admin).withdrawLink())
      .to.emit(linkToken, "Transfer")
      .withArgs(lottery.target, admin.address, linkAmount);

    const adminLinkBalanceAfter = await linkToken.balanceOf(admin.address);
    expect(adminLinkBalanceAfter - adminLinkBalanceBefore).to.equal(linkAmount);
  });

  it("Should revert if no LINK balance to withdraw", async function () {
    await expect(lottery.connect(admin).withdrawLink()).to.be.revertedWith("No LINK to withdraw");
  });

  it("Should allow admin to withdraw native tokens", async function () {
    const nativeAmount = ethers.parseEther("2");
    await admin.sendTransaction({ to: lottery.target, value: nativeAmount });

    const adminNativeBalanceBefore = await ethers.provider.getBalance(admin.address);

    const tx = await lottery.connect(admin).withdrawNative();
    const receipt = await tx.wait();
    const gasUsed = receipt.gasUsed * receipt.gasPrice;

    const adminNativeBalanceAfter = await ethers.provider.getBalance(admin.address);

    // Because of gas, allow margin of error
    expect(adminNativeBalanceAfter).to.be.closeTo(adminNativeBalanceBefore + nativeAmount - gasUsed, ethers.parseEther("0.001"));
  });

  it("Should revert if no native token to withdraw", async function () {
    await expect(lottery.connect(admin).withdrawNative()).to.be.revertedWith("No native token to withdraw");
  });

  it("Should revert if non-admin tries to withdraw", async function () {
    await expect(lottery.connect(participant1).withdrawLink()).to.be.revertedWith("Only admin");
    await expect(lottery.connect(participant1).withdrawNative()).to.be.revertedWith("Only admin");
  });  
});