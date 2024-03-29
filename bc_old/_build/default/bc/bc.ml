open Core.Std ;;
open Caml ;;
module Scope = Caml.Map.Make(String) ;;

let globalStack = Stack.create () ;;
let localStack = Stack.create () ;;
Stack.push Scope.empty localStack ;;
Stack.push Scope.empty globalStack ;;

type sExpr = 
    | Atom of string
    | List of sExpr list
    ;;

type expr = 
    | Num of float
    | Var of string
    | Op1 of string*expr
    | Op2 of string*expr*expr
    | Fct of string* expr list
    ;;

type statement = 
    | Assign of string*expr
    | Return of expr
    | Expr of expr
    | If of expr* statement list * statement list
    | While of expr*statement list
    | For of statement*expr*statement*statement list
    | FctDef of string * string list * statement list 
    ;;

type block = statement list ;;

type env = float Scope.t ;;

type envQueue = env Stack.t;;

let funcMap : statement list Scope.t ref = ref Scope.empty;;
let paramMap : string list Scope.t ref = ref Scope.empty;;

(* Puts value into the appropriate scope *)
let assignVar (var: string) (value : float) (scopes :envQueue): unit = 
    let localScope = Stack.pop scopes in
    let globalScope = Stack.pop globalStack in

    if(Scope.mem var localScope) then
        let localScope = Scope.add var value localScope in
        Stack.push localScope scopes;
        Stack.push globalScope globalStack;
    else if(Scope.mem var globalScope) then
        let globalScope =  Scope.add var value globalScope in
        Stack.push localScope scopes;
        Stack.push globalScope globalStack;
    else begin
        let localScope = Scope.add var value localScope in
        Stack.push localScope scopes;
        Stack.push globalScope globalStack;
    end
    ;;

(* Gets value from the global scope *)    
let rec getGlobalValue (var: string) (scopes :envQueue) : float =
    let globalScope = Stack.top globalStack in
    let value = Scope.find_opt var globalScope in
    match value with
    | Some(flt)     -> flt
    | None          -> assignVar var 0.0 scopes; (* puts default value 0 for this new variable *)
                       0.0
    ;;

(* Gets value from the local scope *)
let varEval (var: string) (scopes :envQueue): float  = 
    let topScope = Stack.top scopes in
    let value = Scope.find_opt var topScope in
    match value with
    | Some(flt)     -> flt
    | None          -> getGlobalValue var scopes
    ;;

let evalPre (addVal : float) (exp : expr) (scopes :envQueue) : float =
    match exp with
        | Var(var)  -> let value = varEval var scopes in 
                       let value = value +. addVal in
                       assignVar var value scopes;
                       value
        | _         -> 0.0 (* TO DO throw error *)
    ;;

let evalRel (op: string)  (left: float) (right: float) : float =
    let diff = left -. right in
    match op with
    | ">"    -> if diff > 0.  then 1.0 else 0.0
    | "<"    -> if diff < 0.  then 1.0 else 0.0
    | ">="   -> if diff >= 0. then 1.0 else 0.0
    | "<="   -> if diff <= 0. then 1.0 else 0.0
    | "=="   -> if diff = 0. then 1.0 else 0.0
    | "!="   -> if diff <> 0. then 1.0 else 0.0
    ;;

let evalLogical (op: string)  (left: float) (right: float) : float =
    match op with
    | "&&" -> if (left != 0.0) && (right != 0.0) then 1.0 else 0.0
    | "||" -> if (left != 0.0) || (right != 0.0) then 1.0 else 0.0
    ;;

let evalOp (op: string)  (left: float) (right: float) : float =
    match op with
    | "*" -> left *. right
    | "/" -> left /. right
    | "+" -> left +. right
    | "-" -> left -. right
    | "^" -> left ** right
    | ">" | "<" | ">=" | "<=" | "==" | "!=" -> evalRel op left right
    | "&&" | "||" -> evalLogical op left right
    | _   -> 0.0
    ;;



let rec evalExpr (exp : expr) (scopes :envQueue) :float  =
    match exp with
    | Num(num)              -> num
    | Var(variable)         -> varEval variable scopes
    | Op1(op, e1)           -> evalUnary op e1 scopes
    | Op2(op, e1, e2)       -> let left = evalExpr e1 scopes in
                               let right = evalExpr e2 scopes in
                               evalOp op left right
    
    | _                     -> 0.0

and evalUnary (op : string) (exp : expr) (scopes :envQueue) : float = 
match op with
    | "++"  -> evalPre 1.0 exp scopes
    | "--"  -> evalPre (0.0 -. 1.0) exp scopes
    | "!" -> let value = evalExpr exp scopes in
             if value == 0.0 then 1.0 else 0.0
    | "-" -> let value = evalExpr exp scopes in
             value *. -1.0
    | _   -> 0.0  (* To do throw error *)
    ;;

let rec evalStatement (s: statement) (scopes :envQueue): envQueue =
    match s with 
        | Assign(var, expr) ->  let value = evalExpr expr scopes in
                                assignVar var value scopes;
                                scopes
        | Expr(expr)        -> let result = evalExpr expr scopes in
                                result |> printf "%F\n";
                                scopes
        | If(exp, codeT, codeF) -> 
            let cond = evalExpr exp scopes in
                if(cond > 0.0) then 
                    evalCode codeT scopes 
                else
                    evalCode codeF scopes
            ;
            scopes
        | While(cond, stat_list)      -> while (evalExpr cond scopes) = 1.0 do
                                            evalCode stat_list scopes 
                                         done;
                                         scopes
        | For(init, cond, update, stat_list) -> let tmp = evalStatement init scopes in
                                                evalForLoop cond update stat_list scopes;
                                                scopes
        | FctDef (name, params, stat_list) -> putFuncDef name params stat_list;
                                              scopes
        | _ -> scopes (*ignore *)
        ;
and evalCode (stat_list: block) (scopes :envQueue): unit = 
    (* crate new environment *)
    (* user fold_left  *)
    (* pop the local environment *)
    match stat_list with
    | hd::tl        -> let s = evalStatement hd scopes in
                       evalCode tl scopes
    | _             -> ()
    ;
and evalForLoop (cond : expr) (update: statement) (stat_list: statement list) (scopes: envQueue): unit = 
    if (evalExpr cond scopes) <> 1.0 then
       ()
    else begin
        evalCode stat_list scopes;
        let tmp = evalStatement update scopes in
        evalForLoop cond update stat_list scopes
    end
    ;
and putFuncDef (name : string) (params : string list) (stat_list : statement list) : unit =
    (*
    let funcMap = Stack.pop funcStack in
    let key = string_of_int (List.length params) ^ name in
    let impl = Scope.find_opt key funcMap in
    
    (*
    let params = Param.find_opt key !paramMap in
    *)

    match impl with
    | list  -> let funcMap = Scope.add key stat_list funcMap in
               Stack.push funcMap funcStack
    | None  -> ()
    
    *)
    ()
    ;;

(* Test for expression *)
let%expect_test "evalNum" = 
    let t1 = Op2("+", Op2("-", (Num 20.0), (Num 20.0)), (Num 4.0))  in
    Stack.push Scope.empty localStack;
    evalExpr t1  localStack |>
    printf "%F";
    [%expect {| 4. |}]
    ;;

(* Test for variable *)
let%expect_test "evalVar" = 
    let var = Var("i") in

    let scope = Scope.empty in
    let global = Scope.empty in
    let scope = Scope.add "i" 24.0 scope in
    let global = Scope.add "r" 23.0 global in
    Stack.push scope localStack;
    Stack.push global globalStack;

    evalExpr var localStack |>
    printf "%F";
    [%expect {| 24. |}]
    ;;
(* 
    v = 4; 
    v //  4
    ++v // 5
    v = v + 4 + v - 4
    v  // 10
 *)
let p1: block = [
        Assign("v", Num(4.0));
        Expr(Var("v"));
        Expr(Op1("++", Var("v")));
        Assign("v", Op2("+", Op2("+", Var("v"), Num(4.0)),  Op2("-", Var("v"), Num(4.0))));
        Expr(Var("v"));
        Expr(Op2("==", Var("v"), Num(10.0)));
        Expr(Op2("!=", Var("v"), Num(10.0)));
];;

let%expect_test "p1" =
    evalCode p1 localStack; 
    [%expect {| 
                4.
                5. 
                10.
                1.
                0.
                |}]
    ;;

(* 
    If else test
    v = 0

    if (v - 4) < 0.0 then
    ++v
    else
    --v
*)
let ifelse: block = [
    Assign("v", Num(0.0));
    If(
        Op2("<", Op2("-",  Var("v"), Num(4.0)), Num(0.0)), 
        [Expr(Op1("++", Var("v")))], 
        [Expr(Op1("--", Var("v")))]
    );
];;

let%expect_test "ifelse" =
    evalCode ifelse localStack; 
    [%expect {| 
              1.
              |}]
    ;;

let while_test: block = [
    While(
        Op2("<", Var("k"), Num(10.0)),
        [Expr(Op1("++", Var("k")))]
    );
];;

let%expect_test "while_test" =
evalCode while_test localStack; 
[%expect {| 
            1.
            2.
            3.
            4.
            5.
            6.
            7.
            8.
            9.
            10.
            |}]
;;
(*
    v = 1.0;
    if (v>10.0) then
        v = v + 1.0
    else
        for(i=2.0; i<10.0; i++) {
            v = v * i
        }
    v   // display v
*)
let p2: block = [
    Assign("v", Num(1.0));
    If(
        Op2(">", Var("v"), Num(10.0)), 
        [Assign("v", Op2("+", Var("v"), Num(1.0)))], 
        [For(
            Assign("i", Num(2.0)),
            Op2("<", Var("i"), Num(10.0)),
            Assign("i",(Op2("+", Var("i"), Num(1.0)))),
            [
                Assign("v", Op2("*", Var("v"), Var("i")))
            ]
        )];
    );
    Expr(Var("v"))
];;


let%expect_test "p1" =
    evalCode p2 localStack; 
    [%expect {| 362880. |}]
    ;;

(*  Fibbonaci sequence
    define f(x) {
        if (x<1.0) then
            return (1.0)
        else
            return (f(x-1)+f(x-2))
    }
    f(3)
    f(5)
 *)
let p3: block = 
    [
        FctDef("f", ["x"], [
            If(
                Op2("<=", Var("x"), Num(1.0)),
                [Return(Num(1.0))],
                [Return(Op2("+",
                    Fct("f", [Op2("-", Var("x"), Num(1.0))]),
                    Fct("f", [Op2("-", Var("x"), Num(1.0))])
                ))])
        ]);
        Expr(Fct("f", [Num(3.0)]));
        Expr(Fct("f", [Num(5.0)]));
    ]
    ;;

(*
let%expect_test "p3" =
    evalCode p3 []; 
    [%expect {| 
        2. 
        5.      
    |}]
    ;;
    *)

(* ADD run. Internal func can change *)
(* Read no needed *)
