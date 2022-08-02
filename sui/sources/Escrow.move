// SPDX-License-Identifier: MIT

/// @title Escrow
/// @dev Basic escrow module: holds an object designated for a recipient until the sender approves withdrawal.
module movemate::escrow {
    use sui::object::{Self, Info};
    use sui::transfer;
    use sui::tx_context::TxContext;

    struct Escrow<T: key + store> has key {
        info: Info,
        recipient: address,
        obj: T
    }

    /// @dev Stores the sent object in an escrow object.
    /// @param recipient The destination address of the escrowed object.
    public entry fun escrow<T: key + store>(sender: address, recipient: address, obj_in: T, ctx: &mut TxContext) {
        let escrow = Escrow<T> {
            info: object::new(ctx),
            recipient,
            obj: obj_in
        };
        transfer::transfer(escrow, sender);
    }

    /// @dev Transfers escrowed object to the recipient.
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
