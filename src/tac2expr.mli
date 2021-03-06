(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, *   INRIA - CNRS - LIX - LRI - PPS - Copyright 1999-2016     *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

open Loc
open Genarg
open Names
open Libnames

type mutable_flag = bool
type rec_flag = bool
type redef_flag = bool
type lid = Id.t
type uid = Id.t

type ltac_constant = KerName.t
type ltac_alias = KerName.t
type ltac_constructor = KerName.t
type ltac_projection = KerName.t
type type_constant = KerName.t

type tacref =
| TacConstant of ltac_constant
| TacAlias of ltac_alias

type 'a or_relid =
| RelId of qualid located
| AbsKn of 'a

(** {5 Misc} *)

type ml_tactic_name = {
  mltac_plugin : string;
  mltac_tactic : string;
}

type 'a or_tuple =
| Tuple of int
| Other of 'a

(** {5 Type syntax} *)

type raw_typexpr =
| CTypVar of Name.t located
| CTypArrow of Loc.t * raw_typexpr * raw_typexpr
| CTypRef of Loc.t * type_constant or_tuple or_relid * raw_typexpr list

type raw_typedef =
| CTydDef of raw_typexpr option
| CTydAlg of (uid * raw_typexpr list) list
| CTydRec of (lid * mutable_flag * raw_typexpr) list
| CTydOpn

type 'a glb_typexpr =
| GTypVar of 'a
| GTypArrow of 'a glb_typexpr * 'a glb_typexpr
| GTypRef of type_constant or_tuple * 'a glb_typexpr list

type glb_alg_type = {
  galg_constructors : (uid * int glb_typexpr list) list;
  (** Constructors of the algebraic type *)
  galg_nconst : int;
  (** Number of constant constructors *)
  galg_nnonconst : int;
  (** Number of non-constant constructors *)
}

type glb_typedef =
| GTydDef of int glb_typexpr option
| GTydAlg of glb_alg_type
| GTydRec of (lid * mutable_flag * int glb_typexpr) list
| GTydOpn

type type_scheme = int * int glb_typexpr

type raw_quant_typedef = Id.t located list * raw_typedef
type glb_quant_typedef = int * glb_typedef

(** {5 Term syntax} *)

type atom =
| AtmInt of int
| AtmStr of string

(** Tactic expressions *)
type raw_patexpr =
| CPatVar of Name.t located
| CPatRef of Loc.t * ltac_constructor or_tuple or_relid * raw_patexpr list

type raw_tacexpr =
| CTacAtm of atom located
| CTacRef of tacref or_relid
| CTacCst of Loc.t * ltac_constructor or_tuple or_relid
| CTacFun of Loc.t * (raw_patexpr * raw_typexpr option) list * raw_tacexpr
| CTacApp of Loc.t * raw_tacexpr * raw_tacexpr list
| CTacLet of Loc.t * rec_flag * (raw_patexpr * raw_typexpr option * raw_tacexpr) list * raw_tacexpr
| CTacCnv of Loc.t * raw_tacexpr * raw_typexpr
| CTacSeq of Loc.t * raw_tacexpr * raw_tacexpr
| CTacCse of Loc.t * raw_tacexpr * raw_taccase list
| CTacRec of Loc.t * raw_recexpr
| CTacPrj of Loc.t * raw_tacexpr * ltac_projection or_relid
| CTacSet of Loc.t * raw_tacexpr * ltac_projection or_relid * raw_tacexpr
| CTacExt of Loc.t * raw_generic_argument

and raw_taccase = raw_patexpr * raw_tacexpr

and raw_recexpr = (ltac_projection or_relid * raw_tacexpr) list

type case_info = type_constant or_tuple

type 'a open_match = {
  opn_match : 'a;
  opn_branch : (Name.t * Name.t array * 'a) KNmap.t;
  (** Invariant: should not be empty *)
  opn_default : Name.t * 'a;
}

type glb_tacexpr =
| GTacAtm of atom
| GTacVar of Id.t
| GTacRef of ltac_constant
| GTacFun of Name.t list * glb_tacexpr
| GTacApp of glb_tacexpr * glb_tacexpr list
| GTacLet of rec_flag * (Name.t * glb_tacexpr) list * glb_tacexpr
| GTacArr of glb_tacexpr list
| GTacCst of case_info * int * glb_tacexpr list
| GTacCse of glb_tacexpr * case_info * glb_tacexpr array * (Name.t array * glb_tacexpr) array
| GTacPrj of type_constant * glb_tacexpr * int
| GTacSet of type_constant * glb_tacexpr * int * glb_tacexpr
| GTacOpn of ltac_constructor * glb_tacexpr list
| GTacWth of glb_tacexpr open_match
| GTacExt of glob_generic_argument
| GTacPrm of ml_tactic_name * glb_tacexpr list

(** {5 Parsing & Printing} *)

type exp_level =
| E5
| E4
| E3
| E2
| E1
| E0

type sexpr =
| SexprStr of string located
| SexprInt of int located
| SexprRec of Loc.t * Id.t option located * sexpr list

(** {5 Toplevel statements} *)

type strexpr =
| StrVal of rec_flag * (Name.t located * raw_tacexpr) list
  (** Term definition *)
| StrTyp of rec_flag * (qualid located * redef_flag * raw_quant_typedef) list
  (** Type definition *)
| StrPrm of Id.t located * raw_typexpr * ml_tactic_name
  (** External definition *)
| StrSyn of sexpr list * int option * raw_tacexpr
  (** Syntactic extensions *)


(** {5 Dynamic semantics} *)

(** Values are represented in a way similar to OCaml, i.e. they constrast
    immediate integers (integers, constructors without arguments) and structured
    blocks (tuples, arrays, constructors with arguments), as well as a few other
    base cases, namely closures, strings, named constructors, and dynamic type
    coming from the Coq implementation. *)

type tag = int

type valexpr =
| ValInt of int
  (** Immediate integers *)
| ValBlk of tag * valexpr array
  (** Structured blocks *)
| ValStr of Bytes.t
  (** Strings *)
| ValCls of closure
  (** Closures *)
| ValOpn of KerName.t * valexpr array
  (** Open constructors *)
| ValExt of Geninterp.Val.t
  (** Arbitrary data *)

and closure = {
  mutable clos_env : valexpr Id.Map.t;
  (** Mutable so that we can implement recursive functions imperatively *)
  clos_var : Name.t list;
  (** Bound variables *)
  clos_exp : glb_tacexpr;
  (** Body *)
}

type ml_tactic = valexpr list -> valexpr Proofview.tactic

type environment = valexpr Id.Map.t
