open Common
open Ostap.Pretty
open Ostap.Util
open List

@type binop = [ `Add | `And | `Div | `Eq | `Ge | `Gt | `Le | `Lt | `Mod | `Mul | `Ne | `Or | `Sub] with gmap, foldl
@type unop  = [`Neg | `Not] with gmap, foldl
@type const = [`True | `False | `Literal of GT.int] with gmap, foldl

@type 'expr expr =  [ `Binop of binop * 'expr * 'expr 
                    | `Unop  of unop * 'expr
		    | `Const of const
		    ] with gmap, foldl

(*
(* ------------------------------------ Generic transformer ------------------------- *)

module Mapper (M : Monad.S) =
  struct
(*    type 'a expr = 'a mytype*)
    open M
    let rec gmap t ext (expr) = 
      let self = gmap t ext in
      match expr with
      | `Binop (op, x, y) -> tuple (self x, self y) >>= (fun (x, y) -> t#binop expr op x y)
      | `Unop  (op, x)    -> self x >>= (fun x -> t#unop expr op x)
      | `Const  x         -> t#const expr x
      |  x                -> ext self x 
  end

let imap t ext expr =
  let module M = Mapper (Monad.Id) in
  M.gmap t ext expr

let cmap t ext expr =
  let module M = Mapper (Monad.Checked) in
  M.gmap t ext expr

let mapT f = object 
               method binop expr op x y = f expr (`Binop (op, x, y))
               method unop  expr op x   = f expr (`Unop (op, x))
               method const expr x      = f expr (`Const x)
             end
*)
(* ----------------------------------------- Parser --------------------------------- *)

let r = Ostap.Matcher.Token.repr
let l = Ostap.Matcher.Token.loc 

let rec parse reference s = 
  let binop t x y = `Binop (t, x, y) in
  Ostap.Util.expr loc [|
   `Nona , List.map (fun (s, t) -> ostap($(s)), binop t) 
           ["=", `Eq; "#", `Ne; "<=", `Le; "<", `Lt; ">=", `Ge; ">", `Gt];
   `Lefta, List.map (fun (s, t) -> s, binop t)
           [ostap ("+"), `Add; ostap ("-"), `Sub; key "OR", `Or];
   `Lefta, List.map (fun (s, t) -> s, binop t)
           [ostap ("*"), `Mul; key "DIV", `Div; key "MOD", `Mod; ostap ("&"), `And]
  |]
  (primary reference)
  s
and ostap (
  primary[reference]: 
   loc[ostap(
         x:LITERAL =>{try ignore (int_of_string (r x)); true with _ -> false}::
                     (new Ostap.Reason.t 
                        (Ostap.Msg.make "integer constant \"%0\" is too large" [|r x|] (l x))
                     )=> {`Const (`Literal (int_of_string (r x)))} 
       | @("TRUE\\b" :"TRUE" ) {`Const `True}
       | @("FALSE\\b":"FALSE") {`Const `False}
       | -"(" x:parse[reference] -")"
       | op:("~" {`Not} | "-" {`Neg}) x:primary[reference] {`Unop (op, x)}
       | -"+" primary[reference]
       | reference)
      ]
)

(* ------------------------------------ Pretty-printer ------------------------------ *)

let imap = invalid_arg ""

(*
class ['e] gprint ps =
  object inherit ... @expr
  end
*)
let gprint ps ext expr =
  let b x = hovboxed (listBySpaceBreak x) in
  let op (s, p) = string s, p in
  let w p' (x, p) = if p' < p then rboxed x else x in 
  imap  
    (object 
       method binop _ o x y = let s, p = op (ps#binop o) in b [w p x; s; w p y], p
       method unop  _ o x   = let s, p = op (ps#unop o) in b [s; w p x], p
       method const _   x   = ps#const x
     end
    )
    ext
    expr

let print ext expr = 
  gprint (object
            method unop = function `Not -> "~", 0 | `Neg -> "-", 0
            method binop  = function 
            | `Mul -> "*" , 1 | `Div -> "DIV", 1 | `Mod -> "MOD", 1 | `And -> "&", 1
            | `Add -> "+" , 2 | `Sub -> "-"  , 2 | `Or  -> "OR" , 2 
            | `Le  -> "<=", 3 | `Lt  -> "<"  , 3 | `Ge  -> ">=" , 3 | `Gt  -> ">", 3 
            | `Ne  -> "#" , 3 | `Eq  -> "="  , 3 
            method const = function 
            | `Literal s -> int s         , 0 
            | `True      -> string "TRUE" , 0 
            | `False     -> string "FALSE", 0
          end) ext expr

(*
let print_c ext expr = 
  gprint (object
            method unop = function `Not -> "!", 0 | `Neg -> "-", 0
            method binop  = function
            | `Mul -> "*" , 1 | `Div -> "/" , 1 | `Mod -> "%" , 1 | `And -> "&&", 1
            | `Add -> "+" , 2 | `Sub -> "-" , 2 | `Or  -> "||", 2 
            | `Le  -> "<=", 3 | `Lt  -> "<" , 3 | `Ge  -> ">=", 3 | `Gt  -> ">" , 3 
            | `Ne  -> "!=", 3 | `Eq  -> "==", 3
            method const = function 
            | `Literal s -> int s     , 0 
            | `True      -> string "1", 0 
            | `False     -> string "0", 0
          end) ext expr
*)
(* ------------------------------------- Name resolver ------------------------------ *)

(*
open Checked 

let rec safeLocate e =
  try ulocate e with Not_found ->
    (match e with
     | `Binop (_, x, y) ->
        let l, r = safeLocate x, safeLocate y in
        Ostap.Msg.Locator.makeInterval l r
     | _ -> Ostap.Msg.Locator.No
    )

let resolve ext expr =
  let reloc x y = reloc (safeLocate x) y in
  cmap (mapT (fun expr e -> !! (reloc expr e))) ext expr
*)
(*
(* -------------------------------------- Typechecker ------------------------------- *)

let typeOf ref = function
| `Const (`Literal _) | `Unop (`Neg, _) -> `Int | `Const _ | `Unop (`Not, _) -> `Bool
| `Binop (op, _, _) -> (match op with `Add | `Sub | `Mul | `Mod | `Div -> `Int | _ -> `Bool)
| x -> ref x

let typecheck ts ext expr = 
  let reloc x y = reloc (safeLocate x) y in
  cmap (object
          method binop e op x y = 
            let t', ensureType =
            match op with          
            | `And | `Or -> `Bool, fun (x, t) -> Common.bool ts x t `Bool  
            | `Eq  | `Ne  | `Le  | `Lt  | `Ge  | `Gt -> `Bool, fun (x, t) -> Common.int ts x t `Int
            | _ -> `Int, fun (x, t) -> Common.int ts x t `Int
            in
            tuple (ensureType x, ensureType y) -?-> (fun _ -> reloc e (`Binop (op, x, y)), t')
          method unop e op ((x, t) as z) = 
            match op with 
            | `Neg -> Common.int ts (reloc e (`Unop (`Neg, z))) t `Int
            | `Not -> Common.bool ts (reloc e (`Unop (`Not, z))) t `Bool
          method const e x =
            match x with
            | `Literal _ -> !! (reloc e (`Const x), `Int)
            | `True | `False -> !! (reloc e (`Const x), `Bool)
        end) ext expr 
*)
(* --------------------------------------- Evaluator -------------------------------- *)

exception Not_a_constant

class ['e] eval = object inherit ['e, unit, GT.int, unit, GT.int] @expr
  method c_Binop inh s op x y = 
    let l f x y = if f x y then 1 else 0 in
    let i f x y = if f (x > 0) (y > 0) then 1 else 0 in
    (match op with
     | `Add -> (+)    | `Sub -> (-)    | `Mul -> ( * )  
     | `Div -> (/)    | `Mod -> (mod) 
     | `Eq  -> l (=)  | `Ne  -> l (<>) 
     | `Le  -> l (<=) | `Lt  -> l (<) 
     | `Ge  -> l (>=) | `Gt  -> l (>)
     | `And -> i (&&) | `Or  -> i (||)
    ) (x.GT.fx inh) (y.GT.fx inh)
  method c_Unop i s op x = 
    (fun x -> match op with `Neg -> -x | `Not -> if x > 0 then 0 else 1)
    (x.GT.fx i)
  method c_Const _ _ = function `Literal x -> x | `True -> 1 | `False -> 0
end
(*
let wrap e x =
  let reloc = reloc (safeLocate e) in
  match typeOf (fun _ -> raise Not_a_constant) e with
  | `Int  -> reloc (`Const (`Literal x))
  | `Bool -> reloc (if x > 0 then `Const `True else `Const `False)

let evaluate expr =
  let x =
    imap 
      (object
         method binop _ op x y =
           let l f x y = if f x y then 1 else 0 in
           let i f x y = if f (x > 0) (y > 0) then 1 else 0 in
           (match op with
            | `Add -> (+)    | `Sub -> (-)    | `Mul -> ( * )  
            | `Div -> (/)    | `Mod -> (mod) 
            | `Eq  -> l (=)  | `Ne  -> l (<>) 
            | `Le  -> l (<=) | `Lt  -> l (<) 
            | `Ge  -> l (>=) | `Gt  -> l (>)
            | `And -> i (&&) | `Or  -> i (||)
           ) x y 
         method unop _ op x = match op with `Neg -> -x | `Not -> if x > 0 then 0 else 1
         method const _ = function `Literal x -> x | `True -> 1 | `False -> 0
       end) 
      (fun _ _ -> raise Not_a_constant) 
      expr
  in
  let reloc = reloc (safeLocate expr) in
  match typeOf (fun _ -> raise Not_a_constant) expr with
  | `Int  -> reloc (`Const (`Literal x))
  | `Bool -> reloc (if x > 0 then `Const `True else `Const `False)

*)
