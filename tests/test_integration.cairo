use cngn::cngn2::{ICngn2Dispatcher, ICngn2DispatcherTrait};
use cngn::forwarder::{IForwarderDispatcher, IForwarderDispatcherTrait, ForwardRequest};
use cngn::interface::IOperations::{IAdminDispatcher, IAdminDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::{ContractAddress, contract_address_const};

// ========== HELPERS ==========

fn deploy_operations2(owner: ContractAddress) -> ContractAddress {
    let contract = declare("Operations2").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (addr, _) = contract.deploy(@constructor_args).unwrap();
    addr
}

fn deploy_forwarder(admin_ops: ContractAddress, owner: ContractAddress) -> ContractAddress {
    let contract = declare("Forwarder").unwrap().contract_class();
    let constructor_args = array![admin_ops.into(), owner.into()];
    let (addr, _) = contract.deploy(@constructor_args).unwrap();
    addr
}

fn deploy_cngn2(
    forwarder: ContractAddress, admin_ops: ContractAddress, owner: ContractAddress,
) -> ContractAddress {
    let contract = declare("Cngn2").unwrap().contract_class();
    let constructor_args = array![forwarder.into(), admin_ops.into(), owner.into()];
    let (addr, _) = contract.deploy(@constructor_args).unwrap();
    addr
}

fn owner() -> ContractAddress {
    contract_address_const::<'OWNER'>()
}

fn minter() -> ContractAddress {
    contract_address_const::<'MINTER'>()
}

fn user1() -> ContractAddress {
    contract_address_const::<'USER1'>()
}

fn user2() -> ContractAddress {
    contract_address_const::<'USER2'>()
}

fn recipient() -> ContractAddress {
    contract_address_const::<'RECIPIENT'>()
}

/// Deploys Operations2, Forwarder, and Cngn2 wired together as in production.
/// Adds Cngn2 as a trusted contract on Operations2 so cross-contract calls
/// (e.g. remove_can_mint during mint) succeed.
fn deploy_full_stack() -> (ContractAddress, ContractAddress, ContractAddress) {
    let owner_addr = owner();
    let ops = deploy_operations2(owner_addr);
    let fwd = deploy_forwarder(ops, owner_addr);
    let cngn = deploy_cngn2(fwd, ops, owner_addr);

    let admin = IAdminDispatcher { contract_address: ops };
    start_cheat_caller_address(ops, owner_addr);
    admin.add_trusted_contract(cngn);
    stop_cheat_caller_address(ops);

    (ops, fwd, cngn)
}

// ========== CNGN2 + OPERATIONS2: MINT FLOW ==========

#[test]
fn test_integration_full_mint_flow() {
    let (ops, _fwd, cngn) = deploy_full_stack();
    let owner_addr = owner();
    let minter_addr = minter();
    let mint_amount: u256 = 5_000_000;

    let admin = IAdminDispatcher { contract_address: ops };
    let token = ICngn2Dispatcher { contract_address: cngn };

    // Owner authorizes minter on Operations2
    start_cheat_caller_address(ops, owner_addr);
    admin.add_can_mint(minter_addr);
    admin.add_mint_amount(minter_addr, mint_amount);
    stop_cheat_caller_address(ops);

    assert(admin.can_mint(minter_addr), 'Minter should be authorized');
    assert(admin.mint_amount(minter_addr) == mint_amount, 'Mint amount should match');

    // Minter mints via Cngn2 (cross-contract: Cngn2 checks + calls remove_can_mint on Operations2)
    start_cheat_caller_address(cngn, minter_addr);
    let result = token.mint(mint_amount, recipient());
    stop_cheat_caller_address(cngn);

    assert(result, 'Mint should succeed');
    assert(token.balance_of(recipient()) == mint_amount, 'Recipient balance wrong');
    assert(token.total_supply() == mint_amount, 'Supply should increase');

    // Verify mint auth was revoked via cross-contract remove_can_mint
    assert(!admin.can_mint(minter_addr), 'Mint auth should be revoked');
    assert(admin.mint_amount(minter_addr) == 0, 'Mint amount should be reset');
}

#[test]
#[should_panic(expected: 'Minter not authorized')]
fn test_integration_mint_auth_single_use() {
    let (ops, _fwd, cngn) = deploy_full_stack();
    let owner_addr = owner();
    let minter_addr = minter();
    let amount: u256 = 1_000_000;

    let admin = IAdminDispatcher { contract_address: ops };
    let token = ICngn2Dispatcher { contract_address: cngn };

    start_cheat_caller_address(ops, owner_addr);
    admin.add_can_mint(minter_addr);
    admin.add_mint_amount(minter_addr, amount);
    stop_cheat_caller_address(ops);

    // First mint succeeds
    start_cheat_caller_address(cngn, minter_addr);
    token.mint(amount, recipient());
    stop_cheat_caller_address(cngn);

    // Second mint fails: auth was revoked by the first mint's cross-contract remove_can_mint
    start_cheat_caller_address(cngn, minter_addr);
    token.mint(amount, recipient());
    stop_cheat_caller_address(cngn);
}

// ========== CNGN2 + OPERATIONS2: TRANSFER REDEMPTION BURN ==========

#[test]
fn test_integration_transfer_redemption_burn() {
    let (ops, _fwd, cngn) = deploy_full_stack();
    let owner_addr = owner();
    let sender_addr = user1();
    let internal_user = user2();
    let mint_amount: u256 = 10_000_000;
    let transfer_amount: u256 = 3_000_000;

    let admin = IAdminDispatcher { contract_address: ops };
    let token = ICngn2Dispatcher { contract_address: cngn };

    // Mint tokens to sender
    start_cheat_caller_address(ops, owner_addr);
    admin.add_can_mint(sender_addr);
    admin.add_mint_amount(sender_addr, mint_amount);
    stop_cheat_caller_address(ops);

    start_cheat_caller_address(cngn, sender_addr);
    token.mint(mint_amount, sender_addr);
    stop_cheat_caller_address(cngn);

    // Whitelist sender as external sender and recipient as internal user
    start_cheat_caller_address(ops, owner_addr);
    admin.whitelist_external_sender(sender_addr);
    admin.whitelist_internal_user(internal_user);
    stop_cheat_caller_address(ops);

    // Transfer from whitelisted external sender to whitelisted internal user triggers burn
    start_cheat_caller_address(cngn, sender_addr);
    token.transfer(internal_user, transfer_amount);
    stop_cheat_caller_address(cngn);

    // Tokens were transferred then burned
    assert(token.balance_of(internal_user) == 0, 'Burned tokens should be 0');
    assert(
        token.balance_of(sender_addr) == mint_amount - transfer_amount, 'Sender balance wrong',
    );
    assert(token.total_supply() == mint_amount - transfer_amount, 'Supply should decrease');
}

#[test]
fn test_integration_transfer_from_redemption_burn() {
    let (ops, _fwd, cngn) = deploy_full_stack();
    let owner_addr = owner();
    let sender_addr = user1();
    let spender = minter();
    let internal_user = user2();
    let mint_amount: u256 = 10_000_000;
    let transfer_amount: u256 = 4_000_000;

    let admin = IAdminDispatcher { contract_address: ops };
    let token = ICngn2Dispatcher { contract_address: cngn };

    // Mint tokens to sender
    start_cheat_caller_address(ops, owner_addr);
    admin.add_can_mint(sender_addr);
    admin.add_mint_amount(sender_addr, mint_amount);
    stop_cheat_caller_address(ops);

    start_cheat_caller_address(cngn, sender_addr);
    token.mint(mint_amount, sender_addr);
    stop_cheat_caller_address(cngn);

    // Sender approves spender
    start_cheat_caller_address(cngn, sender_addr);
    token.approve(spender, transfer_amount);
    stop_cheat_caller_address(cngn);

    // Whitelist for redemption
    start_cheat_caller_address(ops, owner_addr);
    admin.whitelist_external_sender(sender_addr);
    admin.whitelist_internal_user(internal_user);
    stop_cheat_caller_address(ops);

    // Spender calls transfer_from: should trigger burn path
    start_cheat_caller_address(cngn, spender);
    token.transfer_from(sender_addr, internal_user, transfer_amount);
    stop_cheat_caller_address(cngn);

    assert(token.balance_of(internal_user) == 0, 'Burned tokens should be 0');
    assert(
        token.balance_of(sender_addr) == mint_amount - transfer_amount, 'Sender balance wrong',
    );
    assert(token.total_supply() == mint_amount - transfer_amount, 'Supply should decrease');
}

#[test]
fn test_integration_transfer_no_burn_without_whitelist() {
    let (ops, _fwd, cngn) = deploy_full_stack();
    let owner_addr = owner();
    let sender_addr = user1();
    let receiver = user2();
    let mint_amount: u256 = 10_000_000;
    let transfer_amount: u256 = 3_000_000;

    let admin = IAdminDispatcher { contract_address: ops };
    let token = ICngn2Dispatcher { contract_address: cngn };

    // Mint tokens to sender
    start_cheat_caller_address(ops, owner_addr);
    admin.add_can_mint(sender_addr);
    admin.add_mint_amount(sender_addr, mint_amount);
    stop_cheat_caller_address(ops);

    start_cheat_caller_address(cngn, sender_addr);
    token.mint(mint_amount, sender_addr);
    stop_cheat_caller_address(cngn);

    // Transfer without whitelisting: no burn
    start_cheat_caller_address(cngn, sender_addr);
    token.transfer(receiver, transfer_amount);
    stop_cheat_caller_address(cngn);

    assert(token.balance_of(receiver) == transfer_amount, 'Receiver should have tokens');
    assert(token.total_supply() == mint_amount, 'Supply should not change');
}

// ========== CNGN2 + OPERATIONS2: BLACKLIST ENFORCEMENT ==========

#[test]
#[should_panic(expected: 'Caller is blacklisted')]
fn test_integration_mint_blacklisted_caller() {
    let (ops, _fwd, cngn) = deploy_full_stack();
    let owner_addr = owner();
    let evil_minter = user1();

    let admin = IAdminDispatcher { contract_address: ops };
    let token = ICngn2Dispatcher { contract_address: cngn };

    // Authorize minter then blacklist
    start_cheat_caller_address(ops, owner_addr);
    admin.add_can_mint(evil_minter);
    admin.add_mint_amount(evil_minter, 1_000_000);
    admin.add_black_list(evil_minter);
    stop_cheat_caller_address(ops);

    start_cheat_caller_address(cngn, evil_minter);
    token.mint(1_000_000, recipient());
    stop_cheat_caller_address(cngn);
}

#[test]
#[should_panic(expected: 'Receiver is blacklisted')]
fn test_integration_mint_blacklisted_receiver() {
    let (ops, _fwd, cngn) = deploy_full_stack();
    let owner_addr = owner();
    let minter_addr = minter();
    let evil_receiver = user1();

    let admin = IAdminDispatcher { contract_address: ops };
    let token = ICngn2Dispatcher { contract_address: cngn };

    start_cheat_caller_address(ops, owner_addr);
    admin.add_can_mint(minter_addr);
    admin.add_mint_amount(minter_addr, 1_000_000);
    admin.add_black_list(evil_receiver);
    stop_cheat_caller_address(ops);

    start_cheat_caller_address(cngn, minter_addr);
    token.mint(1_000_000, evil_receiver);
    stop_cheat_caller_address(cngn);
}

#[test]
fn test_integration_destroy_black_funds_after_mint() {
    let (ops, _fwd, cngn) = deploy_full_stack();
    let owner_addr = owner();
    let evil_user = user1();
    let mint_amount: u256 = 5_000_000;

    let admin = IAdminDispatcher { contract_address: ops };
    let token = ICngn2Dispatcher { contract_address: cngn };

    // Mint tokens to user
    start_cheat_caller_address(ops, owner_addr);
    admin.add_can_mint(evil_user);
    admin.add_mint_amount(evil_user, mint_amount);
    stop_cheat_caller_address(ops);

    start_cheat_caller_address(cngn, evil_user);
    token.mint(mint_amount, evil_user);
    stop_cheat_caller_address(cngn);

    assert(token.balance_of(evil_user) == mint_amount, 'Should have tokens');

    // Blacklist and destroy funds (cross-contract: Cngn2 reads blacklist from Operations2)
    start_cheat_caller_address(ops, owner_addr);
    admin.add_black_list(evil_user);
    stop_cheat_caller_address(ops);

    start_cheat_caller_address(cngn, owner_addr);
    token.destroy_black_funds(evil_user);
    stop_cheat_caller_address(cngn);

    assert(token.balance_of(evil_user) == 0, 'Funds should be destroyed');
    assert(token.total_supply() == 0, 'Supply should decrease');
}

// ========== FORWARDER + OPERATIONS2: BLACKLIST ENFORCEMENT ==========

#[test]
#[should_panic(expected: 'Route not allowed')]
fn test_integration_forwarder_rejects_non_forwardable() {
    let (_ops, fwd, cngn) = deploy_full_stack();
    let owner_addr = owner();
    let unauthorized = user1();

    let forwarder = IForwarderDispatcher { contract_address: fwd };

    let req = ForwardRequest {
        from: unauthorized, to: cngn, value: 0_u256, gas: 0_u256, nonce: 0, data: array![].span(),
    };

    start_cheat_caller_address(fwd, owner_addr);
    forwarder.execute(req, array![].span());
    stop_cheat_caller_address(fwd);
}

#[test]
#[should_panic(expected: 'Signer blacklisted')]
fn test_integration_forwarder_rejects_blacklisted_signer() {
    let (ops, fwd, cngn) = deploy_full_stack();
    let owner_addr = owner();
    let signer = user1();

    let admin = IAdminDispatcher { contract_address: ops };
    let forwarder = IForwarderDispatcher { contract_address: fwd };

    // Whitelist signer for forwarding, then blacklist
    start_cheat_caller_address(ops, owner_addr);
    admin.add_can_forward(signer);
    admin.add_black_list(signer);
    stop_cheat_caller_address(ops);

    let req = ForwardRequest {
        from: signer, to: cngn, value: 0_u256, gas: 0_u256, nonce: 0, data: array![].span(),
    };

    start_cheat_caller_address(fwd, owner_addr);
    forwarder.execute(req, array![].span());
    stop_cheat_caller_address(fwd);
}

#[test]
#[should_panic(expected: 'Relayer blacklisted')]
fn test_integration_forwarder_rejects_blacklisted_relayer() {
    let (ops, fwd, cngn) = deploy_full_stack();
    let owner_addr = owner();
    let bridge_addr = contract_address_const::<'BRIDGE'>();
    let signer = user1();

    let admin = IAdminDispatcher { contract_address: ops };
    let forwarder = IForwarderDispatcher { contract_address: fwd };

    // Setup: whitelist signer, authorize bridge, then blacklist bridge
    start_cheat_caller_address(ops, owner_addr);
    admin.add_can_forward(signer);
    stop_cheat_caller_address(ops);

    start_cheat_caller_address(fwd, owner_addr);
    forwarder.authorize_bridge(bridge_addr);
    stop_cheat_caller_address(fwd);

    start_cheat_caller_address(ops, owner_addr);
    admin.add_black_list(bridge_addr);
    stop_cheat_caller_address(ops);

    let req = ForwardRequest {
        from: signer, to: cngn, value: 0_u256, gas: 0_u256, nonce: 0, data: array![].span(),
    };

    start_cheat_caller_address(fwd, bridge_addr);
    forwarder.execute_by_bridge(req, array![].span());
    stop_cheat_caller_address(fwd);
}
