%%==============================================================================
%% Copyright 2017 Erlang Solutions Ltd.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%==============================================================================

-module(mongoose_mam_id).
-author('konrad.zemek@erlang-solutions.com').

-export([next_unique/1, reset/0]).
-on_load(load/0).

-ignore_xref([reset/0]).

load() ->
    Path = filename:join(ejabberd:get_so_path(), ?MODULE_STRING),
    erlang:load_nif(Path, 0).

next_unique(_Candidate) ->
    erlang:nif_error(not_loaded).

reset() ->
    erlang:nif_error(not_loaded).
