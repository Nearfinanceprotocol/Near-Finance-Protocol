/**
 *Submitted for verification at BscScan.com on 2022-07-24
*/

/**
 *Submitted for verification at BscScan.com on 2022-06-17
*/

// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.8.0;
import {Context} from "./utils/Context.sol";
import {IBEP20} from "./utils/IBEP20.sol";
import {SafeMath} from "./lib/SafeMath.sol";
import {Ownable} from "./utils/Ownable.sol";
import {IPancakeFactory} from "./utils/IPancakeFactory.sol";
import {IPancakeRouter01} from "./utils/IPancakeRouter01.sol";
import {IPancakeRouter02} from "./utils/IPancakeRouter02.sol";








/// @title Near Finance Protocol
/// @notice this is the ERC20 token that runs the protocol 
contract NearFinanceProtocol is Context, IBEP20, Ownable {
    using SafeMath for uint256;
    IPancakeRouter02 private pancakeV2Router;
    address public pancakeswapPair; //  This would be a NRF / BNB pair
    string private constant _name = "Near Finance Protocol";
    string private constant _symbol = "NRF";
    uint8 private constant _decimals = 18;
    uint256 private constant MAX = ~uint256(0); // MAX is set to type(uint256).max (the maximum digit uint256 can hold)
    uint256 private _tTotal = 1000000 * 10**18;
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 public _tFeeTotal;
    uint256 public _NearFinanceProtocolBurned;
    bool public _cooldownEnabled = true;
    bool public tradeAllowed = false;
    bool private liquidityAdded = false;
    bool private inSwap = false;
    bool public swapEnabled = false;
    bool public feeEnabled = false;
    bool private limitTX = false;
    uint256 private _maxTxAmount = _tTotal;
    uint256 private _reflection = 0;
    uint256 private _contractFee = 5;
    uint256 private _NearFinanceProtocolBurn = 0;
    uint256 private _maxBuyAmount;
    uint256 private buyLimitEnd;
    address payable private _development;
    address payable private _boost;

    address public targetToken = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // this is the address of wrapped BNB



    address public boostFund = 0x01dcA19048Ca3A10C46da7a7423b24112BEF08c8;


    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping (address => User) private cooldown;
    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private _isBlacklisted;

    struct User {
        uint256 buy;
        uint256 sell;
        bool exists;
    }

    event CooldownEnabledUpdated(bool _cooldown);
    event MaxBuyAmountUpdated(uint _maxBuyAmount);
    event MaxTxAmountUpdated(uint256 _maxTxAmount);

    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    /// @param addr1, addr2, addr3 this addresses would be excluded from fees and can transfers even when trade is not yet activated 
    constructor(address payable addr1, address payable addr2, address addr3) {
        _development = addr1;
        _boost = addr2;
        _rOwned[_msgSender()] = _rTotal;
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[_development] = true;
        _isExcludedFromFee[_boost] = true;
        _isExcludedFromFee[addr3] = true;

        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    /// @return the name of the token this would be useful for wallets 
    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return tokenFromReflection(_rOwned[account]);
    }

    /// @dev setting the address that would be the other pair along side with NRF token (the dualt is wbnb)
    function setTargetAddress(address target_adr) external onlyOwner {
        targetToken = target_adr;
    }

    /// @dev any address passed to the function would be excluded from fee
    function setExcludedFromFee(address _address,bool _bool) external onlyOwner {
        address addr3 = _address;
        _isExcludedFromFee[addr3] = _bool;
    }


    /// @notice any address blaclisted using this funtion can cannot perform transaction (admin can set an unset address in the function)
    function setAddressIsBlackListed(address _address, bool _bool) external onlyOwner {
        _isBlacklisted[_address] = _bool;
    }

    /// @notice this function would return true if the user address is blacklisted 
    function viewIsBlackListed(address _address) public view returns(bool) {
        return _isBlacklisted[_address];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender,_msgSender(),_allowances[sender][_msgSender()].sub(amount,"BEP20: transfer amount exceeds allowance"));
        return true;
    }

    /// @notice this write function sets a state varible which would enable fee on every transfer
    function setFeeEnabled(bool enable) external onlyOwner {
        feeEnabled = enable;
    }

    
    /// @dev setting this to true ensures that the amount set in a transfer call if not greater than totalSupply if liquidity has not been added or 100,000 if liquidity has been added
    function setLimitTx(bool enable) external onlyOwner {
        limitTX = enable;
    }

    /// @dev when admin calls the function, the trading on Pancake Swap can now be excequted, their a 5 mins grace, should be admin change his mind, iquidity  must the added before the function is called 
    function enableTrading(bool enable) external onlyOwner {
        require(liquidityAdded);
        tradeAllowed = enable;
        //  first 5 minutes after launch.
        buyLimitEnd = block.timestamp + (300 seconds);
    }

    /// @dev 
    function addLiquidity() external onlyOwner() {
        IPancakeRouter02 _pancakeV2Router = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        pancakeV2Router = _pancakeV2Router;
        _approve(address(this), address(pancakeV2Router), _tTotal);
        pancakeswapPair = IPancakeFactory(_pancakeV2Router.factory()).createPair(address(this), _pancakeV2Router.WETH());
        pancakeV2Router.addLiquidityETH{value: address(this).balance}(address(this),balanceOf(address(this)),0,0,owner(),block.timestamp);
        swapEnabled = true;
        liquidityAdded = true;
        feeEnabled = true;
        limitTX = true;
        _maxTxAmount = 100000 * 10**18;
        _maxBuyAmount = 10000 * 10**18; //1% buy cap
        IBEP20(pancakeswapPair).approve(address(pancakeV2Router),type(uint256).max); // I dont understand want is going on here => the pair contract does not have the function approve 
    }

    /// @notice this function would swap NFR token for BNB (all the NRF token on the contract balance) 
    function manualSwapTokensForEth() external onlyOwner() {
        uint256 contractBalance = balanceOf(address(this));
        swapTokensForEth(contractBalance);
    }

    function manualDistributeETH() external onlyOwner() {
        uint256 contractETHBalance = address(this).balance;
        distributeETH(contractETHBalance);
    }

    function manualSwapEthForTargetToken(uint amount) external onlyOwner() {
        swapETHfortargetToken(amount);
    }

    function setMaxTxPercent(uint256 maxTxPercent) external onlyOwner() {
        require(maxTxPercent > 0, "Amount must be greater than 0");
        _maxTxAmount = _tTotal.mul(maxTxPercent).div(10**2);
        emit MaxTxAmountUpdated(_maxTxAmount);
    }

    function setCooldownEnabled(bool onoff) external onlyOwner() {
        _cooldownEnabled = onoff;
        emit CooldownEnabledUpdated(_cooldownEnabled);
    }

    function timeToBuy(address buyer) public view returns (uint) {
        return block.timestamp - cooldown[buyer].buy;
    }

    function timeToSell(address buyer) public view returns (uint) {
        return block.timestamp - cooldown[buyer].sell;
    }

    function amountInPool() public view returns (uint) {
        return balanceOf(pancakeswapPair);
    }

    function tokenFromReflection(uint256 rAmount) private view returns (uint256) {
        require(rAmount <= _rTotal,"Amount must be less than total reflections");
        uint256 currentRate = _getRate();
        return rAmount.div(currentRate);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "BEP20: approve from the zero address");
        require(spender != address(0), "BEP20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "BEP20: transfer from the zero address");
        require(to != address(0), "BEP20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        if (from != owner() && to != owner() && !_isExcludedFromFee[from] && !_isExcludedFromFee[to]) {
            require(tradeAllowed);
            require(!_isBlacklisted[from] && !_isBlacklisted[to]);
            if(_cooldownEnabled) {
                if(!cooldown[msg.sender].exists) {
                    cooldown[msg.sender] = User(0,0,true);
                }
            }

            if (from == pancakeswapPair && to != address(pancakeV2Router)) {
                if (limitTX) {
                    require(amount <= _maxTxAmount);
                }
                if(_cooldownEnabled) {
                    if(buyLimitEnd > block.timestamp) {
                        require(amount <= _maxBuyAmount);
                        require(cooldown[to].buy < block.timestamp, "Your buy cooldown has not expired.");
                        //  30sec BUY cooldown
                        cooldown[to].buy = block.timestamp + (30 seconds);
                    }
                    // 30 sec cooldown to SELL after a BUY to ban front-runner bots
                    cooldown[to].sell = block.timestamp + (30 seconds);
                }
                uint contractETHBalance = address(this).balance;
                if (contractETHBalance > 0) {
                    swapETHfortargetToken(address(this).balance);
                }
            }


            if(to == address(pancakeswapPair) || to == address(pancakeV2Router) ) {
                
                if(_cooldownEnabled) {
                    require(cooldown[from].sell < block.timestamp, "Your sell cooldown has not expired.");
                }
                uint contractTokenBalance = balanceOf(address(this));
                if (!inSwap && from != pancakeswapPair && swapEnabled) {
                    if (limitTX) {
                    require(amount <= balanceOf(pancakeswapPair).mul(3).div(100) && amount <= _maxTxAmount);
                    }
                    uint initialETHBalance = address(this).balance;
                    swapTokensForEth(contractTokenBalance);
                    uint newETHBalance = address(this).balance;
                    uint ethToDistribute = newETHBalance.sub(initialETHBalance);
                    if (ethToDistribute > 0) {
                        distributeETH(ethToDistribute);
                    }
                }
            }
        }
        bool takeFee = true;
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to] || !feeEnabled) {
            takeFee = false;
        }
        _tokenTransfer(from, to, amount, takeFee);
        restoreAllFee;
    }

    function removeAllFee() private {
        if (_reflection == 0 && _contractFee == 0 && _NearFinanceProtocolBurn == 0) return;
        _reflection = 0;
        _contractFee = 0;
        _NearFinanceProtocolBurn = 0;
    }

    function restoreAllFee() private {
        _reflection = 0;
        _contractFee = 5;
        _NearFinanceProtocolBurn = 0;
    }



    function _tokenTransfer(address sender, address recipient, uint256 amount, bool takeFee) private {
        if (!takeFee) removeAllFee();
        _transferStandard(sender, recipient, amount);
        if (!takeFee) restoreAllFee();
    }

    function _transferStandard(address sender, address recipient, uint256 amount) private {
        (uint256 tAmount, uint256 tBurn) = _NearFinanceProtocolEthBurn(amount);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tTeam) = _getValues(tAmount, tBurn);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeTeam(tTeam);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _takeTeam(uint256 tTeam) private {
        uint256 currentRate = _getRate();
        uint256 rTeam = tTeam.mul(currentRate);
        _rOwned[address(this)] = _rOwned[address(this)].add(rTeam);
    }

    function _NearFinanceProtocolEthBurn(uint amount) private returns (uint, uint) {
        uint orgAmount = amount;
        uint256 currentRate = _getRate();
        uint256 tBurn = amount.mul(_NearFinanceProtocolBurn).div(100);
        uint256 rBurn = tBurn.mul(currentRate);
        _tTotal = _tTotal.sub(tBurn);
        _rTotal = _rTotal.sub(rBurn);
        _NearFinanceProtocolBurned = _NearFinanceProtocolBurned.add(tBurn);
        return (orgAmount, tBurn);
    }

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function _getValues(uint256 tAmount, uint256 tBurn) private view returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        (uint256 tTransferAmount, uint256 tFee, uint256 tTeam) = _getTValues(tAmount, _reflection, _contractFee, tBurn);
        uint256 currentRate = _getRate();
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tFee, tTeam, currentRate);
        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee, tTeam);
    }

    function _getTValues(uint256 tAmount, uint256 taxFee, uint256 teamFee, uint256 tBurn) private pure returns (uint256, uint256, uint256) {
        uint256 tFee = tAmount.mul(taxFee).div(100);
        uint256 tTeam = tAmount.mul(teamFee).div(100);
        uint256 tTransferAmount = tAmount.sub(tFee).sub(tTeam).sub(tBurn);
        return (tTransferAmount, tFee, tTeam);
    }

    function _getRValues(uint256 tAmount, uint256 tFee, uint256 tTeam, uint256 currentRate) private pure returns (uint256, uint256, uint256) {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rTeam = tTeam.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee).sub(rTeam);
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function swapTokensForEth(uint256 tokenAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = pancakeV2Router.WETH();
        _approve(address(this), address(pancakeV2Router), tokenAmount);
        pancakeV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount, 0, path, address(this), block.timestamp);
    }

     function swapETHfortargetToken(uint ethAmount) private {
        address[] memory path = new address[](2);
        path[0] = pancakeV2Router.WETH();
        path[1] = address(targetToken);

        _approve(address(this), address(pancakeV2Router), ethAmount);
        pancakeV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethAmount}(ethAmount,path,address(boostFund),block.timestamp);
    }

    function distributeETH(uint256 amount) private {
        _development.transfer(amount.div(10));
        _boost.transfer(amount.div(2));
    }

    receive() external payable {}
}
