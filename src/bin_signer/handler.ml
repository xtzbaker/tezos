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

open Signer_logging

let log = lwt_log_notice

module High_watermark = struct
  let encoding =
    let open Data_encoding in
    let raw_hash =
      conv Blake2B.to_bytes Blake2B.of_bytes_exn bytes in
    conv
      (List.map (fun (chain_id, marks) -> Chain_id.to_b58check chain_id, marks))
      (List.map (fun (chain_id, marks) -> Chain_id.of_b58check_exn chain_id, marks)) @@
    assoc @@
    conv
      (List.map (fun (pkh, mark) -> Signature.Public_key_hash.to_b58check pkh, mark))
      (List.map (fun (pkh, mark) -> Signature.Public_key_hash.of_b58check_exn pkh, mark)) @@
    assoc @@
    obj2
      (req "level" int32)
      (req "hash" raw_hash)

  let mark_if_block_or_endorsement (cctxt : #Client_context.wallet) pkh bytes =
    let mark art name get_level =
      let file = name ^ "_high_watermark" in
      cctxt#with_lock @@ fun () ->
      cctxt#load file ~default:[] encoding >>=? fun all ->
      if MBytes.length bytes < 9 then
        failwith "byte sequence too short to be %s %s" art name
      else
        let hash = Blake2B.hash_bytes [ bytes ] in
        let chain_id = Chain_id.of_bytes_exn (MBytes.sub bytes 1 4) in
        let level = get_level () in
        begin match List.assoc_opt chain_id all with
          | None -> return ()
          | Some marks ->
              match List.assoc_opt pkh marks with
              | None -> return ()
              | Some (previous_level, previous_hash) ->
                  if previous_level > level then
                    failwith "%s level %ld below high watermark %ld" name level previous_level
                  else if previous_level = level && previous_hash <> hash then
                    failwith "%s level %ld already signed with a different header" name level
                  else
                    return ()
        end >>=? fun () ->
        let rec update = function
          | [] -> [ chain_id, [ pkh, (level, hash) ] ]
          | (e_chain_id, marks) :: rest ->
              if chain_id = e_chain_id then
                let marks = (pkh, (level, hash)) :: List.filter (fun (pkh', _) -> pkh <> pkh') marks in
                (e_chain_id, marks) :: rest
              else
                (e_chain_id, marks) :: update rest in
        cctxt#write file (update all) encoding in
    if MBytes.length bytes > 0 && MBytes.get_uint8 bytes 0 = 0x01 then
      mark "a" "block" (fun () -> MBytes.get_int32 bytes 5)
    else if MBytes.length bytes > 0 && MBytes.get_uint8 bytes 0 = 0x02 then
      mark "an" "endorsement" (fun () -> MBytes.get_int32 bytes (MBytes.length bytes - 4))
    else return ()

end

module Authorized_key =
  Client_aliases.Alias (struct
    include Signature.Public_key
    let name = "authorized_key"
    let to_source s = return (to_b58check s)
    let of_source t = Lwt.return (of_b58check t)
  end)

let check_magic_byte magic_bytes data =
  match magic_bytes with
  | None -> return_unit
  | Some magic_bytes ->
      let byte = MBytes.get_uint8 data 0 in
      if MBytes.length data > 1
      && (List.mem byte magic_bytes) then
        return_unit
      else
        failwith "magic byte 0x%02X not allowed" byte

let sign
    (cctxt : #Client_context.wallet)
    Signer_messages.Sign.Request.{ pkh ; data ; signature }
    ?magic_bytes ~check_high_watermark ~require_auth =
  log Tag.DSL.(fun f ->
      f "Request for signing %d bytes of data for key %a, magic byte = %02X"
      -% t event "request_for_signing"
      -% s num_bytes (MBytes.length data)
      -% a Signature.Public_key_hash.Logging.tag pkh
      -% s magic_byte (MBytes.get_uint8 data 0)) >>= fun () ->
  check_magic_byte magic_bytes data >>=? fun () ->
  begin match require_auth, signature with
    | false, _ -> return_unit
    | true, None -> failwith "missing authentication signature field"
    | true, Some signature ->
        let to_sign = Signer_messages.Sign.Request.to_sign ~pkh ~data in
        Authorized_key.load cctxt >>=? fun keys ->
        if List.fold_left
            (fun acc (_, key) -> acc || Signature.check key signature to_sign)
            false keys
        then
          return_unit
        else
          failwith "invalid authentication signature"
  end >>=? fun () ->
  Client_keys.get_key cctxt pkh >>=? fun (name, _pkh, sk_uri) ->
  log Tag.DSL.(fun f ->
      f "Signing data for key %s"
      -% t event "signing_data"
      -% s Client_keys.Logging.tag name) >>= fun () ->
  begin if check_high_watermark then
      High_watermark.mark_if_block_or_endorsement cctxt pkh data
    else return ()
  end >>=? fun () ->
  Client_keys.sign cctxt sk_uri data >>=? fun signature ->
  return signature

let public_key (cctxt : #Client_context.wallet) pkh =
  log Tag.DSL.(fun f ->
      f "Request for public key %a"
      -% t event "request_for_public_key"
      -% a Signature.Public_key_hash.Logging.tag pkh) >>= fun () ->
  Client_keys.list_keys cctxt >>=? fun all_keys ->
  match List.find_opt (fun (_, h, _, _) -> Signature.Public_key_hash.equal h pkh) all_keys with
  | None ->
      log Tag.DSL.(fun f ->
          f "No public key found for hash %a"
          -% t event "not_found_public_key"
          -% a Signature.Public_key_hash.Logging.tag pkh) >>= fun () ->
      Lwt.fail Not_found
  | Some (_, _, None, _) ->
      log Tag.DSL.(fun f ->
          f "No public key found for hash %a"
          -% t event "not_found_public_key"
          -% a Signature.Public_key_hash.Logging.tag pkh) >>= fun () ->
      Lwt.fail Not_found
  | Some (name, _, Some pk, _) ->
      log Tag.DSL.(fun f ->
          f "Found public key for hash %a (name: %s)"
          -% t event "found_public_key"
          -% a Signature.Public_key_hash.Logging.tag pkh
          -% s Client_keys.Logging.tag name) >>= fun () ->
      return pk
