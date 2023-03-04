// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "../utils/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../libraries/Conversions.sol";
import "../libraries/SaferERC20.sol";
import "./CoreLogic.sol";
import "./SwapHelper.sol";
import "./ProvidedHelper.sol";
import "./ConversionHelper.sol";
import "./ETHWithdrawer.sol";
import "hardhat/console.sol";

contract UniversalSwap is IUniversalSwap, OwnableUpgradeable {
    using Address for address;
    using UintArray for uint256[];
    using AddressArray for address[];
    using SaferERC20 for IERC20;
    using Conversions for Conversion[];
    using SwapFinder for SwapPoint;

    event Trade(address receiver, uint inputUsdValue, address[] tokens, address[] managers, uint256[] amountsAndIds);

    address public networkToken;
    address public stableToken;
    address[] public swappers;
    address[] public poolInteractors;
    address[] public nftPoolInteractors;
    address public oracle;
    ProvidedHelper public providedHelper;
    ConversionHelper public conversionHelper; 
    SwapHelper public swapHelper;
    address public coreLogic;
    uint public devFee;
    address public treasury;
    address payable public ethWithdrawer;

    function initialize(
        address[] memory _poolInteractors,
        address[] memory _nftPoolInteractors,
        address _networkToken,
        address _stableToken,
        address[] memory _swappers,
        address _oracle
    ) public initializer {
        poolInteractors = _poolInteractors;
        nftPoolInteractors = _nftPoolInteractors;
        swappers = _swappers;
        networkToken = _networkToken;
        stableToken = _stableToken;
        oracle = _oracle;
        devFee = 100;
        treasury = msg.sender;
        ethWithdrawer = payable(address(new ETHWithdrawer()));
        __Ownable_init();
    }

    ///-------------Public view functions-------------

    function getSwappers() external view returns (address[] memory) {
        return swappers;
    }

    function getPoolInteractors() external view returns (address[] memory) {
        return poolInteractors;
    }

    function getNFTPoolInteractors() external view returns (address[] memory) {
        return nftPoolInteractors;
    }

    /// @inheritdoc IUniversalSwap
    function isSimpleToken(address token) public view returns (bool) {
        if (token == networkToken || token == address(0)) return true;
        if (getProtocol(token)!=address(0)) return false;
        for (uint256 i = 0; i < swappers.length; i++) {
            if (ISwapper(swappers[i]).checkSwappable(token)) {
                return true;
            }
        }
        return false;
    }

    /// @inheritdoc IUniversalSwap
    function getProtocol(address token) public view returns (address) {
        if (token == networkToken || token == address(0)) return address(0);
        for (uint256 x = 0; x < poolInteractors.length; x++) {
            if (IPoolInteractor(poolInteractors[x]).testSupported(token)) return poolInteractors[x];
        }
        for (uint256 i = 0; i < nftPoolInteractors.length; i++) {
            if (INFTPoolInteractor(nftPoolInteractors[i]).testSupported(token)) return nftPoolInteractors[i];
        }
        return address(0);
    }

    /// @inheritdoc IUniversalSwap
    function getTokenValues(
        address[] memory tokens,
        uint256[] memory tokenAmounts
    ) public view returns (uint256[] memory values, uint256 total) {
        values = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            values[i] = (IOracle(oracle).getPrice(tokens[i], networkToken) * tokenAmounts[i]) / uint256(10) ** ERC20(tokens[i]).decimals();
            total += values[i];
        }
    }

    /// @inheritdoc IUniversalSwap
    function estimateValue(Provided memory assets, address inTermsOf) public view returns (uint256) {
        (address[] memory tokens, uint256[] memory amounts) = providedHelper.simplifyWithoutWrite(assets);
        (, uint256 value) = getTokenValues(tokens, amounts);
        value = (IOracle(oracle).getPrice(networkToken, inTermsOf==address(0)?networkToken:inTermsOf) * value) / uint256(10) ** ERC20(networkToken).decimals();
        return value;
    }

    /// @inheritdoc IUniversalSwap
    function isSupported(address token) public view returns (bool) {
        if (isSimpleToken(token)) return true;
        if (getProtocol(token) != address(0)) return true;
        return false;
    }

    /// @inheritdoc IUniversalSwap
    function estimateValueERC20(address token, uint256 amount, address inTermsOf) public view returns (uint256) {
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = token;
        amounts[0] = amount;
        Provided memory asset = Provided(tokens, amounts, new Asset[](0));
        return estimateValue(asset, inTermsOf);
    }

    /// @inheritdoc IUniversalSwap
    function estimateValueERC721(Asset memory nft, address inTermsOf) public view returns (uint256) {
        Asset[] memory assets = new Asset[](1);
        assets[0] = nft;
        return estimateValue(Provided(new address[](0), new uint256[](0), assets), inTermsOf);
    }

    /// @inheritdoc IUniversalSwap
    function getUnderlying(Provided memory provided) external view returns (address[] memory, uint256[] memory) {
        return providedHelper.simplifyWithoutWrite(provided);
    }

    ///-------------Pre-swap calculations-------------
    /// @inheritdoc IUniversalSwap
    function getAmountsOut(
        Provided memory provided,
        Desired memory desired
    )
        public
        view
        returns (
            uint256[] memory amounts,
            SwapPoint[] memory swaps,
            Conversion[] memory conversions,
            uint256[] memory expectedUSDValues
        )
    {
        for (uint256 i = 0; i < provided.tokens.length; i++) {
            if (provided.tokens[i] == address(0)) {
                provided.tokens[i] = networkToken;
            }
        }
        (provided.tokens, provided.amounts) = providedHelper.simplifyWithoutWrite(provided);
        provided.nfts = new Asset[](0);
        for (uint i = 0; i<provided.tokens.length; i++) {
            provided.amounts[i]-=provided.amounts[i]*devFee/100000;
        }
        (swaps, conversions) = preSwapCalculateSwaps(provided, desired);
        (amounts, expectedUSDValues) = swapHelper.getAmountsOut(provided, desired, swaps, conversions);
    }

    /// @inheritdoc IUniversalSwap
    function getAmountsOutWithSwaps(
        Provided memory provided,
        Desired memory desired,
        SwapPoint[] memory swaps,
        Conversion[] memory conversions
    ) external view returns (uint[] memory amounts, uint[] memory expectedUSDValues) {
        for (uint256 i = 0; i < provided.tokens.length; i++) {
            if (provided.tokens[i] == address(0)) {
                provided.tokens[i] = networkToken;
            }
        }
        (provided.tokens, provided.amounts) = providedHelper.simplifyWithoutWrite(provided);
        provided.nfts = new Asset[](0);
        for (uint i = 0; i<provided.tokens.length; i++) {
            provided.amounts[i]-=provided.amounts[i]*devFee/100000;
        }
        (amounts, expectedUSDValues) = swapHelper.getAmountsOut(provided, desired, swaps, conversions);
    }

    /// @inheritdoc IUniversalSwap
    function preSwapCalculateUnderlying(
        Provided memory provided,
        Desired memory desired
    )
        public
        view
        returns (
            address[] memory,
            uint256[] memory,
            uint256[] memory,
            Conversion[] memory,
            address[] memory,
            uint256[] memory
        )
    {
        uint256 totalValue;
        uint256[] memory inputTokenValues;
        (inputTokenValues, totalValue) = getTokenValues(provided.tokens, provided.amounts);
        Conversion[] memory conversions = conversionHelper.prepareConversions(
            desired.outputERC20s,
            desired.outputERC721s,
            desired.ratios,
            totalValue
        );
        (address[] memory conversionUnderlying, uint256[] memory conversionUnderlyingValues) = conversions
            .getUnderlying();
        (conversionUnderlying, conversionUnderlyingValues) = conversionUnderlying.shrink(conversionUnderlyingValues);
        conversions = conversions.normalizeRatios();
        return (
            provided.tokens,
            provided.amounts,
            inputTokenValues,
            conversions,
            conversionUnderlying,
            conversionUnderlyingValues
        );
    }

    /// @inheritdoc IUniversalSwap
    function preSwapCalculateSwaps(
        Provided memory provided,
        Desired memory desired
    ) public view returns (SwapPoint[] memory swaps, Conversion[] memory conversions) {
        uint256[] memory inputTokenValues;
        address[] memory conversionUnderlying;
        uint256[] memory conversionUnderlyingValues;
        (
            provided.tokens,
            provided.amounts,
            inputTokenValues,
            conversions,
            conversionUnderlying,
            conversionUnderlyingValues
        ) = preSwapCalculateUnderlying(provided, desired);
        swaps = swapHelper.findMultipleSwaps(
            provided.tokens,
            provided.amounts,
            inputTokenValues,
            conversionUnderlying,
            conversionUnderlyingValues
        );
        return (swaps, conversions);
    }

    ///-------------Core logic-------------
    /// @inheritdoc IUniversalSwap
    function swapAfterTransfer(
        Provided memory provided,
        SwapPoint[] memory swaps,
        Conversion[] memory conversions,
        Desired memory desired,
        address receiver
    ) external payable returns (uint256[] memory) {
        uint usdValue = estimateValue(provided, stableToken);
        uint addressZeroIndex = provided.tokens.findFirst(address(0));
        if (addressZeroIndex != provided.tokens.length) {
            provided.tokens = provided.tokens.remove(addressZeroIndex);
            provided.amounts = provided.amounts.remove(addressZeroIndex);
        }
        bytes memory data = coreLogic.functionDelegateCall(abi.encodeWithSelector(
            CoreLogic(coreLogic).breakAssets.selector, provided.tokens, provided.amounts, provided.nfts
        ));
        (provided.tokens, provided.amounts) = abi.decode(data, (address[], uint[]));
        provided.nfts = new Asset[](0);
        data = coreLogic.functionDelegateCall(abi.encodeWithSelector(
            CoreLogic(coreLogic).swap.selector, provided, swaps, conversions, desired, receiver
        ));
        uint[] memory amountsAndIds = abi.decode(data, (uint[]));
        address[] memory managers = new address[](desired.outputERC721s.length);
        for (uint256 i = 0; i < managers.length; i++) {
            managers[i] = desired.outputERC721s[i].manager;
        }
        emit Trade(msg.sender, usdValue, desired.outputERC20s, managers, amountsAndIds);
        return amountsAndIds;
    }

    /// @inheritdoc IUniversalSwap
    function swap(
        Provided memory provided,
        SwapPoint[] memory swaps,
        Conversion[] memory conversions,
        Desired memory desired,
        address receiver
    ) external payable returns (uint256[] memory) {
        uint usdValue = estimateValue(provided, stableToken);
        uint addressZeroIndex = provided.tokens.findFirst(address(0));
        if (addressZeroIndex != provided.tokens.length) {
            provided.tokens = provided.tokens.remove(addressZeroIndex);
            provided.amounts = provided.amounts.remove(addressZeroIndex);
        }
        bytes memory data = coreLogic.functionDelegateCall(abi.encodeWithSelector(
            CoreLogic(coreLogic).collectAndBreak.selector, provided.tokens, provided.amounts, provided.nfts
        ));
        (provided.tokens, provided.amounts) = abi.decode(data, (address[], uint[]));
        provided.nfts = new Asset[](0);
        data = coreLogic.functionDelegateCall(abi.encodeWithSelector(
            CoreLogic(coreLogic).swap.selector, provided, swaps, conversions, desired, receiver
        ));
        uint[] memory amountsAndIds = abi.decode(data, (uint[]));
        address[] memory managers = new address[](desired.outputERC721s.length);
        for (uint256 i = 0; i < managers.length; i++) {
            managers[i] = desired.outputERC721s[i].manager;
        }
        emit Trade(msg.sender, usdValue, desired.outputERC20s, managers, amountsAndIds);
        return amountsAndIds;
    }

    receive() external payable {}

    ///-------------Permissioned functions-------------
    /// @inheritdoc IUniversalSwap
    function setSwappers(address[] calldata _swappers) external onlyOwner {
        swappers = _swappers;
    }

    /// @inheritdoc IUniversalSwap
    function setOracle(address _oracle) external onlyOwner {
        oracle = _oracle;
    }

    /// @inheritdoc IUniversalSwap
    function setPoolInteractors(address[] calldata _poolInteractors) external onlyOwner {
        poolInteractors = _poolInteractors;
    }

    /// @inheritdoc IUniversalSwap
    function setHelpers(
        address _coreLogic,
        address _providedHelper,
        address _conversionHelper,
        address _swapHelper
    ) external onlyOwner {
        coreLogic = _coreLogic;
        providedHelper = ProvidedHelper(_providedHelper);
        conversionHelper = ConversionHelper(_conversionHelper);
        swapHelper = SwapHelper(_swapHelper);
    }

    /// @inheritdoc IUniversalSwap
    function setNFTPoolInteractors(address[] calldata _nftPoolInteractors) external onlyOwner {
        nftPoolInteractors = _nftPoolInteractors;
    }

    /// @inheritdoc IUniversalSwap
    function setDevFee(uint _fee) external onlyOwner {
        devFee = _fee;
    }

    /// @inheritdoc IUniversalSwap
    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }
}
