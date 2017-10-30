pragma solidity ^0.4.11;
import "./Token.sol";
// NOTE: ORIGINALLY THIS WAS "TOKENS/ABSTRACTTOKEN.SOL"... CHECK THAT


/// @title Disbursement contract - allows to distribute tokens over time
/// @author Stefan George - <stefan@gnosis.pm>
contract Disbursement {

    /*
     *  Storage
     */
    address public owner;
    address public receiver;
    uint public disbursementPeriod; /* NOTE: the length of time over which the full amount vests */
    uint public startDate; /* NOTE: the first time at which any amount of tokens is available */
    uint public withdrawnTokens;
    Token public token;

    /*
     *  Modifiers
     */
    modifier isOwner() {
        if (msg.sender != owner)
            // Only owner is allowed to proceed
            revert();
        _;
    }

    modifier isReceiver() {
        if (msg.sender != receiver)
            // Only receiver is allowed to proceed
            revert();
        _;
    }

    /* NOTE: to Janison's question, this could be made to check for either a true or false condition
        by:
        modifier isSetup(bool _boolean) {
            require((address(token) > 0) == _boolean);
            _;
         }
 */

    modifier isSetUp() {
        if (address(token) == 0)
            // Contract is not set up
            revert();
        _;
    }

    /*
     *  Public functions
     */
    /// @dev Constructor function sets contract owner
    /// @param _receiver Receiver of vested tokens
    /// @param _disbursementPeriod Vesting period in seconds
    /// @param _startDate Start date of disbursement period (cliff)
    function Disbursement(address _receiver, uint _disbursementPeriod, uint _startDate)
        public
    {
        if (_receiver == 0 || _disbursementPeriod == 0)
            // Arguments are null
            revert();
        owner = msg.sender; /* NOTE: Does not allow to use cold storage for owner. 
                Nevermind, owner will be the calling contract */
        receiver = _receiver;
        disbursementPeriod = _disbursementPeriod;
        startDate = _startDate;
        if (startDate == 0)
            startDate = now;
    }

    /// @dev Setup function sets external contracts' addresses
    /// @param _token Token address
    /* NOTE: why wouldn't this be done in the constructor? Oh well, no harm. */
    /* QUESTION: why was the argument changed from `address _token` to `Token _token`  */
    function setup(Token _token)
        public
        isOwner
    {
        if (address(token) != 0 || address(_token) == 0) /* SUGGESTION: use `require` */
            // Setup was executed already or address is null
            revert();
        token = _token; 
    }

    /// @dev Transfers tokens to a given address
    /// @param _to Address of token receiver
    /// @param _value Number of tokens to transfer
    function withdraw(address _to, uint256 _value)
        public
        isReceiver /* can only be called by the contract's receiver, but can be withdrawn to anywhere */
        isSetUp /*  */
    {
        uint maxTokens = calcMaxWithdraw();
        /* Don't let them withdraw more than they're allowed*/
        if (_value > maxTokens) /* SUGGESTION: use `require` */
            revert(); 
        withdrawnTokens += _value;
        token.transfer(_to, _value); 
    }

    /// @dev Calculates the maximum amount of vested tokens
    /// @return Number of vested tokens to withdraw
    function calcMaxWithdraw()
        public
        constant /* SUGGESTION: use `view` */
        returns (uint)
    {
        /* Looks like this just describes a straight line increasing with time: y = xt 
            Although, start date may be at some future point in time, ie. 3 months after the sale.
        */
        uint maxTokens = (token.balanceOf(this) + withdrawnTokens) * (now - startDate) / disbursementPeriod;
        /* what if maxTokens is greater than remain tokens? */
        if (withdrawnTokens >= maxTokens || startDate > now)
            return 0; 
        if (maxTokens - withdrawnTokens > token.totalSupply())
            return token.totalSupply();
        /* If you wait a long time this value will be larger than what the contract holds...
            but that's OK, because they don't have to withdraw maxTokens... 
         */
        return maxTokens - withdrawnTokens; 
    }
}
