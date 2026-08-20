defmodule ScaApi.BlueprintWriter do
  @moduledoc """
  Turns what Bureaucrat recorded into an API Blueprint.

  Bureaucrat ships a writer of its own; this one exists because the document is
  read by merchants rather than by us. Endpoints are named the way a reader
  would name them ("Enrol a device", not `create_binding`), the prose from
  `detail:` sits under the heading, a list endpoint keeps the query it was
  called with, and a recorded conn's headers are cut down to the ones a caller
  has to send — a live bearer token is among them otherwise.

  The prose above the endpoints is `docs/api.intro.md`; `FORMAT` has to be the
  first line of a blueprint, so the file is assembled here rather than by
  prepending to somebody else's output.
  """

  alias Bureaucrat.Util

  @host "https://api.sca.example.com"
  @title "SCA API"

  # Everything else — content-type, which the media type beside the example
  # already says, and cache-control, x-request-id, the session — is noise in a
  # document whose subject is what a caller has to send.
  @headers ~w(authorization idempotency-key)

  def write(records, path) do
    groups =
      records
      |> Enum.map(&scrub/1)
      |> Util.stable_group_by(&opt(&1, :group_title))
      |> Enum.map(&group/1)

    File.write!(path, [preamble(path), groups])
  end

  defp preamble(path) do
    intro = path |> Path.rootname() |> Kernel.<>(".intro.md") |> File.read!()

    ["FORMAT: 1A\nHOST: #{@host}\n\n# #{@title}\n\n", intro]
  end

  # One resource per API, named by its group: the endpoints under it carry a
  # URI each, which is what lets `/bindings` and `/approvals` live together.
  defp group({title, records}) do
    endpoints = records |> Util.stable_group_by(&title/1) |> Enum.map(&endpoint/1)

    base = base_path(records)

    ["\n# Group #{title}\n\n## #{resource(records, base)} [#{base}]\n", endpoints]
  end

  defp endpoint({title, [first | _rest] = records}) do
    [
      "\n### #{title} [#{first.method} #{uri(first)}]\n",
      detail(records),
      parameters(first),
      Enum.map(records, &example/1)
    ]
  end

  # Written on whichever example carries it, and shown once, under the heading.
  defp detail(records) do
    case Enum.find_value(records, &opt(&1, :detail)) do
      nil -> []
      prose -> ["\n", prose]
    end
  end

  defp example(conn) do
    [
      "\n+ Request #{opt(conn, :description)}#{media(conn.body_params)}\n",
      headers(conn),
      body(conn.body_params),
      "\n+ Response #{conn.status}#{media(conn.resp_body)}\n",
      body(response(conn))
    ]
  end

  defp headers(%{req_headers: []}), do: []

  defp headers(conn) do
    lines = Enum.map_join(conn.req_headers, "\n", fn {name, value} -> "#{name}: #{value}" end)

    ["\n", indent(4, "+ Headers"), "\n\n", indent(12, lines), "\n"]
  end

  defp body(nil), do: []
  defp body(value) when value == %{}, do: []

  defp body(value) do
    ["\n", indent(4, "+ Body"), "\n\n", indent(12, Jason.encode!(value, pretty: true)), "\n"]
  end

  # A path parameter is part of the address; a query parameter is what a caller
  # may add. Blueprint wants both listed, and the query ones in the URI too.
  defp parameters(conn) do
    params =
      Enum.map(path_params(conn), &parameter(&1, "required")) ++
        Enum.map(query_params(conn), &parameter(&1, "optional"))

    case params do
      [] -> []
      params -> ["\n+ Parameters\n", params]
    end
  end

  defp parameter({name, value}, presence) do
    [indent(4, "+ #{name}: `#{value}` (string, #{presence})"), "\n"]
  end

  defp uri(conn) do
    case query_params(conn) do
      [] -> anchor(conn)
      params -> "#{anchor(conn)}{?#{Enum.map_join(params, ",", &elem(&1, 0))}}"
    end
  end

  # `/bindings/{id}`, not the uuid this example happened to be run against.
  defp anchor(conn), do: Enum.map_join(conn.path_info, "", &segment(&1, conn.path_params))

  defp segment(segment, path_params) do
    case Enum.find(path_params, fn {_name, value} -> value == segment end) do
      {name, _value} -> "/{#{name}}"
      nil -> "/#{segment}"
    end
  end

  # A name for the group's single resource, out of what hangs off its base
  # path: "Bindings and approvals". A path on its own would do, but a heading
  # that is only a URI is read as one by the blueprint parser.
  defp resource(records, base) do
    records
    |> Enum.map(&collection(&1, base))
    |> Enum.uniq()
    |> sentence()
  end

  defp collection(conn, base) do
    conn.request_path |> String.replace_prefix(base <> "/", "") |> String.split("/") |> hd()
  end

  defp sentence([only]), do: String.capitalize(only)

  defp sentence(collections) do
    {last, rest} = List.pop_at(collections, -1)

    "#{Enum.join(rest, ", ")} and #{last}" |> String.capitalize()
  end

  # What every endpoint in the group has in common: `/api/merchant/v1`.
  defp base_path(records) do
    records
    |> Enum.map(&String.split(&1.request_path, "/"))
    |> Enum.zip()
    |> Enum.take_while(fn segments ->
      segments |> Tuple.to_list() |> Enum.uniq() |> length() == 1
    end)
    |> Enum.map_join("/", &elem(&1, 0))
  end

  defp path_params(conn), do: Enum.sort(conn.path_params)

  defp query_params(%{query_params: %Plug.Conn.Unfetched{}}), do: []
  defp query_params(conn), do: Enum.sort(conn.query_params)

  # The examples were made against a test endpoint; the address a reader would
  # call is the one this document is about.
  defp response(%{resp_body: ""}), do: nil

  defp response(%{resp_body: body}) do
    body |> String.replace(ScaApi.Endpoint.url(), @host) |> Jason.decode!()
  end

  defp media(nil), do: ""
  defp media(""), do: ""
  defp media(value) when value == %{}, do: ""
  defp media(_value), do: " (application/json)"

  defp scrub(conn) do
    headers =
      conn.req_headers
      |> Enum.filter(fn {name, _value} -> name in @headers end)
      |> Enum.map(&placeholder/1)
      |> Enum.sort()

    %{conn | req_headers: Enum.map(headers, fn {name, value} -> {header_name(name), value} end)}
  end

  defp header_name(name),
    do: name |> String.split("-") |> Enum.map_join("-", &String.capitalize/1)

  # A key from a test run opens nothing, but it reads like a secret and would
  # change on every regeneration.
  defp placeholder({"authorization", "Bearer sca_" <> _key}) do
    {"authorization", "Bearer sca_live_9WKUq7yTdNjF2m..."}
  end

  defp placeholder({"authorization", "Bearer " <> _token}) do
    {"authorization", "Bearer eyJhbGciOi... (from POST /connections)"}
  end

  defp placeholder(header), do: header

  defp title(conn), do: opt(conn, :title)

  defp opt(conn, key), do: conn.assigns.bureaucrat_opts[key]

  defp indent(spaces, text), do: Bureaucrat.ApiBlueprintWriter.indent_lines(spaces, text)
end
