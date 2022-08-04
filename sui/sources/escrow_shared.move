// SPDX-License-Identifier: MIT

/// @title escrow_shared
/// @dev Basic escrow module with refunds and an arbitrator: holds an object designated for a recipient until the sender approves withdrawal, the recipient refunds the sender, or the arbitrator does one of the two.
module movemate::escrow_shared {
    use std::errors;
    use std::option::{Self, Option};

    use sui::object::{Self, Info};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    /// @dev When trying to transfer escrowed object to the recipient but you are not the sender.
    const ENOT_SENDER: u64 = 0;

    /// @dev When trying to refund escrowed object to the sender but you are not the recipient.
    const ENOT_RECIPIENT: u64 = 1;

    /// @dev When trying to arbitrate an escrowed object but you are not the arbitrator.
    const ENOT_ARBITRATOR: u64 = 2;

    struct Escrow<T: key + store> has key {
        info: Info,
        sender: address,
        recipient: address,
        arbitrator: Option<address>,
        obj: T
    }

    /// @dev Stores the sent object in an escrow object.
    /// @param recipient The destination address of the escrowed object.
    public entry fun escrow<T: key + store>(sender: address, recipient: address, arbitrator: Option<address>, obj_in: T, ctx: &mut TxContext) {
        let escrow = Escrow<T> {
            info: object::new(ctx),
            sender,
            recipient,
            arbitrator,
            obj: obj_in
        };
        transfer::share_object(escrow);
    }

    /// @dev Transfers escrowed object to the recipient.
    public entry fun transfer<T: key + store>(escrow: Escrow<T>, ctx: &mut TxContext) {
        let Escrow {
            info: info,
            sender: sender,
            recipient: recipient,
            arbitrator: _,
            obj: obj,
        } = escrow;
        assert!(tx_context::sender(ctx) == sender, errors::requires_address(ENOT_SENDER));
        object::delete(info);
        transfer::transfer(obj, recipient);
    }

    /// @dev Refunds escrowed object to the sender.
    public entry fun refund<T: key + store>(escrow: Escrow<T>, ctx: &mut TxContext) {
        let Escrow {
            info: info,
            sender: sender,
            recipient: recipient,
            arbitrator: _,
            obj: obj,
        } = escrow;
        assert!(tx_context::sender(ctx) == recipient, errors::requires_address(ENOT_RECIPIENT));
        object::delete(info);
        transfer::transfer(obj, sender);
    }

    /// @dev Transfers escrowed object to the recipient.
    public entry fun transfer_arbitrated<T: key + store>(escrow: Escrow<T>, ctx: &mut TxContext) {
        let Escrow {
            info: info,
            sender: _,
            recipient: recipient,
            arbitrator: arbitrator,
            obj: obj,
        } = escrow;
        assert!(option::is_some(&arbitrator) && tx_context::sender(ctx) == option::destroy_some(arbitrator), errors::requires_address(ENOT_ARBITRATOR));
        object::delete(info);
        transfer::transfer(obj, recipient);
    }

    /// @dev Refunds escrowed object to the sender.
    public entry fun refund_arbitrated<T: key + store>(escrow: Escrow<T>, ctx: &mut TxContext) {
        let Escrow {
            info: info,
            sender: sender,
            recipient: _,
            arbitrator: arbitrator,
            obj: obj,
        } = escrow;
        assert!(option::is_some(&arbitrator) && tx_context::sender(ctx) == option::destroy_some(arbitrator), errors::requires_address(ENOT_ARBITRATOR));
        object::delete(info);
        transfer::transfer(obj, sender);
    }
}
