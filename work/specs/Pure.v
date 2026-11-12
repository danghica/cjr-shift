(** A heap-independent big-step semantics for the pure CJR fragment, with
    a reusable Iris soundness theorem. This is a proof tool, not native code. *)
From iris.proofmode Require Import proofmode.
From cjr Require Export generic_laws.
From iris.prelude Require Import options.
Import ListNotations.
Inductive executes : expr -> val -> Prop :=
| ExValue v : executes (Val v) v
| ExRec f x e : executes (Rec f x e) (RecV f x e)
| ExApp f a name arg body av w :
 executes f (RecV name arg body) -> executes a av ->
 executes (subst_binder arg av (subst_binder name (RecV name arg body) body)) w ->
 executes (App f a) w
| ExLet x a e av w : executes a av -> executes (subst_binder x av e) w -> executes (Let x a e) w
| ExIfTrue c a b w : executes c (LitV (LitBool true)) -> executes a w -> executes (If c a b) w
| ExIfFalse c a b w : executes c (LitV (LitBool false)) -> executes b w -> executes (If c a b) w
| ExBin op a b av bv w : executes a av -> executes b bv -> bin_op_eval op av bv = Some w -> executes (BinOp op a b) w
| ExStructDone vs : executes (Struct vs []) (StructV vs)
| ExStructNext vs a es av w : executes a av -> executes (Struct (vs ++ [av]) es) w -> executes (Struct vs (a::es)) w
| ExField a avs i w : executes a (StructV avs) -> avs !! i = Some w -> executes (StructLoad a i) w.

Theorem executes_wp `{!cjrGS Σ} `{!invGS_gen HasLc Σ} e w : executes e w ->
 ⊢ WP e {{ v, ⌜v = w⌝ }}.
Proof.
 intros H. induction H.
 - iApply wp_value'. done.
 - iApply wp_rec. iIntros "!> _". done.
 - iApply (wp_bind [AppLCtx a]). iApply (wp_wand with "[]"); [iApply IHexecutes1|].
   iIntros (v) "->". iApply (wp_bind [AppRCtx _]).
   iApply (wp_wand with "[]"); [iApply IHexecutes2|]. iIntros (v) "->".
   iApply wp_app. iApply IHexecutes3.
 - iApply (wp_bind [LetCtx x e]). iApply (wp_wand with "[]"); [iApply IHexecutes1|].
   iIntros (v) "->". iApply wp_let. iApply IHexecutes2.
 - iApply (wp_bind [IfCtx a b]). iApply (wp_wand with "[]"); [iApply IHexecutes1|].
   iIntros (v) "->". iApply wp_if_true. iApply IHexecutes2.
 - iApply (wp_bind [IfCtx a b]). iApply (wp_wand with "[]"); [iApply IHexecutes1|].
   iIntros (v) "->". iApply wp_if_false. iApply IHexecutes2.
 - iApply (wp_bind [BinOpLCtx op b]). iApply (wp_wand with "[]"); [iApply IHexecutes1|].
   iIntros (v) "->". iApply (wp_bind [BinOpRCtx op av]).
   iApply (wp_wand with "[]"); [iApply IHexecutes2|]. iIntros (v) "->".
   iApply wp_binop; [exact H1|]. iIntros "!> _". done.
 - iApply wp_struct_done. iIntros "!> _". done.
 - iApply (wp_bind [StructCtx vs es]). iApply (wp_wand with "[]"); [iApply IHexecutes1|].
   iIntros (v) "->". iApply wp_generic_struct_step. iApply IHexecutes2.
 - iApply (wp_bind [StructLoadCtx i]). iApply (wp_wand with "[]"); [iApply IHexecutes|].
   iIntros (v) "->". iApply wp_struct_load; [exact H0|]. iIntros "!> _". done.
Qed.
