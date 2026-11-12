(** The state-validation port checks the domain invariant before a CLI command. *)
From Coq Require Import String List ZArith Lia.
From Tracker Require Import Tracker Model Pure Runtime Contracts Operations Public.
From iris.prelude Require Import options.
Import ListNotations Model.
Local Open Scope string_scope.
Local Open Scope Z_scope.
Lemma le_expression a b x y : executes a (intv x) -> executes b (intv y) ->
 executes (BinOp LeOp a b) (boolv (x <=? y)).
Proof. intros Ha Hb. eapply ExBin; eauto using bin_le. Qed.
Lemma eq_expression a b x y : executes a (intv x) -> executes b (intv y) ->
 executes (BinOp EqOp a b) (boolv (x =? y)).
Proof. intros Ha Hb. eapply ExBin; eauto using bin_eq. Qed.
Lemma and_expression a b x y : executes a (boolv x) -> executes b (boolv y) ->
 executes (BinOp AndOp a b) (boolv (x && y)).
Proof. intros Ha Hb. eapply ExBin; eauto. Qed.
Lemma lt_expression a b x y : executes a (intv x) -> executes b (intv y) ->
 executes (If (BinOp LeOp b a) (Val (boolv false)) (Val (boolv true))) (boolv (x <? y)).
Proof.
 intros Ha Hb. destruct (Z.ltb_spec x y).
 - eapply ExIfFalse; [|constructor]. eapply ExBin; eauto. calculate.
 - eapply ExIfTrue; [|constructor]. eapply ExBin; eauto. calculate.
Qed.
Lemma ite_expression c yes no b w : executes c (boolv b) ->
 executes (if b then yes else no) w -> executes (If c yes no) w.
Proof. destruct b; intros Hc Hw; [eapply ExIfTrue|eapply ExIfFalse]; eauto. Qed.
Lemma ite_bool_expression c yes no b x y : executes c (boolv b) ->
 executes yes (boolv x) -> executes no (boolv y) ->
 executes (If c yes no) (boolv (if b then x else y)).
Proof. destruct b; intros; [eapply ExIfTrue|eapply ExIfFalse]; eauto. Qed.
Ltac formula := first [apply ExValue |
 (eapply ExField; [formula|reflexivity]) |
 (eapply le_expression; [formula|formula]) |
 (eapply eq_expression; [formula|formula]) |
 (eapply and_expression; [formula|formula]) |
 (eapply lt_expression; [formula|formula]) |
 (eapply call_exec; [run|apply midnight_exec]) |
 (eapply ite_bool_expression; [formula|formula|formula])].
Definition piece_good previous a b :=
 ((0 <=? a) && (previous <=? a)) && ((a <? b) && (b <=? next_midnight a)).
Definition pending_good p b := if p =? -1 then true else b <=? p.
Fixpoint valid_list xs previous p :=
 match xs with
 | [] => true
 | (a,b)::xs => if piece_good previous a b then
                  if pending_good p b then valid_list xs b p else false
                else false
 end.
Definition pending_code st := match pending st with None => -1 | Some p => p end.
Definition valid_state st := (-1 <=? pending_code st) && valid_list (shifts st) 0 (pending_code st).
Lemma valid_list_exec xs previous p :
 executes (invoke validPieces_val [listv xs;intv previous;intv p]) (boolv (valid_list xs previous p)).
Proof.
 revert previous. induction xs as [|[a b] xs IH]; intros previous.
 all: unfold invoke,validPieces_val at 1; eapply ExApp; [constructor|constructor|]; normalize;
 do 3 (eapply ExLet; [run|]; normalize).
 - execute ltac:(fail).
 - eapply ExIfFalse; [run|]. cbn [valid_list].
   eapply ite_expression; [formula|].
   fold (piece_good previous a b).
   destruct (piece_good previous a b) eqn:Hgood.
   + eapply ite_expression; [formula|].
     fold (pending_good p b).
     destruct (pending_good p b) eqn:Hpending; solve [execute ltac:(apply IH)].
   + constructor.
Qed.
Lemma valid_state_exec st :
 executes (invoke validState_val [statev st]) (boolv (valid_state st)).
Proof.
 destruct st as [xs p]. unfold invoke,validState_val at 1. eapply ExApp; [constructor|constructor|]. normalize.
 eapply ExLet; [run|]. normalize. unfold valid_state,pending_code. cbn [shifts pending].
 eapply and_expression.
 - formula.
 - eapply call_exec; [run|apply valid_list_exec].
Qed.
Theorem validState_correct `{!cjrGS Σ} `{!invGS_gen HasLc Σ} st :
 ⊢ WP port "validState" [statev st] {{ v, ⌜v = boolv (valid_state st)⌝ }}.
Proof. apply executes_wp. eapply port_exec; [reflexivity|apply valid_state_exec]. Qed.

Lemma valid_list_sound xs previous p : valid_list xs previous p = true ->
 ordered xs /\ Forall daily_valid xs /\ Forall (fun x => previous <= start x) xs /\
 (p = -1 \/ Forall (fun x => finish x <= p) xs).
Proof.
 revert previous. induction xs as [|[a b] xs IH]; intros previous; cbn [valid_list].
 - intros _. split; [constructor|]. split; [constructor|]. split; [constructor|right; constructor].
 - destruct (piece_good previous a b) eqn:Hgood; [|discriminate].
   destruct (pending_good p b) eqn:Hpending; [|discriminate]. intros Htail.
   specialize (IH b Htail). destruct IH as [Ho [Hd [Hstarts Hp]]].
   unfold piece_good in Hgood. repeat rewrite andb_true_iff in Hgood.
   destruct Hgood as [[Ha Hprevious] [Hab Hday]].
   apply Z.leb_le in Ha. apply Z.leb_le in Hprevious. apply Z.leb_le in Hday. apply Z.ltb_lt in Hab.
   split.
   + constructor; [exact Ho|exact Hstarts].
   + split.
     * constructor; auto. unfold daily_valid,valid_shift,start,finish; simpl. tauto.
     * split.
       -- constructor; [exact Hprevious|]. eapply List.Forall_impl; [|exact Hstarts].
          intros x Hx. cbn in Hx. lia.
       -- destruct (Z.eq_dec p (-1)) as [->|Hne]; [auto|right].
          unfold pending_good in Hpending. assert (p =? -1 = false) as Heq by (apply Z.eqb_neq; auto).
          rewrite Heq in Hpending. apply Z.leb_le in Hpending. destruct Hp as [Hp|Hp]; [contradiction|].
          constructor; auto.
Qed.
Theorem validation_implies_invariant st : pending_valid st -> valid_state st = true -> state_invariant st.
Proof.
 destruct st as [xs p]. destruct p as [p|]; cbn [pending_valid pending]; intros Hp Hvalid;
 unfold valid_state,pending_code in Hvalid; cbn [shifts pending] in Hvalid;
 apply andb_true_iff in Hvalid as [_ Hvalid];
 destruct (valid_list_sound xs 0 _ Hvalid) as [Ho [Hd [Hstarts Hbound]]];
 unfold state_invariant; cbn [shifts pending]; repeat split; auto.
 destruct Hbound as [Hbad|Hbound]; [lia|assumption].
Qed.
