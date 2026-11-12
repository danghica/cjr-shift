(** Application ports and their Iris contracts. *)
From Coq Require Import String List ZArith Lia.
From Tracker Require Import Tracker Model Pure Runtime Contracts Operations.
From iris.prelude Require Import options.
Import ListNotations Model.
Local Open Scope string_scope.
Local Open Scope Z_scope.
Ltac known_insert := first [known_helpers |
 (eapply executes_result; [apply insert_exec; lia|congruence])].
Lemma add_exec st s e : pending_valid st ->
 executes (invoke addPair_val [statev st;intv s;intv e]) (answerv (add_pair st s e)).
Proof.
 destruct st as [xs p]. destruct p as [p|]; cbn [pending_valid pending]; intros Hp.
 all: unfold invoke,addPair_val at 1; eapply ExApp; [constructor|constructor|]; normalize;
 do 3 (eapply ExLet; [run|]; normalize).
 - unfold add_pair,reserved,answerv,failure,statev. cbn [shifts pending code updated rows].
   destruct (Z.ltb_spec s 0); destruct (Z.leb_spec e s); destruct (Z.ltb_spec p e);
   destruct (overlaps xs s e) eqn:Ho; solve [execute ltac:(first [use_execution (overlaps_exec xs s e) | let Hs := fresh in assert (0 <= s) as Hs by lia; use_execution (insert_exec xs s e Hs)])].
 - unfold add_pair,reserved,answerv,failure,statev. cbn [shifts pending code updated rows].
   destruct (Z.ltb_spec s 0); destruct (Z.leb_spec e s);
   destruct (overlaps xs s e) eqn:Ho; solve [execute ltac:(first [use_execution (overlaps_exec xs s e) | let Hs := fresh in assert (0 <= s) as Hs by lia; use_execution (insert_exec xs s e Hs)])].
Qed.
Lemma end_exec st e : pending_valid st ->
 executes (invoke endShift_val [statev st;intv e]) (answerv (end_shift st e)).
Proof.
 destruct st as [xs p]. destruct p as [p|]; cbn [pending_valid pending]; intros Hp.
 all: unfold invoke,endShift_val at 1; eapply ExApp; [constructor|constructor|]; normalize;
 do 2 (eapply ExLet; [run|]; normalize).
 - unfold end_shift. cbn [pending shifts].
   remember (add_pair (State xs None) p e) as completed eqn:Hcompleted.
   eapply ExIfFalse.
   { execute ltac:(fail). }
   eapply ExLet.
   { eapply call_exec; [run|]. pose proof (add_exec (State xs None) p e I) as Hrun.
     rewrite <- Hcompleted in Hrun. exact Hrun. }
   clear Hcompleted. normalize. destruct (Z.eqb_spec (code completed) 0); solve [execute ltac:(fail)].
 - unfold end_shift,answerv,failure,statev. cbn [pending code updated rows]. solve [execute ltac:(fail)].
Qed.

Definition port name args := erase tracker_layouts (link_functions tracker_layouts [] tracker_functions)
 (GECall name [] (map GEVal args)).
Lemma port_exec name args f result :
 glookup name tracker_runtime = Some f -> executes (invoke f args) result -> executes (port name args) result.
Proof.
 intros Hlookup Hrun. unfold port. rewrite tracker_linked. cbn [erase]. unfold resolve. rewrite Hlookup.
 eapply call_exec; [|exact Hrun]. unfold gpack. rewrite map_map.
 change (executes (Struct [] (map Val args)) (StructV args)). exact (pack_exec [] args).
Qed.
Section iris_contracts.
Context `{!cjrGS Σ} `{!invGS_gen HasLc Σ}.
Theorem emptyState_correct : ⊢ WP port "emptyState" [] {{ v, ⌜v = statev (State [] None)⌝ }}.
Proof. apply executes_wp. eapply port_exec; [reflexivity|apply empty_state_exec]. Qed.
Theorem addPair_correct st s e : pending_valid st ->
 ⊢ WP port "addPair" [statev st;intv s;intv e] {{ v, ⌜v = answerv (add_pair st s e)⌝ }}.
Proof. intros Hp. apply executes_wp. eapply port_exec; [reflexivity|apply add_exec; exact Hp]. Qed.
Theorem startShift_correct st s : pending_valid st ->
 ⊢ WP port "startShift" [statev st;intv s] {{ v, ⌜v = answerv (start_shift st s)⌝ }}.
Proof. intros Hp. apply executes_wp. eapply port_exec; [reflexivity|apply start_exec; exact Hp]. Qed.
Theorem endShift_correct st e : pending_valid st ->
 ⊢ WP port "endShift" [statev st;intv e] {{ v, ⌜v = answerv (end_shift st e)⌝ }}.
Proof. intros Hp. apply executes_wp. eapply port_exec; [reflexivity|apply end_exec; exact Hp]. Qed.
Theorem queryContained_correct st s e :
 ⊢ WP port "queryContained" [statev st;intv s;intv e] {{ v, ⌜v = answerv (query false st s e)⌝ }}.
Proof. apply executes_wp. eapply port_exec; [reflexivity|apply query_contained_exec]. Qed.
Theorem queryIntersecting_correct st s e :
 ⊢ WP port "queryIntersecting" [statev st;intv s;intv e] {{ v, ⌜v = answerv (query true st s e)⌝ }}.
Proof. apply executes_wp. eapply port_exec; [reflexivity|apply query_intersecting_exec]. Qed.
Theorem deleteShift_correct st s :
 ⊢ WP port "deleteShift" [statev st;intv s] {{ v, ⌜v = answerv (delete_shift st s)⌝ }}.
Proof. apply executes_wp. eapply port_exec; [reflexivity|apply delete_exec]. Qed.
End iris_contracts.
