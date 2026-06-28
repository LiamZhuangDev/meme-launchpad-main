// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LearningMEMECore} from "../src/LearningMEMECore.sol";
import {LearningMEMEFactory} from "../src/LearningMEMEFactory.sol";
import {LearningMEMEHelper} from "../src/LearningMEMEHelper.sol";
import {LearningMEMEToken} from "../src/LearningMEMEToken.sol";
import {LearningDEXRouter} from "../src/LearningDEXRouter.sol";
import {LearningLiquidityPool} from "../src/LearningLiquidityPool.sol";
import {ILearningMEMEHelper} from "../src/interfaces/ILearningMEMEHelper.sol";

contract Step06GraduationAndLiquidityTest is Test {
    uint256 private constant SIGNER_PRIVATE_KEY = 0xA11CE;

    LearningMEMEFactory private factory;
    LearningMEMEHelper private helper;
    LearningMEMECore private core;
    LearningDEXRouter private router;
    LearningMEMEToken private token;

    address private admin = makeAddr("admin");
    address private signer;
    address private platform = makeAddr("platform");
    address private graduateReceiver = makeAddr("graduateReceiver");
    address private creator = makeAddr("creator");
    address private buyer = makeAddr("buyer");
    address private user = makeAddr("user");

    function setUp() public {
        vm.warp(1_717_171_717);
        signer = vm.addr(SIGNER_PRIVATE_KEY);

        factory = new LearningMEMEFactory(admin);
        helper = new LearningMEMEHelper();
        router = new LearningDEXRouter();
        core = new LearningMEMECore();
        core.initialize(
            address(factory), address(helper), signer, platform, makeAddr("margin"), graduateReceiver, admin
        );

        vm.startPrank(admin);
        factory.setCore(address(core));
        core.setDexRouter(address(router));
        vm.stopPrank();

        vm.deal(buyer, 100 ether);
        token = LearningMEMEToken(_createToken());
    }

    function testBuyBelowThresholdMovesTokenToPendingGraduation() public {
        _moveToPendingGraduation();

        (,,, LearningMEMECore.TokenStatus status,) = core.tokenInfo(address(token));
        (,,, uint256 remainingTokens,) = core.bondingCurve(address(token));

        assertLt(remainingTokens, core.MIN_LIQUIDITY());
        assertGt(remainingTokens, 0);
        assertEq(uint8(status), uint8(LearningMEMECore.TokenStatus.PENDING_GRADUATION));
        assertEq(uint8(token.transferMode()), uint8(LearningMEMEToken.TransferMode.RESTRICTED));

        vm.prank(buyer);
        vm.expectRevert(LearningMEMECore.TokenNotTrading.selector);
        core.buy{value: 0.1 ether}(address(token), 0, block.timestamp + 5 minutes);
    }

    function testGraduationDistributesFeesAndLocksLiquidity() public {
        _moveToPendingGraduation();

        (,,, uint256 remainingTokens, uint256 collectedBNB) = core.bondingCurve(address(token));
        uint256 nativePlatformFee = collectedBNB * core.graduationPlatformFeeRate() / 10_000;
        uint256 nativeCreatorFee = collectedBNB * core.graduationCreatorFeeRate() / 10_000;
        uint256 nativeLiquidity = collectedBNB - nativePlatformFee - nativeCreatorFee;
        uint256 tokenPlatformFee = remainingTokens * core.graduationPlatformFeeRate() / 10_000;
        uint256 tokenCreatorFee = remainingTokens * core.graduationCreatorFeeRate() / 10_000;
        uint256 tokenLiquidity = remainingTokens - tokenPlatformFee - tokenCreatorFee;
        uint256 graduateNativeBefore = graduateReceiver.balance;
        uint256 creatorNativeBefore = creator.balance;

        vm.prank(admin);
        core.graduateToken(address(token));

        (,,, LearningMEMECore.TokenStatus status, address pair) = core.tokenInfo(address(token));
        (,,, uint256 availableAfter, uint256 collectedAfter) = core.bondingCurve(address(token));

        assertEq(uint8(status), uint8(LearningMEMECore.TokenStatus.GRADUATED));
        assertEq(pair, router.pairFor(address(token)));
        assertEq(token.dexPair(), pair);
        assertEq(uint8(token.transferMode()), uint8(LearningMEMEToken.TransferMode.NORMAL));
        assertEq(token.balanceOf(pair), tokenLiquidity);
        assertEq(pair.balance, nativeLiquidity);
        assertGt(LearningLiquidityPool(payable(pair)).balanceOf(core.DEAD_ADDRESS()), 0);
        assertEq(graduateReceiver.balance, graduateNativeBefore + nativePlatformFee);
        assertEq(token.balanceOf(graduateReceiver), tokenPlatformFee);
        assertEq(creator.balance, creatorNativeBefore + nativeCreatorFee);
        assertEq(token.balanceOf(creator), tokenCreatorFee);
        assertEq(availableAfter, 0);
        assertEq(collectedAfter, 0);
        assertEq(address(core).balance, 0);

        vm.prank(buyer);
        token.transfer(user, 1 ether);
        assertEq(token.balanceOf(user), 1 ether);
    }

    function testOnlyDeployerCanGraduate() public {
        _moveToPendingGraduation();

        vm.prank(user);
        vm.expectRevert();
        core.graduateToken(address(token));
    }

    function testCannotGraduateWhileTokenIsStillTrading() public {
        vm.prank(admin);
        vm.expectRevert(LearningMEMECore.InvalidGraduationStatus.selector);
        core.graduateToken(address(token));
    }

    function _moveToPendingGraduation() private {
        (
            uint256 virtualBNBReserve,
            uint256 virtualTokenReserve,
            uint256 k,
            uint256 availableTokens,
            uint256 collectedBNB
        ) = core.bondingCurve(address(token));
        ILearningMEMEHelper.BondingCurveParams memory curve = ILearningMEMEHelper.BondingCurveParams({
            virtualBNBReserve: virtualBNBReserve,
            virtualTokenReserve: virtualTokenReserve,
            k: k,
            availableTokens: availableTokens,
            collectedBNB: collectedBNB
        });

        uint256 desiredTokens = availableTokens - 5 ether;
        uint256 requiredNetBNB = helper.calculateRequiredBNB(desiredTokens, curve);
        uint256 payment = _ceilDiv(requiredNetBNB * 10_000, 10_000 - core.tradingFeeRate()) + 2;

        vm.prank(buyer);
        core.buy{value: payment}(address(token), desiredTokens, block.timestamp + 5 minutes);
    }

    function _createToken() private returns (address tokenAddress) {
        LearningMEMECore.CreateTokenParams memory params = LearningMEMECore.CreateTokenParams({
            name: "Graduating Meme",
            symbol: "GRAD",
            totalSupply: 1_000 ether,
            saleAmount: 100 ether,
            virtualBNBReserve: 10 ether,
            virtualTokenReserve: 1_000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("step-06-request"),
            nonce: 6,
            initialBuyPercentage: 0,
            vestingAllocations: new LearningMEMECore.VestingAllocation[](0)
        });
        bytes memory data = abi.encode(params);
        bytes32 digest = keccak256(abi.encodePacked(data, core.chainId(), address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIVATE_KEY, digest);

        tokenAddress = core.createToken{value: core.creationFee()}(data, abi.encodePacked(r, s, v));
    }

    function _ceilDiv(uint256 numerator, uint256 denominator) private pure returns (uint256) {
        return numerator == 0 ? 0 : (numerator - 1) / denominator + 1;
    }
}
