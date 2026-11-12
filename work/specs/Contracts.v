(** Refinement contracts for the erased implementation. *)
From Coq Require Import String List ZArith Lia.
From Tracker Require Import Model Pure Runtime.
From iris.prelude Require Import options.
Import ListNotations Model.
Local Open Scope string_scope.
Local Open Scope Z_scope.
Definition intv n := LitV (LitInt n).
Definition boolv b := LitV (LitBool b).
Definition nilv := StructV [boolv true;intv 0;intv 0;
 RecV None (Some "unused") (App (Val emptyPieces_val) (Struct [] []))].
Definition nodev s e rest := StructV [boolv false;intv s;intv e;RecV None (Some "unused") (Val rest)].
Fixpoint listv (xs : list shift) : val :=
 match xs with [] => nilv | (s,e)::xs => nodev s e (listv xs) end.
Definition statev st := StructV [listv (shifts st);intv (match pending st with None => -1 | Some p => p end)].
Definition answerv a := StructV [intv (code a);statev (updated a);listv (rows a)].
Definition invoke f args := App (Val f) (Val (StructV args)).
Lemma listv_closed xs : closed_val (listv xs).
Proof.
 induction xs as [|[s e] xs IH]; intros x w; simpl.
 - unfold nilv, intv, boolv. cbn -[emptyPieces_val]. repeat case_bool_decide; simpl; rewrite ?emptyPieces_closed; done.
 - unfold nodev, intv, boolv. cbn -[listv]. repeat case_bool_decide; simpl; rewrite ?IH; done.
Qed.
Lemma statev_closed st : closed_val (statev st).
Proof. intros x w. unfold statev. simpl. rewrite listv_closed. reflexivity. Qed.
Lemma nilv_closed : closed_val nilv.
Proof. exact (listv_closed []). Qed.
Lemma nodev_closed s e rest : closed_val rest -> closed_val (nodev s e rest).
Proof. intros H x w. unfold nodev,intv,boolv. simpl. repeat case_bool_decide; simpl; rewrite ?H; reflexivity. Qed.

Lemma structv_closed vs : Forall closed_val vs -> closed_val (StructV vs).
Proof. induction 1 as [|a vs Ha Hvs IH]; intros x w; simpl; [reflexivity|]. rewrite Ha. pose proof (IH x w) as Htail. simpl in Htail. injection Htail as Htail. rewrite Htail. reflexivity. Qed.
Ltac closed_value := first [assumption | apply closed_lit | apply listv_closed | apply statev_closed | apply nilv_closed |
 (apply nodev_closed; closed_value) |
 (apply structv_closed; repeat constructor; closed_value) |
 apply emptyPieces_closed | apply consPiece_closed | apply nextMidnight_closed | apply minMinute_closed | apply overlaps_closed | apply endsAfter_closed | apply splitOnto_closed | apply insertDaily_closed | apply selectPieces_closed | apply hasStart_closed | apply removeStart_closed | apply validPieces_closed | apply emptyState_closed | apply validState_closed | apply addPair_closed | apply startShift_closed | apply endShift_closed | apply queryContained_closed | apply queryIntersecting_closed | apply deleteShift_closed].
Ltac close_values := repeat match goal with
 | |- context[subst_val ?x ?w ?value] =>
   let Hc := fresh "Hclosed" in assert (closed_val value) as Hc by closed_value; rewrite (Hc x w); clear Hc
 end.
Ltac reduce_runtime := cbn -[subst_val listv statev answerv nilv nodev split_fuel split_daily splice add_pair start_shift end_shift query delete_shift next_midnight boundary overlaps ends_after emptyPieces_val consPiece_val nextMidnight_val minMinute_val overlaps_val endsAfter_val splitOnto_val insertDaily_val selectPieces_val hasStart_val removeStart_val validPieces_val emptyState_val validState_val addPair_val startShift_val endShift_val queryContained_val queryIntersecting_val deleteShift_val initializeStore_val stageChange_val prepareAddPair_val prepareStartShift_val prepareEndShift_val prepareDeleteShift_val completeStore_val readContained_val readIntersecting_val]; close_globals.
Ltac normalize := repeat (progress (reduce_runtime; repeat case_bool_decide; simplify_eq; close_values)).
Ltac run := first [apply ExValue | apply ExRec | apply ExStructDone |
 (eapply ExBin; [run|run|reflexivity]) |
 (eapply ExField; [run|reflexivity]) |
 (eapply ExStructNext; [run|simpl;run]) |
 (eapply ExLet; [run|normalize;run]) |
 (eapply ExApp; [run|run|normalize;run])].
Lemma empty_exec : executes (invoke emptyPieces_val []) nilv.
Proof. unfold invoke,emptyPieces_val. eapply ExApp; [constructor|constructor|]. normalize. run. Qed.
Lemma cons_exec s e rest : closed_val rest ->
 executes (invoke consPiece_val [intv s;intv e;rest]) (nodev s e rest).
Proof.
 intros H. unfold invoke,consPiece_val. eapply ExApp; [constructor|constructor|].
 normalize. rewrite ?H. eapply ExLet; [run|]. normalize. rewrite ?H.
 eapply ExLet; [run|]. normalize. rewrite ?H.
 eapply ExLet; [run|]. normalize. rewrite ?H. run.
Qed.
Lemma pack_exec acc vs : executes (Struct acc (map Val vs)) (StructV (acc++vs)).
Proof.
 revert acc. induction vs as [|v vs IH]; intros acc; simpl.
 - rewrite app_nil_r. constructor.
 - eapply ExStructNext; [constructor|]. replace (acc ++ v::vs)%list with ((acc++[v])++vs)%list by (rewrite <- app_assoc; reflexivity). apply IH.
Qed.
Lemma call_exec f a args w : executes a (StructV args) -> executes (invoke f args) w -> executes (App (Val f) a) w.
Proof.
 intros Hargs Hcall. inversion Hcall; subst. inversion H2; subst. eapply ExApp; eauto.
Qed.
Lemma bin_le a b : bin_op_eval LeOp (intv a) (intv b) = Some (boolv (a <=? b)).
Proof. unfold bin_op_eval,intv,boolv. destruct (Z.leb_spec a b); repeat case_bool_decide; f_equal; lia. Qed.
Lemma bin_eq a b : bin_op_eval EqOp (intv a) (intv b) = Some (boolv (a =? b)).
Proof. unfold bin_op_eval,intv,boolv. destruct (Z.eqb_spec a b); repeat case_bool_decide; simplify_eq; try reflexivity; congruence. Qed.
Lemma midnight_exec s : executes (invoke nextMidnight_val [intv s]) (intv (next_midnight s)).
Proof.
 unfold invoke,nextMidnight_val. eapply ExApp; [constructor|constructor|]. normalize.
 eapply ExLet; [run|]. normalize. unfold next_midnight. run.
Qed.
Lemma min_exec a b : executes (invoke minMinute_val [intv a;intv b]) (intv (Z.min a b)).
Proof.
 unfold invoke,minMinute_val. eapply ExApp; [constructor|constructor|]. normalize.
 eapply ExLet; [run|]. normalize. eapply ExLet; [run|]. normalize.
 destruct (Z.leb_spec a b) as [Hle|Hgt].
 - rewrite (Z.min_l a b Hle). eapply ExIfTrue; [|run]. eapply ExBin; [run|run|]. rewrite bin_le. assert (a <=? b = true) as Hbool by (apply Z.leb_le; assumption). rewrite Hbool. reflexivity.
 - rewrite (Z.min_r a b ltac:(lia)). eapply ExIfFalse; [|run]. eapply ExBin; [run|run|]. rewrite bin_le. assert (a <=? b = false) as Hbool by (apply Z.leb_gt; assumption). rewrite Hbool. reflexivity.
Qed.
Ltac calculate := solve [unfold bin_op_eval, intv, boolv; cbn;
 repeat case_bool_decide; simplify_eq; try solve [exfalso; lia]; try reflexivity; try (f_equal; lia); try congruence].
Ltac execute known := first [apply ExValue | apply ExRec | apply ExStructDone |
 (eapply ExField; [execute known|reflexivity]) |
 (eapply ExStructNext; [execute known|simpl;execute known]) |
 (eapply ExLet; [execute known|normalize;execute known]) |
 (eapply ExBin; [execute known|execute known|calculate]) |
 (eapply ExIfTrue; [execute known|execute known]) |
 (eapply ExIfFalse; [execute known|execute known]) |
 (eapply call_exec; [execute known|first [known | apply empty_exec | apply cons_exec; apply listv_closed | apply midnight_exec | apply min_exec]]) |
 (eapply ExApp; [execute known|execute known|normalize;execute known])].

Lemma overlaps_exec xs s e :
 executes (invoke overlaps_val [listv xs;intv s;intv e]) (boolv (overlaps xs s e)).
Proof.
 induction xs as [|[a b] xs IH].
 - unfold invoke,overlaps_val. eapply ExApp; [constructor|constructor|]. normalize.
   eapply ExLet; [run|]. normalize. eapply ExLet; [run|]. normalize.
   eapply ExLet; [run|]. normalize. execute ltac:(fail).
 - unfold invoke,overlaps_val at 1. eapply ExApp; [constructor|constructor|]. normalize.
   eapply ExLet; [run|]. normalize. eapply ExLet; [run|]. normalize.
   eapply ExLet; [run|]. normalize.
   unfold overlaps, hit, start, finish in *. cbn [existsb fst snd].
   destruct (Z.ltb_spec a e); destruct (Z.ltb_spec s b); cbn [orb andb].
   all: timeout 10 solve [execute ltac:(exact IH)].
Qed.
Lemma ends_exec xs s : executes (invoke endsAfter_val [listv xs;intv s]) (boolv (ends_after xs s)).
Proof.
 induction xs as [|[a b] xs IH].
 all: unfold invoke,endsAfter_val at 1;
 eapply ExApp; [constructor|constructor|]; normalize;
 do 2 (eapply ExLet; [run|]; normalize).
 - execute ltac:(fail).
 - unfold ends_after,finish in *. cbn [existsb snd].
   destruct (Z.ltb_spec s b); cbn [orb]; solve [execute ltac:(exact IH)].
Qed.
Lemma has_exec xs s : executes (invoke hasStart_val [listv xs;intv s])
 (boolv (existsb (fun x => start x =? s) xs)).
Proof.
 induction xs as [|[a b] xs IH].
 all: unfold invoke,hasStart_val at 1;
 eapply ExApp; [constructor|constructor|]; normalize;
 do 2 (eapply ExLet; [run|]; normalize).
 - execute ltac:(fail).
 - unfold start in *. cbn [existsb fst].
   destruct (Z.eqb_spec a s); cbn [orb]; solve [execute ltac:(exact IH)].
Qed.
Lemma remove_exec xs s : executes (invoke removeStart_val [listv xs;intv s])
 (listv (List.filter (fun x => negb (start x =? s)) xs)).
Proof.
 induction xs as [|[a b] xs IH].
 all: unfold invoke,removeStart_val at 1;
 eapply ExApp; [constructor|constructor|]; normalize;
 do 2 (eapply ExLet; [run|]; normalize).
 - execute ltac:(fail).
 - unfold start in *. cbn [List.filter fst]. destruct (Z.eqb_spec a s); cbn [negb];
   solve [execute ltac:(exact IH)].
Qed.
Lemma select_exec mode xs s e : executes (invoke selectPieces_val [listv xs;intv s;intv e;boolv mode])
 (listv (List.filter (if mode then hit s e else contained s e) xs)).
Proof.
 induction xs as [|[a b] xs IH].
 all: unfold invoke,selectPieces_val at 1;
 eapply ExApp; [constructor|constructor|]; normalize;
 do 4 (eapply ExLet; [run|]; normalize).
 - execute ltac:(fail).
 - eapply ExIfFalse; [run|].
   eapply ExLet.
   { eapply call_exec; [run|exact IH]. }
   normalize.
   destruct mode.
   + cbn [List.filter]. unfold hit,start,finish. cbn [fst snd].
     destruct (Z.ltb_spec a e); destruct (Z.ltb_spec s b); cbn [andb];
     solve [execute ltac:(fail)].
   + cbn [List.filter]. unfold contained,start,finish. cbn [fst snd].
     destruct (Z.leb_spec s a); destruct (Z.leb_spec b e); cbn [andb];
     solve [execute ltac:(fail)].
Qed.
