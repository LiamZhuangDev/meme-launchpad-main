// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LearningMEMECore} from "../src/LearningMEMECore.sol";
import {LearningMEMEFactory} from "../src/LearningMEMEFactory.sol";
import {LearningMEMEHelper} from "../src/LearningMEMEHelper.sol";
import {LearningMEMEToken} from "../src/LearningMEMEToken.sol";
import {LearningMEMEVesting} from "../src/LearningMEMEVesting.sol";
import {ILearningMEMEVesting} from "../src/interfaces/ILearningMEMEVesting.sol";

contract Step05InitialBuyAndVestingTest is Test {
    uint256 private constant SIGNER_PRIVATE_KEY = 0xA11CE;

    LearningMEMEFactory private factory;
    LearningMEMEHelper private helper;
    LearningMEMECore private core;
    LearningMEMEVesting private vesting;

    address private admin = makeAddr("admin");
    address private signer;
    address private platform = makeAddr("platform");
    address private creator = makeAddr("creator");
    address private payer = makeAddr("payer");

    function setUp() public {
        vm.warp(1_717_171_717);
        signer = vm.addr(SIGNER_PRIVATE_KEY);

        factory = new LearningMEMEFactory(admin);
        helper = new LearningMEMEHelper();
        core = new LearningMEMECore();
        vesting = new LearningMEMEVesting(admin, address(core));
        core.initialize(
            address(factory), address(helper), signer, platform, makeAddr("margin"), makeAddr("graduate"), admin
        );

        vm.prank(admin);
        core.setVesting(address(vesting));

        vm.prank(admin);
        factory.setCore(address(core));

        vm.deal(payer, 100 ether);
    }

    function testInitialBuyTransfersTokensAndStartsCurveAfterPurchase() public {
        LearningMEMECore.VestingAllocation[] memory allocations = new LearningMEMECore.VestingAllocation[](0);
        LearningMEMECore.CreateTokenParams memory params = _params(1_000, allocations);
        (uint256 initialTokens, uint256 initialBNB, uint256 initialFee) = core.calculateInitialBuyCost(
            params.totalSupply, params.virtualBNBReserve, params.virtualTokenReserve, params.initialBuyPercentage
        );
        uint256 totalPayment = core.creationFee() + initialBNB + initialFee;
        uint256 payerBalanceBefore = payer.balance;

        LearningMEMEToken token = LearningMEMEToken(_create(params, totalPayment));

        (uint256 virtualBNB, uint256 virtualTokens,, uint256 remainingTokens, uint256 collectedBNB) =
            core.bondingCurve(address(token));
        assertEq(token.balanceOf(creator), initialTokens);
        assertEq(virtualBNB, params.virtualBNBReserve + initialBNB);
        assertEq(virtualTokens, params.virtualTokenReserve - initialTokens);
        assertEq(remainingTokens, params.saleAmount - initialTokens);
        assertEq(collectedBNB, initialBNB);
        assertEq(address(core).balance, initialBNB);
        assertEq(platform.balance, core.creationFee() + initialFee);
        assertEq(payer.balance, payerBalanceBefore - totalPayment);
    }

    function testLinearVestingReleasesTokensOverTime() public {
        LearningMEMECore.VestingAllocation[] memory allocations = new LearningMEMECore.VestingAllocation[](1);
        allocations[0] = LearningMEMECore.VestingAllocation({
            percentageBP: 600, duration: 10 days, mode: ILearningMEMEVesting.VestingMode.LINEAR
        });
        LearningMEMECore.CreateTokenParams memory params = _params(1_000, allocations);
        LearningMEMEToken token = LearningMEMEToken(_create(params, _requiredPayment(params)));

        assertEq(token.balanceOf(creator), 40_000 ether);
        assertEq(token.balanceOf(address(vesting)), 60_000 ether);
        assertEq(vesting.scheduleCount(address(token), creator), 1);
        assertEq(vesting.totalTokenLocked(address(token)), 60_000 ether);

        (, uint256 startTime, uint256 endTime,, ILearningMEMEVesting.VestingMode mode) =
            vesting.vestingSchedules(address(token), creator, 0);
        assertEq(startTime, block.timestamp);
        assertEq(endTime, block.timestamp + 10 days);
        assertEq(uint8(mode), uint8(ILearningMEMEVesting.VestingMode.LINEAR));

        vm.warp(block.timestamp + 5 days);
        assertEq(vesting.getClaimableAmount(address(token), creator, 0), 30_000 ether);

        vm.prank(creator);
        vesting.claim(address(token), 0);

        assertEq(token.balanceOf(creator), 70_000 ether);
        assertEq(vesting.totalTokenLocked(address(token)), 30_000 ether);
    }

    function testCliffVestingUnlocksEverythingAtEnd() public {
        LearningMEMECore.VestingAllocation[] memory allocations = new LearningMEMECore.VestingAllocation[](1);
        allocations[0] = LearningMEMECore.VestingAllocation({
            percentageBP: 1_000, duration: 7 days, mode: ILearningMEMEVesting.VestingMode.CLIFF
        });
        LearningMEMECore.CreateTokenParams memory params = _params(1_000, allocations);
        LearningMEMEToken token = LearningMEMEToken(_create(params, _requiredPayment(params)));

        vm.warp(block.timestamp + 6 days);
        vm.prank(creator);
        vm.expectRevert(LearningMEMEVesting.NoClaimableAmount.selector);
        vesting.claim(address(token), 0);

        vm.warp(block.timestamp + 1 days);
        vm.prank(creator);
        vesting.claim(address(token), 0);

        assertEq(token.balanceOf(creator), 100_000 ether);
        assertEq(token.balanceOf(address(vesting)), 0);
    }

    function testCreationRejectsInsufficientInitialBuyPayment() public {
        LearningMEMECore.VestingAllocation[] memory allocations = new LearningMEMECore.VestingAllocation[](0);
        LearningMEMECore.CreateTokenParams memory params = _params(1_000, allocations);
        uint256 insufficientPayment = _requiredPayment(params) - 1;
        (bytes memory data, bytes memory signature) = _signedRequest(params);

        vm.prank(payer);
        vm.expectRevert(LearningMEMECore.InsufficientFee.selector);
        core.createToken{value: insufficientPayment}(data, signature);
    }

    function testCreationRejectsVestingAboveInitialBuy() public {
        LearningMEMECore.VestingAllocation[] memory allocations = new LearningMEMECore.VestingAllocation[](1);
        allocations[0] = LearningMEMECore.VestingAllocation({
            percentageBP: 1_100, duration: 7 days, mode: ILearningMEMEVesting.VestingMode.CLIFF
        });
        LearningMEMECore.CreateTokenParams memory params = _params(1_000, allocations);
        uint256 payment = _requiredPayment(params);
        (bytes memory data, bytes memory signature) = _signedRequest(params);

        vm.prank(payer);
        vm.expectRevert(LearningMEMECore.InvalidVestingAllocation.selector);
        core.createToken{value: payment}(data, signature);
    }

    function testCreationRejectsVestingWithoutInitialBuy() public {
        LearningMEMECore.VestingAllocation[] memory allocations = new LearningMEMECore.VestingAllocation[](1);
        allocations[0] = LearningMEMECore.VestingAllocation({
            percentageBP: 100, duration: 7 days, mode: ILearningMEMEVesting.VestingMode.CLIFF
        });
        LearningMEMECore.CreateTokenParams memory params = _params(0, allocations);
        uint256 payment = core.creationFee();
        (bytes memory data, bytes memory signature) = _signedRequest(params);

        vm.prank(payer);
        vm.expectRevert(LearningMEMECore.InvalidVestingAllocation.selector);
        core.createToken{value: payment}(data, signature);
    }

    function _params(uint256 initialBuyPercentage, LearningMEMECore.VestingAllocation[] memory allocations)
        private
        view
        returns (LearningMEMECore.CreateTokenParams memory)
    {
        return LearningMEMECore.CreateTokenParams({
            name: "Vested Meme",
            symbol: "VEST",
            totalSupply: 1_000_000 ether,
            saleAmount: 800_000 ether,
            virtualBNBReserve: 10 ether,
            virtualTokenReserve: 1_000_000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256(abi.encode("step-05-request", initialBuyPercentage, allocations.length)),
            nonce: initialBuyPercentage + allocations.length,
            initialBuyPercentage: initialBuyPercentage,
            vestingAllocations: allocations
        });
    }

    function _requiredPayment(LearningMEMECore.CreateTokenParams memory params) private view returns (uint256) {
        (, uint256 initialBNB, uint256 initialFee) = core.calculateInitialBuyCost(
            params.totalSupply, params.virtualBNBReserve, params.virtualTokenReserve, params.initialBuyPercentage
        );
        return core.creationFee() + initialBNB + initialFee;
    }

    function _create(LearningMEMECore.CreateTokenParams memory params, uint256 payment)
        private
        returns (address tokenAddress)
    {
        (bytes memory data, bytes memory signature) = _signedRequest(params);
        vm.prank(payer);
        return core.createToken{value: payment}(data, signature);
    }

    function _signedRequest(LearningMEMECore.CreateTokenParams memory params)
        private
        view
        returns (bytes memory data, bytes memory signature)
    {
        data = abi.encode(params);
        bytes32 digest = keccak256(abi.encodePacked(data, core.chainId(), address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIVATE_KEY, digest);
        signature = abi.encodePacked(r, s, v);
    }
}
