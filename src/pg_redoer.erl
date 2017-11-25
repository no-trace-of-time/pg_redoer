%%%-------------------------------------------------------------------
%%% @author simon
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 24. 十一月 2017 18:36
%%%-------------------------------------------------------------------
-module(pg_redoer).
-author("simon").

%% API
-export([
  add_notify/2
  , add_query/3
  , list_child/0
]).

%%  , mcht_pay_succ/1
%%  , mcht_refund/1
%%  , mcht_refund/2
%%]).

add_notify(Url, PostBody) ->
  pg_redoer_sup:start_child({notify, Url, PostBody}).

add_query(UpIndexKey, ActionFun, ResultHandleFun)
  when is_tuple(UpIndexKey), is_function(ActionFun), is_function(ResultHandleFun) ->
  pg_redoer_sup:start_child({query, UpIndexKey, ActionFun, ResultHandleFun}).

list_child() ->
  supervisor:count_children(pg_redoer_sup).

mcht_pay_succ(ModelMchtRespPay) when element(1, ModelMchtRespPay) =:= protocol_mcht_resp_pay ->

  lager:debug("prepare new notify, ModelMchtRespPay = ~p", [ModelMchtRespPay]),
  MchtInfoUrl = utils_recop:get(protocol_mcht_resp_pay, ModelMchtRespPay, mcht_back_url),
  PV = behaviour_protocol_model:model_2_out(protocol_mcht_resp_pay, ModelMchtRespPay, proplist),
  add_notify(MchtInfoUrl, PV).

mcht_refund({MchtId, TxnDate, TxnSeq} = _MchtIndexKey)
  when is_binary(MchtId), is_binary(TxnDate), is_binary(TxnSeq) ->

%%  8 = byte_size(TxnDate),
  xfutils:validate(yyyymmdd, TxnDate),

  % new model mcht refund resp
  {ok, ModelMchtInfoRefund} = model_mcht_info_refund:new({mcht_index_key, MchtId, TxnDate, TxnSeq}),
  lager:debug("ModelMchtInfoRefund = ~p", [model_mcht_info_refund:pr(ModelMchtInfoRefund)]),

  MchtInfoUrl = model_mcht_info_refund:get(ModelMchtInfoRefund, mcht_back_url),
  InfoPostVals = model_mcht_info_refund:to_post(ModelMchtInfoRefund, post_body_proplist),

  lager:debug("get_resp_postval_proplist return, RespPostVals = ~p", [InfoPostVals]),
  add_notify(MchtInfoUrl, InfoPostVals).

mcht_refund({MchtId, TxnDate, TxnSeq} = MchtIndexKey, SettleDate)
  when is_binary(MchtId), is_binary(TxnDate), is_binary(TxnSeq), is_binary(SettleDate) ->

%%  8 = byte_size(TxnDate),
%%  8 = byte_size(SettleDate),
  xfutils:validate(yyyymmdd, TxnDate),
  xfutils:validate(yyyymmdd, SettleDate),

  {200, {InfoPostVals, MchtInfoUrl}} = behaviour_txn_process:process(ph_process_mcht_notify_refund, {MchtIndexKey, SettleDate}),

  lager:debug("get_resp_postval_proplist return, RespPostVals = ~p", [InfoPostVals]),
  add_notify(MchtInfoUrl, InfoPostVals).
