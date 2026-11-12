(** Public operation refinements, built from the pure-list helper contracts. *)
From Coq Require Import String List ZArith Lia.
From Tracker Require Import Tracker Model Pure Runtime Contracts.
From iris.prelude Require Import options.
Import ListNotations Model.
Local Open Scope string_scope.
Local Open Scope Z_scope.
Lemma executes_result e v w : executes e v -> v = w -> executes e w.
Proof. intros H ->. assumption. Qed.
Ltac use_execution theorem :=
 let Hexec := fresh "Hexecution" in pose proof theorem as Hexec;
 repeat match goal with Heq : ?a = ?b |- _ => progress rewrite Heq in Hexec end;
 exact Hexec.
Ltac known_helpers := first [
 (eapply executes_result; [apply overlaps_exec|congruence]) |
 (eapply executes_result; [apply ends_exec|congruence]) |
 (eapply executes_result; [apply has_exec|congruence]) |
 (eapply executes_result; [apply remove_exec|congruence]) |
 (eapply executes_result; [apply select_exec|congruence])].

Lemma split_exec fuel s e rest : 0 <= s -> e-s < Z.of_nat fuel ->
 executes (invoke splitOnto_val [intv s;intv e;listv rest]) (listv (split_fuel fuel s e ++ rest)).
Proof.
 revert s. induction fuel as [|fuel IH]; intros s Hs Hfuel.
 - cbn [split_fuel app]. unfold invoke,splitOnto_val at 1. eapply ExApp; [constructor|constructor|]. normalize.
   do 3 (eapply ExLet; [run|]; normalize). solve [execute ltac:(fail)].
 - cbn [split_fuel]. destruct (Z.leb_spec e s) as [Hdone|Hmore].
   + cbn [app]. unfold invoke,splitOnto_val at 1. eapply ExApp; [constructor|constructor|]. normalize.
     do 3 (eapply ExLet; [run|]; normalize). solve [execute ltac:(fail)].
   + pose proof (boundary_bounds s e Hs Hmore) as Hb.
     specialize (IH (boundary s e) ltac:(lia) ltac:(rewrite Nat2Z.inj_succ in Hfuel; lia)).
     unfold invoke,splitOnto_val at 1. eapply ExApp; [constructor|constructor|]. normalize.
     do 3 (eapply ExLet; [run|]; normalize).
     cbn [app listv].
     unfold boundary in *. solve [execute ltac:(exact IH)].
Qed.
Lemma daily_exec s e rest : 0 <= s ->
 executes (invoke splitOnto_val [intv s;intv e;listv rest]) (listv (split_daily s e ++ rest)).
Proof.
 intros Hs. unfold split_daily. apply split_exec; auto.
 rewrite Nat2Z.inj_succ. destruct (Z_le_dec 0 (e-s)).
 - rewrite Z2Nat.id; lia.
 - pose proof (Nat2Z.is_nonneg (Z.to_nat (e-s))). lia.
Qed.
Lemma insert_exec xs s e : 0 <= s ->
 executes (invoke insertDaily_val [listv xs;intv s;intv e]) (listv (splice s (split_daily s e) xs)).
Proof.
 intros Hs. induction xs as [|[a b] xs IH].
 all: unfold invoke,insertDaily_val at 1; eapply ExApp; [constructor|constructor|]; normalize;
 do 3 (eapply ExLet; [run|]; normalize).
 - cbn [splice]. eapply ExIfTrue; [run|]. eapply call_exec; [run|].
   pose proof (daily_exec s e [] Hs) as Hsplit. rewrite app_nil_r in Hsplit. exact Hsplit.
 - cbn [splice start fst]. destruct (Z.leb_spec s a); cbn [app listv].
   + solve [execute ltac:(apply (daily_exec s e ((a,b)::xs)); assumption)].
   + solve [execute ltac:(exact IH)].
Qed.
Definition pending_valid st := match pending st with None => True | Some p => 0 <= p end.
Lemma empty_state_exec : executes (invoke emptyState_val []) (statev (State [] None)).
Proof.
 unfold invoke,emptyState_val. eapply ExApp; [constructor|constructor|]. normalize. solve [execute ltac:(fail)].
Qed.
Lemma start_exec st s : pending_valid st ->
 executes (invoke startShift_val [statev st;intv s]) (answerv (start_shift st s)).
Proof.
 destruct st as [xs p]. destruct p as [p|]; cbn [pending_valid pending]; intros Hp.
 all: unfold invoke,startShift_val at 1; eapply ExApp; [constructor|constructor|]; normalize;
 do 2 (eapply ExLet; [run|]; normalize).
 - unfold start_shift,answerv,failure,statev. cbn [shifts pending code updated rows].
   destruct (Z.ltb_spec s 0); solve [execute ltac:(fail)].
 - unfold start_shift,answerv,failure,statev. cbn [shifts pending code updated rows].
   destruct (Z.ltb_spec s 0) as [Hnegative|Hpositive].
   { solve [execute ltac:(fail)]. }
   eapply ExIfFalse; [execute ltac:(fail)|].
   eapply ExIfFalse; [execute ltac:(fail)|].
   destruct (ends_after xs s) eqn:Hends.
   + eapply ExIfTrue.
     { eapply call_exec; [run|]. pose proof (ends_exec xs s) as Hrun. rewrite Hends in Hrun. exact Hrun. }
     run.
   + eapply ExIfFalse.
     { eapply call_exec; [run|]. pose proof (ends_exec xs s) as Hrun. rewrite Hends in Hrun. exact Hrun. }
     run.

Qed.
Lemma delete_exec st s : executes (invoke deleteShift_val [statev st;intv s]) (answerv (delete_shift st s)).
Proof.
 destruct st as [xs p]. unfold invoke,deleteShift_val at 1. eapply ExApp; [constructor|constructor|]. normalize.
 do 2 (eapply ExLet; [run|]; normalize).
 unfold delete_shift,answerv,failure,statev. cbn [shifts pending code updated rows].
 destruct (Z.ltb_spec s 0); destruct (existsb (fun x => start x =? s) xs) eqn:Hhas;
 solve [execute ltac:(first [use_execution (has_exec xs s) | use_execution (remove_exec xs s)])].
Qed.
Lemma query_contained_exec st s e :
 executes (invoke queryContained_val [statev st;intv s;intv e]) (answerv (query false st s e)).
Proof.
 unfold invoke,queryContained_val at 1. eapply ExApp; [constructor|constructor|]. normalize.
 do 3 (eapply ExLet; [run|]; normalize).
 unfold query,answerv,failure,statev. cbn [code updated rows].
 destruct (Z.ltb_spec s 0); destruct (Z.leb_spec e s); solve [execute ltac:(use_execution (select_exec false (shifts st) s e))].
Qed.
Lemma query_intersecting_exec st s e :
 executes (invoke queryIntersecting_val [statev st;intv s;intv e]) (answerv (query true st s e)).
Proof.
 unfold invoke,queryIntersecting_val at 1. eapply ExApp; [constructor|constructor|]. normalize.
 do 3 (eapply ExLet; [run|]; normalize).
 unfold query,answerv,failure,statev. cbn [code updated rows].
 destruct (Z.ltb_spec s 0); destruct (Z.leb_spec e s); solve [execute ltac:(use_execution (select_exec true (shifts st) s e))].
Qed.
