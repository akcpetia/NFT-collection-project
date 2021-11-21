// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "./lib/RoseCurveSVG.sol";
import "./lib/URI.sol";

/**
 * @title RoseCurve NFT Collection smart contract
 
 The Rose Curve NFT Collection is a generative art project based on rhodonea
 (https://en.wikipedia.org/wiki/Rose_%28mathematics%29) or rose curves. They were discovered by an
 Italian mathematician, Guido Grandi in the early 18th century. They form very aesthetically
 pleasing circles, called petals that have been used to create beautiful NFTs such as floral
 mandalas as part of this collection.

 The project is built on top of the open palette (https://www.openpalette.io/) NFT collection which
 is a fantastic project deployed on the Ethereum blockchain. It is a collection of randomized colour
 palettes made of 5 unique colours that anybody can use to create generative art, games, website
 themes and more. The colour of the palettes is used to generate and colour the petals of the Rose
 Curve NFT Collection. Thus, to mint a Rose Curve NFT, you need to own an Open Palette NFT first.
 * @author leovct
 * @dev Compliant with OpenZeppelin's implementation of the ERC721 spec draft
 */
contract RoseCurveNFT is ERC721URIStorage, VRFConsumerBase {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    bytes32 private keyHash;
    uint256 private fee;

    mapping(bytes32 => address) private requestIdToSender;
    mapping(bytes32 => uint256) private requestIdToTokenId;
    mapping(uint256 => uint256) private tokenIdToRandomNumber;

    event RequestedRoseCurveNFT(bytes32 indexed requestId, uint256 indexed tokenId);
    event ReceivedRandomNumber(bytes32 indexed requestId, uint256 indexed tokenId, uint256 randomNumber);
    event CreatedRoseCurveNFT(uint256 indexed tokenId, string tokenURI);

    /**
     * @notice Constructor of the RoseCurveNFT smart contract
     * @param _vrfCoordinator address of the Chainlink VRF Coordinator. This component proves that 
     the generator random number is actually random and not pseudo-random.
     * @param _linkToken LINK token address on the corresponding network (Ethereum, Polygon, BSC, 
     etc). This is the currency used to pay the fees on the Chainlink network.
     * @param _keyHash public key against which randomness is generated
     * @param _fee fee required to fulfill a VRF request (varies by network)
     */
    constructor(address _vrfCoordinator, address _linkToken, bytes32 _keyHash, uint256 _fee)
        ERC721("Rose Curve NFT", "ROSECURVE")
        VRFConsumerBase(_vrfCoordinator, _linkToken)
    {
        keyHash = _keyHash;
        fee = _fee;
    }

    /**
     * @notice Request a random number from Chainlink VRF
     * @return requestId the id of the request submitted to Chainlink VRF
     */
    function startMint() public returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= fee, "Not enough $LINK, fill the contract with faucet");

        // Get the id of the request
        requestId = requestRandomness(keyHash, fee);

        // Link the id of the request to the sender
        requestIdToSender[requestId] = msg.sender;

        // Also link the id of the request to the NFT id
        uint256 tokenId = _tokenIdCounter.current();
        requestIdToTokenId[requestId] = tokenId;
        _tokenIdCounter.increment();

        emit RequestedRoseCurveNFT(requestId, tokenId);
    }

    /**
     * @notice Callback function used by VRF Coordinator to validate and return the generated 
     random number
     * @param _requestId the id of the request submitted to Chainlink VRF
     * @param _randomNumber the random number generated by Chainlink VRF
     */
    function fulfillRandomness(bytes32 _requestId, uint256 _randomNumber) internal override {
        // Mint the NFT
        address owner = requestIdToSender[_requestId];
        uint256 tokenId = requestIdToTokenId[_requestId];
        _safeMint(owner, tokenId);

        // Store the random number
        tokenIdToRandomNumber[tokenId] = _randomNumber;

        emit ReceivedRandomNumber(_requestId, tokenId, _randomNumber);
    }

    /**
     * @notice Mint a Rose Curve NFT
     * @param _tokenId the id of the NFT
     * @dev It uses Chainlink VRF (Verifiable Random Function) to generate the random svg
     */
    function finishMint(uint256 _tokenId, string[5] memory paletteColours) public {
        require(bytes(tokenURI(_tokenId)).length <= 0, "The URI of the token is already set!");
        require(_tokenIdCounter.current() > _tokenId, "The token has not been minted yet!");
        require(tokenIdToRandomNumber[_tokenId] > 0, "Need to wait for Chainlink VRF to respond and generate a random number");

        // Generate the Rose Curve SVG
        RoseCurve memory roseCurve = RoseCurve(1_000, 10_000_000_000_000_000, 20, 2, 60, paletteColours, "#000000");
        uint256 randomNumber = tokenIdToRandomNumber[_tokenId];
        string memory svg = RoseCurveSVG._createRoseCurveSVG(roseCurve, randomNumber);

        // Update the URI of the token with the svg code stored on-chain
        string memory svgURI = URI._svgToImageURI(svg);
        string memory tokenURI = URI._formatTokenURI("Rose Curve NFT",
            "Generative Art project based on rhodonea and the open palette NFTs.", _tokenId, svgURI);
        _setTokenURI(_tokenId, tokenURI);

        emit CreatedRoseCurveNFT(_tokenId, tokenURI);
    }
}
