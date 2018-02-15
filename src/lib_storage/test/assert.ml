(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2014 - 2018.                                          *)
(*    Dynamic Ledger Solutions, Inc. <contact@tezos.com>                  *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)

let fail expected given msg =
  Format.kasprintf Pervasives.failwith
    "@[%s@ expected: %s@ got: %s@]" msg expected given
let fail_msg fmt = Format.kasprintf (fail "" "") fmt

let default_printer _ = ""

let equal ?(eq=(=)) ?(prn=default_printer) ?(msg="") x y =
  if not (eq x y) then fail (prn x) (prn y) msg

let equal_string_option ?msg o1 o2 =
  let prn = function
    | None -> "None"
    | Some s -> s in
  equal ?msg ~prn o1 o2

let is_false ?(msg="") x =
  if x then fail "false" "true" msg

let is_true ?(msg="") x =
  if not x then fail "true" "false" msg

let is_none ?(msg="") x =
  if x <> None then fail "None" "Some _" msg

let make_equal_list eq prn ?(msg="") x y =
  let rec iter i x y =
    match x, y with
    | hd_x :: tl_x, hd_y :: tl_y ->
        if eq hd_x hd_y then
          iter (succ i) tl_x tl_y
        else
          let fm = Printf.sprintf "%s (at index %d)" msg i in
          fail (prn hd_x) (prn hd_y) fm
    | _ :: _, [] | [], _ :: _ ->
        let fm = Printf.sprintf "%s (lists of different sizes)" msg in
        fail_msg "%s" fm
    | [], [] ->
        () in
  iter 0 x y

let equal_string_list ?msg l1 l2 =
  make_equal_list ?msg (=) (fun x -> x) l1 l2

let equal_string_list_list ?msg l1 l2 =
  let pr_persist l =
    let res =
      String.concat ";" (List.map (fun s -> Printf.sprintf "%S" s) l) in
    Printf.sprintf "[%s]" res in
  make_equal_list ?msg (=) pr_persist l1 l2

let equal_block_set ?msg set1 set2 =
  let b1 = Block_hash.Set.elements set1
  and b2 = Block_hash.Set.elements set2 in
  make_equal_list ?msg
    (fun h1 h2 -> Block_hash.equal h1 h2)
    Block_hash.to_string
    b1 b2

let equal_block_map ?msg ~eq map1 map2 =
  let b1 = Block_hash.Map.bindings map1
  and b2 = Block_hash.Map.bindings map2 in
  make_equal_list ?msg
    (fun (h1, b1) (h2, b2) -> Block_hash.equal h1 h2 && eq b1 b2)
    (fun (h1, _) -> Block_hash.to_string h1)
    b1 b2

let equal_block_hash_list ?msg l1 l2 =
  let pr_block_hash = Block_hash.to_short_b58check in
  make_equal_list ?msg Block_hash.equal pr_block_hash l1 l2