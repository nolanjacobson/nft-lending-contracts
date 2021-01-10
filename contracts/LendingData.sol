// SPDX-License-Identifier: MIT

/* 
 * Stater.co
 */
pragma solidity 0.7.4;
pragma experimental ABIEncoderV2;


import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-solidity/contracts/token/ERC721/ERC721Holder.sol";
import "multi-token-standard/contracts/interfaces/IERC1155.sol";
import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "openzeppelin-solidity/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";


contract LendingLogic is Ownable {

    using SafeMath for uint256;
    uint256 public constant PRECISION = 3;
    uint256 public ltv = 600; // 60%
    uint256 public installmentFrequency = 7; // days
    uint256 public interestRate = 20;
    uint256 public interestRateToStater = 40;
    address public lendingDataAddress;
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

    event ItemsWithdrawn(uint256 indexed loanId, address indexed requester, Status status);
    event LoanPayment(uint256 indexed loanId, uint256 paymentDate, uint256 installmentAmount, uint256 amountPaidAsInstallmentToLender, uint256 interestPerInstallement, uint256 interestToStaterPerInstallement, Status status);
    event LoanApproved(uint256 indexed loanId, address indexed lender, uint256 approvalDate, uint256 loanPaymentEnd, Status status);
    event NewLoan(uint256 indexed loanId, address indexed owner, uint256 creationDate, address indexed currency, Status status, string creationId);
    event LoanCancelled(uint256 indexed loanId, uint256 cancellationDate, Status status);
    event LoanTerminated(uint256 indexed loanId, uint256 terminationDate);
    event LtvChanged(uint256 newLTV);

    modifier isAuthorized {
        require(msg.sender == lendingDataAddress);
        _;
    }

    function changeLendingData(address lendingData) external onlyOwner {
        lendingDataAddress = lendingData;
    }

    // Calculates loan to value ratio
    function percent(uint256 numerator, uint256 denominator, uint256 precision) public pure returns(uint256) {
        return numerator.mul(10 ** (precision + 1)).div(denominator).add(5).div(10);
    }

    // Borrower creates a loan
    function createLoanVerification(
        Loan memory loan,
        uint256 loanId,
        string memory creationId,
        address sender
    ) external isAuthorized {
        
        // Fire event
        require(loan.nrOfInstallments > 0, "Loan must include at least 1 installment");
        require(loan.loanAmount > 0, "Loan amount must be higher than 0");
        require(loan.status == Status.LISTED, "Loan status is not LISTED");

        // Compute loan to value ratio for current loan application
        require(percent(loan.loanAmount, loan.assetsValue, PRECISION) <= ltv, "LTV exceeds maximum limit allowed");

        // Transfer the items from lender to stater contract >> LendingData
        _transferItems(loan.borrower, msg.sender, loan.nftAddressArray, loan.nftTokenIdArray);

        emit NewLoan(loanId, sender, block.timestamp, loan.currency, Status.LISTED, creationId);

    }


    // Lender approves a loan
    function approveLoanVerification(
        Loan memory loan,
        address sender,
        uint loanId
    ) external isAuthorized payable {
        require(loan.lender == address(0), "Someone else payed for this loan before you");
        require(loan.paidAmount == 0, "This loan is currently not ready for lenders");
        require(loan.status == Status.LISTED, "This loan is not currently ready for lenders, check later");

        // msg.value provides the qty of ether sent to smart contract , not good for custom erc20 tokens
        require(loan.currency != address(0) || msg.value >= loan.loanAmount.add(loan.loanAmount.div(100)),"Not enough currency");

        // here we transfer the erc20 tokens / ether
        _transferTokens(loan.lender,loan.borrower,loan.currency,loan.loanAmount,loan.loanAmount.div(100));

        emit LoanApproved(
          loanId,
          sender,
          block.timestamp,
          loan.loanEnd,
          Status.APPROVED
        );

    }
    
    
    // Borrower cancels a loan
    function cancelLoanVerification(
        Loan memory loan,
        uint256 loanId,
        address sender
    ) isAuthorized external {
        require(loan.borrower == sender, "You're not the borrower of this loan");
        require(loan.lender == address(0), "The loan has a lender , it cannot be cancelled");
        require(loan.status != Status.CANCELLED, "This loan is already cancelled");
        require(loan.status == Status.LISTED, "This loan is no longer cancellable");
    
        // We send the items back to him
        _transferItems(
          msg.sender, 
          loan.borrower, 
          loan.nftAddressArray, 
          loan.nftTokenIdArray
        );
        
        emit LoanCancelled(
          loanId,
          block.timestamp,
          Status.CANCELLED
        );
        
    }
    
    
      // Borrower pays installment for loan
      // Multiple installments : OK
      function payLoanVerification(
        Loan memory loan,
        uint256 loanId,
        address sender
      ) isAuthorized external payable {
        require(loan.borrower == sender, "You're not the borrower of this loan");
        require(loan.status == Status.APPROVED, "This loan is no longer in the approval phase, check its status");
        require(loan.loanEnd >= block.timestamp, "Loan validity expired");
        require(msg.value >= loan.installmentAmount, "Not enough currency");
        
        uint256 interestPerInstallement = msg.value.mul(interestRate).div(100).div(loan.nrOfInstallments); // entire interest for installment
        uint256 interestToStaterPerInstallement = interestPerInstallement.mul(interestRateToStater).div(100); // amount of interest that goes to Stater on each installment
        uint256 amountPaidAsInstallmentToLender = msg.value.sub(interestToStaterPerInstallement); // amount of installment that goes to lender
        
        // here we transfer the erc20 tokens / ether
        _transferTokens(loan.borrower,loan.lender,loan.currency,amountPaidAsInstallmentToLender,interestToStaterPerInstallement);
        
        emit LoanPayment(
          loanId,
          block.timestamp,
          msg.value,
          amountPaidAsInstallmentToLender,
          interestPerInstallement,
          interestToStaterPerInstallement,
          loan.status
        );
    
      }
    

      // Borrower can withdraw loan items if loan is LIQUIDATED
      // Lender can withdraw loan item is loan is DEFAULTED
      function withdrawItemsVerification(
          Loan memory loan,
          uint256 loanId,
          address sender
      ) isAuthorized external {
        require(block.timestamp >= loan.loanEnd || loan.paidAmount >= loan.amountDue, "The loan is not finished yet");
        require(loan.status == Status.LIQUIDATED || loan.status == Status.APPROVED, "Incorrect state of loan");
    
        if ( block.timestamp >= loan.loanEnd && loan.paidAmount < loan.amountDue )
          
          // We send the items back to him
          _transferItems(
            msg.sender,
            loan.lender,
            loan.nftAddressArray,
            loan.nftTokenIdArray
          );
    
        else if ( loan.paidAmount >= loan.amountDue )
    
          // Otherwise the lender will receive the items
          _transferItems(
            msg.sender,
            loan.borrower,
            loan.nftAddressArray,
            loan.nftTokenIdArray
          );
            
        
        emit ItemsWithdrawn(
          loanId,
          sender,
          loan.status
        );
    
      }
      
    function terminateLoanVerification(
        Loan memory loan,
        uint256 loanId,
        address sender
    ) isAuthorized external {
        require(sender == loan.borrower || sender == loan.lender, "You can't access this loan");
        require(loan.status == Status.APPROVED, "Loan must be approved");
        require(loan.status == Status.APPROVED && loan.loanStart.add(loan.nrOfPayments.mul(installmentFrequency.mul(1 days))) <= block.timestamp.sub(loan.defaultingLimit.mul(installmentFrequency.mul(1 days))), "Borrower still has time to pay his installments");
    
        // The lender will take the items
        _transferItems(
          msg.sender,
          loan.lender,
          loan.nftAddressArray,
          loan.nftTokenIdArray
        );
    
        emit LoanTerminated(loanId,block.timestamp);
    
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

    function _transferTokens(
        address from,
        address payable to,
        address currency,
        uint256 quantity1,
        uint256 quantity2
    ) internal {
        if ( currency != address(0) ){

            require(IERC20(currency).transferFrom(
                from,
                to, 
                quantity1
            ), "Transfer of liquidity failed"); // Transfer complete loanAmount to borrower

            require(IERC20(currency).transferFrom(
                from,
                owner(), 
                quantity2
            ), "Transfer of liquidity failed"); // 1% of original loanAmount goes to contract owner

        }else{

            require(to.send(quantity1),"Transfer of liquidity failed");
            require(payable(owner()).send(quantity2.div(100)),"Transfer of liquidity failed");

        }
    }
    
      // TODO validate input
      function setLtv(uint256 newLtv) external onlyOwner {
        ltv = newLtv;
        emit LtvChanged(newLtv);
      }

}


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
