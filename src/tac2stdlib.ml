(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, *   INRIA - CNRS - LIX - LRI - PPS - Copyright 1999-2016     *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

open Names
open Locus
open Globnames
open Misctypes
open Genredexpr
open Tac2expr
open Proofview.Notations

module Value = Tac2ffi

let return x = Proofview.tclUNIT x
let v_unit = Value.of_unit ()
let thaw f = Tac2interp.interp_app f [v_unit]

let to_pair f g = function
| ValBlk (0, [| x; y |]) -> (f x, g y)
| _ -> assert false

let to_name c = match Value.to_option Value.to_ident c with
| None -> Anonymous
| Some id -> Name id

let to_qhyp = function
| ValBlk (0, [| i |]) -> AnonHyp (Value.to_int i)
| ValBlk (1, [| id |]) -> NamedHyp (Value.to_ident id)
| _ -> assert false

let to_bindings = function
| ValInt 0 -> NoBindings
| ValBlk (0, [| vl |]) ->
  ImplicitBindings (Value.to_list Value.to_constr vl)
| ValBlk (1, [| vl |]) ->
  ExplicitBindings ((Value.to_list (fun p -> None, to_pair to_qhyp Value.to_constr p) vl))
| _ -> assert false

let to_constr_with_bindings = function
| ValBlk (0, [| c; bnd |]) -> (Value.to_constr c, to_bindings bnd)
| _ -> assert false

let to_int_or_var i = ArgArg (Value.to_int i)

let to_occurrences f = function
| ValInt 0 -> AllOccurrences
| ValBlk (0, [| vl |]) -> AllOccurrencesBut (Value.to_list f vl)
| ValInt 1 -> NoOccurrences
| ValBlk (1, [| vl |]) -> OnlyOccurrences (Value.to_list f vl)
| _ -> assert false

let to_hyp_location_flag = function
| ValInt 0 -> InHyp
| ValInt 1 -> InHypTypeOnly
| ValInt 2 -> InHypValueOnly
| _ -> assert false

let to_clause = function
| ValBlk (0, [| hyps; concl |]) ->
  let cast = function
  | ValBlk (0, [| hyp; occ; flag |]) ->
    ((to_occurrences to_int_or_var occ, Value.to_ident hyp), to_hyp_location_flag flag)
  | _ -> assert false
  in
  let hyps = Value.to_option (fun h -> Value.to_list cast h) hyps in
  { onhyps = hyps; concl_occs = to_occurrences to_int_or_var concl; }
| _ -> assert false

let to_red_flag = function
| ValBlk (0, [| beta; iota; fix; cofix; zeta; delta; const |]) ->
  {
    rBeta = Value.to_bool beta;
    rMatch = Value.to_bool iota;
    rFix = Value.to_bool fix;
    rCofix = Value.to_bool cofix;
    rZeta = Value.to_bool zeta;
    rDelta = Value.to_bool delta;
    rConst = Value.to_list Value.to_reference const;
  }
| _ -> assert false

let to_pattern_with_occs pat =
  to_pair Value.to_pattern (fun occ -> to_occurrences to_int_or_var occ) pat

let to_constr_with_occs c =
  let (c, occ) = to_pair Value.to_constr (fun occ -> to_occurrences to_int_or_var occ) c in
  (occ, c)

let rec to_intro_pattern = function
| ValBlk (0, [| b |]) -> IntroForthcoming (Value.to_bool b)
| ValBlk (1, [| pat |]) -> IntroNaming (to_intro_pattern_naming pat)
| ValBlk (2, [| act |]) -> IntroAction (to_intro_pattern_action act)
| _ -> assert false

and to_intro_pattern_naming = function
| ValBlk (0, [| id |]) -> IntroIdentifier (Value.to_ident id)
| ValBlk (1, [| id |]) -> IntroFresh (Value.to_ident id)
| ValInt 0 -> IntroAnonymous
| _ -> assert false

and to_intro_pattern_action = function
| ValInt 0 -> IntroWildcard
| ValBlk (0, [| op |]) -> IntroOrAndPattern (to_or_and_intro_pattern op)
| ValBlk (1, [| inj |]) ->
  let map ipat = Loc.tag (to_intro_pattern ipat) in
  IntroInjection (Value.to_list map inj)
| ValBlk (2, [| _ |]) -> IntroApplyOn (assert false, assert false) (** TODO *)
| ValBlk (3, [| b |]) -> IntroRewrite (Value.to_bool b)
| _ -> assert false

and to_or_and_intro_pattern = function
| ValBlk (0, [| ill |]) ->
  IntroOrPattern (Value.to_list to_intro_patterns ill)
| ValBlk (1, [| il |]) ->
  IntroAndPattern (to_intro_patterns il)
| _ -> assert false

and to_intro_patterns il =
  let map ipat = Loc.tag (to_intro_pattern ipat) in
  Value.to_list map il

let to_destruction_arg = function
| ValBlk (0, [| c |]) ->
  let c = thaw c >>= fun c -> return (to_constr_with_bindings c) in
  ElimOnConstr c
| ValBlk (1, [| id |]) -> ElimOnIdent (Loc.tag (Value.to_ident id))
| ValBlk (2, [| n |]) -> ElimOnAnonHyp (Value.to_int n)
| _ -> assert false

let to_induction_clause = function
| ValBlk (0, [| arg; eqn; as_; in_ |]) ->
  let arg = to_destruction_arg arg in
  let eqn = Value.to_option (fun p -> Loc.tag (to_intro_pattern_naming p)) eqn in
  let as_ = Value.to_option (fun p -> Loc.tag (to_or_and_intro_pattern p)) as_ in
  let in_ = Value.to_option to_clause in_ in
  ((None, arg), eqn, as_, in_)
| _ ->
  assert false

let to_multi = function
| ValBlk (0, [| n |]) -> Precisely (Value.to_int n)
| ValBlk (1, [| n |]) -> UpTo (Value.to_int n)
| ValInt 0 -> RepeatStar
| ValInt 1 -> RepeatPlus
| _ -> assert false

let to_rewriting = function
| ValBlk (0, [| orient; repeat; c |]) ->
  let orient = Value.to_option Value.to_bool orient in
  let repeat = to_multi repeat in
  let c = thaw c >>= fun c -> return (to_constr_with_bindings c) in
  (orient, repeat, c)
| _ -> assert false

(** Standard tactics sharing their implementation with Ltac1 *)

let pname s = { mltac_plugin = "ltac2"; mltac_tactic = s }

let lift tac = tac <*> return v_unit

let define_prim0 name tac =
  let tac = function
  | [_] -> lift tac
  | _ -> assert false
  in
  Tac2env.define_primitive (pname name) tac

let define_prim1 name tac =
  let tac = function
  | [x] -> lift (tac x)
  | _ -> assert false
  in
  Tac2env.define_primitive (pname name) tac

let define_prim2 name tac =
  let tac = function
  | [x; y] -> lift (tac x y)
  | _ -> assert false
  in
  Tac2env.define_primitive (pname name) tac

let define_prim3 name tac =
  let tac = function
  | [x; y; z] -> lift (tac x y z)
  | _ -> assert false
  in
  Tac2env.define_primitive (pname name) tac

let define_prim4 name tac =
  let tac = function
  | [x; y; z; u] -> lift (tac x y z u)
  | _ -> assert false
  in
  Tac2env.define_primitive (pname name) tac

(** Tactics from Tacexpr *)

let () = define_prim2 "tac_intros" begin fun ev ipat ->
  let ev = Value.to_bool ev in
  let ipat = to_intro_patterns ipat in
  Tactics.intros_patterns ev ipat
end

let () = define_prim4 "tac_apply" begin fun adv ev cb ipat ->
  let adv = Value.to_bool adv in
  let ev = Value.to_bool ev in
  let map_cb c = thaw c >>= fun c -> return (to_constr_with_bindings c) in
  let cb = Value.to_list map_cb cb in
  let map p = Value.to_option (fun p -> Loc.tag (to_intro_pattern p)) p in
  let map_ipat p = to_pair Value.to_ident map p in
  let ipat = Value.to_option map_ipat ipat in
  Tac2tactics.apply adv ev cb ipat
end

let () = define_prim3 "tac_elim" begin fun ev c copt ->
  let ev = Value.to_bool ev in
  let c = to_constr_with_bindings c in
  let copt = Value.to_option to_constr_with_bindings copt in
  Tactics.elim ev None c copt
end

let () = define_prim2 "tac_case" begin fun ev c ->
  let ev = Value.to_bool ev in
  let c = to_constr_with_bindings c in
  Tactics.general_case_analysis ev None c
end

let () = define_prim1 "tac_generalize" begin fun cl ->
  let cast = function
  | ValBlk (0, [| c; occs; na |]) ->
    ((to_occurrences Value.to_int occs, Value.to_constr c), to_name na)
  | _ -> assert false
  in
  let cl = Value.to_list cast cl in
  Tactics.new_generalize_gen cl
end

let () = define_prim3 "tac_assert" begin fun c tac ipat ->
  let c = Value.to_constr c in
  let of_tac t = Proofview.tclIGNORE (thaw t) in
  let tac = Value.to_option (fun t -> Value.to_option of_tac t) tac in
  let ipat = Value.to_option (fun ipat -> Loc.tag (to_intro_pattern ipat)) ipat in
  Tactics.forward true tac ipat c
end

let () = define_prim3 "tac_enough" begin fun c tac ipat ->
  let c = Value.to_constr c in
  let of_tac t = Proofview.tclIGNORE (thaw t) in
  let tac = Value.to_option (fun t -> Value.to_option of_tac t) tac in
  let ipat = Value.to_option (fun ipat -> Loc.tag (to_intro_pattern ipat)) ipat in
  Tactics.forward false tac ipat c
end

let () = define_prim2 "tac_pose" begin fun idopt c ->
  let na = to_name idopt in
  let c = Value.to_constr c in
  Tactics.letin_tac None na c None Locusops.nowhere
end

let () = define_prim4 "tac_set" begin fun ev idopt c cl ->
  let ev = Value.to_bool ev in
  let na = to_name idopt in
  let cl = to_clause cl in
  Proofview.tclEVARMAP >>= fun sigma ->
  thaw c >>= fun c ->
  let c = Value.to_constr c in
  Tactics.letin_pat_tac ev None na (sigma, c) cl
end

let () = define_prim3 "tac_destruct" begin fun ev ic using ->
  let ev = Value.to_bool ev in
  let ic = Value.to_list to_induction_clause ic in
  let using = Value.to_option to_constr_with_bindings using in
  Tac2tactics.induction_destruct false ev ic using
end

let () = define_prim3 "tac_induction" begin fun ev ic using ->
  let ev = Value.to_bool ev in
  let ic = Value.to_list to_induction_clause ic in
  let using = Value.to_option to_constr_with_bindings using in
  Tac2tactics.induction_destruct true ev ic using
end

let () = define_prim1 "tac_red" begin fun cl ->
  let cl = to_clause cl in
  Tactics.reduce (Red false) cl
end

let () = define_prim1 "tac_hnf" begin fun cl ->
  let cl = to_clause cl in
  Tactics.reduce Hnf cl
end

let () = define_prim3 "tac_simpl" begin fun flags where cl ->
  let flags = to_red_flag flags in
  let where = Value.to_option to_pattern_with_occs where in
  let cl = to_clause cl in
  Tac2tactics.simpl flags where cl
end

let () = define_prim2 "tac_cbv" begin fun flags cl ->
  let flags = to_red_flag flags in
  let cl = to_clause cl in
  Tac2tactics.cbv flags cl
end

let () = define_prim2 "tac_cbn" begin fun flags cl ->
  let flags = to_red_flag flags in
  let cl = to_clause cl in
  Tac2tactics.cbn flags cl
end

let () = define_prim2 "tac_lazy" begin fun flags cl ->
  let flags = to_red_flag flags in
  let cl = to_clause cl in
  Tac2tactics.lazy_ flags cl
end

let () = define_prim2 "tac_unfold" begin fun refs cl ->
  let map v = to_pair Value.to_reference (fun occ -> to_occurrences to_int_or_var occ) v in
  let refs = Value.to_list map refs in
  let cl = to_clause cl in
  Tac2tactics.unfold refs cl
end

let () = define_prim2 "tac_fold" begin fun args cl ->
  let args = Value.to_list Value.to_constr args in
  let cl = to_clause cl in
  Tactics.reduce (Fold args) cl
end

let () = define_prim2 "tac_pattern" begin fun where cl ->
  let where = Value.to_list to_constr_with_occs where in
  let cl = to_clause cl in
  Tactics.reduce (Pattern where) cl
end

let () = define_prim2 "tac_vm" begin fun where cl ->
  let where = Value.to_option to_pattern_with_occs where in
  let cl = to_clause cl in
  Tac2tactics.vm where cl
end

let () = define_prim2 "tac_native" begin fun where cl ->
  let where = Value.to_option to_pattern_with_occs where in
  let cl = to_clause cl in
  Tac2tactics.native where cl
end

let () = define_prim4 "tac_rewrite" begin fun ev rw cl by ->
  let ev = Value.to_bool ev in
  let rw = Value.to_list to_rewriting rw in
  let cl = to_clause cl in
  let to_tac t = Proofview.tclIGNORE (thaw t) in
  let by = Value.to_option to_tac by in
  Tac2tactics.rewrite ev rw cl by
end

(** Tactics from coretactics *)

let () = define_prim0 "tac_reflexivity" Tactics.intros_reflexivity

(*

TACTIC EXTEND exact
  [ "exact" casted_constr(c) ] -> [ Tactics.exact_no_check c ]
END

*)

let () = define_prim0 "tac_assumption" Tactics.assumption

let () = define_prim1 "tac_transitivity" begin fun c ->
  let c = Value.to_constr c in
  Tactics.intros_transitivity (Some c)
end

let () = define_prim0 "tac_etransitivity" (Tactics.intros_transitivity None)

let () = define_prim1 "tac_cut" begin fun c ->
  let c = Value.to_constr c in
  Tactics.cut c
end

let () = define_prim2 "tac_left" begin fun ev bnd ->
  let ev = Value.to_bool ev in
  let bnd = to_bindings bnd in
  Tactics.left_with_bindings ev bnd
end
let () = define_prim2 "tac_right" begin fun ev bnd ->
  let ev = Value.to_bool ev in
  let bnd = to_bindings bnd in
  Tactics.right_with_bindings ev bnd
end

let () = define_prim1 "tac_introsuntil" begin fun h ->
  Tactics.intros_until (to_qhyp h)
end

let () = define_prim1 "tac_exactnocheck" begin fun c ->
  Tactics.exact_no_check (Value.to_constr c)
end

let () = define_prim1 "tac_vmcastnocheck" begin fun c ->
  Tactics.vm_cast_no_check (Value.to_constr c)
end

let () = define_prim1 "tac_nativecastnocheck" begin fun c ->
  Tactics.native_cast_no_check (Value.to_constr c)
end

let () = define_prim1 "tac_constructor" begin fun ev ->
  let ev = Value.to_bool ev in
  Tactics.any_constructor ev None
end

let () = define_prim3 "tac_constructorn" begin fun ev n bnd ->
  let ev = Value.to_bool ev in
  let n = Value.to_int n in
  let bnd = to_bindings bnd in
  Tactics.constructor_tac ev None n bnd
end

let () = define_prim1 "tac_symmetry" begin fun cl ->
  let cl = to_clause cl in
  Tactics.intros_symmetry cl
end

let () = define_prim2 "tac_split" begin fun ev bnd ->
  let ev = Value.to_bool ev in
  let bnd = to_bindings bnd in
  Tactics.split_with_bindings ev [bnd]
end

let () = define_prim1 "tac_rename" begin fun ids ->
  let map c = match Value.to_tuple c with
  | [|x; y|] -> (Value.to_ident x, Value.to_ident y)
  | _ -> assert false
  in
  let ids = Value.to_list map ids in
  Tactics.rename_hyp ids
end

let () = define_prim1 "tac_revert" begin fun ids ->
  let ids = Value.to_list Value.to_ident ids in
  Tactics.revert ids
end

let () = define_prim0 "tac_admit" Proofview.give_up

let () = define_prim2 "tac_fix" begin fun idopt n ->
  let idopt = Value.to_option Value.to_ident idopt in
  let n = Value.to_int n in
  Tactics.fix idopt n
end

let () = define_prim1 "tac_cofix" begin fun idopt ->
  let idopt = Value.to_option Value.to_ident idopt in
  Tactics.cofix idopt
end

let () = define_prim1 "tac_clear" begin fun ids ->
  let ids = Value.to_list Value.to_ident ids in
  Tactics.clear ids
end

let () = define_prim1 "tac_keep" begin fun ids ->
  let ids = Value.to_list Value.to_ident ids in
  Tactics.keep ids
end

let () = define_prim1 "tac_clearbody" begin fun ids ->
  let ids = Value.to_list Value.to_ident ids in
  Tactics.clear_body ids
end

(** Tactics from extratactics *)

let () = define_prim2 "tac_discriminate" begin fun ev arg ->
  let ev = Value.to_bool ev in
  let arg = Value.to_option (fun arg -> None, to_destruction_arg arg) arg in
  Tac2tactics.discriminate ev arg
end

let () = define_prim3 "tac_injection" begin fun ev ipat arg ->
  let ev = Value.to_bool ev in
  let ipat = Value.to_option to_intro_patterns ipat in
  let arg = Value.to_option (fun arg -> None, to_destruction_arg arg) arg in
  Tac2tactics.injection ev ipat arg
end

let () = define_prim1 "tac_absurd" begin fun c ->
  Contradiction.absurd (Value.to_constr c)
end

let () = define_prim1 "tac_contradiction" begin fun c ->
  let c = Value.to_option to_constr_with_bindings c in
  Contradiction.contradiction c
end

let () = define_prim4 "tac_autorewrite" begin fun all by ids cl ->
  let all = Value.to_bool all in
  let by = Value.to_option (fun tac -> Proofview.tclIGNORE (thaw tac)) by in
  let ids = Value.to_list Value.to_ident ids in
  let cl = to_clause cl in
  Tac2tactics.autorewrite ~all by ids cl
end

let () = define_prim1 "tac_subst" begin fun ids ->
  let ids = Value.to_list Value.to_ident ids in
  Equality.subst ids
end

let () = define_prim0 "tac_substall" (return () >>= fun () -> Equality.subst_all ())
