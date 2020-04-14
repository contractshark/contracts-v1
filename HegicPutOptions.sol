pragma solidity ^0.6.4;
import "./HegicOptions.sol";

contract HegicPutOptions is HegicOptions {
  constructor(IERC20 DAI, IPriceProvider pp, IUniswapFactory ex)
    HegicOptions(DAI, pp, ex, HegicOptions.OptionType.Put) public {
      pool = new HegicERCPool(DAI);
  }

  function exchange() public returns (uint) { return exchange(address(this).balance); }

  function exchange(uint amount) public returns (uint exchangedAmount) {
    UniswapExchangeInterface ex = exchanges.getExchange(token);
    uint exShare = ex.getEthToTokenInputPrice(1 ether); //e18
    if( exShare > maxSpread.mul( priceProvider.currentAnswer() ).mul(1e8) )
      exchangedAmount = ex.ethToTokenTransferInput {value: amount} (1, now + 1 minutes, address(pool));
  }

  function create(uint period, uint amount) public payable returns (uint optionID) {
    return create(period, amount, priceProvider.currentAnswer());
  }

  function create(uint period, uint amount, uint strike) public payable returns (uint optionID) {
      (uint premium, uint fee,,,) = fees(period, amount, strike);
      uint strikeAmount = strike.mul(amount) / priceDecimals;

      require(strikeAmount > 0,"Amount is too small");
      require(fee > premium,   "Period is too short");
      require(period >= 1 days,"Period is too short");
      require(period <= 8 weeks,"Period is too long");
      require(msg.value == premium, "Wrong value");

      payable( owner() ).transfer(fee);
      exchange();
      pool.lock(strikeAmount);
      optionID = options.length;
      options.push(Option(State.Active, msg.sender, strikeAmount, amount, now + period, now + activationTime));

      emit Create(optionID, msg.sender, fee, premium);
  }

  function exercise(uint optionID) public payable {
      Option storage option = options[optionID];

      require(option.expiration >= now, 'Option has expired');
      require(option.activation <= now, 'Option has not been activated yet');
      require(option.holder == msg.sender, "Wrong msg.sender");
      require(option.state == State.Active, "Wrong state");
      require(option.amount == msg.value, "Wrong value");

      option.state = State.Expired;

      uint amount = exchange();
      pool.send(option.holder, option.strikeAmount);
      emit Exercise(optionID, amount);
  }
}
