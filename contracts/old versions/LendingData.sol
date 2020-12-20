// SPDX-License-Identifier: MIT
pragma solidity 0.7.4;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-solidity/contracts/token/ERC721/ERC721Holder.sol";
import "multi-token-standard/contracts/interfaces/IERC1155.sol";
import "openzeppelin-solidity/contracts/access/Ownable.sol";
// import "openzeppelin-solidity/contracts/access/roles/WhitelistedRole.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";


contract LendingData is ERC721Holder, Ownable {

  using SafeMath for uint256;

  uint256 public constant PRECISION = 3;
  uint256 public loanFee = 1; // 1%
  uint256 public ltv = 600; // 60%
  uint256 public interestRateToCompany = 40; // 40%
  uint256 public interestRate = 20; // 20%
  uint256 public installmentFrequency = 7; // days

  event NewLoan(uint256 indexed loanId, address indexed owner, uint256 creationDate, address indexed currency, Status status, string creationId);
  event LoanApproved(uint256 indexed loanId, uint256 approvalDate, uint256 loanPaymentEnd, uint256 installmentAmount, Status status);
  event LoanCancelled(uint256 indexed loanId, uint256 cancellationDate, Status status);
  event ItemsWithdrawn(uint256 indexed loanId, address indexed requester, Status status);
  event LoanPayment(uint256 indexed loanId, uint256 paymentDate, uint256 installmentAmount, Status status);
  event LtvChanged(uint256 newLTV);
  event InterestRateToLenderChanged(uint256 newInterestRateToLender);
  event InterestRateToCompanyChanged(uint256 newInterestRateToCompany);

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
    uint256 id; // unique Loan identifier
    uint256 loanAmount; // the amount, denominated in tokens (see next struct entry), the borrower lends
    uint256 assetsValue; // important for determintng LTV which has to be under 50-60%
    uint256 loanStart; // the point when the loan is approved
    uint256 loanEnd; // the point when the loan is approved to the point when it must be paid back to the lender
    uint256 nrOfInstallments; // the number of installments that the borrower must pay.
    uint256 installmentAmount; // amount expected for each installment
    uint256 amountDue; // loanAmount + interest that needs to be paid back by borrower
    uint256 paidAmount; // the amount that has been paid back to the lender to date
    uint256 defaultingLimit; // the number of installments allowed to be missed without getting defaulted
    uint256 installmentsPayed; // the number of installments paid
    Status status; // the loan status
    address[] nftAddressArray; // the adderess of the ERC721
    address payable borrower; // the address who receives the loan
    address payable lender; // the address who gives/offers the loan to the borrower
    address currency; // the token that the borrower lends, address(0) for ETH
  }

  Loan[] loans; // the array of NFT loans

  constructor() {
    uint256[] memory empty1;
    address[] memory empty2;
    // Initialize loans[] with empty loan (NULL LOAN)
    loans.push(
        Loan(
            empty1,
            0,
            0,
            0,
            block.timestamp,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            Status.UNINITIALIZED,
            empty2,
            address(0),
            address(0),
            address(0)
        )
    );
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
    require(nrOfInstallments > 0, "Loan must include at least 1 installment");
    require(loanAmount > 0, "Loan amount must be higher than 0");

    // Compute loan to value ratio for current loan application
    require(_percent(loanAmount, assetsValue, PRECISION) <= ltv, "LTV exceeds maximum limit allowed");

    // Transfer the items from lender to stater contract
    _transferItems(msg.sender, address(this), nftAddressArray, nftTokenIdArray);

    // Computing the defaulting limit
    uint256 defaultingLimit = 1;
    if ( nrOfInstallments <= 3 )
        defaultingLimit = 1;
    else if ( nrOfInstallments <= 5 )
        defaultingLimit = 2;
    else if ( nrOfInstallments >= 6 )
        defaultingLimit = 3;

    // Computing loan parameters
    uint256 loanPlusInterest = loanAmount.mul(100 + interestRate).div(100);
    uint256 installmentAmount = loanPlusInterest.div(nrOfInstallments);
    uint256[] memory empty1;

    // Fire event
    emit NewLoan(loans.length, msg.sender, block.timestamp, currency, Status.LISTED, creationId);

    loans.push(
        Loan(
            nftTokenIdArray,
            loans.length,
            loanAmount,
            assetsValue,
            block.timestamp,
            0,
            nrOfInstallments,
            installmentAmount,
            loanPlusInterest,
            0,
            defaultingLimit,
            0,
            Status.LISTED,
            nftAddressArray,
            msg.sender,
            address(0), // Lender
            currency
        )
    );
 
  }


  // Lender approves a loan
  function approveLoan(uint256 loanId) external {
    require(loans[loanId].lender == address(0), "Someone else payed for this loan before you");
    require(loans[loanId].paidAmount == 0, "This loan is currently not ready for lenders");
    require(loans[loanId].status == Status.LISTED, "This loan is not currently ready for lenders, check later");

    // Send 99% to borrower & 1% to company
    // Floating point problem , impossible to send rational qty of ether ( debatable )
    // The rest of the wei is sent to company by default
    require(IERC20(loans[loanId].currency).transferFrom(
      msg.sender,
      loans[loanId].borrower, 
      loans[loanId].loanAmount
    ), "Transfer of liquidity failed"); // Transfer complete loanAmount to borrower

    require(IERC20(loans[loanId].currency).transferFrom(
      msg.sender,
      owner(), 
      loans[loanId].loanAmount.mul(loanFee).div(100)
    ), "Transfer of liquidity failed"); // loanFee percent on top of original loanAmount goes to contract owner

    // Borrower assigned , status is 1 , first installment ( payment ) completed
    loans[loanId].lender = msg.sender;
    loans[loanId].loanEnd = block.timestamp.add(loans[loanId].nrOfInstallments.mul(installmentFrequency).mul(1 days));
    loans[loanId].status = Status.APPROVED;
    loans[loanId].loanStart = block.timestamp;

    emit LoanApproved(
      loanId,
      block.timestamp, 
      loans[loanId].loanEnd, 
      loans[loanId].installmentAmount, 
      Status.APPROVED
    );
  }



  // Borrower cancels a loan
  function cancelLoan(uint256 loanId) external {
    require(loans[loanId].lender == address(0), "The loan has a lender , it cannot be cancelled");
    require(loans[loanId].borrower == msg.sender, "You're not the borrower of this loan");
    require(loans[loanId].status != Status.CANCELLED, "This loan is already cancelled");
    require(loans[loanId].status == Status.LISTED, "This loan is no longer cancellable");
    
    // We set its validity date as block.timestamp
    loans[loanId].loanEnd = block.timestamp;
    loans[loanId].status = Status.CANCELLED;

    // We send the items back to him
    _transferItems(
      address(this), 
      loans[loanId].borrower, 
      loans[loanId].nftAddressArray, 
      loans[loanId].nftTokenIdArray
    );

    emit LoanCancelled(
      loanId,
      block.timestamp,
      Status.CANCELLED
    );
  }

  // Borrower pays installment for loan
  // Multiple installments : OK
  function payLoan(uint256 loanId, uint256 amountPaidAsInstallment) external {
    require(loans[loanId].borrower == msg.sender, "You're not the borrower of this loan");
    require(loans[loanId].status == Status.APPROVED, "Incorrect state of loan");
    require(loans[loanId].loanEnd >= block.timestamp, "Loan validity expired");
    
    // Check how much is payed
    require(amountPaidAsInstallment >= loans[loanId].installmentAmount, "Installment amount is too low");

    // Transfer the ether
    IERC20(loans[loanId].currency).transferFrom(
      msg.sender,
      loans[loanId].lender, 
      amountPaidAsInstallment
    );

    IERC20(loans[loanId].currency).transferFrom(
      msg.sender,
      owner(), 
      loans[loanId].installmentAmount.div(20)
    );

    loans[loanId].paidAmount = loans[loanId].paidAmount.add(amountPaidAsInstallment);
    loans[loanId].installmentsPayed = loans[loanId].paidAmount.div(loans[loanId].nrOfInstallments);

    if (loans[loanId].paidAmount >= loans[loanId].amountDue)
      loans[loanId].status = Status.LIQUIDATED;

    emit LoanPayment(
      loanId,
      block.timestamp,
      amountPaidAsInstallment,
      Status.APPROVED
    );
  }



  // Borrower can withdraw loan items if loan is LIQUIDATED
  // Lender can withdraw loan item is loan is DEFAULTED
  function withdrawItems(uint256 loanId) external {
    require(block.timestamp >= loans[loanId].loanEnd || loans[loanId].paidAmount == loans[loanId].amountDue, "The loan is not finished yet");
    require(loans[loanId].status == Status.LIQUIDATED || loans[loanId].status == Status.APPROVED, "Incorrect state of loan");

    if ((block.timestamp >= loans[loanId].loanEnd) && !(loans[loanId].paidAmount == loans[loanId].amountDue)) {

      loans[loanId].status = Status.DEFAULTED;
      
      // We send the items back to him
      _transferItems(
        address(this),
        loans[loanId].lender,
        loans[loanId].nftAddressArray,
        loans[loanId].nftTokenIdArray
      );

    } else if (loans[loanId].paidAmount == loans[loanId].amountDue) {

      // Otherwise the lender will receive the items
      _transferItems(
        address(this),
        loans[loanId].borrower,
        loans[loanId].nftAddressArray,
        loans[loanId].nftTokenIdArray
      );
        
    }

    emit ItemsWithdrawn(
      loanId,
      msg.sender,
      Status.LIQUIDATED
    );

  }


  

  // Internal Functions 

  // Calculates loan to value ratio
  function _percent(uint256 numerator, uint256 denominator, uint256 precision) internal pure returns(uint256) {
    // (((numerator * 10 ** (precision + 1)) / denominator) + 5) / 10;
    return numerator.mul(10 ** (precision + 1)).div(denominator).add(5).div(10);
  }

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

  // TODO validate input
  function setLtv(uint256 newLtv) external onlyOwner {
    ltv = newLtv;
    emit LtvChanged(newLtv);
  }

  // TODO validate input
  function setInterestRateToCompany(uint256 newInterestRateToCompany) external onlyOwner {
    interestRateToCompany = newInterestRateToCompany;
    emit InterestRateToCompanyChanged(newInterestRateToCompany);
  }

  // TODO validate input
  function setLoanFee(uint256 newLoanFee) external onlyOwner {
    require(loanFee >= 0 && loanFee < 100, "Loan fee out of bounds");
    loanFee = newLoanFee;
  }


  // Auxiliary functions

  // Returns loan by id, ommits nrOfInstallments as the stack was too deep and we can derive it in the backend
  function getLoanById(uint256 loanId) 
    external
    view
    returns(
      uint256 id,
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
      
      id = uint256(loan.id);
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

  function updateLoanStatus(uint256 loanId) external returns(uint256,uint256){
      require(loans[loanId].status == Status.APPROVED);
      if ( block.timestamp > loans[loanId].loanStart.add(loans[loanId].installmentsPayed.mul(1 days)) )
        return (block.timestamp,loans[loanId].loanStart.add(loans[loanId].installmentsPayed.mul(1 days)));
  }

  function getNextPaymentDate(uint256 loanId) public returns(uint256) {
      return loans[loanId].loanEnd.sub(loans[loanId].installmentsPayed.mul(installmentFrequency.mul(1 days)));
  }

  // TODO: Add auxiliary loan status update function for DEFAULTED state to be used by whomever

}