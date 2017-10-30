
pragma solidity 0.4.11;

import "./HumanStandardToken.sol";
import "./Disbursement.sol";
// import "./Filter.sol"; /* FLAG: this was removed */
import "./SafeMath.sol";


contract Sale {

    // EVENTS
    event TransferredTimelockedTokens(address beneficiary, address disbursement, uint beneficiaryTokens);
    event PurchasedTokens(address indexed purchaser, uint amount);
    event LockedUnsoldTokens(uint numTokensLocked, address disburser);

    // STORAGE

    uint public constant TOTAL_SUPPLY = 1000000000000000000;
    uint public constant MAX_PRIVATE = 750000000000000000; /* 75%! */
    uint8 public constant DECIMALS = 9;
    string public constant NAME = "Leverj";
    string public constant SYMBOL = "LEV";

    address public owner;
    address public wallet;
    HumanStandardToken public token;
    uint public freezeBlock;
    uint public startBlock;
    uint public endBlock;
    /* NOTE: this is apparenlty here just for info? */
    uint public presale_price_in_wei = 216685; //wei per 10**-9 of LEV! 
    uint public price_in_wei = 333333; //wei per 10**-9 of a LEV!

    //address[] public filters; 

    uint public privateAllocated = 0;
    bool public setupCompleteFlag = false;
    bool public emergencyFlag = false;

    address[] public disbursements;
    mapping(address => uint) public whitelistRegistrants;

    // PUBLIC FUNCTIONS
    function Sale(
        address _owner,
        uint _freezeBlock,
        uint _startBlock,
        uint _endBlock)
        public 
        checkBlockNumberInputs(_freezeBlock, _startBlock, _endBlock)
    {
        owner = _owner;
        token = new HumanStandardToken(TOTAL_SUPPLY, NAME, DECIMALS, SYMBOL, address(this));
        freezeBlock = _freezeBlock;
        startBlock = _startBlock;
        endBlock = _endBlock;
        assert(token.transfer(this, token.totalSupply()));
        assert(token.balanceOf(this) == token.totalSupply());
        assert(token.balanceOf(this) == TOTAL_SUPPLY);
    }

    function purchaseTokens()
        public
        payable
        setupComplete /* FLAG: possible for this to revert, even if `saleInProgress` is true*/
        notInEmergency
        saleInProgress
    {
        require(whitelistRegistrants[msg.sender] > 0);
        uint tempWhitelistAmount = whitelistRegistrants[msg.sender]; /* why 'temp'? */

        /* Calculate whether any of the msg.value needs to be returned to
           the sender. The purchaseAmount is the actual number of tokens which
           will be purchased. */
        uint purchaseAmount = msg.value / price_in_wei; /* Unit is LEV */
        uint excessAmount = msg.value % price_in_wei; /* Unit is WEI */

        if (purchaseAmount > whitelistRegistrants[msg.sender]) {
            uint extra = purchaseAmount - whitelistRegistrants[msg.sender]; /* Is LEV minus WEI? */
            purchaseAmount = whitelistRegistrants[msg.sender];
            excessAmount += extra*price_in_wei;
        }
        /* NOTE: so we refund the modulo remainder + the excess after whitelisting
            what 
            Price: 10 LEV per 2 ETH
            Whitelisted: 100 LEV (20 ETH)
            I send 31 ETH
            excessAmount: 1 ETH
            purchaseAmount = whitelisted = 20 ETH
            Refund amount = 11 ETH 
            This is OK, because the whitelist amount is in LEV, so there's no remainder
         */
        whitelistRegistrants[msg.sender] -= purchaseAmount;
        assert(whitelistRegistrants[msg.sender] < tempWhitelistAmount);

        // Cannot purchase more tokens than this contract has available to sell
        require(purchaseAmount <= token.balanceOf(this));

        // Return any excess msg.value
        if (excessAmount > 0) {
            msg.sender.transfer(excessAmount);
        }

        // Forward received ether minus any excessAmount to the wallet
        /* FLAG: nothing ensures the wallet is setup */
        wallet.transfer(this.balance);

        // Transfer the sum of tokens tokenPurchase to the msg.sender
        assert(token.transfer(msg.sender, purchaseAmount)); /* assert and transfer are redundant */
        PurchasedTokens(msg.sender, purchaseAmount);
    }

    function lockUnsoldTokens(address _unsoldTokensWallet)
        public
        saleEnded
        setupComplete
        onlyOwner
    {
        Disbursement disbursement = new Disbursement(
            _unsoldTokensWallet, /* this will be the receiver */
            1*365*  24*60*60, /* 1 year */
            block.timestamp
        );

        disbursement.setup(token);
        uint amountToLock = token.balanceOf(this);
        disbursements.push(disbursement);
        token.transfer(disbursement, amountToLock);
        LockedUnsoldTokens(amountToLock, disbursement);
    }

    // OWNER-ONLY FUNCTIONS
    function distributeTimelockedTokens(
        address[] _beneficiaries,
        uint[] _beneficiariesTokens,
        uint[] _timelockStarts,
        uint[] _periods
    ) 
        public
        onlyOwner
        saleNotEnded
    { 
        /* These should be `require`'s, and there should be a `notSetup` modifier or something */
        assert(!setupCompleteFlag); 
        assert(_beneficiariesTokens.length < 11);
        assert(_beneficiaries.length == _beneficiariesTokens.length);
        assert(_beneficiariesTokens.length == _timelockStarts.length);
        assert(_timelockStarts.length == _periods.length);

        for (uint i = 0; i < _beneficiaries.length; i++) {
            require(privateAllocated + _beneficiariesTokens[i] <= MAX_PRIVATE);
            privateAllocated += _beneficiariesTokens[i];
            address beneficiary = _beneficiaries[i];
            uint beneficiaryTokens = _beneficiariesTokens[i];

            Disbursement disbursement = new Disbursement(
                beneficiary,
                _periods[i],
                _timelockStarts[i] /* Should it be possible to specify this without constraint? */
            );

            disbursement.setup(token);
            token.transfer(disbursement, beneficiaryTokens);
            disbursements.push(disbursement);
            TransferredTimelockedTokens(beneficiary, disbursement, beneficiaryTokens);
        }

        assert(token.balanceOf(this) >= (TOTAL_SUPPLY - MAX_PRIVATE));
    }

    function distributePresaleTokens(address[] _buyers, uint[] _amounts)
        public
        onlyOwner
        saleNotEnded
    {
        assert(!setupCompleteFlag); 
        require(_buyers.length < 11);
        require(_buyers.length == _amounts.length);

        for (uint i=0; i < _buyers.length; i++) {
            require(privateAllocated + _amounts[i] <= MAX_PRIVATE);
            assert(token.transfer(_buyers[i], _amounts[i]));
            privateAllocated += _amounts[i];
            PurchasedTokens(_buyers[i], _amounts[i]);
        }

        assert(token.balanceOf(this) >= (TOTAL_SUPPLY - MAX_PRIVATE));
    }

    function removeTransferLock()
        public
        onlyOwner
    {
        token.removeTransferLock();
    }

    function reversePurchase(address _tokenHolder)
        public
        payable
        onlyOwner
    {
        /* FLAG: Uhm... so at any time the owner can reverse a purchase, to buy back the tokens
        at the original value? That's a nice little option to short sell your own token.
        More: token.reversePurchase() will give the tokens to the Sale contract.
            This can then be moved via `LockUnsold()`. 
            Very dangerous to leave this option available permanently. 
         */
        uint refund = token.baltanceOf(_tokenHolder)*price_in_wei;
        require(msg.value >= refund);
        uint excessAmount = msg.value - refund;

        if (excessAmount > 0) {
            msg.sender.transfer(excessAmount); // External call to `owner`. very safe
        }

        _tokenHolder.transfer(refund); // External call to _tokenHolder. gas is limited
        token.reversePurchase(_tokenHolder); /* FLAG: where does this function come from? */
    }

    function setSetupComplete()
        public
        onlyOwner
    {
        require(wallet != 0);
        require(privateAllocated != 0);  
        setupCompleteFlag = true;
    }

    function configureWallet(address _wallet)
        public
        onlyOwner
    {
        wallet = _wallet; 
    }

    function changeOwner(address _newOwner)
        public
        onlyOwner
    {
        require(_newOwner != 0);
        owner = _newOwner;
    }

    function changePrice(uint _newPrice)
        public
        onlyOwner
        notFrozen
        validPrice(_newPrice)
    {
        price_in_wei = _newPrice;
    }

    function changeStartBlock(uint _newBlock)
        public
        onlyOwner
        notFrozen
    {
        /* the newBlock must be in the future, but before the current start? */
        require(block.number <= _newBlock && _newBlock < startBlock);
        /* This moves freezeBlock sooner? */
        freezeBlock = _newBlock - (startBlock - freezeBlock);
        startBlock = _newBlock;
    }

    function emergencyToggle()
        public
        onlyOwner
    {
        emergencyFlag = !emergencyFlag;
    }
    
    /* 
        QUESTION: amount of what? 
        This needs to be input as LEV in order for 
    */
    function addWhitelist(address[] _purchaser, uint[] _amount)
        public
        onlyOwner
        saleNotEnded
    {
        assert(_purchaser.length < 11);
        assert(_purchaser.length == _amount.length);
        for (uint i = 0; i < _purchaser.length; i++) {
            whitelistRegistrants[_purchaser[i]] = _amount[i];
        }
    }

    // MODIFIERS
    modifier saleEnded {
        require(block.number >= endBlock);
        _;
    }

    modifier saleNotEnded {
        require(block.number < endBlock);
        _;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    /* So freezeBlock is before startBlock, and is when the price can no longer be changed */
    modifier notFrozen {
        require(block.number < freezeBlock);
        _;
    }

    modifier saleInProgress {
        require(block.number >= startBlock && block.number < endBlock);
        _;
    }

    modifier setupComplete { 
        assert(setupCompleteFlag);
        _;
    }

    modifier notInEmergency {
        assert(emergencyFlag == false);
        _;
    }

    modifier checkBlockNumberInputs(uint _freeze, uint _start, uint _end) {
        require(_freeze >= block.number
        && _start >= _freeze
        && _end >= _start);
        _;
    }

    modifier validPrice(uint _price) {
        require(_price > 0);
        _;
    }

}