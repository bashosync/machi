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

-module(machi_pb_translate).

-include("machi.hrl").
-include("machi_pb.hrl").
-include("machi_projection.hrl").

-export([from_pb/1,
         to_pb/2,
         to_pb/3
        ]).

from_pb(#mpb_ll_request{req_id=ReqID,
                        echo=#mpb_echoreq{message=Msg}}) ->
    {ReqID, {low_echo, Msg}};
from_pb(#mpb_ll_request{req_id=ReqID,
                     auth=#mpb_authreq{user=User, password=Pass}}) ->
    {ReqID, {low_auth, User, Pass}};
from_pb(#mpb_ll_request{
           req_id=ReqID,
           checksum_list=#mpb_ll_checksumlistreq{epoch_id=PB_EpochID,
                                                 file=File}}) ->
    EpochID = conv_to_epoch_id(PB_EpochID),
    {ReqID, {low_checksum_list, EpochID, File}};
from_pb(#mpb_ll_response{req_id=ReqID,
                         echo=#mpb_echoresp{message=Msg}}) ->
    {ReqID, Msg};
from_pb(#mpb_ll_response{req_id=ReqID,
                         checksum_list=#mpb_ll_checksumlistresp{
                           status=Status, chunk=Chunk}}) ->
    case Status of
        'OK' ->
            {ReqID, {ok, Chunk}};
        _ ->
            {ReqID, machi_pb_high_client:convert_general_status_code(Status)}
    end;
from_pb(#mpb_ll_response{req_id=ReqID,
                         proj_gl=#mpb_ll_getlatestepochidresp{
        status=Status, epoch_id=EID}}) ->
    case Status of
        'OK' ->
            #mpb_epochid{epoch_number=Epoch, epoch_csum=CSum} = EID,
            {ReqID, {ok, {Epoch, CSum}}};
        _ ->
            {ReqID, machi_pb_high_client:convert_general_status_code(Status)}
    end;
from_pb(#mpb_ll_response{req_id=ReqID,
                         proj_rl=#mpb_ll_readlatestprojectionresp{
        status=Status, proj=P}}) ->
    case Status of
        'OK' ->
            {ReqID, {ok, conv_to_projection_v1(P)}};
        _ ->
            {ReqID, machi_pb_high_client:convert_general_status_code(Status)}
    end;
from_pb(#mpb_ll_response{req_id=ReqID,
                         proj_rp=#mpb_ll_readprojectionresp{
        status=Status, proj=P}}) ->
    case Status of
        'OK' ->
            {ReqID, {ok, conv_to_projection_v1(P)}};
        _ ->
            {ReqID, machi_pb_high_client:convert_general_status_code(Status)}
    end;
from_pb(#mpb_ll_response{req_id=ReqID,
                         proj_wp=#mpb_ll_writeprojectionresp{
        status=Status}}) ->
    {ReqID, machi_pb_high_client:convert_general_status_code(Status)};
from_pb(#mpb_ll_response{req_id=ReqID,
                         proj_ga=#mpb_ll_getallprojectionsresp{
        status=Status, projs=ProjsM}}) ->
    case Status of
        'OK' ->
            {ReqID, {ok, [conv_to_projection_v1(ProjM) || ProjM <- ProjsM]}};
        _ ->
            {ReqID, machi_pb_high_client:convert_general_status_code(Status)}
    end;
from_pb(#mpb_ll_response{req_id=ReqID,
                         proj_la=#mpb_ll_listallprojectionsresp{
        status=Status, epochs=Epochs}}) ->
    case Status of
        'OK' ->
            {ReqID, {ok, Epochs}};
        _ ->
            {ReqID< machi_pb_high_client:convert_general_status_code(Status)}
    end;
%-%-%-%-%
from_pb(#mpb_request{req_id=ReqID,
                     echo=#mpb_echoreq{message=Msg}}) ->
    {ReqID, {high_echo, Msg}};
from_pb(#mpb_request{req_id=ReqID,
                     auth=#mpb_authreq{user=User, password=Pass}}) ->
    {ReqID, {high_auth, User, Pass}};
from_pb(#mpb_request{req_id=ReqID,
                     append_chunk=IR=#mpb_appendchunkreq{}}) ->
    #mpb_appendchunkreq{placement_key=__todoPK,
                        prefix=Prefix,
                        chunk=ChunkBin,
                        csum=CSum,
                        chunk_extra=ChunkExtra} = IR,
    TaggedCSum = make_tagged_csum(CSum, ChunkBin),
    {ReqID, {high_append_chunk, __todoPK, Prefix, ChunkBin, TaggedCSum,
             ChunkExtra}};
from_pb(#mpb_request{req_id=ReqID,
                     write_chunk=IR=#mpb_writechunkreq{}}) ->
    #mpb_writechunkreq{file=File,
                       offset=Offset,
                       chunk=ChunkBin,
                       csum=CSum} = IR,
    TaggedCSum = make_tagged_csum(CSum, ChunkBin),
    {ReqID, {high_write_chunk, File, Offset, ChunkBin, TaggedCSum}};
from_pb(#mpb_request{req_id=ReqID,
                     read_chunk=IR=#mpb_readchunkreq{}}) ->
    #mpb_readchunkreq{file=File,
                      offset=Offset,
                      size=Size} = IR,
    {ReqID, {high_read_chunk, File, Offset, Size}};
from_pb(#mpb_request{req_id=ReqID,
                     checksum_list=IR=#mpb_checksumlistreq{}}) ->
    #mpb_checksumlistreq{file=File} = IR,
    {ReqID, {high_checksum_list, File}};
from_pb(#mpb_request{req_id=ReqID,
                     list_files=_IR=#mpb_listfilesreq{}}) ->
    {ReqID, {high_list_files}};
from_pb(#mpb_request{req_id=ReqID}) ->
    {ReqID, {high_error, 999966, "Unknown request"}};
from_pb(_) ->
    {<<>>, {high_error, 999667, "Unknown PB request"}}.

to_pb(ReqID, {low_echo, Msg}) ->
    #mpb_ll_request{
       req_id=ReqID,
       echo=#mpb_echoreq{message=Msg}};
to_pb(ReqID, {low_checksum_list, EpochID, File}) ->
    PB_EpochID = conv_from_epoch_id(EpochID),
    #mpb_ll_request{
           req_id=ReqID,
           checksum_list=#mpb_ll_checksumlistreq{epoch_id=PB_EpochID,
                                                 file=File}}.
to_pb(ReqID, {low_echo, Msg}, Resp) ->
    #mpb_ll_response{
       req_id=ReqID,
       echo=#mpb_echoresp{message=Msg}};
to_pb(ReqID, {low_checksum_list, _EpochID, _File}, Resp) ->
    case Resp of
        {ok, Chunk} ->
            make_ll_checksum_list_resp(ReqID, 'OK', Chunk);
        {error, bad_arg} ->
            make_ll_checksum_list_resp(ReqID, 'BAD_ARG', undefined);
        {error, wedged} ->
            make_ll_checksum_list_resp(ReqID, 'WEDGED', undefined);
        {error, bad_checksum} ->
            make_ll_checksum_list_resp(ReqID, 'BAD_CHECKSUM', undefined);
        {error, partition} ->
            make_ll_checksum_list_resp(ReqID, 'PARTITION', undefined);
        {error, no_such_file} ->
            make_ll_checksum_list_resp(ReqID, 'NO_SUCH_FILE', undefined);
        _Else ->
            make_ll_error_resp(ReqID, 66, io_lib:format("err ~p", [_Else]))
    end;
to_pb(ReqID, {high_echo, _Msg}, Resp) ->
    Msg = Resp,
    #mpb_response{req_id=ReqID,
                  echo=#mpb_echoresp{message=Msg}};
to_pb(ReqID, {high_auth, _User, _Pass}, _Resp) ->
    #mpb_response{req_id=ReqID,
                  generic=#mpb_errorresp{code=1,
                                         msg="AUTH not implemented"}};
to_pb(ReqID, {high_append_chunk, _TODO, _Prefix, _ChunkBin, _TSum, _CE}, Resp)->
    case Resp of
        {ok, {Offset, Size, File}} ->
            make_append_resp(ReqID, 'OK',
                             #mpb_chunkpos{offset=Offset,
                                           chunk_size=Size,
                                           file_name=File});
        {error, bad_arg} ->
            make_append_resp(ReqID, 'BAD_ARG');
        {error, wedged} ->
            make_append_resp(ReqID, 'WEDGED');
        {error, bad_checksum} ->
            make_append_resp(ReqID, 'BAD_CHECKSUM');
        {error, partition} ->
            make_append_resp(ReqID, 'PARTITION');
        _Else ->
            make_error_resp(ReqID, 66, io_lib:format("err ~p", [_Else]))
    end;
to_pb(ReqID, {high_write_chunk, _File, _Offset, _ChunkBin, _TaggedCSum}, Resp) ->
    case Resp of
        {ok, {_,_,_}} ->
            %% machi_cr_client returns ok 2-tuple, convert to simple ok.
            make_write_resp(ReqID, 'OK');
        {error, bad_arg} ->
            make_write_resp(ReqID, 'BAD_ARG');
        {error, wedged} ->
            make_write_resp(ReqID, 'WEDGED');
        {error, bad_checksum} ->
            make_write_resp(ReqID, 'BAD_CHECKSUM');
        {error, partition} ->
            make_write_resp(ReqID, 'PARTITION');
        _Else ->
            make_error_resp(ReqID, 66, io_lib:format("err ~p", [_Else]))
    end;
to_pb(ReqID, {high_read_chunk, _File, _Offset, _Size}, Resp) ->
    case Resp of
        {ok, Chunk} ->
            make_read_resp(ReqID, 'OK', Chunk);
        {error, bad_arg} ->
            make_read_resp(ReqID, 'BAD_ARG', undefined);
        {error, wedged} ->
            make_read_resp(ReqID, 'WEDGED', undefined);
        {error, bad_checksum} ->
            make_read_resp(ReqID, 'BAD_CHECKSUM', undefined);
        {error, partition} ->
            make_read_resp(ReqID, 'PARTITION', undefined);
        _Else ->
            make_error_resp(ReqID, 66, io_lib:format("err ~p", [_Else]))
    end;
to_pb(ReqID, {high_checksum_list, _File}, Resp) ->
    case Resp of
        {ok, Chunk} ->
            make_checksum_list_resp(ReqID, 'OK', Chunk);
        {error, bad_arg} ->
            make_checksum_list_resp(ReqID, 'BAD_ARG', undefined);
        {error, wedged} ->
            make_checksum_list_resp(ReqID, 'WEDGED', undefined);
        {error, bad_checksum} ->
            make_checksum_list_resp(ReqID, 'BAD_CHECKSUM', undefined);
        {error, partition} ->
            make_checksum_list_resp(ReqID, 'PARTITION', undefined);
        _Else ->
            make_error_resp(ReqID, 66, io_lib:format("err ~p", [_Else]))
    end;
to_pb(ReqID, {high_list_files}, Resp) ->
    case Resp of
        {ok, FileInfo} ->
            make_list_files_resp(ReqID, 'OK', FileInfo);
        {error, bad_arg} ->
            make_list_files_resp(ReqID, 'BAD_ARG', []);
        {error, wedged} ->
            make_list_files_resp(ReqID, 'WEDGED', []);
        {error, bad_checksum} ->
            make_list_files_resp(ReqID, 'BAD_CHECKSUM', []);
        {error, partition} ->
            make_list_files_resp(ReqID, 'PARTITION', []);
        _Else ->
            make_error_resp(ReqID, 66, io_lib:format("err ~p", [_Else]))
    end;
to_pb(ReqID, {high_error, _, _}, {ErrCode, ErrMsg}) ->
    make_error_resp(ReqID, ErrCode, ErrMsg).

make_tagged_csum(#mpb_chunkcsum{type='CSUM_TAG_NONE'}, ChunkBin) ->
    C = machi_util:checksum_chunk(ChunkBin),
    machi_util:make_tagged_csum(server_sha, C);
make_tagged_csum(#mpb_chunkcsum{type='CSUM_TAG_CLIENT_SHA', csum=CSum}, _CB) ->
    machi_util:make_tagged_csum(client_sha, CSum).

make_ll_checksum_list_resp(ReqID, Status, __todo__Chunk) ->
    Chunk = <<"TODO item: refactor the checksum_list op to return simply the text file representation of the checksums?">>,
    #mpb_ll_response{req_id=ReqID,
                     checksum_list=#mpb_ll_checksumlistresp{status=Status,
                                                            chunk=Chunk}}.
make_ll_error_resp(ReqID, Code, Msg) ->
    #mpb_ll_response{req_id=ReqID,
                     generic=#mpb_errorresp{code=Code,
                                            msg=Msg}}.    

make_append_resp(ReqID, Status) ->
    make_append_resp(ReqID, Status, undefined).

make_append_resp(ReqID, Status, Where) ->
    #mpb_response{req_id=ReqID,
                  append_chunk=#mpb_appendchunkresp{status=Status,
                                                    chunk_pos=Where}}.

make_write_resp(ReqID, Status) ->
    #mpb_response{req_id=ReqID,
                  write_chunk=#mpb_writechunkresp{status=Status}}.

make_read_resp(ReqID, Status, Chunk) ->
    #mpb_response{req_id=ReqID,
                  read_chunk=#mpb_readchunkresp{status=Status,
                                                chunk=Chunk}}.

make_checksum_list_resp(ReqID, Status, __todo__Chunk) ->
    Chunk = <<"TODO item: refactor the checksum_list op to return simply the text file representation of the checksums?">>,
    #mpb_response{req_id=ReqID,
                  checksum_list=#mpb_checksumlistresp{status=Status,
                                                      chunk=Chunk}}.

make_list_files_resp(ReqID, Status, FileInfo) ->
    Files = [#mpb_fileinfo{file_size=Size, file_name=Name} ||
                {Size, Name} <- FileInfo],
    #mpb_response{req_id=ReqID,
                  list_files=#mpb_listfilesresp{status=Status,
                                                files=Files}}.

make_error_resp(ReqID, Code, Msg) ->
    #mpb_response{req_id=ReqID,
                  generic=#mpb_errorresp{code=Code,
                                         msg=Msg}}.    

conv_from_epoch_id({Epoch, EpochCSum}) ->
    #mpb_epochid{epoch_number=Epoch,
                 epoch_csum=EpochCSum}.

conv_to_epoch_id(#mpb_epochid{epoch_number=Epoch,
                              epoch_csum=EpochCSum}) ->
    {Epoch, EpochCSum}.

conv_to_projection_v1(#mpb_projectionv1{epoch_number=Epoch,
                                        epoch_csum=CSum,
                                        author_server=Author,
                                        all_members=AllMembers,
                                        creation_time=CTime,
                                        mode=Mode,
                                        upi=UPI,
                                        repairing=Repairing,
                                        down=Down,
                                        opaque_flap=Flap,
                                        opaque_inner=Inner,
                                        opaque_dbg=Dbg,
                                        opaque_dbg2=Dbg2,
                                        members_dict=MembersDict}) ->
    #projection_v1{epoch_number=Epoch,
                   epoch_csum=CSum,
                   author_server=to_atom(Author),
                   all_members=[to_atom(X) || X <- AllMembers],
                   creation_time=conv_to_now(CTime),
                   mode=conv_to_mode(Mode),
                   upi=[to_atom(X) || X <- UPI],
                   repairing=[to_atom(X) || X <- Repairing],
                   down=[to_atom(X) || X <- Down],
                   flap=dec_optional_sexp(Flap),
                   inner=dec_optional_sexp(Inner),
                   dbg=dec_sexp(Dbg),
                   dbg2=dec_sexp(Dbg2),
                   members_dict=conv_to_members_dict(MembersDict)}.

enc_sexp(T) ->
    term_to_binary(T).

dec_sexp(Bin) when is_binary(Bin) ->
    binary_to_term(Bin).

enc_optional_sexp(undefined) ->
    undefined;
enc_optional_sexp(T) ->
    enc_sexp(T).

dec_optional_sexp(undefined) ->
    undefined;
dec_optional_sexp(T) ->
    dec_sexp(T).

conv_from_members_dict(D) ->
    %% Use list_to_binary() here to "flatten" the serialized #p_srvr{}
    [#mpb_membersdictentry{key=to_list(K), val=conv_from_p_srvr(V)} ||
        {K, V} <- orddict:to_list(D)].

conv_to_members_dict(List) ->
    orddict:from_list([{to_atom(K), conv_to_p_srvr(V)} ||
                          #mpb_membersdictentry{key=K, val=V} <- List]).

conv_from_p_srvr(#p_srvr{name=Name,
                   proto_mod=ProtoMod,
                   address=Address,
                   port=Port,
                   props=Props}) ->
    #mpb_p_srvr{name=to_list(Name),
                proto_mod=to_list(ProtoMod),
                address=to_list(Address),
                port=to_list(Port),
                opaque_props=enc_sexp(Props)}.

conv_to_p_srvr(#mpb_p_srvr{name=Name,
                           proto_mod=ProtoMod,
                           address=Address,
                           port=Port,
                           opaque_props=Props}) ->
    #p_srvr{name=to_atom(Name),
            proto_mod=to_atom(ProtoMod),
            address=to_list(Address),
            port=to_integer(Port),
            props=dec_sexp(Props)}.

to_list(X) when is_atom(X) ->
    atom_to_list(X);
to_list(X) when is_binary(X) ->
    binary_to_list(X);
to_list(X) when is_integer(X) ->
    integer_to_list(X);
to_list(X) when is_list(X) ->
    X.

to_atom(X) when is_list(X) ->
    list_to_atom(X);
to_atom(X) when is_binary(X) ->
    erlang:binary_to_atom(X, latin1);
to_atom(X) when is_atom(X) ->
    X.

to_integer(X) when is_list(X) ->
    list_to_integer(X);
to_integer(X) when is_binary(X) ->
    list_to_binary(binary_to_list(X));
to_integer(X) when is_integer(X) ->
    X.

conv_from_now({A,B,C}) ->
    #mpb_now{sec=(1000000 * A) + B,
             usec=C}.

conv_to_now(#mpb_now{sec=Sec, usec=USec}) ->
    {Sec div 1000000, Sec rem 1000000, USec}.

conv_from_mode(ap_mode) -> 'AP_MODE';
conv_from_mode(cp_mode) -> 'CP_MODE'.

conv_to_mode('AP_MODE') -> ap_mode;
conv_to_mode('CP_MODE') -> cp_mode.

conv_from_type(private) -> 'PRIVATE';
conv_from_type(public)  -> 'PUBLIC'.

conv_to_type('PRIVATE') -> private;
conv_to_type('PUBLIC')  -> public.

conv_from_status(ok) ->
    'OK';
conv_from_status({error, bad_arg}) ->
    'BAD_ARG';
conv_from_status({error, wedged}) ->
    'WEDGED';
conv_from_status({error, bad_checksum}) ->
    'BAD_CHECKSUM';
conv_from_status({error, partition}) ->
    'PARTITION';
conv_from_status({error, not_written}) ->
    'NOT_WRITTEN';
conv_from_status({error, written}) ->
    'WRITTEN';
conv_from_status({error, no_such_file}) ->
    'NO_SUCH_FILE';
conv_from_status(_OOPS) ->
    io:format(user, "HEY, ~s:~w got ~w\n", [?MODULE, ?LINE, _OOPS]),
    'BAD_JOSS'.