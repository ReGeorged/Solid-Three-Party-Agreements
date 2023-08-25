// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9 <9.0.0;

contract UsersWallet{
    address owner;
    uint256 starterIndex = 0;
    address[] contractUsers;
    mapping (address=>uint256) addressBalances;
    mapping(address =>uint256) addressIndexInArrayToSaveGas;
    event fundsReceived (string status, uint256 amount);
    event fundsTransferred (string message,address toAddress, uint256 amount);

    constructor(){
        owner = msg.sender;
    }

    modifier onlyOwner(){
        require(tx.origin==owner,"You're not the owner of this smart contract!");
        _;
    }

    function createNewUser()internal {
        //create new user check the users array if user never existed update the array and remmember the index in addressIndexInArrayToSaveGas mapping
        if(addressBalances[msg.sender]==0){
            if(addressIndexInArrayToSaveGas[msg.sender]!=0){
                contractUsers[addressIndexInArrayToSaveGas[msg.sender]] = msg.sender;
            } else{
            contractUsers.push(msg.sender);
            addressIndexInArrayToSaveGas[msg.sender]=starterIndex;
            starterIndex++;
            } 
        }
    }

    function getFunds() public payable{
        createNewUser();
        addressBalances[msg.sender]+=msg.value;
        emit fundsReceived("Funds are received, amount is: ",msg.value);
    }
    function checkBalanceOf(address _address)external view returns(uint256){
        return addressBalances[_address];
    }

    function deleteFromArrayIfNoFunds()internal{
        /*no need to keep inactive users in the array and with the help of the additional mapping we crated
         if this user decides to come back his/her index will be remmembered and the array will be updated
        without it increasing thus initial deployement gas cost will be a bit higher but will save funds down the line as the project grows!*/
        addressBalances[msg.sender]=0;
        delete contractUsers[addressIndexInArrayToSaveGas[msg.sender]];
    }

    function externalTransferCustomAmount(address receiverAddress, uint256 amount)external {
        //needed for triggering transfer from voucher contract (2 types of transfers are defined transferAll and transfer custom amount)
        require(addressBalances[tx.origin]>=amount,"Not enough balance to transfer!");
        addressBalances[tx.origin]-=amount;
        if(addressBalances[tx.origin]==0){
            deleteFromArrayIfNoFunds();
        }
        payable(receiverAddress).transfer(amount); 
        emit fundsTransferred("Funds are transferred , address and amount are following: ", receiverAddress, amount);
    }

    function externalTransferAllAmount(address receiverAddress) external returns(uint256 allFunds){
        require(addressBalances[tx.origin]>0,"No balance to transfer!");
        uint256 funds = addressBalances[tx.origin];
        bool result = payable(receiverAddress).send(addressBalances[tx.origin]);
        if(result){
        deleteFromArrayIfNoFunds();
        emit fundsTransferred("All your funds are transferred, address and amount are following: ", receiverAddress, addressBalances[msg.sender]);
        return funds;
        }else{
            revert();
            }
    } 
    function transferCustomAmount(address receiverAddress, uint256 amount)public {
        require(addressBalances[msg.sender]>=amount,"Not enough balance to transfer!");
        addressBalances[msg.sender]-=amount;
        if(addressBalances[msg.sender]==0){
            deleteFromArrayIfNoFunds();
        }
        payable(receiverAddress).transfer(amount); 
        emit fundsTransferred("Funds are received, address and amount are following: ", receiverAddress, amount);
    }

    function transferAllAmount(address receiverAddress) public{
        require(addressBalances[msg.sender]>0,"No balance to transfer!");
        uint256 amount = addressBalances[msg.sender];
        bool result = payable(receiverAddress).send(addressBalances[msg.sender]);
        if(result){
        deleteFromArrayIfNoFunds();
        emit fundsTransferred("Funds are received, address and amount are following: ", receiverAddress, amount);
        }else{
            revert();
            }

    }
    //well what if we wanted to get an array?
    function getArray()public view onlyOwner returns( address[] memory){
        return contractUsers;
    }

    fallback() external payable {
        
    }
    receive() external payable {

    }
    
}

contract Voucher{
    address owner;
    address private  thisContractAddress;
    uint256 public idCounter = 0 ; 
    UsersWallet private usersWallet;
    mapping(uint256 => voucherStruct) voucherMapping;
    mapping(address => uint256) totalAmount;
    mapping(address => uint256) totalFrozenAmount;

    struct  voucherStruct {
    address issuer;
    address recipient;
    address finalDestination;
    string voucherDetails;
    uint256 price;
    bool used;
    }

    event voucherWasIssued(uint256 idOfVoucher, address from, address userId, address destination,string message, uint256 funds);
    event moneyIsDeposited(address  userAddr, uint256 amount);
    event voucherRedeemed(address redeemer, address redeemedFor, string message, uint256 amount);

    //while deploying the voucher SC we need to pass the Wallet SC address
    constructor (address walletsContractAddress){
        usersWallet = UsersWallet(payable(walletsContractAddress));
        thisContractAddress = address(this);
        owner = msg.sender;
    }
     modifier onlyOwner(){
        require(tx.origin==owner,"You're not the owner of this smart contract!");
        _;
    }
    modifier notNegative(){
        require((totalAmount[msg.sender]-totalFrozenAmount[msg.sender])>=0,"Your NET balance is negative!");
        _;
    }
  //to issue a voucher caller needs to have funds greater than or equal to the price of the voucher in the wallet smart contract
  // while the voucher gets created the funds get tansacted from wallet to this smart contract and get locker
  //only way to unlock the funds is for party 2 (userOfVoucher) to call an redeem function
  //this automatically increases the balance of party3(final destination)
  //no other way to move funds around here
  //you can call self destruct..etc but you wont get funds... use as intended!
    function issueVoucher(address _userOfVoucher, address _redeemerCompany, uint256 _funds, string calldata details)public{
        require((tx.origin==msg.sender)&&(_userOfVoucher != msg.sender) && (_redeemerCompany != msg.sender) && ( _userOfVoucher != _redeemerCompany));
        callTransferCustomAmount(_funds);
        totalFrozenAmount[msg.sender] += _funds;

        voucherStruct storage v =  voucherMapping[idCounter];
        v.issuer = msg.sender;
        v.recipient =_userOfVoucher;
        v.finalDestination =  _redeemerCompany;
        v.voucherDetails = details;
        v.price = _funds;
        

        totalFrozenAmount[v.recipient] += _funds;

        emit voucherWasIssued(idCounter,msg.sender,_userOfVoucher,_redeemerCompany,details,_funds);
        idCounter++;
    }

    //only way to redeem the voucher is to know the id of it (id gets emitted when voucher is created)
    //only party2 (user) can redeem the voucher
    //when redeemed frozen funds get released

    function redeemVoucher(uint256 id)public {
        require (voucherMapping[id].recipient == msg.sender && voucherMapping[id].used==false, "You're not the recipient of this voucher!");
        voucherMapping[id].used = true;
        uint256 voucherValue = voucherMapping[id].price;
        totalFrozenAmount[voucherMapping[id].issuer]-= voucherValue;
        totalFrozenAmount[voucherMapping[id].recipient]-= voucherValue;
        totalAmount[voucherMapping[id].finalDestination]+=voucherValue;
        totalAmount[voucherMapping[id].issuer]-=voucherValue;

        emit voucherRedeemed(msg.sender,voucherMapping[id].finalDestination,voucherMapping[id].voucherDetails, voucherMapping[id].price);
    }

    //check balance in wallets smartContract
    function checkAmountInWallett(address _balanceOf)public view returns(uint256){
       return usersWallet.checkBalanceOf(_balanceOf);
    }

    //internal function is called in createVoucher function (it is needed to transfer funds from wallet SC to this SC)
    function callTransferCustomAmount(uint256  amount)internal {
        usersWallet.externalTransferCustomAmount(thisContractAddress,amount);
        totalAmount[msg.sender]+=amount;
        emit moneyIsDeposited(msg.sender,amount);
    }
    //get full voucher
    function getVoucher(uint256 id)public view returns(voucherStruct memory){
        require((voucherMapping[id].issuer == msg.sender) || (voucherMapping[id].recipient == msg.sender) ||(voucherMapping[id].finalDestination == msg.sender),"You're not the participant of this voucher!" );
        return voucherMapping[id];
    }
    //get voucher details
    function getVoucherDetails(uint256 id)public view returns(address from,address recipient, address voucherFor, string  memory details, uint256 price,bool used){
        require((voucherMapping[id].issuer == msg.sender) || (voucherMapping[id].recipient == msg.sender) ||(voucherMapping[id].finalDestination == msg.sender),"You're not the participant of this voucher!" );
        return(
            voucherMapping[id].issuer,
            voucherMapping[id].recipient,
            voucherMapping[id].finalDestination,
            voucherMapping[id].voucherDetails,
            voucherMapping[id].price,
            voucherMapping[id].used
        );
    }
    //check balances (returns all amount and frozen amount) available amount logically is: all - frozen
    function checkMyBalances()public view returns(uint256 _totalFunds,uint256 _frozenFunds){
        return (totalAmount[msg.sender],totalFrozenAmount[msg.sender]);
    }
    //names of few below functions are pretty much self explanatory
    function getAvailableFunds()public view notNegative returns(uint256){
        return totalAmount[msg.sender]-totalFrozenAmount[msg.sender];
    }

    function withdrawAllAvailableAmount(address whereTo)public notNegative{
        uint256 available = getAvailableFunds();
        totalAmount[msg.sender] -= available;
        payable(whereTo).transfer(available); 
    }
    function withdrawCustomAmount(address whereTo,uint256 amount)public{
        require(amount>=getAvailableFunds());
        totalAmount[msg.sender] -= amount;
        payable(whereTo).transfer(amount); 
    }
    //this function was totally needed and was not only put here to comply with the rules of final project
    // satoshi strike me down if im lying 
    function generalCallGetArray(address _addr)public returns(bool success, bytes memory payload){
            (success,payload) =  _addr.call{gas:30000}(abi.encodeWithSignature("getArray()"));
            if(success){
                return (success,payload);
            }else{
                revert();
            }
    }

    fallback() external payable { 
    }
    receive() external payable {
    }
}

contract Submitter{
    address private constant submitAddress = 0xFD591AEFb9e601d13727f035080d5aDB674e4Bee;
    string public todaysPlan;
    address owner;
    function getFunds()public payable{

    }
    function withdrawFunds(address _addr)public onlyOwner{
        payable(_addr).transfer(address(this).balance);
    }

    constructor(){
        todaysPlan = "Work!";
        owner = msg.sender;
    }
    modifier onlyOwner(){
        require(owner==msg.sender);
        _;
    }
    event Response(bool success, bytes data);


    //missed a minor detail -it was woring - spent few hours debugging - now it works, dont touch it :)

    function projectSubmitted(string memory _codeFileHash,string memory _topicName, string memory _authorName, address _sendHashTo) external payable onlyOwner returns(bool , bytes memory ) {
         (bool _success, bytes memory data) = payable(_sendHashTo).call{value:msg.value}(abi.encodeWithSignature("receiveProjectData(string,string,string)",_codeFileHash,_topicName,_authorName));
         emit Response(_success,data);

        return (_success,data);
    }

    function checkSubmission()public  returns(bool){
        bool result =  NotAStolenInterface(submitAddress).isProjectReceived();
        if(result){
            todaysPlan = "We drink Tonight";
        }else{
            todaysPlan = "Work harder!";
        }
        return result;
    }

    fallback()external payable{

    }
    receive()external payable{

    }

}

interface NotAStolenInterface{
    function receiveProjectData(string memory _codeHash, string memory _topicName, string memory _authorName) external payable ;
    function isProjectReceived() external view returns (bool);


}