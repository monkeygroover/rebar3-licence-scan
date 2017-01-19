-module(rebar_license_scan).

-behaviour(provider).

-export([init/1,
         do/1,
         format_error/1]).

-define(PROVIDER, 'license-scan').
-define(DEPS, [lock]).

-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    State1 = rebar_state:add_provider(
               State,
               providers:create([{name, ?PROVIDER},
                                 {module, ?MODULE},
                                 {bare, true},
                                 {deps, ?DEPS},
                                 {example, "rebar3 license-scan"},
                                 {short_desc, "Scan dependencies for license information"},
                                 {desc, ""},
                                 {opts, []}])),
    {ok, State1}.

-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, string()}.
do(State) ->
    print_deps_tree(rebar_state:all_deps(State), State),
    {ok, State}.

-spec format_error(any()) -> iolist().
format_error(Reason) ->
    io_lib:format("~p", [Reason]).

%% Internal functions

print_deps_tree(SrcDeps, State) ->
    Resources = rebar_state:resources(State),
    D = lists:foldl(fun(App, Dict) ->
                            Name = rebar_app_info:name(App),
                            Vsn = rebar_app_info:original_vsn(App),
                            AppDir = rebar_app_info:dir(App),
                            Vsn1 = rebar_utils:vcs_vsn(Vsn, AppDir, Resources),
                            Source  = rebar_app_info:source(App),
                            Parent = rebar_app_info:parent(App),
                            dict:append_list(Parent, [{Name, Vsn1, Source, AppDir}], Dict)
                    end, dict:new(), SrcDeps),
    ProjectAppNames = [{rebar_app_info:name(App)
                       ,rebar_utils:vcs_vsn(rebar_app_info:original_vsn(App), rebar_app_info:dir(App), Resources)
                       ,project, skip_folder} || App <- rebar_state:project_apps(State)],
    io:setopts([{encoding, unicode}]),
    case dict:find(root, D) of
        {ok, Children} ->
            print_children("", lists:keysort(1, Children++ProjectAppNames), D);
        error ->
            print_children("", lists:keysort(1, ProjectAppNames), D)
    end,
    io:setopts([{encoding, latin1}]).

print_children(_, [], _) ->
    ok;
print_children(Prefix, [{Name, Vsn, Source, AppDir} | Rest], Dict) ->
    Prefix1 = case Rest of
                [] ->
                    io:format("~ts~ts", [Prefix, <<226,148,148,226,148,128,32>>]), %Binary for └─ utf8%
                    [Prefix, "   "];
                _ ->
                    io:format("~ts~ts", [Prefix, <<226,148,156,226,148,128,32>>]), %Binary for ├─ utf8%
                    [Prefix, <<226,148,130,32,32>>] %Binary for │  utf8%
                end,
    License = detect_license(AppDir),

    io:format("~ts~ts~ts (~ts) ~ts~n", [Name, <<226,148,128>>, Vsn, type(Source), License]), %Binary for ─ utf8%

    case dict:find(Name, Dict) of
        {ok, Children} ->
            print_children(Prefix1, lists:keysort(1, Children), Dict),
            print_children(Prefix, Rest, Dict);
        error ->
            print_children(Prefix, Rest, Dict)
    end.

type(project) ->
    "project app";
type(checkout) ->
    "checkout app";
type(Source) ->
    case element(1, Source) of
        pkg ->
            "hex package";
        Other ->
            io_lib:format("~s repo", [Other])
    end.

detect_license(skip_folder) ->
    no_licence;
detect_license(AppDir) ->
    % call the ruby licensee gem to look for licence information
    case exec("licensee " ++ AppDir) of
        {0, Result} -> Result;
        {_, _Error} -> "Unable to determine license for " ++ AppDir
    end.

exec(Command) ->
    Port = open_port({spawn, Command}, [stream, in, eof, hide, exit_status]),
    get_data(Port, []).

get_data(Port, Sofar) ->
    receive
    {Port, {data, Bytes}} ->
        get_data(Port, [Sofar|Bytes]);
    {Port, eof} ->
        Port ! {self(), close},
        receive
        {Port, closed} ->
            true
        end,
        receive
        {'EXIT',  Port,  _} ->
            ok
        after 1 ->              % force context switch
            ok
        end,
        ExitCode =
            receive
            {Port, {exit_status, Code}} ->
                Code
        end,
        {ExitCode, lists:flatten(Sofar)}
    end.
