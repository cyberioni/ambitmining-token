pragma solidity ^0.4.18;

import './math/SafeMath.sol';

contract AMBToken {
    using SafeMath for uint256;

    string  public constant name     = "Ambit token";
    string  public constant symbol   = "AMBT";
    uint8   public constant decimals = 18;
    uint256 public totalSupply;

    bool internal contractIsWorking = true;

    struct Investor {
        uint256 tokenBalance;
        uint256 icoInvest;
        bool    activated;
    }
    mapping(address => Investor) internal investors;
    mapping(address => mapping (address => uint256)) internal allowed;

    /*
            Dividend's Structures
    */
    uint256   internal dividendCandidate = 0;
    uint256[] internal dividends;

    enum ProfitStatus {Initial, StartFixed, EndFixed, Claimed}
    struct InvestorProfitData {
        uint256      start_balance;
        uint256      end_balance;
        ProfitStatus status;
    }

    mapping(address => mapping(uint32 => InvestorProfitData)) internal profits;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function balanceOf(address _owner) public view returns (uint256 balance) {
        return investors[_owner].tokenBalance;
    }

    function allowance(address _owner, address _spender) public view returns (uint256) {
        return allowed[_owner][_spender];
    }

    function _approve(address _spender, uint256 _value) internal returns (bool) {
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }

    function approve(address _spender, uint256 _value) public returns (bool) {
        require(investors[msg.sender].activated && contractIsWorking);
        return _approve(_spender, _value);
    }

    function _transfer(address _from, address _to, uint256 _value) internal returns (bool) {
        require(_to != address(0));
        require(_value <= investors[_from].tokenBalance);

        fixDividendBalances(_to,false);

        investors[_from].tokenBalance = investors[_from].tokenBalance.sub(_value);
        investors[_to].tokenBalance = investors[_to].tokenBalance.add(_value);
        Transfer(_from, _to, _value);
        return true;
    }

    function transfer(address _to, uint256 _value) public returns (bool) {
        require(investors[msg.sender].activated && contractIsWorking);
        fixDividendBalances(msg.sender,false);
        return _transfer( msg.sender, _to,  _value);
    }

    function transferFrom(address _from, address _to, uint256 _value) public returns (bool) {
        require(investors[msg.sender].activated && investors[_from].activated && contractIsWorking);

        require(_to != address(0));
        require(_value <= investors[_from].tokenBalance);
        require(_value <= allowed[_from][msg.sender]);

        fixDividendBalances(_from,false);
        fixDividendBalances(_to,false);

        investors[_from].tokenBalance = investors[_from].tokenBalance.sub(_value);
        investors[_to].tokenBalance = investors[_to].tokenBalance.add(_value);
        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
        Transfer(_from, _to, _value);
        return true;
    }

    /*
        Eligible token and balance helper function
     */
    function fixDividendBalances(address investor, bool revertIfClaimed) internal returns (InvestorProfitData storage current_profit,uint256 profit_per_token){
        uint32 next_id      = uint32(dividends.length);
        uint32 current_id   = next_id-1;
        current_profit      = profits[investor][current_id];

        if (revertIfClaimed) require(current_profit.status != ProfitStatus.Claimed);
        InvestorProfitData storage next_profit      = profits[investor][next_id];

        if (current_profit.status == ProfitStatus.Initial) {

            current_profit.start_balance = investors[investor].tokenBalance;
            current_profit.end_balance   = investors[investor].tokenBalance;
            current_profit.status        = ProfitStatus.EndFixed;

            next_profit.start_balance = investors[investor].tokenBalance;
            next_profit.status        = ProfitStatus.StartFixed;

        } else if (current_profit.status == ProfitStatus.StartFixed) {
            current_profit.end_balance = investors[investor].tokenBalance;
            current_profit.status      = ProfitStatus.EndFixed;

            next_profit.start_balance = investors[investor].tokenBalance;
            next_profit.status        = ProfitStatus.StartFixed;
        }
        profit_per_token = dividends[current_id];
    }
}
