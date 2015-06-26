%% -------------------------------------------------------------------
%%
%% Copyright (c) 2007-2015 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

%% @doc Miscellaneous utility functions.

-module(machi_util).

-export([
         checksum_chunk/1,
         make_tagged_csum/1, make_tagged_csum/2,
         unmake_tagged_csum/1,
         hexstr_to_bin/1, bin_to_hexstr/1,
         hexstr_to_int/1, int_to_hexstr/2, int_to_hexbin/2,
         make_binary/1, make_string/1,
         make_regname/1,
         make_config_filename/2,
         make_checksum_filename/4, make_checksum_filename/2,
         make_data_filename/4, make_data_filename/2,
         make_projection_filename/2,
         read_max_filenum/2, increment_max_filenum/2,
         info_msg/2, verb/1, verb/2,
         mbytes/1,
         %% TCP protocol helpers
         connect/2, connect/3
        ]).
-compile(export_all).

-include("machi.hrl").
-include("machi_projection.hrl").
-include_lib("kernel/include/file.hrl").

%% @doc Create a registered name atom for FLU sequencer internal
%% rendezvous/message passing use.

-spec make_regname(binary()|string()) ->
      atom().
make_regname(Prefix) when is_binary(Prefix) ->
    erlang:binary_to_atom(Prefix, latin1);
make_regname(Prefix) when is_list(Prefix) ->
    erlang:list_to_atom(Prefix).

%% @doc Calculate a config file path, by common convention.

-spec make_config_filename(string(), string()) ->
      string().
make_config_filename(DataDir, Prefix) ->
    lists:flatten(io_lib:format("~s/config/~s", [DataDir, Prefix])).

%% @doc Calculate a checksum file path, by common convention.

-spec make_checksum_filename(string(), string(), atom()|string()|binary(), integer()) ->
      string().
make_checksum_filename(DataDir, Prefix, SequencerName, FileNum) ->
    lists:flatten(io_lib:format("~s/config/~s.~s.~w.csum",
                                [DataDir, Prefix, SequencerName, FileNum])).

%% @doc Calculate a checksum file path, by common convention.

-spec make_checksum_filename(string(), [] | string() | binary()) ->
      string().
make_checksum_filename(DataDir, "") ->
    lists:flatten(io_lib:format("~s/config", [DataDir]));
make_checksum_filename(DataDir, FileName) ->
    lists:flatten(io_lib:format("~s/config/~s.csum", [DataDir, FileName])).

%% @doc Calculate a file data file path, by common convention.

-spec make_data_filename(string(), string(), atom()|string()|binary(), integer()) ->
      {binary(), string()}.
make_data_filename(DataDir, Prefix, SequencerName, FileNum) ->
    File = erlang:iolist_to_binary(io_lib:format("~s.~s.~w",
                                                 [Prefix, SequencerName, FileNum])),
    FullPath = lists:flatten(io_lib:format("~s/data/~s",  [DataDir, File])),
    {File, FullPath}.

%% @doc Calculate a file data file path, by common convention.

-spec make_data_filename(string(), [] | string() | binary()) ->
      {binary(), string()}.
make_data_filename(DataDir, "") ->
    FullPath = lists:flatten(io_lib:format("~s/data",  [DataDir])),
    {"", FullPath};
make_data_filename(DataDir, File) ->
    FullPath = lists:flatten(io_lib:format("~s/data/~s",  [DataDir, File])),
    {File, FullPath}.

%% @doc Calculate a projection store file path, by common convention.

-spec make_projection_filename(string(), [] | string()) ->
      string().
make_projection_filename(DataDir, "") ->
    lists:flatten(io_lib:format("~s/projection",  [DataDir]));
make_projection_filename(DataDir, File) ->
    lists:flatten(io_lib:format("~s/projection/~s",  [DataDir, File])).

%% @doc Read the file size of a config file, which is used as the
%% basis for a minimum sequence number.

-spec read_max_filenum(string(), string()) ->
      non_neg_integer().
read_max_filenum(DataDir, Prefix) ->
    case file:read_file_info(make_config_filename(DataDir, Prefix)) of
        {error, enoent} ->
            0;
        {ok, FI} ->
            FI#file_info.size
    end.

%% @doc Increase the file size of a config file, which is used as the
%% basis for a minimum sequence number.

-spec increment_max_filenum(string(), string()) ->
      ok | {error, term()}.
increment_max_filenum(DataDir, Prefix) ->
    try
        {ok, FH} = file:open(make_config_filename(DataDir, Prefix), [append]),
        ok = file:write(FH, "x"),
        %% ok = file:sync(FH),
        ok = file:close(FH)
    catch
        error:{badmatch,_}=Error ->
            {error, {Error, erlang:get_stacktrace()}}
    end.

%% @doc Convert a hexadecimal string to a `binary()'.

-spec hexstr_to_bin(string() | binary()) ->
      binary().
hexstr_to_bin(S) when is_list(S) ->
  hexstr_to_bin(S, []);
hexstr_to_bin(B) when is_binary(B) ->
  hexstr_to_bin(binary_to_list(B), []).

hexstr_to_bin([], Acc) ->
  list_to_binary(lists:reverse(Acc));
hexstr_to_bin([X,Y|T], Acc) ->
  {ok, [V], []} = io_lib:fread("~16u", [X,Y]),
  hexstr_to_bin(T, [V | Acc]).

%% @doc Convert a `binary()' to a hexadecimal string.

-spec bin_to_hexstr(binary()) ->
      string().
bin_to_hexstr(<<>>) ->
    [];
bin_to_hexstr(<<X:4, Y:4, Rest/binary>>) ->
    [hex_digit(X), hex_digit(Y)|bin_to_hexstr(Rest)].

hex_digit(X) when X < 10 ->
    X + $0;
hex_digit(X) ->
    X - 10 + $a.

%% @doc Convert a compatible Erlang data type into a `binary()' equivalent.

-spec make_binary(binary() | iolist()) ->
      binary().
make_binary(X) when is_binary(X) ->
    X;
make_binary(X) when is_list(X) ->
    iolist_to_binary(X).

%% @doc Convert a compatible Erlang data type into a `string()' equivalent.

-spec make_string(binary() | iolist()) ->
      string().
make_string(X) when is_list(X) ->
    lists:flatten(X);
make_string(X) when is_binary(X) ->
    binary_to_list(X).

%% @doc Convert a hexadecimal string to an integer.

-spec hexstr_to_int(string() | binary()) ->
      non_neg_integer().
hexstr_to_int(X) ->
    B = hexstr_to_bin(X),
    B_size = byte_size(B) * 8,
    <<I:B_size/big>> = B,
    I.

%% @doc Convert an integer into a hexadecimal string whose length is
%% based on `I_size'.

-spec int_to_hexstr(non_neg_integer(), non_neg_integer()) ->
      string().
int_to_hexstr(I, I_size) ->
    bin_to_hexstr(<<I:I_size/big>>).

%% @doc Convert an integer into a hexadecimal string (in `binary()'
%% form) whose length is based on `I_size'.

-spec int_to_hexbin(non_neg_integer(), non_neg_integer()) ->
      binary().
int_to_hexbin(I, I_size) ->
    list_to_binary(int_to_hexstr(I, I_size)).

%% @doc Calculate a checksum for a chunk of file data.

-spec checksum_chunk(binary() | iolist()) ->
    binary().
checksum_chunk(Chunk) when is_binary(Chunk); is_list(Chunk) ->
    crypto:hash(sha, Chunk).

%% @doc Create a tagged checksum

make_tagged_csum(none) ->
    <<?CSUM_TAG_NONE:8>>;
make_tagged_csum({Tag, CSum}) ->
    make_tagged_csum(Tag, CSum).

make_tagged_csum(none, _SHA) ->
    <<?CSUM_TAG_NONE:8>>;
make_tagged_csum(client_sha, SHA) ->
    <<?CSUM_TAG_CLIENT_SHA:8, SHA/binary>>;
make_tagged_csum(server_sha, SHA) ->
    <<?CSUM_TAG_SERVER_SHA:8, SHA/binary>>;
make_tagged_csum(server_regen_sha, SHA) ->
    <<?CSUM_TAG_SERVER_REGEN_SHA:8, SHA/binary>>.

unmake_tagged_csum(<<Tag:8, Rest/binary>>) ->
    {Tag, Rest}.

%% @doc Log a verbose message.

-spec verb(string()) -> ok.
verb(Fmt) ->
    verb(Fmt, []).

%% @doc Log a verbose message.

-spec verb(string(), list()) -> ok.
verb(Fmt, Args) ->
    case application:get_env(kernel, verbose) of
        {ok, true} -> io:format(Fmt, Args);
        _          -> ok
    end.

mbytes(0) ->
    "0.0";
mbytes(Size) ->
    lists:flatten(io_lib:format("~.1.0f", [max(0.1, Size / (1024*1024))])).

%% @doc Log an 'info' level message.

-spec info_msg(string(), list()) -> term().
info_msg(Fmt, Args) ->
    case application:get_env(kernel, verbose) of {ok, false} -> ok;
                                                 _     -> error_logger:info_msg(Fmt, Args)
    end.

wait_for_death(Pid, 0) ->
    exit({not_dead_yet, Pid});
wait_for_death(Pid, Iters) when is_pid(Pid) ->
    case erlang:is_process_alive(Pid) of
        false ->
            ok;
        true  ->
            timer:sleep(1),
            wait_for_death(Pid, Iters-1)
    end.

%%%%%%%%%%%%%%%%%

%% @doc Create a TCP connection to a remote Machi server.

-spec connect(inet:ip_address() | inet:hostname(), inet:port_number()) ->
      port().
connect(Host, Port) ->
    escript_connect(Host, Port, 4500).

%% @doc Create a TCP connection to a remote Machi server.

-spec connect(inet:ip_address() | inet:hostname(), inet:port_number(),
              timeout()) ->
      port().
connect(Host, Port, Timeout) ->
    escript_connect(Host, Port, Timeout).

escript_connect(Host, PortStr, Timeout) when is_list(PortStr) ->
    Port = list_to_integer(PortStr),
    escript_connect(Host, Port, Timeout);
escript_connect(Host, Port, Timeout) when is_integer(Port) ->
    {ok, Sock} = gen_tcp:connect(Host, Port, [{active,false}, {mode,binary},
                                              {packet, raw}], Timeout),
    Sock.
