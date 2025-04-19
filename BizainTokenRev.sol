// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title BizainToken - Token BEP-20 Sempurna dengan Fitur Canggih
/// @notice Token ini mencakup mint, burn, blacklist, pausability, transfer fee, anti-whale, anti-bot cooldown,
/// snapshot untuk governance, airdrop, timelock pada fungsi kritis, serta role-based access (admin)
contract BizainToken {
    // --- Token Basic Data ---
    string public name = "Bizains";
    string public symbol = "BIZN";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    // --- Ownership & Administration ---
    address public owner;
    mapping(address => bool) public admins;

    // --- Fee & Anti-Whale Settings ---
    uint256 public transferFee = 2; // 2% fee
    address public feeRecipient;
    uint256 public maxTxAmount;

    // --- Pausability & Blacklist ---
    bool public paused = false;
    mapping(address => bool) public blacklist;

    // --- Anti-Bot Cooldown ---
    uint256 public cooldownTime = 30;
    mapping(address => uint256) public lastTransferTime;

    // --- ERC20 Standard Mappings ---
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // --- Snapshot Mechanism ---
    struct Snapshot {
        uint256 id;
        uint256 value;
    }
    mapping(address => Snapshot[]) private accountSnapshots;
    Snapshot[] private totalSupplySnapshots;
    uint256 public currentSnapshotId;

    // --- Timelock Mechanism ---
    mapping(bytes32 => uint256) public timelocks;
    uint256 public timelockDelay = 1 days;

    // --- Events ---
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);
    event Blacklisted(address indexed account);
    event Unblacklisted(address indexed account);
    event Paused();
    event Unpaused();
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event AdminAdded(address indexed account);
    event AdminRemoved(address indexed account);
    event TransferFeeUpdated(uint256 newFee);
    event FeeRecipientUpdated(address newRecipient);
    event MaxTxAmountUpdated(uint256 newMaxTx);
    event SnapshotCreated(uint256 id);
    event AirdropExecuted(uint256 totalRecipients, uint256 totalAmount);
    event TimelockScheduled(bytes32 indexed functionId, uint256 unlockTime);

    // --- Modifiers ---
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyAdminOrOwner() {
        require(msg.sender == owner || admins[msg.sender], "Only admin or owner");
        _;
    }

    modifier notBlacklisted(address account) {
        require(!blacklist[account], "Blacklisted");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }

    modifier antiBot(address sender) {
        if (sender != owner && !admins[sender]) {
            require(block.timestamp - lastTransferTime[sender] >= cooldownTime, "Cooldown active");
            lastTransferTime[sender] = block.timestamp;
        }
        _;
    }

    modifier onlyAfterTimelock(bytes32 functionId) {
        require(block.timestamp >= timelocks[functionId], "Function is timelocked");
        _;
    }

    // --- Constructor ---
    constructor() {
        owner = msg.sender;
        feeRecipient = msg.sender;
        admins[msg.sender] = true;
        _mint(msg.sender, 500_000_000 * 10 ** decimals);
    }

    // --- Internal Functions ---
    function _mint(address to, uint256 amount) internal {
        require(to != address(0), "Cannot mint to zero address");
        totalSupply += amount;
        balanceOf[to] += amount;
        maxTxAmount = totalSupply / 100;
        emit Transfer(address(0), to, amount);
        emit Mint(to, amount);
        _updateAccountSnapshot(to);
        _updateTotalSupplySnapshot();
    }

    function _burn(address from, uint256 amount) internal {
        require(balanceOf[from] >= amount, "Insufficient balance");
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
        emit Burn(from, amount);
        _updateAccountSnapshot(from);
        _updateTotalSupplySnapshot();
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(to != address(0), "Invalid recipient");

        if (from != owner && to != owner && !admins[from] && !admins[to]) {
            require(amount <= maxTxAmount, "Exceeds max transaction limit");
            uint256 fee = (amount * transferFee) / 100;
            uint256 netAmount = amount - fee;
            balanceOf[from] -= amount;
            balanceOf[to] += netAmount;
            balanceOf[feeRecipient] += fee;
            emit Transfer(from, to, netAmount);
            emit Transfer(from, feeRecipient, fee);
        } else {
            balanceOf[from] -= amount;
            balanceOf[to] += amount;
            emit Transfer(from, to, amount);
        }

        _updateAccountSnapshot(from);
        _updateAccountSnapshot(to);
    }

    // --- External Functions: Token Operations ---
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) external whenNotPaused notBlacklisted(msg.sender) {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) external onlyOwner {
        _burn(account, amount);
    }

    function transfer(address to, uint256 amount) external whenNotPaused notBlacklisted(msg.sender) notBlacklisted(to) antiBot(msg.sender) returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external whenNotPaused returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external whenNotPaused notBlacklisted(from) notBlacklisted(to) antiBot(from) returns (bool) {
        require(allowance[from][msg.sender] >= amount, "Allowance too low");
        allowance[from][msg.sender] -= amount;
        _transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external whenNotPaused returns (bool) {
        allowance[msg.sender][spender] += addedValue;
        emit Approval(msg.sender, spender, allowance[msg.sender][spender]);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external whenNotPaused returns (bool) {
        require(allowance[msg.sender][spender] >= subtractedValue, "Decreased below zero");
        allowance[msg.sender][spender] -= subtractedValue;
        emit Approval(msg.sender, spender, allowance[msg.sender][spender]);
        return true;
    }

    // --- Snapshot Functions ---
    function snapshot() external onlyAdminOrOwner returns (uint256) {
        currentSnapshotId += 1;
        _updateTotalSupplySnapshot();
        emit SnapshotCreated(currentSnapshotId);
        return currentSnapshotId;
    }

    function _updateAccountSnapshot(address account) internal {
        accountSnapshots[account].push(Snapshot({ id: currentSnapshotId, value: balanceOf[account] }));
    }

    function _updateTotalSupplySnapshot() internal {
        totalSupplySnapshots.push(Snapshot({ id: currentSnapshotId, value: totalSupply }));
    }

    function balanceOfAt(address account, uint256 snapshotId) external view returns (uint256) {
        Snapshot[] storage snapshots = accountSnapshots[account];
        if (snapshots.length == 0) return 0;
        for (uint256 i = snapshots.length; i > 0; i--) {
            if (snapshots[i - 1].id <= snapshotId) return snapshots[i - 1].value;
        }
        return 0;
    }

    function totalSupplyAt(uint256 snapshotId) external view returns (uint256) {
        for (uint256 i = totalSupplySnapshots.length; i > 0; i--) {
            if (totalSupplySnapshots[i - 1].id <= snapshotId) return totalSupplySnapshots[i - 1].value;
        }
        return 0;
    }

    // --- Airdrop ---
    function airdrop(address[] calldata recipients, uint256[] calldata amounts) external onlyAdminOrOwner whenNotPaused {
        require(recipients.length == amounts.length, "Length mismatch");
        uint256 total = 0;
        for (uint256 i = 0; i < amounts.length; i++) total += amounts[i];
        require(balanceOf[msg.sender] >= total, "Not enough balance");
        for (uint256 i = 0; i < recipients.length; i++) {
            _transfer(msg.sender, recipients[i], amounts[i]);
        }
        emit AirdropExecuted(recipients.length, total);
    }

    // --- Blacklist ---
    function blacklistAddress(address account) external onlyAdminOrOwner {
        blacklist[account] = true;
        emit Blacklisted(account);
    }

    function unblacklistAddress(address account) external onlyAdminOrOwner {
        blacklist[account] = false;
        emit Unblacklisted(account);
    }

    // --- Pausability ---
    function pause() external onlyAdminOrOwner {
        paused = true;
        emit Paused();
    }

    function unpause() external onlyAdminOrOwner {
        paused = false;
        emit Unpaused();
    }

    // --- Admin Management ---
    function addAdmin(address account) external onlyOwner {
        admins[account] = true;
        emit AdminAdded(account);
    }

    function removeAdmin(address account) external onlyOwner {
        admins[account] = false;
        emit AdminRemoved(account);
    }

    // --- Ownership ---
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    // --- Fee & Anti-Whale Settings ---
    function scheduleFeeUpdate(uint256 newFee) external onlyOwner {
        require(newFee <= 10, "Max fee 10%");
        bytes32 id = keccak256("setTransferFee");
        timelocks[id] = block.timestamp + timelockDelay;
        emit TimelockScheduled(id, timelocks[id]);
    }

    function setTransferFee(uint256 fee) external onlyOwner onlyAfterTimelock(keccak256("setTransferFee")) {
        require(fee <= 10, "Max fee 10%");
        transferFee = fee;
        emit TransferFeeUpdated(fee);
    }

    function setFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), "Zero address");
        feeRecipient = recipient;
        emit FeeRecipientUpdated(recipient);
    }

    function setMaxTxAmount(uint256 amount) external onlyOwner {
        maxTxAmount = amount;
        emit MaxTxAmountUpdated(amount);
    }

    function setCooldownTime(uint256 secondsDelay) external onlyOwner {
        cooldownTime = secondsDelay;
    }

    function setTimelockDelay(uint256 delaySeconds) external onlyOwner {
        timelockDelay = delaySeconds;
    }
}
