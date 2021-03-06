(*  OCamlPro Scilab Toolbox - OcSciLab, primitives/overloading dispatcher
 *  Copyright (C) 2014 - OCamlPro - Benjamin CANOU
 *
 *  This file must be used under the terms of the CeCILL.
 *  This source file is licensed as described in the file COPYING, which
 *  you should have received as part of this distribution.
 *  The terms are also available at
 *  http://www.cecill.info/licences/Licence_CeCILL_V2-en.txt *)

(** The type based dispatching tree used at run-time for finding
    implementations of possibly overloaded primitives, and by the type
    system to find all the possible types of operations. *)
module type S = sig

  (** Parameter erased by the functor to [Values.rtt] *)
  type rtt

  (** The kinds of primitives that can be overloaded *)
  type overloading =
    | Colon
    | Matrix_horizontal_collation
    | Matrix_vertical_collation
    | Injection
    | Extraction
    | Recursive_extraction
    | Unary of ScilabAst.Shared.unop
    | Binary of ScilabAst.Shared.op
    | Function of string
    | Print

  (** Dispatching route elements as runtime type discriminators, using
      a finer grain than user defineable overloadings,
      cf. {!parse_overloading_notation} *)
  type matcher =
    | Typed : rtt -> matcher
    | Any : matcher

  (** Builds the list of type tags that correspond to a given character
      sequence in Scilab's overloading type notation *)
  val parse_overloading_char_code : string -> matcher list

  (** Accepts valid char codes for unary overloadings *)
  val parse_unary_overloading : string -> overloading

  (** Accepts valid char codes for binary overloadings *)
  val parse_binary_overloading : char -> overloading

  (** Parses a Scilab overloading function name (%t_k or %t1_k_t2) and
      returns the kind of operation with all possible associated
      matchers (since the matcher are finer than user types). *)
  val parse_overloading_notation : string -> overloading * matcher list list

  (** Produce the name of the user overloading that would affect a
      given operation (and probably others) *)
  val overloading_notation : overloading -> rtt list -> string

  (** Produce the character to use in user overloading notations for a
      given type (and probably others) *)
  val char_code : rtt -> string

  (** A dispatcher tree *)
  type 'a table

  (** An empty dispatching tree *)
  val create : unit -> 'a table

  (** Duplicates a dispatching tree *)
  val dup : 'a table -> 'a table

  (** Inserts the implementation of a given operation for a given
      dispatching type route. If the route already exists, it is
      overwritten and the function returns [true], unless it has been
      frozen, in which case [Error (Failure "register")] is raised. If
      the route does not exist yet, the function returns [false]. *)
  val register
    : ?frozen:bool -> ?more:bool ->
    overloading -> matcher list -> int -> 'a -> 'a table -> bool

  (** Finds an appropirate implementation for the given overloading
      types of parameters, and return arity, using the following order.
      - exact length with exact types
      - exact length with some parameters matched by Any
      - prefix length with exact types
      - prefix length with some parameters matched by Any
      The last two are only selected when the registration was done
      with [~more:true] *)
  val lookup : overloading -> rtt list -> int -> 'a table -> 'a
end

module Make (Values : InterpValues.S)
  : S with type rtt := Values.rtt = struct

  open Values

  open ScilabAst.Shared

  type overloading =
    | Colon
    | Matrix_horizontal_collation
    | Matrix_vertical_collation
    | Injection
    | Extraction
    | Recursive_extraction
    | Unary of ScilabAst.Shared.unop
    | Binary of ScilabAst.Shared.op
    | Function of string
    | Print

  type matcher =
    | Typed : rtt -> matcher
    | Any : matcher

  let parse_overloading_char_code : string -> matcher list = function
    | ":" ->
      [ Any ]
    | "s" ->
      [ Typed (T (Matrix (Number Real))) ; Typed (T (Matrix (Number Complex))) ;
        Typed (T (Single (Number Real))) ; Typed (T (Single (Number Complex))) ;
        Typed (T Atom) ]
    | "p" ->
      [ Typed (T (Matrix (Poly Real))) ; Typed (T (Matrix (Poly Complex))) ;
        Typed (T (Single (Poly Real))) ; Typed (T (Single (Poly Complex))) ]
    | "b" ->
      [ Typed (T (Matrix Bool)) ; Typed (T (Single Bool)) ]
    | "sp" ->
      [ Typed (T (Sparse (Number Real))) ; Typed (T (Sparse (Number Complex))) ]
    | "spb" ->
      [ Typed (T (Sparse Bool)) ]
    | "i" ->
      [ Typed (T (Matrix Int8)) ; Typed (T (Matrix Int16)) ; Typed (T (Matrix Int32)) ;
        Typed (T (Matrix Uint8)) ; Typed (T (Matrix Uint16)) ; Typed (T (Matrix Uint32)) ;
        Typed (T (Single Int8)) ; Typed (T (Single Int16)) ; Typed (T (Single Int32)) ;
        Typed (T (Single Uint8)) ; Typed (T (Single Uint16)) ; Typed (T (Single Uint32)) ]
    | "c" ->
      [ Typed (T (Matrix String)) ; Typed (T (Single String)) ]
    | "h" ->
      [ Typed (T Handle) ]
    | "l" ->
      [ Typed (T Vlist) ]
    | "fptr" ->
      [ Typed (T Primitive) ]
    | "mc" ->
      [ Typed (T Macro) ]
    |  name ->
      [ Typed (T (Tlist name)) ; Typed (T (Mlist name)) ]

  let parse_unary_overloading : string -> overloading = fun c ->
    if String.length c = 1 then
      match c.[0] with
      | 't' -> Unary Transpose_conjugate      (* ' *) ;
      | '0' -> Unary Transpose_non_conjugate  (* .' *) ;
      | '5' -> Unary Not                      (* ~ *) ;
      | 's' -> Unary Unary_minus              (* - *) ;
      | 'a' -> Unary Unary_plus               (* + *) ;
      | 'e' -> Extraction                     (* () extraction *) ;
      | '6' -> Recursive_extraction           (* iext *)
      | 'p' -> Print                          (* print *)
      | _ -> Function c (* TODO: failwith "invalid overloading notation" ? *)
    else Function c

  let parse_binary_overloading : char -> overloading = fun c ->
    match c with
    | 'a' -> Binary Plus                     (* + *) ;
    | 's' -> Binary Minus                    (* - *) ;
    | 'm' -> Binary Times                    (* * *) ;
    | 'r' -> Binary Rdivide                  (* / *) ;
    | 'l' -> Binary Ldivide                  (* \ *) ;
    | 'p' -> Binary Power                    (* ^ *) ;
    | 'x' -> Binary Dot_times                (* .* *) ;
    | 'd' -> Binary Dot_rdivide              (* ./ *) ;
    | 'q' -> Binary Dot_ldivide              (* .\ *) ;
    | 'j' -> Binary Dot_power                (* .^ *) ;
    | 'k' -> Binary Kron_times               (* .*. *) ;
    | 'y' -> Binary Kron_ldivide             (* ./. *) ;
    | 'z' -> Binary Kron_rdivide             (* .\. *) ;
    | 'u' -> Binary Control_times            (* *. *) ;
    | 'v' -> Binary Control_rdivide          (* /. *) ;
    | 'w' -> Binary Control_ldivide          (* \. *) ;
    | 'o' -> Binary Eq                       (* == *) ;
    | 'n' -> Binary Ne                       (* <> *) ;
    | 'g' -> Binary Or                       (* | *) ;
    | 'h' -> Binary And                      (* & *) ;
    | '1' -> Binary Lt                       (* < *) ;
    | '2' -> Binary Gt                       (* > *) ;
    | '3' -> Binary Le                       (* <= *) ;
    | '4' -> Binary Ge                       (* >= *) ;
    | 'b' -> Colon                           (* _:_ *);
    | 'c' -> Matrix_horizontal_collation     (* [a,b] *) ;
    | 'f' -> Matrix_vertical_collation       (* [a;b] *) ;
    | 'i' -> Injection                       (* () insertion *) ;
    | _ -> failwith "invalid overloading notation"

  let rec overloading_notation overloading rtts = match overloading, rtts with
    | Unary Transpose_conjugate, [ rtt ] ->
      "%" ^ char_code rtt ^ "_t"
    | Unary Transpose_non_conjugate, [ rtt ] ->
      "%" ^ char_code rtt ^ "_0"
    | Unary Not, [ rtt ] ->
      "%" ^ char_code rtt ^ "_5"
    | Unary Unary_minus, [ rtt ] ->
      "%" ^ char_code rtt ^ "_s"
    | Unary Unary_plus, [ rtt ] ->
      "%" ^ char_code rtt ^ "_a"
    | Extraction, rtt :: _ ->
      "%" ^ char_code rtt ^ "_e"
    | Recursive_extraction, rtt :: _ ->
      "%" ^ char_code rtt ^ "_6"
    | Print, [ rtt ] ->
      "%" ^ char_code rtt ^ "_p"
    | Function name, rtt :: _ ->
      "%" ^ char_code rtt ^ "_name"
    | Binary Plus, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_a_" ^ char_code rttr
    | Binary Minus, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_s_" ^ char_code rttr
    | Binary Times, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_m_" ^ char_code rttr
    | Binary Rdivide, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_r_" ^ char_code rttr
    | Binary Ldivide, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_l_" ^ char_code rttr
    | Binary Power, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_p_" ^ char_code rttr
    | Binary Dot_times, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_x_" ^ char_code rttr
    | Binary Dot_rdivide, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_d_" ^ char_code rttr
    | Binary Dot_ldivide, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_q_" ^ char_code rttr
    | Binary Dot_power, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_j_" ^ char_code rttr
    | Binary Kron_times, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_k_" ^ char_code rttr
    | Binary Kron_ldivide, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_y_" ^ char_code rttr
    | Binary Kron_rdivide, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_z_" ^ char_code rttr
    | Binary Control_times, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_u_" ^ char_code rttr
    | Binary Control_rdivide, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_v_" ^ char_code rttr
    | Binary Control_ldivide, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_w_" ^ char_code rttr
    | Binary Eq, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_o_" ^ char_code rttr
    | Binary Ne, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_n_" ^ char_code rttr
    | Binary Or, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_g_" ^ char_code rttr
    | Binary And, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_h_" ^ char_code rttr
    | Binary Lt, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_1_" ^ char_code rttr
    | Binary Gt, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_2_" ^ char_code rttr
    | Binary Le, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_3_" ^ char_code rttr
    | Binary Ge, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_4_" ^ char_code rttr
    | Colon, rttl :: rttr :: _ ->
      "%" ^ char_code rttl ^ "_b_" ^ char_code rttr
    | Matrix_horizontal_collation, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_c_" ^ char_code rttr
    | Matrix_vertical_collation, [ rttl ; rttr ] ->
      "%" ^ char_code rttl ^ "_f_" ^ char_code rttr
    | Injection, rttl :: rttr :: _ ->
      "%" ^ char_code rttr ^ "_i_" ^ char_code rttl
    | _ -> failwith "non user defineable overloading"

  and char_code = function
    | T (Matrix (Number Real)) -> "s"
    | T (Matrix (Number Complex)) -> "s"
    | T (Single (Number Real)) -> "s"
    | T (Single (Number Complex)) -> "s"
    | T Atom -> "s"
    | T (Matrix (Poly Real)) -> "p"
    | T (Matrix (Poly Complex)) -> "p"
    | T (Single (Poly Real)) -> "p"
    | T (Single (Poly Complex)) -> "p"
    | T (Matrix Bool) -> "b"
    | T (Single Bool) -> "b"
    | T (Sparse (Number Real)) -> "sp"
    | T (Sparse (Number Complex)) -> "sp"
    | T (Sparse Bool) -> "spb"
    | T (Matrix Int8) -> "i"
    | T (Matrix Int16) -> "i"
    | T (Matrix Int32) -> "i"
    | T (Matrix Uint8) -> "i"
    | T (Matrix Uint16) -> "i"
    | T (Matrix Uint32) -> "i"
    | T (Single Int8) -> "i"
    | T (Single Int16) -> "i"
    | T (Single Int32) -> "i"
    | T (Single Uint8) -> "i"
    | T (Single Uint16) -> "i"
    | T (Single Uint32) -> "i"
    | T (Matrix String) -> "c"
    | T (Single String) -> "c"
    | T Handle -> "h"
    | T Vlist -> "l"
    | T Primitive -> "fptr"
    | T Macro -> "mc"
    | T (Tlist name) -> name
    | T (Mlist name) -> name
    | _ -> failwith "non user defineable overloading"

  let unary_re =
    Re_pcre.(regexp "^%([a-z0-9A-Z]+)_([a-z0-9A-Z]+)_?$")
  let binary_re =
    Re_pcre.(regexp "^%([a-z0-9A-Z]+)_([a-z0-9A-Z]+)_([a-z0-9A-Z]+)_?$")

  let parse_overloading_notation : string -> overloading * matcher list list = function name ->
    let fail () = failwith "invalid overloading notation" in
    try
      match Re.(get_all (exec unary_re name)) with
      | [| _ ; ty ; op |] ->
        parse_unary_overloading op,
        List.map (fun m -> [ m ]) (parse_overloading_char_code ty)
      | _ -> fail ()
    with Not_found -> try
        match Re.(get_all (exec binary_re name)) with
        | [| _ ; tyl ; op ; tyr |] when String.length op = 1 ->
          let op = parse_binary_overloading op.[0] in
          op,
          List.map (fun ml ->
              List.map (fun mr ->
                  if op = Injection then [ mr ; ml ]
                  else [ ml ; mr ])
                (parse_overloading_char_code tyr))
            (parse_overloading_char_code tyl) |>
          List.flatten
        | _ -> fail ()
      with Not_found -> fail ()

  module OverloadingMap =
    Map.Make (struct type t = overloading let compare = compare end)

  module RttMap =
    Map.Make (struct type t = rtt let compare = compare end)

  module IntMap =
    Map.Make (struct type t = int let compare = (-) end)

  type 'a arg =
    { leaf : 'a ret ;
      typed : 'a arg RttMap.t ;
      any : 'a arg option }

  and 'a table =
    'a arg OverloadingMap.t ref

  and 'a ret =
    { accepts_more : 'a item IntMap.t ;
      exact_arity : 'a item IntMap.t }

  and 'a item =
    { frozen : bool ;
      bucket : 'a }

  let create () =
    ref OverloadingMap.empty

  let dup { contents = table } =
    ref table

  let empty_ret =
    { accepts_more = IntMap.empty ;
      exact_arity =  IntMap.empty }

  let empty_arg =
    { leaf = empty_ret ; typed = RttMap.empty ; any = None }

  let register
      ?(frozen = false) ?(more = false)
      overloading matchers lhs bucket table =
    let res = ref false in
    let rec insert_in_ret ret =
      if more then
        { ret with accepts_more = insert_in_map ret.accepts_more }
      else
        { ret with exact_arity = insert_in_map ret.exact_arity }
    and insert_in_map map =
      match IntMap.find lhs map with
      | { frozen = true } ->
        raise (Failure "register")
      | exception Not_found ->
        IntMap.add lhs { bucket ; frozen } map
      | _ ->
        res := true ;
        IntMap.add lhs { bucket ; frozen } map

    and insert_in_arg ({ leaf ; typed ; any } as unchanged) matchers =
      match leaf, any, matchers with
      | _, _, []->
        { leaf = insert_in_ret leaf ; typed ; any }
      | leaf, _, Typed rtt :: rest ->
        { leaf ; typed = insert_in_typed typed rtt rest ; any }
      | leaf, None, Any :: rest ->
        { leaf ; typed ; any = Some (insert_in_arg (empty_arg) rest) }
      | leaf, Some arg, Any :: rest ->
        { leaf ; typed ; any = Some (insert_in_arg arg rest) }
    and insert_in_typed typed t rest =
      let arg = try RttMap.find t typed with Not_found -> empty_arg in
      RttMap.add t (insert_in_arg arg rest) typed
    in
    let first_arg = try OverloadingMap.find overloading !table with Not_found -> empty_arg in
    table := OverloadingMap.add overloading (insert_in_arg first_arg matchers) !table ;
    !res

  let lookup overloading rtts lhs table =
    let rec find_in_arg { leaf ; typed ; any } rtts = match rtts with
      | [] -> begin try
            IntMap.find lhs leaf.exact_arity
          with Not_found ->
            IntMap.find lhs leaf.accepts_more
        end
      | rtt :: rtts ->
        try
          try
            find_in_arg (RttMap.find rtt typed) rtts
          with Not_found -> match any with
            | None -> raise Not_found
            | Some arg -> find_in_arg arg rtts
        with Not_found ->
          IntMap.find lhs leaf.accepts_more
    in
    (find_in_arg (OverloadingMap.find overloading !table) rtts).bucket
end
