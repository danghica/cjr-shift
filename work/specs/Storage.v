(** Pure startup and atomic persistence protocol. External I/O is an adapter obligation. *)
From Coq Require Import String List ZArith Lia.
From Tracker Require Import Tracker Model Pure Runtime Contracts Operations Public Validation.
From iris.prelude Require Import options.
Import ListNotations Model.
Local Open Scope string_scope.
Local Open Scope Z_scope.
Record session := Session { committed : tracker; candidate : tracker; waiting : bool; status : Z }.
Definition sessionv t := StructV [statev (committed t);statev (candidate t);boolv (waiting t);intv (status t)].
Definition idle st c := Session st st false c.
Definition initialize_store st := if valid_state st then idle st 0 else idle (State [] None) 7.
Definition blocked t := Session (committed t) (candidate t) (waiting t) 8.
Definition stage t a := if code a =? 0 then Session (committed t) (updated a) true 0
                      else idle (committed t) (code a).
Definition prepare t a := if waiting t then blocked t else stage t a.
Definition complete_store t (ok : bool) :=
 if waiting t then if ok then idle (candidate t) 0 else idle (committed t) 9
 else Session (committed t) (candidate t) false 10.
Definition read_store mode t s e := if waiting t then failure 8 (committed t) else query mode (committed t) s e.
Definition session_invariant t := state_invariant (committed t) /\ state_invariant (candidate t).

Theorem rollback_restores t : waiting t = true -> complete_store t false = idle (committed t) 9.
Proof. intros H. unfold complete_store. rewrite H. reflexivity. Qed.
Theorem commit_adopts t : waiting t = true -> complete_store t true = idle (candidate t) 0.
Proof. intros H. unfold complete_store. rewrite H. reflexivity. Qed.
Theorem prepare_preserves_committed t a : committed (prepare t a) = committed t.
Proof. unfold prepare,stage,blocked,idle. destruct (waiting t), (code a =? 0); reflexivity. Qed.
Theorem rejected_mutation_no_request t a : waiting t = false -> code a <> 0 ->
 waiting (prepare t a) = false /\ committed (prepare t a) = committed t.
Proof. intros Hw Hc. unfold prepare,stage. rewrite Hw. assert (code a =? 0 = false) as -> by (apply Z.eqb_neq; exact Hc). split; reflexivity. Qed.
Theorem unresolved_blocks t a : waiting t = true -> prepare t a = blocked t.
Proof. intros H. unfold prepare. rewrite H. reflexivity. Qed.
Theorem query_no_mutation mode t s e : updated (read_store mode t s e) = committed t.
Proof. unfold read_store. destruct (waiting t); [reflexivity|apply query_preserves_state]. Qed.
Theorem completion_preserves_invariant t ok : session_invariant t -> session_invariant (complete_store t ok).
Proof. destruct t as [st next busy c],busy,ok; unfold session_invariant,complete_store,idle; simpl; tauto. Qed.
Theorem staged_invariant t a : session_invariant t -> state_invariant (updated a) -> session_invariant (prepare t a).
Proof. unfold session_invariant,prepare,stage,blocked,idle. destruct (waiting t), (code a =? 0); simpl; tauto. Qed.
Theorem initialized_invariant st : pending_valid st -> session_invariant (initialize_store st).
Proof. intros Hp. unfold initialize_store,session_invariant,idle. destruct (valid_state st) eqn:H; simpl; split; auto using empty_invariant; eapply validation_implies_invariant; eauto. Qed.
Theorem successful_stage_candidate t a : waiting t = false -> code a = 0 -> candidate (prepare t a) = updated a /\ waiting (prepare t a) = true.
Proof. intros Hw Hc. unfold prepare,stage. rewrite Hw Hc. split; reflexivity. Qed.
Theorem persisted_mutation t a : waiting t = false -> code a = 0 ->
 committed (complete_store (prepare t a) true) = updated a.
Proof. intros Hw Hc. unfold prepare,stage,complete_store. rewrite Hw Hc. reflexivity. Qed.
Theorem failed_mutation t a : waiting t = false -> code a = 0 ->
 complete_store (prepare t a) false = idle (committed t) 9.
Proof. intros Hw Hc. unfold prepare,stage,complete_store. rewrite Hw Hc. reflexivity. Qed.

(** External-store agreement assumes the adapter's atomic apply contract. *)
Theorem atomic_store_agreement t external ok : waiting t = true -> external = committed t ->
 committed (complete_store t ok) = (if ok then candidate t else external).
Proof. intros Hw ->. unfold complete_store. rewrite Hw. destruct ok; reflexivity. Qed.
Theorem persisted_add_round_trip mode t s e : waiting t = false ->
 Forall valid_shift (shifts (committed t)) -> code (add_pair (committed t) s e) = 0 ->
 rows (query mode (committed (complete_store (prepare t (add_pair (committed t) s e)) true)) s e) = split_daily s e.
Proof. intros Hw Hv Hc. rewrite persisted_mutation; auto. apply add_query_round_trip; auto. Qed.
Theorem persisted_duplicate_rejected t s e : waiting t = false -> code (add_pair (committed t) s e) = 0 ->
 code (add_pair (committed (complete_store (prepare t (add_pair (committed t) s e)) true)) s e) <> 0.
Proof. intros Hw Hc. rewrite persisted_mutation; auto. apply duplicate_rejected; auto. Qed.
Theorem persisted_add_invariant t s e : session_invariant t ->
 code (add_pair (committed t) s e) = 0 -> session_invariant (prepare t (add_pair (committed t) s e)).
Proof. intros Hinv Hc. apply staged_invariant; auto. apply successful_add_preserves_invariant; [exact (proj1 Hinv)|exact Hc]. Qed.
Theorem persisted_start_invariant t s : session_invariant t -> session_invariant (prepare t (start_shift (committed t) s)).
Proof. intros Hinv. apply staged_invariant; auto. apply start_preserves_invariant. exact (proj1 Hinv). Qed.
Theorem persisted_end_invariant t e : session_invariant t -> session_invariant (prepare t (end_shift (committed t) e)).
Proof. intros Hinv. apply staged_invariant; auto. apply end_preserves_invariant. exact (proj1 Hinv). Qed.
Theorem persisted_delete_invariant t s : session_invariant t -> session_invariant (prepare t (delete_shift (committed t) s)).
Proof. intros Hinv. apply staged_invariant; auto. apply deletion_preserves_invariant. exact (proj1 Hinv). Qed.

Lemma sessionv_closed t : closed_val (sessionv t).
Proof. unfold sessionv. apply structv_closed. repeat constructor; first [apply statev_closed | apply closed_lit]. Qed.
Ltac closed_value ::= first [apply sessionv_closed | assumption | apply closed_lit | apply listv_closed | apply statev_closed | apply nilv_closed | (apply structv_closed; repeat constructor; closed_value) | (apply nodev_closed; closed_value)].
Ltac storage_normalize := repeat (progress (cbn -[subst_val sessionv statev answerv listv nilv nodev emptyPieces_val consPiece_val nextMidnight_val minMinute_val overlaps_val endsAfter_val splitOnto_val insertDaily_val selectPieces_val hasStart_val removeStart_val validPieces_val emptyState_val validState_val addPair_val startShift_val endShift_val queryContained_val queryIntersecting_val deleteShift_val initializeStore_val stageChange_val prepareAddPair_val prepareStartShift_val prepareEndShift_val prepareDeleteShift_val completeStore_val readContained_val readIntersecting_val]; close_globals; repeat case_bool_decide; simplify_eq; close_values)).
Ltac normalize ::= storage_normalize.
Lemma initialize_exec st : executes (invoke initializeStore_val [statev st]) (sessionv (initialize_store st)).
Proof.
 unfold invoke,initializeStore_val at 1. eapply ExApp; [constructor|constructor|]. normalize.
 eapply ExLet; [run|]. normalize.
 unfold initialize_store. eapply ite_expression.
 { eapply call_exec; [run|apply valid_state_exec]. }
 destruct (valid_state st); unfold idle,sessionv; simpl;
 solve [execute ltac:(apply empty_state_exec)].
Qed.
Lemma stage_exec t a : executes (invoke stageChange_val [sessionv t;answerv a]) (sessionv (stage t a)).
Proof.
 destruct t as [st next busy c], a as [ac ast ar].
 unfold invoke,stageChange_val at 1. eapply ExApp; [constructor|constructor|]. normalize.
 do 2 (eapply ExLet; [run|]; normalize).
 unfold stage,sessionv,idle,answerv. simpl.
 destruct (Z.eqb_spec ac 0); solve [execute ltac:(fail)].
Qed.
Lemma complete_exec t ok : executes (invoke completeStore_val [sessionv t;boolv ok]) (sessionv (complete_store t ok)).
Proof.
 destruct t as [st next busy c],busy,ok.
 all: unfold invoke,completeStore_val at 1; eapply ExApp; [constructor|constructor|]; normalize;
 do 2 (eapply ExLet; [run|]; normalize);
 unfold complete_store,sessionv,idle; simpl; solve [execute ltac:(fail)].
Qed.
Lemma prepareAddPair_exec t s e : pending_valid (committed t) ->
 executes (invoke prepareAddPair_val [sessionv t;intv s;intv e]) (sessionv (prepare t (add_pair (committed t) s e))).
Proof.
 intros Hp. destruct t as [st next busy c].
 unfold invoke,prepareAddPair_val at 1. eapply ExApp; [constructor|constructor|]. normalize.
 do 3 (eapply ExLet; [run|]; normalize).
 unfold prepare. simpl. destruct busy.
 - unfold blocked,sessionv. simpl. solve [execute ltac:(fail)].
 - eapply ExIfFalse; [run|].
   eapply call_exec; [|apply stage_exec].
   eapply ExStructNext; [run|simpl].
   eapply ExStructNext.
   + eapply call_exec; [run|apply add_exec; exact Hp].
   + simpl. constructor.
Qed.
Lemma prepareStartShift_exec t s : pending_valid (committed t) ->
 executes (invoke prepareStartShift_val [sessionv t;intv s]) (sessionv (prepare t (start_shift (committed t) s))).
Proof.
 intros Hp. destruct t as [st next busy c].
 unfold invoke,prepareStartShift_val at 1. eapply ExApp; [constructor|constructor|]. normalize.
 do 2 (eapply ExLet; [run|]; normalize).
 unfold prepare. simpl. destruct busy.
 - unfold blocked,sessionv. simpl. solve [execute ltac:(fail)].
 - eapply ExIfFalse; [run|].
   eapply call_exec; [|apply stage_exec].
   eapply ExStructNext; [run|simpl].
   eapply ExStructNext.
   + eapply call_exec; [run|apply start_exec; exact Hp].
   + simpl. constructor.
Qed.
Lemma prepareEndShift_exec t e : pending_valid (committed t) ->
 executes (invoke prepareEndShift_val [sessionv t;intv e]) (sessionv (prepare t (end_shift (committed t) e))).
Proof.
 intros Hp. destruct t as [st next busy c].
 unfold invoke,prepareEndShift_val at 1. eapply ExApp; [constructor|constructor|]. normalize.
 do 2 (eapply ExLet; [run|]; normalize).
 unfold prepare. simpl. destruct busy.
 - unfold blocked,sessionv. simpl. solve [execute ltac:(fail)].
 - eapply ExIfFalse; [run|].
   eapply call_exec; [|apply stage_exec].
   eapply ExStructNext; [run|simpl].
   eapply ExStructNext.
   + eapply call_exec; [run|apply end_exec; exact Hp].
   + simpl. constructor.
Qed.
Lemma prepareDeleteShift_exec t s : pending_valid (committed t) ->
 executes (invoke prepareDeleteShift_val [sessionv t;intv s]) (sessionv (prepare t (delete_shift (committed t) s))).
Proof.
 intros Hp. destruct t as [st next busy c].
 unfold invoke,prepareDeleteShift_val at 1. eapply ExApp; [constructor|constructor|]. normalize.
 do 2 (eapply ExLet; [run|]; normalize).
 unfold prepare. simpl. destruct busy.
 - unfold blocked,sessionv. simpl. solve [execute ltac:(fail)].
 - eapply ExIfFalse; [run|].
   eapply call_exec; [|apply stage_exec].
   eapply ExStructNext; [run|simpl].
   eapply ExStructNext.
   + eapply call_exec; [run|apply delete_exec].
   + simpl. constructor.
Qed.
Lemma readContained_exec t s e : executes (invoke readContained_val [sessionv t;intv s;intv e]) (answerv (read_store false t s e)).
Proof.
 destruct t as [st next busy c]. unfold invoke,readContained_val at 1.
 eapply ExApp; [constructor|constructor|]. normalize.
 do 3 (eapply ExLet; [run|]; normalize).
 unfold read_store. simpl. destruct busy.
 - unfold failure,answerv. simpl. solve [execute ltac:(fail)].
 - eapply ExIfFalse; [run|]. eapply call_exec; [run|apply query_contained_exec].
Qed.
Lemma readIntersecting_exec t s e : executes (invoke readIntersecting_val [sessionv t;intv s;intv e]) (answerv (read_store true t s e)).
Proof.
 destruct t as [st next busy c]. unfold invoke,readIntersecting_val at 1.
 eapply ExApp; [constructor|constructor|]. normalize.
 do 3 (eapply ExLet; [run|]; normalize).
 unfold read_store. simpl. destruct busy.
 - unfold failure,answerv. simpl. solve [execute ltac:(fail)].
 - eapply ExIfFalse; [run|]. eapply call_exec; [run|apply query_intersecting_exec].
Qed.
Section iris_contracts.
Context `{!cjrGS Σ} `{!invGS_gen HasLc Σ}.
Theorem initializeStore_correct st : ⊢ WP port "initializeStore" [statev st] {{ v, ⌜v = sessionv (initialize_store st)⌝ }}.
Proof. apply executes_wp. eapply port_exec; [reflexivity|apply initialize_exec]. Qed.
Theorem completeStore_correct t ok : ⊢ WP port "completeStore" [sessionv t;boolv ok] {{ v, ⌜v = sessionv (complete_store t ok)⌝ }}.
Proof. apply executes_wp. eapply port_exec; [reflexivity|apply complete_exec]. Qed.
Theorem prepareAddPair_correct t s e : pending_valid (committed t) ->
 ⊢ WP port "prepareAddPair" [sessionv t;intv s;intv e] {{ v, ⌜v = sessionv (prepare t (add_pair (committed t) s e))⌝ }}.
Proof. intros Hp. apply executes_wp. eapply port_exec; [reflexivity|apply prepareAddPair_exec; exact Hp]. Qed.
Theorem prepareStartShift_correct t s : pending_valid (committed t) ->
 ⊢ WP port "prepareStartShift" [sessionv t;intv s] {{ v, ⌜v = sessionv (prepare t (start_shift (committed t) s))⌝ }}.
Proof. intros Hp. apply executes_wp. eapply port_exec; [reflexivity|apply prepareStartShift_exec; exact Hp]. Qed.
Theorem prepareEndShift_correct t e : pending_valid (committed t) ->
 ⊢ WP port "prepareEndShift" [sessionv t;intv e] {{ v, ⌜v = sessionv (prepare t (end_shift (committed t) e))⌝ }}.
Proof. intros Hp. apply executes_wp. eapply port_exec; [reflexivity|apply prepareEndShift_exec; exact Hp]. Qed.
Theorem prepareDeleteShift_correct t s : pending_valid (committed t) ->
 ⊢ WP port "prepareDeleteShift" [sessionv t;intv s] {{ v, ⌜v = sessionv (prepare t (delete_shift (committed t) s))⌝ }}.
Proof. intros Hp. apply executes_wp. eapply port_exec; [reflexivity|apply prepareDeleteShift_exec; exact Hp]. Qed.
Theorem readContained_correct t s e : ⊢ WP port "readContained" [sessionv t;intv s;intv e] {{ v, ⌜v = answerv (read_store false t s e)⌝ }}.
Proof. apply executes_wp. eapply port_exec; [reflexivity|apply readContained_exec]. Qed.
Theorem readIntersecting_correct t s e : ⊢ WP port "readIntersecting" [sessionv t;intv s;intv e] {{ v, ⌜v = answerv (read_store true t s e)⌝ }}.
Proof. apply executes_wp. eapply port_exec; [reflexivity|apply readIntersecting_exec]. Qed.
End iris_contracts.
