// SPDX-License-Identifier: MIT

/* 
 * Stater.co
 */
pragma solidity 0.7.4;
pragma experimental ABIEncoderV2;

import "./LendingLogic.sol";

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-solidity/contracts/token/ERC721/ERC721Holder.sol";
import "multi-token-standard/contracts/interfaces/IERC1155.sol";
import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "openzeppelin-solidity/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";



contract LendingData is ERC721Holder, Ownable, ReentrancyGuard {

  using SafeMath for uint256;

  address public lendingLogicAddress;
  LendingLogic lendingLogic;
  uint256 public loanID;
  uint256 public installmentFrequency = 7; // days
  uint256 public interestRate = 20;
  uint256 public interestRateToStater = 40;

  enum Status {
    UNINITIALIZED,
    LISTED,
    APPROVED,
    DEFAULTED, 
    LIQUIDATED,
    CANCELLED
  }
  
  struct Loan {
    uint256[] nftTokenIdArray; // the unique identifier of the NFT token that the borrower uses as collateral
    uint256 loanAmount; // the amount, denominated in tokens (see next struct entry), the borrower lends
    uint256 assetsValue; // important for determintng LTV which has to be under 50-60%
    uint256 loanStart; // the point when the loan is approved
    uint256 loanEnd; // the point when the loan is approved to the point when it must be paid back to the lender
    uint256 nrOfInstallments; // the number of installments that the borrower must pay.
    uint256 installmentAmount; // amount expected for each installment
    uint256 amountDue; // loanAmount + interest that needs to be paid back by borrower
    uint256 paidAmount; // the amount that has been paid back to the lender to date
    uint256 defaultingLimit; // the number of installments allowed to be missed without getting defaulted
    uint256 nrOfPayments; // the number of installments paid
    Status status; // the loan status
    address[] nftAddressArray; // the adderess of the ERC721
    address payable borrower; // the address who receives the loan
    address payable lender; // the address who gives/offers the loan to the borrower
    address currency; // the token that the borrower lends, address(0) for ETH
  }

  mapping(uint256 => Loan) public loans;

  function changeLendingLogic(address theLendingLogicAddress) external onlyOwner {
    lendingLogicAddress = theLendingLogicAddress;
    lendingLogic = LendingLogic(lendingLogicAddress);
  }

  // Borrower creates a loan
  function createLoan(
    uint256 loanAmount,
    uint256 nrOfInstallments,
    address currency,
    uint256 assetsValue, 
    address[] calldata nftAddressArray, 
    uint256[] calldata nftTokenIdArray,
    string calldata creationId
  ) external {

    // Set loan fields
    loans[loanID].nftTokenIdArray = nftTokenIdArray;
    loans[loanID].loanAmount = loanAmount;
    loans[loanID].assetsValue = assetsValue;
    loans[loanID].nrOfInstallments = nrOfInstallments;
    loans[loanID].status = Status.LISTED;
    loans[loanID].nftAddressArray = nftAddressArray;
    loans[loanID].borrower = msg.sender;
    loans[loanID].currency = currency;


    // Computing the defaulting limit
    uint256 defaultingLimit = 1;
    if ( nrOfInstallments <= 3 )
        defaultingLimit = 1;
    else if ( nrOfInstallments <= 5 )
        defaultingLimit = 2;
    else if ( nrOfInstallments >= 6 )
        defaultingLimit = 3;

    // Computing loan parameters
    uint256 loanPlusInterest = loanAmount.mul(interestRate.add(100)).div(100); // interest rate >> 20%
    uint256 installmentAmount = loanPlusInterest.div(nrOfInstallments);
    
    loans[loanID].amountDue = loanPlusInterest;
    loans[loanID].installmentAmount = installmentAmount;
    loans[loanID].defaultingLimit = defaultingLimit;
    
    lendingLogicAddress.call(abi.encodeWithSignature("createLoanVerification(Loan,uint256,string,address)",loans[loanID],loanID,creationId,msg.sender));
 
    loanID.add(1);
  }


  // Lender approves a loan
  function approveLoan(uint256 loanId) external payable {

    // lendingLogicAddress.call{ value : msg.value }(abi.encodeWithSignature("approveLoanVerification(Loan)",loans[loanId])); >> returns boolean
    lendingLogicAddress.call{ value : msg.value }(abi.encodeWithSignature("approveLoanVerification(Loan,address,uint256)",loans[loanId],msg.sender,loanId));

    // Borrower assigned , status is APPROVED , first installment ( payment ) completed
    loans[loanId].lender = msg.sender;
    loans[loanId].status = Status.APPROVED;
    
    loans[loanId].loanStart = block.timestamp;
    loans[loanId].loanEnd = block.timestamp.add(loans[loanId].nrOfInstallments.mul(installmentFrequency).mul(1 days));

  }



  // Borrower cancels a loan
  function cancelLoan(uint256 loanId) external {
        
    lendingLogicAddress.call(abi.encodeWithSignature("cancelLoanVerification(Loan,uint256,address)",loans[loanId],loanId,msg.sender));
    
    // We set its validity date as block.timestamp
    loans[loanId].loanEnd = block.timestamp;
    loans[loanId].status = Status.CANCELLED;

  }

  // Borrower pays installment for loan
  // Multiple installments : OK
  function payLoan(uint256 loanId) external payable {

    loans[loanId].paidAmount = loans[loanId].paidAmount.add(msg.value);
    loans[loanId].nrOfPayments = loans[loanId].paidAmount.div(loans[loanId].installmentAmount);

    if (loans[loanId].paidAmount >= loans[loanId].amountDue)
      loans[loanId].status = Status.LIQUIDATED;
      
    lendingLogicAddress.call{ value : msg.value }(abi.encodeWithSignature("payLoanVerification(Loan,uint256,address)",loans[loanId],loanId,msg.sender));

  }



  // Borrower can withdraw loan items if loan is LIQUIDATED
  // Lender can withdraw loan item is loan is DEFAULTED
  function withdrawItems(uint256 loanId) external {

    lendingLogicAddress.call(abi.encodeWithSignature("withdrawItemsVerification(Loan,uint256,address)",loans[loanId],loanId,msg.sender));

    if ( block.timestamp >= loans[loanId].loanEnd && loans[loanId].paidAmount < loans[loanId].amountDue )
      loans[loanId].status = Status.DEFAULTED;

  }

  function terminateLoan(uint256 loanId) external {

    lendingLogicAddress.call(abi.encodeWithSignature("terminateLoanVerification(Loan,uint256,address)",loans[loanId],loanId,msg.sender));

    loans[loanId].status = Status.DEFAULTED;
    loans[loanId].loanEnd = block.timestamp;

  }
  

  // Internal Functions 

  // Transfer items fron an account to another
  // Requires approvement
  function _transferItems(
    address from, 
    address to, 
    address[] memory nftAddressArray, 
    uint256[] memory nftTokenIdArray
  ) internal {
    uint256 length = nftAddressArray.length;
    require(length == nftTokenIdArray.length, "Token infos provided are invalid");
    for(uint256 i = 0; i < length; ++i) 
      IERC721(nftAddressArray[i]).safeTransferFrom(
        from,
        to,
        nftTokenIdArray[i]
      );
  }



  // Getters & Setters

  function getLoanStatus(uint256 loanId) external view returns(Status) {
    return loans[loanId].status;
  }
  
  function getLoanApproveTotalPayment(uint256 loanId) external view returns(uint256) {
      return loans[loanId].loanAmount.add(loans[loanId].loanAmount.div(100));
  }

  function getNftTokenIdArray(uint256 loanId) external view returns(uint256[] memory) {
    return loans[loanId].nftTokenIdArray;
  }

  function getLoanAmount(uint256 loanId) external view returns(uint256) {
    return loans[loanId].loanAmount;
  }

  function getAssetsValue(uint256 loanId) external view returns(uint256) {
    return loans[loanId].assetsValue;
  }

  function getLoanStart(uint256 loanId) external view returns(uint256) {
    return loans[loanId].loanStart;
  }

  function getLoanEnd(uint256 loanId) external view returns(uint256) {
    return loans[loanId].loanEnd;
  }

  function getNrOfInstallments(uint256 loanId) external view returns(uint256) {
    return loans[loanId].nrOfInstallments;
  }

  function getInstallmentAmount(uint256 loanId) external view returns(uint256) {
    return loans[loanId].installmentAmount;
  }

  function getAmountDue(uint256 loanId) external view returns(uint256) {
    return loans[loanId].amountDue;
  }

  function getPaidAmount(uint256 loanId) external view returns(uint256) {
    return loans[loanId].paidAmount;
  }

  function toPayForApprove(uint256 loanId) external view returns(uint256) {
	return loans[loanId].loanAmount.add(loans[loanId].loanAmount.div(100));
  }

  function getDefaultingLimit(uint256 loanId) external view returns(uint256) {
    return loans[loanId].defaultingLimit;
  }

  function getNrOfPayments(uint256 loanId) external view returns(uint256) {
    return loans[loanId].nrOfPayments;
  }

  function getNftAddressArray(uint256 loanId) external view returns(address[] memory) {
    return loans[loanId].nftAddressArray;
  }

  function getBorrower(uint256 loanId) external view returns(address) {
    return loans[loanId].borrower;
  }

  function getLender(uint256 loanId) external view returns(address) {
    return loans[loanId].lender;
  }

  function getCurrency(uint256 loanId) external view returns(address) {
    return loans[loanId].currency;
  }
  
  function getLoansCount() external view returns(uint256) {
    return loanID;
  }


  // Auxiliary functions

  // Returns loan by id, ommits nrOfInstallments as the stack was too deep and we can derive it in the backend
  function getLoanById(uint256 loanId) 
    external
    view
    returns(
      uint256 loanAmount,
      uint256 assetsValue,
      uint256 loanEnd,
      uint256 installmentAmount,
      uint256 amountDue,
      uint256 paidAmount,
      uint256[] memory nftTokenIdArray,
      address[] memory nftAddressArray,
      address payable borrower,
      address payable lender,
      address currency,
      Status status
    ) {
      Loan storage loan = loans[loanId];
      
      loanAmount = uint256(loan.loanAmount);
      assetsValue = uint256(loan.assetsValue);
      loanEnd = uint256(loan.loanEnd);
      installmentAmount = uint256(loan.installmentAmount);
      amountDue = uint256(loan.amountDue);
      paidAmount = uint256(loan.paidAmount);
      nftTokenIdArray = uint256[](loan.nftTokenIdArray);
      nftAddressArray = address[](loan.nftAddressArray);
      borrower = payable(loan.borrower);
      lender = payable(loan.lender);
      currency = address(currency);
      status = Status(loan.status);
  }

  // This function will indicate if the borrower has payed all his installments in time or not
  // False >> Borrower still has time to pay his installments
  // True >> Time to pay installments expired , the loan can be ended
  function lackOfPayment(uint256 loanId) public view returns(bool) {
    return loans[loanId].status == Status.APPROVED && loans[loanId].loanStart.add(loans[loanId].nrOfPayments.mul(installmentFrequency.mul(1 days))) <= block.timestamp.sub(loans[loanId].defaultingLimit.mul(installmentFrequency.mul(1 days)));
  }

  // TODO: Add auxiliary loan status update function for DEFAULTED state to be used by whomever

}
