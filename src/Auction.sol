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
        START,
        END
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

    AuctionInformation private auction;

    mapping(address => uint256) private pendingReturns;

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

        if(auction.status == Status.START && block.timestamp < auction.endAt) {
            revert Auction__AuctionAlreadyStarted();
        }

        // transfer NFT to contract
        IERC721 nft = IERC721(_nft);
        nft.safeTransferFrom(msg.sender, address(this), _tokenId);

        // build workOfArt struct
        WorkOfArt memory workOfArt = WorkOfArt({nft: nft, tokenId: _tokenId});

        // build auctionInformation struct
        auction = AuctionInformation({
            status: Status.START,
            endAt: block.timestamp + i_duration,
            highestBid: 0,
            highestBidder: address(0),
            workOfArt: workOfArt
        });

        emit AuctionStart(msg.sender, _tokenId);
    }

    function bid() external payable {
        if (auction.status != Status.START) {
            revert Auction__AuctionNotStarted();
        }

        if (msg.value <= auction.highestBid) {
            revert Auction__BidNeedBeHigherThanCurrentHighestBid();
        }

        if (block.timestamp >= auction.endAt) {
            revert Auction__AuctionTimeEnded();
        }

        if (auction.highestBidder != address(0)) {
            pendingReturns[auction.highestBidder] += auction.highestBid;
        }

        auction.highestBidder = msg.sender;
        auction.highestBid = msg.value;

        emit BidPlaced(msg.sender, msg.value);
    }

    function withdraw() external nonReentrant {
        if (pendingReturns[msg.sender] == 0) {
            revert Auction__NothingToWithdraw();
        }

        uint256 currentAmount = pendingReturns[msg.sender];
        pendingReturns[msg.sender] = 0;

        (bool success,) = payable(msg.sender).call{value: currentAmount}("");
        if (!success) {
            revert Auction__WithdrawFailed();
        }

        emit Withdraw(msg.sender, currentAmount);
    }

    function end() external onlySeller nonReentrant {
        if (auction.status != Status.START) {
            revert Auction__AuctionNotStarted();
        }

        if (block.timestamp < auction.endAt) {
            revert Auction__TimeDoNotEndYet();
        }

        auction.status = Status.END;

        uint256 highestBid = auction.highestBid;
        address highestBidder = auction.highestBidder;

        auction.highestBid = 0;
        auction.highestBidder = address(0);

        WorkOfArt memory workOfArt = auction.workOfArt;

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

            if(highestBidder != address(0)) {
                pendingReturns[highestBidder] += highestBid;
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
        return pendingReturns[_user];
    }
}
