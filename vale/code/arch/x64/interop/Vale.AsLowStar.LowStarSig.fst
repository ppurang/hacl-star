module Vale.AsLowStar.LowStarSig
open X64.MemoryAdapters
open Interop.Base
module B = LowStar.Buffer
module BS = X64.Bytes_Semantics_s
module BV = LowStar.BufferView
module HS = FStar.HyperStack
module ME = X64.Memory
module TS = X64.Taint_Semantics_s
module MS = X64.Machine_s
module IA = Interop.Assumptions
module V = X64.Vale.Decls
module VS = X64.Vale.State
module IX64 = Interop.X64
module VSig = Vale.AsLowStar.ValeSig

[@__reduce__]
let nat_to_uint (t:ME.base_typ) (x:ME.base_typ_as_vale_type t)
  : base_typ_as_type t
  = let open ME in
    match t with
    | TUInt8   -> UInt8.uint_to_t x
    | TUInt16  -> UInt16.uint_to_t x
    | TUInt32  -> UInt32.uint_to_t x
    | TUInt64  -> UInt64.uint_to_t x
    | TUInt128 -> x


let uint_to_nat (t:ME.base_typ) (x:base_typ_as_type t)
  : ME.base_typ_as_vale_type t
  = let open ME in
    match t with
    | TUInt8   -> UInt8.v x
    | TUInt16  -> UInt16.v x
    | TUInt32  -> UInt32.v x
    | TUInt64  -> UInt64.v x
    | TUInt128 -> x

let nat_to_uint_seq_t
      (t:ME.base_typ)
      (b:Seq.seq (ME.base_typ_as_vale_type t))
    : Seq.seq (base_typ_as_type t)
    = Seq.init (Seq.length b) (fun (i:nat{i < Seq.length b}) -> nat_to_uint t (Seq.index b i))


let uint_to_nat_seq_t
      (t:ME.base_typ)
      (b:Seq.seq (base_typ_as_type t))
    : Seq.seq (ME.base_typ_as_vale_type t)
    = Seq.init (Seq.length b) (fun (i:nat{i < Seq.length b}) -> uint_to_nat t (Seq.index b i))


[@__reduce__]
let view_of_base_typ (t:ME.base_typ)
  : BV.view UInt8.t (base_typ_as_type t)
  = let open ME in
    match t with
    | TUInt8 -> Views.view8
    | TUInt16 -> Views.view16
    | TUInt32 -> Views.view32
    | TUInt64 -> Views.view64
    | TUInt128 -> Views.view128

//////////////////////////////////////////////////////////////////////////////////////////
//lowstar_sig pre post:
//    Interepreting a vale pre/post as a Low* function type
//////////////////////////////////////////////////////////////////////////////////////////
let hprop = HS.mem -> prop
let hsprop = HS.mem -> VS.state -> prop
module IB = Interop.Base

[@__reduce__]
let mem_correspondence_1
      (t:ME.base_typ)
      (x:IB.buf_t t)
      (h:HS.mem)
      (s:VS.state) =
  let y = as_vale_buffer x in
  Seq.equal
    (nat_to_uint_seq_t t (ME.buffer_as_seq s.VS.mem y))
    (BV.as_seq h (BV.mk_buffer_view x (view_of_base_typ t)))

[@__reduce__]
let mem_imm_correspondence_1
      (t:ME.base_typ)
      (x:IB.ibuf_t t)
      (h:HS.mem)
      (s:VS.state) =
  let y = as_vale_immbuffer x in
  Seq.equal
    (nat_to_uint_seq_t t (ME.buffer_as_seq s.VS.mem y))
    (BV.as_seq h (BV.mk_buffer_view x (view_of_base_typ t)))

[@__reduce__]
let rec mem_correspondence (args:list arg) : hsprop =
  match args with
  | [] -> fun h s -> True
  | hd :: tl ->
    let (| tag, x |) = hd in
    match tag with
    | TD_Buffer bt _ ->
      fun h s ->
        mem_correspondence_1 bt x h s /\
        mem_correspondence tl h s
    | TD_ImmBuffer bt _ ->
      fun h s ->
        mem_imm_correspondence_1 bt x h s /\
        mem_correspondence tl h s        
    | TD_Base _ ->
      mem_correspondence tl

[@__reduce__]
let arg_as_nat64 (a:arg) (s:VS.state) : GTot ME.nat64 =
  let (| tag, x |) = a in
  let open ME in
  match tag with
  | TD_Base TUInt8 ->
     UInt8.v x
  | TD_Base TUInt16 ->
     UInt16.v x
  | TD_Base TUInt32 ->
     UInt32.v x
  | TD_Base TUInt64 ->
     UInt64.v x
  | TD_Buffer bt _ ->
     buffer_addr_is_nat64 (as_vale_buffer #bt x) s;
     ME.buffer_addr (as_vale_buffer #bt x) VS.(s.mem)
  | TD_ImmBuffer bt _ ->
     buffer_addr_is_nat64 (as_vale_immbuffer #bt x) s;
     ME.buffer_addr (as_vale_immbuffer #bt x) VS.(s.mem)
    

[@__reduce__]
let rec register_args (max_arity:nat)
                      (arg_reg:IX64.arg_reg_relation max_arity)
                      (n:nat)
                      (args:IX64.arity_ok max_arity arg{List.length args = n}) : VSig.sprop =
    match args with
    | [] -> (fun s -> True)
    | hd::tl ->
      fun s ->
        register_args max_arity arg_reg (n - 1) tl s /\
        VS.eval_reg (arg_reg.IX64.of_arg (n - 1)) s == arg_as_nat64 hd s

[@__reduce__]
let taint_hyp_arg (m:ME.mem) (tm:MS.memTaint_t) (a:arg) =
   let (| tag, x |) = a in
    match tag with
    | TD_Buffer TUInt64 {taint=tnt} ->
      ME.valid_taint_buf64
         (as_vale_buffer #TUInt64 x)
         m
         tm
         tnt
    | TD_Buffer TUInt128 {taint=tnt} ->
      ME.valid_taint_buf128
         (as_vale_buffer #TUInt128 x)
         m
         tm
         tnt
    | TD_ImmBuffer TUInt64 {taint=tnt} ->
      ME.valid_taint_buf64
         (as_vale_immbuffer #TUInt64 x)
         m
         tm
         tnt
    | TD_ImmBuffer TUInt128 {taint=tnt} ->
      ME.valid_taint_buf128
         (as_vale_immbuffer #TUInt128 x)
         m
         tm
         tnt         
    | _ ->
      True

[@__reduce__]
let taint_hyp (args:list arg) : VSig.sprop =
  fun s0 -> BigOps.big_and' (taint_hyp_arg s0.VS.mem s0.VS.memTaint) args

[@__reduce__]
let vale_pre_hyp (#max_arity:nat) (#arg_reg:IX64.arg_reg_relation max_arity) #n (sb:IX64.stack_buffer n) (args:IX64.arity_ok max_arity arg) : VSig.sprop =
    fun s0 ->
      let s_args = arg_of_sb sb :: args in
      VSig.disjoint_or_eq s_args /\
      VSig.readable s_args VS.(s0.mem) /\
      register_args max_arity arg_reg (List.length args) args s0 /\
      taint_hyp args s0

[@__reduce__]
let to_low_pre
    (#max_arity:nat)
    (#arg_reg:IX64.arg_reg_relation max_arity)
    (#n:IX64.max_slots)
    (pre:VSig.vale_pre_tl n [])
    (args:IX64.arity_ok max_arity arg)
    (hs_mem:mem_roots args)
  : prop =
  (forall (s0:V.va_state)
     (sb:IX64.stack_buffer n).
    V.va_get_ok s0 /\
    vale_pre_hyp #max_arity #arg_reg #n sb args s0 /\
    mem_correspondence args hs_mem s0 /\
    V.valid_stack_slots s0.VS.mem (VS.eval_reg MS.Rsp s0) (as_vale_buffer sb) (n / 8) s0.VS.memTaint ==>
    elim_nil pre s0 sb)

[@__reduce__]
let to_low_post
    (#n:IX64.max_slots)
    (post:VSig.vale_post_tl n [])
    (args:list arg)
    (hs_mem0:mem_roots args)
    (res:UInt64.t)
    (hs_mem1:mem_roots args)
  : prop =
  let open V in
  B.modifies (loc_modified_args args) hs_mem0 hs_mem1 /\
  (exists
    (s0:va_state)
    (sb:IX64.stack_buffer n)
    (s1:va_state)
    (f:va_fuel).
       mem_correspondence args hs_mem0 s0 /\
       mem_correspondence args hs_mem1 s1 /\
       UInt64.v res == VS.eval_reg MS.Rax s1 /\
       elim_nil post s0 sb s1 f)

[@__reduce__]
let create_initial_vale_state
       (#max_arity:nat)
       (#arg_reg:IX64.arg_reg_relation max_arity)
       (#n:IX64.max_slots)
       (args:IX64.arity_ok max_arity arg)
  : IX64.state_builder_t n args V.va_state =
  fun h0 stack ->
    let t_state, mem = IX64.create_initial_trusted_state max_arity arg_reg n args Interop.down_mem h0 stack in
    let open VS in
    { ok = true;
      regs = X64.Vale.Regs.of_fun t_state.TS.state.BS.regs;
      xmms = X64.Vale.Xmms.of_fun t_state.TS.state.BS.xmms;
      flags = IA.init_flags;
      mem = as_vale_mem mem;
      memTaint = TS.(t_state.memTaint) }