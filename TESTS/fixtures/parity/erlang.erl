%% @doc Parity fixture — Erlang.
%%
%% One exported function, one unexported helper, an include, a call,
%% a module constant and a marker.
-module(parity_widget).

-include("other.hrl").

-export([widen/1]).

-define(MAX, 10).

%% @doc Double a value.
-spec double(integer()) -> integer().
double(N) ->
    N * 2.

%% @doc Widen a value.
%% TODO: cap at MAX
-spec widen(integer()) -> integer().
widen(N) ->
    double(N) + other:bump(?MAX).
