-module(domain_isolation_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-compile([export_all, nowarn_export_all]).

-import(distributed_helper, [mim/0, require_rpc_nodes/1, rpc/4, subhost_pattern/1]).
-import(domain_helper, [host_type/0, secondary_host_type/0]).
-import(config_parser_helper, [mod_config/2]).

suite() ->
    require_rpc_nodes([mim]).

all() ->
    [{group, two_domains}].

groups() ->
    [{two_domains, [parallel], cases()}].

cases() ->
    [routing_one2one_message_inside_one_domain_works,
     routing_one2one_message_to_another_domain_gets_dropped,
     routing_one2one_message_to_another_domain_results_in_service_unavailable,
     routing_to_yours_subdomain_gets_passed_to_muc_module,
     routing_to_foreign_subdomain_results_in_service_unavailable].

host_types() ->
    %% Two domains may share host type but still must be isolated
    lists:usort([host_type(), secondary_host_type()]).

init_per_suite(Config) ->
    %% HARD REQUIREMENT:
    %% This suite only makes sense if mod_domain_isolation exists.
    case code:which(mod_domain_isolation) of
        non_existing ->
            ct:skip("mod_domain_isolation is not available in this distribution");
        _ ->
            instrument_helper:start([{router_stanza_dropped,
                                      #{host_type => host_type()}}]),
            escalus:init_per_suite(Config)
    end.

end_per_suite(Config) ->
    escalus:end_per_suite(Config),
    instrument_helper:stop().

modules() ->
    MucHost = subhost_pattern(muc_helper:muc_host_pattern()),
    Backend = mongoose_helper:mnesia_or_rdbms_backend(),
    [{mod_domain_isolation, []},
     {mod_muc_light,
      mod_config(mod_muc_light,
                 #{host => MucHost, backend => Backend})}].

init_per_group(two_domains, Config) ->
    Config2 = dynamic_modules:save_modules(host_types(), Config),
    [dynamic_modules:ensure_modules(HostType, modules())
     || HostType <- host_types()],
    Config2.

end_per_group(two_domains, Config) ->
    escalus_fresh:clean(),
    dynamic_modules:restore_modules(Config),
    Config.

init_per_testcase(Testcase, Config) ->
    escalus:init_per_testcase(Testcase, Config).

end_per_testcase(Testcase, Config) ->
    escalus:end_per_testcase(Testcase, Config).

%%--------------------------------------------------------------------
%% Tests
%%--------------------------------------------------------------------

routing_one2one_message_inside_one_domain_works(Config) ->
    F = fun(Alice, Bob) ->
          escalus_client:send(
            Bob, escalus_stanza:chat_to(Alice, <<"Hello">>)
          ),
          Stanza = escalus:wait_for_stanza(Alice),
          escalus:assert(is_chat_message, [<<"Hello">>], Stanza)
        end,
    escalus:fresh_story(Config, [{alice, 1}, {bob, 1}], F).

routing_one2one_message_to_another_domain_gets_dropped(Config) ->
    F = fun(Alice, Bob, Bis) ->
          Msg = escalus_stanza:chat_to(Alice, <<"Hello">>),
          escalus_client:send(Bis, Msg),
          verify_alice_has_no_pending_messages(Alice, Bob),
          assert_stanza_dropped(Bis, Alice, Msg)
        end,
    escalus:fresh_story(Config,
                        [{alice, 1}, {bob, 1}, {alice_bis, 1}],
                        F).

routing_one2one_message_to_another_domain_results_in_service_unavailable(Config) ->
    F = fun(Alice, Bis) ->
          escalus_client:send(
            Bis, escalus_stanza:chat_to(Alice, <<"Hello">>)
          ),
          receives_service_unavailable(Bis)
        end,
    escalus:fresh_story(Config, [{alice, 1}, {alice_bis, 1}], F).

routing_to_yours_subdomain_gets_passed_to_muc_module(Config) ->
    F = fun(Alice) ->
          escalus_client:send(Alice, invalid_muc_stanza()),
          receives_muc_bad_request(Alice)
        end,
    escalus:fresh_story(Config, [{alice, 1}], F).

routing_to_foreign_subdomain_results_in_service_unavailable(Config) ->
    F = fun(Alice) ->
          escalus_client:send(Alice, invalid_muc_stanza()),
          receives_service_unavailable(Alice)
        end,
    escalus:fresh_story(Config, [{alice_bis, 1}], F).

%%--------------------------------------------------------------------
%% Helpers
%%--------------------------------------------------------------------

get_error_text(Err) ->
    exml_query:path(Err,
                    [{element, <<"error">>},
                     {element, <<"text">>},
                     cdata]).

invalid_muc_address() ->
    MucHost = muc_helper:muc_host(),
    <<MucHost/binary, "/wow_resource_not_so_empty">>.

invalid_muc_stanza() ->
    escalus_stanza:chat_to(invalid_muc_address(), <<"Hi muc!">>).

receives_service_unavailable(Client) ->
    Err = escalus:wait_for_stanza(Client),
    escalus:assert(is_error,
                   [<<"cancel">>, <<"service-unavailable">>],
                   Err),
    <<"Filtered by the domain isolation">> = get_error_text(Err).

receives_muc_bad_request(Client) ->
    Err = escalus:wait_for_stanza(Client),
    escalus:assert(is_error,
                   [<<"modify">>, <<"bad-request">>],
                   Err),
    <<"Resource expected to be empty">> = get_error_text(Err).

verify_alice_has_no_pending_messages(Alice, Bob) ->
    escalus_client:send(
      Bob, escalus_stanza:chat_to(Alice, <<"Forces to flush">>)
    ),
    Stanza = escalus:wait_for_stanza(Alice),
    escalus:assert(is_chat_message,
                   [<<"Forces to flush">>],
                   Stanza).

assert_stanza_dropped(Sender, Recipient, Stanza) ->
    SenderJid = jid:from_binary(escalus_utils:get_jid(Sender)),
    RecipientJid = jid:from_binary(escalus_utils:get_jid(Recipient)),
    instrument_helper:assert_one(
      router_stanza_dropped,
      #{host_type => host_type()},
      fun(#{count := 1,
            from_jid := From,
            to_jid := To,
            stanza := DroppedStanza}) ->
          From =:= SenderJid
          andalso To =:= RecipientJid
          andalso DroppedStanza =:= Stanza
      end).
