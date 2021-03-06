(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(*                                                                           *)
(* Permission is hereby granted, free of charge, to any person obtaining a   *)
(* copy of this software and associated documentation files (the "Software"),*)
(* to deal in the Software without restriction, including without limitation *)
(* the rights to use, copy, modify, merge, publish, distribute, sublicense,  *)
(* and/or sell copies of the Software, and to permit persons to whom the     *)
(* Software is furnished to do so, subject to the following conditions:      *)
(*                                                                           *)
(* The above copyright notice and this permission notice shall be included   *)
(* in all copies or substantial portions of the Software.                    *)
(*                                                                           *)
(* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR*)
(* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,  *)
(* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL   *)
(* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER*)
(* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING   *)
(* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER       *)
(* DEALINGS IN THE SOFTWARE.                                                 *)
(*                                                                           *)
(*****************************************************************************)

(** A newly received block is validated by replaying locally the block
    creation, applying each operation and its finalization to ensure their
    consistency. This module is stateless and creates and manupulates the
    prevalidation_state. *)

type prevalidation_state

(** Creates a new prevalidation context w.r.t. the protocol associate to the
    predecessor block . When ?protocol_data is passed to this function, it will
    be used to create the new block *)
val start_prevalidation :
  ?protocol_data: MBytes.t ->
  predecessor: State.Block.t ->
  timestamp: Time.t ->
  unit -> prevalidation_state tzresult Lwt.t

(** Given a prevalidation context applies a list of operations,
    returns a new prevalidation context plus the preapply result containing the
    list of operations that cannot be applied to this context *)
val prevalidate :
  prevalidation_state -> sort:bool ->
  (Operation_hash.t * Operation.t) list ->
  (prevalidation_state * error Preapply_result.t) Lwt.t

val end_prevalidation :
  prevalidation_state ->
  Tezos_protocol_environment_shell.validation_result tzresult Lwt.t

(** Pre-apply creates a new block ( running start_prevalidation, prevalidate and
    end_prevalidation), and returns a new block. *)
val preapply :
  predecessor:State.Block.t ->
  timestamp:Time.t ->
  protocol_data:MBytes.t ->
  sort_operations:bool ->
  Operation.t list list ->
  (Block_header.shell_header * error Preapply_result.t list) tzresult Lwt.t

val notify_operation :
  prevalidation_state ->
  error Preapply_result.t ->
  unit

val shutdown_operation_input :
  prevalidation_state ->
  unit

val build_rpc_directory :
  Protocol_hash.t ->
  (prevalidation_state * error Preapply_result.t) RPC_directory.t tzresult Lwt.t
