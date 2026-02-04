// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Auction
/// @notice English auction for an ERC721 NFT with reserve price and safe refunds.
/// @dev
/// - Uses the pull-payment pattern (`pendingReturns`) to avoid refund-based DoS attacks.
/// - Protects ETH transfers with `ReentrancyGuard`.
/// - The contract temporarily escrows the NFT during the auction.
contract Auction is IERC721Receiver, ReentrancyGuard {
    //////////////
    /// ERRORS ///
    //////////////
    /// @notice Custom errors are cheaper than revert strings and easier to test.
    error Auction__NftAddressCanNotBeZero();
    error Auction__TokenIdCanNotBeZero();
    error Auction__AuctionNotStarted();
    error Auction__WithdrawFailed();
    error Auction__TransferToSellerFailed();
    error Auction__YouAreNotSeller();
    error Auction__TimeDoNotEndYet();
    error Auction__AuctionTimeEnded();
    error Auction__AuctionAlreadyStarted();
    error Auction__BidNeedBeHigherThanCurrentHighestBid();
    error Auction__NothingToWithdraw();

    /////////////
    /// ENUMS ///
    /////////////
    /// @notice Minimal auction lifecycle states.
    enum Status {
        NOT_STARTED, // 0
        START,       // 1
        END          // 2
    }

    ///////////////
    /// STRUCTS ///
    ///////////////
    /// @notice Identifies the NFT being auctioned.
    struct WorkOfArt {
        IERC721 nft;
        uint256 tokenId;
    }

    /// @notice Complete auction state stored on-chain.
    struct AuctionInformation {
        Status status;            // Current auction status
        uint256 endAt;            // Timestamp when the auction ends
        uint256 highestBid;       // Current highest bid
        address highestBidder;    // Current highest bidder
        WorkOfArt workOfArt;      // NFT being auctioned
    }

    ///////////////
    /// STORAGE ///
    ///////////////
    /// @dev Immutable configuration set at deployment (gas efficient and non-upgradable).
    address private immutable i_seller;
    uint256 private immutable i_duration;
    uint256 private immutable i_reservePrice;

    /// @dev State of the current auction (single auction at a time).
    AuctionInformation private s_auction;

    /// @dev Tracks refundable ETH balances for bidders (pull-payment pattern).
    mapping(address => uint256) private s_pendingReturns;

    /////////////
    /// EVENTS ///
    /////////////
    /// @notice Emitted when an auction starts.
    event AuctionStart(address indexed seller, uint256 indexed tokenId);

    /// @notice Emitted when a valid bid is placed.
    event BidPlaced(address indexed bidder, uint256 indexed amount);

    /// @notice Emitted when a bidder withdraws refundable ETH.
    event Withdraw(address indexed bidder, uint256 indexed amount);

    /// @notice Emitted when the auction ends.
    event AuctionEnded(address indexed winner, uint256 indexed tokenId);

    ////////////////
    /// MODIFIER ///
    ////////////////
    /// @dev Restricts execution to the seller only.
    modifier onlySeller() {
        _onlySeller();
        _;
    }

    /// @param _duration Auction duration in seconds.
    /// @param _reservePrice Minimum price required for a successful sale.
    constructor(uint256 _duration, uint256 _reservePrice) {
        i_seller = msg.sender;
        i_duration = _duration;
        i_reservePrice = _reservePrice;
    }

    /// @notice Allows bidding by sending ETH directly to the contract.
    /// @dev Triggered when `msg.data` is empty.
    receive() external payable {
        bid();
    }

    //////////////////////////
    /// EXTERNAL FUNCTIONS ///
    //////////////////////////

    /// @notice Starts a new auction and transfers the NFT into escrow.
    /// @dev
    /// - Callable only by the seller.
    /// - Requires prior approval of the NFT to this contract.
    function start(address _nft, uint256 _tokenId) external onlySeller {
        if (_nft == address(0)) {
            revert Auction__NftAddressCanNotBeZero();
        }

        /// @dev Note: tokenId == 0 may be valid in some ERC721s,
        /// but it is disallowed here by design.
        if (_tokenId == 0) {
            revert Auction__TokenIdCanNotBeZero();
        }

        /// @dev Prevents restarting an already active auction.
        if (s_auction.status == Status.START && block.timestamp < s_auction.endAt) {
            revert Auction__AuctionAlreadyStarted();
        }

        IERC721 nft = IERC721(_nft);

        // Build the NFT struct
        WorkOfArt memory workOfArt = WorkOfArt({nft: nft, tokenId: _tokenId});

        // Initialize auction state
        s_auction = AuctionInformation({
            status: Status.START,
            endAt: block.timestamp + i_duration,
            highestBid: 0,
            highestBidder: address(0),
            workOfArt: workOfArt
        });

        // Transfer NFT into escrow
        nft.safeTransferFrom(msg.sender, address(this), _tokenId);

        emit AuctionStart(msg.sender, _tokenId);
    }

    /// @notice Places a bid using ETH.
    /// @dev
    /// - The bid must exceed the current highest bid.
    /// - Previous highest bidder is credited in `pendingReturns`.
    /// - Refunds are not sent inline to prevent DoS.
    function bid() public payable {
        if (s_auction.status != Status.START) {
            revert Auction__AuctionNotStarted();
        }

        if (msg.value <= s_auction.highestBid) {
            revert Auction__BidNeedBeHigherThanCurrentHighestBid();
        }

        if (block.timestamp >= s_auction.endAt) {
            revert Auction__AuctionTimeEnded();
        }

        // Store refundable amount for the previous highest bidder
        if (s_auction.highestBidder != address(0)) {
            s_pendingReturns[s_auction.highestBidder] += s_auction.highestBid;
        }

        // Update auction leader
        s_auction.highestBidder = msg.sender;
        s_auction.highestBid = msg.value;

        emit BidPlaced(msg.sender, msg.value);
    }

    /// @notice Withdraws refundable ETH from previous bids.
    /// @dev
    /// - Uses Checks-Effects-Interactions pattern.
    /// - Protected by nonReentrant.
    function withdraw() external nonReentrant {
        if (s_pendingReturns[msg.sender] == 0) {
            revert Auction__NothingToWithdraw();
        }

        uint256 currentAmount = s_pendingReturns[msg.sender];

        // Effects
        s_pendingReturns[msg.sender] = 0;

        // Interaction
        (bool success,) = payable(msg.sender).call{value: currentAmount}("");
        if (!success) {
            revert Auction__WithdrawFailed();
        }

        emit Withdraw(msg.sender, currentAmount);
    }

    /// @notice Ends the auction and settles NFT and ETH transfers.
    /// @dev
    /// - Callable only by the seller.
    /// - Can only be executed after `endAt`.
    /// - If reserve price is not met, the NFT is returned to the seller.
    function end() external onlySeller nonReentrant {
        if (s_auction.status != Status.START) {
            revert Auction__AuctionNotStarted();
        }

        if (block.timestamp < s_auction.endAt) {
            revert Auction__TimeDoNotEndYet();
        }

        s_auction.status = Status.END;

        uint256 highestBid = s_auction.highestBid;
        address highestBidder = s_auction.highestBidder;
        WorkOfArt memory workOfArt = s_auction.workOfArt;

        // Clear bid state
        s_auction.highestBid = 0;
        s_auction.highestBidder = address(0);

        if (highestBid >= i_reservePrice) {
            // Successful auction: transfer NFT to winner
            workOfArt.nft.safeTransferFrom(address(this), highestBidder, workOfArt.tokenId);

            // Transfer ETH to seller
            (bool success,) = payable(msg.sender).call{value: highestBid}("");
            if (!success) {
                revert Auction__TransferToSellerFailed();
            }
        } else {
            // Reserve not met: return NFT to seller
            workOfArt.nft.safeTransferFrom(address(this), i_seller, workOfArt.tokenId);

            // Allow highest bidder to withdraw their ETH
            if (highestBidder != address(0)) {
                s_pendingReturns[highestBidder] += highestBid;
            }
        }

        emit AuctionEnded(highestBidder, workOfArt.tokenId);
    }

    /// @notice Required ERC721 receiver hook.
    /// @dev Always returns the expected selector to accept safe transfers.
    function onERC721Received(
        address, /* operator */
        address, /* from */
        uint256, /* tokenId */
        bytes calldata /* data */
    )
        external
        pure
        override
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }

    //////////////////////////
    /// INTERNAL FUNCTIONS ///
    //////////////////////////

    /// @dev Ensures the caller is the seller.
    function _onlySeller() internal view {
        if (msg.sender != i_seller) {
            revert Auction__YouAreNotSeller();
        }
    }

    ////////////////////////
    /// VIEW FUNCTIONS ///
    ////////////////////////

    function getSeller() external view returns (address) {
        return i_seller;
    }

    function getDuration() external view returns (uint256) {
        return i_duration;
    }

    function getReservePrice() external view returns (uint256) {
        return i_reservePrice;
    }

    function getPendingReturnsByUser(address _user) external view returns (uint256) {
        return s_pendingReturns[_user];
    }

    function getAuction() public view returns (AuctionInformation memory) {
        return s_auction;
    }

    /// @notice Returns the auction status as a uint for frontend compatibility.
    function getAuctionStatus() public view returns (uint256) {
        // 0 -> NOT_STARTED
        // 1 -> START
        // 2 -> END
        return uint256(s_auction.status);
    }
}
