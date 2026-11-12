(** Working-time assessment of explicitly identified statutory periods.
    Legal applicability and complete period identification are input facts.
    Breaks are neither recorded, inferred nor assessed. *)
From Coq Require Import ZArith List Bool Lia.
From Tracker Require Import Model.
Import ListNotations Model.
Open Scope Z_scope.

Definition clip_minutes (s e : Z) (x : shift) : Z :=
 Z.max 0 (Z.min e (finish x) - Z.max s (start x)).
Fixpoint minutes_in (xs : list shift) s e :=
 match xs with [] => 0 | x::xs => clip_minutes s e x + minutes_in xs s e end.
Fixpoint ordered_intervals xs previous :=
 match xs with [] => true | (s,e)::xs =>
 (previous <=? s) && (s <? e) && ordered_intervals xs e end.
Fixpoint merge_work xs ys :=
 match xs with [] => ys | x::xs =>
   (fix insert_into ys := match ys with [] => x::xs
     | y::ys => if start x <=? start y then x::merge_work xs (y::ys)
               else y::insert_into ys end) ys end.
Fixpoint longest_rest xs cursor e :=
 match xs with [] => Z.max 0 (e-cursor)
 | (a,b)::xs => if e <=? a then Z.max 0 (e-cursor)
   else Z.max (Z.max 0 (a-cursor)) (longest_rest xs (Z.max cursor b) e)
 end.
Fixpoint rest_count xs cursor e required :=
 match xs with [] => if required <=? e-cursor then 1 else 0
 | (a,b)::xs => if e <=? a then (if required <=? e-cursor then 1 else 0)
   else (if required <=? a-cursor then 1 else 0) + rest_count xs (Z.max cursor b) e required
 end.
Definition all_inside small large := forallb (fun '(s,e) => minutes_in large s e =? e-s) small.
Definition all_rest rest work := forallb (fun '(s,e) => minutes_in work s e =? 0) rest.

(** Evidence status: 0 unknown, 1 known, 2 rule not applicable, 3 unsupported.
    This is applicability/evidence, never a supplied compliance verdict. *)
Record period := Period {
 rule : Z; from_minute : Z; to_minute : Z;
 calendar_minutes : Z; extra_from : Z; extra_to : Z;
 evidence : Z; rest_scheme : Z; daily_rest_overlap : bool
}.
Record metadata := Metadata {
 jurisdiction : Z; adult : bool; ordinary_regime : bool;
 coverage_from : Z; coverage_to : Z;
 period_coverage_complete : bool; elapsed_work_known : bool;
 other_work : list shift; normal_work : list shift;
 weekly_rest : list shift; night_work : list shift;
 periods : list period
}.
Record finding := Finding {
 finding_code : Z; finding_rule : Z;
 finding_from : Z; finding_to : Z;
 measured : Z; limit : Z
}.
Definition finding_for p c value bound :=
 Finding c (rule p) (from_minute p) (to_minute p) value bound.
Definition period_last p := if rule p =? 101 then Z.max (to_minute p) (extra_to p) else to_minute p.
Definition period_known st m p :=
 elapsed_work_known m &&
 (coverage_from m <=? from_minute p) && ((period_last p) <=? coverage_to m) &&
 (match pending st with None => true | Some t => (period_last p) <=? t end).
Definition good_period p :=
 ((rule p =? 101) || (rule p =? 102) || (rule p =? 103) || (rule p =? 105) || (rule p =? 106)) &&
 (0 <=? from_minute p) && (from_minute p <? to_minute p) &&
 (0 <=? calendar_minutes p) && (0 <=? extra_from p) && (extra_from p <=? extra_to p) &&
 (0 <=? evidence p) && (evidence p <=? 3) &&
 (if rule p =? 102 then to_minute p-from_minute p =? 1440 else true) &&
 (if rule p =? 106 then to_minute p-from_minute p =? 1440 else true) &&
 (if rule p =? 103 then (1 <=? rest_scheme p) && (rest_scheme p <=? 3) &&
   (if rest_scheme p =? 1 then calendar_minutes p =? 10080 else calendar_minutes p =? 20160) else true) &&
 (if rule p =? 101 then (extra_from p =? extra_to p) || (to_minute p <=? extra_from p) else true).
Definition assess_weekly m work p :=
 let s := from_minute p in let e := to_minute p in
 if negb ((0 <? calendar_minutes p) && ((extra_from p =? extra_to p) ||
      ((coverage_from m <=? extra_from p) && (extra_to p <=? coverage_to m))))
 then finding_for p 21 0 0 else
 let a := minutes_in work s e + minutes_in work (extra_from p) (extra_to p) in
 finding_for p (if a*10080 <=? 2880*calendar_minutes p then 0 else 101) (a*10080) (2880*calendar_minutes p).
Definition assess_daily work p :=
 let a := longest_rest work (from_minute p) (to_minute p) in
 finding_for p (if 660 <=? a then 0 else 102) a 660.
Definition assess_weekly_rest work p :=
 let s := from_minute p in let e := to_minute p in
 let extra := if daily_rest_overlap p then 0 else 660 in
 let required := (if rest_scheme p =? 3 then 2880 else 1440)+extra in
 let count := rest_count work s e required in
 let a := if (rest_scheme p =? 2) && (2880+extra <=? longest_rest work s e) then Z.max 2 count else count in
 let needed := if rest_scheme p =? 2 then 2 else 1 in
 finding_for p (if needed <=? a then 0 else 103) a needed.
Definition assess_average_night m p :=
 let s := from_minute p in let e := to_minute p in
 let denominator := calendar_minutes p-minutes_in (weekly_rest m) s e in
 if denominator <=? 0 then finding_for p 20 denominator 0 else
 let a := minutes_in (normal_work m) s e in
 finding_for p (if a*1440 <=? 480*denominator then 0 else 105) (a*1440) (480*denominator).
Definition assess_hazard_night m work p :=
 let s := from_minute p in let e := to_minute p in
 if minutes_in (night_work m) s e =? 0 then finding_for p 0 0 480 else
 let a := minutes_in work s e in finding_for p (if a <=? 480 then 0 else 106) a 480.
Definition assess_period st m work p :=
 if evidence p =? 2 then finding_for p 0 0 0 else
 if evidence p =? 3 then finding_for p 22 0 0 else
 if negb ((evidence p =? 1) && period_known st m p) then finding_for p 21 0 0 else
 if rule p =? 101 then assess_weekly m work p else
 if rule p =? 102 then assess_daily work p else
 if rule p =? 103 then assess_weekly_rest work p else
 if rule p =? 105 then assess_average_night m p else assess_hazard_night m work p.

Definition valid_metadata st m lower upper :=
 (0 <=? lower) && (lower <? upper) &&
 (0 <=? coverage_from m) && (coverage_from m <=? coverage_to m) &&
 ordered_intervals (shifts st) 0 && ordered_intervals (other_work m) 0 &&
 ordered_intervals (merge_work (shifts st) (other_work m)) 0 &&
 ordered_intervals (normal_work m) 0 && ordered_intervals (weekly_rest m) 0 && ordered_intervals (night_work m) 0 &&
 all_inside (normal_work m) (merge_work (shifts st) (other_work m)) &&
 all_inside (night_work m) (merge_work (shifts st) (other_work m)) &&
 all_rest (weekly_rest m) (merge_work (shifts st) (other_work m)) &&
 forallb (fun p => good_period p && (from_minute p <? upper) && (lower <? to_minute p)) (periods m).
Definition supported_metadata m := ((jurisdiction m =? 1) || (jurisdiction m =? 2)) && adult m && ordinary_regime m.
Fixpoint first_violation fs := match fs with [] => 0 | f::fs =>
 let rest := first_violation fs in
 if 100 <=? finding_code f then if rest =? 0 then finding_code f else Z.min (finding_code f) rest else rest end.
Definition summary fs complete :=
 let violation := first_violation fs in
 if negb (violation =? 0) then violation else
 if existsb (fun f => finding_code f =? 20) fs then 20 else
 if existsb (fun f => finding_code f =? 22) fs then 22 else
 if negb complete || existsb (fun f => finding_code f =? 21) fs then 21 else 0.
Definition complete_periods ps := forallb (fun r => existsb (fun p => rule p =? r) ps) [101;102;103;105;106].
Record validation_report := Report { report_code : Z; findings : list finding; breaks_assessed : bool }.
Definition validate_working_time st lower upper m :=
 if negb (valid_metadata st m lower upper) then Report 20 [] false else
 if negb (supported_metadata m) then Report 22 [] false else
 let fs := map (assess_period st m (merge_work (shifts st) (other_work m))) (periods m) in
 Report (summary fs (period_coverage_complete m && complete_periods (periods m))) fs false.

(** Read-only result; break compliance cannot accidentally become a pass/fail check. *)
Theorem breaks_always_not_assessed st lower upper m :
 breaks_assessed (validate_working_time st lower upper m) = false.
Proof. unfold validate_working_time. destruct (negb (valid_metadata st m lower upper)); [reflexivity|]. destruct (negb (supported_metadata m)); reflexivity. Qed.
