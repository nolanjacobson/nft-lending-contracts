// SPDX-License-Identifier: MIT

/* 
 * Stater.co
 */
pragma solidity 0.7.4;

import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";

contract LendingLogic is Ownable {

    using SafeMath for uint256;
    uint256 public constant PRECISION = 3;
    uint256 public ltv = 600; // 60%
    uint256 public installmentFrequency = 7; // days
    uint256 public interestRate = 20;
    uint256 public interestRateToStater = 40;
    address public LendingData;
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

    modifier isAuthorized {
        require(msg.sender == LendingData);
    }

    function changeLendingData(address lendingData) external onlyOwner {
        LendingData = lendingData;
    }

    // Calculates loan to value ratio
    function percent(uint256 numerator, uint256 denominator, uint256 precision) public pure returns(uint256) {
        return numerator.mul(10 ** (precision + 1)).div(denominator).add(5).div(10);
    }

    // Borrower creates a loan
    function createLoanVerification(
        Loan loan
    ) external isAuthorized returns(uint256, uint256, uint256) {
        require(loan.nrOfInstallments > 0, "Loan must include at least 1 installment");
        require(loan.loanAmount > 0, "Loan amount must be higher than 0");

        // Compute loan to value ratio for current loan application
        require(percent(loan.loanAmount, loan.assetsValue, PRECISION) <= ltv, "LTV exceeds maximum limit allowed");

        // Transfer the items from lender to stater contract >> LendingData
        _transferItems(loan.borrower, address(msg.sender), loan.nftAddressArray, loan.nftTokenIdArray);

        // Computing the defaulting limit
        uint256 defaultingLimit = 1;
        if ( loan.nrOfInstallments <= 3 )
            defaultingLimit = 1;
        else if ( loan.nrOfInstallments <= 5 )
            defaultingLimit = 2;
        else if ( loan.nrOfInstallments >= 6 )
            defaultingLimit = 3;

        // Computing loan parameters
        uint256 loanPlusInterest = loan.loanAmount.mul(interestRate.add(100)).div(100); // interest rate >> 20%
        uint256 installmentAmount = loanPlusInterest.div(loan.nrOfInstallments);

        return(defaultingLimit,loanPlusInterest,installmentAmount);

    }


    // Lender approves a loan
    function approveLoanVerification(
        Loan loan
    ) external isAuthorized payable returns(uint256,uint256){
        require(loan.lender == address(0), "Someone else payed for this loan before you");
        require(loan.paidAmount == 0, "This loan is currently not ready for lenders");
        require(loan.status == Status.LISTED, "This loan is not currently ready for lenders, check later");

        // msg.value provides the qty of ether sent to smart contract , not good for custom erc20 tokens
        require(loan.currency != address(0) || msg.value >= loan.loanAmount.add(loan.loanAmount.div(100)),"Not enough currency");

        // here we transfer the erc20 tokens / ether
        _transferTokens(loan.lender,loan.borrower,loan.currency,loan.loanAmount);

        return (block.timestamp,block.timestamp.add(loan.nrOfInstallments.mul(installmentFrequency).mul(1 days)));
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
    function payLoan(uint256 loanId) external payable {
        require(loans[loanId].borrower == msg.sender, "You're not the borrower of this loan");
        require(loans[loanId].status == Status.APPROVED, "This loan is no longer in the approval phase, check its status");
        require(loans[loanId].loanEnd >= block.timestamp, "Loan validity expired");
        require(msg.value >= loans[loanId].installmentAmount, "Not enough currency");
        
        uint256 interestPerInstallement = msg.value.mul(interestRate).div(100).div(loans[loanId].nrOfInstallments); // entire interest for installment
        uint256 interestToStaterPerInstallement = interestPerInstallement.mul(interestRateToStater).div(100); // amount of interest that goes to Stater on each installment
        uint256 amountPaidAsInstallmentToLender = msg.value.sub(interestToStaterPerInstallement); // amount of installment that goes to lender
        
        if ( loans[loanId].currency != address(0) ) {
        require(IERC20(loans[loanId].currency).transferFrom(
            msg.sender,
            loans[loanId].lender, 
            amountPaidAsInstallmentToLender
        ), "Installment transfer failed");
        require(IERC20(loans[loanId].currency).transferFrom(
            msg.sender,
            owner(),
            interestToStaterPerInstallement
        ), "Installment transfer failed");
        } else {
        require(loans[loanId].lender.send(amountPaidAsInstallmentToLender), "Installment transfer to lender failed");
        require(payable(owner()).send(interestToStaterPerInstallement), "Installment transfer to stater failed");
        }

        loans[loanId].paidAmount = loans[loanId].paidAmount.add(msg.value);
        loans[loanId].nrOfPayments = loans[loanId].paidAmount.div(loans[loanId].installmentAmount);

        if (loans[loanId].paidAmount >= loans[loanId].amountDue)
        loans[loanId].status = Status.LIQUIDATED;

        emit LoanPayment(
        loanId,
        block.timestamp,
        msg.value,
        amountPaidAsInstallmentToLender,
        interestPerInstallement,
        interestToStaterPerInstallement,
        loans[loanId].status
        );
    }



    // Borrower can withdraw loan items if loan is LIQUIDATED
    // Lender can withdraw loan item is loan is DEFAULTED
    function withdrawItems(uint256 loanId) external {
        require(block.timestamp >= loans[loanId].loanEnd || loans[loanId].paidAmount >= loans[loanId].amountDue, "The loan is not finished yet");
        require(loans[loanId].status == Status.LIQUIDATED || loans[loanId].status == Status.APPROVED, "Incorrect state of loan");

        if ( (block.timestamp >= loans[loanId].loanEnd) && !(loans[loanId].paidAmount >= loans[loanId].amountDue) ) {

        loans[loanId].status = Status.DEFAULTED;
        
        // We send the items back to him
        _transferItems(
            address(this),
            loans[loanId].lender,
            loans[loanId].nftAddressArray,
            loans[loanId].nftTokenIdArray
        );

        } else if ( loans[loanId].paidAmount >= loans[loanId].amountDue ) {

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
        loans[loanId].status
        );

    }

    function terminateLoan(uint256 loanId) external {
        require(msg.sender == loans[loanId].borrower || msg.sender == loans[loanId].lender, "You can't access this loan");
        require(loans[loanId].status == Status.APPROVED, "Loan must be approved");
        require(lackOfPayment(loanId), "Borrower still has time to pay his installments");

        // The lender will take the items
        _transferItems(
        address(this),
        loans[loanId].lender,
        loans[loanId].nftAddressArray,
        loans[loanId].nftTokenIdArray
        );

        loans[loanId].status = Status.DEFAULTED;
        loans[loanId].loanEnd = block.timestamp;

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

    function _transferTokens(
        address from,
        address to,
        address currency,
        uint256 quantity
    ) internal {
        if ( currency != address(0) ){

            require(IERC20(currency).transferFrom(
                from,
                to, 
                quantity
            ), "Transfer of liquidity failed"); // Transfer complete loanAmount to borrower

            require(IERC20(currency).transferFrom(
                from,
                owner(), 
                quantity.div(100)
            ), "Transfer of liquidity failed"); // 1% of original loanAmount goes to contract owner

        }else{

            require(to.send(quantity),"Transfer of liquidity failed");
            require(payable(owner()).send(quantity.div(100)),"Transfer of liquidity failed");

        }
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

    // TODO validate input
    function setLtv(uint256 newLtv) external onlyOwner {
        ltv = newLtv;
        emit LtvChanged(newLtv);
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

}
