exception Entry_not_found
exception Bad_gateway

let rec get ?headers ?fallback uri =
  let headers = Ezgz.gzip_h headers in
  let open Lwt.Syntax in
  let* resp, body = Cohttp_lwt_unix.Client.get ?headers uri in
  let status = Cohttp_lwt.Response.status resp in
  if status <> `OK then Lwt.ignore_result (Cohttp_lwt.Body.drain_body body);
  match status with
  | `OK ->
    let* body = Cohttp_lwt.Body.to_string body in
    let is_gzipped : bool =
      Cohttp_lwt.Response.headers resp
      |> fun resp -> Cohttp.Header.get resp "content-encoding" = Some "gzip"
    in
    let open Ezgz in
    (try Lwt.return @@ extract is_gzipped body with
    | GzipError error -> Lwt.fail @@ Failure error)
  | `Found ->
    let uri' = Cohttp_lwt.(resp |> Response.headers |> Cohttp.Header.get_location) in
    (match uri', fallback with
    | Some uri, _ -> get ?headers ?fallback uri
    | None, Some uri -> get ?headers uri
    | None, None ->
      Lwt.fail_with ("Malformed redirection trying to access '" ^ Uri.to_string uri ^ "'."))
  | d when (d = `Not_found || d = `Gateway_timeout) && Option.is_some fallback ->
    (match fallback with
    | Some uri -> get ?headers uri
    | None -> assert false)
  | `Bad_request | `Not_found -> Lwt.fail Entry_not_found
  | `Bad_gateway -> Lwt.fail Bad_gateway
  | _ ->
    Lwt.fail_with
      ("Response error: '"
      ^ Cohttp.Code.string_of_status status
      ^ "' trying to access '"
      ^ Uri.to_string uri
      ^ "'.")