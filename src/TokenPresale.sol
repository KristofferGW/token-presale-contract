// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
using SafeERC20 for IERC20;

contract TokenPresale is Ownable {
    IERC20 public token;

    uint256 public rate; // tokens per ETH
    uint256 public softCap;
    uint256 public hardCap;
    uint256 public minBuy;
    uint256 public maxBuy;

    uint256 public startTime;
    uint256 public endTime;
    uint256 public totalRaised;
    uint256 public totalSold;
    uint256 public tokensDeposited;

    address public initialOwner;

    bool public whitelistEnabled = false;
    mapping(address => bool) public whitelist;

    mapping(address => uint256) public contributions;
    mapping(address => uint256) public claimableTokens;

    bool public claimedBackUnsold = false;

    event TokensPurchased(
        address indexed buyer,
        uint256 ethAmount,
        uint256 tokens
    );
    event TokensClaimed(address indexed user, uint256 amount);
    event Refunded(address indexed user, uint256 amount);

    constructor(
        address _token,
        uint256 _rate,
        uint256 _softCap,
        uint256 _hardCap,
        uint256 _minBuy,
        uint256 _maxBuy,
        uint256 _startTime,
        uint256 _endTime,
        address _initialOwner
    ) Ownable(_initialOwner) {
        require(_token != address(0), "Token address required");
        require(_startTime < _endTime, "Invalid time window");

        token = IERC20(_token);
        rate = _rate;
        softCap = _softCap;
        hardCap = _hardCap;
        minBuy = _minBuy;
        maxBuy = _maxBuy;
        startTime = _startTime;
        endTime = _endTime;
    }

    // Buy tokens during sale
    function buyTokens() external payable {
        require(
            block.timestamp >= startTime && block.timestamp <= endTime,
            "Presale not active"
        );
        require(
            msg.value >= minBuy && msg.value <= maxBuy,
            "Amount out of range"
        );
        require(
            contributions[msg.sender] + msg.value <= maxBuy,
            "Max allocation exceeded"
        );

        if (whitelistEnabled) {
            require(whitelist[msg.sender], "Not whitelisted");
        }

        uint256 tokensToBuy = msg.value * rate;
        require(totalRaised + msg.value <= hardCap, "Hard cap reached");

        contributions[msg.sender] += msg.value;
        claimableTokens[msg.sender] += tokensToBuy;
        totalRaised += msg.value;
        totalSold += tokensToBuy;

        emit TokensPurchased(msg.sender, msg.value, tokensToBuy);
    }

    // Fund contract with tokens before claim
    function depositPresaleTokens(uint256 amount) external onlyOwner {
        require(amount > 0, "Zero amount");
        bool success = token.transferFrom(msg.sender, address(this), amount);
        require(success, "Token transfer failed");
        tokensDeposited += amount;
    }

    // Claim purchased tokens
    function claimTokens() external {
        require(block.timestamp > endTime, "Presale not ended");
        require(totalRaised >= softCap, "Soft cap not met");
        uint256 amount = claimableTokens[msg.sender];
        require(amount > 0, "Nothing to claim");
        require(
            token.balanceOf(address(this)) >= amount,
            "Not enough tokens in contract"
        );

        claimableTokens[msg.sender] = 0;
        token.safeTransfer(msg.sender, amount);

        emit TokensClaimed(msg.sender, amount);
    }

    // Refund if presale fails
    function refund() external {
        require(block.timestamp > endTime, "Presale not ended");
        require(totalRaised < softCap, "Soft cap met");
        uint256 amount = contributions[msg.sender];
        require(amount > 0, "Nothing to refund");

        contributions[msg.sender] = 0;
        payable(msg.sender).transfer(amount);

        emit Refunded(msg.sender, amount);
    }

    // Owner withdraws ETH if sale is successful
    function withdrawFunds() external onlyOwner {
        require(block.timestamp > endTime, "Presale not ended");
        require(totalRaised >= softCap, "Soft cap not met");

        payable(owner()).transfer(address(this).balance);
    }

    // Withdraw unsold tokens (once only)
    function withdrawUnsoldTokens() external onlyOwner {
        require(block.timestamp > endTime, "Presale not ended");
        require(!claimedBackUnsold, "Already withdrawn");
        claimedBackUnsold = true;

        // Calculate how many tokens should remain for claims
        uint256 tokensNeededForClaims = totalSold;
        uint256 currentBalance = token.balanceOf(address(this));

        if (currentBalance > tokensNeededForClaims) {
            uint256 unsold = currentBalance - tokensNeededForClaims;
            token.safeTransfer(owner(), unsold);
        }
    }

    // --- Whitelist Functions ---

    function enableWhitelist(bool _enabled) external onlyOwner {
        whitelistEnabled = _enabled;
    }

    function addToWhitelist(address[] calldata addresses) external onlyOwner {
        for (uint i = 0; i < addresses.length; i++) {
            whitelist[addresses[i]] = true;
        }
    }

    // Emergency token rescue (non-sale tokens only)
    function rescueERC20(address _token, uint256 amount) external onlyOwner {
        require(_token != address(token), "Cannot rescue sale token");
        IERC20(_token).transfer(owner(), amount);
    }
}
