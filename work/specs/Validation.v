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

(** Specification-only validation of the daily-rest rule. A short gap alone is
    insufficient: the supplied daily period must have no continuous rest of
    eleven hours, and its applicability and coverage must be known. No CJR
    execution lemma or implementation correctness theorem is used below. *)
From Tracker Require Import WorkingTimeModel.

Lemma first_violation_zero_or_error fs :
 WorkingTimeModel.first_violation fs = 0 \/
 100 <= WorkingTimeModel.first_violation fs.
Proof.
 induction fs as [|f fs IH]; [left; reflexivity|].
 cbn [WorkingTimeModel.first_violation].
 destruct (100 <=? WorkingTimeModel.finding_code f) eqn:Hhead; [|exact IH].
 apply Z.leb_le in Hhead.
 destruct IH as [Hzero|Herror].
 - rewrite Hzero. cbn. right. exact Hhead.
 - assert (Hnonzero : WorkingTimeModel.first_violation fs =? 0 = false)
     by (apply Z.eqb_neq; lia).
   rewrite Hnonzero. right. apply Z.min_glb; assumption.
Qed.

Lemma first_violation_detects_error fs f :
 In f fs -> 100 <= WorkingTimeModel.finding_code f ->
 100 <= WorkingTimeModel.first_violation fs.
Proof.
 induction fs as [|head fs IH]; [contradiction|].
 intros Hin Hcode. cbn [WorkingTimeModel.first_violation].
 destruct Hin as [Heq|Hin].
 - subst head.
   assert (Hhead : 100 <=? WorkingTimeModel.finding_code f = true)
     by (apply Z.leb_le; exact Hcode).
   rewrite Hhead.
   destruct (first_violation_zero_or_error fs) as [Hzero|Herror].
   + rewrite Hzero. cbn. exact Hcode.
   + assert (Hnonzero : WorkingTimeModel.first_violation fs =? 0 = false)
       by (apply Z.eqb_neq; lia).
     rewrite Hnonzero. apply Z.min_glb; assumption.
 - specialize (IH Hin Hcode).
   destruct (100 <=? WorkingTimeModel.finding_code head) eqn:Hhead; [|exact IH].
   apply Z.leb_le in Hhead.
   assert (Hnonzero : WorkingTimeModel.first_violation fs =? 0 = false)
     by (apply Z.eqb_neq; lia).
   rewrite Hnonzero. apply Z.min_glb; assumption.
Qed.

Lemma summary_preserves_error fs complete f :
 In f fs -> 100 <= WorkingTimeModel.finding_code f ->
 100 <= WorkingTimeModel.summary fs complete.
Proof.
 intros Hin Hcode.
 pose proof (first_violation_detects_error fs f Hin Hcode) as Herror.
 unfold WorkingTimeModel.summary.
 assert (Hnonzero : WorkingTimeModel.first_violation fs =? 0 = false)
   by (apply Z.eqb_neq; lia).
 rewrite Hnonzero. exact Herror.
Qed.

Lemma daily_rest_under_eleven_hours_finding st m p :
 WorkingTimeModel.rule p = 102 ->
 WorkingTimeModel.evidence p = 1 ->
 WorkingTimeModel.period_known st m p = true ->
 WorkingTimeModel.longest_rest
   (WorkingTimeModel.merge_work (shifts st) (WorkingTimeModel.other_work m))
   (WorkingTimeModel.from_minute p) (WorkingTimeModel.to_minute p) < 11 * 60 ->
 WorkingTimeModel.assess_period st m
   (WorkingTimeModel.merge_work (shifts st) (WorkingTimeModel.other_work m)) p =
 WorkingTimeModel.finding_for p 102
   (WorkingTimeModel.longest_rest
     (WorkingTimeModel.merge_work (shifts st) (WorkingTimeModel.other_work m))
     (WorkingTimeModel.from_minute p) (WorkingTimeModel.to_minute p)) (11 * 60).
Proof.
 intros Hrule Hevidence Hknown Hrest.
 unfold WorkingTimeModel.assess_period. rewrite Hevidence Hknown Hrule.
 cbn. unfold WorkingTimeModel.assess_daily.
 assert (Hshort : 660 <=? WorkingTimeModel.longest_rest
   (WorkingTimeModel.merge_work (shifts st) (WorkingTimeModel.other_work m))
   (WorkingTimeModel.from_minute p) (WorkingTimeModel.to_minute p) = false)
   by (apply Z.leb_gt; lia).
 rewrite Hshort. reflexivity.
Qed.

(** The report contains daily-rest finding 102 and has a violation code.
    The overall code need not be 102: another rule, such as 101, may take
    precedence. Valid metadata ensures p is a genuine 24-hour daily period. *)
Lemma insufficient_daily_rest_returns_error st lower upper m p :
 WorkingTimeModel.valid_metadata st m lower upper = true ->
 WorkingTimeModel.supported_metadata m = true ->
 In p (WorkingTimeModel.periods m) ->
 WorkingTimeModel.rule p = 102 ->
 WorkingTimeModel.evidence p = 1 ->
 WorkingTimeModel.period_known st m p = true ->
 WorkingTimeModel.longest_rest
   (WorkingTimeModel.merge_work (shifts st) (WorkingTimeModel.other_work m))
   (WorkingTimeModel.from_minute p) (WorkingTimeModel.to_minute p) < 11 * 60 ->
 (exists f, In f (WorkingTimeModel.findings
     (WorkingTimeModel.validate_working_time st lower upper m)) /\
     WorkingTimeModel.finding_code f = 102) /\
 100 <= WorkingTimeModel.report_code
   (WorkingTimeModel.validate_working_time st lower upper m).
Proof.
 intros Hvalid Hsupported Hin Hrule Hevidence Hknown Hrest.
 pose proof (daily_rest_under_eleven_hours_finding st m p
   Hrule Hevidence Hknown Hrest) as Hfinding.
 unfold WorkingTimeModel.validate_working_time.
 rewrite Hvalid Hsupported. cbn [negb].
 set (f := WorkingTimeModel.assess_period st m
   (WorkingTimeModel.merge_work (shifts st) (WorkingTimeModel.other_work m)) p).
 assert (Hin_result : In f (map
   (WorkingTimeModel.assess_period st m
     (WorkingTimeModel.merge_work (shifts st) (WorkingTimeModel.other_work m)))
   (WorkingTimeModel.periods m))).
 { apply in_map. exact Hin. }
 assert (Hcode : WorkingTimeModel.finding_code f = 102).
 { unfold f. rewrite Hfinding. reflexivity. }
 split.
 - exists f. split; assumption.
 - eapply summary_preserves_error; [exact Hin_result|]. rewrite Hcode. lia.
Qed.

(** Two shifts cover the beginning and end of the assessed day; therefore
    their intervening gap is its only possible continuous rest. *)
Lemma longest_rest_between_covering_shifts a b c d s e :
 a <= s -> s <= b -> b <= c -> c < e -> e <= d ->
 WorkingTimeModel.longest_rest [(a,b);(c,d)] s e = c-b.
Proof.
 intros Has Hsb Hbc Hce Hed.
 assert (Hea : e <=? a = false) by (apply Z.leb_gt; lia).
 assert (Hec : e <=? c = false) by (apply Z.leb_gt; lia).
 assert (Hbd : b <= d) by lia.
 assert (Has' : a-s <= 0) by lia.
 assert (Hed' : e-d <= 0) by lia.
 assert (Hgap : 0 <= c-b) by lia.
 cbn [WorkingTimeModel.longest_rest].
 rewrite Hea (Z.max_r s b Hsb) Hec (Z.max_r b d Hbd).
 rewrite (Z.max_l 0 (a-s) Has') (Z.max_l 0 (e-d) Hed').
 rewrite (Z.max_r 0 (c-b) Hgap) (Z.max_l (c-b) 0 Hgap).
 exact (Z.max_r 0 (c-b) Hgap).
Qed.

Lemma short_inter_shift_gap_returns_error st lower upper m p a b c d :
 WorkingTimeModel.valid_metadata st m lower upper = true ->
 WorkingTimeModel.supported_metadata m = true ->
 In p (WorkingTimeModel.periods m) ->
 WorkingTimeModel.rule p = 102 ->
 WorkingTimeModel.evidence p = 1 ->
 WorkingTimeModel.period_known st m p = true ->
 WorkingTimeModel.merge_work (shifts st) (WorkingTimeModel.other_work m) = [(a,b);(c,d)] ->
 a <= WorkingTimeModel.from_minute p ->
 WorkingTimeModel.from_minute p <= b -> b <= c ->
 c < WorkingTimeModel.to_minute p -> WorkingTimeModel.to_minute p <= d ->
 c-b < 11*60 ->
 100 <= WorkingTimeModel.report_code
   (WorkingTimeModel.validate_working_time st lower upper m).
Proof.
 intros Hvalid Hsupported Hin Hrule Hevidence Hknown Hwork Has Hsb Hbc Hce Hed Hgap.
 assert (Hrest : WorkingTimeModel.longest_rest
   (WorkingTimeModel.merge_work (shifts st) (WorkingTimeModel.other_work m))
   (WorkingTimeModel.from_minute p) (WorkingTimeModel.to_minute p) < 11*60).
 { rewrite Hwork.
   rewrite (longest_rest_between_covering_shifts a b c d _ _ Has Hsb Hbc Hce Hed).
   exact Hgap. }
 exact (proj2 (insufficient_daily_rest_returns_error st lower upper m p
   Hvalid Hsupported Hin Hrule Hevidence Hknown Hrest)).
Qed.

(** A one-hour gap between two short shifts is not, by itself, a daily-rest
    violation: this day still has twenty-one continuous hours of rest. The
    other applicable ordinary-adult checks pass; night rules are not applicable. *)
Lemma short_gap_alone_can_pass :
 let st := State [(0,60);(120,180)] None in
 let daily := WorkingTimeModel.Period 102 0 1440 1440 0 0 1 0 false in
 let weekly := WorkingTimeModel.Period 101 0 171360 171360 0 0 1 0 false in
 let rest := WorkingTimeModel.Period 103 0 10080 10080 0 0 1 1 false in
 let night := WorkingTimeModel.Period 105 0 171360 171360 0 0 2 0 false in
 let hazard := WorkingTimeModel.Period 106 0 1440 1440 0 0 2 0 false in
 let m := WorkingTimeModel.Metadata 1 true true 0 171360 true true
   [] [] [] [] [daily;weekly;rest;night;hazard] in
 120-60 < 11*60 /\
 WorkingTimeModel.longest_rest (shifts st) 0 1440 = 21*60 /\
 WorkingTimeModel.report_code
   (WorkingTimeModel.validate_working_time st 0 1440 m) = 0.
Proof. vm_compute. repeat split; reflexivity. Qed.
