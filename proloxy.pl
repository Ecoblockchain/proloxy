/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   HTTP reverse proxy.

   Currently very preliminary:

   It only directs <File> to localhost:4041/<File>, that is, it just
   directs everything to a different port.

   Eventually, we want to relay requests to different ports based on
   flexible rules.

   This requires SWI-Prolog >= 7.3.12.

   Written by Markus Triska, July 2015.
   Public domain code.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

:- module(proloxy,
	  [ proloxy/1			% +Port
	  ]).

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_log)).
:- use_module(library(http/http_unix_daemon)).
:- use_module(library(http/http_ssl_plugin)).
:- use_module(library(http/http_open)).
:- use_module(library(http/http_header)).
:- use_module(library(http/http_error)).
:- use_module(library(http/html_write)).
:- use_module(library(http/http_server_files)).

%:- initialization http_daemon.

:- http_handler('/test',
                handle_request('/test', 'http://localhost:4041'),
                [prefix]).

:- http_handler('/rits',
                handle_request('/rits', 'http://localhost:4043'),
                [prefix]).


:- debug(proloxy).

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   1) is request_uri guaranteed to be present? how else to obtain the
      request URI? (please document it if it is the case)
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */


handle_request(Prefix, To, Request) :-
        debug(proloxy, "request: ~q\n", [Request]),
        memberchk(request_uri(URI0), Request),
        atom_concat(Prefix, URI, URI0),
        memberchk(method(Method0), Request),
        atomic_list_concat([To,URI], Target),
        debug(proloxy, "target: ~q\n", [Target]),
        method_pure(Method0, Method),
        proxy(Method, Prefix, Target, Request).

proxy(data(Method), _, Target, Request) :-
        read_data(Request, Data),
        http_open(Target, In, [method(Method), post(Data),
                               % cert_verify_hook(cert_accept_any),
                               header(content_type, ContentType)]),
        call_cleanup(read_string(In, _, Bytes),
                     close(In)),
        throw(http_reply(bytes(ContentType, Bytes))).
proxy(other(Method), Prefix, Target, _) :-
        http_open(Target, In, [method(Method),
                               % cert_verify_hook(cert_accept_any),
                               redirect(false),
                               header(location, Location0),
                               status_code(Code),
                               header(content_type, ContentType)]),
        call_cleanup(read_string(In, _, Bytes),
                     close(In)),
        (   redirect_code(Code, Status) ->
            (   uri_is_global(Location0) ->
                Location = Location0
            ;   atom_concat(Prefix, Location0, Location)
            ),
            Reply =.. [Status,Location],
            throw(http_reply(Reply))
        ;   throw(http_reply(bytes(ContentType, Bytes)))
        ).

redirect_code(301, moved).
redirect_code(302, moved_temporary).
redirect_code(303, see_other).

read_data(Request, bytes(ContentType, Bytes)) :-
        memberchk(input(In), Request),
        memberchk(content_type(ContentType), Request),
        (   memberchk(content_length(Len), Request) ->
            read_string(In, Len, Bytes)
        ;   read_string(In, _, Bytes)
        ).

method_pure(M0, M) :- once(defaulty_pure(M0, M)).

defaulty_pure(post, data(post)).
defaulty_pure(put, data(put)).
defaulty_pure(M, other(M)).

proloxy(Port) :-
	http_server(http_dispatch, [port(Port)]).

https_proloxy(Port) :-
	http_server(http_dispatch,
		    [ port(Port),
		      ssl([ certificate_file('server.crt'),
			    key_file('server.key'),
			    password("your_password")
			  ])
		    ]).

http:http_address -->
	html(address([a(href('https://github.com/triska/proloxy'),
                        'Proloxy')])).
