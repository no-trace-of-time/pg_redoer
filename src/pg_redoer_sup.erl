%%%-------------------------------------------------------------------
%% @doc pg_redoer top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(pg_redoer_sup).
-include_lib("eunit/include/eunit.hrl").

-behaviour(supervisor).

%% API
-export([
  start_link/0
  , start_child/1
]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
  supervisor:start_link({local, ?SERVER}, ?MODULE, []).

start_child({notify, Url, PostBody} = Param) when is_binary(Url), is_binary(PostBody) ->
  Ret = supervisor:start_child(?SERVER, [Param]),
  lager:debug("Start redoer worker child, ret = ~p", [Ret]),
  ok.


%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
init([]) ->
  Children = [
    xfutils:child_spec(pg_redoer_worker, dynamic)
  ],
  RestartStrategy = xfutils:sup_restart_strategy(dynamic),
  ?debugFmt("Children = ~p,RestartStrategy = ~p", [Children, RestartStrategy]),
  {ok, {RestartStrategy, Children}}.

%%====================================================================
%% Internal functions
%%====================================================================
