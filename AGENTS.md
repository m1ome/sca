This is a web application written using the Phoenix web framework.

## SCA umbrella

- `apps/sca` is the domain, and the only application that talks to the database.
  Three layers inside it: `Sca.Models.*` (schemas, changesets, the entity's own
  policy), `Sca.Repos.*Repo` (queries only, answering
  `{:ok, _} | {:error, :not_found}`), `Sca.Actions.*` (one module per aggregate —
  `Tenant`, `Binding`, `Request` — where transactions and side effects live).
  Plus `Sca.Workers.*`, `Sca.Webhooks` and `Sca.Push`.
- New business logic goes into its aggregate's action module, not into a repo and
  not into a model. An `if` appearing in a repo is a reason to write an action.
- There is no authentication in the domain: password checks and bearer parsing
  live in `sca_api` / `sca_web` / `sca_admin`. Do not move them back.
- Inside actions, models are reached through `alias Sca.Models` (`Models.Binding`)
  — a direct alias would collide with the action module's own name.
- A repo starts with `use Sca.Repo.Base, model: Sca.Models.X`: CRUD,
  `get_by_public_id/1` and the Flop `list/1` are already there. Add only what is
  specific to that entity; overriding the base is fine (`UserRepo.update/2`).
- In models: enum values as `~w(active suspended)a`, fields as
  `@required_fields` / `@optional_fields` / `@all_fields`, casting from
  `@all_fields`, `validate_required(@required_fields)`. What lists may filter and
  sort by goes into `@derive {Flop.Schema, ...}` in the same file.
- `apps/sca_api` is the JSON API (dev: 4001), `apps/sca_web` the merchant console
  (4000), `apps/sca_admin` the internal one (4002). They call the domain, never
  `Sca.Repo`.
- Postgres comes up with `docker compose up -d db` on `localhost:55433`.
- Everything read from the environment belongs in `config/runtime.exs`, written
  once against the `endpoints` list: the three endpoints differ only in variable
  names, so a fourth copied block is a reason to write a loop. Compile-time
  settings (`cache_static_manifest`) go in `prod.exs`.
- TLS is terminated in front of the application; the endpoints speak plain HTTP
  and only their `:url` says `https`. No certificates in config, no `force_ssl`.
- Production is the `sca` release built by the `Dockerfile`; migrations run as
  their own step through `/app/bin/setup` (`Sca.Release.setup/0`: migrations plus
  the first staff account) or `/app/bin/migrate` for the schema alone. There is
  no `mix` in the image, so anything that has to be runnable in production lives
  in `Sca.Release` and gets a wrapper in `rel/overlays/bin`.
- Schemas are declared with `use Sca.Schema, public_id: "TNT"`: a UUID key plus a
  human-readable `public_id` (`TNT-1`, `BIN-42`) created by the migration through
  `Sca.Repo.Migration.add_public_id/2`. Parsing is `Sca.PublicId`.
- Test factories are `Sca.Factory` (ExMachina); a device with a real key pair is
  `Sca.Support.Device` (`Device.bind/2`, `Device.decide/3`). Jobs do not run in
  tests (`Oban` in `testing: :manual`), and the webhook and push clients are
  `Sca.Webhooks.ClientMock` and `Sca.Push.ClientMock` (Mox).
- `Sca.Crypto` is a cross-language contract with the mobile client. Changing the
  canonical form, the signing strings or the key format breaks signatures in the
  field: change it together with the client, and with the vector in
  `test/sca/crypto_test.exs`.
- Webhooks are `Sca.Webhooks`, not an action: `Webhooks.queue(event, entity)`
  inside the action's transaction, or `emit/2` when there is none. The action
  passes an event and an entity; tenant, payload, envelope and delivery are the
  module's business. A new event goes into `@events` and `Sca.Webhooks.Payload`,
  sample included — a merchant can fire any of them at their own endpoint from
  Settings (`Webhooks.send_test/2`: one call on the caller's process, no Oban, no
  retries, the real envelope with `"test": true` and `Payload.sample/1` inside).
- Push is `Sca.Push`, built the same way: `Push.queue(request, binding)` inside
  the transaction, the message shape in `Sca.Push.Message`, sending in
  `Sca.Workers.PushWorker`. A notification carries `title` and `description` and
  nothing else — it passes through Google and Apple onto a lock screen. The
  `data` keys (`c`, `a`, `x`) are a contract with the mobile client.
- Actions log explicitly, in the branch where the decision was made:
  `Logger.info("[actions.<aggregate>.<operation>] <public_id> …")` on success,
  `Logger.warning` on a refusal, `Logger.error` when giving up. No wrappers like
  `log_ok`: a log line should be visible in the code, not hidden behind a pipe.
- A log message is **one interpolated string** — no `<>`, no line breaks. If it
  does not fit, it carries too much: the details are in the database row, the log
  needs identifiers and an outcome.
- Every `{:error, _}` leaving an action is logged where it is returned; a silent
  refusal cannot be debugged in production. Format the reason with `reason/1`
  from `Sca.Actions.Helpers`.
- Logs carry identifiers and statuses, never passwords, tokens, signatures or the
  contents of a card.
- HTTP requests are logged by Logster (one line, logfmt in dev, JSON in prod);
  Phoenix's own logger is off. A new parameter carrying a secret goes into
  `filter_parameters` in `config/config.exs` (substring match). A noisy endpoint
  is quieted with a `Logster.ChangeConfig` plug in its own controller, not by
  editing the global config.
- Do not match a transaction result rigidly (`{:ok, x} = Repo.transact(...)`):
  take it apart with `case` and log it. A `MatchError` in production is worse
  than a refusal.
- Next to a log line, a counter: `Sca.Telemetry.emit([:request, :decided], …)`.
  Logs answer "what happened to REQ-4711", telemetry answers "how many signatures
  fail today". New events are described in the table in `Sca.Telemetry`.
- The boundary layers (`sca_api`, `sca_web`, `sca_admin`) reach entities **only**
  through `Sca.Scope` (`fetch_binding/2`, `fetch_request/2`, …), never through
  repos: another tenant must get `:not_found`.
- Anything shared by actions goes into `Sca.Actions.Helpers` (`stringify/1`,
  `reason/1`), not into a third copy of a private function.
- Time is `Timex`, not `DateTime`: `Timex.now/0`, `Timex.shift/2`,
  `Timex.before?/2`, `Timex.after?/2`, `Timex.diff/3`, `Timex.format!/2`. Watch
  out: `Timex.compare/2` returns `-1 | 0 | 1`, not `:lt | :eq | :gt`.
- `mix typecheck` is dialyzer, and it must stay clean. Silence a warning only
  with a targeted `@dialyzer {:no_opaque, fun: arity}` and a comment saying why,
  never with a project-wide flag.
- Do not hand-write cryptography or format parsing: encryption is `jose` (JWE),
  signatures and curves `:crypto`, money `Decimal`, currencies `money`.

## Web layer (`sca_web`, `sca_admin`)

- The design system is the Enum8 handoff
  (`~/Downloads/enum8-design-system-package`): Tailwind 4 utilities and Heroicons
  outline. No daisyUI, no new CSS files, no private tokens — colours and sizes
  come from `@theme` in `app.css`.
- Never build a class name at runtime (`"hidden #{breakpoint}:table-cell"`).
  Tailwind writes its stylesheet by scanning the source for class names, so an
  assembled one is never generated: the markup looks right, the page does not,
  and nothing fails. Write each variant out and pick between them.
- Primitives and the shell are shared, in `apps/sca_ui` (`ScaUi.Components`,
  `ScaUi.Shell`). A new primitive goes there rather than into one console: two
  copies of a design system drift apart quietly.
- In admin lists the merchant's name links to its page, and lists that belong to
  merchants have a filter by merchant.
- A merchant's secrets (the signing key) are never shown in the admin console,
  only the fact that they are configured.
- A list row carries a title, a human description, a status, a time and `View` —
  no decisions, and none of the signed params.
- `status/1` is read-only: a pill must never look clickable.
- Anything that looks like a button is `<.button>` — it takes `navigate`/`href`
  for links. Hand-rolling the classes is how two buttons end up different sizes
  next to each other.
- Screens reach entities through `Sca.Scope`, not through repos.
- Authentication is `ScaWeb.Auth`: the password check lives here, the domain
  hands out a hash.

## API (`sca_api`)

- The device API is mounted twice: at `/api/sca/v1` and under `/t/:tenant`. The
  QR hands the phone the tenant-scoped base URL, the client appends
  `/api/sca/v1/...` to whatever it was given, and `ScaApi.TenantPath` refuses a
  code or a session belonging to another merchant.
- What goes into the QR is `Sca.Enrollment` — a contract with the installed
  client, like `Sca.Crypto`. The base URL is not the domain's business: each
  entry point passes in the address the world reaches *it* at, and both the
  console and `POST /bindings` answer with the same string.
- `/api/sca/v1` is a contract with a mobile client that is already installed.
  Field names (`params`, `payload_hash`, `connection_id`),
  status codes and the 401/403 distinction cannot change without changing it.
- Response shapes are written by hand in `ScaApi.JSON`, never derived from
  schemas: a new column must not leak outward on its own.
- Anything leaving the system names resources by uuid — the API, webhook
  payloads and headers, push data. `public_id` is for people reading a console
  and for logs; a merchant matching a webhook against an API answer needs the
  same id in both. The one exception is the `/t/:tenant` prefix, which is an
  address people sometimes type.
- Retry-safety in the merchant API is a unique column on the entity, not a
  ledger beside it. For a request that column is `external_id` — the merchant's
  own reference, which is already the same thing — and the `Idempotency-Key`
  header only fills it in when the body did not. A binding has
  `idempotency_key` of its own, because its `external_id` names a person and
  enrolling that person again is how a lost phone is replaced.
- Both authentications are plugs (`ScaApi.DeviceAuth`, `ScaApi.MerchantAuth`) and
  both put a `Sca.Scope` in the conn; controllers go through it.
- An error goes out as `{"error": {"code", "message", "fields"}}`, the fields
  from `Sca.Errors.to_map/1`.

## Style: pipes, `with`, transactions

- **A pipe** is for steps about one subject, passed as the first argument. One
  `|> case do` at the end is fine; two in a row is a fork that wants a name.
- **`with`** is a chain of steps that each return `{:ok, _} | {:error, _}`. The
  `else` renames an error or logs a refusal — it is not for logic. A one-step
  `with` is right when success needs work and the error passes through untouched;
  if both branches need work, that is a `case`.
- **A transaction is `Repo.transact/2` + `with`**, not `Ecto.Multi`: the steps
  read top to bottom, and `{:error, _}` rolls back on its own — no
  `Repo.rollback`. `Multi` is not used in actions.
- Every check inside is a named predicate (`ensure_owner/2`, `ensure_pending/1`,
  `ensure_enrollable/1`) returning `:ok | {:error, atom}`, not a `cond` branch.
- **Careful with `with` as a replacement for `case`:** if the last clause does
  not match, its value *is* the result. `with {:error, r} <- check() do … end`
  returns `{:ok, jwk}` on success, and the junk travels on. Do not write that
  inverted form: two outcomes are a `case`.
- **Predicates** return `:ok | {:error, atom}` rather than `true/false`, so they
  drop into a `with` without a wrapper.
- Function bodies nest two levels deep at most (credo checks this); deeper means
  a named private function.

## Errors

- A domain refusal that no field can fix is an atom:
  `{:error, :not_yours | :already_decided | :expired | :invalid_signature}`.
- Bad input is `{:error, %Ecto.Changeset{}}`, unfolded for the caller by
  `Sca.Errors.to_map/1` (keys as the caller sent them, card param names
  included).
- Never mix the two for the same cause.

## Project guidelines

- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps

### Phoenix v1.8 guidelines

- **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- The `MyAppWeb.Layouts` module is aliased in the `my_app_web.ex` file, so you can use it without needing to alias it again
- Anytime you run into errors with no `current_scope` assign:
  - You failed to follow the Authenticated Routes guidelines, or you failed to pass `current_scope` to `<Layouts.app>`
  - **Always** fix the `current_scope` error by moving your routes to the proper `live_session` and ensure you pass `current_scope` as needed
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. You are **forbidden** from calling `<.flash_group>` outside of the `layouts.ex` module
- Out of the box, `core_components.ex` imports an `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for hero icons. **Always** use the `<.icon>` component for icons, **never** use `Heroicons` modules or similar
- **Always** use the imported `<.input>` component for form inputs from `core_components.ex` when available. `<.input>` is imported and using it will save steps and prevent errors
- If you override the default input classes (`<.input class="myclass px-2 py-1 rounded-lg">)`) class with your own values, no default classes are inherited, so your
custom classes must fully style the input

### JS and CSS guidelines

- **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive, and visually stunning interfaces.
- Tailwindcss v4 **no longer needs a tailwind.config.js** and uses a new import syntax in `app.css`:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/my_app_web";

- **Always use and maintain this import syntax** in the app.css file for projects generated with `phx.new`
- **Never** use `@apply` when writing raw css
- **Always** manually write your own tailwind-based components instead of using daisyUI for a unique, world-class design
- Out of the box **only the app.js and app.css bundles are supported**
  - You cannot reference an external vendor'd script `src` or link `href` in the layouts
  - You must import the vendor deps into app.js and app.css to use them
  - **Never write inline <script>custom js</script> tags within templates**

### UI/UX & design guidelines

- **Produce world-class UI designs** with a focus on usability, aesthetics, and modern design principles
- Implement **subtle micro-interactions** (e.g., button hover effects, and smooth transitions)
- Ensure **clean typography, spacing, and layout balance** for a refined, premium look
- Focus on **delightful details** like hover effects, loading states, and smooth page transitions


<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->
## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason

## Test guidelines

- **Always use `start_supervised!/1`** to start processes in tests as it guarantees cleanup between tests
- **Avoid** `Process.sleep/1` and `Process.alive?/1` in tests
  - Instead of sleeping to wait for a process to finish, **always** use `Process.monitor/1` and assert on the DOWN message:

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

   - Instead of sleeping to synchronize before the next call, **always** use `_ = :sys.get_state/1` to ensure the process has handled prior messages
<!-- phoenix:elixir-end -->

<!-- phoenix:phoenix-start -->
## Phoenix guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.

- You **never** need to create your own `alias` for route definitions! The `scope` provides the alias, ie:

      scope "/admin", AppWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  the UserLive route would point to the `AppWeb.Admin.UserLive` module

- `Phoenix.View` no longer is needed or included with Phoenix, don't use it
<!-- phoenix:phoenix-end -->

<!-- phoenix:ecto-start -->
## Ecto Guidelines

- **Always** preload Ecto associations in queries when they'll be accessed in templates, ie a message that needs to reference the `message.user.email`
- Remember `import Ecto.Query` and other supporting modules when you write `seeds.exs`
- `Ecto.Schema` fields always use the `:string` type, even for `:text`, columns, ie: `field :name, :string`
- `Ecto.Changeset.validate_number/2` **DOES NOT SUPPORT the `:allow_nil` option**. By default, Ecto validations only run if a change for the given field exists and the change value is not nil, so such as option is never needed
- You **must** use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields
- Fields which are set programmatically, such as `user_id`, must not be listed in `cast` calls or similar for security purposes. Instead they must be explicitly set when creating the struct
- **Always** invoke `mix ecto.gen.migration migration_name_using_underscores` when generating migration files, so the correct timestamp and conventions are applied
<!-- phoenix:ecto-end -->

<!-- phoenix:html-start -->
## Phoenix HTML guidelines

- Phoenix templates **always** use `~H` or .html.heex files (known as HEEx), **never** use `~E`
- **Always** use the imported `Phoenix.Component.form/1` and `Phoenix.Component.inputs_for/1` function to build forms. **Never** use `Phoenix.HTML.form_for` or `Phoenix.HTML.inputs_for` as they are outdated
- When building forms **always** use the already imported `Phoenix.Component.to_form/2` (`assign(socket, form: to_form(...))` and `<.form for={@form} id="msg-form">`), then access those forms in the template via `@form[:field]`
- **Always** add unique DOM IDs to key elements (like forms, buttons, etc) when writing templates, these IDs can later be used in tests (`<.form for={@form} id="product-form">`)
- For "app wide" template imports, you can import/alias into the `my_app_web.ex`'s `html_helpers` block, so they will be available to all LiveViews, LiveComponent's, and all modules that do `use MyAppWeb, :html` (replace "my_app" by the actual app name)

- Elixir supports `if/else` but **does NOT support `if/else if` or `if/elsif`**. **Never use `else if` or `elseif` in Elixir**, **always** use `cond` or `case` for multiple conditionals.

  **Never do this (invalid)**:

      <%= if condition do %>
        ...
      <% else if other_condition %>
        ...
      <% end %>

  Instead **always** do this:

      <%= cond do %>
        <% condition -> %>
          ...
        <% condition2 -> %>
          ...
        <% true -> %>
          ...
      <% end %>

- HEEx require special tag annotation if you want to insert literal curly's like `{` or `}`. If you want to show a textual code snippet on the page in a `<pre>` or `<code>` block you *must* annotate the parent tag with `phx-no-curly-interpolation`:

      <code phx-no-curly-interpolation>
        let obj = {key: "val"}
      </code>

  Within `phx-no-curly-interpolation` annotated tags, you can use `{` and `}` without escaping them, and dynamic Elixir expressions can still be used with `<%= ... %>` syntax

- HEEx class attrs support lists, but you must **always** use list `[...]` syntax. You can use the class list syntax to conditionally add classes, **always do this for multiple class values**:

      <a class={[
        "px-2 text-white",
        @some_flag && "py-5",
        if(@other_condition, do: "border-red-500", else: "border-blue-100"),
        ...
      ]}>Text</a>

  and **always** wrap `if`'s inside `{...}` expressions with parens, like done above (`if(@other_condition, do: "...", else: "...")`)

  and **never** do this, since it's invalid (note the missing `[` and `]`):

      <a class={
        "px-2 text-white",
        @some_flag && "py-5"
      }> ...
      => Raises compile syntax error on invalid HEEx attr syntax

- **Never** use `<% Enum.each %>` or non-for comprehensions for generating template content, instead **always** use `<%= for item <- @collection do %>`
- HEEx HTML comments use `<%!-- comment --%>`. **Always** use the HEEx HTML comment syntax for template comments (`<%!-- comment --%>`)
- HEEx allows interpolation via `{...}` and `<%= ... %>`, but the `<%= %>` **only** works within tag bodies. **Always** use the `{...}` syntax for interpolation within tag attributes, and for interpolation of values within tag bodies. **Always** interpolate block constructs (if, cond, case, for) within tag bodies using `<%= ... %>`.

  **Always** do this:

      <div id={@id}>
        {@my_assign}
        <%= if @some_block_condition do %>
          {@another_assign}
        <% end %>
      </div>

  and **Never** do this – the program will terminate with a syntax error:

      <%!-- THIS IS INVALID NEVER EVER DO THIS --%>
      <div id="<%= @invalid_interpolation %>">
        {if @invalid_block_construct do}
        {end}
      </div>
<!-- phoenix:html-end -->

<!-- phoenix:liveview-start -->
## Phoenix LiveView guidelines

- **Never** use the deprecated `live_redirect` and `live_patch` functions, instead **always** use the `<.link navigate={href}>` and  `<.link patch={href}>` in templates, and `push_navigate` and `push_patch` functions LiveViews
- **Avoid LiveComponent's** unless you have a strong, specific need for them
- LiveViews should be named like `AppWeb.WeatherLive`, with a `Live` suffix. When you go to add LiveView routes to the router, the default `:browser` scope is **already aliased** with the `AppWeb` module, so you can just do `live "/weather", WeatherLive`

### LiveView streams

- **Always** use LiveView streams for collections for assigning regular lists to avoid memory ballooning and runtime termination with the following operations:
  - basic append of N items - `stream(socket, :messages, [new_msg])`
  - resetting stream with new items - `stream(socket, :messages, [new_msg], reset: true)` (e.g. for filtering items)
  - prepend to stream - `stream(socket, :messages, [new_msg], at: -1)`
  - deleting items - `stream_delete(socket, :messages, msg)`

- When using the `stream/3` interfaces in the LiveView, the LiveView template must 1) always set `phx-update="stream"` on the parent element, with a DOM id on the parent element like `id="messages"` and 2) consume the `@streams.stream_name` collection and use the id as the DOM id for each child. For a call like `stream(socket, :messages, [new_msg])` in the LiveView, the template would be:

      <div id="messages" phx-update="stream">
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {msg.text}
        </div>
      </div>

- LiveView streams are *not* enumerable, so you cannot use `Enum.filter/2` or `Enum.reject/2` on them. Instead, if you want to filter, prune, or refresh a list of items on the UI, you **must refetch the data and re-stream the entire stream collection, passing reset: true**:

      def handle_event("filter", %{"filter" => filter}, socket) do
        # re-fetch the messages based on the filter
        messages = list_messages(filter)

        {:noreply,
         socket
         |> assign(:messages_empty?, messages == [])
         # reset the stream with the new messages
         |> stream(:messages, messages, reset: true)}
      end

- LiveView streams *do not support counting or empty states*. If you need to display a count, you must track it using a separate assign. For empty states, you can use Tailwind classes:

      <div id="tasks" phx-update="stream">
        <div class="hidden only:block">No tasks yet</div>
        <div :for={{id, task} <- @streams.tasks} id={id}>
          {task.name}
        </div>
      </div>

  The above only works if the empty state is the only HTML block alongside the stream for-comprehension.

- When updating an assign that should change content inside any streamed item(s), you MUST re-stream the items
  along with the updated assign:

      def handle_event("edit_message", %{"message_id" => message_id}, socket) do
        message = Chat.get_message!(message_id)
        edit_form = to_form(Chat.change_message(message, %{content: message.content}))

        # re-insert message so @editing_message_id toggle logic takes effect for that stream item
        {:noreply,
         socket
         |> stream_insert(:messages, message)
         |> assign(:editing_message_id, String.to_integer(message_id))
         |> assign(:edit_form, edit_form)}
      end

  And in the template:

      <div id="messages" phx-update="stream">
        <div :for={{id, message} <- @streams.messages} id={id} class="flex group">
          {message.username}
          <%= if @editing_message_id == message.id do %>
            <%!-- Edit mode --%>
            <.form for={@edit_form} id="edit-form-#{message.id}" phx-submit="save_edit">
              ...
            </.form>
          <% end %>
        </div>
      </div>

- **Never** use the deprecated `phx-update="append"` or `phx-update="prepend"` for collections

### LiveView JavaScript interop

- Remember anytime you use `phx-hook="MyHook"` and that JS hook manages its own DOM, you **must** also set the `phx-update="ignore"` attribute
- **Always** provide an unique DOM id alongside `phx-hook` otherwise a compiler error will be raised

LiveView hooks come in two flavors, 1) colocated js hooks for "inline" scripts defined inside HEEx,
and 2) external `phx-hook` annotations where JavaScript object literals are defined and passed to the `LiveSocket` constructor.

#### Inline colocated js hooks

**Never** write raw embedded `<script>` tags in heex as they are incompatible with LiveView.
Instead, **always use a colocated js hook script tag (`:type={Phoenix.LiveView.ColocatedHook}`)
when writing scripts inside the template**:

    <input type="text" name="user[phone_number]" id="user-phone-number" phx-hook=".PhoneNumber" />
    <script :type={Phoenix.LiveView.ColocatedHook} name=".PhoneNumber">
      export default {
        mounted() {
          this.el.addEventListener("input", e => {
            let match = this.el.value.replace(/\D/g, "").match(/^(\d{3})(\d{3})(\d{4})$/)
            if(match) {
              this.el.value = `${match[1]}-${match[2]}-${match[3]}`
            }
          })
        }
      }
    </script>

- colocated hooks are automatically integrated into the app.js bundle
- colocated hooks names **MUST ALWAYS** start with a `.` prefix, i.e. `.PhoneNumber`

#### External phx-hook

External JS hooks (`<div id="myhook" phx-hook="MyHook">`) must be placed in `assets/js/` and passed to the
LiveSocket constructor:

    const MyHook = {
      mounted() { ... }
    }
    let liveSocket = new LiveSocket("/live", Socket, {
      hooks: { MyHook }
    });

#### Pushing events between client and server

Use LiveView's `push_event/3` when you need to push events/data to the client for a phx-hook to handle.
**Always** return or rebind the socket on `push_event/3` when pushing events:

    # re-bind socket so we maintain event state to be pushed
    socket = push_event(socket, "my_event", %{...})

    # or return the modified socket directly:
    def handle_event("some_event", _, socket) do
      {:noreply, push_event(socket, "my_event", %{...})}
    end

Pushed events can then be picked up in a JS hook with `this.handleEvent`:

    mounted() {
      this.handleEvent("my_event", data => console.log("from server:", data));
    }

Clients can also push an event to the server and receive a reply with `this.pushEvent`:

    mounted() {
      this.el.addEventListener("click", e => {
        this.pushEvent("my_event", { one: 1 }, reply => console.log("got reply from server:", reply));
      })
    }

Where the server handled it via:

    def handle_event("my_event", %{"one" => 1}, socket) do
      {:reply, %{two: 2}, socket}
    end

### LiveView tests

- `Phoenix.LiveViewTest` module and `LazyHTML` (included) for making your assertions
- Form tests are driven by `Phoenix.LiveViewTest`'s `render_submit/2` and `render_change/2` functions
- Come up with a step-by-step test plan that splits major test cases into small, isolated files. You may start with simpler tests that verify content exists, gradually add interaction tests
- **Always reference the key element IDs you added in the LiveView templates in your tests** for `Phoenix.LiveViewTest` functions like `element/2`, `has_element/2`, selectors, etc
- **Never** tests again raw HTML, **always** use `element/2`, `has_element/2`, and similar: `assert has_element?(view, "#my-form")`
- Instead of relying on testing text content, which can change, favor testing for the presence of key elements
- Focus on testing outcomes rather than implementation details
- Be aware that `Phoenix.Component` functions like `<.form>` might produce different HTML than expected. Test against the output HTML structure, not your mental model of what you expect it to be
- When facing test failures with element selectors, add debug statements to print the actual HTML, but use `LazyHTML` selectors to limit the output, ie:

      html = render(view)
      document = LazyHTML.from_fragment(html)
      matches = LazyHTML.filter(document, "your-complex-selector")
      IO.inspect(matches, label: "Matches")

### Form handling

#### Creating a form from params

If you want to create a form based on `handle_event` params:

    def handle_event("submitted", params, socket) do
      {:noreply, assign(socket, form: to_form(params))}
    end

When you pass a map to `to_form/1`, it assumes said map contains the form params, which are expected to have string keys.

You can also specify a name to nest the params:

    def handle_event("submitted", %{"user" => user_params}, socket) do
      {:noreply, assign(socket, form: to_form(user_params, as: :user))}
    end

#### Creating a form from changesets

When using changesets, the underlying data, form params, and errors are retrieved from it. The `:as` option is automatically computed too. E.g. if you have a user schema:

    defmodule MyApp.Users.User do
      use Ecto.Schema
      ...
    end

And then you create a changeset that you pass to `to_form`:

    %MyApp.Users.User{}
    |> Ecto.Changeset.change()
    |> to_form()

Once the form is submitted, the params will be available under `%{"user" => user_params}`.

In the template, the form form assign can be passed to the `<.form>` function component:

    <.form for={@form} id="todo-form" phx-change="validate" phx-submit="save">
      <.input field={@form[:field]} type="text" />
    </.form>

Always give the form an explicit, unique DOM ID, like `id="todo-form"`.

#### Avoiding form errors

**Always** use a form assigned via `to_form/2` in the LiveView, and the `<.input>` component in the template. In the template **always access forms this**:

    <%!-- ALWAYS do this (valid) --%>
    <.form for={@form} id="my-form">
      <.input field={@form[:field]} type="text" />
    </.form>

And **never** do this:

    <%!-- NEVER do this (invalid) --%>
    <.form for={@changeset} id="my-form">
      <.input field={@changeset[:field]} type="text" />
    </.form>

- You are FORBIDDEN from accessing the changeset in the template as it will cause errors
- **Never** use `<.form let={f} ...>` in the template, instead **always use `<.form for={@form} ...>`**, then drive all form references from the form assign as in `@form[:field]`. The UI should **always** be driven by a `to_form/2` assigned in the LiveView module that is derived from a changeset
<!-- phoenix:liveview-end -->

<!-- usage-rules-end -->