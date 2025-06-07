// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TokenPresale.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockToken is ERC20 {
    constructor() ERC20("Test Token", "TEST") {
        _mint(msg.sender, 1000000 * 10**18); // 1M tokens
    }
}

contract TokenPresaleTest is Test {
    TokenPresale public presale;
    MockToken public token;
    
    address public owner = address(0x1);
    address public buyer1 = address(0x2);
    address public buyer2 = address(0x3);
    address public buyer3 = address(0x4);
    
    uint256 public constant RATE = 1000; // 1000 tokens per ETH
    uint256 public constant SOFT_CAP = 5 ether;
    uint256 public constant HARD_CAP = 10 ether;
    uint256 public constant MIN_BUY = 0.1 ether;
    uint256 public constant MAX_BUY = 2 ether;
    
    uint256 public startTime;
    uint256 public endTime;
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy mock token
        token = new MockToken();
        
        // Set up presale times
        startTime = block.timestamp + 1 hours;
        endTime = startTime + 7 days;
        
        // Deploy presale contract
        presale = new TokenPresale(
            address(token),
            RATE,
            SOFT_CAP,
            HARD_CAP,
            MIN_BUY,
            MAX_BUY,
            startTime,
            endTime,
            owner
        );
        
        vm.stopPrank();
        
        // Give buyers some ETH
        vm.deal(buyer1, 10 ether);
        vm.deal(buyer2, 10 ether);
        vm.deal(buyer3, 10 ether);
    }
    
    // === Constructor Tests ===
    
    function testConstructorSetsCorrectValues() public {
        assertEq(address(presale.token()), address(token));
        assertEq(presale.rate(), RATE);
        assertEq(presale.softCap(), SOFT_CAP);
        assertEq(presale.hardCap(), HARD_CAP);
        assertEq(presale.minBuy(), MIN_BUY);
        assertEq(presale.maxBuy(), MAX_BUY);
        assertEq(presale.startTime(), startTime);
        assertEq(presale.endTime(), endTime);
        assertEq(presale.owner(), owner);
    }
    
    function testConstructorRevertsWithZeroTokenAddress() public {
        vm.expectRevert("Token address required");
        new TokenPresale(
            address(0),
            RATE,
            SOFT_CAP,
            HARD_CAP,
            MIN_BUY,
            MAX_BUY,
            startTime,
            endTime,
            owner
        );
    }
    
    function testConstructorRevertsWithInvalidTimeWindow() public {
        vm.expectRevert("Invalid time window");
        new TokenPresale(
            address(token),
            RATE,
            SOFT_CAP,
            HARD_CAP,
            MIN_BUY,
            MAX_BUY,
            endTime, // start time after end time
            startTime,
            owner
        );
    }
    
    // === Buy Tokens Tests ===
    
    function testBuyTokensSuccess() public {
        // Warp to presale start
        vm.warp(startTime);
        
        uint256 ethAmount = 1 ether;
        uint256 expectedTokens = ethAmount * RATE;
        
        vm.prank(buyer1);
        presale.buyTokens{value: ethAmount}();
        
        assertEq(presale.contributions(buyer1), ethAmount);
        assertEq(presale.claimableTokens(buyer1), expectedTokens);
        assertEq(presale.totalRaised(), ethAmount);
        assertEq(presale.totalSold(), expectedTokens);
    }
    
    function testBuyTokensEmitsEvent() public {
        vm.warp(startTime);
        
        uint256 ethAmount = 1 ether;
        uint256 expectedTokens = ethAmount * RATE;
        
        vm.expectEmit(true, false, false, true);
        emit TokenPresale.TokensPurchased(buyer1, ethAmount, expectedTokens);
        
        vm.prank(buyer1);
        presale.buyTokens{value: ethAmount}();
    }
    
    function testBuyTokensRevertsBeforeStart() public {
        vm.expectRevert("Presale not active");
        vm.prank(buyer1);
        presale.buyTokens{value: 1 ether}();
    }
    
    function testBuyTokensRevertsAfterEnd() public {
        vm.warp(endTime + 1);
        
        vm.expectRevert("Presale not active");
        vm.prank(buyer1);
        presale.buyTokens{value: 1 ether}();
    }
    
    function testBuyTokensRevertsWithTooLowAmount() public {
        vm.warp(startTime);
        
        vm.expectRevert("Amount out of range");
        vm.prank(buyer1);
        presale.buyTokens{value: MIN_BUY - 1}();
    }
    
    function testBuyTokensRevertsWithTooHighAmount() public {
        vm.warp(startTime);
        
        vm.expectRevert("Amount out of range");
        vm.prank(buyer1);
        presale.buyTokens{value: MAX_BUY + 1}();
    }
    
    function testBuyTokensRevertsWhenMaxAllocationExceeded() public {
        vm.warp(startTime);
        
        // First purchase
        vm.prank(buyer1);
        presale.buyTokens{value: 1.5 ether}();
        
        // Second purchase would exceed max
        vm.expectRevert("Max allocation exceeded");
        vm.prank(buyer1);
        presale.buyTokens{value: 0.6 ether}();
    }
    
    function testBuyTokensRevertsWhenHardCapReached() public {
        vm.warp(startTime);
        
        // Fill up to hard cap
        vm.prank(buyer1);
        presale.buyTokens{value: 2 ether}();
        vm.prank(buyer2);
        presale.buyTokens{value: 2 ether}();
        vm.prank(buyer3);
        presale.buyTokens{value: 2 ether}();
        
        // This should fill exactly to hard cap
        address buyer4 = address(0x5);
        vm.deal(buyer4, 10 ether);
        vm.prank(buyer4);
        presale.buyTokens{value: 2 ether}();
        
        address buyer5 = address(0x6);
        vm.deal(buyer5, 10 ether);
        vm.prank(buyer5);
        presale.buyTokens{value: 2 ether}();
        
        // Now hard cap should be reached
        address buyer6 = address(0x7);
        vm.deal(buyer6, 10 ether);
        vm.expectRevert("Hard cap reached");
        vm.prank(buyer6);
        presale.buyTokens{value: 0.1 ether}();
    }
    
    // === Whitelist Tests ===
    
    function testWhitelistFunctionality() public {
        vm.startPrank(owner);
        presale.enableWhitelist(true);
        
        address[] memory addresses = new address[](2);
        addresses[0] = buyer1;
        addresses[1] = buyer2;
        presale.addToWhitelist(addresses);
        vm.stopPrank();
        
        vm.warp(startTime);
        
        // Whitelisted user can buy
        vm.prank(buyer1);
        presale.buyTokens{value: 1 ether}();
        
        // Non-whitelisted user cannot buy
        vm.expectRevert("Not whitelisted");
        vm.prank(buyer3);
        presale.buyTokens{value: 1 ether}();
    }
    
    function testDisableWhitelist() public {
        vm.startPrank(owner);
        presale.enableWhitelist(true);
        presale.enableWhitelist(false);
        vm.stopPrank();
        
        vm.warp(startTime);
        
        // Any user can buy when whitelist is disabled
        vm.prank(buyer3);
        presale.buyTokens{value: 1 ether}();
    }
    
    // === Token Deposit Tests ===
    
    function testDepositPresaleTokens() public {
        uint256 depositAmount = 10000 * 10**18;
        
        vm.startPrank(owner);
        token.approve(address(presale), depositAmount);
        presale.depositPresaleTokens(depositAmount);
        vm.stopPrank();
        
        assertEq(presale.tokensDeposited(), depositAmount);
        assertEq(token.balanceOf(address(presale)), depositAmount);
    }
    
    function testDepositPresaleTokensRevertsWithZeroAmount() public {
        vm.expectRevert("Zero amount");
        vm.prank(owner);
        presale.depositPresaleTokens(0);
    }
    
    function testDepositPresaleTokensRevertsWithoutAllowance() public {
        vm.expectRevert("Token transfer failed");
        vm.prank(owner);
        presale.depositPresaleTokens(1000);
    }
    
    function testDepositPresaleTokensOnlyOwner() public {
        vm.expectRevert();
        vm.prank(buyer1);
        presale.depositPresaleTokens(1000);
    }
    
    // === Claim Tokens Tests ===
    
    function testClaimTokensSuccess() public {
        // Setup: buy and deposit tokens
        uint256 ethAmount = 1 ether;
        uint256 expectedTokens = ethAmount * RATE;
        
        vm.warp(startTime);
        vm.prank(buyer1);
        presale.buyTokens{value: ethAmount}();
        
        // Ensure we meet soft cap
        vm.prank(buyer2);
        presale.buyTokens{value: 2 ether}();
        vm.prank(buyer3);
        presale.buyTokens{value: 2.5 ether}();
        
        // Deposit tokens
        vm.startPrank(owner);
        token.approve(address(presale), expectedTokens);
        presale.depositPresaleTokens(expectedTokens);
        vm.stopPrank();
        
        // Warp to after presale end
        vm.warp(endTime + 1);
        
        uint256 balanceBefore = token.balanceOf(buyer1);
        
        vm.prank(buyer1);
        presale.claimTokens();
        
        assertEq(token.balanceOf(buyer1), balanceBefore + expectedTokens);
        assertEq(presale.claimableTokens(buyer1), 0);
    }
    
    function testClaimTokensEmitsEvent() public {
        uint256 ethAmount = 1 ether;
        uint256 expectedTokens = ethAmount * RATE;
        
        // Setup
        vm.warp(startTime);
        vm.prank(buyer1);
        presale.buyTokens{value: ethAmount}();
        
        vm.prank(buyer2);
        presale.buyTokens{value: 5 ether}(); // Meet soft cap
        
        vm.startPrank(owner);
        token.approve(address(presale), expectedTokens);
        presale.depositPresaleTokens(expectedTokens);
        vm.stopPrank();
        
        vm.warp(endTime + 1);
        
        vm.expectEmit(true, false, false, true);
        emit TokenPresale.TokensClaimed(buyer1, expectedTokens);
        
        vm.prank(buyer1);
        presale.claimTokens();
    }
    
    function testClaimTokensRevertsBeforePresaleEnd() public {
        vm.warp(startTime);
        vm.prank(buyer1);
        presale.buyTokens{value: 1 ether}();
        
        vm.expectRevert("Presale not ended");
        vm.prank(buyer1);
        presale.claimTokens();
    }
    
    function testClaimTokensRevertsWhenSoftCapNotMet() public {
        vm.warp(startTime);
        vm.prank(buyer1);
        presale.buyTokens{value: 1 ether}(); // Less than soft cap
        
        vm.warp(endTime + 1);
        
        vm.expectRevert("Soft cap not met");
        vm.prank(buyer1);
        presale.claimTokens();
    }
    
    function testClaimTokensRevertsWithNothingToClaim() public {
        vm.warp(endTime + 1);
        
        vm.expectRevert("Nothing to claim");
        vm.prank(buyer1);
        presale.claimTokens();
    }
    
    function testClaimTokensRevertsWithoutEnoughTokensInContract() public {
        vm.warp(startTime);
        vm.prank(buyer1);
        presale.buyTokens{value: 5 ether}(); // Meet soft cap
        
        vm.warp(endTime + 1);
        
        vm.expectRevert("Not enough tokens in contract");
        vm.prank(buyer1);
        presale.claimTokens();
    }
    
    // === Refund Tests ===
    
    function testRefundSuccess() public {
        vm.warp(startTime);
        vm.prank(buyer1);
        presale.buyTokens{value: 1 ether}(); // Less than soft cap
        
        vm.warp(endTime + 1);
        
        uint256 balanceBefore = buyer1.balance;
        
        vm.prank(buyer1);
        presale.refund();
        
        assertEq(buyer1.balance, balanceBefore + 1 ether);
        assertEq(presale.contributions(buyer1), 0);
    }
    
    function testRefundEmitsEvent() public {
        vm.warp(startTime);
        vm.prank(buyer1);
        presale.buyTokens{value: 1 ether}();
        
        vm.warp(endTime + 1);
        
        vm.expectEmit(true, false, false, true);
        emit TokenPresale.Refunded(buyer1, 1 ether);
        
        vm.prank(buyer1);
        presale.refund();
    }
    
    function testRefundRevertsBeforePresaleEnd() public {
        vm.warp(startTime);
        vm.prank(buyer1);
        presale.buyTokens{value: 1 ether}();
        
        vm.expectRevert("Presale not ended");
        vm.prank(buyer1);
        presale.refund();
    }
    
    function testRefundRevertsWhenSoftCapMet() public {
        vm.warp(startTime);
        vm.prank(buyer1);
        presale.buyTokens{value: 5 ether}(); // Meet soft cap
        
        vm.warp(endTime + 1);
        
        vm.expectRevert("Soft cap met");
        vm.prank(buyer1);
        presale.refund();
    }
    
    function testRefundRevertsWithNothingToRefund() public {
        vm.warp(endTime + 1);
        
        vm.expectRevert("Nothing to refund");
        vm.prank(buyer1);
        presale.refund();
    }
    
    // === Withdraw Funds Tests ===
    
    function testWithdrawFundsSuccess() public {
        vm.warp(startTime);
        vm.prank(buyer1);
        presale.buyTokens{value: 5 ether}(); // Meet soft cap
        
        vm.warp(endTime + 1);
        
        uint256 balanceBefore = owner.balance;
        
        vm.prank(owner);
        presale.withdrawFunds();
        
        assertEq(owner.balance, balanceBefore + 5 ether);
        assertEq(address(presale).balance, 0);
    }
    
    function testWithdrawFundsOnlyOwner() public {
        vm.warp(startTime);
        vm.prank(buyer1);
        presale.buyTokens{value: 5 ether}();
        
        vm.warp(endTime + 1);
        
        vm.expectRevert();
        vm.prank(buyer1);
        presale.withdrawFunds();
    }
    
    function testWithdrawFundsRevertsBeforePresaleEnd() public {
        vm.warp(startTime);
        vm.prank(buyer1);
        presale.buyTokens{value: 5 ether}();
        
        vm.expectRevert("Presale not ended");
        vm.prank(owner);
        presale.withdrawFunds();
    }
    
    function testWithdrawFundsRevertsWhenSoftCapNotMet() public {
        vm.warp(startTime);
        vm.prank(buyer1);
        presale.buyTokens{value: 1 ether}(); // Less than soft cap
        
        vm.warp(endTime + 1);
        
        vm.expectRevert("Soft cap not met");
        vm.prank(owner);
        presale.withdrawFunds();
    }
    
    // === Withdraw Unsold Tokens Tests ===
    
    function testWithdrawUnsoldTokensSuccess() public {
        uint256 depositAmount = 10000 * 10**18;
        uint256 soldAmount = 5000 * 10**18;
        
        // Setup
        vm.warp(startTime);
        vm.prank(buyer1);
        presale.buyTokens{value: 5 ether}(); // 5000 tokens
        
        vm.startPrank(owner);
        token.approve(address(presale), depositAmount);
        presale.depositPresaleTokens(depositAmount);
        vm.stopPrank();
        
        vm.warp(endTime + 1);
        
        uint256 ownerBalanceBefore = token.balanceOf(owner);
        
        vm.prank(owner);
        presale.withdrawUnsoldTokens();
        
        uint256 expectedUnsold = depositAmount - soldAmount;
        assertEq(token.balanceOf(owner), ownerBalanceBefore + expectedUnsold);
        assertTrue(presale.claimedBackUnsold());
    }
    
    function testWithdrawUnsoldTokensOnlyOwner() public {
        vm.warp(endTime + 1);
        
        vm.expectRevert();
        vm.prank(buyer1);
        presale.withdrawUnsoldTokens();
    }
    
    function testWithdrawUnsoldTokensRevertsBeforePresaleEnd() public {
        vm.expectRevert("Presale not ended");
        vm.prank(owner);
        presale.withdrawUnsoldTokens();
    }
    
    function testWithdrawUnsoldTokensRevertsWhenAlreadyWithdrawn() public {
        vm.warp(endTime + 1);
        
        vm.startPrank(owner);
        presale.withdrawUnsoldTokens();
        
        vm.expectRevert("Already withdrawn");
        presale.withdrawUnsoldTokens();
        vm.stopPrank();
    }
    
    // === Emergency Rescue Tests ===
    
    function testRescueERC20Success() public {
        // Deploy a different token
        MockToken otherToken = new MockToken();
        uint256 rescueAmount = 1000 * 10**18;
        
        // Transfer some tokens to the presale contract
        vm.prank(owner);
        otherToken.transfer(address(presale), rescueAmount);
        
        uint256 ownerBalanceBefore = otherToken.balanceOf(owner);
        
        vm.prank(owner);
        presale.rescueERC20(address(otherToken), rescueAmount);
        
        assertEq(otherToken.balanceOf(owner), ownerBalanceBefore + rescueAmount);
    }
    
    function testRescueERC20RevertsWithSaleToken() public {
        vm.expectRevert("Cannot rescue sale token");
        vm.prank(owner);
        presale.rescueERC20(address(token), 1000);
    }
    
    function testRescueERC20OnlyOwner() public {
        MockToken otherToken = new MockToken();
        
        vm.expectRevert();
        vm.prank(buyer1);
        presale.rescueERC20(address(otherToken), 1000);
    }
    
    // === Integration Tests ===
    
    function testFullSuccessfulPresaleFlow() public {
        uint256 depositAmount = 20000 * 10**18;
        
        // 1. Owner deposits tokens
        vm.startPrank(owner);
        token.approve(address(presale), depositAmount);
        presale.depositPresaleTokens(depositAmount);
        vm.stopPrank();
        
        // 2. Presale starts and users buy tokens
        vm.warp(startTime);
        
        vm.prank(buyer1);
        presale.buyTokens{value: 2 ether}(); // 2000 tokens
        
        vm.prank(buyer2);
        presale.buyTokens{value: 1.5 ether}(); // 1500 tokens
        
        vm.prank(buyer3);
        presale.buyTokens{value: 2.5 ether}(); // 2500 tokens
        
        // Total: 6 ETH raised, 6000 tokens sold, soft cap met
        assertEq(presale.totalRaised(), 6 ether);
        assertEq(presale.totalSold(), 6000 ether);
        assertTrue(presale.totalRaised() >= presale.softCap());
        
        // 3. Presale ends
        vm.warp(endTime + 1);
        
        // 4. Users claim tokens
        vm.prank(buyer1);
        presale.claimTokens();
        assertEq(token.balanceOf(buyer1), 2000 ether);
        
        vm.prank(buyer2);
        presale.claimTokens();
        assertEq(token.balanceOf(buyer2), 1500 ether);
        
        vm.prank(buyer3);
        presale.claimTokens();
        assertEq(token.balanceOf(buyer3), 2500 ether);
        
        // 5. Owner withdraws ETH
        uint256 ownerBalanceBefore = owner.balance;
        vm.prank(owner);
        presale.withdrawFunds();
        assertEq(owner.balance, ownerBalanceBefore + 6 ether);
        
        // 6. Owner withdraws unsold tokens
        uint256 ownerTokenBalanceBefore = token.balanceOf(owner);
        vm.prank(owner);
        presale.withdrawUnsoldTokens();
        assertEq(token.balanceOf(owner), ownerTokenBalanceBefore + (depositAmount - 6000 ether));
    }
    
    function testFullFailedPresaleFlow() public {
        // 1. Presale starts but doesn't reach soft cap
        vm.warp(startTime);
        
        vm.prank(buyer1);
        presale.buyTokens{value: 1 ether}(); // 1000 tokens
        
        vm.prank(buyer2);
        presale.buyTokens{value: 2 ether}(); // 2000 tokens
        
        // Total: 3 ETH raised, less than 5 ETH soft cap
        assertEq(presale.totalRaised(), 3 ether);
        assertTrue(presale.totalRaised() < presale.softCap());
        
        // 2. Presale ends
        vm.warp(endTime + 1);
        
        // 3. Users get refunds
        uint256 buyer1BalanceBefore = buyer1.balance;
        uint256 buyer2BalanceBefore = buyer2.balance;
        
        vm.prank(buyer1);
        presale.refund();
        assertEq(buyer1.balance, buyer1BalanceBefore + 1 ether);
        
        vm.prank(buyer2);
        presale.refund();
        assertEq(buyer2.balance, buyer2BalanceBefore + 2 ether);
        
        // 4. Claiming tokens should fail
        vm.expectRevert("Soft cap not met");
        vm.prank(buyer1);
        presale.claimTokens();
        
        // 5. Owner can't withdraw funds
        vm.expectRevert("Soft cap not met");
        vm.prank(owner);
        presale.withdrawFunds();
    }
}