// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Auction is IERC721Receiver, ReentrancyGuard {
    //////////////
    /// ERRORS ///
    //////////////
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
    enum Status {
        NOT_STARTED, // 0
        START, // 1
        END // 2
    }

    ///////////////
    /// STRUCTS ///
    ///////////////
    struct WorkOfArt {
        IERC721 nft;
        uint256 tokenId;
    }

    struct AuctionInformation {
        Status status;
        uint256 endAt;
        uint256 highestBid;
        address highestBidder;
        WorkOfArt workOfArt;
    }

    ///////////////
    /// STORAGE ///
    ///////////////
    address private immutable i_seller;
    uint256 private immutable i_duration;
    uint256 private immutable i_reservePrice;

    AuctionInformation private s_auction;

    mapping(address => uint256) private s_pendingReturns;

    event AuctionStart(address indexed seller, uint256 indexed tokenId);
    event BidPlaced(address indexed bidder, uint256 indexed amount);
    event Withdraw(address indexed bidder, uint256 indexed amount);
    event AuctionEnded(address indexed winner, uint256 indexed tokenId);

    ////////////////
    /// MODIFIER ///
    ////////////////
    modifier onlySeller() {
        _onlySeller();
        _;
    }

    constructor(uint256 _duration, uint256 _reservePrice) {
        i_seller = msg.sender;
        i_duration = _duration;
        i_reservePrice = _reservePrice;
    }

    receive() external payable {
        bid();
    }

    //////////////////////////
    /// EXTERNAL FUNCTIONS ///
    //////////////////////////
    function start(address _nft, uint256 _tokenId) external onlySeller {
        if (_nft == address(0)) {
            revert Auction__NftAddressCanNotBeZero();
        }

        if (_tokenId == 0) {
            revert Auction__TokenIdCanNotBeZero();
        }

        if (s_auction.status == Status.START && block.timestamp < s_auction.endAt) {
            revert Auction__AuctionAlreadyStarted();
        }

        IERC721 nft = IERC721(_nft);
        
        // build workOfArt struct
        WorkOfArt memory workOfArt = WorkOfArt({nft: nft, tokenId: _tokenId});

        // build auctionInformation struct
        s_auction = AuctionInformation({
            status: Status.START,
            endAt: block.timestamp + i_duration,
            highestBid: 0,
            highestBidder: address(0),
            workOfArt: workOfArt
        });

        // transfer NFT to contract
        nft.safeTransferFrom(msg.sender, address(this), _tokenId);

        emit AuctionStart(msg.sender, _tokenId);
    }

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

        if (s_auction.highestBidder != address(0)) {
            s_pendingReturns[s_auction.highestBidder] += s_auction.highestBid;
        }

        s_auction.highestBidder = msg.sender;
        s_auction.highestBid = msg.value;

        emit BidPlaced(msg.sender, msg.value);
    }

    function withdraw() external nonReentrant {
        if (s_pendingReturns[msg.sender] == 0) {
            revert Auction__NothingToWithdraw();
        }

        uint256 currentAmount = s_pendingReturns[msg.sender];
        s_pendingReturns[msg.sender] = 0;

        (bool success,) = payable(msg.sender).call{value: currentAmount}("");
        if (!success) {
            revert Auction__WithdrawFailed();
        }

        emit Withdraw(msg.sender, currentAmount);
    }

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

        s_auction.highestBid = 0;
        s_auction.highestBidder = address(0);

        WorkOfArt memory workOfArt = s_auction.workOfArt;

        if (highestBid >= i_reservePrice) {
            // transfer nft to winner
            workOfArt.nft.safeTransferFrom(address(this), highestBidder, workOfArt.tokenId);

            // send amount to seller
            (bool success,) = payable(msg.sender).call{value: highestBid}("");
            if (!success) {
                revert Auction__TransferToSellerFailed();
            }
        } else {
            workOfArt.nft.safeTransferFrom(address(this), i_seller, workOfArt.tokenId);

            if (highestBidder != address(0)) {
                s_pendingReturns[highestBidder] += highestBid;
            }
        }

        emit AuctionEnded(highestBidder, workOfArt.tokenId);
    }

    function onERC721Received(
        address,
        /*operator*/
        address,
        /*from*/
        uint256,
        /*tokenId*/
        bytes calldata /*data*/
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
    function _onlySeller() internal view {
        if (msg.sender != i_seller) {
            revert Auction__YouAreNotSeller();
        }
    }

    ////////////////////////
    /// GETTER FUNCTIONS ///
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

    function getAuctionStatus() public view returns (uint256) {
        // 0 -> NotStarted
        // 1 -> Start
        // 2 -> End
        return uint256(s_auction.status);
    }
}
