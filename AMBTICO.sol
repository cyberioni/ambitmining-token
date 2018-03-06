pragma solidity ^0.4.18;

import './AMBToken.sol';

contract AMBTICO is AMBToken {
    uint256 internal constant ONE_TOKEN           = 10 ** uint256(decimals);//just for convenience
    uint256 internal constant MILLION             = 1000000;                //just for convenience

    uint256 internal constant BOUNTY_QUANTITY     = 3 * MILLION;
    uint256 internal constant RESERV_QUANTITY     = 7 * MILLION;

    uint256 internal constant TOKEN_MAX_SUPPLY    = 100 * MILLION   * ONE_TOKEN;
    uint256 internal constant BOUNTY_TOKENS       = BOUNTY_QUANTITY * ONE_TOKEN;
    uint256 internal constant RESERV_TOKENS       = RESERV_QUANTITY * ONE_TOKEN;
    uint256 internal constant MIN_SOLD_TOKENS     = 200             * ONE_TOKEN;
    uint256 internal constant SOFTCAP             = BOUNTY_TOKENS + RESERV_TOKENS + 6 * MILLION * ONE_TOKEN;

    uint256 internal constant REFUND_PERIOD       = 60 days;
    uint256 internal constant KYC_REVIEW_PERIOD   = 60 days;

    address internal owner;
    address internal bountyManager;
    address internal dividendManager;
    address internal tokenTransferManager;
    address internal priceManager;

    enum ContractMode {Initial, TokenSale, UnderSoftCap, DividendDistribution, Destroyed}
    ContractMode public mode = ContractMode.Initial;

    uint256 public icoFinishTime = 0;
    uint256 public tokenSold = 0;
    uint256 public etherCollected = 0;

    uint8   public currentSection = 0;
    uint[4] public saleSectionDiscounts = [ uint8(20),10,5];
    uint[4] public saleSectionPrice     = [ uint256(484848484848485),545454545454546,575757575757576,606060606060606];//price: 0.40 0.45 0.475 0.50 cent | ETH/USD initial rate: 825
    uint[4] public saleSectionCount     = [ uint256(20 * MILLION),20 * MILLION,20 * MILLION,40 * MILLION - (BOUNTY_QUANTITY+RESERV_QUANTITY)];
    uint[4] public saleSectionInvest    = [ uint256(saleSectionCount[0] * saleSectionPrice[0]),
                                                    saleSectionCount[1] * saleSectionPrice[1],
                                                    saleSectionCount[2] * saleSectionPrice[2],
                                                    saleSectionCount[3] * saleSectionPrice[3]];
    uint256 public buyBackPriceWei = 0 ether;

    event OwnershipTransferred          (address previousOwner, address newOwner);
    event BountyManagerAssigned         (address previousBountyManager, address newBountyManager);
    event DividendManagerAssigned       (address previousDividendManager, address newDividendManager);
    event TokenTransferManagerAssigned  (address previousTokenTransferManager, address newTokenTransferManager);
    event PriceManagerAssigned          (address previousPriceManager, address newPriceManager);
    event ModeChanged                   (ContractMode  newMode, uint256 tokenBalance);
    event DividendDeclared              (uint32 indexed dividendID, uint256 profitPerToken);
    event DividendClaimed               (address indexed investor, uint256 amount);
    event BuyBack                       (address indexed requestor);
    event Refund                        (address indexed investor,uint256 amount);
    event Handbrake                     (ContractMode current_mode, bool functioning);
    event FundsAdded                    (address owner,uint256 amount);
    event FundsWithdrawal               (address owner,uint256 amount);
    event BountyTransfered              (address recipient, uint256 amount);
    event PriceChanged                  (uint256 newPrice);

    modifier grantOwner() {
        require(msg.sender == owner);
        _;
    }

    modifier grantBountyManager() {
        require(msg.sender == bountyManager);
        _;
    }

    modifier grantDividendManager() {
        require(msg.sender == dividendManager);
        _;
    }

    modifier grantTokenTransferManager() {
        require(msg.sender == tokenTransferManager);
        _;
    }

    modifier grantPriceManager() {
        require(msg.sender == priceManager);
        _;
    }

    function AMBTICO() public {
        owner = msg.sender;
    }

    function setTokenPrice(uint256 new_wei_price) public grantPriceManager {
        uint8 len = uint8(saleSectionPrice.length)-1;
        for (uint8 i=0; i<=len; i++) {
            uint256 prdsc = 100 - saleSectionDiscounts[i];
            saleSectionPrice[i]  = (prdsc * new_wei_price ) / uint256(100);
            saleSectionInvest[i] = saleSectionPrice[i] * saleSectionCount[i];
        }
        PriceChanged(new_wei_price);
    }

    function startICO() public grantOwner {
        require(contractIsWorking);
        require(mode == ContractMode.Initial);
        require(bountyManager != 0x0);

        totalSupply = TOKEN_MAX_SUPPLY;

        investors[this].tokenBalance            = TOKEN_MAX_SUPPLY-(BOUNTY_TOKENS+RESERV_TOKENS);
        investors[bountyManager].tokenBalance   = BOUNTY_TOKENS;
        investors[owner].tokenBalance           = RESERV_TOKENS;

        tokenSold = investors[bountyManager].tokenBalance + investors[owner].tokenBalance;//???
        dividends.push(0);
        mode = ContractMode.TokenSale;
        ModeChanged(mode, investors[this].tokenBalance);
    }

    function getCurrentTokenPrice() public view returns(uint256) {
        require(currentSection < saleSectionCount.length);
        return saleSectionPrice[currentSection];
    }

    function () public payable {
        invest();
    }
    function invest() public payable {
        require(contractIsWorking);
        require(currentSection < saleSectionCount.length);
        require(mode == ContractMode.TokenSale);
        require(msg.sender != bountyManager);

        uint wei_value = msg.value;
        uint _tokens = 0;

        while (wei_value > 0 && (currentSection < saleSectionCount.length)) {
            if (saleSectionInvest[currentSection] >= wei_value) {
                _tokens += (ONE_TOKEN * wei_value)/saleSectionPrice[currentSection];
                saleSectionInvest[currentSection] -= wei_value;
                wei_value =0;
            } else {
                _tokens += (ONE_TOKEN * saleSectionInvest[currentSection])/saleSectionPrice[currentSection];
                wei_value -=saleSectionInvest[currentSection];
                saleSectionInvest[currentSection] = 0;
            }
            if (saleSectionInvest[currentSection] <= 0) currentSection++;
        }

        require(_tokens >= MIN_SOLD_TOKENS);

        assert(_transfer(this, msg.sender, _tokens));

        profits[msg.sender][1] = InvestorProfitData({
            start_balance:  investors[msg.sender].tokenBalance,
            end_balance:    investors[msg.sender].tokenBalance,
            status:         ProfitStatus.StartFixed
            });

        investors[msg.sender].icoInvest += (msg.value - wei_value);

        tokenSold += _tokens;
        etherCollected += (msg.value - wei_value);

        if (saleSectionInvest[saleSectionInvest.length-1] == 0 ) {
            _finishICO();
        }

        if (wei_value > 0) {
            msg.sender.transfer(wei_value);
        }
    }

    function _finishICO() internal {
        require(contractIsWorking);
        require(mode == ContractMode.TokenSale);

        if (tokenSold >= SOFTCAP) {
            mode = ContractMode.DividendDistribution;
        } else {
            mode = ContractMode.UnderSoftCap;
        }

        icoFinishTime = now;
        investors[this].tokenBalance = 0;
        totalSupply = tokenSold;
        ModeChanged(mode,investors[this].tokenBalance);
    }

    function finishICO() public grantOwner  {
        _finishICO();
    }

    function getInvestedAmount(address investor) public view returns(uint256) {
        return investors[investor].icoInvest;
    }

    function activateAddress(address investor, bool status) public grantTokenTransferManager {
        require(contractIsWorking);
        require(mode == ContractMode.DividendDistribution);
        require((now - icoFinishTime) < KYC_REVIEW_PERIOD);
        investors[investor].activated = status;
    }

    function isAddressActivated(address investor) public view returns (bool) {
        return investors[investor].activated;
    }

    /*******
            Dividend Declaration Section
    *********/
    function declareDividend(uint256 profit_per_token) public grantDividendManager {
        dividendCandidate = profit_per_token;
    }

    function confirmDividend(uint256 profit_per_token) public grantOwner {
        require(contractIsWorking);
        require(dividendCandidate == profit_per_token);
        require(mode == ContractMode.DividendDistribution);

        dividends.push(dividendCandidate);
        DividendDeclared(uint32(dividends.length),dividendCandidate);
        dividendCandidate = 0;
    }

    function claimDividend() public {
        require(contractIsWorking);
        require(mode == ContractMode.DividendDistribution);
        require(investors[msg.sender].activated);

        InvestorProfitData storage current_profit;

        uint256 price_per_token;
        (current_profit, price_per_token) = fixDividendBalances(msg.sender,true);

        uint256 investorProfitWei = (current_profit.start_balance < current_profit.end_balance ? current_profit.start_balance : current_profit.end_balance )/ONE_TOKEN * price_per_token;

        current_profit.status = ProfitStatus.Claimed;
        DividendClaimed(msg.sender,investorProfitWei);

        msg.sender.transfer(investorProfitWei);
    }

    function getDividendInfo() public view returns(uint256) {
        return dividends[dividends.length-1];
    }

    /*******
                BuyBack
    ********/
    function setBuyBackPrice(uint256 token_buyback_price) public grantOwner {
        require(mode == ContractMode.DividendDistribution);
        buyBackPriceWei = token_buyback_price;
    }

    function buyback() public {
        require(contractIsWorking);
        require(mode == ContractMode.DividendDistribution);
        require(buyBackPriceWei > 0);

        uint256 token_amount = investors[msg.sender].tokenBalance;
        uint256 ether_amount = calcTokenToWei(token_amount);

        require(this.balance > ether_amount);

        if (transfer(this,token_amount)){
            BuyBack(msg.sender);
            msg.sender.transfer(ether_amount);
        }
    }

    /********
                Under SoftCap Section
    *********/
    function refund() public {
        require(contractIsWorking);
        require(mode == ContractMode.UnderSoftCap);
        require(investors[msg.sender].tokenBalance >0);
        require(investors[msg.sender].icoInvest>0);

        require (this.balance > investors[msg.sender].icoInvest);

        if (_transfer(msg.sender, this, investors[msg.sender].tokenBalance)){
            Refund(msg.sender,investors[msg.sender].icoInvest);
            msg.sender.transfer(investors[msg.sender].icoInvest);
        }
    }

    function destroyContract() public grantOwner {
        require(mode == ContractMode.UnderSoftCap);
        require((now - icoFinishTime)> REFUND_PERIOD);
        selfdestruct(owner);
    }
    /********
                Permission related
    ********/

    function transferOwnership(address new_owner) public grantOwner {
        require(contractIsWorking);
        require(new_owner != address(0));
        OwnershipTransferred(owner, new_owner);
        owner = new_owner;
    }

    function setBountyManager(address new_bounty_manager) public grantOwner {
        require(investors[new_bounty_manager].tokenBalance ==0);
        if (mode == ContractMode.Initial) {
            BountyManagerAssigned(bountyManager, new_bounty_manager);
            bountyManager = new_bounty_manager;
        } else if (mode == ContractMode.TokenSale) {
            BountyManagerAssigned(bountyManager, new_bounty_manager);
            address old_bounty_manager = bountyManager;
            bountyManager              = new_bounty_manager;
            require(_transfer(old_bounty_manager,new_bounty_manager,investors[old_bounty_manager].tokenBalance));
        } else {
            revert();
        }
    }

    function setDividendManager(address new_dividend_manager) public grantOwner {
        DividendManagerAssigned(dividendManager, new_dividend_manager);
        dividendManager = new_dividend_manager;
    }

    function setTokenTransferManager(address new_token_transfer_manager) public grantOwner {
        TokenTransferManagerAssigned(tokenTransferManager, new_token_transfer_manager);
        tokenTransferManager = new_token_transfer_manager;
    }

    function setPriceManager(address new_price_manager) public grantOwner {
        PriceManagerAssigned(priceManager, new_price_manager);
        priceManager = new_price_manager;
    }
    /********
                Security and funds section
    ********/
    function manualTransfer(address _to, uint256 value_tokens) public grantTokenTransferManager {
        require(contractIsWorking);
        require(mode == ContractMode.TokenSale || mode == ContractMode.DividendDistribution);
        assert(_transfer(this,_to,value_tokens));
    }

    function transferBounty(address _to, uint256 _amount) public grantBountyManager {
        require(contractIsWorking);
        require(mode == ContractMode.DividendDistribution);
        if (_transfer(bountyManager, _to, _amount)) {
            BountyTransfered(_to, _amount);
        }
    }

    function withdrawFunds(uint wei_value) grantOwner external {
        require(mode != ContractMode.UnderSoftCap);
        require(this.balance >= wei_value);

        FundsWithdrawal(msg.sender, wei_value);
        msg.sender.transfer(wei_value);
    }

    function addFunds() public payable grantOwner {
        require(contractIsWorking);
        FundsAdded(msg.sender,msg.value);
    }

    function pauseContract() public grantOwner {
        require(contractIsWorking);
        contractIsWorking = false;
        Handbrake(mode,contractIsWorking);
    }

    function restoreContract() public grantOwner {
        require(!contractIsWorking);
        contractIsWorking = true;
        Handbrake(mode,contractIsWorking);
    }

    /********
                Helper functions
    ********/
    function calcTokenToWei(uint256 token_amount) internal view returns (uint256) {
        return (buyBackPriceWei * token_amount) / ONE_TOKEN;
    }
}
