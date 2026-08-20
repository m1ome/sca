defmodule Mix.Tasks.Api.Docs do
  @shortdoc "Regenerates the API documentation from the tests"

  @moduledoc """
  Rebuilds the merchant-facing API documentation, in two steps:

      mix api.docs

  `ScaApi.ApiDocsTest` runs with `DOC=1`, which is what makes Bureaucrat write
  `docs/api.apib` out of the calls that test really made — prose from
  `docs/api.intro.md` above them. Aglio then renders the blueprint into
  `apps/sca_web/priv/docs/api.html`, which the merchant console serves at
  `/docs`.

  Both outputs are committed: the release image has no Node in it, and the
  console has to be able to serve the page.

  Aglio is a Node program, fetched by `npx` on demand; nothing else here needs
  Node.
  """

  use Mix.Task

  @root Path.expand("../../../../..", __DIR__)
  @blueprint "docs/api.apib"
  @html "apps/sca_web/priv/docs/api.html"
  @aglio "aglio@2.3.0"

  @impl Mix.Task
  def run(_args) do
    blueprint()
    html()

    Mix.shell().info("#{@blueprint} and #{@html} written")
  end

  defp blueprint do
    Mix.shell().info("recording the examples…")

    cmd("mix", ["test", "test/sca_api/api_docs_test.exs"],
      cd: Path.join(@root, "apps/sca_api"),
      env: [{"DOC", "1"}]
    )
  end

  defp html do
    Mix.shell().info("rendering the blueprint…")
    File.mkdir_p!(Path.join(@root, Path.dirname(@html)))

    cmd(
      "npx",
      ["--yes", @aglio, "--theme-template", "triple", "-i", @blueprint, "-o", @html],
      cd: @root
    )
  end

  defp cmd(command, args, opts) do
    opts = Keyword.merge([into: IO.stream(:stdio, :line), stderr_to_stdout: true], opts)

    case System.cmd(command, args, opts) do
      {_output, 0} -> :ok
      {_output, status} -> Mix.raise("`#{command}` exited with #{status}")
    end
  rescue
    ErlangError -> Mix.raise("`#{command}` is not on the PATH; aglio needs Node installed")
  end
end
