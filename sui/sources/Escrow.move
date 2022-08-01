// SPDX-License-Identifier: MIT

/// @title Escrow
/// @dev Basic escrow module: holds an object designated for a recipient until the sender approves withdrawal.
module Movemate::Escrow {
    use sui::object::{Self, Info};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    struct Escrow<T: store> has key {
        info: Info,
        recipient: address,
        obj: T
    }

    /// @dev Stores the sent object in an escrow object.
    /// @param recipient The destination address of the escrowed object.
    public entry fun escrow<T: store>(sender: address, recipient: address, obj_in: T, ctx: &mut TxContext) {
        let escrow = Escrow<T> {
            info: object::new(ctx),
            recipient,
            obj: obj_in
        };
        transfer::transfer(escrow, sender);
    }

    /// @dev Withdraw escrowed objected to the recipient.
    public entry fun withdraw<T: store>(escrow: Escrow<T>, ctx: &mut TxContext): T {
        let Escrow {
            info: info,
            recipient: recipient,
            obj: obj,
        } = escrow;
        assert!(recipient == tx_context::sender(ctx), 1000);
        object::delete(info);
        obj
    }

    /// @dev Transfers escrowed objected to the recipient.
    public entry fun transfer<T: key + store>(escrow: Escrow<T>) {
        let Escrow {
            info: info,
            recipient: recipient,
            obj: obj,
        } = escrow;
        object::delete(info);
        transfer::transfer(obj, recipient);
    }
}
