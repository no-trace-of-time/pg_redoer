%%%-------------------------------------------------------------------
%%% @author simonxu
%%% @copyright (C) 2016, <COMPANY>
%%% @doc 实际处理通知消息的进程
%%%
%%% @end
%%% Created : 09. Apr 2016 11:06
%%%-------------------------------------------------------------------
-module(pg_redoer_worker).
-author("simonxu").
-include_lib("eunit/include/eunit.hrl").

-behaviour(gen_server).

%% API
-export([start_link/1
]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).
-define(APP, pg_redoer).

-record(state, {type, url, post_vals, count, up_index_key, action_fun, result_handle_fun}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec start_link(Param) ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()} when
  Param :: tuple().
start_link(Param) ->
  gen_server:start_link(?MODULE, [Param], []).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
  {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([{notify, Url, PostBody}]) ->

  lager:debug("new notify, Url = ~p,PostVals = ~p", [Url, PostBody]),
  {ok, RetryCount} = application:get_env(?APP, notify_retry_count),
  {ok, #state{
    type = notify,
    url = Url,
    post_vals = PostBody,
    count = RetryCount
  },
    0};
init([{query, UpIndexKey, ActionFun, ResultHandleFun}])
  when is_tuple(UpIndexKey), is_function(ActionFun), is_function(ResultHandleFun) ->
  lager:debug("new query, UpIndexKey = ~p", [UpIndexKey]),
  {ok, FirstTimeDelaySecons} = application:get_env(?APP, query_first_time_delay_seconds),
  {ok, QueryRetryCount} = application:get_env(?APP, query_retry_count),
  {ok, #state{
    type = query,
    up_index_key = UpIndexKey,
    action_fun = ActionFun,
    result_handle_fun = ResultHandleFun,
    count = QueryRetryCount
  }, FirstTimeDelaySecons}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
  {reply, Reply :: term(), NewState :: #state{}} |
  {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_cast(_Request, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_info(timeout, #state{type = notify} = State) ->
  %% timeout reached , need send notify info to url
  #state{
    url = Url,
    post_vals = PostBody,
    count = Count

  } = State,
%%  PostString = xfutils:post_vals_to_string(PostBody),
%%  lager:debug("PostString=~ts", [PostString]),
  try
    {200, _Header, _Body} = xfutils:post(Url, PostBody),
    lager:info("notify success, exit ...."),
    {stop, normal, State}
  catch
    _:_X ->
      case Count of
        1 ->
          %% last time not succ : not 200, or just error return
          %% exit anyway
          lager:error("Last notify, still error, aborted ...."),
          {stop, normal, State};
        _ ->
          lager:error("Notify error,retring....", []),
          {ok, Timeout} = application:get_env(notify_retry_timeout_seconds),
          ?debugFmt("Timeout = ~p,Count = ~p", [Timeout, Count]),
          {noreply, State#state{count = Count - 1}, Timeout * 1000}

      end
  end;
handle_info(timeout, #state{type = query} = State) ->
  %% timeout reached, need issue query txn to channel
  #state{
    up_index_key = UpIndexKey,
    count = Count,
    action_fun = ActionFun,
    result_handle_fun = ResultHandleFun
  } = State,

  try
    QueryResult = apply(ActionFun, [UpIndexKey]),
    lager:info("query result = ~p", [QueryResult]),
    ok = apply(ResultHandleFun, [QueryResult])
  catch
    _:_X ->
      %% some thing wrong
      %% maybe query result not succ
      %% maybe query process fail
      case Count of
        1 ->
          %% last time not succ
          %% exit anyway
          lager:error("Last query, still not success, aborted ..."),
          {stop, normal, State};
        _ ->
          lager:error("query error ,retring ...", []),
          {ok, TimeOut} = application:get_env(query_retry_timeout_seconds),
          ?debugFmt("Timeout = ~p,Count = ~p", [TimeOut, Count]),
          {noreply, State#state{count = Count - 1}, TimeOut * 1000}

      end
  end;

handle_info(_Info, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
  {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
