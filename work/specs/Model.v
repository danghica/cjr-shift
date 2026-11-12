(** Mathematical specification. Minutes are unbounded nonnegative integers;
    native representation bounds and adapter conversions are separate. *)
From Coq Require Import ZArith Lia List Bool Sorting.Sorted.
Import ListNotations.
Open Scope Z_scope.
Definition shift := (Z * Z)%type.
Definition start (x : shift) := fst x.
Definition finish (x : shift) := snd x.
Definition valid_shift (x : shift) := 0 <= start x /\ start x < finish x.
Definition inside (s e : Z) (x : shift) := s <= start x /\ finish x <= e.
Definition hit (s e : Z) (x : shift) := (start x <? e) && (s <? finish x).
Definition contained (s e : Z) (x : shift) := (s <=? start x) && (finish x <=? e).
Definition next_midnight s := s - Z.rem s 1440 + 1440.
Definition boundary s e := Z.min (next_midnight s) e.
Lemma next_midnight_bounds s : 0 <= s -> s < next_midnight s <= s + 1440.
Proof. intros H. unfold next_midnight. pose proof (Z.rem_bound_pos s 1440 H ltac:(lia)). lia. Qed.
Lemma boundary_bounds s e : 0 <= s -> s < e -> s < boundary s e <= e.
Proof. intros Hs He. pose proof (next_midnight_bounds s Hs). unfold boundary. lia. Qed.
Fixpoint split_fuel (fuel : nat) (s e : Z) : list shift :=
 match fuel with
 | O => []
 | S fuel => if e <=? s then [] else (s,boundary s e)::split_fuel fuel (boundary s e) e
 end.
Definition split_daily s e := split_fuel (S (Z.to_nat (e-s))) s e.
Lemma split_inside fuel s e : 0 <= s ->
 Forall (fun x => valid_shift x /\ inside s e x /\ finish x <= next_midnight (start x)) (split_fuel fuel s e).
Proof.
 revert s. induction fuel as [|fuel IH]; intros s Hs; simpl; [constructor|].
 destruct (e <=? s) eqn:Hse; [constructor|]. apply Z.leb_gt in Hse.
 pose proof (boundary_bounds s e Hs Hse) as Hb.
 constructor.
 - unfold valid_shift, inside, start, finish; simpl. pose proof (Z.le_min_l (next_midnight s) e). unfold boundary in *. repeat split; lia.
 - specialize (IH (boundary s e) ltac:(lia)). eapply Forall_impl; [|exact IH].
   intros [a b] [[Ha Hab] [[Hba Hbe] Hd]]. unfold valid_shift, inside, start, finish in *; simpl in *.
   repeat split; lia.
Qed.
Lemma split_head s e : 0 <= s -> s < e ->
 exists rest, split_daily s e = (s,boundary s e)::rest.
Proof. intros Hs He. unfold split_daily. simpl. assert (e <=? s = false) as -> by (apply Z.leb_gt; lia). eauto. Qed.
Lemma split_nonempty s e : 0 <= s -> s < e -> split_daily s e <> [].
Proof. intros Hs He. destruct (split_head s e Hs He) as [xs H]. rewrite H. discriminate. Qed.
Lemma split_selected s e : 0 <= s -> s < e ->
 Forall (fun x => contained s e x = true /\ hit s e x = true) (split_daily s e).
Proof.
 intros Hs He. unfold split_daily. pose proof (split_inside (S (Z.to_nat (e-s))) s e Hs) as H.
 eapply Forall_impl; [|exact H]. intros [a b] [[Ha Hab] [[Hsa Hbe] _]].
 unfold contained, hit, valid_shift, inside, start, finish in *; simpl in *.
 split; apply andb_true_iff; split; first [apply Z.leb_le; lia|apply Z.ltb_lt; lia].
Qed.
Fixpoint splice (s : Z) (pieces existing : list shift) :=
 match existing with
 | [] => pieces
 | x::xs => if s <=? start x then pieces ++ existing else x :: splice s pieces xs
 end.
Lemma splice_contains s ps xs x : In x ps -> In x (splice s ps xs).
Proof. induction xs as [|a xs IH]; simpl; auto. destruct (s <=? start a); simpl; auto using in_or_app. Qed.
Lemma filter_none (f : shift -> bool) xs : Forall (fun x => f x = false) xs -> filter f xs = [].
Proof. induction 1 as [|x xs Hx Hxs IH]; simpl; auto. rewrite Hx, IH. reflexivity. Qed.
Lemma filter_splice_empty (f : shift -> bool) s ps xs :
 Forall (fun x => f x = false) xs -> filter f (splice s ps xs) = filter f ps.
Proof.
 induction xs as [|x xs IH]; simpl; [reflexivity|]. intros H. inversion H; subst.
 destruct (s <=? start x); simpl.
 - rewrite filter_app. simpl. rewrite H2. simpl. assert (filter f xs = []) as ->.
   { apply filter_none. assumption. }
   apply app_nil_r.
 - rewrite H2. apply IH. assumption.
Qed.
Lemma filter_all (f : shift -> bool) xs : Forall (fun x => f x = true) xs -> filter f xs = xs.
Proof. induction 1; simpl; auto. rewrite H, IHForall. reflexivity. Qed.
Record tracker := State { shifts : list shift; pending : option Z }.
Record answer := Answer { code : Z; updated : tracker; rows : list shift }.
Definition failure c st := Answer c st [].
Definition overlaps xs s e := existsb (hit s e) xs.
Definition reserved st e := match pending st with None => false | Some p => p <? e end.
Definition add_pair st s e :=
 if s <? 0 then failure 1 st else
 if e <=? s then failure 2 st else
 if reserved st e then failure 4 st else
 if overlaps (shifts st) s e then failure 3 st else
 Answer 0 (State (splice s (split_daily s e) (shifts st)) (pending st)) [].
Definition ends_after xs s := existsb (fun x => s <? finish x) xs.
Definition start_shift st s :=
 if s <? 0 then failure 1 st else
 match pending st with
 | Some _ => failure 4 st
 | None => if ends_after (shifts st) s then failure 4 st
           else Answer 0 (State (shifts st) (Some s)) []
 end.
Definition end_shift st e :=
 match pending st with
 | None => failure 5 st
 | Some s => let a := add_pair (State (shifts st) None) s e in
             if code a =? 0 then a else failure (code a) st
 end.
Definition query (intersect : bool) st s e :=
 if s <? 0 then failure 1 st else
 if e <=? s then failure 2 st else
 Answer 0 st (filter (if intersect then hit s e else contained s e) (shifts st)).
Definition delete_shift st s :=
 if s <? 0 then failure 1 st else
 if existsb (fun x => start x =? s) (shifts st)
 then Answer 0 (State (filter (fun x => negb (start x =? s)) (shifts st)) (pending st)) []
 else failure 6 st.

Lemma add_success st s e : code (add_pair st s e) = 0 ->
 0 <= s /\ s < e /\ reserved st e = false /\ overlaps (shifts st) s e = false /\
 updated (add_pair st s e) = State (splice s (split_daily s e) (shifts st)) (pending st).
Proof.
 unfold add_pair. destruct (s <? 0) eqn:Hs; simpl; [discriminate|].
 destruct (e <=? s) eqn:He; simpl; [discriminate|].
 destruct (reserved st e) eqn:Hr; simpl; [discriminate|].
 destruct (overlaps (shifts st) s e) eqn:Ho; simpl; [discriminate|].
 intros _. apply Z.ltb_ge in Hs. apply Z.leb_gt in He. auto.
Qed.
Lemma no_hit xs s e : overlaps xs s e = false -> Forall (fun x => hit s e x = false) xs.
Proof. unfold overlaps. intros H. apply Forall_forall. intros x Hx.
 destruct (hit s e x) eqn:Hx'; [|reflexivity].
 assert (existsb (hit s e) xs = true) by (apply existsb_exists; eauto). congruence.
Qed.
Lemma valid_contained_hits s e x : valid_shift x -> contained s e x = true -> hit s e x = true.
Proof.
 unfold valid_shift, contained, hit. intros [Hpos Hlen] H.
 apply andb_true_iff in H as [Hs He]. apply Z.leb_le in Hs, He.
 apply andb_true_iff. split; apply Z.ltb_lt; lia.
Qed.
Theorem add_query_round_trip mode st s e :
 Forall valid_shift (shifts st) -> code (add_pair st s e) = 0 ->
 rows (query mode (updated (add_pair st s e)) s e) = split_daily s e.
Proof.
 intros Hvalid Hsuccess. destruct (add_success st s e Hsuccess) as [Hs [He [_ [Ho Hu]]]].
 rewrite Hu. unfold query. assert (s <? 0 = false) as -> by (apply Z.ltb_ge; lia). assert (e <=? s = false) as -> by (apply Z.leb_gt; lia). simpl.
 rewrite filter_splice_empty.
 - apply filter_all. pose proof (split_selected s e Hs He) as H.
   eapply Forall_impl; [|exact H]. intros x [Hc Hi]. destruct mode; assumption.
 - pose proof (no_hit _ _ _ Ho) as Hnone. apply Forall_forall. intros x Hx.
   rewrite Forall_forall in Hnone, Hvalid. specialize (Hnone x Hx). specialize (Hvalid x Hx).
   destruct mode; [exact Hnone|]. destruct (contained s e x) eqn:Hc; [|reflexivity].
   pose proof (valid_contained_hits s e x Hvalid Hc). congruence.
Qed.
Theorem duplicate_rejected st s e : code (add_pair st s e) = 0 ->
 code (add_pair (updated (add_pair st s e)) s e) <> 0.
Proof.
 intros Hsuccess Hduplicate. destruct (add_success st s e Hsuccess) as [Hs [He [_ [_ Hu]]]].
 destruct (add_success _ _ _ Hduplicate) as [_ [_ [_ [Ho _]]]]. rewrite Hu in Ho. simpl in Ho.
 destruct (split_head s e Hs He) as [rest Hsplit].
 assert (Hin : In (s,boundary s e) (splice s (split_daily s e) (shifts st))).
 { apply splice_contains. rewrite Hsplit. left. reflexivity. }
 assert (Hhit : hit s e (s,boundary s e) = true).
 { pose proof (boundary_bounds s e Hs He). unfold hit, start, finish; simpl.
   apply andb_true_iff. split; apply Z.ltb_lt; lia. }
 assert (overlaps (splice s (split_daily s e) (shifts st)) s e = true).
 { unfold overlaps. apply existsb_exists. eauto. } congruence.
Qed.
Theorem rejected_add_preserves st s e : code (add_pair st s e) <> 0 -> updated (add_pair st s e) = st.
Proof. unfold add_pair. repeat (destruct (_ : bool)); simpl; congruence. Qed.
Theorem start_end_equivalent st s e :
 code (start_shift st s) = 0 -> code (add_pair st s e) = 0 ->
 end_shift (updated (start_shift st s)) e = add_pair st s e.
Proof.
 destruct st as [xs p]. unfold start_shift. simpl.
 destruct (s <? 0) eqn:Hs; simpl; [discriminate|].
 destruct p as [p|]; simpl; [discriminate|].
 destruct (ends_after xs s); simpl; [discriminate|].
 intros _ Hsuccess. unfold end_shift. simpl. rewrite Hsuccess. simpl. reflexivity.
Qed.
Theorem later_start_rejected st s x :
 valid_shift x -> In x (shifts st) -> s < start x -> code (start_shift st s) <> 0.
Proof.
 intros [Hpos Hlen] Hin Hlater. unfold start_shift.
 destruct (s <? 0); simpl; [lia|]. destruct (pending st); simpl; [lia|].
 assert (ends_after (shifts st) s = true) as ->.
 { unfold ends_after. apply existsb_exists. exists x. split; auto. apply Z.ltb_lt. lia. }
 simpl. lia.
Qed.
Theorem reservation st s : code (start_shift st s) = 0 ->
 Forall (fun x => finish x <= s) (shifts st).
Proof.
 unfold start_shift. destruct (s <? 0); simpl; [discriminate|].
 destruct (pending st); simpl; [discriminate|]. destruct (ends_after (shifts st) s) eqn:Hends; simpl; [discriminate|].
 intros _. apply Forall_forall. intros x Hx. unfold ends_after in Hends.
 destruct (s <? finish x) eqn:H; [|apply Z.ltb_ge in H; lia].
 assert (existsb (fun x => s <? finish x) (shifts st) = true) by (apply existsb_exists; eauto). congruence.
Qed.
Theorem rejected_end_preserves st e : code (end_shift st e) <> 0 -> updated (end_shift st e) = st.
Proof.
 unfold end_shift. destruct (pending st); simpl; [|reflexivity].
 destruct (code (add_pair (State (shifts st) None) z e) =? 0) eqn:H; simpl; [|reflexivity].
 intros Hneq. apply Z.eqb_eq in H. contradiction.
Qed.

(** A split covers every working minute, including across arbitrarily many days. *)
Lemma split_covers fuel s e t : 0 <= s -> s <= t < e -> e-s < Z.of_nat fuel ->
 exists x, In x (split_fuel fuel s e) /\ start x <= t < finish x.
Proof.
 revert s. induction fuel as [|fuel IH]; intros s Hs Ht Hfuel; [simpl in *; lia|].
 simpl. assert (e <=? s = false) as -> by (apply Z.leb_gt; lia).
 pose proof (boundary_bounds s e Hs ltac:(lia)) as Hb.
 destruct (Z_lt_ge_dec t (boundary s e)) as [Hbefore|Hafter].
 - exists (s,boundary s e). split; [left; reflexivity|]. unfold start,finish; simpl. lia.
 - destruct (IH (boundary s e) ltac:(lia) ltac:(lia) ltac:(rewrite Nat2Z.inj_succ in Hfuel; lia)) as [x [Hin Hrange]].
   exists x. split; [right; exact Hin|assumption].
Qed.
Theorem split_daily_covers s e t : 0 <= s -> s <= t < e ->
 exists x, In x (split_daily s e) /\ start x <= t < finish x.
Proof.
 intros Hs Ht. unfold split_daily. apply split_covers; auto.
 rewrite Nat2Z.inj_succ, Z2Nat.id by lia. lia.
Qed.
Definition ordered := StronglySorted (fun a b : shift => finish a <= start b).
Definition daily_valid x := valid_shift x /\ finish x <= next_midnight (start x).
Definition state_invariant st := ordered (shifts st) /\ Forall daily_valid (shifts st) /\
 match pending st with None => True | Some s => 0 <= s /\ Forall (fun x => finish x <= s) (shifts st) end.
Lemma split_ordered fuel s e : 0 <= s -> ordered (split_fuel fuel s e).
Proof.
 revert s. induction fuel as [|fuel IH]; intros s Hs; simpl; [constructor|].
 destruct (e <=? s) eqn:Hse; [constructor|]. apply Z.leb_gt in Hse.
 pose proof (boundary_bounds s e Hs Hse) as Hb. constructor.
 - apply IH. lia.
 - pose proof (split_inside fuel (boundary s e) e ltac:(lia)) as H.
   eapply Forall_impl; [|exact H]. intros [a b] Hx. unfold start,finish,inside in *; simpl in *. tauto.
Qed.
Lemma splice_forall (P : shift -> Prop) s ps xs : Forall P ps -> Forall P xs -> Forall P (splice s ps xs).
Proof.
 intros Hp. induction xs as [|x xs IH]; simpl; auto. intros Hx. inversion Hx; subst.
 destruct (s <=? start x); [apply Forall_app; auto|constructor; auto].
Qed.
Lemma splice_elements s ps xs x : In x (splice s ps xs) -> In x ps \/ In x xs.
Proof.
 induction xs as [|a xs IH]; simpl; auto. destruct (s <=? start a); simpl.
 - intros H. apply in_app_or in H. tauto.
 - intros [->|H]; [auto|]. specialize (IH H). tauto.
Qed.
Lemma ordered_app xs ys : ordered xs -> ordered ys ->
 (forall x y, In x xs -> In y ys -> finish x <= start y) -> ordered (xs++ys).
Proof.
 intros Hx Hy Hcross. induction Hx as [|a xs Hxs IH Hafter]; simpl; auto.
 constructor.
 - apply IH. intros. apply Hcross; auto. right. assumption.
 - apply Forall_app. split; auto. apply Forall_forall. intros y Hyin. apply Hcross; auto. left. reflexivity.
Qed.
Lemma splice_ordered s e ps xs :
 ordered ps -> Forall (fun x => valid_shift x /\ inside s e x) ps ->
 ordered xs -> Forall valid_shift xs -> overlaps xs s e = false -> ordered (splice s ps xs).
Proof.
 intros Hps Hbounds Hxs. induction Hxs as [|x xs Hxs IH Hafter]; simpl; auto.
 intros Hvalid Hnone. inversion Hvalid as [|? ? Hx Hrest]; subst.
 unfold overlaps in Hnone. simpl in Hnone. apply orb_false_iff in Hnone as [Hhit Hnone].
 destruct (s <=? start x) eqn:Hposition.
 - apply ordered_app; auto. constructor; auto.
   intros a y Ha Hy. apply Forall_forall with (x:=a) in Hbounds; auto.
   assert (He : e <= start x).
   { unfold hit in Hhit. apply Z.leb_le in Hposition. unfold valid_shift in Hx.
     destruct (start x <? e) eqn:Hxe; [|apply Z.ltb_ge in Hxe; lia].
     simpl in Hhit. apply Z.ltb_ge in Hhit. apply Z.ltb_lt in Hxe. lia. }
   destruct Hy as [<-|Hy].
   + unfold inside in Hbounds. lia.
   + apply Forall_forall with (x:=y) in Hafter; auto. unfold valid_shift in Hx. unfold inside in Hbounds. lia.
 - constructor.
   + apply IH; auto.
   + apply Forall_forall. intros y Hy. apply splice_elements in Hy. destruct Hy as [Hy|Hy].
     * apply Forall_forall with (x:=y) in Hbounds; auto.
       assert (Hend : finish x <= s).
       { apply Z.leb_gt in Hposition. unfold hit in Hhit. unfold valid_shift,inside in Hbounds.
         destruct (s <? finish x) eqn:Hsx; [|apply Z.ltb_ge in Hsx; lia].
         rewrite andb_true_r in Hhit. apply Z.ltb_ge in Hhit. apply Z.ltb_lt in Hsx. lia. }
       unfold inside in Hbounds. lia.
     * apply Forall_forall with (x:=y) in Hafter; auto.
Qed.
Theorem successful_add_preserves_invariant st s e : state_invariant st -> code (add_pair st s e) = 0 ->
 state_invariant (updated (add_pair st s e)).
Proof.
 intros [Hord [Hdaily Hpending]] Hsuccess.
 destruct (add_success st s e Hsuccess) as [Hs [He [Hr [Ho Hu]]]]. rewrite Hu.
 unfold state_invariant. simpl. pose proof (split_inside (S (Z.to_nat (e-s))) s e Hs) as Hsplit.
 assert (Hvalid : Forall valid_shift (shifts st)).
 { eapply Forall_impl; [|exact Hdaily]. intros x Hx. unfold daily_valid in Hx. tauto. }
 split.
 - apply splice_ordered with (e:=e); auto.
   + apply split_ordered. assumption.
   + eapply Forall_impl; [|exact Hsplit]. intros x Hx. cbn in Hx. tauto.
 - split.
   + apply splice_forall; auto. eapply Forall_impl; [|exact Hsplit]. intros x Hx. cbn in Hx. unfold daily_valid. tauto.
   + destruct (pending st) as [p|] eqn:Hp; auto. destruct Hpending as [Hpos Hbound]. split; auto.
     unfold reserved in Hr. rewrite Hp in Hr. apply Z.ltb_ge in Hr.
     apply splice_forall; auto. eapply Forall_impl; [|exact Hsplit]. intros x Hx. cbn in Hx. unfold inside in Hx. lia.
Qed.
Lemma ordered_filter f xs : ordered xs -> ordered (filter f xs).
Proof.
 induction 1 as [|x xs Hxs IH Hafter]; simpl; [constructor|].
 destruct (f x); auto. constructor; auto.
 apply Forall_forall. intros y Hy. apply filter_In in Hy as [Hy _]. rewrite Forall_forall in Hafter. auto.
Qed.
Theorem deletion_preserves_invariant st s : state_invariant st -> state_invariant (updated (delete_shift st s)).
Proof.
 intros Hinv. unfold delete_shift. destruct (s <? 0); simpl; auto.
 destruct (existsb (fun x => start x =? s) (shifts st)); simpl; auto.
 destruct Hinv as [Ho [Hd Hp]]. unfold state_invariant. simpl. split; [apply ordered_filter; assumption|].
 split.
 - apply Forall_forall. intros x Hx. apply filter_In in Hx as [Hx _]. rewrite Forall_forall in Hd. auto.
 - destruct (pending st); auto. destruct Hp as [Hpos Hp]. split; auto.
   apply Forall_forall. intros x Hx. apply filter_In in Hx as [Hx _]. rewrite Forall_forall in Hp. auto.
Qed.
Theorem start_preserves_invariant st s : state_invariant st -> state_invariant (updated (start_shift st s)).
Proof.
 intros Hinv. unfold start_shift. destruct (s <? 0) eqn:Hs; simpl; auto.
 destruct (pending st); simpl; auto. destruct (ends_after (shifts st) s) eqn:He; simpl; auto.
 destruct Hinv as [Ho [Hd _]]. unfold state_invariant. simpl. repeat split; auto.
 - apply Z.ltb_ge in Hs. assumption.
 - apply Forall_forall. intros x Hx. unfold ends_after in He.
   destruct (s <? finish x) eqn:Hx'; [|apply Z.ltb_ge in Hx'; lia].
   assert (existsb (fun x => s <? finish x) (shifts st) = true) by (apply existsb_exists; eauto). congruence.
Qed.
Theorem query_preserves_state mode st s e : updated (query mode st s e) = st.
Proof. unfold query. repeat destruct (_ : bool); reflexivity. Qed.
Theorem end_preserves_invariant st e : state_invariant st -> state_invariant (updated (end_shift st e)).
Proof.
 intros Hinv. unfold end_shift. destruct (pending st) as [s|] eqn:Hp; [|exact Hinv].
 destruct (code (add_pair (State (shifts st) None) s e) =? 0) eqn:Hcode.
 - apply successful_add_preserves_invariant.
   + destruct Hinv as [Ho [Hd _]]. unfold state_invariant. simpl. auto.
   + apply Z.eqb_eq in Hcode. exact Hcode.
 - exact Hinv.
Qed.
Theorem empty_invariant : state_invariant (State [] None).
Proof. unfold state_invariant; simpl. repeat split; constructor. Qed.
