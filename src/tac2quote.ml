(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, *   INRIA - CNRS - LIX - LRI - PPS - Copyright 1999-2016     *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

open Pp
open Names
open Util
open Tac2dyn
open Tac2expr
open Tac2qexpr

(** Generic arguments *)

let wit_pattern = Arg.create "pattern"
let wit_reference = Arg.create "reference"
let wit_ident = Arg.create "ident"
let wit_constr = Arg.create "constr"
let wit_open_constr = Arg.create "open_constr"
let wit_ltac1 = Arg.create "ltac1"

(** Syntactic quoting of expressions. *)

let prefix_gen n =
  MPfile (DirPath.make (List.map Id.of_string [n; "Ltac2"]))

let control_prefix = prefix_gen "Control"
let pattern_prefix = prefix_gen "Pattern"
let array_prefix = prefix_gen "Array"

let kername prefix n = KerName.make2 prefix (Label.of_id (Id.of_string_soft n))
let std_core n = kername Tac2env.std_prefix n
let coq_core n = kername Tac2env.coq_prefix n
let control_core n = kername control_prefix n
let pattern_core n = kername pattern_prefix n

let global_ref ?loc kn =
  Loc.tag ?loc @@ CTacRef (AbsKn (TacConstant kn))

let constructor ?loc kn args =
  let cst = Loc.tag ?loc @@ CTacCst (AbsKn (Other kn)) in
  if List.is_empty args then cst
  else Loc.tag ?loc @@ CTacApp (cst, args)

let std_constructor ?loc name args =
  constructor ?loc (std_core name) args

let std_proj ?loc name =
  AbsKn (std_core name)

let thunk e =
  let t_unit = coq_core "unit" in
  let loc = Tac2intern.loc_of_tacexpr e in
  let var = [Loc.tag ?loc @@ CPatVar (Anonymous), Some (Loc.tag ?loc @@ CTypRef (AbsKn (Other t_unit), []))] in
  Loc.tag ?loc @@ CTacFun (var, e)

let of_pair f g (loc, (e1, e2)) =
  Loc.tag ?loc @@ CTacApp (Loc.tag ?loc @@ CTacCst (AbsKn (Tuple 2)), [f e1; g e2])

let of_tuple ?loc el = match el with
| [] ->
  Loc.tag ?loc @@ CTacCst (AbsKn (Tuple 0))
| [e] -> e
| el ->
  let len = List.length el in
  Loc.tag ?loc @@ CTacApp (Loc.tag ?loc @@ CTacCst (AbsKn (Tuple len)), el)

let of_int (loc, n) =
  Loc.tag ?loc @@ CTacAtm (AtmInt n)

let of_option ?loc f opt = match opt with
| None -> constructor ?loc (coq_core "None") []
| Some e -> constructor ?loc (coq_core "Some") [f e]

let inj_wit ?loc wit x =
  Loc.tag ?loc @@ CTacExt (wit, x)

let of_variable (loc, id) =
  let qid = Libnames.qualid_of_ident id in
  if Tac2env.is_constructor qid then
    CErrors.user_err ?loc (str "Invalid identifier")
  else Loc.tag ?loc @@ CTacRef (RelId (Loc.tag ?loc qid))

let of_anti f = function
| QExpr x -> f x
| QAnti id -> of_variable id

let of_ident (loc, id) = inj_wit ?loc wit_ident id

let of_constr c =
  let loc = Constrexpr_ops.constr_loc c in
  inj_wit ?loc wit_constr c

let of_open_constr c =
  let loc = Constrexpr_ops.constr_loc c in
  inj_wit ?loc wit_open_constr c

let of_bool ?loc b =
  let c = if b then coq_core "true" else coq_core "false" in
  constructor ?loc c []

let rec of_list ?loc f = function
| [] -> constructor (coq_core "[]") []
| e :: l ->
  constructor ?loc (coq_core "::") [f e; of_list ?loc f l]

let of_qhyp (loc, h) = match h with
| QAnonHyp n -> std_constructor ?loc "AnonHyp" [of_int n]
| QNamedHyp id -> std_constructor ?loc "NamedHyp" [of_ident id]

let of_bindings (loc, b) = match b with
| QNoBindings ->
  std_constructor ?loc "NoBindings" []
| QImplicitBindings tl ->
  std_constructor ?loc "ImplicitBindings" [of_list ?loc of_open_constr tl]
| QExplicitBindings tl ->
  let map e = of_pair (fun q -> of_anti of_qhyp q) of_open_constr e in
  std_constructor ?loc "ExplicitBindings" [of_list ?loc map tl]

let of_constr_with_bindings c = of_pair of_open_constr of_bindings c

let rec of_intro_pattern (loc, pat) = match pat with
| QIntroForthcoming b ->
  std_constructor ?loc "IntroForthcoming" [of_bool b]
| QIntroNaming iname ->
  std_constructor ?loc "IntroNaming" [of_intro_pattern_naming iname]
| QIntroAction iact ->
  std_constructor ?loc "IntroAction" [of_intro_pattern_action iact]

and of_intro_pattern_naming (loc, pat) = match pat with
| QIntroIdentifier id ->
  std_constructor ?loc "IntroIdentifier" [of_anti of_ident id]
| QIntroFresh id ->
  std_constructor ?loc "IntroFresh" [of_anti of_ident id]
| QIntroAnonymous ->
  std_constructor ?loc "IntroAnonymous" []

and of_intro_pattern_action (loc, pat) = match pat with
| QIntroWildcard ->
  std_constructor ?loc "IntroWildcard" []
| QIntroOrAndPattern pat ->
  std_constructor ?loc "IntroOrAndPattern" [of_or_and_intro_pattern pat]
| QIntroInjection il ->
  std_constructor ?loc "IntroInjection" [of_intro_patterns il]
| QIntroRewrite b ->
  std_constructor ?loc "IntroRewrite" [of_bool ?loc b]

and of_or_and_intro_pattern (loc, pat) = match pat with
| QIntroOrPattern ill ->
  std_constructor ?loc "IntroOrPattern" [of_list ?loc of_intro_patterns ill]
| QIntroAndPattern il ->
  std_constructor ?loc "IntroAndPattern" [of_intro_patterns il]

and of_intro_patterns (loc, l) =
  of_list ?loc of_intro_pattern l

let of_hyp_location_flag ?loc = function
| Locus.InHyp -> std_constructor ?loc "InHyp" []
| Locus.InHypTypeOnly -> std_constructor ?loc "InHypTypeOnly" []
| Locus.InHypValueOnly -> std_constructor ?loc "InHypValueOnly" []

let of_occurrences (loc, occ) = match occ with
| QAllOccurrences -> std_constructor ?loc "AllOccurrences" []
| QAllOccurrencesBut occs ->
  let map occ = of_anti of_int occ in
  let occs = of_list ?loc map occs in
  std_constructor ?loc "AllOccurrencesBut" [occs]
| QNoOccurrences -> std_constructor ?loc "NoOccurrences" []
| QOnlyOccurrences occs ->
  let map occ = of_anti of_int occ in
  let occs = of_list ?loc map occs in
  std_constructor ?loc "OnlyOccurrences" [occs]

let of_hyp_location ?loc ((occs, id), flag) =
  of_tuple ?loc [
    of_anti of_ident id;
    of_occurrences occs;
    of_hyp_location_flag ?loc flag;
  ]

let of_clause (loc, cl) =
  let hyps = of_option ?loc (fun l -> of_list ?loc of_hyp_location l) cl.q_onhyps in
  let concl = of_occurrences cl.q_concl_occs in
  Loc.tag ?loc @@ CTacRec ([
    std_proj "on_hyps", hyps;
    std_proj "on_concl", concl;
  ])

let of_destruction_arg (loc, arg) = match arg with
| QElimOnConstr c ->
  let arg = thunk (of_constr_with_bindings c) in
  std_constructor ?loc "ElimOnConstr" [arg]
| QElimOnIdent id -> std_constructor ?loc "ElimOnIdent" [of_ident id]
| QElimOnAnonHyp n -> std_constructor ?loc "ElimOnAnonHyp" [of_int n]

let of_induction_clause (loc, cl) =
  let arg = of_destruction_arg cl.indcl_arg in
  let eqn = of_option ?loc of_intro_pattern_naming cl.indcl_eqn in
  let as_ = of_option ?loc of_or_and_intro_pattern cl.indcl_as in
  let in_ = of_option ?loc of_clause cl.indcl_in in
  Loc.tag ?loc @@ CTacRec ([
    std_proj "indcl_arg", arg;
    std_proj "indcl_eqn", eqn;
    std_proj "indcl_as", as_;
    std_proj "indcl_in", in_;
  ])

let of_repeat (loc, r) = match r with
| QPrecisely n -> std_constructor ?loc "Precisely" [of_int n]
| QUpTo n -> std_constructor ?loc "UpTo" [of_int n]
| QRepeatStar -> std_constructor ?loc "RepeatStar" []
| QRepeatPlus -> std_constructor ?loc "RepeatPlus" []

let of_orient loc b =
  if b then std_constructor ?loc "LTR" []
  else std_constructor ?loc "RTL" []

let of_rewriting (loc, rew) =
  let orient =
    let (loc, orient) = rew.rew_orient in
    of_option ?loc (fun b -> of_orient loc b) orient
  in
  let repeat = of_repeat rew.rew_repeat in
  let equatn = thunk (of_constr_with_bindings rew.rew_equatn) in
  Loc.tag ?loc @@ CTacRec ([
    std_proj "rew_orient", orient;
    std_proj "rew_repeat", repeat;
    std_proj "rew_equatn", equatn;
  ])

let of_hyp ?loc id =
  let hyp = global_ref ?loc (control_core "hyp") in
  Loc.tag ?loc @@ CTacApp (hyp, [of_ident id])

let of_exact_hyp ?loc id =
  let refine = global_ref ?loc (control_core "refine") in
  Loc.tag ?loc @@ CTacApp (refine, [thunk (of_hyp ?loc id)])

let of_exact_var ?loc id =
  let refine = global_ref ?loc (control_core "refine") in
  Loc.tag ?loc @@ CTacApp (refine, [thunk (of_variable id)])

let of_dispatch tacs =
  let (loc, _) = tacs in
  let default = function
  | Some e -> thunk e
  | None -> thunk (Loc.tag ?loc @@ CTacCst (AbsKn (Tuple 0)))
  in
  let map e = of_pair default (fun l -> of_list ?loc default l) (Loc.tag ?loc e) in
  of_pair (fun l -> of_list ?loc default l) (fun r -> of_option ?loc map r) tacs

let make_red_flag l =
  let open Genredexpr in
  let rec add_flag red = function
  | [] -> red
  | (_, flag) :: lf ->
    let red = match flag with
    | QBeta -> { red with rBeta = true }
    | QMatch -> { red with rMatch = true }
    | QFix -> { red with rFix = true }
    | QCofix -> { red with rCofix = true }
    | QZeta -> { red with rZeta = true }
    | QConst (loc, l) ->
        if red.rDelta then
          CErrors.user_err ?loc Pp.(str
            "Cannot set both constants to unfold and constants not to unfold");
        { red with rConst = red.rConst @ l }
    | QDeltaBut (loc, l) ->
        if red.rConst <> [] && not red.rDelta then
          CErrors.user_err ?loc Pp.(str
            "Cannot set both constants to unfold and constants not to unfold");
        { red with rConst = red.rConst @ l; rDelta = true }
    | QIota ->
      { red with rMatch = true; rFix = true; rCofix = true }
    in
    add_flag red lf
  in
  add_flag
    {rBeta = false; rMatch = false; rFix = false; rCofix = false;
     rZeta = false; rDelta = false; rConst = []}
    l

let of_reference r =
  let of_ref ref =
    let loc = Libnames.loc_of_reference ref in
    inj_wit ?loc wit_reference ref
  in
  of_anti of_ref r

let of_strategy_flag (loc, flag) =
  let open Genredexpr in
  let flag = make_red_flag flag in
  Loc.tag ?loc @@ CTacRec ([
    std_proj "rBeta", of_bool ?loc flag.rBeta;
    std_proj "rMatch", of_bool ?loc flag.rMatch;
    std_proj "rFix", of_bool ?loc flag.rFix;
    std_proj "rCofix", of_bool ?loc flag.rCofix;
    std_proj "rZeta", of_bool ?loc flag.rZeta;
    std_proj "rDelta", of_bool ?loc flag.rDelta;
    std_proj "rConst", of_list ?loc of_reference flag.rConst;
  ])

let of_hintdb (loc, hdb) = match hdb with
| QHintAll -> of_option ?loc (fun l -> of_list (fun id -> of_anti of_ident id) l) None
| QHintDbs ids -> of_option ?loc (fun l -> of_list (fun id -> of_anti of_ident id) l) (Some ids)

let pattern_vars pat =
  let rec aux () accu pat = match pat.CAst.v with
  | Constrexpr.CPatVar id -> Id.Set.add id accu
  | Constrexpr.CEvar (id, []) -> Id.Set.add id accu
  | _ ->
    Topconstr.fold_constr_expr_with_binders (fun _ () -> ()) aux () accu pat
  in
  aux () Id.Set.empty pat

let of_constr_matching (loc, m) =
  let check_id loc id =
    if Tac2env.is_constructor (Libnames.qualid_of_ident id) then
      CErrors.user_err ?loc (str "Invalid pattern binding name " ++ Id.print id)
  in
  let abstract_vars loc pat tac =
    let vars = pattern_vars pat in
    let na, tac =
      if Id.Set.is_empty vars then (Anonymous, tac)
      else
        (** Trick: in order not to shadow a variable nor to choose an arbitrary
            name, we reuse one which is going to be shadowed by the matched
            variables anyways. *)
        let id0 = Id.Set.choose vars in
        let build_bindings id (n, accu) =
          let () = check_id loc id in
          let get = global_ref ?loc (kername array_prefix "get")  in
          let args = [of_variable (loc, id0); of_int (loc, n)] in
          let e = Loc.tag ?loc @@ CTacApp (get, args) in
          let accu = (Loc.tag ?loc @@ CPatVar (Name id), None, e) :: accu in
          (n + 1, accu)
        in
        let (_, bnd) = Id.Set.fold build_bindings vars (0, []) in
        let tac = Loc.tag ?loc @@ CTacLet (false, bnd, tac) in
        (Name id0, tac)
    in
    Loc.tag ?loc @@ CTacFun ([Loc.tag ?loc @@ CPatVar na, None], tac)
  in
  let map (loc, p) = match p with
  | QConstrMatchPattern (pat, tac) ->
    let e = abstract_vars loc pat tac in
    let pat = inj_wit ?loc wit_pattern pat in
    constructor ?loc (pattern_core "ConstrMatchPattern") [pat; e]
  | QConstrMatchContext (id, pat, tac) ->
    let e = abstract_vars loc pat tac in
    let na = match id with
    | None -> Anonymous
    | Some id ->
      let () = check_id loc id in
      Name id
    in
    let e = Loc.tag ?loc @@ CTacFun ([Loc.tag ?loc @@ CPatVar na, None], e) in
    let pat = inj_wit ?loc wit_pattern pat in
    constructor ?loc (pattern_core "ConstrMatchContext") [pat; e]
  in
  of_list ?loc map m

let of_move_location (loc, mv) = match mv with
| QMoveAfter id -> std_constructor ?loc "MoveAfter" [of_anti of_ident id]
| QMoveBefore id -> std_constructor ?loc "MoveBefore" [of_anti of_ident id]
| QMoveFirst -> std_constructor ?loc "MoveFirst" []
| QMoveLast -> std_constructor ?loc "MoveLast" []

let of_pose p =
  of_pair (fun id -> of_option (fun id -> of_anti of_ident id) id) of_open_constr p

let of_assertion (loc, ast) = match ast with
| QAssertType (ipat, c, tac) ->
  let ipat = of_option of_intro_pattern ipat in
  let c = of_constr c in
  let tac = of_option thunk tac in
  std_constructor ?loc "AssertType" [ipat; c; tac]
| QAssertValue (id, c) ->
  let id = of_anti of_ident id in
  let c = of_constr c in
  std_constructor ?loc "AssertValue" [id; c]
